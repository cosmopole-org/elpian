//! The egress broker: the only way out.
//!
//! # Why a broker can be the boundary at all
//!
//! A guest's sole outward effect is `askHost`. There is no socket call and no
//! syscall in the instruction set, so every byte a mini app sends anywhere
//! passes through a host API the host implements. The broker is therefore not a
//! wrapper something could route around — it is the only door, and the
//! capability gate in front of it is checked inside the VM before the call is
//! even emitted.
//!
//! # The three modes
//!
//! * `closed` — the app does not hold [`Capability::Network`] at all. Its
//!   client half's only reachable peer is its own server functions, and those
//!   have no egress either. Nothing reaches the broker, because nothing can.
//! * `brokered` — egress only to an allowlist, checked here.
//! * `open` — unrestricted. First-party code and nothing else.
//!
//! # Client-side policy is advisory
//!
//! The device is told the app's mode so a well-behaved client can apply it too.
//! That is a courtesy, not the boundary: a device is under the user's control
//! and its policy can be edited. Every rule here is enforced again on the
//! server for every call that arrives, and the server's answer is the one that
//! counts.

use std::net::{IpAddr, SocketAddr, ToSocketAddrs};

use crate::app::NetworkMode;

/// Why the broker refused.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DenyReason {
    /// The app's mode grants no egress at all.
    ClosedCycle,
    /// A scheme other than http/https.
    UnsupportedScheme(String),
    /// The URL could not be parsed into host and path.
    MalformedUrl,
    /// The host is not on the app's allowlist.
    NotAllowlisted(String),
    /// The name did not resolve.
    UnresolvableHost(String),
    /// The name resolved to an address the host will not connect to —
    /// loopback, link-local, private, or a cloud metadata endpoint.
    BlockedAddress { host: String, addr: IpAddr },
    /// Too many redirects, or a redirect that left the allowlist.
    RedirectRefused,
    /// The app is over its egress byte budget.
    ByteBudgetExhausted,
}

impl DenyReason {
    /// What the *guest* is told. Deliberately coarse: a guest that could tell
    /// "not allowlisted" from "resolved to a private address" would have a port
    /// and address scanner built out of the error message.
    pub fn guest_message(&self) -> &'static str {
        "the request was not permitted"
    }

    /// What the operator's audit record says.
    pub fn audit_detail(&self) -> String {
        match self {
            DenyReason::ClosedCycle => "app is in a closed network posture".into(),
            DenyReason::UnsupportedScheme(s) => format!("unsupported scheme: {s}"),
            DenyReason::MalformedUrl => "malformed url".into(),
            DenyReason::NotAllowlisted(h) => format!("host not on the allowlist: {h}"),
            DenyReason::UnresolvableHost(h) => format!("could not resolve: {h}"),
            DenyReason::BlockedAddress { host, addr } => {
                format!("{host} resolved to a blocked address: {addr}")
            }
            DenyReason::RedirectRefused => "redirect refused".into(),
            DenyReason::ByteBudgetExhausted => "egress byte budget exhausted".into(),
        }
    }
}

/// What the broker decided, and — crucially — the address it decided *about*.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EgressDecision {
    /// Allowed. The connection must be made to exactly `addr`.
    ///
    /// Returning the resolved address rather than the hostname is the whole
    /// defence against DNS rebinding: if the caller re-resolved the name to
    /// connect, a name that answered with a public address during the check
    /// could answer with `127.0.0.1` a moment later, and the check would have
    /// been performed on an address that is never connected to.
    Allow {
        addr: SocketAddr,
        host: String,
    },
    Deny(DenyReason),
}

/// A parsed request target.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Target {
    pub scheme: String,
    pub host: String,
    pub port: u16,
    pub path: String,
}

impl Target {
    /// Parse a URL far enough to check it. Hand-rolled rather than pulling in a
    /// URL crate: what is needed is host, port and scheme, and a parser whose
    /// behaviour on the odd cases is *visible here* is worth more than one
    /// whose is not — the odd cases are the attack.
    ///
    /// Rejects any control character anywhere in the URL, before anything is
    /// split out of it.
    ///
    /// This is not tidiness. The path ends up interpolated into an HTTP request
    /// line (`fetch::perform`), so a CR or LF in it lets a guest write a second
    /// request onto the socket — with a method, headers and a body of its
    /// choosing, to an origin the broker approved. That turns a deliberately
    /// GET-only, header-fixed, body-less client into an arbitrary HTTP writer
    /// aimed at whatever the host can reach. The check lives *here*, in the one
    /// function every caller must go through, rather than at the point of use,
    /// so a future call site cannot skip it.
    pub fn parse(url: &str) -> Option<Target> {
        if url.bytes().any(|b| b < 0x21 || b == 0x7f) {
            return None;
        }
        let (scheme, rest) = url.split_once("://")?;
        let scheme = scheme.to_ascii_lowercase();

        // Strip userinfo. `http://allowed.example.com@evil.example/` has an
        // authority of `evil.example`; a check that read up to the first `.`
        // or matched on the prefix would get this exactly backwards.
        let rest = match rest.split_once('/') {
            Some((authority, path)) => {
                let authority = authority.rsplit('@').next()?;
                (authority.to_string(), format!("/{path}"))
            }
            None => {
                let authority = rest.rsplit('@').next()?;
                (authority.to_string(), "/".to_string())
            }
        };
        let (authority, path) = rest;

        let default_port = match scheme.as_str() {
            "http" => 80,
            "https" => 443,
            _ => 0,
        };

        // IPv6 literals are bracketed: `[::1]:8080`.
        let (host, port) = if let Some(stripped) = authority.strip_prefix('[') {
            let (inside, after) = stripped.split_once(']')?;
            let port = after
                .strip_prefix(':')
                .and_then(|p| p.parse().ok())
                .unwrap_or(default_port);
            (inside.to_string(), port)
        } else {
            match authority.rsplit_once(':') {
                Some((h, p)) => (h.to_string(), p.parse().ok()?),
                None => (authority.clone(), default_port),
            }
        };

        if host.is_empty() {
            return None;
        }
        Some(Target {
            scheme,
            host: host.to_ascii_lowercase(),
            port,
            path,
        })
    }
}

/// Whether an address is one the host will never connect to on a guest's behalf.
///
/// The list is not about privacy — it is about the fact that a server's
/// *network position* is a capability. A mini app that can make the host fetch
/// `http://169.254.169.254/` is asking the host to read its own cloud
/// credentials and hand them back, and a mini app that can reach `127.0.0.1` is
/// asking it to call services that trust localhost precisely because they
/// assumed nothing untrusted could.
pub fn is_blocked_address(addr: IpAddr) -> bool {
    match addr {
        IpAddr::V4(v4) => {
            v4.is_loopback()
                || v4.is_private()
                || v4.is_link_local()      // 169.254/16 — includes the metadata endpoint
                || v4.is_broadcast()
                || v4.is_documentation()
                || v4.is_unspecified()
                || v4.octets()[0] == 0
                // 100.64/10, carrier-grade NAT: routable-looking, not public.
                || (v4.octets()[0] == 100 && (64..=127).contains(&v4.octets()[1]))
                // 192.0.0/24, IETF protocol assignments.
                || (v4.octets()[0] == 192 && v4.octets()[1] == 0 && v4.octets()[2] == 0)
                // 198.18/15, benchmarking.
                || (v4.octets()[0] == 198 && (18..=19).contains(&v4.octets()[1]))
                // 224/4 multicast and 240/4 reserved.
                || v4.octets()[0] >= 224
        }
        IpAddr::V6(v6) => {
            v6.is_loopback()
                || v6.is_unspecified()
                || v6.is_multicast()
                // fc00::/7 unique-local.
                || (v6.segments()[0] & 0xfe00) == 0xfc00
                // fe80::/10 link-local.
                || (v6.segments()[0] & 0xffc0) == 0xfe80
                // An IPv4-mapped address is an IPv4 address wearing a hat;
                // checking only the v6 rules would wave ::ffff:127.0.0.1 through.
                || v6.to_ipv4_mapped().map(|v4| is_blocked_address(IpAddr::V4(v4)))
                    .unwrap_or(false)
        }
    }
}

/// Does `host` match an allowlist entry?
///
/// Exact match, or a `*.` prefix matching one or more leading labels. Matching
/// is on whole labels: `*.example.com` must not match `evil-example.com`, and
/// `example.com` must not match `notexample.com`.
pub fn allowlist_matches(allowlist: &[String], host: &str) -> bool {
    allowlist.iter().any(|entry| {
        let entry = entry.trim().to_ascii_lowercase();
        match entry.strip_prefix("*.") {
            Some(suffix) => {
                host != suffix
                    && host.len() > suffix.len()
                    && host.ends_with(&suffix)
                    && host.as_bytes()[host.len() - suffix.len() - 1] == b'.'
            }
            None => host == entry,
        }
    })
}

/// Decide one request.
///
/// The checks run in this order, and the order is deliberate: the cheapest and
/// most decisive first, so a closed app never pays for a DNS lookup and a
/// malformed URL never reaches the resolver.
///
/// 1. mode — a closed app is refused outright;
/// 2. parse — no host, no decision;
/// 3. scheme — http/https only;
/// 4. allowlist — on the name, before resolution;
/// 5. resolve — once;
/// 6. address — every answer checked, not just the first;
/// 7. the caller connects to **the address returned here**, never re-resolving.
pub fn decide(mode: &NetworkMode, url: &str) -> EgressDecision {
    let allowlist = match mode {
        NetworkMode::Closed => return EgressDecision::Deny(DenyReason::ClosedCycle),
        NetworkMode::Brokered { allowlist } => Some(allowlist),
        NetworkMode::Open => None,
    };

    let Some(target) = Target::parse(url) else {
        return EgressDecision::Deny(DenyReason::MalformedUrl);
    };
    if target.scheme != "http" && target.scheme != "https" {
        return EgressDecision::Deny(DenyReason::UnsupportedScheme(target.scheme));
    }
    if let Some(allowlist) = allowlist {
        if !allowlist_matches(allowlist, &target.host) {
            return EgressDecision::Deny(DenyReason::NotAllowlisted(target.host));
        }
    }

    let resolved = match (target.host.as_str(), target.port).to_socket_addrs() {
        Ok(addrs) => addrs.collect::<Vec<_>>(),
        Err(_) => return EgressDecision::Deny(DenyReason::UnresolvableHost(target.host)),
    };
    if resolved.is_empty() {
        return EgressDecision::Deny(DenyReason::UnresolvableHost(target.host));
    }

    // Every answer, not just the one that will be used. A name that resolves to
    // a public address *and* a private one is refused: picking the public one
    // would leave which address gets connected to up to resolver ordering.
    for addr in &resolved {
        if is_blocked_address(addr.ip()) {
            return EgressDecision::Deny(DenyReason::BlockedAddress {
                host: target.host,
                addr: addr.ip(),
            });
        }
    }

    EgressDecision::Allow {
        addr: resolved[0],
        host: target.host,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn brokered(hosts: &[&str]) -> NetworkMode {
        NetworkMode::Brokered {
            allowlist: hosts.iter().map(|h| h.to_string()).collect(),
        }
    }

    #[test]
    fn a_closed_app_is_refused_before_anything_is_parsed_or_resolved() {
        for url in ["http://example.com", "not a url at all", ""] {
            assert_eq!(
                decide(&NetworkMode::Closed, url),
                EgressDecision::Deny(DenyReason::ClosedCycle)
            );
        }
    }

    #[test]
    fn userinfo_cannot_disguise_the_real_authority() {
        // The authority here is `evil.example`, not `allowed.example`.
        let target = Target::parse("http://allowed.example@evil.example/path").unwrap();
        assert_eq!(target.host, "evil.example");

        assert_eq!(
            decide(
                &brokered(&["allowed.example"]),
                "http://allowed.example@evil.example/"
            ),
            EgressDecision::Deny(DenyReason::NotAllowlisted("evil.example".into()))
        );
    }

    #[test]
    fn allowlist_matching_is_on_whole_labels() {
        let list = vec!["example.com".to_string(), "*.api.example.com".to_string()];
        assert!(allowlist_matches(&list, "example.com"));
        assert!(allowlist_matches(&list, "v1.api.example.com"));
        assert!(allowlist_matches(&list, "a.b.api.example.com"));

        assert!(!allowlist_matches(&list, "notexample.com"));
        assert!(!allowlist_matches(&list, "example.com.evil.net"));
        assert!(
            !allowlist_matches(&list, "api.example.com"),
            "the bare suffix is not a subdomain of itself"
        );
        assert!(!allowlist_matches(&list, "evil-api.example.com"));
    }

    #[test]
    fn only_http_and_https_are_carried() {
        for url in [
            "file:///etc/passwd",
            "ftp://example.com/x",
            "gopher://example.com/",
            "data:text/plain,hi",
        ] {
            match decide(&NetworkMode::Open, url) {
                EgressDecision::Deny(DenyReason::UnsupportedScheme(_))
                | EgressDecision::Deny(DenyReason::MalformedUrl) => {}
                other => panic!("{url} produced {other:?}"),
            }
        }
    }

    #[test]
    fn addresses_the_host_must_never_reach_on_a_guests_behalf() {
        let blocked = [
            "127.0.0.1",        // loopback
            "127.1.2.3",        // the rest of 127/8
            "0.0.0.0",          // unspecified
            "10.1.2.3",         // private
            "172.16.0.1",       // private
            "192.168.1.1",      // private
            "169.254.169.254",  // the cloud metadata endpoint
            "100.64.0.1",       // carrier-grade NAT
            "198.18.0.1",       // benchmarking
            "224.0.0.1",        // multicast
            "::1",              // v6 loopback
            "fd00::1",          // v6 unique-local
            "fe80::1",          // v6 link-local
            "::ffff:127.0.0.1", // v4-mapped loopback wearing a v6 hat
            "::ffff:169.254.169.254",
        ];
        for raw in blocked {
            let addr: IpAddr = raw.parse().unwrap();
            assert!(is_blocked_address(addr), "{raw} should be blocked");
        }

        for raw in ["8.8.8.8", "1.1.1.1", "93.184.216.34", "2606:4700::1111"] {
            let addr: IpAddr = raw.parse().unwrap();
            assert!(!is_blocked_address(addr), "{raw} should be allowed");
        }
    }

    #[test]
    fn a_literal_private_address_is_refused_even_when_allowlisted() {
        // An allowlist entry cannot buy access to the host's own network: the
        // address check runs after it, not instead of it.
        let mode = brokered(&["127.0.0.1", "169.254.169.254"]);
        match decide(&mode, "http://127.0.0.1:8080/") {
            EgressDecision::Deny(DenyReason::BlockedAddress { .. }) => {}
            other => panic!("expected a blocked address, got {other:?}"),
        }
        match decide(&mode, "http://169.254.169.254/latest/meta-data/") {
            EgressDecision::Deny(DenyReason::BlockedAddress { .. }) => {}
            other => panic!("expected a blocked address, got {other:?}"),
        }
    }

    #[test]
    fn a_deny_tells_the_guest_nothing_it_could_scan_with() {
        // Every refusal reads identically to the guest; the detail is the
        // operator's. Otherwise the error message is a port scanner.
        let reasons = [
            DenyReason::ClosedCycle,
            DenyReason::NotAllowlisted("internal.corp".into()),
            DenyReason::BlockedAddress {
                host: "internal.corp".into(),
                addr: "10.0.0.1".parse().unwrap(),
            },
            DenyReason::UnresolvableHost("nope.invalid".into()),
        ];
        let messages: Vec<&str> = reasons.iter().map(|r| r.guest_message()).collect();
        assert!(
            messages.windows(2).all(|w| w[0] == w[1]),
            "guest-visible messages must be indistinguishable, got {messages:?}"
        );
        // The operator's version does distinguish them.
        assert!(reasons[2].audit_detail().contains("10.0.0.1"));
    }

    #[test]
    fn a_url_carrying_control_characters_does_not_parse() {
        // The path is interpolated into an HTTP request line. A CR or LF in it
        // would let a guest append a second, entirely attacker-written request
        // to an origin the broker approved.
        for url in [
            "http://api.example.com/x\r\nX-Injected: yes",
            "http://api.example.com/x\nGET /admin HTTP/1.1",
            "http://api.example.com/x\r\n\r\nPOST /internal HTTP/1.1",
            "http://api.example.com/pa th",
            "http://api.example.com/x\0y",
            "http://api.exa\rmple.com/",
            "http://api.example.com/x\x7f",
        ] {
            assert_eq!(Target::parse(url), None, "{url:?} should not parse");
            // And the decision function refuses it too, whatever the mode.
            assert_eq!(
                decide(&NetworkMode::Open, url),
                EgressDecision::Deny(DenyReason::MalformedUrl),
                "{url:?} should be denied"
            );
        }
    }

    #[test]
    fn an_ordinary_path_still_parses() {
        // The control-character check must not reject legitimate URLs.
        let target = Target::parse("http://api.example.com/v1/things?a=1&b=%20c").unwrap();
        assert_eq!(target.host, "api.example.com");
        assert_eq!(target.path, "/v1/things?a=1&b=%20c");
    }

    #[test]
    fn ipv6_literals_parse_with_their_port() {
        let target = Target::parse("http://[2606:4700::1111]:8443/x").unwrap();
        assert_eq!(target.host, "2606:4700::1111");
        assert_eq!(target.port, 8443);
        assert_eq!(target.path, "/x");
    }

    #[test]
    fn default_ports_follow_the_scheme() {
        assert_eq!(Target::parse("http://example.com/").unwrap().port, 80);
        assert_eq!(Target::parse("https://example.com/").unwrap().port, 443);
    }
}
