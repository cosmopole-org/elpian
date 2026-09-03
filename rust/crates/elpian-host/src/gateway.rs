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
use crate::runtime::{AppRuntime, CallError};
use crate::Outcome;

/// Build the request handler for a runtime.
pub fn handler(runtime: Arc<AppRuntime>) -> Arc<dyn Fn(Request) -> Response + Send + Sync> {
    Arc::new(move |request| route(&runtime, &request))
}

fn route(runtime: &Arc<AppRuntime>, request: &Request) -> Response {
    let segments = request.segments();
    match segments.as_slice() {
        ["health"] => Response::json(200, &json!({ "status": "ok" })),

        ["apps"] if request.method == "GET" => {
            Response::json(200, &json!({ "apps": runtime.app_ids() }))
        }

        ["apps", app, "manifest.json"] if is_read(&request.method) => match runtime.manifest(app) {
            Some(manifest) => Response::json(200, &manifest),
            None => Response::error(404, "no such app"),
        },

        ["apps", app, "client.bc"] if is_read(&request.method) => match runtime.client_bytecode(app)
        {
            Some(bytes) => Response::bytes(200, "application/octet-stream", bytes)
                // A device caches the bytecode by content, and verifies it
                // against the hash the manifest carried.
                .with_header("Cache-Control", "public, max-age=31536000, immutable"),
            None => Response::error(404, "no client bytecode for this app"),
        },

        ["apps", app, "fn", function] if request.method == "POST" => {
            invoke_route(runtime, app, function, request, false)
        }

        ["apps", app, "render", function] if request.method == "POST" => {
            invoke_route(runtime, app, function, request, true)
        }

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
    runtime: &Arc<AppRuntime>,
    app: &str,
    function: &str,
    request: &Request,
    render: bool,
) -> Response {
    let args = match parse_args(&request.body) {
        Ok(args) => args,
        Err(message) => return Response::error(400, &message),
    };

    let result = if render {
        runtime.render(app, function, &args)
    } else {
        runtime.call(app, function, &args)
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
        Err(error @ CallError::CallDepthExceeded) => {
            Response::error(500, &error.client_message())
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
