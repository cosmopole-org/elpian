//! The HTTPS client the providers share: `ureq` with rustls.
//!
//! The host has no TLS stack by design (guest egress is brokered and refuses
//! HTTPS); the agent runtime owns its own client for exactly one purpose —
//! talking to the model provider an app was configured with.

use std::io::{BufRead, BufReader, Read};
use std::time::Duration;

use super::{ProviderError, RetryPolicy};

/// A streaming response that came back 2xx.
pub struct StreamResponse {
    pub reader: Box<dyn BufRead + Send>,
}

/// An error response, with what is needed to decide on a retry.
#[derive(Debug)]
pub struct Failure {
    pub error: ProviderError,
    pub retry_after: Option<Duration>,
}

pub fn agent() -> ureq::Agent {
    let config = ureq::Agent::config_builder()
        // Error statuses are read, not raised: the body says why.
        .http_status_as_error(false)
        .timeout_connect(Some(Duration::from_secs(30)))
        .timeout_recv_response(Some(Duration::from_secs(600)))
        // No overall body deadline: a long generation legitimately streams
        // for many minutes. The loop's own bounds (maxTurns, max_tokens)
        // limit what one request can cost.
        .timeout_recv_body(None)
        .build();
    ureq::Agent::new_with_config(config)
}

/// POST `body` and return the response stream, retrying per `policy` on
/// retryable statuses and transport failures. Streams themselves are not
/// retried here — the caller decides, because only it knows whether anything
/// was consumed.
pub fn post_stream(
    url: &str,
    headers: &[(String, String)],
    body: &str,
    policy: &RetryPolicy,
) -> Result<StreamResponse, ProviderError> {
    let agent = agent();
    let mut attempt = 0;
    loop {
        match post_once(&agent, url, headers, body) {
            Ok(response) => return Ok(response),
            Err(failure) => {
                attempt += 1;
                if attempt > policy.max_retries || !failure.error.retryable() {
                    return Err(failure.error);
                }
                std::thread::sleep(policy.delay(attempt, failure.retry_after));
            }
        }
    }
}

/// One attempt, no retries.
pub fn post_once(
    agent: &ureq::Agent,
    url: &str,
    headers: &[(String, String)],
    body: &str,
) -> Result<StreamResponse, Failure> {
    let mut request = agent.post(url);
    for (name, value) in headers {
        request = request.header(name.as_str(), value.as_str());
    }
    let response = request.send(body).map_err(|e| Failure {
        error: ProviderError::Transport(e.to_string()),
        retry_after: None,
    })?;
    let status = response.status().as_u16();
    let retry_after = response
        .headers()
        .get("retry-after")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.trim().parse::<f64>().ok())
        .filter(|s| s.is_finite() && *s >= 0.0)
        .map(Duration::from_secs_f64);
    let reader = response.into_body().into_reader();
    if (200..300).contains(&status) {
        return Ok(StreamResponse {
            reader: Box::new(BufReader::new(reader)),
        });
    }
    let mut text = String::new();
    let _ = reader.take(64 * 1024).read_to_string(&mut text);
    Err(Failure {
        error: ProviderError::Http {
            status,
            message: error_message(&text),
        },
        retry_after,
    })
}

/// The `error.message` of a JSON error body, or the body itself, shortened.
pub fn error_message(body: &str) -> String {
    let parsed: Option<serde_json::Value> = serde_json::from_str(body).ok();
    let message = parsed
        .as_ref()
        .and_then(|v| {
            v.pointer("/error/message")
                .or_else(|| v.get("message"))
                .and_then(|m| m.as_str())
                .map(str::to_string)
        })
        .unwrap_or_else(|| body.trim().to_string());
    message.chars().take(500).collect()
}
