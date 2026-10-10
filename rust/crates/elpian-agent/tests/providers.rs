//! Providers: SSE parsing against recorded streams, the request body the
//! Anthropic provider sends, and the real HTTP path (headers, retries) against
//! a local mock server. Nothing here calls a real provider.

use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpListener;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use elpian_agent::provider::anthropic::{
    echo_content, parse_stream, request_body, request_headers, AnthropicProvider,
};
use elpian_agent::provider::openai::{self, OpenAiProvider};
use elpian_agent::provider::{
    ModelRequest, Progress, Provider, ProviderError, RetryPolicy, ToolDef,
};
use serde_json::{json, Value};

fn fixture(path: &str) -> String {
    let full = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures")
        .join(path);
    std::fs::read_to_string(&full).unwrap_or_else(|e| panic!("{}: {e}", full.display()))
}

fn parse(path: &str) -> Result<elpian_agent::provider::ModelResponse, ProviderError> {
    let raw = fixture(path);
    let mut reader = BufReader::new(raw.as_bytes());
    parse_stream(&mut reader, &mut |_| {}).map_err(|f| f.error)
}

// ---- SSE parsing -----------------------------------------------------------

#[test]
fn text_stream() {
    let r = parse("anthropic/text.sse").unwrap();
    assert_eq!(r.stop_reason, "end_turn");
    assert_eq!(r.model, "claude-opus-5-5");
    assert_eq!(
        r.content,
        vec![json!({ "type": "text", "text": "Hello, world." })]
    );
    assert_eq!(
        r.usage["output_tokens"],
        json!(9),
        "message_delta usage merges in"
    );
    assert_eq!(r.usage["cache_read_input_tokens"], json!(1100));
    assert!(r.invalid_inputs.is_empty());
}

#[test]
fn tool_use_with_input_json_deltas_and_thinking() {
    let mut tools = Vec::new();
    let raw = fixture("anthropic/tool_use.sse");
    let r = parse_stream(&mut BufReader::new(raw.as_bytes()), &mut |p| {
        let Progress::ToolUse(name) = p;
        tools.push(name);
    })
    .unwrap();
    assert_eq!(r.stop_reason, "tool_use");
    assert_eq!(tools, vec!["fn_listProducts", "load_skill"]);
    assert_eq!(r.content.len(), 4);
    // The thinking block is kept whole — signature included — so it can be
    // echoed back unchanged.
    assert_eq!(
        r.content[0],
        json!({ "type": "thinking", "thinking": "", "signature": "EqQBCkYIARgCIkB2c2lnbmF0dXJl" })
    );
    assert_eq!(r.content[1]["text"], json!("Let me look that up."));
    assert_eq!(
        r.content[2],
        json!({ "type": "tool_use", "id": "toolu_01A", "name": "fn_listProducts",
                "input": { "category": "tea", "limit": 3 } })
    );
    assert_eq!(r.content[3]["input"], json!({ "name": "browse" }));
    assert_eq!(
        echo_content(&r.content),
        r.content,
        "no fallback: echoed unchanged"
    );
}

#[test]
fn refusal_is_reported_by_stop_reason() {
    let r = parse("anthropic/refusal.sse").unwrap();
    assert_eq!(r.stop_reason, "refusal");
    assert_eq!(r.stop_details["category"], json!("cyber"));
}

#[test]
fn max_tokens_mid_tool_input_marks_the_input_invalid() {
    let r = parse("anthropic/max_tokens.sse").unwrap();
    assert_eq!(r.stop_reason, "max_tokens");
    assert_eq!(r.invalid_inputs.len(), 1);
    assert_eq!(r.invalid_inputs[0].0, "toolu_04");
    assert!(r.invalid_inputs[0].1.contains("createSur"));
    assert_eq!(r.content[0]["input"], json!({}));
}

#[test]
fn malformed_tool_json_is_caught_by_the_strict_parse() {
    let r = parse("anthropic/invalid_tool_json.sse").unwrap();
    assert_eq!(r.stop_reason, "tool_use");
    assert_eq!(r.invalid_inputs.len(), 1);
    assert_eq!(r.invalid_inputs[0].0, "toolu_07");
}

#[test]
fn an_error_event_fails_the_stream_before_any_content() {
    let raw = fixture("anthropic/error_overloaded.sse");
    let failure = parse_stream(&mut BufReader::new(raw.as_bytes()), &mut |_| {}).unwrap_err();
    assert!(!failure.content_started, "retryable: nothing was consumed");
    assert_eq!(
        failure.error,
        ProviderError::Stream {
            kind: "overloaded_error".into(),
            message: "Overloaded".into()
        }
    );
    assert!(failure.error.retryable());
}

#[test]
fn a_truncated_stream_is_an_error() {
    let raw = fixture("anthropic/text.sse");
    let cut = &raw[..raw.find("event: message_delta").unwrap()];
    let failure = parse_stream(&mut BufReader::new(cut.as_bytes()), &mut |_| {}).unwrap_err();
    assert!(failure.content_started);
    assert!(
        matches!(failure.error, ProviderError::Stream { ref kind, .. } if kind == "incomplete")
    );
}

#[test]
fn a_mid_stream_fallback_is_echoed_by_the_rules() {
    let r = parse("anthropic/fallback_mid_stream.sse").unwrap();
    assert_eq!(r.stop_reason, "end_turn");
    assert_eq!(r.content.len(), 5);
    let echoed = echo_content(&r.content);
    let kinds: Vec<&str> = echoed.iter().map(|b| b["type"].as_str().unwrap()).collect();
    // Thinking and tool_use before the boundary are dropped; text and
    // everything after it stay.
    assert_eq!(kinds, vec!["text", "fallback", "text"]);
}

#[test]
fn openai_stream_becomes_anthropic_blocks() {
    let raw = fixture("openai/tool_calls.sse");
    let r = openai::parse_stream(&mut BufReader::new(raw.as_bytes()), &mut |_| {}).unwrap();
    assert_eq!(r.stop_reason, "tool_use");
    assert_eq!(
        r.content[0],
        json!({ "type": "text", "text": "Checking stock." })
    );
    assert_eq!(
        r.content[1],
        json!({ "type": "tool_use", "id": "call_a", "name": "fn_listProducts", "input": { "limit": 2 } })
    );
}

#[test]
fn openai_history_translation() {
    let history = vec![
        json!({ "role": "user", "content": [{ "type": "text", "text": "hi" }] }),
        json!({ "role": "assistant", "content": [
            { "type": "thinking", "thinking": "", "signature": "x" },
            { "type": "text", "text": "ok" },
            { "type": "tool_use", "id": "t1", "name": "fn_a", "input": { "x": 1 } }
        ] }),
        json!({ "role": "user", "content": [
            { "type": "tool_result", "tool_use_id": "t1", "content": "{\"y\":2}" }
        ] }),
    ];
    let out = openai::to_chat_messages("sys", &history);
    assert_eq!(out[0], json!({ "role": "system", "content": "sys" }));
    assert_eq!(out[1], json!({ "role": "user", "content": "hi" }));
    assert_eq!(
        out[2]["tool_calls"][0]["function"]["arguments"],
        json!("{\"x\":1}")
    );
    assert_eq!(
        out[3],
        json!({ "role": "tool", "tool_call_id": "t1", "content": "{\"y\":2}" })
    );
}

// ---- The request -------------------------------------------------------------

fn tools() -> Vec<ToolDef> {
    vec![ToolDef {
        name: "a2ui_send".into(),
        description: "send".into(),
        input_schema: json!({ "type": "object" }),
    }]
}

fn request<'a>(model: &'a str, tools: &'a [ToolDef], messages: &'a [Value]) -> ModelRequest<'a> {
    ModelRequest {
        model,
        system: "You are a test.",
        tools,
        messages,
        max_tokens: 64000,
        effort: "medium",
    }
}

#[test]
fn the_request_body_follows_the_api_rules() {
    let tools = tools();
    let messages = vec![json!({ "role": "user", "content": [{ "type": "text", "text": "hi" }] })];
    let body = request_body(&request("claude-opus-5-5", &tools, &messages), true);

    assert_eq!(body["model"], json!("claude-opus-5-5"));
    assert_eq!(body["max_tokens"], json!(64000));
    assert_eq!(body["stream"], json!(true));
    assert_eq!(body["output_config"], json!({ "effort": "medium" }));
    assert_eq!(body["cache_control"], json!({ "type": "ephemeral" }));
    assert_eq!(body["system"], json!("You are a test."));
    assert_eq!(body["fallbacks"], json!("default"));
    // Never sent: thinking (always adaptive; disabled/budget_tokens 400) and
    // tool_choice (forced any/tool 400s; auto is the default).
    assert!(body.get("thinking").is_none());
    assert!(body.get("tool_choice").is_none());
    assert!(body.get("temperature").is_none());
    assert_eq!(body["tools"][0]["eager_input_streaming"], json!(true));
    assert_eq!(
        body["tools"][0]["input_schema"],
        json!({ "type": "object" })
    );

    let headers = request_headers("sk-test", "claude-opus-5-5", true);
    let get = |name: &str| {
        headers
            .iter()
            .find(|(n, _)| n == name)
            .map(|(_, v)| v.as_str())
    };
    assert_eq!(get("x-api-key"), Some("sk-test"));
    assert_eq!(get("anthropic-version"), Some("2023-06-01"));
    assert_eq!(get("content-type"), Some("application/json"));
    assert_eq!(
        get("anthropic-beta"),
        Some("server-side-fallback-2026-07-01")
    );
}

#[test]
fn fallbacks_only_for_the_right_models_on_the_claude_api() {
    let tools = tools();
    let messages = vec![];
    for model in [
        "claude-opus-5-5",
        "claude-opus-5",
        "claude-fable-5-1",
        "claude-sonnet-5-5",
    ] {
        let body = request_body(&request(model, &tools, &messages), true);
        assert_eq!(body["fallbacks"], json!("default"), "{model}");
        assert!(request_headers("k", model, true)
            .iter()
            .any(|(n, _)| n == "anthropic-beta"));
    }
    for model in ["claude-haiku-5-5", "claude-haiku-4-5", "claude-opus-4-8"] {
        let body = request_body(&request(model, &tools, &messages), true);
        assert!(body.get("fallbacks").is_none(), "{model}");
        assert!(!request_headers("k", model, true)
            .iter()
            .any(|(n, _)| n == "anthropic-beta"));
    }
    // Not through a gateway that is not the Claude API.
    let body = request_body(&request("claude-opus-5-5", &tools, &messages), false);
    assert!(body.get("fallbacks").is_none());
    assert!(!request_headers("k", "claude-opus-5-5", false)
        .iter()
        .any(|(n, _)| n == "anthropic-beta"));
}

#[test]
fn the_effort_is_always_explicit() {
    let tools = tools();
    let messages = vec![];
    for effort in ["low", "medium", "high", "xhigh", "max"] {
        let mut r = request("claude-opus-5-5", &tools, &messages);
        r.effort = effort;
        assert_eq!(
            request_body(&r, true)["output_config"]["effort"],
            json!(effort)
        );
    }
}

#[test]
fn no_tools_means_no_tools_key() {
    let none: Vec<ToolDef> = vec![];
    let body = request_body(&request("claude-opus-5-5", &none, &[]), true);
    assert!(body.get("tools").is_none());
}

#[test]
fn the_request_is_byte_stable() {
    let tools = tools();
    let messages = vec![json!({ "role": "user", "content": [{ "type": "text", "text": "hi" }] })];
    let a = request_body(&request("claude-opus-5-5", &tools, &messages), true).to_string();
    let b = request_body(&request("claude-opus-5-5", &tools, &messages), true).to_string();
    assert_eq!(a, b);
}

// ---- The HTTP path, against a local mock -------------------------------------

struct Recorded {
    head: String,
    body: String,
}

/// Serve `responses` one per connection, recording each request.
fn mock(responses: Vec<String>) -> (String, Arc<Mutex<Vec<Recorded>>>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let addr = listener.local_addr().unwrap();
    let seen = Arc::new(Mutex::new(Vec::new()));
    let log = Arc::clone(&seen);
    std::thread::spawn(move || {
        for response in responses {
            let Ok((stream, _)) = listener.accept() else {
                return;
            };
            let mut reader = BufReader::new(stream.try_clone().unwrap());
            let mut head = String::new();
            loop {
                let mut line = String::new();
                if reader.read_line(&mut line).unwrap_or(0) == 0 {
                    break;
                }
                if line == "\r\n" {
                    break;
                }
                head.push_str(&line);
            }
            let length = head
                .lines()
                .find_map(|l| {
                    let (n, v) = l.split_once(':')?;
                    n.eq_ignore_ascii_case("content-length")
                        .then(|| v.trim().parse::<usize>().ok())?
                })
                .unwrap_or(0);
            let mut body = vec![0; length];
            reader.read_exact(&mut body).unwrap();
            log.lock().unwrap().push(Recorded {
                head,
                body: String::from_utf8_lossy(&body).into_owned(),
            });
            let mut stream = stream;
            stream.write_all(response.as_bytes()).unwrap();
            stream.flush().unwrap();
        }
    });
    (format!("http://{addr}"), seen)
}

fn http(status: &str, extra: &str, content_type: &str, body: &str) -> String {
    format!(
        "HTTP/1.1 {status}\r\ncontent-type: {content_type}\r\ncontent-length: {}\r\n{extra}connection: close\r\n\r\n{body}",
        body.len()
    )
}

fn fast_retries() -> RetryPolicy {
    RetryPolicy {
        max_retries: 2,
        base_delay: Duration::from_millis(1),
        max_delay: Duration::from_millis(5),
    }
}

#[test]
fn the_live_path_retries_overload_then_streams() {
    let (base, seen) = mock(vec![
        http(
            "529 Overloaded",
            "retry-after: 0\r\n",
            "application/json",
            r#"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#,
        ),
        http(
            "200 OK",
            "",
            "text/event-stream",
            &fixture("anthropic/error_overloaded.sse"),
        ),
        http(
            "200 OK",
            "",
            "text/event-stream",
            &fixture("anthropic/tool_use.sse"),
        ),
    ]);
    let mut provider = AnthropicProvider::new("sk-test-key", base);
    provider.retry = fast_retries();
    let tools = tools();
    let messages = vec![json!({ "role": "user", "content": [{ "type": "text", "text": "hi" }] })];
    let response = provider
        .complete(&request("claude-opus-5-5", &tools, &messages), &mut |_| {})
        .expect("the third attempt succeeds");
    assert_eq!(response.stop_reason, "tool_use");

    let seen = seen.lock().unwrap();
    assert_eq!(
        seen.len(),
        3,
        "a 529 and a pre-content overload are both retried"
    );
    let head = seen[0].head.to_ascii_lowercase();
    assert!(head.starts_with("post /v1/messages "), "{head}");
    assert!(head.contains("x-api-key: sk-test-key"));
    assert!(head.contains("anthropic-version: 2023-06-01"));
    assert!(head.contains("content-type: application/json"));
    // A local base URL is not the Claude API: no fallback beta.
    assert!(!head.contains("anthropic-beta"));
    let body: Value = serde_json::from_str(&seen[0].body).unwrap();
    assert_eq!(body["stream"], json!(true));
    assert!(body.get("fallbacks").is_none());
    assert_eq!(
        seen[0].body, seen[2].body,
        "every retry sends the same bytes"
    );
}

#[test]
fn the_live_path_gives_up_after_two_retries_and_does_not_retry_a_400() {
    let overloaded = http(
        "503 Service Unavailable",
        "",
        "application/json",
        r#"{"error":{"message":"busy"}}"#,
    );
    let (base, seen) = mock(vec![overloaded.clone(), overloaded.clone(), overloaded]);
    let mut provider = AnthropicProvider::new("k", base);
    provider.retry = fast_retries();
    let err = provider
        .complete(&request("claude-opus-5-5", &tools(), &[]), &mut |_| {})
        .unwrap_err();
    assert_eq!(
        err,
        ProviderError::Http {
            status: 503,
            message: "busy".into()
        }
    );
    assert_eq!(seen.lock().unwrap().len(), 3, "one try and two retries");

    let (base, seen) = mock(vec![http(
        "400 Bad Request",
        "",
        "application/json",
        r#"{"type":"error","error":{"type":"invalid_request_error","message":"thinking.type: disabled is not supported"}}"#,
    )]);
    let mut provider = AnthropicProvider::new("k", base);
    provider.retry = fast_retries();
    let err = provider
        .complete(&request("claude-opus-5-5", &tools(), &[]), &mut |_| {})
        .unwrap_err();
    assert!(matches!(err, ProviderError::Http { status: 400, .. }));
    assert_eq!(seen.lock().unwrap().len(), 1);
}

#[test]
fn the_openai_live_path() {
    let (base, seen) = mock(vec![http(
        "200 OK",
        "",
        "text/event-stream",
        &fixture("openai/tool_calls.sse"),
    )]);
    let provider = OpenAiProvider::new("sk-oai", format!("{base}/v1"));
    let response = provider
        .complete(&request("gpt-test", &tools(), &[]), &mut |_| {})
        .unwrap();
    assert_eq!(response.stop_reason, "tool_use");
    let seen = seen.lock().unwrap();
    let head = seen[0].head.to_ascii_lowercase();
    assert!(head.starts_with("post /v1/chat/completions "));
    assert!(head.contains("authorization: bearer sk-oai"));
    let body: Value = serde_json::from_str(&seen[0].body).unwrap();
    assert_eq!(body["tools"][0]["type"], json!("function"));
    assert_eq!(body["messages"][0]["role"], json!("system"));
}
