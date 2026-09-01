//! # js2elpian — the JavaScript → Elpian compiler
//!
//! Lowers a practical subset of JavaScript source to the **Elpian AST JSON**
//! that [`elpian_vm`] executes, then (optionally) through the VM's `compile_ast`
//! bytecode serialiser. The Elpian VM itself is purely an executor of that
//! AST/bytecode — it has no notion of JavaScript. This crate owns the JS
//! language front-end (tokenizer + recursive-descent / precedence-climbing
//! parser + closure/class desugaring); the VM owns execution.
//!
//! ## Supported surface
//!
//! * **operators**: the full binary tower `?? || && | ^ & == === != !== < <= >
//!   >= << >> >>> + - * / % **`, unary `! - + ~ typeof void delete`, `instanceof`
//!   / `in`, optional chaining `?.` (member / index / call), and every
//!   assignment form (`= += … **= &= |= ^= <<= >>= >>>= &&= ||= ??=`, `++`/`--`).
//!   Bitwise & shift operators lower to universal builtins with JS 32-bit
//!   semantics; `??`/`&&`/`||` are the VM's short-circuit opcodes.
//! * **statements**: `let`/`const`/`var` (incl. destructuring), `function`,
//!   `class` (fields, methods, `extends`/`super`, statics), `if`/`else`,
//!   `while`, `do`/`while`, C-style `for`, `for-of`, `for-in`, `switch`/`case`/
//!   `default` (default desugars to an if-chain), `break`/`continue`, `return`,
//!   `throw`, and `try`/`catch`/`finally` (over the VM's neutral exception
//!   opcode).
//! * **closures capture by reference**: a post-parse transform boxes locals a
//!   nested closure mutates into one-element arrays, so `arr.forEach(x => sum +=
//!   x)` propagates (see [`transforms`]).
//! * **methods & statics**: JS core-member spellings map to the VM's universal
//!   stdlib names at compile time (`includes`→`contains`, `filter`→`where`,
//!   `some`→`any`, `replace`→`replaceFirst`, …), and the static namespaces
//!   `Math` / `JSON` / `Object` / `Number` / `Array` / `console` plus the
//!   `parseInt`/`parseFloat` globals resolve to builtins / intrinsics. The
//!   higher-order Array/Map methods run as guest prelude functions.
//!
//! ```text
//!   JS source ──parse_js──▶ Elpian AST JSON ──compile_ast (elpian-vm)──▶ bytecode
//! ```
//!
//! Convenience entry points ([`create_vm_from_js`], [`compile_js_to_ast`], …)
//! parse and then hand the AST to `elpian_vm::api`, registering / validating a
//! VM through the same `from ast` path every Elpian front-end uses.

use std::collections::{HashMap, HashSet};

use serde_json::{json, Value};

mod transforms;

/// Front-end debug logging (compiled out in practice; kept for parity with the
/// original in-VM front-end).
#[allow(dead_code)]
fn log(_s: &str) {}

// ============================================================================
// JavaScript front-end
//
// `parse_js` turns a practical subset of JavaScript source into the very same
// Elpian AST JSON that the hand-written test helpers and external front-ends
// emit (see the node shapes consumed by `compile_ast` / `serialize_expr`
// above). It is intentionally self-contained — a tokenizer plus a
// recursive-descent / precedence-climbing parser — so the VM can build an Elpa
// instance straight from JS code without an off-VM toolchain.
//
// The pipeline mirrors the AST path exactly:
//
//     JS source ──parse_js──▶ Elpian AST JSON ──compile_ast──▶ bytecode
//
// i.e. JS is first lowered to the documented AST and then handed to the same
// `from ast` compiler that every other entry point uses.
//
// Supported subset (everything the AST/bytecode actually models):
//   * `let` / `const` / `var` declarations (→ `definition`).
//   * assignment, including `+= -= *= /= %=` and `++` / `--` (→ `assignment`).
//     A simple target (`x`, `a.b`, `a[i]`) uses the native `assignment`; a nested
//     or computed target (`a.b.c`, `a[i].x`, `o.a[i]`) is lowered to a
//     `__setIndex(base, key, value)` builtin call, so deep assignment works.
//   * `function name(params) { ... }` (→ `functionDefinition`).
//   * `return` (→ `returnOperation`).
//   * `if` / `else if` / `else` (→ `ifStmt` chains).
//   * `while` and C-style `for` loops (→ `loopStmt`; `for` is desugared into an
//     init prefix plus a `loopStmt` whose body carries the update step).
//   * `switch` / `case` (→ `switchStmt`; `default` and `break` are accepted but
//     not modelled by the bytecode, so they are dropped).
//   * expressions: numbers, strings, booleans, identifiers, arrays, objects,
//     member access (`a.b` / `a[i]` → `indexer`), calls (→ `functionCall`),
//     the arithmetic/comparison operators the VM understands
//     (`+ - * / % ** == === != !== < <= > >=`, with `**`→`^`,
//     `===`→`==`, `!==`→`!=`) and the `!` / unary `-` prefixes.
//   * `class` declarations with a `constructor`, instance methods, class-field
//     initialisers, single inheritance (`extends`) and `super(...)` constructor
//     chaining; `new C(...)` and a bare `C(...)` both construct. Lowered to a
//     factory function whose methods are closures over a `this` object — no new
//     opcode (see `parse_class`). `this` is an ordinary lexical local.
//   * arrow functions and `function` *expressions* (anonymous closures):
//     `x => e`, `(a, b) => e`, `() => { ... }`, `function (a) { ... }`. The VM
//     has no function-literal expression opcode — a function value only enters
//     scope via the `functionDefinition` *statement* (which captures the
//     enclosing locals as the closure's environment). So each arrow / function
//     expression is **desugared**: it is lifted into a synthetic, uniquely-named
//     `functionDefinition` hoisted just before the statement that uses it, and
//     the expression site is replaced by an `identifier` referencing that name.
//     A concise body `=> e` becomes `{ return e; }`. The lifted definition runs
//     in place, so it closes over exactly the locals lexically in scope there —
//     real per-call closures (e.g. a fresh `let` per loop iteration is captured
//     independently). The VM already supports calling such a value held in any
//     variable or object field (e.g. a widget's `onTap`).

#[derive(Clone, Debug, PartialEq)]
enum JsTok {
    Num(String),
    Str(String),
    Ident(String),
    Punct(String),
    /// A template / interpolated string (`` `a${x}b` ``) as an ordered list of
    /// literal-text and embedded-expression-source parts. The parser lowers it to
    /// the VM's native `template` node.
    Template(Vec<TplPart>),
    Eof,
}

/// One segment of a template literal: either fixed literal text or the raw
/// source of an interpolated `${ … }` expression (re-parsed by the parser).
#[derive(Clone, Debug, PartialEq)]
enum TplPart {
    Lit(String),
    Expr(String),
}

/// A binary operator's lowering: either a native arithmetic/comparison operator
/// (emitted as an `arithmetic` node) or a call to a universal builtin / prelude
/// helper (bitwise & shift operators, which have no VM opcode).
#[derive(Clone, Copy)]
enum JsBinOp {
    Arith(&'static str),
    Call(&'static str),
}

/// The JavaScript static namespaces whose `Namespace.member` accesses are
/// resolved to universal builtins / intrinsics at compile time (see
/// [`JsParser::resolve_namespace`]).
fn is_js_namespace(name: &str) -> bool {
    matches!(name, "Math" | "JSON" | "Object" | "Number" | "Array" | "console")
}

/// Decode one backslash escape starting at `chars[i]` (the backslash) inside a
/// string/template literal, pushing the decoded character(s) onto `out` and
/// returning the index just past the escape. Handles the classic single-char
/// escapes plus `\uXXXX` (with UTF-16 surrogate-pair combining), `\u{…}` and
/// `\xNN` — the forms JS tooling (Babel et al.) routinely emits for non-ASCII
/// text such as emoji.
fn js_escape(chars: &[char], i: usize, out: &mut String) -> usize {
    let n = chars.len();
    debug_assert!(chars[i] == '\\' && i + 1 < n);
    let c = chars[i + 1];
    let hex4 = |at: usize| -> Option<u32> {
        if at + 4 > n {
            return None;
        }
        let mut v = 0u32;
        for k in 0..4 {
            v = v * 16 + chars[at + k].to_digit(16)?;
        }
        Some(v)
    };
    match c {
        'n' => out.push('\n'),
        't' => out.push('\t'),
        'r' => out.push('\r'),
        'b' => out.push('\u{0008}'),
        'f' => out.push('\u{000C}'),
        'v' => out.push('\u{000B}'),
        '0' => out.push('\0'),
        'x' => {
            // \xNN
            if i + 4 <= n {
                if let (Some(h), Some(l)) = (chars[i + 2].to_digit(16), chars[i + 3].to_digit(16)) {
                    out.push(char::from_u32(h * 16 + l).unwrap_or('\u{FFFD}'));
                    return i + 4;
                }
            }
            out.push('x');
        }
        'u' => {
            // \u{XXXXXX}
            if i + 2 < n && chars[i + 2] == '{' {
                let mut j = i + 3;
                let mut v = 0u32;
                let mut any = false;
                while j < n && chars[j] != '}' {
                    match chars[j].to_digit(16) {
                        Some(d) => {
                            v = v.saturating_mul(16).saturating_add(d);
                            any = true;
                            j += 1;
                        }
                        None => break,
                    }
                }
                if any && j < n && chars[j] == '}' {
                    out.push(char::from_u32(v).unwrap_or('\u{FFFD}'));
                    return j + 1;
                }
                out.push('u');
                return i + 2;
            }
            // \uXXXX — combine a high+low surrogate pair into one scalar.
            if let Some(hi) = hex4(i + 2) {
                if (0xD800..0xDC00).contains(&hi)
                    && i + 8 < n
                    && chars[i + 6] == '\\'
                    && chars[i + 7] == 'u'
                {
                    if let Some(lo) = hex4(i + 8) {
                        if (0xDC00..0xE000).contains(&lo) {
                            let scalar = 0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00);
                            out.push(char::from_u32(scalar).unwrap_or('\u{FFFD}'));
                            return i + 12;
                        }
                    }
                }
                out.push(char::from_u32(hi).unwrap_or('\u{FFFD}'));
                return i + 6;
            }
            out.push('u');
        }
        other => out.push(other),
    }
    i + 2
}

fn tokenize_js(src: &str) -> Vec<JsTok> {
    let chars: Vec<char> = src.chars().collect();
    let n = chars.len();
    let mut i = 0usize;
    let mut toks: Vec<JsTok> = vec![];
    // Longest punctuators first so the greedy scan never splits `===` into
    // `==` + `=`, `>>>` into `>>` + `>`, and so on.
    let puncts: &[&str] = &[
        ">>>=", "...", "===", "!==", "**=", "<<=", ">>=", ">>>", "&&=", "||=", "??=", "**",
        "??", "==", "!=", "<=", ">=", "=>", "&&", "||", "++", "--", "+=", "-=", "*=", "/=",
        "%=", "&=", "|=", "^=", "?.", "<<", ">>", "(", ")", "{", "}", "[", "]", ";", ",", ".",
        ":", "?", "<", ">", "=", "+", "-", "*", "/", "%", "!", "^", "&", "|", "~",
    ];
    while i < n {
        let c = chars[i];
        if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
            i += 1;
            continue;
        }
        // Comments.
        if c == '/' && i + 1 < n && chars[i + 1] == '/' {
            i += 2;
            while i < n && chars[i] != '\n' {
                i += 1;
            }
            continue;
        }
        if c == '/' && i + 1 < n && chars[i + 1] == '*' {
            i += 2;
            while i + 1 < n && !(chars[i] == '*' && chars[i + 1] == '/') {
                i += 1;
            }
            i += 2;
            continue;
        }
        // String literals (single or double quoted) with the common escapes.
        if c == '"' || c == '\'' {
            let quote = c;
            i += 1;
            let mut s = String::new();
            while i < n && chars[i] != quote {
                if chars[i] == '\\' && i + 1 < n {
                    i = js_escape(&chars, i, &mut s);
                } else {
                    s.push(chars[i]);
                    i += 1;
                }
            }
            i += 1; // closing quote
            toks.push(JsTok::Str(s));
            continue;
        }
        // Template / interpolated string literals (backtick-quoted), split into
        // alternating literal-text and `${ … }` expression-source parts. Nested
        // braces inside an interpolation are balanced so `${ {a:1}[x] }` works.
        if c == '`' {
            i += 1;
            let mut parts: Vec<TplPart> = vec![];
            let mut lit = String::new();
            while i < n && chars[i] != '`' {
                if chars[i] == '\\' && i + 1 < n {
                    i = js_escape(&chars, i, &mut lit);
                    continue;
                }
                if chars[i] == '$' && i + 1 < n && chars[i + 1] == '{' {
                    if !lit.is_empty() {
                        parts.push(TplPart::Lit(std::mem::take(&mut lit)));
                    }
                    i += 2; // skip `${`
                    let mut depth = 1i32;
                    let mut expr = String::new();
                    while i < n && depth > 0 {
                        match chars[i] {
                            '{' => depth += 1,
                            '}' => {
                                depth -= 1;
                                if depth == 0 {
                                    break;
                                }
                            }
                            _ => {}
                        }
                        expr.push(chars[i]);
                        i += 1;
                    }
                    i += 1; // skip closing `}`
                    parts.push(TplPart::Expr(expr));
                    continue;
                }
                lit.push(chars[i]);
                i += 1;
            }
            i += 1; // closing backtick
            if !lit.is_empty() || parts.is_empty() {
                parts.push(TplPart::Lit(lit));
            }
            toks.push(JsTok::Template(parts));
            continue;
        }
        // Numeric literals (integer, fractional, exponent, and the 0x / 0b / 0o
        // radix forms — normalised to their decimal value at lex time).
        //
        // A leading-dot fraction (`.45`) is legal JavaScript and is exactly what
        // a minifying codegen emits for `0.45` — oxc, which the Elpian CLI runs
        // ahead of this front-end, does so. Without this branch every fractional
        // literal between -1 and 1 in a TypeScript source failed to compile with
        // "unexpected token '.'", which for graphics-shaped code is most of
        // them. Guarded on a following digit so member access (`a.b`) and the
        // spread token still tokenize as punctuation.
        if c == '.' && i + 1 < n && chars[i + 1].is_ascii_digit() {
            let start = i;
            i += 1;
            while i < n && chars[i].is_ascii_digit() {
                i += 1;
            }
            if i < n && (chars[i] == 'e' || chars[i] == 'E') {
                i += 1;
                if i < n && (chars[i] == '+' || chars[i] == '-') {
                    i += 1;
                }
                while i < n && chars[i].is_ascii_digit() {
                    i += 1;
                }
            }
            // Emit with the leading zero restored so every downstream consumer
            // sees a conventional literal.
            toks.push(JsTok::Num(format!("0{}", chars[start..i].iter().collect::<String>())));
            continue;
        }
        if c.is_ascii_digit() {
            if c == '0' && i + 1 < n && matches!(chars[i + 1], 'x' | 'X' | 'b' | 'B' | 'o' | 'O') {
                let radix = match chars[i + 1] {
                    'x' | 'X' => 16,
                    'b' | 'B' => 2,
                    _ => 8,
                };
                let start = i + 2;
                let mut j = start;
                while j < n && (chars[j].is_ascii_alphanumeric() || chars[j] == '_') {
                    j += 1;
                }
                let digits: String = chars[start..j].iter().filter(|c| **c != '_').collect();
                if let Ok(v) = i64::from_str_radix(&digits, radix) {
                    toks.push(JsTok::Num(v.to_string()));
                    i = j;
                    continue;
                }
            }
            let start = i;
            while i < n && chars[i].is_ascii_digit() {
                i += 1;
            }
            if i < n && chars[i] == '.' {
                i += 1;
                while i < n && chars[i].is_ascii_digit() {
                    i += 1;
                }
            }
            if i < n && (chars[i] == 'e' || chars[i] == 'E') {
                i += 1;
                if i < n && (chars[i] == '+' || chars[i] == '-') {
                    i += 1;
                }
                while i < n && chars[i].is_ascii_digit() {
                    i += 1;
                }
            }
            toks.push(JsTok::Num(chars[start..i].iter().collect()));
            continue;
        }
        // Identifiers and keywords.
        if c.is_alphabetic() || c == '_' || c == '$' {
            let start = i;
            while i < n && (chars[i].is_alphanumeric() || chars[i] == '_' || chars[i] == '$') {
                i += 1;
            }
            toks.push(JsTok::Ident(chars[start..i].iter().collect()));
            continue;
        }
        // Punctuators, greedily matching the longest spelling.
        let mut matched = false;
        for p in puncts.iter() {
            let pl = p.chars().count();
            if i + pl <= n {
                let slice: String = chars[i..i + pl].iter().collect();
                if &slice == p {
                    toks.push(JsTok::Punct((*p).to_string()));
                    i += pl;
                    matched = true;
                    break;
                }
            }
        }
        if !matched {
            // Unknown character: skip it rather than abort the whole parse.
            i += 1;
        }
    }
    toks.push(JsTok::Eof);
    toks
}

// ---- AST node builders (exact shapes consumed by `compile_ast`) -------------

fn js_num_literal(s: &str) -> Value {
    if s.contains('.') || s.contains('e') || s.contains('E') {
        json!({ "type": "f64", "data": { "value": s.parse::<f64>().unwrap_or(0.0) } })
    } else {
        match s.parse::<i64>() {
            Ok(v) => json!({ "type": "i64", "data": { "value": v } }),
            Err(_) => json!({ "type": "f64", "data": { "value": s.parse::<f64>().unwrap_or(0.0) } }),
        }
    }
}
fn js_int(n: i64) -> Value {
    json!({ "type": "i64", "data": { "value": n } })
}
/// The VM's first-class null literal — what JS `null` and `undefined` lower to,
/// and the value of every "absent" position (an uninitialised `let`, a bare
/// `return`, a class field with no initialiser).
fn js_null() -> Value {
    json!({ "type": "null" })
}
fn js_ident(name: &str) -> Value {
    json!({ "type": "identifier", "data": { "name": name } })
}
fn js_string(s: &str) -> Value {
    json!({ "type": "string", "data": { "value": s } })
}
fn js_arith(op: &str, a: Value, b: Value) -> Value {
    json!({ "type": "arithmetic", "data": { "operation": op, "operand1": a, "operand2": b } })
}
fn js_def(name: &str, val: Value) -> Value {
    json!({ "type": "definition", "data": { "leftSide": js_ident(name), "rightSide": val } })
}
/// Wrap a value in a spread element (`...value`) — the VM's universal
/// expand-in-place marker, valid in array literals, object literals and call
/// argument lists.
fn js_spread(v: Value) -> Value {
    json!({ "type": "spread", "data": { "value": v } })
}
/// Build an assignment for any JS lvalue. A bare identifier or a *direct* indexer
/// (`a.b` / `a[i]`, whose base is a named variable) uses the native `assignment`
/// node the bytecode models. A *nested or computed* base (`a.b.c`, `a[i].x`,
/// `o.a[i]`) — where the base is itself an expression — is lowered to a call to
/// the `__setIndex` builtin: the base expression evaluates to a container
/// reference and the builtin stores into it. This keeps deep assignment working
/// without the lvalue having to be a single named variable. Anything else yields
/// `None`, so the caller can drop the meaningless statement.
fn js_assign(target: Value, rhs: Value) -> Option<Value> {
    match target["type"].as_str().unwrap_or("") {
        "identifier" => {
            Some(json!({ "type": "assignment", "data": { "leftSide": target, "rightSide": rhs } }))
        }
        "indexer" => {
            if target["data"]["target"]["type"] == "identifier" {
                Some(json!({ "type": "assignment", "data": { "leftSide": target, "rightSide": rhs } }))
            } else {
                let base = target["data"]["target"].clone();
                let index = target["data"]["index"].clone();
                Some(json!({ "type": "functionCall", "data": {
                    "callee": js_ident("__setIndex"),
                    "args": [base, index, rhs]
                } }))
            }
        }
        _ => None,
    }
}
/// Fold a unary minus into the literal where possible, else lower to `0 - x`.
fn js_negate(v: Value) -> Value {
    if v["type"] == "i64" {
        if let Some(n) = v["data"]["value"].as_i64() {
            return js_int(-n);
        }
    }
    if v["type"] == "f64" {
        if let Some(n) = v["data"]["value"].as_f64() {
            return json!({ "type": "f64", "data": { "value": -n } });
        }
    }
    js_arith("-", js_int(0), v)
}
/// Short-circuiting `&&` / `||`. Modelled as a dedicated node (not an arithmetic
/// op) so the bytecode can evaluate the right operand lazily — `a && b` only
/// touches `b` when `a` is truthy, `a || b` only when `a` is falsy — exactly as
/// JavaScript requires (and as guard idioms like `obj && obj.x` depend on).
fn js_logical(op: &str, a: Value, b: Value) -> Value {
    json!({ "type": "logical", "data": { "operation": op, "operand1": a, "operand2": b } })
}
/// The conditional (ternary) operator `c ? a : b`. Like `&&`/`||` it is lazy:
/// only the taken branch is evaluated.
fn js_ternary(c: Value, a: Value, b: Value) -> Value {
    json!({ "type": "ternary", "data": { "condition": c, "consequent": a, "alternate": b } })
}

struct JsParser {
    toks: Vec<JsTok>,
    pos: usize,
    /// Synthetic `functionDefinition` nodes produced by desugaring arrow /
    /// function expressions, awaiting hoisting in front of the statement
    /// currently being parsed (drained by [`JsParser::parse_statement`]).
    lifted: Vec<Value>,
    /// Counter for unique synthetic closure names (`__anon_N`).
    anon_counter: usize,
    /// While parsing a class method body, the parent class name (if the class
    /// `extends` one) so `super.m(...)` can resolve to the parent's method.
    class_parent: Option<String>,
    /// Class names that declared at least one `static` member, with the per-class
    /// holder object `__static_<Name>`. A `C.member` access where `C` is such a
    /// class is rewritten to read off that holder (see [`JsParser::parse_postfix`]).
    class_statics: HashSet<String>,
    /// The constructor parameter list recorded for each class, so a derived class
    /// with no explicit constructor can synthesise one that forwards those args to
    /// `super` (JS's implicit-constructor behaviour).
    class_ctor_params: HashMap<String, Vec<String>>,
    /// Every method name declared by a class in the program (collected up front,
    /// since a call site can textually precede the declaration). A JS core-member
    /// spelling that collides with one of these is left untranslated so a user's
    /// own method still resolves against its object.
    user_members: HashSet<String>,
}

/// Compile-time resolution of a standard JavaScript core-type member spelling to
/// the VM's single **universal** stdlib name — the js2elpian counterpart of the
/// Dart front-end's mapping. Names JS already spells the universal way (`push`,
/// `pop`, `slice`, `indexOf`, `concat`, `split`, `substring`, `charAt`, `trim`,
/// `join`, `keys`, `values`, …) need no entry. Returns `None` when unchanged.
fn js_universal_member(name: &str) -> Option<&'static str> {
    Some(match name {
        // Array / iterable
        "includes" => "contains",
        "filter" => "where",
        "some" => "any",
        "flat" => "flatten",
        // String
        "toUpperCase" => "upper",
        "toLowerCase" => "lower",
        "charCodeAt" => "codeUnitAt",
        "codePointAt" => "codeUnitAt",
        // JS `replace(str, str)` replaces the *first* occurrence; `replaceAll`
        // replaces every one. The VM's `replace` is replace-all and
        // `replaceFirst` is first-only, so the mapping is crossed.
        "replace" => "replaceFirst",
        "replaceAll" => "replace",
        // Number
        "toFixed" => "toStringAsFixed",
        // Map
        "containsKey" => "has",
        "containsValue" => "hasValue",
        "delete" => "remove",
        "set" => "setKey",
        _ => return None,
    })
}

/// Runtime prelude prepended to every JS program — the js2elpian counterpart
/// of the Dart emitter's PRELUDE. Three groups of helpers, all written in the
/// supported JS subset and lowered through the same pipeline:
///
/// * **operator helpers** the parser lowers to (bitwise/shift with JS's 32-bit
///   semantics, `typeof`/`void`/`delete`, optional-chaining short-circuits);
/// * **`__List_*` / `__Map_*` higher-order methods** — the VM's member dispatch
///   binds a `list.map` / `.find` / `.sort` / `map.forEach` read to the matching
///   helper with the receiver as `this` (see `type_methods.rs`,
///   `Dispatch::Prelude`), so the callback runs as guest bytecode. Callbacks get
///   `(element, index)` for lists and `(value, key)` for maps, matching JS.
const JS_PRELUDE: &str = concat!(
    // ---- bitwise / shift operators (JS ToInt32/ToUint32 semantics) ----------
    "function __band(a, b){ return bitAnd(toInt32(a), toInt32(b)); }\n",
    "function __bor(a, b){ return bitOr(toInt32(a), toInt32(b)); }\n",
    "function __bxor(a, b){ return bitXor(toInt32(a), toInt32(b)); }\n",
    "function __bnot(a){ return bitNot(toInt32(a)); }\n",
    "function __shl(a, b){ return toInt32(shl(toInt32(a), __band(b, 31))); }\n",
    "function __shr(a, b){ return shr(toInt32(a), __band(b, 31)); }\n",
    "function __ushr(a, b){ return ushr(toUint32(a), __band(b, 31)); }\n",
    // ---- typeof / void / delete ---------------------------------------------
    "function __typeof(x){ if (x == null) { return \"undefined\"; } if (__isType(x, \"bool\")) { return \"boolean\"; } if (__isType(x, \"number\")) { return \"number\"; } if (__isType(x, \"string\")) { return \"string\"; } if (__isType(x, \"function\")) { return \"function\"; } return \"object\"; }\n",
    "function __void(x){ return null; }\n",
    "function __delete(o, k){ delKey(o, k); return true; }\n",
    // ---- optional chaining ---------------------------------------------------
    "function __optGet(o, k){ if (o == null) { return null; } return o[k]; }\n",
    "function __optCall(o, m, a){ if (o == null) { return null; } return o[m](...a); }\n",
    "function __optCallFn(f, a){ if (f == null) { return null; } return f(...a); }\n",
    // ---- higher-order list methods (callback gets (element, index)) ---------
    "function __List_map(f){ var out = []; var i = 0; while (i < this.length) { out.push(f(this[i], i)); i = i + 1; } return out; }\n",
    "function __List_where(f){ var out = []; var i = 0; while (i < this.length) { if (f(this[i], i)) { out.push(this[i]); } i = i + 1; } return out; }\n",
    "function __List_forEach(f){ var i = 0; while (i < this.length) { f(this[i], i); i = i + 1; } return null; }\n",
    "function __List_fold(init, f){ var acc = init; var i = 0; while (i < this.length) { acc = f(acc, this[i]); i = i + 1; } return acc; }\n",
    "function __List_any(f){ var i = 0; while (i < this.length) { if (f(this[i], i)) { return true; } i = i + 1; } return false; }\n",
    "function __List_every(f){ var i = 0; while (i < this.length) { if (!f(this[i], i)) { return false; } i = i + 1; } return true; }\n",
    // JS reduce: an explicit initial value starts at index 0; without one the
    // seed is this[0] and iteration starts at index 1.
    "function __List_reduce(f, init){ var acc; var i; if (init == null) { acc = this[0]; i = 1; } else { acc = init; i = 0; } while (i < this.length) { acc = f(acc, this[i], i); i = i + 1; } return acc; }\n",
    "function __List_reduceRight(f, init){ var acc; var i; if (init == null) { acc = this[this.length - 1]; i = this.length - 2; } else { acc = init; i = this.length - 1; } while (i >= 0) { acc = f(acc, this[i], i); i = i - 1; } return acc; }\n",
    "function __List_find(f){ var i = 0; while (i < this.length) { if (f(this[i], i)) { return this[i]; } i = i + 1; } return null; }\n",
    "function __List_findIndex(f){ var i = 0; while (i < this.length) { if (f(this[i], i)) { return i; } i = i + 1; } return -1; }\n",
    "function __List_findLast(f){ var i = this.length - 1; while (i >= 0) { if (f(this[i], i)) { return this[i]; } i = i - 1; } return null; }\n",
    "function __List_findLastIndex(f){ var i = this.length - 1; while (i >= 0) { if (f(this[i], i)) { return i; } i = i - 1; } return -1; }\n",
    "function __List_flatMap(f){ var out = []; var i = 0; while (i < this.length) { var r = f(this[i], i); if (__isType(r, \"list\")) { var j = 0; while (j < r.length) { out.push(r[j]); j = j + 1; } } else { out.push(r); } i = i + 1; } return out; }\n",
    "function __List_takeWhile(f){ var out = []; var i = 0; while (i < this.length) { if (!f(this[i], i)) { return out; } out.push(this[i]); i = i + 1; } return out; }\n",
    "function __List_skipWhile(f){ var i = 0; while (i < this.length) { if (!f(this[i], i)) { break; } i = i + 1; } var out = []; while (i < this.length) { out.push(this[i]); i = i + 1; } return out; }\n",
    "function __List_removeWhere(f){ var i = 0; while (i < this.length) { if (f(this[i], i)) { splice(this, i, 1); } else { i = i + 1; } } return null; }\n",
    // Insertion sort with an optional comparator (JS/Dart `(a,b)=>number`);
    // without one, delegate to the native lexicographic/numeric sort.
    "function __List_sort(cmp){ if (cmp == null) { sort(this); return this; } var i = 1; while (i < this.length) { var x = this[i]; var j = i - 1; while (j >= 0 && cmp(this[j], x) > 0) { this[j + 1] = this[j]; j = j - 1; } this[j + 1] = x; i = i + 1; } return this; }\n",
    // ---- higher-order map methods (callback gets (value, key), JS Map order) -
    "function __Map_forEach(f){ var ks = keys(this); var i = 0; while (i < ks.length) { f(this[ks[i]], ks[i]); i = i + 1; } return null; }\n",
    "function __Map_removeWhere(f){ var ks = keys(this); var i = 0; while (i < ks.length) { if (f(this[ks[i]], ks[i])) { delKey(this, ks[i]); } i = i + 1; } return null; }\n",
    // ---- misc globals --------------------------------------------------------
    "function __identity(x){ return x; }\n",
    // `parseInt` / `parseFloat` — lenient numeric parses that yield null (JS
    // `NaN`) on failure rather than throwing.
    "function parseFloat(s){ return tryNum(s); }\n",
    "function parseInt(s){ var n = tryNum(s); if (n == null) { return null; } return floor(n); }\n",
);

/// Scan the token stream for class method declarations — an identifier at
/// class-body brace depth immediately followed by `(`. Used to guard the
/// JS→universal member rename against a user's own like-named methods.
fn collect_class_members(toks: &[JsTok]) -> HashSet<String> {
    let mut out = HashSet::new();
    let mut i = 0;
    while i < toks.len() {
        if matches!(&toks[i], JsTok::Ident(k) if k == "class") {
            // Advance to the opening brace of the class body.
            while i < toks.len() && !matches!(&toks[i], JsTok::Punct(p) if p == "{") {
                i += 1;
            }
            if i >= toks.len() {
                break;
            }
            // Walk the body, recording `ident (` at depth 1 (a member header).
            let mut depth = 0i32;
            while i < toks.len() {
                match &toks[i] {
                    JsTok::Punct(p) if p == "{" => depth += 1,
                    JsTok::Punct(p) if p == "}" => {
                        depth -= 1;
                        if depth == 0 {
                            break;
                        }
                    }
                    JsTok::Ident(name) if depth == 1 => {
                        if matches!(toks.get(i + 1), Some(JsTok::Punct(p)) if p == "(") {
                            out.insert(name.clone());
                        }
                    }
                    _ => {}
                }
                i += 1;
            }
        }
        i += 1;
    }
    out
}

impl JsParser {
    fn new(toks: Vec<JsTok>) -> Self {
        let user_members = collect_class_members(&toks);
        JsParser {
            toks,
            pos: 0,
            lifted: Vec::new(),
            anon_counter: 0,
            class_parent: None,
            class_statics: HashSet::new(),
            class_ctor_params: HashMap::new(),
            user_members,
        }
    }

    /// Resolve a JS member spelling to the VM's universal name, unless a user
    /// class declares a method by that name (then it addresses that object).
    fn resolve_member(&self, name: &str) -> String {
        if self.user_members.contains(name) {
            name.to_string()
        } else {
            js_universal_member(name).unwrap_or(name).to_string()
        }
    }
    fn peek(&self) -> &JsTok {
        &self.toks[self.pos]
    }
    fn advance(&mut self) -> JsTok {
        let t = self.toks[self.pos].clone();
        if self.pos + 1 < self.toks.len() {
            self.pos += 1;
        }
        t
    }
    fn at_eof(&self) -> bool {
        matches!(self.peek(), JsTok::Eof)
    }
    fn at_punct(&self, p: &str) -> bool {
        matches!(self.peek(), JsTok::Punct(s) if s == p)
    }
    fn eat_punct(&mut self, p: &str) -> bool {
        if self.at_punct(p) {
            self.advance();
            true
        } else {
            false
        }
    }
    fn expect_punct(&mut self, p: &str) {
        if !self.eat_punct(p) {
            panic!("js: expected '{}', found {:?}", p, self.peek());
        }
    }
    fn at_ident(&self, name: &str) -> bool {
        matches!(self.peek(), JsTok::Ident(s) if s == name)
    }
    fn eat_ident(&mut self, name: &str) -> bool {
        if self.at_ident(name) {
            self.advance();
            true
        } else {
            false
        }
    }
    fn expect_ident(&mut self, name: &str) {
        if !self.eat_ident(name) {
            panic!("js: expected keyword '{}', found {:?}", name, self.peek());
        }
    }
    fn expect_ident_name(&mut self) -> String {
        match self.advance() {
            JsTok::Ident(s) => s,
            t => panic!("js: expected identifier, found {:?}", t),
        }
    }

    fn parse_program(&mut self) -> Value {
        let mut body: Vec<Value> = vec![];
        while !self.at_eof() {
            body.extend(self.parse_statement());
        }
        json!({ "type": "program", "body": body })
    }

    // ---- Statements ---------------------------------------------------------

    /// Parse one statement, then hoist any arrow / function expressions it
    /// desugared into synthetic `functionDefinition`s *in front of* it, so each
    /// closure is defined (and captures its environment) right where it appears.
    fn parse_statement(&mut self) -> Vec<Value> {
        let mark = self.lifted.len();
        let mut stmts = self.parse_statement_inner();
        if self.lifted.len() > mark {
            let mut hoisted: Vec<Value> = self.lifted.split_off(mark);
            hoisted.append(&mut stmts);
            return hoisted;
        }
        stmts
    }

    fn parse_statement_inner(&mut self) -> Vec<Value> {
        if self.eat_punct(";") {
            return vec![];
        }
        if self.at_ident("async") {
            panic!("js: `async` functions are not supported — the Elpian VM has no event loop; use the timer host APIs (setTimeout/setInterval) and callback style instead");
        }
        if self.at_ident("function") {
            return vec![self.parse_function_decl()];
        }
        if self.at_ident("class") {
            return self.parse_class();
        }
        if self.at_ident("if") {
            return vec![self.parse_if()];
        }
        if self.at_ident("while") {
            return vec![self.parse_while()];
        }
        if self.at_ident("for") {
            return self.parse_for();
        }
        if self.at_ident("switch") {
            return self.parse_switch();
        }
        if self.at_ident("do") {
            return vec![self.parse_do_while()];
        }
        if self.at_ident("try") {
            return self.parse_try();
        }
        if self.at_ident("throw") {
            self.advance();
            let val = self.parse_expr();
            self.eat_punct(";");
            return vec![json!({ "type": "throwOperation", "data": { "value": val } })];
        }
        if self.at_ident("return") {
            self.advance();
            let val = if self.at_punct(";") || self.at_punct("}") || self.at_eof() {
                // A bare `return` yields JS `undefined` — the VM's null.
                js_null()
            } else {
                self.parse_expr()
            };
            self.eat_punct(";");
            return vec![json!({ "type": "returnOperation", "data": { "value": val } })];
        }
        if self.at_ident("break") {
            self.advance();
            self.eat_punct(";");
            return vec![json!({ "type": "breakStmt", "data": {} })];
        }
        if self.at_ident("continue") {
            self.advance();
            self.eat_punct(";");
            return vec![json!({ "type": "continueStmt", "data": {} })];
        }
        if self.at_punct("{") {
            // A bare block: inline its statements (the VM has one flat scope).
            return self.parse_block();
        }
        let s = self.parse_simple();
        self.eat_punct(";");
        s
    }

    /// A block `{ ... }` or, when unbraced, a single statement — returned as the
    /// flat operation list the AST uses for `body` arrays.
    fn parse_block_or_single(&mut self) -> Vec<Value> {
        if self.at_punct("{") {
            self.parse_block()
        } else {
            self.parse_statement()
        }
    }
    fn parse_block(&mut self) -> Vec<Value> {
        self.expect_punct("{");
        let mut out: Vec<Value> = vec![];
        while !self.at_punct("}") && !self.at_eof() {
            out.extend(self.parse_statement());
        }
        self.expect_punct("}");
        out
    }

    fn parse_function_decl(&mut self) -> Value {
        self.expect_ident("function");
        let name = self.expect_ident_name();
        self.expect_punct("(");
        let mut params: Vec<String> = vec![];
        while !self.at_punct(")") && !self.at_eof() {
            params.push(self.expect_ident_name());
            if !self.eat_punct(",") {
                break;
            }
        }
        self.expect_punct(")");
        let body = self.parse_block();
        json!({ "type": "functionDefinition", "data": { "name": name, "params": params, "body": body } })
    }

    // ---- classes (desugared to shared prototype + factory constructor) -------
    //
    // ES6 `class` syntax is lowered, in the front-end, onto plain objects + a
    // shared prototype. For
    //
    //     class C extends P {
    //         field = init;
    //         constructor(a) { super(a); this.x = a; }
    //         greet(n) { return this.x + n; }
    //     }
    //
    // it emits:
    //
    //   * each method as a *shared, top-level* function `__m_C__greet(n)` (defined
    //     once for the whole program, not per instance — so construction allocates
    //     no closures and method calls pay no capture-copy cost). `this` is not a
    //     declared parameter: when a method is read off an object the executor
    //     binds it to the receiver (see `bind_proto_method` / the indexer), so the
    //     body uses `this` as an ordinary local.
    //   * a prototype object `__proto_C = { __parent: __proto_P, greet: __m_C__greet }`
    //     built once, with `__parent` linking the inheritance chain.
    //   * an initialiser `__init_C(this, a)` that chains to `__init_P` (the leading
    //     `super(...)`), applies class-field initialisers, then runs the rest of
    //     the constructor body — `this` is an explicit parameter here.
    //   * a constructor `C(a)` = `let this = { __proto: __proto_C }; __init_C(this, a);
    //     return this;`. `new C(a)` and a bare `C(a)` both run it.
    //
    // The executor change this relies on is small and isolated: on a field miss,
    // the indexer resolves the name through the object's `__proto` chain and
    // returns the method bound to the receiver. No new opcode.
    fn parse_class(&mut self) -> Vec<Value> {
        self.expect_ident("class");
        let name = self.expect_ident_name();
        let parent = if self.eat_ident("extends") {
            Some(self.expect_ident_name())
        } else {
            None
        };
        self.expect_punct("{");

        // Lifted closures from field initialisers / `super(...)` args must stay
        // inside the installer (so they capture `this`), not leak to top level.
        let lifted_mark = self.lifted.len();

        let mut ctor_params: Vec<String> = vec![];
        let mut ctor_body: Vec<Value> = vec![];
        let mut had_ctor = false;
        let mut methods: Vec<(String, Vec<String>, Vec<Value>)> = vec![];
        let mut fields: Vec<(String, Value)> = vec![];
        // `static` members belong to the class itself, not its instances.
        let mut static_methods: Vec<(String, Vec<String>, Vec<Value>)> = vec![];
        let mut static_fields: Vec<(String, Value)> = vec![];

        // Method bodies may use `super.m(...)`; record the parent for the duration
        // of the class body so `parse_postfix` can resolve it (saving/restoring any
        // outer class context to support nested class definitions).
        let prev_parent = self.class_parent.take();
        self.class_parent = parent.clone();

        while !self.at_punct("}") && !self.at_eof() {
            if self.eat_punct(";") {
                continue;
            }
            let is_static = self.eat_ident("static");
            let member = self.expect_ident_name();
            if self.at_punct("(") {
                let params = self.parse_paren_params();
                let body = self.parse_block();
                if member == "constructor" {
                    ctor_params = params;
                    ctor_body = body;
                    had_ctor = true;
                } else if is_static {
                    static_methods.push((member, params, body));
                } else {
                    methods.push((member, params, body));
                }
            } else {
                // Class field: `name = expr;` or bare `name;` (defaults to null).
                let val = if self.eat_punct("=") { self.parse_expr() } else { js_null() };
                self.eat_punct(";");
                if is_static {
                    static_fields.push((member, val));
                } else {
                    fields.push((member, val));
                }
            }
        }
        self.expect_punct("}");
        self.class_parent = prev_parent;

        // A derived class with no explicit constructor implicitly forwards its
        // arguments to `super` (`constructor(...args) { super(...args); }`). The VM
        // front-end has no rest params, so adopt the parent constructor's parameter
        // list (recorded when the parent was parsed) and forward those by name.
        if !had_ctor {
            if let Some(p) = &parent {
                if let Some(pp) = self.class_ctor_params.get(p) {
                    ctor_params = pp.clone();
                }
            }
        }
        self.class_ctor_params.insert(name.clone(), ctor_params.clone());

        // Drain field-initialiser / super-arg closures lifted during member
        // parsing; they belong at the head of the installer body.
        let field_lifted: Vec<Value> = self.lifted.split_off(lifted_mark);

        // Extract a leading `super(...)` call from the constructor body, if any.
        let mut super_args: Vec<Value> = vec![];
        let mut had_super = false;
        let mut ctor_rest: Vec<Value> = vec![];
        for stmt in ctor_body.into_iter() {
            if !had_super
                && stmt["type"] == "functionCall"
                && stmt["data"]["callee"]["type"] == "identifier"
                && stmt["data"]["callee"]["data"]["name"] == "super"
            {
                super_args = stmt["data"]["args"].as_array().cloned().unwrap_or_default();
                had_super = true;
            } else {
                ctor_rest.push(stmt);
            }
        }
        // An implicit constructor forwards its (parent-derived) parameters to
        // `super`, so a subclass that omits the constructor still initialises the
        // base correctly.
        if !had_ctor && parent.is_some() {
            super_args = ctor_params.iter().map(|p| js_ident(p)).collect();
            had_super = true;
        }

        let mut out: Vec<Value> = vec![];

        // 1. Methods as *shared, top-level* functions (defined once, not per
        //    instance). `this` is supplied by the method-dispatch path — when a
        //    method is read off an object it is bound to the receiver via the
        //    closure machinery — so it is not a declared parameter; the body
        //    references it as an ordinary local. A `__proto_<Class>` object maps
        //    each method name to its function, with `__parent` linking the chain.
        let mut proto_map = serde_json::Map::new();
        // The class name is stamped on the prototype so the native reified
        // type-test opcode (`is`/`as`) can identify an instance by walking its
        // `__proto` → `__parent` chain, no external class table required.
        proto_map.insert("__class_name".to_string(), js_string(&name));
        if let Some(p) = &parent {
            proto_map.insert("__parent".to_string(), js_ident(&format!("__proto_{}", p)));
        } else {
            proto_map.insert("__parent".to_string(), js_null());
        }
        for (mname, params, body) in methods.into_iter() {
            let fname = format!("__m_{}__{}", name, mname);
            out.push(json!({ "type": "functionDefinition", "data": {
                "name": fname, "params": params, "body": body } }));
            proto_map.insert(mname.clone(), js_ident(&fname));
        }

        // 2. The per-instance initialiser: chain to the parent initialiser
        //    (`super`), apply class-field initialisers, then run the constructor
        //    body. `this` is an explicit parameter here (the constructor passes the
        //    freshly-made instance). No method closures are created per instance.
        let mut init_body: Vec<Value> = vec![];
        if let Some(p) = &parent {
            let mut args: Vec<Value> = vec![js_ident("this")];
            if had_super {
                args.extend(super_args);
            }
            init_body.push(json!({ "type": "functionCall", "data": {
                "callee": js_ident(&format!("__init_{}", p)), "args": args } }));
        }
        // Class-field initialisers (their lifted closures first, so they capture
        // `this`), applied after `super` per JS field-initialiser semantics.
        init_body.extend(field_lifted);
        for (fname, val) in fields.into_iter() {
            init_body.push(js_assign(
                json!({ "type": "indexer", "data": { "target": js_ident("this"), "index": js_string(&fname) } }),
                val,
            ).unwrap());
        }
        init_body.extend(ctor_rest);
        let mut init_params: Vec<String> = vec!["this".to_string()];
        init_params.extend(ctor_params.iter().cloned());
        out.push(json!({ "type": "functionDefinition", "data": {
            "name": format!("__init_{}", name), "params": init_params, "body": init_body } }));

        // 3. The shared prototype, built once at class-definition time.
        out.push(js_def(&format!("__proto_{}", name),
            json!({ "type": "object", "data": { "value": Value::Object(proto_map) } })));

        // 4. The constructor: a fresh object linked to the prototype, initialised,
        //    and returned. `new C(...)` and a bare `C(...)` both run this.
        let mut this_obj = serde_json::Map::new();
        this_obj.insert("__proto".to_string(), js_ident(&format!("__proto_{}", name)));
        let mut call_args: Vec<Value> = vec![js_ident("this")];
        for p in ctor_params.iter() {
            call_args.push(js_ident(p));
        }
        let ctor_body_out = vec![
            js_def("this", json!({ "type": "object", "data": { "value": Value::Object(this_obj) } })),
            json!({ "type": "functionCall", "data": {
                "callee": js_ident(&format!("__init_{}", name)), "args": call_args } }),
            json!({ "type": "returnOperation", "data": { "value": js_ident("this") } }),
        ];
        out.push(json!({ "type": "functionDefinition", "data": {
            "name": name, "params": ctor_params, "body": ctor_body_out } }));

        // 5. Static members live on the class itself. There is no class object in
        //    the VM (the class name is the constructor function), so collect them
        //    into a companion holder `__static_<Class>`; a `C.member` access where
        //    `C` is a class with statics is rewritten to read off that holder (see
        //    `parse_postfix`). Static methods are shared top-level functions, like
        //    instance methods.
        if !static_methods.is_empty() || !static_fields.is_empty() {
            let mut static_map = serde_json::Map::new();
            // Inherit the parent's static holder so `Child.staticOfParent` resolves.
            if let Some(p) = &parent {
                if self.class_statics.contains(p) {
                    static_map.insert("__parent".to_string(), js_ident(&format!("__static_{}", p)));
                }
            }
            for (mname, params, body) in static_methods.into_iter() {
                let fname = format!("__sm_{}__{}", name, mname);
                out.push(json!({ "type": "functionDefinition", "data": {
                    "name": fname, "params": params, "body": body } }));
                static_map.insert(mname, js_ident(&fname));
            }
            for (fname, val) in static_fields.into_iter() {
                static_map.insert(fname, val);
            }
            out.push(js_def(&format!("__static_{}", name),
                json!({ "type": "object", "data": { "value": Value::Object(static_map) } })));
            self.class_statics.insert(name.clone());
        }

        out
    }

    fn parse_if(&mut self) -> Value {
        self.expect_ident("if");
        self.expect_punct("(");
        let cond = self.parse_expr();
        self.expect_punct(")");
        let body = self.parse_block_or_single();
        let mut data = json!({ "condition": cond, "body": body });
        if self.eat_ident("else") {
            if self.at_ident("if") {
                // `else if` — attach the whole nested `ifStmt` as the elseif
                // chain; `serialize_condition_chain` walks `node["data"]`.
                data["elseifStmt"] = self.parse_if();
            } else {
                let else_body = self.parse_block_or_single();
                data["elseStmt"] = json!({ "data": { "body": else_body } });
            }
        }
        json!({ "type": "ifStmt", "data": data })
    }

    fn parse_while(&mut self) -> Value {
        self.expect_ident("while");
        self.expect_punct("(");
        let cond = self.parse_expr();
        self.expect_punct(")");
        let body = self.parse_block_or_single();
        json!({ "type": "loopStmt", "data": { "condition": cond, "body": body } })
    }

    /// `do body while (cond);` — the body runs at least once. Desugared to a
    /// `loopStmt` whose guard is `first || cond`: the first iteration is
    /// unconditional (and clears `first`), so a `continue` correctly re-tests the
    /// condition at the loop head.
    fn parse_do_while(&mut self) -> Value {
        self.expect_ident("do");
        let mut body = self.parse_block_or_single();
        self.expect_ident("while");
        self.expect_punct("(");
        let cond = self.parse_expr();
        self.expect_punct(")");
        self.eat_punct(";");
        self.anon_counter += 1;
        let first = format!("__do_first_{}", self.anon_counter);
        let guard = js_logical("||", js_ident(&first), cond);
        let mut loop_body: Vec<Value> = vec![
            js_assign(js_ident(&first), json!({ "type": "bool", "data": { "value": false } })).unwrap(),
        ];
        loop_body.append(&mut body);
        // Emit the `first` declaration then the loop, wrapped so the pair reads
        // as one statement via a bare block (inlined by the VM's flat scope).
        json!({ "type": "ifStmt", "data": {
            "condition": json!({ "type": "bool", "data": { "value": true } }),
            "body": [
                js_def(&first, json!({ "type": "bool", "data": { "value": true } })),
                json!({ "type": "loopStmt", "data": { "condition": guard, "body": loop_body } }),
            ]
        } })
    }

    /// `try { … } catch (e) { … } finally { … }`. Try/catch lowers to the VM's
    /// native `tryStmt`; `finally` is desugared by wrapping so its cleanup runs on
    /// both the normal and the exceptional path (including a re-throwing catch).
    fn parse_try(&mut self) -> Vec<Value> {
        self.expect_ident("try");
        let body = self.parse_block();
        let mut err_name = "__e".to_string();
        let mut catch_body: Option<Vec<Value>> = None;
        if self.eat_ident("catch") {
            if self.eat_punct("(") {
                if !self.at_punct(")") {
                    err_name = self.expect_ident_name();
                }
                self.expect_punct(")");
            }
            catch_body = Some(self.parse_block());
        }
        let finally_body = if self.eat_ident("finally") {
            Some(self.parse_block())
        } else {
            None
        };

        // The inner try/catch (or the bare body when there is no catch clause).
        let inner: Vec<Value> = match catch_body {
            Some(cb) => vec![json!({ "type": "tryStmt", "data": {
                "errName": err_name, "body": body, "catchBody": cb } })],
            None => body,
        };

        match finally_body {
            None => inner,
            Some(fin) => {
                // Wrap: a catch around `inner` runs the cleanup and re-throws, and
                // the cleanup also runs after normal completion.
                self.anon_counter += 1;
                let fe = format!("__fe_{}", self.anon_counter);
                let mut catch_fin = fin.clone();
                catch_fin.push(json!({ "type": "throwOperation", "data": { "value": js_ident(&fe) } }));
                let mut out = vec![json!({ "type": "tryStmt", "data": {
                    "errName": fe, "body": inner, "catchBody": catch_fin } })];
                out.extend(fin);
                out
            }
        }
    }

    /// Desugar `for (init; cond; update) body` into the init statement(s)
    /// followed by a `loopStmt` whose body ends with the update step.
    fn parse_for(&mut self) -> Vec<Value> {
        self.expect_ident("for");
        self.expect_punct("(");
        // A `for-of` / `for-in` header has an `of` / `in` keyword at the top
        // level and no `;`.
        if let Some(kind) = self.for_header_kind() {
            return self.parse_for_of_in(kind);
        }
        let mut out: Vec<Value> = vec![];
        if !self.at_punct(";") {
            out.extend(self.parse_simple());
        }
        self.expect_punct(";");
        let cond = if self.at_punct(";") {
            json!({ "type": "bool", "data": { "value": true } })
        } else {
            self.parse_expr()
        };
        self.expect_punct(";");
        let update = if self.at_punct(")") {
            vec![]
        } else {
            self.parse_simple()
        };
        self.expect_punct(")");
        let body = self.parse_block_or_single();

        if !Self::body_has_continue(&body) {
            // Fast path: no `continue` in the body, so appending the update step
            // to the end of each iteration is both correct and cheap.
            let mut loop_body = body;
            loop_body.extend(update);
            out.push(json!({ "type": "loopStmt", "data": { "condition": cond, "body": loop_body } }));
            return out;
        }

        // `continue` jumps to the loop head, which would skip an update appended at
        // the tail. Run the update at the *top* of every iteration instead (guarded
        // so the first iteration skips it), then test the condition with `break`.
        // This makes `for (...; ...; update) { ...; continue; }` run `update` on the
        // `continue` path, matching JavaScript.
        self.anon_counter += 1;
        let started = format!("__for_started_{}", self.anon_counter);
        let mut loop_body: Vec<Value> = vec![];
        // if (started) { update } else { started = true }
        loop_body.push(json!({ "type": "ifStmt", "data": {
            "condition": js_ident(&started),
            "body": update,
            "elseStmt": { "data": { "body": [
                js_assign(js_ident(&started), json!({ "type": "bool", "data": { "value": true } })).unwrap()
            ] } }
        } }));
        // if (!(cond)) { break; }
        loop_body.push(json!({ "type": "ifStmt", "data": {
            "condition": json!({ "type": "not", "data": { "value": cond } }),
            "body": [ json!({ "type": "breakStmt", "data": {} }) ]
        } }));
        loop_body.extend(body);
        out.push(js_def(&started, json!({ "type": "bool", "data": { "value": false } })));
        out.push(json!({ "type": "loopStmt", "data": {
            "condition": json!({ "type": "bool", "data": { "value": true } }),
            "body": loop_body
        } }));
        out
    }

    /// With the cursor just past `for (`, report whether this is a `for-of`
    /// (`Some("of")`) or `for-in` (`Some("in")`) header — an `of`/`in` keyword
    /// at paren depth 0 with no intervening top-level `;` — or `None` for the
    /// C-style form.
    fn for_header_kind(&self) -> Option<&'static str> {
        let mut i = self.pos;
        let mut depth = 0i32;
        loop {
            match &self.toks[i] {
                JsTok::Punct(p) if p == "(" || p == "[" || p == "{" => depth += 1,
                JsTok::Punct(p) if p == ")" || p == "]" || p == "}" => {
                    if depth == 0 {
                        return None;
                    }
                    depth -= 1;
                }
                JsTok::Punct(p) if p == ";" && depth == 0 => return None,
                JsTok::Ident(k) if depth == 0 && k == "of" => return Some("of"),
                JsTok::Ident(k) if depth == 0 && k == "in" => return Some("in"),
                JsTok::Eof => return None,
                _ => {}
            }
            i += 1;
        }
    }

    /// Parse and desugar `for (x of iterable)` / `for (x in obj)` (the `(` is
    /// already consumed). `for-of` walks an iterable's elements by index;
    /// `for-in` walks an object's keys. Both re-declare the loop variable each
    /// iteration (per-iteration binding), matching `let`-scoped JS loops.
    fn parse_for_of_in(&mut self, kind: &str) -> Vec<Value> {
        // Optional `let` / `const` / `var`.
        if self.at_ident("let") || self.at_ident("const") || self.at_ident("var") {
            self.advance();
        }
        let name = self.expect_ident_name();
        self.advance(); // `of` / `in`
        let iter = self.parse_expr();
        self.expect_punct(")");
        let body = self.parse_block_or_single();

        self.anon_counter += 1;
        let seq = self.anon_counter;
        let src = format!("__iter_src_{seq}");
        let idx = format!("__iter_i_{seq}");
        // for-in walks the source's keys; for-of walks the source itself.
        let src_init = if kind == "in" {
            json!({ "type": "functionCall", "data": { "callee": js_ident("keys"), "args": [iter] } })
        } else {
            iter
        };
        let elem = json!({ "type": "indexer", "data": {
            "target": js_ident(&src), "index": js_ident(&idx) } });
        // Bind the element, then advance the index *before* the body — so a
        // `continue` (which jumps to the loop head) still makes progress.
        let mut loop_body: Vec<Value> = vec![
            js_def(&name, elem),
            js_assign(js_ident(&idx), js_arith("+", js_ident(&idx), js_int(1))).unwrap(),
        ];
        loop_body.extend(body);
        let cond = js_arith(
            "<",
            js_ident(&idx),
            json!({ "type": "indexer", "data": { "target": js_ident(&src), "index": js_string("length") } }),
        );
        vec![
            js_def(&src, src_init),
            js_def(&idx, js_int(0)),
            json!({ "type": "loopStmt", "data": { "condition": cond, "body": loop_body } }),
        ]
    }

    /// Whether a (already-lowered) statement list contains a `continue` that
    /// targets *this* loop — i.e. one not nested inside another loop (which owns
    /// its own `continue`) or a function body.
    fn body_has_continue(body: &[Value]) -> bool {
        body.iter().any(Self::stmt_has_continue)
    }
    fn stmt_has_continue(stmt: &Value) -> bool {
        match stmt["type"].as_str().unwrap_or("") {
            "continueStmt" => true,
            // Nested loops / functions bind their own `continue`; do not descend.
            "loopStmt" | "functionDefinition" => false,
            "ifStmt" => {
                let d = &stmt["data"];
                if d["body"].as_array().map(|b| Self::body_has_continue(b)).unwrap_or(false) {
                    return true;
                }
                if d.get("elseifStmt").map(Self::stmt_has_continue).unwrap_or(false) {
                    return true;
                }
                d.get("elseStmt")
                    .and_then(|e| e["data"]["body"].as_array())
                    .map(|b| Self::body_has_continue(b))
                    .unwrap_or(false)
            }
            "switchStmt" => stmt["data"]["cases"]
                .as_array()
                .map(|cs| {
                    cs.iter().any(|c| {
                        c["body"]["body"].as_array().map(|b| Self::body_has_continue(b)).unwrap_or(false)
                    })
                })
                .unwrap_or(false),
            _ => false,
        }
    }

    /// Parse a `switch`. With no `default` clause it lowers to the VM's native
    /// `switchStmt` (matched case runs, then the switch exits). A `default`
    /// clause has no native opcode, so the whole switch is instead desugared to
    /// an `if / else if / … / else` chain over the switch value (evaluated once
    /// into a temp), with the default as the final `else` — no fall-through,
    /// matching Dart and the common `break`-terminated JS style.
    fn parse_switch(&mut self) -> Vec<Value> {
        self.expect_ident("switch");
        self.expect_punct("(");
        let val = self.parse_expr();
        self.expect_punct(")");
        self.expect_punct("{");
        let mut cases: Vec<Value> = vec![];
        let mut default_body: Option<Vec<Value>> = None;
        while !self.at_punct("}") && !self.at_eof() {
            if self.eat_ident("case") {
                let cv = self.parse_expr();
                self.expect_punct(":");
                let body = self.parse_case_body();
                cases.push(json!({ "value": cv, "body": { "body": body } }));
            } else if self.eat_ident("default") {
                self.expect_punct(":");
                default_body = Some(Self::strip_trailing_break(self.parse_case_body()));
            } else {
                break;
            }
        }
        self.expect_punct("}");

        if default_body.is_none() {
            return vec![json!({ "type": "switchStmt", "data": { "value": val, "cases": cases } })];
        }

        // Desugar to a temp + if/else-if chain.
        self.anon_counter += 1;
        let temp = format!("__sw_{}", self.anon_counter);
        let mut out = vec![js_def(&temp, val)];
        // Build the chain from the last arm up.
        let mut else_branch: Option<Value> = default_body.map(|b| json!({ "data": { "body": b } }));
        let mut chain: Option<Value> = None;
        for case in cases.into_iter().rev() {
            let cv = case["value"].clone();
            let body = Self::strip_trailing_break(
                case["body"]["body"].as_array().cloned().unwrap_or_default(),
            );
            let mut data = json!({
                "condition": js_arith("==", js_ident(&temp), cv),
                "body": body,
            });
            if let Some(next) = chain.take() {
                data["elseifStmt"] = next;
            } else if let Some(e) = else_branch.take() {
                data["elseStmt"] = e;
            }
            chain = Some(json!({ "type": "ifStmt", "data": data }));
        }
        if let Some(c) = chain {
            out.push(c);
        } else if let Some(e) = else_branch {
            // Only a default clause: run it unconditionally.
            if let Some(b) = e["data"]["body"].as_array() {
                out.extend(b.iter().cloned());
            }
        }
        out
    }
    /// Drop a single trailing `break` statement (which merely terminates a case)
    /// from a desugared case body.
    fn strip_trailing_break(mut body: Vec<Value>) -> Vec<Value> {
        if body.last().map(|s| s["type"] == "breakStmt").unwrap_or(false) {
            body.pop();
        }
        body
    }
    fn parse_case_body(&mut self) -> Vec<Value> {
        let mut body: Vec<Value> = vec![];
        while !self.at_ident("case")
            && !self.at_ident("default")
            && !self.at_punct("}")
            && !self.at_eof()
        {
            body.extend(self.parse_statement());
        }
        body
    }

    /// A "simple" statement with no trailing `;`: a declaration, an assignment
    /// (including compound and `++`/`--` forms), or a bare call expression.
    /// Used directly for `for` init/update clauses and wrapped by
    /// `parse_statement` for ordinary statements.
    fn parse_simple(&mut self) -> Vec<Value> {
        if self.at_ident("let") || self.at_ident("const") || self.at_ident("var") {
            self.advance();
            let mut out: Vec<Value> = vec![];
            loop {
                // An object / array pattern binds a native `destructure` statement
                // instead of a single name.
                if self.at_punct("{") || self.at_punct("[") {
                    out.push(self.parse_destructure_decl());
                    if !self.eat_punct(",") {
                        break;
                    }
                    continue;
                }
                let name = self.expect_ident_name();
                let val = if self.eat_punct("=") {
                    self.parse_expr()
                } else {
                    // An uninitialised declaration binds JS `undefined` — the
                    // VM's null.
                    js_null()
                };
                out.push(js_def(&name, val));
                if !self.eat_punct(",") {
                    break;
                }
            }
            return out;
        }
        // Prefix increment / decrement.
        if self.eat_punct("++") {
            let t = self.parse_postfix();
            return js_assign(t.clone(), js_arith("+", t, js_int(1)))
                .into_iter()
                .collect();
        }
        if self.eat_punct("--") {
            let t = self.parse_postfix();
            return js_assign(t.clone(), js_arith("-", t, js_int(1)))
                .into_iter()
                .collect();
        }
        let target = self.parse_expr();
        // Postfix increment / decrement.
        if self.eat_punct("++") {
            return js_assign(target.clone(), js_arith("+", target, js_int(1)))
                .into_iter()
                .collect();
        }
        if self.eat_punct("--") {
            return js_assign(target.clone(), js_arith("-", target, js_int(1)))
                .into_iter()
                .collect();
        }
        if self.eat_punct("=") {
            let rhs = self.parse_expr();
            return js_assign(target, rhs).into_iter().collect();
        }
        // Arithmetic compound assignment (native arithmetic operators).
        for (pp, op) in [("+=", "+"), ("-=", "-"), ("*=", "*"), ("/=", "/"), ("%=", "%"), ("**=", "^")] {
            if self.eat_punct(pp) {
                let rhs = self.parse_expr();
                return js_assign(target.clone(), js_arith(op, target, rhs))
                    .into_iter()
                    .collect();
            }
        }
        // Bitwise / shift compound assignment (prelude-helper operators).
        for (pp, helper) in [
            ("&=", "__band"), ("|=", "__bor"), ("^=", "__bxor"),
            ("<<=", "__shl"), (">>=", "__shr"), (">>>=", "__ushr"),
        ] {
            if self.eat_punct(pp) {
                let rhs = self.parse_expr();
                let combined = json!({ "type": "functionCall", "data": {
                    "callee": js_ident(helper), "args": [target.clone(), rhs] } });
                return js_assign(target, combined).into_iter().collect();
            }
        }
        // Logical compound assignment: `x &&= y`, `x ||= y`, `x ??= y` — assign
        // only when the short-circuit says to (so `y`'s side effects are
        // conditional), matching JS.
        for (pp, op) in [("&&=", "&&"), ("||=", "||"), ("??=", "??")] {
            if self.eat_punct(pp) {
                let rhs = self.parse_expr();
                let combined = js_logical(op, target.clone(), rhs);
                return js_assign(target, combined).into_iter().collect();
            }
        }
        // A bare expression carries meaning to the bytecode when it can have a
        // side effect: a call (`log(x)`), or a short-circuit / conditional whose
        // taken branch may call (`ready && start()`, `cond ? a() : b()`).
        match target["type"].as_str().unwrap_or("") {
            "functionCall" | "logical" | "ternary" => vec![target],
            _ => vec![],
        }
    }

    // ---- Expressions (precedence climbing) ----------------------------------

    fn parse_expr(&mut self) -> Value {
        self.parse_ternary()
    }

    /// The conditional operator sits below everything else and is
    /// right-associative: `a ? b : c ? d : e` parses as `a ? b : (c ? d : e)`.
    fn parse_ternary(&mut self) -> Value {
        let cond = self.parse_nullish();
        if self.eat_punct("?") {
            let consequent = self.parse_ternary();
            self.expect_punct(":");
            let alternate = self.parse_ternary();
            return js_ternary(cond, consequent, alternate);
        }
        cond
    }

    /// `??` (null-coalescing) — lower precedence than `||`, above the ternary;
    /// left-associative. Lowers to the short-circuiting `logical` node so the
    /// right operand is only evaluated when the left is null.
    fn parse_nullish(&mut self) -> Value {
        let mut left = self.parse_logical_or();
        while self.at_punct("??") {
            self.advance();
            let right = self.parse_logical_or();
            left = js_logical("??", left, right);
        }
        left
    }

    /// `||` — lower precedence than `&&`; left-associative.
    fn parse_logical_or(&mut self) -> Value {
        let mut left = self.parse_logical_and();
        while self.at_punct("||") {
            self.advance();
            let right = self.parse_logical_and();
            left = js_logical("||", left, right);
        }
        left
    }

    /// `&&` — binds tighter than `||`, looser than comparison/arithmetic (which
    /// `parse_binary` handles); left-associative.
    fn parse_logical_and(&mut self) -> Value {
        let mut left = self.parse_binary(0);
        while self.at_punct("&&") {
            self.advance();
            let right = self.parse_binary(0);
            left = js_logical("&&", left, right);
        }
        left
    }

    /// Map a punctuator to `(precedence, operator kind, right-associative)`.
    /// Precedences follow JavaScript's binary tower (loosest first): bitwise
    /// `|`^`&`, equality, relational, shift, additive, multiplicative, `**`.
    /// `&&`/`||`/`??` sit above this (handled by their own parse levels), which
    /// all call `parse_binary(0)`.
    fn binop(p: &str) -> Option<(u8, JsBinOp, bool)> {
        use JsBinOp::*;
        Some(match p {
            "|" => (1, Call("__bor"), false),
            "^" => (2, Call("__bxor"), false),
            "&" => (3, Call("__band"), false),
            "==" | "===" => (4, Arith("=="), false),
            "!=" | "!==" => (4, Arith("!="), false),
            "<" => (5, Arith("<"), false),
            "<=" => (5, Arith("<="), false),
            ">" => (5, Arith(">"), false),
            ">=" => (5, Arith(">="), false),
            "<<" => (6, Call("__shl"), false),
            ">>" => (6, Call("__shr"), false),
            ">>>" => (6, Call("__ushr"), false),
            "+" => (7, Arith("+"), false),
            "-" => (7, Arith("-"), false),
            "*" => (8, Arith("*"), false),
            "/" => (8, Arith("/"), false),
            "%" => (8, Arith("%"), false),
            "**" => (9, Arith("^"), true),
            _ => return None,
        })
    }

    fn parse_binary(&mut self, min_prec: u8) -> Value {
        let mut left = self.parse_unary();
        loop {
            // `instanceof` and `in` are relational-precedence keyword operators.
            if let JsTok::Ident(kw) = self.peek() {
                let kw = kw.clone();
                if (kw == "instanceof" || kw == "in") && min_prec <= 5 {
                    self.advance();
                    let right = self.parse_binary(6);
                    left = if kw == "instanceof" {
                        // `x instanceof C` walks the prototype chain — exactly the
                        // reified class type-test, with the constructor's name.
                        let cname = right["data"]["name"].as_str().unwrap_or("").to_string();
                        json!({ "type": "typeTest", "data": {
                            "value": left, "typeName": cname, "cast": false } })
                    } else {
                        // `k in obj` — key membership.
                        json!({ "type": "functionCall", "data": {
                            "callee": js_ident("has"), "args": [right, left] } })
                    };
                    continue;
                }
            }
            let op_punct = match self.peek() {
                JsTok::Punct(p) => p.clone(),
                _ => break,
            };
            let (prec, op, right_assoc) = match Self::binop(&op_punct) {
                Some(x) => x,
                None => break,
            };
            if prec < min_prec {
                break;
            }
            self.advance();
            let next_min = if right_assoc { prec } else { prec + 1 };
            let right = self.parse_binary(next_min);
            left = match op {
                JsBinOp::Arith(o) => js_arith(o, left, right),
                JsBinOp::Call(fname) => json!({ "type": "functionCall", "data": {
                    "callee": js_ident(fname), "args": [left, right] } }),
            };
        }
        left
    }

    fn parse_unary(&mut self) -> Value {
        // `new C(args)` — our class constructors are factory functions, so `new`
        // is sugar: it drops to the constructor call (`C(args)`). `new C` without
        // parentheses still constructs (call with no args).
        if self.at_ident("new") {
            self.advance();
            let e = self.parse_postfix();
            if e["type"] == "functionCall" {
                return e;
            }
            return json!({ "type": "functionCall", "data": { "callee": e, "args": [] } });
        }
        if self.eat_punct("!") {
            return json!({ "type": "not", "data": { "value": self.parse_unary() } });
        }
        if self.at_punct("-") {
            self.advance();
            let v = self.parse_unary();
            return js_negate(v);
        }
        if self.at_punct("+") {
            // Unary plus coerces to a number.
            self.advance();
            let v = self.parse_unary();
            return json!({ "type": "functionCall", "data": { "callee": js_ident("num"), "args": [v] } });
        }
        if self.at_punct("~") {
            // Bitwise NOT — the 32-bit complement, via the prelude helper.
            self.advance();
            let v = self.parse_unary();
            return json!({ "type": "functionCall", "data": { "callee": js_ident("__bnot"), "args": [v] } });
        }
        // `async` / `await` are not in the subset. The VM is a pausing
        // interpreter, not an event loop: there is no Promise, no microtask
        // queue, and no opcode to suspend on one. Left unhandled these tokenize
        // as ordinary identifiers and compile to a program that traps at run
        // time ("non object value can not be indexed by string"), so reject
        // them here where the diagnostic can still name the construct.
        if self.at_ident("await") {
            panic!("js: `await` is not supported — the Elpian VM has no event loop; use the timer host APIs (setTimeout/setInterval) and callback style instead");
        }
        // `async` in expression position: `async () => …`, `async function () {}`.
        // Without this the `async` token parses as a bare identifier and the
        // failure surfaces later as a confusing "unexpected token '=>'".
        if self.at_ident("async") {
            panic!("js: `async` functions are not supported — the Elpian VM has no event loop; use the timer host APIs (setTimeout/setInterval) and callback style instead");
        }
        // Prefix keyword operators (`typeof`, `void`, `delete`) — identifiers in
        // our tokenizer.
        if self.at_ident("typeof") {
            self.advance();
            let v = self.parse_unary();
            return json!({ "type": "functionCall", "data": { "callee": js_ident("__typeof"), "args": [v] } });
        }
        if self.at_ident("void") {
            self.advance();
            let v = self.parse_unary();
            // Evaluate the operand (for side effects), then yield null.
            return json!({ "type": "functionCall", "data": { "callee": js_ident("__void"), "args": [v] } });
        }
        if self.at_ident("delete") {
            self.advance();
            let v = self.parse_unary();
            // `delete a.b` / `delete a[k]` removes the member; anything else is a
            // no-op that yields true (JS's non-reference delete).
            if v["type"] == "indexer" {
                let base = v["data"]["target"].clone();
                let key = v["data"]["index"].clone();
                return json!({ "type": "functionCall", "data": {
                    "callee": js_ident("__delete"), "args": [base, key] } });
            }
            return json!({ "type": "bool", "data": { "value": true } });
        }
        self.parse_postfix()
    }

    fn parse_postfix(&mut self) -> Value {
        let mut e = self.parse_primary();
        loop {
            // Optional chaining `?.` — `a?.b`, `a?.[i]`, `a?.b(args)`, `f?.(args)`.
            // Each short-circuits to null when the base is null, evaluated once.
            if self.at_punct("?.") {
                self.advance();
                if self.at_punct("(") {
                    // Optional function call `f?.(args)`.
                    let args = self.parse_args();
                    e = json!({ "type": "functionCall", "data": {
                        "callee": js_ident("__optCallFn"),
                        "args": [e, json!({ "type": "array", "data": { "value": args } })] } });
                } else if self.at_punct("[") {
                    self.advance();
                    let idx = self.parse_expr();
                    self.expect_punct("]");
                    e = json!({ "type": "functionCall", "data": {
                        "callee": js_ident("__optGet"), "args": [e, idx] } });
                } else {
                    let name = self.expect_ident_name();
                    let resolved = self.resolve_member(&name);
                    if self.at_punct("(") {
                        // Optional method call `a?.b(args)` — guards the call too.
                        let args = self.parse_args();
                        e = json!({ "type": "functionCall", "data": {
                            "callee": js_ident("__optCall"),
                            "args": [e, js_string(&resolved),
                                json!({ "type": "array", "data": { "value": args } })] } });
                    } else {
                        e = json!({ "type": "functionCall", "data": {
                            "callee": js_ident("__optGet"), "args": [e, js_string(&resolved)] } });
                    }
                }
                continue;
            }
            if self.eat_punct(".") {
                let name = self.expect_ident_name();
                // Static namespaces (`Math.floor`, `JSON.parse`, `Object.keys`,
                // `console.log`, …) are resolved to universal builtins /
                // intrinsics at compile time, unless a user class of that name
                // owns statics (then it is an ordinary static read below).
                if e["type"] == "identifier"
                    && !self.class_statics.contains(e["data"]["name"].as_str().unwrap_or(""))
                {
                    if let Some(ns) = e["data"]["name"].as_str() {
                        if is_js_namespace(ns) {
                            if let Some(rewritten) = self.resolve_namespace(ns, &name) {
                                e = rewritten;
                                continue;
                            }
                        }
                    }
                }
                // `super.m` — resolve `m` on the parent prototype and bind it to the
                // current `this`, so `super.m(args)` dispatches to the overridden
                // base method with the right receiver.
                if e["type"] == "identifier" && e["data"]["name"] == "super" {
                    let parent = self.class_parent.clone().unwrap_or_default();
                    e = json!({ "type": "functionCall", "data": {
                        "callee": js_ident("superMethod"),
                        "args": [
                            js_ident(&format!("__proto_{}", parent)),
                            js_string(&name),
                            js_ident("this"),
                        ],
                    } });
                    continue;
                }
                // `Class.staticMember` — read off the class's static holder rather
                // than treating the constructor function as an object.
                if e["type"] == "identifier"
                    && e["data"]["name"].as_str().map(|n| self.class_statics.contains(n)).unwrap_or(false)
                {
                    let cname = e["data"]["name"].as_str().unwrap().to_string();
                    e = json!({ "type": "indexer", "data": {
                        "target": js_ident(&format!("__static_{}", cname)),
                        "index": js_string(&name),
                    } });
                    continue;
                }
                // Resolve the JS member spelling to the VM's universal stdlib name
                // at compile time (`includes`→`contains`, `toUpperCase`→`upper`, …),
                // so the VM only ever sees universal names.
                let resolved = self.resolve_member(&name);
                e = json!({ "type": "indexer", "data": { "target": e, "index": js_string(&resolved) } });
            } else if self.at_punct("[") {
                self.advance();
                let idx = self.parse_expr();
                self.expect_punct("]");
                e = json!({ "type": "indexer", "data": { "target": e, "index": idx } });
            } else if self.at_punct("(") {
                let args = self.parse_args();
                // Reified type tests are compiler intrinsics: `__isType(x, "T")`
                // and `__asType(x, "T")` lower to the native VM type-test opcode
                // (a `typeTest` AST node), not a guest call or a host round-trip.
                // The type name is a string literal produced by the front-end.
                e = Self::type_test_intrinsic(&e, &args)
                    .unwrap_or_else(|| json!({ "type": "functionCall", "data": { "callee": e, "args": args } }));
            } else {
                break;
            }
        }
        e
    }

    /// Resolve a static-namespace member (`Math.floor`, `JSON.stringify`,
    /// `console.log`, …) to the universal builtin / intrinsic it maps to. Members
    /// that are plain builtins return a bare identifier (so a following call
    /// applies normally); constants return a builtin call; the few that need
    /// argument shaping (`console.log`, `Array.isArray`, `Array.of`) consume the
    /// argument list here. Returns `None` for an unknown member (left as an
    /// ordinary field read).
    fn resolve_namespace(&mut self, ns: &str, member: &str) -> Option<Value> {
        // A member that is exactly a universal builtin of another name.
        let as_builtin = |b: &str| Some(js_ident(b));
        // A numeric constant read (`Math.PI`), realised as a builtin call.
        let as_const = |b: &str| Some(json!({ "type": "functionCall", "data": {
            "callee": js_ident(b), "args": [] } }));
        match ns {
            "Math" => match member {
                "PI" => as_const("PI"),
                "E" => as_const("E"),
                "floor" | "ceil" | "round" | "trunc" | "abs" | "sqrt" | "cbrt" | "sign" | "exp"
                | "sin" | "cos" | "tan" | "asin" | "acos" | "atan" | "atan2" | "sinh" | "cosh"
                | "tanh" | "pow" | "log" | "log2" | "log10" | "min" | "max" | "hypot"
                | "random" => as_builtin(member),
                _ => None,
            },
            "JSON" => match member {
                "stringify" => as_builtin("jsonStringify"),
                "parse" => as_builtin("jsonParse"),
                _ => None,
            },
            "Object" => match member {
                "keys" => as_builtin("keys"),
                "values" => as_builtin("values"),
                "entries" => as_builtin("entries"),
                "assign" | "merge" => as_builtin("merge"),
                "freeze" | "from" => as_builtin("__identity"),
                _ => None,
            },
            "Number" => match member {
                "parseInt" => as_builtin("int"),
                "parseFloat" => as_builtin("num"),
                "isNaN" => as_builtin("isNaN"),
                "isFinite" | "isInteger" => as_builtin("isFinite"),
                _ => None,
            },
            "console" => {
                // `console.log(a, b, …)` / warn / error / info → a host log call
                // over the whole argument list.
                if matches!(member, "log" | "warn" | "error" | "info" | "debug") {
                    let args = if self.at_punct("(") { self.parse_args() } else { vec![] };
                    return Some(json!({ "type": "functionCall", "data": {
                        "callee": js_ident("askHost"),
                        "args": [js_string("log"), json!({ "type": "array", "data": { "value": args } })] } }));
                }
                None
            }
            "Array" => match member {
                "isArray" => {
                    // `Array.isArray(x)` → the reified list type test.
                    if self.at_punct("(") {
                        let args = self.parse_args();
                        let x = args.into_iter().next().unwrap_or_else(js_null);
                        return Some(json!({ "type": "typeTest", "data": {
                            "value": x, "typeName": "list", "cast": false } }));
                    }
                    None
                }
                "of" => {
                    // `Array.of(a, b, …)` → a list literal.
                    if self.at_punct("(") {
                        let args = self.parse_args();
                        return Some(json!({ "type": "array", "data": { "value": args } }));
                    }
                    None
                }
                "from" => as_builtin("__identity"),
                _ => None,
            },
            _ => None,
        }
    }

    /// Recognise the `__isType` / `__asType` intrinsics and lower them to a
    /// `typeTest` node (`is` when `cast` is false, `as` when true). Returns `None`
    /// for any other call so it stays an ordinary `functionCall`.
    fn type_test_intrinsic(callee: &Value, args: &[Value]) -> Option<Value> {
        if callee["type"] != "identifier" || args.len() != 2 {
            return None;
        }
        let cast = match callee["data"]["name"].as_str()? {
            "__isType" => false,
            "__asType" => true,
            _ => return None,
        };
        if args[1]["type"] != "string" {
            return None;
        }
        let type_name = Self::universal_type_name(args[1]["data"]["value"].as_str()?);
        Some(json!({ "type": "typeTest", "data": {
            "value": args[0].clone(), "typeName": type_name, "cast": cast } }))
    }

    /// Compile-time resolution of an `__isType` / `__asType` type name to the
    /// VM's neutral type-tag vocabulary (the same job dart2elpian's
    /// `universal_type_name` does for reified `is` / `as`). The VM understands
    /// only its own names (`int`, `float`, `number`, `string`, `list`, `map`,
    /// `function`, `bool`, `null`, `any`); guest JS written before the neutral
    /// vocabulary landed spells them `List`, `Map`, `num`, `Array`, … Any other
    /// name is a class name and passes through unchanged (matched against the
    /// instance's prototype chain).
    fn universal_type_name(ty: &str) -> &str {
        match ty {
            "Array" | "List" | "Set" | "Iterable" => "list",
            "Object" | "Map" => "map",
            "num" | "Number" => "number",
            "double" => "float",
            "String" => "string",
            "Boolean" => "bool",
            "Function" => "function",
            "Null" | "undefined" => "null",
            other => other,
        }
    }

    fn parse_args(&mut self) -> Vec<Value> {
        self.expect_punct("(");
        let mut args: Vec<Value> = vec![];
        while !self.at_punct(")") && !self.at_eof() {
            if self.eat_punct("...") {
                args.push(js_spread(self.parse_expr()));
            } else {
                args.push(self.parse_expr());
            }
            if !self.eat_punct(",") {
                break;
            }
        }
        self.expect_punct(")");
        args
    }

    // ---- arrow / function expressions (desugared to lifted closures) --------

    /// With `self.pos` at a `(`, decide whether it opens an arrow parameter list
    /// by scanning to the matching `)` and checking for a following `=>`.
    fn is_paren_arrow(&self) -> bool {
        let mut depth = 0i32;
        let mut i = self.pos;
        while i < self.toks.len() {
            match &self.toks[i] {
                JsTok::Punct(p) if p == "(" => depth += 1,
                JsTok::Punct(p) if p == ")" => {
                    depth -= 1;
                    if depth == 0 {
                        return matches!(self.toks.get(i + 1), Some(JsTok::Punct(p2)) if p2 == "=>");
                    }
                }
                JsTok::Eof => return false,
                _ => {}
            }
            i += 1;
        }
        false
    }

    /// Parse a parenthesized identifier list `( a, b, ... )` (arrow params or a
    /// `function` expression's params).
    fn parse_paren_params(&mut self) -> Vec<String> {
        self.expect_punct("(");
        let mut params: Vec<String> = vec![];
        while !self.at_punct(")") && !self.at_eof() {
            params.push(self.expect_ident_name());
            if !self.eat_punct(",") {
                break;
            }
        }
        self.expect_punct(")");
        params
    }

    /// Consume `=> body` (concise expression or `{ block }`) and lift the result
    /// into a synthetic named closure, returning a reference to it.
    fn finish_arrow(&mut self, params: Vec<String>) -> Value {
        self.expect_punct("=>");
        let body = if self.at_punct("{") {
            self.parse_block()
        } else {
            // Concise body `=> expr` is `{ return expr; }`.
            let e = self.parse_expr();
            vec![json!({ "type": "returnOperation", "data": { "value": e } })]
        };
        self.make_anon(params, body)
    }

    /// A `function (params) { ... }` (or named `function f(...) {...}`) used in
    /// expression position — lowered like an arrow. Any name is accepted but not
    /// bound (the value is anonymous; reference it through where it is stored).
    fn parse_function_expr(&mut self) -> Value {
        self.expect_ident("function");
        if matches!(self.peek(), JsTok::Ident(_)) {
            self.advance(); // optional name, ignored
        }
        let params = self.parse_paren_params();
        let body = self.parse_block();
        self.make_anon(params, body)
    }

    /// Register a synthetic closure definition to be hoisted before the current
    /// statement and return an `identifier` referencing it.
    fn make_anon(&mut self, params: Vec<String>, body: Vec<Value>) -> Value {
        self.anon_counter += 1;
        let name = format!("__anon_{}", self.anon_counter);
        self.lifted.push(json!({
            "type": "functionDefinition",
            "data": { "name": name, "params": params, "body": body }
        }));
        js_ident(&name)
    }

    /// Lower a tokenized template literal into the VM's native `template` node:
    /// literal segments become string parts, `${ … }` segments are re-parsed as
    /// expressions (sharing this parser's desugaring context).
    fn build_template(&mut self, parts: Vec<TplPart>) -> Value {
        let mut out: Vec<Value> = vec![];
        for p in parts {
            match p {
                TplPart::Lit(s) => out.push(js_string(&s)),
                TplPart::Expr(src) => out.push(self.parse_subexpr(&src)),
            }
        }
        json!({ "type": "template", "data": { "parts": out } })
    }

    /// Parse a standalone expression source (an interpolation body) with a fresh
    /// parser that inherits this one's class / member context, then carry back
    /// any lifted closures and the advanced anonymous-name counter so synthetic
    /// names stay globally unique.
    fn parse_subexpr(&mut self, src: &str) -> Value {
        let mut sub = JsParser::new(tokenize_js(src));
        sub.class_parent = self.class_parent.clone();
        sub.class_statics = self.class_statics.clone();
        sub.class_ctor_params = self.class_ctor_params.clone();
        sub.user_members = self.user_members.clone();
        sub.anon_counter = self.anon_counter;
        let e = sub.parse_expr();
        self.anon_counter = sub.anon_counter;
        self.lifted.append(&mut sub.lifted);
        e
    }

    /// Parse one destructuring declarator (`{ … } = src` or `[ … ] = src`) into a
    /// native `destructure` statement node. Supports member renaming (object),
    /// per-binding defaults, holes (array) and a trailing rest binding.
    fn parse_destructure_decl(&mut self) -> Value {
        let is_array = self.at_punct("[");
        let mut bindings: Vec<Value> = vec![];
        if is_array {
            self.expect_punct("[");
            loop {
                if self.at_punct("]") {
                    break;
                }
                if self.at_punct(",") {
                    // An elision / hole (`[a, , c]`).
                    bindings.push(json!({ "hole": true }));
                    self.advance();
                    continue;
                }
                if self.eat_punct("...") {
                    let name = self.expect_ident_name();
                    bindings.push(json!({ "name": name, "rest": true }));
                } else {
                    let name = self.expect_ident_name();
                    if self.eat_punct("=") {
                        let def = self.parse_expr();
                        bindings.push(json!({ "name": name, "default": def }));
                    } else {
                        bindings.push(json!({ "name": name }));
                    }
                }
                if !self.eat_punct(",") {
                    break;
                }
            }
            self.expect_punct("]");
        } else {
            self.expect_punct("{");
            loop {
                if self.at_punct("}") {
                    break;
                }
                if self.eat_punct("...") {
                    let name = self.expect_ident_name();
                    bindings.push(json!({ "name": name, "rest": true }));
                } else {
                    let key = self.expect_ident_name();
                    // `{ key: name }` renames; plain `{ key }` binds the same name.
                    let name = if self.eat_punct(":") {
                        self.expect_ident_name()
                    } else {
                        key.clone()
                    };
                    if self.eat_punct("=") {
                        let def = self.parse_expr();
                        bindings.push(json!({ "name": name, "key": key, "default": def }));
                    } else {
                        bindings.push(json!({ "name": name, "key": key }));
                    }
                }
                if !self.eat_punct(",") {
                    break;
                }
            }
            self.expect_punct("}");
        }
        self.expect_punct("=");
        let source = self.parse_expr();
        json!({ "type": "destructure", "data": {
            "isArray": is_array, "source": source, "bindings": bindings } })
    }

    fn parse_primary(&mut self) -> Value {
        match self.peek().clone() {
            JsTok::Num(s) => {
                self.advance();
                js_num_literal(&s)
            }
            JsTok::Str(s) => {
                self.advance();
                js_string(&s)
            }
            JsTok::Template(parts) => {
                self.advance();
                self.build_template(parts)
            }
            JsTok::Ident(name) => match name.as_str() {
                "true" => {
                    self.advance();
                    json!({ "type": "bool", "data": { "value": true } })
                }
                "false" => {
                    self.advance();
                    json!({ "type": "bool", "data": { "value": false } })
                }
                // Both JS spellings of "no value" lower to the VM's single
                // first-class null literal.
                "null" | "undefined" => {
                    self.advance();
                    js_null()
                }
                "function" => self.parse_function_expr(),
                _ => {
                    self.advance();
                    // Single-parameter arrow without parens: `x => body`.
                    if self.at_punct("=>") {
                        return self.finish_arrow(vec![name]);
                    }
                    js_ident(&name)
                }
            },
            JsTok::Punct(p) => match p.as_str() {
                "(" => {
                    // `(a, b) => ...` / `() => ...` is an arrow, not a group.
                    if self.is_paren_arrow() {
                        let params = self.parse_paren_params();
                        return self.finish_arrow(params);
                    }
                    self.advance();
                    let e = self.parse_expr();
                    self.expect_punct(")");
                    e
                }
                "[" => self.parse_array(),
                "{" => self.parse_object(),
                other => panic!("js: unexpected token '{}'", other),
            },
            JsTok::Eof => panic!("js: unexpected end of input"),
        }
    }

    fn parse_array(&mut self) -> Value {
        self.expect_punct("[");
        let mut items: Vec<Value> = vec![];
        while !self.at_punct("]") && !self.at_eof() {
            if self.eat_punct("...") {
                items.push(js_spread(self.parse_expr()));
            } else {
                items.push(self.parse_expr());
            }
            if !self.eat_punct(",") {
                break;
            }
        }
        self.expect_punct("]");
        json!({ "type": "array", "data": { "value": items } })
    }

    fn parse_object(&mut self) -> Value {
        self.expect_punct("{");
        // Collect ordered entries so a spread (`{ ...src }`) keeps its position;
        // if none appears we emit the classic unordered `value` map so existing
        // behaviour (and its bytecode) is byte-for-byte unchanged.
        let mut entries: Vec<Value> = vec![];
        let mut had_spread = false;
        while !self.at_punct("}") && !self.at_eof() {
            if self.eat_punct("...") {
                had_spread = true;
                entries.push(json!({ "spread": self.parse_expr() }));
                if !self.eat_punct(",") {
                    break;
                }
                continue;
            }
            let key = match self.advance() {
                JsTok::Ident(s) => s,
                JsTok::Str(s) => s,
                JsTok::Num(s) => s,
                t => panic!("js: invalid object key {:?}", t),
            };
            let val = if self.eat_punct(":") {
                self.parse_expr()
            } else {
                // Shorthand `{ a }` is `{ a: a }`.
                js_ident(&key)
            };
            entries.push(json!({ "key": key, "value": val }));
            if !self.eat_punct(",") {
                break;
            }
        }
        self.expect_punct("}");
        if had_spread {
            json!({ "type": "object", "data": { "entries": entries } })
        } else {
            let mut map = serde_json::Map::new();
            for e in entries {
                map.insert(e["key"].as_str().unwrap().to_string(), e["value"].clone());
            }
            json!({ "type": "object", "data": { "value": Value::Object(map) } })
        }
    }
}

/// Parse JavaScript source into Elpian AST JSON (a `program` node). Panics on a
/// syntax error in the supported subset; use [`try_parse_js`] for a fallible
/// variant.
pub fn parse_js(src: &str) -> serde_json::Value {
    let full = format!("{JS_PRELUDE}\n{src}");
    let mut program = JsParser::new(tokenize_js(&full)).parse_program();
    // Recover JavaScript's by-reference closure capture: box locals that a
    // nested closure captures and mutates into one-element arrays.
    transforms::box_captured_program(&mut program);
    program
}

/// Run `f`, catching the panic the parser uses to report "outside the subset".
///
/// The parser signals rejection by panicking, so the default hook prints a crash
/// dump before the caller ever sees the message. That makes a *rejected input*
/// look like a *compiler bug*. Silence the hook for the duration of the attempt
/// and hand the message back instead.
///
/// The hook is process-global, so a panic on another thread during this window
/// also prints nothing. Compilation is serial in every current caller, and the
/// message is still returned to whoever asked, so the trade is worth the clean
/// diagnostic.
fn catch_subset_panic<T>(f: impl FnOnce() -> T) -> Result<T, String> {
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(|_| {}));
    let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(f));
    std::panic::set_hook(previous);
    outcome.map_err(|payload| {
        payload
            .downcast_ref::<String>()
            .cloned()
            .or_else(|| payload.downcast_ref::<&'static str>().map(|s| s.to_string()))
            .unwrap_or_else(|| "javascript parse error".to_string())
    })
}

/// Parse JavaScript source into Elpian AST JSON, returning an error instead of
/// panicking when the source is outside the supported subset.
pub fn try_parse_js(src: &str) -> Result<serde_json::Value, String> {
    catch_subset_panic(|| parse_js(src))
}

/// Compile JavaScript source straight to bytecode by lowering it to the Elpian
/// AST and feeding that to [`compile_ast`] — the same `from ast` path every
/// other entry point uses.
pub fn compile_js(src: &str) -> Vec<u8> {
    elpian_vm::sdk::compiler::compile_ast(parse_js(src), 0)
}

// ============================================================================
// Public API — parse JS and drive an elpian-vm instance through the AST path.
// ============================================================================

/// Compile JS source to Elpian **AST JSON** (the string form the VM ingests).
pub fn compile_js_to_ast(code: String) -> String {
    match try_parse_js(&code) {
        Ok(ast) => ast.to_string(),
        Err(e) => json!({ "error": e }).to_string(),
    }
}

/// Compile JS source to Elpian **bytecode** (via the VM's AST serialiser).
/// Returns `None` if the source is outside the supported subset.
pub fn compile_js_to_bytecode(code: &str) -> Option<Vec<u8>> {
    catch_subset_panic(|| compile_js(code)).ok()
}

/// Validate that JS source parses + compiles, without registering a VM.
pub fn validate_js(code: String) -> bool {
    catch_subset_panic(|| {
        let _ = compile_js(&code);
    })
    .is_ok()
}

/// Parse JS to AST and create a live VM from it (registered in the VM's global
/// registry under `machine_id`). Returns `false` if the source fails to
/// parse / compile. This is the JS analogue of `elpian_vm::api::create_vm_from_ast`.
pub fn create_vm_from_js(machine_id: String, code: String) -> bool {
    elpian_vm::api::init_vm_system();
    let ast = match try_parse_js(&code) {
        Ok(ast) => ast,
        Err(_) => return false,
    };
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        elpian_vm::api::create_vm_from_ast(machine_id, ast.to_string())
    }))
    .unwrap_or(false)
}
