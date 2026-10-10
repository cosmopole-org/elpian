//! An OpenAI-compatible Chat Completions provider.
//!
//! `POST {baseUrl}/chat/completions` with `stream: true` and function tools.
//! History stays in the Anthropic shape; it is translated here, and the reply
//! is translated back, so the loop does not know which provider it runs on.

use std::io::BufRead;

use serde_json::{json, Value};

use super::http::post_stream;
use super::sse::read_events;
use super::{ModelRequest, ModelResponse, Progress, Provider, ProviderError, RetryPolicy};

#[derive(Clone)]
pub struct OpenAiProvider {
    pub api_key: String,
    pub base_url: String,
    pub retry: RetryPolicy,
}

impl std::fmt::Debug for OpenAiProvider {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("OpenAiProvider")
            .field("base_url", &self.base_url)
            .finish()
    }
}

impl OpenAiProvider {
    pub fn new(api_key: impl Into<String>, base_url: impl Into<String>) -> Self {
        OpenAiProvider {
            api_key: api_key.into(),
            base_url: base_url.into(),
            retry: RetryPolicy::default(),
        }
    }
}

/// Translate Anthropic-shaped history into Chat Completions messages.
pub fn to_chat_messages(system: &str, messages: &[Value]) -> Vec<Value> {
    let mut out = vec![json!({ "role": "system", "content": system })];
    for message in messages {
        let role = message["role"].as_str().unwrap_or("user");
        let blocks: Vec<Value> = match &message["content"] {
            Value::String(text) => vec![json!({ "type": "text", "text": text })],
            Value::Array(blocks) => blocks.clone(),
            _ => Vec::new(),
        };
        if role == "assistant" {
            let text: Vec<&str> = blocks
                .iter()
                .filter(|b| b["type"] == json!("text"))
                .filter_map(|b| b["text"].as_str())
                .collect();
            let calls: Vec<Value> = blocks
                .iter()
                .filter(|b| b["type"] == json!("tool_use"))
                .map(|b| {
                    json!({
                        "id": b["id"],
                        "type": "function",
                        "function": { "name": b["name"], "arguments": b["input"].to_string() }
                    })
                })
                .collect();
            let mut m = json!({ "role": "assistant", "content": text.join("\n") });
            if !calls.is_empty() {
                m["tool_calls"] = Value::Array(calls);
            }
            out.push(m);
        } else {
            let mut text = Vec::new();
            for block in &blocks {
                match block["type"].as_str() {
                    Some("tool_result") => {
                        let content = match &block["content"] {
                            Value::String(s) => s.clone(),
                            Value::Array(parts) => parts
                                .iter()
                                .filter_map(|p| p["text"].as_str())
                                .collect::<Vec<_>>()
                                .join("\n"),
                            other => other.to_string(),
                        };
                        out.push(json!({
                            "role": "tool",
                            "tool_call_id": block["tool_use_id"],
                            "content": content,
                        }));
                    }
                    Some("text") => text.push(block["text"].as_str().unwrap_or("").to_string()),
                    _ => {}
                }
            }
            if !text.is_empty() {
                out.push(json!({ "role": "user", "content": text.join("\n") }));
            }
        }
    }
    out
}

pub fn request_body(model: &str, request: &ModelRequest<'_>) -> Value {
    let tools: Vec<Value> = request
        .tools
        .iter()
        .map(|t| {
            json!({
                "type": "function",
                "function": {
                    "name": t.name,
                    "description": t.description,
                    "parameters": t.input_schema,
                }
            })
        })
        .collect();
    let mut body = json!({
        "model": model,
        "stream": true,
        "max_tokens": request.max_tokens,
        "messages": to_chat_messages(request.system, request.messages),
    });
    if !tools.is_empty() {
        body["tools"] = Value::Array(tools);
    }
    body
}

/// Parse a Chat Completions stream into an Anthropic-shaped response.
pub fn parse_stream(
    reader: &mut dyn BufRead,
    progress: &mut dyn FnMut(Progress),
) -> Result<ModelResponse, ProviderError> {
    let mut text = String::new();
    // index → (id, name, arguments)
    let mut calls: Vec<(String, String, String)> = Vec::new();
    let mut finish = String::new();
    let mut model = String::new();
    let mut usage = Value::Null;
    let mut done = false;
    let mut failure = None;
    read_events(reader, &mut |event| {
        if event.data.trim() == "[DONE]" {
            done = true;
            return false;
        }
        let Ok(data) = serde_json::from_str::<Value>(&event.data) else {
            return true;
        };
        if let Some(error) = data.get("error") {
            failure = Some(ProviderError::Stream {
                kind: error["type"].as_str().unwrap_or("error").to_string(),
                message: error["message"].as_str().unwrap_or("").to_string(),
            });
            return false;
        }
        if let Some(m) = data["model"].as_str() {
            model = m.to_string();
        }
        if !data["usage"].is_null() {
            usage = data["usage"].clone();
        }
        let choice = &data["choices"][0];
        if let Some(reason) = choice["finish_reason"].as_str() {
            finish = reason.to_string();
        }
        let delta = &choice["delta"];
        if let Some(t) = delta["content"].as_str() {
            text.push_str(t);
        }
        for call in delta["tool_calls"].as_array().into_iter().flatten() {
            let index = call["index"].as_u64().unwrap_or(calls.len() as u64) as usize;
            while calls.len() <= index {
                calls.push(Default::default());
            }
            let slot = &mut calls[index];
            if let Some(id) = call["id"].as_str() {
                slot.0 = id.to_string();
            }
            if let Some(name) = call["function"]["name"].as_str() {
                if slot.1.is_empty() {
                    progress(Progress::ToolUse(name.to_string()));
                }
                slot.1.push_str(name);
            }
            if let Some(args) = call["function"]["arguments"].as_str() {
                slot.2.push_str(args);
            }
        }
        true
    })
    .map_err(|e| ProviderError::Transport(e.to_string()))?;
    if let Some(error) = failure {
        return Err(error);
    }
    if !done && finish.is_empty() {
        return Err(ProviderError::Stream {
            kind: "incomplete".into(),
            message: "the stream ended before it finished".into(),
        });
    }

    let mut content = Vec::new();
    if !text.is_empty() {
        content.push(json!({ "type": "text", "text": text }));
    }
    let mut invalid = Vec::new();
    for (i, (id, name, args)) in calls.into_iter().enumerate() {
        let id = if id.is_empty() {
            format!("call_{i}")
        } else {
            id
        };
        let input = if args.trim().is_empty() {
            json!({})
        } else {
            match serde_json::from_str::<Value>(&args) {
                Ok(v) if v.is_object() => v,
                _ => {
                    invalid.push((id.clone(), args.clone()));
                    json!({})
                }
            }
        };
        content.push(json!({ "type": "tool_use", "id": id, "name": name, "input": input }));
    }
    let stop_reason = match finish.as_str() {
        "tool_calls" | "function_call" => "tool_use",
        "length" => "max_tokens",
        "content_filter" => "refusal",
        _ if content.iter().any(|b| b["type"] == json!("tool_use")) => "tool_use",
        _ => "end_turn",
    };
    Ok(ModelResponse {
        content,
        stop_reason: stop_reason.to_string(),
        stop_details: Value::Null,
        model,
        usage,
        invalid_inputs: invalid,
    })
}

impl Provider for OpenAiProvider {
    fn complete(
        &self,
        request: &ModelRequest<'_>,
        progress: &mut dyn FnMut(Progress),
    ) -> Result<ModelResponse, ProviderError> {
        let url = format!("{}/chat/completions", self.base_url.trim_end_matches('/'));
        let body = request_body(request.model, request).to_string();
        let headers = vec![
            (
                "authorization".to_string(),
                format!("Bearer {}", self.api_key),
            ),
            ("content-type".to_string(), "application/json".to_string()),
            ("accept".to_string(), "text/event-stream".to_string()),
        ];
        let mut response = post_stream(&url, &headers, &body, &self.retry)?;
        parse_stream(&mut response.reader, progress)
    }
}
