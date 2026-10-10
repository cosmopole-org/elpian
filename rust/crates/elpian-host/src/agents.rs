//! Serving an app's agents.
//!
//! `POST /apps/<app>/agent/<agent>` runs one turn of a conversation and
//! streams it back as NDJSON. Everything that can refuse the request — an
//! unknown app or agent, a malformed body, the quota, a busy conversation, a
//! provider with no key — is decided *before* the stream starts, so it can be
//! an ordinary HTTP status. Once the stream has started, problems are frames.
//!
//! # Governance
//!
//! * An agent request is admitted by the app's quota like a write (it spends
//!   the app's model budget and may call actions), and counts as an
//!   invocation.
//! * Function tools run through [`AppRuntime::call_as`] /
//!   [`AppRuntime::render_as`] — the same path as `POST /apps/<app>/fn/<name>`
//!   — with the caller's identity, so each one is admitted by the quota and
//!   governed by the app's capabilities and network posture. An agent can only
//!   call the functions its manifest entry lists, of its own app.
//! * The provider key is a declared app secret. A host started for
//!   development (`elpiand --dev`, which `elpian run dev` passes) falls back to
//!   the process environment for a declared secret it holds no value for. The
//!   key is never sent to a client.

use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use elpian_agent::agent::{frame_conversation, frame_done, frame_error, Agent, FunctionRunner};
use elpian_agent::provider::anthropic::AnthropicProvider;
use elpian_agent::provider::openai::OpenAiProvider;
use elpian_agent::provider::scripted::ScriptedProvider;
use elpian_agent::provider::Provider;
use elpian_agent::{Conversation, TurnContext, TurnInput};
use serde_json::Value;

use crate::app::FunctionKind;
use crate::identity::Identity;
use crate::invoke::Outcome;
use crate::quota::Admission;
use crate::runtime::{AppRuntime, CallError};

/// How this host runs agents.
#[derive(Debug, Clone, Default)]
pub struct AgentSettings {
    /// Run every agent on this provider instead of the one its manifest names
    /// (`ELPIAN_AGENT_PROVIDER`; `scripted` for offline development and CI).
    pub provider_override: Option<String>,
    /// The script the scripted provider plays (`ELPIAN_AGENT_SCRIPT`). Without
    /// it, the app's own `agents/scripted.json`.
    pub script: Option<PathBuf>,
    /// Read a declared secret from the process environment when the host
    /// holds no value for it. Development only.
    pub env_secrets: bool,
}

impl AgentSettings {
    /// From `ELPIAN_AGENT_PROVIDER` / `ELPIAN_AGENT_SCRIPT`.
    pub fn from_env(env_secrets: bool) -> AgentSettings {
        let get = |name: &str| std::env::var(name).ok().filter(|v| !v.trim().is_empty());
        AgentSettings {
            provider_override: get("ELPIAN_AGENT_PROVIDER"),
            script: get("ELPIAN_AGENT_SCRIPT").map(PathBuf::from),
            env_secrets,
        }
    }
}

/// Why an agent request was refused before it started.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AgentError {
    UnknownApp,
    UnknownAgent,
    BadRequest(String),
    OverQuota {
        stage: String,
        axis: String,
    },
    /// Another request is running on this conversation.
    Busy,
    /// The provider cannot be used (no key, no script, …). The message is the
    /// operator's; the caller is told the agent is unavailable.
    Unavailable(String),
}

impl AgentError {
    pub fn status(&self) -> u16 {
        match self {
            AgentError::UnknownApp | AgentError::UnknownAgent => 404,
            AgentError::BadRequest(_) => 400,
            AgentError::OverQuota { .. } => 429,
            AgentError::Busy => 409,
            AgentError::Unavailable(_) => 503,
        }
    }

    pub fn client_message(&self) -> String {
        match self {
            AgentError::UnknownApp => "no such app".into(),
            AgentError::UnknownAgent => "no such agent".into(),
            AgentError::BadRequest(m) => m.clone(),
            AgentError::OverQuota { .. } => "this app is over its quota".into(),
            AgentError::Busy => "this conversation is busy; wait for its reply".into(),
            AgentError::Unavailable(_) => "this agent is not available".into(),
        }
    }
}

/// A turn that has been admitted and is ready to stream.
pub struct PreparedTurn {
    runtime: Arc<AppRuntime>,
    app: String,
    agent: Arc<Agent>,
    provider: Box<dyn Provider>,
    conversation_id: String,
    conversation: Arc<Mutex<Conversation>>,
    input: TurnInput,
    user: Option<Identity>,
}

impl AppRuntime {
    /// Admit one agent turn. Nothing has run when this returns.
    pub fn prepare_agent_turn(
        self: &Arc<Self>,
        app_id: &str,
        agent_name: &str,
        body: &Value,
        user: Option<Identity>,
    ) -> Result<PreparedTurn, AgentError> {
        let app = self.app_definition(app_id).ok_or(AgentError::UnknownApp)?;
        let agents = app.agents.clone().ok_or(AgentError::UnknownAgent)?;
        let agent = agents.get(agent_name).ok_or(AgentError::UnknownAgent)?;
        let input = TurnInput::from_body(body).map_err(AgentError::BadRequest)?;
        let requested_id = match body.get("conversationId") {
            None | Some(Value::Null) => None,
            Some(Value::String(id)) => Some(id.clone()),
            Some(_) => {
                return Err(AgentError::BadRequest(
                    "\"conversationId\" must be a string".into(),
                ))
            }
        };

        // Quota before anything is spent.
        let meters = self.meters(app_id);
        if let Admission::Refuse { stage, axis } = self.quotas().admit(app_id, &meters, true) {
            return Err(AgentError::OverQuota {
                stage: stage.as_str().to_string(),
                axis: axis.to_string(),
            });
        }

        let provider = self.provider_for(&app, &agents, &agent)?;

        let user_key = user.as_ref().map(|u| u.id.clone()).unwrap_or_default();
        let (conversation_id, conversation) = self
            .conversations()
            .open(app_id, agent_name, &user_key, requested_id.as_deref())
            .map_err(|_| {
                AgentError::BadRequest("\"conversationId\" must match [A-Za-z0-9_-]{1,128}".into())
            })?;
        {
            // One turn at a time per conversation: a second request while one
            // is streaming would interleave two histories.
            let mut held = conversation.try_lock().map_err(|_| AgentError::Busy)?;
            if held.in_use {
                return Err(AgentError::Busy);
            }
            held.in_use = true;
        }

        self.pool().meters.record(app_id, |m| m.invocations += 1);

        Ok(PreparedTurn {
            runtime: Arc::clone(self),
            app: app_id.to_string(),
            agent,
            provider,
            conversation_id,
            conversation,
            input,
            user,
        })
    }

    fn provider_for(
        &self,
        app: &crate::app::AppDefinition,
        agents: &elpian_agent::AppAgents,
        agent: &Agent,
    ) -> Result<Box<dyn Provider>, AgentError> {
        let settings = self.agent_settings();
        let name = settings
            .provider_override
            .clone()
            .unwrap_or_else(|| agent.spec.provider.clone());
        match name.as_str() {
            "scripted" => {
                let raw = match &settings.script {
                    Some(path) => std::fs::read(path).map_err(|e| {
                        AgentError::Unavailable(format!("agent script {}: {e}", path.display()))
                    })?,
                    None => agents
                        .files
                        .get("agents/scripted.json")
                        .cloned()
                        .ok_or_else(|| {
                            AgentError::Unavailable(
                            "scripted provider: no ELPIAN_AGENT_SCRIPT and no agents/scripted.json"
                                .into(),
                        )
                        })?,
                };
                let provider = ScriptedProvider::from_bytes(&raw)
                    .map_err(|e| AgentError::Unavailable(e.message()))?;
                Ok(Box::new(provider))
            }
            "anthropic" | "openai" => {
                let spec = agents.config.provider(&name);
                let secret = spec.secret.clone().unwrap_or_default();
                let key = self
                    .secrets()
                    .get(&app.id, &secret, &app.declared_secrets)
                    .or_else(|| {
                        // Development: the declared secret from the
                        // environment. Still only a *declared* name.
                        (settings.env_secrets && app.declared_secrets.contains(&secret))
                            .then(|| std::env::var(&secret).ok())
                            .flatten()
                    })
                    .filter(|k| !k.trim().is_empty())
                    .ok_or_else(|| {
                        AgentError::Unavailable(format!(
                            "{}: no value for secret {secret} (provider {name})",
                            app.id
                        ))
                    })?;
                let base_url = spec.base_url.clone().unwrap_or_default();
                if name == "anthropic" {
                    Ok(Box::new(AnthropicProvider::new(key, base_url)))
                } else {
                    Ok(Box::new(OpenAiProvider::new(key, base_url)))
                }
            }
            other => Err(AgentError::Unavailable(format!("unknown provider {other}"))),
        }
    }
}

/// Clears the conversation's in-use mark however the turn ends.
struct InUse<'a>(&'a mut Conversation);

impl Drop for InUse<'_> {
    fn drop(&mut self) {
        self.0.in_use = false;
    }
}

impl PreparedTurn {
    pub fn conversation_id(&self) -> &str {
        &self.conversation_id
    }

    /// Run the turn, handing every frame to `emit` — the `conversation` frame
    /// first and `done` last. `emit` returns `false` when the reader is gone.
    pub fn run(self, emit: &mut dyn FnMut(&Value) -> bool) {
        let mut guard = self.conversation.lock().unwrap_or_else(|p| p.into_inner());
        let conversation = InUse(&mut guard);
        if !emit(&frame_conversation(&self.conversation_id)) {
            return;
        }

        let functions = RuntimeFunctions {
            runtime: Arc::clone(&self.runtime),
            app: self.app.clone(),
            user: self.user.clone(),
        };
        let app = self.app.clone();
        let log = move |line: &str| eprintln!("[elpian] {app}: {line}");
        let ctx = TurnContext {
            agent: &self.agent,
            provider: self.provider.as_ref(),
            functions: &functions,
            log: &log,
        };
        // A panic in the loop must not leave the client waiting for a `done`
        // that never comes.
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            elpian_agent::run_turn(&ctx, conversation.0, self.input.clone(), emit)
        }));
        match result {
            Ok(summary) => eprintln!(
                "[elpian] {}/agent/{}: {} after {} model call(s), {} in / {} out tokens",
                self.app,
                self.agent.spec.name,
                summary.stop_reason,
                summary.model_calls,
                summary.input_tokens,
                summary.output_tokens
            ),
            Err(_) => {
                eprintln!(
                    "[elpian] {}/agent/{} panicked",
                    self.app, self.agent.spec.name
                );
                emit(&frame_error("the agent failed"));
                emit(&frame_done("error"));
            }
        }
    }
}

/// The most an app's `agents/**` may hold, in total.
pub const MAX_AGENT_FILES_BYTES: u64 = 16 * 1024 * 1024;

/// Read `<root>/agents/**` into bundle paths (`agents/…`, `/`-separated).
///
/// Symbolic links are not followed: a bundle is what is in its directory, and
/// a link out of it would let an app's manifest read the host's files.
pub fn read_agent_files(
    root: &std::path::Path,
) -> Result<std::collections::BTreeMap<String, Vec<u8>>, String> {
    let mut files = std::collections::BTreeMap::new();
    let base = root.join("agents");
    if !base.is_dir() {
        return Ok(files);
    }
    let mut total = 0u64;
    let mut stack = vec![base];
    while let Some(dir) = stack.pop() {
        let entries = std::fs::read_dir(&dir).map_err(|e| format!("{}: {e}", dir.display()))?;
        for entry in entries.flatten() {
            let path = entry.path();
            let kind = entry
                .file_type()
                .map_err(|e| format!("{}: {e}", path.display()))?;
            if kind.is_symlink() {
                continue;
            }
            if kind.is_dir() {
                stack.push(path);
                continue;
            }
            let relative = path
                .strip_prefix(root)
                .map_err(|e| e.to_string())?
                .components()
                .map(|c| c.as_os_str().to_string_lossy().into_owned())
                .collect::<Vec<_>>()
                .join("/");
            let data = std::fs::read(&path).map_err(|e| format!("{}: {e}", path.display()))?;
            total += data.len() as u64;
            if total > MAX_AGENT_FILES_BYTES {
                return Err(format!(
                    "agents/ holds more than {MAX_AGENT_FILES_BYTES} bytes"
                ));
            }
            files.insert(relative, data);
        }
    }
    Ok(files)
}

/// Function tools, through the ordinary invoke path.
struct RuntimeFunctions {
    runtime: Arc<AppRuntime>,
    app: String,
    user: Option<Identity>,
}

impl FunctionRunner for RuntimeFunctions {
    fn run(&self, function: &str, args: &Value) -> Result<Value, String> {
        let kind = self
            .runtime
            .app_definition(&self.app)
            .and_then(|a| a.function(function).map(|f| f.kind))
            .ok_or_else(|| format!("no such function: {function}"))?;
        let result = match kind {
            FunctionKind::Action => {
                self.runtime
                    .call_as(&self.app, function, args, self.user.clone())
            }
            FunctionKind::Component => {
                self.runtime
                    .render_as(&self.app, function, args, self.user.clone())
            }
        };
        match result {
            Ok(invocation) => match invocation.outcome {
                Outcome::Returned(value) => Ok(value),
                Outcome::Trapped(reason) => {
                    eprintln!(
                        "[elpian] {}/{function} trapped (agent tool): {reason}",
                        self.app
                    );
                    Err("the function failed".into())
                }
                Outcome::TooManyHostCalls => Err("the function failed".into()),
                Outcome::DeadlineExceeded => Err("the function took too long".into()),
            },
            Err(CallError::OverQuota { stage, axis }) => {
                eprintln!(
                    "[elpian] {}/{function} refused (agent tool): {stage} on {axis}",
                    self.app
                );
                Err("this app is over its quota".into())
            }
            Err(error) => Err(error.client_message()),
        }
    }
}
