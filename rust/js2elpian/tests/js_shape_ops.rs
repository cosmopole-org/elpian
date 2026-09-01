//! JS front-end coverage for the VM's universal shape operators: spread,
//! template literals and destructuring. Each program compiles JS to the Elpian
//! AST and runs it on the real VM through `f()`.

use elpian_vm::api;

fn run(id: &str, js: &str) -> String {
    assert!(js2elpian::create_vm_from_js(id.to_string(), js.to_string()), "JS should compile: {id}");
    let _ = api::execute_vm(id.to_string());
    api::execute_vm_func(id.to_string(), "f".to_string(), 1).result_value
}

// ---- spread -----------------------------------------------------------------

#[test]
fn array_spread() {
    assert_eq!(run("js-arr-spread", "function f(){ let a=[1,2]; let b=[0,...a,3]; return b; }"), "[0, 1, 2, 3]");
}

#[test]
fn array_spread_concat() {
    assert_eq!(run("js-arr-cat", "function f(){ let a=[1,2]; let b=[3,4]; return [...a,...b]; }"), "[1, 2, 3, 4]");
}

#[test]
fn object_spread() {
    let js = "function f(){ let o={a:1,b:2}; let p={...o,b:3,c:4}; return p.a + p.b + p.c; }";
    // 1 + 3 + 4 = 8
    assert_eq!(run("js-obj-spread", js), "8");
}

#[test]
fn call_spread() {
    let js = "function sum3(a,b,c){ return a+b+c; } function f(){ let xs=[1,2,3]; return sum3(...xs); }";
    assert_eq!(run("js-call-spread", js), "6");
}

#[test]
fn call_spread_mixed() {
    let js = "function sum3(a,b,c){ return a+b+c; } function f(){ return sum3(1,...[2,3]); }";
    assert_eq!(run("js-call-spread-mix", js), "6");
}

// ---- template literals ------------------------------------------------------

#[test]
fn template_basic() {
    let js = "function f(){ let name='World'; let n=42; return `Hello, ${name}! n=${n}`; }";
    assert_eq!(run("js-tmpl", js), "\"Hello, World! n=42\"");
}

#[test]
fn template_with_expression() {
    let js = "function f(){ let a=2; let b=3; return `${a}+${b}=${a+b}`; }";
    assert_eq!(run("js-tmpl-expr", js), "\"2+3=5\"");
}

#[test]
fn template_plain_text() {
    assert_eq!(run("js-tmpl-plain", "function f(){ return `just text`; }"), "\"just text\"");
}

// ---- destructuring ----------------------------------------------------------

#[test]
fn object_destructuring() {
    let js = "function f(){ let o={x:10,y:20}; let {x,y}=o; return x+y; }";
    assert_eq!(run("js-dstr-obj", js), "30");
}

#[test]
fn object_destructuring_rename_default() {
    let js = "function f(){ let o={x:10}; let {x: rx, z = 5}=o; return rx + z; }";
    assert_eq!(run("js-dstr-obj-def", js), "15");
}

#[test]
fn object_destructuring_rest() {
    let js = "function f(){ let o={x:1,y:2,z:3}; let {x, ...rest}=o; return rest.y + rest.z; }";
    assert_eq!(run("js-dstr-obj-rest", js), "5");
}

#[test]
fn array_destructuring() {
    assert_eq!(run("js-dstr-arr", "function f(){ let [a,b,c]=[1,2,3]; return a+b+c; }"), "6");
}

#[test]
fn array_destructuring_hole_default() {
    assert_eq!(run("js-dstr-arr-hole", "function f(){ let [a,,c]=[1,2,3]; return a+c; }"), "4");
    assert_eq!(run("js-dstr-arr-def", "function f(){ let [a,b=9]=[1]; return a+b; }"), "10");
}

#[test]
fn array_destructuring_rest() {
    assert_eq!(run("js-dstr-arr-rest", "function f(){ let [a,...rest]=[1,2,3,4]; return rest; }"), "[2, 3, 4]");
}

#[test]
fn destructuring_swap_via_array() {
    // Bind two names from one array pattern.
    let js = "function f(){ let [p,q]=[7,8]; return p*10+q; }";
    assert_eq!(run("js-dstr-two", js), "78");
}
