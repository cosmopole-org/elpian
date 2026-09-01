use std::{cell::RefCell, rc::Rc};

use crate::sdk::data::{Payload, Val, ValGroup, ValMap};

pub struct Scope {
    pub tag: String,
    pub memory: Rc<RefCell<ValGroup>>,
    pub frozen_start: usize,
    pub frozen_end: usize,
    pub frozen_pointer: usize,
}
impl Scope {
    pub fn new(
        tag: String,
        initial_pointer: usize,
        frozen_start: usize,
        frozen_end: usize,
    ) -> Self {
        Scope {
            tag,
            memory: Rc::new(RefCell::new(ValGroup::new_empty())),
            frozen_pointer: initial_pointer,
            frozen_start,
            frozen_end,
        }
    }
    pub fn new_with_args(
        tag: String,
        initial_pointer: usize,
        frozen_start: usize,
        frozen_end: usize,
        args: ValMap,
    ) -> Self {
        Scope {
            tag,
            memory: Rc::new(RefCell::new(ValGroup::new(args))),
            frozen_pointer: initial_pointer,
            frozen_start,
            frozen_end,
        }
    }
    pub fn update_frozen_pointer(&mut self, pointer: usize) {
        self.frozen_pointer = pointer;
    }
    pub fn update_initial_pointer_info(
        &mut self,
        pointer: usize,
        frozen_start: usize,
        frozen_end: usize,
    ) {
        self.frozen_pointer = pointer;
        self.frozen_start = frozen_start;
        self.frozen_end = frozen_end;
    }
    pub fn find_val(&self, name: &str) -> Val {
        self.get_val(name).unwrap_or_else(|| Val::new(0, Payload::Null))
    }
    /// Presence-based read: `Some` for any binding — **including one whose value
    /// is the first-class null** — and `None` only when the name is not bound in
    /// this scope. Distinguishing "bound to null" from "unbound" matters now
    /// that null is an ordinary value (`var x = null;` must shadow an outer `x`
    /// and a like-named builtin exactly as any other binding does).
    pub fn get_val(&self, name: &str) -> Option<Val> {
        self.memory.borrow().data.get(name).cloned()
    }
    pub fn update_val(&mut self, name: String, val: Val) -> bool {
        let mut v = self.memory.borrow_mut();
        if v.data.contains_key(&name) {
            v.data.insert(name, val);
            return true;
        }
        false
    }
    pub fn define_val(&mut self, name: String, val: Val) {
        let mut v = self.memory.borrow_mut();
        v.data.insert(name, val);
    }
}

pub struct Context {
    pub memory: Vec<Rc<RefCell<Scope>>>,
}

impl Context {
    pub fn new() -> Self {
        Context { memory: vec![] }
    }
    pub fn push_scope(
        &mut self,
        tag: String,
        inital_pointer: usize,
        frozen_start: usize,
        frozen_end: usize,
    ) {
        self.memory.push(Rc::new(RefCell::new(Scope::new(
            tag,
            inital_pointer,
            frozen_start,
            frozen_end,
        ))));
    }
    pub fn push_scope_with_args(
        &mut self,
        tag: String,
        inital_pointer: usize,
        frozen_start: usize,
        frozen_end: usize,
        args: ValMap,
    ) {
        self.memory.push(Rc::new(RefCell::new(Scope::new_with_args(
            tag,
            inital_pointer,
            frozen_start,
            frozen_end,
            args,
        ))));
    }
    pub fn pop_scope(&mut self) {
        self.memory.pop();
    }
    pub fn get_scope(&mut self, index: usize) -> Rc<RefCell<Scope>> {
        self.memory.get(index).unwrap().clone()
    }
    /// Resolve `name` **lexically**: search the current function's own scope frames
    /// (its `funcBody` plus any nested block/loop scopes stacked on top), then the
    /// global scope — but **not** the caller frames in between, which are not
    /// lexically visible to the callee. A closure that genuinely needs an enclosing
    /// local has already captured it (see `capture_named`), so it lands in the
    /// callee's own `funcBody` frame and is found here.
    ///
    /// This is both more correct (JS is lexically, not dynamically, scoped) and far
    /// cheaper: identifier resolution previously walked the **entire** dynamic call
    /// stack (measured at ~11 hash probes per lookup, up to 79 deep, on the demo's
    /// hot paint loop). Now it walks only the active function's own (shallow) scope
    /// nest plus one global probe, so resolving a global or builtin is O(1)-ish
    /// regardless of recursion depth — the single biggest per-frame cost in the
    /// renderer's deep widget/paint recursion.
    pub fn find_val_globally(&mut self, name: &str) -> Val {
        self.lookup_val_globally(name)
            .unwrap_or_else(|| Val::new(0, Payload::Null))
    }
    /// The presence-based form of [`find_val_globally`]: `None` means the name
    /// is bound in no lexically visible scope (so the executor may fall back to
    /// a builtin), while `Some(null)` is a real binding whose current value is
    /// null — which shadows outer bindings and builtins like any other value.
    pub fn lookup_val_globally(&mut self, name: &str) -> Option<Val> {
        let mem = &self.memory;
        let mut i = mem.len();
        while i > 0 {
            i -= 1;
            let (val, is_func_body) = {
                let s = mem[i].borrow();
                (s.get_val(name), s.tag == "funcBody")
            };
            if let Some(v) = val {
                return Some(v);
            }
            if is_func_body {
                // Reached the current function's frame. Caller frames below are
                // out of lexical scope; probe the global scope directly, then stop.
                if i > 0 {
                    return mem[0].borrow().get_val(name);
                }
                return None;
            }
        }
        None
    }
    pub fn define_val_globally(&mut self, name: String, val: Val) {
        self.memory.last().unwrap().borrow_mut().define_val(name, val);
    }
    pub fn update_val_globally(&mut self, name: String, val: Val) {
        // Assignment resolves its target with the same **lexical** rule as reads
        // (`find_val_globally`): the first of the current function's own scopes (or
        // the global scope) that already binds `name` takes the new value; caller
        // frames in between are not lexically visible and are skipped. Probe with a
        // borrow (no clone of name/val) and move the owned pair into exactly one
        // `insert`. A name bound nowhere becomes a fresh binding in the top scope.
        let mut i = self.memory.len();
        while i > 0 {
            i -= 1;
            let is_func_body = {
                let scope = self.memory[i].borrow();
                if scope.memory.borrow().data.contains_key(&name) {
                    scope.memory.borrow_mut().data.insert(name, val);
                    return;
                }
                scope.tag == "funcBody"
            };
            if is_func_body {
                if i > 0 {
                    let g = self.memory[0].borrow();
                    if g.memory.borrow().data.contains_key(&name) {
                        g.memory.borrow_mut().data.insert(name, val);
                        return;
                    }
                }
                self.memory.last().unwrap().borrow_mut().define_val(name, val);
                return;
            }
        }
        self.memory.last().unwrap().borrow_mut().define_val(name, val);
    }
    pub fn find_val_in_last_scope(&mut self, name: &str) -> Val {
        self.memory.last().unwrap().borrow().find_val(name)
    }
    pub fn find_val_in_first_scope(&mut self, name: &str) -> Val {
        self.memory.first().unwrap().borrow().find_val(name)
    }
}
