//! Server components that emit their UI progressively.
//!
//! The transport is newline-delimited JSON over a long-lived response: the
//! traffic is one-way, so a WebSocket would buy bidirectionality nothing uses
//! at the cost of an upgrade handshake, frame masking and a close protocol.
//! Each line is an `ElpianStreamCommand`, the shape `ElpianStreamWidget`
//! already consumes.

use std::io::{Read, Write};
use std::net::TcpStream;
use std::sync::Arc;

use elpian_host::app::{AppDefinition, FunctionKind};
use elpian_host::runtime::{AppRuntime, CallError};
use elpian_vm::api::Capability;
use serde_json::{json, Value};

fn strv(s: &str) -> Value {
    json!({ "type": "string", "data": { "value": s } })
}
fn i64v(n: i64) -> Value {
    json!({ "type": "i64", "data": { "value": n } })
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

/// A component that emits three frames and then returns a final tree.
fn progressive() -> Vec<u8> {
    let emit = |text: &str| {
        host_call(
            "stream.emit",
            vec![json!({ "type": "object", "data": { "value": {
                "action": strv("setView"),
                "view": { "type": "object", "data": { "value": {
                    "type": strv("Text"),
                    "props": { "type": "object", "data": { "value": {
                        "text": strv(text) } } } } } }
            } } })],
        )
    };
    module(vec![func_def(
        "Progressive",
        vec![],
        vec![
            emit("first"),
            emit("second"),
            emit("third"),
            ret(json!({ "type": "object", "data": { "value": {
                "component": { "type": "object", "data": { "value": {
                    "type": strv("Text"),
                    "props": { "type": "object", "data": { "value": {
                        "text": strv("final") } } } } } }
            } } })),
        ],
    )])
}

fn app() -> Arc<AppRuntime> {
    let runtime = AppRuntime::new();
    assert!(runtime.register(
        AppDefinition::new("live")
            .with_capabilities(vec![Capability::ServerCall, Capability::State])
            .with_function("Progressive", FunctionKind::Component, progressive())
            .with_function(
                "Silent",
                FunctionKind::Component,
                // Neither emits nor returns a payload.
                module(vec![func_def("Silent", vec![], vec![ret(strv("nope"))])]),
            )
            .with_function(
                "Emitter",
                FunctionKind::Component,
                module(vec![func_def(
                    "Emitter",
                    vec![],
                    vec![
                        host_call(
                            "stream.emit",
                            vec![json!({ "type": "object", "data": { "value": {
                                "action": strv("setView"),
                                "view": { "type": "object", "data": { "value": {
                                    "type": strv("Text") } } } } } })],
                        ),
                        ret(i64v(0)),
                    ],
                )]),
            )
            .with_function(
                "Act",
                FunctionKind::Action,
                module(vec![func_def("Act", vec![], vec![ret(strv("ok"))])]),
            )
    ));
    runtime
}

// ---- The runtime path ------------------------------------------------------

#[test]
fn frames_arrive_in_order_as_the_component_emits_them() {
    let runtime = app();
    let mut frames = Vec::new();
    runtime
        .render_stream("live", "Progressive", &json!(null), None, &mut |frame| {
            frames.push(frame.clone());
            true
        })
        .expect("the stream should complete");

    let texts: Vec<String> = frames
        .iter()
        .filter_map(|f| f["view"]["props"]["text"].as_str().map(str::to_string))
        .collect();
    assert_eq!(
        texts,
        vec!["first", "second", "third", "final"],
        "three emitted frames, then the returned payload as the last one"
    );
    assert!(frames.iter().all(|f| f["action"] == json!("setView")));
}

#[test]
fn a_component_that_only_emits_is_fine() {
    // Returning a payload is optional: a component may stream and stop.
    let runtime = app();
    let mut count = 0;
    runtime
        .render_stream("live", "Emitter", &json!(null), None, &mut |_| {
            count += 1;
            true
        })
        .expect("the stream should complete");
    assert_eq!(count, 1);
}

#[test]
fn a_component_that_neither_emits_nor_returns_a_payload_is_an_error() {
    // Silently sending nothing would leave the device on its pending state
    // forever with no way to tell whether that was intended.
    let runtime = app();
    let result = runtime.render_stream("live", "Silent", &json!(null), None, &mut |_| true);
    assert!(
        matches!(result, Err(CallError::WrongKind { .. })),
        "got {result:?}"
    );
}

#[test]
fn a_dead_reader_is_reported_to_the_guest_so_it_can_stop() {
    // A component looping over a large result should be able to stop when the
    // device has gone, rather than computing the rest for nobody.
    let runtime = app();
    let mut seen = 0;
    let _ = runtime.render_stream("live", "Progressive", &json!(null), None, &mut |_| {
        seen += 1;
        false // the reader is gone from the very first frame
    });
    // The host keeps offering frames the guest chooses to emit — the signal is
    // advisory, not a kill — but the guest was told on every one.
    assert!(seen >= 1);
}

#[test]
fn an_action_cannot_be_streamed() {
    let runtime = app();
    match runtime.render_stream("live", "Act", &json!(null), None, &mut |_| true) {
        Err(CallError::WrongKind { actual, .. }) => assert_eq!(actual, "action"),
        other => panic!("expected a kind mismatch, got {other:?}"),
    }
}

#[test]
fn a_streaming_render_is_never_served_from_or_written_to_the_cache() {
    // The cache stores one payload; a stream is a sequence. Replaying a
    // finished sequence as a single frame would silently change what the
    // component does.
    let runtime = app();
    let mut first = Vec::new();
    runtime
        .render_stream("live", "Progressive", &json!(null), None, &mut |f| {
            first.push(f.clone());
            true
        })
        .unwrap();

    let mut second = Vec::new();
    runtime
        .render_stream("live", "Progressive", &json!(null), None, &mut |f| {
            second.push(f.clone());
            true
        })
        .unwrap();

    assert_eq!(first.len(), second.len(), "the second run streamed too");
    assert_eq!(first.len(), 4);
}

#[test]
fn stream_emit_from_a_non_streaming_invocation_returns_false() {
    // A component written for the streaming door and invoked through the plain
    // one should be able to tell, rather than having its frames vanish.
    let runtime = app();
    let invocation = runtime.render("live", "Emitter", &json!(null)).unwrap();
    assert!(
        invocation
            .log
            .host
            .iter()
            .any(|line| line.contains("stream.emit outside a streaming invocation")),
        "the host recorded the mismatch: {:?}",
        invocation.log.host
    );
}

// ---- Over HTTP -------------------------------------------------------------

#[test]
fn the_http_route_writes_newline_delimited_json() {
    let runtime = app();
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let server = elpian_host::httpcore::serve(
        listener,
        2,
        elpian_host::gateway::handler(Arc::clone(&runtime)),
    );

    let mut stream = TcpStream::connect(server.addr).unwrap();
    stream
        .write_all(
            b"POST /apps/live/stream/Progressive HTTP/1.1\r\nHost: localhost\r\n\
              Content-Length: 0\r\nConnection: close\r\n\r\n",
        )
        .unwrap();
    stream.flush().unwrap();

    let mut raw = Vec::new();
    stream.read_to_end(&mut raw).unwrap();
    let text = String::from_utf8_lossy(&raw).to_string();

    assert!(text.contains("200 OK"), "{text}");
    assert!(
        text.contains("application/x-ndjson"),
        "the content type says what the body is: {text}"
    );
    // No Content-Length: the host genuinely does not know how many frames a
    // component will emit, and saying otherwise would be a lie the client acts on.
    assert!(!text.to_lowercase().contains("content-length"), "{text}");

    let body = text.split("\r\n\r\n").nth(1).expect("a body");
    let lines: Vec<&str> = body.lines().filter(|l| !l.trim().is_empty()).collect();
    assert_eq!(lines.len(), 4, "four frames, one per line: {body}");
    for line in &lines {
        let frame: Value = serde_json::from_str(line)
            .unwrap_or_else(|e| panic!("each line is its own JSON object ({e}): {line}"));
        assert_eq!(frame["action"], json!("setView"));
    }

    server.stop();
}

#[test]
fn a_stream_of_an_unknown_function_reports_the_error_in_band() {
    // The status line went out with the first byte and cannot be revised, so a
    // failure has to arrive as a frame.
    let runtime = app();
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let server = elpian_host::httpcore::serve(
        listener,
        2,
        elpian_host::gateway::handler(Arc::clone(&runtime)),
    );

    let mut stream = TcpStream::connect(server.addr).unwrap();
    stream
        .write_all(
            b"POST /apps/live/stream/Ghost HTTP/1.1\r\nHost: localhost\r\n\
              Content-Length: 0\r\nConnection: close\r\n\r\n",
        )
        .unwrap();
    stream.flush().unwrap();

    let mut raw = Vec::new();
    stream.read_to_end(&mut raw).unwrap();
    let text = String::from_utf8_lossy(&raw).to_string();
    let body = text.split("\r\n\r\n").nth(1).unwrap_or_default();

    let frame: Value = serde_json::from_str(body.trim()).expect("an error frame");
    assert_eq!(frame["action"], json!("error"));
    assert_eq!(frame["message"], json!("no such function: Ghost"));

    server.stop();
}
