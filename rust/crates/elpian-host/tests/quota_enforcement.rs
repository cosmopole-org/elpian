//! Quotas, applied to real invocations.
//!
//! The unit tests in `quota` cover the ladder's arithmetic. These check the
//! part that only shows up when it is wired in: that the decision happens
//! *before* guest code runs, that nested calls are not refused halfway through,
//! and that an operator's suspension actually stops an app.

use std::sync::Arc;

use elpian_host::app::{AppDefinition, FunctionKind};
use elpian_host::quota::Quota;
use elpian_host::runtime::{AppRuntime, CallError};
use elpian_host::Outcome;
use elpian_vm::api::Capability;
use serde_json::{json, Value};

fn strv(s: &str) -> Value {
    json!({ "type": "string", "data": { "value": s } })
}
fn ident(n: &str) -> Value {
    json!({ "type": "identifier", "data": { "name": n } })
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

fn app(id: &str) -> Arc<AppRuntime> {
    let runtime = AppRuntime::new();
    runtime.register(
        AppDefinition::new(id)
            .with_capabilities(vec![Capability::State, Capability::ServerCall])
            .with_function(
                "write",
                FunctionKind::Action,
                module(vec![func_def(
                    "write",
                    vec![],
                    vec![ret(host_call("kv.set", vec![strv("k"), strv("v")]))],
                )]),
            )
            .with_function(
                "Read",
                FunctionKind::Component,
                module(vec![func_def(
                    "Read",
                    vec![],
                    vec![ret(json!({ "type": "object", "data": { "value": {
                        "component": { "type": "object", "data": { "value": {
                            "type": strv("Text") } } }
                    } } }))],
                )]),
            )
            .with_function(
                "outer",
                FunctionKind::Action,
                module(vec![func_def(
                    "outer",
                    vec![],
                    vec![ret(host_call(
                        "server.call",
                        vec![strv("inner"), strv("x")],
                    ))],
                )]),
            )
            .with_function(
                "inner",
                FunctionKind::Action,
                module(vec![func_def("inner", vec!["x"], vec![ret(ident("x"))])]),
            ),
    );
    runtime
}

#[test]
fn an_app_with_no_quota_runs_freely() {
    let runtime = app("free");
    for _ in 0..20 {
        assert!(runtime.call("free", "write", &json!(null)).is_ok());
    }
}

#[test]
fn an_app_far_over_budget_is_refused_before_any_guest_code_runs() {
    let runtime = app("drained");
    // Spend first, then tighten. A refused call does not increment the meter —
    // correctly, since it never ran — so an app cannot climb the ladder by
    // being refused, and a test cannot drive it there that way either.
    for _ in 0..10 {
        let _ = runtime.call("drained", "write", &json!(null));
    }
    let spent = runtime.meters("drained").invocations;
    runtime.set_quota(
        "drained",
        Quota {
            max_invocations: Some(2),
            ..Quota::default()
        },
    );

    // Now well past 1.5x. Every further call is refused.
    for _ in 0..5 {
        match runtime.call("drained", "write", &json!(null)) {
            Err(CallError::OverQuota { .. }) => {}
            other => panic!("expected a quota refusal, got {other:?}"),
        }
    }
    assert_eq!(
        runtime.meters("drained").invocations,
        spent,
        "a refused call must not have run — the meter did not move"
    );
}

#[test]
fn strangling_refuses_writes_while_still_serving_reads() {
    let runtime = app("strangled");
    // Spend 5 invocations, then set a budget of 4 — putting usage at 1.25x,
    // which is the Strangle band (>= 1.0, < 1.5).
    for _ in 0..5 {
        runtime.call("strangled", "write", &json!(null)).unwrap();
    }
    runtime.set_quota(
        "strangled",
        Quota {
            max_invocations: Some(4),
            ..Quota::default()
        },
    );

    assert!(
        matches!(
            runtime.call("strangled", "write", &json!(null)),
            Err(CallError::OverQuota { .. })
        ),
        "an action must be refused"
    );
    assert!(
        runtime.render("strangled", "Read", &json!(null)).is_ok(),
        "a component must still render — the app stays readable"
    );
}

#[test]
fn a_nested_call_is_not_refused_halfway_through() {
    // The outer call was already admitted. Refusing the inner one would leave
    // the app's state half-written with no way for the guest to recover — its
    // subset has no try/catch.
    let runtime = app("nested");
    // Usage well past any small budget, but a budget generous enough that the
    // *outer* call is admitted. The nested call then runs while usage is high —
    // which is the property under test: depth 0 is checked, deeper is not.
    for _ in 0..10 {
        runtime.call("nested", "write", &json!(null)).unwrap();
    }
    runtime.set_quota(
        "nested",
        Quota {
            max_invocations: Some(1_000_000),
            ..Quota::default()
        },
    );
    let outcome = runtime
        .call("nested", "outer", &json!(null))
        .unwrap()
        .outcome;
    assert_eq!(outcome, Outcome::Returned(json!("x")));
}

#[test]
fn an_operator_suspension_stops_an_app_regardless_of_usage() {
    let runtime = app("suspended");
    assert!(runtime.call("suspended", "write", &json!(null)).is_ok());

    runtime.quotas().suspend("suspended");
    assert!(matches!(
        runtime.call("suspended", "write", &json!(null)),
        Err(CallError::OverQuota { .. })
    ));
    assert!(
        matches!(
            runtime.render("suspended", "Read", &json!(null)),
            Err(CallError::OverQuota { .. })
        ),
        "a suspension stops reads too — it is not a strangle"
    );

    runtime.quotas().resume("suspended");
    assert!(runtime.call("suspended", "write", &json!(null)).is_ok());
}

#[test]
fn a_quota_refusal_names_the_axis_for_the_operator_and_not_the_caller() {
    let runtime = app("axis");
    for _ in 0..10 {
        runtime.call("axis", "write", &json!(null)).unwrap();
    }
    runtime.set_quota(
        "axis",
        Quota {
            max_invocations: Some(1),
            max_instructions: Some(u64::MAX),
            ..Quota::default()
        },
    );

    match runtime.call("axis", "write", &json!(null)) {
        Err(error @ CallError::OverQuota { .. }) => {
            let CallError::OverQuota { axis, stage } = &error else {
                unreachable!()
            };
            assert_eq!(axis, "invocations", "the operator learns which budget");
            assert!(!stage.is_empty());
            assert_eq!(
                error.client_message(),
                "this app is over its quota",
                "the caller learns only that it is over budget"
            );
        }
        other => panic!("expected a quota refusal, got {other:?}"),
    }
}
