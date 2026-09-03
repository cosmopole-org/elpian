//! Loading function instances on demand, and unloading them when nothing needs
//! them — requirement 3, and the thing every call was paying for before.

use std::time::Duration;

use elpian_host::app::{AppDefinition, FunctionKind};
use elpian_host::pool::PoolConfig;
use elpian_host::runtime::AppRuntime;
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
fn returned(outcome: Outcome) -> Value {
    match outcome {
        Outcome::Returned(v) => v,
        other => panic!("expected a returned value, got {other:?}"),
    }
}

/// A module whose *top level* increments a counter, and whose function returns
/// it. The returned number is therefore how many times module initialisation
/// has run for this instance — a direct, unambiguous read on warm reuse.
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

fn app_with(name: &str, stateless: bool) -> std::sync::Arc<AppRuntime> {
    let runtime = AppRuntime::new();
    let mut def =
        AppDefinition::new(name).with_function("loadCount", FunctionKind::Action, counting_module());
    if stateless {
        def = def.stateless("loadCount");
    }
    runtime.register(def);
    runtime
}

#[test]
fn a_warm_instance_does_not_re_run_module_initialisation() {
    let runtime = app_with("warm", false);

    let first = runtime.call("warm", "loadCount", &json!(null)).unwrap();
    assert!(first.cold_start, "the first call must load the module");
    assert_eq!(returned(first.outcome), json!(1));

    let second = runtime.call("warm", "loadCount", &json!(null)).unwrap();
    assert!(!second.cold_start, "the second must reuse the instance");
    assert_eq!(
        returned(second.outcome),
        json!(1),
        "the module ran once; a cold instance would report 2"
    );

    let third = runtime.call("warm", "loadCount", &json!(null)).unwrap();
    assert!(!third.cold_start);
    assert_eq!(returned(third.outcome), json!(1));
}

#[test]
fn a_stateless_function_gets_a_fresh_instance_every_call() {
    let runtime = app_with("fresh", true);

    for _ in 0..3 {
        let call = runtime.call("fresh", "loadCount", &json!(null)).unwrap();
        assert!(call.cold_start, "a stateless function is always cold");
        assert_eq!(
            returned(call.outcome),
            json!(1),
            "each call sees a module that has initialised exactly once — its own"
        );
    }
    assert_eq!(
        runtime.pool().loaded(),
        0,
        "and nothing is left loaded afterwards"
    );
}

#[test]
fn an_idle_instance_is_unloaded() {
    let runtime = app_with("evictable", false);
    runtime.call("evictable", "loadCount", &json!(null)).unwrap();
    assert_eq!(runtime.pool().loaded(), 1);
    assert_eq!(runtime.pool().idle(), 1, "it went back to the pool warm");

    // A zero TTL makes everything idle immediately.
    let unloaded = runtime.pool().evict_idle_with(&PoolConfig {
        idle_ttl: Duration::ZERO,
        ..PoolConfig::default()
    });
    assert_eq!(unloaded.len(), 1);
    assert_eq!(runtime.pool().loaded(), 0, "nothing needed it, so it went");

    // And the next call loads it again, from cold.
    let after = runtime.call("evictable", "loadCount", &json!(null)).unwrap();
    assert!(after.cold_start);
}

#[test]
fn draining_an_app_unloads_only_that_apps_instances() {
    let runtime = AppRuntime::new();
    for id in ["keep", "drop"] {
        runtime.register(AppDefinition::new(id).with_function(
            "loadCount",
            FunctionKind::Action,
            counting_module(),
        ));
        runtime.call(id, "loadCount", &json!(null)).unwrap();
    }
    assert_eq!(runtime.pool().loaded(), 2);

    let unloaded = runtime.pool().drain_app("drop");
    assert_eq!(unloaded.len(), 1);
    assert_eq!(runtime.pool().loaded(), 1);

    // The surviving app's instance is still warm.
    assert!(!runtime.call("keep", "loadCount", &json!(null)).unwrap().cold_start);
}

#[test]
fn an_instance_that_trapped_is_not_handed_to_the_next_caller() {
    let runtime = AppRuntime::new();
    runtime.register(AppDefinition::new("faulty").with_function(
        "boom",
        FunctionKind::Action,
        module(vec![func_def(
            "boom",
            vec![],
            vec![ret(json!({ "type": "arithmetic", "data": {
                "operation": "-",
                "operand1": { "type": "object", "data": { "value": {} } },
                "operand2": { "type": "i64", "data": { "value": 1 } } } }))],
        )]),
    ));

    runtime.call("faulty", "boom", &json!(null)).unwrap();
    assert_eq!(
        runtime.pool().loaded(),
        0,
        "whatever left the instance in that state is still in its module scope; \
         reusing it would spread one call's failure across every later one"
    );

    let next = runtime.call("faulty", "boom", &json!(null)).unwrap();
    assert!(next.cold_start, "the next caller gets a clean instance");
}

#[test]
fn cost_meters_accumulate_across_invocations() {
    let runtime = AppRuntime::new();
    runtime.register(
        AppDefinition::new("metered")
            .with_capabilities(vec![Capability::State])
            .with_function(
                "work",
                FunctionKind::Action,
                module(vec![func_def(
                    "work",
                    vec![],
                    vec![
                        host_call("kv.set", vec![strv("k"), strv("some stored value")]),
                        ret(strv("done")),
                    ],
                )]),
            ),
    );

    let before = runtime.meters("metered");
    assert_eq!(before.invocations, 0);

    for _ in 0..3 {
        runtime.call("metered", "work", &json!(null)).unwrap();
    }

    let after = runtime.meters("metered");
    assert_eq!(after.invocations, 3);
    assert_eq!(after.cold_starts, 1, "only the first call loaded a module");
    assert!(after.instructions > 0, "guest instructions were counted");
    assert!(after.peak_memory_bytes > 0, "peak memory was observed");
    assert!(
        after.storage_bytes > 0,
        "the app's stored state is reported as a level, read when asked"
    );
}

#[test]
fn meters_are_per_app() {
    let runtime = AppRuntime::new();
    for id in ["one", "two"] {
        runtime.register(AppDefinition::new(id).with_function(
            "loadCount",
            FunctionKind::Action,
            counting_module(),
        ));
    }
    runtime.call("one", "loadCount", &json!(null)).unwrap();
    runtime.call("one", "loadCount", &json!(null)).unwrap();
    runtime.call("two", "loadCount", &json!(null)).unwrap();

    assert_eq!(runtime.meters("one").invocations, 2);
    assert_eq!(runtime.meters("two").invocations, 1);
    assert_eq!(
        runtime.meters("never-called").invocations,
        0,
        "an app that never ran reports zero rather than failing"
    );
}
