//! The runtime: registered apps, and the machinery that runs one of their
//! functions on demand.
//!
//! For now an instance is created per call and destroyed after it. That is
//! deliberately the simple thing — the warm pool, hibernation and eviction are
//! their own workstream — but the *seam* is here: every instance is created,
//! governed, run and destroyed inside [`AppRuntime::with_instance`], so the
//! pool replaces one function rather than being threaded through the callers.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, RwLock};

use elpian_vm::api;
use serde_json::{json, Value};

use crate::app::{valid_app_id, AppDefinition, FunctionKind};
use crate::appfs::AppFs;
use crate::component::{ComponentPayload, RenderCache};
use crate::identity::Identity;
use crate::invoke::{invoke, InvokeLimits, Outcome};
use crate::pool::{InstancePool, Meters, PoolConfig};
use crate::quota::{Admission, Quota, QuotaEnforcer};
use crate::services::{InvocationLog, ServerContext, ServerServices};
use crate::state::{SecretStore, StateStore};

/// How deep a chain of `server.call`s may go.
///
/// A function calling another function is ordinary; a function calling itself,
/// directly or through a cycle, is not, and each level holds an instance and a
/// stack frame. The bound is small on purpose: a legitimate chain is a handful
/// deep, and anything more is a bug that would otherwise cost a thread.
const MAX_CALL_DEPTH: u32 = 8;

/// How many rendered components the host keeps. A bound, not a tuning target:
/// what matters is that one app cannot grow it without limit.
const DEFAULT_RENDER_CACHE_ENTRIES: usize = 1024;

/// How many frames one streaming render may emit.
///
/// The dead-reader signal lets a *well-behaved* component stop when nobody is
/// listening. A component that ignores it, or one with a bug, would emit
/// forever into a reader that is still there — so the host caps it too. Past
/// the cap the sink reports the reader as gone, which is the signal a guest
/// already has to handle, rather than a new failure mode for it to learn.
const MAX_STREAM_FRAMES: usize = 10_000;

/// Why an invocation could not be attempted.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CallError {
    UnknownApp(String),
    /// The app is over budget. `stage` says how far up the ladder it is and
    /// `axis` which budget it blew — both for the operator; the caller is told
    /// only that the app is over its quota.
    OverQuota {
        stage: String,
        axis: String,
    },
    UnknownFunction {
        app: String,
        function: String,
    },
    /// The function exists but is the other kind — an action asked to render,
    /// or a component invoked as an action.
    WrongKind {
        function: String,
        expected: &'static str,
        actual: &'static str,
    },
    CallDepthExceeded,
}

impl CallError {
    /// The message a *caller* may see. Deliberately terse and free of host
    /// detail; the operator's version goes to the log.
    pub fn client_message(&self) -> String {
        match self {
            CallError::UnknownApp(app) => format!("no such app: {app}"),
            CallError::UnknownFunction { function, .. } => {
                format!("no such function: {function}")
            }
            CallError::WrongKind {
                function, expected, ..
            } => format!("{function} is not {expected}"),
            CallError::CallDepthExceeded => "call depth exceeded".to_string(),
            CallError::OverQuota { .. } => "this app is over its quota".to_string(),
        }
    }
}

/// The result of one invocation, with what the host learned along the way.
#[derive(Debug, Clone)]
pub struct Invocation {
    pub outcome: Outcome,
    pub log: InvocationLog,
    /// Whether this call had to load the function's module (as opposed to
    /// reusing a warm instance). Always true until the pool arrives; recorded
    /// from the start so the meter has something to report.
    pub cold_start: bool,
    /// Whether a server component's payload came from the render cache. No
    /// guest code ran when this is true.
    pub cache_hit: bool,
}

/// Registered apps and the stores they run against.
pub struct AppRuntime {
    apps: RwLock<HashMap<String, AppDefinition>>,
    state: StateStore,
    secrets: SecretStore,
    /// Where each app's private directory lives, if apps get one.
    data_root: Option<PathBuf>,
    limits: RwLock<InvokeLimits>,
    cache: RenderCache,
    pool: Arc<InstancePool>,
    quotas: QuotaEnforcer,
}

impl AppRuntime {
    pub fn new() -> Arc<AppRuntime> {
        Arc::new(AppRuntime {
            apps: RwLock::new(HashMap::new()),
            state: StateStore::default(),
            secrets: SecretStore::new(),
            data_root: None,
            limits: RwLock::new(InvokeLimits::default()),
            cache: RenderCache::new(DEFAULT_RENDER_CACHE_ENTRIES),
            pool: InstancePool::new(PoolConfig::default()),
            quotas: QuotaEnforcer::new(),
        })
    }

    pub fn with_data_root(root: impl Into<PathBuf>) -> Arc<AppRuntime> {
        let root = root.into();
        // Counters live beside the app data they describe, so moving one moves
        // the other.
        let _ = std::fs::create_dir_all(&root);
        let meters = crate::pool::MeterStore::persisted(root.join("meters.json"));
        Arc::new(AppRuntime {
            apps: RwLock::new(HashMap::new()),
            state: StateStore::default(),
            secrets: SecretStore::new(),
            data_root: Some(root),
            limits: RwLock::new(InvokeLimits::default()),
            cache: RenderCache::new(DEFAULT_RENDER_CACHE_ENTRIES),
            pool: InstancePool::with_meters(PoolConfig::default(), meters),
            quotas: QuotaEnforcer::new(),
        })
    }

    /// Replace the per-invocation bounds.
    ///
    /// Not on the constructor because the host may want to change them without
    /// rebuilding the runtime — and because a test needs a short deadline
    /// without waiting for the default one.
    pub fn set_invoke_limits(&self, limits: InvokeLimits) {
        *self.limits.write().unwrap_or_else(|p| p.into_inner()) = limits;
    }

    fn invoke_limits(&self) -> InvokeLimits {
        self.limits
            .read()
            .unwrap_or_else(|p| p.into_inner())
            .clone()
    }

    pub fn quotas(&self) -> &QuotaEnforcer {
        &self.quotas
    }

    /// Set an app's budget.
    pub fn set_quota(&self, app_id: &str, quota: Quota) {
        self.quotas.set_quota(app_id, quota);
    }

    pub fn pool(&self) -> &Arc<InstancePool> {
        &self.pool
    }

    /// This app's accumulated cost meters.
    pub fn meters(&self, app_id: &str) -> Meters {
        let mut meters = self.pool.meters.get(app_id);
        // Storage is a level held elsewhere, so it is read at the moment it is
        // asked for rather than accumulated.
        meters.storage_bytes = self.state.bytes_used(app_id) as u64;
        meters
    }

    pub fn cache(&self) -> &RenderCache {
        &self.cache
    }

    /// Drop every cached render belonging to one app.
    ///
    /// Scoped to the app for the same reason `cache.revalidate` is: an operator
    /// clearing one tenant's cache must not clear every other tenant's.
    pub fn clear_cache(&self, app_id: &str) -> usize {
        self.cache.clear_app(app_id)
    }

    /// Register an app, or refuse it.
    ///
    /// Refusing here rather than at each use site is the point: the id becomes
    /// a directory name, a state-key prefix and a URL segment, and defending
    /// each of those separately is how one of them gets missed. See
    /// [`valid_app_id`].
    pub fn register(&self, app: AppDefinition) -> bool {
        if !valid_app_id(&app.id) {
            return false;
        }
        self.write_apps().insert(app.id.clone(), app);
        true
    }

    pub fn unregister(&self, app_id: &str) -> bool {
        self.write_apps().remove(app_id).is_some()
    }

    /// The manifest a device fetches for an app.
    pub fn manifest(&self, app_id: &str) -> Option<Value> {
        self.read_apps().get(app_id).map(|a| a.client_manifest())
    }

    /// An app's client-half bytecode.
    pub fn client_bytecode(&self, app_id: &str) -> Option<Vec<u8>> {
        self.read_apps()
            .get(app_id)
            .and_then(|a| a.client_bytecode.clone())
    }

    /// A registered app's definition.
    pub fn app_definition(&self, app_id: &str) -> Option<AppDefinition> {
        self.read_apps().get(app_id).cloned()
    }

    pub fn app_ids(&self) -> Vec<String> {
        let mut ids: Vec<String> = self.read_apps().keys().cloned().collect();
        ids.sort();
        ids
    }

    pub fn secrets(&self) -> &SecretStore {
        &self.secrets
    }

    pub fn state(&self) -> &StateStore {
        &self.state
    }

    fn read_apps(&self) -> std::sync::RwLockReadGuard<'_, HashMap<String, AppDefinition>> {
        self.apps.read().unwrap_or_else(|p| p.into_inner())
    }

    fn write_apps(&self) -> std::sync::RwLockWriteGuard<'_, HashMap<String, AppDefinition>> {
        self.apps.write().unwrap_or_else(|p| p.into_inner())
    }

    /// Invoke an action (`server.call`).
    pub fn call(
        self: &Arc<Self>,
        app: &str,
        function: &str,
        args: &Value,
    ) -> Result<Invocation, CallError> {
        self.dispatch(app, function, args, FunctionKind::Action, 0, None)
    }

    /// Invoke an action on behalf of a verified caller.
    pub fn call_as(
        self: &Arc<Self>,
        app: &str,
        function: &str,
        args: &Value,
        user: Option<Identity>,
    ) -> Result<Invocation, CallError> {
        self.dispatch(app, function, args, FunctionKind::Action, 0, user)
    }

    /// Invoke a server component (`server.render`).
    pub fn render(
        self: &Arc<Self>,
        app: &str,
        function: &str,
        args: &Value,
    ) -> Result<Invocation, CallError> {
        self.dispatch(app, function, args, FunctionKind::Component, 0, None)
    }

    /// Render a component on behalf of a verified caller.
    pub fn render_as(
        self: &Arc<Self>,
        app: &str,
        function: &str,
        args: &Value,
        user: Option<Identity>,
    ) -> Result<Invocation, CallError> {
        self.dispatch(app, function, args, FunctionKind::Component, 0, user)
    }

    /// Render a component that emits its UI progressively.
    ///
    /// Deliberately its own path rather than a flag on `dispatch`. A streaming
    /// render is **never cached** — the cache stores one payload, and a stream
    /// is a sequence — and it is never served *from* the cache either, because
    /// replaying a finished sequence as one frame would silently change what a
    /// component does. Keeping it separate makes that structural rather than a
    /// condition somebody has to remember.
    pub fn render_stream(
        self: &Arc<Self>,
        app_id: &str,
        function: &str,
        args: &Value,
        user: Option<Identity>,
        sink: &mut dyn FnMut(&Value) -> bool,
    ) -> Result<(), CallError> {
        let app = self
            .read_apps()
            .get(app_id)
            .cloned()
            .ok_or_else(|| CallError::UnknownApp(app_id.to_string()))?;

        let def = app
            .function(function)
            .ok_or_else(|| CallError::UnknownFunction {
                app: app_id.to_string(),
                function: function.to_string(),
            })?
            .clone();

        if def.kind != FunctionKind::Component {
            return Err(CallError::WrongKind {
                function: function.to_string(),
                expected: FunctionKind::Component.as_str(),
                actual: def.kind.as_str(),
            });
        }

        // Quota, before anything runs — the same rule as `dispatch`. A stream
        // counts as a read, so an app being strangled can still be looked at.
        let meters = self.meters(app_id);
        if let Admission::Refuse { stage, axis } = self.quotas.admit(app_id, &meters, false) {
            return Err(CallError::OverQuota {
                stage: stage.as_str().to_string(),
                axis: axis.to_string(),
            });
        }

        // Counts frames so a component that neither emitted nor returned a
        // payload can be told apart from one that streamed successfully.
        let mut emitted = 0usize;
        let mut over_budget = false;
        let mut counting_sink = |frame: &Value| {
            if emitted >= MAX_STREAM_FRAMES {
                over_budget = true;
                // Reported as "the reader is gone" rather than a new signal: a
                // guest already has to handle that answer, and inventing a
                // second one would mean components that handled the first
                // correctly still looped forever on this.
                return false;
            }
            emitted += 1;
            sink(frame)
        };
        let invocation = self.with_instance(&app, &def, |machine_id, cold| {
            let fs = self.data_root.as_ref().map(|root| {
                let dir = root.join(&app.id);
                let _ = std::fs::create_dir_all(&dir);
                AppFs::new(dir)
            });
            let ctx = ServerContext {
                app: app.id.clone(),
                machine_id: machine_id.to_string(),
                function: function.to_string(),
                declared_secrets: app.declared_secrets.clone(),
                fs,
                user: user.clone(),
                network: app.network.clone(),
            };
            let mut services = ServerServices::new(ctx, self.state.clone(), self.secrets.clone());
            services.set_invoker(Box::new(NestedInvoker {
                runtime: Arc::clone(self),
                app: app.id.clone(),
                depth: 1,
                user: user.clone(),
            }));
            services.set_cache(self.cache.clone());

            services.set_stream(&mut counting_sink);

            let outcome = invoke(
                machine_id,
                function,
                args,
                &mut services,
                &self.invoke_limits(),
                cold,
            );
            Invocation {
                outcome,
                log: services.log,
                cold_start: cold,
                cache_hit: false,
            }
        });

        if over_budget {
            eprintln!(
                "[elpian] {app_id}/{function} hit the {MAX_STREAM_FRAMES}-frame stream budget"
            );
        }

        match invocation.outcome {
            Outcome::Returned(value) => {
                // A streaming component may also *return* a final payload. If it
                // did, that is the last frame — so a component can stream
                // progress and finish with a complete tree, and one that only
                // returns still works through this door.
                if let Ok(payload) = ComponentPayload::parse(&value) {
                    let frame = json!({ "action": "setView", "view": payload.value["component"] });
                    sink(&frame);
                } else if emitted == 0 {
                    return Err(CallError::WrongKind {
                        function: function.to_string(),
                        expected: "a component that emits or returns a payload",
                        actual: "a component that did neither",
                    });
                }
                Ok(())
            }
            Outcome::Trapped(reason) => {
                eprintln!("[elpian] {app_id}/{function} trapped mid-stream: {reason}");
                Err(CallError::UnknownFunction {
                    app: app_id.to_string(),
                    function: function.to_string(),
                })
            }
            Outcome::TooManyHostCalls | Outcome::DeadlineExceeded => {
                Err(CallError::CallDepthExceeded)
            }
        }
    }

    fn dispatch(
        self: &Arc<Self>,
        app_id: &str,
        function: &str,
        args: &Value,
        expected: FunctionKind,
        depth: u32,
        user: Option<Identity>,
    ) -> Result<Invocation, CallError> {
        if depth >= MAX_CALL_DEPTH {
            return Err(CallError::CallDepthExceeded);
        }

        // Clone the definition out and drop the lock: an invocation is long
        // (it runs guest code) and holding a registry lock across it would
        // block every other app's dispatch behind this one guest.
        let app = self
            .read_apps()
            .get(app_id)
            .cloned()
            .ok_or_else(|| CallError::UnknownApp(app_id.to_string()))?;

        let def = app
            .function(function)
            .ok_or_else(|| CallError::UnknownFunction {
                app: app_id.to_string(),
                function: function.to_string(),
            })?
            .clone();

        if def.kind != expected {
            return Err(CallError::WrongKind {
                function: function.to_string(),
                expected: expected.as_str(),
                actual: def.kind.as_str(),
            });
        }

        // Quota, before anything else runs.
        //
        // An over-budget app refused *after* its instructions are spent has
        // already cost what the quota exists to bound. This is a map lookup and
        // a few comparisons, so it is affordable in front of every call.
        //
        // Nested calls are exempt: the outer call was already admitted, and
        // refusing halfway through would leave the app's state half-written
        // with no way for the guest to recover — the subset has no try/catch.
        if depth == 0 {
            let meters = self.meters(app_id);
            let is_write = expected == FunctionKind::Action;
            if let Admission::Refuse { stage, axis } = self.quotas.admit(app_id, &meters, is_write)
            {
                return Err(CallError::OverQuota {
                    stage: stage.as_str().to_string(),
                    axis: axis.to_string(),
                });
            }
        }

        // A cached render short-circuits before any instance is created — the
        // point of the cache is to not run the guest, not to run it faster.
        // A component rendered for a *specific* caller is not shared: the
        // cache key is the app, the component and the arguments, and serving
        // one user's page to another would be the worst possible cache bug. So
        // an authenticated render bypasses the cache entirely rather than being
        // keyed by identity — per-user caching is a real feature, and it needs
        // to be designed rather than fallen into.
        if expected == FunctionKind::Component && user.is_none() {
            if let Some(payload) = self.cache.get(&app.id, function, args) {
                return Ok(Invocation {
                    outcome: Outcome::Returned(payload),
                    log: InvocationLog::default(),
                    cold_start: false,
                    cache_hit: true,
                });
            }
        }

        let invocation = self.with_instance(&app, &def, |machine_id, cold| {
            // `app.id` was validated at registration, so this join cannot
            // leave the data root. The assertion keeps that dependency visible
            // rather than implicit — a future path that registered without
            // checking would fail here instead of silently rooting an app at
            // its neighbours.
            let fs = self.data_root.as_ref().map(|root| {
                debug_assert!(
                    valid_app_id(&app.id),
                    "unvalidated app id reached the filesystem"
                );
                let dir = root.join(&app.id);
                let _ = std::fs::create_dir_all(&dir);
                AppFs::new(dir)
            });

            let ctx = ServerContext {
                app: app.id.clone(),
                machine_id: machine_id.to_string(),
                function: function.to_string(),
                declared_secrets: app.declared_secrets.clone(),
                fs,
                user: user.clone(),
                network: app.network.clone(),
            };
            let mut services = ServerServices::new(ctx, self.state.clone(), self.secrets.clone());
            services.set_invoker(Box::new(NestedInvoker {
                runtime: Arc::clone(self),
                app: app.id.clone(),
                depth: depth + 1,
                // A nested call acts for the same caller. Dropping the identity
                // here would silently turn an authenticated chain anonymous
                // halfway through, and a function checking `ctx.user` two hops
                // in would refuse work it should have done.
                user: user.clone(),
            }));
            services.set_cache(self.cache.clone());

            let outcome = invoke(
                machine_id,
                function,
                args,
                &mut services,
                &self.invoke_limits(),
                cold,
            );
            Invocation {
                outcome,
                log: services.log,
                cold_start: true,
                cache_hit: false,
            }
        });

        // Store only what validates. A component returning something that is
        // not a payload is a bug in that app; caching it would serve the bug
        // back for as long as the entry lived.
        if expected == FunctionKind::Component && user.is_none() {
            if let Outcome::Returned(value) = &invocation.outcome {
                match ComponentPayload::parse(value) {
                    Ok(payload) => self.cache.put(&app.id, function, args, &payload),
                    Err(error) => eprintln!(
                        "[elpian] {}/{function}: {} — not cached",
                        app.id,
                        error.as_str()
                    ),
                }
            }
        }

        Ok(invocation)
    }

    /// Lease an instance, run `body` against it, and hand it back.
    ///
    /// The single place an instance's lifetime is decided. Governance is
    /// applied by the pool before `body` runs — on creation *and* on reuse,
    /// because an app's grant can change between calls and a warm instance
    /// carrying the old one would be a way to keep a capability after it was
    /// revoked.
    ///
    /// An instance that trapped is discarded rather than reused: whatever left
    /// it in that state is still in its module scope, and handing it to the
    /// next caller would spread one call's failure across every later one.
    fn with_instance(
        &self,
        app: &AppDefinition,
        def: &crate::app::FunctionDef,
        body: impl FnOnce(&str, bool) -> Invocation,
    ) -> Invocation {
        let lease = self.pool.acquire(app, def);
        let machine_id = lease.machine_id.clone();
        let cold_start = lease.cold_start;

        let before = api::usage(&machine_id).map(|u| u.instructions).unwrap_or(0);
        let started = std::time::Instant::now();

        let mut invocation = body(&machine_id, cold_start);
        invocation.cold_start = cold_start;

        let usage = api::usage(&machine_id);
        let elapsed_ms = started.elapsed().as_millis() as u64;
        self.pool.meters.record(&app.id, |m| {
            m.invocations += 1;
            if cold_start {
                m.cold_starts += 1;
            }
            m.compute_ms += elapsed_ms;
            if let Some(usage) = &usage {
                m.instructions += usage.instructions.saturating_sub(before);
                m.peak_memory_bytes = m.peak_memory_bytes.max(usage.peak_memory_bytes);
            }
        });

        let healthy = matches!(invocation.outcome, Outcome::Returned(_))
            && api::trap_reason(&machine_id).is_none();
        if healthy && !def.stateless {
            lease.release();
        } else {
            lease.discard();
        }
        invocation
    }
}

/// Lets a running server function call another function of **the same app**.
///
/// The app id is fixed at construction from the app whose function is running —
/// the guest never supplies it and so cannot name another app's function. That
/// is the whole of the cross-app isolation story for `server.call`: there is no
/// check to bypass because there is no parameter to forge.
struct NestedInvoker {
    runtime: Arc<AppRuntime>,
    app: String,
    depth: u32,
    user: Option<Identity>,
}

impl crate::services::FunctionInvoker for NestedInvoker {
    fn invoke(&self, function: &str, args: &Value, kind: FunctionKind) -> Value {
        match self.runtime.dispatch(
            &self.app,
            function,
            args,
            kind,
            self.depth,
            self.user.clone(),
        ) {
            Ok(Invocation {
                outcome: Outcome::Returned(value),
                ..
            }) => value,
            // A nested failure is a null to the *calling guest*, matching every
            // other refused host call, so guest code has one shape to handle.
            // The detail is not lost: it is in the nested invocation's own log.
            Ok(_) => Value::Null,
            Err(error) => json!({ "error": error.client_message() }),
        }
    }
}
