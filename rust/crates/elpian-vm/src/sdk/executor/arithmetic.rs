//! Arithmetic and comparison semantics.
//!
//! Split out of the interpreter so `mod.rs` carries the run loop rather than
//! 1,500 lines of operator behaviour. These are inherent methods on
//! [`Executor`]; Rust allows a type's inherent impls to be spread across
//! modules of the defining crate, so nothing about the call sites changes.
//!
//! The numeric coercion matrix is written once, in [`Executor::numeric_binop`].
//! `operate_sum`, `operate_subtract` and `operate_multiply` each used to carry
//! their own copy of the same nested match over the five numeric tags.

use super::operations::is_null;
use super::Executor;
use crate::sdk::data::{ty, Array, Object, Payload, Val, ValGroup};
use std::cell::RefCell;
use std::rc::Rc;

/// A numeric binary operation.
///
/// Named so the integer/float coercion matrix below can be written once rather
/// than once per operator. `operate_sum`, `operate_subtract` and
/// `operate_multiply` each carried their own copy of the same nested match over
/// the five numeric type tags — about 600 lines of identical structure that
/// differed only in the operator and the error wording, and that could drift
/// apart silently because nothing tied them together.
#[derive(Clone, Copy, PartialEq, Eq)]
enum ArithOp {
    Add,
    Sub,
    Mul,
}

impl ArithOp {
    fn apply_i64(self, a: i64, b: i64) -> i64 {
        match self {
            ArithOp::Add => a.wrapping_add(b),
            ArithOp::Sub => a.wrapping_sub(b),
            ArithOp::Mul => a.wrapping_mul(b),
        }
    }

    fn apply_f64(self, a: f64, b: f64) -> f64 {
        match self {
            ArithOp::Add => a + b,
            ArithOp::Sub => a - b,
            ArithOp::Mul => a * b,
        }
    }
}

/// Read a numeric value as i64. Only meaningful when `ty::is_numeric(v.typ)`.
fn numeric_as_i64(v: &Val) -> i64 {
    match v.typ {
        ty::I16 => v.as_i16() as i64,
        ty::I32 => v.as_i32() as i64,
        ty::I64 => v.as_i64(),
        ty::F32 => v.as_f32() as i64,
        ty::F64 => v.as_f64() as i64,
        _ => 0,
    }
}

/// Read a numeric value as f64. Only meaningful when `ty::is_numeric(v.typ)`.
fn numeric_as_f64(v: &Val) -> f64 {
    match v.typ {
        ty::I16 => v.as_i16() as f64,
        ty::I32 => v.as_i32() as f64,
        ty::I64 => v.as_i64() as f64,
        ty::F32 => v.as_f32() as f64,
        ty::F64 => v.as_f64(),
        _ => 0.0,
    }
}

impl Executor {
    /// Apply `op` to two operands when **both** are numeric.
    ///
    /// Integer inputs stay integral; any float on either side promotes the
    /// whole operation to f64, which is what the three hand-written matrices
    /// did. Returns `None` when either side is non-numeric, leaving the caller
    /// to handle its own special cases (string concatenation for `+`, string
    /// and array repetition for `*`, errors for `-`).
    fn numeric_binop(&self, arg1: &Val, arg2: &Val, op: ArithOp) -> Option<Val> {
        if !ty::is_numeric(arg1.typ) || !ty::is_numeric(arg2.typ) {
            return None;
        }
        let both_integral = ty::is_integral(arg1.typ) && ty::is_integral(arg2.typ);
        Some(if both_integral {
            self.check_int_range(op.apply_i64(numeric_as_i64(arg1), numeric_as_i64(arg2)))
        } else {
            self.check_float_range(op.apply_f64(numeric_as_f64(arg1), numeric_as_f64(arg2)))
        })
    }

    fn check_float_range(&self, num: f64) -> Val {
        if num < f32::MAX.into() {
            Val {
                typ: ty::F32,
                data: Payload::from(num as f32),
            }
        } else {
            Val {
                typ: ty::F64,
                data: Payload::from(num),
            }
        }
    }
    fn check_int_range(&self, num: i64) -> Val {
        if num < i16::MAX.into() {
            Val {
                typ: ty::I16,
                data: Payload::from(num as i16),
            }
        } else if num < i32::MAX.into() {
            Val {
                typ: ty::I32,
                data: Payload::from(num as i32),
            }
        } else {
            Val {
                typ: ty::I64,
                data: Payload::from(num),
            }
        }
    }
    /// `a + b`.
    ///
    /// Three meanings, in order: the shared numeric matrix, string
    /// concatenation whenever either side is a string, and array prepend/append
    /// when exactly one side is an array. Everything else is a guest error.
    pub(super) fn operate_sum(&self, arg1: Val, arg2: Val) -> Val {
        // Before first-class null landed the front-ends compiled absent values
        // to integer 0, and guest code (JS `x + null` is defined) relies on a
        // sum with null not tearing the VM down.
        // null is the additive identity on the numeric path, including
        // `null + null`, which must be 0 rather than a trap.
        if (arg1.typ == ty::NULL || ty::is_numeric(arg1.typ))
            && (arg2.typ == ty::NULL || ty::is_numeric(arg2.typ))
        {
            let zero = Val::new(ty::I64, Payload::from(0i64));
            let a = if arg1.typ == ty::NULL { &zero } else { &arg1 };
            let b = if arg2.typ == ty::NULL { &zero } else { &arg2 };
            return self
                .numeric_binop(a, b, ArithOp::Add)
                .expect("both operands are numeric after the null substitution");
        }

        if let Some(v) = self.numeric_binop(&arg1, &arg2, ArithOp::Add) {
            return v;
        }

        // Concatenation. Functions are deliberately excluded: appending a
        // function's name to a string is far more likely a bug than an intent.
        if arg1.typ == ty::STRING || arg2.typ == ty::STRING {
            if arg1.typ == ty::FUNCTION || arg2.typ == ty::FUNCTION {
                panic!("elpian error: function and string can not be summed");
            }
            return Val::new(
                7,
                Payload::from(format!("{}{}", arg1.to_display(), arg2.to_display())),
            );
        }

        // Array prepend / append: `x + [..]` and `[..] + x`. Two arrays
        // concatenate.
        if arg1.typ == ty::ARRAY || arg2.typ == ty::ARRAY {
            let mut out: Vec<Val> = Vec::new();
            let mut push = |v: &Val| {
                if v.typ == ty::ARRAY {
                    out.extend(v.as_array().borrow().data.iter().cloned());
                } else {
                    out.push(v.clone());
                }
            };
            push(&arg1);
            push(&arg2);
            return Val::new(
                ty::ARRAY,
                Payload::from(Rc::new(RefCell::new(Array::new(out)))),
            );
        }

        panic!(
            "elpian error: {} and {} can not be summed",
            ty::name(arg1.typ),
            ty::name(arg2.typ)
        );
    }

    /// `a * b`.
    ///
    /// Numeric multiplication comes from the shared matrix; the branches below
    /// carry the meanings unique to `*` — string and array repetition by an
    /// integer count, boolean masking, and string concatenation with a float.
    pub(super) fn operate_multiply(&self, arg1: Val, arg2: Val) -> Val {
        if let Some(v) = self.numeric_binop(&arg1, &arg2, ArithOp::Mul) {
            return v;
        }
        match arg1.typ {
            ty::I16..=ty::I64 => {
                let val1 = match arg1.typ {
                    ty::I16 => arg1.as_i16() as i64,
                    ty::I32 => arg1.as_i32() as i64,
                    ty::I64 => arg1.as_i64(),
                    _ => 0,
                };
                match arg2.typ {
                    ty::BOOL => {
                        panic!("elpian error: boolean and integer can not be multiplied");
                    }
                    ty::STRING => {
                        let val2 = arg2.as_string();
                        let mut res = "".to_string();
                        for _i in 0..val1 {
                            res.push_str(&val2);
                        }
                        Val {
                            typ: ty::STRING,
                            data: Payload::from(res),
                        }
                    }
                    ty::OBJECT => {
                        panic!("elpian error: object and integer can not be multiplied");
                    }
                    ty::ARRAY => {
                        let val2 = arg2.as_array();
                        let mut res: Vec<Val> = vec![];
                        for _i in 0..val1 {
                            res.append(&mut val2.borrow().data.clone());
                        }
                        Val {
                            typ: ty::ARRAY,
                            data: Payload::from(Rc::new(RefCell::new(Array::new(res)))),
                        }
                    }
                    ty::FUNCTION => {
                        panic!("elpian error: function and integer can not be multiplied");
                    }
                    _ => {
                        panic!("elpian error: unknown data type and integer can not be multiplied");
                    }
                }
            }
            ty::F32 | ty::F64 => {
                let val1 = match arg1.typ {
                    ty::F32 => arg1.as_f32() as f64,
                    ty::F64 => arg1.as_f64(),
                    _ => 0.0,
                };
                match arg2.typ {
                    ty::BOOL => {
                        panic!("elpian error: boolean and float can not be multiplied");
                    }
                    ty::STRING => {
                        let val2 = arg2.as_string();
                        let val1_temp = val1.to_string();
                        Val {
                            typ: ty::STRING,
                            data: Payload::from(format!("{}{}", val1_temp, val2)),
                        }
                    }
                    ty::OBJECT => {
                        panic!("elpian error: object and float can not be multiplied");
                    }
                    ty::ARRAY => {
                        panic!("elpian error: array and float can not be multiplied");
                    }
                    ty::FUNCTION => {
                        panic!("elpian error: function and float can not be multiplied");
                    }
                    _ => {
                        panic!("elpian error: unknown data type and float can not be multiplied");
                    }
                }
            }
            ty::BOOL => {
                let val1 = arg1.as_bool();
                match arg2.typ {
                    ty::I16 => {
                        panic!("elpian error: bool and integer can not be multiplied");
                    }
                    ty::I32 => {
                        panic!("elpian error: bool and integer can not be multiplied");
                    }
                    ty::I64 => {
                        panic!("elpian error: bool and integer can not be multiplied");
                    }
                    ty::F32 => {
                        panic!("elpian error: bool and float can not be multiplied");
                    }
                    ty::F64 => {
                        panic!("elpian error: bool and float can not be multiplied");
                    }
                    ty::BOOL => {
                        // Logical AND, consistent with how `*` treats a
                        // boolean everywhere else in this function: as a mask.
                        // This was tagged `typ: 7` (string) while storing a
                        // `Payload::Bool`, so the result claimed to be a string
                        // and panicked inside `as_string` as soon as anything
                        // printed or stringified it.
                        let val2 = arg2.as_bool();
                        Val {
                            typ: ty::BOOL,
                            data: Payload::from(val1 & val2),
                        }
                    }
                    ty::STRING => {
                        let val2 = arg2.as_string();
                        let val1_temp = val1.to_string();
                        Val {
                            typ: ty::STRING,
                            data: Payload::from(format!("{}{}", val1_temp, val2)),
                        }
                    }
                    ty::OBJECT => {
                        if val1 {
                            arg2.clone()
                        } else {
                            Val {
                                typ: ty::OBJECT,
                                data: Payload::from(Rc::new(RefCell::new(Object::new(
                                    -2,
                                    ValGroup::new_empty(),
                                )))),
                            }
                        }
                    }
                    ty::ARRAY => {
                        if val1 {
                            arg2.clone()
                        } else {
                            Val {
                                typ: ty::ARRAY,
                                data: Payload::from(Rc::new(RefCell::new(Array::new_empty()))),
                            }
                        }
                    }
                    ty::FUNCTION => {
                        panic!("elpian error: function and bool can not be multiplied");
                    }
                    _ => {
                        panic!("elpian error: unknown data type and bool can not be multiplied");
                    }
                }
            }
            ty::STRING => {
                let val1 = arg1.as_string();
                match arg2.typ {
                    ty::I16 => {
                        let mut res = "".to_string();
                        for _i in 0..arg2.as_i16() {
                            res.push_str(&val1);
                        }
                        Val {
                            typ: ty::STRING,
                            data: Payload::from(res),
                        }
                    }
                    ty::I32 => {
                        let mut res = "".to_string();
                        for _i in 0..arg2.as_i32() {
                            res.push_str(&val1);
                        }
                        Val {
                            typ: ty::STRING,
                            data: Payload::from(res),
                        }
                    }
                    ty::I64 => {
                        let mut res = "".to_string();
                        for _i in 0..arg2.as_i64() {
                            res.push_str(&val1);
                        }
                        Val {
                            typ: ty::STRING,
                            data: Payload::from(res),
                        }
                    }
                    ty::F32 => {
                        panic!("elpian error: string and float can not be multiplied");
                    }
                    ty::F64 => {
                        panic!("elpian error: string and float can not be multiplied");
                    }
                    ty::BOOL => {
                        panic!("elpian error: string and bool can not be multiplied");
                    }
                    ty::STRING => {
                        panic!("elpian error: string and string can not be multiplied");
                    }
                    ty::OBJECT => {
                        panic!("elpian error: string and object can not be multiplied");
                    }
                    ty::ARRAY => {
                        panic!("elpian error: string and array can not be multiplied");
                    }
                    ty::FUNCTION => {
                        panic!("elpian error: string and function can not be multiplied");
                    }
                    _ => {
                        panic!("elpian error: string type and unknown data can not be multiplied");
                    }
                }
            }
            ty::OBJECT => {
                panic!("elpian error: object can not be multiplied with other types");
            }
            ty::ARRAY => {
                let val1 = arg1.as_array();
                match arg2.typ {
                    ty::I16 => {
                        let mut res: Vec<Val> = vec![];
                        for _i in 0..arg2.as_i16() {
                            res.append(&mut val1.borrow().data.clone());
                        }
                        Val {
                            typ: ty::ARRAY,
                            data: Payload::from(Rc::new(RefCell::new(Array::new(res)))),
                        }
                    }
                    ty::I32 => {
                        let mut res: Vec<Val> = vec![];
                        for _i in 0..arg2.as_i32() {
                            res.append(&mut val1.borrow().data.clone());
                        }
                        Val {
                            typ: ty::ARRAY,
                            data: Payload::from(Rc::new(RefCell::new(Array::new(res)))),
                        }
                    }
                    ty::I64 => {
                        let mut res: Vec<Val> = vec![];
                        for _i in 0..arg2.as_i64() {
                            res.append(&mut val1.borrow().data.clone());
                        }
                        Val {
                            typ: ty::ARRAY,
                            data: Payload::from(Rc::new(RefCell::new(Array::new(res)))),
                        }
                    }
                    ty::F32 | ty::F64 => {
                        panic!("elpian error: array and float can not be multiplied");
                    }
                    ty::BOOL => {
                        if arg2.as_bool() {
                            arg1.clone()
                        } else {
                            Val {
                                typ: ty::ARRAY,
                                data: Payload::from(Rc::new(RefCell::new(Array::new_empty()))),
                            }
                        }
                    }
                    ty::STRING => {
                        panic!("elpian error: array and string can not be multiplied");
                    }
                    ty::OBJECT => {
                        panic!("elpian error: array and object can not be multiplied");
                    }
                    ty::FUNCTION => {
                        panic!("elpian error: array and function can not be multiplied");
                    }
                    _ => {
                        panic!("elpian error: unknown data type and array can not be multiplied");
                    }
                }
            }
            ty::FUNCTION => {
                panic!("elpian error: function can not be multiplied with other types");
            }
            _ => {
                panic!("elpian error: unknown type can not be multiplied with other types");
            }
        }
    }
    /// `a - b`.
    ///
    /// Subtraction has no non-numeric meaning in Elpian — unlike `+`, which
    /// concatenates strings, and `*`, which repeats them — so every case is
    /// either the shared numeric matrix or an error.
    pub(super) fn operate_subtract(&self, arg1: Val, arg2: Val) -> Val {
        if let Some(v) = self.numeric_binop(&arg1, &arg2, ArithOp::Sub) {
            return v;
        }
        panic!(
            "elpian error: {} and {} can not be subtracted",
            ty::name(arg1.typ),
            ty::name(arg2.typ)
        );
    }

    pub(super) fn operate_division(&self, arg1: Val, arg2: Val) -> Val {
        match arg1.typ {
            ty::I16..=ty::I64 => {
                let val1 = match arg1.typ {
                    ty::I16 => arg1.as_i16() as f64,
                    ty::I32 => arg1.as_i32() as f64,
                    ty::I64 => arg1.as_i64() as f64,
                    _ => 0.0,
                };
                match arg2.typ {
                    ty::I16 => {
                        let val2 = arg2.as_i16() as f64;
                        self.check_float_range(val1 / val2)
                    }
                    ty::I32 => {
                        let val2 = arg2.as_i32() as f64;
                        self.check_float_range(val1 / val2)
                    }
                    ty::I64 => {
                        let val2 = arg2.as_i64() as f64;
                        self.check_float_range(val1 / val2)
                    }
                    ty::F32 => {
                        let val2 = arg2.as_f32() as f64;
                        self.check_float_range(val1 / val2)
                    }
                    ty::F64 => {
                        let val2 = arg2.as_f64();
                        self.check_float_range(val1 / val2)
                    }
                    ty::BOOL => {
                        panic!("elpian error: integer and boolean can not be divisioned");
                    }
                    ty::STRING => {
                        panic!("elpian error: integer and boolean can not be divisioned");
                    }
                    ty::OBJECT => {
                        panic!("elpian error: integer and object can not be divisioned");
                    }
                    ty::ARRAY => {
                        panic!("elpian error: integer and array can not be divisioned");
                    }
                    ty::FUNCTION => {
                        panic!("elpian error: integer and function can not be divisioned");
                    }
                    _ => {
                        panic!("elpian error: integer and unknown data type can not be divisioned");
                    }
                }
            }
            ty::F32 | ty::F64 => {
                let val1 = match arg1.typ {
                    ty::F32 => arg1.as_f32() as f64,
                    ty::F64 => arg1.as_f64(),
                    _ => 0.0,
                };
                match arg2.typ {
                    ty::I16 => {
                        let val2 = arg2.as_i16() as f64;
                        self.check_float_range(val1 / val2)
                    }
                    ty::I32 => {
                        let val2 = arg2.as_i32() as f64;
                        self.check_float_range(val1 / val2)
                    }
                    ty::I64 => {
                        let val2 = arg2.as_i64() as f64;
                        self.check_float_range(val1 / val2)
                    }
                    ty::F32 => {
                        let val2 = arg2.as_f32() as f64;
                        self.check_float_range(val1 / val2)
                    }
                    ty::F64 => {
                        let val2 = arg2.as_f64();
                        self.check_float_range(val1 / val2)
                    }
                    ty::BOOL => {
                        panic!("elpian error: float and boolean can not be divisioned");
                    }
                    ty::STRING => {
                        panic!("elpian error: float and string can not be divisioned");
                    }
                    ty::OBJECT => {
                        panic!("elpian error: float and object can not be divisioned");
                    }
                    ty::ARRAY => {
                        panic!("elpian error: float and array can not be divisioned");
                    }
                    ty::FUNCTION => {
                        panic!("elpian error: float and function can not be divisioned");
                    }
                    _ => {
                        panic!("elpian error: float and unknown data type can not be divisioned");
                    }
                }
            }
            ty::BOOL => {
                panic!("elpian error: bool can not be divisioned with other types");
            }
            ty::STRING => {
                panic!("elpian error: bool can not be divisioned with other types");
            }
            ty::OBJECT => {
                panic!("elpian error: object can not be divisioned with other types");
            }
            ty::ARRAY => {
                panic!("elpian error: array can not be divisioned with other types");
            }
            ty::FUNCTION => {
                panic!("elpian error: function can not be divisioned with other types");
            }
            _ => {
                panic!("elpian error: unknown type can not be divisioned with other types");
            }
        }
    }
    pub(super) fn operate_modulo(&self, arg1: Val, arg2: Val) -> Val {
        match arg1.typ {
            // Integer dividend: keep an integer remainder for integer divisors,
            // promote to float when the divisor is a float (matching the rest of
            // the arithmetic ops, e.g. `operate_subtract`).
            ty::I16..=ty::I64 => {
                let val1 = match arg1.typ {
                    ty::I16 => arg1.as_i16() as i64,
                    ty::I32 => arg1.as_i32() as i64,
                    ty::I64 => arg1.as_i64(),
                    _ => 0,
                };
                match arg2.typ {
                    ty::I16 => self.check_int_range(val1 % arg2.as_i16() as i64),
                    ty::I32 => self.check_int_range(val1 % arg2.as_i32() as i64),
                    ty::I64 => self.check_int_range(val1 % arg2.as_i64()),
                    ty::F32 => self.check_float_range(val1 as f64 % arg2.as_f32() as f64),
                    ty::F64 => self.check_float_range(val1 as f64 % arg2.as_f64()),
                    ty::BOOL => panic!("elpian error: integer and boolean can not be modulo'd"),
                    ty::STRING => panic!("elpian error: integer and string can not be modulo'd"),
                    ty::OBJECT => panic!("elpian error: integer and object can not be modulo'd"),
                    ty::ARRAY => panic!("elpian error: integer and array can not be modulo'd"),
                    ty::FUNCTION => {
                        panic!("elpian error: integer and function can not be modulo'd")
                    }
                    _ => panic!("elpian error: integer and unknown data type can not be modulo'd"),
                }
            }
            ty::F32 | ty::F64 => {
                let val1 = match arg1.typ {
                    ty::F32 => arg1.as_f32() as f64,
                    ty::F64 => arg1.as_f64(),
                    _ => 0.0,
                };
                match arg2.typ {
                    ty::I16 => self.check_float_range(val1 % arg2.as_i16() as f64),
                    ty::I32 => self.check_float_range(val1 % arg2.as_i32() as f64),
                    ty::I64 => self.check_float_range(val1 % arg2.as_i64() as f64),
                    ty::F32 => self.check_float_range(val1 % arg2.as_f32() as f64),
                    ty::F64 => self.check_float_range(val1 % arg2.as_f64()),
                    ty::BOOL => panic!("elpian error: float and boolean can not be modulo'd"),
                    ty::STRING => panic!("elpian error: float and string can not be modulo'd"),
                    ty::OBJECT => panic!("elpian error: float and object can not be modulo'd"),
                    ty::ARRAY => panic!("elpian error: float and array can not be modulo'd"),
                    ty::FUNCTION => panic!("elpian error: float and function can not be modulo'd"),
                    _ => panic!("elpian error: float and unknown data type can not be modulo'd"),
                }
            }
            ty::BOOL => panic!("elpian error: bool can not be modulo'd with other types"),
            ty::STRING => panic!("elpian error: string can not be modulo'd with other types"),
            ty::OBJECT => panic!("elpian error: object can not be modulo'd with other types"),
            ty::ARRAY => panic!("elpian error: array can not be modulo'd with other types"),
            ty::FUNCTION => panic!("elpian error: function can not be modulo'd with other types"),
            _ => panic!("elpian error: unknown type can not be modulo'd with other types"),
        }
    }
    pub(super) fn operate_power(&self, arg1: Val, arg2: Val) -> Val {
        match arg1.typ {
            // Integer base raised to a non-negative integer exponent stays an
            // integer (falling back to float on overflow); any float operand or
            // negative exponent yields a float, like the other arithmetic ops.
            ty::I16..=ty::I64 => {
                let val1 = match arg1.typ {
                    ty::I16 => arg1.as_i16() as i64,
                    ty::I32 => arg1.as_i32() as i64,
                    ty::I64 => arg1.as_i64(),
                    _ => 0,
                };
                let int_pow = |exp: i64| -> Val {
                    if (0..=u32::MAX as i64).contains(&exp) {
                        match val1.checked_pow(exp as u32) {
                            Some(r) => self.check_int_range(r),
                            None => self.check_float_range((val1 as f64).powf(exp as f64)),
                        }
                    } else {
                        self.check_float_range((val1 as f64).powf(exp as f64))
                    }
                };
                match arg2.typ {
                    ty::I16 => int_pow(arg2.as_i16() as i64),
                    ty::I32 => int_pow(arg2.as_i32() as i64),
                    ty::I64 => int_pow(arg2.as_i64()),
                    ty::F32 => self.check_float_range((val1 as f64).powf(arg2.as_f32() as f64)),
                    ty::F64 => self.check_float_range((val1 as f64).powf(arg2.as_f64())),
                    ty::BOOL => {
                        panic!("elpian error: integer and boolean can not be exponentiated")
                    }
                    ty::STRING => {
                        panic!("elpian error: integer and string can not be exponentiated")
                    }
                    ty::OBJECT => {
                        panic!("elpian error: integer and object can not be exponentiated")
                    }
                    ty::ARRAY => panic!("elpian error: integer and array can not be exponentiated"),
                    ty::FUNCTION => {
                        panic!("elpian error: integer and function can not be exponentiated")
                    }
                    _ => panic!(
                        "elpian error: integer and unknown data type can not be exponentiated"
                    ),
                }
            }
            ty::F32 | ty::F64 => {
                let val1 = match arg1.typ {
                    ty::F32 => arg1.as_f32() as f64,
                    ty::F64 => arg1.as_f64(),
                    _ => 0.0,
                };
                match arg2.typ {
                    ty::I16 => self.check_float_range(val1.powf(arg2.as_i16() as f64)),
                    ty::I32 => self.check_float_range(val1.powf(arg2.as_i32() as f64)),
                    ty::I64 => self.check_float_range(val1.powf(arg2.as_i64() as f64)),
                    ty::F32 => self.check_float_range(val1.powf(arg2.as_f32() as f64)),
                    ty::F64 => self.check_float_range(val1.powf(arg2.as_f64())),
                    ty::BOOL => panic!("elpian error: float and boolean can not be exponentiated"),
                    ty::STRING => panic!("elpian error: float and string can not be exponentiated"),
                    ty::OBJECT => panic!("elpian error: float and object can not be exponentiated"),
                    ty::ARRAY => panic!("elpian error: float and array can not be exponentiated"),
                    ty::FUNCTION => {
                        panic!("elpian error: float and function can not be exponentiated")
                    }
                    _ => {
                        panic!("elpian error: float and unknown data type can not be exponentiated")
                    }
                }
            }
            ty::BOOL => panic!("elpian error: bool can not be exponentiated with other types"),
            ty::STRING => panic!("elpian error: string can not be exponentiated with other types"),
            ty::OBJECT => panic!("elpian error: object can not be exponentiated with other types"),
            ty::ARRAY => panic!("elpian error: array can not be exponentiated with other types"),
            ty::FUNCTION => {
                panic!("elpian error: function can not be exponentiated with other types")
            }
            _ => panic!("elpian error: unknown type can not be exponentiated with other types"),
        }
    }
    pub(super) fn is_eq(&self, v: Val, v2: Val) -> bool {
        // The first-class null (typ 0) is equal only to itself: guest `null`
        // literals, host replies decoding JSON `null`, and every absent read
        // all produce the same value, and a numeric zero is an ordinary
        // number, distinct from null.
        if v.typ == ty::NULL || v2.typ == ty::NULL {
            return is_null(&v) && is_null(&v2);
        }
        match v.typ {
            ty::I16..=ty::I64 => {
                let v_val = match v.typ {
                    ty::I16 => v.as_i16() as i64,
                    ty::I32 => v.as_i32() as i64,
                    ty::I64 => v.as_i64(),
                    _ => 0,
                };
                match v2.typ {
                    ty::I16..=ty::I64 => {
                        let v2_val = match v2.typ {
                            ty::I16 => v2.as_i16() as i64,
                            ty::I32 => v2.as_i32() as i64,
                            ty::I64 => v2.as_i64(),
                            _ => 0,
                        };
                        v_val == v2_val
                    }
                    ty::F32 | ty::F64 => {
                        let v_val_temp = v_val as f64;
                        let v2_val = match v2.typ {
                            ty::F32 => v2.as_f32() as f64,
                            ty::F64 => v2.as_f64(),
                            _ => 0.0,
                        };
                        v_val_temp == v2_val
                    }
                    _ => false,
                }
            }
            ty::F32 | ty::F64 => {
                let v_val = match v.typ {
                    ty::F32 => v.as_f32() as f64,
                    ty::F64 => v.as_f64(),
                    _ => 0.0,
                };
                match v2.typ {
                    ty::I16..=ty::I64 => {
                        let v2_val = match v2.typ {
                            ty::I16 => v2.as_i16() as f64,
                            ty::I32 => v2.as_i32() as f64,
                            ty::I64 => v2.as_i64() as f64,
                            _ => 0.0,
                        };
                        v_val == v2_val
                    }
                    ty::F32 | ty::F64 => {
                        let v2_val = match v2.typ {
                            ty::F32 => v2.as_f32() as f64,
                            ty::F64 => v2.as_f64(),
                            _ => 0.0,
                        };
                        v_val == v2_val
                    }
                    _ => false,
                }
            }
            ty::BOOL => {
                let v_val = v.as_bool();
                match v2.typ {
                    ty::BOOL => {
                        let v2_val = v2.as_bool();
                        v_val == v2_val
                    }
                    _ => false,
                }
            }
            ty::STRING => {
                let v_val = v.as_string();
                match v2.typ {
                    ty::STRING => {
                        let v2_val = v2.as_string();
                        v_val == v2_val
                    }
                    _ => false,
                }
            }
            ty::OBJECT => {
                let v_val = v.as_object();
                match v2.typ {
                    ty::OBJECT => {
                        let v2_val = v2.as_object();
                        // Identity short-circuit: the same object is always
                        // equal to itself. Besides being fast, this is what
                        // terminates comparisons of self-referential object
                        // graphs (e.g. a UI tree with parent/child
                        // back-references), which the structural walk below
                        // would recurse into forever.
                        if std::rc::Rc::ptr_eq(&v_val, &v2_val) {
                            return true;
                        }
                        if v_val.borrow().data.data.iter().all(|(k, _d)| {
                            if !v2_val.borrow().data.data.contains_key(&k.clone()) {
                                return false;
                            }
                            true
                        }) && v_val.borrow().data.data.iter().all(|(k, _d)| {
                            if !v2_val.borrow().data.data.contains_key(&k.clone()) {
                                return false;
                            }
                            true
                        }) {
                            return v_val.borrow().data.data.iter().all(|(k, d)| {
                                self.is_eq(
                                    d.clone(),
                                    v2_val.borrow().data.data.get(&k.clone()).unwrap().clone(),
                                )
                            });
                        }
                        false
                    }
                    _ => false,
                }
            }
            ty::ARRAY => {
                let v_val = v.as_array();
                match v2.typ {
                    ty::ARRAY => {
                        let v2_val = v2.as_array();
                        // Identity short-circuit (see the object case above).
                        if std::rc::Rc::ptr_eq(&v_val, &v2_val) {
                            return true;
                        }
                        if v_val.borrow().data.len() != v2_val.borrow().data.len() {
                            return false;
                        }
                        let mut counter: usize = 0;
                        return v_val.borrow().data.iter().all(|d| {
                            if self.is_eq(
                                d.clone(),
                                v2_val.borrow().data.get(counter).unwrap().clone(),
                            ) {
                                counter += 1;
                                true
                            } else {
                                false
                            }
                        });
                    }
                    _ => false,
                }
            }
            ty::FUNCTION => {
                let v_val = v.as_func();
                match v2.typ {
                    ty::FUNCTION => {
                        let v2_val = v2.as_func();
                        v_val.borrow().start == v2_val.borrow().start
                            && v_val.borrow().end == v2_val.borrow().end
                    }
                    _ => false,
                }
            }
            _ => false,
        }
    }
    pub(super) fn is_ge(&self, v: Val, v2: Val) -> bool {
        match v.typ {
            ty::I16..=ty::I64 => {
                let v_val = match v.typ {
                    ty::I16 => v.as_i16() as i64,
                    ty::I32 => v.as_i32() as i64,
                    ty::I64 => v.as_i64(),
                    _ => 0,
                };
                match v2.typ {
                    ty::I16..=ty::I64 => {
                        let v2_val = match v2.typ {
                            ty::I16 => v2.as_i16() as i64,
                            ty::I32 => v2.as_i32() as i64,
                            ty::I64 => v2.as_i64(),
                            _ => 0,
                        };
                        v_val > v2_val
                    }
                    ty::F32 | ty::F64 => {
                        let v_val_temp = v_val as f64;
                        let v2_val = match v2.typ {
                            ty::F32 => v2.as_f32() as f64,
                            ty::F64 => v2.as_f64(),
                            _ => 0.0,
                        };
                        v_val_temp > v2_val
                    }
                    _ => panic!(
                        "elpian error: numerical and non numerical values are not comparable unless it is just equality check"
                    ),
                }
            }
            ty::F32 | ty::F64 => {
                let v_val = match v.typ {
                    ty::F32 => v.as_f32() as f64,
                    ty::F64 => v.as_f64(),
                    _ => 0.0,
                };
                match v2.typ {
                    ty::I16..=ty::I64 => {
                        let v2_val = match v2.typ {
                            ty::I16 => v2.as_i16() as f64,
                            ty::I32 => v2.as_i32() as f64,
                            ty::I64 => v2.as_i64() as f64,
                            _ => 0.0,
                        };
                        v_val > v2_val
                    }
                    ty::F32 | ty::F64 => {
                        let v2_val = match v2.typ {
                            ty::F32 => v2.as_f32() as f64,
                            ty::F64 => v2.as_f64(),
                            _ => 0.0,
                        };
                        v_val > v2_val
                    }
                    _ => panic!(
                        "elpian error: numerical and non numerical values are not comparable unless it is just equality check"
                    ),
                }
            }
            ty::BOOL => {
                let v_val = v.as_bool();
                match v2.typ {
                    ty::BOOL => {
                        let v2_val = v2.as_bool();
                        v_val & !v2_val
                    }
                    _ => panic!(
                        "elpian error: boolean and non boolean values are not comparable unless it is just equality check"
                    ),
                }
            }
            ty::STRING => {
                let v_val = v.as_string();
                match v2.typ {
                    ty::BOOL => {
                        let v2_val = v2.as_string();
                        v_val > v2_val
                    }
                    _ => panic!(
                        "elpian error: string and non string values are not comparable unless it is just equality check"
                    ),
                }
            }
            ty::OBJECT => {
                let v_val = v.as_object();
                match v2.typ {
                    ty::BOOL => {
                        let v2_val = v2.as_object();
                        if v_val.borrow().data.data.iter().all(|(k, _d)| {
                            if !v2_val.borrow().data.data.contains_key(&k.clone()) {
                                return false;
                            }
                            true
                        }) && v_val.borrow().data.data.iter().all(|(k, _d)| {
                            if !v2_val.borrow().data.data.contains_key(&k.clone()) {
                                return false;
                            }
                            true
                        }) {
                            let mut counter1 = 0;
                            let mut counter2 = 0;
                            v_val.borrow().data.data.iter().for_each(|(k, d)| {
                                if self.is_ge(
                                    d.clone(),
                                    v2_val.borrow().data.data.get(&k.clone()).unwrap().clone(),
                                ) {
                                    counter1 += 1;
                                } else {
                                    counter2 += 1;
                                }
                            });
                            return counter1 > counter2;
                        }
                        false
                    }
                    _ => panic!(
                        "elpian error: object and non object values are not comparable unless it is just equality check"
                    ),
                }
            }
            ty::ARRAY => {
                let v_val = v.as_array();
                match v2.typ {
                    ty::ARRAY => {
                        let v2_val = v2.as_array();
                        if v_val.borrow().data.len() != v2_val.borrow().data.len() {
                            return false;
                        }
                        let mut counter1 = 0;
                        let mut counter2 = 0;
                        let mut counter = 0;
                        v_val.borrow().data.iter().for_each(|d| {
                            if self.is_ge(
                                d.clone(),
                                v2_val.borrow().data.get(counter).unwrap().clone(),
                            ) {
                                counter1 += 1;
                            } else {
                                counter2 += 1;
                            }
                            counter += 1;
                        });
                        counter1 > counter2
                    }
                    _ => panic!(
                        "elpian error: array and non array values are not comparable unless it is just equality check"
                    ),
                }
            }
            ty::FUNCTION => panic!(
                "elpian error: function types are not comparable unless it is just equality check"
            ),
            _ => panic!("elpian error: unknown types are not comparable"),
        }
    }
    pub(super) fn is_gee(&self, v: Val, v2: Val) -> bool {
        match v.typ {
            ty::I16..=ty::I64 => {
                let v_val = match v.typ {
                    ty::I16 => v.as_i16() as i64,
                    ty::I32 => v.as_i32() as i64,
                    ty::I64 => v.as_i64(),
                    _ => 0,
                };
                match v2.typ {
                    ty::I16..=ty::I64 => {
                        let v2_val = match v2.typ {
                            ty::I16 => v2.as_i16() as i64,
                            ty::I32 => v2.as_i32() as i64,
                            ty::I64 => v2.as_i64(),
                            _ => 0,
                        };
                        v_val >= v2_val
                    }
                    ty::F32 | ty::F64 => {
                        let v_val_temp = v_val as f64;
                        let v2_val = match v2.typ {
                            ty::F32 => v2.as_f32() as f64,
                            ty::F64 => v2.as_f64(),
                            _ => 0.0,
                        };
                        v_val_temp >= v2_val
                    }
                    _ => panic!(
                        "elpian error: numerical and non numerical values are not comparable unless it is just equality check"
                    ),
                }
            }
            ty::F32 | ty::F64 => {
                let v_val = match v.typ {
                    ty::F32 => v.as_f32() as f64,
                    ty::F64 => v.as_f64(),
                    _ => 0.0,
                };
                match v2.typ {
                    ty::I16..=ty::I64 => {
                        let v2_val = match v2.typ {
                            ty::I16 => v2.as_i16() as f64,
                            ty::I32 => v2.as_i32() as f64,
                            ty::I64 => v2.as_i64() as f64,
                            _ => 0.0,
                        };
                        v_val >= v2_val
                    }
                    ty::F32 | ty::F64 => {
                        let v2_val = match v2.typ {
                            ty::F32 => v2.as_f32() as f64,
                            ty::F64 => v2.as_f64(),
                            _ => 0.0,
                        };
                        v_val >= v2_val
                    }
                    _ => panic!(
                        "elpian error: numerical and non numerical values are not comparable unless it is just equality check"
                    ),
                }
            }
            ty::BOOL => {
                let v_val = v.as_bool();
                match v2.typ {
                    ty::BOOL => {
                        let v2_val = v2.as_bool();
                        v_val >= v2_val
                    }
                    _ => panic!(
                        "elpian error: boolean and non boolean values are not comparable unless it is just equality check"
                    ),
                }
            }
            ty::STRING => {
                let v_val = v.as_string();
                match v2.typ {
                    ty::BOOL => {
                        let v2_val = v2.as_string();
                        v_val >= v2_val
                    }
                    _ => panic!(
                        "elpian error: string and non string values are not comparable unless it is just equality check"
                    ),
                }
            }
            ty::OBJECT => {
                let v_val = v.as_object();
                match v2.typ {
                    ty::BOOL => {
                        let v2_val = v2.as_object();
                        if v_val.borrow().data.data.iter().all(|(k, _d)| {
                            if !v2_val.borrow().data.data.contains_key(&k.clone()) {
                                return false;
                            }
                            true
                        }) && v_val.borrow().data.data.iter().all(|(k, _d)| {
                            if !v2_val.borrow().data.data.contains_key(&k.clone()) {
                                return false;
                            }
                            true
                        }) {
                            let mut counter1 = 0;
                            let mut counter2 = 0;
                            v_val.borrow().data.data.iter().for_each(|(k, d)| {
                                if self.is_gee(
                                    d.clone(),
                                    v2_val.borrow().data.data.get(&k.clone()).unwrap().clone(),
                                ) {
                                    counter1 += 1;
                                } else {
                                    counter2 += 1;
                                }
                            });
                            return counter1 >= counter2;
                        }
                        false
                    }
                    _ => panic!(
                        "elpian error: object and non object values are not comparable unless it is just equality check"
                    ),
                }
            }
            ty::ARRAY => {
                let v_val = v.as_array();
                match v2.typ {
                    ty::ARRAY => {
                        let v2_val = v2.as_array();
                        if v_val.borrow().data.len() != v2_val.borrow().data.len() {
                            return false;
                        }
                        let mut counter1 = 0;
                        let mut counter2 = 0;
                        let mut counter = 0;
                        v_val.borrow().data.iter().for_each(|d| {
                            if self.is_gee(
                                d.clone(),
                                v2_val.borrow().data.get(counter).unwrap().clone(),
                            ) {
                                counter1 += 1;
                            } else {
                                counter2 += 1;
                            }
                            counter += 1;
                        });
                        counter1 >= counter2
                    }
                    _ => panic!(
                        "elpian error: array and non array values are not comparable unless it is just equality check"
                    ),
                }
            }
            ty::FUNCTION => panic!(
                "elpian error: function types are not comparable unless it is just equality check"
            ),
            _ => panic!("elpian error: unknown types are not comparable"),
        }
    }
    pub(super) fn is_le(&self, v: Val, v2: Val) -> bool {
        match v.typ {
            ty::I16..=ty::I64 => {
                let v_val = match v.typ {
                    ty::I16 => v.as_i16() as i64,
                    ty::I32 => v.as_i32() as i64,
                    ty::I64 => v.as_i64(),
                    _ => 0,
                };
                match v2.typ {
                    ty::I16..=ty::I64 => {
                        let v2_val = match v2.typ {
                            ty::I16 => v2.as_i16() as i64,
                            ty::I32 => v2.as_i32() as i64,
                            ty::I64 => v2.as_i64(),
                            _ => 0,
                        };
                        v_val < v2_val
                    }
                    ty::F32 | ty::F64 => {
                        let v_val_temp = v_val as f64;
                        let v2_val = match v2.typ {
                            ty::F32 => v2.as_f32() as f64,
                            ty::F64 => v2.as_f64(),
                            _ => 0.0,
                        };
                        v_val_temp < v2_val
                    }
                    _ => panic!(
                        "elpian error: numerical and non numerical values are not comparable unless it is just equality check"
                    ),
                }
            }
            ty::F32 | ty::F64 => {
                let v_val = match v.typ {
                    ty::F32 => v.as_f32() as f64,
                    ty::F64 => v.as_f64(),
                    _ => 0.0,
                };
                match v2.typ {
                    ty::I16..=ty::I64 => {
                        let v2_val = match v2.typ {
                            ty::I16 => v2.as_i16() as f64,
                            ty::I32 => v2.as_i32() as f64,
                            ty::I64 => v2.as_i64() as f64,
                            _ => 0.0,
                        };
                        v_val < v2_val
                    }
                    ty::F32 | ty::F64 => {
                        let v2_val = match v2.typ {
                            ty::F32 => v2.as_f32() as f64,
                            ty::F64 => v2.as_f64(),
                            _ => 0.0,
                        };
                        v_val < v2_val
                    }
                    _ => panic!(
                        "elpian error: numerical and non numerical values are not comparable unless it is just equality check"
                    ),
                }
            }
            ty::BOOL => {
                let v_val = v.as_bool();
                match v2.typ {
                    ty::BOOL => {
                        let v2_val = v2.as_bool();
                        !v_val & v2_val
                    }
                    _ => panic!(
                        "elpian error: boolean and non boolean values are not comparable unless it is just equality check"
                    ),
                }
            }
            ty::STRING => {
                let v_val = v.as_string();
                match v2.typ {
                    ty::BOOL => {
                        let v2_val = v2.as_string();
                        v_val < v2_val
                    }
                    _ => panic!(
                        "elpian error: string and non string values are not comparable unless it is just equality check"
                    ),
                }
            }
            ty::OBJECT => {
                let v_val = v.as_object();
                match v2.typ {
                    ty::BOOL => {
                        let v2_val = v2.as_object();
                        if v_val.borrow().data.data.iter().all(|(k, _d)| {
                            if !v2_val.borrow().data.data.contains_key(&k.clone()) {
                                return false;
                            }
                            true
                        }) && v_val.borrow().data.data.iter().all(|(k, _d)| {
                            if !v2_val.borrow().data.data.contains_key(&k.clone()) {
                                return false;
                            }
                            true
                        }) {
                            let mut counter1 = 0;
                            let mut counter2 = 0;
                            v_val.borrow().data.data.iter().for_each(|(k, d)| {
                                if self.is_le(
                                    d.clone(),
                                    v2_val.borrow().data.data.get(&k.clone()).unwrap().clone(),
                                ) {
                                    counter1 += 1;
                                } else {
                                    counter2 += 1;
                                }
                            });
                            return counter1 < counter2;
                        }
                        false
                    }
                    _ => panic!(
                        "elpian error: object and non object values are not comparable unless it is just equality check"
                    ),
                }
            }
            ty::ARRAY => {
                let v_val = v.as_array();
                match v2.typ {
                    ty::ARRAY => {
                        let v2_val = v2.as_array();
                        if v_val.borrow().data.len() != v2_val.borrow().data.len() {
                            return false;
                        }
                        let mut counter1 = 0;
                        let mut counter2 = 0;
                        let mut counter = 0;
                        v_val.borrow().data.iter().for_each(|d| {
                            if self.is_le(
                                d.clone(),
                                v2_val.borrow().data.get(counter).unwrap().clone(),
                            ) {
                                counter1 += 1;
                            } else {
                                counter2 += 1;
                            }
                            counter += 1;
                        });
                        counter1 < counter2
                    }
                    _ => panic!(
                        "elpian error: array and non array values are not comparable unless it is just equality check"
                    ),
                }
            }
            ty::FUNCTION => panic!(
                "elpian error: function types are not comparable unless it is just equality check"
            ),
            _ => panic!("elpian error: unknown types are not comparable"),
        }
    }
    pub(super) fn is_lee(&self, v: Val, v2: Val) -> bool {
        match v.typ {
            ty::I16..=ty::I64 => {
                let v_val = match v.typ {
                    ty::I16 => v.as_i16() as i64,
                    ty::I32 => v.as_i32() as i64,
                    ty::I64 => v.as_i64(),
                    _ => 0,
                };
                match v2.typ {
                    ty::I16..=ty::I64 => {
                        let v2_val = match v2.typ {
                            ty::I16 => v2.as_i16() as i64,
                            ty::I32 => v2.as_i32() as i64,
                            ty::I64 => v2.as_i64(),
                            _ => 0,
                        };
                        v_val <= v2_val
                    }
                    ty::F32 | ty::F64 => {
                        let v_val_temp = v_val as f64;
                        let v2_val = match v2.typ {
                            ty::F32 => v2.as_f32() as f64,
                            ty::F64 => v2.as_f64(),
                            _ => 0.0,
                        };
                        v_val_temp <= v2_val
                    }
                    _ => panic!(
                        "elpian error: numerical and non numerical values are not comparable unless it is just equality check"
                    ),
                }
            }
            ty::F32 | ty::F64 => {
                let v_val = match v.typ {
                    ty::F32 => v.as_f32() as f64,
                    ty::F64 => v.as_f64(),
                    _ => 0.0,
                };
                match v2.typ {
                    ty::I16..=ty::I64 => {
                        let v2_val = match v2.typ {
                            ty::I16 => v2.as_i16() as f64,
                            ty::I32 => v2.as_i32() as f64,
                            ty::I64 => v2.as_i64() as f64,
                            _ => 0.0,
                        };
                        v_val <= v2_val
                    }
                    ty::F32 | ty::F64 => {
                        let v2_val = match v2.typ {
                            ty::F32 => v2.as_f32() as f64,
                            ty::F64 => v2.as_f64(),
                            _ => 0.0,
                        };
                        v_val <= v2_val
                    }
                    _ => panic!(
                        "elpian error: numerical and non numerical values are not comparable unless it is just equality check"
                    ),
                }
            }
            ty::BOOL => {
                let v_val = v.as_bool();
                match v2.typ {
                    ty::BOOL => {
                        let v2_val = v2.as_bool();
                        v_val <= v2_val
                    }
                    _ => panic!(
                        "elpian error: boolean and non boolean values are not comparable unless it is just equality check"
                    ),
                }
            }
            ty::STRING => {
                let v_val = v.as_string();
                match v2.typ {
                    ty::BOOL => {
                        let v2_val = v2.as_string();
                        v_val <= v2_val
                    }
                    _ => panic!(
                        "elpian error: string and non string values are not comparable unless it is just equality check"
                    ),
                }
            }
            ty::OBJECT => {
                let v_val = v.as_object();
                match v2.typ {
                    ty::BOOL => {
                        let v2_val = v2.as_object();
                        if v_val.borrow().data.data.iter().all(|(k, _d)| {
                            if !v2_val.borrow().data.data.contains_key(&k.clone()) {
                                return false;
                            }
                            true
                        }) && v_val.borrow().data.data.iter().all(|(k, _d)| {
                            if !v2_val.borrow().data.data.contains_key(&k.clone()) {
                                return false;
                            }
                            true
                        }) {
                            let mut counter1 = 0;
                            let mut counter2 = 0;
                            v_val.borrow().data.data.iter().for_each(|(k, d)| {
                                if self.is_lee(
                                    d.clone(),
                                    v2_val.borrow().data.data.get(&k.clone()).unwrap().clone(),
                                ) {
                                    counter1 += 1;
                                } else {
                                    counter2 += 1;
                                }
                            });
                            return counter1 <= counter2;
                        }
                        false
                    }
                    _ => panic!(
                        "elpian error: object and non object values are not comparable unless it is just equality check"
                    ),
                }
            }
            ty::ARRAY => {
                let v_val = v.as_array();
                match v2.typ {
                    ty::ARRAY => {
                        let v2_val = v2.as_array();
                        if v_val.borrow().data.len() != v2_val.borrow().data.len() {
                            return false;
                        }
                        let mut counter1 = 0;
                        let mut counter2 = 0;
                        let mut counter = 0;
                        v_val.borrow().data.iter().for_each(|d| {
                            if self.is_lee(
                                d.clone(),
                                v2_val.borrow().data.get(counter).unwrap().clone(),
                            ) {
                                counter1 += 1;
                            } else {
                                counter2 += 1;
                            }
                            counter += 1;
                        });
                        counter1 <= counter2
                    }
                    _ => panic!(
                        "elpian error: array and non array values are not comparable unless it is just equality check"
                    ),
                }
            }
            ty::FUNCTION => panic!(
                "elpian error: function types are not comparable unless it is just equality check"
            ),
            _ => panic!("elpian error: unknown types are not comparable"),
        }
    }
}
