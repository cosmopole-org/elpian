//! The Elpian native standard library.
//!
//! These are *builtin functions* — native Rust implementations the guest calls
//! by name, exactly like a user-defined function (`sqrt(2)`, `len(xs)`,
//! `jsonParse(s)`). They run synchronously inside the interpreter with no host
//! round-trip, so they are pure, deterministic, and free of any environmental
//! capability. Anything non-deterministic or side-effecting (time, randomness,
//! the network, the filesystem) is deliberately *not* here — it goes through the
//! capability-gated `askHost` seam instead.
//!
//! The library is organised as:
//! * **math** — the full elementary function set plus combinators (`min`,
//!   `max`, `clamp`, `gcd`, `hypot`, …) and constants (`PI()`, `E()`, …).
//! * **foundation** — type reflection, numeric/string/array/object utilities,
//!   and JSON in/out, the bedrock most guest code needs.
//! * **oop** — a class / inheritance / instantiation system built on the VM's
//!   object model (`class`, `extend`, `new`, `method`, `isInstance`, …).
//! * **closures** — `cell` reference helpers, the canonical way to give a
//!   closure mutable captured state with a clear lifecycle.
//!
//! The executor resolves an unbound identifier to a builtin only when no
//! user/scope binding shadows it (see `Executor::extract_val`), so guests can
//! always define their own `len` or `map` and win.
//!
//! This is the VM's **single, universal** standard-library surface. There is no
//! second "type-method" surface and nothing is proxied: a `list.push(x)` /
//! `str.upper()` member call and a bare `push(list, x)` / `upper(str)` call reach
//! the *same* implementation under the *same* universal name (the executor's
//! member dispatch, driven by [`crate::sdk::type_methods`], calls straight into
//! `invoke`). Mapping a source language's spelling (`List.add`, `toUpperCase`,
//! `Array.push`) onto these universal names is the *compiler's* job — done in
//! `dart2elpian` / `js2elpian` at compile time — never the VM's at runtime.

use std::cell::RefCell;
use std::rc::Rc;

use crate::sdk::data::{Array, Object, Payload, Val, ValGroup, ValMap};

/// Object `typ` tag for a class descriptor produced by `class` / `extend`.
pub const CLASS_TYPE: i64 = -100;
/// Object `typ` tag for an instance produced by `new`.
pub const INSTANCE_TYPE: i64 = -101;
/// Object `typ` tag for a closure cell produced by `cell`.
pub const CELL_TYPE: i64 = -102;

thread_local! {
    /// State of the deterministic `random` builtin (xorshift64*). Per-thread —
    /// the VM system is single-threaded per instance — and reseedable via
    /// `seedRandom`.
    static RNG_STATE: std::cell::Cell<u64> = const { std::cell::Cell::new(0x9E3779B97F4A7C15) };
}

// ----------------------------------------------------------------------------
// Value constructors (kept terse so the builtin bodies read like math).
// ----------------------------------------------------------------------------

pub(crate) fn vnull() -> Val {
    Val::new(0, Payload::Null)
}
pub(crate) fn vbool(b: bool) -> Val {
    Val::new(6, Payload::from(b))
}
pub(crate) fn vi64(n: i64) -> Val {
    Val::new(3, Payload::from(n))
}
pub(crate) fn vf64(n: f64) -> Val {
    Val::new(5, Payload::from(n))
}
pub(crate) fn vstr(s: String) -> Val {
    Val::new(7, Payload::from(s))
}
pub(crate) fn varr(items: Vec<Val>) -> Val {
    Val::new(
        9,
        Payload::from(Rc::new(RefCell::new(Array::new(items)))),
    )
}
pub(crate) fn vobj(typ: i64, map: ValMap) -> Val {
    Val::new(
        8,
        Payload::from(Rc::new(RefCell::new(Object::new(
            typ,
            ValGroup::new(map),
        )))),
    )
}

/// Coerce any numeric value to `f64`. Errors on non-numeric inputs.
pub(crate) fn as_num(v: &Val) -> Result<f64, String> {
    match v.typ {
        1 => Ok(v.as_i16() as f64),
        2 => Ok(v.as_i32() as f64),
        3 => Ok(v.as_i64() as f64),
        4 => Ok(v.as_f32() as f64),
        5 => Ok(v.as_f64()),
        6 => Ok(if v.as_bool() { 1.0 } else { 0.0 }),
        _ => Err("expected a number".to_string()),
    }
}

/// Coerce to `i64` (truncating floats).
pub(crate) fn as_int(v: &Val) -> Result<i64, String> {
    Ok(as_num(v)? as i64)
}

/// Produce the most compact numeric value: an integer if the float is whole and
/// in range, otherwise an f64. Keeps arithmetic results idiomatic.
pub(crate) fn num_result(x: f64) -> Val {
    if x.is_finite() && x.fract() == 0.0 && x.abs() < 9.007_199_254_740_992e15 {
        vi64(x as i64)
    } else {
        vf64(x)
    }
}

pub(crate) fn arity(name: &str, args: &[Val], n: usize) -> Result<(), String> {
    if args.len() != n {
        Err(format!("{name} expects {n} argument(s), got {}", args.len()))
    } else {
        Ok(())
    }
}

pub(crate) fn at_least(name: &str, args: &[Val], n: usize) -> Result<(), String> {
    if args.len() < n {
        Err(format!("{name} expects at least {n} argument(s), got {}", args.len()))
    } else {
        Ok(())
    }
}

/// The runtime name of a value's type, used by `typeOf` and diagnostics.
pub fn type_name(v: &Val) -> &'static str {
    match v.typ {
        0 => "null",
        1 => "i16",
        2 => "i32",
        3 => "i64",
        4 => "f32",
        5 => "f64",
        6 => "bool",
        7 => "string",
        8 => "object",
        9 => "array",
        10 => "function",
        _ => "unknown",
    }
}

/// Convert a [`Val`] to a `serde_json::Value` for `jsonStringify` and host
/// payloads. Functions serialize to their name.
pub fn val_to_json(v: &Val) -> serde_json::Value {
    use serde_json::Value as J;
    match v.typ {
        0 => J::Null,
        1 => J::from(v.as_i16()),
        2 => J::from(v.as_i32()),
        3 => J::from(v.as_i64()),
        4 => serde_json::Number::from_f64(v.as_f32() as f64).map(J::Number).unwrap_or(J::Null),
        5 => serde_json::Number::from_f64(v.as_f64()).map(J::Number).unwrap_or(J::Null),
        6 => J::Bool(v.as_bool()),
        7 => J::String(v.as_string()),
        8 => {
            let o = v.as_object();
            let b = o.borrow();
            let mut m = serde_json::Map::new();
            for (k, val) in b.data.data.iter() {
                m.insert(k.clone(), val_to_json(val));
            }
            J::Object(m)
        }
        9 => {
            let a = v.as_array();
            let b = a.borrow();
            J::Array(b.data.iter().map(val_to_json).collect())
        }
        10 => J::String(v.as_func().borrow().name.clone()),
        _ => J::Null,
    }
}

/// Convert a `serde_json::Value` into a [`Val`] (used by `jsonParse`).
pub fn json_to_val(j: &serde_json::Value) -> Val {
    use serde_json::Value as J;
    match j {
        J::Null => vnull(),
        J::Bool(b) => vbool(*b),
        J::Number(n) => {
            if let Some(i) = n.as_i64() {
                vi64(i)
            } else {
                vf64(n.as_f64().unwrap_or(0.0))
            }
        }
        J::String(s) => vstr(s.clone()),
        J::Array(items) => varr(items.iter().map(json_to_val).collect()),
        J::Object(map) => {
            let mut m = ValMap::default();
            for (k, v) in map.iter() {
                m.insert(k.clone(), json_to_val(v));
            }
            vobj(-2, m)
        }
    }
}

// ----------------------------------------------------------------------------
// Registry.
// ----------------------------------------------------------------------------

/// Every builtin name. Kept in one place so `is_builtin` and documentation stay
/// in sync with `invoke`.
pub const BUILTINS: &[&str] = &[
    // math — constants
    "PI", "E", "TAU", "SQRT2", "LN2", "LN10", "INF", "NAN",
    // math — unary
    "abs", "floor", "ceil", "round", "trunc", "fract", "sign", "sqrt", "cbrt", "exp", "expm1",
    "ln", "log2", "log10", "sin", "cos", "tan", "asin", "acos", "atan", "sinh", "cosh", "tanh",
    "asinh", "acosh", "atanh", "degrees", "radians", "isNaN", "isFinite", "factorial",
    // math — binary / variadic
    "pow", "log", "atan2", "hypot", "min", "max", "clamp", "gcd", "lcm", "sum", "mean",
    "intDiv", "remainder", "isEven", "isOdd", "random", "seedRandom",
    // integer bit operations + 32-bit wrap conversions
    "bitAnd", "bitOr", "bitXor", "bitNot", "shl", "shr", "ushr", "toInt32", "toUint32",
    // radix / lenient numeric parsing
    "toRadix", "parseRadix", "tryNum", "compareTo",
    // foundation — reflection / conversion + codecs
    "typeOf", "len", "length", "isEmpty", "isNotEmpty", "str", "num", "int", "bool", "isNull",
    "jsonParse", "jsonStringify",
    "base64Encode", "base64Decode", "utf8Encode", "utf8Decode",
    // foundation — numeric members (universal names for the num core-type members)
    "toDouble", "isNegative", "toString", "toStringAsFixed",
    // foundation — object / map
    "keys", "values", "entries", "has", "get", "setKey", "delKey", "merge", "__setIndex",
    "remove", "putIfAbsent", "hasValue",
    // foundation — array
    "push", "emit", "pop", "shift", "unshift", "slice", "concat", "reverse", "reversed",
    "contains", "indexOf", "join", "range", "first", "last", "sort", "fill",
    "pushAll", "removeAt", "insert", "clear", "setAt", "at", "lastIndexOf", "splice",
    "flatten", "take", "skip", "toSet", "shuffle",
    // foundation — string
    "upper", "lower", "trim", "trimStart", "trimEnd", "split", "substring", "charAt", "replace",
    "replaceFirst", "repeat", "startsWith", "endsWith", "padStart", "padEnd", "ord", "chr",
    "codeUnitAt", "codeUnits",
    // oop
    "class", "extend", "new", "method", "field", "setField", "isInstance", "className",
    "parentMethod", "classOf", "superMethod",
    // closures
    "cell", "cellGet", "cellSet",
];

/// Set form of [`BUILTINS`] for O(1) membership tests. `is_builtin` is called on
/// every identifier resolution that misses the scope chain — including the hot
/// `push`/`len`/math builtins the renderer hammers each frame — so a linear scan
/// of ~150 names showed up in frame profiles. Built once, then hashed.
static BUILTIN_SET: once_cell::sync::Lazy<std::collections::HashSet<&'static str>> =
    once_cell::sync::Lazy::new(|| BUILTINS.iter().copied().collect());

/// Whether `name` resolves to a native builtin.
pub fn is_builtin(name: &str) -> bool {
    BUILTIN_SET.contains(name)
}

/// Invoke a builtin by name. Returns the result value or a guest-visible error
/// string (which the executor surfaces as a trap). `args` are already evaluated.
pub fn invoke(name: &str, args: &[Val]) -> Result<Val, String> {
    match name {
        // ---- math constants -------------------------------------------------
        "PI" => Ok(vf64(std::f64::consts::PI)),
        "E" => Ok(vf64(std::f64::consts::E)),
        "TAU" => Ok(vf64(std::f64::consts::TAU)),
        "SQRT2" => Ok(vf64(std::f64::consts::SQRT_2)),
        "LN2" => Ok(vf64(std::f64::consts::LN_2)),
        "LN10" => Ok(vf64(std::f64::consts::LN_10)),
        "INF" => Ok(vf64(f64::INFINITY)),
        "NAN" => Ok(vf64(f64::NAN)),

        // ---- math unary -----------------------------------------------------
        // `abs` preserves the numeric kind: an integer stays an integer, a float
        // stays a float (so `(-3.0).abs()` is the double `3.0`, not the int `3`).
        "abs" => {
            arity(name, args, 1)?;
            if matches!(args[0].typ, 1 | 2 | 3) {
                Ok(vi64(as_int(&args[0])?.abs()))
            } else {
                Ok(vf64(as_num(&args[0])?.abs()))
            }
        }
        "floor" => unary_int(name, args, f64::floor),
        "ceil" => unary_int(name, args, f64::ceil),
        "round" => unary_int(name, args, f64::round),
        "trunc" => unary_int(name, args, f64::trunc),
        "fract" => unary(name, args, f64::fract),
        "sign" => unary(name, args, f64::signum),
        "sqrt" => unary(name, args, f64::sqrt),
        "cbrt" => unary(name, args, f64::cbrt),
        "exp" => unary(name, args, f64::exp),
        "expm1" => unary(name, args, f64::exp_m1),
        "ln" => unary(name, args, f64::ln),
        "log2" => unary(name, args, f64::log2),
        "log10" => unary(name, args, f64::log10),
        "sin" => unary(name, args, f64::sin),
        "cos" => unary(name, args, f64::cos),
        "tan" => unary(name, args, f64::tan),
        "asin" => unary(name, args, f64::asin),
        "acos" => unary(name, args, f64::acos),
        "atan" => unary(name, args, f64::atan),
        "sinh" => unary(name, args, f64::sinh),
        "cosh" => unary(name, args, f64::cosh),
        "tanh" => unary(name, args, f64::tanh),
        "asinh" => unary(name, args, f64::asinh),
        "acosh" => unary(name, args, f64::acosh),
        "atanh" => unary(name, args, f64::atanh),
        "degrees" => unary(name, args, f64::to_degrees),
        "radians" => unary(name, args, f64::to_radians),
        "isNaN" => {
            arity(name, args, 1)?;
            Ok(vbool(as_num(&args[0])?.is_nan()))
        }
        "isFinite" => {
            arity(name, args, 1)?;
            Ok(vbool(as_num(&args[0])?.is_finite()))
        }
        "factorial" => {
            arity(name, args, 1)?;
            let n = as_int(&args[0])?;
            if n < 0 {
                return Err("factorial of negative number".to_string());
            }
            let mut acc: f64 = 1.0;
            for k in 2..=n {
                acc *= k as f64;
            }
            Ok(num_result(acc))
        }

        // ---- math binary / variadic ----------------------------------------
        "pow" => binary(name, args, f64::powf),
        "atan2" => binary(name, args, f64::atan2),
        "hypot" => binary(name, args, f64::hypot),
        "log" => {
            arity(name, args, 2)?;
            Ok(num_result(as_num(&args[0])?.log(as_num(&args[1])?)))
        }
        "min" => {
            at_least(name, args, 1)?;
            let mut m = as_num(&args[0])?;
            for a in &args[1..] {
                m = m.min(as_num(a)?);
            }
            Ok(num_result(m))
        }
        "max" => {
            at_least(name, args, 1)?;
            let mut m = as_num(&args[0])?;
            for a in &args[1..] {
                m = m.max(as_num(a)?);
            }
            Ok(num_result(m))
        }
        "sum" => {
            let mut acc = 0.0;
            for a in args {
                acc += as_num(a)?;
            }
            Ok(num_result(acc))
        }
        "mean" => {
            at_least(name, args, 1)?;
            let mut acc = 0.0;
            for a in args {
                acc += as_num(a)?;
            }
            Ok(num_result(acc / args.len() as f64))
        }
        "clamp" => {
            arity(name, args, 3)?;
            let (x, lo, hi) = (as_num(&args[0])?, as_num(&args[1])?, as_num(&args[2])?);
            Ok(num_result(x.max(lo).min(hi)))
        }
        // Truncating integer division: the quotient of `a / b` truncated toward
        // zero, always an integer. The universal primitive a front-end lowers
        // its language's integer-division operator to (Dart's `~/`, Python's
        // `int(a / b)`, …). Division by zero is an error (a trap in the guest).
        "intDiv" => {
            arity(name, args, 2)?;
            if matches!(args[0].typ, 1 | 2 | 3) && matches!(args[1].typ, 1 | 2 | 3) {
                let a = as_int(&args[0])?;
                let b = as_int(&args[1])?;
                if b == 0 {
                    return Err("integer division by zero".to_string());
                }
                // i64::MIN / -1 is the one overflowing case; fall through to the
                // float path for it rather than aborting the process.
                if let Some(q) = a.checked_div(b) {
                    return Ok(vi64(q));
                }
            }
            let a = as_num(&args[0])?;
            let b = as_num(&args[1])?;
            if b == 0.0 {
                return Err("integer division by zero".to_string());
            }
            Ok(vi64((a / b).trunc() as i64))
        }
        // ---- integer bit operations (64-bit, like wasm's i64 op set) --------
        // Language front-ends lower their bitwise operators here; a language
        // with 32-bit bitwise semantics (JS) composes these with `toInt32` /
        // `toUint32` at compile time.
        "bitAnd" | "bitOr" | "bitXor" => {
            arity(name, args, 2)?;
            let (a, b) = (as_int(&args[0])?, as_int(&args[1])?);
            Ok(vi64(match name {
                "bitAnd" => a & b,
                "bitOr" => a | b,
                _ => a ^ b,
            }))
        }
        "bitNot" => {
            arity(name, args, 1)?;
            Ok(vi64(!as_int(&args[0])?))
        }
        // Shifts: `shl`/`shr` are arithmetic (sign-preserving); `ushr` shifts in
        // zeros. Shift counts are masked to 0..=63.
        "shl" | "shr" | "ushr" => {
            arity(name, args, 2)?;
            let a = as_int(&args[0])?;
            let b = (as_int(&args[1])? & 63) as u32;
            Ok(vi64(match name {
                "shl" => a.wrapping_shl(b),
                "shr" => a.wrapping_shr(b),
                _ => ((a as u64).wrapping_shr(b)) as i64,
            }))
        }
        // 32-bit wrap conversions (the ToInt32/ToUint32 of JS-like languages).
        "toInt32" => {
            arity(name, args, 1)?;
            Ok(vi64(as_num(&args[0])? as i64 as i32 as i64))
        }
        "toUint32" => {
            arity(name, args, 1)?;
            Ok(vi64(as_num(&args[0])? as i64 as u32 as i64))
        }
        // Truncating remainder (same sign as the dividend), the `remainder`
        // member of numbers.
        "remainder" => {
            arity(name, args, 2)?;
            if matches!(args[0].typ, 1 | 2 | 3) && matches!(args[1].typ, 1 | 2 | 3) {
                let b = as_int(&args[1])?;
                if b == 0 {
                    return Err("remainder by zero".to_string());
                }
                return Ok(vi64(as_int(&args[0])?.wrapping_rem(b)));
            }
            Ok(vf64(as_num(&args[0])? % as_num(&args[1])?))
        }
        "isEven" => {
            arity(name, args, 1)?;
            Ok(vbool(as_int(&args[0])? % 2 == 0))
        }
        "isOdd" => {
            arity(name, args, 1)?;
            Ok(vbool(as_int(&args[0])? % 2 != 0))
        }
        // Integer to text in a radix 2..=36 and back. `parseRadix` errors (a
        // guest trap / catchable throw) on malformed input; `tryNum` is the
        // non-trapping numeric parse that yields null instead.
        "toRadix" => {
            arity(name, args, 2)?;
            let mut n = as_int(&args[0])?;
            let radix = as_int(&args[1])?;
            if !(2..=36).contains(&radix) {
                return Err("toRadix: radix must be in 2..=36".to_string());
            }
            let digits = b"0123456789abcdefghijklmnopqrstuvwxyz";
            let neg = n < 0;
            let mut out = Vec::new();
            loop {
                let d = (n % radix).unsigned_abs() as usize;
                out.push(digits[d]);
                n /= radix;
                if n == 0 {
                    break;
                }
            }
            if neg {
                out.push(b'-');
            }
            out.reverse();
            Ok(vstr(String::from_utf8(out).unwrap()))
        }
        "parseRadix" => {
            arity(name, args, 2)?;
            let s = expect_string(name, &args[0])?;
            let radix = as_int(&args[1])?;
            if !(2..=36).contains(&radix) {
                return Err("parseRadix: radix must be in 2..=36".to_string());
            }
            i64::from_str_radix(s.trim(), radix as u32)
                .map(vi64)
                .map_err(|_| format!("parseRadix: not a base-{radix} integer"))
        }
        "tryNum" => {
            arity(name, args, 1)?;
            match args[0].typ {
                1..=5 => Ok(args[0].clone()),
                7 => Ok(args[0]
                    .as_string()
                    .trim()
                    .parse::<f64>()
                    .map(num_result)
                    .unwrap_or_else(|_| vnull())),
                _ => Ok(vnull()),
            }
        }
        // Deterministic pseudo-random stream (xorshift64*), seedable via
        // `seedRandom`. Deliberately *not* a source of real entropy — the same
        // seed always yields the same sequence, keeping guest execution
        // reproducible; a host that wants real randomness seeds it through the
        // capability-gated `askHost` seam.
        "random" => {
            arity(name, args, 0)?;
            let x = RNG_STATE.with(|s| {
                let mut x = s.get();
                x ^= x >> 12;
                x ^= x << 25;
                x ^= x >> 27;
                s.set(x);
                x.wrapping_mul(0x2545F4914F6CDD1D)
            });
            Ok(vf64((x >> 11) as f64 / (1u64 << 53) as f64))
        }
        "seedRandom" => {
            arity(name, args, 1)?;
            let seed = as_int(&args[0])? as u64;
            RNG_STATE.with(|s| s.set(if seed == 0 { 0x9E3779B97F4A7C15 } else { seed }));
            Ok(vnull())
        }
        "gcd" => {
            arity(name, args, 2)?;
            Ok(vi64(gcd(as_int(&args[0])?.abs(), as_int(&args[1])?.abs())))
        }
        "lcm" => {
            arity(name, args, 2)?;
            let (a, b) = (as_int(&args[0])?.abs(), as_int(&args[1])?.abs());
            if a == 0 || b == 0 {
                Ok(vi64(0))
            } else {
                Ok(vi64(a / gcd(a, b) * b))
            }
        }

        // ---- foundation: reflection / conversion ---------------------------
        "typeOf" => {
            arity(name, args, 1)?;
            // `typeOf` exposes a single unified `number` type: the VM's distinct
            // numeric representations (i16..f64) all report as `number`. A
            // front-end whose language distinguishes int/double inspects the
            // value tag directly instead.
            let t = match args[0].typ {
                1..=5 => "number",
                _ => type_name(&args[0]),
            };
            Ok(vstr(t.to_string()))
        }
        "isNull" => {
            arity(name, args, 1)?;
            Ok(vbool(args[0].typ == 0))
        }
        "len" | "length" => {
            arity(name, args, 1)?;
            match args[0].typ {
                7 => Ok(vi64(args[0].as_string().chars().count() as i64)),
                9 => Ok(vi64(args[0].as_array().borrow().data.len() as i64)),
                8 => Ok(vi64(args[0].as_object().borrow().data.data.len() as i64)),
                _ => Err("len expects a string, array, or object".to_string()),
            }
        }
        // Emptiness of a string / list / map — the universal size getters behind
        // the `isEmpty` / `isNotEmpty` members of every sized core type.
        "isEmpty" | "isNotEmpty" => {
            arity(name, args, 1)?;
            let n = match args[0].typ {
                7 => args[0].as_string().chars().count(),
                9 => args[0].as_array().borrow().data.len(),
                8 => args[0].as_object().borrow().data.data.len(),
                _ => return Err(format!("{name} expects a string, array, or object")),
            };
            Ok(vbool(if name == "isEmpty" { n == 0 } else { n != 0 }))
        }
        "str" => {
            arity(name, args, 1)?;
            Ok(vstr(match args[0].typ {
                7 => args[0].as_string(),
                _ => args[0].stringify().trim_matches('"').to_string(),
            }))
        }
        "num" => {
            arity(name, args, 1)?;
            match args[0].typ {
                7 => args[0]
                    .as_string()
                    .trim()
                    .parse::<f64>()
                    .map(num_result)
                    .map_err(|_| "num: not a numeric string".to_string()),
                _ => Ok(num_result(as_num(&args[0])?)),
            }
        }
        "int" => {
            arity(name, args, 1)?;
            match args[0].typ {
                7 => args[0]
                    .as_string()
                    .trim()
                    .parse::<i64>()
                    .map(vi64)
                    .map_err(|_| "int: not an integer string".to_string()),
                _ => Ok(vi64(as_int(&args[0])?)),
            }
        }
        "bool" => {
            arity(name, args, 1)?;
            Ok(vbool(truthy(&args[0])))
        }
        // Force a floating-point value (the numeric `toDouble` member): unlike
        // `num`, never collapses a whole value back to an integer.
        "toDouble" => {
            arity(name, args, 1)?;
            Ok(vf64(as_num(&args[0])?))
        }
        "isNegative" => {
            arity(name, args, 1)?;
            Ok(vbool(as_num(&args[0])? < 0.0))
        }
        // The numeric `toString` member: integers stringify plainly (`3`), floats
        // always keep a decimal point (`3.0`), matching Dart's `num.toString()`.
        "toString" => {
            arity(name, args, 1)?;
            if matches!(args[0].typ, 1 | 2 | 3) {
                Ok(vstr(as_int(&args[0])?.to_string()))
            } else if matches!(args[0].typ, 4 | 5) {
                let d = as_num(&args[0])?;
                Ok(vstr(if d.fract() == 0.0 { format!("{d:.1}") } else { format!("{d}") }))
            } else {
                // Any other value stringifies via the VM's display coercion, so
                // `x.toString()` is total.
                Ok(vstr(args[0].to_display()))
            }
        }
        "toStringAsFixed" => {
            at_least(name, args, 2)?;
            let d = as_num(&args[0])?;
            let k = as_int(&args[1])? as usize;
            Ok(vstr(format!("{d:.*}", k)))
        }
        "jsonParse" => {
            arity(name, args, 1)?;
            if args[0].typ != 7 {
                return Err("jsonParse expects a string".to_string());
            }
            serde_json::from_str::<serde_json::Value>(&args[0].as_string())
                .map(|j| json_to_val(&j))
                .map_err(|e| format!("jsonParse: {e}"))
        }
        "jsonStringify" => {
            arity(name, args, 1)?;
            Ok(vstr(val_to_json(&args[0]).to_string()))
        }
        // Pure, deterministic byte codecs — the `dart:convert` UTF-8 / Base64
        // surface, provided natively in-process rather than over the host seam.
        // A byte list is a VM array of integers in 0..=255.
        "utf8Encode" => {
            arity(name, args, 1)?;
            let s = expect_string(name, &args[0])?;
            Ok(varr(s.into_bytes().into_iter().map(|b| vi64(b as i64)).collect()))
        }
        "utf8Decode" => {
            arity(name, args, 1)?;
            let bytes = expect_bytes(name, &args[0])?;
            String::from_utf8(bytes)
                .map(vstr)
                .map_err(|_| format!("{name}: invalid UTF-8"))
        }
        "base64Encode" => {
            arity(name, args, 1)?;
            Ok(vstr(base64_encode(&expect_bytes(name, &args[0])?)))
        }
        "base64Decode" => {
            arity(name, args, 1)?;
            let s = expect_string(name, &args[0])?;
            base64_decode(&s).map(|bytes| varr(bytes.into_iter().map(|b| vi64(b as i64)).collect()))
        }

        // ---- foundation: object --------------------------------------------
        "keys" => {
            arity(name, args, 1)?;
            let o = expect_object(name, &args[0])?;
            let mut ks: Vec<String> = o.borrow().data.data.keys().cloned().collect();
            ks.sort();
            Ok(varr(ks.into_iter().map(vstr).collect()))
        }
        "values" => {
            arity(name, args, 1)?;
            let o = expect_object(name, &args[0])?;
            let mut pairs: Vec<(String, Val)> =
                o.borrow().data.data.iter().map(|(k, v)| (k.clone(), v.clone())).collect();
            pairs.sort_by(|a, b| a.0.cmp(&b.0));
            Ok(varr(pairs.into_iter().map(|(_, v)| v).collect()))
        }
        "entries" => {
            arity(name, args, 1)?;
            let o = expect_object(name, &args[0])?;
            let mut pairs: Vec<(String, Val)> =
                o.borrow().data.data.iter().map(|(k, v)| (k.clone(), v.clone())).collect();
            pairs.sort_by(|a, b| a.0.cmp(&b.0));
            Ok(varr(pairs.into_iter().map(|(k, v)| varr(vec![vstr(k), v])).collect()))
        }
        "has" => {
            arity(name, args, 2)?;
            let o = expect_object(name, &args[0])?;
            let key = expect_string(name, &args[1])?;
            let present = o.borrow().data.data.contains_key(&key);
            Ok(vbool(present))
        }
        "get" => {
            at_least(name, args, 2)?;
            let default = args.get(2).cloned().unwrap_or_else(vnull);
            match args[0].typ {
                8 => {
                    let o = args[0].as_object();
                    let key = expect_string(name, &args[1])?;
                    let v = { o.borrow().data.data.get(&key).cloned().unwrap_or(default) };
                    Ok(v)
                }
                9 => {
                    let a = args[0].as_array();
                    let idx = as_int(&args[1])?;
                    let v = { a.borrow().data.get(idx as usize).cloned().unwrap_or(default) };
                    Ok(v)
                }
                _ => Err("get expects an object or array".to_string()),
            }
        }
        "setKey" => {
            arity(name, args, 3)?;
            let o = expect_object(name, &args[0])?;
            let key = expect_string(name, &args[1])?;
            o.borrow_mut().data.data.insert(key, args[2].clone());
            Ok(args[0].clone())
        }
        "delKey" => {
            arity(name, args, 2)?;
            let o = expect_object(name, &args[0])?;
            let key = expect_string(name, &args[1])?;
            o.borrow_mut().data.data.remove(&key);
            Ok(args[0].clone())
        }
        // Unified indexed store used to lower nested/computed assignment targets
        // (`a.b.c = v`, `a[i].x = v`, `o.a[i] = v`). The container is whatever the
        // base expression evaluated to — an object (string key) or an array
        // (numeric index, the array grown with nulls if needed) — and because both
        // are reference types the mutation is visible through every alias. Returns
        // the assigned value so the expression form (`x = a.b.c = v`) yields `v`.
        "__setIndex" => {
            arity(name, args, 3)?;
            let c = &args[0];
            if c.typ == 8 {
                let o = c.as_object();
                let key = expect_string(name, &args[1])?;
                o.borrow_mut().data.data.insert(key, args[2].clone());
            } else if c.typ == 9 {
                let a = c.as_array();
                let idx = as_num(&args[1]).map_err(|_| {
                    format!("{name}: array index must be a number")
                })? as i64;
                if idx >= 0 {
                    let i = idx as usize;
                    let mut b = a.borrow_mut();
                    while b.data.len() <= i {
                        b.data.push(vnull());
                    }
                    b.data[i] = args[2].clone();
                }
            } else {
                return Err(format!("{name}: cannot assign into {}", type_name(c)));
            }
            Ok(args[2].clone())
        }
        // Bounds-checked indexed store: `setAt(list, i, v)` replaces an existing
        // element and errors (a guest trap) on any out-of-range index. This is
        // the strict counterpart of the assignment opcode's auto-growing store —
        // a front-end for a bounds-strict language lowers `list[i] = v` to this
        // builtin instead. Returns the assigned value.
        "setAt" => {
            arity(name, args, 3)?;
            let a = expect_array(name, &args[0])?;
            let idx = as_int(&args[1])?;
            let mut b = a.borrow_mut();
            if idx < 0 || idx as usize >= b.data.len() {
                return Err(format!(
                    "setAt: index {idx} out of range for length {}",
                    b.data.len()
                ));
            }
            b.data[idx as usize] = args[2].clone();
            Ok(args[2].clone())
        }
        "merge" => {
            arity(name, args, 2)?;
            let a = expect_object(name, &args[0])?;
            let b = expect_object(name, &args[1])?;
            let mut m: ValMap = a.borrow().data.data.clone();
            for (k, v) in b.borrow().data.data.iter() {
                m.insert(k.clone(), v.clone());
            }
            Ok(vobj(-2, m))
        }
        // Remove from a collection — the `remove` member. Map receiver: delete a
        // key and return the value that was removed (or null); distinct from
        // `delKey`, which returns the map. List receiver: remove the first
        // element equal to the argument and return whether one was removed.
        "remove" => {
            arity(name, args, 2)?;
            if args[0].typ == 9 {
                let a = args[0].as_array();
                let mut b = a.borrow_mut();
                let pos = b.data.iter().position(|v| values_equal(v, &args[1]));
                if let Some(i) = pos {
                    b.data.remove(i);
                }
                return Ok(vbool(pos.is_some()));
            }
            let o = expect_object(name, &args[0])?;
            let removed = o.borrow_mut().data.data.remove(&expect_string(name, &args[1])?);
            Ok(removed.unwrap_or_else(vnull))
        }
        // Insert `value` under `key` only if absent, then return the value now
        // held for `key` — the map `putIfAbsent` member.
        "putIfAbsent" => {
            arity(name, args, 3)?;
            let o = expect_object(name, &args[0])?;
            let key = expect_string(name, &args[1])?;
            let mut b = o.borrow_mut();
            if !b.data.data.contains_key(&key) {
                b.data.data.insert(key.clone(), args[2].clone());
            }
            Ok(b.data.data.get(&key).cloned().unwrap_or_else(vnull))
        }

        // ---- foundation: array ---------------------------------------------
        // Variadic, matching JS `Array.prototype.push(...items)`: append every
        // trailing argument. The transpiler rewrites `xs.push(a, b, c)` to
        // `push(xs, a, b, c)`, so rejecting >2 args silently aborts the VM turn
        // (a recoverable stdlib error, so no panic/log) — which is how a single
        // `verts.push(x, y, z, ...)` could leave the whole app a blank screen.
        // (`emit` is the same append; it stays as the hot-path alias.)
        "push" => {
            at_least(name, args, 2)?;
            let a = expect_array(name, &args[0])?;
            let mut b = a.borrow_mut();
            b.data.reserve(args.len() - 1);
            for v in &args[1..] {
                b.data.push(v.clone());
            }
            drop(b);
            Ok(args[0].clone())
        }
        // Append every trailing argument to `args[0]` in one call. The renderer's
        // hot path emits a fixed 24-float SDF instance per primitive; doing that as
        // 24 separate `push` calls paid the VM's per-call dispatch (frame setup,
        // arg-array build, native trampoline) 24 times per primitive. `emit` pays
        // it once, appending the whole instance in a single native call — a large
        // paint-throughput win with thousands of primitives per frame.
        "emit" => {
            at_least(name, args, 1)?;
            let a = expect_array(name, &args[0])?;
            let mut b = a.borrow_mut();
            b.data.reserve(args.len() - 1);
            for v in &args[1..] {
                b.data.push(v.clone());
            }
            drop(b);
            Ok(args[0].clone())
        }
        "pop" => {
            arity(name, args, 1)?;
            let a = expect_array(name, &args[0])?;
            let v = { a.borrow_mut().data.pop().unwrap_or_else(vnull) };
            Ok(v)
        }
        "shift" => {
            arity(name, args, 1)?;
            let a = expect_array(name, &args[0])?;
            let mut b = a.borrow_mut();
            if b.data.is_empty() {
                Ok(vnull())
            } else {
                Ok(b.data.remove(0))
            }
        }
        "unshift" => {
            arity(name, args, 2)?;
            let a = expect_array(name, &args[0])?;
            a.borrow_mut().data.insert(0, args[1].clone());
            Ok(args[0].clone())
        }
        "slice" => {
            at_least(name, args, 2)?;
            let start = as_int(&args[1])?;
            let end = args.get(2).map(as_int).transpose()?;
            match args[0].typ {
                9 => {
                    let a = args[0].as_array();
                    let b = a.borrow();
                    let (s, e) = clamp_range(start, end, b.data.len());
                    Ok(varr(b.data[s..e].to_vec()))
                }
                7 => {
                    let chars: Vec<char> = args[0].as_string().chars().collect();
                    let (s, e) = clamp_range(start, end, chars.len());
                    Ok(vstr(chars[s..e].iter().collect()))
                }
                _ => Err("slice expects a string or array".to_string()),
            }
        }
        "concat" => {
            arity(name, args, 2)?;
            match (args[0].typ, args[1].typ) {
                (9, 9) => {
                    // Reserve the exact final length up front and clone elements
                    // straight into it — one allocation, no throwaway temp Vec.
                    // `concat` is the workhorse of the layout reassembly path, so
                    // this runs on the hot frame loop.
                    let a = args[0].as_array();
                    let b = args[1].as_array();
                    let a_ref = a.borrow();
                    let b_ref = b.borrow();
                    let mut out = Vec::with_capacity(a_ref.data.len() + b_ref.data.len());
                    out.extend(a_ref.data.iter().cloned());
                    out.extend(b_ref.data.iter().cloned());
                    Ok(varr(out))
                }
                (7, _) | (_, 7) => Ok(vstr(format!(
                    "{}{}",
                    str_of(&args[0]),
                    str_of(&args[1])
                ))),
                _ => Err("concat expects two arrays or a string".to_string()),
            }
        }
        "reverse" => {
            arity(name, args, 1)?;
            match args[0].typ {
                9 => {
                    let a = args[0].as_array();
                    a.borrow_mut().data.reverse();
                    Ok(args[0].clone())
                }
                7 => Ok(vstr(args[0].as_string().chars().rev().collect())),
                _ => Err("reverse expects a string or array".to_string()),
            }
        }
        // Non-mutating reverse (the list `reversed` getter): yields a fresh array
        // and leaves the receiver untouched, unlike the in-place `reverse`.
        "reversed" => {
            arity(name, args, 1)?;
            let mut v = expect_array(name, &args[0])?.borrow().data.clone();
            v.reverse();
            Ok(varr(v))
        }
        // Bulk add-into: for a list receiver, append every element of another
        // list in place (the list `addAll` member); for a map receiver, insert
        // every entry of another map in place, later entries winning (the map
        // `addAll` member). Distinct from `concat`/`merge`, which build a new
        // collection. Returns null.
        "pushAll" => {
            arity(name, args, 2)?;
            if args[0].typ == 8 {
                let o = expect_object(name, &args[0])?;
                let other = expect_object(name, &args[1])?;
                let entries: Vec<(String, Val)> = other
                    .borrow()
                    .data
                    .data
                    .iter()
                    .map(|(k, v)| (k.clone(), v.clone()))
                    .collect();
                let mut b = o.borrow_mut();
                for (k, v) in entries {
                    b.data.data.insert(k, v);
                }
                return Ok(vnull());
            }
            let a = expect_array(name, &args[0])?;
            let other = expect_array(name, &args[1])?.borrow().data.clone();
            a.borrow_mut().data.extend(other);
            Ok(vnull())
        }
        "removeAt" => {
            arity(name, args, 2)?;
            let a = expect_array(name, &args[0])?;
            let i = as_int(&args[1])? as usize;
            let mut b = a.borrow_mut();
            if i < b.data.len() {
                Ok(b.data.remove(i))
            } else {
                Err("RangeError: removeAt out of range".to_string())
            }
        }
        "insert" => {
            arity(name, args, 3)?;
            let a = expect_array(name, &args[0])?;
            let mut b = a.borrow_mut();
            let idx = (as_int(&args[1])? as usize).min(b.data.len());
            b.data.insert(idx, args[2].clone());
            Ok(vnull())
        }
        "clear" => {
            arity(name, args, 1)?;
            expect_array(name, &args[0])?.borrow_mut().data.clear();
            Ok(vnull())
        }
        "contains" => {
            arity(name, args, 2)?;
            match args[0].typ {
                9 => {
                    let a = args[0].as_array();
                    let found = a.borrow().data.iter().any(|v| values_equal(v, &args[1]));
                    Ok(vbool(found))
                }
                7 => Ok(vbool(args[0].as_string().contains(&str_of(&args[1])))),
                _ => Err("contains expects a string or array".to_string()),
            }
        }
        "indexOf" => {
            at_least(name, args, 2)?;
            // Optional third argument: the index to start searching from
            // (clamped; a negative value counts from the end).
            let from = args.get(2).map(as_int).transpose()?.unwrap_or(0);
            match args[0].typ {
                9 => {
                    let a = args[0].as_array();
                    let b = a.borrow();
                    let (s, _) = clamp_range(from, None, b.data.len());
                    let idx = b.data[s..].iter().position(|v| values_equal(v, &args[1]));
                    Ok(vi64(idx.map(|i| (i + s) as i64).unwrap_or(-1)))
                }
                7 => {
                    let hay = args[0].as_string();
                    let needle = str_of(&args[1]);
                    let chars: Vec<char> = hay.chars().collect();
                    let (s, _) = clamp_range(from, None, chars.len());
                    let tail: String = chars[s..].iter().collect();
                    Ok(vi64(
                        tail.find(&needle)
                            .map(|b| (tail[..b].chars().count() + s) as i64)
                            .unwrap_or(-1),
                    ))
                }
                _ => Err("indexOf expects a string or array".to_string()),
            }
        }
        // Search from the end: the index of the last occurrence of the needle in
        // a list or string, or -1. An optional third argument bounds the search
        // to indices at or below it.
        "lastIndexOf" => {
            at_least(name, args, 2)?;
            match args[0].typ {
                9 => {
                    let a = args[0].as_array();
                    let b = a.borrow();
                    let upper = args
                        .get(2)
                        .map(as_int)
                        .transpose()?
                        .map(|i| if i < 0 { (b.data.len() as i64 + i).max(-1) } else { i })
                        .unwrap_or(b.data.len() as i64 - 1);
                    let mut found = -1i64;
                    for (i, v) in b.data.iter().enumerate() {
                        if i as i64 <= upper && values_equal(v, &args[1]) {
                            found = i as i64;
                        }
                    }
                    Ok(vi64(found))
                }
                7 => {
                    let hay = args[0].as_string();
                    let needle = str_of(&args[1]);
                    Ok(vi64(
                        hay.rfind(&needle).map(|b| hay[..b].chars().count() as i64).unwrap_or(-1),
                    ))
                }
                _ => Err("lastIndexOf expects a string or array".to_string()),
            }
        }
        // Read one element with negative-from-the-end indexing; out of range
        // reads as null. Works on lists and strings.
        "at" => {
            arity(name, args, 2)?;
            let i = as_int(&args[1])?;
            match args[0].typ {
                9 => {
                    let a = args[0].as_array();
                    let b = a.borrow();
                    let idx = if i < 0 { b.data.len() as i64 + i } else { i };
                    if idx < 0 || idx as usize >= b.data.len() {
                        Ok(vnull())
                    } else {
                        Ok(b.data[idx as usize].clone())
                    }
                }
                7 => {
                    let chars: Vec<char> = args[0].as_string().chars().collect();
                    let idx = if i < 0 { chars.len() as i64 + i } else { i };
                    if idx < 0 || idx as usize >= chars.len() {
                        Ok(vnull())
                    } else {
                        Ok(vstr(chars[idx as usize].to_string()))
                    }
                }
                _ => Err("at expects a string or array".to_string()),
            }
        }
        // In-place remove-and-insert: `splice(list, start[, deleteCount,
        // items...])` removes `deleteCount` elements at `start` (negative counts
        // from the end; the count defaults to "to the end"), inserts the trailing
        // arguments in their place, and returns the removed elements as a new
        // list.
        "splice" => {
            at_least(name, args, 2)?;
            let a = expect_array(name, &args[0])?;
            let mut b = a.borrow_mut();
            let len = b.data.len();
            let (start, _) = clamp_range(as_int(&args[1])?, None, len);
            let del = match args.get(2) {
                Some(v) => (as_int(v)?.max(0) as usize).min(len - start),
                None => len - start,
            };
            let removed: Vec<Val> = b.data.splice(start..start + del, args[3..].iter().cloned()).collect();
            Ok(varr(removed))
        }
        // A new list with nested lists expanded in place, `depth` levels deep
        // (default 1; pass a large depth for a full flatten).
        "flatten" => {
            at_least(name, args, 1)?;
            let depth = args.get(1).map(as_int).transpose()?.unwrap_or(1);
            fn flat_into(src: &[Val], depth: i64, out: &mut Vec<Val>) {
                for v in src {
                    if v.typ == 9 && depth > 0 {
                        flat_into(&v.as_array().borrow().data, depth - 1, out);
                    } else {
                        out.push(v.clone());
                    }
                }
            }
            let a = expect_array(name, &args[0])?;
            let mut out = Vec::new();
            flat_into(&a.borrow().data, depth, &mut out);
            Ok(varr(out))
        }
        // Whether any value in the map equals the argument (the map
        // `containsValue` member).
        "hasValue" => {
            arity(name, args, 2)?;
            let o = expect_object(name, &args[0])?;
            let found = o.borrow().data.data.values().any(|v| values_equal(v, &args[1]));
            Ok(vbool(found))
        }
        // The string's UTF-16-ish code units as a list of ints (chars here — the
        // VM's strings are unicode scalar sequences).
        "codeUnits" => {
            arity(name, args, 1)?;
            let s = expect_string(name, &args[0])?;
            Ok(varr(s.chars().map(|c| vi64(c as i64)).collect()))
        }
        // Three-way comparison for numbers and strings: -1, 0, or 1. The
        // primitive behind `compareTo` / `localeCompare`-style members.
        "compareTo" => {
            arity(name, args, 2)?;
            if args[0].typ == 7 && args[1].typ == 7 {
                let (a, b) = (args[0].as_string(), args[1].as_string());
                return Ok(vi64(match a.cmp(&b) {
                    std::cmp::Ordering::Less => -1,
                    std::cmp::Ordering::Equal => 0,
                    std::cmp::Ordering::Greater => 1,
                }));
            }
            let (a, b) = (as_num(&args[0])?, as_num(&args[1])?);
            Ok(vi64(if a < b { -1 } else if a > b { 1 } else { 0 }))
        }
        "join" => {
            at_least(name, args, 1)?;
            let a = expect_array(name, &args[0])?;
            // The separator is optional (defaults to ""); a source language whose
            // `join` defaults differently supplies its own default at compile time.
            let sep = match args.get(1) {
                Some(v) => expect_string(name, v)?,
                None => String::new(),
            };
            let parts: Vec<String> = a.borrow().data.iter().map(str_of).collect();
            Ok(vstr(parts.join(&sep)))
        }
        "range" => {
            at_least(name, args, 1)?;
            let (start, end, step) = match args.len() {
                1 => (0, as_int(&args[0])?, 1),
                2 => (as_int(&args[0])?, as_int(&args[1])?, 1),
                _ => (as_int(&args[0])?, as_int(&args[1])?, as_int(&args[2])?),
            };
            if step == 0 {
                return Err("range step cannot be zero".to_string());
            }
            let mut out = Vec::new();
            let mut i = start;
            // Bound output so a pathological range can't allocate unboundedly;
            // the governor still charges the resulting memory.
            while (step > 0 && i < end) || (step < 0 && i > end) {
                out.push(vi64(i));
                if out.len() > 10_000_000 {
                    return Err("range too large".to_string());
                }
                i += step;
            }
            Ok(varr(out))
        }
        "first" => {
            arity(name, args, 1)?;
            let a = expect_array(name, &args[0])?;
            let v = a.borrow().data.first().cloned().unwrap_or_else(vnull);
            Ok(v)
        }
        "last" => {
            arity(name, args, 1)?;
            let a = expect_array(name, &args[0])?;
            let v = a.borrow().data.last().cloned().unwrap_or_else(vnull);
            Ok(v)
        }
        "sort" => {
            arity(name, args, 1)?;
            let a = expect_array(name, &args[0])?;
            // Numeric if all-numeric, else lexicographic by string form. Stable.
            let all_num = a.borrow().data.iter().all(|v| as_num(v).is_ok());
            if all_num {
                a.borrow_mut()
                    .data
                    .sort_by(|x, y| as_num(x).unwrap().partial_cmp(&as_num(y).unwrap()).unwrap());
            } else {
                a.borrow_mut().data.sort_by(|x, y| str_of(x).cmp(&str_of(y)));
            }
            Ok(args[0].clone())
        }
        "fill" => {
            arity(name, args, 2)?;
            let n = as_int(&args[0])?.max(0) as usize;
            if n > 10_000_000 {
                return Err("fill count too large".to_string());
            }
            Ok(varr(vec![args[1].clone(); n]))
        }
        // The first / last `n` elements as a new list (the `take` / `skip`
        // members; negative or over-length counts clamp). No callback, so native.
        "take" => {
            arity(name, args, 2)?;
            let a = expect_array(name, &args[0])?;
            let b = a.borrow();
            let n = (as_int(&args[1])?.max(0) as usize).min(b.data.len());
            Ok(varr(b.data[..n].to_vec()))
        }
        "skip" => {
            arity(name, args, 2)?;
            let a = expect_array(name, &args[0])?;
            let b = a.borrow();
            let n = (as_int(&args[1])?.max(0) as usize).min(b.data.len());
            Ok(varr(b.data[n..].to_vec()))
        }
        // A new list with duplicate values removed, first occurrence kept (the
        // `toSet`/dedupe member — a set is modelled as a list here).
        "toSet" => {
            arity(name, args, 1)?;
            let a = expect_array(name, &args[0])?;
            let mut out: Vec<Val> = Vec::new();
            for v in a.borrow().data.iter() {
                if !out.iter().any(|u| values_equal(u, v)) {
                    out.push(v.clone());
                }
            }
            Ok(varr(out))
        }
        // In-place Fisher–Yates shuffle using the deterministic `random` stream.
        "shuffle" => {
            arity(name, args, 1)?;
            let a = expect_array(name, &args[0])?;
            let mut b = a.borrow_mut();
            let len = b.data.len();
            for i in (1..len).rev() {
                let r = RNG_STATE.with(|s| {
                    let mut x = s.get();
                    x ^= x >> 12;
                    x ^= x << 25;
                    x ^= x >> 27;
                    s.set(x);
                    x.wrapping_mul(0x2545F4914F6CDD1D)
                });
                let j = (r >> 11) as usize % (i + 1);
                b.data.swap(i, j);
            }
            Ok(args[0].clone())
        }

        // ---- foundation: string --------------------------------------------
        "upper" => str_map(name, args, |s| s.to_uppercase()),
        "lower" => str_map(name, args, |s| s.to_lowercase()),
        "trim" => str_map(name, args, |s| s.trim().to_string()),
        "trimStart" => str_map(name, args, |s| s.trim_start().to_string()),
        "trimEnd" => str_map(name, args, |s| s.trim_end().to_string()),
        "codeUnitAt" => {
            at_least(name, args, 2)?;
            let s = expect_string(name, &args[0])?;
            let i = as_int(&args[1])? as usize;
            Ok(vi64(s.encode_utf16().nth(i).map(|c| c as i64).unwrap_or(0)))
        }
        "replaceFirst" => {
            arity(name, args, 3)?;
            let s = expect_string(name, &args[0])?;
            let from = expect_string(name, &args[1])?;
            let to = expect_string(name, &args[2])?;
            Ok(vstr(s.replacen(&from as &str, &to, 1)))
        }
        "split" => {
            arity(name, args, 2)?;
            let s = expect_string(name, &args[0])?;
            let sep = expect_string(name, &args[1])?;
            let parts: Vec<Val> = if sep.is_empty() {
                s.chars().map(|c| vstr(c.to_string())).collect()
            } else {
                s.split(&sep as &str).map(|p| vstr(p.to_string())).collect()
            };
            Ok(varr(parts))
        }
        "substring" => {
            at_least(name, args, 2)?;
            let chars: Vec<char> = expect_string(name, &args[0])?.chars().collect();
            let start = as_int(&args[1])?;
            let end = args.get(2).map(as_int).transpose()?;
            let (s, e) = clamp_range(start, end, chars.len());
            Ok(vstr(chars[s..e].iter().collect()))
        }
        "charAt" => {
            arity(name, args, 2)?;
            let chars: Vec<char> = expect_string(name, &args[0])?.chars().collect();
            let idx = as_int(&args[1])?;
            Ok(vstr(
                usize::try_from(idx)
                    .ok()
                    .and_then(|i| chars.get(i))
                    .map(|c| c.to_string())
                    .unwrap_or_default(),
            ))
        }
        "replace" => {
            arity(name, args, 3)?;
            let s = expect_string(name, &args[0])?;
            let from = expect_string(name, &args[1])?;
            let to = expect_string(name, &args[2])?;
            Ok(vstr(s.replace(&from as &str, &to)))
        }
        "repeat" => {
            arity(name, args, 2)?;
            let s = expect_string(name, &args[0])?;
            let n = as_int(&args[1])?.max(0) as usize;
            if s.len().saturating_mul(n) > 64 * 1024 * 1024 {
                return Err("repeat result too large".to_string());
            }
            Ok(vstr(s.repeat(n)))
        }
        "startsWith" => {
            arity(name, args, 2)?;
            Ok(vbool(expect_string(name, &args[0])?.starts_with(&expect_string(name, &args[1])?)))
        }
        "endsWith" => {
            arity(name, args, 2)?;
            Ok(vbool(expect_string(name, &args[0])?.ends_with(&expect_string(name, &args[1])?)))
        }
        "padStart" => pad(name, args, true),
        "padEnd" => pad(name, args, false),
        "ord" => {
            arity(name, args, 1)?;
            let s = expect_string(name, &args[0])?;
            Ok(vi64(s.chars().next().map(|c| c as i64).unwrap_or(0)))
        }
        "chr" => {
            arity(name, args, 1)?;
            let code = as_int(&args[0])?;
            Ok(vstr(
                u32::try_from(code)
                    .ok()
                    .and_then(char::from_u32)
                    .map(|c| c.to_string())
                    .unwrap_or_default(),
            ))
        }

        // ---- oop ------------------------------------------------------------
        "class" => oop_class(args),
        "extend" => oop_extend(args),
        "new" => oop_new(args),
        "method" => oop_method(args),
        "parentMethod" => oop_parent_method(args),
        "superMethod" => super_method(args),
        "field" => {
            arity(name, args, 2)?;
            let o = expect_object(name, &args[0])?;
            let key = expect_string(name, &args[1])?;
            let v = { o.borrow().data.data.get(&key).cloned().unwrap_or_else(vnull) };
            Ok(v)
        }
        "setField" => {
            arity(name, args, 3)?;
            let o = expect_object(name, &args[0])?;
            let key = expect_string(name, &args[1])?;
            o.borrow_mut().data.data.insert(key, args[2].clone());
            Ok(args[0].clone())
        }
        "isInstance" => {
            arity(name, args, 2)?;
            Ok(vbool(is_instance_of(&args[0], &args[1])))
        }
        "className" | "classOf" => {
            arity(name, args, 1)?;
            if args[0].typ != 8 {
                return Ok(vnull());
            }
            let o = args[0].as_object();
            let b = o.borrow();
            Ok(b.data.data.get("__class_name").cloned().unwrap_or_else(vnull))
        }

        // ---- closures -------------------------------------------------------
        "cell" => {
            at_least(name, args, 0)?;
            let mut m = ValMap::default();
            m.insert("value".to_string(), args.first().cloned().unwrap_or_else(vnull));
            Ok(vobj(CELL_TYPE, m))
        }
        "cellGet" => {
            arity(name, args, 1)?;
            let o = expect_object(name, &args[0])?;
            let v = { o.borrow().data.data.get("value").cloned().unwrap_or_else(vnull) };
            Ok(v)
        }
        "cellSet" => {
            arity(name, args, 2)?;
            let o = expect_object(name, &args[0])?;
            o.borrow_mut().data.data.insert("value".to_string(), args[1].clone());
            Ok(args[0].clone())
        }

        _ => Err(format!("unknown builtin '{name}'")),
    }
}

// ----------------------------------------------------------------------------
// Helpers shared across builtins.
// ----------------------------------------------------------------------------

pub(crate) fn unary(name: &str, args: &[Val], f: impl Fn(f64) -> f64) -> Result<Val, String> {
    arity(name, args, 1)?;
    Ok(num_result(f(as_num(&args[0])?)))
}

/// Like `unary`, but the mathematically-integer results (`floor`, `ceil`, …)
/// always come back as integers when finite.
pub(crate) fn unary_int(name: &str, args: &[Val], f: impl Fn(f64) -> f64) -> Result<Val, String> {
    arity(name, args, 1)?;
    Ok(num_result(f(as_num(&args[0])?)))
}

pub(crate) fn binary(name: &str, args: &[Val], f: impl Fn(f64, f64) -> f64) -> Result<Val, String> {
    arity(name, args, 2)?;
    Ok(num_result(f(as_num(&args[0])?, as_num(&args[1])?)))
}

pub(crate) fn str_map(name: &str, args: &[Val], f: impl Fn(String) -> String) -> Result<Val, String> {
    arity(name, args, 1)?;
    Ok(vstr(f(expect_string(name, &args[0])?)))
}

pub(crate) fn pad(name: &str, args: &[Val], start: bool) -> Result<Val, String> {
    at_least(name, args, 2)?;
    let s = expect_string(name, &args[0])?;
    let width = as_int(&args[1])?.max(0) as usize;
    let pad_char = args
        .get(2)
        .map(str_of)
        .and_then(|p| p.chars().next())
        .unwrap_or(' ');
    let len = s.chars().count();
    if len >= width {
        return Ok(vstr(s));
    }
    let fill: String = std::iter::repeat(pad_char).take(width - len).collect();
    Ok(vstr(if start { format!("{fill}{s}") } else { format!("{s}{fill}") }))
}

pub(crate) fn expect_object(name: &str, v: &Val) -> Result<Rc<RefCell<Object>>, String> {
    if v.typ == 8 {
        Ok(v.as_object())
    } else {
        Err(format!("{name} expects an object, got {}", type_name(v)))
    }
}
pub(crate) fn expect_array(name: &str, v: &Val) -> Result<Rc<RefCell<Array>>, String> {
    if v.typ == 9 {
        Ok(v.as_array())
    } else {
        Err(format!("{name} expects an array, got {}", type_name(v)))
    }
}
pub(crate) fn expect_string(name: &str, v: &Val) -> Result<String, String> {
    if v.typ == 7 {
        Ok(v.as_string())
    } else {
        Err(format!("{name} expects a string, got {}", type_name(v)))
    }
}
/// Read a byte list (a VM array of integers, each taken mod 256) for the codec
/// builtins.
pub(crate) fn expect_bytes(name: &str, v: &Val) -> Result<Vec<u8>, String> {
    let a = expect_array(name, v)?;
    let b = a.borrow();
    let mut out = Vec::with_capacity(b.data.len());
    for item in b.data.iter() {
        out.push(as_int(item)? as u8);
    }
    Ok(out)
}

// ----------------------------------------------------------------------------
// Base64 (RFC 4648) — a pure, self-contained codec for the `base64Encode` /
// `base64Decode` builtins.
// ----------------------------------------------------------------------------

const B64: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

pub(crate) fn base64_encode(data: &[u8]) -> String {
    let mut out = String::with_capacity((data.len() + 2) / 3 * 4);
    for chunk in data.chunks(3) {
        let b = [chunk[0], *chunk.get(1).unwrap_or(&0), *chunk.get(2).unwrap_or(&0)];
        let n = ((b[0] as u32) << 16) | ((b[1] as u32) << 8) | (b[2] as u32);
        out.push(B64[((n >> 18) & 63) as usize] as char);
        out.push(B64[((n >> 12) & 63) as usize] as char);
        out.push(if chunk.len() > 1 { B64[((n >> 6) & 63) as usize] as char } else { '=' });
        out.push(if chunk.len() > 2 { B64[(n & 63) as usize] as char } else { '=' });
    }
    out
}

pub(crate) fn base64_decode(s: &str) -> Result<Vec<u8>, String> {
    let inv = |c: u8| -> Option<u32> { B64.iter().position(|&x| x == c).map(|p| p as u32) };
    let clean: Vec<u8> = s.bytes().filter(|&c| c != b'=' && !c.is_ascii_whitespace()).collect();
    let mut out = Vec::with_capacity(clean.len() / 4 * 3);
    for chunk in clean.chunks(4) {
        let mut n = 0u32;
        let mut bits = 0;
        for &c in chunk {
            let v = inv(c).ok_or_else(|| format!("invalid base64 char '{}'", c as char))?;
            n = (n << 6) | v;
            bits += 6;
        }
        let bytes = bits / 8;
        n <<= (4 - chunk.len()) as u32 * 6;
        let be = n.to_be_bytes(); // n occupies the low 24 bits
        for i in 0..bytes {
            out.push(be[1 + i]);
        }
    }
    Ok(out)
}

/// String form of a scalar/compound for joining and concatenation.
pub(crate) fn str_of(v: &Val) -> String {
    match v.typ {
        7 => v.as_string(),
        _ => v.stringify().trim_matches('"').to_string(),
    }
}

pub(crate) fn truthy(v: &Val) -> bool {
    match v.typ {
        0 => false,
        6 => v.as_bool(),
        7 => !v.as_string().is_empty(),
        9 => !v.as_array().borrow().data.is_empty(),
        8 => !v.as_object().borrow().data.data.is_empty(),
        _ => as_num(v).map(|n| n != 0.0).unwrap_or(true),
    }
}

pub(crate) fn clamp_range(start: i64, end: Option<i64>, len: usize) -> (usize, usize) {
    let len_i = len as i64;
    let norm = |i: i64| -> i64 {
        if i < 0 {
            (len_i + i).max(0)
        } else {
            i.min(len_i)
        }
    };
    let s = norm(start);
    let e = end.map(norm).unwrap_or(len_i);
    (s as usize, e.max(s) as usize)
}

pub(crate) fn gcd(mut a: i64, mut b: i64) -> i64 {
    while b != 0 {
        let t = b;
        b = a % b;
        a = t;
    }
    a
}

/// Structural-ish equality used by `contains`/`indexOf`: cheap and total. Scalars
/// compare by value; strings by content; other types by their stringification.
pub(crate) fn values_equal(a: &Val, b: &Val) -> bool {
    match (a.typ, b.typ) {
        (0, 0) => true,
        (6, 6) => a.as_bool() == b.as_bool(),
        (7, 7) => a.as_string() == b.as_string(),
        _ => match (as_num(a), as_num(b)) {
            (Ok(x), Ok(y)) => x == y,
            _ => a.stringify() == b.stringify(),
        },
    }
}

// ----------------------------------------------------------------------------
// OOP implementation.
// ----------------------------------------------------------------------------

/// `class(name, defaults, methods)` — build a class descriptor.
/// `name` is a string; `defaults` an object of default field values (or null);
/// `methods` an object of functions (or null).
pub(crate) fn oop_class(args: &[Val]) -> Result<Val, String> {
    at_least("class", args, 1)?;
    let name = expect_string("class", &args[0])?;
    let defaults = args.get(1).cloned().unwrap_or_else(vnull);
    let methods = args.get(2).cloned().unwrap_or_else(vnull);
    let mut m = ValMap::default();
    m.insert("__class_name".to_string(), vstr(name));
    m.insert("__defaults".to_string(), normalize_object(defaults));
    m.insert("__methods".to_string(), normalize_object(methods));
    m.insert("__parent".to_string(), vnull());
    Ok(vobj(CLASS_TYPE, m))
}

/// `extend(parent, name, defaults, methods)` — derive a subclass, inheriting and
/// overriding the parent's defaults and methods.
pub(crate) fn oop_extend(args: &[Val]) -> Result<Val, String> {
    at_least("extend", args, 2)?;
    let parent = args[0].clone();
    if parent.typ != 8 || object_typ(&parent) != CLASS_TYPE {
        return Err("extend expects a class as its first argument".to_string());
    }
    let name = expect_string("extend", &args[1])?;
    let defaults = args.get(2).cloned().unwrap_or_else(vnull);
    let methods = args.get(3).cloned().unwrap_or_else(vnull);

    let merged_defaults = merge_objects(class_field(&parent, "__defaults"), normalize_object(defaults));
    let merged_methods = merge_objects(class_field(&parent, "__methods"), normalize_object(methods));

    let mut m = ValMap::default();
    m.insert("__class_name".to_string(), vstr(name));
    m.insert("__defaults".to_string(), merged_defaults);
    m.insert("__methods".to_string(), merged_methods);
    m.insert("__parent".to_string(), parent);
    Ok(vobj(CLASS_TYPE, m))
}

/// `new(class, overrides?)` — instantiate a class. The instance starts from the
/// class's (flattened) default fields, applies any `overrides` object, and is
/// tagged with its class so `isInstance` / `method` work.
pub(crate) fn oop_new(args: &[Val]) -> Result<Val, String> {
    at_least("new", args, 1)?;
    let class = args[0].clone();
    if class.typ != 8 || object_typ(&class) != CLASS_TYPE {
        return Err("new expects a class".to_string());
    }
    let defaults = class_field(&class, "__defaults");
    let mut fields: ValMap = if defaults.typ == 8 {
        // Deep-ish copy of defaults so instances don't share mutable default
        // containers; scalars are cheap clones, containers get fresh copies.
        defaults
            .as_object()
            .borrow()
            .data
            .data
            .iter()
            .map(|(k, v)| (k.clone(), copy_value(v)))
            .collect()
    } else {
        ValMap::default()
    };
    if let Some(overrides) = args.get(1) {
        if overrides.typ == 8 {
            for (k, v) in overrides.as_object().borrow().data.data.iter() {
                fields.insert(k.clone(), v.clone());
            }
        }
    }
    fields.insert("__class_name".to_string(), class_field(&class, "__class_name"));
    fields.insert("__class".to_string(), class);
    Ok(vobj(INSTANCE_TYPE, fields))
}

/// `method(instance, name)` — resolve a method through the inheritance chain and
/// return the function value (the guest then calls it, passing the instance as
/// the receiver). Returns null if unknown.
pub(crate) fn oop_method(args: &[Val]) -> Result<Val, String> {
    arity("method", args, 2)?;
    let inst = &args[0];
    let mname = expect_string("method", &args[1])?;
    if inst.typ != 8 {
        return Ok(vnull());
    }
    let class = inst.as_object().borrow().data.data.get("__class").cloned();
    match class {
        Some(c) => Ok(lookup_method(&c, &mname).unwrap_or_else(vnull)),
        None => Ok(vnull()),
    }
}

/// `parentMethod(instance, name)` — resolve a method starting from the *parent*
/// of the instance's class, enabling `super`-style dispatch.
pub(crate) fn oop_parent_method(args: &[Val]) -> Result<Val, String> {
    arity("parentMethod", args, 2)?;
    let inst = &args[0];
    let mname = expect_string("parentMethod", &args[1])?;
    if inst.typ != 8 {
        return Ok(vnull());
    }
    let class = inst.as_object().borrow().data.data.get("__class").cloned();
    let parent = class.and_then(|c| {
        if c.typ == 8 {
            c.as_object().borrow().data.data.get("__parent").cloned()
        } else {
            None
        }
    });
    match parent {
        Some(p) if p.typ == 8 => Ok(lookup_method(&p, &mname).unwrap_or_else(vnull)),
        _ => Ok(vnull()),
    }
}

/// `superMethod(proto, name, receiver)` — used by the JS front-end's `super.m()`
/// lowering. Walks `proto` and its `__parent` chain (the prototype links a
/// `class` desugaring builds) for the method `name`, and returns it *bound* to
/// `receiver` so the inherited body sees the right `this`. Returns null if the
/// method is not found anywhere on the chain.
pub(crate) fn super_method(args: &[Val]) -> Result<Val, String> {
    arity("superMethod", args, 3)?;
    let mut proto = args[0].clone();
    let name = expect_string("superMethod", &args[1])?;
    let receiver = args[2].clone();
    while proto.typ == 8 {
        let (entry, parent) = {
            let p = proto.as_object();
            let b = p.borrow();
            (b.data.data.get(&name).cloned(), b.data.data.get("__parent").cloned())
        };
        if let Some(m) = entry {
            if m.typ == 10 {
                let bound = m.as_func().borrow().bind(receiver);
                return Ok(Val { typ: 10, data: Payload::from(Rc::new(RefCell::new(bound))) });
            }
            return Ok(m);
        }
        match parent {
            Some(p) => proto = p,
            None => break,
        }
    }
    Ok(vnull())
}

pub(crate) fn lookup_method(class: &Val, name: &str) -> Option<Val> {
    if class.typ != 8 {
        return None;
    }
    let methods = class.as_object().borrow().data.data.get("__methods").cloned();
    if let Some(m) = methods {
        if m.typ == 8 {
            if let Some(f) = m.as_object().borrow().data.data.get(name).cloned() {
                return Some(f);
            }
        }
    }
    None
}

pub(crate) fn is_instance_of(inst: &Val, class: &Val) -> bool {
    if inst.typ != 8 || class.typ != 8 {
        return false;
    }
    let target = class
        .as_object()
        .borrow()
        .data
        .data
        .get("__class_name")
        .map(|n| str_of(n))
        .unwrap_or_default();
    let mut cur = inst.as_object().borrow().data.data.get("__class").cloned();
    while let Some(c) = cur {
        if c.typ != 8 {
            break;
        }
        let cname = c.as_object().borrow().data.data.get("__class_name").map(|n| str_of(n));
        if cname.as_deref() == Some(target.as_str()) {
            return true;
        }
        cur = c.as_object().borrow().data.data.get("__parent").cloned();
    }
    false
}

pub(crate) fn object_typ(v: &Val) -> i64 {
    if v.typ == 8 {
        v.as_object().borrow().typ
    } else {
        0
    }
}

pub(crate) fn class_field(class: &Val, key: &str) -> Val {
    class
        .as_object()
        .borrow()
        .data
        .data
        .get(key)
        .cloned()
        .unwrap_or_else(vnull)
}

/// Ensure a value is an object (turning null into an empty object), for the
/// `defaults` / `methods` slots of a class.
pub(crate) fn normalize_object(v: Val) -> Val {
    if v.typ == 8 {
        v
    } else {
        vobj(-2, ValMap::default())
    }
}

/// Shallow merge of two object-or-null values; `b` overrides `a`.
pub(crate) fn merge_objects(a: Val, b: Val) -> Val {
    let mut m: ValMap = ValMap::default();
    if a.typ == 8 {
        for (k, v) in a.as_object().borrow().data.data.iter() {
            m.insert(k.clone(), v.clone());
        }
    }
    if b.typ == 8 {
        for (k, v) in b.as_object().borrow().data.data.iter() {
            m.insert(k.clone(), v.clone());
        }
    }
    vobj(-2, m)
}

/// Fresh copy of a value used when seeding instance fields from class defaults,
/// so two instances never alias the same mutable container.
pub(crate) fn copy_value(v: &Val) -> Val {
    match v.typ {
        8 => {
            let src = v.as_object();
            let b = src.borrow();
            let m: ValMap =
                b.data.data.iter().map(|(k, val)| (k.clone(), copy_value(val))).collect();
            vobj(b.typ, m)
        }
        9 => {
            let src = v.as_array();
            let items: Vec<Val> = src.borrow().data.iter().map(copy_value).collect();
            varr(items)
        }
        _ => v.clone(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn math_core() {
        // Whole results collapse to integers (num_result); fractional stay f64.
        assert_eq!(invoke("sqrt", &[vf64(16.0)]).unwrap().as_i64(), 4);
        assert!((invoke("sqrt", &[vf64(2.0)]).unwrap().as_f64() - std::f64::consts::SQRT_2).abs() < 1e-12);
        assert_eq!(invoke("abs", &[vi64(-7)]).unwrap().as_i64(), 7);
        assert_eq!(invoke("pow", &[vi64(2), vi64(10)]).unwrap().as_i64(), 1024);
        assert_eq!(invoke("gcd", &[vi64(54), vi64(24)]).unwrap().as_i64(), 6);
        assert_eq!(invoke("max", &[vi64(3), vi64(9), vi64(5)]).unwrap().as_i64(), 9);
        assert_eq!(invoke("clamp", &[vi64(12), vi64(0), vi64(10)]).unwrap().as_i64(), 10);
        assert_eq!(invoke("factorial", &[vi64(5)]).unwrap().as_i64(), 120);
        assert!((invoke("PI", &[]).unwrap().as_f64() - std::f64::consts::PI).abs() < 1e-12);
        assert!(invoke("isNaN", &[invoke("NAN", &[]).unwrap()]).unwrap().as_bool());
    }

    #[test]
    fn foundation_collections() {
        let arr = varr(vec![vi64(3), vi64(1), vi64(2)]);
        assert_eq!(invoke("len", &[arr.clone()]).unwrap().as_i64(), 3);
        invoke("push", &[arr.clone(), vi64(9)]).unwrap();
        assert_eq!(invoke("len", &[arr.clone()]).unwrap().as_i64(), 4);
        // push is variadic, like JS `Array.prototype.push(...items)` — the
        // transpiler emits `push(xs, a, b, c)` for `xs.push(a, b, c)`.
        invoke("push", &[arr.clone(), vi64(5), vi64(6), vi64(7)]).unwrap();
        assert_eq!(invoke("len", &[arr.clone()]).unwrap().as_i64(), 7);
        let sorted = invoke("sort", &[varr(vec![vi64(3), vi64(1), vi64(2)])]).unwrap();
        assert_eq!(sorted.as_array().borrow().data[0].as_i64(), 1);
        let joined = invoke("join", &[varr(vec![vstr("a".into()), vstr("b".into())]), vstr("-".into())]).unwrap();
        assert_eq!(joined.as_string(), "a-b");
        let r = invoke("range", &[vi64(0), vi64(5)]).unwrap();
        assert_eq!(r.as_array().borrow().data.len(), 5);
    }

    #[test]
    fn foundation_strings_and_json() {
        assert_eq!(invoke("upper", &[vstr("abc".into())]).unwrap().as_string(), "ABC");
        let parts = invoke("split", &[vstr("a,b,c".into()), vstr(",".into())]).unwrap();
        assert_eq!(parts.as_array().borrow().data.len(), 3);
        let parsed = invoke("jsonParse", &[vstr(r#"{"x":1,"y":[2,3]}"#.into())]).unwrap();
        assert_eq!(parsed.typ, 8);
        let s = invoke("jsonStringify", &[parsed]).unwrap();
        assert!(s.as_string().contains("\"x\":1"));
    }

    #[test]
    fn oop_inheritance_and_instances() {
        // Build an Animal class with a default and a "kind" method.
        let methods = vobj(-2, {
            let mut m = ValMap::default();
            m.insert("legs".to_string(), {
                use crate::sdk::data::Function;
                Val::new(10, Payload::from(Rc::new(RefCell::new(Function::new(
                    "legs".into(),
                    0,
                    0,
                    vec!["self".into()],
                )))))
            });
            m
        });
        let defaults = vobj(-2, {
            let mut m = ValMap::default();
            m.insert("name".to_string(), vstr("animal".into()));
            m
        });
        let animal = invoke("class", &[vstr("Animal".into()), defaults, methods]).unwrap();
        assert_eq!(object_typ(&animal), CLASS_TYPE);

        // Subclass Dog overrides the default name.
        let dog_defaults = vobj(-2, {
            let mut m = ValMap::default();
            m.insert("name".to_string(), vstr("dog".into()));
            m
        });
        let dog = invoke("extend", &[animal.clone(), vstr("Dog".into()), dog_defaults, vnull()]).unwrap();

        let rex = invoke("new", &[dog.clone()]).unwrap();
        assert_eq!(invoke("field", &[rex.clone(), vstr("name".into())]).unwrap().as_string(), "dog");
        assert!(invoke("isInstance", &[rex.clone(), dog.clone()]).unwrap().as_bool());
        // Inheritance: a Dog is also an Animal.
        assert!(invoke("isInstance", &[rex.clone(), animal.clone()]).unwrap().as_bool());
        // The inherited method resolves to a function value.
        assert_eq!(invoke("method", &[rex.clone(), vstr("legs".into())]).unwrap().typ, 10);
        assert_eq!(invoke("className", &[rex]).unwrap().as_string(), "Dog");
    }

    #[test]
    fn instances_do_not_alias_default_containers() {
        let defaults = vobj(-2, {
            let mut m = ValMap::default();
            m.insert("tags".to_string(), varr(vec![]));
            m
        });
        let c = invoke("class", &[vstr("Box".into()), defaults, vnull()]).unwrap();
        let a = invoke("new", &[c.clone()]).unwrap();
        let b = invoke("new", &[c]).unwrap();
        let a_tags = invoke("field", &[a, vstr("tags".into())]).unwrap();
        invoke("push", &[a_tags, vi64(1)]).unwrap();
        let b_tags = invoke("field", &[b, vstr("tags".into())]).unwrap();
        assert_eq!(b_tags.as_array().borrow().data.len(), 0, "instance b unaffected");
    }

    #[test]
    fn universal_member_ops_have_one_implementation() {
        // A core-type member call and the bare builtin are the *same* universal
        // name reaching the *same* implementation — no separate `Type.method`
        // surface, no proxy. A member call is just `invoke(name, [recv, ..args])`.
        let list = varr(vec![vi64(1), vi64(2), vi64(3)]);
        assert!(invoke("contains", &[list.clone(), vi64(2)]).unwrap().as_bool());
        assert_eq!(invoke("upper", &[vstr("abc".into())]).unwrap().as_string(), "ABC");

        // `reversed` copies (non-mutating), unlike the in-place `reverse`.
        let src = varr(vec![vi64(1), vi64(2), vi64(3)]);
        let rev = invoke("reversed", &[src.clone()]).unwrap();
        assert_eq!(rev.as_array().borrow().data[0].as_i64(), 3);
        assert_eq!(src.as_array().borrow().data[0].as_i64(), 1, "receiver untouched");

        // `extend` appends in place and returns null; `removeAt`/`insert`/`clear`.
        let xs = varr(vec![vi64(1)]);
        invoke("pushAll", &[xs.clone(), varr(vec![vi64(2), vi64(3)])]).unwrap();
        assert_eq!(invoke("len", &[xs.clone()]).unwrap().as_i64(), 3);
        invoke("insert", &[xs.clone(), vi64(0), vi64(9)]).unwrap();
        assert_eq!(xs.as_array().borrow().data[0].as_i64(), 9);
        assert_eq!(invoke("removeAt", &[xs.clone(), vi64(0)]).unwrap().as_i64(), 9);
        invoke("clear", &[xs.clone()]).unwrap();
        assert_eq!(invoke("len", &[xs]).unwrap().as_i64(), 0);

        // `abs` preserves the numeric kind (a double stays a double).
        assert_eq!(invoke("abs", &[vi64(-7)]).unwrap().typ, 3);
        assert_eq!(invoke("abs", &[vf64(-3.0)]).unwrap().typ, 5);
        assert_eq!(invoke("abs", &[vf64(-3.0)]).unwrap().as_f64(), 3.0);

        // num members: `toDouble`, `toString` (Dart-style), `toStringAsFixed`.
        assert_eq!(invoke("toDouble", &[vi64(4)]).unwrap().typ, 5);
        assert_eq!(invoke("toString", &[vf64(3.0)]).unwrap().as_string(), "3.0");
        assert_eq!(invoke("toString", &[vi64(3)]).unwrap().as_string(), "3");
        assert_eq!(invoke("toStringAsFixed", &[vf64(3.14159), vi64(2)]).unwrap().as_string(), "3.14");

        // map members: `remove` returns the removed value; `putIfAbsent`.
        let map = vobj(-2, {
            let mut m = ValMap::default();
            m.insert("k".into(), vi64(9));
            m
        });
        assert_eq!(invoke("remove", &[map.clone(), vstr("k".into())]).unwrap().as_i64(), 9);
        assert_eq!(invoke("has", &[map.clone(), vstr("k".into())]).unwrap().as_bool(), false);
        assert_eq!(invoke("putIfAbsent", &[map, vstr("k".into()), vi64(5)]).unwrap().as_i64(), 5);

        // `join`'s separator is optional (defaults to "").
        assert_eq!(
            invoke("join", &[varr(vec![vi64(1), vi64(2)])]).unwrap().as_string(),
            "12"
        );
    }

    #[test]
    fn byte_codecs_roundtrip() {
        // UTF-8: 'h' = 0x68, 'é' = 0xC3 0xA9.
        let bytes = invoke("utf8Encode", &[vstr("hé".into())]).unwrap();
        let b = bytes.as_array();
        assert_eq!(
            b.borrow().data.iter().map(|v| v.as_i64()).collect::<Vec<_>>(),
            vec![0x68, 0xC3, 0xA9]
        );
        assert_eq!(invoke("utf8Decode", &[bytes]).unwrap().as_string(), "hé");

        // Base64 RFC 4648 vectors, including padding.
        assert_eq!(
            invoke("base64Encode", &[varr(vec![vi64(77), vi64(97), vi64(110)])]).unwrap().as_string(),
            "TWFu"
        );
        assert_eq!(
            invoke("base64Encode", &[varr(vec![vi64(77)])]).unwrap().as_string(),
            "TQ=="
        );
        let dec = invoke("base64Decode", &[vstr("TWFu".into())]).unwrap();
        assert_eq!(
            dec.as_array().borrow().data.iter().map(|v| v.as_i64()).collect::<Vec<_>>(),
            vec![77, 97, 110]
        );
    }

    #[test]
    fn closure_cells_hold_mutable_state() {
        let c = invoke("cell", &[vi64(0)]).unwrap();
        assert_eq!(invoke("cellGet", &[c.clone()]).unwrap().as_i64(), 0);
        invoke("cellSet", &[c.clone(), vi64(42)]).unwrap();
        assert_eq!(invoke("cellGet", &[c]).unwrap().as_i64(), 42);
    }

    #[test]
    fn every_builtin_name_is_invokable_or_errs_cleanly() {
        // No builtin should panic on an empty arg list; it returns Ok or a
        // descriptive Err. (Guards against a name in BUILTINS with no arm.)
        for name in BUILTINS {
            let _ = invoke(name, &[]);
            assert!(is_builtin(name));
        }
    }
}
