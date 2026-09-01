//! Decoded program representation.
//!
//! The executor used to walk the raw bytecode byte-by-byte on *every* step of
//! *every* frame: re-reading each opcode, re-parsing every length-prefixed
//! identifier / object key / parameter name (a fresh UTF-8 validation **and**
//! `String` allocation each time), and rebuilding each literal `Val` from its
//! bytes. For a program whose render path re-runs dozens of times a second over
//! thousands of operations this re-decoding dominated the per-frame cost.
//!
//! [`DecodedProgram`] lifts that work out of the hot loop. At construction the
//! whole byte stream is decoded **once** into a flat list of [`UnitKind`]s — one
//! self-contained object per operation, carrying *all* of its operands
//! pre-parsed: literals prebuilt as [`Val`], names interned as
//! `Rc<str>`/`Rc<Vec<String>>` (shared, never re-allocated), counts as plain
//! integers, and every branch/body/case **target as a unit index**. The
//! interpreter traverses this list directly, using a unit index as its program
//! counter (`pc += 1`), and branches by assigning a target unit index straight
//! to the pointer. Nothing is re-parsed and there are no trailing "immediate"
//! units to read back — each opcode object already holds its data. The raw
//! bytecode is not retained past decode.
//!
//! ## Unit-relative addressing
//!
//! The compiler bakes control-flow targets into the bytecode as **byte offsets**
//! (jump destinations, function/scope bounds, if/loop/switch/branch pointers). A
//! second decode pass ([`Decoder::relocate`]) rewrites every one of those into
//! the **index of the unit** at that offset. A target one past the program's last
//! unit (a body/function that ends the stream) becomes `units.len()`, the same
//! "end" sentinel the run loop compares against.
//!
//! The grammar decoded here mirrors exactly what `compiler::serialize_expr`,
//! `compiler::serialize_condition_chain` and `compiler::compile_ast` emit; the
//! two must stay in lock-step.

use std::rc::Rc;

use crate::sdk::data::{Payload, Val};

/// The three short-circuiting binary operators the VM lowers through the single
/// `0xef` opcode, distinguished by the opcode's flag byte. All three are
/// language-neutral value selectors: `And` yields the left operand when it is
/// falsy (by the VM's truthiness rule, see [`crate::sdk::data::Val::truthy`])
/// and otherwise evaluates and yields the right; `Or` is its dual;
/// `NullCoalesce` yields the left operand unless it is the first-class null
/// (type tag 0), in which case it evaluates and yields the right operand.
/// Front-ends whose source language uses a different notion of truthiness
/// coerce their operands at compile time (e.g. via the `bool` builtin).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum LogicalKind {
    And,
    Or,
    NullCoalesce,
}

impl LogicalKind {
    /// Decode the opcode flag byte: `0` = `&&`, `1` = `||`, `2` = `??`.
    fn from_flag(flag: u8) -> LogicalKind {
        match flag {
            1 => LogicalKind::Or,
            2 => LogicalKind::NullCoalesce,
            _ => LogicalKind::And,
        }
    }
}

/// One binding of a [`UnitKind::Destructure`]. A destructuring statement binds a
/// list of these from a single source value: object bindings read member `key`,
/// array bindings read by position (their order in the plan). `is_hole` (array
/// only) skips a position with no binding; `is_rest` collects everything not yet
/// consumed into a fresh collection; `has_default` means a default-value
/// expression was serialized for this binding (defaults appear as inline
/// expressions after the source, in binding order, and are supplied to the
/// executor as collected values).
#[derive(Clone)]
pub struct DestructureBinding {
    pub name: String,
    pub key: String,
    pub has_default: bool,
    pub is_rest: bool,
    pub is_hole: bool,
}

/// The fixed metadata of a `destructure` statement, shared (`Rc`) into the
/// `Destructure` unit. The source value and any default expressions are separate
/// value units the executor evaluates and hands back; `value_count` is how many
/// such values the operation collects (`1` for the source plus one per default).
#[derive(Clone)]
pub struct DestructurePlan {
    pub is_array: bool,
    pub bindings: Vec<DestructureBinding>,
    pub value_count: usize,
}

/// One decoded operation, with every operand already parsed. Cheap to clone
/// (scalars are copied; names, parameter lists and case tables are `Rc` pointer
/// bumps), which the dispatch loop relies on. Every position field is a **unit
/// index** after decode, not a byte offset.
#[derive(Clone)]
pub enum UnitKind {
    /// A no-op (`0x00` padding for an empty body, or any unknown opcode — matched
    /// the interpreter's old `_ => {}` arm).
    Nop,

    // ---- value-producing units (what the old `extract_val` returned) --------
    /// A null, scalar or string literal (`typ` 0..=7). Cloned to produce the
    /// value.
    Lit(Val),
    /// An identifier reference (`0x0b`); resolved against the scope chain /
    /// builtins / the `askHost` seam at run time.
    Ident(Rc<str>),
    /// A function *literal* (`0x0a`). Closes over the live lexical environment
    /// when evaluated. `start`/`end` are unit indices.
    FuncLit { start: usize, end: usize, params: Rc<Vec<String>> },

    // ---- operators / control, each carrying its own operands ----------------
    /// `0x0c` — indexer (`target[index]`).
    Indexer,
    /// `0x0d` — function / host call (`argc` arguments follow as expressions).
    Call { argc: u32 },
    /// `0xfc` — boolean `!`.
    Not,
    /// `0xef` — short-circuiting logical operator (`&&`, `||`, or the
    /// null-coalescing `??`), discriminated by [`LogicalKind`]. The left operand
    /// follows immediately; `op2_end` is the unit index just past the right
    /// operand, so the executor can skip it on short-circuit.
    Logical { kind: LogicalKind, op2_end: usize },
    /// `0xee` — conditional/ternary `c ? a : b`. The condition follows
    /// immediately, then the consequent and alternate. `alt_start` is the unit
    /// index of the alternate; `end` is one past the whole expression.
    Conditional { alt_start: usize, end: usize },
    /// `0xfd` — `cast` of the following value expression to `target_type`.
    Cast { target_type: Rc<str> },
    /// `0xed` — reified type test of the following value expression against
    /// `type_name`. `cast` false is `is` (yields a bool); `cast` true is `as`
    /// (yields the value, trapping on a mismatch).
    TypeTest { type_name: Rc<str>, cast: bool },
    /// `0xf0..=0xfb` — an arithmetic / comparison operator, normalised to the
    /// `1..=12` id the interpreter switches on.
    Arith(i16),
    /// `0x14` — `return`.
    Return,
    /// `0x11` — `while`/`for` loop head (condition follows; bounds are unit
    /// indices).
    Loop { body_start: usize, body_end: usize, branch_after: usize },
    /// `0x12` — `switch` (value follows; `cases` is the `(body_start, body_end)`
    /// unit-index range of each case, in order; `branch_after` is where the whole
    /// switch ends).
    Switch { branch_after: usize, cases: Rc<Vec<(usize, usize)>> },
    /// `0x16` — low-level conditional branch (condition follows; both targets are
    /// unit indices).
    CondBranch { true_branch: usize, false_branch: usize },

    // ---- statement heads ----------------------------------------------------
    /// `0x0e` — `let`/`const`/`var` of a simple name (value expression follows).
    DefineVar(Rc<str>),
    /// `0x0f` — assignment. `kind` is 1 for a plain identifier target and 2 for
    /// an indexed target (`a[i] = v` / `a.b = v`, whose index expression then
    /// precedes the value expression).
    AssignVar { name: Rc<str>, kind: i16 },
    /// `0x10` — head of one arm of an if/else chain (condition follows when
    /// `has_condition`; the bounds are unit indices). `next` is the following arm
    /// (only meaningful when `has_condition`); `branch_after` is the end of the
    /// whole chain.
    IfHead {
        has_condition: bool,
        body_start: usize,
        body_end: usize,
        next: usize,
        branch_after: usize,
    },
    /// `0x15` — unconditional jump to a unit index.
    Jump(usize),
    /// `0x17` — `continue` (re-run the enclosing loop head).
    Continue,
    /// `0x18` — `break` (exit the enclosing loop or switch).
    Break,
    /// `0x08` — object-literal head (type id + property count).
    ObjHead { typ: i64, props_len: i32 },
    /// `0x09` — array-literal head (element count).
    ArrHead { len: i32 },
    /// `0x19` — spread element (`...value`): the inner value expression follows.
    /// Produces a spread marker the enclosing array / object / call builder
    /// flattens; a universal "expand this collection in place" operator.
    Spread,
    /// `0x1a` — object-spread key marker (no operand). Sits in an object
    /// literal's key position to signal that the following value expression is an
    /// object whose members are merged in, rather than a single named property.
    SpreadKey,
    /// `0x1b` — interpolated / template string: `count` value expressions follow;
    /// each is coerced to display text and the results concatenated.
    Template { count: u32 },
    /// `0x1c` — destructuring binding. The source value follows, then one default
    /// expression per binding that declares a default (in binding order); the
    /// plan describes how to bind names from the source's members / positions.
    Destructure { plan: Rc<DestructurePlan> },
    /// `0x1d` — try/catch. The protected body runs first; a value thrown inside
    /// it (dynamically, at any call depth) unwinds to the catch body with the
    /// value bound under `err_name`. Normal completion of the body skips the
    /// catch entirely. All four positions are unit indices after decode.
    TryHead {
        body_start: usize,
        body_end: usize,
        catch_start: usize,
        catch_end: usize,
        err_name: Rc<str>,
    },
    /// `0x1e` — `throw` (value expression follows).
    Throw,
    /// `0x13` — function definition (hoisted; body follows). `start`/`end` are
    /// unit indices.
    FuncDef {
        name: Rc<str>,
        params: Rc<Vec<String>>,
        frees: Rc<Vec<String>>,
        start: usize,
        end: usize,
    },
}

/// The whole program decoded once into a flat list of [`UnitKind`]s, traversed by
/// unit index. The raw bytecode is dropped after decoding.
pub struct DecodedProgram {
    pub units: Vec<UnitKind>,
}

const NONE: u32 = u32::MAX;

impl DecodedProgram {
    /// Decode an entire bytecode program into units, then rewrite every baked
    /// byte-offset target into a unit index. Mirrors the compiler's emission
    /// grammar; see the module docs.
    pub fn decode(bytes: &[u8]) -> DecodedProgram {
        let mut d = Decoder { bytes, units: Vec::new(), index_at: vec![NONE; bytes.len()] };
        if !bytes.is_empty() {
            d.decode_stmt_seq(0, bytes.len());
        }
        d.relocate();
        DecodedProgram { units: d.units }
    }
}

struct Decoder<'a> {
    bytes: &'a [u8],
    units: Vec<UnitKind>,
    /// Byte offset → unit index (`NONE` for offsets interior to a unit).
    index_at: Vec<u32>,
}

impl<'a> Decoder<'a> {
    #[inline]
    fn emit(&mut self, off: usize, kind: UnitKind) -> usize {
        let idx = self.units.len();
        self.index_at[off] = idx as u32;
        self.units.push(kind);
        idx
    }

    /// Translate a target **byte offset** (stashed in a unit during decoding) to
    /// a unit index. A target at or past the end of the stream becomes the
    /// one-past-last sentinel `units.len()`; every other target is a unit start
    /// the compiler aligned a branch to.
    fn target_unit(&self, off: usize) -> usize {
        if off >= self.bytes.len() {
            return self.units.len();
        }
        let i = self.index_at[off];
        debug_assert!(i != NONE, "branch target offset {off} is not a unit start");
        if i == NONE {
            self.units.len()
        } else {
            i as usize
        }
    }

    /// Second pass: rewrite every position field from the byte offset stashed
    /// during decoding to a unit index.
    fn relocate(&mut self) {
        for i in 0..self.units.len() {
            let translated = match &self.units[i] {
                UnitKind::Jump(off) => UnitKind::Jump(self.target_unit(*off)),
                UnitKind::CondBranch { true_branch, false_branch } => UnitKind::CondBranch {
                    true_branch: self.target_unit(*true_branch),
                    false_branch: self.target_unit(*false_branch),
                },
                UnitKind::Loop { body_start, body_end, branch_after } => UnitKind::Loop {
                    body_start: self.target_unit(*body_start),
                    body_end: self.target_unit(*body_end),
                    branch_after: self.target_unit(*branch_after),
                },
                UnitKind::IfHead { has_condition, body_start, body_end, next, branch_after } => {
                    UnitKind::IfHead {
                        has_condition: *has_condition,
                        body_start: self.target_unit(*body_start),
                        body_end: self.target_unit(*body_end),
                        next: self.target_unit(*next),
                        branch_after: self.target_unit(*branch_after),
                    }
                }
                UnitKind::Switch { branch_after, cases } => {
                    let cases: Vec<(usize, usize)> = cases
                        .iter()
                        .map(|(s, e)| (self.target_unit(*s), self.target_unit(*e)))
                        .collect();
                    UnitKind::Switch {
                        branch_after: self.target_unit(*branch_after),
                        cases: Rc::new(cases),
                    }
                }
                UnitKind::FuncDef { name, params, frees, start, end } => UnitKind::FuncDef {
                    name: name.clone(),
                    params: params.clone(),
                    frees: frees.clone(),
                    start: self.target_unit(*start),
                    end: self.target_unit(*end),
                },
                UnitKind::TryHead { body_start, body_end, catch_start, catch_end, err_name } => {
                    UnitKind::TryHead {
                        body_start: self.target_unit(*body_start),
                        body_end: self.target_unit(*body_end),
                        catch_start: self.target_unit(*catch_start),
                        catch_end: self.target_unit(*catch_end),
                        err_name: err_name.clone(),
                    }
                }
                UnitKind::FuncLit { start, end, params } => UnitKind::FuncLit {
                    start: self.target_unit(*start),
                    end: self.target_unit(*end),
                    params: params.clone(),
                },
                _ => continue,
            };
            self.units[i] = translated;
        }
    }

    #[inline]
    fn read_i16(&self, p: usize) -> i16 {
        i16::from_be_bytes(self.bytes[p..p + 2].try_into().unwrap())
    }
    #[inline]
    fn read_i32(&self, p: usize) -> i32 {
        i32::from_be_bytes(self.bytes[p..p + 4].try_into().unwrap())
    }
    #[inline]
    fn read_i64(&self, p: usize) -> i64 {
        i64::from_be_bytes(self.bytes[p..p + 8].try_into().unwrap())
    }
    #[inline]
    fn read_f32(&self, p: usize) -> f32 {
        f32::from_be_bytes(self.bytes[p..p + 4].try_into().unwrap())
    }
    #[inline]
    fn read_f64(&self, p: usize) -> f64 {
        f64::from_be_bytes(self.bytes[p..p + 8].try_into().unwrap())
    }
    /// Read a length-prefixed string at `p`, returning it and the total bytes
    /// consumed (the 4-byte length plus the payload).
    fn read_str(&self, p: usize) -> (String, usize) {
        let len = self.read_i32(p) as usize;
        let s = String::from_utf8(self.bytes[p + 4..p + 4 + len].to_vec()).unwrap();
        (s, 4 + len)
    }

    // ---- expressions (mirror of `serialize_expr` / `extract_val`) -----------

    /// Decode one expression starting at byte offset `pos`; return the offset
    /// just past it.
    fn decode_value(&mut self, pos: usize) -> usize {
        let tag = self.bytes[pos];
        match tag {
            0 => {
                // The first-class null literal.
                self.emit(pos, UnitKind::Lit(Val::new(0, Payload::Null)));
                pos + 1
            }
            1 => {
                self.emit(pos, UnitKind::Lit(Val::new(1, Payload::from(self.read_i16(pos + 1)))));
                pos + 3
            }
            2 => {
                self.emit(pos, UnitKind::Lit(Val::new(2, Payload::from(self.read_i32(pos + 1)))));
                pos + 5
            }
            3 => {
                self.emit(pos, UnitKind::Lit(Val::new(3, Payload::from(self.read_i64(pos + 1)))));
                pos + 9
            }
            4 => {
                self.emit(pos, UnitKind::Lit(Val::new(4, Payload::from(self.read_f32(pos + 1)))));
                pos + 5
            }
            5 => {
                self.emit(pos, UnitKind::Lit(Val::new(5, Payload::from(self.read_f64(pos + 1)))));
                pos + 9
            }
            6 => {
                let b = self.bytes[pos + 1] == 0x01;
                self.emit(pos, UnitKind::Lit(Val::new(6, Payload::from(b))));
                pos + 2
            }
            7 => {
                let (s, consumed) = self.read_str(pos + 1);
                self.emit(pos, UnitKind::Lit(Val::new(7, Payload::from(s))));
                pos + 1 + consumed
            }
            0x0a => {
                // Function literal: start, end, param count, params.
                let start = self.read_i64(pos + 1) as usize;
                let end = self.read_i64(pos + 9) as usize;
                let param_count = self.read_i32(pos + 17) as usize;
                let mut p = pos + 21;
                let mut params = Vec::with_capacity(param_count);
                for _ in 0..param_count {
                    let (name, consumed) = self.read_str(p);
                    params.push(name);
                    p += consumed;
                }
                // start/end stashed as byte offsets; `relocate` turns them into
                // unit indices.
                self.emit(pos, UnitKind::FuncLit { start, end, params: Rc::new(params) });
                p
            }
            0x0b => {
                let (name, consumed) = self.read_str(pos + 1);
                self.emit(pos, UnitKind::Ident(Rc::from(name.as_str())));
                pos + 1 + consumed
            }
            0x0c => {
                // Indexer: opcode, then target expression, then index expression.
                self.emit(pos, UnitKind::Indexer);
                let after_target = self.decode_value(pos + 1);
                self.decode_value(after_target)
            }
            0xfc => {
                self.emit(pos, UnitKind::Not);
                self.decode_value(pos + 1)
            }
            0xef => {
                // Logical: opcode, flag (1 byte), op1, op2. The skip target
                // (`op2_end`) is the unit index just past `op2`; since units are
                // emitted in order, that is simply `units.len()` once `op2` is
                // decoded — a unit index already, needing no relocation.
                let idx = self.emit(
                    pos,
                    UnitKind::Logical { kind: LogicalKind::And, op2_end: 0 },
                );
                let kind = LogicalKind::from_flag(self.bytes[pos + 1]);
                let after_op1 = self.decode_value(pos + 2);
                let after_op2 = self.decode_value(after_op1);
                self.units[idx] = UnitKind::Logical { kind, op2_end: self.units.len() };
                after_op2
            }
            0xee => {
                // Conditional: opcode, cond, consequent, alternate. `alt_start` is
                // the unit index where the alternate begins (units emitted so far,
                // just after the consequent); `end` is one past the alternate.
                let idx = self.emit(pos, UnitKind::Conditional { alt_start: 0, end: 0 });
                let after_cond = self.decode_value(pos + 1);
                let after_conseq = self.decode_value(after_cond);
                let alt_start = self.units.len();
                let after_alt = self.decode_value(after_conseq);
                self.units[idx] = UnitKind::Conditional { alt_start, end: self.units.len() };
                after_alt
            }
            0xfd => {
                // Cast: opcode, value expression, then the target-type string —
                // which is folded straight into the unit (no trailing immediate).
                let idx = self.emit(pos, UnitKind::Cast { target_type: Rc::from("") });
                let after_val = self.decode_value(pos + 1);
                let (ty, consumed) = self.read_str(after_val);
                self.units[idx] = UnitKind::Cast { target_type: Rc::from(ty.as_str()) };
                after_val + consumed
            }
            0xed => {
                // Reified type test: opcode, cast flag, value expression, then the
                // type-name string, folded into the unit.
                let cast = self.bytes[pos + 1] == 1;
                let idx = self.emit(pos, UnitKind::TypeTest { type_name: Rc::from(""), cast });
                let after_val = self.decode_value(pos + 2);
                let (ty, consumed) = self.read_str(after_val);
                self.units[idx] = UnitKind::TypeTest { type_name: Rc::from(ty.as_str()), cast };
                after_val + consumed
            }
            0xf0..=0xfb => {
                self.emit(pos, UnitKind::Arith((tag - 0xf0 + 1) as i16));
                let after_op1 = self.decode_value(pos + 1);
                self.decode_value(after_op1)
            }
            0x0d => self.decode_call(pos),
            8 => self.decode_object(pos),
            9 => self.decode_array(pos),
            0x19 => {
                // Spread: opcode then the inner value expression.
                self.emit(pos, UnitKind::Spread);
                self.decode_value(pos + 1)
            }
            0x1a => {
                // Object-spread key marker: no operand.
                self.emit(pos, UnitKind::SpreadKey);
                pos + 1
            }
            0x1b => {
                // Template: opcode, part count, then that many value expressions.
                let count = self.read_i32(pos + 1) as u32;
                self.emit(pos, UnitKind::Template { count });
                let mut p = pos + 5;
                for _ in 0..count {
                    p = self.decode_value(p);
                }
                p
            }
            other => panic!("program decode: unknown value tag 0x{other:02x} at offset {pos}"),
        }
    }

    /// Decode a call expression/statement: opcode, callee, arg count, args. The
    /// argument count is folded into the `Call` unit.
    fn decode_call(&mut self, pos: usize) -> usize {
        let idx = self.emit(pos, UnitKind::Call { argc: 0 });
        let mut p = self.decode_value(pos + 1); // callee
        let argc = self.read_i32(p) as u32;
        p += 4;
        self.units[idx] = UnitKind::Call { argc };
        for _ in 0..argc {
            p = self.decode_value(p);
        }
        p
    }

    fn decode_object(&mut self, pos: usize) -> usize {
        let typ = self.read_i64(pos + 1);
        let props_len = self.read_i32(pos + 9);
        self.emit(pos, UnitKind::ObjHead { typ, props_len });
        let mut p = pos + 13;
        for _ in 0..props_len {
            p = self.decode_value(p); // key (a tag-7 string literal)
            p = self.decode_value(p); // value
        }
        p
    }

    fn decode_array(&mut self, pos: usize) -> usize {
        let len = self.read_i32(pos + 1);
        self.emit(pos, UnitKind::ArrHead { len });
        let mut p = pos + 5;
        for _ in 0..len {
            p = self.decode_value(p);
        }
        p
    }

    // ---- statements (mirror of `compile_ast`) -------------------------------

    fn decode_stmt_seq(&mut self, start: usize, end: usize) {
        let mut pos = start;
        while pos < end {
            pos = self.decode_stmt(pos);
        }
    }

    /// Decode one statement starting at `pos`; return the offset just past its
    /// entire extent (so the linear scan resumes at the next statement and
    /// never re-decodes an already-decoded body).
    fn decode_stmt(&mut self, pos: usize) -> usize {
        let tag = self.bytes[pos];
        match tag {
            0x15 => {
                let dest = self.read_i64(pos + 1) as usize;
                self.emit(pos, UnitKind::Jump(dest)); // byte offset → unit in relocate
                pos + 9
            }
            0x16 => {
                let idx = self.emit(pos, UnitKind::CondBranch { true_branch: 0, false_branch: 0 });
                let mut p = self.decode_value(pos + 1); // condition
                let tb = self.read_i64(p) as usize;
                p += 8;
                let fb = self.read_i64(p) as usize;
                p += 8;
                self.units[idx] = UnitKind::CondBranch { true_branch: tb, false_branch: fb };
                p
            }
            0x0d => self.decode_call(pos),
            // A bare expression statement whose value is discarded: a
            // short-circuit (`0xef`) or conditional (`0xee`). Decode the whole
            // expression so its (possibly side-effecting) units run as a unit.
            0xef | 0xee => self.decode_value(pos),
            0x14 => {
                self.emit(pos, UnitKind::Return);
                self.decode_value(pos + 1)
            }
            0x17 => {
                self.emit(pos, UnitKind::Continue);
                pos + 1
            }
            0x18 => {
                self.emit(pos, UnitKind::Break);
                pos + 1
            }
            0x10 => self.decode_if_chain(pos),
            0x11 => {
                // loop: opcode, condition, body_start, body_end, branch_after, body.
                let idx = self.emit(
                    pos,
                    UnitKind::Loop { body_start: 0, body_end: 0, branch_after: 0 },
                );
                let mut p = self.decode_value(pos + 1); // condition
                let body_start = self.read_i64(p) as usize;
                p += 8;
                let body_end = self.read_i64(p) as usize;
                p += 8;
                let branch_after = self.read_i64(p) as usize;
                p += 8;
                debug_assert_eq!(p, body_start);
                self.units[idx] = UnitKind::Loop { body_start, body_end, branch_after };
                self.decode_stmt_seq(body_start, body_end);
                body_end
            }
            0x12 => self.decode_switch(pos),
            0x1c => self.decode_destructure(pos),
            0x1d => {
                // try/catch: opcode, errName, body_start, body_end, catch_start,
                // catch_end, body, catch body.
                let (err_name, consumed) = self.read_str(pos + 1);
                let idx = self.emit(
                    pos,
                    UnitKind::TryHead {
                        body_start: 0,
                        body_end: 0,
                        catch_start: 0,
                        catch_end: 0,
                        err_name: Rc::from(err_name.as_str()),
                    },
                );
                let mut p = pos + 1 + consumed;
                let body_start = self.read_i64(p) as usize;
                p += 8;
                let body_end = self.read_i64(p) as usize;
                p += 8;
                let catch_start = self.read_i64(p) as usize;
                p += 8;
                let catch_end = self.read_i64(p) as usize;
                p += 8;
                debug_assert_eq!(p, body_start);
                if let UnitKind::TryHead { err_name, .. } = &self.units[idx] {
                    let err_name = err_name.clone();
                    self.units[idx] = UnitKind::TryHead {
                        body_start,
                        body_end,
                        catch_start,
                        catch_end,
                        err_name,
                    };
                }
                self.decode_stmt_seq(body_start, body_end);
                self.decode_stmt_seq(catch_start, catch_end);
                catch_end
            }
            0x1e => {
                self.emit(pos, UnitKind::Throw);
                self.decode_value(pos + 1)
            }
            0x13 => self.decode_funcdef(pos),
            0x0e => {
                // definition: 0x0e, 0x0b discriminator, name, value expression.
                let (name, consumed) = self.read_str(pos + 2);
                self.emit(pos, UnitKind::DefineVar(Rc::from(name.as_str())));
                self.decode_value(pos + 2 + consumed)
            }
            0x0f => {
                // assignment: 0x0f, discriminator (0x0b ident / 0x0c index), name,
                // [index expression], value expression.
                let disc = self.bytes[pos + 1];
                let kind = if disc == 0x0c { 2 } else { 1 };
                let (name, consumed) = self.read_str(pos + 2);
                self.emit(pos, UnitKind::AssignVar { name: Rc::from(name.as_str()), kind });
                let mut p = pos + 2 + consumed;
                if kind == 2 {
                    p = self.decode_value(p); // index expression
                }
                self.decode_value(p) // value expression
            }
            // `0x00` (empty body) and anything unknown: a no-op, exactly like the
            // interpreter's old fall-through arm.
            _ => {
                self.emit(pos, UnitKind::Nop);
                pos + 1
            }
        }
    }

    /// Decode one if/else-if/else chain starting at `pos`; return the offset
    /// just past the whole chain (its shared `branch_after`).
    fn decode_if_chain(&mut self, pos: usize) -> usize {
        let conditioned = self.bytes[pos + 1] == 0x01;
        let idx = self.emit(
            pos,
            UnitKind::IfHead {
                has_condition: conditioned,
                body_start: 0,
                body_end: 0,
                next: 0,
                branch_after: 0,
            },
        );
        let mut p = pos + 2;
        if conditioned {
            p = self.decode_value(p); // condition
        }
        let body_start = self.read_i64(p) as usize;
        p += 8;
        let body_end = self.read_i64(p) as usize;
        p += 8;
        // The conditioned form carries the "next arm" pointer; the unconditional
        // `else` does not, so reuse `branch_after` for `next` (it is never read).
        let next = if conditioned {
            let n = self.read_i64(p) as usize;
            p += 8;
            n
        } else {
            0
        };
        let branch_after = self.read_i64(p) as usize;
        p += 8;
        debug_assert_eq!(p, body_start);
        let next = if conditioned { next } else { branch_after };
        self.units[idx] = UnitKind::IfHead {
            has_condition: conditioned,
            body_start,
            body_end,
            next,
            branch_after,
        };
        self.decode_stmt_seq(body_start, body_end);
        // The trailing else-if / else arm (if any) lives between this arm's body
        // and the chain's shared end.
        if body_end < branch_after {
            self.decode_if_chain(body_end);
        }
        branch_after
    }

    fn decode_switch(&mut self, pos: usize) -> usize {
        let idx = self.emit(pos, UnitKind::Switch { branch_after: 0, cases: Rc::new(vec![]) });
        let mut p = self.decode_value(pos + 1); // switch value
        let branch_after = self.read_i64(p) as usize;
        p += 8;
        let case_count = self.read_i64(p);
        p += 8;
        let mut cases = Vec::with_capacity(case_count.max(0) as usize);
        for _ in 0..case_count {
            p = self.decode_value(p); // case value (an expression, evaluated at run time)
            let case_start = self.read_i64(p) as usize;
            p += 8;
            let case_end = self.read_i64(p) as usize;
            p += 8;
            debug_assert_eq!(p, case_start);
            cases.push((case_start, case_end)); // byte offsets; relocate -> unit indices
            self.decode_stmt_seq(case_start, case_end);
            p = case_end;
        }
        self.units[idx] = UnitKind::Switch { branch_after, cases: Rc::new(cases) };
        branch_after
    }

    /// Decode a destructuring statement: `[0x1c][flags][binding count]` then a
    /// fixed metadata record per binding, then the source value expression, then
    /// one default expression per binding that declares a default (in binding
    /// order). Mirrors `compiler::serialize_destructure`.
    fn decode_destructure(&mut self, pos: usize) -> usize {
        let is_array = self.bytes[pos + 1] == 1;
        let count = self.read_i32(pos + 2) as usize;
        let mut p = pos + 6;
        let mut bindings = Vec::with_capacity(count);
        let mut num_defaults = 0usize;
        for _ in 0..count {
            let flags = self.bytes[p];
            p += 1;
            let has_default = flags & 1 != 0;
            let is_rest = flags & 2 != 0;
            let is_hole = flags & 4 != 0;
            if has_default {
                num_defaults += 1;
            }
            if is_hole {
                bindings.push(DestructureBinding {
                    name: String::new(),
                    key: String::new(),
                    has_default,
                    is_rest,
                    is_hole,
                });
                continue;
            }
            let mut key = String::new();
            if !is_array {
                let (k, consumed) = self.read_str(p);
                key = k;
                p += consumed;
            }
            let (name, consumed) = self.read_str(p);
            p += consumed;
            bindings.push(DestructureBinding { name, key, has_default, is_rest, is_hole });
        }
        let value_count = 1 + num_defaults;
        self.emit(pos, UnitKind::Destructure {
            plan: Rc::new(DestructurePlan { is_array, bindings, value_count }),
        });
        // Source expression, then each default expression, all emitted as value
        // units the executor evaluates in order.
        p = self.decode_value(p);
        for _ in 0..num_defaults {
            p = self.decode_value(p);
        }
        p
    }

    fn decode_funcdef(&mut self, pos: usize) -> usize {
        let mut p = pos + 1;
        let (name, consumed) = self.read_str(p);
        p += consumed;
        let param_count = self.read_i32(p) as usize;
        p += 4;
        let mut params = Vec::with_capacity(param_count);
        for _ in 0..param_count {
            let (n, c) = self.read_str(p);
            params.push(n);
            p += c;
        }
        let free_count = self.read_i32(p) as usize;
        p += 4;
        let mut frees = Vec::with_capacity(free_count);
        for _ in 0..free_count {
            let (n, c) = self.read_str(p);
            frees.push(n);
            p += c;
        }
        let func_start = self.read_i64(p) as usize;
        p += 8;
        let func_end = self.read_i64(p) as usize;
        p += 8;
        debug_assert_eq!(p, func_start);
        // start/end stashed as byte offsets; `relocate` turns them into unit
        // indices.
        self.emit(
            pos,
            UnitKind::FuncDef {
                name: Rc::from(name.as_str()),
                params: Rc::new(params),
                frees: Rc::new(frees),
                start: func_start,
                end: func_end,
            },
        );
        self.decode_stmt_seq(func_start, func_end);
        func_end
    }
}
