//! Arithmetic behaviour, pinned.
//!
//! `operate_sum`, `operate_subtract` and `operate_multiply` each carried their
//! own copy of the same nested match over the five numeric type tags — three
//! hand-maintained coercion matrices that nothing tied together and that could
//! drift apart silently. They now share one `numeric_binop`.
//!
//! That is a behaviour-preserving refactor of the VM's hottest path, so these
//! tests state the behaviour directly rather than leaving it implied by the
//! language-conformance suites: integer stays integer, any float promotes,
//! narrowing follows the value's magnitude, and each operator's non-numeric
//! meanings are exactly the ones it had.

use elpian_vm::api;
use serde_json::{json, Value};

fn num(v: f64) -> Value {
    if v.fract() == 0.0 && v.abs() < 9.2e18 {
        json!({ "type": "i64", "data": { "value": v as i64 } })
    } else {
        json!({ "type": "f64", "data": { "value": v } })
    }
}

fn lit(type_name: &str, value: Value) -> Value {
    json!({ "type": type_name, "data": { "value": value } })
}

fn arith(op: &str, a: Value, b: Value) -> Value {
    json!({ "type": "arithmetic", "data": { "operation": op, "operand1": a, "operand2": b } })
}

/// Evaluate `a <op> b` and return the VM's stringified result.
fn eval(id: &str, op: &str, a: Value, b: Value) -> String {
    let ast = json!({
        "type": "program",
        "body": [
            { "type": "definition", "data": {
                "leftSide": { "type": "identifier", "data": { "name": "r" } },
                "rightSide": arith(op, a, b) } },
            { "type": "functionDefinition", "data": {
                "name": "get", "params": [],
                "body": [{ "type": "returnOperation", "data": {
                    "value": { "type": "identifier", "data": { "name": "r" } } } }] } }
        ]
    })
    .to_string();

    assert!(
        api::create_vm_from_ast(id.to_string(), ast),
        "{id} should compile"
    );
    let _ = api::execute_vm(id.to_string());
    let out = api::execute_vm_func(id.to_string(), "get".to_string(), 1).result_value;
    api::destroy_vm(id.to_string());
    out
}

#[test]
fn integer_arithmetic_stays_integral() {
    assert_eq!(eval("ar-i-add", "+", num(2.0), num(3.0)), "5");
    assert_eq!(eval("ar-i-sub", "-", num(9.0), num(4.0)), "5");
    assert_eq!(eval("ar-i-mul", "*", num(6.0), num(7.0)), "42");
    assert_eq!(eval("ar-i-neg", "-", num(3.0), num(10.0)), "-7");
}

#[test]
fn a_float_on_either_side_promotes_the_whole_operation() {
    assert_eq!(eval("ar-f-l", "+", lit("f64", json!(0.5)), num(1.0)), "1.5");
    assert_eq!(eval("ar-f-r", "+", num(1.0), lit("f64", json!(0.5))), "1.5");
    assert_eq!(
        eval("ar-f-sub", "-", lit("f64", json!(2.5)), num(1.0)),
        "1.5"
    );
    assert_eq!(eval("ar-f-mul", "*", lit("f64", json!(1.5)), num(2.0)), "3");
}

#[test]
fn results_narrow_by_magnitude_not_by_operand_width() {
    // check_int_range picks the smallest tag that holds the value, so a big
    // i64 input with a small result comes back small, and vice versa.
    assert_eq!(
        eval(
            "ar-narrow",
            "-",
            lit("i64", json!(100000)),
            lit("i64", json!(99999))
        ),
        "1"
    );
    assert_eq!(
        eval(
            "ar-widen",
            "*",
            lit("i32", json!(100000)),
            lit("i32", json!(100000))
        ),
        "10000000000"
    );
}

#[test]
fn null_is_the_additive_identity() {
    // Before first-class null, the front-ends compiled absent values to
    // integer 0, and guest code relies on a sum with null not trapping.
    let null = json!({ "type": "null", "data": { "value": null } });
    assert_eq!(eval("ar-n-l", "+", null.clone(), num(5.0)), "5");
    assert_eq!(eval("ar-n-r", "+", num(5.0), null.clone()), "5");
    assert_eq!(eval("ar-n-n", "+", null.clone(), null), "0");
}

#[test]
fn plus_concatenates_whenever_either_side_is_a_string() {
    let s = |v: &str| lit("string", json!(v));
    assert_eq!(eval("ar-s-ss", "+", s("ab"), s("cd")), "\"abcd\"");
    assert_eq!(eval("ar-s-si", "+", s("n="), num(7.0)), "\"n=7\"");
    assert_eq!(eval("ar-s-is", "+", num(7.0), s(" left")), "\"7 left\"");
    assert_eq!(
        eval("ar-s-sb", "+", s("v="), lit("bool", json!(true))),
        "\"v=true\""
    );
    // Concatenation is total over null: `"lives: " + maybeNull` yields a
    // string rather than a trap.
    assert_eq!(
        eval(
            "ar-s-sn",
            "+",
            s("x="),
            json!({ "type": "null", "data": { "value": null } })
        ),
        "\"x=null\""
    );
}

#[test]
fn plus_joins_arrays_and_prepends_or_appends_a_scalar() {
    let arr = |items: Vec<Value>| json!({ "type": "array", "data": { "value": items } });
    assert_eq!(
        eval("ar-a-aa", "+", arr(vec![num(1.0)]), arr(vec![num(2.0)])),
        "[1, 2]"
    );
    assert_eq!(
        eval("ar-a-ia", "+", num(1.0), arr(vec![num(2.0)])),
        "[1, 2]"
    );
    assert_eq!(
        eval("ar-a-ai", "+", arr(vec![num(1.0)]), num(2.0)),
        "[1, 2]"
    );
}

#[test]
fn star_repeats_a_string_or_array_by_an_integer_count() {
    assert_eq!(
        eval("ar-r-si", "*", lit("string", json!("ab")), num(3.0)),
        "\"ababab\""
    );
    assert_eq!(
        eval("ar-r-is", "*", num(3.0), lit("string", json!("ab"))),
        "\"ababab\""
    );
    let arr = json!({ "type": "array", "data": { "value": [num(1.0)] } });
    assert_eq!(eval("ar-r-ai", "*", arr, num(3.0)), "[1, 1, 1]");
}

#[test]
fn a_type_error_traps_the_instance_instead_of_tearing_down_the_host() {
    // Guest type errors are raised as panics inside the executor; the turn
    // boundary converts them into ordinary traps. This is the property the
    // whole FFI boundary rests on, so it is asserted here too.
    let obj = json!({ "type": "object", "data": { "value": {} } });
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(|_| {}));
    let out = eval("ar-trap", "-", obj, num(1.0));
    std::panic::set_hook(previous);

    assert!(
        out.contains("can not be subtracted"),
        "the trap should carry the guest's own reason, got {out:?}"
    );
    assert!(
        out.contains("object") && out.contains("integer"),
        "and should name both operand types, got {out:?}"
    );
}

#[test]
fn bool_times_bool_is_a_boolean_and() {
    // `*` treats a boolean as a mask elsewhere — `arr * false` yields an empty
    // array, `obj * true` yields the object — so `bool * bool` is a logical
    // AND. It computed exactly that, but tagged the result `typ: 7` (string)
    // while storing a `Payload::Bool`, so the value claimed to be a string and
    // panicked inside `as_string` the moment anything printed or stringified
    // it.
    let t = || lit("bool", json!(true));
    let f = || lit("bool", json!(false));

    assert_eq!(eval("ar-bb-tt", "*", t(), t()), "true");
    assert_eq!(eval("ar-bb-tf", "*", t(), f()), "false");
    assert_eq!(eval("ar-bb-ft", "*", f(), t()), "false");
    assert_eq!(eval("ar-bb-ff", "*", f(), f()), "false");
}

#[test]
fn a_boolean_masks_the_value_it_multiplies() {
    // The behaviour `bool * bool` should be consistent with.
    let arr = json!({ "type": "array", "data": { "value": [num(1.0), num(2.0)] } });
    assert_eq!(
        eval("ar-mask-on", "*", lit("bool", json!(true)), arr.clone()),
        "[1, 2]"
    );
    assert_eq!(
        eval("ar-mask-off", "*", lit("bool", json!(false)), arr),
        "[]"
    );
}
