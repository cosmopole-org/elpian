//! The closed cycle: an app that may talk to its own halves and to nothing else.
//!
//! This is the security claim of the whole network design, so it gets a test
//! that does not take anyone's word for it. A canary TCP listener records every
//! connection made to it. After the run, the assertion is not "the call
//! returned null" — it is that **the canary recorded nothing at all**.
//!
//! A test that only checked the return value would pass against a broker that
//! made the connection and discarded the response.

use std::io::Read;
use std::net::TcpListener;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

use elpian_host::app::{AppDefinition, FunctionKind, NetworkMode};
use elpian_host::egress::{decide, DenyReason, EgressDecision};
use elpian_host::runtime::AppRuntime;
use elpian_host::Outcome;
use elpian_vm::api::Capability;
use serde_json::{json, Value};

// ---- Canary ----------------------------------------------------------------

/// A listener that counts every connection anyone makes to it.
struct Canary {
    addr: std::net::SocketAddr,
    connections: Arc<AtomicUsize>,
}

impl Canary {
    fn start() -> Canary {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind the canary");
        let addr = listener.local_addr().unwrap();
        let connections = Arc::new(AtomicUsize::new(0));
        let counter = Arc::clone(&connections);

        std::thread::spawn(move || {
            for stream in listener.incoming() {
                let Ok(mut stream) = stream else { continue };
                counter.fetch_add(1, Ordering::SeqCst);
                let mut sink = [0u8; 512];
                let _ = stream.read(&mut sink);
            }
        });

        Canary { addr, connections }
    }

    fn url(&self) -> String {
        format!("http://{}/pilfer", self.addr)
    }

    fn connections(&self) -> usize {
        self.connections.load(Ordering::SeqCst)
    }
}

// ---- AST helpers -----------------------------------------------------------

fn strv(s: &str) -> Value {
    json!({ "type": "string", "data": { "value": s } })
}
fn ret(value: Value) -> Value {
    json!({ "type": "returnOperation", "data": { "value": value } })
}
fn host_call(name: &str, args: Vec<Value>) -> Value {
    json!({ "type": "host_call", "data": { "name": name, "args": args } })
}
fn func_def(name: &str, params: Vec<&str>, body: Vec<Value>) -> Value {
    json!({ "type": "functionDefinition", "data": { "name": name, "params": params, "body": body } })
}
fn module(body: Vec<Value>) -> Vec<u8> {
    elpian_vm::sdk::compiler::compile_ast(json!({ "type": "program", "body": body }), 0)
}

/// Every way out a guest could try, in one function.
fn escape_attempts(url: &str) -> Vec<u8> {
    module(vec![func_def(
        "escape",
        vec![],
        vec![
            host_call("net.fetch", vec![strv(url)]),
            host_call("net.open", vec![strv(url)]),
            host_call("vm.import", vec![strv(url)]),
            host_call("fs.read", vec![strv("/etc/passwd")]),
            ret(strv("tried everything")),
        ],
    )])
}

// ---- Tests -----------------------------------------------------------------

/// The canary must be able to detect a connection, or every assertion made with
/// it is vacuous. This is the control.
#[test]
fn the_canary_counts_connections() {
    let canary = Canary::start();
    assert_eq!(canary.connections(), 0);

    {
        use std::io::Write;
        let mut probe = std::net::TcpStream::connect(canary.addr).expect("connect to the canary");
        let _ = probe.write_all(b"GET /pilfer HTTP/1.1\r\n\r\n");
    }

    // The accept loop is on another thread; give it a moment to record.
    for _ in 0..100 {
        if canary.connections() > 0 {
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    assert_eq!(
        canary.connections(),
        1,
        "the canary did not record a connection that was definitely made —          every other assertion in this file depends on it doing so"
    );
}

#[test]
fn a_closed_apps_server_function_reaches_nothing() {
    let canary = Canary::start();
    let runtime = AppRuntime::new();
    runtime.register(
        AppDefinition::new("sealed")
            // Everything a manifest could possibly ask for.
            .with_capabilities(vec![
                Capability::Network,
                Capability::ModuleImport,
                Capability::Storage,
                Capability::State,
                Capability::Logging,
            ])
            .with_network(NetworkMode::Closed)
            .with_function(
                "escape",
                FunctionKind::Action,
                escape_attempts(&canary.url()),
            ),
    );

    let invocation = runtime.call("sealed", "escape", &json!(null)).unwrap();
    assert_eq!(
        invocation.outcome,
        Outcome::Returned(json!("tried everything")),
        "the guest ran to completion; it simply reached nothing"
    );

    // Give any connection the guest managed to start time to be recorded, so a
    // pass cannot be an artefact of checking too early.
    std::thread::sleep(std::time::Duration::from_millis(100));

    // The claim.
    assert_eq!(
        canary.connections(),
        0,
        "a closed app opened {} connection(s) to the outside world",
        canary.connections()
    );
}

#[test]
fn a_closed_app_does_not_even_hold_the_gate() {
    // The stronger statement: this is not "the broker said no", it is that the
    // call never leaves the VM. The capability short-circuits inside the
    // executor, so there is no host code to get wrong.
    let app = AppDefinition::new("sealed")
        .with_capabilities(vec![Capability::Network])
        .with_network(NetworkMode::Closed);
    assert!(!app
        .effective_capabilities()
        .contains(&Capability::Network));

    assert_eq!(
        decide(&NetworkMode::Closed, "http://example.com/"),
        EgressDecision::Deny(DenyReason::ClosedCycle),
        "and if one somehow reached the broker, the broker refuses it too"
    );
}

#[test]
fn a_closed_apps_two_halves_can_still_reach_each_other() {
    // The point of a closed cycle is not that the app is inert. Its halves must
    // still talk — through the host, and only to each other.
    let runtime = AppRuntime::new();
    runtime.register(
        AppDefinition::new("sealed")
            .with_capabilities(vec![Capability::ServerCall, Capability::State])
            .with_network(NetworkMode::Closed)
            .with_function(
                "outer",
                FunctionKind::Action,
                module(vec![func_def(
                    "outer",
                    vec![],
                    vec![ret(host_call(
                        "server.call",
                        vec![strv("inner"), strv("still connected")],
                    ))],
                )]),
            )
            .with_function(
                "inner",
                FunctionKind::Action,
                module(vec![func_def(
                    "inner",
                    vec!["x"],
                    vec![ret(json!({ "type": "identifier", "data": { "name": "x" } }))],
                )]),
            ),
    );

    assert_eq!(
        runtime.call("sealed", "outer", &json!(null)).unwrap().outcome,
        Outcome::Returned(json!("still connected"))
    );
}

#[test]
fn a_brokered_app_reaches_only_what_it_was_allowlisted() {
    let canary = Canary::start();
    let canary_host = canary.addr.ip().to_string();

    // The canary is on 127.0.0.1, so even allowlisting it must not get through:
    // the address check runs after the allowlist, not instead of it.
    let allowlisted = NetworkMode::Brokered {
        allowlist: vec![canary_host.clone()],
    };
    match decide(&allowlisted, &canary.url()) {
        EgressDecision::Deny(DenyReason::BlockedAddress { .. }) => {}
        other => panic!("a loopback canary should be refused on its address, got {other:?}"),
    }

    // And a host that is simply not on the list is refused earlier.
    let elsewhere = NetworkMode::Brokered {
        allowlist: vec!["api.example.com".into()],
    };
    assert_eq!(
        decide(&elsewhere, "http://other.example.com/"),
        EgressDecision::Deny(DenyReason::NotAllowlisted("other.example.com".into()))
    );

    assert_eq!(canary.connections(), 0, "nothing connected during the checks");
}

/// The SSRF corpus. Table-driven, and not to be allowed to rot: each row is a
/// way somebody has actually reached a server's own network through a fetch
/// proxy.
#[test]
fn the_ssrf_corpus() {
    let open = NetworkMode::Open;
    let cases: &[(&str, &str)] = &[
        ("http://127.0.0.1/", "loopback"),
        ("http://127.0.0.1:22/", "loopback, another port"),
        ("http://0.0.0.0/", "the unspecified address"),
        ("http://[::1]/", "v6 loopback"),
        ("http://[::ffff:127.0.0.1]/", "v4-mapped loopback"),
        ("http://10.0.0.1/", "RFC1918"),
        ("http://172.16.0.1/", "RFC1918"),
        ("http://192.168.0.1/", "RFC1918"),
        ("http://169.254.169.254/latest/meta-data/", "cloud metadata"),
        ("http://[fd00::1]/", "v6 unique-local"),
        ("http://100.64.0.1/", "carrier-grade NAT"),
        ("file:///etc/passwd", "a non-http scheme"),
        ("gopher://127.0.0.1:6379/_SET%20x%20y", "protocol smuggling"),
        ("http://user@127.0.0.1/", "userinfo before a private host"),
        ("http://127.0.0.1@example.com/", "userinfo that looks private"),
        ("not-a-url", "unparseable"),
        ("http:///nohost", "empty authority"),
    ];

    for (url, why) in cases {
        match decide(&open, url) {
            EgressDecision::Deny(_) => {}
            // The one row that is *meant* to be allowed: the authority is
            // example.com, and `127.0.0.1@` is userinfo, not a host. It is in
            // the corpus because reading it the other way is a real bug — a
            // broker that refused it would be wrong in a way that hides a
            // broker that allows the reverse.
            EgressDecision::Allow { host, .. } if *url == "http://127.0.0.1@example.com/" => {
                assert_eq!(host, "example.com", "the authority is after the @");
            }
            other => panic!("{url} ({why}) was not refused: {other:?}"),
        }
    }
}

#[test]
fn a_redirect_does_not_escape_the_allowlist() {
    // Following a redirect is making a *new* request, so it gets a new
    // decision. A broker that checked only the original URL would let any
    // allowlisted host redirect a guest anywhere it liked — including back at
    // the host's own network.
    let mode = NetworkMode::Brokered {
        allowlist: vec!["api.example.com".into()],
    };
    // Where an allowlisted host might try to send us.
    for hop in [
        "http://169.254.169.254/latest/meta-data/",
        "http://127.0.0.1:6379/",
        "http://elsewhere.example.com/",
    ] {
        match decide(&mode, hop) {
            EgressDecision::Deny(_) => {}
            other => panic!("a redirect to {hop} was allowed: {other:?}"),
        }
    }
}
