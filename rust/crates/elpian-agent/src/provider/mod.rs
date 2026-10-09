//! Model providers behind one interface.
//!
//! History is kept in the Anthropic Messages shape (role + content blocks),
//! because that is the shape that must be echoed back unchanged — thinking
//! blocks included — for the default provider. Other providers translate to
//! and from it at their edge.

use std::time::Duration;

use serde_json::Value;

pub mod anthropic;
pub mod http;
pub mod openai;
pub mod scripted;
pub mod sse;

/// A tool the model may call.
#[derive(Debug, Clone, PartialEq)]
pub struct ToolDef {
    pub name: String,
    pub description: String,
    pub input_schema: Value,
}

/// One model call.
#[derive(Debug, Clone)]
pub struct ModelRequest<'a> {
    pub model: &'a str,
    pub system: &'a str,
    /// Sorted by name, so the request prefix is byte-stable and caches.
    pub tools: &'a [ToolDef],
    /// Anthropic-shaped messages.
    pub messages: &'a [Value],
    pub max_tokens: u32,
    /// `low` … `max`.
    pub effort: &'a str,
}

/// What one model call produced.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct ModelResponse {
    /// Anthropic-shaped content blocks, as received.
    pub content: Vec<Value>,
    /// `end_turn`, `tool_use`, `max_tokens`, `refusal`, `pause_turn`,
    /// `stop_sequence`, … — always check it before using `content`.
    pub stop_reason: String,
    pub stop_details: Value,
    pub model: String,
    pub usage: Value,
    /// Tool-use ids whose streamed input was not valid JSON, with the raw text.
    /// Their blocks carry `{}` as input and must not be executed.
    pub invalid_inputs: Vec<(String, String)>,
}

/// Why a model call failed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ProviderError {
    /// The provider answered with an error status.
    Http { status: u16, message: String },
    /// The connection failed.
    Transport(String),
    /// The stream carried an error event, or ended before it was complete.
    Stream { kind: String, message: String },
    /// The provider is not usable as configured (no key, bad script, …).
    Config(String),
}

impl ProviderError {
    /// The operator's description. Never contains the key.
    pub fn message(&self) -> String {
        match self {
            ProviderError::Http { status, message } => format!("HTTP {status}: {message}"),
            ProviderError::Transport(m) => format!("transport: {m}"),
            ProviderError::Stream { kind, message } => format!("stream {kind}: {message}"),
            ProviderError::Config(m) => m.clone(),
        }
    }

    /// Whether trying again might help.
    pub fn retryable(&self) -> bool {
        match self {
            ProviderError::Http { status, .. } => {
                matches!(status, 408 | 409 | 429) || *status >= 500
            }
            ProviderError::Transport(_) => true,
            ProviderError::Stream { kind, .. } => matches!(
                kind.as_str(),
                "overloaded_error" | "api_error" | "rate_limit_error" | "timeout_error"
            ),
            ProviderError::Config(_) => false,
        }
    }
}

/// Progress a provider reports while it streams.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Progress {
    /// The model started a tool call.
    ToolUse(String),
}

/// A model provider.
pub trait Provider: Send + Sync {
    fn complete(
        &self,
        request: &ModelRequest<'_>,
        progress: &mut dyn FnMut(Progress),
    ) -> Result<ModelResponse, ProviderError>;
}

/// How many times a failed call is retried, and how long to wait.
#[derive(Debug, Clone)]
pub struct RetryPolicy {
    pub max_retries: u32,
    pub base_delay: Duration,
    /// The longest a `retry-after` header is honoured for.
    pub max_delay: Duration,
}

impl Default for RetryPolicy {
    fn default() -> Self {
        RetryPolicy {
            max_retries: 2,
            base_delay: Duration::from_millis(500),
            max_delay: Duration::from_secs(60),
        }
    }
}

impl RetryPolicy {
    /// The wait before retry number `attempt` (1-based).
    pub fn delay(&self, attempt: u32, retry_after: Option<Duration>) -> Duration {
        match retry_after {
            Some(d) => d.min(self.max_delay),
            None => (self.base_delay * 2u32.saturating_pow(attempt.saturating_sub(1)))
                .min(self.max_delay),
        }
    }
}
