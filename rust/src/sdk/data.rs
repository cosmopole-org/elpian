use std::cell::RefCell;
use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};
use std::rc::Rc;

/// Append `s` to `out` as a JSON-encoded string literal (with surrounding
/// quotes). Mirrors the helper in `vm.rs`; kept inside `data.rs` so the
/// streaming `stringify_into` family can escape map keys and string values
/// without rebuilding a temporary `String` per element.
fn push_json_string(out: &mut String, s: &str) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{08}' => out.push_str("\\b"),
            '\u{0c}' => out.push_str("\\f"),
            c if (c as u32) < 0x20 => {
                use std::fmt::Write as _;
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

/// A fast, non-cryptographic hasher (the `FxHash` algorithm rustc itself uses)
/// for the VM's internal string-keyed maps. Variable scopes and object fields
/// are looked up by name on *every* access, and the default `SipHash` — built
/// for HashDoS resistance, not speed — showed up as ~13% of instructions when
/// profiling a frame. These maps are never exposed to untrusted key streams, so
/// a small, branch-light hash optimised for short keys is the right trade.
#[derive(Default)]
pub struct FxHasher {
    hash: u64,
}

const FX_SEED: u64 = 0x51_7c_c1_b7_27_22_0a_95;

impl FxHasher {
    #[inline]
    fn add(&mut self, i: u64) {
        self.hash = (self.hash.rotate_left(5) ^ i).wrapping_mul(FX_SEED);
    }
}

impl Hasher for FxHasher {
    #[inline]
    fn write(&mut self, mut bytes: &[u8]) {
        while bytes.len() >= 8 {
            let mut buf = [0u8; 8];
            buf.copy_from_slice(&bytes[..8]);
            self.add(u64::from_le_bytes(buf));
            bytes = &bytes[8..];
        }
        if bytes.len() >= 4 {
            let mut buf = [0u8; 4];
            buf.copy_from_slice(&bytes[..4]);
            self.add(u32::from_le_bytes(buf) as u64);
            bytes = &bytes[4..];
        }
        for &b in bytes {
            self.add(b as u64);
        }
    }
    #[inline]
    fn finish(&self) -> u64 {
        self.hash
    }
}

/// String-keyed map of VM values (scope memory, object fields), hashed with
/// [`FxHasher`] instead of the default `SipHash`.
pub type ValMap = HashMap<String, Val, BuildHasherDefault<FxHasher>>;

/// The concrete payload of a [`Val`]. Replaces the previous
/// `Box<dyn Any>`: a scalar now lives *inline* in the enum (no per-value `Box`
/// allocation and no dynamic downcast on every read), while the reference types
/// keep their own inner `Rc<RefCell<…>>` so shared-mutation identity is exactly
/// as before. Removing the inner `Box` halves the allocations behind every
/// number/bool the VM produces — and the VM produces millions per frame — which
/// is the engine's dominant cost.
#[derive(Clone)]
pub enum Payload {
    Null,
    I16(i16),
    I32(i32),
    I64(i64),
    F32(f32),
    F64(f64),
    Bool(bool),
    Str(String),
    Obj(Rc<RefCell<Object>>),
    Arr(Rc<RefCell<Array>>),
    Func(Rc<RefCell<Function>>),
}

impl From<i16> for Payload {
    fn from(v: i16) -> Self {
        Payload::I16(v)
    }
}
impl From<i32> for Payload {
    fn from(v: i32) -> Self {
        Payload::I32(v)
    }
}
impl From<i64> for Payload {
    fn from(v: i64) -> Self {
        Payload::I64(v)
    }
}
impl From<f32> for Payload {
    fn from(v: f32) -> Self {
        Payload::F32(v)
    }
}
impl From<f64> for Payload {
    fn from(v: f64) -> Self {
        Payload::F64(v)
    }
}
impl From<bool> for Payload {
    fn from(v: bool) -> Self {
        Payload::Bool(v)
    }
}
impl From<String> for Payload {
    fn from(v: String) -> Self {
        Payload::Str(v)
    }
}
impl From<&str> for Payload {
    fn from(v: &str) -> Self {
        Payload::Str(v.to_string())
    }
}
impl From<Rc<RefCell<Object>>> for Payload {
    fn from(v: Rc<RefCell<Object>>) -> Self {
        Payload::Obj(v)
    }
}
impl From<Rc<RefCell<Array>>> for Payload {
    fn from(v: Rc<RefCell<Array>>) -> Self {
        Payload::Arr(v)
    }
}
impl From<Rc<RefCell<Function>>> for Payload {
    fn from(v: Rc<RefCell<Function>>) -> Self {
        Payload::Func(v)
    }
}

#[derive(Clone)]
pub struct Val {
    pub typ: i64,
    pub data: Payload,
}

impl std::fmt::Debug for Val {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Val(typ={}, {})", self.typ, self.stringify())
    }
}

unsafe impl Send for Val {}

impl Val {
    pub fn new(typ: i64, data: Payload) -> Self {
        Val { typ, data }
    }
    pub fn stringify(&self) -> String {
        // Heuristic capacity: arrays/objects amortize across many fields, so we
        // pre-grow the buffer a bit to avoid the first few doublings. Numbers
        // and bools stay tiny.
        let mut out = String::with_capacity(match self.typ {
            8 | 9 => 64,
            _ => 16,
        });
        self.stringify_into(&mut out);
        out
    }
    /// Append this value's JSON encoding to `out`. Avoids the per-element
    /// `String` allocation `stringify()` would do for arrays / objects, which
    /// matters because the host-call envelope's `gpu.submit` payload is
    /// dominated by a long instance buffer (`data_f32: [...]`) re-emitted
    /// every frame. Writing straight into the envelope's buffer keeps the
    /// frame on a single, growing allocation instead of thousands of throw-
    /// away ones.
    pub fn stringify_into(&self, out: &mut String) {
        use std::fmt::Write as _;
        match self.typ {
            1 => { let _ = write!(out, "{}", self.as_i16()); }
            2 => { let _ = write!(out, "{}", self.as_i32()); }
            3 => { let _ = write!(out, "{}", self.as_i64()); }
            4 => { let _ = write!(out, "{}", self.as_f32()); }
            5 => { let _ = write!(out, "{}", self.as_f64()); }
            6 => out.push_str(if self.as_bool() { "true" } else { "false" }),
            7 => push_json_string(out, &self.as_string()),
            8 => self.as_object().borrow().data.stringify_into(out),
            9 => self.as_array().borrow().stringify_into(out),
            10 => {
                let f = self.as_func();
                let n = &f.borrow().name;
                push_json_string(out, n);
            }
            _ => out.push_str("\"[undefined]\""),
        }
    }
    /// The value's *display* (human-readable) string coercion — the form used by
    /// interpolated / template strings and any front-end "value to text"
    /// operation. Unlike [`stringify`], a string coerces to itself with **no**
    /// surrounding quotes and null coerces to the word `null`; numbers, booleans
    /// and functions render as their bare text, while objects and arrays fall
    /// back to their structural (JSON) encoding since they have no shorter
    /// canonical text. This is deliberately language-neutral: it is the VM's own
    /// notion of "the text of a value", not any one language's `toString`.
    pub fn to_display(&self) -> String {
        match self.typ {
            0 => "null".to_string(),
            7 => self.as_string(),
            8 | 9 => self.stringify(),
            10 => self.as_func().borrow().name.clone(),
            _ => {
                let mut out = String::new();
                self.stringify_into(&mut out);
                out
            }
        }
    }
    fn clone_data(&self) -> Self {
        // Deep-copy scalars and strings; objects and arrays get a *fresh* inner
        // `Rc<RefCell<…>>` with recursively cloned contents (value semantics);
        // functions share their `Rc` (as before — a function value is immutable).
        let payload = match &self.data {
            Payload::Null => Payload::Null,
            Payload::I16(v) => Payload::I16(*v),
            Payload::I32(v) => Payload::I32(*v),
            Payload::I64(v) => Payload::I64(*v),
            Payload::F32(v) => Payload::F32(*v),
            Payload::F64(v) => Payload::F64(*v),
            Payload::Bool(v) => Payload::Bool(*v),
            Payload::Str(s) => Payload::Str(s.clone()),
            Payload::Obj(o) => Payload::Obj(Rc::new(RefCell::new(o.borrow().clone_object()))),
            Payload::Arr(a) => Payload::Arr(Rc::new(RefCell::new(a.borrow().clone_arr()))),
            Payload::Func(func) => Payload::Func(func.clone()),
        };
        Val {
            typ: self.typ,
            data: payload,
        }
    }
    pub fn as_i16(&self) -> i16 {
        match &self.data {
            Payload::I16(v) => *v,
            _ => panic!("as_i16 on non-i16 value (typ {})", self.typ),
        }
    }
    pub fn as_i32(&self) -> i32 {
        match &self.data {
            Payload::I32(v) => *v,
            _ => panic!("as_i32 on non-i32 value (typ {})", self.typ),
        }
    }
    pub fn as_i64(&self) -> i64 {
        match &self.data {
            Payload::I64(v) => *v,
            _ => panic!("as_i64 on non-i64 value (typ {})", self.typ),
        }
    }
    pub fn as_f32(&self) -> f32 {
        match &self.data {
            Payload::F32(v) => *v,
            _ => panic!("as_f32 on non-f32 value (typ {})", self.typ),
        }
    }
    pub fn as_f64(&self) -> f64 {
        match &self.data {
            Payload::F64(v) => *v,
            _ => panic!("as_f64 on non-f64 value (typ {})", self.typ),
        }
    }
    pub fn as_bool(&self) -> bool {
        match &self.data {
            Payload::Bool(v) => *v,
            _ => panic!("as_bool on non-bool value (typ {})", self.typ),
        }
    }
    /// Truthiness: the value's boolean coercion used by `if`/`while`/
    /// `for` conditions, `!`, `&&`/`||` and the ternary. `null`/`undefined`, the
    /// numeric zeros, an empty string and `false` are falsy; every object, array,
    /// function and non-empty string (and any non-zero number) is truthy.
    pub fn truthy(&self) -> bool {
        match &self.data {
            Payload::Null => false,
            Payload::Bool(v) => *v,
            Payload::I16(v) => *v != 0,
            Payload::I32(v) => *v != 0,
            Payload::I64(v) => *v != 0,
            Payload::F32(v) => *v != 0.0 && !v.is_nan(),
            Payload::F64(v) => *v != 0.0 && !v.is_nan(),
            Payload::Str(s) => !s.is_empty(),
            Payload::Obj(_) | Payload::Arr(_) | Payload::Func(_) => true,
        }
    }
    pub fn as_string(&self) -> String {
        match &self.data {
            Payload::Str(s) => s.clone(),
            _ => panic!("as_string on non-string value (typ {})", self.typ),
        }
    }
    pub fn as_object(&self) -> Rc<RefCell<Object>> {
        match &self.data {
            Payload::Obj(o) => o.clone(),
            _ => panic!("as_object on non-object value (typ {})", self.typ),
        }
    }
    pub fn as_array(&self) -> Rc<RefCell<Array>> {
        match &self.data {
            Payload::Arr(a) => a.clone(),
            _ => panic!("as_array on non-array value (typ {})", self.typ),
        }
    }
    pub fn as_func(&self) -> Rc<RefCell<Function>> {
        match &self.data {
            Payload::Func(func) => func.clone(),
            _ => panic!("as_func on non-func value (typ {})", self.typ),
        }
    }
    pub fn is_empty(&self) -> bool {
        self.typ == 0
    }
    /// Approximate live footprint of this value in bytes, used by the resource
    /// governor to bound a guest's heap. It is a deliberately shallow, stable
    /// estimate (the value's own header plus its inline payload); container
    /// elements are charged as they are themselves allocated, so a deep tree is
    /// accounted for incrementally rather than re-walked here.
    pub fn approx_size(&self) -> u64 {
        const HEADER: u64 = 24; // Rc + RefCell + enum tag, amortised.
        HEADER
            + match self.typ {
                1 | 6 => 2,
                2 | 4 => 4,
                3 | 5 => 8,
                7 => self.as_string().len() as u64 + 16,
                8 => {
                    let o = self.as_object();
                    let b = o.borrow();
                    b.data
                        .data
                        .keys()
                        .map(|k| k.len() as u64 + 16)
                        .sum::<u64>()
                        + 16
                }
                9 => self.as_array().borrow().data.len() as u64 * 8 + 16,
                10 => 48,
                _ => 0,
            }
    }
}

pub struct ValGroup {
    pub data: ValMap,
}

impl ValGroup {
    pub fn new_empty() -> Self {
        ValGroup {
            data: ValMap::default(),
        }
    }
    pub fn new(data: ValMap) -> Self {
        ValGroup { data }
    }
    fn clone_data(&self) -> Self {
        let mut copied: ValMap = ValMap::default();
        for (k, v) in self.data.iter() {
            copied.insert(k.clone(), v.clone_data());
        }
        ValGroup::new(copied)
    }
    pub fn stringify(&self) -> String {
        let mut out = String::with_capacity(self.data.len() * 24 + 4);
        self.stringify_into(&mut out);
        out
    }
    /// Append this group's JSON encoding to `out` (the streaming counterpart of
    /// [`stringify`]). Keys are emitted as JSON strings (correctly escaped)
    /// instead of being printed verbatim — the previous form would have
    /// produced invalid JSON for any key containing a quote, backslash, or
    /// control character; the streaming path makes that correct without
    /// introducing per-key allocation.
    pub fn stringify_into(&self, out: &mut String) {
        out.push('{');
        for (index, (k, v)) in self.data.iter().enumerate() {
            if index > 0 {
                out.push_str(", ");
            } else {
                out.push(' ');
            }
            push_json_string(out, k);
            out.push_str(": ");
            v.stringify_into(out);
        }
        out.push_str(" }");
    }
}

pub struct Blueprint {
    pub typ_id: i64,
    pub def_props: ValGroup,
}

impl Blueprint {
    pub fn new(typ_id: i64, def_props: ValGroup) -> Self {
        Blueprint { typ_id, def_props }
    }
    pub fn new_instance(&self) -> Object {
        Object::new(self.typ_id, self.def_props.clone_data())
    }
}

pub struct Object {
    pub typ: i64,
    pub data: ValGroup,
}

impl Object {
    pub fn new(typ: i64, data: ValGroup) -> Self {
        Object { typ, data }
    }
    pub fn clone_object(&self) -> Self {
        Object::new(self.typ, self.data.clone_data())
    }
    pub fn stringify(&self) -> String {
        self.data.stringify()
    }
}

pub struct Array {
    pub data: Vec<Val>,
}

impl Array {
    pub fn new_empty() -> Self {
        Array { data: vec![] }
    }
    pub fn new(data: Vec<Val>) -> Self {
        Array { data }
    }
    pub fn clone_arr(&self) -> Self {
        Array::new(self.data.iter().map(|item| item.clone_data()).collect())
    }
    pub fn stringify(&self) -> String {
        // Pre-size for a typical numeric array (~12 chars per number including
        // separator); strings and nested arrays grow on demand. Significantly
        // reduces re-allocs for the per-frame instance buffer.
        let mut out = String::with_capacity(self.data.len() * 12 + 2);
        self.stringify_into(&mut out);
        out
    }
    /// Streaming-append counterpart of [`stringify`]. The instance buffer the
    /// material kit re-submits every frame is a `Vec<Val>` of thousands of
    /// floats — its `stringify()` is the single largest allocation per frame.
    /// Writing each element straight into the host-call envelope's buffer
    /// avoids that allocation entirely.
    pub fn stringify_into(&self, out: &mut String) {
        out.push('[');
        for (index, v) in self.data.iter().enumerate() {
            if index > 0 {
                out.push_str(", ");
            }
            v.stringify_into(out);
        }
        out.push(']');
    }
}

#[derive(Clone)]
pub struct Function {
    pub name: String,
    pub start: usize,
    pub end: usize,
    /// Declared parameter names. `Rc`-wrapped because the call path clones this
    /// list for every invocation (to seed the frame); sharing it makes that a
    /// pointer bump rather than a deep `Vec<String>` copy.
    pub params: Rc<Vec<String>>,
    /// Captured lexical environment (closure upvalues). When a function value is
    /// produced inside another function's body, the enclosing locals reachable
    /// at that point are snapshotted here as `name -> Val`. The snapshot shares
    /// the *same* `Rc`-backed values, so reference types (objects, arrays, cells)
    /// stay live for exactly as long as some closure references them and mutate
    /// in lock-step — this is the closure's environment lifecycle, managed for
    /// free by reference counting rather than a tracing collector. `None` means
    /// a plain top-level function with nothing to close over.
    pub captured: Option<Rc<RefCell<ValGroup>>>,
    /// The receiver a *bound method* runs against. When a class method is read
    /// off an instance (`obj.method`), the shared method function is wrapped with
    /// `this_arg = Some(obj)`; the call path then seeds `this` into the frame.
    /// `None` for ordinary functions and closures. Carrying just the receiver
    /// (rather than cloning the whole function into a fresh closure) keeps method
    /// dispatch allocation-light on the hot per-frame path.
    pub this_arg: Option<Val>,
}

impl std::fmt::Debug for Function {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Function")
            .field("name", &self.name)
            .field("start", &self.start)
            .field("end", &self.end)
            .field("params", &self.params)
            .field("closure", &self.captured.is_some())
            .finish()
    }
}

impl Function {
    pub fn new(name: String, start: usize, end: usize, params: Vec<String>) -> Self {
        Function {
            name,
            start,
            end,
            params: Rc::new(params),
            captured: None,
            this_arg: None,
        }
    }
    /// A function value that closes over `captured`.
    pub fn new_closure(
        name: String,
        start: usize,
        end: usize,
        params: Vec<String>,
        captured: Rc<RefCell<ValGroup>>,
    ) -> Self {
        Function {
            name,
            start,
            end,
            params: Rc::new(params),
            captured: Some(captured),
            this_arg: None,
        }
    }
    pub fn clone_func(&self) -> Self {
        Function {
            name: self.name.clone(),
            start: self.start,
            end: self.end,
            params: self.params.clone(),
            captured: self.captured.clone(),
            this_arg: self.this_arg.clone(),
        }
    }
    /// Wrap this (shared, top-level) method function as a method bound to
    /// `receiver`, sharing the parameter list and body by pointer. Cheap: one
    /// `Function` allocation plus reference-count bumps — no deep clones.
    pub fn bind(&self, receiver: Val) -> Self {
        Function {
            name: String::new(),
            start: self.start,
            end: self.end,
            params: self.params.clone(),
            captured: None,
            this_arg: Some(receiver),
        }
    }
}
