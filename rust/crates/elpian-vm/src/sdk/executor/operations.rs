//! The operation vocabulary: what a compiled program is made of.
//!
//! Each unit the compiler emits becomes an [`Operation`] pushed onto the
//! executor's register stack. An operation is a small state machine: the run
//! loop feeds it values with [`Operation::set_state`] as its operands finish
//! evaluating, and reads them back with [`Operation::get_data`] once it is
//! complete.
//!
//! Split out of `executor.rs`, which held this vocabulary and the interpreter
//! that runs it in one 6,000-line file.

use crate::sdk::{
    data::{ty, Array, Function, Object, Payload, Val, ValGroup, ValMap},
    program::{DestructurePlan, LogicalKind},
};
use std::{cell::RefCell, fmt, rc::Rc};

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum OperationTypes {
    DefineVar,
    AssignVar,
    CallFunc,
    ReturnVal,
    ThrowVal,
    IfStmt,
    LoopStmt,
    SwitchStmt,
    Arithmetic,
    Indexer,
    NotVal,
    ObjExpr,
    ArrExpr,
    CondBrch,
    CastOprt,
    TypeTest,
    Logical,
    Conditional,
    Spread,
    Template,
    Destructure,
    Dummy,
}

impl fmt::Display for OperationTypes {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:?}", self)
    }
}

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum ExecStates {
    AssignVarExtractName,
    AssignVarExtractIndex,
    AssignVarExtractValue,
    DefineVarExtractName,
    DefineVarExtractValue,
    CallFuncStarted,
    CallFuncExtractFunc,
    CallFuncExtractParam,
    CallFuncFinished,
    ReturnValStarted,
    ReturnValFinished,
    ThrowValStarted,
    ThrowValFinished,
    IfStmtIsConditioned,
    IfStmtFinished,
    LoopStmtStarted,
    LoopStmtFinished,
    SwitchStmtStarted,
    SwitchStmtExtractVal,
    SwitchStmtExtractCase,
    SwitchStmtFinished,
    ArithmeticStarted,
    ArithmeticExtractOp,
    ArithmeticExtractArg1,
    ArithmeticExtractArg2,
    IndexerStarted,
    IndexerExtractVarName,
    IndexerExtractIndex,
    NotValStarted,
    NotValFinished,
    ObjExprStarted,
    ObjExprExtractInfo,
    ObjExprExtractProp,
    ObjExprFinished,
    ArrExprStarted,
    ArrExprExtractInfo,
    ArrExprExtractItem,
    ArrExprFinished,
    CondBranchStarted,
    CondBranchFinished,
    CastOprtStarted,
    CastOprtFinished,
    TypeTestStarted,
    TypeTestFinished,
    LogicalExtractOp1,
    LogicalExtractOp2,
    CondExprExtractCond,
    CondExprExtractValue,
    SpreadStarted,
    SpreadFinished,
    TemplateExtractInfo,
    TemplateExtractPart,
    TemplateFinished,
    DestructureExtractValue,
    DestructureFinished,
    Dummy,
}

impl fmt::Display for ExecStates {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:?}", self)
    }
}

/// The payload handed to [`Operation::set_state`] on a state transition.
///
/// This used to be a `Box<dyn Any>`, which heap-allocated (and then dynamically
/// downcast) on *every* operation step — the arithmetic operand flow alone does
/// this hundreds of thousands of times per frame. A closed enum of the handful
/// of shapes the executor actually feeds keeps the payload on the stack: no
/// allocation, no vtable, no downcast. Each `(operation, state)` pair fixes the
/// shape, so the matching extractor is unambiguous (and a mismatch is a bug, not
/// a recoverable case — hence `unreachable!`).
pub enum StateData {
    Empty,
    Val(Val),
    I16(i16),
    I32(i32),
    Str(String),
    StrI16(String, i16),
    I64I32(i64, i32),
}

impl StateData {
    #[inline]
    fn val(self) -> Val {
        match self {
            StateData::Val(v) => v,
            _ => unreachable!("StateData::val on a non-Val payload"),
        }
    }
    #[inline]
    fn i16v(self) -> i16 {
        match self {
            StateData::I16(v) => v,
            _ => unreachable!("StateData::i16v on a non-I16 payload"),
        }
    }
    #[inline]
    fn i32v(self) -> i32 {
        match self {
            StateData::I32(v) => v,
            _ => unreachable!("StateData::i32v on a non-I32 payload"),
        }
    }
    #[inline]
    fn string(self) -> String {
        match self {
            StateData::Str(v) => v,
            _ => unreachable!("StateData::string on a non-Str payload"),
        }
    }
    #[inline]
    fn str_i16(self) -> (String, i16) {
        match self {
            StateData::StrI16(s, n) => (s, n),
            _ => unreachable!("StateData::str_i16 on a non-StrI16 payload"),
        }
    }
    #[inline]
    fn i64_i32(self) -> (i64, i32) {
        match self {
            StateData::I64I32(a, b) => (a, b),
            _ => unreachable!("StateData::i64_i32 on a non-I64I32 payload"),
        }
    }
}

/// The two `Operation` accessors every implementation writes identically.
///
/// Each operation struct carries a `typ` and a `state` field, and every one of
/// the 22 implementations returned them with the same four lines. Only
/// `set_state` and `get_data` differ per operation, so those stay written out
/// where they can be read; this removes the part that was pure repetition.
macro_rules! operation_accessors {
    () => {
        fn get_state(&self) -> ExecStates {
            self.state
        }

        fn get_type(&self) -> OperationTypes {
            self.typ
        }
    };
}

pub trait Operation {
    fn get_type(&self) -> OperationTypes;
    fn get_state(&self) -> ExecStates;
    fn set_state(&mut self, state: ExecStates, data: StateData);
    fn get_data(&self) -> Vec<Val>;
    /// For a [`SwitchStmt`] mid-collection: the `(body_start, body_end)` unit
    /// range of the *next* case about to be collected. The run loop reads the
    /// end to skip the case body once its value has been evaluated. Other
    /// operations never collect cases, so the default is unused.
    fn next_case_bounds(&self) -> (usize, usize) {
        (0, 0)
    }
    /// For a [`Destructure`] operation: the binding plan describing how to bind
    /// the collected source (and default) values. Every other operation returns
    /// `None`; the executor only asks a `Destructure` register for it.
    fn destructure_plan(&self) -> Option<Rc<DestructurePlan>> {
        None
    }
}

impl fmt::Debug for dyn Operation {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Operation{{{} {}}}", self.get_type(), self.get_state())
    }
}

pub(super) struct DefineVariable {
    typ: OperationTypes,
    state: ExecStates,
    pub var_name: Option<String>,
    pub var_value: Option<Val>,
}

impl DefineVariable {
    pub(super) fn new() -> Self {
        DefineVariable {
            typ: OperationTypes::DefineVar,
            state: ExecStates::DefineVarExtractName,
            var_name: None,
            var_value: None,
        }
    }
}

impl Operation for DefineVariable {
    operation_accessors!();

    fn set_state(&mut self, state: ExecStates, data: StateData) {
        self.state = state;
        if state == ExecStates::DefineVarExtractName {
            self.var_name = Some(data.string());
        } else if state == ExecStates::DefineVarExtractValue {
            self.var_value = Some(data.val());
        }
    }

    fn get_data(&self) -> Vec<Val> {
        vec![
            Val {
                typ: ty::STRING,
                data: Payload::from(self.var_name.clone().unwrap()),
            },
            self.var_value.clone().unwrap(),
        ]
    }
}

pub(super) struct AssignVariable {
    typ: OperationTypes,
    state: ExecStates,
    pub var_name: Option<String>,
    pub assign_target_type: i16,
    pub index: Option<Val>,
    pub var_value: Option<Val>,
}

impl AssignVariable {
    pub(super) fn new() -> Self {
        AssignVariable {
            typ: OperationTypes::AssignVar,
            state: ExecStates::AssignVarExtractName,
            var_name: None,
            assign_target_type: 0,
            index: None,
            var_value: None,
        }
    }
}

impl Operation for AssignVariable {
    operation_accessors!();

    fn set_state(&mut self, state: ExecStates, data: StateData) {
        self.state = state;
        if state == ExecStates::AssignVarExtractName {
            let (var_name, assign_target_type) = data.str_i16();
            self.var_name = Some(var_name.clone());
            self.assign_target_type = assign_target_type;
        } else if state == ExecStates::AssignVarExtractIndex {
            if self.assign_target_type == 2 {
                self.index = Some(data.val());
            } else {
                panic!("elpian error: wrong state set to assignment operation");
            }
        } else if state == ExecStates::AssignVarExtractValue {
            self.var_value = Some(data.val());
        }
    }

    fn get_data(&self) -> Vec<Val> {
        if self.assign_target_type == 2 {
            // The index is only known after `AssignVarExtractIndex`; callers that
            // read `get_data` earlier (e.g. to inspect the target type while still
            // in `AssignVarExtractName`) get a typed-null placeholder for it.
            let index = self.index.clone().unwrap_or(Val {
                typ: ty::NULL,
                data: Payload::Null,
            });
            if self.var_value.is_none() {
                vec![
                    Val {
                        typ: ty::STRING,
                        data: Payload::from(self.var_name.clone().unwrap()),
                    },
                    Val {
                        typ: ty::BOOL,
                        data: Payload::from(self.assign_target_type),
                    },
                    index,
                    Val {
                        typ: ty::NULL,
                        data: Payload::Null,
                    },
                ]
            } else {
                vec![
                    Val {
                        typ: ty::STRING,
                        data: Payload::from(self.var_name.clone().unwrap()),
                    },
                    Val {
                        typ: ty::BOOL,
                        data: Payload::from(self.assign_target_type),
                    },
                    index,
                    self.var_value.clone().unwrap(),
                ]
            }
        } else {
            if self.var_value.is_none() {
                vec![
                    Val {
                        typ: ty::STRING,
                        data: Payload::from(self.var_name.clone().unwrap()),
                    },
                    Val {
                        typ: ty::BOOL,
                        data: Payload::from(self.assign_target_type),
                    },
                    Val {
                        typ: ty::NULL,
                        data: Payload::Null,
                    },
                    Val {
                        typ: ty::NULL,
                        data: Payload::Null,
                    },
                ]
            } else {
                vec![
                    Val {
                        typ: ty::STRING,
                        data: Payload::from(self.var_name.clone().unwrap()),
                    },
                    Val {
                        typ: ty::BOOL,
                        data: Payload::from(self.assign_target_type),
                    },
                    Val {
                        typ: ty::NULL,
                        data: Payload::Null,
                    },
                    self.var_value.clone().unwrap(),
                ]
            }
        }
    }
}

pub(super) struct CallFunction {
    typ: OperationTypes,
    state: ExecStates,
    pub func: Option<Rc<RefCell<Function>>>,
    pub is_native: bool,
    pub param_count: i32,
    pub params: Vec<Val>,
}

impl CallFunction {
    /// `param_count` is the number of arguments the *call site* provides, folded
    /// into the `Call` unit at decode time (so it no longer trails the callee in
    /// the instruction stream).
    pub(super) fn new(param_count: i32) -> Self {
        CallFunction {
            typ: OperationTypes::CallFunc,
            state: ExecStates::CallFuncStarted,
            func: None,
            param_count,
            is_native: false,
            params: vec![],
        }
    }
}

impl Operation for CallFunction {
    operation_accessors!();

    fn set_state(&mut self, state: ExecStates, data: StateData) {
        self.state = state;
        if state == ExecStates::CallFuncExtractFunc {
            // The callee value just evaluated; the argument count is already known
            // (folded into the `Call` unit, stored as `param_count` at creation).
            let callee = data.val();
            if callee.typ == ty::FUNCTION {
                self.func = Some(callee.as_func());
                self.is_native = false;
            } else if callee.typ == ty::ASK_HOST {
                self.func = Some(Rc::new(RefCell::new(Function::new(
                    "".to_string(),
                    0,
                    0,
                    vec!["apiName".to_string(), "input".to_string()],
                ))));
                self.param_count = 2;
                self.is_native = true;
            } else if callee.typ == ty::NATIVE_BUILTIN {
                // Native standard-library builtin. The finish check gates on the
                // call-site argument count (`param_count`), and the builtin reads
                // its arguments positionally from the provided-args array — the
                // formal parameter *names* are never consulted. So we skip building
                // the `arg0..argN` name list entirely (it allocated one `String`
                // per argument on every native call, the hottest path in the VM).
                let name = callee.as_string();
                self.func = Some(Rc::new(RefCell::new(Function::new(name, 0, 0, Vec::new()))));
                self.is_native = true;
            } else if callee.typ == ty::BOUND_NATIVE {
                // Bound native method: [receiver, "<universalName>"]. Dispatch as
                // the like-named native builtin whose receiver is threaded via
                // `this_arg` and prepended to the argument list at the call site.
                let holder = callee.as_array();
                let (receiver, name) = {
                    let b = holder.borrow();
                    (b.data[0].clone(), b.data[1].as_string())
                };
                // Keep the builtin name (bind() would blank it) and thread the
                // receiver via this_arg so native dispatch prepends it.
                let mut f = Function::new(name, 0, 0, Vec::new());
                f.this_arg = Some(receiver);
                self.func = Some(Rc::new(RefCell::new(f)));
                self.is_native = true;
            } else {
                panic!("elpian error: the specified data is not runnable");
            }
        } else if state == ExecStates::CallFuncExtractParam {
            self.params.push(data.val());
        }
        if self.func.is_some() {
            // Collect exactly as many argument values as the *call site* provided
            // (`param_count`), not as many as the function declares. VM calls are
            // arity-flexible: extra arguments are ignored and missing ones bind
            // to null (done when the frame is built), so front-ends can express
            // their language's arity rules on top. Gating on the declared param
            // count desynced the arg stream whenever a function was called with
            // fewer arguments than it declares.
            if self.params.len() >= self.param_count.max(0) as usize {
                self.state = ExecStates::CallFuncFinished;
            }
        }
    }

    fn get_data(&self) -> Vec<Val> {
        vec![
            Val {
                typ: ty::FUNCTION,
                data: Payload::from(self.func.clone().unwrap()),
            },
            Val {
                typ: ty::BOOL,
                data: Payload::from(self.is_native),
            },
            Val {
                typ: ty::I32,
                data: Payload::from(self.param_count),
            },
            Val {
                typ: ty::ARRAY,
                data: Payload::from(Rc::new(RefCell::new(Array::new(
                    // Expand any spread arguments (`f(...args)`) into the flat
                    // positional list before the frame is built or a native
                    // builtin reads them. A call with no spreads is untouched.
                    flatten_spread(&self.params),
                )))),
            },
        ]
    }
}

pub(super) struct ReturnValue {
    typ: OperationTypes,
    state: ExecStates,
    pub value: Option<Val>,
}

impl ReturnValue {
    pub(super) fn new() -> Self {
        ReturnValue {
            typ: OperationTypes::ReturnVal,
            state: ExecStates::ReturnValStarted,
            value: None,
        }
    }
}

impl Operation for ReturnValue {
    operation_accessors!();

    fn set_state(&mut self, state: ExecStates, data: StateData) {
        self.state = state;
        if state == ExecStates::ReturnValFinished {
            self.value = Some(data.val());
        }
    }

    fn get_data(&self) -> Vec<Val> {
        vec![self.value.clone().unwrap()]
    }
}

/// The `throw` statement's value collector — the throwing twin of
/// [`ReturnValue`]: the value expression that follows the `Throw` unit lands
/// here, and the dispatch loop then raises it through the try stack.
pub(super) struct ThrowValue {
    typ: OperationTypes,
    state: ExecStates,
    pub value: Option<Val>,
}

impl ThrowValue {
    pub(super) fn new() -> Self {
        ThrowValue {
            typ: OperationTypes::ThrowVal,
            state: ExecStates::ThrowValStarted,
            value: None,
        }
    }
}

impl Operation for ThrowValue {
    operation_accessors!();

    fn set_state(&mut self, state: ExecStates, data: StateData) {
        self.state = state;
        if state == ExecStates::ThrowValFinished {
            self.value = Some(data.val());
        }
    }

    fn get_data(&self) -> Vec<Val> {
        vec![self.value.clone().unwrap()]
    }
}

/// One live `try` region: everything needed to transfer control to its catch
/// body when a value is thrown while the region is active — the handler's unit
/// range, the name the thrown value binds to, and the scope/register depths to
/// unwind back to (recorded *before* the try body's scope was pushed).
pub(super) struct TryFrame {
    pub(super) catch_start: usize,
    pub(super) catch_end: usize,
    pub(super) err_name: Rc<str>,
    pub(super) scope_depth: usize,
    pub(super) register_depth: usize,
}

pub(super) struct IfStmt {
    typ: OperationTypes,
    state: ExecStates,
    pub has_condition: bool,
    pub condition: Option<Val>,
    // Branch targets, as unit indices, folded into the `IfHead` unit at decode.
    body_start: usize,
    body_end: usize,
    next: usize,
    branch_after: usize,
}

impl IfStmt {
    pub(super) fn new(
        has_condition: bool,
        body_start: usize,
        body_end: usize,
        next: usize,
        branch_after: usize,
    ) -> Self {
        IfStmt {
            typ: OperationTypes::IfStmt,
            // A conditioned arm waits for its condition to evaluate; an
            // unconditional `else` is already decided (it always runs).
            state: if has_condition {
                ExecStates::IfStmtIsConditioned
            } else {
                ExecStates::IfStmtFinished
            },
            has_condition,
            condition: if has_condition {
                None
            } else {
                Some(Val {
                    typ: ty::BOOL,
                    data: Payload::from(true),
                })
            },
            body_start,
            body_end,
            next,
            branch_after,
        }
    }
}

impl Operation for IfStmt {
    operation_accessors!();

    fn set_state(&mut self, state: ExecStates, data: StateData) {
        self.state = state;
        if state == ExecStates::IfStmtFinished {
            self.condition = Some(data.val());
        }
    }

    fn get_data(&self) -> Vec<Val> {
        vec![
            Val {
                typ: ty::BOOL,
                data: Payload::from(self.has_condition),
            },
            self.condition.clone().unwrap(),
            Val {
                typ: ty::I64,
                data: Payload::from(self.body_start as i64),
            },
            Val {
                typ: ty::I64,
                data: Payload::from(self.body_end as i64),
            },
            Val {
                typ: ty::I64,
                data: Payload::from(self.next as i64),
            },
            Val {
                typ: ty::I64,
                data: Payload::from(self.branch_after as i64),
            },
        ]
    }
}

pub(super) struct LoopStmt {
    typ: OperationTypes,
    state: ExecStates,
    pub condition: Option<Val>,
    // Loop bounds, as unit indices, folded into the `Loop` unit at decode.
    body_start: usize,
    body_end: usize,
    branch_after: usize,
}

impl LoopStmt {
    pub(super) fn new(body_start: usize, body_end: usize, branch_after: usize) -> Self {
        LoopStmt {
            typ: OperationTypes::LoopStmt,
            state: ExecStates::LoopStmtStarted,
            condition: None,
            body_start,
            body_end,
            branch_after,
        }
    }
}

impl Operation for LoopStmt {
    operation_accessors!();

    fn set_state(&mut self, state: ExecStates, data: StateData) {
        self.state = state;
        if state == ExecStates::LoopStmtFinished {
            self.condition = Some(data.val());
        }
    }

    fn get_data(&self) -> Vec<Val> {
        vec![
            self.condition.clone().unwrap(),
            Val {
                typ: ty::I64,
                data: Payload::from(self.body_start as i64),
            },
            Val {
                typ: ty::I64,
                data: Payload::from(self.body_end as i64),
            },
            Val {
                typ: ty::I64,
                data: Payload::from(self.branch_after as i64),
            },
        ]
    }
}

pub(super) struct SwitchStmt {
    typ: OperationTypes,
    state: ExecStates,
    pub comparing_value: Option<Val>,
    pub branch_after_start: usize,
    pub case_count: usize,
    pub cases: Vec<(Val, usize, usize)>,
    /// The `(body_start, body_end)` unit range of each case, in order, folded
    /// into the `Switch` unit at decode. Each case value is still an expression
    /// evaluated at run time; as it arrives it is paired with the next entry.
    cases_bounds: std::rc::Rc<Vec<(usize, usize)>>,
}

impl SwitchStmt {
    pub(super) fn new(branch_after: usize, cases_bounds: std::rc::Rc<Vec<(usize, usize)>>) -> Self {
        SwitchStmt {
            typ: OperationTypes::SwitchStmt,
            state: ExecStates::SwitchStmtStarted,
            comparing_value: None,
            branch_after_start: branch_after,
            case_count: cases_bounds.len(),
            cases: vec![],
            cases_bounds,
        }
    }
}

impl Operation for SwitchStmt {
    operation_accessors!();

    fn next_case_bounds(&self) -> (usize, usize) {
        self.cases_bounds
            .get(self.cases.len())
            .copied()
            .unwrap_or((0, 0))
    }

    fn set_state(&mut self, state: ExecStates, data: StateData) {
        self.state = state;
        if state == ExecStates::SwitchStmtExtractVal {
            // The switch value just evaluated; the case table is already known.
            self.comparing_value = Some(data.val());
        } else if state == ExecStates::SwitchStmtExtractCase {
            // A case value just evaluated; pair it with the next case's body range.
            let value = data.val();
            let (start, end) = self.next_case_bounds();
            self.cases.push((value, start, end));
        }
        if self.case_count == self.cases.len() {
            self.state = ExecStates::SwitchStmtFinished;
        }
    }

    fn get_data(&self) -> Vec<Val> {
        let case_items: Vec<Val> = self
            .cases
            .iter()
            .map(|item| {
                let mut case_info = ValMap::default();
                case_info.insert("val".to_string(), item.0.clone());
                case_info.insert(
                    "start".to_string(),
                    Val {
                        typ: ty::I64,
                        data: Payload::from(item.1 as i64),
                    },
                );
                case_info.insert(
                    "end".to_string(),
                    Val {
                        typ: ty::I64,
                        data: Payload::from(item.2 as i64),
                    },
                );
                Val {
                    typ: ty::OBJECT,
                    data: Payload::from(Rc::new(RefCell::new(Object::new(
                        -1,
                        ValGroup::new(case_info),
                    )))),
                }
            })
            .collect();
        vec![
            self.comparing_value.clone().unwrap(),
            Val {
                typ: ty::I64,
                data: Payload::from(self.branch_after_start as i64),
            },
            Val {
                typ: ty::I64,
                data: Payload::from(self.case_count as i64),
            },
            Val {
                typ: ty::ARRAY,
                data: Payload::from(Rc::new(RefCell::new(Array::new(case_items)))),
            },
        ]
    }
}

pub(super) struct Arithmetic {
    typ: OperationTypes,
    state: ExecStates,
    pub arg1: Option<Val>,
    pub arg2: Option<Val>,
    pub op: i16,
}

impl Arithmetic {
    pub(super) fn new() -> Self {
        Arithmetic {
            typ: OperationTypes::Arithmetic,
            state: ExecStates::ArithmeticStarted,
            arg1: None,
            arg2: None,
            op: 0,
        }
    }
}

impl Operation for Arithmetic {
    operation_accessors!();

    fn set_state(&mut self, state: ExecStates, data: StateData) {
        self.state = state;
        if state == ExecStates::ArithmeticExtractOp {
            self.op = data.i16v();
        } else if state == ExecStates::ArithmeticExtractArg1 {
            self.arg1 = Some(data.val());
        } else if state == ExecStates::ArithmeticExtractArg2 {
            self.arg2 = Some(data.val());
        }
    }

    fn get_data(&self) -> Vec<Val> {
        vec![
            Val {
                typ: ty::I16,
                data: Payload::from(self.op),
            },
            self.arg1.clone().unwrap(),
            self.arg2.clone().unwrap(),
        ]
    }
}

pub(super) struct IndexerValue {
    typ: OperationTypes,
    state: ExecStates,
    pub var: Option<Val>,
    pub index: Option<Val>,
}

impl IndexerValue {
    pub(super) fn new() -> Self {
        IndexerValue {
            typ: OperationTypes::Indexer,
            state: ExecStates::IndexerStarted,
            var: None,
            index: None,
        }
    }
}

impl Operation for IndexerValue {
    operation_accessors!();

    fn set_state(&mut self, state: ExecStates, data: StateData) {
        self.state = state;
        if state == ExecStates::IndexerExtractVarName {
            self.var = Some(data.val());
        } else if state == ExecStates::IndexerExtractIndex {
            self.index = Some(data.val());
        }
    }

    fn get_data(&self) -> Vec<Val> {
        vec![self.var.clone().unwrap(), self.index.clone().unwrap()]
    }
}

pub(super) struct NotValue {
    typ: OperationTypes,
    state: ExecStates,
    pub value: Option<Val>,
}

impl NotValue {
    pub(super) fn new() -> Self {
        NotValue {
            typ: OperationTypes::NotVal,
            state: ExecStates::NotValStarted,
            value: None,
        }
    }
}

impl Operation for NotValue {
    operation_accessors!();

    fn set_state(&mut self, state: ExecStates, data: StateData) {
        self.state = state;
        if state == ExecStates::NotValFinished {
            self.value = Some(data.val());
        }
    }

    fn get_data(&self) -> Vec<Val> {
        vec![self.value.clone().unwrap()]
    }
}

pub(super) struct ObjectExpr {
    typ: OperationTypes,
    state: ExecStates,
    pub object_typ_id: i64,
    pub prop_count: i32,
    pub props: Vec<Val>,
}

impl ObjectExpr {
    pub(super) fn new() -> Self {
        ObjectExpr {
            typ: OperationTypes::ObjExpr,
            state: ExecStates::ObjExprStarted,
            object_typ_id: 0,
            prop_count: 0,
            props: vec![],
        }
    }
}

impl Operation for ObjectExpr {
    operation_accessors!();

    fn set_state(&mut self, state: ExecStates, data: StateData) {
        self.state = state;
        if state == ExecStates::ObjExprExtractInfo {
            let val = data.i64_i32();
            self.object_typ_id = val.0;
            self.prop_count = val.1;
        } else if state == ExecStates::ObjExprExtractProp {
            let val = data.val();
            self.props.push(val.clone());
        }
        if (self.prop_count as usize) == (self.props.len() / 2) {
            self.state = ExecStates::ObjExprFinished;
        }
    }

    fn get_data(&self) -> Vec<Val> {
        vec![
            Val {
                typ: ty::I64,
                data: Payload::from(self.object_typ_id),
            },
            Val {
                typ: ty::I32,
                data: Payload::from(self.prop_count),
            },
            Val {
                typ: ty::ARRAY,
                data: Payload::from(Rc::new(RefCell::new(Array::new(self.props.clone())))),
            },
        ]
    }
}

pub(super) struct ArrayExpr {
    typ: OperationTypes,
    state: ExecStates,
    pub item_count: i32,
    pub items: Vec<Val>,
}

impl ArrayExpr {
    pub(super) fn new() -> Self {
        ArrayExpr {
            typ: OperationTypes::ArrExpr,
            state: ExecStates::ArrExprStarted,
            item_count: 0,
            items: vec![],
        }
    }
}

impl Operation for ArrayExpr {
    operation_accessors!();

    fn set_state(&mut self, state: ExecStates, data: StateData) {
        self.state = state;
        if state == ExecStates::ArrExprExtractInfo {
            self.item_count = data.i32v();
        } else if state == ExecStates::ArrExprExtractItem {
            let val = data.val();
            self.items.push(val.clone());
        }
        if (self.item_count as usize) == self.items.len() {
            self.state = ExecStates::ArrExprFinished;
        }
    }

    fn get_data(&self) -> Vec<Val> {
        vec![
            Val {
                typ: ty::I32,
                data: Payload::from(self.item_count),
            },
            Val {
                typ: ty::ARRAY,
                data: Payload::from(Rc::new(RefCell::new(Array::new(self.items.clone())))),
            },
        ]
    }
}

// ---- spread / template / destructuring (universal collection operators) -----
//
// These three operations implement language-neutral "shape" operators that the
// classic scalar/collection opcodes could not express: expanding one collection
// into another (spread), building a string from interpolated parts (template),
// and binding many names from one value (destructuring). They are native VM
// operations — no front-end desugaring — so any language lowered to the Elpian
// AST gets them for free.

/// Value type tag of a *spread marker*: a transient one-element wrapper produced
/// by the spread operator (`...value`) that the enclosing array / object / call
/// builder recognises and flattens. It never escapes into guest-visible state —
/// it lives only between a `Spread` unit and the collection that consumes it.
const SPREAD_MARKER: i64 = 200;
/// Value type tag of an *object-spread key marker*: occupies an object literal's
/// key slot to signal that the paired value is an object whose members are
/// merged in place rather than stored under a literal key.
pub(super) const SPREAD_KEY_MARKER: i64 = 201;

/// Wrap `inner` in a spread marker (see [`SPREAD_MARKER`]).
pub(super) fn make_spread_marker(inner: Val) -> Val {
    Val {
        typ: SPREAD_MARKER,
        data: Payload::from(Rc::new(RefCell::new(Array::new(vec![inner])))),
    }
}

/// Flatten any spread markers in a list of collected items (array elements or
/// call arguments): a marker wrapping an array contributes its elements, one
/// wrapping a string contributes its characters (each as a one-char string), and
/// any other wrapped value contributes itself; a plain item is kept as-is. The
/// common case — no spreads at all — returns a straight clone so the hot call
/// path pays nothing extra.
pub(super) fn flatten_spread(items: &[Val]) -> Vec<Val> {
    if !items.iter().any(|i| i.typ == SPREAD_MARKER) {
        return items.to_vec();
    }
    let mut out = Vec::with_capacity(items.len());
    for item in items {
        if item.typ == SPREAD_MARKER {
            let inner_rc = item.as_array();
            let inner = inner_rc.borrow().data[0].clone();
            match inner.typ {
                ty::ARRAY => {
                    for e in inner.as_array().borrow().data.iter() {
                        out.push(e.clone());
                    }
                }
                ty::STRING => {
                    for c in inner.as_string().chars() {
                        out.push(Val {
                            typ: ty::STRING,
                            data: Payload::from(c.to_string()),
                        });
                    }
                }
                _ => out.push(inner),
            }
        } else {
            out.push(item.clone());
        }
    }
    out
}

/// Spread operator `...value`: collects its single inner value and re-emits it
/// wrapped in a spread marker. One-operand, mirroring [`NotValue`].
pub(super) struct SpreadOp {
    typ: OperationTypes,
    state: ExecStates,
    pub value: Option<Val>,
}

impl SpreadOp {
    pub(super) fn new() -> Self {
        SpreadOp {
            typ: OperationTypes::Spread,
            state: ExecStates::SpreadStarted,
            value: None,
        }
    }
}

impl Operation for SpreadOp {
    operation_accessors!();
    fn set_state(&mut self, state: ExecStates, data: StateData) {
        self.state = state;
        if state == ExecStates::SpreadFinished {
            self.value = Some(data.val());
        }
    }
    fn get_data(&self) -> Vec<Val> {
        vec![self.value.clone().unwrap()]
    }
}

/// Interpolated / template string: collects `part_count` value parts, then joins
/// their display coercions into one string. Structurally a sibling of
/// [`ArrayExpr`] (collect N, then reduce).
pub(super) struct TemplateExpr {
    typ: OperationTypes,
    state: ExecStates,
    pub part_count: i32,
    pub parts: Vec<Val>,
}

impl TemplateExpr {
    pub(super) fn new() -> Self {
        TemplateExpr {
            typ: OperationTypes::Template,
            state: ExecStates::TemplateExtractInfo,
            part_count: 0,
            parts: vec![],
        }
    }
}

impl Operation for TemplateExpr {
    operation_accessors!();
    fn set_state(&mut self, state: ExecStates, data: StateData) {
        self.state = state;
        if state == ExecStates::TemplateExtractInfo {
            self.part_count = data.i32v();
        } else if state == ExecStates::TemplateExtractPart {
            self.parts.push(data.val());
        }
        if (self.part_count as usize) == self.parts.len() {
            self.state = ExecStates::TemplateFinished;
        }
    }
    fn get_data(&self) -> Vec<Val> {
        let mut out = String::new();
        for p in self.parts.iter() {
            out.push_str(&p.to_display());
        }
        vec![Val {
            typ: ty::STRING,
            data: Payload::from(out),
        }]
    }
}

/// Destructuring binding: collects the source value (and one value per
/// defaulted binding), then the executor binds each name from the source's
/// members (object) or positions (array). Carries its [`DestructurePlan`].
pub(super) struct DestructureOp {
    typ: OperationTypes,
    state: ExecStates,
    pub plan: Rc<DestructurePlan>,
    pub values: Vec<Val>,
}

impl DestructureOp {
    pub(super) fn new(plan: Rc<DestructurePlan>) -> Self {
        DestructureOp {
            typ: OperationTypes::Destructure,
            state: ExecStates::DestructureExtractValue,
            plan,
            values: vec![],
        }
    }
}

impl Operation for DestructureOp {
    operation_accessors!();
    fn set_state(&mut self, state: ExecStates, data: StateData) {
        self.state = state;
        if state == ExecStates::DestructureExtractValue {
            self.values.push(data.val());
        }
        if self.values.len() == self.plan.value_count {
            self.state = ExecStates::DestructureFinished;
        }
    }
    fn get_data(&self) -> Vec<Val> {
        self.values.clone()
    }
    fn destructure_plan(&self) -> Option<Rc<DestructurePlan>> {
        Some(self.plan.clone())
    }
}

/// Compute the `(name, value)` bindings a destructuring statement produces, from
/// its plan and the collected values (`values[0]` is the source; the remaining
/// values are the defaults, in binding order). Pure — the executor performs the
/// actual `define` for each returned pair. A missing / null member falls back
/// to its declared default (consistent with the VM's `??` null test); a rest
/// binding gathers whatever the earlier bindings did not consume.
pub(super) fn apply_destructure(plan: &DestructurePlan, values: &[Val]) -> Vec<(String, Val)> {
    let null = Val {
        typ: ty::NULL,
        data: Payload::Null,
    };
    let source = values.first().cloned().unwrap_or_else(|| null.clone());
    let mut default_idx = 1usize;
    let mut out: Vec<(String, Val)> = Vec::with_capacity(plan.bindings.len());
    if plan.is_array {
        let elems: Vec<Val> = if source.typ == ty::ARRAY {
            source.as_array().borrow().data.clone()
        } else if source.typ == ty::STRING {
            source
                .as_string()
                .chars()
                .map(|c| Val {
                    typ: ty::STRING,
                    data: Payload::from(c.to_string()),
                })
                .collect()
        } else {
            vec![]
        };
        let mut pos = 0usize;
        for b in plan.bindings.iter() {
            if b.is_rest {
                let rest: Vec<Val> = if pos < elems.len() {
                    elems[pos..].to_vec()
                } else {
                    vec![]
                };
                pos = elems.len();
                out.push((
                    b.name.clone(),
                    Val {
                        typ: ty::ARRAY,
                        data: Payload::from(Rc::new(RefCell::new(Array::new(rest)))),
                    },
                ));
                continue;
            }
            let elem = elems.get(pos).cloned();
            pos += 1;
            if b.is_hole {
                continue;
            }
            let mut v = elem.unwrap_or_else(|| null.clone());
            if b.has_default {
                let dv = values
                    .get(default_idx)
                    .cloned()
                    .unwrap_or_else(|| null.clone());
                default_idx += 1;
                if is_null(&v) {
                    v = dv;
                }
            }
            out.push((b.name.clone(), v));
        }
    } else {
        let obj = if source.typ == ty::OBJECT {
            Some(source.as_object())
        } else {
            None
        };
        // Keys claimed by explicit bindings, excluded from a rest binding.
        let claimed: Vec<&str> = plan
            .bindings
            .iter()
            .filter(|b| !b.is_rest && !b.is_hole)
            .map(|b| b.key.as_str())
            .collect();
        for b in plan.bindings.iter() {
            if b.is_rest {
                let mut map = ValMap::default();
                if let Some(o) = &obj {
                    for (k, v) in o.borrow().data.data.iter() {
                        if !claimed.contains(&k.as_str()) {
                            map.insert(k.clone(), v.clone());
                        }
                    }
                }
                out.push((
                    b.name.clone(),
                    Val {
                        typ: ty::OBJECT,
                        data: Payload::from(Rc::new(RefCell::new(Object::new(
                            -2,
                            ValGroup::new(map),
                        )))),
                    },
                ));
                continue;
            }
            if b.is_hole {
                continue;
            }
            let mut v = obj
                .as_ref()
                .and_then(|o| o.borrow().data.data.get(&b.key).cloned())
                .unwrap_or_else(|| null.clone());
            if b.has_default {
                let dv = values
                    .get(default_idx)
                    .cloned()
                    .unwrap_or_else(|| null.clone());
                default_idx += 1;
                if is_null(&v) {
                    v = dv;
                }
            }
            out.push((b.name.clone(), v));
        }
    }
    out
}

pub(super) struct CondBranch {
    typ: OperationTypes,
    state: ExecStates,
    pub condition: Option<Val>,
    pub true_branch: i64,
    pub false_branch: i64,
}

impl CondBranch {
    /// `true_branch`/`false_branch` are unit indices folded into the `CondBranch`
    /// unit at decode.
    pub(super) fn new(true_branch: usize, false_branch: usize) -> Self {
        CondBranch {
            typ: OperationTypes::CondBrch,
            state: ExecStates::CondBranchStarted,
            condition: None,
            true_branch: true_branch as i64,
            false_branch: false_branch as i64,
        }
    }
}

impl Operation for CondBranch {
    operation_accessors!();

    fn set_state(&mut self, state: ExecStates, data: StateData) {
        self.state = state;
        if state == ExecStates::CondBranchFinished {
            // The condition just evaluated; both targets are already known.
            self.condition = Some(data.val());
        }
    }

    fn get_data(&self) -> Vec<Val> {
        vec![
            self.condition.clone().unwrap(),
            Val {
                typ: ty::I64,
                data: Payload::from(self.true_branch),
            },
            Val {
                typ: ty::I64,
                data: Payload::from(self.false_branch),
            },
        ]
    }
}

pub(super) struct CastOp {
    typ: OperationTypes,
    state: ExecStates,
    pub data: Option<Val>,
    pub target_type: String,
}

impl CastOp {
    /// `target_type` is folded into the `Cast` unit at decode.
    pub(super) fn new(target_type: String) -> Self {
        CastOp {
            typ: OperationTypes::CastOprt,
            state: ExecStates::CastOprtStarted,
            data: None,
            target_type,
        }
    }
}

impl Operation for CastOp {
    operation_accessors!();

    fn set_state(&mut self, state: ExecStates, data: StateData) {
        self.state = state;
        if state == ExecStates::CastOprtFinished {
            // The value just evaluated; the target type is already known.
            self.data = Some(data.val());
        }
    }

    fn get_data(&self) -> Vec<Val> {
        vec![
            self.data.clone().unwrap(),
            Val {
                typ: ty::STRING,
                data: Payload::from(self.target_type.clone()),
            },
        ]
    }
}

/// Reified `is` / `as`. The value expression is evaluated first; the finalizer
/// then tests it against `type_name` (`cast` false = `is`, yielding a bool;
/// `cast` true = `as`, yielding the value or trapping on a mismatch). The type
/// name is folded into the unit at decode, exactly like [`CastOp`]'s target.
pub(super) struct TypeTestOp {
    typ: OperationTypes,
    state: ExecStates,
    value: Option<Val>,
    type_name: String,
    cast: bool,
}

impl TypeTestOp {
    pub(super) fn new(type_name: String, cast: bool) -> Self {
        TypeTestOp {
            typ: OperationTypes::TypeTest,
            state: ExecStates::TypeTestStarted,
            value: None,
            type_name,
            cast,
        }
    }
}

impl Operation for TypeTestOp {
    operation_accessors!();
    fn set_state(&mut self, state: ExecStates, data: StateData) {
        self.state = state;
        if state == ExecStates::TypeTestFinished {
            self.value = Some(data.val());
        }
    }
    fn get_data(&self) -> Vec<Val> {
        vec![
            self.value.clone().unwrap(),
            Val {
                typ: ty::STRING,
                data: Payload::from(self.type_name.clone()),
            },
            Val {
                typ: ty::BOOL,
                data: Payload::from(self.cast),
            },
        ]
    }
}

/// Reified type test: does `value` have (dynamic) type `type_name`? The names
/// the VM understands are its own **neutral** type-tag names — `null`, `bool`,
/// `int`, `float`, `number`, `string`, `list`, `map`, `function`, and the
/// universal `any` — never a source language's spellings. A front-end maps its
/// language's type names onto these at compile time (dart2elpian lowers
/// `double`→`float`, `String`→`string`, `List`→`list`, …; a JS front-end would
/// map its `typeof` vocabulary the same way). Any other name is a class name,
/// matched by walking the instance's prototype chain (`__proto` → `__parent`),
/// each prototype carrying its `__class_name`, so the class hierarchy embedded
/// in the value answers the check with no external class table.
pub(super) fn value_is_type(value: &Val, type_name: &str) -> bool {
    match type_name {
        "any" => true,
        "int" => matches!(value.typ, 1..=3),
        "float" => matches!(value.typ, 4 | 5),
        "number" => matches!(value.typ, 1..=5),
        "string" => value.typ == ty::STRING,
        "bool" => value.typ == ty::BOOL,
        "list" => value.typ == ty::ARRAY,
        "map" => value.typ == ty::OBJECT,
        "function" => value.typ == ty::FUNCTION,
        "null" => value.typ == ty::NULL,
        class => {
            if value.typ != ty::OBJECT {
                return false;
            }
            // Walk the prototype chain, comparing each level's class name. Both the
            // js2elpian/dart2elpian `__proto`→`__parent` prototype scheme and the
            // stdlib `class`/`new` `__class`→`__parent` scheme are handled: each
            // prototype/class carries a `__class_name` string.
            let mut cur = {
                let inst = value.as_object();
                let b = inst.borrow();
                b.data
                    .data
                    .get("__proto")
                    .or_else(|| b.data.data.get("__class"))
                    .cloned()
            };
            // A directly-tagged instance (`__class_name` on the object itself).
            if let Some(name) = value.as_object().borrow().data.data.get("__class_name") {
                if name.typ == ty::STRING && name.as_string() == class {
                    return true;
                }
            }
            while let Some(proto) = cur {
                if proto.typ != ty::OBJECT {
                    break;
                }
                let b = proto.as_object();
                let bref = b.borrow();
                if let Some(name) = bref.data.data.get("__class_name") {
                    if name.typ == ty::STRING && name.as_string() == class {
                        return true;
                    }
                }
                cur = bref.data.data.get("__parent").cloned();
            }
            false
        }
    }
}

/// Whether a value is the VM's first-class null (type tag 0) — the single,
/// language-neutral "absent value". Every front-end lowers its own spelling
/// (`null`, `undefined`, `nil`, …) to this literal at compile time, host
/// replies decode JSON `null` to it, and every absent read (missing argument,
/// absent member/key, out-of-range element) yields it. It is the value the
/// null-coalescing operator and `x == null` comparisons test against; a
/// numeric zero is an ordinary number, never null.
pub(super) fn is_null(v: &Val) -> bool {
    v.typ == ty::NULL
}

/// Short-circuiting `&&` / `||` / `??`. The left operand is evaluated first; the
/// right is only evaluated when the result is not already decided (`&&` with a
/// truthy left, `||` with a falsy left, `??` with a non-null left — truthiness
/// is the VM's own rule, see [`Val::truthy`]; null is the first-class null). On
/// short-circuit the dispatch loop reuses the left value as the result and jumps
/// the program counter to `op2_end`, skipping the right operand's units entirely.
/// No double evaluation.
pub(super) struct LogicalOp {
    typ: OperationTypes,
    state: ExecStates,
    kind: LogicalKind,
    op2_end: usize,
}

impl LogicalOp {
    pub(super) fn new(kind: LogicalKind, op2_end: usize) -> Self {
        LogicalOp {
            typ: OperationTypes::Logical,
            state: ExecStates::LogicalExtractOp1,
            kind,
            op2_end,
        }
    }
    /// The kind re-encoded as the small integer the flag byte uses (`0`=`&&`,
    /// `1`=`||`, `2`=`??`), so it can travel through `get_data`'s `Val` list.
    fn kind_tag(kind: LogicalKind) -> i16 {
        match kind {
            LogicalKind::And => 0,
            LogicalKind::Or => 1,
            LogicalKind::NullCoalesce => 2,
        }
    }
    pub(super) fn kind_from_tag(tag: i16) -> LogicalKind {
        match tag {
            1 => LogicalKind::Or,
            2 => LogicalKind::NullCoalesce,
            _ => LogicalKind::And,
        }
    }
}

impl Operation for LogicalOp {
    operation_accessors!();
    fn set_state(&mut self, state: ExecStates, _data: StateData) {
        // Operands are consumed straight from `main_reg` in the dispatch loop; the
        // op only tracks which operand is awaited and carries its skip target.
        self.state = state;
    }
    fn get_data(&self) -> Vec<Val> {
        vec![
            Val {
                typ: ty::I16,
                data: Payload::from(LogicalOp::kind_tag(self.kind)),
            },
            Val {
                typ: ty::I64,
                data: Payload::from(self.op2_end as i64),
            },
        ]
    }
}

/// The conditional (ternary) operator `c ? a : b`. The condition is evaluated
/// first; the dispatch loop then either lets execution fall into the consequent
/// or jumps to `alt_start`, and after the taken branch's value is produced jumps
/// to `end` so the other branch's units are skipped.
pub(super) struct ConditionalOp {
    typ: OperationTypes,
    state: ExecStates,
    alt_start: usize,
    end: usize,
}

impl ConditionalOp {
    pub(super) fn new(alt_start: usize, end: usize) -> Self {
        ConditionalOp {
            typ: OperationTypes::Conditional,
            state: ExecStates::CondExprExtractCond,
            alt_start,
            end,
        }
    }
}

impl Operation for ConditionalOp {
    operation_accessors!();
    fn set_state(&mut self, state: ExecStates, _data: StateData) {
        self.state = state;
    }
    fn get_data(&self) -> Vec<Val> {
        vec![
            Val {
                typ: ty::I64,
                data: Payload::from(self.alt_start as i64),
            },
            Val {
                typ: ty::I64,
                data: Payload::from(self.end as i64),
            },
        ]
    }
}

pub(super) struct DummyOp {
    typ: OperationTypes,
    state: ExecStates,
}

impl DummyOp {
    pub(super) fn new() -> Self {
        DummyOp {
            typ: OperationTypes::Dummy,
            state: ExecStates::Dummy,
        }
    }
}

impl Operation for DummyOp {
    operation_accessors!();

    fn set_state(&mut self, state: ExecStates, _data: StateData) {
        self.state = state;
    }

    fn get_data(&self) -> Vec<Val> {
        vec![]
    }
}
