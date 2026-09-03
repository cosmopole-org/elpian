//! The real [`HostServices`]: what actually answers a server function's
//! `askHost` calls.
//!
//! Two rules run through all of it.
//!
//! **The guest never supplies its own identity.** App scoping for state, files
//! and secrets comes from the [`ServerContext`] the host built when it routed
//! the request. A guest cannot name another app because it never names an app
//! at all.
//!
//! **A refusal is a null, not an error.** The VM already substitutes a typed
//! null when a capability is denied, so guest code must handle null from any
//! host call regardless. Answering a *failed* call the same way means there is
//! one path to get right in guest code instead of two — and it means a
//! failure cannot be distinguished from a denial by probing, which is the
//! answer we want for anything the guest is not allowed to learn.

use std::time::{SystemTime, UNIX_EPOCH};

use elpian_vm::api;
use serde_json::{json, Value};

use crate::app::FunctionKind;
use crate::appfs::AppFs;
use crate::hostcall::{HostCall, HostServices};
use crate::state::{SecretStore, StateStore};

/// How a running server function reaches another function of the same app.
///
/// A trait so the services layer does not depend on the runtime that owns it —
/// which would be a cycle — and so a test can supply a stub.
pub trait FunctionInvoker: Send {
    fn invoke(&self, function: &str, args: &Value, kind: FunctionKind) -> Value;
}

/// Everything one invocation runs against.
#[derive(Clone)]
pub struct ServerContext {
    /// Which app this is. The host's, from the routed request — never the
    /// guest's.
    pub app: String,
    /// The instance being driven, for storage accounting.
    pub machine_id: String,
    /// Which function is running, for logs.
    pub function: String,
    /// Secret names this app's manifest declared. A name absent here reads as
    /// absent entirely.
    pub declared_secrets: Vec<String>,
    /// The app's private directory, if it was given one.
    pub fs: Option<AppFs>,
}

/// Diagnostics a host collects from an invocation.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct InvocationLog {
    /// Lines the guest wrote with `log`.
    pub guest: Vec<String>,
    /// Lines the host wrote about the guest.
    pub host: Vec<String>,
}

/// The host side of one invocation.
pub struct ServerServices {
    ctx: ServerContext,
    state: StateStore,
    secrets: SecretStore,
    /// Set when this invocation is allowed to call sibling functions. Absent
    /// means `server.*` answers null — which is what a bare `invoke` in a test
    /// gets, and is the safe direction.
    invoker: Option<Box<dyn FunctionInvoker>>,
    /// Collected rather than printed, so the caller decides where diagnostics
    /// go — a test asserts on them, a server writes them to its log, and
    /// neither has to intercept stdout.
    pub log: InvocationLog,
}

impl ServerServices {
    pub fn new(ctx: ServerContext, state: StateStore, secrets: SecretStore) -> Self {
        ServerServices {
            ctx,
            state,
            secrets,
            invoker: None,
            log: InvocationLog::default(),
        }
    }

    /// Allow this invocation to call sibling functions of the same app.
    pub fn set_invoker(&mut self, invoker: Box<dyn FunctionInvoker>) {
        self.invoker = Some(invoker);
    }

    fn service_kv(&mut self, call: &HostCall) -> Value {
        let Some(key) = call.str_arg(0) else {
            return Value::Null;
        };
        match call.api.as_str() {
            "kv.get" => self
                .state
                .get(&self.ctx.app, key)
                .unwrap_or(Value::Null),
            "kv.set" => {
                let value = call.arg(1).clone();
                match self.state.set(&self.ctx.app, key, value) {
                    Ok(()) => Value::Bool(true),
                    Err(error) => {
                        // The operator sees why; the guest sees a plain false,
                        // because "which quota did I hit" is host capacity
                        // information, not the app's.
                        self.log.host.push(format!(
                            "kv.set refused for {}: {}",
                            self.ctx.app,
                            error.as_str()
                        ));
                        Value::Bool(false)
                    }
                }
            }
            "kv.delete" => Value::Bool(self.state.delete(&self.ctx.app, key)),
            "kv.list" => json!(self.state.list(&self.ctx.app, key)),
            _ => Value::Null,
        }
    }

    fn service_fs(&mut self, call: &HostCall) -> Value {
        let (Some(fs), Some(path)) = (self.ctx.fs.clone(), call.str_arg(0)) else {
            return Value::Null;
        };
        let Some(resolved) = fs.resolve(path) else {
            self.log
                .host
                .push(format!("fs: refused path outside the app root: {path}"));
            return Value::Null;
        };

        match call.api.as_str() {
            "fs.read" => std::fs::read_to_string(&resolved)
                .map(Value::String)
                .unwrap_or(Value::Null),
            "fs.write" | "fs.append" => {
                let Some(contents) = call.str_arg(1) else {
                    return Value::Null;
                };
                let previous = std::fs::metadata(&resolved).map(|m| m.len()).unwrap_or(0);
                let result = if call.api == "fs.append" {
                    use std::io::Write;
                    std::fs::OpenOptions::new()
                        .create(true)
                        .append(true)
                        .open(&resolved)
                        .and_then(|mut f| f.write_all(contents.as_bytes()))
                } else {
                    if let Some(parent) = resolved.parent() {
                        let _ = std::fs::create_dir_all(parent);
                    }
                    std::fs::write(&resolved, contents)
                };
                if result.is_err() {
                    return Value::Bool(false);
                }
                // Charge the delta against the instance's storage budget, so a
                // server function's files count the same as a client's.
                let now = std::fs::metadata(&resolved).map(|m| m.len()).unwrap_or(0);
                let delta = now as i64 - previous as i64;
                if let Err(reason) = api::charge_storage(&self.ctx.machine_id, delta) {
                    self.log
                        .host
                        .push(format!("fs: storage charge refused: {reason}"));
                }
                Value::Bool(true)
            }
            "fs.delete" => {
                let size = std::fs::metadata(&resolved).map(|m| m.len()).unwrap_or(0);
                match std::fs::remove_file(&resolved) {
                    Ok(()) => {
                        let _ = api::charge_storage(&self.ctx.machine_id, -(size as i64));
                        Value::Bool(true)
                    }
                    Err(_) => Value::Bool(false),
                }
            }
            "fs.exists" => Value::Bool(resolved.exists()),
            "fs.mkdir" => Value::Bool(std::fs::create_dir_all(&resolved).is_ok()),
            "fs.list" => match std::fs::read_dir(&resolved) {
                Ok(entries) => {
                    let mut names: Vec<String> = entries
                        .flatten()
                        .map(|e| e.file_name().to_string_lossy().into_owned())
                        .collect();
                    // Sorted for the same reason `kv.list` is: a directory's
                    // iteration order is not stable, and a server component
                    // that renders it would not be cacheable.
                    names.sort();
                    json!(names)
                }
                Err(_) => Value::Null,
            },
            "fs.stat" => match std::fs::metadata(&resolved) {
                Ok(meta) => json!({
                    "size": meta.len(),
                    "isFile": meta.is_file(),
                    "isDir": meta.is_dir(),
                }),
                Err(_) => Value::Null,
            },
            _ => Value::Null,
        }
    }
}

impl HostServices for ServerServices {
    fn service(&mut self, call: &HostCall) -> Value {
        match call.api.as_str() {
            "log" | "println" => {
                let line = match call.arg(0) {
                    Value::String(s) => s.clone(),
                    other => other.to_string(),
                };
                self.log.guest.push(line);
                Value::Null
            }

            "time.now" => {
                let millis = SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .map(|d| d.as_millis() as u64)
                    .unwrap_or(0);
                json!(millis)
            }
            "time.monotonic" => json!(monotonic_millis()),

            "random.next" => json!(next_random()),
            "random.bytes" => {
                let count = call.arg(0).as_u64().unwrap_or(0).min(4096) as usize;
                json!((0..count)
                    .map(|_| (next_random() * 256.0) as u8)
                    .collect::<Vec<u8>>())
            }

            // A server function calling a sibling. The app is *not* a
            // parameter: the invoker was built around the app whose function is
            // running, so a guest cannot name another app's function because it
            // never names an app at all.
            "server.call" | "server.render" => {
                let Some(name) = call.str_arg(0) else {
                    return Value::Null;
                };
                let args = call.arg(1).clone();
                let kind = if call.api == "server.render" {
                    FunctionKind::Component
                } else {
                    FunctionKind::Action
                };
                match &self.invoker {
                    Some(invoker) => invoker.invoke(name, &args, kind),
                    None => {
                        self.log.host.push(format!(
                            "{}: {} with no invoker configured",
                            self.ctx.app, call.api
                        ));
                        Value::Null
                    }
                }
            }

            api if api.starts_with("kv.") => self.service_kv(call),
            api if api.starts_with("fs.") => self.service_fs(call),

            "secret.get" => match call.str_arg(0) {
                Some(name) => self
                    .secrets
                    .get(&self.ctx.app, name, &self.ctx.declared_secrets)
                    .map(Value::String)
                    .unwrap_or(Value::Null),
                None => Value::Null,
            },

            // Anything else reaching here is a call the capability posture let
            // through but this host does not implement. Answering null keeps
            // the guest deterministic; the log line is how the gap gets found.
            other => {
                self.log.host.push(format!(
                    "{}/{}: unimplemented host API {other}",
                    self.ctx.app, self.ctx.function
                ));
                Value::Null
            }
        }
    }

    fn log(&mut self, message: &str) {
        self.log.host.push(message.to_string());
    }
}

fn monotonic_millis() -> u64 {
    use std::sync::OnceLock;
    use std::time::Instant;
    static START: OnceLock<Instant> = OnceLock::new();
    START.get_or_init(Instant::now).elapsed().as_millis() as u64
}

/// Host-side randomness for `random.*`.
///
/// Deliberately *not* the VM's deterministic `random` builtin: that one is
/// seeded and reproducible, which is right for a guest's own arithmetic and
/// wrong for anything a guest would use to make an id. This draws from the
/// OS-independent entropy the host can reach without a dependency — good enough
/// for ids and jitter, and explicitly not for keys.
fn next_random() -> f64 {
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};
    static STATE: AtomicU64 = AtomicU64::new(0);

    let mut x = STATE.load(Ordering::Relaxed);
    if x == 0 {
        // Seed from the clock on first use, so two processes started at
        // different times do not draw the same sequence.
        x = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos() as u64)
            .unwrap_or(0x9E37_79B9_7F4A_7C15)
            | 1;
    }
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    STATE.store(x, Ordering::Relaxed);
    let scrambled = x.wrapping_mul(0x2545_F491_4F6C_DD1D);
    (scrambled >> 11) as f64 / (1u64 << 53) as f64
}
