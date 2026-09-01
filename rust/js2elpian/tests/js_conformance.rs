//! JavaScript-spec conformance fixes in the VM, exercised through the real
//! JS → AST → bytecode → executor path. Each test pins a behaviour that the VM
//! previously got wrong (or rejected) but which standard JavaScript guarantees.

use elpian_vm::api;

/// Compile JS, run its top-level program, then call `f()` and return the result.
fn run(id: &str, js: &str) -> String {
    assert!(js2elpian::create_vm_from_js(id.to_string(), js.to_string()), "JS should compile");
    let _ = api::execute_vm(id.to_string());
    api::execute_vm_func(id.to_string(), "f".to_string(), 1).result_value
}

// ---- Call arity (flexible, like JS) ----------------------------------------

#[test]
fn calling_with_fewer_args_binds_the_rest_to_undefined() {
    // Previously the call desynced when fewer args than declared params were
    // passed; the provided args failed to bind at all.
    assert_eq!(run("arity-fewer", "function g(a, b) { return a; } function f() { return g(5); }"), "5");
}

#[test]
fn a_missing_argument_is_undefined_and_falsy() {
    let js = "function g(a, b) { if (b) { return 1; } return 2; } function f() { return g(5); }";
    assert_eq!(run("arity-undef", js), "2");
}

#[test]
fn extra_arguments_are_ignored() {
    assert_eq!(run("arity-extra", "function g(a) { return a; } function f() { return g(5, 6, 7); }"), "5");
}

// ---- Truthiness (JS coercion in conditions / `!`) --------------------------

#[test]
fn objects_and_nonzero_numbers_are_truthy() {
    assert_eq!(run("truthy-obj", "function f() { let o = { x: 1 }; if (o) { return 1; } return 0; }"), "1");
    assert_eq!(run("truthy-num", "function f() { if (7) { return 1; } return 0; }"), "1");
    assert_eq!(run("truthy-str", "function f() { if (\"hi\") { return 1; } return 0; }"), "1");
}

#[test]
fn zero_empty_string_and_null_are_falsy() {
    assert_eq!(run("falsy-zero", "function f() { if (0) { return 1; } return 0; }"), "0");
    assert_eq!(run("falsy-str", "function f() { if (\"\") { return 1; } return 0; }"), "0");
}

#[test]
fn not_operator_applies_to_any_value() {
    // `!x` used to panic on non-booleans; it now negates JS truthiness.
    assert_eq!(run("not-zero", "function f() { if (!0) { return 1; } return 0; }"), "1");
    assert_eq!(run("not-obj", "function f() { let o = { x: 1 }; if (!o) { return 1; } return 0; }"), "0");
    assert_eq!(run("not-num", "function f() { if (!5) { return 1; } return 0; }"), "0");
}

// ---- Nested / computed assignment targets ----------------------------------

#[test]
fn nested_member_assignment() {
    assert_eq!(run("asg-nested", "function f() { let o = { a: { b: 1 } }; o.a.b = 5; return o.a.b; }"), "5");
}

#[test]
fn computed_assignment_targets() {
    assert_eq!(run("asg-idxmem", "function f() { let a = [{ x: 1 }]; a[0].x = 7; return a[0].x; }"), "7");
    assert_eq!(run("asg-memidx", "function f() { let o = { a: [1, 2] }; o.a[1] = 9; return o.a[1]; }"), "9");
    assert_eq!(run("asg-deep", "function f() { let o = { a: { b: { c: 1 } } }; o.a.b.c = 42; return o.a.b.c; }"), "42");
}

#[test]
fn single_level_assignment_still_works() {
    assert_eq!(run("asg-mem", "function f() { let o = { a: 1 }; o.a = 3; return o.a; }"), "3");
    assert_eq!(run("asg-idx", "function f() { let a = [1, 2]; a[0] = 8; return a[0]; }"), "8");
}

// ---- String escape decoding (\uXXXX / \u{…} / \xNN) -------------------------

#[test]
fn unicode_escapes_decode_including_surrogate_pairs() {
    // Babel emits ASCII-safe output by default, so emoji arrive as surrogate
    // pairs: "🔱" must decode to U+1F531 (🔱). Previously the lexer
    // dropped the backslashes and produced the literal text "uD83DuDD31".
    let js = "function f() { return \"\\uD83D\\uDD31 A\\x42 \\u{1F30A}\"; }";
    assert_eq!(run("esc-uni", js), "\"\u{1F531} AB \u{1F30A}\"");
}

#[test]
fn unicode_escapes_decode_in_template_literals() {
    let js = "function f() { return `\\u2713 \\uD83C\\uDF0A`; }";
    assert_eq!(run("esc-tpl", js), "\"✓ 🌊\"");
}

#[test]
fn lone_high_surrogate_becomes_replacement_char() {
    let js = r#"function f() { return "\uD83D!"; }"#;
    assert_eq!(run("esc-lone", js), "\"\u{FFFD}!\"");
}

// ---- Sums involving null / undefined (must never tear down the VM) ---------

#[test]
fn string_concat_with_null_and_undefined_is_total() {
    // JS defines `"x" + undefined` / `"x" + null`; before first-class null the
    // VM summed the compiled 0, and with typ-0 null it panicked the host
    // process (the CaspiGames client died mid-flow on a status string). Both
    // spellings conflate to the VM's null and stringify via the total display
    // coercion.
    assert_eq!(run("null-cat-r", "function f() { let u; return \"x\" + u; }"), "\"xnull\"");
    assert_eq!(run("null-cat-l", "function f() { return null + \"x\"; }"), "\"nullx\"");
    assert_eq!(run("null-cat-m", "function f() { let o = {}; return \"v=\" + o.nope + \"!\"; }"), "\"v=null!\"");
}

#[test]
fn numeric_sum_with_null_is_the_identity() {
    // Pre-null front-ends compiled null/undefined to integer 0, so guest code
    // relies on `n + null == n` (JS agrees for null: `5 + null === 5`).
    assert_eq!(run("null-sum-int", "function f() { return 5 + null; }"), "5");
    assert_eq!(run("null-sum-int-l", "function f() { let u; return u + 5; }"), "5");
    assert_eq!(run("null-sum-float", "function f() { return 1.5 + null; }"), "1.5");
    assert_eq!(run("null-sum-null", "function f() { return null + null; }"), "0");
}

// ---- __isType type-name spellings -------------------------------------------

#[test]
fn is_type_accepts_pre_neutral_spellings() {
    // Guest JS written before the VM's neutral type-tag vocabulary spells the
    // tags `List` / `Map` / `num` / `Array` (the CaspiGames client gates its
    // whole discovery flow on `__isType(r.games, "List")`). The front-end
    // resolves them to the neutral names at compile time.
    assert_eq!(run("ist-list", "function f() { if (__isType([1], \"List\")) { return 1; } return 0; }"), "1");
    assert_eq!(run("ist-arr", "function f() { if (__isType([1], \"Array\")) { return 1; } return 0; }"), "1");
    assert_eq!(run("ist-map", "function f() { if (__isType({ a: 1 }, \"Map\")) { return 1; } return 0; }"), "1");
    assert_eq!(run("ist-num", "function f() { if (__isType(3, \"num\")) { return 1; } return 0; }"), "1");
    assert_eq!(run("ist-not", "function f() { if (__isType(3, \"List\")) { return 1; } return 0; }"), "0");
}

/// A minifying codegen (oxc, which the Elpian CLI runs ahead of this front-end)
/// emits `0.45` as `.45`. Before this was handled, every fractional literal
/// between -1 and 1 in a TypeScript source failed to compile with
/// "unexpected token '.'".
#[test]
fn leading_dot_fractions_tokenize() {
    for src in [
        "let a = .5; let b = a;",
        "let a = .45e2; let b = a;",
        "let a = [.1, .25, .75]; let b = a;",
        "let a = { x: .5 }; let b = a;",
    ] {
        assert!(
            js2elpian::try_parse_js(src).is_ok(),
            "leading-dot fraction rejected: {src}"
        );
    }
}

/// The leading-dot branch must not swallow member access or spread.
#[test]
fn leading_dot_does_not_break_member_access_or_spread() {
    for src in [
        "let o = { b: 1 }; let v = o.b;",
        "let a = [1, 2]; let b = [...a, 3];",
        "let s = 'x'; let n = s.length;",
        "let a = [1]; a.push(2);",
    ] {
        assert!(
            js2elpian::try_parse_js(src).is_ok(),
            "regressed: {src}"
        );
    }
}
