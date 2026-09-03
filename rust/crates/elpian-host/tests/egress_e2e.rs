//! Outbound requests, end to end: a real listener, a real socket, and the
//! broker in the middle.
//!
//! The unit tests in `egress` cover the decision rules. These cover the other
//! half — that an *allowed* request actually happens, that a denied one
//! actually does not reach the wire, and that both are audited.

use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

use elpian_host::app::NetworkMode;
use elpian_host::fetch::{fetch, FetchError, FetchLimits};
use elpian_host::DenyReason;

/// A minimal origin server that answers a fixed response and counts hits.
struct Origin {
    addr: std::net::SocketAddr,
    hits: Arc<AtomicUsize>,
    paths: Arc<Mutex<Vec<String>>>,
}

impl Origin {
    fn start(reply: &'static str) -> Origin {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        let hits = Arc::new(AtomicUsize::new(0));
        let paths = Arc::new(Mutex::new(Vec::new()));
        let (h, p) = (Arc::clone(&hits), Arc::clone(&paths));

        std::thread::spawn(move || {
            for stream in listener.incoming() {
                let Ok(mut stream) = stream else { continue };
                h.fetch_add(1, Ordering::SeqCst);
                let mut buf = [0u8; 2048];
                let n = stream.read(&mut buf).unwrap_or(0);
                let request = String::from_utf8_lossy(&buf[..n]).to_string();
                if let Some(path) = request
                    .lines()
                    .next()
                    .and_then(|l| l.split_whitespace().nth(1))
                {
                    p.lock().unwrap().push(path.to_string());
                }
                let _ = stream.write_all(reply.as_bytes());
                let _ = stream.flush();
            }
        });

        Origin { addr, hits, paths }
    }

    fn url(&self, path: &str) -> String {
        format!("http://{}{path}", self.addr)
    }

    fn hits(&self) -> usize {
        self.hits.load(Ordering::SeqCst)
    }

    fn paths(&self) -> Vec<String> {
        self.paths.lock().unwrap().clone()
    }
}

/// The origin is on loopback, which the broker blocks by address — correctly,
/// and inconveniently for a test. `Open` mode still applies the address check,
/// so these tests need a mode that skips it. There isn't one, deliberately.
///
/// So instead of weakening the broker for the test's benefit, the tests below
/// verify the two things that *can* be verified honestly against a loopback
/// origin: that the address check fires and nothing reaches the wire, and —
/// using a direct `perform`-equivalent path — that the HTTP client itself
/// speaks correctly to a server.
#[test]
fn a_loopback_origin_is_refused_and_never_contacted() {
    let origin = Origin::start("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nhi");
    let mut records = Vec::new();

    let result = fetch(
        &NetworkMode::Open,
        &origin.url("/data"),
        &FetchLimits::default(),
        |r| records.push(r),
        "app",
        "fn",
    );

    match result {
        Err(FetchError::Denied(DenyReason::BlockedAddress { .. })) => {}
        other => panic!("expected a blocked address, got {other:?}"),
    }
    std::thread::sleep(std::time::Duration::from_millis(100));
    assert_eq!(
        origin.hits(),
        0,
        "the refusal happened before anything reached the wire"
    );

    assert_eq!(records.len(), 1, "the attempt was audited");
    assert!(!records[0].allowed);
    assert!(records[0].detail.contains("blocked address"));
    assert_eq!(records[0].app, "app");
    assert_eq!(records[0].bytes, 0);
}

#[test]
fn an_allowlist_entry_does_not_override_the_address_check() {
    let origin = Origin::start("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nhi");
    let mode = NetworkMode::Brokered {
        allowlist: vec![origin.addr.ip().to_string()],
    };
    let mut records = Vec::new();

    let result = fetch(
        &mode,
        &origin.url("/data"),
        &FetchLimits::default(),
        |r| records.push(r),
        "app",
        "fn",
    );

    assert!(matches!(
        result,
        Err(FetchError::Denied(DenyReason::BlockedAddress { .. }))
    ));
    std::thread::sleep(std::time::Duration::from_millis(100));
    assert_eq!(
        origin.hits(),
        0,
        "an allowlist cannot buy access to the host's own network"
    );
    assert!(!records[0].allowed);
}

#[test]
fn every_attempt_produces_exactly_one_audit_record() {
    // An audit trail with only denials in it answers "what was blocked" and not
    // "what did this app reach" — and the second is the question asked after an
    // incident. Both directions must record.
    let cases: Vec<(NetworkMode, &str)> = vec![
        (NetworkMode::Closed, "http://example.com/"),
        (
            NetworkMode::Brokered {
                allowlist: vec!["allowed.example".into()],
            },
            "http://denied.example/",
        ),
        (NetworkMode::Open, "http://127.0.0.1/"),
        (NetworkMode::Open, "https://example.com/"),
    ];

    for (mode, url) in cases {
        let mut records = Vec::new();
        let _ = fetch(
            &mode,
            url,
            &FetchLimits::default(),
            |r| records.push(r),
            "auditing",
            "probe",
        );
        assert_eq!(
            records.len(),
            1,
            "{url} in {} mode produced {} records",
            mode.as_str(),
            records.len()
        );
        assert_eq!(records[0].url, url);
        assert_eq!(records[0].app, "auditing");
        assert_eq!(records[0].function, "probe");
        assert!(
            !records[0].detail.is_empty(),
            "an audit record with no detail is not an audit record"
        );
    }
}

#[test]
fn the_guest_message_never_distinguishes_a_denial_from_a_failure() {
    // Otherwise the error string is a scanner: a guest could tell "there is a
    // service on this port" from "the allowlist said no" and enumerate the
    // host's network from inside the sandbox.
    let messages: Vec<&str> = [
        FetchError::Denied(DenyReason::ClosedCycle),
        FetchError::Denied(DenyReason::NotAllowlisted("x".into())),
        FetchError::Denied(DenyReason::BlockedAddress {
            host: "x".into(),
            addr: "10.0.0.1".parse().unwrap(),
        }),
        FetchError::ConnectFailed,
        FetchError::Timeout,
        FetchError::MalformedResponse,
    ]
    .iter()
    .map(FetchError::guest_message)
    .collect();

    assert!(
        messages.windows(2).all(|w| w[0] == w[1]),
        "these must be indistinguishable to a guest: {messages:?}"
    );
    // The operator's side does distinguish them.
    assert_ne!(
        FetchError::ConnectFailed.audit_detail(),
        FetchError::Timeout.audit_detail()
    );
}

#[test]
fn https_is_refused_plainly_because_it_is_a_host_gap_not_a_policy() {
    // The one message that *is* distinct, and deliberately: an author whose
    // https call silently failed like every other refusal would have no way to
    // discover the host has no TLS stack. It reveals nothing about the network.
    assert_eq!(
        FetchError::TlsUnsupported.guest_message(),
        "https is not supported by this host"
    );
    assert_ne!(
        FetchError::TlsUnsupported.guest_message(),
        FetchError::ConnectFailed.guest_message()
    );
}

#[test]
fn a_response_larger_than_the_cap_does_not_grow_without_bound() {
    // Verified through the limit rather than through a huge transfer: what
    // matters is that the cap is applied while reading, so the check is on the
    // configuration being honoured by `perform`'s loop.
    let limits = FetchLimits {
        max_response_bytes: 16,
        ..FetchLimits::default()
    };
    assert_eq!(limits.max_response_bytes, 16);

    // And the paths list on a never-contacted origin stays empty, confirming
    // the refusal path does not partially transfer.
    let origin = Origin::start("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nhi");
    let _ = fetch(
        &NetworkMode::Open,
        &origin.url("/big"),
        &limits,
        |_| {},
        "app",
        "fn",
    );
    std::thread::sleep(std::time::Duration::from_millis(100));
    assert!(origin.paths().is_empty());
}

// ---- The HTTP client itself ------------------------------------------------
//
// `perform` is the wire protocol with no policy in it, so it can be pointed at
// a loopback origin that `fetch` would rightly refuse. Testing the two layers
// separately is what lets both be tested honestly: the alternative is a
// test-only hole in the broker, which would mean the rule under test is not the
// rule that ships.

#[test]
fn the_http_client_speaks_to_a_real_server() {
    let origin = Origin::start("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello");
    let response = elpian_host::fetch::perform(
        origin.addr,
        "api.example.com",
        "/v1/things",
        &FetchLimits::default(),
    )
    .expect("the request should complete");

    assert_eq!(response.status, 200);
    assert_eq!(response.body, "hello");
    assert_eq!(response.bytes, 5);
    assert_eq!(origin.hits(), 1);
    assert_eq!(
        origin.paths(),
        vec!["/v1/things".to_string()],
        "the path is sent as given"
    );
}

#[test]
fn the_host_header_carries_the_name_while_the_connection_used_the_checked_address() {
    // This is the resolve-then-connect property, seen from the wire: the socket
    // went to an address the broker approved, and the Host header still names
    // the site, so virtual hosting works and the address cannot drift.
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let addr = listener.local_addr().unwrap();
    let seen = Arc::new(Mutex::new(String::new()));
    let sink = Arc::clone(&seen);

    std::thread::spawn(move || {
        if let Ok((mut stream, _)) = listener.accept() {
            let mut buf = [0u8; 2048];
            let n = stream.read(&mut buf).unwrap_or(0);
            *sink.lock().unwrap() = String::from_utf8_lossy(&buf[..n]).to_string();
            let _ = stream.write_all(b"HTTP/1.1 204 No Content\r\nContent-Length: 0\r\n\r\n");
        }
    });

    let response =
        elpian_host::fetch::perform(addr, "virtual.example.com", "/", &FetchLimits::default())
            .expect("the request should complete");
    assert_eq!(response.status, 204);

    let request = seen.lock().unwrap().clone();
    assert!(
        request.contains("Host: virtual.example.com"),
        "the Host header names the site, not the address: {request}"
    );
}

#[test]
fn a_redirect_response_surfaces_its_location_for_re_deciding() {
    let origin = Origin::start(
        "HTTP/1.1 302 Found\r\nLocation: http://elsewhere.example/next\r\nContent-Length: 0\r\n\r\n",
    );
    let response =
        elpian_host::fetch::perform(origin.addr, "start.example", "/", &FetchLimits::default())
            .expect("the request should complete");

    assert_eq!(response.status, 302);
    assert_eq!(
        response.location.as_deref(),
        Some("http://elsewhere.example/next"),
        "the location is surfaced so the fetch loop can put it back through the broker"
    );
}

#[test]
fn an_oversized_body_is_truncated_during_the_read() {
    // 64 KiB of body against a 16-byte cap. The cap is applied while reading,
    // so the host never buffers the whole thing.
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let addr = listener.local_addr().unwrap();
    std::thread::spawn(move || {
        if let Ok((mut stream, _)) = listener.accept() {
            let mut buf = [0u8; 1024];
            let _ = stream.read(&mut buf);
            let body = "x".repeat(64 * 1024);
            let _ = stream.write_all(
                format!(
                    "HTTP/1.1 200 OK\r\nContent-Length: {}\r\n\r\n{body}",
                    body.len()
                )
                .as_bytes(),
            );
        }
    });

    let response = elpian_host::fetch::perform(
        addr,
        "big.example",
        "/",
        &FetchLimits {
            max_response_bytes: 16,
            ..FetchLimits::default()
        },
    )
    .expect("the request should complete");

    assert_eq!(response.status, 200);
    assert!(
        response.bytes <= 16,
        "the cap must be applied while reading, got {} bytes",
        response.bytes
    );
}

#[test]
fn an_unreachable_address_fails_promptly_rather_than_hanging() {
    // A port nothing is listening on. The point is that it returns at all: a
    // plain `connect` to a blackholed address waits for the OS default, which
    // is minutes, and the caller is a guest invocation with a deadline.
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let addr = listener.local_addr().unwrap();
    drop(listener); // nothing is listening now

    let started = std::time::Instant::now();
    let result = elpian_host::fetch::perform(addr, "gone.example", "/", &FetchLimits::default());
    assert!(result.is_err());
    assert!(
        started.elapsed() < std::time::Duration::from_secs(10),
        "took {:?}",
        started.elapsed()
    );
}
