//! The tool loop, against a provider that plays canned responses and records
//! every request it was sent.

use std::collections::BTreeMap;
use std::sync::Mutex;

use elpian_agent::a2ui::BASIC_CATALOG_ID;
use elpian_agent::agent::{FunctionInfo, FunctionRunner, TurnContext, TurnInput};
use elpian_agent::provider::{ModelRequest, ModelResponse, Progress, Provider, ProviderError};
use elpian_agent::{manifest, run_turn, AppAgents, Conversation};
use serde_json::{json, Value};

struct Canned {
    responses: Mutex<Vec<Result<ModelResponse, ProviderError>>>,
    requests: Mutex<Vec<Value>>,
}

impl Canned {
    fn new(responses: Vec<Result<ModelResponse, ProviderError>>) -> Canned {
        Canned {
            responses: Mutex::new(responses.into_iter().rev().collect()),
            requests: Mutex::new(Vec::new()),
        }
    }
}

impl Provider for Canned {
    fn complete(
        &self,
        request: &ModelRequest<'_>,
        _: &mut dyn FnMut(Progress),
    ) -> Result<ModelResponse, ProviderError> {
        self.requests.lock().unwrap().push(json!({
            "model": request.model,
            "effort": request.effort,
            "max_tokens": request.max_tokens,
            "tools": request.tools.iter().map(|t| t.name.clone()).collect::<Vec<_>>(),
            "messages": request.messages,
            "system": request.system,
        }));
        self.responses
            .lock()
            .unwrap()
            .pop()
            .unwrap_or_else(|| Ok(reply(vec![], "end_turn")))
    }
}

fn reply(content: Vec<Value>, stop: &str) -> ModelResponse {
    ModelResponse {
        content,
        stop_reason: stop.into(),
        model: "claude-opus-5-5".into(),
        usage: json!({ "input_tokens": 10, "output_tokens": 5 }),
        ..Default::default()
    }
}

fn tool(id: &str, name: &str, input: Value) -> Value {
    json!({ "type": "tool_use", "id": id, "name": name, "input": input })
}

struct Functions {
    calls: Mutex<Vec<(String, Value)>>,
}

impl FunctionRunner for Functions {
    fn run(&self, function: &str, args: &Value) -> Result<Value, String> {
        self.calls
            .lock()
            .unwrap()
            .push((function.into(), args.clone()));
        match function {
            "listProducts" => Ok(json!([{ "id": "p1", "name": "Tea" }])),
            _ => Err("the function failed".into()),
        }
    }
}

fn app() -> AppAgents {
    let manifest = json!({
        "id": "shop",
        "secrets": ["ANTHROPIC_API_KEY"],
        "functions": [
            { "name": "listProducts", "kind": "action", "description": "List products.",
              "params": { "type": "object", "properties": { "limit": { "type": "integer" } },
                          "additionalProperties": false } }
        ],
        "agents": [{
            "name": "assistant",
            "description": "Shop assistant",
            "instructions": "agents/assistant.md",
            "skills": ["browse"],
            "tools": ["listProducts"],
            "effort": "high",
            "maxTurns": 4
        }]
    });
    let mut files = BTreeMap::new();
    files.insert("agents/assistant.md".to_string(), b"Be helpful.".to_vec());
    files.insert(
        "agents/skills/browse/SKILL.md".to_string(),
        b"---\nname: browse\ndescription: Show the catalogue.\n---\nUse a List.\n".to_vec(),
    );
    files.insert(
        "agents/skills/browse/examples/list.json".to_string(),
        br#"[{"version":"v0.9.1","deleteSurface":{"surfaceId":"x"}}]"#.to_vec(),
    );
    let functions = vec!["listProducts".to_string()];
    let config = manifest::parse(&manifest, &functions, &|p| files.contains_key(p)).unwrap();
    let infos = vec![FunctionInfo {
        name: "listProducts".into(),
        kind: "action".into(),
        description: Some("List products.".into()),
        params: manifest["functions"][0]["params"].clone().into(),
    }];
    AppAgents::build(config, files, &infos).unwrap()
}

fn run(
    provider: &Canned,
    conversation: &mut Conversation,
    input: TurnInput,
) -> (Vec<Value>, elpian_agent::TurnSummary, Vec<(String, Value)>) {
    let app = app();
    let agent = app.get("assistant").unwrap();
    let functions = Functions {
        calls: Mutex::new(Vec::new()),
    };
    let ctx = TurnContext {
        agent: &agent,
        provider,
        functions: &functions,
        log: &|_| {},
    };
    let mut frames = Vec::new();
    let summary = run_turn(&ctx, conversation, input, &mut |f| {
        frames.push(f.clone());
        true
    });
    let calls = functions.calls.into_inner().unwrap();
    (frames, summary, calls)
}

fn say(text: &str) -> TurnInput {
    TurnInput {
        message: Some(text.into()),
        ..Default::default()
    }
}

fn ui() -> Value {
    json!({ "messages": [
        { "createSurface": { "surfaceId": "main", "catalogId": BASIC_CATALOG_ID, "sendDataModel": true } },
        { "version": "v0.9.1", "updateComponents": { "surfaceId": "main", "components": [
            { "id": "root", "component": "Text", "text": { "path": "/title" } } ] } },
        { "version": "v0.9.1", "updateDataModel": { "surfaceId": "main", "value": { "title": "Tea" } } }
    ] })
}

#[test]
fn the_agent_is_built_from_the_manifest() {
    let app = app();
    let agent = app.get("assistant").unwrap();
    assert_eq!(
        agent.tool_names(),
        vec!["a2ui_send", "fn_listProducts", "load_skill"]
    );
    assert_eq!(agent.model.as_deref(), Some("claude-opus-5-5"));
    assert!(agent
        .system_prompt
        .contains("<instructions>\nBe helpful.\n</instructions>"));
    assert!(agent
        .system_prompt
        .contains("- browse: Show the catalogue."));
    assert!(agent.system_prompt.contains(BASIC_CATALOG_ID));
    assert!(
        agent
            .system_prompt
            .contains("For 'Text', you MUST provide 'text'"),
        "rules.txt"
    );
    // Byte-stable: building twice gives the same prompt.
    assert_eq!(
        agent.system_prompt,
        self::app().get("assistant").unwrap().system_prompt
    );
}

#[test]
fn a_full_turn_text_ui_tools_and_done() {
    let thinking = json!({ "type": "thinking", "thinking": "", "signature": "sig" });
    let provider = Canned::new(vec![
        Ok(reply(
            vec![
                thinking.clone(),
                json!({ "type": "text", "text": "Looking." }),
                tool("t1", "fn_listProducts", json!({ "limit": 2 })),
                tool("t2", "load_skill", json!({ "name": "browse" })),
            ],
            "tool_use",
        )),
        Ok(reply(vec![tool("t3", "a2ui_send", ui())], "tool_use")),
        Ok(reply(
            vec![json!({ "type": "text", "text": "Here is the tea." })],
            "end_turn",
        )),
    ]);
    let mut conversation = Conversation::default();
    let (frames, summary, calls) = run(&provider, &mut conversation, say("show tea"));

    assert_eq!(summary.stop_reason, "end_turn");
    assert_eq!(summary.model_calls, 3);
    assert_eq!(
        calls,
        vec![("listProducts".to_string(), json!({ "limit": 2 }))]
    );

    let kinds: Vec<String> = frames
        .iter()
        .map(|f| match f["type"].as_str() {
            Some(t) => t.to_string(),
            None => ["createSurface", "updateComponents", "updateDataModel"]
                .iter()
                .find(|k| f.get(**k).is_some())
                .unwrap()
                .to_string(),
        })
        .collect();
    assert_eq!(
        kinds,
        vec![
            "status",
            "text",
            "status",
            "status",
            "status",
            "status",
            "createSurface",
            "updateComponents",
            "updateDataModel",
            "status",
            "text",
            "done"
        ]
    );
    assert_eq!(frames[6]["version"], json!("v0.9.1"), "version filled in");
    assert_eq!(
        frames.last().unwrap(),
        &json!({ "type": "done", "stopReason": "end_turn" })
    );

    // History: append-only, thinking echoed unchanged, all results in one message.
    let requests = provider.requests.lock().unwrap();
    assert_eq!(requests[0]["effort"], json!("high"));
    let second = requests[1]["messages"].as_array().unwrap();
    assert_eq!(second[1]["content"][0], thinking);
    let results = second[2]["content"].as_array().unwrap();
    assert_eq!(results.len(), 2, "both tool results in one user message");
    assert_eq!(results[0]["tool_use_id"], json!("t1"));
    assert!(results[0].get("is_error").is_none());
    assert!(results[1]["content"]
        .as_str()
        .unwrap()
        .contains("Use a List."));
    assert!(
        results[1]["content"]
            .as_str()
            .unwrap()
            .contains("deleteSurface"),
        "skill examples"
    );
    // Earlier requests are prefixes of later ones.
    let third = requests[2]["messages"].as_array().unwrap();
    assert_eq!(&third[..second.len()], &second[..]);
    assert!(conversation.surfaces.contains("main"));
    assert_eq!(
        conversation.surfaces.get("main").unwrap().data_model,
        json!({ "title": "Tea" })
    );
}

#[test]
fn invalid_ui_goes_back_to_the_model_and_is_not_shown() {
    let provider = Canned::new(vec![
        Ok(reply(
            vec![tool(
                "t1",
                "a2ui_send",
                json!({ "messages": [
                { "createSurface": { "surfaceId": "s", "catalogId": BASIC_CATALOG_ID } },
                { "updateComponents": { "surfaceId": "s", "components": [
                    { "id": "root", "component": "Marquee" } ] } }
            ] }),
            )],
            "tool_use",
        )),
        Ok(reply(
            vec![json!({ "type": "text", "text": "fixed" })],
            "end_turn",
        )),
    ]);
    let mut conversation = Conversation::default();
    let (frames, _, _) = run(&provider, &mut conversation, say("go"));
    assert!(frames.iter().any(|f| f.get("createSurface").is_some()));
    assert!(!frames.iter().any(|f| f.get("updateComponents").is_some()));
    let requests = provider.requests.lock().unwrap();
    let result = &requests[1]["messages"][2]["content"][0];
    assert_eq!(result["is_error"], json!(true));
    let report: Value = serde_json::from_str(result["content"].as_str().unwrap()).unwrap();
    assert_eq!(report["errors"][0]["code"], json!("VALIDATION_FAILED"));
    assert_eq!(report["errors"][0]["surfaceId"], json!("s"));
    assert_eq!(
        report["errors"][0]["path"],
        json!("/components/0/component")
    );
}

#[test]
fn tool_input_is_validated_before_anything_runs() {
    let provider = Canned::new(vec![
        Ok(reply(
            vec![tool("t1", "fn_listProducts", json!({ "limit": "many" }))],
            "tool_use",
        )),
        Ok(ModelResponse {
            invalid_inputs: vec![("t2".into(), "{\"limit\": 2".into())],
            ..reply(vec![tool("t2", "fn_listProducts", json!({}))], "tool_use")
        }),
        Ok(reply(vec![], "end_turn")),
    ]);
    let mut conversation = Conversation::default();
    let (_, _, calls) = run(&provider, &mut conversation, say("go"));
    assert!(calls.is_empty(), "neither call ran");
    let requests = provider.requests.lock().unwrap();
    let first = &requests[1]["messages"][2]["content"][0];
    assert_eq!(first["is_error"], json!(true));
    assert!(first["content"].as_str().unwrap().contains("invalid input"));
    let second = &requests[2]["messages"][4]["content"][0];
    assert_eq!(second["is_error"], json!(true));
    assert!(second["content"].as_str().unwrap().contains("INVALID_JSON"));
}

#[test]
fn a_refusal_is_an_error_frame_and_the_partial_is_discarded() {
    let provider = Canned::new(vec![Ok(ModelResponse {
        stop_details: json!({ "type": "refusal", "category": "cyber" }),
        ..reply(
            vec![json!({ "type": "text", "text": "partial" })],
            "refusal",
        )
    })]);
    let mut conversation = Conversation::default();
    let (frames, summary, _) = run(&provider, &mut conversation, say("go"));
    assert_eq!(summary.stop_reason, "refusal");
    assert!(
        !frames.iter().any(|f| f["type"] == json!("text")),
        "partial output never shown"
    );
    assert_eq!(frames[frames.len() - 2]["type"], json!("error"));
    assert_eq!(frames.last().unwrap()["stopReason"], json!("refusal"));
    assert_eq!(
        conversation.messages.len(),
        1,
        "only the user's turn is kept"
    );
}

#[test]
fn max_tokens_is_reported_and_the_cut_off_call_is_answered_next_turn() {
    let provider = Canned::new(vec![
        Ok(ModelResponse {
            invalid_inputs: vec![("t1".into(), "{\"messa".into())],
            ..reply(vec![tool("t1", "a2ui_send", json!({}))], "max_tokens")
        }),
        Ok(reply(
            vec![json!({ "type": "text", "text": "ok" })],
            "end_turn",
        )),
    ]);
    let mut conversation = Conversation::default();
    let (frames, summary, _) = run(&provider, &mut conversation, say("big"));
    assert_eq!(summary.stop_reason, "max_tokens");
    assert_eq!(frames.last().unwrap()["stopReason"], json!("max_tokens"));
    assert_eq!(conversation.pending_tool_uses, vec!["t1".to_string()]);

    let (_, summary, _) = run(&provider, &mut conversation, say("again"));
    assert_eq!(summary.stop_reason, "end_turn");
    let requests = provider.requests.lock().unwrap();
    let next_user = &requests[1]["messages"][2]["content"];
    assert_eq!(next_user[0]["type"], json!("tool_result"));
    assert_eq!(next_user[0]["tool_use_id"], json!("t1"));
    assert_eq!(next_user[0]["is_error"], json!(true));
    assert_eq!(next_user[1], json!({ "type": "text", "text": "again" }));
}

#[test]
fn max_turns_bounds_the_loop() {
    let looping: Vec<_> = (0..10)
        .map(|i| {
            Ok(reply(
                vec![tool(
                    &format!("t{i}"),
                    "load_skill",
                    json!({ "name": "browse" }),
                )],
                "tool_use",
            ))
        })
        .collect();
    let provider = Canned::new(looping);
    let mut conversation = Conversation::default();
    let (frames, summary, _) = run(&provider, &mut conversation, say("loop"));
    assert_eq!(summary.stop_reason, "max_turns");
    assert_eq!(summary.model_calls, 4);
    assert_eq!(frames.last().unwrap()["stopReason"], json!("max_turns"));
}

#[test]
fn a_provider_failure_is_an_error_frame() {
    let provider = Canned::new(vec![Err(ProviderError::Http {
        status: 401,
        message: "invalid x-api-key".into(),
    })]);
    let mut conversation = Conversation::default();
    let (frames, summary, _) = run(&provider, &mut conversation, say("hi"));
    assert_eq!(summary.stop_reason, "error");
    assert!(frames[frames.len() - 2]["message"]
        .as_str()
        .unwrap()
        .contains("401"));
}

#[test]
fn an_action_becomes_the_next_user_turn_with_the_data_model() {
    let provider = Canned::new(vec![
        Ok(reply(vec![tool("t1", "a2ui_send", ui())], "tool_use")),
        Ok(reply(vec![], "end_turn")),
        Ok(reply(
            vec![json!({ "type": "text", "text": "Ordered." })],
            "end_turn",
        )),
    ]);
    let mut conversation = Conversation::default();
    run(&provider, &mut conversation, say("menu"));
    let action = json!({ "name": "order", "surfaceId": "main", "sourceComponentId": "buy",
                         "timestamp": "2026-10-09T10:00:00Z", "context": { "id": "p1" } });
    let input = TurnInput {
        action: Some(action.clone()),
        data_model: Some(
            json!({ "surfaces": { "main": { "title": "Green tea" }, "forged": { "x": 1 } } }),
        ),
        ..Default::default()
    };
    let (_, summary, _) = run(&provider, &mut conversation, input);
    assert_eq!(summary.stop_reason, "end_turn");
    let last_user = conversation
        .messages
        .iter()
        .rev()
        .find(|m| m["role"] == json!("user"))
        .unwrap();
    let turn: Value =
        serde_json::from_str(last_user["content"][0]["text"].as_str().unwrap()).unwrap();
    assert_eq!(turn["a2uiAction"], action);
    assert_eq!(
        turn["dataModel"]["surfaces"]["main"],
        json!({ "title": "Green tea" })
    );
    assert!(
        turn["dataModel"]["surfaces"].get("forged").is_none(),
        "unknown surfaces are ignored"
    );
    assert_eq!(
        conversation.surfaces.get("main").unwrap().data_model,
        json!({ "title": "Green tea" })
    );
}

#[test]
fn a_client_without_the_catalog_gets_no_ui() {
    let provider = Canned::new(vec![
        Ok(reply(vec![tool("t1", "a2ui_send", ui())], "tool_use")),
        Ok(reply(vec![], "end_turn")),
    ]);
    let mut conversation = Conversation::default();
    let input = TurnInput {
        message: Some("hi".into()),
        supported_catalogs: Some(vec!["https://example.com/other".into()]),
        ..Default::default()
    };
    let (frames, _, _) = run(&provider, &mut conversation, input);
    assert!(!frames.iter().any(|f| f.get("createSurface").is_some()));
}

#[test]
fn request_bodies_are_parsed_strictly() {
    assert!(TurnInput::from_body(&json!({})).is_err());
    assert!(TurnInput::from_body(&json!({ "message": "  " })).is_err());
    assert!(TurnInput::from_body(&json!({ "message": 3 })).is_err());
    assert!(TurnInput::from_body(&json!({ "action": { "surfaceId": "x" } })).is_err());
    assert!(TurnInput::from_body(&json!({ "message": "hi", "dataModel": { "x": 1 } })).is_err());
    let ok = TurnInput::from_body(&json!({
        "message": "hi",
        "capabilities": { "supportedCatalogIds": [BASIC_CATALOG_ID] }
    }))
    .unwrap();
    assert_eq!(
        ok.supported_catalogs.unwrap(),
        vec![BASIC_CATALOG_ID.to_string()]
    );
}
