//! The interpreter: a pausing bytecode executor.
//!
//! The operation vocabulary it runs lives in [`operations`]; the arithmetic and
//! comparison semantics live in [`arithmetic`].

mod arithmetic;
mod governance;
mod operations;

use operations::{
    apply_destructure, flatten_spread, is_null, make_spread_marker, value_is_type, Arithmetic,
    ArrayExpr, AssignVariable, CallFunction, CastOp, CondBranch, ConditionalOp, DefineVariable,
    DestructureOp, DummyOp, IfStmt, IndexerValue, LogicalOp, LoopStmt, NotValue, ObjectExpr,
    ReturnValue, SpreadOp, SwitchStmt, TemplateExpr, ThrowValue, TryFrame, TypeTestOp,
    SPREAD_KEY_MARKER,
};
pub use operations::{ExecStates, Operation, OperationTypes, StateData};

use crate::sdk::{
    capabilities::CapabilitySet,
    context::Context,
    data::{ty, Array, Function, Object, Payload, Val, ValGroup, ValMap},
    lifecycle::ExecControl,
    limits::{Governor, ResourceLimits},
    program::{DecodedProgram, LogicalKind, UnitKind},
    stdlib,
    type_methods::{self, CoreType, Dispatch},
};
use core::panic;
use std::{cell::RefCell, rc::Rc};

use std::vec;

pub struct Executor {
    executor_id: i16,
    /// Program counter: an index into [`DecodedProgram::units`] (not a byte
    /// offset). The interpreter advances it one unit at a time and branches by
    /// assigning a target unit index directly.
    pointer: usize,
    /// One past the last unit of the range currently executing (the top-level
    /// program, or a function/control body). The step loop stops when
    /// `pointer == end_at`.
    end_at: usize,
    ctx: Context,
    /// The program decoded once into an in-memory list of operation objects,
    /// with all branch targets pre-translated to unit indices. The raw bytecode
    /// is not retained — the interpreter traverses these units directly. See
    /// `program.rs`.
    prog: DecodedProgram,
    cb_counter: i64,
    pending_func_result_value: Val,
    registers: Vec<Box<dyn Operation>>,
    run_cb_id: i64,
    exec_globally: bool,
    reserved_host_call: Option<(u8, i64, Val)>,
    pub processing: bool,
    /// Resource governor (instruction / memory / storage / call-depth budgets).
    governor: Governor,
    /// Host-togglable capabilities gating every `askHost` side effect.
    capabilities: CapabilitySet,
    /// Host-driven pause / resume / terminate control.
    control: ExecControl,
    /// Set when `run_from` suspended this turn because of a host pause request,
    /// so `single_thread_operation` reports the instance as paused (not done).
    paused_out: bool,
    /// A fatal trap (limit overrun or uncaught error) that ended the instance.
    /// Once set, the instance is terminated and reports this reason to the host.
    trap: Option<String>,
    /// The live `try` regions, innermost last. A thrown value transfers control
    /// to the innermost frame's catch body (unwinding scopes and registers back
    /// to the depths recorded at `try` entry); with no frame the throw is a trap.
    try_stack: Vec<TryFrame>,
    /// This instance's `random` stream state (xorshift64*).
    ///
    /// Held here rather than in the thread-local the builtin reads, so the
    /// stream belongs to the instance and not to whichever thread ran it. Every
    /// turn swaps it onto the thread on entry and back off on exit — see
    /// [`Executor::with_rng_installed`].
    rng_state: u64,
}

impl Executor {
    /// Build an executor over `program`.
    ///
    /// There is deliberately no host-API allowlist parameter. One used to be
    /// threaded down from `api::all_host_apis()`, stored in an `_allowed_api`
    /// map, and never read — so it gated nothing, and every `askHost` name
    /// reached the host whether or not it appeared in that list. What actually
    /// gates a host call is the capability set (see the `askHost` arm of the
    /// run loop), which resolves *any* name through `Capability::for_api` and
    /// so needs no list to work.
    pub fn create_in_single_thread(program: Vec<u8>, exec_id: i16) -> Self {
        // Decode the bytecode once into the in-memory unit list; the raw bytes
        // are not kept past this point.
        let prog = DecodedProgram::decode(&program);
        let end_at = prog.units.len();
        Executor {
            executor_id: exec_id,
            pointer: 0,
            end_at,
            ctx: Context::new(),
            prog,
            cb_counter: 0,
            pending_func_result_value: Val::new(254, Payload::Null),
            registers: vec![],
            run_cb_id: 0,
            exec_globally: false,
            reserved_host_call: None,
            processing: false,
            governor: Governor::new(ResourceLimits::unlimited()),
            capabilities: CapabilitySet::allow_all(),
            control: ExecControl::new(),
            paused_out: false,
            trap: None,
            try_stack: Vec::new(),
            rng_state: crate::sdk::stdlib::RNG_DEFAULT_SEED,
        }
    }

    /// A clone of this instance's execution-control flag.
    ///
    /// The point of handing it out is that the holder can flip it *without*
    /// going through this executor — no `RefCell` borrow, no registry lock — so
    /// a host can stop a guest that is currently spinning inside a turn.
    pub fn control_handle(&self) -> crate::sdk::lifecycle::ExecControl {
        self.control.clone()
    }

    /// Run `body` with this instance's RNG stream installed on the current
    /// thread, restoring the previous occupant afterwards.
    ///
    /// `stdlib::invoke` reaches the `random` builtin from call sites that hold
    /// no executor, so the stream cannot simply be read out of `self` at the
    /// point of use. Swapping it on for the duration of a turn gets the same
    /// result: `random` sees this instance's state and nothing else's, whichever
    /// thread the turn runs on, and a `seedRandom` performed during the turn is
    /// carried back into `self` on the way out.
    ///
    /// The restore also runs on unwind, so a guest that traps mid-turn cannot
    /// strand its state on the thread for the next instance to inherit.
    fn with_rng_installed<R>(&mut self, body: impl FnOnce(&mut Self) -> R) -> R {
        /// Puts the previous occupant back if the turn unwinds.
        struct Restore(u64);
        impl Drop for Restore {
            fn drop(&mut self) {
                crate::sdk::stdlib::swap_rng_state(self.0);
            }
        }
        let guard = Restore(crate::sdk::stdlib::swap_rng_state(self.rng_state));
        let out = body(self);
        // Normal exit: take our advanced state back and restore the previous
        // occupant in the same swap, then defuse the guard.
        self.rng_state = crate::sdk::stdlib::swap_rng_state(guard.0);
        std::mem::forget(guard);
        out
    }

    /// After `run_from` returns, surface a host-driven stop (trap / terminate /
    /// pause) as the operation result, short-circuiting the normal
    /// done/host-call detection. Returns `None` when execution stopped for an
    /// ordinary reason (completion or a pending host call).
    fn control_status(&mut self, cb_id: i64) -> Option<(u8, i64, Val)> {
        if self.trap.is_some() || self.control.is_terminated() {
            self.processing = false;
            // Status 0x06 = terminated/trapped; payload is the reason string
            // (empty for a clean host-ordered terminate).
            let msg = self.trap.clone().unwrap_or_default();
            return Some((0x06, cb_id, Val::new(ty::STRING, Payload::from(msg))));
        }
        if self.paused_out {
            self.processing = false;
            // Status 0x05 = paused; the continuation is preserved for `resume`.
            return Some((0x05, cb_id, Val::new(253, Payload::Null)));
        }
        None
    }
    /// Drive one turn of this instance. Every entry into guest code goes
    /// through here, which is what makes it the right place to install the
    /// instance's RNG stream (see [`Executor::with_rng_installed`]).
    pub fn single_thread_operation(
        &mut self,
        op_code: u8,
        cb_id: i64,
        payload: Val,
    ) -> (u8, i64, Val) {
        self.with_rng_installed(move |this| {
            this.single_thread_operation_inner(op_code, cb_id, payload)
        })
    }

    fn single_thread_operation_inner(
        &mut self,
        op_code: u8,
        cb_id: i64,
        payload: Val,
    ) -> (u8, i64, Val) {
        match op_code {
            0x01 => {
                // println!("executor: run_func called");
                self.run_cb_id = cb_id;
                self.governor.begin_turn();
                self.paused_out = false;
                // A fresh top-level turn carries no pending return value. Clear
                // any sentinel a previous call may have left behind so a function
                // that falls off its end without an explicit `return` yields "no
                // value" instead of leaking the last returned result.
                self.pending_func_result_value = Val::new(254, Payload::Null);
                if self.control.is_terminated() {
                    return (
                        0x06,
                        cb_id,
                        Val::new(
                            ty::STRING,
                            Payload::from(self.trap.clone().unwrap_or_default()),
                        ),
                    );
                }
                if payload.typ != ty::ARRAY {
                    self.exec_globally = true;
                    self.processing = true;
                    let result = self.run_from(
                        0,
                        self.prog.units.len(),
                        false,
                        Val {
                            typ: ty::NULL,
                            data: Payload::Null,
                        },
                        false,
                    );
                    if let Some(status) = self.control_status(cb_id) {
                        return status;
                    }
                    if self.reserved_host_call.is_some() {
                        let host_call_data = self.reserved_host_call.clone().unwrap();
                        self.reserved_host_call = None;
                        host_call_data
                    } else if self.pointer == self.ctx.memory.first().unwrap().borrow().frozen_end {
                        self.processing = false;
                        (0x01, cb_id, result)
                    } else {
                        self.processing = false;
                        (
                            0x00,
                            0,
                            Val {
                                typ: ty::NULL,
                                data: Payload::Null,
                            },
                        )
                    }
                } else {
                    self.exec_globally = false;
                    self.processing = true;
                    let arr = payload.as_array();
                    let func_name = arr.borrow().data[0].as_string();
                    let input = arr.borrow().data[1].clone();
                    let val = self.ctx.find_val_in_first_scope(&func_name);
                    if !val.is_empty() {
                        let func = val.as_func();
                        let mut m = ValMap::default();
                        if !func.borrow().params.is_empty() {
                            m.insert(func.borrow().params[0].clone(), input);
                        }
                        self.ctx.push_scope_with_args(
                            "funcBody".to_string(),
                            func.borrow().start,
                            func.borrow().start,
                            func.borrow().end,
                            m,
                        );
                        let result = self.run_from(
                            func.borrow().start,
                            func.borrow().end,
                            false,
                            Val {
                                typ: ty::NULL,
                                data: Payload::Null,
                            },
                            true,
                        );
                        if let Some(status) = self.control_status(cb_id) {
                            return status;
                        }
                        if self.reserved_host_call.is_some() {
                            let host_call_data = self.reserved_host_call.clone().unwrap();
                            self.reserved_host_call = None;
                            host_call_data
                        } else if self.ctx.memory.len() == 1 {
                            self.processing = false;
                            (0x01, cb_id, result)
                        } else {
                            self.processing = false;
                            (
                                0x00,
                                0,
                                Val {
                                    typ: ty::NULL,
                                    data: Payload::Null,
                                },
                            )
                        }
                    } else {
                        // The host may invoke an *optional* lifecycle handler the
                        // app didn't define (e.g. `onEvent`, `onResize`, `onFrame`,
                        // `onHostMessage`). Per the documented contract this is a
                        // harmless no-op — so complete the turn with no value rather
                        // than panicking. Panicking here poisons the VM mutex, after
                        // which every subsequent call fails ("cannot recursively
                        // acquire mutex"), silently freezing a host that simply drove
                        // a handler the app chose not to implement.
                        self.processing = false;
                        (
                            0x01,
                            cb_id,
                            Val {
                                typ: ty::NULL,
                                data: Payload::Null,
                            },
                        )
                    }
                }
            }
            0x02 => {
                // println!("executor: print_memory called");
                self.ctx.memory.iter().for_each(|scope| {
                    scope
                        .borrow()
                        .memory
                        .borrow()
                        .data
                        .iter()
                        .for_each(|(key, val)| {
                            println!("{{ key: {}, val: {} }}", key, val.stringify());
                        });
                });
                (
                    0x00,
                    0,
                    Val {
                        typ: ty::NULL,
                        data: Payload::Null,
                    },
                )
            }
            0x03 | 0x04 => {
                // 0x03 resumes after a host call (injecting `payload` as the
                // call's return value). 0x04 resumes after a host-ordered pause
                // (no value injected — `payload` is the typ-254 "no value"
                // marker), continuing exactly where the step loop suspended.
                self.governor.begin_turn();
                self.paused_out = false;
                if self.control.is_terminated() {
                    return (
                        0x06,
                        cb_id,
                        Val::new(
                            ty::STRING,
                            Payload::from(self.trap.clone().unwrap_or_default()),
                        ),
                    );
                }
                self.processing = true;
                let result = self.run_from(
                    self.pointer,
                    self.end_at,
                    true,
                    payload,
                    !self.exec_globally,
                );
                if let Some(status) = self.control_status(cb_id) {
                    return status;
                }
                if !self.ctx.memory.is_empty() {
                    if self.exec_globally {
                        if self.reserved_host_call.is_some() {
                            let host_call_data = self.reserved_host_call.clone().unwrap();
                            self.reserved_host_call = None;
                            host_call_data
                        } else if self.pointer
                            == self.ctx.memory.first().unwrap().borrow().frozen_end
                        {
                            self.processing = false;
                            (0x01, cb_id, result)
                        } else {
                            self.processing = false;
                            (
                                0x00,
                                0,
                                Val {
                                    typ: ty::NULL,
                                    data: Payload::Null,
                                },
                            )
                        }
                    } else {
                        if self.reserved_host_call.is_some() {
                            let host_call_data = self.reserved_host_call.clone().unwrap();
                            self.reserved_host_call = None;
                            host_call_data
                        } else if self.ctx.memory.len() == 1 {
                            self.processing = false;
                            (0x01, cb_id, result)
                        } else {
                            self.processing = false;
                            (
                                0x00,
                                0,
                                Val {
                                    typ: ty::NULL,
                                    data: Payload::Null,
                                },
                            )
                        }
                    }
                } else {
                    self.processing = false;
                    (
                        0x00,
                        0,
                        Val {
                            typ: ty::NULL,
                            data: Payload::Null,
                        },
                    )
                }
            }
            _ => {
                self.processing = false;
                (
                    0x00,
                    0,
                    Val {
                        typ: ty::NULL,
                        data: Payload::Null,
                    },
                )
            }
        }
    }
    /// Resolve an identifier reference to a value: a scope-chain binding shadows
    /// everything; otherwise `askHost` is the host-call seam (typ 255) and a
    /// known standard-library builtin resolves to its native handle (typ 252).
    fn resolve_ident(&mut self, id: &str) -> Val {
        if id == "askHost" {
            return Val {
                typ: ty::ASK_HOST,
                data: Payload::Null,
            };
        }
        // A scope binding — even one currently holding null — shadows a builtin;
        // only a name bound nowhere falls through to the builtin table, and an
        // entirely unknown identifier reads as null.
        if let Some(bound) = self.ctx.lookup_val_globally(id) {
            return bound;
        }
        if stdlib::is_builtin(id) {
            return Val {
                typ: ty::NATIVE_BUILTIN,
                data: Payload::from(id.to_string()),
            };
        }
        Val {
            typ: ty::NULL,
            data: Payload::Null,
        }
    }
    /// Build the value that reading a resolved built-in type member yields. This
    /// is the executor's *only* knowledge of type members: it defers every
    /// name/behaviour decision to [`type_methods`], then realises the returned
    /// [`Dispatch`] uniformly. `stdlib::invoke` runs the actual implementation.
    fn deliver_type_member(&mut self, receiver: &Val, member: &type_methods::Member) -> Val {
        match member.dispatch {
            // A getter reads eagerly through stdlib — the member name is the
            // universal builtin name, invoked directly. A getter that errors
            // reads as null, like any other absent member.
            Dispatch::Getter => stdlib::invoke(&member.name, std::slice::from_ref(receiver))
                .unwrap_or(Val {
                    typ: ty::NULL,
                    data: Payload::Null,
                }),
            // A method becomes a bound native (typ 253) carrying `[recv, name]`;
            // the call machinery appends the args and calls `stdlib::invoke`.
            Dispatch::Method => {
                let name_val = Val {
                    typ: ty::STRING,
                    data: Payload::from(member.name.clone()),
                };
                let holder = Array::new(vec![receiver.clone(), name_val]);
                Val {
                    typ: ty::BOUND_NATIVE,
                    data: Payload::from(Rc::new(RefCell::new(holder))),
                }
            }
            // A higher-order method binds the guest prelude fn `__<Type>_<name>`
            // to the receiver, so its closure argument runs as guest bytecode.
            Dispatch::Prelude => {
                let g = self.ctx.find_val_globally(&member.prelude_fn);
                if g.typ == ty::FUNCTION {
                    let bound = g.as_func().borrow().bind(receiver.clone());
                    Val {
                        typ: ty::FUNCTION,
                        data: Payload::from(Rc::new(RefCell::new(bound))),
                    }
                } else {
                    Val {
                        typ: ty::NULL,
                        data: Payload::Null,
                    }
                }
            }
        }
    }
    fn define(&mut self, id_name: String, val: Val) {
        if let Err(e) = self.governor.charge_memory(val.approx_size()) {
            self.trap = Some(e.to_string());
        }
        self.ctx.define_val_globally(id_name, val);
    }
    fn assign(&mut self, id_name: String, val: Val) {
        if let Err(e) = self.governor.charge_memory(val.approx_size()) {
            self.trap = Some(e.to_string());
        }
        self.ctx.update_val_globally(id_name, val);
    }
    /// Pop the innermost scope, crediting the governor with the value-memory it
    /// held. This is the release half of the executor's approximate live-heap
    /// accounting: values are charged when bound (`define`/`assign`) and freed
    /// when their owning scope is torn down, so the tally tracks what the guest
    /// currently holds rather than everything it has ever allocated.
    fn pop_scope_governed(&mut self) {
        if let Some(scope) = self.ctx.memory.last() {
            let (bytes, is_func) = {
                let s = scope.borrow();
                let bytes: u64 = s
                    .memory
                    .borrow()
                    .data
                    .values()
                    .map(|v| v.approx_size())
                    .sum();
                (bytes, s.tag == "funcBody")
            };
            self.governor.release_memory(bytes);
            if is_func {
                self.governor.leave_call();
            }
        }
        self.ctx.pop_scope();
        // A try frame dies with the scope its `tryBody` lives at — whether it
        // ends normally, is unwound by `return`/`break`/`continue`, or is torn
        // down by an outer throw. Every scope pop funnels through here, so this
        // is the single place frames are retired.
        while self
            .try_stack
            .last()
            .is_some_and(|f| f.scope_depth >= self.ctx.memory.len())
        {
            self.try_stack.pop();
        }
    }
    /// Raise `err`: transfer control to the innermost live `try` frame's catch
    /// body — unwinding scopes (across function frames if needed) and pending
    /// operation registers back to the depths recorded at `try` entry, and
    /// binding the thrown value under the frame's error name — or, with no
    /// live frame, trap the instance with the value's display text. Returns
    /// whether the throw was caught. Callers must reset their local
    /// `main_reg` / `is_reg_state_final` and `continue` the dispatch loop.
    fn begin_catch(&mut self, err: Val) -> bool {
        match self.try_stack.pop() {
            Some(frame) => {
                while self.ctx.memory.len() > frame.scope_depth {
                    self.pop_scope_governed();
                }
                self.registers.truncate(frame.register_depth);
                // Any return value mid-propagation died with the frames it was
                // travelling through.
                self.pending_func_result_value = Val {
                    typ: ty::NO_VALUE,
                    data: Payload::Null,
                };
                let mut args = ValMap::default();
                args.insert(frame.err_name.to_string(), err);
                self.ctx.push_scope_with_args(
                    "catchBody".to_string(),
                    frame.catch_start,
                    frame.catch_start,
                    frame.catch_end,
                    args,
                );
                self.pointer = frame.catch_start;
                self.end_at = frame.catch_end;
                true
            }
            None => {
                self.trap = Some(format!("uncaught error: {}", err.to_display()));
                false
            }
        }
    }
    /// The error value a *native* failure (a stdlib builtin error, a failed
    /// checked cast) throws: a plain object `{ name, message }`, so guest
    /// handlers can read `e.message` in any source language.
    fn native_error(&self, message: String) -> Val {
        let mut m = ValMap::default();
        m.insert(
            "name".to_string(),
            Val {
                typ: ty::STRING,
                data: Payload::from("Error".to_string()),
            },
        );
        m.insert(
            "message".to_string(),
            Val {
                typ: ty::STRING,
                data: Payload::from(message),
            },
        );
        Val {
            typ: ty::OBJECT,
            data: Payload::from(Rc::new(RefCell::new(Object::new(-2, ValGroup::new(m))))),
        }
    }
    /// Snapshot the enclosing (non-global) locals as a closure's captured
    /// environment. Returns `None` at top level (nothing to close over), so
    /// plain functions pay no capture cost. Values are shared by `Rc`, so the
    /// closure keeps exactly its upvalues alive for as long as it lives.
    fn capture_env(&self) -> Option<Rc<RefCell<ValGroup>>> {
        if self.ctx.memory.len() <= 1 {
            return None;
        }
        let mut map: ValMap = ValMap::default();
        for scope in self.ctx.memory[1..].iter() {
            for (k, v) in scope.borrow().memory.borrow().data.iter() {
                map.insert(k.clone(), v.clone());
            }
        }
        if map.is_empty() {
            None
        } else {
            Some(Rc::new(RefCell::new(ValGroup::new(map))))
        }
    }
    /// Capture only the closure's *free variables* (computed by the compiler)
    /// from the enclosing non-global scopes — the innermost binding of each name
    /// wins, matching lexical resolution. This replaces snapshotting the entire
    /// scope chain: a closure pays only for the upvalues it actually uses, both
    /// to create and to seed on each call. Names not found in an enclosing scope
    /// (globals, or a closure's own not-yet-declared locals) are simply omitted
    /// and resolve normally at run time.
    fn capture_named(&self, names: &[String]) -> Option<Rc<RefCell<ValGroup>>> {
        if self.ctx.memory.len() <= 1 || names.is_empty() {
            return None;
        }
        let mut map: ValMap = ValMap::default();
        for name in names {
            for scope in self.ctx.memory[1..].iter().rev() {
                let found = scope.borrow().memory.borrow().data.get(name).cloned();
                if let Some(v) = found {
                    map.insert(name.clone(), v);
                    break;
                }
            }
        }
        if map.is_empty() {
            None
        } else {
            Some(Rc::new(RefCell::new(ValGroup::new(map))))
        }
    }
    /// Resolve a class method for `receiver.key` through the object's `__proto`
    /// chain (set by a `class` constructor), returning the method *bound* to the
    /// receiver. Binding reuses the closure mechanism: the shared top-level method
    /// function is cloned with a one-entry captured env `{ this: receiver }`, so
    /// the existing call path seeds `this` into the frame at no extra machinery —
    /// and, crucially, the method itself is never installed per instance. Returns
    /// `None` when `key` is not a method anywhere on the chain.
    fn bind_proto_method(&self, receiver: &Val, key: &str) -> Option<Val> {
        let mut proto = receiver
            .as_object()
            .borrow()
            .data
            .data
            .get("__proto")
            .cloned();
        while let Some(p) = proto {
            if p.typ != ty::OBJECT {
                break;
            }
            let (entry, parent) = {
                let pb = p.as_object();
                let b = pb.borrow();
                (
                    b.data.data.get(key).cloned(),
                    b.data.data.get("__parent").cloned(),
                )
            };
            if let Some(m) = entry {
                if m.typ == ty::FUNCTION {
                    let bound = m.as_func().borrow().bind(receiver.clone());
                    return Some(Val {
                        typ: ty::FUNCTION,
                        data: Payload::from(Rc::new(RefCell::new(bound))),
                    });
                }
                return Some(m);
            }
            proto = parent;
        }
        None
    }
    pub fn run_from(
        &mut self,
        start: usize,
        end: usize,
        continue_exec: bool,
        host_call_result: Val,
        is_partial_exec: bool,
    ) -> Val {
        if !continue_exec {
            if !is_partial_exec {
                self.ctx
                    .push_scope("funcBody".to_string(), start, start, end);
            }
            self.pointer = start;
            self.end_at = end;
        } else {
            self.pending_func_result_value = host_call_result.clone();
        }
        let mut main_reg: Option<Val> = None;
        let mut is_reg_state_final = false;
        if continue_exec && self.pending_func_result_value.typ != ty::NO_VALUE {
            let returned_val = self.pending_func_result_value.clone();
            self.pending_func_result_value = Val {
                typ: ty::NO_VALUE,
                data: Payload::Null,
            };
            if !self.registers.is_empty() {
                main_reg = Some(returned_val);
                is_reg_state_final = false;
            }
        }
        loop {
            // --- Host-driven lifecycle + resource governance (per step) ------
            // Checked at every step boundary so the host can pause, resume, or
            // terminate an instance, and so runaway work/memory is trapped long
            // before it can exhaust the real process.
            if self.trap.is_some() {
                self.control.confirm_terminated();
                self.registers.clear();
                break;
            }
            if self.control.should_suspend() {
                if self.control.is_terminating() {
                    self.control.confirm_terminated();
                    self.registers.clear();
                    break;
                } else {
                    self.control.confirm_paused();
                    self.paused_out = true;
                    break;
                }
            }
            if let Err(e) = self.governor.charge_instruction() {
                self.trap = Some(e.to_string());
                self.control.confirm_terminated();
                self.registers.clear();
                break;
            }
            if main_reg.is_some() {
                if !self.registers.is_empty() {
                    let op_type = self.registers.last().unwrap().get_type();
                    if op_type == OperationTypes::Dummy {
                        // A `DummyOp` is a called-function frame marker. A bare
                        // expression statement inside that body bubbles its value
                        // up to here; statement values are discarded (only an
                        // explicit `return` propagates), so drop it. Without this
                        // the stale value would be picked up by the next
                        // operation (e.g. a following `return`).
                        main_reg = None;
                        continue;
                    }
                    if op_type == OperationTypes::ArrExpr {
                        if self.registers.last().unwrap().get_state()
                            == ExecStates::ArrExprExtractInfo
                            || self.registers.last().unwrap().get_state()
                                == ExecStates::ArrExprExtractItem
                        {
                            self.registers.last_mut().unwrap().set_state(
                                ExecStates::ArrExprExtractItem,
                                StateData::Val(main_reg.take().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final = self.registers.last().unwrap().get_state()
                                == ExecStates::ArrExprFinished;
                            continue;
                        }
                    } else if op_type == OperationTypes::ObjExpr {
                        if self.registers.last().unwrap().get_state()
                            == ExecStates::ObjExprExtractInfo
                            || self.registers.last().unwrap().get_state()
                                == ExecStates::ObjExprExtractProp
                        {
                            self.registers.last_mut().unwrap().set_state(
                                ExecStates::ObjExprExtractProp,
                                StateData::Val(main_reg.take().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final = self.registers.last().unwrap().get_state()
                                == ExecStates::ObjExprFinished;
                            continue;
                        }
                    } else if op_type == OperationTypes::CallFunc {
                        if self.registers.last().unwrap().get_state() == ExecStates::CallFuncStarted
                        {
                            // The callee just evaluated; the argument count is
                            // already stored in the operation (folded into the
                            // `Call` unit at decode).
                            self.registers.last_mut().unwrap().set_state(
                                ExecStates::CallFuncExtractFunc,
                                StateData::Val(main_reg.take().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final = self.registers.last().unwrap().get_state()
                                == ExecStates::CallFuncFinished;
                            continue;
                        } else if self.registers.last().unwrap().get_state()
                            == ExecStates::CallFuncExtractFunc
                            || self.registers.last().unwrap().get_state()
                                == ExecStates::CallFuncExtractParam
                        {
                            self.registers.last_mut().unwrap().set_state(
                                ExecStates::CallFuncExtractParam,
                                StateData::Val(main_reg.take().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final = self.registers.last().unwrap().get_state()
                                == ExecStates::CallFuncFinished;
                            continue;
                        }
                    } else if op_type == OperationTypes::ReturnVal {
                        if self.registers.last().unwrap().get_state()
                            == ExecStates::ReturnValStarted
                        {
                            self.registers.last_mut().unwrap().set_state(
                                ExecStates::ReturnValFinished,
                                StateData::Val(main_reg.take().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final = self.registers.last().unwrap().get_state()
                                == ExecStates::ReturnValFinished;
                            continue;
                        }
                    } else if op_type == OperationTypes::ThrowVal {
                        if self.registers.last().unwrap().get_state() == ExecStates::ThrowValStarted
                        {
                            self.registers.last_mut().unwrap().set_state(
                                ExecStates::ThrowValFinished,
                                StateData::Val(main_reg.take().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final = true;
                            continue;
                        }
                    } else if op_type == OperationTypes::DefineVar {
                        if self.registers.last().unwrap().get_state()
                            == ExecStates::DefineVarExtractName
                        {
                            self.registers.last_mut().unwrap().set_state(
                                ExecStates::DefineVarExtractValue,
                                StateData::Val(main_reg.take().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final = self.registers.last().unwrap().get_state()
                                == ExecStates::DefineVarExtractValue;
                            continue;
                        }
                    } else if op_type == OperationTypes::AssignVar {
                        if self.registers.last().unwrap().get_state()
                            == ExecStates::AssignVarExtractName
                        {
                            if self.registers.last().unwrap().get_data()[1].as_i16() == 1 {
                                self.registers.last_mut().unwrap().set_state(
                                    ExecStates::AssignVarExtractValue,
                                    StateData::Val(main_reg.take().unwrap()),
                                );
                                main_reg = None;
                                is_reg_state_final = self.registers.last().unwrap().get_state()
                                    == ExecStates::AssignVarExtractValue;
                                continue;
                            } else if self.registers.last().unwrap().get_data()[1].as_i16() == 2 {
                                self.registers.last_mut().unwrap().set_state(
                                    ExecStates::AssignVarExtractIndex,
                                    StateData::Val(main_reg.take().unwrap()),
                                );
                                main_reg = None;
                                is_reg_state_final = self.registers.last().unwrap().get_state()
                                    == ExecStates::AssignVarExtractValue;
                                continue;
                            }
                        } else if self.registers.last().unwrap().get_state()
                            == ExecStates::AssignVarExtractIndex
                        {
                            self.registers.last_mut().unwrap().set_state(
                                ExecStates::AssignVarExtractValue,
                                StateData::Val(main_reg.take().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final = self.registers.last().unwrap().get_state()
                                == ExecStates::AssignVarExtractValue;
                            continue;
                        }
                    } else if op_type == OperationTypes::IfStmt {
                        if self.registers.last().unwrap().get_state()
                            == ExecStates::IfStmtIsConditioned
                        {
                            self.registers.last_mut().unwrap().set_state(
                                ExecStates::IfStmtFinished,
                                StateData::Val(main_reg.take().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final = self.registers.last().unwrap().get_state()
                                == ExecStates::IfStmtFinished;
                            continue;
                        }
                    } else if op_type == OperationTypes::LoopStmt {
                        if self.registers.last().unwrap().get_state() == ExecStates::LoopStmtStarted
                        {
                            self.registers.last_mut().unwrap().set_state(
                                ExecStates::LoopStmtFinished,
                                StateData::Val(main_reg.take().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final = self.registers.last().unwrap().get_state()
                                == ExecStates::LoopStmtFinished;
                            continue;
                        }
                    } else if op_type == OperationTypes::SwitchStmt {
                        if self.registers.last().unwrap().get_state()
                            == ExecStates::SwitchStmtStarted
                        {
                            // The switch value just evaluated; the branch-after and
                            // case table are already stored in the operation
                            // (folded into the `Switch` unit at decode).
                            self.registers.last_mut().unwrap().set_state(
                                ExecStates::SwitchStmtExtractVal,
                                StateData::Val(main_reg.take().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final = self.registers.last().unwrap().get_state()
                                == ExecStates::SwitchStmtFinished;
                            continue;
                        } else if self.registers.last().unwrap().get_state()
                            == ExecStates::SwitchStmtExtractVal
                            || self.registers.last().unwrap().get_state()
                                == ExecStates::SwitchStmtExtractCase
                        {
                            // A case value just evaluated. Its body range is the
                            // next entry in the operation's case table; read the
                            // end before recording the case so we can skip the body.
                            let (_, branch_true_end) =
                                self.registers.last().unwrap().next_case_bounds();
                            self.registers.last_mut().unwrap().set_state(
                                ExecStates::SwitchStmtExtractCase,
                                StateData::Val(main_reg.take().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final = self.registers.last().unwrap().get_state()
                                == ExecStates::SwitchStmtFinished;
                            // Skip past this case's body to the next case's value
                            // expression. Without this the scan would fall into
                            // the body and execute it while still collecting
                            // cases. Once every case is collected the dispatch
                            // (SwitchStmtFinished) sets the pointer itself, so the
                            // value parked here is only used between cases.
                            self.pointer = branch_true_end;
                            continue;
                        }
                    } else if op_type == OperationTypes::Arithmetic {
                        if self.registers.last().unwrap().get_state()
                            == ExecStates::ArithmeticExtractOp
                        {
                            self.registers.last_mut().unwrap().set_state(
                                ExecStates::ArithmeticExtractArg1,
                                StateData::Val(main_reg.take().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final = self.registers.last().unwrap().get_state()
                                == ExecStates::ArithmeticExtractArg2;
                            continue;
                        } else if self.registers.last().unwrap().get_state()
                            == ExecStates::ArithmeticExtractArg1
                        {
                            self.registers.last_mut().unwrap().set_state(
                                ExecStates::ArithmeticExtractArg2,
                                StateData::Val(main_reg.take().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final = self.registers.last().unwrap().get_state()
                                == ExecStates::ArithmeticExtractArg2;
                            continue;
                        }
                    } else if op_type == OperationTypes::Indexer {
                        if self.registers.last().unwrap().get_state() == ExecStates::IndexerStarted
                        {
                            self.registers.last_mut().unwrap().set_state(
                                ExecStates::IndexerExtractVarName,
                                StateData::Val(main_reg.take().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final = self.registers.last().unwrap().get_state()
                                == ExecStates::IndexerExtractIndex;
                            continue;
                        } else if self.registers.last().unwrap().get_state()
                            == ExecStates::IndexerExtractVarName
                        {
                            self.registers.last_mut().unwrap().set_state(
                                ExecStates::IndexerExtractIndex,
                                StateData::Val(main_reg.take().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final = self.registers.last().unwrap().get_state()
                                == ExecStates::IndexerExtractIndex;
                            continue;
                        }
                    } else if op_type == OperationTypes::NotVal {
                        if self.registers.last().unwrap().get_state() == ExecStates::NotValStarted {
                            self.registers.last_mut().unwrap().set_state(
                                ExecStates::NotValFinished,
                                StateData::Val(main_reg.take().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final = self.registers.last().unwrap().get_state()
                                == ExecStates::NotValFinished;
                            continue;
                        }
                    } else if op_type == OperationTypes::Spread {
                        if self.registers.last().unwrap().get_state() == ExecStates::SpreadStarted {
                            self.registers.last_mut().unwrap().set_state(
                                ExecStates::SpreadFinished,
                                StateData::Val(main_reg.take().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final = self.registers.last().unwrap().get_state()
                                == ExecStates::SpreadFinished;
                            continue;
                        }
                    } else if op_type == OperationTypes::Template {
                        if self.registers.last().unwrap().get_state()
                            == ExecStates::TemplateExtractInfo
                            || self.registers.last().unwrap().get_state()
                                == ExecStates::TemplateExtractPart
                        {
                            self.registers.last_mut().unwrap().set_state(
                                ExecStates::TemplateExtractPart,
                                StateData::Val(main_reg.take().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final = self.registers.last().unwrap().get_state()
                                == ExecStates::TemplateFinished;
                            continue;
                        }
                    } else if op_type == OperationTypes::Destructure {
                        if self.registers.last().unwrap().get_state()
                            == ExecStates::DestructureExtractValue
                        {
                            self.registers.last_mut().unwrap().set_state(
                                ExecStates::DestructureExtractValue,
                                StateData::Val(main_reg.take().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final = self.registers.last().unwrap().get_state()
                                == ExecStates::DestructureFinished;
                            continue;
                        }
                    } else if op_type == OperationTypes::CondBrch {
                        if self.registers.last().unwrap().get_state()
                            == ExecStates::CondBranchStarted
                        {
                            // The condition just evaluated; both targets are
                            // already stored in the operation (folded into the
                            // `CondBranch` unit at decode).
                            self.registers.last_mut().unwrap().set_state(
                                ExecStates::CondBranchFinished,
                                StateData::Val(main_reg.take().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final = self.registers.last().unwrap().get_state()
                                == ExecStates::CondBranchFinished;
                            continue;
                        }
                    } else if op_type == OperationTypes::CastOprt {
                        if self.registers.last().unwrap().get_state() == ExecStates::CastOprtStarted
                        {
                            // The value just evaluated; the target type is already
                            // stored in the operation (folded into the `Cast` unit).
                            self.registers.last_mut().unwrap().set_state(
                                ExecStates::CastOprtFinished,
                                StateData::Val(main_reg.take().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final = self.registers.last().unwrap().get_state()
                                == ExecStates::CastOprtFinished;
                            continue;
                        }
                    } else if op_type == OperationTypes::TypeTest {
                        if self.registers.last().unwrap().get_state() == ExecStates::TypeTestStarted
                        {
                            // The value just evaluated; the type name + mode are
                            // already folded into the operation.
                            self.registers.last_mut().unwrap().set_state(
                                ExecStates::TypeTestFinished,
                                StateData::Val(main_reg.take().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final = self.registers.last().unwrap().get_state()
                                == ExecStates::TypeTestFinished;
                            continue;
                        }
                    } else if op_type == OperationTypes::Logical {
                        let state = self.registers.last().unwrap().get_state();
                        if state == ExecStates::LogicalExtractOp1 {
                            // The left operand just evaluated. Decide whether the
                            // result is settled (reuse the left value and skip the
                            // right operand) or the right operand must be evaluated:
                            // `&&` short-circuits on a falsy left, `||` on a truthy
                            // left, and `??` on a non-null left.
                            let data = self.registers.last().unwrap().get_data();
                            let kind = LogicalOp::kind_from_tag(data[0].as_i16());
                            let op2_end = data[1].as_i64() as usize;
                            let left = main_reg.take().unwrap();
                            let evaluate_right = match kind {
                                LogicalKind::And => left.truthy(),
                                LogicalKind::Or => !left.truthy(),
                                LogicalKind::NullCoalesce => is_null(&left),
                            };
                            if evaluate_right {
                                self.registers
                                    .last_mut()
                                    .unwrap()
                                    .set_state(ExecStates::LogicalExtractOp2, StateData::Empty);
                                main_reg = None;
                                is_reg_state_final = false;
                                // Fall through into the right operand's units.
                                continue;
                            } else {
                                self.registers.pop();
                                self.pointer = op2_end; // skip the right operand
                                main_reg = Some(left);
                                is_reg_state_final = false;
                                continue;
                            }
                        } else if state == ExecStates::LogicalExtractOp2 {
                            // The right operand just evaluated and is the result.
                            let right = main_reg.take().unwrap();
                            self.registers.pop();
                            main_reg = Some(right);
                            is_reg_state_final = false;
                            continue;
                        }
                    } else if op_type == OperationTypes::Conditional {
                        let state = self.registers.last().unwrap().get_state();
                        if state == ExecStates::CondExprExtractCond {
                            // The condition just evaluated. A truthy condition lets
                            // execution fall into the consequent (which immediately
                            // follows); otherwise jump to the alternate.
                            let data = self.registers.last().unwrap().get_data();
                            let alt_start = data[0].as_i64() as usize;
                            let cond = main_reg.take().unwrap();
                            if !cond.truthy() {
                                self.pointer = alt_start;
                            }
                            self.registers
                                .last_mut()
                                .unwrap()
                                .set_state(ExecStates::CondExprExtractValue, StateData::Empty);
                            main_reg = None;
                            is_reg_state_final = false;
                            continue;
                        } else if state == ExecStates::CondExprExtractValue {
                            // The taken branch's value is the result; skip past the
                            // other branch.
                            let data = self.registers.last().unwrap().get_data();
                            let end = data[1].as_i64() as usize;
                            let val = main_reg.take().unwrap();
                            self.registers.pop();
                            self.pointer = end;
                            main_reg = Some(val);
                            is_reg_state_final = false;
                            continue;
                        }
                    }
                } else {
                    main_reg = None;
                }
            } else if is_reg_state_final {
                if !self.registers.is_empty() {
                    if self.registers.last().unwrap().get_state() == ExecStates::ArrExprFinished {
                        let regs = self.registers.last().unwrap().get_data();
                        let items_arr = regs[1].as_array();
                        // Expand any spread elements (`[...xs, y]`) in place before
                        // materialising the array; a plain array is untouched.
                        let flattened = flatten_spread(&items_arr.borrow().data);
                        self.registers.pop();
                        main_reg = Some(Val {
                            typ: ty::ARRAY,
                            data: Payload::from(Rc::new(RefCell::new(Array::new(flattened)))),
                        });
                        is_reg_state_final = false;
                        continue;
                    } else if self.registers.last().unwrap().get_state()
                        == ExecStates::ObjExprFinished
                    {
                        let regs = self.registers.last().unwrap().get_data();
                        let typ_id = regs[0].as_i64();
                        let props_vec = regs[2].as_array();
                        let mut props_map = ValMap::default();
                        for i in (0..props_vec.borrow().data.len()).step_by(2) {
                            let key = props_vec.borrow().data[i].clone();
                            let val = props_vec.borrow().data[i + 1].clone();
                            if key.typ == SPREAD_KEY_MARKER {
                                // Object spread (`{...src}`): merge the paired
                                // object's members, later entries winning — exactly
                                // the ordered-override semantics of a literal.
                                if val.typ == ty::OBJECT {
                                    let src = val.as_object();
                                    for (k, v) in src.borrow().data.data.iter() {
                                        props_map.insert(k.clone(), v.clone());
                                    }
                                }
                            } else {
                                props_map.insert(key.as_string(), val);
                            }
                        }
                        let result = Val {
                            typ: ty::OBJECT,
                            data: Payload::from(Rc::new(RefCell::new(Object::new(
                                typ_id,
                                ValGroup::new(props_map),
                            )))),
                        };
                        self.registers.pop();
                        main_reg = Some(result);
                        is_reg_state_final = false;
                        continue;
                    } else if self.registers.last().unwrap().get_state()
                        == ExecStates::CallFuncFinished
                    {
                        let regs = self.registers.last().unwrap().get_data();
                        let is_native = regs[1].as_bool();
                        if !is_native {
                            let func = regs[0].as_func().clone();
                            // Guard native-stack exhaustion via the call-depth
                            // budget before entering the new frame.
                            if let Err(e) = self.governor.enter_call() {
                                self.trap = Some(e.to_string());
                                continue;
                            }
                            let expected_params = func.borrow().params.clone();
                            let provided_args = regs[3].as_array().borrow().data.clone();
                            let mut args = ValMap::default();
                            // Seed the frame with the closure's captured upvalues
                            // first, so explicit parameters override them.
                            if let Some(captured) = func.borrow().captured.clone() {
                                for (k, v) in captured.borrow().data.iter() {
                                    args.insert(k.clone(), v.clone());
                                }
                            }
                            // A bound method receives its receiver as `this`.
                            if let Some(receiver) = func.borrow().this_arg.clone() {
                                args.insert("this".to_string(), receiver);
                            }
                            for (i, param_name) in expected_params.iter().enumerate() {
                                // Calls are arity-flexible at the VM level: a
                                // parameter with no supplied argument binds to the
                                // first-class null, so a front-end can express its
                                // language's defaulting (optional/named parameters,
                                // `undefined`, …) with a compile-time `== null`
                                // check.
                                let arg = provided_args
                                    .get(i)
                                    .cloned()
                                    .unwrap_or_else(|| Val::new(ty::NULL, Payload::Null));
                                args.insert(param_name.clone(), arg);
                            }
                            self.ctx
                                .memory
                                .last()
                                .unwrap()
                                .borrow_mut()
                                .update_frozen_pointer(self.pointer);
                            self.ctx.push_scope_with_args(
                                "funcBody".to_string(),
                                func.borrow().start,
                                func.borrow().start,
                                func.borrow().end,
                                args,
                            );
                            self.pointer = func.borrow().start;
                            self.end_at = func.borrow().end;
                            self.registers.pop();
                            self.registers.push(Box::new(DummyOp::new()));
                            is_reg_state_final = false;
                            continue;
                        } else {
                            // A native call: either a standard-library builtin
                            // (named function, typ 252) or the `askHost` seam
                            // (unnamed, typ 255). The two construction sites are the
                            // only producers of a native function value, so a
                            // non-empty name unambiguously means "builtin" — no need
                            // to re-scan the builtin table here (it ran already at
                            // resolve time). We dispatch straight off the borrowed
                            // name and the borrowed argument slice, cloning neither
                            // the name `String` nor the argument `Vec` on this path.
                            let func = regs[0].as_func();
                            let is_builtin_call = !func.borrow().name.is_empty();
                            if is_builtin_call {
                                let func_ref = func.borrow();
                                let arg_arr = regs[3].as_array();
                                let arg_ref = arg_arr.borrow();
                                // A bound native method (core-type method) threads
                                // its receiver as the first argument.
                                let outcome = if let Some(recv) = func_ref.this_arg.clone() {
                                    let mut combined = Vec::with_capacity(arg_ref.data.len() + 1);
                                    combined.push(recv);
                                    combined.extend(arg_ref.data.iter().cloned());
                                    stdlib::invoke(&func_ref.name, &combined)
                                } else {
                                    stdlib::invoke(&func_ref.name, &arg_ref.data)
                                };
                                match outcome {
                                    Ok(result) => {
                                        drop(arg_ref);
                                        drop(func_ref);
                                        self.registers.pop();
                                        let _ = self.governor.charge_memory(result.approx_size());
                                        main_reg = Some(result);
                                        is_reg_state_final = false;
                                        continue;
                                    }
                                    Err(e) => {
                                        // A builtin error is a *thrown* error: a
                                        // guest `try` anywhere up the call chain
                                        // catches it as `{ name, message }`;
                                        // uncaught it traps the instance as
                                        // before.
                                        let msg = format!("{}: {e}", func_ref.name);
                                        drop(arg_ref);
                                        drop(func_ref);
                                        let err = self.native_error(msg);
                                        self.begin_catch(err);
                                        main_reg = None;
                                        is_reg_state_final = false;
                                        continue;
                                    }
                                }
                            }
                            let arg1 = regs[3].as_array().borrow().data[0].clone();
                            let api_name = arg1.as_string();
                            // Capability gate: if the host has switched this
                            // interface off, the call does not reach the host —
                            // it short-circuits to a typed null so the guest
                            // keeps running deterministically.
                            if !self.capabilities.allows_api(&api_name) {
                                self.registers.pop();
                                main_reg = Some(Val::new(ty::NULL, Payload::Null));
                                is_reg_state_final = false;
                                continue;
                            }
                            let arg2 = regs[3].as_array().borrow().data[1].clone();
                            self.cb_counter += 1;
                            let cb_id = self.cb_counter;
                            self.registers.pop();
                            self.reserved_host_call = Some((
                                0x02,
                                cb_id,
                                Val {
                                    typ: ty::ARRAY,
                                    data: Payload::from(Rc::new(RefCell::new(Array::new(vec![
                                        arg1,
                                        Val {
                                            typ: ty::I16,
                                            data: Payload::from(self.executor_id),
                                        },
                                        arg2,
                                    ])))),
                                },
                            ));
                            break;
                        }
                    } else if self.registers.last().unwrap().get_state()
                        == ExecStates::ReturnValFinished
                    {
                        let data = self.registers.last().unwrap().get_data();
                        let returned_val = data[0].clone();
                        self.registers.pop();
                        // A `return` exits the whole function, not just the block
                        // (if / loop / switch) it textually sits in. Unwind any
                        // such intervening scopes so the enclosing function-body
                        // frame is innermost, then jump to its end and let the
                        // normal scope teardown deliver the value — making every
                        // return behave like a top-level return. The outermost
                        // scope (the top-level program) is itself tagged
                        // "funcBody" but must never be unwound, so the length
                        // guard keeps it in place (a top-level `return` simply
                        // ends the run).
                        while self.ctx.memory.len() > 1
                            && self.ctx.memory.last().unwrap().borrow().tag != "funcBody"
                        {
                            self.pop_scope_governed();
                        }
                        let func_end = self.ctx.memory.last().unwrap().borrow().frozen_end;
                        self.pointer = func_end;
                        self.end_at = func_end;
                        self.pending_func_result_value = returned_val;
                        is_reg_state_final = false;
                        continue;
                    } else if self.registers.last().unwrap().get_state()
                        == ExecStates::ThrowValFinished
                    {
                        // The thrown value is collected; raise it through the try
                        // stack (or trap when uncaught).
                        let data = self.registers.last().unwrap().get_data();
                        let err = data[0].clone();
                        self.registers.pop();
                        self.begin_catch(err);
                        main_reg = None;
                        is_reg_state_final = false;
                        continue;
                    } else if self.registers.last().unwrap().get_state()
                        == ExecStates::DefineVarExtractValue
                    {
                        let regs = self.registers.last().unwrap().get_data();
                        let var_name = regs[0].as_string();
                        let var_value = regs[1].clone();
                        self.registers.pop();
                        self.define(var_name.clone(), var_value.clone());
                        is_reg_state_final = false;
                        continue;
                    } else if self.registers.last().unwrap().get_state()
                        == ExecStates::AssignVarExtractValue
                    {
                        let regs = self.registers.last().unwrap().get_data();
                        let var_name = regs[0].as_string();
                        let assign_target_type = regs[1].as_i16();
                        let data = regs[3].clone();
                        if assign_target_type == 1 {
                            self.assign(var_name.clone(), data);
                        } else if assign_target_type == 2 {
                            let index = regs[2].clone();
                            let indexed = self.ctx.find_val_globally(&var_name);
                            if index.typ == ty::STRING {
                                if indexed.typ == ty::OBJECT {
                                    let obj = indexed.as_object();
                                    obj.borrow_mut().data.data.insert(index.as_string(), data);
                                } else {
                                    panic!(
                                    "elpian error: non object value can not be indexed by string"
                                );
                                }
                            } else if index.typ >= 1 && index.typ <= 3 {
                                if indexed.typ == ty::ARRAY {
                                    let sidx = match index.typ {
                                        ty::I16 => index.as_i16() as i64,
                                        ty::I32 => index.as_i32() as i64,
                                        _ => index.as_i64(),
                                    };
                                    if sidx < 0 {
                                        panic!("elpian error: negative array index");
                                    }
                                    let idx = sidx as usize;
                                    let arr = indexed.as_array();
                                    let mut b = arr.borrow_mut();
                                    // The VM's list store semantics: assigning at or
                                    // past the end grows the list, filling the gap
                                    // with null (e.g. `var out = []; out[i] = v;`).
                                    // A front-end for a bounds-strict language lowers
                                    // an indexed store to the `setAt` builtin, which
                                    // traps on an out-of-range index, instead.
                                    if idx >= b.data.len() {
                                        b.data.resize(
                                            idx + 1,
                                            Val {
                                                typ: ty::NULL,
                                                data: Payload::Null,
                                            },
                                        );
                                    }
                                    b.data[idx] = data;
                                } else {
                                    panic!(
                                    "elpian error: non object value can not be indexed by string"
                                );
                                }
                            } else {
                                panic!(
                                "elpian error: types other than integer and string can not be used to index anything"
                            );
                            }
                        }
                        self.registers.pop();
                        is_reg_state_final = false;
                        continue;
                    } else if self.registers.last().unwrap().get_state()
                        == ExecStates::IfStmtFinished
                    {
                        // The branch targets are part of the operation (folded into
                        // the `IfHead` unit at decode): regs = [has_condition,
                        // condition, body_start, body_end, next, branch_after].
                        let regs = self.registers.last().unwrap().get_data();
                        let has_condition = regs[0].as_bool();
                        let cond_val = regs[1].clone();
                        let branch_true_start = regs[2].as_i64() as usize;
                        let branch_true_end = regs[3].as_i64() as usize;
                        let branch_next_start = regs[4].as_i64() as usize;
                        let branch_after_start = regs[5].as_i64() as usize;
                        let mut condition = false;
                        if has_condition {
                            // The VM's truthiness rule (see `Val::truthy`) — any
                            // non-falsy value takes the branch, not just `true`. A
                            // front-end whose language coerces differently wraps the
                            // condition at compile time (e.g. the `bool` builtin).
                            condition = cond_val.truthy();
                        }
                        if !has_condition {
                            self.ctx
                                .memory
                                .last()
                                .unwrap()
                                .borrow_mut()
                                .update_frozen_pointer(branch_after_start);
                            self.ctx.push_scope(
                                "ifBody".to_string(),
                                branch_true_start,
                                branch_true_start,
                                branch_true_end,
                            );
                            self.pointer = branch_true_start;
                            self.end_at = branch_true_end;
                        } else {
                            if condition {
                                self.ctx
                                    .memory
                                    .last()
                                    .unwrap()
                                    .borrow_mut()
                                    .update_frozen_pointer(branch_after_start);
                                self.ctx.push_scope(
                                    "ifBody".to_string(),
                                    branch_true_start,
                                    branch_true_start,
                                    branch_true_end,
                                );
                                self.pointer = branch_true_start;
                                self.end_at = branch_true_end;
                            } else {
                                self.pointer = branch_next_start;
                            }
                        }
                        self.registers.pop();
                        is_reg_state_final = false;
                        continue;
                    } else if self.registers.last().unwrap().get_state()
                        == ExecStates::LoopStmtFinished
                    {
                        // The loop bounds are part of the operation (folded into the
                        // `Loop` unit at decode): regs = [condition, body_start,
                        // body_end, branch_after].
                        let regs = self.registers.last().unwrap().get_data();
                        let cond_val = regs[0].clone();
                        // The VM's truthiness rule for the loop guard (see the
                        // if-statement above).
                        let condition = cond_val.truthy();
                        let branch_true_start = regs[1].as_i64() as usize;
                        let branch_true_end = regs[2].as_i64() as usize;
                        let branch_after_start = regs[3].as_i64() as usize;
                        if condition {
                            // A loop re-evaluates its `LoopStmt` unit while still
                            // *inside* the previous iteration's body scope: the body's
                            // final instruction jumps back to the loop unit (see the
                            // compiler's `loopStmt` emission), so the spent `loopBody`
                            // scope is still on top here. Reclaim it before opening a
                            // fresh one, so only ever **one** body scope is live and an
                            // N-iteration loop stays O(N) — otherwise one empty scope
                            // leaks per iteration, every variable lookup then walks an
                            // ever-deeper chain (`find_val_globally`/`update_val_globally`),
                            // and the loop degrades to O(N^2) time and O(N) memory
                            // (reclaimed only when the whole function returns). Match by
                            // tag **and** the body-start it was opened at, so nested
                            // loops reclaim only their own bodies and the loop's first
                            // entry (top scope is the enclosing frame, not a matching
                            // `loopBody`) is left untouched. Closures created in the
                            // body keep their captured environment alive through their
                            // own `Rc`, so popping it from the active scope stack does
                            // not disturb per-iteration captures. The exit path
                            // (condition false) deliberately does **not** pre-pop: the
                            // teardown cascade below reclaims the final body scope.
                            let reentered_body = self
                                .ctx
                                .memory
                                .last()
                                .map(|s| {
                                    let s = s.borrow();
                                    s.tag == "loopBody" && s.frozen_start == branch_true_start
                                })
                                .unwrap_or(false);
                            if reentered_body {
                                self.pop_scope_governed();
                            }
                            self.ctx
                                .memory
                                .last()
                                .unwrap()
                                .borrow_mut()
                                .update_frozen_pointer(branch_after_start);
                            self.ctx.push_scope(
                                "loopBody".to_string(),
                                branch_true_start,
                                branch_true_start,
                                branch_true_end,
                            );
                            self.pointer = branch_true_start;
                            self.end_at = branch_true_end;
                        } else {
                            self.pointer = branch_after_start;
                        }
                        self.registers.pop();
                        is_reg_state_final = false;
                        continue;
                    } else if self.registers.last().unwrap().get_state()
                        == ExecStates::SwitchStmtFinished
                    {
                        let regs = self.registers.last().unwrap().get_data();
                        let comparing_val = regs[0].clone();
                        let branch_after_start = regs[1].as_i64() as usize;
                        let cases = regs[3].as_array();
                        let mut matched = false;
                        for case_info in cases.borrow().data.iter() {
                            let data = case_info.as_object().borrow().data.data.clone();
                            let case_val = data["val"].clone();
                            let branch_true_start = data["start"].as_i64() as usize;
                            let branch_true_end = data["end"].as_i64() as usize;
                            if self.is_eq(comparing_val.clone(), case_val) {
                                matched = true;
                                self.ctx
                                    .memory
                                    .last()
                                    .unwrap()
                                    .borrow_mut()
                                    .update_frozen_pointer(branch_after_start);
                                self.ctx.push_scope(
                                    "switchBody".to_string(),
                                    branch_true_start,
                                    branch_true_start,
                                    branch_true_end,
                                );
                                self.pointer = branch_true_start;
                                self.end_at = branch_true_end;
                            }
                        }
                        if !matched {
                            self.pointer = branch_after_start;
                        }
                        self.registers.pop();
                        is_reg_state_final = false;
                        continue;
                    } else if self.registers.last().unwrap().get_state()
                        == ExecStates::ArithmeticExtractArg2
                    {
                        let regs = self.registers.last().unwrap().get_data();
                        let op = regs[0].as_i16();
                        let arg1 = regs[1].clone();
                        let arg2 = regs[2].clone();
                        self.registers.pop();
                        match op {
                            1 => {
                                main_reg = Some(Val {
                                    typ: ty::BOOL,
                                    data: Payload::from(self.is_eq(arg1, arg2)),
                                });
                            }
                            2 => {
                                main_reg = Some(Val {
                                    typ: ty::BOOL,
                                    data: Payload::from(self.is_ge(arg1, arg2)),
                                });
                            }
                            3 => {
                                main_reg = Some(Val {
                                    typ: ty::BOOL,
                                    data: Payload::from(self.is_gee(arg1, arg2)),
                                });
                            }
                            4 => {
                                main_reg = Some(Val {
                                    typ: ty::BOOL,
                                    data: Payload::from(self.is_le(arg1, arg2)),
                                });
                            }
                            5 => {
                                main_reg = Some(Val {
                                    typ: ty::BOOL,
                                    data: Payload::from(self.is_lee(arg1, arg2)),
                                });
                            }
                            6 => {
                                main_reg = Some(Val {
                                    typ: ty::BOOL,
                                    data: Payload::from(!self.is_eq(arg1, arg2)),
                                });
                            }
                            7 => {
                                main_reg = Some(self.operate_sum(arg1, arg2));
                            }
                            8 => {
                                main_reg = Some(self.operate_subtract(arg1, arg2));
                            }
                            9 => {
                                main_reg = Some(self.operate_multiply(arg1, arg2));
                            }
                            10 => {
                                main_reg = Some(self.operate_division(arg1, arg2));
                            }
                            11 => {
                                main_reg = Some(self.operate_modulo(arg1, arg2));
                            }
                            12 => {
                                main_reg = Some(self.operate_power(arg1, arg2));
                            }
                            _ => {}
                        }
                        is_reg_state_final = false;
                        continue;
                    } else if self.registers.last().unwrap().get_state()
                        == ExecStates::IndexerExtractIndex
                    {
                        let regs = self.registers.last().unwrap().get_data();
                        let indexed = regs[0].clone();
                        let index = regs[1].clone();
                        self.registers.pop();
                        if index.typ == ty::STRING {
                            let __key = index.as_string();
                            if let Some(member) = CoreType::of_tag(indexed.typ)
                                .filter(|t| *t != CoreType::Map)
                                .and_then(|t| type_methods::resolve(t, &__key))
                            {
                                // A built-in List/String/num member, named with the
                                // universal Elpian vocabulary the front-end already
                                // resolved to. The executor holds no method names —
                                // `type_methods` owns them and says how to deliver
                                // this one (a getter, a bound native method, or a
                                // prelude closure fn), all straight over the single
                                // universal `stdlib::invoke`. Map members are handled
                                // in the object branch below (gated on no `__class`).
                                main_reg = Some(self.deliver_type_member(&indexed, &member));
                            } else if indexed.typ == ty::OBJECT {
                                let key = index.as_string();
                                let own = indexed.as_object().borrow().data.data.get(&key).cloned();
                                if let Some(o) = own {
                                    main_reg = Some(o);
                                } else if let Some(bound) = self.bind_proto_method(&indexed, &key) {
                                    // Not an own field: a class method, bound to the
                                    // receiver, so `obj.method(args)` runs with `this`.
                                    main_reg = Some(bound);
                                } else {
                                    // A plain Map (no `__class` tag) exposes Map
                                    // members; class instances do not.
                                    let is_plain_map = !indexed
                                        .as_object()
                                        .borrow()
                                        .data
                                        .data
                                        .contains_key("__class");
                                    let map_member = if is_plain_map {
                                        type_methods::resolve(CoreType::Map, &key)
                                    } else {
                                        None
                                    };
                                    if let Some(member) = map_member {
                                        // A plain-Map member (`length`/`keys`/`values`/
                                        // `isEmpty`/`has`/…): delivered by the same
                                        // registry-driven path as List/String/num.
                                        main_reg =
                                            Some(self.deliver_type_member(&indexed, &member));
                                    } else {
                                        // An absent key/field reads as the first-class
                                        // null — the VM's single "absent value".
                                        main_reg = Some(Val {
                                            typ: ty::NULL,
                                            data: Payload::Null,
                                        });
                                    }
                                }
                            } else {
                                eprintln!(
                                    "elpian error: non object value can not be indexed by string"
                                );
                                main_reg = Some(Val {
                                    typ: ty::NULL,
                                    data: Payload::Null,
                                });
                            }
                        } else if index.typ >= 1 && index.typ <= 3 {
                            if indexed.typ == ty::ARRAY {
                                let arr = indexed.as_array();
                                if index.typ == ty::I16 {
                                    if let Some(o) = arr.borrow().data.get(index.as_i16() as usize)
                                    {
                                        main_reg = Some(o.clone());
                                    } else {
                                        main_reg = Some(Val {
                                            typ: ty::NULL,
                                            data: Payload::Null,
                                        });
                                    }
                                } else if index.typ == ty::I32 {
                                    if let Some(o) = arr.borrow().data.get(index.as_i32() as usize)
                                    {
                                        main_reg = Some(o.clone());
                                    } else {
                                        main_reg = Some(Val {
                                            typ: ty::NULL,
                                            data: Payload::Null,
                                        });
                                    }
                                } else {
                                    if let Some(o) = arr.borrow().data.get(index.as_i64() as usize)
                                    {
                                        main_reg = Some(o.clone());
                                    } else {
                                        main_reg = Some(Val {
                                            typ: ty::NULL,
                                            data: Payload::Null,
                                        });
                                    }
                                }
                            } else {
                                eprintln!(
                                    "elpian error: non object value can not be indexed by string"
                                );
                                main_reg = Some(Val {
                                    typ: ty::NULL,
                                    data: Payload::Null,
                                });
                            }
                        } else {
                            eprintln!(
                            "elpian error: types other than integer and string can not be used to index anything"
                        );
                            main_reg = Some(Val {
                                typ: ty::NULL,
                                data: Payload::Null,
                            });
                        }
                        is_reg_state_final = false;
                        continue;
                    } else if self.registers.last().unwrap().get_state()
                        == ExecStates::NotValFinished
                    {
                        let data = self.registers.last().unwrap().get_data();
                        let val = data[0].clone();
                        self.registers.pop();
                        // `!x` is the boolean negation of the VM's truthiness,
                        // defined for every value (not just booleans).
                        main_reg = Some(Val {
                            typ: ty::BOOL,
                            data: Payload::from(!val.truthy()),
                        });
                        is_reg_state_final = false;
                        continue;
                    } else if self.registers.last().unwrap().get_state()
                        == ExecStates::SpreadFinished
                    {
                        // Wrap the inner value in a spread marker; the enclosing
                        // array / object / call builder flattens it.
                        let data = self.registers.last().unwrap().get_data();
                        let inner = data[0].clone();
                        self.registers.pop();
                        main_reg = Some(make_spread_marker(inner));
                        is_reg_state_final = false;
                        continue;
                    } else if self.registers.last().unwrap().get_state()
                        == ExecStates::TemplateFinished
                    {
                        // The joined interpolation is already built by the
                        // operation's `get_data`.
                        let data = self.registers.last().unwrap().get_data();
                        let joined = data[0].clone();
                        self.registers.pop();
                        main_reg = Some(joined);
                        is_reg_state_final = false;
                        continue;
                    } else if self.registers.last().unwrap().get_state()
                        == ExecStates::DestructureFinished
                    {
                        // Bind each name from the source value; a statement, so it
                        // produces no register value.
                        let plan = self.registers.last().unwrap().destructure_plan().unwrap();
                        let values = self.registers.last().unwrap().get_data();
                        self.registers.pop();
                        for (name, value) in apply_destructure(&plan, &values) {
                            self.define(name, value);
                        }
                        main_reg = None;
                        is_reg_state_final = false;
                        continue;
                    } else if self.registers.last().unwrap().get_state()
                        == ExecStates::CondBranchFinished
                    {
                        let regs = self.registers.last().unwrap().get_data();
                        let condition = regs[0].truthy();
                        let branch_true_start = regs[1].as_i64() as usize;
                        let branch_false_start = regs[2].as_i64() as usize;
                        if condition {
                            self.pointer = branch_true_start;
                        } else {
                            self.pointer = branch_false_start;
                        }
                        self.registers.pop();
                        is_reg_state_final = false;
                        continue;
                    } else if self.registers.last().unwrap().get_state()
                        == ExecStates::TypeTestFinished
                    {
                        let regs = self.registers.last().unwrap().get_data();
                        let value = regs[0].clone();
                        let type_name = regs[1].as_string();
                        let cast = regs[2].as_bool();
                        self.registers.pop();
                        let matches = value_is_type(&value, &type_name);
                        if cast {
                            // Checked cast: yield the value on a match; a
                            // mismatch throws (catchable by a guest `try`,
                            // trapping the instance when uncaught).
                            if matches {
                                main_reg = Some(value);
                            } else {
                                let err = self
                                    .native_error(format!("TypeError: value is not a {type_name}"));
                                self.begin_catch(err);
                                main_reg = None;
                                is_reg_state_final = false;
                                continue;
                            }
                        } else {
                            // `is`: the boolean result of the type test.
                            main_reg = Some(Val {
                                typ: ty::BOOL,
                                data: Payload::from(matches),
                            });
                        }
                        is_reg_state_final = false;
                        continue;
                    } else if self.registers.last().unwrap().get_state()
                        == ExecStates::CastOprtFinished
                    {
                        let regs = self.registers.last().unwrap().get_data();
                        let data = regs[0].clone();
                        let target_type = regs[1].as_string();
                        if target_type == "i16" {
                            match data.typ {
                                ty::I16 => {
                                    main_reg = Some(Val {
                                        typ: ty::I16,
                                        data: Payload::from(data.as_i16()),
                                    });
                                }
                                ty::I32 => {
                                    main_reg = Some(Val {
                                        typ: ty::I16,
                                        data: Payload::from(data.as_i32() as i16),
                                    });
                                }
                                ty::I64 => {
                                    main_reg = Some(Val {
                                        typ: ty::I16,
                                        data: Payload::from(data.as_i64() as i16),
                                    });
                                }
                                ty::F32 => {
                                    main_reg = Some(Val {
                                        typ: ty::I16,
                                        data: Payload::from(data.as_f32() as i16),
                                    });
                                }
                                ty::F64 => {
                                    main_reg = Some(Val {
                                        typ: ty::I16,
                                        data: Payload::from(data.as_f64() as i16),
                                    });
                                }
                                ty::BOOL => {
                                    main_reg = Some(Val {
                                        typ: ty::I16,
                                        data: Payload::from(
                                            if data.as_bool() { 1 } else { 0 } as i16
                                        ),
                                    });
                                }
                                ty::STRING => {
                                    main_reg = Some(Val {
                                        typ: ty::I16,
                                        data: Payload::from(
                                            data.as_string().parse::<i16>().unwrap(),
                                        ),
                                    });
                                }
                                _ => {
                                    main_reg = Some(Val {
                                        typ: ty::NULL,
                                        data: Payload::Null,
                                    });
                                }
                            }
                        } else if target_type == "i32" {
                            match data.typ {
                                ty::I16 => {
                                    main_reg = Some(Val {
                                        typ: ty::I32,
                                        data: Payload::from(data.as_i16() as i32),
                                    });
                                }
                                ty::I32 => {
                                    main_reg = Some(Val {
                                        typ: ty::I32,
                                        data: Payload::from(data.as_i32()),
                                    });
                                }
                                ty::I64 => {
                                    main_reg = Some(Val {
                                        typ: ty::I32,
                                        data: Payload::from(data.as_i64() as i32),
                                    });
                                }
                                ty::F32 => {
                                    main_reg = Some(Val {
                                        typ: ty::I32,
                                        data: Payload::from(data.as_f32() as i32),
                                    });
                                }
                                ty::F64 => {
                                    main_reg = Some(Val {
                                        typ: ty::I32,
                                        data: Payload::from(data.as_f64() as i32),
                                    });
                                }
                                ty::BOOL => {
                                    main_reg = Some(Val {
                                        typ: ty::I32,
                                        data: Payload::from(if data.as_bool() { 1 } else { 0 }),
                                    });
                                }
                                ty::STRING => {
                                    main_reg = Some(Val {
                                        typ: ty::I32,
                                        data: Payload::from(
                                            data.as_string().parse::<i32>().unwrap(),
                                        ),
                                    });
                                }
                                _ => {
                                    main_reg = Some(Val {
                                        typ: ty::NULL,
                                        data: Payload::Null,
                                    });
                                }
                            }
                        } else if target_type == "i64" {
                            match data.typ {
                                ty::I16 => {
                                    main_reg = Some(Val {
                                        typ: ty::I64,
                                        data: Payload::from(data.as_i16() as i64),
                                    });
                                }
                                ty::I32 => {
                                    main_reg = Some(Val {
                                        typ: ty::I64,
                                        data: Payload::from(data.as_i32() as i64),
                                    });
                                }
                                ty::I64 => {
                                    main_reg = Some(Val {
                                        typ: ty::I64,
                                        data: Payload::from(data.as_i64()),
                                    });
                                }
                                ty::F32 => {
                                    main_reg = Some(Val {
                                        typ: ty::I64,
                                        data: Payload::from(data.as_f32() as i64),
                                    });
                                }
                                ty::F64 => {
                                    main_reg = Some(Val {
                                        typ: ty::I64,
                                        data: Payload::from(data.as_f64() as i64),
                                    });
                                }
                                ty::BOOL => {
                                    main_reg = Some(Val {
                                        typ: ty::I64,
                                        data: Payload::from(
                                            if data.as_bool() { 1 } else { 0 } as i64
                                        ),
                                    });
                                }
                                ty::STRING => {
                                    main_reg = Some(Val {
                                        typ: ty::I64,
                                        data: Payload::from(
                                            data.as_string().parse::<i64>().unwrap(),
                                        ),
                                    });
                                }
                                _ => {
                                    main_reg = Some(Val {
                                        typ: ty::NULL,
                                        data: Payload::Null,
                                    });
                                }
                            }
                        } else if target_type == "f32" {
                            match data.typ {
                                ty::I16 => {
                                    main_reg = Some(Val {
                                        typ: ty::F32,
                                        data: Payload::from(data.as_i16() as f32),
                                    });
                                }
                                ty::I32 => {
                                    main_reg = Some(Val {
                                        typ: ty::F32,
                                        data: Payload::from(data.as_i32() as f32),
                                    });
                                }
                                ty::I64 => {
                                    main_reg = Some(Val {
                                        typ: ty::F32,
                                        data: Payload::from(data.as_i64() as f32),
                                    });
                                }
                                ty::F32 => {
                                    main_reg = Some(Val {
                                        typ: ty::F32,
                                        data: Payload::from(data.as_f32()),
                                    });
                                }
                                ty::F64 => {
                                    main_reg = Some(Val {
                                        typ: ty::F32,
                                        data: Payload::from(data.as_f64() as f32),
                                    });
                                }
                                ty::BOOL => {
                                    main_reg = Some(Val {
                                        typ: ty::F32,
                                        data: Payload::from(
                                            if data.as_bool() { 1 } else { 0 } as f32
                                        ),
                                    });
                                }
                                ty::STRING => {
                                    main_reg = Some(Val {
                                        typ: ty::F32,
                                        data: Payload::from(
                                            data.as_string().parse::<f32>().unwrap(),
                                        ),
                                    });
                                }
                                _ => {
                                    main_reg = Some(Val {
                                        typ: ty::NULL,
                                        data: Payload::Null,
                                    });
                                }
                            }
                        } else if target_type == "f64" || target_type == "number" {
                            // `number` is the VM's unified numeric type name,
                            // aliased onto the f64 representation.
                            match data.typ {
                                ty::I16 => {
                                    main_reg = Some(Val {
                                        typ: ty::F64,
                                        data: Payload::from(data.as_i16() as f64),
                                    });
                                }
                                ty::I32 => {
                                    main_reg = Some(Val {
                                        typ: ty::F64,
                                        data: Payload::from(data.as_i32() as f64),
                                    });
                                }
                                ty::I64 => {
                                    main_reg = Some(Val {
                                        typ: ty::F64,
                                        data: Payload::from(data.as_i64() as f64),
                                    });
                                }
                                ty::F32 => {
                                    main_reg = Some(Val {
                                        typ: ty::F64,
                                        data: Payload::from(data.as_f32() as f64),
                                    });
                                }
                                ty::F64 => {
                                    main_reg = Some(Val {
                                        typ: ty::F64,
                                        data: Payload::from(data.as_f64()),
                                    });
                                }
                                ty::BOOL => {
                                    main_reg = Some(Val {
                                        typ: ty::F64,
                                        data: Payload::from(
                                            if data.as_bool() { 1 } else { 0 } as f64
                                        ),
                                    });
                                }
                                ty::STRING => {
                                    main_reg = Some(Val {
                                        typ: ty::F64,
                                        data: Payload::from(
                                            data.as_string().parse::<f64>().unwrap(),
                                        ),
                                    });
                                }
                                _ => {
                                    main_reg = Some(Val {
                                        typ: ty::NULL,
                                        data: Payload::Null,
                                    });
                                }
                            }
                        } else if target_type == "bool" {
                            match data.typ {
                                ty::I16 => {
                                    main_reg = Some(Val {
                                        typ: ty::BOOL,
                                        data: Payload::from(data.as_i16() > 0),
                                    });
                                }
                                ty::I32 => {
                                    main_reg = Some(Val {
                                        typ: ty::BOOL,
                                        data: Payload::from(data.as_i32() > 0),
                                    });
                                }
                                ty::I64 => {
                                    main_reg = Some(Val {
                                        typ: ty::BOOL,
                                        data: Payload::from(data.as_i64() > 0),
                                    });
                                }
                                ty::F32 => {
                                    main_reg = Some(Val {
                                        typ: ty::BOOL,
                                        data: Payload::from(data.as_f32() > 0.0),
                                    });
                                }
                                ty::F64 => {
                                    main_reg = Some(Val {
                                        typ: ty::BOOL,
                                        data: Payload::from(data.as_f64() > 0.0),
                                    });
                                }
                                ty::BOOL => {
                                    main_reg = Some(Val {
                                        typ: ty::BOOL,
                                        data: Payload::from(data.as_bool()),
                                    });
                                }
                                ty::STRING => {
                                    main_reg = Some(Val {
                                        typ: ty::BOOL,
                                        data: Payload::from(data.as_string() == "true"),
                                    });
                                }
                                _ => {
                                    main_reg = Some(Val {
                                        typ: ty::NULL,
                                        data: Payload::Null,
                                    });
                                }
                            }
                        } else if target_type == "string" {
                            match data.typ {
                                ty::I16 => {
                                    main_reg = Some(Val {
                                        typ: ty::STRING,
                                        data: Payload::from(data.as_i16().to_string()),
                                    });
                                }
                                ty::I32 => {
                                    main_reg = Some(Val {
                                        typ: ty::STRING,
                                        data: Payload::from(data.as_i32().to_string()),
                                    });
                                }
                                ty::I64 => {
                                    main_reg = Some(Val {
                                        typ: ty::STRING,
                                        data: Payload::from(data.as_i64().to_string()),
                                    });
                                }
                                ty::F32 => {
                                    main_reg = Some(Val {
                                        typ: ty::STRING,
                                        data: Payload::from(data.as_f32().to_string()),
                                    });
                                }
                                ty::F64 => {
                                    main_reg = Some(Val {
                                        typ: ty::STRING,
                                        data: Payload::from(data.as_f64().to_string()),
                                    });
                                }
                                ty::BOOL => {
                                    main_reg = Some(Val {
                                        typ: ty::STRING,
                                        data: Payload::from(data.as_bool().to_string()),
                                    });
                                }
                                ty::STRING => {
                                    main_reg = Some(Val {
                                        typ: ty::STRING,
                                        data: Payload::from(data.as_string()),
                                    });
                                }
                                ty::OBJECT => {
                                    main_reg = Some(Val {
                                        typ: ty::STRING,
                                        data: Payload::from(data.stringify()),
                                    });
                                }
                                ty::ARRAY => {
                                    main_reg = Some(Val {
                                        typ: ty::STRING,
                                        data: Payload::from(data.stringify()),
                                    });
                                }
                                _ => {
                                    main_reg = Some(Val {
                                        typ: ty::NULL,
                                        data: Payload::Null,
                                    });
                                }
                            }
                        }
                        self.registers.pop();
                        is_reg_state_final = false;
                        continue;
                    }
                } else {
                    main_reg = None;
                }
            }
            let mut terminate = false;
            if self.pointer == self.end_at {
                while self.pointer == self.end_at {
                    if self.ctx.memory.len() == 1 {
                        terminate = true;
                        break;
                    }
                    // Only a *function-body* frame owns a `DummyOp` register (pushed
                    // at call dispatch). Control-flow bodies (`ifBody`/`loopBody`/
                    // `switchBody`) are plain scopes with no register of their own, so
                    // their teardown must NOT pop the enclosing function's `DummyOp`
                    // — doing so would unbalance the register stack and let a
                    // statement after the block leak its value into the caller's
                    // awaiting expression (the bug behind "array used as object key"
                    // traps and corrupted returns in larger programs).
                    let popped_tag = self.ctx.memory.last().unwrap().borrow().tag.clone();
                    self.pop_scope_governed();
                    if is_partial_exec && (self.ctx.memory.len() == 1) {
                        return self.pending_func_result_value.clone();
                    }
                    if popped_tag == "funcBody"
                        && !self.registers.is_empty()
                        && self.registers.last().unwrap().get_type() == OperationTypes::Dummy
                    {
                        self.registers.pop();
                    }
                    if !self.ctx.memory.is_empty() {
                        self.pointer = self.ctx.memory.last().unwrap().borrow().frozen_pointer;
                        self.end_at = self.ctx.memory.last().unwrap().borrow().frozen_end;
                        if self.pending_func_result_value.typ != ty::NO_VALUE {
                            // A `return` is propagating to a caller. The callee's
                            // own nested scopes were already unwound at the point
                            // of return, so here we only hand the value to the
                            // caller's awaiting expression register (an in-program
                            // call). The caller's scope stack is left untouched —
                            // it may legitimately sit inside its own control block.
                            let returned_val = self.pending_func_result_value.clone();
                            self.pending_func_result_value = Val {
                                typ: ty::NO_VALUE,
                                data: Payload::Null,
                            };
                            if !self.registers.is_empty() {
                                main_reg = Some(returned_val);
                                is_reg_state_final = false;
                                break;
                            }
                        }
                    } else {
                        terminate = true;
                        break;
                    }
                }
                if terminate {
                    break;
                }
                continue;
            }
            // Fetch the pre-decoded operation at the program counter and advance
            // to the next unit (control-flow arms below override the pointer
            // afterwards). The bytecode is never re-parsed: every operand was
            // decoded once into the unit, and branch targets are unit indices
            // (see `program.rs`).
            let kind = self.prog.units[self.pointer].clone();
            self.pointer += 1;
            match kind {
                // ----------------------------------
                // arithmetic / comparison operators (op id 1..=12)
                UnitKind::Arith(op_id) => {
                    self.registers.push(Box::new(Arithmetic::new()));
                    self.registers
                        .last_mut()
                        .unwrap()
                        .set_state(ExecStates::ArithmeticExtractOp, StateData::I16(op_id));
                }
                // not operator
                UnitKind::Not => {
                    self.registers.push(Box::new(NotValue::new()));
                }
                // short-circuiting logical && / || / ??
                UnitKind::Logical { kind, op2_end } => {
                    self.registers.push(Box::new(LogicalOp::new(kind, op2_end)));
                }
                // conditional / ternary expression
                UnitKind::Conditional { alt_start, end } => {
                    self.registers
                        .push(Box::new(ConditionalOp::new(alt_start, end)));
                }
                // cast operation (target type folded into the unit)
                UnitKind::Cast { target_type } => {
                    self.registers
                        .push(Box::new(CastOp::new(target_type.to_string())));
                }
                // reified type test `is` / `as` (type name + mode folded in)
                UnitKind::TypeTest { type_name, cast } => {
                    self.registers
                        .push(Box::new(TypeTestOp::new(type_name.to_string(), cast)));
                }
                // ----------------------------------
                // program operators:
                // data indexer
                UnitKind::Indexer => {
                    self.registers.push(Box::new(IndexerValue::new()));
                }
                // function call (argument count folded into the unit)
                UnitKind::Call { argc } => {
                    self.registers
                        .push(Box::new(CallFunction::new(argc as i32)));
                }
                // definition statement (name pre-decoded; value expression follows)
                UnitKind::DefineVar(name) => {
                    self.registers.push(Box::new(DefineVariable::new()));
                    self.registers.last_mut().unwrap().set_state(
                        ExecStates::DefineVarExtractName,
                        StateData::Str(name.to_string()),
                    );
                }
                // assignment statement (target name + kind pre-decoded)
                UnitKind::AssignVar { name, kind } => {
                    self.registers.push(Box::new(AssignVariable::new()));
                    self.registers.last_mut().unwrap().set_state(
                        ExecStates::AssignVarExtractName,
                        StateData::StrI16(name.to_string(), kind),
                    );
                }
                // if statement (one arm of an if/else chain; targets folded in)
                UnitKind::IfHead {
                    has_condition,
                    body_start,
                    body_end,
                    next,
                    branch_after,
                } => {
                    self.registers.push(Box::new(IfStmt::new(
                        has_condition,
                        body_start,
                        body_end,
                        next,
                        branch_after,
                    )));
                    if !has_condition {
                        // The unconditional `else` arm is already decided (the
                        // operation starts finished); run its finalizer next step.
                        main_reg = None;
                        is_reg_state_final = true;
                        continue;
                    }
                }
                // loop statement (bounds folded into the unit)
                UnitKind::Loop {
                    body_start,
                    body_end,
                    branch_after,
                } => {
                    self.registers.push(Box::new(LoopStmt::new(
                        body_start,
                        body_end,
                        branch_after,
                    )));
                }
                // switch case statement (branch-after + case table folded in)
                UnitKind::Switch {
                    branch_after,
                    cases,
                } => {
                    self.registers
                        .push(Box::new(SwitchStmt::new(branch_after, cases)));
                }
                // function definition (header pre-decoded; body skipped here)
                UnitKind::FuncDef {
                    name,
                    params,
                    frees,
                    start,
                    end,
                } => {
                    let mut func = Function::new(name.to_string(), start, end, (*params).clone());
                    // A function defined inside another function closes over the
                    // enclosing locals it uses (e.g. a factory returning a
                    // counter). Capture just those free variables; at top level
                    // there is nothing to capture and this is a no-op.
                    func.captured = self.capture_named(&frees);
                    self.define(
                        name.to_string(),
                        Val {
                            typ: ty::FUNCTION,
                            data: Payload::from(Rc::new(RefCell::new(func))),
                        },
                    );
                    self.pointer = end;
                }
                // return command
                UnitKind::Return => {
                    self.registers.push(Box::new(ReturnValue::new()));
                }
                // throw command (value expression follows)
                UnitKind::Throw => {
                    self.registers.push(Box::new(ThrowValue::new()));
                }
                // try/catch: record a try frame (scope/register depths as they
                // are *now*, before the body scope), park the resume point past
                // the catch body, and enter the protected body. Normal completion
                // tears the body scope down like any block and resumes at
                // `catch_end`; a throw anywhere inside (any call depth) unwinds
                // back here and enters the catch body instead.
                UnitKind::TryHead {
                    body_start,
                    body_end,
                    catch_start,
                    catch_end,
                    err_name,
                } => {
                    self.ctx
                        .memory
                        .last()
                        .unwrap()
                        .borrow_mut()
                        .update_frozen_pointer(catch_end);
                    self.try_stack.push(TryFrame {
                        catch_start,
                        catch_end,
                        err_name,
                        scope_depth: self.ctx.memory.len(),
                        register_depth: self.registers.len(),
                    });
                    self.ctx
                        .push_scope("tryBody".to_string(), body_start, body_start, body_end);
                    self.pointer = body_start;
                    self.end_at = body_end;
                }
                // jump command
                UnitKind::Jump(dest) => {
                    self.pointer = dest;
                }
                // `continue` — unwind any control-flow scopes (if/switch bodies)
                // opened since the loop body, then re-run the loop head. The loop
                // body's last unit is the compiler's back-jump to the condition, so
                // jumping there re-evaluates it (and, for `for`, runs the update,
                // which the desugaring places at the head on the `continue` path).
                UnitKind::Continue => {
                    loop {
                        let tag = self.ctx.memory.last().unwrap().borrow().tag.clone();
                        if tag == "loopBody" {
                            let body_end = self.ctx.memory.last().unwrap().borrow().frozen_end;
                            self.end_at = body_end;
                            self.pointer = body_end - 1; // the back-jump unit
                            break;
                        }
                        // `continue` not inside a loop (e.g. a stray statement, or
                        // only switch/function scopes around it): nothing to do.
                        if tag == "funcBody" || self.ctx.memory.len() == 1 {
                            break;
                        }
                        self.pop_scope_governed();
                    }
                }
                // `break` — unwind to the nearest enclosing loop or switch body and
                // fall through its end so the normal teardown resumes after it.
                UnitKind::Break => loop {
                    let tag = self.ctx.memory.last().unwrap().borrow().tag.clone();
                    if tag == "loopBody" || tag == "switchBody" {
                        let body_end = self.ctx.memory.last().unwrap().borrow().frozen_end;
                        self.end_at = body_end;
                        self.pointer = body_end;
                        break;
                    }
                    if tag == "funcBody" || self.ctx.memory.len() == 1 {
                        break;
                    }
                    self.pop_scope_governed();
                },
                // conditional branch (targets folded into the unit)
                UnitKind::CondBranch {
                    true_branch,
                    false_branch,
                } => {
                    self.registers
                        .push(Box::new(CondBranch::new(true_branch, false_branch)));
                }
                // ----------------------------------
                // expressions
                // scalar / string literal
                UnitKind::Lit(val) => {
                    main_reg = Some(val);
                    continue;
                }
                // identifier reference (resolved against scope / builtins / host)
                UnitKind::Ident(name) => {
                    let val = self.resolve_ident(&name);
                    main_reg = Some(val);
                    continue;
                }
                // function literal (closure over the live environment)
                UnitKind::FuncLit { start, end, params } => {
                    let mut func = Function::new(String::new(), start, end, (*params).clone());
                    func.captured = self.capture_env();
                    main_reg = Some(Val {
                        typ: ty::FUNCTION,
                        data: Payload::from(Rc::new(RefCell::new(func))),
                    });
                    continue;
                }
                // object expression
                UnitKind::ObjHead { typ, props_len } => {
                    self.registers.push(Box::new(ObjectExpr::new()));
                    self.registers.last_mut().unwrap().set_state(
                        ExecStates::ObjExprExtractInfo,
                        StateData::I64I32(typ, props_len),
                    );
                    if self.registers.last().unwrap().get_state() == ExecStates::ObjExprFinished {
                        main_reg = None;
                        is_reg_state_final = true;
                        continue;
                    }
                }
                // array expression
                UnitKind::ArrHead { len } => {
                    self.registers.push(Box::new(ArrayExpr::new()));
                    self.registers
                        .last_mut()
                        .unwrap()
                        .set_state(ExecStates::ArrExprExtractInfo, StateData::I32(len));
                    if self.registers.last().unwrap().get_state() == ExecStates::ArrExprFinished {
                        main_reg = None;
                        is_reg_state_final = true;
                        continue;
                    }
                }
                // spread element `...value` (the inner value expression follows)
                UnitKind::Spread => {
                    self.registers.push(Box::new(SpreadOp::new()));
                }
                // object-spread key marker: emits the marker value directly (no
                // operand), exactly like a literal.
                UnitKind::SpreadKey => {
                    main_reg = Some(Val {
                        typ: SPREAD_KEY_MARKER,
                        data: Payload::Null,
                    });
                    continue;
                }
                // interpolated / template string (part count folded into the unit)
                UnitKind::Template { count } => {
                    self.registers.push(Box::new(TemplateExpr::new()));
                    self.registers.last_mut().unwrap().set_state(
                        ExecStates::TemplateExtractInfo,
                        StateData::I32(count as i32),
                    );
                    if self.registers.last().unwrap().get_state() == ExecStates::TemplateFinished {
                        main_reg = None;
                        is_reg_state_final = true;
                        continue;
                    }
                }
                // destructuring binding (plan folded into the unit; source and
                // default value expressions follow)
                UnitKind::Destructure { plan } => {
                    self.registers.push(Box::new(DestructureOp::new(plan)));
                }
                // ----------------------------------
                // Bare immediates (consumed by a state transition, not dispatched
                // here) and no-op padding: nothing to do, exactly like the old
                // fall-through arm.
                UnitKind::Nop => {}
            }
        }
        Val::new(ty::NULL, Payload::Null)
    }
}
