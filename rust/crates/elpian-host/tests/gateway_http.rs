//! The HTTP surface, over a real socket.
//!
//! These drive the whole path a device takes: fetch the manifest, fetch the
//! client bytecode, invoke a function, get a result — the thing the previous
//! server answered with 501.

use std::io::{Read, Write};
use std::net::TcpStream;
use std::sync::Arc;

use elpian_host::app::{AppDefinition, FunctionKind, NetworkMode};
use elpian_host::runtime::AppRuntime;
use elpian_vm::api::Capability;
use serde_json::{json, Value};

// ---- AST helpers -----------------------------------------------------------

fn ident(name: &str) -> Value {
    json!({ "type": "identifier", "data": { "name": name } })
}
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

// ---- A tiny HTTP client ----------------------------------------------------

struct HttpResponse {
    status: u16,
    body: Vec<u8>,
}

impl HttpResponse {
    fn json(&self) -> Value {
        serde_json::from_slice(&self.body).unwrap_or_else(|e| {
            panic!(
                "body was not JSON ({e}): {}",
                String::from_utf8_lossy(&self.body)
            )
        })
    }
}

fn request(addr: std::net::SocketAddr, method: &str, path: &str, body: &str) -> HttpResponse {
    let mut stream = TcpStream::connect(addr).expect("connect to the host");
    let head = format!(
        "{method} {path} HTTP/1.1\r\nHost: localhost\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        body.len()
    );
    stream.write_all(head.as_bytes()).unwrap();
    stream.write_all(body.as_bytes()).unwrap();
    stream.flush().unwrap();

    let mut raw = Vec::new();
    stream.read_to_end(&mut raw).expect("read the response");

    let split = raw
        .windows(4)
        .position(|w| w == b"\r\n\r\n")
        .expect("a complete response with headers");
    let head = String::from_utf8_lossy(&raw[..split]).to_string();
    let status = head
        .lines()
        .next()
        .and_then(|line| line.split_whitespace().nth(1))
        .and_then(|code| code.parse().ok())
        .expect("a status line");

    HttpResponse {
        status,
        body: raw[split + 4..].to_vec(),
    }
}

// ---- Fixture ---------------------------------------------------------------

fn serving() -> (elpian_host::httpcore::ServerHandle, Arc<AppRuntime>) {
    serving_with_queue(4, elpian_host::httpcore::DEFAULT_QUEUE_PER_WORKER * 4)
}

fn serving_with_queue(
    workers: usize,
    queue: usize,
) -> (elpian_host::httpcore::ServerHandle, Arc<AppRuntime>) {
    let runtime = AppRuntime::new();
    runtime.register(
        AppDefinition::new("notes")
            .with_capabilities(vec![Capability::State, Capability::Logging])
            .with_network(NetworkMode::Closed)
            .with_client(module(vec![func_def(
                "view",
                vec![],
                vec![ret(strv("the client half"))],
            )]))
            .with_function(
                "save",
                FunctionKind::Action,
                module(vec![func_def(
                    "save",
                    vec!["v"],
                    vec![ret(host_call("kv.set", vec![strv("note"), ident("v")]))],
                )]),
            )
            .with_function(
                "load",
                FunctionKind::Action,
                module(vec![func_def(
                    "load",
                    vec![],
                    vec![ret(host_call("kv.get", vec![strv("note")]))],
                )]),
            )
            .with_function(
                "NoteView",
                FunctionKind::Component,
                module(vec![func_def(
                    "NoteView",
                    vec![],
                    vec![ret(host_call("kv.get", vec![strv("note")]))],
                )]),
            ),
    );

    let listener = std::net::TcpListener::bind("127.0.0.1:0").expect("bind an ephemeral port");
    let handle = elpian_host::httpcore::serve_with_queue(
        listener,
        workers,
        queue,
        elpian_host::gateway::handler(Arc::clone(&runtime)),
    );
    (handle, runtime)
}

// ---- Tests -----------------------------------------------------------------

#[test]
fn a_device_can_fetch_a_manifest_and_the_client_bytecode() {
    let (server, _runtime) = serving();

    let manifest = request(server.addr, "GET", "/apps/notes/manifest.json", "");
    assert_eq!(manifest.status, 200);
    let body = manifest.json();
    assert_eq!(body["app"], json!("notes"));
    assert_eq!(body["client"], json!("/apps/notes/client.bc"));
    assert_eq!(body["network"], json!("closed"));
    // The function table names every function and its kind, so a client knows
    // which door to use.
    let functions = body["functions"].as_array().unwrap();
    assert_eq!(functions.len(), 3);
    assert!(functions
        .iter()
        .any(|f| f["name"] == json!("NoteView") && f["kind"] == json!("component")));

    let client = request(server.addr, "GET", "/apps/notes/client.bc", "");
    assert_eq!(client.status, 200);
    assert!(!client.body.is_empty(), "the client bytecode was served");

    server.stop();
}

#[test]
fn invoking_a_function_over_http_returns_its_value() {
    let (server, _runtime) = serving();

    let saved = request(server.addr, "POST", "/apps/notes/fn/save", "\"hello\"");
    assert_eq!(saved.status, 200);
    assert_eq!(saved.json()["ok"], json!(true));
    assert_eq!(saved.json()["result"], json!(true));

    let loaded = request(server.addr, "POST", "/apps/notes/fn/load", "");
    assert_eq!(loaded.status, 200);
    assert_eq!(
        loaded.json()["result"],
        json!("hello"),
        "state written by one call was visible to the next"
    );

    server.stop();
}

#[test]
fn a_server_component_is_invoked_through_its_own_route() {
    let (server, _runtime) = serving();
    request(server.addr, "POST", "/apps/notes/fn/save", "\"rendered\"");

    let rendered = request(server.addr, "POST", "/apps/notes/render/NoteView", "");
    assert_eq!(rendered.status, 200);
    assert_eq!(rendered.json()["result"], json!("rendered"));

    // The same function through the action door is a 400, not a silent success.
    let wrong = request(server.addr, "POST", "/apps/notes/fn/NoteView", "");
    assert_eq!(wrong.status, 400);
    assert_eq!(wrong.json()["error"], json!("NoteView is not action"));

    server.stop();
}

#[test]
fn unknown_apps_functions_routes_and_methods_are_distinguished() {
    let (server, _runtime) = serving();

    assert_eq!(
        request(server.addr, "GET", "/apps/ghost/manifest.json", "").status,
        404
    );
    assert_eq!(
        request(server.addr, "POST", "/apps/ghost/fn/save", "").status,
        404
    );
    assert_eq!(
        request(server.addr, "POST", "/apps/notes/fn/ghost", "").status,
        404
    );
    assert_eq!(request(server.addr, "GET", "/nowhere", "").status, 404);
    // The right path, the wrong verb.
    assert_eq!(
        request(server.addr, "GET", "/apps/notes/fn/save", "").status,
        405
    );

    server.stop();
}

#[test]
fn a_malformed_body_is_refused_before_any_guest_runs() {
    let (server, _runtime) = serving();
    let response = request(server.addr, "POST", "/apps/notes/fn/save", "{not json");
    assert_eq!(response.status, 400);
    assert!(response.json()["error"]
        .as_str()
        .unwrap()
        .contains("not valid JSON"));
    server.stop();
}

#[test]
fn a_guest_trap_returns_500_without_leaking_the_reason_to_the_caller() {
    let runtime = AppRuntime::new();
    runtime.register(AppDefinition::new("bad").with_function(
        "boom",
        FunctionKind::Action,
        module(vec![func_def(
            "boom",
            vec![],
            vec![ret(json!({ "type": "arithmetic", "data": {
                "operation": "-",
                "operand1": { "type": "object", "data": { "value": {} } },
                "operand2": { "type": "i64", "data": { "value": 1 } } } }))],
        )]),
    ));
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let server = elpian_host::httpcore::serve(
        listener,
        2,
        elpian_host::gateway::handler(Arc::clone(&runtime)),
    );

    let response = request(server.addr, "POST", "/apps/bad/fn/boom", "");
    let error = response.json()["error"].as_str().unwrap().to_string();
    assert_eq!(response.status, 500);
    assert_eq!(
        error, "the function failed",
        "the caller must not be told about interpreter internals"
    );
    assert!(
        !error.contains("subtract"),
        "the trap detail stayed server-side"
    );

    server.stop();
}

#[test]
fn a_burst_well_past_the_worker_count_is_absorbed_rather_than_shed() {
    let (server, _runtime) = serving();
    let addr = server.addr;

    // 64 simultaneous invocations on a host with a handful of workers. A page
    // opening does not arrive one request at a time, so a burst this size is
    // ordinary traffic and every one of them must be answered — the queue's
    // job is to absorb it. (It was `workers * 4` deep, which on a two-core box
    // is eight slots, and this shed load at 503.)
    let handles: Vec<_> = (0..64)
        .map(|n| {
            std::thread::spawn(move || {
                let body = format!("\"value-{n}\"");
                request(addr, "POST", "/apps/notes/fn/save", &body).status
            })
        })
        .collect();
    let statuses: Vec<u16> = handles
        .into_iter()
        .map(|h| h.join().expect("no thread panicked"))
        .collect();

    let shed = statuses.iter().filter(|s| **s == 503).count();
    assert_eq!(
        shed, 0,
        "{shed} of 64 requests were shed under an ordinary burst"
    );
    assert!(statuses.iter().all(|s| *s == 200));

    server.stop();
}

#[test]
fn the_queue_is_still_bounded() {
    // The bound is a safety property, not a tuning knob: an unbounded queue
    // turns overload into unbounded latency, where every client waits and then
    // times out. With a queue of one and a single worker, a burst must shed
    // rather than accept everything.
    let (server, _runtime) = serving_with_queue(1, 1);
    let addr = server.addr;

    let handles: Vec<_> = (0..32)
        .map(|_| {
            std::thread::spawn(move || request(addr, "POST", "/apps/notes/fn/load", "").status)
        })
        .collect();
    let statuses: Vec<u16> = handles.into_iter().map(|h| h.join().unwrap()).collect();

    assert!(
        statuses.contains(&503),
        "a deliberately tiny queue should shed load, got {statuses:?}"
    );
    assert!(
        statuses.iter().all(|s| *s == 200 || *s == 503),
        "shedding must be an explicit 503, never a dropped connection"
    );

    server.stop();
}
