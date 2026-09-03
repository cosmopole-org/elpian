//! An app is a set of server functions with one governance posture, and one of
//! its functions can call another — but only its own.

use elpian_host::app::{AppDefinition, FunctionKind, NetworkMode};
use elpian_host::runtime::{AppRuntime, CallError};
use elpian_host::Outcome;
use elpian_vm::api::Capability;
use serde_json::{json, Value};

// ---- AST helpers -----------------------------------------------------------

fn ident(name: &str) -> Value {
    json!({ "type": "identifier", "data": { "name": name } })
}
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

/// Compile one function's module to bytecode, the way the CLI will.
fn module(body: Vec<Value>) -> Vec<u8> {
    elpian_vm::sdk::compiler::compile_ast(json!({ "type": "program", "body": body }), 0)
}

fn returned(outcome: Outcome) -> Value {
    match outcome {
        Outcome::Returned(v) => v,
        other => panic!("expected a returned value, got {other:?}"),
    }
}

// ---- Tests -----------------------------------------------------------------

#[test]
fn an_app_runs_its_own_functions() {
    let runtime = AppRuntime::new();
    runtime.register(
        AppDefinition::new("notes")
            .with_capabilities(vec![Capability::State])
            .with_function(
                "save",
                FunctionKind::Action,
                module(vec![func_def(
                    "save",
                    vec!["v"],
                    vec![ret(host_call("kv.set", vec![strv("n"), ident("v")]))],
                )]),
            )
            .with_function(
                "load",
                FunctionKind::Action,
                module(vec![func_def(
                    "load",
                    vec![],
                    vec![ret(host_call("kv.get", vec![strv("n")]))],
                )]),
            ),
    );

    assert_eq!(
        returned(runtime.call("notes", "save", &json!("hi")).unwrap().outcome),
        json!(true)
    );
    // A different function, a different instance, the same app state.
    assert_eq!(
        returned(runtime.call("notes", "load", &json!(null)).unwrap().outcome),
        json!("hi")
    );
}

#[test]
fn one_function_can_call_another_in_the_same_app() {
    let runtime = AppRuntime::new();
    runtime.register(
        AppDefinition::new("chain")
            .with_capabilities(vec![Capability::ServerCall])
            .with_function(
                "outer",
                FunctionKind::Action,
                module(vec![func_def(
                    "outer",
                    vec![],
                    vec![ret(host_call(
                        "server.call",
                        vec![strv("inner"), strv("payload")],
                    ))],
                )]),
            )
            .with_function(
                "inner",
                FunctionKind::Action,
                module(vec![func_def("inner", vec!["x"], vec![ret(ident("x"))])]),
            ),
    );

    assert_eq!(
        returned(
            runtime
                .call("chain", "outer", &json!(null))
                .unwrap()
                .outcome
        ),
        json!("payload"),
        "the outer function received the inner function's return value"
    );
}

#[test]
fn a_function_cannot_reach_another_apps_functions() {
    let runtime = AppRuntime::new();
    // Two apps, each with a function called `secret`.
    runtime.register(
        AppDefinition::new("attacker")
            .with_capabilities(vec![Capability::ServerCall])
            .with_function(
                "probe",
                FunctionKind::Action,
                module(vec![func_def(
                    "probe",
                    vec![],
                    // Every spelling a guest might try. None of them can work,
                    // because the app is not a parameter of `server.call` at
                    // all — the host fixed it before the guest started.
                    vec![ret(host_call(
                        "server.call",
                        vec![strv("victim/secret"), strv("x")],
                    ))],
                )]),
            ),
    );
    runtime.register(AppDefinition::new("victim").with_function(
        "secret",
        FunctionKind::Action,
        module(vec![func_def(
            "secret",
            vec![],
            vec![ret(strv("the victim's data"))],
        )]),
    ));

    let value = returned(
        runtime
            .call("attacker", "probe", &json!(null))
            .unwrap()
            .outcome,
    );
    assert_ne!(value, json!("the victim's data"));
    assert_eq!(
        value,
        json!({ "error": "no such function: victim/secret" }),
        "the name resolves inside the calling app and finds nothing"
    );
}

#[test]
fn calling_a_component_as_an_action_is_refused() {
    let runtime = AppRuntime::new();
    runtime.register(AppDefinition::new("kinds").with_function(
        "List",
        FunctionKind::Component,
        module(vec![func_def("List", vec![], vec![ret(strv("ui"))])]),
    ));

    match runtime.call("kinds", "List", &json!(null)) {
        Err(CallError::WrongKind {
            expected, actual, ..
        }) => {
            assert_eq!(expected, "action");
            assert_eq!(actual, "component");
        }
        other => panic!("expected a kind mismatch, got {other:?}"),
    }
    // The same function through the right door works.
    assert_eq!(
        returned(
            runtime
                .render("kinds", "List", &json!(null))
                .unwrap()
                .outcome
        ),
        json!("ui")
    );
}

#[test]
fn an_unknown_app_or_function_is_reported_without_running_anything() {
    let runtime = AppRuntime::new();
    runtime.register(AppDefinition::new("known").with_function(
        "there",
        FunctionKind::Action,
        module(vec![func_def("there", vec![], vec![ret(strv("ok"))])]),
    ));

    assert_eq!(
        runtime.call("missing", "there", &json!(null)).err(),
        Some(CallError::UnknownApp("missing".into()))
    );
    assert_eq!(
        runtime.call("known", "missing", &json!(null)).err(),
        Some(CallError::UnknownFunction {
            app: "known".into(),
            function: "missing".into()
        })
    );
}

#[test]
fn a_closed_app_does_not_hold_the_network_capability_even_if_granted() {
    let closed = AppDefinition::new("shut")
        .with_capabilities(vec![Capability::Network, Capability::State])
        .with_network(NetworkMode::Closed);
    assert!(
        !closed
            .effective_capabilities()
            .contains(&Capability::Network),
        "a closed app's egress is absent, not merely blocked downstream"
    );
    assert!(closed.effective_capabilities().contains(&Capability::State));

    let brokered = closed.clone().with_network(NetworkMode::Brokered {
        allowlist: vec!["api.example.com".into()],
    });
    assert!(brokered
        .effective_capabilities()
        .contains(&Capability::Network));
}

#[test]
fn a_grant_the_server_posture_forbids_is_dropped() {
    let app = AppDefinition::new("greedy").with_capabilities(vec![
        Capability::Dom,
        Capability::VmManage,
        Capability::Render,
        Capability::State,
    ]);
    let effective = app.effective_capabilities();
    assert_eq!(effective, vec![Capability::State]);
}

#[test]
fn a_recursive_function_is_stopped_by_the_call_depth_bound() {
    let runtime = AppRuntime::new();
    runtime.register(
        AppDefinition::new("loop")
            .with_capabilities(vec![Capability::ServerCall])
            .with_function(
                "again",
                FunctionKind::Action,
                module(vec![func_def(
                    "again",
                    vec![],
                    vec![ret(host_call(
                        "server.call",
                        vec![strv("again"), strv("x")],
                    ))],
                )]),
            ),
    );

    // It must terminate at all — the assertion is that this returns.
    let value = returned(runtime.call("loop", "again", &json!(null)).unwrap().outcome);
    assert_eq!(value, json!({ "error": "call depth exceeded" }));
}
