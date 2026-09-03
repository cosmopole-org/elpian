//! The admin surface, and where `ctx.user` comes from.

use std::io::{Read, Write};
use std::net::TcpStream;
use std::sync::Arc;

use elpian_host::app::{AppDefinition, FunctionKind};
use elpian_host::gateway::Gateway;
use elpian_host::identity::{Identity, StaticTokens};
use elpian_host::runtime::AppRuntime;
use elpian_host::Outcome;
use elpian_vm::api::Capability;
use serde_json::{json, Value};

fn strv(s: &str) -> Value {
    json!({ "type": "string", "data": { "value": s } })
}
fn ret(value: Value) -> Value {
    json!({ "type": "returnOperation", "data": { "value": value } })
}
fn host_call(name: &str, args: Vec<Value>) -> Value {
    json!({ "type": "host_call", "data": { "name": name, "args": args } })
}
fn func_def(name: &str, params: Vec<&str>, body: Vec<Value>) -> Value {
    json!({ "type": "functionDefinition", "data": { "name": name, "params": params, "body": body } })
}
fn module(body: Vec<Value>) -> Vec<u8> {
    elpian_vm::sdk::compiler::compile_ast(json!({ "type": "program", "body": body }), 0)
}
fn returned(outcome: Outcome) -> Value {
    match outcome {
        Outcome::Returned(v) => v,
        other => panic!("expected a returned value, got {other:?}"),
    }
}

// ---- HTTP client -----------------------------------------------------------

struct Res {
    status: u16,
    body: Vec<u8>,
}

impl Res {
    fn json(&self) -> Value {
        serde_json::from_slice(&self.body).unwrap_or(Value::Null)
    }
}

fn request(
    addr: std::net::SocketAddr,
    method: &str,
    path: &str,
    auth: Option<&str>,
    body: &str,
) -> Res {
    let mut stream = TcpStream::connect(addr).unwrap();
    let mut head = format!(
        "{method} {path} HTTP/1.1\r\nHost: localhost\r\nContent-Length: {}\r\nConnection: close\r\n",
        body.len()
    );
    if let Some(token) = auth {
        head.push_str(&format!("Authorization: {token}\r\n"));
    }
    head.push_str("\r\n");
    stream.write_all(head.as_bytes()).unwrap();
    stream.write_all(body.as_bytes()).unwrap();
    stream.flush().unwrap();

    let mut raw = Vec::new();
    stream.read_to_end(&mut raw).unwrap();
    let split = raw.windows(4).position(|w| w == b"\r\n\r\n").unwrap();
    let status = String::from_utf8_lossy(&raw[..split])
        .lines()
        .next()
        .and_then(|l| l.split_whitespace().nth(1))
        .and_then(|c| c.parse().ok())
        .unwrap();
    Res {
        status,
        body: raw[split + 4..].to_vec(),
    }
}

// ---- Fixture ---------------------------------------------------------------

fn app_runtime() -> Arc<AppRuntime> {
    let runtime = AppRuntime::new();
    runtime.register(
        AppDefinition::new("notes")
            .with_capabilities(vec![Capability::State])
            .with_function(
                "whoami",
                FunctionKind::Action,
                module(vec![func_def(
                    "whoami",
                    vec![],
                    vec![ret(host_call("ctx.user", vec![]))],
                )]),
            )
            .with_function(
                "save",
                FunctionKind::Action,
                module(vec![func_def(
                    "save",
                    vec![],
                    vec![ret(host_call("kv.set", vec![strv("k"), strv("v")]))],
                )]),
            ),
    );
    runtime
}

fn serve(gateway: Gateway) -> elpian_host::httpcore::ServerHandle {
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    elpian_host::httpcore::serve(
        listener,
        2,
        elpian_host::gateway::gateway_handler(Arc::new(gateway)),
    )
}

// ---- ctx.user --------------------------------------------------------------

#[test]
fn a_verified_caller_becomes_ctx_user() {
    let tokens = StaticTokens::new();
    tokens.add(
        "alice-token",
        Identity {
            id: "alice".into(),
            roles: vec!["member".into()],
        },
    );
    let server = serve(Gateway::new(app_runtime()).with_auth(tokens));

    let known = request(
        server.addr,
        "POST",
        "/apps/notes/fn/whoami",
        Some("Bearer alice-token"),
        "",
    );
    assert_eq!(known.status, 200);
    assert_eq!(
        known.json()["result"],
        json!({ "id": "alice", "roles": ["member"] })
    );

    server.stop();
}

#[test]
fn an_unverified_caller_is_anonymous_rather_than_whatever_it_claimed() {
    let tokens = StaticTokens::new();
    tokens.add(
        "real-token",
        Identity {
            id: "alice".into(),
            roles: vec!["admin".into()],
        },
    );
    let server = serve(Gateway::new(app_runtime()).with_auth(tokens));

    // No credential at all.
    let anon = request(server.addr, "POST", "/apps/notes/fn/whoami", None, "");
    assert_eq!(anon.json()["result"], json!(null));

    // A guessed one.
    let guessed = request(
        server.addr,
        "POST",
        "/apps/notes/fn/whoami",
        Some("Bearer not-the-token"),
        "",
    );
    assert_eq!(guessed.json()["result"], json!(null));

    // And — the one that matters — an identity asserted in the *body* is
    // ignored entirely. If this were honoured, every `ctx.user` check in every
    // app would be forgeable by the person it protects against.
    let forged = request(
        server.addr,
        "POST",
        "/apps/notes/fn/whoami",
        None,
        r#"{"user":{"id":"alice","roles":["admin"]}}"#,
    );
    assert_eq!(
        forged.json()["result"],
        json!(null),
        "an identity in the request body must never become ctx.user"
    );

    server.stop();
}

#[test]
fn an_authenticated_render_is_not_served_from_the_shared_cache() {
    // Serving one user's page to another is the worst possible cache bug, so an
    // authenticated render bypasses the shared cache entirely. Per-user caching
    // is a real feature; it has to be designed rather than fallen into.
    let runtime = AppRuntime::new();
    runtime.register(
        AppDefinition::new("peruser")
            .with_capabilities(vec![Capability::State])
            .with_function(
                "Panel",
                FunctionKind::Component,
                module(vec![func_def(
                    "Panel",
                    vec![],
                    vec![ret(json!({ "type": "object", "data": { "value": {
                        "component": { "type": "object", "data": { "value": {
                            "type": strv("text") } } },
                        "revalidate": { "type": "object", "data": { "value": {
                            "tags": { "type": "array", "data": { "value": [strv("t")] } } } } }
                    } } }))],
                )]),
            ),
    );

    // Anonymous renders do cache.
    assert!(
        !runtime
            .render("peruser", "Panel", &json!(null))
            .unwrap()
            .cache_hit
    );
    assert!(
        runtime
            .render("peruser", "Panel", &json!(null))
            .unwrap()
            .cache_hit
    );

    // An authenticated one never reads that entry, and never writes one.
    let alice = Some(Identity {
        id: "alice".into(),
        roles: vec![],
    });
    let rendered = runtime
        .render_as("peruser", "Panel", &json!(null), alice)
        .unwrap();
    assert!(
        !rendered.cache_hit,
        "an authenticated render must not be served from the shared cache"
    );
    assert!(returned(rendered.outcome)["component"].is_object());
}

// ---- The admin surface -----------------------------------------------------

#[test]
fn an_unconfigured_admin_surface_refuses_everyone() {
    // Not "allows everyone". An open, unconfigured admin API is how hosts get
    // taken over, and it fails silently.
    let server = serve(Gateway::new(app_runtime()));

    for path in ["/admin/apps", "/admin/audit", "/admin/apps/notes/meters"] {
        assert_eq!(
            request(server.addr, "GET", path, None, "").status,
            401,
            "{path} should be refused"
        );
        assert_eq!(
            request(server.addr, "GET", path, Some("Bearer anything"), "").status,
            401,
            "{path} should be refused even with a token"
        );
    }
    server.stop();
}

#[test]
fn an_operator_token_opens_the_admin_surface() {
    let server = serve(Gateway::new(app_runtime()).with_operator_tokens(vec!["op-token".into()]));
    let auth = Some("Bearer op-token");

    let apps = request(server.addr, "GET", "/admin/apps", auth, "");
    assert_eq!(apps.status, 200);
    assert_eq!(apps.json()["apps"], json!(["notes"]));

    // A wrong token is still refused, and reads the same as no token at all —
    // distinguishing them would say whether there is a token to find.
    assert_eq!(
        request(server.addr, "GET", "/admin/apps", Some("Bearer wrong"), "").status,
        401
    );
    server.stop();
}

#[test]
fn meters_are_readable_through_the_admin_surface() {
    let server = serve(Gateway::new(app_runtime()).with_operator_tokens(vec!["op".into()]));
    let auth = Some("Bearer op");

    for _ in 0..3 {
        request(server.addr, "POST", "/apps/notes/fn/save", None, "");
    }

    let meters = request(server.addr, "GET", "/admin/apps/notes/meters", auth, "").json();
    assert_eq!(meters["invocations"], json!(3));
    assert_eq!(
        meters["coldStarts"],
        json!(1),
        "only the first loaded a module"
    );
    assert!(meters["instructions"].as_u64().unwrap() > 0);
    assert!(meters["storageBytes"].as_u64().unwrap() > 0);

    server.stop();
}

#[test]
fn an_operator_can_drain_one_apps_instances() {
    let server = serve(Gateway::new(app_runtime()).with_operator_tokens(vec!["op".into()]));
    let auth = Some("Bearer op");

    request(server.addr, "POST", "/apps/notes/fn/save", None, "");
    let before = request(server.addr, "GET", "/admin/apps/notes/instances", auth, "").json();
    assert_eq!(before["loaded"], json!(1));

    let drained = request(server.addr, "POST", "/admin/apps/notes/drain", auth, "").json();
    assert_eq!(drained["unloaded"], json!(1));

    let after = request(server.addr, "GET", "/admin/apps/notes/instances", auth, "").json();
    assert_eq!(after["loaded"], json!(0));

    server.stop();
}

#[test]
fn refused_admin_attempts_are_audited_too() {
    // A run of refusals is the single most interesting thing an admin log can
    // contain, and a trail with only successes would not show it.
    let server = serve(Gateway::new(app_runtime()).with_operator_tokens(vec!["op".into()]));

    for _ in 0..3 {
        request(
            server.addr,
            "GET",
            "/admin/apps",
            Some("Bearer guessed"),
            "",
        );
    }
    let audit = request(server.addr, "GET", "/admin/audit", Some("Bearer op"), "").json();
    let events = audit["events"].as_array().unwrap();

    let refusals = events
        .iter()
        .filter(|e| e["allowed"] == json!(false))
        .count();
    assert_eq!(refusals, 3, "every refused attempt was recorded");
    assert!(
        events.iter().any(|e| e["allowed"] == json!(true)),
        "and the successful read of the audit itself"
    );

    server.stop();
}

#[test]
fn the_admin_prefix_cannot_be_reached_through_an_app_route() {
    // The admin surface is separated by prefix and checked before anything
    // else, so no route that forgot to ask can land inside it.
    let server = serve(Gateway::new(app_runtime()));
    for path in [
        "/admin/apps/notes/meters",
        "/apps/../admin/apps",
        "/admin/../admin/apps",
    ] {
        let status = request(server.addr, "GET", path, None, "").status;
        assert!(
            status == 401 || status == 404,
            "{path} returned {status}; it must not be served"
        );
    }
    server.stop();
}
