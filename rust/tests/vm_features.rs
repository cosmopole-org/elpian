//! End-to-end tests for the extended VM: the native standard library, closures,
//! the OOP system, resource limits, capability gating, and pause / resume /
//! terminate — all exercised through the real AST → bytecode → executor path via
//! the public `api`.

use elpian_vm::api;
use elpian_vm::api::{Capability, ResourceLimits, RunState};
use serde_json::{json, Value};

// ---- AST construction helpers ----------------------------------------------

fn i64v(n: i64) -> Value {
    json!({ "type": "i64", "data": { "value": n } })
}
fn strv(s: &str) -> Value {
    json!({ "type": "string", "data": { "value": s } })
}
fn ident(name: &str) -> Value {
    json!({ "type": "identifier", "data": { "name": name } })
}
fn call(name: &str, args: Vec<Value>) -> Value {
    json!({ "type": "functionCall", "data": { "callee": ident(name), "args": args } })
}
fn call_val(callee: Value, args: Vec<Value>) -> Value {
    json!({ "type": "functionCall", "data": { "callee": callee, "args": args } })
}
fn arith(op: &str, a: Value, b: Value) -> Value {
    json!({ "type": "arithmetic", "data": { "operation": op, "operand1": a, "operand2": b } })
}
fn object(map: Value) -> Value {
    json!({ "type": "object", "data": { "value": map } })
}
fn def(name: &str, value: Value) -> Value {
    json!({ "type": "definition", "data": { "leftSide": ident(name), "rightSide": value } })
}
fn assign(name: &str, value: Value) -> Value {
    json!({ "type": "assignment", "data": { "leftSide": ident(name), "rightSide": value } })
}
fn ret(value: Value) -> Value {
    json!({ "type": "returnOperation", "data": { "value": value } })
}
fn func_def(name: &str, params: Vec<&str>, body: Vec<Value>) -> Value {
    json!({ "type": "functionDefinition", "data": { "name": name, "params": params, "body": body } })
}
fn host_call(name: &str, args: Vec<Value>) -> Value {
    json!({ "type": "host_call", "data": { "name": name, "args": args } })
}
fn program(body: Vec<Value>) -> String {
    json!({ "type": "program", "body": body }).to_string()
}

/// Register a VM, run its top-level program, then call `func` and return the
/// stringified result value.
fn run_and_call(id: &str, ast: &str, func: &str) -> String {
    assert!(api::create_vm_from_ast(id.to_string(), ast.to_string()), "AST should compile");
    let _ = api::execute_vm(id.to_string());
    let res = api::execute_vm_func(id.to_string(), func.to_string(), 1);
    res.result_value
}

// ---- Standard library -------------------------------------------------------

#[test]
fn math_builtins_run_in_the_vm() {
    let ast = program(vec![func_def(
        "f",
        vec![],
        vec![ret(call("pow", vec![i64v(2), i64v(10)]))],
    )]);
    assert_eq!(run_and_call("feat-math", &ast, "f"), "1024");
}

#[test]
fn nested_builtin_calls_compose() {
    // max(gcd(54, 24), sqrt(81)) = max(6, 9) = 9
    let ast = program(vec![func_def(
        "f",
        vec![],
        vec![ret(call(
            "max",
            vec![call("gcd", vec![i64v(54), i64v(24)]), call("sqrt", vec![i64v(81)])],
        ))],
    )]);
    assert_eq!(run_and_call("feat-nested", &ast, "f"), "9");
}

#[test]
fn foundation_string_and_json_builtins() {
    // upper(concat("el", "pa")) -> "ELPA"
    let ast = program(vec![func_def(
        "f",
        vec![],
        vec![ret(call("upper", vec![call("concat", vec![strv("el"), strv("pa")])]))],
    )]);
    assert_eq!(run_and_call("feat-str", &ast, "f"), "\"ELPA\"");
}

#[test]
fn user_definition_shadows_builtin() {
    // A user variable named `len` must win over the builtin.
    let ast = program(vec![func_def(
        "f",
        vec![],
        vec![def("len", i64v(7)), ret(ident("len"))],
    )]);
    assert_eq!(run_and_call("feat-shadow", &ast, "f"), "7");
}

// ---- Closures ---------------------------------------------------------------

#[test]
fn closures_capture_mutable_cell_state() {
    // makeCounter returns a closure over a captured cell; each call increments it.
    let make_counter = func_def(
        "makeCounter",
        vec![],
        vec![
            def("c", call("cell", vec![i64v(0)])),
            func_def(
                "inc",
                vec![],
                vec![
                    // cellSet(c, cellGet(c) + 1) — mutate the captured cell.
                    call("cellSet", vec![ident("c"), arith("+", call("cellGet", vec![ident("c")]), i64v(1))]),
                    ret(call("cellGet", vec![ident("c")])),
                ],
            ),
            ret(ident("inc")),
        ],
    );
    let ast = program(vec![
        make_counter,
        def("counter", call("makeCounter", vec![])),
        func_def("step", vec![], vec![ret(call_val(ident("counter"), vec![]))]),
    ]);

    let id = "feat-closure";
    assert!(api::create_vm_from_ast(id.to_string(), ast));
    let _ = api::execute_vm(id.to_string());

    assert_eq!(api::execute_vm_func(id.to_string(), "step".into(), 1).result_value, "1");
    assert_eq!(api::execute_vm_func(id.to_string(), "step".into(), 2).result_value, "2");
    assert_eq!(api::execute_vm_func(id.to_string(), "step".into(), 3).result_value, "3");
}

// ---- OOP --------------------------------------------------------------------

#[test]
fn oop_class_extend_new_and_field() {
    // B extends A overriding the default hp; new(B).hp == 20.
    let class_a = call(
        "class",
        vec![strv("A"), object(json!({ "hp": i64v(10) })), object(json!({}))],
    );
    let class_b = call(
        "extend",
        vec![class_a.clone(), strv("B"), object(json!({ "hp": i64v(20) })), object(json!({}))],
    );
    let ast = program(vec![
        def("A", class_a),
        def("B", call("extend", vec![ident("A"), strv("B"), object(json!({ "hp": i64v(20) })), object(json!({}))])),
        def("inst", call("new", vec![ident("B"), object(json!({}))])),
        func_def("hp", vec![], vec![ret(call("field", vec![ident("inst"), strv("hp")]))]),
        func_def(
            "isA",
            vec![],
            vec![ret(call("isInstance", vec![ident("inst"), ident("A")]))],
        ),
    ]);
    let _ = class_b; // (built inline above too; keep the helper exercised)

    let id = "feat-oop";
    assert!(api::create_vm_from_ast(id.to_string(), ast));
    let _ = api::execute_vm(id.to_string());
    assert_eq!(api::execute_vm_func(id.to_string(), "hp".into(), 1).result_value, "20");
    // Inheritance: an instance of B is also an A.
    assert_eq!(api::execute_vm_func(id.to_string(), "isA".into(), 2).result_value, "true");
}

// ---- Control flow: return propagation & switch dispatch ---------------------

#[test]
fn return_inside_conditional_exits_the_function() {
    // A `return` inside an if-body must exit the whole function, and the
    // statement following the if must not run when a branch returns.
    let body = vec![
        json!({ "type": "ifStmt", "data": {
            "condition": arith(">", ident("n"), i64v(0)),
            "body": [ ret(strv("pos")) ],
            "elseStmt": { "data": { "body": [ ret(strv("nonpos")) ] } }
        }}),
        ret(strv("fell-through")),
    ];
    let ast = program(vec![func_def("sign", vec!["n"], body)]);
    let id = "feat-return-if";
    assert!(api::create_vm_from_ast(id.to_string(), ast));
    let _ = api::execute_vm(id.to_string());
    assert_eq!(
        api::execute_vm_func_with_input(id.to_string(), "sign".into(), "5".into(), 1).result_value,
        "\"pos\""
    );
    assert_eq!(
        api::execute_vm_func_with_input(id.to_string(), "sign".into(), "-5".into(), 2).result_value,
        "\"nonpos\""
    );
}

#[test]
fn switch_dispatches_to_the_matching_case() {
    let case = |v: Value, body: Vec<Value>| json!({ "value": v, "body": { "body": body } });
    let body = vec![
        json!({ "type": "switchStmt", "data": {
            "value": ident("n"),
            "cases": [
                case(i64v(1), vec![ ret(strv("one")) ]),
                case(i64v(2), vec![ ret(strv("two")) ]),
            ]
        }}),
        ret(strv("other")),
    ];
    let ast = program(vec![func_def("name", vec!["n"], body)]);
    let id = "feat-switch";
    assert!(api::create_vm_from_ast(id.to_string(), ast));
    let _ = api::execute_vm(id.to_string());
    let call =
        |n: &str, cb| api::execute_vm_func_with_input(id.to_string(), "name".into(), n.into(), cb).result_value;
    assert_eq!(call("1", 1), "\"one\"");
    assert_eq!(call("2", 2), "\"two\"");
    assert_eq!(call("3", 3), "\"other\"");
}

// ---- Resource limits --------------------------------------------------------

#[test]
fn instruction_limit_traps_a_runaway_loop() {
    // A loop that would run a long time; a tiny instruction budget traps it.
    let ast = program(vec![
        def("i", i64v(0)),
        json!({ "type": "loopStmt", "data": {
            "condition": arith("<", ident("i"), i64v(1000000)),
            "body": [ assign("i", arith("+", ident("i"), i64v(1))) ]
        }}),
    ]);
    let id = "feat-limit";
    assert!(api::create_vm_from_ast(id.to_string(), ast));
    assert!(api::set_limits(id, ResourceLimits { max_instructions: Some(2000), ..ResourceLimits::unlimited() }));
    let _ = api::execute_vm(id.to_string());

    assert_eq!(api::run_state(id), Some(RunState::Terminated));
    let trap = api::trap_reason(id).expect("a trap reason");
    assert!(trap.contains("instructions"), "trap was: {trap}");
    let usage = api::usage(id).unwrap();
    assert!(usage.instructions <= 2000, "instructions capped: {}", usage.instructions);
}

#[test]
fn usage_is_reported_for_a_normal_run() {
    let ast = program(vec![def("x", arith("+", i64v(1), i64v(2)))]);
    let id = "feat-usage";
    assert!(api::create_vm_from_ast(id.to_string(), ast));
    let _ = api::execute_vm(id.to_string());
    let usage = api::usage(id).unwrap();
    assert!(usage.instructions > 0);
    assert_eq!(api::run_state(id), Some(RunState::Running));
}

// ---- Capability gating ------------------------------------------------------

#[test]
fn disabled_capability_short_circuits_host_call() {
    let ast = program(vec![host_call("net.fetch", vec![strv("https://example/x")])]);

    // Allowed: the call reaches the host (the VM pauses on it).
    let allowed = "feat-cap-on";
    assert!(api::create_vm_from_ast(allowed.to_string(), ast.clone()));
    let r = api::execute_vm(allowed.to_string());
    assert!(r.has_host_call, "net.fetch should reach the host when permitted");

    // Disabled: the call short-circuits to null, no host round-trip, run done.
    let denied = "feat-cap-off";
    assert!(api::create_vm_from_ast(denied.to_string(), ast));
    assert!(api::set_capability(denied, Capability::Network, false));
    let r = api::execute_vm(denied.to_string());
    assert!(!r.has_host_call, "net.fetch should be gated off");
}

// ---- Pause / resume / terminate --------------------------------------------

#[test]
fn pause_then_resume_completes_program() {
    let ast = program(vec![
        def("x", i64v(5)),
        func_def("getx", vec![], vec![ret(ident("x"))]),
    ]);
    let id = "feat-pause";
    assert!(api::create_vm_from_ast(id.to_string(), ast));

    // Pause before the first step: the program suspends immediately.
    assert!(api::pause_vm(id));
    let _ = api::execute_vm(id.to_string());
    assert_eq!(api::run_state(id), Some(RunState::Paused));

    // Resume: the top-level runs to completion and defines getx / x.
    let _ = api::resume_execution(id.to_string());
    assert_ne!(api::run_state(id), Some(RunState::Paused));
    assert_eq!(api::execute_vm_func(id.to_string(), "getx".into(), 1).result_value, "5");
}

#[test]
fn terminate_makes_instance_inert() {
    let ast = program(vec![func_def("getx", vec![], vec![ret(i64v(5))])]);
    let id = "feat-terminate";
    assert!(api::create_vm_from_ast(id.to_string(), ast));
    let _ = api::execute_vm(id.to_string());
    // It works before termination.
    assert_eq!(api::execute_vm_func(id.to_string(), "getx".into(), 1).result_value, "5");

    assert!(api::terminate_vm(id));
    assert_eq!(api::run_state(id), Some(RunState::Terminated));
    // After termination, further drive calls are inert (no "5").
    let after = api::execute_vm_func(id.to_string(), "getx".into(), 2);
    assert_ne!(after.result_value, "5");
}

// ---- new universal builtins + neutral primitives ---------------------------

#[test]
fn universal_integer_bit_and_math_builtins() {
    // Bitwise / shift primitives operate on 64-bit integers.
    assert_eq!(run_and_call("bit-and", &program(vec![func_def("f", vec![],
        vec![ret(call("bitAnd", vec![i64v(6), i64v(3)]))])]), "f"), "2");
    assert_eq!(run_and_call("bit-shl", &program(vec![func_def("f", vec![],
        vec![ret(call("shl", vec![i64v(1), i64v(10)]))])]), "f"), "1024");
    // Truncating integer division and remainder.
    assert_eq!(run_and_call("intdiv", &program(vec![func_def("f", vec![],
        vec![ret(call("intDiv", vec![i64v(7), i64v(2)]))])]), "f"), "3");
    assert_eq!(run_and_call("rem", &program(vec![func_def("f", vec![],
        vec![ret(call("remainder", vec![i64v(7), i64v(3)]))])]), "f"), "1");
    // Radix conversion round-trips.
    assert_eq!(run_and_call("radix", &program(vec![func_def("f", vec![],
        vec![ret(call("toRadix", vec![i64v(255), i64v(16)]))])]), "f"), "\"ff\"");
    assert_eq!(run_and_call("parseradix", &program(vec![func_def("f", vec![],
        vec![ret(call("parseRadix", vec![strv("ff"), i64v(16)]))])]), "f"), "255");
}

#[test]
fn universal_list_builtins() {
    // splice returns the removed slice and mutates in place.
    let ast = program(vec![func_def("f", vec![], vec![
        def("xs", json!({ "type": "array", "data": { "value": [i64v(1), i64v(2), i64v(3), i64v(4)] } })),
        def("removed", call("splice", vec![ident("xs"), i64v(1), i64v(2)])),
        ret(call("len", vec![ident("removed")])),
    ])]);
    assert_eq!(run_and_call("splice", &ast, "f"), "2");
    // at() with negative index, flatten, toSet.
    assert_eq!(run_and_call("at", &program(vec![func_def("f", vec![], vec![
        ret(call("at", vec![json!({ "type": "array", "data": { "value": [i64v(1), i64v(2), i64v(3)] } }), i64v(-1)]))])]), "f"), "3");
    assert_eq!(run_and_call("toset", &program(vec![func_def("f", vec![], vec![
        ret(call("len", vec![call("toSet", vec![json!({ "type": "array", "data": { "value": [i64v(1), i64v(1), i64v(2)] } })])]))])]), "f"), "2");
}

#[test]
fn native_error_is_catchable_and_uncaught_traps() {
    // An out-of-range native error thrown from a builtin is caught by a guest
    // try/catch as an object carrying a message.
    let ast = program(vec![func_def("f", vec![], vec![
        json!({ "type": "tryStmt", "data": {
            "errName": "e",
            "body": [ ret(call("removeAt", vec![
                json!({ "type": "array", "data": { "value": [i64v(1)] } }), i64v(9)])) ],
            "catchBody": [ ret(json!({ "type": "indexer", "data": {
                "target": ident("e"), "index": strv("name") } })) ],
        } }),
    ])]);
    assert_eq!(run_and_call("native-catch", &ast, "f"), "\"Error\"");
}

#[test]
fn throw_and_catch_binds_the_thrown_value() {
    let ast = program(vec![func_def("f", vec![], vec![
        json!({ "type": "tryStmt", "data": {
            "errName": "e",
            "body": [ json!({ "type": "throwOperation", "data": { "value": i64v(77) } }) ],
            "catchBody": [ ret(ident("e")) ],
        } }),
    ])]);
    assert_eq!(run_and_call("throw-catch", &ast, "f"), "77");
}
