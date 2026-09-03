//! An instance's `random` stream must belong to the instance, not to the thread
//! that happens to run it.
//!
//! The state used to live in a bare thread-local, which held only because a
//! process-wide lock made all guest execution serial and every instance was
//! driven from one thread. Both of those stop being true once server function
//! instances are pooled across threads: two instances sharing a thread would
//! draw from one stream, and an instance that migrated would jump to another.
//! These tests pin the fixed behaviour through the real AST → bytecode → executor
//! path.

use elpian_vm::api;
use serde_json::{json, Value};

fn i64v(n: i64) -> Value {
    json!({ "type": "i64", "data": { "value": n } })
}
fn ident(name: &str) -> Value {
    json!({ "type": "identifier", "data": { "name": name } })
}
fn call(name: &str, args: Vec<Value>) -> Value {
    json!({ "type": "functionCall", "data": { "callee": ident(name), "args": args } })
}
fn ret(value: Value) -> Value {
    json!({ "type": "returnOperation", "data": { "value": value } })
}
fn func_def(name: &str, params: Vec<&str>, body: Vec<Value>) -> Value {
    json!({ "type": "functionDefinition", "data": { "name": name, "params": params, "body": body } })
}
fn program(body: Vec<Value>) -> String {
    json!({ "type": "program", "body": body }).to_string()
}

/// `draw()` returns the next value of the stream; `seed(n)` re-seeds it.
fn rng_program() -> String {
    program(vec![
        func_def("draw", vec![], vec![ret(call("random", vec![]))]),
        func_def(
            "seed",
            vec!["n"],
            vec![call("seedRandom", vec![ident("n")]), ret(i64v(0))],
        ),
    ])
}

fn spawn(id: &str) {
    assert!(api::create_vm_from_ast(id.to_string(), rng_program()), "AST should compile");
    let _ = api::execute_vm(id.to_string());
}

fn draw(id: &str, cb: i64) -> String {
    api::execute_vm_func(id.to_string(), "draw".into(), cb).result_value
}

#[test]
fn interleaved_instances_do_not_share_a_random_stream() {
    spawn("rng-a");
    spawn("rng-b");

    // Interleave the turns: a, b, a, b. Identically seeded instances must stay
    // in step with each other, and each must advance only its own stream.
    let (a1, b1) = (draw("rng-a", 1), draw("rng-b", 1));
    let (a2, b2) = (draw("rng-a", 2), draw("rng-b", 2));

    assert_eq!(a1, b1, "identically seeded instances start at the same value");
    assert_eq!(a2, b2, "and stay in step despite interleaving");
    assert_ne!(a1, a2, "a single instance still advances its own stream");

    api::destroy_vm("rng-a".into());
    api::destroy_vm("rng-b".into());
}

#[test]
fn seeding_one_instance_does_not_reseed_another() {
    spawn("rng-seeded");
    spawn("rng-untouched");
    spawn("rng-control");

    api::execute_vm_func_with_input("rng-seeded".into(), "seed".into(), "7".into(), 1);

    let seeded = draw("rng-seeded", 2);
    let untouched = draw("rng-untouched", 2);
    assert_ne!(seeded, untouched, "the re-seed reached only the instance that asked");
    assert_eq!(
        untouched,
        draw("rng-control", 2),
        "the untouched instance still matches a never-seeded one"
    );

    for id in ["rng-seeded", "rng-untouched", "rng-control"] {
        api::destroy_vm(id.into());
    }
}

/// Turns must leave the thread's scratch cell as they found it, so nothing an
/// instance does to its own stream can reach whatever the thread runs next.
#[test]
fn a_turn_leaves_no_residue_on_the_thread() {
    spawn("rng-first");
    api::execute_vm_func_with_input("rng-first".into(), "seed".into(), "99".into(), 1);
    let _ = draw("rng-first", 2);

    // A brand-new instance created *after* that re-seed must still start from
    // the default stream.
    spawn("rng-later");
    spawn("rng-reference");
    assert_eq!(
        draw("rng-later", 3),
        draw("rng-reference", 3),
        "a later instance starts from the default seed, not the previous instance's state"
    );

    for id in ["rng-first", "rng-later", "rng-reference"] {
        api::destroy_vm(id.into());
    }
}
