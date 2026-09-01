//! # dart2elpian — a bounded **Dart → Elpian** front-end.
//!
//! Phase 3 of running Flutter logic on Elpian is a compiler from Dart source to
//! something the VM already executes. Elpian ingests a JS subset directly
//! (`create_vm_from_js`), so this front-end lowers a **Dart subset** to that JS
//! subset — parsing the Dart-specific surface (typed declarations, `~/`, string
//! interpolation, C-style `for`) and erasing/rewriting it into the VM's input.
//! Runtime intrinsics are still reached through `askHost`, exactly as the
//! hand-written JS path does, so the front-end is purely a *language* layer.
//!
//! Supported subset (grows over the roadmap):
//! * top-level function declarations and statements; typed or `var`/`final`
//!   locals (types are parsed and erased);
//! * **classes**: fields (with initializers), constructors incl. `this.x`
//!   initializing formals, methods, `extends`/`super`, instantiation
//!   (`ClassName(args)`), member access, and `this`. Bare field/method
//!   references inside methods resolve to `this.member` (including inherited
//!   members), so idiomatic Dart lowers to valid JS classes;
//! * **control flow**: `if`/`else`, `while`, `do`/`while`, C-style `for` and
//!   **`for-in`** (lowered to `while`), `switch`/`case`/`default` (with the
//!   `default` arm), `break`/`continue`, `return`, and blocks;
//! * **exceptions**: `throw` / `rethrow` and `try` / `on T` / `catch (e[, st])`
//!   / `finally`, lowered to the VM's neutral try-catch opcode (the `on Type`
//!   filter and stack-trace binding are erased; a native builtin error is a
//!   catchable `{ name, message }`);
//! * expressions: literals (incl. **hex integers** `0xFF2196F3` for colours),
//!   identifiers, calls, list literals, indexing,
//!   assignment + compound assignment (`+= -= *= /= %= &= |= ^= <<= >>= >>>=`
//!   and `??=`), `++`/`--`, ternary `?:`, the full binary tower
//!   `?? || && | ^ & == != < <= > >= << >> >>> + - * / % ~/`, unary `! - ~`,
//!   the null-assertion `x!` (erased), null-aware `obj?.member`, and **cascades**
//!   `target..a()..b = c`;
//! * string interpolation (`"$x"`, `"${expr}"`) lowered to concatenation;
//! * `print(x)` lowered to `askHost("log",[x])`; `~/` and the bitwise/shift
//!   operators lower to the VM's universal builtins (the operators themselves
//!   never reach the VM). `main()` is auto-invoked if present.
//!
//! * **closures / function expressions**: `(a) => expr`, `(a) { body }`, and
//!   arrow bodies for function/method declarations (`int f() => expr;`). These
//!   plus the VM's higher-order Iterable methods (`map`/`where`/`fold`/`reduce`/
//!   `any`/`every`/`firstWhere`/`expand`/`takeWhile`/`sort`/…, bound in the VM
//!   to prelude functions) run real functional Dart. Closures capture **by
//!   reference** for mutated captured locals — the boxing transform is applied by
//!   the downstream JS layer (js2elpian), so `forEach((e) => acc += e)` and
//!   closure counters propagate correctly.
//!
//! * **named & optional parameters** (`{this.width}`, `[int x = 0]`, `required`)
//!   with defaults, lowered to a trailing options object; named arguments at
//!   call sites; and **generic type args** in type positions (erased).
//! * **idiomatic-Flutter surface**: metadata annotations (`@override`,
//!   `@immutable`, …, dropped), `abstract`/soft class modifiers (erased),
//!   `const` constructors/expressions (erased to plain instantiation), `enum`s
//!   (lowered to an object mapping each constant to its name string), `static`
//!   fields/methods and named constructors (reached as `Class.member`, backed by
//!   the VM's static-member support), **getters** (`T get x => …`, emitted as a
//!   method and called when read as `obj.x`), and the `??` null-coalescing
//!   operator (emitted onto the VM's neutral short-circuit opcode, which tests
//!   the first-class null). A `void` arrow body (`void f() => g();`) is a
//!   statement, not a `return`.
//! * **`async`/`await`**: `async` functions are CPS-transformed to return a
//!   `Future` built from `.then` continuations driven by the microtask loop;
//!   `await` sequences them. Bounded: awaits are transformed only at statement
//!   top level (var init, expression statement, `return await`) — awaits nested
//!   inside loops, conditionals, or sub-expressions need full state-machine
//!   lowering and are not yet handled.
//!
//! NOT yet covered (later phases): mixins, pattern matching, initializer lists
//! with super-args, async closures / awaits inside control flow, generic
//! *typed-local* declarations, and by-reference closure capture.


pub mod ast;
pub mod emitter;
pub mod lexer;
pub mod parser;
pub mod token;

use crate::token::Tok;
use crate::ast::Item;
use crate::lexer::Lexer;
use crate::parser::Parser;
use crate::emitter::Emitter;

/// Transpile Dart-subset source to the JS subset the Elpian VM ingests.
pub fn transpile(dart: &str) -> Result<String, String> {
    Ok(transpile_program(dart)?.0)
}

/// A declared class and its optional superclass. Retained for callers that want
/// the source-declared hierarchy; the VM itself answers reified `is`/`as`
/// natively from each instance's prototype chain, so no external table is needed.
pub type ClassInfo = (String, Option<String>);

/// Transpile and also return the declared class hierarchy, so the runtime can
/// answer reified `is`/`as` checks over the same class relationships.
pub fn transpile_program(dart: &str) -> Result<(String, Vec<ClassInfo>), String> {
    let toks = Lexer::new(dart).tokenize()?;
    let class_names = {
        let mut set = std::collections::HashSet::new();
        for w in toks.windows(2) {
            if w[0] == Tok::Kw("class".into()) {
                if let Tok::Ident(n) = &w[1] {
                    set.insert(n.clone());
                }
            }
        }
        set
    };
    let items = Parser::new(toks).parse_program()?;
    // By-reference closure capture (boxing captured, mutated locals) is applied
    // downstream by js2elpian on the emitted JS, so it is intentionally *not*
    // done here — doing it in both layers would double-box.
    let classes: Vec<ClassInfo> = items
        .iter()
        .filter_map(|it| match it {
            Item::Class(c) => Some((c.name.clone(), c.superclass.clone())),
            _ => None,
        })
        .collect();
    let mut em = Emitter::new(class_names);
    em.emit_program(&items);
    Ok((em.out, classes))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn erases_types_and_lowers_trunc_div_to_int_div() {
        // `~/` is a Dart-specific operator: it never reaches the VM. The
        // front-end lowers it to the universal `intDiv` builtin at compile time.
        let js = transpile("int x = 7 ~/ 2;").unwrap();
        assert!(js.contains("var x = intDiv(7, 2)"), "got: {js}");
        assert!(!js.contains("~/"), "no Dart operator in the emitted program: {js}");
    }

    #[test]
    fn lowers_for_to_while_and_print_to_host_call() {
        let js = transpile("void main() { for (int i = 0; i < 3; i = i + 1) { print(i); } }").unwrap();
        assert!(js.contains("while ("), "got: {js}");
        assert!(js.contains("askHost(\"log\""), "got: {js}");
        assert!(js.contains("main();"), "should auto-call main: {js}");
    }

    #[test]
    fn string_interpolation_becomes_concatenation() {
        let js = transpile(r#"var s = "n=$x done";"#).unwrap();
        assert!(js.contains('+'), "interpolation should concat: {js}");
        assert!(js.contains("(x)"), "should reference x: {js}");
    }

    #[test]
    fn annotations_abstract_and_const_are_erased() {
        let dart = "@immutable\nabstract class Shape { const Shape(); }\n\
                    var s = const Shape();";
        let js = transpile(dart).unwrap();
        assert!(js.contains("class Shape"), "abstract erased to a class: {js}");
        assert!(!js.contains('@'), "annotation stripped: {js}");
        assert!(js.contains("new Shape()"), "const erased to instantiation: {js}");
    }

    #[test]
    fn statics_getters_and_named_constructors() {
        let dart = "class Color {\n\
                      final int value;\n\
                      const Color(this.value);\n\
                      static const int black = 4278190080;\n\
                      static Color fromValue(int v) => Color(v);\n\
                      int get red => (value ~/ 65536) % 256;\n\
                    }";
        let js = transpile(dart).unwrap();
        assert!(js.contains("static black = 4278190080"), "static field: {js}");
        assert!(js.contains("static fromValue"), "static method: {js}");
        // A getter is emitted as a method and *called* when read as a bare member.
        assert!(js.contains("red("), "getter emitted as method: {js}");
    }

    #[test]
    fn enum_lowers_to_name_object() {
        let js = transpile("enum Axis { horizontal, vertical }").unwrap();
        assert!(
            js.contains("var Axis = {horizontal: \"horizontal\", vertical: \"vertical\"}"),
            "enum -> name object: {js}"
        );
    }

    #[test]
    fn is_and_as_emit_native_intrinsics_not_host_calls() {
        // Reified `is`/`as` lower to the `__isType`/`__asType` compiler intrinsics
        // (native VM opcode), not a `dart:core/isType` host round-trip. Generics
        // are erased to the base type name, and Dart's type spellings are resolved
        // to the VM's neutral names here, at compile time (`List`→`list`,
        // `double`→`float`, …); a user class name passes through unchanged.
        let js = transpile(
            "var a = x is List<int>; var b = y as Foo; var c = z is double; var d = w is String;",
        )
        .unwrap();
        assert!(js.contains("__isType(x, \"list\")"), "is -> neutral name: {js}");
        assert!(js.contains("__asType(y, \"Foo\")"), "as -> class passthrough: {js}");
        assert!(js.contains("__isType(z, \"float\")"), "double -> float: {js}");
        assert!(js.contains("__isType(w, \"string\")"), "String -> string: {js}");
        assert!(!js.contains("isType\""), "no isType host round-trip: {js}");
        assert!(!js.contains("asType\""), "no asType host round-trip: {js}");
    }

    #[test]
    fn is_object_and_dynamic_are_pure_compile_time_lowerings() {
        // `Object` / `dynamic` never reach the VM's type-test opcode: their Dart
        // semantics are decided here in the front-end.
        let js = transpile("var a = x is Object; var b = y as Object; var c = z is dynamic;").unwrap();
        assert!(js.contains("(x != null)"), "is Object -> null test: {js}");
        assert!(!js.contains("__isType(x"), "no opcode for is Object: {js}");
        assert!(js.contains("var b = y"), "as Object -> value: {js}");
        assert!(js.contains("__isType(z, \"any\")"), "is dynamic -> any: {js}");
    }

    #[test]
    fn null_coalescing_emits_native_operator() {
        // `??` is a native short-circuiting VM operator now, not a helper call.
        let js = transpile("var x = a ?? 5;").unwrap();
        assert!(js.contains("(a ?? 5)"), "?? -> native operator: {js}");
        assert!(!js.contains("__ifNull"), "no helper lowering: {js}");
    }

    #[test]
    fn void_arrow_body_is_a_statement_not_a_return() {
        // A void arrow function must not `return` its call's value.
        let js = transpile("void main() => run();").unwrap();
        assert!(js.contains("function main"), "got: {js}");
        assert!(!js.contains("return run()"), "void arrow must be a statement: {js}");
    }

    #[test]
    fn hex_integer_literals_lex() {
        let js = transpile("var c = 0xFF2196F3;").unwrap();
        assert!(js.contains("4280391411"), "hex parsed to its value: {js}");
    }

    #[test]
    fn for_in_desugars_to_indexed_while() {
        // Typed loop var, bare form, and a C-style `for` in the same program all
        // parse; the for-in lowers to a length-bounded while over the iterable.
        let js = transpile(
            "void main() { for (var x in xs) { total = total + x; } \
             for (int i = 0; i < 3; i = i + 1) { print(i); } }",
        )
        .unwrap();
        assert!(js.contains("__for_it0"), "for-in should bind an iterator temp: {js}");
        assert!(js.contains(".length"), "for-in should bound on length: {js}");
        assert!(js.contains("while"), "for-in lowers to while: {js}");
    }

    #[test]
    fn parses_function_with_typed_params() {
        let js = transpile("int add(int a, int b) { return a + b; }").unwrap();
        assert!(js.contains("function add(a, b)"), "got: {js}");
    }

    #[test]
    fn emits_native_class_with_field_resolution() {
        let dart = r#"
            class Counter {
                int value = 0;
                Counter(this.value);
                void inc() { value = value + 1; }
            }
        "#;
        let js = transpile(dart).unwrap();
        assert!(js.contains("class Counter {"), "got: {js}");
        assert!(js.contains("constructor(value)"), "got: {js}");
        assert!(js.contains("this.value = value"), "got: {js}");
        // Bare field ref inside a method resolves to this.value.
        assert!(js.contains("this.value = (this.value + 1)"), "got: {js}");
    }

    #[test]
    fn emits_inheritance_and_super() {
        let dart = "class A { } class B extends A { int x = 1; }";
        let js = transpile(dart).unwrap();
        assert!(js.contains("class B extends A {"), "got: {js}");
        assert!(js.contains("super();"), "got: {js}");
    }

    #[test]
    fn instantiation_and_ternary_and_compound() {
        let dart = "class P { } var p = P(); var y = 1 > 0 ? 2 : 3; var z = 5; z += 4;";
        let js = transpile(dart).unwrap();
        assert!(js.contains("new P()"), "got: {js}");
        assert!(js.contains("? 2 : 3"), "got: {js}");
        assert!(js.contains("z += 4"), "got: {js}");
    }

    #[test]
    fn core_member_spellings_resolve_to_universal_names() {
        // Dart core-type member spellings are mapped to the VM's universal stdlib
        // names at compile time — the VM never sees `add`/`toUpperCase`/… .
        let dart = "void main() {\n\
                      var xs = [];\n\
                      xs.add(1);\n\
                      xs.addAll([2, 3]);\n\
                      xs.removeLast();\n\
                      var s = \"hi\".toUpperCase();\n\
                      var n = (3.7).toInt();\n\
                      var m = {};\n\
                      var has = m.containsKey(\"k\");\n\
                    }";
        let js = transpile(dart).unwrap();
        assert!(js.contains("xs.push(1)"), "add -> push: {js}");
        assert!(js.contains("xs.pushAll("), "addAll -> pushAll: {js}");
        assert!(js.contains("xs.pop()"), "removeLast -> pop: {js}");
        assert!(js.contains(".upper()"), "toUpperCase -> upper: {js}");
        assert!(js.contains(".int()"), "toInt -> int: {js}");
        assert!(js.contains(".has("), "containsKey -> has: {js}");
        // None of the Dart spellings survive into the emitted program.
        assert!(!js.contains(".add(1)"), "no Dart add spelling: {js}");
        assert!(!js.contains("toUpperCase"), "no Dart toUpperCase spelling: {js}");
    }

    #[test]
    fn user_method_named_like_a_core_member_is_not_rewritten() {
        // A user class method whose name collides with a core spelling (`add`)
        // must not be rewritten to the `push` builtin — it addresses the object.
        let dart = "class Bag {\n\
                      void add(int x) { }\n\
                    }\n\
                    void main() { var b = Bag(); b.add(5); }";
        let js = transpile(dart).unwrap();
        assert!(js.contains("b.add(5)"), "user add() preserved, not renamed: {js}");
        assert!(!js.contains("b.push(5)"), "user method not turned into a builtin: {js}");
    }
}

