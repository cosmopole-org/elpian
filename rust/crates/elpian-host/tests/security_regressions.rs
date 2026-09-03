//! Regressions for the findings of the security review.
//!
//! Each of these failed before the fix. They are kept together because they
//! share a theme: every one is a case where an untrusted app's *own* data — a
//! URL it chose, an id it declared — reached somewhere that treated it as
//! trusted.

use std::sync::Arc;

use elpian_host::app::{valid_app_id, AppDefinition, FunctionKind, NetworkMode};
use elpian_host::egress::{decide, DenyReason, EgressDecision, Target};
use elpian_host::runtime::AppRuntime;
use serde_json::{json, Value};

fn strv(s: &str) -> Value {
    json!({ "type": "string", "data": { "value": s } })
}
fn ret(value: Value) -> Value {
    json!({ "type": "returnOperation", "data": { "value": value } })
}
fn func_def(name: &str, params: Vec<&str>, body: Vec<Value>) -> Value {
    json!({ "type": "functionDefinition", "data": { "name": name, "params": params, "body": body } })
}
fn module(body: Vec<Value>) -> Vec<u8> {
    elpian_vm::sdk::compiler::compile_ast(json!({ "type": "program", "body": body }), 0)
}

// ---- 1. Request splitting through the egress path -------------------------

/// A CR or LF in a URL's path reached the outbound HTTP request line verbatim,
/// so a guest could append a second, entirely attacker-written request — with
/// its own method, headers and body — to an origin the broker had approved.
/// That turned a deliberately GET-only, header-fixed, body-less client into an
/// arbitrary HTTP writer aimed at whatever the host could reach.
#[test]
fn a_url_cannot_smuggle_a_second_request_into_the_wire_format() {
    let brokered = NetworkMode::Brokered {
        allowlist: vec!["api.example.com".into()],
    };

    let attacks = [
        "http://api.example.com/x\r\nX-Injected: yes",
        "http://api.example.com/ping HTTP/1.1\r\nHost: api.example.com\r\n\r\nPOST /admin HTTP/1.1",
        "http://api.example.com/x\n\nGET /internal HTTP/1.1",
        "http://api.example.com/x\r\n\r\nevil",
    ];

    for url in attacks {
        // Refused by the parser, so no call site can reach the wire with it...
        assert_eq!(Target::parse(url), None, "{url:?} parsed");
        // ...and refused by the decision function in every mode.
        for mode in [&brokered, &NetworkMode::Open] {
            assert_eq!(
                decide(mode, url),
                EgressDecision::Deny(DenyReason::MalformedUrl),
                "{url:?} was allowed in {} mode",
                mode.as_str()
            );
        }
    }

    // The equivalent well-formed request is still allowed to proceed to the
    // address check, so the fix did not simply refuse everything.
    assert!(!matches!(
        decide(&brokered, "http://api.example.com/ping"),
        EgressDecision::Deny(DenyReason::MalformedUrl)
    ));
}

// ---- 2. An app id that escapes its directory ------------------------------

/// An app's id becomes a directory name joined onto the host's data root. An id
/// of `..` therefore rooted the app at its neighbours' *parent*, and `AppFs`'s
/// confinement — which is correct — then enforced that wrong boundary: the app
/// could read and write every other tenant's files.
#[test]
fn an_app_whose_id_would_escape_its_directory_is_not_registered() {
    let runtime = AppRuntime::with_data_root(std::env::temp_dir().join("elpian-sec-test"));

    for id in ["..", ".", "../elsewhere", "a/b", ".hidden", ""] {
        let app = AppDefinition::new(id).with_function(
            "read",
            FunctionKind::Action,
            module(vec![func_def("read", vec![], vec![ret(strv("ok"))])]),
        );
        assert!(
            !runtime.register(app),
            "an app with id {id:?} was registered"
        );
        assert!(!runtime.app_ids().iter().any(|a| a == id));
    }

    // An ordinary id still works.
    let ok = AppDefinition::new("notes").with_function(
        "read",
        FunctionKind::Action,
        module(vec![func_def("read", vec![], vec![ret(strv("ok"))])]),
    );
    assert!(runtime.register(ok));
    assert!(runtime.call("notes", "read", &json!(null)).is_ok());
}

#[test]
fn the_id_rule_rejects_what_it_should_and_nothing_more() {
    for bad in ["..", ".", "a/b", "a\\b", "/x", "UPPER", "with space", ""] {
        assert!(!valid_app_id(bad), "{bad:?} should be refused");
    }
    for good in ["notes", "my-app", "my_app", "app.v2", "a1"] {
        assert!(valid_app_id(good), "{good:?} should be accepted");
    }
}

// ---- 4. Randomness is not shared between tenants --------------------------

/// The `random.*` stream was one process-global state shared by every app.
/// Because the output is the top bits of an invertible multiply of that state,
/// two draws recover it — so one app could predict every value the whole host
/// produced next, including another tenant's ids and tokens. The generator is
/// now per-invocation and OS-seeded.
#[test]
fn two_apps_do_not_draw_from_the_same_random_stream() {
    let runtime = AppRuntime::new();
    let draw = module(vec![func_def(
        "draw",
        vec![],
        vec![ret(json!({ "type": "host_call", "data": {
            "name": "random.next", "args": [] } }))],
    )]);

    for id in ["alpha", "beta"] {
        assert!(runtime.register(
            AppDefinition::new(id)
                .with_capabilities(vec![elpian_vm::api::Capability::Randomness])
                .with_function("draw", FunctionKind::Action, draw.clone())
        ));
    }

    let mut values = Vec::new();
    for _ in 0..8 {
        for id in ["alpha", "beta"] {
            if let elpian_host::Outcome::Returned(v) =
                runtime.call(id, "draw", &json!(null)).unwrap().outcome
            {
                values.push(v.as_f64().expect("a float"));
            }
        }
    }

    // Every draw is in range, and they are not all the same value — which is
    // what a fixed or zero-seeded stream would produce.
    assert!(values.iter().all(|v| *v >= 0.0 && *v < 1.0));
    let distinct: std::collections::BTreeSet<u64> = values.iter().map(|v| v.to_bits()).collect();
    assert!(
        distinct.len() >= values.len() - 1,
        "draws repeated: {distinct:?} distinct of {}",
        values.len()
    );
}

/// Two runtimes started independently must not produce the same sequence — the
/// old global was seeded once per *process*, so everything sharing it shared a
/// sequence.
#[test]
fn independently_created_services_do_not_replay_one_anothers_sequence() {
    fn first_draws(app: &str) -> Vec<u64> {
        let runtime = AppRuntime::new();
        assert!(runtime.register(
            AppDefinition::new(app)
                .with_capabilities(vec![elpian_vm::api::Capability::Randomness])
                .with_function(
                    "draw",
                    FunctionKind::Action,
                    module(vec![func_def(
                        "draw",
                        vec![],
                        vec![ret(json!({ "type": "host_call", "data": {
                            "name": "random.next", "args": [] } }))],
                    )]),
                )
        ));
        (0..4)
            .filter_map(
                |_| match runtime.call(app, "draw", &json!(null)).unwrap().outcome {
                    elpian_host::Outcome::Returned(v) => v.as_f64().map(f64::to_bits),
                    _ => None,
                },
            )
            .collect()
    }

    let a = first_draws("one");
    let b = first_draws("two");
    assert_eq!(a.len(), 4);
    assert_ne!(
        a, b,
        "two independent runtimes produced identical sequences"
    );
}

/// `random.bytes` must not be a re-encoding of the float generator.
#[test]
fn random_bytes_returns_the_requested_count_and_varies() {
    let runtime = AppRuntime::new();
    assert!(runtime.register(
        AppDefinition::new("bytes")
            .with_capabilities(vec![elpian_vm::api::Capability::Randomness])
            .with_function(
                "get",
                FunctionKind::Action,
                module(vec![func_def(
                    "get",
                    vec![],
                    vec![ret(json!({ "type": "host_call", "data": {
                        "name": "random.bytes",
                        "args": [{ "type": "i64", "data": { "value": 32 } }] } }))],
                )]),
            )
    ));

    let mut seen = std::collections::BTreeSet::new();
    for _ in 0..4 {
        if let elpian_host::Outcome::Returned(v) =
            runtime.call("bytes", "get", &json!(null)).unwrap().outcome
        {
            let bytes: Vec<u64> = v
                .as_array()
                .unwrap()
                .iter()
                .filter_map(Value::as_u64)
                .collect();
            assert_eq!(bytes.len(), 32);
            seen.insert(bytes);
        }
    }
    assert!(seen.len() > 1, "four draws produced the same 32 bytes");
    let _ = Arc::new(());
}
