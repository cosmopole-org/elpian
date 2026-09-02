//! Calling a closure that has been through an object field or an array slot.
//!
//! `react.js`'s `useState` builds its setter as an arrow function, stores it on
//! an object (`hook.setState = …`), then pushes it into the array it returns.
//! A component calls it as `pair[1](next)`. If any step in that round trip
//! loses the function, every state update in the React runtime traps with
//! "the specified data is not runnable" — which is exactly what happens.
//!
//! These narrow it down without the 250 KB of prelude the React tests need.

use serde_json::Value;

/// Run `src` and return whatever it pushed through `test.emit`, or the trap
/// reason if it stopped.
fn run(id: &str, src: &str) -> Result<Vec<Value>, String> {
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(|_| {}));
    let created = js2elpian::create_vm_from_js(id.to_string(), src.to_string());
    let out = std::panic::catch_unwind(|| {
        if !created {
            return Err("did not compile".to_string());
        }
        let _ = elpian_vm::api::execute_vm(id.to_string());
        match elpian_vm::api::trap_reason(id) {
            Some(r) => Err(r),
            None => Ok(Vec::new()),
        }
    });
    std::panic::set_hook(previous);
    let result = match out {
        Ok(r) => r,
        Err(payload) => Err(payload
            .downcast_ref::<String>()
            .cloned()
            .or_else(|| payload.downcast_ref::<&str>().map(|s| s.to_string()))
            .unwrap_or_else(|| "panic".to_string())),
    };
    elpian_vm::api::destroy_vm(id.to_string());
    result
}

#[test]
fn a_closure_called_directly_works() {
    assert!(run("clo-direct", "let f = (x) => x + 1; let r = f(1);").is_ok());
}

#[test]
fn a_closure_stored_in_a_local_and_called_works() {
    assert!(run(
        "clo-local",
        "let f = (x) => x + 1; let g = f; let r = g(1);"
    )
    .is_ok());
}

#[test]
fn a_closure_stored_on_an_object_field_can_be_called_back() {
    // `hook.setState = (next) => …; hook.setState(1)`
    let r = run(
        "clo-obj",
        "let o = { f: null }; o.f = (x) => x + 1; let r = o.f(1);",
    );
    assert!(
        r.is_ok(),
        "calling a closure off an object field failed: {r:?}"
    );
}

#[test]
fn a_closure_pushed_into_an_array_can_be_called_back() {
    // `out.push(h.setState); out[1](next)`
    let r = run(
        "clo-arr",
        "let f = (x) => x + 1; let a = []; a.push(f); let r = a[0](1);",
    );
    assert!(
        r.is_ok(),
        "calling a closure read back out of an array failed: {r:?}"
    );
}

#[test]
fn the_exact_use_state_round_trip_works() {
    // Object field -> array slot -> call. This is what react.js does.
    let r = run(
        "clo-usestate",
        r#"
let hook = { state: 0, setState: null };
hook.setState = (next) => { hook.state = next; };
let out = [];
out.push(hook.state);
out.push(hook.setState);
let set = out[1];
set(5);
"#,
    );
    assert!(r.is_ok(), "the useState round trip failed: {r:?}");
}

#[test]
fn calling_the_array_slot_without_binding_it_first_works() {
    // The form react.js components actually write: `s[1](1)`, with no
    // intermediate variable.
    let r = run(
        "clo-inline",
        r#"
let hook = { state: 0, setState: null };
hook.setState = (next) => { hook.state = next; };
let out = [];
out.push(hook.state);
out.push(hook.setState);
out[1](5);
"#,
    );
    assert!(
        r.is_ok(),
        "calling an array slot inline failed — this is the form every React \
         component uses: {r:?}"
    );
}

#[test]
fn a_closure_returned_from_a_factory_survives() {
    // `__vrHook(make)` calls `make()`, which builds the hook object and its
    // closure, and returns it through a second function.
    let r = run(
        "clo-factory",
        r#"
let take = (fn) => fn();
let make = () => {
  let h = { state: 1, setState: null };
  h.setState = (n) => { h.state = n; };
  return h;
};
let h = take(make);
h.setState(9);
"#,
    );
    assert!(r.is_ok(), "a closure built inside a factory failed: {r:?}");
}
