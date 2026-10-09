//! The Anthropic Messages API, over raw HTTP (Rust has no official SDK).
//!
//! `POST {baseUrl}/v1/messages` with `"stream": true`, parsed from SSE:
//! `message_start`, `content_block_start` / `content_block_delta` (`text_delta`,
//! `input_json_delta`, `thinking_delta`, `signature_delta`, `citations_delta`)
//! / `content_block_stop`, `message_delta` (stop reason, usage),
//! `message_stop`, `ping` and `error`.
//!
//! What the request does, and why:
//!
//! * `output_config.effort` is always sent — Claude Opus 5.5 defaults to
//!   `medium`, so leaving it out would silently change with the model.
//! * `thinking` is never sent: Claude Opus 5.5 thinks adaptively and rejects
//!   `disabled` and `budget_tokens` with a 400. Thinking blocks that come back
//!   are kept in the content and echoed back unchanged.
//! * `tool_choice` is omitted (the default is `auto`); forced `any` / `tool`
//!   is a 400 on the current models.
//! * Every tool carries `eager_input_streaming: true`, so the API no longer
//!   validates tool input — the loop parses it strictly and checks it against
//!   the tool's schema before running anything.
//! * On the Claude API, for the models that support it, `fallbacks: "default"`
//!   with `anthropic-beta: server-side-fallback-2026-07-01` lets a refused
//!   request be retried server-side on the recommended model.
//! * A top-level `cache_control` caches the prefix; the system prompt and the
//!   tool list are byte-stable (sorted, no timestamps) so it actually hits.
//! * 408/409/429/5xx and transport failures are retried with backoff
//!   (honouring `retry-after`), at most twice; an `overloaded_error` that
//!   arrives before any content is retried the same way.

use std::io::BufRead;

use serde_json::{json, Map, Value};

use super::http;
use super::sse::{read_events, SseEvent};
use super::{ModelRequest, ModelResponse, Progress, Provider, ProviderError, RetryPolicy};

pub const ANTHROPIC_VERSION: &str = "2023-06-01";
pub const FALLBACK_BETA: &str = "server-side-fallback-2026-07-01";

/// The models server-side refusal fallback (`fallbacks: "default"`) is sent
/// for. Not Haiku: it has no server-side fallback.
pub const FALLBACK_MODELS: [&str; 4] = [
    "claude-opus-5-5",
    "claude-opus-5",
    "claude-fable-5-1",
    "claude-sonnet-5-5",
];

/// The Anthropic provider.
#[derive(Clone)]
pub struct AnthropicProvider {
    pub api_key: String,
    pub base_url: String,
    pub retry: RetryPolicy,
}

impl std::fmt::Debug for AnthropicProvider {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // Never the key.
        f.debug_struct("AnthropicProvider")
            .field("base_url", &self.base_url)
            .finish()
    }
}

impl AnthropicProvider {
    pub fn new(api_key: impl Into<String>, base_url: impl Into<String>) -> Self {
        AnthropicProvider {
            api_key: api_key.into(),
            base_url: base_url.into(),
            retry: RetryPolicy::default(),
        }
    }

    /// Whether this provider talks to the Claude API itself (server-side
    /// fallbacks exist there and not behind arbitrary gateways).
    pub fn is_claude_api(&self) -> bool {
        is_claude_api(&self.base_url)
    }

    fn url(&self) -> String {
        format!("{}/v1/messages", self.base_url.trim_end_matches('/'))
    }
}

pub fn is_claude_api(base_url: &str) -> bool {
    let rest = base_url.strip_prefix("https://").unwrap_or("");
    rest.split(['/', ':']).next() == Some("api.anthropic.com")
}

/// Whether `fallbacks: "default"` is sent for this model.
pub fn uses_fallbacks(model: &str, claude_api: bool) -> bool {
    claude_api && FALLBACK_MODELS.contains(&model)
}

/// The request body.
pub fn request_body(request: &ModelRequest<'_>, claude_api: bool) -> Value {
    let tools: Vec<Value> = request
        .tools
        .iter()
        .map(|t| {
            json!({
                "name": t.name,
                "description": t.description,
                "input_schema": t.input_schema,
                "eager_input_streaming": true,
            })
        })
        .collect();
    let mut body = Map::new();
    body.insert("model".into(), json!(request.model));
    body.insert("max_tokens".into(), json!(request.max_tokens));
    body.insert("stream".into(), json!(true));
    body.insert("system".into(), json!(request.system));
    body.insert("messages".into(), Value::Array(request.messages.to_vec()));
    if !tools.is_empty() {
        body.insert("tools".into(), Value::Array(tools));
    }
    body.insert("output_config".into(), json!({ "effort": request.effort }));
    body.insert("cache_control".into(), json!({ "type": "ephemeral" }));
    if uses_fallbacks(request.model, claude_api) {
        body.insert("fallbacks".into(), json!("default"));
    }
    Value::Object(body)
}

/// The request headers (the key included — never log these).
pub fn request_headers(api_key: &str, model: &str, claude_api: bool) -> Vec<(String, String)> {
    let mut headers = vec![
        ("x-api-key".to_string(), api_key.to_string()),
        (
            "anthropic-version".to_string(),
            ANTHROPIC_VERSION.to_string(),
        ),
        ("content-type".to_string(), "application/json".to_string()),
        ("accept".to_string(), "text/event-stream".to_string()),
    ];
    if uses_fallbacks(model, claude_api) {
        headers.push(("anthropic-beta".to_string(), FALLBACK_BETA.to_string()));
    }
    headers
}

/// A stream that failed, and whether any content had arrived when it did.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StreamFailure {
    pub error: ProviderError,
    pub content_started: bool,
}

/// Parse a Messages SSE stream into a response.
pub fn parse_stream(
    reader: &mut dyn BufRead,
    progress: &mut dyn FnMut(Progress),
) -> Result<ModelResponse, StreamFailure> {
    let mut state = StreamState::default();
    let mut failure: Option<ProviderError> = None;
    let read = read_events(reader, &mut |event| match state.apply(&event, progress) {
        Ok(more) => more,
        Err(error) => {
            failure = Some(error);
            false
        }
    });
    let started = state.started;
    if let Err(e) = read {
        return Err(StreamFailure {
            error: ProviderError::Transport(e.to_string()),
            content_started: started,
        });
    }
    if let Some(error) = failure {
        return Err(StreamFailure {
            error,
            content_started: started,
        });
    }
    if !state.stopped {
        return Err(StreamFailure {
            error: ProviderError::Stream {
                kind: "incomplete".into(),
                message: "the stream ended before message_stop".into(),
            },
            content_started: started,
        });
    }
    Ok(state.finish())
}

#[derive(Default)]
struct StreamState {
    model: String,
    usage: Value,
    blocks: Vec<Value>,
    /// Accumulated `partial_json` per block index.
    partial: Vec<Option<String>>,
    stop_reason: String,
    stop_details: Value,
    invalid: Vec<(String, String)>,
    started: bool,
    stopped: bool,
}

impl StreamState {
    fn apply(
        &mut self,
        event: &SseEvent,
        progress: &mut dyn FnMut(Progress),
    ) -> Result<bool, ProviderError> {
        if event.data.is_empty() {
            return Ok(true);
        }
        let data: Value = serde_json::from_str(&event.data).map_err(|e| ProviderError::Stream {
            kind: "malformed".into(),
            message: format!("unparseable event: {e}"),
        })?;
        let kind = data
            .get("type")
            .and_then(Value::as_str)
            .unwrap_or(event.event.as_str());
        match kind {
            "message_start" => {
                let message = &data["message"];
                self.model = message["model"].as_str().unwrap_or("").to_string();
                self.usage = message["usage"].clone();
                // A message_start may carry content already (rare); keep it.
                if let Some(content) = message["content"].as_array() {
                    for block in content {
                        self.blocks.push(block.clone());
                        self.partial.push(None);
                    }
                }
            }
            "content_block_start" => {
                self.started = true;
                let index = data["index"].as_u64().unwrap_or(self.blocks.len() as u64) as usize;
                let mut block = data["content_block"].clone();
                let is_tool = block["type"] == json!("tool_use");
                if is_tool {
                    if let Some(name) = block["name"].as_str() {
                        progress(Progress::ToolUse(name.to_string()));
                    }
                    // The input arrives as input_json_delta fragments.
                    block["input"] = json!({});
                }
                while self.blocks.len() <= index {
                    self.blocks.push(Value::Null);
                    self.partial.push(None);
                }
                self.blocks[index] = block;
                self.partial[index] = is_tool.then(String::new);
            }
            "content_block_delta" => {
                let index = data["index"].as_u64().unwrap_or(0) as usize;
                let Some(block) = self.blocks.get_mut(index) else {
                    return Ok(true);
                };
                let delta = &data["delta"];
                match delta["type"].as_str().unwrap_or("") {
                    "text_delta" => append(block, "text", delta["text"].as_str()),
                    "thinking_delta" => append(block, "thinking", delta["thinking"].as_str()),
                    "signature_delta" => append(block, "signature", delta["signature"].as_str()),
                    "input_json_delta" => {
                        if let Some(Some(buffer)) = self.partial.get_mut(index) {
                            buffer.push_str(delta["partial_json"].as_str().unwrap_or(""));
                        }
                    }
                    "citations_delta" => {
                        if let Some(map) = block.as_object_mut() {
                            let list = map.entry("citations").or_insert_with(|| json!([]));
                            if let Some(items) = list.as_array_mut() {
                                items.push(delta["citation"].clone());
                            }
                        }
                    }
                    _ => {}
                }
            }
            "content_block_stop" => {
                let index = data["index"].as_u64().unwrap_or(0) as usize;
                if let Some(Some(raw)) = self.partial.get_mut(index).map(Option::take) {
                    let block = &mut self.blocks[index];
                    // Strict parse: with eager input streaming the API does
                    // not validate, so the text may be cut off or malformed.
                    let parsed = if raw.trim().is_empty() {
                        Ok(json!({}))
                    } else {
                        serde_json::from_str::<Value>(&raw)
                    };
                    match parsed {
                        Ok(value) if value.is_object() => block["input"] = value,
                        _ => {
                            let id = block["id"].as_str().unwrap_or("").to_string();
                            self.invalid.push((id, raw));
                        }
                    }
                }
            }
            "message_delta" => {
                if let Some(reason) = data["delta"]["stop_reason"].as_str() {
                    self.stop_reason = reason.to_string();
                }
                if let Some(details) = data["delta"].get("stop_details") {
                    self.stop_details = details.clone();
                }
                if let Some(usage) = data["usage"].as_object() {
                    if !self.usage.is_object() {
                        self.usage = json!({});
                    }
                    for (k, v) in usage {
                        self.usage[k] = v.clone();
                    }
                }
            }
            "message_stop" => {
                self.stopped = true;
                return Ok(false);
            }
            "error" => {
                return Err(ProviderError::Stream {
                    kind: data["error"]["type"]
                        .as_str()
                        .unwrap_or("error")
                        .to_string(),
                    message: data["error"]["message"].as_str().unwrap_or("").to_string(),
                });
            }
            // `ping` and anything newer.
            _ => {}
        }
        Ok(true)
    }

    fn finish(self) -> ModelResponse {
        // Blocks still holding an unfinished tool input were cut off (the
        // stream stopped at max_tokens mid-block): their input is invalid.
        let mut invalid = self.invalid;
        for (block, partial) in self.blocks.iter().zip(&self.partial) {
            if let Some(raw) = partial {
                invalid.push((block["id"].as_str().unwrap_or("").to_string(), raw.clone()));
            }
        }
        ModelResponse {
            content: self.blocks.into_iter().filter(|b| !b.is_null()).collect(),
            stop_reason: self.stop_reason,
            stop_details: self.stop_details,
            model: self.model,
            usage: self.usage,
            invalid_inputs: invalid,
        }
    }
}

fn append(block: &mut Value, key: &str, text: Option<&str>) {
    let Some(text) = text else { return };
    let Some(map) = block.as_object_mut() else {
        return;
    };
    let entry = map.entry(key).or_insert_with(|| json!(""));
    if let Value::String(s) = entry {
        s.push_str(text);
    } else {
        *entry = json!(text);
    }
}

impl Provider for AnthropicProvider {
    fn complete(
        &self,
        request: &ModelRequest<'_>,
        progress: &mut dyn FnMut(Progress),
    ) -> Result<ModelResponse, ProviderError> {
        let claude_api = self.is_claude_api();
        let body = request_body(request, claude_api).to_string();
        let headers = request_headers(&self.api_key, request.model, claude_api);
        let agent = http::agent();
        // One retry budget for both ways a call can fail before producing
        // anything: an error status (or no connection), and a stream whose
        // first event is an error.
        let mut attempt = 0;
        loop {
            let (error, retry_after) = match http::post_once(&agent, &self.url(), &headers, &body) {
                Ok(mut response) => match parse_stream(&mut response.reader, progress) {
                    Ok(message) => return Ok(message),
                    // A stream that failed mid-way cannot be retried: its
                    // partial output has been consumed.
                    Err(failure) if failure.content_started => return Err(failure.error),
                    Err(failure) => (failure.error, None),
                },
                Err(failure) => (failure.error, failure.retry_after),
            };
            attempt += 1;
            if !error.retryable() || attempt > self.retry.max_retries {
                return Err(error);
            }
            std::thread::sleep(self.retry.delay(attempt, retry_after));
        }
    }
}

/// Prepare an assistant turn's content for echoing back.
///
/// Unchanged in the ordinary case. After a mid-output server-side fallback the
/// API's rule applies: `thinking`, `redacted_thinking`, `tool_use` (and any
/// other model-internal block) that appear *before* the last `fallback` block
/// are dropped; text and everything after the boundary are kept.
pub fn echo_content(content: &[Value]) -> Vec<Value> {
    let Some(boundary) = content.iter().rposition(|b| b["type"] == json!("fallback")) else {
        return content.to_vec();
    };
    content
        .iter()
        .enumerate()
        .filter(|(i, block)| {
            *i >= boundary
                || matches!(block["type"].as_str(), Some("text"))
                || (block["type"] == json!("server_tool_use") && has_result(content, block))
                || block["type"]
                    .as_str()
                    .is_some_and(|t| t.ends_with("_tool_result"))
        })
        .map(|(_, b)| b.clone())
        .collect()
}

fn has_result(content: &[Value], tool_use: &Value) -> bool {
    let id = &tool_use["id"];
    content.iter().any(|b| {
        b["type"]
            .as_str()
            .is_some_and(|t| t.ends_with("_tool_result"))
            && &b["tool_use_id"] == id
    })
}
