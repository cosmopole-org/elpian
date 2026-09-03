//! Server components: returned payloads, caching, and revalidation.

use elpian_host::app::{AppDefinition, FunctionKind};
use elpian_host::runtime::AppRuntime;
use elpian_host::Outcome;
use elpian_vm::api::Capability;
use serde_json::{json, Value};

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
fn returned(outcome: Outcome) -> Value {
    match outcome {
        Outcome::Returned(v) => v,
        other => panic!("expected a returned value, got {other:?}"),
    }
}

/// A component whose payload embeds the current value of `kv["n"]`, so a test
/// can tell a fresh render from a cached one by what it contains.
fn counting_component() -> Vec<u8> {
    module(vec![func_def(
        "Panel",
        vec![],
        vec![
            json!({ "type": "definition", "data": {
                "leftSide": { "type": "identifier", "data": { "name": "seen" } },
                "rightSide": host_call("kv.get", vec![strv("n")]) } }),
            ret(json!({ "type": "object", "data": { "value": {
                "component": { "type": "object", "data": { "value": {
                    "type": strv("text"),
                    "text": { "type": "identifier", "data": { "name": "seen" } } } } },
                "revalidate": { "type": "object", "data": { "value": {
                    "tags": { "type": "array", "data": { "value": [strv("panel")] } } } } }
            } } })),
        ],
    )])
}

fn app() -> std::sync::Arc<AppRuntime> {
    let runtime = AppRuntime::new();
    runtime.register(
        AppDefinition::new("dash")
            .with_capabilities(vec![Capability::State])
            .with_function("Panel", FunctionKind::Component, counting_component())
            .with_function(
                "bump",
                FunctionKind::Action,
                module(vec![func_def(
                    "bump",
                    vec!["v"],
                    vec![
                        host_call(
                            "kv.set",
                            vec![
                                strv("n"),
                                json!({ "type": "identifier", "data": { "name": "v" } }),
                            ],
                        ),
                        ret(host_call("cache.revalidate", vec![strv("panel")])),
                    ],
                )]),
            ),
    );
    runtime
}

#[test]
fn a_component_returns_a_payload_rather_than_rendering() {
    let runtime = app();
    runtime.call("dash", "bump", &json!("first")).unwrap();

    let payload = returned(
        runtime
            .render("dash", "Panel", &json!(null))
            .unwrap()
            .outcome,
    );
    assert_eq!(payload["component"]["type"], json!("text"));
    assert_eq!(payload["component"]["text"], json!("first"));
}

#[test]
fn a_second_render_is_served_from_the_cache_without_running_the_guest() {
    let runtime = app();
    runtime.call("dash", "bump", &json!("cached")).unwrap();

    let first = runtime.render("dash", "Panel", &json!(null)).unwrap();
    assert!(!first.cache_hit, "the first render must run the component");

    let second = runtime.render("dash", "Panel", &json!(null)).unwrap();
    assert!(second.cache_hit, "the second must not");
    assert_eq!(
        returned(second.outcome)["component"]["text"],
        json!("cached")
    );
}

#[test]
fn an_action_revalidating_a_tag_makes_the_next_render_fresh() {
    let runtime = app();
    runtime.call("dash", "bump", &json!("before")).unwrap();
    let cached = returned(
        runtime
            .render("dash", "Panel", &json!(null))
            .unwrap()
            .outcome,
    );
    assert_eq!(cached["component"]["text"], json!("before"));

    // The state changed *and* the action said so.
    let bumped = runtime.call("dash", "bump", &json!("after")).unwrap();
    assert_eq!(
        returned(bumped.outcome),
        json!(1),
        "one cached render was invalidated"
    );

    let fresh = runtime.render("dash", "Panel", &json!(null)).unwrap();
    assert!(!fresh.cache_hit, "the entry was dropped, so this ran again");
    assert_eq!(
        returned(fresh.outcome)["component"]["text"],
        json!("after"),
        "and it saw the new state"
    );
}

#[test]
fn different_arguments_are_different_renders() {
    let runtime = AppRuntime::new();
    runtime.register(AppDefinition::new("pager").with_function(
        "Page",
        FunctionKind::Component,
        module(vec![func_def(
            "Page",
            vec!["n"],
            vec![ret(json!({ "type": "object", "data": { "value": {
                "component": { "type": "object", "data": { "value": {
                    "type": strv("text"),
                    "text": { "type": "identifier", "data": { "name": "n" } } } } },
                "revalidate": { "type": "object", "data": { "value": {
                    "tags": { "type": "array", "data": { "value": [strv("pages")] } } } } }
            } } }))],
        )]),
    ));

    let one = returned(
        runtime
            .render("pager", "Page", &json!("one"))
            .unwrap()
            .outcome,
    );
    let two = runtime.render("pager", "Page", &json!("two")).unwrap();

    assert_eq!(one["component"]["text"], json!("one"));
    assert!(
        !two.cache_hit,
        "different arguments must not share a cache entry"
    );
    assert_eq!(returned(two.outcome)["component"]["text"], json!("two"));
}

#[test]
fn a_component_that_asked_for_no_caching_runs_every_time() {
    let runtime = AppRuntime::new();
    runtime.register(AppDefinition::new("live").with_function(
        "Now",
        FunctionKind::Component,
        module(vec![func_def(
            "Now",
            vec![],
            // No `revalidate` stanza at all.
            vec![ret(json!({ "type": "object", "data": { "value": {
                "component": { "type": "object", "data": { "value": {
                    "type": strv("text") } } }
            } } }))],
        )]),
    ));

    assert!(
        !runtime
            .render("live", "Now", &json!(null))
            .unwrap()
            .cache_hit
    );
    assert!(
        !runtime
            .render("live", "Now", &json!(null))
            .unwrap()
            .cache_hit,
        "a component that named neither a tag nor a TTL is never cached"
    );
}

#[test]
fn one_app_cannot_invalidate_another_apps_cache() {
    let runtime = AppRuntime::new();
    // Both apps use the tag "shared".
    for id in ["alpha", "beta"] {
        runtime.register(
            AppDefinition::new(id)
                .with_capabilities(vec![Capability::State])
                .with_function(
                    "Panel",
                    FunctionKind::Component,
                    module(vec![func_def(
                        "Panel",
                        vec![],
                        vec![ret(json!({ "type": "object", "data": { "value": {
                            "component": { "type": "object", "data": { "value": {
                                "type": strv("text") } } },
                            "revalidate": { "type": "object", "data": { "value": {
                                "tags": { "type": "array", "data": { "value": [strv("shared")] } } } } }
                        } } }))],
                    )]),
                )
                .with_function(
                    "clear",
                    FunctionKind::Action,
                    module(vec![func_def(
                        "clear",
                        vec![],
                        vec![ret(host_call("cache.revalidate", vec![strv("shared")]))],
                    )]),
                ),
        );
    }

    runtime.render("alpha", "Panel", &json!(null)).unwrap();
    runtime.render("beta", "Panel", &json!(null)).unwrap();

    // beta clears "shared" — alpha's entry must survive.
    assert_eq!(
        returned(runtime.call("beta", "clear", &json!(null)).unwrap().outcome),
        json!(1)
    );
    assert!(
        runtime
            .render("alpha", "Panel", &json!(null))
            .unwrap()
            .cache_hit,
        "an app must not be able to clear another's cache by naming a tag they share"
    );
}

/// A component that is *not* cached must still work on a warm instance.
///
/// This is a regression test for a bug the caching tests found by accident:
/// `invoke` re-ran the module's top level on every call, including on a warm
/// instance whose top level had already completed. The executor unwinds its
/// scope stack when the top level finishes, so the second global run reached
/// for a scope that was no longer there and panicked — and the component
/// returned `[undefined]`.
///
/// Skipping module initialisation on a warm instance is not an optimisation
/// bolted on afterwards; it *is* the warm path. This test drives a component
/// with no caching at all so every call after the first is warm and must
/// produce a real payload.
#[test]
fn an_uncached_component_works_on_a_warm_instance() {
    let runtime = AppRuntime::new();
    runtime.register(
        AppDefinition::new("warmcomp")
            .with_capabilities(vec![Capability::State])
            .with_function(
                "Live",
                FunctionKind::Component,
                // No `revalidate` stanza, so nothing is ever cached and every
                // call after the first runs on a reused instance.
                module(vec![func_def(
                    "Live",
                    vec![],
                    vec![ret(json!({ "type": "object", "data": { "value": {
                        "component": { "type": "object", "data": { "value": {
                            "type": strv("text"),
                            "text": strv("still here") } } }
                    } } }))],
                )]),
            ),
    );

    let first = runtime.render("warmcomp", "Live", &json!(null)).unwrap();
    assert!(first.cold_start);
    assert_eq!(
        returned(first.outcome)["component"]["text"],
        json!("still here")
    );

    for _ in 0..3 {
        let warm = runtime.render("warmcomp", "Live", &json!(null)).unwrap();
        assert!(!warm.cold_start, "the instance is being reused");
        assert!(
            !warm.cache_hit,
            "and nothing is cached, so the guest really ran"
        );
        assert_eq!(
            returned(warm.outcome)["component"]["text"],
            json!("still here"),
            "a warm instance must produce the same payload, not [undefined]"
        );
    }
}

/// The same property for actions, which is where a warm instance is most used.
#[test]
fn an_action_returns_correctly_on_a_warm_instance() {
    let runtime = AppRuntime::new();
    runtime.register(
        AppDefinition::new("warmact")
            .with_capabilities(vec![Capability::State])
            .with_function(
                "echo",
                FunctionKind::Action,
                module(vec![func_def(
                    "echo",
                    vec!["v"],
                    vec![ret(
                        json!({ "type": "identifier", "data": { "name": "v" } }),
                    )],
                )]),
            ),
    );

    assert_eq!(
        returned(
            runtime
                .call("warmact", "echo", &json!("one"))
                .unwrap()
                .outcome
        ),
        json!("one")
    );
    let warm = runtime.call("warmact", "echo", &json!("two")).unwrap();
    assert!(!warm.cold_start);
    assert_eq!(returned(warm.outcome), json!("two"));
}
