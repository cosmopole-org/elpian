//! Making the outbound request the broker allowed.
//!
//! [`crate::egress::decide`] says whether a request may happen and to which
//! address. This does it — and the two are split because the decision is the
//! part with the security content, and it is worth being able to test every
//! rule without a socket in the way.
//!
//! # Two rules this file exists to enforce
//!
//! **Connect to the address the broker returned, never re-resolve.** The whole
//! DNS-rebinding defence is that the address checked and the address connected
//! to are the same one. A convenience call like `TcpStream::connect(host)`
//! quietly re-resolves and undoes it.
//!
//! **A redirect is a new request, so it gets a new decision.** Following one on
//! the client's behalf without re-deciding lets any allowlisted host send a
//! guest anywhere — including back at the host's own network, which is the
//! usual way an allowlist is defeated.
//!
//! HTTPS is *not* implemented here. A hand-rolled TLS stack would be a bad idea
//! and a TLS crate is a dependency decision for the maintainer, so an `https`
//! target is refused with a reason that says so rather than being silently
//! downgraded to cleartext — which would be the genuinely dangerous outcome.

use std::io::{Read, Write};
use std::net::TcpStream;
use std::time::Duration;

use crate::app::NetworkMode;
use crate::egress::{decide, DenyReason, EgressDecision, Target};

/// Bounds on one outbound request.
#[derive(Debug, Clone)]
pub struct FetchLimits {
    pub connect_timeout: Duration,
    pub read_timeout: Duration,
    /// The largest response body accepted. Enforced *during* the read, so an
    /// oversized response is abandoned rather than buffered and then rejected.
    pub max_response_bytes: usize,
    /// How many redirects to follow. Each is re-decided.
    pub max_redirects: u32,
}

impl Default for FetchLimits {
    fn default() -> Self {
        FetchLimits {
            connect_timeout: Duration::from_secs(5),
            read_timeout: Duration::from_secs(10),
            max_response_bytes: 4 * 1024 * 1024,
            max_redirects: 3,
        }
    }
}

/// What a guest gets back.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FetchResponse {
    pub status: u16,
    pub body: String,
    /// How many bytes came back, before any truncation.
    pub bytes: usize,
}

/// Why a fetch did not happen or did not finish.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FetchError {
    /// The broker refused. Carries the operator-facing reason; the guest is
    /// told only that it was not permitted.
    Denied(DenyReason),
    /// TLS is not implemented. Named separately from `Denied` because it is a
    /// gap in this host, not a policy decision about the app.
    TlsUnsupported,
    ConnectFailed,
    Timeout,
    /// The response was not HTTP the host could read.
    MalformedResponse,
    TooManyRedirects,
}

impl FetchError {
    /// What the guest is told. Uniform, for the same reason the broker's denials
    /// are: a guest that could distinguish "connection refused" from "not
    /// allowlisted" has a port scanner.
    pub fn guest_message(&self) -> &'static str {
        match self {
            // A missing TLS stack is the host's gap and not something a guest
            // could scan with, so it is worth saying plainly — an author whose
            // https call silently fails would otherwise have no way to find out
            // why.
            FetchError::TlsUnsupported => "https is not supported by this host",
            _ => "the request was not permitted",
        }
    }

    pub fn audit_detail(&self) -> String {
        match self {
            FetchError::Denied(reason) => reason.audit_detail(),
            FetchError::TlsUnsupported => "https requested; no TLS stack".into(),
            FetchError::ConnectFailed => "connect failed".into(),
            FetchError::Timeout => "timed out".into(),
            FetchError::MalformedResponse => "malformed response".into(),
            FetchError::TooManyRedirects => "too many redirects".into(),
        }
    }
}

/// One record of an egress attempt, allowed or not.
///
/// Every decision produces one. An audit trail with only the denials in it
/// answers "what was blocked" and not "what did this app actually reach", and
/// the second question is the one asked after an incident.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EgressRecord {
    pub app: String,
    pub function: String,
    pub url: String,
    pub allowed: bool,
    /// The address actually connected to, when one was.
    pub addr: Option<std::net::SocketAddr>,
    pub detail: String,
    pub bytes: usize,
}

/// Perform a fetch on an app's behalf, re-deciding at every hop.
///
/// `record` is called once per hop, allowed or denied.
pub fn fetch(
    mode: &NetworkMode,
    url: &str,
    limits: &FetchLimits,
    mut record: impl FnMut(EgressRecord),
    app: &str,
    function: &str,
) -> Result<FetchResponse, FetchError> {
    let mut current = url.to_string();

    for _hop in 0..=limits.max_redirects {
        let decision = decide(mode, &current);

        let (addr, host) = match decision {
            EgressDecision::Allow { addr, host } => (addr, host),
            EgressDecision::Deny(reason) => {
                record(EgressRecord {
                    app: app.into(),
                    function: function.into(),
                    url: current.clone(),
                    allowed: false,
                    addr: None,
                    detail: reason.audit_detail(),
                    bytes: 0,
                });
                return Err(FetchError::Denied(reason));
            }
        };

        // Parsing succeeded inside `decide`, so this cannot fail — but the
        // scheme still has to be looked at, because `https` is allowed by the
        // broker and unimplemented here.
        let target = Target::parse(&current).ok_or(FetchError::MalformedResponse)?;
        if target.scheme == "https" {
            record(EgressRecord {
                app: app.into(),
                function: function.into(),
                url: current.clone(),
                allowed: false,
                addr: Some(addr),
                detail: "https requested; no TLS stack".into(),
                bytes: 0,
            });
            return Err(FetchError::TlsUnsupported);
        }

        let outcome = perform(addr, &host, &target.path, limits);

        match outcome {
            Ok(raw) => {
                record(EgressRecord {
                    app: app.into(),
                    function: function.into(),
                    url: current.clone(),
                    allowed: true,
                    addr: Some(addr),
                    detail: format!("{} {}", raw.status, raw.bytes),
                    bytes: raw.bytes,
                });

                // A redirect becomes a new request and goes back through the
                // broker at the top of the loop.
                if matches!(raw.status, 301 | 302 | 303 | 307 | 308) {
                    match raw.location {
                        Some(next) => {
                            current = resolve_redirect(&current, &next);
                            continue;
                        }
                        // A redirect status with no Location is not something
                        // to guess at.
                        None => return Err(FetchError::MalformedResponse),
                    }
                }

                return Ok(FetchResponse {
                    status: raw.status,
                    body: raw.body,
                    bytes: raw.bytes,
                });
            }
            Err(error) => {
                record(EgressRecord {
                    app: app.into(),
                    function: function.into(),
                    url: current.clone(),
                    allowed: true,
                    addr: Some(addr),
                    detail: error.audit_detail(),
                    bytes: 0,
                });
                return Err(error);
            }
        }
    }

    Err(FetchError::TooManyRedirects)
}

/// A response as it came off the wire, before redirect handling.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RawResponse {
    pub status: u16,
    pub body: String,
    pub bytes: usize,
    pub location: Option<String>,
}

/// Connect to `addr` — the address the broker checked — and speak HTTP/1.1.
///
/// Public so the HTTP mechanics can be tested against a real listener without
/// going through [`decide`]. That separation is deliberate rather than a
/// convenience: the broker blocks loopback, correctly, so a test that drove a
/// successful fetch end to end would have to weaken the very rule it depends
/// on. Policy and transport are different layers and are tested as such — the
/// rules in `egress`, the wire protocol here.
///
/// Calling this directly performs **no** policy check. Every path a guest can
/// reach goes through [`fetch`].
pub fn perform(
    addr: std::net::SocketAddr,
    host: &str,
    path: &str,
    limits: &FetchLimits,
) -> Result<RawResponse, FetchError> {
    // `connect_timeout` rather than `connect`: a plain connect to an address
    // that blackholes packets waits for the OS default, which is minutes, and
    // the caller is a guest invocation with a deadline.
    let mut stream = TcpStream::connect_timeout(&addr, limits.connect_timeout)
        .map_err(|_| FetchError::ConnectFailed)?;
    stream
        .set_read_timeout(Some(limits.read_timeout))
        .map_err(|_| FetchError::ConnectFailed)?;
    stream
        .set_write_timeout(Some(limits.read_timeout))
        .map_err(|_| FetchError::ConnectFailed)?;

    // The Host header carries the *name*, while the connection went to the
    // checked address. That is the point: virtual hosting still works and the
    // address cannot drift from the one that was approved.
    let request = format!(
        "GET {path} HTTP/1.1\r\nHost: {host}\r\nUser-Agent: elpian-host/1\r\n\
         Accept: */*\r\nConnection: close\r\n\r\n"
    );
    stream
        .write_all(request.as_bytes())
        .map_err(|_| FetchError::Timeout)?;
    stream.flush().map_err(|_| FetchError::Timeout)?;

    // Read the head and the body under *separate* bounds.
    //
    // Capping the whole stream at `max_response_bytes` was wrong: a small body
    // cap truncated the response mid-header, the `\r\n\r\n` was never found,
    // and a perfectly well-formed reply was reported malformed. The body cap is
    // about how much data a guest may pull in; the head cap is about not
    // letting a server stream headers forever. They are different limits.
    const MAX_HEAD_BYTES: usize = 64 * 1024;

    let mut raw = Vec::new();
    let mut chunk = [0u8; 8192];
    let mut head_end = None;

    loop {
        match stream.read(&mut chunk) {
            Ok(0) => break,
            Ok(n) => {
                raw.extend_from_slice(&chunk[..n]);

                if head_end.is_none() {
                    // Rescan from a little before the new bytes, so a terminator
                    // split across two reads is still found.
                    let from = raw.len().saturating_sub(n + 3);
                    if let Some(offset) = raw[from..].windows(4).position(|w| w == b"\r\n\r\n") {
                        head_end = Some(from + offset);
                    } else if raw.len() > MAX_HEAD_BYTES {
                        return Err(FetchError::MalformedResponse);
                    }
                }

                if let Some(split) = head_end {
                    if raw.len() - (split + 4) >= limits.max_response_bytes {
                        raw.truncate(split + 4 + limits.max_response_bytes);
                        break;
                    }
                }
            }
            Err(_) => break,
        }
    }

    let split = head_end.ok_or(FetchError::MalformedResponse)?;
    let head = String::from_utf8_lossy(&raw[..split]).to_string();
    let body = raw[split + 4..].to_vec();

    let status = head
        .lines()
        .next()
        .and_then(|line| line.split_whitespace().nth(1))
        .and_then(|code| code.parse().ok())
        .ok_or(FetchError::MalformedResponse)?;

    let location = head
        .lines()
        .skip(1)
        .filter_map(|line| line.split_once(':'))
        .find(|(name, _)| name.trim().eq_ignore_ascii_case("location"))
        .map(|(_, value)| value.trim().to_string());

    Ok(RawResponse {
        status,
        bytes: body.len(),
        body: String::from_utf8_lossy(&body).into_owned(),
        location,
    })
}

/// Resolve a `Location` against the URL it came from.
///
/// A relative redirect must stay on the origin it came from — resolving it
/// against nothing, or treating it as a bare host, would be a way to move the
/// request somewhere the broker never looked at.
fn resolve_redirect(from: &str, location: &str) -> String {
    if location.contains("://") {
        return location.to_string();
    }
    let Some(target) = Target::parse(from) else {
        return location.to_string();
    };
    let origin = format!("{}://{}:{}", target.scheme, target.host, target.port);
    if location.starts_with('/') {
        format!("{origin}{location}")
    } else {
        let base = target.path.rsplit_once('/').map(|(b, _)| b).unwrap_or("");
        format!("{origin}{base}/{location}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_relative_redirect_stays_on_its_origin() {
        assert_eq!(
            resolve_redirect("http://api.example.com/v1/a", "/v2/b"),
            "http://api.example.com:80/v2/b"
        );
        assert_eq!(
            resolve_redirect("http://api.example.com/v1/a", "b"),
            "http://api.example.com:80/v1/b"
        );
    }

    #[test]
    fn an_absolute_redirect_is_taken_as_written_then_re_decided() {
        // Taken as written here; the *decision* happens at the top of the fetch
        // loop, which is what stops it going somewhere it should not.
        assert_eq!(
            resolve_redirect("http://api.example.com/x", "http://evil.example/y"),
            "http://evil.example/y"
        );
    }

    #[test]
    fn https_is_refused_rather_than_downgraded() {
        let mut records = Vec::new();
        let result = fetch(
            &NetworkMode::Open,
            "https://example.com/",
            &FetchLimits::default(),
            |r| records.push(r),
            "app",
            "fn",
        );
        assert_eq!(result, Err(FetchError::TlsUnsupported));
        assert_eq!(records.len(), 1);
        assert!(!records[0].allowed);
    }

    #[test]
    fn a_closed_app_is_refused_and_the_attempt_is_recorded() {
        let mut records = Vec::new();
        let result = fetch(
            &NetworkMode::Closed,
            "http://example.com/",
            &FetchLimits::default(),
            |r| records.push(r),
            "sealed",
            "escape",
        );
        assert_eq!(result, Err(FetchError::Denied(DenyReason::ClosedCycle)));
        assert_eq!(records.len(), 1, "a denial is still an audit record");
        assert_eq!(records[0].app, "sealed");
        assert!(!records[0].allowed);
        assert!(records[0].detail.contains("closed"));
    }
}
