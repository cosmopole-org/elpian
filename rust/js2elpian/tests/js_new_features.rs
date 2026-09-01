use elpian_vm::api;

fn run(id: &str, js: &str) -> String {
    assert!(js2elpian::create_vm_from_js(id.to_string(), js.to_string()), "JS should compile: {id}");
    let _ = api::execute_vm(id.to_string());
    api::execute_vm_func(id.to_string(), "f".to_string(), 1).result_value
}

#[test]
fn logical_and_or_basic() {
    assert_eq!(run("t1", "function f(){ if (1 < 2 && 3 < 4) { return 1; } return 0; }"), "1");
    assert_eq!(run("t2", "function f(){ if (1 > 2 || 3 < 4) { return 1; } return 0; }"), "1");
    assert_eq!(run("t3", "function f(){ if (1 > 2 && 3 < 4) { return 1; } return 0; }"), "0");
}

#[test]
fn logical_value_result() {
    // && returns right when left truthy, left when falsy
    assert_eq!(run("t4", "function f(){ let x = 5 && 7; return x; }"), "7");
    assert_eq!(run("t5", "function f(){ let x = 0 && 7; return x; }"), "0");
    assert_eq!(run("t6", "function f(){ let x = 0 || 9; return x; }"), "9");
    assert_eq!(run("t7", "function f(){ let x = 3 || 9; return x; }"), "3");
}

#[test]
fn logical_short_circuit_guards() {
    // obj null guard: must not index null
    let js = "function f(){ let o = 0; if (o && o.x) { return 1; } return 2; }";
    assert_eq!(run("t8", js), "2");
    // right side not evaluated would otherwise trap
    let js2 = "function f(){ let o = { x: 5 }; if (o && o.x > 3) { return o.x; } return 0; }";
    assert_eq!(run("t9", js2), "5");
}

#[test]
fn ternary_basic() {
    assert_eq!(run("t10", "function f(){ let x = 1 < 2 ? 10 : 20; return x; }"), "10");
    assert_eq!(run("t11", "function f(){ let x = 1 > 2 ? 10 : 20; return x; }"), "20");
    // nested
    assert_eq!(run("t12", "function f(){ let n = 5; return n > 10 ? 1 : n > 3 ? 2 : 3; }"), "2");
}

#[test]
fn ternary_in_loop_condition() {
    // logical in loop condition re-evaluated each iteration
    let js = "function f(){ let i = 0; let s = 0; while (i < 10 && s < 6) { s = s + i; i = i + 1; } return s; }";
    // i:0 s0; i1 s0; i2 s1; i3 s3; i4 s6 stop -> 6
    assert_eq!(run("t13", js), "6");
}

#[test]
fn continue_in_while() {
    let js = "function f(){ let i = 0; let s = 0; while (i < 10) { i = i + 1; if (i == 5) { continue; } s = s + i; } return s; }";
    // sum 1..10 = 55 minus 5 = 50
    assert_eq!(run("t14", js), "50");
}

#[test]
fn continue_in_for() {
    let js = "function f(){ let s = 0; for (let i = 0; i < 10; i++) { if (i == 3) { continue; } s = s + i; } return s; }";
    // sum 0..9 = 45 minus 3 = 42
    assert_eq!(run("t15", js), "42");
}

#[test]
fn break_in_for() {
    let js = "function f(){ let s = 0; for (let i = 0; i < 100; i++) { if (i == 5) { break; } s = s + i; } return s; }";
    // 0+1+2+3+4 = 10
    assert_eq!(run("t16", js), "10");
}

#[test]
fn break_in_while() {
    let js = "function f(){ let i = 0; while (true) { if (i >= 5) { break; } i = i + 1; } return i; }";
    assert_eq!(run("t17", js), "5");
}

#[test]
fn super_method_call() {
    let js = "
        class A { greet() { return 10; } }
        class B extends A { greet() { return super.greet() + 5; } }
        function f(){ let b = new B(); return b.greet(); }";
    assert_eq!(run("t18", js), "15");
}

#[test]
fn static_method() {
    let js = "
        class MathU { static sq(x) { return x * x; } }
        function f(){ return MathU.sq(7); }";
    assert_eq!(run("t19", js), "49");
}

#[test]
fn static_field() {
    let js = "
        class C { static count = 42; }
        function f(){ return C.count; }";
    assert_eq!(run("t20", js), "42");
}

#[test]
fn implicit_ctor_forwards_args() {
    let js = "
        class Base { constructor(a, b) { this.sum = a + b; } }
        class Derived extends Base { }
        function f(){ let d = new Derived(3, 4); return d.sum; }";
    assert_eq!(run("t21", js), "7");
}

#[test]
fn typeof_number() {
    assert_eq!(run("t22", "function f(){ return typeOf(5); }"), "\"number\"");
    assert_eq!(run("t23", "function f(){ return typeOf(5.5); }"), "\"number\"");
    assert_eq!(run("t24", "function f(){ return typeOf(\"hi\"); }"), "\"string\"");
}

#[test]
fn combined_continue_and_ternary() {
    let js = "function f(){ let s = 0; for (let i = 0; i < 6; i++) { let add = (i % 2 == 0) ? i : 0; if (add == 0) { continue; } s = s + add; } return s; }";
    // even i added: 0,2,4 but add==0 for i=0 continue; so 2+4=6
    assert_eq!(run("t25", js), "6");
}

#[test]
fn short_circuit_call_statement() {
    // `cond && f()` as a statement runs the call only when cond is truthy.
    let js = "
        function bump(o) { o.n = o.n + 5; }
        function f(){
            let o = { n: 0 };
            let go = true;
            go && bump(o);
            let stop = false;
            stop && bump(o);
            return o.n;
        }";
    assert_eq!(run("t26", js), "5");
}

#[test]
fn nested_loops_continue_targets_inner() {
    let js = "
        function f(){
            let s = 0;
            for (let i = 0; i < 3; i++) {
                for (let j = 0; j < 3; j++) {
                    if (j == 1) { continue; }
                    s = s + 1;
                }
            }
            return s;
        }";
    // inner runs j=0,2 (skip 1) => 2 per outer, 3 outers => 6
    assert_eq!(run("t27", js), "6");
}

#[test]
fn super_method_grandparent_chain() {
    let js = "
        class A { who() { return 1; } }
        class B extends A { }
        class C extends B { who() { return super.who() + 10; } }
        function f(){ let c = new C(); return c.who(); }";
    assert_eq!(run("t28", js), "11");
}

#[test]
fn for_loop_no_update_with_continue() {
    // `for` with an empty update clause, plus `continue`.
    let js = "
        function f(){
            let s = 0; let i = 0;
            for (; i < 6;) {
                i = i + 1;
                if (i == 3) { continue; }
                s = s + i;
            }
            return s;
        }";
    // sum 1..6 = 21 minus 3 = 18
    assert_eq!(run("t29", js), "18");
}

#[test]
fn js_member_spellings_resolve_to_universal_names_at_compile_time() {
    // Real JS core-type member spellings are mapped to the VM's universal stdlib
    // names by js2elpian at compile time — the VM only ever sees the universal
    // name. `arr.push`/`arr.pop` are already universal; `includes`/`toUpperCase`/
    // `charCodeAt` diverge and are translated (`contains`/`upper`/`codeUnitAt`).
    let js = "
        function f(){
            let a = [1, 2, 3];
            a.push(4);
            let hit = a.includes(4) ? 100 : 0;
            let s = \"hi\".toUpperCase();
            let code = s.charCodeAt(0);      // 'H' = 72
            return hit + a.length + code;    // 100 + 4 + 72 = 176
        }";
    assert_eq!(run("js-universal-members", js), "176");
}

#[test]
fn user_method_named_like_a_js_builtin_is_not_rewritten() {
    // A class method whose name collides with a JS core spelling (`includes`)
    // still dispatches to the user's method, not the universal `contains`.
    let js = "
        class Bag {
            constructor() { this.n = 7; }
            includes(x) { return this.n + x; }
        }
        function f(){ let b = new Bag(); return b.includes(5); }";  // 7 + 5 = 12
    assert_eq!(run("js-user-includes", js), "12");
}
