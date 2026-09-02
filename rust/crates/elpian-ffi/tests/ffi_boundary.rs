//! The FFI boundary must contain guest faults.
//!
//! The Elpian executor raises guest type errors as `panic!`, not as traps — a
//! mini app evaluating `{} - 1` unwinds with
//! `"elpian error: object and integer can not be subtracted"`. Unwinding out of
//! an `extern "C"` frame is undefined behaviour and in practice aborts the
//! whole host application, so an untrusted mini app could kill the app it runs
//! inside with a type error.
//!
//! These tests drive the real C ABI the Flutter engine links against and assert
//! that a faulting guest:
//!
//!   1. does not unwind past the boundary,
//!   2. yields a well-formed result the Dart side can parse,
//!   3. records a readable reason in `elpian_last_error`, and
//!   4. leaves the registry usable — a second, healthy VM still runs.
//!
//! Point 4 is the one that matters most in a super app: one mini app's fault
//! must not cost every other mini app in the process its runtime.

#![cfg(not(target_arch = "wasm32"))]

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use ::vm::api;
use elpian_vm::abi::{
    elpian_create_vm_from_ast, elpian_destroy_vm, elpian_execute, elpian_free_string,
    elpian_last_error,
};
use serde_json::{json, Value};

/// Silence the default panic hook for the duration of a deliberately faulting
/// call, so an expected guest fault does not spray a backtrace over the test
/// output. Restores the previous hook on the way out.
fn without_panic_output<T>(body: impl FnOnce() -> T) -> T {
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(|_| {}));
    let out = body();
    std::panic::set_hook(previous);
    out
}

fn last_error() -> String {
    unsafe { CStr::from_ptr(elpian_last_error()) }
        .to_string_lossy()
        .into_owned()
}

fn take_string(ptr: *mut c_char) -> String {
    assert!(!ptr.is_null(), "boundary returned a NULL string");
    let s = unsafe { CStr::from_ptr(ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { elpian_free_string(ptr) };
    s
}

/// `askHost("render", <arg>)` where `arg` is whatever expression is given.
fn program_rendering(expr: Value) -> Value {
    json!({
        "type": "program",
        "body": [{
            "type": "host_call",
            "data": { "name": "render", "args": [expr] }
        }]
    })
}

fn create(id: &str, ast: &Value) -> bool {
    let c_id = CString::new(id).unwrap();
    let c_ast = CString::new(ast.to_string()).unwrap();
    unsafe { elpian_create_vm_from_ast(c_id.as_ptr(), c_ast.as_ptr()) == 1 }
}

fn execute(id: &str) -> String {
    let c_id = CString::new(id).unwrap();
    take_string(unsafe { elpian_execute(c_id.as_ptr()) })
}

fn destroy(id: &str) {
    let c_id = CString::new(id).unwrap();
    unsafe { elpian_destroy_vm(c_id.as_ptr()) };
}

/// An object minus an integer: the executor's own words are "object and integer
/// can not be subtracted", raised as a panic from `operate_subtract`.
fn faulting_expression() -> Value {
    json!({
        "type": "arithmetic",
        "data": {
            "operation": "-",
            "operand1": { "type": "object", "data": { "value": {} } },
            "operand2": { "type": "i64", "data": { "value": 1 } }
        }
    })
}

#[test]
fn a_guest_type_error_does_not_unwind_past_the_boundary() {
    let id = "ffi-boundary-fault";
    assert!(create(id, &program_rendering(faulting_expression())));

    // The bug this guards: before the boundary was sealed, this call aborted
    // the process instead of returning.
    let raw = without_panic_output(|| execute(id));

    let parsed: Value = serde_json::from_str(&raw)
        .unwrap_or_else(|e| panic!("boundary returned unparseable JSON {raw:?}: {e}"));
    assert_eq!(
        parsed["hasHostCall"], false,
        "a faulting turn must not report a pending host call"
    );
    assert!(
        parsed["resultValue"].is_string(),
        "resultValue must still be a string: {parsed}"
    );

    // The fault is contained at the VM turn, so it surfaces the way a limit
    // overrun does — as a trap on that instance, with its reason readable.
    let reason = api::trap_reason(id).expect("the faulting VM should be trapped");
    assert!(
        reason.contains("can not be subtracted"),
        "the trap should carry the guest's own fault reason, got {reason:?}"
    );
    assert_eq!(
        api::run_state(id),
        Some(api::RunState::Terminated),
        "a faulted instance must end terminated, not wedged mid-turn"
    );
    assert!(
        !api::vm_is_processing(id),
        "a faulted instance must not stay flagged as processing — it would \
         bounce every later call with vm_busy for the rest of its life"
    );

    destroy(id);
}

#[test]
fn a_faulting_guest_does_not_disturb_a_healthy_one() {
    let (bad, good) = ("ffi-boundary-bad-neighbour", "ffi-boundary-good-neighbour");

    assert!(create(bad, &program_rendering(faulting_expression())));
    assert!(create(
        good,
        &program_rendering(json!({ "type": "string", "data": { "value": "still here" } }))
    ));

    without_panic_output(|| execute(bad));

    // The registry mutex was poisoned by the unwind above. `lock_tolerant`
    // recovers it; without that recovery every later call would fail for the
    // life of the process — one bad mini app taking down the whole super app.
    let raw = execute(good);
    let parsed: Value = serde_json::from_str(&raw).expect("healthy VM returned unparseable JSON");
    assert_eq!(
        parsed["hasHostCall"], true,
        "the healthy VM should have paused on its render host call: {parsed}"
    );
    assert!(
        parsed["hostCallData"]
            .as_str()
            .is_some_and(|d| d.contains("still here")),
        "the healthy VM's payload should be intact: {parsed}"
    );

    destroy(bad);
    destroy(good);
}

#[test]
fn a_trapped_vm_stays_trapped_and_refuses_further_turns() {
    let id = "ffi-boundary-stays-trapped";
    assert!(create(id, &program_rendering(faulting_expression())));
    without_panic_output(|| execute(id));

    let first = api::trap_reason(id).expect("expected a trap");

    // Driving it again must neither revive it nor overwrite why it died: a
    // host looking at the trap reason needs the original fault, not a later
    // one raised on top of a corpse.
    let raw = without_panic_output(|| execute(id));
    let parsed: Value = serde_json::from_str(&raw).expect("unparseable JSON from a trapped VM");
    assert_eq!(parsed["hasHostCall"], false);
    assert_eq!(
        api::trap_reason(id).as_deref(),
        Some(first.as_str()),
        "the first fault must win"
    );

    destroy(id);
}

/// The FFI guard is the backstop beneath `drive_turn`: it catches anything that
/// panics outside a VM turn (registry bookkeeping, serialization) so nothing at
/// all unwinds through an `extern "C"` frame. A clean call must leave no stale
/// reason behind in its slot.
#[test]
fn the_boundary_error_slot_is_empty_after_a_clean_call() {
    let id = "ffi-boundary-clean";
    assert!(create(
        id,
        &program_rendering(json!({ "type": "string", "data": { "value": "ok" } }))
    ));
    execute(id);
    assert_eq!(last_error(), "");
    destroy(id);
}

#[test]
fn null_and_empty_inputs_are_handled_rather_than_dereferenced() {
    // Every entry point accepts NULL as the empty string; none may dereference
    // it. A crash here would be the boundary reading a pointer it was handed.
    assert_eq!(
        unsafe { elpian_create_vm_from_ast(std::ptr::null(), std::ptr::null()) },
        0,
        "a NULL AST is not a valid program"
    );

    let missing = CString::new("ffi-boundary-no-such-vm").unwrap();
    let raw = take_string(unsafe { elpian_execute(missing.as_ptr()) });
    let parsed: Value = serde_json::from_str(&raw).expect("unknown VM returned unparseable JSON");
    assert_eq!(parsed["hasHostCall"], false);

    // Freeing NULL is a no-op, not a fault.
    unsafe { elpian_free_string(std::ptr::null_mut()) };
}

/// Every registry read must go through `lock_tolerant`. A guest panic poisons
/// the mutex on its way out, so any function reaching for `VMS.lock().unwrap()`
/// panics for the rest of the process's life.
///
/// `trap_reason` was the sharpest case: it is the function a host calls to find
/// out *why* a guest just faulted, and it panicked on the poison that same
/// guest had left behind.
#[test]
fn post_fault_introspection_survives_the_poisoned_registry() {
    let bad = "ffi-boundary-poison-probe";
    assert!(create(bad, &program_rendering(faulting_expression())));
    without_panic_output(|| execute(bad));

    // Each of these takes the registry lock after the unwind poisoned it.
    // Before `lock_tolerant` covered them, every one of these panicked.
    assert!(!api::vm_is_processing(bad));
    let _ = api::capability_allows(bad, "net.fetch");
    let _ = api::trap_reason(bad);
    assert!(
        api::vm_exists(bad.to_string()),
        "the VM is still registered after its fault"
    );

    destroy(bad);
}

/// A guard against the pattern coming back: no registry read in `api.rs` may
/// use a plain `.lock().unwrap()`.
#[test]
fn no_registry_lock_bypasses_the_poison_recovery() {
    let source = include_str!("../../elpian-vm/src/api.rs");
    for (n, line) in source.lines().enumerate() {
        let line = line.trim();
        assert!(
            !(line.contains("VMS.lock()") || line.contains("HIERARCHY.lock()")),
            "elpian-vm/src/api.rs:{}: take the registry through `lock_tolerant`, not `{}` — \
             a guest panic poisons this mutex and every later call would fail \
             for the life of the process",
            n + 1,
            line
        );
    }
}
