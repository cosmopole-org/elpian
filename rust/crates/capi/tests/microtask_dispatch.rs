//! The deferred-callback seam every reactive prelude is built on.
//!
//! `react.js` schedules its re-render flush with `__later(__vrFlush)`, which
//! pushes the function into `__cbReg` and asks the host for a microtask. When
//! the microtask fires, `__dartDispatch` reads the slot back and calls it.
//!
//! If that round trip does not work, no React state update ever produces a
//! second render — which is exactly the symptom: the first render happens, then
//! the VM traps with "the specified data is not runnable".
//!
//! These tests use only `godot.js`, so they are cheap to run.

use elpian_godot::GodotSurface;
use elpian_godot::{GuestLang, VmManager, ROOT_VM};
use serde_json::{json, Value};

fn run(machine: &str, program: &str) -> (VmManager, Vec<Value>) {
    let mut mgr = VmManager::new_root_lang(
        Box::new(GodotSurface),
        machine.to_string(),
        program,
        GuestLang::Js,
        true,
        0,
        0,
    )
    .unwrap_or_else(|e| panic!("{machine} should compile: {e}"));

    mgr.set_bridge(Some(Box::new(|_name: &str, _args: &[Value]| {
        Some(Value::Bool(true))
    })));
    let _ = mgr.run_root();
    mgr.settle();
    let out = mgr
        .runtime_mut(ROOT_VM)
        .map(|rt| rt.emitted().to_vec())
        .unwrap_or_default();
    (mgr, out)
}

#[test]
fn a_deferred_callback_runs() {
    let (mgr, out) = run(
        "micro-basic",
        r#"
__later(() => { askHost("test.emit", ["ran"]); });
askHost("test.emit", ["scheduled"]);
"#,
    );
    assert_eq!(
        elpian_vm::api::trap_reason(&mgr.machine_of(ROOT_VM).unwrap()),
        None,
        "scheduling a microtask should not trap"
    );
    assert_eq!(
        out,
        vec![json!("scheduled"), json!("ran")],
        "the deferred callback should run after the synchronous code"
    );
}

#[test]
fn a_deferred_named_function_runs() {
    // What react.js actually does: `__later(__vrFlush)` — a top-level function
    // *declaration* passed by name, not an inline arrow.
    let (mgr, out) = run(
        "micro-named",
        r#"
function flush() { askHost("test.emit", ["flushed"]); }
__later(flush);
askHost("test.emit", ["scheduled"]);
"#,
    );
    assert_eq!(
        elpian_vm::api::trap_reason(&mgr.machine_of(ROOT_VM).unwrap()),
        None,
        "deferring a named function should not trap"
    );
    assert_eq!(out, vec![json!("scheduled"), json!("flushed")]);
}

#[test]
fn several_deferred_callbacks_all_run_in_order() {
    let (_mgr, out) = run(
        "micro-many",
        r#"
__later(() => { askHost("test.emit", [1]); });
__later(() => { askHost("test.emit", [2]); });
__later(() => { askHost("test.emit", [3]); });
"#,
    );
    assert_eq!(out, vec![json!(1), json!(2), json!(3)]);
}

#[test]
fn a_callback_scheduled_from_inside_a_callback_also_runs() {
    // `__vrFlush` re-schedules itself when a render enqueues more work, so a
    // microtask that schedules another must be drained too.
    let (_mgr, out) = run(
        "micro-nested",
        r#"
__later(() => {
  askHost("test.emit", ["outer"]);
  __later(() => { askHost("test.emit", ["inner"]); });
});
"#,
    );
    assert_eq!(
        out,
        vec![json!("outer"), json!("inner")],
        "a microtask scheduled from a microtask must still be drained"
    );
}

#[test]
fn a_closure_capturing_state_still_sees_it_when_deferred() {
    // The shape `useState`'s setter has: a closure over an object that is
    // mutated between scheduling and running.
    let (_mgr, out) = run(
        "micro-capture",
        r#"
let box = { n: 1 };
__later(() => { askHost("test.emit", [box.n]); });
box.n = 2;
"#,
    );
    assert_eq!(
        out,
        vec![json!(2)],
        "a deferred closure should see the captured object's current value"
    );
}
