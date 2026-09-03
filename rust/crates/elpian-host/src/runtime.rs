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
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, RwLock};

use elpian_vm::api;
use serde_json::{json, Value};

use crate::app::{AppDefinition, FunctionKind};
use crate::appfs::AppFs;
use crate::invoke::{invoke, InvokeLimits, Outcome};
use crate::posture::server_capabilities;
use crate::services::{InvocationLog, ServerContext, ServerServices};
use crate::state::{SecretStore, StateStore};

/// How deep a chain of `server.call`s may go.
///
/// A function calling another function is ordinary; a function calling itself,
/// directly or through a cycle, is not, and each level holds an instance and a
/// stack frame. The bound is small on purpose: a legitimate chain is a handful
/// deep, and anything more is a bug that would otherwise cost a thread.
const MAX_CALL_DEPTH: u32 = 8;

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
}

/// Registered apps and the stores they run against.
pub struct AppRuntime {
    apps: RwLock<HashMap<String, AppDefinition>>,
    state: StateStore,
    secrets: SecretStore,
    /// Where each app's private directory lives, if apps get one.
    data_root: Option<PathBuf>,
    limits: InvokeLimits,
    /// Makes each instance's machine id unique. Ids must not be reused while a
    /// previous instance could still be finishing: the registry is keyed by id,
    /// and a reused one would address the wrong instance.
    next_instance: AtomicU64,
}

impl AppRuntime {
    pub fn new() -> Arc<AppRuntime> {
        Arc::new(AppRuntime {
            apps: RwLock::new(HashMap::new()),
            state: StateStore::default(),
            secrets: SecretStore::new(),
            data_root: None,
            limits: InvokeLimits::default(),
            next_instance: AtomicU64::new(1),
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
            next_instance: AtomicU64::new(1),
        })
    }

    pub fn register(&self, app: AppDefinition) {
        self.write_apps().insert(app.id.clone(), app);
    }

    pub fn unregister(&self, app_id: &str) -> bool {
        self.write_apps().remove(app_id).is_some()
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

        Ok(self.with_instance(&app, &def, |machine_id| {
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
            };
            let mut services = ServerServices::new(ctx, self.state.clone(), self.secrets.clone());
            services.set_invoker(Box::new(NestedInvoker {
                runtime: Arc::clone(self),
                app: app.id.clone(),
                depth: depth + 1,
            }));

            let outcome = invoke(machine_id, function, args, &mut services, &self.limits);
            Invocation {
                outcome,
                log: services.log,
                cold_start: true,
            }
        }))
    }

    /// Create, govern, run and destroy one instance.
    ///
    /// The single place an instance's lifetime is decided, so the warm pool
    /// replaces this function rather than every caller. Governance is applied
    /// *before* `body` runs — there is no window in which guest code executes
    /// ungoverned.
    fn with_instance<R>(
        &self,
        app: &AppDefinition,
        def: &crate::app::FunctionDef,
        body: impl FnOnce(&str) -> R,
    ) -> R {
        let machine_id = format!(
            "{}::{}::{}",
            app.id,
            def.name,
            self.next_instance.fetch_add(1, Ordering::Relaxed)
        );

        api::create_vm_from_bytecode(machine_id.clone(), def.bytecode.clone());
        api::set_capabilities(&machine_id, server_capabilities(&app.effective_capabilities()));
        api::set_limits(&machine_id, app.limits.clone());

        let result = body(&machine_id);
        api::destroy_vm(machine_id);
        result
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
