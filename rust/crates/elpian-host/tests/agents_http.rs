//! Agents over HTTP, end to end with the scripted provider: the NDJSON
//! contract, function tools through the ordinary invoke path (identity and
//! meters), the manifest listing, and the refusals that happen before a stream
//! starts.

use std::collections::BTreeMap;
use std::io::{Read, Write};
use std::net::TcpStream;
use std::sync::Arc;

use elpian_agent::a2ui::BASIC_CATALOG_ID;
use elpian_host::agents::AgentSettings;
use elpian_host::app::{AppDefinition, FunctionKind};
use elpian_host::gateway::{gateway_handler, Gateway};
use elpian_host::identity::{Identity, StaticTokens};
use elpian_host::runtime::AppRuntime;
use elpian_vm::api::Capability;
use serde_json::{json, Value};

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

fn script() -> Value {
    json!({ "exchanges": [
        { "when": { "action": "order" },
          "turns": [ { "text": "Ordered {{action.context.item}}." } ] },
        { "turns": [
            { "text": "Let me check who you are.",
              "tools": [ { "name": "fn_whoami", "input": {} } ] },
            { "tools": [ { "name": "a2ui_send", "input": { "messages": [
                { "createSurface": { "surfaceId": "main", "catalogId": BASIC_CATALOG_ID } },
                { "updateComponents": { "surfaceId": "main", "components": [
                    { "id": "root", "component": "Column", "children": ["title", "buy"] },
                    { "id": "title", "component": "Text", "text": { "path": "/title" }, "variant": "h2" },
                    { "id": "buy_label", "component": "Text", "text": "Buy" },
                    { "id": "buy", "component": "Button", "child": "buy_label",
                      "action": { "event": { "name": "order", "context": { "item": "tea" } } } }
                ] } },
                { "updateDataModel": { "surfaceId": "main", "value": { "title": "{{message}}" } } }
            ] } } ] },
            { "text": "Here you go." }
        ] }
    ] })
}

fn manifest() -> Value {
    json!({
        "id": "shop",
        "secrets": ["ANTHROPIC_API_KEY"],
        "functions": [ { "name": "whoami", "kind": "action", "description": "Who is calling." } ],
        "agents": [ {
            "name": "assistant",
            "description": "Shop assistant",
            "instructions": "agents/assistant.md",
            "skills": ["browse"],
            "tools": ["whoami"],
            "provider": "scripted"
        } ]
    })
}

fn files() -> BTreeMap<String, Vec<u8>> {
    let mut files = BTreeMap::new();
    files.insert("agents/assistant.md".into(), b"Sell tea.".to_vec());
    files.insert(
        "agents/skills/browse/SKILL.md".into(),
        b"---\nname: browse\ndescription: Browse the shop.\n---\nShow a list.\n".to_vec(),
    );
    files.insert(
        "agents/scripted.json".into(),
        script().to_string().into_bytes(),
    );
    files
}

fn runtime() -> Arc<AppRuntime> {
    let runtime = AppRuntime::new();
    let app = AppDefinition::new("shop")
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
        .with_secrets(vec!["ANTHROPIC_API_KEY".into()])
        .with_manifest(&manifest(), files())
        .expect("the manifest is valid");
    assert!(runtime.register(app));
    runtime
}

struct Server {
    handle: elpian_host::httpcore::ServerHandle,
    runtime: Arc<AppRuntime>,
}

fn serve(runtime: Arc<AppRuntime>) -> Server {
    let tokens = StaticTokens::new();
    tokens.add(
        "alice-token",
        Identity {
            id: "alice".into(),
            roles: vec![],
        },
    );
    let gateway = Gateway::new(Arc::clone(&runtime)).with_auth(tokens);
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let handle = elpian_host::httpcore::serve(listener, 2, gateway_handler(Arc::new(gateway)));
    Server { handle, runtime }
}

/// `(status, head, body)`
fn post(server: &Server, path: &str, body: &Value, token: Option<&str>) -> (u16, String, String) {
    let body = body.to_string();
    let mut stream = TcpStream::connect(server.handle.addr).unwrap();
    let auth = token
        .map(|t| format!("Authorization: Bearer {t}\r\n"))
        .unwrap_or_default();
    let head = format!(
        "POST {path} HTTP/1.1\r\nHost: localhost\r\n{auth}Content-Length: {}\r\nConnection: close\r\n\r\n",
        body.len()
    );
    stream.write_all(head.as_bytes()).unwrap();
    stream.write_all(body.as_bytes()).unwrap();
    let mut raw = Vec::new();
    stream.read_to_end(&mut raw).unwrap();
    let text = String::from_utf8_lossy(&raw).to_string();
    let (head, body) = text.split_once("\r\n\r\n").unwrap();
    let status = head.split_whitespace().nth(1).unwrap().parse().unwrap();
    (status, head.to_string(), body.to_string())
}

fn lines(body: &str) -> Vec<Value> {
    body.lines()
        .filter(|l| !l.trim().is_empty())
        .map(|l| serde_json::from_str(l).unwrap_or_else(|e| panic!("not JSON ({e}): {l}")))
        .collect()
}

fn kind(frame: &Value) -> String {
    frame["type"]
        .as_str()
        .map(str::to_string)
        .unwrap_or_else(|| {
            [
                "createSurface",
                "updateComponents",
                "updateDataModel",
                "deleteSurface",
            ]
            .iter()
            .find(|k| frame.get(**k).is_some())
            .map(|k| k.to_string())
            .unwrap_or_else(|| "?".into())
        })
}

#[test]
fn a_turn_streams_conversation_ui_text_and_done_in_order() {
    let server = serve(runtime());
    let (status, head, body) = post(
        &server,
        "/apps/shop/agent/assistant",
        &json!({ "message": "Green tea", "capabilities": { "supportedCatalogIds": [BASIC_CATALOG_ID] } }),
        Some("alice-token"),
    );
    assert_eq!(status, 200, "{body}");
    assert!(head.contains("application/x-ndjson"), "{head}");
    let frames = lines(&body);
    let kinds: Vec<String> = frames.iter().map(kind).collect();
    assert_eq!(
        kinds,
        vec![
            "conversation",
            "status",
            "text",
            "status",
            "status",
            "status",
            "createSurface",
            "updateComponents",
            "updateDataModel",
            "status",
            "text",
            "done"
        ],
        "{body}"
    );
    let id = frames[0]["conversationId"].as_str().unwrap().to_string();
    assert!(!id.is_empty());
    assert_eq!(frames[2]["text"], json!("Let me check who you are."));
    assert_eq!(
        frames[3],
        json!({ "type": "status", "state": "tool", "tool": "fn_whoami" })
    );
    assert_eq!(frames[6]["version"], json!("v0.9.1"));
    assert_eq!(
        frames[8]["updateDataModel"]["value"]["title"],
        json!("Green tea")
    );
    assert_eq!(frames[10]["text"], json!("Here you go."));
    assert_eq!(
        frames[11],
        json!({ "type": "done", "stopReason": "end_turn" })
    );

    // The tool ran through the invoke path, as the caller.
    let conversation = server
        .runtime
        .conversations()
        .get("shop", "assistant", "alice", &id)
        .expect("kept under alice's identity");
    let conversation = conversation.lock().unwrap();
    let result = &conversation.messages[2]["content"][0];
    assert_eq!(result["type"], json!("tool_result"));
    let user: Value = serde_json::from_str(result["content"].as_str().unwrap()).unwrap();
    assert_eq!(user["id"], json!("alice"));
    drop(conversation);
    // One agent request and one function invocation, both metered.
    assert_eq!(server.runtime.meters("shop").invocations, 2);

    // An action continues the same conversation.
    let (status, _, body) = post(
        &server,
        "/apps/shop/agent/assistant",
        &json!({
            "conversationId": id,
            "action": { "name": "order", "surfaceId": "main", "sourceComponentId": "buy",
                        "timestamp": "2026-10-09T12:00:00Z", "context": { "item": "tea" } },
            "dataModel": { "surfaces": { "main": { "title": "Green tea" } } }
        }),
        Some("alice-token"),
    );
    assert_eq!(status, 200);
    let frames = lines(&body);
    assert_eq!(frames[0]["conversationId"], json!(id));
    assert!(
        frames.iter().any(|f| f["text"] == json!("Ordered tea.")),
        "{body}"
    );
    assert_eq!(frames.last().unwrap()["type"], json!("done"));

    // Another caller cannot reach alice's conversation by its id: theirs is new.
    let (_, _, body) = post(
        &server,
        "/apps/shop/agent/assistant",
        &json!({ "conversationId": id, "message": "hello" }),
        None,
    );
    let frames = lines(&body);
    let anonymous = server
        .runtime
        .conversations()
        .get("shop", "assistant", "", &id)
        .unwrap();
    assert_eq!(
        anonymous.lock().unwrap().messages[0]["content"][0]["text"],
        json!("hello")
    );
    assert_eq!(frames.last().unwrap()["type"], json!("done"));
    server.handle.stop();
}

#[test]
fn the_manifest_lists_agents_by_name_and_description_only() {
    let runtime = runtime();
    let manifest = runtime.manifest("shop").unwrap();
    assert_eq!(
        manifest["agents"],
        json!([{ "name": "assistant", "description": "Shop assistant" }])
    );
    let text = manifest.to_string();
    for secret in [
        "Sell tea",
        "browse",
        "ANTHROPIC_API_KEY",
        "scripted",
        "whoami\"]",
    ] {
        assert!(!text.contains(secret), "{secret} leaked into {text}");
    }
}

#[test]
fn refusals_before_the_stream_are_http_statuses() {
    let server = serve(runtime());
    let path = "/apps/shop/agent/assistant";
    assert_eq!(
        post(
            &server,
            "/apps/nope/agent/assistant",
            &json!({ "message": "x" }),
            None
        )
        .0,
        404
    );
    assert_eq!(
        post(
            &server,
            "/apps/shop/agent/nobody",
            &json!({ "message": "x" }),
            None
        )
        .0,
        404
    );
    assert_eq!(post(&server, path, &json!({}), None).0, 400);
    assert_eq!(
        post(
            &server,
            path,
            &json!({ "message": "x", "conversationId": "../x" }),
            None
        )
        .0,
        400
    );

    server.runtime.quotas().suspend("shop");
    assert_eq!(post(&server, path, &json!({ "message": "x" }), None).0, 429);
    server.runtime.quotas().resume("shop");
    server.handle.stop();
}

#[test]
fn a_real_provider_without_a_key_is_unavailable_and_with_one_is_reached() {
    let runtime = runtime();
    runtime.set_agent_settings(AgentSettings {
        provider_override: Some("anthropic".into()),
        ..Default::default()
    });
    let server = serve(runtime);
    let (status, _, body) = post(
        &server,
        "/apps/shop/agent/assistant",
        &json!({ "message": "x" }),
        None,
    );
    assert_eq!(status, 503);
    assert!(
        !body.contains("ANTHROPIC_API_KEY"),
        "the operator detail stays in the log"
    );

    // With a key held for the app the request is admitted; the provider is
    // then reached over HTTP — point it at a closed local port so the test
    // never leaves the machine, and expect an in-band error frame.
    server
        .runtime
        .secrets()
        .put("shop", "ANTHROPIC_API_KEY", "sk-test".into());
    let mut manifest = manifest();
    manifest["providers"] = json!({ "anthropic": { "baseUrl": "http://127.0.0.1:9" } });
    let app = AppDefinition::new("shop")
        .with_capabilities(vec![Capability::State])
        .with_function("whoami", FunctionKind::Action, module(vec![]))
        .with_secrets(vec!["ANTHROPIC_API_KEY".into()])
        .with_manifest(&manifest, files())
        .unwrap();
    server.runtime.register(app);
    let (status, _, body) = post(
        &server,
        "/apps/shop/agent/assistant",
        &json!({ "message": "x" }),
        None,
    );
    assert_eq!(status, 200);
    let frames = lines(&body);
    assert_eq!(
        frames.last().unwrap(),
        &json!({ "type": "done", "stopReason": "error" })
    );
    assert!(frames.iter().any(|f| f["type"] == json!("error")));
    server.handle.stop();
}

#[test]
fn manifest_errors_refuse_the_app() {
    let base = || {
        AppDefinition::new("shop")
            .with_function("whoami", FunctionKind::Action, module(vec![]))
            .with_secrets(vec!["ANTHROPIC_API_KEY".into()])
    };
    let mut bad_tool = manifest();
    bad_tool["agents"][0]["tools"] = json!(["deleteEverything"]);
    let err = base().with_manifest(&bad_tool, files()).unwrap_err();
    assert!(err.contains("unknown tool \"deleteEverything\""), "{err}");

    let mut bad_skill = manifest();
    bad_skill["agents"][0]["skills"] = json!(["checkout"]);
    let err = base().with_manifest(&bad_skill, files()).unwrap_err();
    assert!(err.contains("unknown skill \"checkout\""), "{err}");

    let mut no_instructions = files();
    no_instructions.remove("agents/assistant.md");
    let err = base()
        .with_manifest(&manifest(), no_instructions)
        .unwrap_err();
    assert!(err.contains("agents/assistant.md"), "{err}");
}
