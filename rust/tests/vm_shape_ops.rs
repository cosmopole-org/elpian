//! End-to-end tests for the VM's universal "shape" operators — spread,
//! interpolated/template strings, and destructuring — exercised through the real
//! AST → bytecode → executor path via the public `api`. These are native VM
//! opcodes (no front-end desugaring), so the tests build the Elpian AST directly
//! the same way any language front-end would.

use elpian_vm::api;
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
fn arr(items: Vec<Value>) -> Value {
    json!({ "type": "array", "data": { "value": items } })
}
fn spread(v: Value) -> Value {
    json!({ "type": "spread", "data": { "value": v } })
}
fn template(parts: Vec<Value>) -> Value {
    json!({ "type": "template", "data": { "parts": parts } })
}
fn obj_entries(entries: Vec<Value>) -> Value {
    json!({ "type": "object", "data": { "entries": entries } })
}
fn entry(key: &str, value: Value) -> Value {
    json!({ "key": key, "value": value })
}
fn entry_spread(v: Value) -> Value {
    json!({ "spread": v })
}
fn indexer(target: Value, index: Value) -> Value {
    json!({ "type": "indexer", "data": { "target": target, "index": index } })
}
fn arith(op: &str, a: Value, b: Value) -> Value {
    json!({ "type": "arithmetic", "data": { "operation": op, "operand1": a, "operand2": b } })
}
fn call(name: &str, args: Vec<Value>) -> Value {
    json!({ "type": "functionCall", "data": { "callee": ident(name), "args": args } })
}
fn def(name: &str, value: Value) -> Value {
    json!({ "type": "definition", "data": { "leftSide": ident(name), "rightSide": value } })
}
fn ret(value: Value) -> Value {
    json!({ "type": "returnOperation", "data": { "value": value } })
}
fn func_def(name: &str, params: Vec<&str>, body: Vec<Value>) -> Value {
    json!({ "type": "functionDefinition", "data": { "name": name, "params": params, "body": body } })
}
fn destructure_obj(source: Value, bindings: Vec<Value>) -> Value {
    json!({ "type": "destructure", "data": { "isArray": false, "source": source, "bindings": bindings } })
}
fn destructure_arr(source: Value, bindings: Vec<Value>) -> Value {
    json!({ "type": "destructure", "data": { "isArray": true, "source": source, "bindings": bindings } })
}
fn program(body: Vec<Value>) -> String {
    json!({ "type": "program", "body": body }).to_string()
}

fn run_and_call(id: &str, ast: &str, func: &str) -> String {
    assert!(api::create_vm_from_ast(id.to_string(), ast.to_string()), "AST should compile");
    let _ = api::execute_vm(id.to_string());
    api::execute_vm_func(id.to_string(), func.to_string(), 1).result_value
}

// ---- spread -----------------------------------------------------------------

#[test]
fn array_spread_expands_in_place() {
    // b = [0, ...a, 3]
    let body = vec![
        def("a", arr(vec![i64v(1), i64v(2)])),
        def("b", arr(vec![i64v(0), spread(ident("a")), i64v(3)])),
        ret(ident("b")),
    ];
    let ast = program(vec![func_def("f", vec![], body)]);
    assert_eq!(run_and_call("spread-arr", &ast, "f"), "[0, 1, 2, 3]");
}

#[test]
fn array_spread_of_string_yields_chars() {
    let body = vec![ret(arr(vec![spread(strv("hi"))]))];
    let ast = program(vec![func_def("f", vec![], body)]);
    assert_eq!(run_and_call("spread-str", &ast, "f"), "[\"h\", \"i\"]");
}

#[test]
fn multiple_array_spreads_concatenate() {
    let body = vec![
        def("a", arr(vec![i64v(1), i64v(2)])),
        def("b", arr(vec![i64v(3), i64v(4)])),
        ret(arr(vec![spread(ident("a")), spread(ident("b"))])),
    ];
    let ast = program(vec![func_def("f", vec![], body)]);
    assert_eq!(run_and_call("spread-cat", &ast, "f"), "[1, 2, 3, 4]");
}

#[test]
fn object_spread_merges_and_overrides() {
    // o = {a:1, b:2}; p = {...o, b:3, c:4}; return p.b (override wins) etc.
    let make = |field: &str| {
        program(vec![func_def(
            "f",
            vec![],
            vec![
                def("o", obj_entries(vec![entry("a", i64v(1)), entry("b", i64v(2))])),
                def(
                    "p",
                    obj_entries(vec![
                        entry_spread(ident("o")),
                        entry("b", i64v(3)),
                        entry("c", i64v(4)),
                    ]),
                ),
                ret(indexer(ident("p"), strv(field))),
            ],
        )])
    };
    assert_eq!(run_and_call("spread-obj-a", &make("a"), "f"), "1"); // inherited
    assert_eq!(run_and_call("spread-obj-b", &make("b"), "f"), "3"); // overridden
    assert_eq!(run_and_call("spread-obj-c", &make("c"), "f"), "4"); // added
}

#[test]
fn call_spread_expands_arguments() {
    let sum3 = func_def(
        "sum3",
        vec!["a", "b", "c"],
        vec![ret(arith("+", arith("+", ident("a"), ident("b")), ident("c")))],
    );
    // sum3(...[1,2,3]) and sum3(1, ...[2,3]) both == 6
    let f_all = func_def(
        "f",
        vec![],
        vec![ret(call("sum3", vec![spread(arr(vec![i64v(1), i64v(2), i64v(3)]))]))],
    );
    let ast = program(vec![sum3.clone(), f_all]);
    assert_eq!(run_and_call("spread-call-all", &ast, "f"), "6");

    let f_mix = func_def(
        "f",
        vec![],
        vec![ret(call("sum3", vec![i64v(1), spread(arr(vec![i64v(2), i64v(3)]))]))],
    );
    let ast = program(vec![sum3, f_mix]);
    assert_eq!(run_and_call("spread-call-mix", &ast, "f"), "6");
}

// ---- template strings -------------------------------------------------------

#[test]
fn template_interpolates_values() {
    let body = vec![
        def("name", strv("World")),
        def("n", i64v(42)),
        ret(template(vec![strv("Hello, "), ident("name"), strv("! answer="), ident("n")])),
    ];
    let ast = program(vec![func_def("f", vec![], body)]);
    assert_eq!(run_and_call("tmpl-basic", &ast, "f"), "\"Hello, World! answer=42\"");
}

#[test]
fn template_coerces_bool_and_expr() {
    // parts include a boolean and an arithmetic expression
    let body = vec![ret(template(vec![
        strv("sum="),
        arith("+", i64v(2), i64v(3)),
        strv(" ok="),
        json!({ "type": "bool", "data": { "value": true } }),
    ]))];
    let ast = program(vec![func_def("f", vec![], body)]);
    assert_eq!(run_and_call("tmpl-coerce", &ast, "f"), "\"sum=5 ok=true\"");
}

#[test]
fn empty_template_is_empty_string() {
    let ast = program(vec![func_def("f", vec![], vec![ret(template(vec![]))])]);
    assert_eq!(run_and_call("tmpl-empty", &ast, "f"), "\"\"");
}

// ---- destructuring ----------------------------------------------------------

#[test]
fn object_destructuring_binds_members() {
    let body = vec![
        def("o", obj_entries(vec![entry("x", i64v(10)), entry("y", i64v(20))])),
        destructure_obj(ident("o"), vec![json!({"name":"x"}), json!({"name":"y"})]),
        ret(arith("+", ident("x"), ident("y"))),
    ];
    let ast = program(vec![func_def("f", vec![], body)]);
    assert_eq!(run_and_call("dstr-obj", &ast, "f"), "30");
}

#[test]
fn object_destructuring_with_rename_and_default() {
    // { x: renamed, z = 5 } from { x: 10 }  -> renamed=10, z=5
    let body = vec![
        def("o", obj_entries(vec![entry("x", i64v(10))])),
        destructure_obj(
            ident("o"),
            vec![
                json!({"name":"renamed","key":"x"}),
                json!({"name":"z","default": i64v(5)}),
            ],
        ),
        ret(arith("+", ident("renamed"), ident("z"))),
    ];
    let ast = program(vec![func_def("f", vec![], body)]);
    assert_eq!(run_and_call("dstr-obj-def", &ast, "f"), "15");
}

#[test]
fn object_destructuring_rest_collects_remainder() {
    // { x, ...rest } from { x:1, y:2, z:3 } -> rest.y + rest.z = 5
    let body = vec![
        def(
            "o",
            obj_entries(vec![entry("x", i64v(1)), entry("y", i64v(2)), entry("z", i64v(3))]),
        ),
        destructure_obj(
            ident("o"),
            vec![json!({"name":"x"}), json!({"name":"rest","rest":true})],
        ),
        ret(arith(
            "+",
            indexer(ident("rest"), strv("y")),
            indexer(ident("rest"), strv("z")),
        )),
    ];
    let ast = program(vec![func_def("f", vec![], body)]);
    assert_eq!(run_and_call("dstr-obj-rest", &ast, "f"), "5");
}

#[test]
fn array_destructuring_binds_positions() {
    let body = vec![
        destructure_arr(
            arr(vec![i64v(1), i64v(2), i64v(3)]),
            vec![json!({"name":"a"}), json!({"name":"b"}), json!({"name":"c"})],
        ),
        ret(arith("+", arith("+", ident("a"), ident("b")), ident("c"))),
    ];
    let ast = program(vec![func_def("f", vec![], body)]);
    assert_eq!(run_and_call("dstr-arr", &ast, "f"), "6");
}

#[test]
fn array_destructuring_with_hole_and_default() {
    // [a, , c] from [1,2,3] -> a + c = 4
    let body = vec![
        destructure_arr(
            arr(vec![i64v(1), i64v(2), i64v(3)]),
            vec![json!({"name":"a"}), json!({"hole":true}), json!({"name":"c"})],
        ),
        ret(arith("+", ident("a"), ident("c"))),
    ];
    let ast = program(vec![func_def("f", vec![], body)]);
    assert_eq!(run_and_call("dstr-arr-hole", &ast, "f"), "4");

    // [a, b=9] from [1] -> a + b = 10
    let body = vec![
        destructure_arr(
            arr(vec![i64v(1)]),
            vec![json!({"name":"a"}), json!({"name":"b","default": i64v(9)})],
        ),
        ret(arith("+", ident("a"), ident("b"))),
    ];
    let ast = program(vec![func_def("f", vec![], body)]);
    assert_eq!(run_and_call("dstr-arr-def", &ast, "f"), "10");
}

#[test]
fn array_destructuring_rest_collects_tail() {
    // [a, ...rest] from [1,2,3,4] -> rest == [2,3,4]
    let body = vec![
        destructure_arr(
            arr(vec![i64v(1), i64v(2), i64v(3), i64v(4)]),
            vec![json!({"name":"a"}), json!({"name":"rest","rest":true})],
        ),
        ret(ident("rest")),
    ];
    let ast = program(vec![func_def("f", vec![], body)]);
    assert_eq!(run_and_call("dstr-arr-rest", &ast, "f"), "[2, 3, 4]");
}

#[test]
fn destructuring_inside_closure_captures_correctly() {
    // A destructured local referenced from a nested closure must be captured.
    let inner = func_def("g", vec![], vec![ret(arith("+", ident("a"), ident("b")))]);
    let body = vec![
        destructure_arr(
            arr(vec![i64v(4), i64v(5)]),
            vec![json!({"name":"a"}), json!({"name":"b"})],
        ),
        inner,
        ret(call("g", vec![])),
    ];
    let ast = program(vec![func_def("f", vec![], body)]);
    assert_eq!(run_and_call("dstr-closure", &ast, "f"), "9");
}
