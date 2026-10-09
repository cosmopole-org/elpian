//! An app's agents, built from its manifest, and the loop that runs one turn.
//!
//! # The loop
//!
//! A manual, append-only loop: call the provider; check `stop_reason` before
//! touching the content; on `tool_use` run every tool and return *all* the
//! results in one user message; repeat until `end_turn`, `maxTurns`,
//! `max_tokens` (reported), or `refusal` (a friendly error, and the refused
//! output is discarded rather than kept in history). The assistant's content is
//! appended as received — thinking blocks included — so it is echoed back
//! unchanged on the next call.
//!
//! # Frames
//!
//! Everything the client sees is a JSON object handed to `emit`, one per NDJSON
//! line: `{"type":"conversation"}` first, A2UI messages verbatim (no `type`
//! key), `{"type":"text"}`, `{"type":"status"}`, `{"type":"error"}`, and
//! `{"type":"done"}` last.

use std::collections::BTreeMap;
use std::sync::Arc;

use serde_json::{json, Value};

use crate::a2ui::validator;
use crate::conversation::Conversation;
use crate::manifest::{AgentSpec, AgentsConfig, Instructions};
use crate::prompt::{system_prompt, ToolNote};
use crate::provider::anthropic::echo_content;
use crate::provider::{ModelRequest, Progress, Provider, ToolDef};
use crate::skills::{self, Skill};

pub const A2UI_SEND: &str = "a2ui_send";
pub const LOAD_SKILL: &str = "load_skill";
pub const FUNCTION_TOOL_PREFIX: &str = "fn_";

/// What the manifest says about one of the app's functions.
#[derive(Debug, Clone, PartialEq)]
pub struct FunctionInfo {
    pub name: String,
    /// `action` or `component`.
    pub kind: String,
    pub description: Option<String>,
    /// JSON Schema of the arguments.
    pub params: Option<Value>,
}

/// Runs the app's own functions on behalf of the agent — through the same
/// path, identity and governance as a client calling them.
pub trait FunctionRunner {
    fn run(&self, function: &str, args: &Value) -> Result<Value, String>;
}

/// One agent, ready to run.
pub struct Agent {
    pub spec: AgentSpec,
    pub model: Option<String>,
    pub system_prompt: String,
    /// Sorted by name.
    pub tools: Vec<ToolDef>,
    tool_validators: BTreeMap<String, jsonschema::Validator>,
    skills: BTreeMap<String, Skill>,
}

impl std::fmt::Debug for Agent {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Agent")
            .field("name", &self.spec.name)
            .field(
                "tools",
                &self.tools.iter().map(|t| &t.name).collect::<Vec<_>>(),
            )
            .finish()
    }
}

/// Every agent of one app.
#[derive(Debug)]
pub struct AppAgents {
    pub config: AgentsConfig,
    pub agents: BTreeMap<String, Arc<Agent>>,
    /// The `agents/**` files of the app bundle.
    pub files: BTreeMap<String, Vec<u8>>,
}

impl AppAgents {
    /// Build every declared agent. Fails on anything the manifest promised
    /// and the bundle does not deliver.
    pub fn build(
        config: AgentsConfig,
        files: BTreeMap<String, Vec<u8>>,
        functions: &[FunctionInfo],
    ) -> Result<AppAgents, String> {
        let mut agents = BTreeMap::new();
        for spec in config.agents.values() {
            let agent = Agent::build(spec, &config, &files, functions)
                .map_err(|e| format!("agent {:?}: {e}", spec.name))?;
            agents.insert(spec.name.clone(), Arc::new(agent));
        }
        Ok(AppAgents {
            config,
            agents,
            files,
        })
    }

    pub fn get(&self, name: &str) -> Option<Arc<Agent>> {
        self.agents.get(name).cloned()
    }
}

impl Agent {
    pub fn build(
        spec: &AgentSpec,
        config: &AgentsConfig,
        files: &BTreeMap<String, Vec<u8>>,
        functions: &[FunctionInfo],
    ) -> Result<Agent, String> {
        let instructions = match &spec.instructions {
            Instructions::Inline(text) => text.clone(),
            Instructions::File(path) => String::from_utf8_lossy(
                files
                    .get(path)
                    .ok_or_else(|| format!("{path} is not in the app bundle"))?,
            )
            .into_owned(),
        };

        let mut skills = BTreeMap::new();
        for name in &spec.skills {
            skills.insert(name.clone(), skills::load(name, files)?);
        }

        let mut tools = vec![ToolDef {
            name: A2UI_SEND.into(),
            description: "Send A2UI v0.9.1 server-to-client messages to the user's device. Valid \
                          messages are shown immediately; the result lists VALIDATION_FAILED \
                          errors for any that were not."
                .into(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "messages": {
                        "type": "array",
                        "minItems": 1,
                        "description": "A2UI messages: createSurface, updateComponents, updateDataModel or deleteSurface.",
                        "items": { "type": "object" }
                    }
                },
                "required": ["messages"],
                "additionalProperties": false
            }),
        }];
        let mut notes = vec![ToolNote {
            name: A2UI_SEND.into(),
            note: "the only way to show UI. Batch related messages in one call.".into(),
        }];
        if !skills.is_empty() {
            tools.push(ToolDef {
                name: LOAD_SKILL.into(),
                description: "Load a skill's full instructions (and example A2UI messages) by name."
                    .into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "name": { "type": "string", "enum": spec.skills.iter().collect::<std::collections::BTreeSet<_>>() }
                    },
                    "required": ["name"],
                    "additionalProperties": false
                }),
            });
        }
        for name in &spec.tools {
            let info = functions
                .iter()
                .find(|f| &f.name == name)
                .ok_or_else(|| format!("unknown tool {name:?}"))?;
            let tool_name = format!("{FUNCTION_TOOL_PREFIX}{name}");
            if tool_name.len() > 128
                || !tool_name
                    .chars()
                    .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
            {
                return Err(format!(
                    "function {name:?} cannot be offered as a tool: tool names must match \
                     [a-zA-Z0-9_-]{{1,128}}"
                ));
            }
            let schema = match &info.params {
                Some(schema) => {
                    if schema.get("type") != Some(&json!("object")) {
                        return Err(format!(
                            "function {name:?}: \"params\" must be a JSON Schema with \"type\": \"object\""
                        ));
                    }
                    schema.clone()
                }
                None => json!({ "type": "object", "additionalProperties": true }),
            };
            let description = info
                .description
                .clone()
                .unwrap_or_else(|| format!("Call the app's {} function {name}.", info.kind));
            if info.kind == "component" {
                notes.push(ToolNote {
                    name: tool_name.clone(),
                    note:
                        "returns an Elpian UI payload as JSON (the app's own static UI); use its \
                           data, but show UI to the user with a2ui_send."
                            .into(),
                });
            }
            tools.push(ToolDef {
                name: tool_name,
                description,
                input_schema: schema,
            });
        }
        tools.sort_by(|a, b| a.name.cmp(&b.name));

        let mut tool_validators = BTreeMap::new();
        for tool in &tools {
            let compiled = jsonschema::options()
                .with_draft(jsonschema::Draft::Draft202012)
                .build(&tool.input_schema)
                .map_err(|e| format!("tool {}: invalid input schema: {e}", tool.name))?;
            tool_validators.insert(tool.name.clone(), compiled);
        }

        let skill_list: Vec<Skill> = skills.values().cloned().collect();
        let prompt = system_prompt(
            &spec.name,
            &instructions,
            &spec.catalogs,
            &skill_list,
            &notes,
        );

        Ok(Agent {
            spec: spec.clone(),
            model: config.model_for(spec),
            system_prompt: prompt,
            tools,
            tool_validators,
            skills,
        })
    }

    /// The tools offered to the model, by name.
    pub fn tool_names(&self) -> Vec<&str> {
        self.tools.iter().map(|t| t.name.as_str()).collect()
    }
}

/// What the client sent for this turn.
#[derive(Debug, Clone, Default)]
pub struct TurnInput {
    pub message: Option<String>,
    pub action: Option<Value>,
    /// `a2uiClientDataModel`: `{"surfaces": {"<id>": {…}}}`.
    pub data_model: Option<Value>,
    /// `a2uiClientCapabilities.supportedCatalogIds`.
    pub supported_catalogs: Option<Vec<String>>,
}

impl TurnInput {
    /// Parse a request body.
    pub fn from_body(body: &Value) -> Result<TurnInput, String> {
        if !body.is_object() {
            return Err("the body must be a JSON object".into());
        }
        let message = match body.get("message") {
            None | Some(Value::Null) => None,
            Some(Value::String(s)) => Some(s.clone()),
            Some(_) => return Err("\"message\" must be a string".into()),
        };
        let action = match body.get("action") {
            None | Some(Value::Null) => None,
            Some(a @ Value::Object(_)) => {
                if a.get("name").and_then(Value::as_str).is_none() {
                    return Err("\"action.name\" must be a string".into());
                }
                Some(a.clone())
            }
            Some(_) => return Err("\"action\" must be an object".into()),
        };
        if message.as_deref().is_none_or(|m| m.trim().is_empty()) && action.is_none() {
            return Err("send a \"message\" or an \"action\"".into());
        }
        let data_model = match body.get("dataModel") {
            None | Some(Value::Null) => None,
            Some(d) if d.get("surfaces").is_some_and(Value::is_object) => Some(d.clone()),
            Some(_) => return Err("\"dataModel\" must be {\"surfaces\": {…}}".into()),
        };
        let supported_catalogs = match body.pointer("/capabilities/supportedCatalogIds") {
            None | Some(Value::Null) => None,
            Some(Value::Array(ids)) => Some(
                ids.iter()
                    .filter_map(Value::as_str)
                    .map(str::to_string)
                    .collect(),
            ),
            Some(_) => return Err("\"capabilities.supportedCatalogIds\" must be an array".into()),
        };
        Ok(TurnInput {
            message,
            action,
            data_model,
            supported_catalogs,
        })
    }
}

/// How a turn ended.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TurnSummary {
    /// `end_turn`, `max_turns`, `max_tokens`, `refusal` or `error`.
    pub stop_reason: String,
    pub model_calls: u32,
    pub input_tokens: u64,
    pub output_tokens: u64,
}

pub fn frame_conversation(id: &str) -> Value {
    json!({ "type": "conversation", "conversationId": id })
}
pub fn frame_text(text: &str) -> Value {
    json!({ "type": "text", "text": text })
}
pub fn frame_status(state: &str, tool: Option<&str>) -> Value {
    match tool {
        Some(tool) => json!({ "type": "status", "state": state, "tool": tool }),
        None => json!({ "type": "status", "state": state }),
    }
}
pub fn frame_error(message: &str) -> Value {
    json!({ "type": "error", "message": message })
}
pub fn frame_done(stop_reason: &str) -> Value {
    json!({ "type": "done", "stopReason": stop_reason })
}

/// Everything one turn runs against.
pub struct TurnContext<'a> {
    pub agent: &'a Agent,
    pub provider: &'a dyn Provider,
    pub functions: &'a dyn FunctionRunner,
    /// For the operator's log (provider failures, refusals). Never shown to
    /// the client verbatim.
    pub log: &'a dyn Fn(&str),
}

/// Run one turn of `conversation`. Emits every frame after the
/// `conversation` frame (the caller writes that one), ending with `done`.
/// `emit` returns `false` when the reader has gone; the turn then stops at the
/// next safe point.
pub fn run_turn(
    ctx: &TurnContext<'_>,
    conversation: &mut Conversation,
    input: TurnInput,
    emit: &mut dyn FnMut(&Value) -> bool,
) -> TurnSummary {
    let agent = ctx.agent;
    let mut summary = TurnSummary {
        stop_reason: "end_turn".into(),
        model_calls: 0,
        input_tokens: 0,
        output_tokens: 0,
    };
    let finish = |summary: &mut TurnSummary, reason: &str, emit: &mut dyn FnMut(&Value) -> bool| {
        summary.stop_reason = reason.to_string();
        emit(&frame_done(reason));
    };

    let Some(model) = agent.model.clone() else {
        emit(&frame_error("this agent has no model configured"));
        finish(&mut summary, "error", emit);
        return summary;
    };

    // The catalogs a surface may use: the agent's, narrowed by the client's.
    let allowed: Vec<String> = match &input.supported_catalogs {
        Some(client) if !client.is_empty() => agent
            .spec
            .catalogs
            .iter()
            .filter(|c| client.contains(c))
            .cloned()
            .collect(),
        _ => agent.spec.catalogs.clone(),
    };

    // The client's data model is the current one for surfaces it holds.
    let mut reported = serde_json::Map::new();
    if let Some(surfaces) = input
        .data_model
        .as_ref()
        .and_then(|d| d["surfaces"].as_object())
    {
        for (id, model) in surfaces {
            // Only surfaces this conversation created: a client cannot make
            // the agent believe in a surface it never sent.
            if conversation
                .surfaces
                .set_client_data_model(id, model.clone())
            {
                reported.insert(id.clone(), model.clone());
            }
        }
    }

    // The new user turn. Tool calls the last turn never answered are answered
    // first, with errors, so the history stays valid.
    let mut content: Vec<Value> = conversation
        .pending_tool_uses
        .drain(..)
        .map(|id| {
            json!({
                "type": "tool_result",
                "tool_use_id": id,
                "is_error": true,
                "content": "Not run: the previous response was cut off before this call completed.",
            })
        })
        .collect();
    if let Some(message) = input.message.as_deref().filter(|m| !m.trim().is_empty()) {
        content.push(json!({ "type": "text", "text": message }));
    }
    if let Some(action) = &input.action {
        let mut turn = json!({ "a2uiAction": action });
        if !reported.is_empty() {
            turn["dataModel"] = json!({ "surfaces": reported });
        }
        content.push(json!({ "type": "text", "text": turn.to_string() }));
    } else if !reported.is_empty() {
        content.push(json!({
            "type": "text",
            "text": json!({ "a2uiDataModel": { "surfaces": reported } }).to_string(),
        }));
    }
    conversation
        .messages
        .push(json!({ "role": "user", "content": content }));

    let mut reader_gone = false;
    let mut turns = 0u32;
    loop {
        if turns >= agent.spec.max_turns {
            finish(&mut summary, "max_turns", emit);
            return summary;
        }
        turns += 1;
        if !emit(&frame_status("working", None)) {
            reader_gone = true;
        }
        if reader_gone {
            finish(&mut summary, "error", emit);
            return summary;
        }

        let request = ModelRequest {
            model: &model,
            system: &agent.system_prompt,
            tools: &agent.tools,
            messages: &conversation.messages,
            max_tokens: agent.spec.max_output_tokens,
            effort: &agent.spec.effort,
        };
        let mut progress = |_: Progress| {};
        summary.model_calls += 1;
        let response = match ctx.provider.complete(&request, &mut progress) {
            Ok(r) => r,
            Err(error) => {
                (ctx.log)(&format!(
                    "agent {}: provider failed: {}",
                    agent.spec.name,
                    error.message()
                ));
                emit(&frame_error(&format!(
                    "The assistant is unavailable right now ({}).",
                    error.message()
                )));
                finish(&mut summary, "error", emit);
                return summary;
            }
        };
        summary.input_tokens += response.usage["input_tokens"].as_u64().unwrap_or(0);
        summary.output_tokens += response.usage["output_tokens"].as_u64().unwrap_or(0);

        // stop_reason first, content second.
        if response.stop_reason == "refusal" {
            (ctx.log)(&format!(
                "agent {}: the model declined (stop_details: {})",
                agent.spec.name, response.stop_details
            ));
            // The partial output of a refused turn is discarded, not kept.
            emit(&frame_error(
                "The assistant declined this request. Try rephrasing it.",
            ));
            finish(&mut summary, "refusal", emit);
            return summary;
        }

        let content = echo_content(&response.content);
        let tool_uses: Vec<Value> = content
            .iter()
            .filter(|b| b["type"] == json!("tool_use"))
            .cloned()
            .collect();
        // An empty assistant turn cannot be sent back (the API rejects empty
        // content), so it is not recorded; the next user turn simply follows.
        if !content.is_empty() {
            conversation
                .messages
                .push(json!({ "role": "assistant", "content": content.clone() }));
        }
        conversation.pending_tool_uses = tool_uses
            .iter()
            .filter_map(|b| b["id"].as_str().map(str::to_string))
            .collect();

        for block in &content {
            if block["type"] == json!("text") {
                if let Some(text) = block["text"].as_str().filter(|t| !t.trim().is_empty()) {
                    if !emit(&frame_text(text)) {
                        reader_gone = true;
                    }
                }
            }
        }

        match response.stop_reason.as_str() {
            "tool_use" => {}
            "pause_turn" => continue,
            "max_tokens" => {
                // A tool call cut off mid-input is not run; it is answered
                // with an error at the start of the next turn.
                finish(&mut summary, "max_tokens", emit);
                return summary;
            }
            _ => {
                conversation.pending_tool_uses.clear();
                finish(&mut summary, "end_turn", emit);
                return summary;
            }
        }
        if tool_uses.is_empty() {
            conversation.pending_tool_uses.clear();
            finish(&mut summary, "end_turn", emit);
            return summary;
        }
        if reader_gone {
            finish(&mut summary, "error", emit);
            return summary;
        }

        let mut results = Vec::new();
        for block in &tool_uses {
            let id = block["id"].as_str().unwrap_or("").to_string();
            let name = block["name"].as_str().unwrap_or("");
            if !emit(&frame_status("tool", Some(name))) {
                reader_gone = true;
            }
            let invalid = response.invalid_inputs.iter().find(|(i, _)| *i == id);
            let (text, is_error) = match invalid {
                Some((_, raw)) => (json!({ "INVALID_JSON": raw }).to_string(), true),
                None => run_tool(ctx, conversation, &allowed, name, &block["input"], emit),
            };
            let mut result = json!({ "type": "tool_result", "tool_use_id": id, "content": text });
            if is_error {
                result["is_error"] = json!(true);
            }
            results.push(result);
        }
        conversation
            .messages
            .push(json!({ "role": "user", "content": results }));
        conversation.pending_tool_uses.clear();
        if reader_gone {
            finish(&mut summary, "error", emit);
            return summary;
        }
    }
}

/// Run one tool call. Returns the result text and whether it is an error.
fn run_tool(
    ctx: &TurnContext<'_>,
    conversation: &mut Conversation,
    allowed_catalogs: &[String],
    name: &str,
    input: &Value,
    emit: &mut dyn FnMut(&Value) -> bool,
) -> (String, bool) {
    let agent = ctx.agent;
    let Some(schema) = agent.tool_validators.get(name) else {
        return (format!("Unknown tool {name:?}."), true);
    };
    let problems: Vec<String> = schema
        .iter_errors(input)
        .map(|e| {
            let at = e.instance_path().as_str().to_string();
            format!("{}: {e}", if at.is_empty() { "/" } else { &at })
        })
        .collect();
    if !problems.is_empty() {
        return (
            json!({ "error": "invalid input", "problems": problems }).to_string(),
            true,
        );
    }

    if name == A2UI_SEND {
        if allowed_catalogs.is_empty() {
            return (
                "The client supports none of this agent's catalogs; no UI can be shown. Answer in text."
                    .into(),
                true,
            );
        }
        let messages = input["messages"].as_array().cloned().unwrap_or_default();
        let outcome =
            validator().validate_batch(&conversation.surfaces, &messages, allowed_catalogs);
        for message in &outcome.accepted {
            emit(message);
            conversation.surfaces.apply(message);
        }
        return (outcome.report().to_string(), !outcome.errors.is_empty());
    }

    if name == LOAD_SKILL {
        let skill = input["name"].as_str().unwrap_or("");
        return match agent.skills.get(skill) {
            Some(skill) => (skill.render(), false),
            None => (format!("No skill named {skill:?}."), true),
        };
    }

    if let Some(function) = name.strip_prefix(FUNCTION_TOOL_PREFIX) {
        if !agent.spec.tools.iter().any(|t| t == function) {
            return (format!("Unknown tool {name:?}."), true);
        }
        return match ctx.functions.run(function, input) {
            Ok(value) => (value.to_string(), false),
            Err(message) => (json!({ "error": message }).to_string(), true),
        };
    }
    (format!("Unknown tool {name:?}."), true)
}
