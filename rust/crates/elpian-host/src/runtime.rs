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

use crate::app::{AppDefinition, FunctionKind};
use crate::appfs::AppFs;
use crate::component::{ComponentPayload, RenderCache};
use crate::pool::{InstancePool, Meters, PoolConfig};
use crate::invoke::{invoke, InvokeLimits, Outcome};
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

/// Why an invocation could not be attempted.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CallError {
    UnknownApp(String),
    UnknownFunction { app: String, function: String },
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
    limits: InvokeLimits,
    cache: RenderCache,
    pool: Arc<InstancePool>,
}

impl AppRuntime {
    pub fn new() -> Arc<AppRuntime> {
        Arc::new(AppRuntime {
            apps: RwLock::new(HashMap::new()),
            state: StateStore::default(),
            secrets: SecretStore::new(),
            data_root: None,
            limits: InvokeLimits::default(),
            cache: RenderCache::new(DEFAULT_RENDER_CACHE_ENTRIES),
            pool: InstancePool::new(PoolConfig::default()),
        })
    }

    pub fn with_data_root(root: impl Into<PathBuf>) -> Arc<AppRuntime> {
        let root = root.into();
        Arc::new(AppRuntime {
            apps: RwLock::new(HashMap::new()),
            state: StateStore::default(),
            secrets: SecretStore::new(),
            data_root: Some(root),
            limits: InvokeLimits::default(),
            cache: RenderCache::new(DEFAULT_RENDER_CACHE_ENTRIES),
            pool: InstancePool::new(PoolConfig::default()),
        })
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

    pub fn register(&self, app: AppDefinition) {
        self.write_apps().insert(app.id.clone(), app);
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
    pub fn call(self: &Arc<Self>, app: &str, function: &str, args: &Value) -> Result<Invocation, CallError> {
        self.dispatch(app, function, args, FunctionKind::Action, 0)
    }

    /// Invoke a server component (`server.render`).
    pub fn render(self: &Arc<Self>, app: &str, function: &str, args: &Value) -> Result<Invocation, CallError> {
        self.dispatch(app, function, args, FunctionKind::Component, 0)
    }

    fn dispatch(
        self: &Arc<Self>,
        app_id: &str,
        function: &str,
        args: &Value,
        expected: FunctionKind,
        depth: u32,
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

        // A cached render short-circuits before any instance is created — the
        // point of the cache is to not run the guest, not to run it faster.
        if expected == FunctionKind::Component {
            if let Some(payload) = self.cache.get(&app.id, function, args) {
                return Ok(Invocation {
                    outcome: Outcome::Returned(payload),
                    log: InvocationLog::default(),
                    cold_start: false,
                    cache_hit: true,
                });
            }
        }

        let invocation = self.with_instance(&app, &def, |machine_id| {
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
                network: app.network.clone(),
            };
            let mut services = ServerServices::new(ctx, self.state.clone(), self.secrets.clone());
            services.set_invoker(Box::new(NestedInvoker {
                runtime: Arc::clone(self),
                app: app.id.clone(),
                depth: depth + 1,
            }));
            services.set_cache(self.cache.clone());

            let outcome = invoke(machine_id, function, args, &mut services, &self.limits);
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
        if expected == FunctionKind::Component {
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
        body: impl FnOnce(&str) -> Invocation,
    ) -> Invocation {
        let lease = self.pool.acquire(app, def);
        let machine_id = lease.machine_id.clone();
        let cold_start = lease.cold_start;

        let before = api::usage(&machine_id).map(|u| u.instructions).unwrap_or(0);
        let started = std::time::Instant::now();

        let mut invocation = body(&machine_id);
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
}

impl crate::services::FunctionInvoker for NestedInvoker {
    fn invoke(&self, function: &str, args: &Value, kind: FunctionKind) -> Value {
        match self
            .runtime
            .dispatch(&self.app, function, args, kind, self.depth)
        {
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
