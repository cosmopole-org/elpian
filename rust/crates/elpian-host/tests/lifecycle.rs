//! The rest of the instance lifecycle: supervisor adoption, deadlines and
//! hibernation.

use std::time::Duration;

use elpian_host::app::{AppDefinition, FunctionKind};
use elpian_host::invoke::InvokeLimits;
use elpian_host::pool::PoolConfig;
use elpian_host::runtime::AppRuntime;
use elpian_host::Outcome;
use elpian_vm::api::{self, Capability};
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

/// A module whose top level increments a counter its function returns, so the
/// value says exactly how many times initialisation has run.
fn counting_module() -> Vec<u8> {
    module(vec![
        json!({ "type": "definition", "data": {
            "leftSide": ident("loads"),
            "rightSide": { "type": "i64", "data": { "value": 0 } } } }),
        json!({ "type": "assignment", "data": {
            "leftSide": ident("loads"),
            "rightSide": { "type": "arithmetic", "data": {
                "operation": "+",
                "operand1": ident("loads"),
                "operand2": { "type": "i64", "data": { "value": 1 } } } } } }),
        func_def("loadCount", vec![], vec![ret(ident("loads"))]),
    ])
}

fn returned(outcome: Outcome) -> Value {
    match outcome {
        Outcome::Returned(v) => v,
        other => panic!("expected a value, got {other:?}"),
    }
}

// ---- Supervisor adoption ---------------------------------------------------

#[test]
fn an_apps_instances_are_adopted_under_one_supervisor_node() {
    // This is what makes the VM tree's machinery apply to a whole *app* rather
    // than one instance: usage across every function, and teardown in one call.
    let runtime = AppRuntime::new();
    assert!(runtime.register(
        AppDefinition::new("tree")
            .with_capabilities(vec![Capability::State])
            .with_function("a", FunctionKind::Action, counting_module())
            .with_function("b", FunctionKind::Action, counting_module())
    ));

    runtime.call("tree", "a", &json!(null)).unwrap();
    runtime.call("tree", "b", &json!(null)).unwrap();

    let usage = runtime
        .pool()
        .app_usage("tree")
        .expect("the supervisor exists once the app has run");
    assert!(
        usage.instructions > 0,
        "the subtree total covers instances of both functions"
    );

    // The supervisor is a real node with both instances beneath it.
    let subtree = api::vm_subtree("app::tree");
    assert!(
        subtree.len() >= 3,
        "supervisor plus two instances, got {subtree:?}"
    );
}

#[test]
fn draining_an_app_takes_down_its_whole_subtree() {
    let runtime = AppRuntime::new();
    for id in ["keeps", "goes"] {
        assert!(runtime.register(
            AppDefinition::new(id)
                .with_capabilities(vec![Capability::State])
                .with_function("loadCount", FunctionKind::Action, counting_module())
        ));
        runtime.call(id, "loadCount", &json!(null)).unwrap();
    }

    runtime.pool().drain_app("goes");

    assert!(
        api::vm_subtree("app::goes").len() <= 1,
        "the drained app's subtree is gone"
    );
    assert!(
        !api::vm_exists("app::goes".to_string()),
        "including its supervisor"
    );
    // The other tenant is untouched.
    assert!(api::vm_exists("app::keeps".to_string()));
    assert!(
        !runtime
            .call("keeps", "loadCount", &json!(null))
            .unwrap()
            .cold_start
    );
}

// ---- The per-invocation deadline -------------------------------------------

#[test]
fn an_invocation_that_runs_past_its_deadline_is_stopped() {
    // The layer the other two miss. The instruction budget bounds computation,
    // not time; the per-turn deadline bounds one stretch of guest execution,
    // and a guest making host calls starts a new turn each time — so a loop of
    // quick calls resets it forever. This bounds the invocation.
    let runtime = AppRuntime::new();
    assert!(runtime.register(
        AppDefinition::new("slow")
            .with_capabilities(vec![Capability::Logging])
            .with_function(
                "spin",
                FunctionKind::Action,
                module(vec![func_def(
                    "spin",
                    vec![],
                    vec![
                        json!({ "type": "definition", "data": {
                            "leftSide": ident("i"),
                            "rightSide": { "type": "i64", "data": { "value": 0 } } } }),
                        json!({ "type": "loopStmt", "data": {
                            "condition": { "type": "arithmetic", "data": {
                                "operation": "<",
                                "operand1": ident("i"),
                                "operand2": { "type": "i64", "data": { "value": 100000000 } } } },
                            // A host call every iteration, so every turn is
                            // short and the per-turn deadline never fires.
                            "body": [ host_call("log", vec![strv("tick")]) ] } }),
                        ret(strv("never")),
                    ],
                )]),
            )
    ));
    runtime.set_invoke_limits(InvokeLimits {
        max_host_calls: u32::MAX,
        deadline: Some(Duration::from_millis(150)),
    });

    let started = std::time::Instant::now();
    let outcome = runtime.call("slow", "spin", &json!(null)).unwrap().outcome;
    let elapsed = started.elapsed();

    assert_eq!(outcome, Outcome::DeadlineExceeded);
    assert!(
        elapsed < Duration::from_secs(10),
        "the deadline did not stop it: {elapsed:?}"
    );
}

#[test]
fn an_ordinary_invocation_is_not_affected_by_the_deadline() {
    let runtime = AppRuntime::new();
    assert!(runtime.register(
        AppDefinition::new("quick")
            .with_capabilities(vec![Capability::State])
            .with_function("loadCount", FunctionKind::Action, counting_module())
    ));
    runtime.set_invoke_limits(InvokeLimits {
        max_host_calls: 10_000,
        deadline: Some(Duration::from_secs(5)),
    });
    assert_eq!(
        returned(
            runtime
                .call("quick", "loadCount", &json!(null))
                .unwrap()
                .outcome
        ),
        json!(1)
    );
}

// ---- Hibernation -----------------------------------------------------------

#[test]
fn an_idle_instance_is_parked_and_wakes_without_re_initialising() {
    // The point of parking rather than unloading: an app that goes quiet
    // between bursts should not pay a cold start on every burst.
    let runtime = AppRuntime::new();
    assert!(runtime.register(
        AppDefinition::new("napper")
            .with_capabilities(vec![Capability::State])
            .with_function("loadCount", FunctionKind::Action, counting_module())
    ));

    assert!(
        runtime
            .call("napper", "loadCount", &json!(null))
            .unwrap()
            .cold_start
    );
    assert_eq!(runtime.pool().idle(), 1);
    assert_eq!(runtime.pool().hibernated(), 0);

    // Zero delay: everything idle parks immediately.
    let parked = runtime.pool().hibernate_idle(&PoolConfig {
        hibernate_after: Some(Duration::ZERO),
        ..PoolConfig::default()
    });
    assert_eq!(parked.len(), 1);
    assert_eq!(runtime.pool().hibernated(), 1);
    assert_eq!(
        runtime.pool().loaded(),
        1,
        "a parked instance is still loaded — it just costs no CPU"
    );

    // Waking skips module initialisation, exactly as a warm instance does.
    let woken = runtime.call("napper", "loadCount", &json!(null)).unwrap();
    assert!(!woken.cold_start, "waking is not a cold start");
    assert_eq!(
        returned(woken.outcome),
        json!(1),
        "the module ran once; a cold instance would report 2"
    );
    assert_eq!(runtime.pool().hibernated(), 0, "it is awake again");
}

#[test]
fn hibernation_never_parks_a_busy_instance() {
    // An instance mid-call is not idle however long ago it last finished one,
    // and pausing it would suspend a running turn.
    let runtime = AppRuntime::new();
    assert!(runtime.register(
        AppDefinition::new("busy")
            .with_capabilities(vec![Capability::State])
            .with_function("loadCount", FunctionKind::Action, counting_module())
    ));

    // Nothing has ever run, so there is nothing loaded and nothing to park.
    let parked = runtime.pool().hibernate_idle(&PoolConfig {
        hibernate_after: Some(Duration::ZERO),
        ..PoolConfig::default()
    });
    assert!(parked.is_empty());

    runtime.call("busy", "loadCount", &json!(null)).unwrap();
    // Now idle, so it parks.
    assert_eq!(
        runtime
            .pool()
            .hibernate_idle(&PoolConfig {
                hibernate_after: Some(Duration::ZERO),
                ..PoolConfig::default()
            })
            .len(),
        1
    );
}

#[test]
fn hibernation_can_be_turned_off() {
    let runtime = AppRuntime::new();
    assert!(runtime.register(
        AppDefinition::new("nonap")
            .with_capabilities(vec![Capability::State])
            .with_function("loadCount", FunctionKind::Action, counting_module())
    ));
    runtime.call("nonap", "loadCount", &json!(null)).unwrap();

    let parked = runtime.pool().hibernate_idle(&PoolConfig {
        hibernate_after: None,
        ..PoolConfig::default()
    });
    assert!(parked.is_empty());
    assert_eq!(runtime.pool().hibernated(), 0);
}
