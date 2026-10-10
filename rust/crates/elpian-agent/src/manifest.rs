//! The `agents` and `providers` sections of a mini app's manifest.
//!
//! Parsed and validated at load (and at package time), so a manifest that
//! names a tool the app does not have, a skill with no `SKILL.md`, or an
//! instructions file that is not in the bundle is an error before anything is
//! served — the same rule the host applies to a declared function with no
//! module.

use std::collections::BTreeMap;

use serde_json::Value;

use crate::a2ui;

/// The model an Anthropic agent uses unless the manifest names one.
pub const DEFAULT_ANTHROPIC_MODEL: &str = "claude-opus-5-5";
pub const DEFAULT_ANTHROPIC_BASE_URL: &str = "https://api.anthropic.com";
pub const DEFAULT_OPENAI_BASE_URL: &str = "https://api.openai.com/v1";
pub const DEFAULT_MAX_TURNS: u32 = 16;
pub const DEFAULT_MAX_OUTPUT_TOKENS: u32 = 64_000;
pub const DEFAULT_EFFORT: &str = "medium";

const EFFORTS: [&str; 5] = ["low", "medium", "high", "xhigh", "max"];
const PROVIDERS: [&str; 3] = ["anthropic", "openai", "scripted"];

/// Where an agent's instructions come from.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Instructions {
    /// A file in the app bundle (`agents/….md` or `.txt`).
    File(String),
    /// The text itself.
    Inline(String),
}

/// One declared agent.
#[derive(Debug, Clone, PartialEq)]
pub struct AgentSpec {
    pub name: String,
    pub description: String,
    pub instructions: Instructions,
    /// Skill names → `agents/skills/<name>/SKILL.md`.
    pub skills: Vec<String>,
    /// The app's own server functions this agent may call.
    pub tools: Vec<String>,
    pub provider: String,
    /// `None` uses the provider's default.
    pub model: Option<String>,
    pub effort: String,
    pub max_turns: u32,
    pub max_output_tokens: u32,
    pub catalogs: Vec<String>,
}

/// Per-app provider configuration.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ProviderSpec {
    /// The declared secret holding the API key.
    pub secret: Option<String>,
    pub base_url: Option<String>,
    pub model: Option<String>,
}

/// Everything agent-related a manifest declares.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct AgentsConfig {
    pub agents: BTreeMap<String, AgentSpec>,
    pub providers: BTreeMap<String, ProviderSpec>,
}

impl AgentsConfig {
    pub fn is_empty(&self) -> bool {
        self.agents.is_empty()
    }

    /// The provider settings for `provider`, with defaults filled in.
    pub fn provider(&self, provider: &str) -> ProviderSpec {
        let mut spec = self.providers.get(provider).cloned().unwrap_or_default();
        if spec.secret.is_none() {
            spec.secret = default_secret(provider).map(str::to_string);
        }
        if spec.base_url.is_none() {
            spec.base_url = match provider {
                "anthropic" => Some(DEFAULT_ANTHROPIC_BASE_URL.into()),
                "openai" => Some(DEFAULT_OPENAI_BASE_URL.into()),
                _ => None,
            };
        }
        spec
    }

    /// The model an agent runs on.
    pub fn model_for(&self, agent: &AgentSpec) -> Option<String> {
        agent
            .model
            .clone()
            .or_else(|| {
                self.providers
                    .get(&agent.provider)
                    .and_then(|p| p.model.clone())
            })
            .or_else(|| match agent.provider.as_str() {
                "anthropic" => Some(DEFAULT_ANTHROPIC_MODEL.into()),
                "scripted" => Some("scripted".into()),
                _ => None,
            })
    }

    /// What a client is told: names and descriptions, nothing else.
    pub fn client_listing(&self) -> Value {
        Value::Array(
            self.agents
                .values()
                .map(|a| serde_json::json!({ "name": a.name, "description": a.description }))
                .collect(),
        )
    }
}

/// The secret a provider's key is read from unless configured otherwise.
pub fn default_secret(provider: &str) -> Option<&'static str> {
    match provider {
        "anthropic" => Some("ANTHROPIC_API_KEY"),
        "openai" => Some("OPENAI_API_KEY"),
        _ => None,
    }
}

/// `[a-zA-Z][a-zA-Z0-9_-]*`
pub fn valid_agent_name(name: &str) -> bool {
    let mut chars = name.chars();
    matches!(chars.next(), Some(c) if c.is_ascii_alphabetic())
        && chars.all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
        && name.len() <= 64
}

/// A skill name is a directory name: `[a-z0-9][a-z0-9_-]*`.
pub fn valid_skill_name(name: &str) -> bool {
    let mut chars = name.chars();
    matches!(chars.next(), Some(c) if c.is_ascii_lowercase() || c.is_ascii_digit())
        && chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_' || c == '-')
        && name.len() <= 64
}

/// A bundle path an app may name: relative, under `agents/`, no `..`.
pub fn valid_bundle_path(path: &str) -> bool {
    path.starts_with("agents/")
        && !path.contains('\\')
        && path
            .split('/')
            .all(|s| !s.is_empty() && s != "." && s != "..")
}

/// The path of a skill's `SKILL.md`.
pub fn skill_path(name: &str) -> String {
    format!("agents/skills/{name}/SKILL.md")
}

/// Parse and validate the `agents` / `providers` sections.
///
/// `functions` are the app's declared function names; `has_file` answers
/// whether a bundle path exists.
pub fn parse(
    manifest: &Value,
    functions: &[String],
    has_file: &dyn Fn(&str) -> bool,
) -> Result<AgentsConfig, String> {
    let mut config = AgentsConfig::default();
    let declared_secrets: Vec<&str> = manifest
        .get("secrets")
        .and_then(Value::as_array)
        .map(|a| a.iter().filter_map(Value::as_str).collect())
        .unwrap_or_default();

    if let Some(providers) = manifest.get("providers") {
        let map = providers
            .as_object()
            .ok_or("\"providers\" must be an object")?;
        for (name, entry) in map {
            if !PROVIDERS.contains(&name.as_str()) || name == "scripted" {
                return Err(format!(
                    "providers.{name}: unknown provider (expected anthropic or openai)"
                ));
            }
            let entry = entry
                .as_object()
                .ok_or_else(|| format!("providers.{name} must be an object"))?;
            let get = |key: &str| -> Result<Option<String>, String> {
                match entry.get(key) {
                    None | Some(Value::Null) => Ok(None),
                    Some(Value::String(s)) => Ok(Some(s.clone())),
                    Some(_) => Err(format!("providers.{name}.{key} must be a string")),
                }
            };
            let spec = ProviderSpec {
                secret: get("secret")?,
                base_url: get("baseUrl")?,
                model: get("model")?,
            };
            if let Some(url) = &spec.base_url {
                if !acceptable_base_url(url) {
                    return Err(format!(
                        "providers.{name}.baseUrl must be https:// (http:// only for localhost)"
                    ));
                }
            }
            config.providers.insert(name.clone(), spec);
        }
    }

    let Some(agents) = manifest.get("agents") else {
        return Ok(config);
    };
    let agents = agents.as_array().ok_or("\"agents\" must be an array")?;
    for (i, entry) in agents.iter().enumerate() {
        let entry = entry
            .as_object()
            .ok_or_else(|| format!("agents[{i}] must be an object"))?;
        let name = entry
            .get("name")
            .and_then(Value::as_str)
            .ok_or_else(|| format!("agents[{i}] has no \"name\""))?
            .to_string();
        let at = |field: &str| format!("agent {name:?}: {field}");
        if !valid_agent_name(&name) {
            return Err(at("name must match [a-zA-Z][a-zA-Z0-9_-]*"));
        }
        if config.agents.contains_key(&name) {
            return Err(at("declared twice"));
        }

        let string = |key: &str| -> Result<Option<String>, String> {
            match entry.get(key) {
                None | Some(Value::Null) => Ok(None),
                Some(Value::String(s)) => Ok(Some(s.clone())),
                Some(_) => Err(at(&format!("\"{key}\" must be a string"))),
            }
        };
        let strings = |key: &str| -> Result<Vec<String>, String> {
            match entry.get(key) {
                None | Some(Value::Null) => Ok(Vec::new()),
                Some(Value::Array(items)) => items
                    .iter()
                    .map(|v| {
                        v.as_str()
                            .map(str::to_string)
                            .ok_or_else(|| at(&format!("\"{key}\" must be an array of strings")))
                    })
                    .collect(),
                Some(_) => Err(at(&format!("\"{key}\" must be an array of strings"))),
            }
        };
        let number = |key: &str, default: u32, max: u32| -> Result<u32, String> {
            match entry.get(key) {
                None | Some(Value::Null) => Ok(default),
                Some(v) => match v.as_u64() {
                    Some(n) if n >= 1 && n <= max as u64 => Ok(n as u32),
                    _ => Err(at(&format!("\"{key}\" must be an integer from 1 to {max}"))),
                },
            }
        };

        let instructions = match string("instructions")? {
            None => Instructions::Inline(String::new()),
            Some(text) if text.ends_with(".md") || text.ends_with(".txt") => {
                if !valid_bundle_path(&text) {
                    return Err(at(&format!(
                        "instructions file {text:?} must be a relative path under agents/"
                    )));
                }
                if !has_file(&text) {
                    return Err(at(&format!(
                        "instructions file {text} is not in the app bundle"
                    )));
                }
                Instructions::File(text)
            }
            Some(text) => Instructions::Inline(text),
        };

        let skills = strings("skills")?;
        for skill in &skills {
            if !valid_skill_name(skill) {
                return Err(at(&format!(
                    "skill {skill:?} must match [a-z0-9][a-z0-9_-]*"
                )));
            }
            if !has_file(&skill_path(skill)) {
                return Err(at(&format!(
                    "unknown skill {skill:?}: {} is not in the app bundle",
                    skill_path(skill)
                )));
            }
        }

        let tools = strings("tools")?;
        for tool in &tools {
            if !functions.iter().any(|f| f == tool) {
                return Err(at(&format!(
                    "unknown tool {tool:?}: an agent's tools must be functions this app \
                     declares in \"functions\""
                )));
            }
        }

        let provider = string("provider")?.unwrap_or_else(|| "anthropic".into());
        if !PROVIDERS.contains(&provider.as_str()) {
            return Err(at(&format!(
                "unknown provider {provider:?} (expected anthropic, openai or scripted)"
            )));
        }
        if let Some(secret) = config
            .providers
            .get(&provider)
            .and_then(|p| p.secret.clone())
            .or_else(|| default_secret(&provider).map(str::to_string))
        {
            if !declared_secrets.contains(&secret.as_str()) {
                return Err(at(&format!(
                    "provider {provider} reads its key from secret {secret:?}, which the \
                     manifest does not declare in \"secrets\""
                )));
            }
        }

        let model = string("model")?;
        if provider == "openai"
            && model.is_none()
            && config
                .providers
                .get("openai")
                .and_then(|p| p.model.as_ref())
                .is_none()
        {
            return Err(at(
                "an openai agent needs a \"model\" (on the agent or in providers.openai)",
            ));
        }

        let effort = string("effort")?.unwrap_or_else(|| DEFAULT_EFFORT.into());
        if !EFFORTS.contains(&effort.as_str()) {
            return Err(at("effort must be one of low, medium, high, xhigh, max"));
        }

        let catalogs = strings("catalogs")?;
        let catalogs = if catalogs.is_empty() {
            vec![a2ui::BASIC_CATALOG_ID.to_string()]
        } else {
            catalogs
        };
        for catalog in &catalogs {
            if !a2ui::known_catalog(catalog) {
                return Err(at(&format!(
                    "catalog {catalog:?} is not available on this host (only the basic \
                     catalog, {})",
                    a2ui::BASIC_CATALOG_ID
                )));
            }
        }

        let spec = AgentSpec {
            description: string("description")?.unwrap_or_default(),
            instructions,
            skills,
            tools,
            model,
            effort,
            max_turns: number("maxTurns", DEFAULT_MAX_TURNS, 64)?,
            max_output_tokens: number("maxOutputTokens", DEFAULT_MAX_OUTPUT_TOKENS, 128_000)?,
            catalogs,
            provider,
            name: name.clone(),
        };
        config.agents.insert(name, spec);
    }
    Ok(config)
}

fn acceptable_base_url(url: &str) -> bool {
    if url.starts_with("https://") {
        return true;
    }
    let Some(rest) = url.strip_prefix("http://") else {
        return false;
    };
    let host = rest.split(['/', ':']).next().unwrap_or("");
    matches!(host, "localhost" | "127.0.0.1") || rest.starts_with("[::1]")
}
