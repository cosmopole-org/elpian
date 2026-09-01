//! `dart:core` and `dart:math` native helpers.
//!
//! A handful of `dart:core`/`dart:math` members are native (not Dart source):
//! `DateTime.now`, `Random`, and a few numeric/string formatters that bottom out
//! in runtime intrinsics. They are gated by the `Environment` capability.
//!
//! Both sources of nondeterminism — the clock and the PRNG — are made injectable
//! so runs are reproducible and unit-testable: the clock can be pinned, and
//! `Random` is a seeded xorshift so a given seed yields a fixed sequence
//! (matching Dart's "seeded `Random` is deterministic" guarantee).

use std::collections::HashMap;

use serde_json::{json, Value};

/// A monotonically-usable clock. Pinned in tests, wall-clock in production.
#[derive(Debug, Clone)]
pub enum Clock {
    /// Milliseconds since the Unix epoch, fixed.
    Fixed(i64),
    /// Real wall clock.
    System,
}

impl Clock {
    fn now_millis(&self) -> i64 {
        match self {
            Clock::Fixed(ms) => *ms,
            Clock::System => {
                use std::time::{SystemTime, UNIX_EPOCH};
                SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .map(|d| d.as_millis() as i64)
                    .unwrap_or(0)
            }
        }
    }
}

/// A seeded xorshift64* PRNG — small, fast, deterministic for a given seed.
#[derive(Debug, Clone)]
struct Prng {
    state: u64,
}

impl Prng {
    fn new(seed: u64) -> Self {
        // Avoid the zero fixed-point.
        Prng {
            state: if seed == 0 { 0x9E3779B97F4A7C15 } else { seed },
        }
    }

    fn next_u64(&mut self) -> u64 {
        let mut x = self.state;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.state = x;
        x.wrapping_mul(0x2545F4914F6CDD1D)
    }

    /// `Random.nextInt(max)` — uniform in `[0, max)`.
    fn next_int(&mut self, max: i64) -> i64 {
        if max <= 0 {
            return 0;
        }
        (self.next_u64() % max as u64) as i64
    }

    /// `Random.nextDouble()` — uniform in `[0, 1)`.
    fn next_double(&mut self) -> f64 {
        // 53 bits of mantissa for a uniform double.
        (self.next_u64() >> 11) as f64 / (1u64 << 53) as f64
    }
}

/// Native `dart:core`/`dart:math` runtime state.
#[derive(Debug)]
pub struct CoreRuntime {
    clock: Clock,
    rngs: HashMap<u32, Prng>,
    next_rng: u32,
}

pub type OpResult = Result<Value, String>;

impl CoreRuntime {
    pub fn new(clock: Clock) -> Self {
        CoreRuntime {
            clock,
            rngs: HashMap::new(),
            next_rng: 0,
        }
    }

    /// Dispatch a `dart:core/...` or `dart:math/...` method (the `library`
    /// segment selects which; `method` is the remainder).
    pub fn dispatch(&mut self, library: &str, method: &str, args: &[Value]) -> OpResult {
        match (library, method) {
            ("core", "DateTime.now") => Ok(json!(self.clock.now_millis())),

            ("core", "int.parse") => {
                let s = as_str(args, 0)?;
                s.trim()
                    .parse::<i64>()
                    .map(|i| json!(i))
                    .map_err(|_| format!("FormatException: {s}"))
            }
            ("core", "double.parse") => {
                let s = as_str(args, 0)?;
                s.trim()
                    .parse::<f64>()
                    .map(|f| json!(f))
                    .map_err(|_| format!("FormatException: {s}"))
            }
            ("core", "double.toStringAsFixed") => {
                let v = as_f64(args, 0)?;
                let digits = as_usize(args, 1)?;
                Ok(json!(format!("{v:.*}", digits)))
            }
            ("core", "num.toRadixString") => {
                let v = as_i64(args, 0)?;
                let radix = as_i64(args, 1)?;
                Ok(json!(to_radix(v, radix)))
            }

            // ---- String methods (receiver is arg 0) ----
            ("core", "String.length") => Ok(json!(as_str(args, 0)?.chars().count())),
            ("core", "String.toUpperCase") => Ok(json!(as_str(args, 0)?.to_uppercase())),
            ("core", "String.toLowerCase") => Ok(json!(as_str(args, 0)?.to_lowercase())),
            ("core", "String.trim") => Ok(json!(as_str(args, 0)?.trim())),
            ("core", "String.contains") => {
                Ok(json!(as_str(args, 0)?.contains(&as_str(args, 1)?)))
            }
            ("core", "String.indexOf") => {
                let s = as_str(args, 0)?;
                let needle = as_str(args, 1)?;
                Ok(json!(s.find(&needle).map(|b| s[..b].chars().count() as i64).unwrap_or(-1)))
            }
            ("core", "String.substring") => {
                let s = as_str(args, 0)?;
                let chars: Vec<char> = s.chars().collect();
                let start = as_usize(args, 1)?;
                let end = args.get(2).and_then(|v| v.as_u64()).map(|v| v as usize).unwrap_or(chars.len());
                if start > end || end > chars.len() {
                    return Err(format!("RangeError: substring({start}, {end}) of length {}", chars.len()));
                }
                Ok(json!(chars[start..end].iter().collect::<String>()))
            }
            ("core", "String.replaceAll") => {
                let s = as_str(args, 0)?;
                Ok(json!(s.replace(&as_str(args, 1)?, &as_str(args, 2)?)))
            }
            ("core", "String.split") => {
                let s = as_str(args, 0)?;
                let sep = as_str(args, 1)?;
                Ok(json!(s.split(&sep).map(|p| p.to_string()).collect::<Vec<_>>()))
            }
            ("core", "String.padLeft") => {
                let s = as_str(args, 0)?;
                let width = as_usize(args, 1)?;
                let pad = args.get(2).and_then(|v| v.as_str()).unwrap_or(" ").chars().next().unwrap_or(' ');
                let deficit = width.saturating_sub(s.chars().count());
                Ok(json!(format!("{}{}", pad.to_string().repeat(deficit), s)))
            }

            ("math", "Random") => {
                // args: [seed?]  -> returns an opaque Random handle.
                let seed = args
                    .first()
                    .and_then(|v| v.as_i64())
                    .map(|s| s as u64)
                    .unwrap_or_else(|| self.clock.now_millis() as u64);
                let id = self.next_rng;
                self.next_rng += 1;
                self.rngs.insert(id, Prng::new(seed));
                Ok(json!(id))
            }
            ("math", "Random.nextInt") => {
                let id = as_u32(args, 0)?;
                let max = as_i64(args, 1)?;
                let rng = self.rng(id)?;
                Ok(json!(rng.next_int(max)))
            }
            ("math", "Random.nextDouble") => {
                let id = as_u32(args, 0)?;
                let rng = self.rng(id)?;
                Ok(json!(rng.next_double()))
            }
            ("math", "sqrt") => Ok(json!(as_f64(args, 0)?.sqrt())),
            ("math", "sin") => Ok(json!(as_f64(args, 0)?.sin())),
            ("math", "cos") => Ok(json!(as_f64(args, 0)?.cos())),
            ("math", "pow") => Ok(json!(as_f64(args, 0)?.powf(as_f64(args, 1)?))),

            (lib, m) => Err(format!("NoSuchMethodError: dart:{lib}/{m}")),
        }
    }

    fn rng(&mut self, id: u32) -> Result<&mut Prng, String> {
        self.rngs
            .get_mut(&id)
            .ok_or_else(|| format!("StateError: no Random for handle {id}"))
    }
}

fn to_radix(mut v: i64, radix: i64) -> String {
    if !(2..=36).contains(&radix) {
        return v.to_string();
    }
    if v == 0 {
        return "0".into();
    }
    let neg = v < 0;
    let mut out = Vec::new();
    let digits = b"0123456789abcdefghijklmnopqrstuvwxyz";
    let mut n = v.unsigned_abs();
    let r = radix as u64;
    while n > 0 {
        out.push(digits[(n % r) as usize]);
        n /= r;
    }
    if neg {
        out.push(b'-');
    }
    out.reverse();
    v = 0;
    let _ = v;
    String::from_utf8(out).unwrap()
}

fn get<'a>(args: &'a [Value], i: usize) -> Result<&'a Value, String> {
    args.get(i).ok_or_else(|| format!("missing argument {i}"))
}
fn as_str(args: &[Value], i: usize) -> Result<String, String> {
    get(args, i)?
        .as_str()
        .map(|s| s.to_string())
        .ok_or_else(|| format!("argument {i} is not a string"))
}
fn as_f64(args: &[Value], i: usize) -> Result<f64, String> {
    get(args, i)?
        .as_f64()
        .ok_or_else(|| format!("argument {i} is not a number"))
}
fn as_i64(args: &[Value], i: usize) -> Result<i64, String> {
    get(args, i)?
        .as_i64()
        .ok_or_else(|| format!("argument {i} is not an integer"))
}
fn as_usize(args: &[Value], i: usize) -> Result<usize, String> {
    get(args, i)?
        .as_u64()
        .map(|v| v as usize)
        .ok_or_else(|| format!("argument {i} is not a non-negative integer"))
}
fn as_u32(args: &[Value], i: usize) -> Result<u32, String> {
    get(args, i)?
        .as_u64()
        .map(|v| v as u32)
        .ok_or_else(|| format!("argument {i} is not a handle"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pinned_clock_is_deterministic() {
        let mut c = CoreRuntime::new(Clock::Fixed(1_700_000_000_000));
        let now = c.dispatch("core", "DateTime.now", &[]).unwrap();
        assert_eq!(now, json!(1_700_000_000_000i64));
    }

    #[test]
    fn seeded_random_is_reproducible() {
        let mut a = CoreRuntime::new(Clock::Fixed(0));
        let mut b = CoreRuntime::new(Clock::Fixed(0));
        let ha = a.dispatch("math", "Random", &[json!(42)]).unwrap();
        let hb = b.dispatch("math", "Random", &[json!(42)]).unwrap();
        let ha = ha.as_u64().unwrap() as i64;
        let hb = hb.as_u64().unwrap() as i64;
        for _ in 0..8 {
            let va = a.dispatch("math", "Random.nextInt", &[json!(ha), json!(1000)]).unwrap();
            let vb = b.dispatch("math", "Random.nextInt", &[json!(hb), json!(1000)]).unwrap();
            assert_eq!(va, vb);
            assert!(va.as_i64().unwrap() >= 0 && va.as_i64().unwrap() < 1000);
        }
    }

    #[test]
    fn string_methods() {
        let mut c = CoreRuntime::new(Clock::Fixed(0));
        assert_eq!(c.dispatch("core", "String.toUpperCase", &[json!("abc")]).unwrap(), json!("ABC"));
        assert_eq!(c.dispatch("core", "String.substring", &[json!("hello"), json!(1), json!(4)]).unwrap(), json!("ell"));
        assert_eq!(c.dispatch("core", "String.indexOf", &[json!("hello"), json!("l")]).unwrap(), json!(2));
        assert_eq!(c.dispatch("core", "String.split", &[json!("a,b,c"), json!(",")]).unwrap(), json!(["a","b","c"]));
        assert_eq!(c.dispatch("core", "String.replaceAll", &[json!("aaa"), json!("a"), json!("b")]).unwrap(), json!("bbb"));
        assert_eq!(c.dispatch("core", "String.padLeft", &[json!("7"), json!(3), json!("0")]).unwrap(), json!("007"));
    }

    #[test]
    fn number_formatting_matches_dart() {
        let mut c = CoreRuntime::new(Clock::Fixed(0));
        assert_eq!(
            c.dispatch("core", "double.toStringAsFixed", &[json!(3.14159), json!(2)]).unwrap(),
            json!("3.14")
        );
        assert_eq!(
            c.dispatch("core", "num.toRadixString", &[json!(255), json!(16)]).unwrap(),
            json!("ff")
        );
        assert_eq!(
            c.dispatch("core", "int.parse", &[json!("  42 ")]).unwrap(),
            json!(42)
        );
    }
}
