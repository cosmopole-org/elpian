//! The HTTP surface: what a device talks to.
//!
//! Four routes, and the shape of them is the security model in miniature.
//!
//! ```text
//! GET  /apps/<app>/manifest.json   what the app is and what it may call
//! GET  /apps/<app>/client.bc       the client half's bytecode
//! POST /apps/<app>/fn/<name>       invoke an action
//! POST /apps/<app>/render/<name>   invoke a server component
//! ```
//!
//! The app id comes from the **path**, which the gateway parsed, and is handed
//! to the runtime directly. Nothing in the request body influences which app a
//! call runs as. That is why `server.call` needs no cross-app check: by the
//! time guest code runs, the app was decided by routing.

use std::sync::Arc;

use serde_json::{json, Value};

use crate::httpcore::{Request, Response};
use crate::identity::{AdminAudit, AdminEvent, AnonymousOnly, AuthProvider, OperatorAuth};
use crate::registry::now_millis;
use crate::runtime::{AppRuntime, CallError};
use crate::Outcome;

/// Everything the gateway needs besides the runtime.
pub struct Gateway {
    pub runtime: Arc<AppRuntime>,
    /// Turns a caller's credential into `ctx.user`.
    pub auth: Arc<dyn AuthProvider>,
    /// Who may reach `/admin/*`. Unconfigured means nobody.
    pub operator: Arc<OperatorAuth>,
    pub audit: AdminAudit,
}

impl Gateway {
    /// A gateway with anonymous callers and **no** admin access.
    ///
    /// The admin surface being closed by default is the important half: an
    /// unconfigured admin API that is open is how hosts get taken over, and it
    /// fails silently because nothing looks wrong until somebody finds it.
    pub fn new(runtime: Arc<AppRuntime>) -> Gateway {
        Gateway {
            runtime,
            auth: Arc::new(AnonymousOnly),
            operator: Arc::new(OperatorAuth::new(vec![])),
            audit: AdminAudit::new(1000),
        }
    }

    pub fn with_auth(mut self, auth: Arc<dyn AuthProvider>) -> Gateway {
        self.auth = auth;
        self
    }

    pub fn with_operator_tokens(mut self, tokens: Vec<String>) -> Gateway {
        self.operator = Arc::new(OperatorAuth::new(tokens));
        self
    }
}

/// Build the request handler for a runtime, with anonymous callers and no
/// admin access. See [`gateway_handler`] for the configurable form.
pub fn handler(runtime: Arc<AppRuntime>) -> Arc<dyn Fn(Request) -> Response + Send + Sync> {
    gateway_handler(Arc::new(Gateway::new(runtime)))
}

pub fn gateway_handler(gateway: Arc<Gateway>) -> Arc<dyn Fn(Request) -> Response + Send + Sync> {
    Arc::new(move |request| route(&gateway, &request))
}

fn route(gateway: &Arc<Gateway>, request: &Request) -> Response {
    let runtime = &gateway.runtime;
    let segments = request.segments();

    // The admin surface is separated by prefix and checked before anything
    // else, so no admin path can be reached by a route that forgot to ask.
    if segments.first() == Some(&"admin") {
        return admin_route(gateway, request, &segments[1..]);
    }

    match segments.as_slice() {
        ["health"] => Response::json(200, &json!({ "status": "ok" })),

        ["apps"] if request.method == "GET" => {
            Response::json(200, &json!({ "apps": runtime.app_ids() }))
        }

        ["apps", app, "manifest.json"] if is_read(&request.method) => match runtime.manifest(app) {
            Some(manifest) => Response::json(200, &manifest),
            None => Response::error(404, "no such app"),
        },

        ["apps", app, "client.bc"] if is_read(&request.method) => {
            match runtime.client_bytecode(app) {
                Some(bytes) => Response::bytes(200, "application/octet-stream", bytes)
                    // A device caches the bytecode by content, and verifies it
                    // against the hash the manifest carried.
                    .with_header("Cache-Control", "public, max-age=31536000, immutable"),
                None => Response::error(404, "no client bytecode for this app"),
            }
        }

        ["apps", app, "fn", function] if request.method == "POST" => {
            invoke_route(gateway, app, function, request, false)
        }

        ["apps", app, "render", function] if request.method == "POST" => {
            invoke_route(gateway, app, function, request, true)
        }

        // A client VM's outbound request, brokered by the host.
        //
        // The device could open its own socket — but then the app's posture
        // would be enforced only by the device, which the user controls, and
        // the host would have no record of what the app reached. Routing it
        // here means one policy governs both halves and one audit trail sees
        // both.
        ["apps", app, "proxy"] if request.method == "POST" => proxy_route(gateway, app, request),

        // A known path with the wrong method deserves a 405 rather than a 404:
        // "you asked the right thing the wrong way" is actionable, "it does not
        // exist" is not.
        ["apps", _, "fn", _] | ["apps", _, "render", _] => {
            Response::error(405, "use POST to invoke a function")
        }

        _ => Response::error(404, "no such route"),
    }
}

fn is_read(method: &str) -> bool {
    method == "GET" || method == "HEAD"
}

fn invoke_route(
    gateway: &Arc<Gateway>,
    app: &str,
    function: &str,
    request: &Request,
    render: bool,
) -> Response {
    let args = match parse_args(&request.body) {
        Ok(args) => args,
        Err(message) => return Response::error(400, &message),
    };

    // The caller's identity comes from a credential this host verified, and
    // from nowhere else — never from the body, which the caller controls.
    let user = gateway.auth.verify(request.header("authorization"));

    let runtime = &gateway.runtime;
    let result = if render {
        runtime.render_as(app, function, &args, user)
    } else {
        runtime.call_as(app, function, &args, user)
    };

    match result {
        Ok(invocation) => match invocation.outcome {
            Outcome::Returned(value) => Response::json(
                200,
                &json!({ "ok": true, "result": value, "coldStart": invocation.cold_start }),
            ),
            Outcome::Trapped(reason) => {
                // The reason describes the guest's internals — a type error
                // inside somebody's mini app. The operator gets it; the caller
                // gets that it failed. Leaking it would tell a caller about
                // code they cannot see and did not write.
                eprintln!("[elpian] {app}/{function} trapped: {reason}");
                Response::error(500, "the function failed")
            }
            Outcome::TooManyHostCalls => {
                eprintln!("[elpian] {app}/{function} exceeded its host-call budget");
                Response::error(500, "the function failed")
            }
        },
        Err(error @ CallError::UnknownApp(_)) | Err(error @ CallError::UnknownFunction { .. }) => {
            Response::error(404, &error.client_message())
        }
        Err(error @ CallError::WrongKind { .. }) => Response::error(400, &error.client_message()),
        Err(error @ CallError::CallDepthExceeded) => Response::error(500, &error.client_message()),
        // 429, because it is the app that is over budget and a caller may
        // usefully retry later — a 500 would say "broken", which it is not.
        Err(CallError::OverQuota { stage, axis }) => {
            eprintln!("[elpian] {app}/{function} refused: {stage} on {axis}");
            Response::error(429, "this app is over its quota")
        }
    }
}

/// A client-side `net.fetch`, decided and performed by the host.
fn proxy_route(gateway: &Arc<Gateway>, app_id: &str, request: &Request) -> Response {
    let Some(app) = gateway.runtime.app_definition(app_id) else {
        return Response::error(404, "no such app");
    };

    let body: Value = match serde_json::from_slice(&request.body) {
        Ok(value) => value,
        Err(_) => return Response::error(400, "body is not valid JSON"),
    };
    let Some(url) = body.get("url").and_then(Value::as_str) else {
        return Response::error(400, "no url");
    };

    let mut records = Vec::new();
    let result = crate::fetch::fetch(
        &app.network,
        url,
        &crate::fetch::FetchLimits::default(),
        |record| records.push(record),
        app_id,
        "client",
    );
    for record in &records {
        // The operator's record. Allowed and denied alike — an audit trail with
        // only denials answers "what was blocked" and not "what did this app
        // reach", and the second is the question asked after an incident.
        eprintln!(
            "[elpian] egress {} {} {} -> {}",
            record.app,
            if record.allowed { "allow" } else { "deny" },
            record.url,
            record.detail
        );
    }

    match result {
        Ok(response) => Response::json(
            200,
            &json!({
                "ok": true,
                "result": { "status": response.status, "body": response.body }
            }),
        ),
        Err(error) => {
            // The guest-facing message, not the operator's. A caller that could
            // distinguish "not allowlisted" from "connection refused" would
            // have a port scanner built out of the error string.
            Response::json(403, &json!({ "ok": false, "error": error.guest_message() }))
        }
    }
}

/// Parse the request body into the function's arguments.
///
/// An empty body means "no arguments" rather than an error, so a call with
/// nothing to pass does not have to send `null`.
fn parse_args(body: &[u8]) -> Result<Value, String> {
    if body.is_empty() {
        return Ok(Value::Null);
    }
    serde_json::from_slice(body).map_err(|e| format!("body is not valid JSON: {e}"))
}

// ---- The admin surface -----------------------------------------------------

/// Routes under `/admin/`.
///
/// Every one of them is authorised first and audited whatever the outcome. A
/// trail with only successes in it cannot show a run of refused attempts, which
/// is the single most interesting thing an admin log can contain.
fn admin_route(gateway: &Arc<Gateway>, request: &Request, rest: &[&str]) -> Response {
    let credential = request.header("authorization");
    let allowed = gateway.operator.authorize(credential);

    let (action, app) = match rest {
        ["apps"] => ("list", String::new()),
        ["apps", app, verb] => (*verb, (*app).to_string()),
        ["audit"] => ("audit", String::new()),
        _ => ("unknown", String::new()),
    };

    gateway.audit.record(AdminEvent {
        at_ms: now_millis(),
        action: action.to_string(),
        app: app.clone(),
        detail: request.path.clone(),
        allowed,
    });

    if !allowed {
        // The same answer whether the token was wrong or the admin surface was
        // never configured. Distinguishing them would tell an attacker whether
        // there is a token to find.
        return Response::error(401, "not authorised");
    }

    let runtime = &gateway.runtime;
    match rest {
        ["apps"] if request.method == "GET" => {
            Response::json(200, &json!({ "apps": runtime.app_ids() }))
        }

        ["apps", app, "meters"] if request.method == "GET" => {
            let meters = runtime.meters(app);
            Response::json(
                200,
                &json!({
                    "app": app,
                    "stage": runtime.quotas().stage(app, &meters).as_str(),
                    "suspended": runtime.quotas().is_suspended(app),
                    "invocations": meters.invocations,
                    "coldStarts": meters.cold_starts,
                    "instructions": meters.instructions,
                    "computeMs": meters.compute_ms,
                    "peakMemoryBytes": meters.peak_memory_bytes,
                    "storageBytes": meters.storage_bytes,
                }),
            )
        }

        ["apps", app, "drain"] if request.method == "POST" => {
            // Unload every instance of one app without touching any other
            // tenant — what an operator needs before a redeploy or a suspend.
            let unloaded = runtime.pool().drain_app(app);
            Response::json(200, &json!({ "app": app, "unloaded": unloaded.len() }))
        }

        ["apps", app, "instances"] if request.method == "GET" => Response::json(
            200,
            &json!({
                "app": app,
                "loaded": runtime.pool().loaded(),
                "idle": runtime.pool().idle(),
            }),
        ),

        ["apps", app, "suspend"] if request.method == "POST" => {
            gateway.runtime.quotas().suspend(app);
            let unloaded = gateway.runtime.pool().drain_app(app);
            Response::json(
                200,
                &json!({ "app": app, "suspended": true, "unloaded": unloaded.len() }),
            )
        }

        ["apps", app, "resume"] if request.method == "POST" => {
            gateway.runtime.quotas().resume(app);
            Response::json(200, &json!({ "app": app, "suspended": false }))
        }

        ["apps", app, "cache"] if request.method == "DELETE" => {
            let cleared = runtime.clear_cache(app);
            Response::json(200, &json!({ "app": app, "cleared": cleared }))
        }

        ["audit"] if request.method == "GET" => {
            let events: Vec<Value> = gateway
                .audit
                .events()
                .into_iter()
                .map(|e| {
                    json!({
                        "at": e.at_ms,
                        "action": e.action,
                        "app": e.app,
                        "detail": e.detail,
                        "allowed": e.allowed,
                    })
                })
                .collect();
            Response::json(200, &json!({ "events": events }))
        }

        _ => Response::error(404, "no such admin route"),
    }
}
