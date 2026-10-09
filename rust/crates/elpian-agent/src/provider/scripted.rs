//! A deterministic provider for tests, CI and offline development.
//!
//! A script is a list of exchanges. Each exchange says which user turn it
//! answers (`when`) and the assistant turns to play for it, one per model call
//! within that request:
//!
//! ```json
//! { "exchanges": [
//!     { "when": { "action": "addToCart" },
//!       "turns": [ { "tools": [ { "name": "fn_addToCart", "input": { "id": "{{action.context.id}}" } } ] },
//!                  { "text": "Added." } ] },
//!     { "when": { "message": "hello" },
//!       "turns": [ { "text": "You said: {{message}}" } ] },
//!     { "turns": [ { "tools": [ { "name": "a2ui_send", "input": { "messages": [ … ] } } ] },
//!                  { "text": "Here you go." } ] }
//! ] }
//! ```
//!
//! `when.message` matches a substring of the user's text; `when.action` an
//! A2UI action name; an exchange without `when` matches anything. Within an
//! exchange, the *n*th model call of the request plays `turns[n]`; past the end
//! it ends the turn. A turn is `{text?, tools?, stopReason?}` or raw
//! `{content, stopReason}`. In strings, `{{message}}` is the user's text and
//! `{{action.<path>}}` a field of the action.

use serde_json::{json, Value};

use super::{ModelRequest, ModelResponse, Progress, Provider, ProviderError};

#[derive(Debug, Clone)]
pub struct ScriptedProvider {
    exchanges: Vec<Value>,
}

impl ScriptedProvider {
    pub fn from_json(script: &Value) -> Result<ScriptedProvider, ProviderError> {
        let exchanges = match script {
            Value::Array(items) => items.clone(),
            Value::Object(map) => map
                .get("exchanges")
                .and_then(Value::as_array)
                .cloned()
                .ok_or_else(|| ProviderError::Config("a script needs \"exchanges\"".into()))?,
            _ => {
                return Err(ProviderError::Config(
                    "a script must be a JSON object".into(),
                ))
            }
        };
        Ok(ScriptedProvider { exchanges })
    }

    pub fn from_bytes(raw: &[u8]) -> Result<ScriptedProvider, ProviderError> {
        let value: Value = serde_json::from_slice(raw).map_err(|e| {
            ProviderError::Config(format!("the agent script is not valid JSON: {e}"))
        })?;
        Self::from_json(&value)
    }
}

/// The last turn a person (not a tool result) wrote, and how many assistant
/// turns have answered it so far.
fn last_user_turn(messages: &[Value]) -> (String, Value, usize) {
    let mut answered = 0;
    for message in messages.iter().rev() {
        let blocks = message["content"].as_array().cloned().unwrap_or_default();
        if message["role"] == json!("assistant") {
            answered += 1;
            continue;
        }
        let texts: Vec<&str> = blocks
            .iter()
            .filter(|b| b["type"] == json!("text"))
            .filter_map(|b| b["text"].as_str())
            .collect();
        if texts.is_empty() {
            continue; // tool results only
        }
        let mut message_text = String::new();
        let mut action = Value::Null;
        for text in texts {
            match serde_json::from_str::<Value>(text) {
                Ok(v) if v.get("a2uiAction").is_some() => action = v["a2uiAction"].clone(),
                _ => {
                    if !message_text.is_empty() {
                        message_text.push('\n');
                    }
                    message_text.push_str(text);
                }
            }
        }
        return (message_text, action, answered);
    }
    (String::new(), Value::Null, answered)
}

fn matches(when: &Value, text: &str, action: &Value) -> bool {
    if when.is_null() {
        return true;
    }
    if let Some(needle) = when.get("message").and_then(Value::as_str) {
        if !text.to_lowercase().contains(&needle.to_lowercase()) {
            return false;
        }
    }
    if let Some(name) = when.get("action").and_then(Value::as_str) {
        if action["name"].as_str() != Some(name) {
            return false;
        }
    }
    true
}

fn substitute(value: &Value, text: &str, action: &Value) -> Value {
    match value {
        Value::String(s) => {
            // A string that is exactly one placeholder takes the field's JSON
            // value, so numbers and objects survive.
            if let Some(path) = s
                .strip_prefix("{{action.")
                .and_then(|r| r.strip_suffix("}}"))
            {
                if !path.contains("}}") {
                    let pointer = format!("/{}", path.replace('.', "/"));
                    return action.pointer(&pointer).cloned().unwrap_or(Value::Null);
                }
            }
            let mut out = s.replace("{{message}}", text);
            while let Some(start) = out.find("{{action.") {
                let Some(end) = out[start..].find("}}") else {
                    break;
                };
                let path = &out[start + 9..start + end];
                let pointer = format!("/{}", path.replace('.', "/"));
                let replacement = match action.pointer(&pointer) {
                    Some(Value::String(v)) => v.clone(),
                    Some(other) => other.to_string(),
                    None => String::new(),
                };
                out.replace_range(start..start + end + 2, &replacement);
            }
            Value::String(out)
        }
        Value::Array(items) => {
            Value::Array(items.iter().map(|v| substitute(v, text, action)).collect())
        }
        Value::Object(map) => Value::Object(
            map.iter()
                .map(|(k, v)| (k.clone(), substitute(v, text, action)))
                .collect(),
        ),
        other => other.clone(),
    }
}

impl Provider for ScriptedProvider {
    fn complete(
        &self,
        request: &ModelRequest<'_>,
        progress: &mut dyn FnMut(Progress),
    ) -> Result<ModelResponse, ProviderError> {
        let (text, action, answered) = last_user_turn(request.messages);
        let exchange = self
            .exchanges
            .iter()
            .find(|e| matches(&e["when"], &text, &action));
        let turn = exchange
            .and_then(|e| e["turns"].as_array())
            .and_then(|turns| turns.get(answered))
            .map(|t| substitute(t, &text, &action));

        let Some(turn) = turn else {
            return Ok(ModelResponse {
                content: Vec::new(),
                stop_reason: "end_turn".into(),
                model: "scripted".into(),
                ..Default::default()
            });
        };

        let mut content = Vec::new();
        if let Some(raw) = turn["content"].as_array() {
            content = raw.clone();
        } else {
            if let Some(t) = turn["text"].as_str() {
                content.push(json!({ "type": "text", "text": t }));
            }
            for (i, tool) in turn["tools"].as_array().into_iter().flatten().enumerate() {
                let name = tool["name"].as_str().unwrap_or("").to_string();
                progress(Progress::ToolUse(name.clone()));
                content.push(json!({
                    "type": "tool_use",
                    "id": format!("toolu_scripted_{}_{i}", request.messages.len()),
                    "name": name,
                    "input": tool.get("input").cloned().unwrap_or_else(|| json!({})),
                }));
            }
        }
        let stop_reason = turn["stopReason"]
            .as_str()
            .map(str::to_string)
            .unwrap_or_else(|| {
                if content.iter().any(|b| b["type"] == json!("tool_use")) {
                    "tool_use".into()
                } else {
                    "end_turn".into()
                }
            });
        Ok(ModelResponse {
            content,
            stop_reason,
            stop_details: Value::Null,
            model: "scripted".into(),
            usage: json!({ "input_tokens": 0, "output_tokens": 0 }),
            invalid_inputs: Vec::new(),
        })
    }
}
