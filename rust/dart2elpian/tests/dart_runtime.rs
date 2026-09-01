//! End-to-end tests for the matured Dart front-end: Dart source is transpiled
//! to the JS subset, run through js2elpian → the Elpian VM, and the result of a
//! `main()`-style entry is observed. Exercises the new statements (do-while,
//! switch, try/catch/throw), operators (bitwise/shift, `??=`, `?.`, cascades),
//! and core-library methods end-to-end.

use elpian_vm::api;

/// Transpile Dart, run its top-level program (which defines `f`), then call `f`
/// and return the stringified result.
fn run_dart(id: &str, dart: &str) -> String {
    let js = dart2elpian::transpile(dart).expect("Dart should transpile");
    assert!(js2elpian::create_vm_from_js(id.to_string(), js), "emitted JS should compile");
    let _ = api::execute_vm(id.to_string());
    api::execute_vm_func(id.to_string(), "f".to_string(), 1).result_value
}

#[test]
fn bitwise_and_shift() {
    assert_eq!(run_dart("d-band", "int f() { return 6 & 3; }"), "2");
    assert_eq!(run_dart("d-bor", "int f() { return 6 | 1; }"), "7");
    assert_eq!(run_dart("d-bxor", "int f() { return 6 ^ 3; }"), "5");
    assert_eq!(run_dart("d-bnot", "int f() { return ~5; }"), "-6");
    assert_eq!(run_dart("d-shl", "int f() { return 1 << 4; }"), "16");
    assert_eq!(run_dart("d-shr", "int f() { return 32 >> 2; }"), "8");
}

#[test]
fn do_while_loop() {
    let dart = "int f() { var i = 0; var s = 0; do { s = s + i; i = i + 1; } while (i < 5); return s; }";
    assert_eq!(run_dart("d-dowhile", dart), "10");
}

#[test]
fn switch_statement() {
    let dart = "int f() { var x = 2; var r = 0; switch (x) { case 1: r = 10; break; case 2: r = 20; break; default: r = 99; } return r; }";
    assert_eq!(run_dart("d-switch", dart), "20");
    let dart2 = "int f() { var x = 7; var r = 0; switch (x) { case 1: r = 10; break; default: r = 99; } return r; }";
    assert_eq!(run_dart("d-switch-def", dart2), "99");
}

#[test]
fn try_catch_throw() {
    let dart = "int f() { try { throw 5; } catch (e) { return e; } }";
    assert_eq!(run_dart("d-try", dart), "5");
    // finally runs on the normal path.
    let dart2 = "int f() { var x = 0; try { x = 1; } finally { x = x + 10; } return x; }";
    assert_eq!(run_dart("d-finally", dart2), "11");
    // A native error (checked cast failure) is catchable.
    let dart3 = "int f() { try { var x = \"s\" as int; return x; } catch (e) { return 42; } }";
    assert_eq!(run_dart("d-cast-catch", dart3), "42");
}

#[test]
fn null_coalescing_assign_and_null_aware_access() {
    let dart = "int f() { var x = null; x ??= 7; return x; }";
    assert_eq!(run_dart("d-ncassign", dart), "7");
    let dart2 = "int f() { var o = null; return (o?.length) ?? 42; }";
    assert_eq!(run_dart("d-nullaware", dart2), "42");
}

#[test]
fn cascades() {
    let dart = "int f() { var xs = []; xs..add(1)..add(2)..add(3); return xs.length; }";
    assert_eq!(run_dart("d-cascade", dart), "3");
}

#[test]
fn iterable_methods() {
    let dart = "int f() { var xs = [1, 2, 3, 4]; return xs.where((x) => x % 2 == 0).map((x) => x * 10).fold(0, (a, b) => a + b); }";
    assert_eq!(run_dart("d-iter", dart), "60");
    let dart2 = "int f() { var xs = [3, 1, 4, 1, 5]; return xs.firstWhere((x) => x > 3); }";
    assert_eq!(run_dart("d-firstwhere", dart2), "4");
    let dart3 = "int f() { var xs = [5, 3, 8, 1]; xs.sort((a, b) => a - b); return xs[0]; }";
    assert_eq!(run_dart("d-sort", dart3), "1");
    let dart4 = "int f() { var xs = [1, 2, 3]; var total = 0; xs.forEach((x) { total = total + x; }); return total; }";
    assert_eq!(run_dart("d-foreach", dart4), "6");
}

#[test]
fn closure_by_reference_capture_via_js_layer() {
    // A closure mutating a captured local must propagate — boxing is applied by
    // the downstream JS layer, so the Dart-side removal of its own transform is
    // covered end-to-end.
    let dart = "int f() { var acc = 0; var add = (x) { acc = acc + x; }; add(3); add(4); return acc; }";
    assert_eq!(run_dart("d-closure", dart), "7");
}

#[test]
fn map_methods() {
    let dart = "int f() { var m = {\"a\": 1, \"b\": 2}; var s = 0; m.forEach((k, v) { s = s + v; }); return s; }";
    assert_eq!(run_dart("d-mapfe", dart), "3");
    let dart2 = "bool f() { var m = {\"a\": 1}; return m.containsKey(\"a\") && !m.containsKey(\"z\"); }";
    assert_eq!(run_dart("d-mapck", dart2), "true");
}

#[test]
fn string_and_num_methods() {
    assert_eq!(run_dart("d-str", "String f() { return \"hello\".toUpperCase(); }"), "\"HELLO\"");
    assert_eq!(run_dart("d-radix", "String f() { return (255).toRadixString(16); }"), "\"ff\"");
    assert_eq!(run_dart("d-int", "int f() { return (3.9).toInt(); }"), "3");
}
