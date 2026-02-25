// use wasm_bindgen::prelude::wasm_bindgen;

use crate::sdk::{
    context::Context,
    data::{Array, Function, Object, Val, ValGroup},
};
use core::panic;
use std::{any::Any, cell::RefCell, collections::HashMap, fmt, i16, rc::Rc};

use std::vec;

#[derive(Clone, Debug, PartialEq)]
pub enum OperationTypes {
    DefineVar,
    AssignVar,
    CallFunc,
    ReturnVal,
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
    Dummy,
}

impl fmt::Display for OperationTypes {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:?}", self)
    }
}

#[derive(Clone, Debug, PartialEq)]
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
    IfStmtStarted,
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
    Dummy,
}

impl fmt::Display for ExecStates {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:?}", self)
    }
}

pub trait Operation {
    fn get_type(&self) -> OperationTypes;
    fn get_state(&self) -> ExecStates;
    fn set_state(&mut self, state: ExecStates, data: Box<dyn Any>);
    fn get_data(&self) -> Vec<Val>;
}

impl fmt::Debug for dyn Operation {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Operation{{{} {}}}", self.get_type(), self.get_state())
    }
}

struct DefineVariable {
    typ: OperationTypes,
    state: ExecStates,
    pub var_name: Option<String>,
    pub var_value: Option<Val>,
}

impl DefineVariable {
    pub fn new() -> Self {
        DefineVariable {
            typ: OperationTypes::DefineVar,
            state: ExecStates::DefineVarExtractName,
            var_name: None,
            var_value: None,
        }
    }
}

impl Operation for DefineVariable {
    fn get_state(&self) -> ExecStates {
        self.state.clone()
    }

    fn get_type(&self) -> OperationTypes {
        self.typ.clone()
    }

    fn set_state(&mut self, state: ExecStates, data: Box<dyn Any>) {
        self.state = state.clone();
        if state == ExecStates::DefineVarExtractName {
            self.var_name = Some(*data.downcast::<String>().unwrap());
        } else if state == ExecStates::DefineVarExtractValue {
            self.var_value = Some(*data.downcast::<Val>().unwrap());
        }
    }

    fn get_data(&self) -> Vec<Val> {
        vec![
            Val {
                typ: 7,
                data: Rc::new(RefCell::new(Box::new(self.var_name.clone().unwrap()))),
            },
            self.var_value.clone().unwrap(),
        ]
    }
}

struct AssignVariable {
    typ: OperationTypes,
    state: ExecStates,
    pub var_name: Option<String>,
    pub assign_target_type: i16,
    pub index: Option<Val>,
    pub var_value: Option<Val>,
}

impl AssignVariable {
    pub fn new() -> Self {
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
    fn get_state(&self) -> ExecStates {
        self.state.clone()
    }

    fn get_type(&self) -> OperationTypes {
        self.typ.clone()
    }

    fn set_state(&mut self, state: ExecStates, data: Box<dyn Any>) {
        self.state = state.clone();
        if state == ExecStates::AssignVarExtractName {
            let (var_name, assign_target_type) = *data.downcast::<(String, i16)>().unwrap();
            self.var_name = Some(var_name.clone());
            self.assign_target_type = assign_target_type;
        } else if state == ExecStates::AssignVarExtractIndex {
            if self.assign_target_type == 2 {
                self.index = Some(*data.downcast::<Val>().unwrap());
            } else {
                panic!("elpian error: wrong state set to assignment operation");
            }
        } else if state == ExecStates::AssignVarExtractValue {
            self.var_value = Some(*data.downcast::<Val>().unwrap());
        }
    }

    fn get_data(&self) -> Vec<Val> {
        if self.assign_target_type == 2 {
            if self.var_value.is_none() {
                return vec![
                    Val {
                        typ: 7,
                        data: Rc::new(RefCell::new(Box::new(self.var_name.clone().unwrap()))),
                    },
                    Val {
                        typ: 6,
                        data: Rc::new(RefCell::new(Box::new(self.assign_target_type))),
                    },
                    self.index.clone().unwrap(),
                    Val {
                        typ: 0,
                        data: Rc::new(RefCell::new(Box::new(0))),
                    },
                ];
            } else {
                return vec![
                    Val {
                        typ: 7,
                        data: Rc::new(RefCell::new(Box::new(self.var_name.clone().unwrap()))),
                    },
                    Val {
                        typ: 6,
                        data: Rc::new(RefCell::new(Box::new(self.assign_target_type))),
                    },
                    self.index.clone().unwrap(),
                    self.var_value.clone().unwrap(),
                ];
            }
        } else {
            if self.var_value.is_none() {
                return vec![
                    Val {
                        typ: 7,
                        data: Rc::new(RefCell::new(Box::new(self.var_name.clone().unwrap()))),
                    },
                    Val {
                        typ: 6,
                        data: Rc::new(RefCell::new(Box::new(self.assign_target_type))),
                    },
                    Val {
                        typ: 0,
                        data: Rc::new(RefCell::new(Box::new(0))),
                    },
                    Val {
                        typ: 0,
                        data: Rc::new(RefCell::new(Box::new(0))),
                    },
                ];
            } else {
                return vec![
                    Val {
                        typ: 7,
                        data: Rc::new(RefCell::new(Box::new(self.var_name.clone().unwrap()))),
                    },
                    Val {
                        typ: 6,
                        data: Rc::new(RefCell::new(Box::new(self.assign_target_type))),
                    },
                    Val {
                        typ: 0,
                        data: Rc::new(RefCell::new(Box::new(0))),
                    },
                    self.var_value.clone().unwrap(),
                ];
            }
        }
    }
}

struct CallFunction {
    typ: OperationTypes,
    state: ExecStates,
    pub func: Option<Rc<RefCell<Function>>>,
    pub is_native: bool,
    pub param_count: i32,
    pub params: Vec<Val>,
}

impl CallFunction {
    pub fn new() -> Self {
        CallFunction {
            typ: OperationTypes::CallFunc,
            state: ExecStates::CallFuncStarted,
            func: None,
            param_count: 0,
            is_native: false,
            params: vec![],
        }
    }
}

impl Operation for CallFunction {
    fn get_state(&self) -> ExecStates {
        self.state.clone()
    }

    fn get_type(&self) -> OperationTypes {
        self.typ.clone()
    }

    fn set_state(&mut self, state: ExecStates, data: Box<dyn Any>) {
        self.state = state.clone();
        if state == ExecStates::CallFuncExtractFunc {
            let val = data.downcast::<(Val, usize)>().unwrap();
            if val.as_ref().0.typ == 10 {
                self.func = Some(val.as_ref().0.as_func());
                self.param_count = val.as_ref().1 as i32;
                self.is_native = false;
            } else if val.as_ref().0.typ == 255 {
                self.func = Some(Rc::new(RefCell::new(Function::new(
                    "".to_string(),
                    0,
                    0,
                    vec!["apiName".to_string(), "input".to_string()],
                ))));
                self.param_count = 2;
                self.is_native = true;
            } else {
                panic!("elpian error: the specified data is not runnable");
            }
        } else if state == ExecStates::CallFuncExtractParam {
            self.params.push(*data.downcast::<Val>().unwrap());
        }
        if let Some(func) = &self.func {
            if func.borrow().params.len() == self.params.len() {
                self.state = ExecStates::CallFuncFinished;
            }
        }
    }

    fn get_data(&self) -> Vec<Val> {
        vec![
            Val {
                typ: 10,
                data: Rc::new(RefCell::new(Box::new(self.func.clone().unwrap()))),
            },
            Val {
                typ: 6,
                data: Rc::new(RefCell::new(Box::new(self.is_native))),
            },
            Val {
                typ: 2,
                data: Rc::new(RefCell::new(Box::new(self.param_count))),
            },
            Val {
                typ: 9,
                data: Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(Array::new(
                    self.params.clone(),
                )))))),
            },
        ]
    }
}

struct ReturnValue {
    typ: OperationTypes,
    state: ExecStates,
    pub value: Option<Val>,
}

impl ReturnValue {
    pub fn new() -> Self {
        ReturnValue {
            typ: OperationTypes::ReturnVal,
            state: ExecStates::ReturnValStarted,
            value: None,
        }
    }
}

impl Operation for ReturnValue {
    fn get_state(&self) -> ExecStates {
        self.state.clone()
    }

    fn get_type(&self) -> OperationTypes {
        self.typ.clone()
    }

    fn set_state(&mut self, state: ExecStates, data: Box<dyn Any>) {
        self.state = state.clone();
        if state == ExecStates::ReturnValFinished {
            self.value = Some(*data.downcast::<Val>().unwrap());
        }
    }

    fn get_data(&self) -> Vec<Val> {
        vec![self.value.clone().unwrap()]
    }
}

struct IfStmt {
    typ: OperationTypes,
    state: ExecStates,
    pub has_condition: bool,
    pub condition: Option<Val>,
}

impl IfStmt {
    pub fn new() -> Self {
        IfStmt {
            typ: OperationTypes::IfStmt,
            state: ExecStates::IfStmtStarted,
            has_condition: false,
            condition: None,
        }
    }
}

impl Operation for IfStmt {
    fn get_state(&self) -> ExecStates {
        self.state.clone()
    }

    fn get_type(&self) -> OperationTypes {
        self.typ.clone()
    }

    fn set_state(&mut self, state: ExecStates, data: Box<dyn Any>) {
        self.state = state.clone();
        if state == ExecStates::IfStmtIsConditioned {
            self.has_condition = *data.downcast::<bool>().unwrap();
            if !self.has_condition {
                self.condition = None;
                self.state = ExecStates::IfStmtFinished;
            }
        } else if state == ExecStates::IfStmtFinished {
            self.condition = Some(*data.downcast::<Val>().unwrap());
        }
    }

    fn get_data(&self) -> Vec<Val> {
        vec![
            Val {
                typ: 6,
                data: Rc::new(RefCell::new(Box::new(self.has_condition))),
            },
            self.condition.clone().unwrap(),
        ]
    }
}

struct LoopStmt {
    typ: OperationTypes,
    state: ExecStates,
    pub condition: Option<Val>,
}

impl LoopStmt {
    pub fn new() -> Self {
        LoopStmt {
            typ: OperationTypes::LoopStmt,
            state: ExecStates::LoopStmtStarted,
            condition: None,
        }
    }
}

impl Operation for LoopStmt {
    fn get_state(&self) -> ExecStates {
        self.state.clone()
    }

    fn get_type(&self) -> OperationTypes {
        self.typ.clone()
    }

    fn set_state(&mut self, state: ExecStates, data: Box<dyn Any>) {
        self.state = state.clone();
        if state == ExecStates::LoopStmtFinished {
            self.condition = Some(*data.downcast::<Val>().unwrap());
        }
    }

    fn get_data(&self) -> Vec<Val> {
        vec![self.condition.clone().unwrap()]
    }
}

struct SwitchStmt {
    typ: OperationTypes,
    state: ExecStates,
    pub comparing_value: Option<Val>,
    pub branch_after_start: usize,
    pub case_count: usize,
    pub cases: Vec<(Val, usize, usize)>,
}

impl SwitchStmt {
    pub fn new() -> Self {
        SwitchStmt {
            typ: OperationTypes::SwitchStmt,
            state: ExecStates::SwitchStmtStarted,
            comparing_value: None,
            branch_after_start: 0,
            case_count: 0,
            cases: vec![],
        }
    }
}

impl Operation for SwitchStmt {
    fn get_state(&self) -> ExecStates {
        self.state.clone()
    }

    fn get_type(&self) -> OperationTypes {
        self.typ.clone()
    }

    fn set_state(&mut self, state: ExecStates, data: Box<dyn Any>) {
        self.state = state.clone();
        if state == ExecStates::SwitchStmtExtractVal {
            let (comparing_val, branch_after_start, case_count) =
                *data.downcast::<(Val, usize, usize)>().unwrap();
            self.comparing_value = Some(comparing_val.clone());
            self.branch_after_start = branch_after_start;
            self.case_count = case_count;
        } else if state == ExecStates::SwitchStmtExtractCase {
            self.cases
                .push(*data.downcast::<(Val, usize, usize)>().unwrap());
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
                let mut case_info = HashMap::new();
                case_info.insert("val".to_string(), item.0.clone());
                case_info.insert(
                    "start".to_string(),
                    Val {
                        typ: 3,
                        data: Rc::new(RefCell::new(Box::new(item.1 as i64))),
                    },
                );
                case_info.insert(
                    "end".to_string(),
                    Val {
                        typ: 3,
                        data: Rc::new(RefCell::new(Box::new(item.2 as i64))),
                    },
                );
                Val {
                    typ: 8,
                    data: Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(Object::new(
                        -1,
                        ValGroup::new(case_info),
                    )))))),
                }
            })
            .collect();
        vec![
            self.comparing_value.clone().unwrap(),
            Val {
                typ: 3,
                data: Rc::new(RefCell::new(Box::new(self.branch_after_start as i64))),
            },
            Val {
                typ: 3,
                data: Rc::new(RefCell::new(Box::new(self.case_count as i64))),
            },
            Val {
                typ: 9,
                data: Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(Array::new(
                    case_items,
                )))))),
            },
        ]
    }
}

struct Arithmetic {
    typ: OperationTypes,
    state: ExecStates,
    pub arg1: Option<Val>,
    pub arg2: Option<Val>,
    pub op: i16,
}

impl Arithmetic {
    pub fn new() -> Self {
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
    fn get_state(&self) -> ExecStates {
        self.state.clone()
    }

    fn get_type(&self) -> OperationTypes {
        self.typ.clone()
    }

    fn set_state(&mut self, state: ExecStates, data: Box<dyn Any>) {
        self.state = state.clone();
        if state == ExecStates::ArithmeticExtractOp {
            self.op = *data.downcast::<i16>().unwrap();
        } else if state == ExecStates::ArithmeticExtractArg1 {
            self.arg1 = Some(*data.downcast::<Val>().unwrap());
        } else if state == ExecStates::ArithmeticExtractArg2 {
            self.arg2 = Some(*data.downcast::<Val>().unwrap());
        }
    }

    fn get_data(&self) -> Vec<Val> {
        vec![
            Val {
                typ: 1,
                data: Rc::new(RefCell::new(Box::new(self.op))),
            },
            self.arg1.clone().unwrap(),
            self.arg2.clone().unwrap(),
        ]
    }
}

struct IndexerValue {
    typ: OperationTypes,
    state: ExecStates,
    pub var: Option<Val>,
    pub index: Option<Val>,
}

impl IndexerValue {
    pub fn new() -> Self {
        IndexerValue {
            typ: OperationTypes::Indexer,
            state: ExecStates::IndexerStarted,
            var: None,
            index: None,
        }
    }
}

impl Operation for IndexerValue {
    fn get_state(&self) -> ExecStates {
        self.state.clone()
    }

    fn get_type(&self) -> OperationTypes {
        self.typ.clone()
    }

    fn set_state(&mut self, state: ExecStates, data: Box<dyn Any>) {
        self.state = state.clone();
        if state == ExecStates::IndexerExtractVarName {
            self.var = Some(*data.downcast::<Val>().unwrap());
        } else if state == ExecStates::IndexerExtractIndex {
            self.index = Some(*data.downcast::<Val>().unwrap());
        }
    }

    fn get_data(&self) -> Vec<Val> {
        vec![self.var.clone().unwrap(), self.index.clone().unwrap()]
    }
}

struct NotValue {
    typ: OperationTypes,
    state: ExecStates,
    pub value: Option<Val>,
}

impl NotValue {
    pub fn new() -> Self {
        NotValue {
            typ: OperationTypes::NotVal,
            state: ExecStates::NotValStarted,
            value: None,
        }
    }
}

impl Operation for NotValue {
    fn get_state(&self) -> ExecStates {
        self.state.clone()
    }

    fn get_type(&self) -> OperationTypes {
        self.typ.clone()
    }

    fn set_state(&mut self, state: ExecStates, data: Box<dyn Any>) {
        self.state = state.clone();
        if state == ExecStates::NotValFinished {
            self.value = Some(*data.downcast::<Val>().unwrap());
        }
    }

    fn get_data(&self) -> Vec<Val> {
        vec![self.value.clone().unwrap()]
    }
}

struct ObjectExpr {
    typ: OperationTypes,
    state: ExecStates,
    pub object_typ_id: i64,
    pub prop_count: i32,
    pub props: Vec<Val>,
}

impl ObjectExpr {
    pub fn new() -> Self {
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
    fn get_state(&self) -> ExecStates {
        self.state.clone()
    }

    fn get_type(&self) -> OperationTypes {
        self.typ.clone()
    }

    fn set_state(&mut self, state: ExecStates, data: Box<dyn Any>) {
        self.state = state.clone();
        if state == ExecStates::ObjExprExtractInfo {
            let val = data.downcast::<(i64, i32)>().unwrap();
            self.object_typ_id = val.as_ref().0;
            self.prop_count = val.as_ref().1;
        } else if state == ExecStates::ObjExprExtractProp {
            let val = *data.downcast::<Val>().unwrap();
            self.props.push(val.clone());
        }
        if (self.prop_count as usize) == (self.props.len() / 2) {
            self.state = ExecStates::ObjExprFinished;
        }
    }

    fn get_data(&self) -> Vec<Val> {
        vec![
            Val {
                typ: 3,
                data: Rc::new(RefCell::new(Box::new(self.object_typ_id))),
            },
            Val {
                typ: 2,
                data: Rc::new(RefCell::new(Box::new(self.prop_count))),
            },
            Val {
                typ: 9,
                data: Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(Array::new(
                    self.props.clone(),
                )))))),
            },
        ]
    }
}

struct ArrayExpr {
    typ: OperationTypes,
    state: ExecStates,
    pub item_count: i32,
    pub items: Vec<Val>,
}

impl ArrayExpr {
    pub fn new() -> Self {
        ArrayExpr {
            typ: OperationTypes::ArrExpr,
            state: ExecStates::ArrExprStarted,
            item_count: 0,
            items: vec![],
        }
    }
}

impl Operation for ArrayExpr {
    fn get_state(&self) -> ExecStates {
        self.state.clone()
    }

    fn get_type(&self) -> OperationTypes {
        self.typ.clone()
    }

    fn set_state(&mut self, state: ExecStates, data: Box<dyn Any>) {
        self.state = state.clone();
        if state == ExecStates::ArrExprExtractInfo {
            self.item_count = *data.downcast::<i32>().unwrap();
        } else if state == ExecStates::ArrExprExtractItem {
            let val = *data.downcast::<Val>().unwrap();
            self.items.push(val.clone());
        }
        if (self.item_count as usize) == self.items.len() {
            self.state = ExecStates::ArrExprFinished;
        }
    }

    fn get_data(&self) -> Vec<Val> {
        vec![
            Val {
                typ: 2,
                data: Rc::new(RefCell::new(Box::new(self.item_count))),
            },
            Val {
                typ: 9,
                data: Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(Array::new(
                    self.items.clone(),
                )))))),
            },
        ]
    }
}

struct CondBranch {
    typ: OperationTypes,
    state: ExecStates,
    pub condition: Option<Val>,
    pub true_branch: i64,
    pub false_branch: i64,
}

impl CondBranch {
    pub fn new() -> Self {
        CondBranch {
            typ: OperationTypes::CondBrch,
            state: ExecStates::CondBranchStarted,
            condition: None,
            true_branch: 0,
            false_branch: 0,
        }
    }
}

impl Operation for CondBranch {
    fn get_state(&self) -> ExecStates {
        self.state.clone()
    }

    fn get_type(&self) -> OperationTypes {
        self.typ.clone()
    }

    fn set_state(&mut self, state: ExecStates, data: Box<dyn Any>) {
        self.state = state.clone();
        if state == ExecStates::CondBranchFinished {
            let (cond, tb, fb) = *data.downcast::<(Val, i64, i64)>().unwrap().clone();
            self.condition = Some(cond);
            self.true_branch = tb;
            self.false_branch = fb;
        }
    }

    fn get_data(&self) -> Vec<Val> {
        vec![
            self.condition.clone().unwrap(),
            Val {
                typ: 3,
                data: Rc::new(RefCell::new(Box::new(self.true_branch))),
            },
            Val {
                typ: 3,
                data: Rc::new(RefCell::new(Box::new(self.false_branch))),
            },
        ]
    }
}

struct CastOp {
    typ: OperationTypes,
    state: ExecStates,
    pub data: Option<Val>,
    pub target_type: String,
}

impl CastOp {
    pub fn new() -> Self {
        CastOp {
            typ: OperationTypes::CastOprt,
            state: ExecStates::CastOprtStarted,
            data: None,
            target_type: "".to_string(),
        }
    }
}

impl Operation for CastOp {
    fn get_state(&self) -> ExecStates {
        self.state.clone()
    }

    fn get_type(&self) -> OperationTypes {
        self.typ.clone()
    }

    fn set_state(&mut self, state: ExecStates, data: Box<dyn Any>) {
        self.state = state.clone();
        if state == ExecStates::CastOprtFinished {
            let (data, tt) = *data.downcast::<(Val, String)>().unwrap().clone();
            self.data = Some(data);
            self.target_type = tt;
        }
    }

    fn get_data(&self) -> Vec<Val> {
        vec![
            self.data.clone().unwrap(),
            Val {
                typ: 7,
                data: Rc::new(RefCell::new(Box::new(self.target_type.clone()))),
            },
        ]
    }
}

struct DummyOp {
    typ: OperationTypes,
    state: ExecStates,
}

impl DummyOp {
    pub fn new() -> Self {
        DummyOp {
            typ: OperationTypes::Dummy,
            state: ExecStates::Dummy,
        }
    }
}

impl Operation for DummyOp {
    fn get_state(&self) -> ExecStates {
        self.state.clone()
    }

    fn get_type(&self) -> OperationTypes {
        self.typ.clone()
    }

    fn set_state(&mut self, state: ExecStates, _data: Box<dyn Any>) {
        self.state = state.clone();
    }

    fn get_data(&self) -> Vec<Val> {
        vec![]
    }
}

pub struct Executor {
    executor_id: i16,
    pointer: usize,
    end_at: usize,
    ctx: Context,
    program: Vec<u8>,
    cb_counter: i64,
    pending_func_result_value: Val,
    registers: Vec<Rc<RefCell<Box<dyn Operation>>>>,
    _allowed_api: HashMap<String, bool>,
    run_cb_id: i64,
    exec_globally: bool,
    reserved_host_call: Option<(u8, i64, Val)>,
    pub processing: bool,
}

impl Executor {
    pub fn create_in_single_thread(
        program: Vec<u8>,
        exec_id: i16,
        func_group: Vec<String>,
    ) -> Self {
        let mut allowed_api: HashMap<String, bool> = HashMap::new();
        for api_name in func_group.iter() {
            allowed_api.insert(api_name.clone(), true);
        }
        Executor {
            _allowed_api: allowed_api,
            executor_id: exec_id,
            pointer: 0,
            end_at: program.len(),
            ctx: Context::new(),
            program,
            cb_counter: 0,
            pending_func_result_value: Val::new(254, Rc::new(RefCell::new(Box::new(0)))),
            registers: vec![],
            run_cb_id: 0,
            exec_globally: false,
            reserved_host_call: None,
            processing: false,
        }
    }
    pub fn single_thread_operation(
        &mut self,
        op_code: u8,
        cb_id: i64,
        payload: Val,
    ) -> (u8, i64, Val) {
        match op_code {
            0x01 => {
                // println!("executor: run_func called");
                self.run_cb_id = cb_id;
                if payload.typ != 9 {
                    self.exec_globally = true;
                    self.processing = true;
                    let result = self.run_from(
                        0,
                        self.program.len(),
                        false,
                        Val {
                            typ: 0,
                            data: Rc::new(RefCell::new(Box::new(0))),
                        },
                        false,
                    );
                    if self.reserved_host_call.is_some() {
                        let host_call_data = self.reserved_host_call.clone().unwrap();
                        self.reserved_host_call = None;
                        return host_call_data;
                    } else if self.pointer == self.ctx.memory.get(0).unwrap().borrow().frozen_end {
                        self.processing = false;
                        return (0x01, cb_id, result);
                    } else {
                        self.processing = false;
                        return (
                            0x00,
                            0,
                            Val {
                                typ: 0,
                                data: Rc::new(RefCell::new(Box::new(0))),
                            },
                        );
                    }
                } else {
                    self.exec_globally = false;
                    self.processing = true;
                    let arr = payload.as_array();
                    let func_name = arr.borrow().data[0].as_string();
                    let input = arr.borrow().data[1].clone();
                    let val = self.ctx.find_val_in_first_scope(func_name);
                    if !val.is_empty() {
                        let func = val.as_func();
                        let mut m = HashMap::new();
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
                                typ: 0,
                                data: Rc::new(RefCell::new(Box::new(0))),
                            },
                            true,
                        );
                        if self.reserved_host_call.is_some() {
                            let host_call_data = self.reserved_host_call.clone().unwrap();
                            self.reserved_host_call = None;
                            return host_call_data;
                        } else if self.ctx.memory.len() == 1 {
                            self.processing = false;
                            return (0x01, cb_id, result);
                        } else {
                            self.processing = false;
                            return (
                                0x00,
                                0,
                                Val {
                                    typ: 0,
                                    data: Rc::new(RefCell::new(Box::new(0))),
                                },
                            );
                        }
                    } else {
                        panic!("elpian error: global function not found");
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
                return (
                    0x00,
                    0,
                    Val {
                        typ: 0,
                        data: Rc::new(RefCell::new(Box::new(0))),
                    },
                );
            }
            0x03 => {
                let result = self.run_from(
                    self.pointer,
                    self.end_at,
                    true,
                    payload,
                    !self.exec_globally,
                );
                if !self.ctx.memory.is_empty() {
                    if self.exec_globally {
                        if self.reserved_host_call.is_some() {
                            let host_call_data = self.reserved_host_call.clone().unwrap();
                            self.reserved_host_call = None;
                            return host_call_data;
                        } else if self.pointer
                            == self.ctx.memory.get(0).unwrap().borrow().frozen_end
                        {
                            self.processing = false;
                            return (0x01, cb_id, result);
                        } else {
                            self.processing = false;
                            return (
                                0x00,
                                0,
                                Val {
                                    typ: 0,
                                    data: Rc::new(RefCell::new(Box::new(0))),
                                },
                            );
                        }
                    } else {
                        if self.reserved_host_call.is_some() {
                            let host_call_data = self.reserved_host_call.clone().unwrap();
                            self.reserved_host_call = None;
                            return host_call_data;
                        } else if self.ctx.memory.len() == 1 {
                            self.processing = false;
                            return (0x01, cb_id, result);
                        } else {
                            self.processing = false;
                            return (
                                0x00,
                                0,
                                Val {
                                    typ: 0,
                                    data: Rc::new(RefCell::new(Box::new(0))),
                                },
                            );
                        }
                    }
                } else {
                    self.processing = false;
                    return (
                        0x00,
                        0,
                        Val {
                            typ: 0,
                            data: Rc::new(RefCell::new(Box::new(0))),
                        },
                    );
                }
            }
            _ => {
                self.processing = false;
                return (
                    0x00,
                    0,
                    Val {
                        typ: 0,
                        data: Rc::new(RefCell::new(Box::new(0))),
                    },
                );
            }
        }
    }
    fn extract_i16(&mut self) -> i16 {
        let num_bytes: [u8; 2] = self.program[self.pointer..(self.pointer + 2)]
            .try_into()
            .unwrap();
        self.pointer += 2;
        i16::from_be_bytes(num_bytes)
    }
    fn extract_i32(&mut self) -> i32 {
        let num_bytes: [u8; 4] = self.program[self.pointer..(self.pointer + 4)]
            .try_into()
            .unwrap();
        self.pointer += 4;
        i32::from_be_bytes(num_bytes)
    }
    fn extract_i64(&mut self) -> i64 {
        let num_bytes: [u8; 8] = self.program[self.pointer..(self.pointer + 8)]
            .try_into()
            .unwrap();
        self.pointer += 8;
        i64::from_be_bytes(num_bytes)
    }
    fn extract_f32(&mut self) -> f32 {
        let num_bytes: [u8; 4] = self.program[self.pointer..(self.pointer + 4)]
            .try_into()
            .unwrap();
        self.pointer += 4;
        f32::from_be_bytes(num_bytes)
    }
    fn extract_f64(&mut self) -> f64 {
        let num_bytes: [u8; 8] = self.program[self.pointer..(self.pointer + 8)]
            .try_into()
            .unwrap();
        self.pointer += 8;
        f64::from_be_bytes(num_bytes)
    }
    fn extract_bool(&mut self) -> bool {
        let result = self.program[self.pointer] == 0x01;
        self.pointer += 1;
        result
    }
    fn extract_str(&mut self) -> String {
        let len_bytes: [u8; 4] = self.program[self.pointer..(self.pointer + 4)]
            .try_into()
            .unwrap();
        self.pointer += 4;
        let length = i32::from_be_bytes(len_bytes) as usize;
        let str_bytes = self.program[self.pointer..(self.pointer + length)].to_vec();
        self.pointer += length;
        String::from_utf8(str_bytes).unwrap()
    }
    fn extract_arr(&mut self) -> Rc<RefCell<Array>> {
        let mut data: Vec<Val> = vec![];
        let arr_len = self.extract_i32();
        for _ in 0..arr_len {
            data.push(self.extract_val());
        }
        Rc::new(RefCell::new(Array::new(data)))
    }
    fn extract_func(&mut self) -> Rc<RefCell<Function>> {
        let start = self.extract_i64() as usize;
        let end = self.extract_i64() as usize;
        let param_count = self.extract_i32();
        let mut params = vec![];
        for _i in 0..param_count {
            params.push(self.extract_str());
        }
        Rc::new(RefCell::new(Function::new(
            "".to_string(),
            start,
            end,
            params,
        )))
    }
    fn extract_val(&mut self) -> Val {
        let p = self.program[self.pointer];
        self.pointer += 1;
        match p {
            0x01 => Val {
                typ: 1,
                data: Rc::new(RefCell::new(Box::new(self.extract_i16()))),
            },
            0x02 => Val {
                typ: 2,
                data: Rc::new(RefCell::new(Box::new(self.extract_i32()))),
            },
            0x03 => Val {
                typ: 3,
                data: Rc::new(RefCell::new(Box::new(self.extract_i64()))),
            },
            0x04 => Val {
                typ: 4,
                data: Rc::new(RefCell::new(Box::new(self.extract_f32()))),
            },
            0x05 => Val {
                typ: 5,
                data: Rc::new(RefCell::new(Box::new(self.extract_f64()))),
            },
            0x06 => Val {
                typ: 6,
                data: Rc::new(RefCell::new(Box::new(self.extract_bool()))),
            },
            0x07 => Val {
                typ: 7,
                data: Rc::new(RefCell::new(Box::new(self.extract_str()))),
            },
            0x09 => Val {
                typ: 9,
                data: Rc::new(RefCell::new(Box::new(self.extract_arr()))),
            },
            0x0a => Val {
                typ: 10,
                data: Rc::new(RefCell::new(Box::new(self.extract_func()))),
            },
            0x0b => {
                let id = self.extract_str();
                if id == "askHost" {
                    return Val {
                        typ: 255,
                        data: Rc::new(RefCell::new(Box::new(0))),
                    };
                } else {
                    return self.ctx.find_val_globally(id);
                }
            }
            _ => Val {
                typ: 0,
                data: Rc::new(RefCell::new(Box::new(0))),
            },
        }
    }
    fn check_float_range(&self, num: f64) -> Val {
        if num < f32::MAX.into() {
            return Val {
                typ: 4,
                data: Rc::new(RefCell::new(Box::new(num as f32))),
            };
        } else {
            return Val {
                typ: 5,
                data: Rc::new(RefCell::new(Box::new(num))),
            };
        }
    }
    fn check_int_range(&self, num: i64) -> Val {
        if num < i16::MAX.into() {
            return Val {
                typ: 1,
                data: Rc::new(RefCell::new(Box::new(num as i16))),
            };
        } else if num < i32::MAX.into() {
            return Val {
                typ: 2,
                data: Rc::new(RefCell::new(Box::new(num as i32))),
            };
        } else {
            return Val {
                typ: 3,
                data: Rc::new(RefCell::new(Box::new(num))),
            };
        }
    }
    fn operate_sum(&self, arg1: Val, arg2: Val) -> Val {
        match arg1.typ {
            1 | 2 | 3 => {
                let val1 = match arg1.typ {
                    1 => arg1.as_i16() as i64,
                    2 => arg1.as_i32() as i64,
                    3 => arg1.as_i64() as i64,
                    _ => 0,
                };
                match arg2.typ {
                    1 => {
                        let val2 = arg2.as_i16() as i64;
                        self.check_int_range(val1 + val2)
                    }
                    2 => {
                        let val2 = arg2.as_i32() as i64;
                        self.check_int_range(val1 + val2)
                    }
                    3 => {
                        let val2 = arg2.as_i64() as i64;
                        self.check_int_range(val1 + val2)
                    }
                    4 => {
                        let val2 = arg2.as_f32() as f64;
                        let val1_temp = val1 as f64;
                        self.check_float_range(val1_temp + val2)
                    }
                    5 => {
                        let val2 = arg2.as_f64() as f64;
                        let val1_temp = val1 as f64;
                        self.check_float_range(val1_temp + val2)
                    }
                    6 => {
                        panic!("elpian error: boolean and integer can not be summed");
                    }
                    7 => {
                        let val2 = arg2.as_string();
                        let val1_temp = val1.to_string();
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(format!("{}{}", val1_temp, val2)))),
                        }
                    }
                    8 => {
                        panic!("elpian error: object and integer can not be summed");
                    }
                    9 => {
                        let mut val2 = arg2.as_array().borrow().clone_arr();
                        val2.data.insert(0, arg1);
                        Val {
                            typ: 9,
                            data: Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(val2))))),
                        }
                    }
                    10 => {
                        panic!("elpian error: function and integer can not be summed");
                    }
                    _ => {
                        panic!("elpian error: unknown data type and integer can not be summed");
                    }
                }
            }
            4 | 5 => {
                let val1 = match arg1.typ {
                    4 => arg1.as_f32() as f64,
                    5 => arg1.as_f64() as f64,
                    _ => 0.0,
                };
                match arg2.typ {
                    1 => {
                        let val2 = arg2.as_i16() as f64;
                        self.check_float_range(val1 + val2)
                    }
                    2 => {
                        let val2 = arg2.as_i32() as f64;
                        self.check_float_range(val1 + val2)
                    }
                    3 => {
                        let val2 = arg2.as_i64() as f64;
                        self.check_float_range(val1 + val2)
                    }
                    4 => {
                        let val2 = arg2.as_f32() as f64;
                        self.check_float_range(val1 + val2)
                    }
                    5 => {
                        let val2 = arg2.as_f64() as f64;
                        self.check_float_range(val1 + val2)
                    }
                    6 => {
                        panic!("elpian error: boolean and float can not be summed");
                    }
                    7 => {
                        let val2 = arg2.as_string();
                        let val1_temp = val1.to_string();
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(format!("{}{}", val1_temp, val2)))),
                        }
                    }
                    8 => {
                        panic!("elpian error: object and float can not be summed");
                    }
                    9 => {
                        let mut val2 = arg2.as_array().borrow().clone_arr();
                        val2.data.insert(0, arg1);
                        Val {
                            typ: 9,
                            data: Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(val2))))),
                        }
                    }
                    10 => {
                        panic!("elpian error: function and float can not be summed");
                    }
                    _ => {
                        panic!("elpian error: unknown data type and float can not be summed");
                    }
                }
            }
            6 => {
                let val1 = arg1.as_bool();
                match arg2.typ {
                    1 => {
                        panic!("elpian error: bool and integer can not be summed");
                    }
                    2 => {
                        panic!("elpian error: bool and integer can not be summed");
                    }
                    3 => {
                        panic!("elpian error: objeboolt and integer can not be summed");
                    }
                    4 => {
                        panic!("elpian error: bool and float can not be summed");
                    }
                    5 => {
                        panic!("elpian error: bool and float can not be summed");
                    }
                    6 => {
                        let val2 = arg2.as_bool();
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(val1 ^ val2))),
                        }
                    }
                    7 => {
                        let val2 = arg2.as_string();
                        let val1_temp = val1.to_string();
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(format!("{}{}", val1_temp, val2)))),
                        }
                    }
                    8 => {
                        panic!("elpian error: object and bool can not be summed");
                    }
                    9 => {
                        let mut val2 = arg2.as_array().borrow().clone_arr();
                        val2.data.insert(0, arg1);
                        Val {
                            typ: 9,
                            data: Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(val2))))),
                        }
                    }
                    10 => {
                        panic!("elpian error: function and bool can not be summed");
                    }
                    _ => {
                        panic!("elpian error: unknown data type and bool can not be summed");
                    }
                }
            }
            7 => {
                let val1 = arg1.as_string();
                match arg2.typ {
                    1 => {
                        let val2 = arg2.as_i16().to_string();
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(format!("{}{}", val1, val2)))),
                        }
                    }
                    2 => {
                        let val2 = arg2.as_i32().to_string();
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(format!("{}{}", val1, val2)))),
                        }
                    }
                    3 => {
                        let val2 = arg2.as_i64().to_string();
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(format!("{}{}", val1, val2)))),
                        }
                    }
                    4 => {
                        let val2 = arg2.as_f32().to_string();
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(format!("{}{}", val1, val2)))),
                        }
                    }
                    5 => {
                        let val2 = arg2.as_f64().to_string();
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(format!("{}{}", val1, val2)))),
                        }
                    }
                    6 => {
                        let val2 = arg2.as_bool().to_string();
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(format!("{}{}", val1, val2)))),
                        }
                    }
                    7 => {
                        let val2 = arg2.as_string();
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(format!("{}{}", val1, val2)))),
                        }
                    }
                    8 => {
                        let val2 = arg2.as_object().borrow().stringify();
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(format!("{}{}", val1, val2)))),
                        }
                    }
                    9 => {
                        let val2 = arg2.as_array().borrow().stringify();
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(format!("{}{}", val1, val2)))),
                        }
                    }
                    10 => {
                        panic!("elpian error: function and string can not be summed");
                    }
                    _ => {
                        panic!("elpian error: unknown data type and string can not be summed");
                    }
                }
            }
            8 => {
                let val1 = arg1.as_object();
                match arg2.typ {
                    1 => {
                        panic!("elpian error: object and integer can not be summed");
                    }
                    2 => {
                        panic!("elpian error: object and integer can not be summed");
                    }
                    3 => {
                        panic!("elpian error: object and integer can not be summed");
                    }
                    4 => {
                        panic!("elpian error: object and float can not be summed");
                    }
                    5 => {
                        panic!("elpian error: object and float can not be summed");
                    }
                    6 => {
                        panic!("elpian error: object and bool can not be summed");
                    }
                    7 => {
                        let val1_temp = val1.borrow().stringify();
                        let val2 = arg2.as_string();
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(format!("{}{}", val1_temp, val2)))),
                        }
                    }
                    8 => {
                        let val2 = arg2.as_object();
                        val2.borrow().data.data.iter().for_each(|(k, v)| {
                            val1.borrow_mut().data.data.insert(k.clone(), v.clone());
                        });
                        Val {
                            typ: 8,
                            data: Rc::new(RefCell::new(Box::new(val2))),
                        }
                    }
                    9 => {
                        let mut val2 = arg2.as_array().borrow().clone_arr();
                        val2.data.insert(0, arg1);
                        Val {
                            typ: 9,
                            data: Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(val2))))),
                        }
                    }
                    10 => {
                        panic!("elpian error: function and object can not be summed");
                    }
                    _ => {
                        panic!("elpian error: unknown data type and object can not be summed");
                    }
                }
            }
            9 => {
                let val1 = arg1.as_array();
                match arg2.typ {
                    1 | 2 | 3 | 4 | 5 | 6 | 8 | 10 => {
                        val1.borrow_mut().data.push(arg2);
                        Val {
                            typ: 9,
                            data: Rc::new(RefCell::new(Box::new(val1))),
                        }
                    }
                    7 => {
                        let val1_temp = val1.borrow().stringify();
                        let val2 = arg2.as_string();
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(format!("{}{}", val1_temp, val2)))),
                        }
                    }
                    9 => {
                        let mut val1 = arg2.as_array().borrow().clone_arr();
                        val1.data.append(&mut arg2.as_array().borrow().data.clone());
                        Val {
                            typ: 9,
                            data: Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(val1))))),
                        }
                    }
                    _ => {
                        panic!("elpian error: unknown data type and array can not be summed");
                    }
                }
            }
            10 => {
                panic!("elpian error: function can not be summed with other types");
            }
            _ => {
                panic!("elpian error: unknown type can not be summed with other types");
            }
        }
    }
    fn operate_multiply(&self, arg1: Val, arg2: Val) -> Val {
        match arg1.typ {
            1 | 2 | 3 => {
                let val1 = match arg1.typ {
                    1 => arg1.as_i16() as i64,
                    2 => arg1.as_i32() as i64,
                    3 => arg1.as_i64() as i64,
                    _ => 0,
                };
                match arg2.typ {
                    1 => {
                        let val2 = arg2.as_i16() as i64;
                        self.check_int_range(val1 * val2)
                    }
                    2 => {
                        let val2 = arg2.as_i32() as i64;
                        self.check_int_range(val1 * val2)
                    }
                    3 => {
                        let val2 = arg2.as_i64() as i64;
                        self.check_int_range(val1 * val2)
                    }
                    4 => {
                        let val2 = arg2.as_f32() as f64;
                        let val1_temp = val1 as f64;
                        self.check_float_range(val1_temp * val2)
                    }
                    5 => {
                        let val2 = arg2.as_f64() as f64;
                        let val1_temp = val1 as f64;
                        self.check_float_range(val1_temp * val2)
                    }
                    6 => {
                        panic!("elpian error: boolean and integer can not be multiplied");
                    }
                    7 => {
                        let val2 = arg2.as_string();
                        let mut res = "".to_string();
                        for _i in 0..val1 {
                            res.push_str(&val2);
                        }
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(res))),
                        }
                    }
                    8 => {
                        panic!("elpian error: object and integer can not be multiplied");
                    }
                    9 => {
                        let val2 = arg2.as_array();
                        let mut res: Vec<Val> = vec![];
                        for _i in 0..val1 {
                            res.append(&mut val2.borrow().data.clone());
                        }
                        Val {
                            typ: 9,
                            data: Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(
                                Array::new(res),
                            ))))),
                        }
                    }
                    10 => {
                        panic!("elpian error: function and integer can not be multiplied");
                    }
                    _ => {
                        panic!("elpian error: unknown data type and integer can not be multiplied");
                    }
                }
            }
            4 | 5 => {
                let val1 = match arg1.typ {
                    4 => arg1.as_f32() as f64,
                    5 => arg1.as_f64() as f64,
                    _ => 0.0,
                };
                match arg2.typ {
                    1 => {
                        let val2 = arg2.as_i16() as f64;
                        self.check_float_range(val1 * val2)
                    }
                    2 => {
                        let val2 = arg2.as_i32() as f64;
                        self.check_float_range(val1 * val2)
                    }
                    3 => {
                        let val2 = arg2.as_i64() as f64;
                        self.check_float_range(val1 * val2)
                    }
                    4 => {
                        let val2 = arg2.as_f32() as f64;
                        self.check_float_range(val1 * val2)
                    }
                    5 => {
                        let val2 = arg2.as_f64() as f64;
                        self.check_float_range(val1 * val2)
                    }
                    6 => {
                        panic!("elpian error: boolean and float can not be multiplied");
                    }
                    7 => {
                        let val2 = arg2.as_string();
                        let val1_temp = val1.to_string();
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(format!("{}{}", val1_temp, val2)))),
                        }
                    }
                    8 => {
                        panic!("elpian error: object and float can not be multiplied");
                    }
                    9 => {
                        panic!("elpian error: array and float can not be multiplied");
                    }
                    10 => {
                        panic!("elpian error: function and float can not be multiplied");
                    }
                    _ => {
                        panic!("elpian error: unknown data type and float can not be multiplied");
                    }
                }
            }
            6 => {
                let val1 = arg1.as_bool();
                match arg2.typ {
                    1 => {
                        panic!("elpian error: bool and integer can not be multiplied");
                    }
                    2 => {
                        panic!("elpian error: bool and integer can not be multiplied");
                    }
                    3 => {
                        panic!("elpian error: bool and integer can not be multiplied");
                    }
                    4 => {
                        panic!("elpian error: bool and float can not be multiplied");
                    }
                    5 => {
                        panic!("elpian error: bool and float can not be multiplied");
                    }
                    6 => {
                        let val2 = arg2.as_bool();
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(val1 & val2))),
                        }
                    }
                    7 => {
                        let val2 = arg2.as_string();
                        let val1_temp = val1.to_string();
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(format!("{}{}", val1_temp, val2)))),
                        }
                    }
                    8 => {
                        if val1 {
                            return arg2.clone();
                        } else {
                            return Val {
                                typ: 8,
                                data: Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(
                                    Object::new(-2, ValGroup::new_empty()),
                                ))))),
                            };
                        }
                    }
                    9 => {
                        if val1 {
                            return arg2.clone();
                        } else {
                            return Val {
                                typ: 9,
                                data: Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(
                                    Array::new_empty(),
                                ))))),
                            };
                        }
                    }
                    10 => {
                        panic!("elpian error: function and bool can not be multiplied");
                    }
                    _ => {
                        panic!("elpian error: unknown data type and bool can not be multiplied");
                    }
                }
            }
            7 => {
                let val1 = arg1.as_string();
                match arg2.typ {
                    1 => {
                        let mut res = "".to_string();
                        for _i in 0..arg2.as_i16() {
                            res.push_str(&val1);
                        }
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(res))),
                        }
                    }
                    2 => {
                        let mut res = "".to_string();
                        for _i in 0..arg2.as_i32() {
                            res.push_str(&val1);
                        }
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(res))),
                        }
                    }
                    3 => {
                        let mut res = "".to_string();
                        for _i in 0..arg2.as_i64() {
                            res.push_str(&val1);
                        }
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(res))),
                        }
                    }
                    4 => {
                        panic!("elpian error: string and float can not be multiplied");
                    }
                    5 => {
                        panic!("elpian error: string and float can not be multiplied");
                    }
                    6 => {
                        panic!("elpian error: string and bool can not be multiplied");
                    }
                    7 => {
                        panic!("elpian error: string and string can not be multiplied");
                    }
                    8 => {
                        panic!("elpian error: string and object can not be multiplied");
                    }
                    9 => {
                        panic!("elpian error: string and array can not be multiplied");
                    }
                    10 => {
                        panic!("elpian error: string and function can not be multiplied");
                    }
                    _ => {
                        panic!("elpian error: string type and unknown data can not be multiplied");
                    }
                }
            }
            8 => {
                panic!("elpian error: object can not be multiplied with other types");
            }
            9 => {
                let val1 = arg1.as_array();
                match arg2.typ {
                    1 => {
                        let mut res: Vec<Val> = vec![];
                        for _i in 0..arg2.as_i16() {
                            res.append(&mut val1.borrow().data.clone());
                        }
                        Val {
                            typ: 9,
                            data: Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(
                                Array::new(res),
                            ))))),
                        }
                    }
                    2 => {
                        let mut res: Vec<Val> = vec![];
                        for _i in 0..arg2.as_i32() {
                            res.append(&mut val1.borrow().data.clone());
                        }
                        Val {
                            typ: 9,
                            data: Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(
                                Array::new(res),
                            ))))),
                        }
                    }
                    3 => {
                        let mut res: Vec<Val> = vec![];
                        for _i in 0..arg2.as_i64() {
                            res.append(&mut val1.borrow().data.clone());
                        }
                        Val {
                            typ: 9,
                            data: Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(
                                Array::new(res),
                            ))))),
                        }
                    }
                    4 | 5 => {
                        panic!("elpian error: array and float can not be multiplied");
                    }
                    6 => {
                        if arg2.as_bool() {
                            return arg1.clone();
                        } else {
                            return Val {
                                typ: 9,
                                data: Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(
                                    Array::new_empty(),
                                ))))),
                            };
                        }
                    }
                    7 => {
                        panic!("elpian error: array and string can not be multiplied");
                    }
                    8 => {
                        panic!("elpian error: array and object can not be multiplied");
                    }
                    10 => {
                        panic!("elpian error: array and function can not be multiplied");
                    }
                    _ => {
                        panic!("elpian error: unknown data type and array can not be multiplied");
                    }
                }
            }
            10 => {
                panic!("elpian error: function can not be multiplied with other types");
            }
            _ => {
                panic!("elpian error: unknown type can not be multiplied with other types");
            }
        }
    }
    fn operate_subtract(&self, arg1: Val, arg2: Val) -> Val {
        match arg1.typ {
            1 | 2 | 3 => {
                let val1 = match arg1.typ {
                    1 => arg1.as_i16() as i64,
                    2 => arg1.as_i32() as i64,
                    3 => arg1.as_i64() as i64,
                    _ => 0,
                };
                match arg2.typ {
                    1 => {
                        let val2 = arg2.as_i16() as i64;
                        self.check_int_range(val1 - val2)
                    }
                    2 => {
                        let val2 = arg2.as_i32() as i64;
                        self.check_int_range(val1 - val2)
                    }
                    3 => {
                        let val2 = arg2.as_i64() as i64;
                        self.check_int_range(val1 - val2)
                    }
                    4 => {
                        let val2 = arg2.as_f32() as f64;
                        let val1_temp = val1 as f64;
                        self.check_float_range(val1_temp - val2)
                    }
                    5 => {
                        let val2 = arg2.as_f64() as f64;
                        let val1_temp = val1 as f64;
                        self.check_float_range(val1_temp - val2)
                    }
                    6 => {
                        panic!("elpian error: boolean and integer can not be subtracted");
                    }
                    7 => {
                        panic!("elpian error: string can not be subtracted from integer");
                    }
                    8 => {
                        panic!("elpian error: object and integer can not be subtracted");
                    }
                    9 => {
                        panic!("elpian error: array can not be subtracted from integer");
                    }
                    10 => {
                        panic!("elpian error: function and integer can not be subtracted");
                    }
                    _ => {
                        panic!("elpian error: unknown data type and integer can not be subtracted");
                    }
                }
            }
            4 | 5 => {
                let val1 = match arg1.typ {
                    4 => arg1.as_f32() as f64,
                    5 => arg1.as_f64() as f64,
                    _ => 0.0,
                };
                match arg2.typ {
                    1 => {
                        let val2 = arg2.as_i16() as f64;
                        self.check_float_range(val1 - val2)
                    }
                    2 => {
                        let val2 = arg2.as_i32() as f64;
                        self.check_float_range(val1 - val2)
                    }
                    3 => {
                        let val2 = arg2.as_i64() as f64;
                        self.check_float_range(val1 - val2)
                    }
                    4 => {
                        let val2 = arg2.as_f32() as f64;
                        self.check_float_range(val1 - val2)
                    }
                    5 => {
                        let val2 = arg2.as_f64() as f64;
                        self.check_float_range(val1 - val2)
                    }
                    6 => {
                        panic!("elpian error: boolean and float can not be subtracted");
                    }
                    7 => {
                        panic!("elpian error: string can not be subtracted from float");
                    }
                    8 => {
                        panic!("elpian error: object and float can not be subtracted");
                    }
                    9 => {
                        panic!("elpian error: array can not be subtracted from float");
                    }
                    10 => {
                        panic!("elpian error: function and float can not be subtracted");
                    }
                    _ => {
                        panic!("elpian error: unknown data type and float can not be subtracted");
                    }
                }
            }
            6 => {
                let val1 = arg1.as_bool();
                match arg2.typ {
                    1 => {
                        panic!("elpian error: bool and float can not be subtracted");
                    }
                    2 => {
                        panic!("elpian error: bool and integer can not be subtracted");
                    }
                    3 => {
                        panic!("elpian error: bool and integer can not be subtracted");
                    }
                    4 => {
                        panic!("elpian error: bool and float can not be subtracted");
                    }
                    5 => {
                        panic!("elpian error: bool and float can not be subtracted");
                    }
                    6 => {
                        let val2 = arg2.as_bool();
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(val1 ^ val2))),
                        }
                    }
                    7 => {
                        panic!("elpian error: bool and string can not be subtracted");
                    }
                    8 => {
                        panic!("elpian error: bool and object can not be subtracted");
                    }
                    9 => {
                        let val2 = arg2.as_array();
                        val2.borrow_mut().data.insert(0, arg1);
                        Val {
                            typ: 9,
                            data: Rc::new(RefCell::new(Box::new(val2))),
                        }
                    }
                    10 => {
                        panic!("elpian error: function and bool can not be subtracted");
                    }
                    _ => {
                        panic!("elpian error: unknown data type and bool can not be subtracted");
                    }
                }
            }
            7 => {
                let mut val1 = arg1.as_string();
                match arg2.typ {
                    1 => {
                        let val2 = arg2.as_i16().to_string();
                        val1 = val1.replace(&val2, "");
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(val1))),
                        }
                    }
                    2 => {
                        let val2 = arg2.as_i32().to_string();
                        val1 = val1.replace(&val2, "");
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(val1))),
                        }
                    }
                    3 => {
                        let val2 = arg2.as_i64().to_string();
                        val1 = val1.replace(&val2, "");
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(val1))),
                        }
                    }
                    4 => {
                        let val2 = arg2.as_f32().to_string();
                        val1 = val1.replace(&val2, "");
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(val1))),
                        }
                    }
                    5 => {
                        let val2 = arg2.as_f64().to_string();
                        val1 = val1.replace(&val2, "");
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(val1))),
                        }
                    }
                    6 => {
                        let val2 = arg2.as_bool().to_string();
                        val1 = val1.replace(&val2, "");
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(val1))),
                        }
                    }
                    7 => {
                        let val2 = arg2.as_string();
                        val1 = val1.replace(&val2, "");
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(val1))),
                        }
                    }
                    8 => {
                        let val2 = arg2.as_object().borrow().stringify();
                        val1 = val1.replace(&val2, "");
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(val1))),
                        }
                    }
                    9 => {
                        let val2 = arg2.as_array().borrow().stringify();
                        val1 = val1.replace(&val2, "");
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(val1))),
                        }
                    }
                    10 => {
                        panic!("elpian error: function and string can not be subtracted");
                    }
                    _ => {
                        panic!("elpian error: unknown data type and string can not be subtracted");
                    }
                }
            }
            8 => {
                let val1 = arg1.as_object();
                match arg2.typ {
                    1 => {
                        panic!("elpian error: object and integer can not be subtracted");
                    }
                    2 => {
                        panic!("elpian error: object and integer can not be subtracted");
                    }
                    3 => {
                        panic!("elpian error: object and integer can not be subtracted");
                    }
                    4 => {
                        panic!("elpian error: object and float can not be subtracted");
                    }
                    5 => {
                        panic!("elpian error: object and float can not be subtracted");
                    }
                    6 => {
                        panic!("elpian error: object and bool can not be subtracted");
                    }
                    7 => {
                        let mut val1_temp = val1.borrow().stringify();
                        let val2 = arg2.as_string();
                        val1_temp = val1_temp.replace(&val2, "");
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(val1_temp))),
                        }
                    }
                    8 => {
                        let val2 = arg2.as_object();
                        let mut deleted: Vec<String> = vec![];
                        val2.borrow().data.data.iter().for_each(|(k, v)| {
                            if val1.borrow().data.data.contains_key(k) {
                                let val1_data = &val1.borrow().data.data;
                                let v2 = val1_data.get(k).unwrap();
                                if self.is_eq(v.clone(), v2.clone()) {
                                    deleted.push(k.clone());
                                }
                            }
                        });
                        deleted.iter().for_each(|k| {
                            val1.borrow_mut().data.data.remove(&k.clone());
                        });
                        Val {
                            typ: 8,
                            data: Rc::new(RefCell::new(Box::new(val2))),
                        }
                    }
                    9 => {
                        panic!("elpian error: array can not be subtracted from object");
                    }
                    10 => {
                        panic!("elpian error: function and integer can not be summed");
                    }
                    _ => {
                        panic!("elpian error: unknown data type and integer can not be summed");
                    }
                }
            }
            9 => {
                let val1 = arg1.as_array();
                match arg2.typ {
                    1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 10 => {
                        val1.borrow_mut().data = val1
                            .borrow()
                            .data
                            .iter()
                            .filter_map(|item| {
                                if self.is_eq(item.clone(), arg2.clone()) {
                                    return None;
                                } else {
                                    return Some(item.clone());
                                }
                            })
                            .collect();
                        Val {
                            typ: 9,
                            data: Rc::new(RefCell::new(Box::new(val1))),
                        }
                    }
                    9 => {
                        let val2 = arg2.as_array();
                        val1.borrow_mut().data = val1
                            .borrow()
                            .data
                            .iter()
                            .filter_map(|item| {
                                for item2 in val2.borrow().data.iter() {
                                    if self.is_eq(item.clone(), item2.clone()) {
                                        return None;
                                    }
                                }
                                return Some(item.clone());
                            })
                            .collect();
                        Val {
                            typ: 9,
                            data: Rc::new(RefCell::new(Box::new(val1))),
                        }
                    }
                    _ => {
                        panic!("elpian error: unknown data type and integer can not be summed");
                    }
                }
            }
            10 => {
                panic!("nothing can be subtracted from function");
            }
            _ => {
                panic!("can not subtract unknown type with anything");
            }
        }
    }
    fn operate_division(&self, arg1: Val, arg2: Val) -> Val {
        match arg1.typ {
            1 | 2 | 3 => {
                let val1 = match arg1.typ {
                    1 => arg1.as_i16() as f64,
                    2 => arg1.as_i32() as f64,
                    3 => arg1.as_i64() as f64,
                    _ => 0.0,
                };
                match arg2.typ {
                    1 => {
                        let val2 = arg2.as_i16() as f64;
                        self.check_float_range(val1 / val2)
                    }
                    2 => {
                        let val2 = arg2.as_i32() as f64;
                        self.check_float_range(val1 / val2)
                    }
                    3 => {
                        let val2 = arg2.as_i64() as f64;
                        self.check_float_range(val1 / val2)
                    }
                    4 => {
                        let val2 = arg2.as_f32() as f64;
                        self.check_float_range(val1 / val2)
                    }
                    5 => {
                        let val2 = arg2.as_f64() as f64;
                        self.check_float_range(val1 / val2)
                    }
                    6 => {
                        panic!("elpian error: integer and boolean can not be divisioned");
                    }
                    7 => {
                        panic!("elpian error: integer and boolean can not be divisioned");
                    }
                    8 => {
                        panic!("elpian error: integer and object can not be divisioned");
                    }
                    9 => {
                        panic!("elpian error: integer and array can not be divisioned");
                    }
                    10 => {
                        panic!("elpian error: integer and function can not be divisioned");
                    }
                    _ => {
                        panic!("elpian error: integer and unknown data type can not be divisioned");
                    }
                }
            }
            4 | 5 => {
                let val1 = match arg1.typ {
                    4 => arg1.as_f32() as f64,
                    5 => arg1.as_f64() as f64,
                    _ => 0.0,
                };
                match arg2.typ {
                    1 => {
                        let val2 = arg2.as_i16() as f64;
                        self.check_float_range(val1 / val2)
                    }
                    2 => {
                        let val2 = arg2.as_i32() as f64;
                        self.check_float_range(val1 / val2)
                    }
                    3 => {
                        let val2 = arg2.as_i64() as f64;
                        self.check_float_range(val1 / val2)
                    }
                    4 => {
                        let val2 = arg2.as_f32() as f64;
                        self.check_float_range(val1 / val2)
                    }
                    5 => {
                        let val2 = arg2.as_f64() as f64;
                        self.check_float_range(val1 / val2)
                    }
                    6 => {
                        panic!("elpian error: float and boolean can not be divisioned");
                    }
                    7 => {
                        panic!("elpian error: float and string can not be divisioned");
                    }
                    8 => {
                        panic!("elpian error: float and object can not be divisioned");
                    }
                    9 => {
                        panic!("elpian error: float and array can not be divisioned");
                    }
                    10 => {
                        panic!("elpian error: float and function can not be divisioned");
                    }
                    _ => {
                        panic!("elpian error: float and unknown data type can not be divisioned");
                    }
                }
            }
            6 => {
                panic!("elpian error: bool can not be divisioned with other types");
            }
            7 => {
                panic!("elpian error: bool can not be divisioned with other types");
            }
            8 => {
                panic!("elpian error: object can not be divisioned with other types");
            }
            9 => {
                panic!("elpian error: array can not be divisioned with other types");
            }
            10 => {
                panic!("elpian error: function can not be divisioned with other types");
            }
            _ => {
                panic!("elpian error: unknown type can not be divisioned with other types");
            }
        }
    }
    fn is_eq(&self, v: Val, v2: Val) -> bool {
        return match v.typ {
            1 | 2 | 3 => {
                let v_val = match v.typ {
                    1 => v.as_i16() as i64,
                    2 => v.as_i32() as i64,
                    3 => v.as_i64() as i64,
                    _ => 0,
                };
                match v2.typ {
                    1 | 2 | 3 => {
                        let v2_val = match v2.typ {
                            1 => v2.as_i16() as i64,
                            2 => v2.as_i32() as i64,
                            3 => v2.as_i64() as i64,
                            _ => 0,
                        };
                        v_val == v2_val
                    }
                    4 | 5 => {
                        let v_val_temp = v_val as f64;
                        let v2_val = match v2.typ {
                            4 => v2.as_f32() as f64,
                            5 => v2.as_f64() as f64,
                            _ => 0.0,
                        };
                        v_val_temp == v2_val
                    }
                    _ => false,
                }
            }
            4 | 5 => {
                let v_val = match v.typ {
                    4 => v.as_f32() as f64,
                    5 => v.as_f64() as f64,
                    _ => 0.0,
                };
                match v2.typ {
                    1 | 2 | 3 => {
                        let v2_val = match v2.typ {
                            1 => v2.as_i16() as f64,
                            2 => v2.as_i32() as f64,
                            3 => v2.as_i64() as f64,
                            _ => 0.0,
                        };
                        v_val == v2_val
                    }
                    4 | 5 => {
                        let v2_val = match v2.typ {
                            4 => v2.as_f32() as f64,
                            5 => v2.as_f64() as f64,
                            _ => 0.0,
                        };
                        v_val == v2_val
                    }
                    _ => false,
                }
            }
            6 => {
                let v_val = v.as_bool();
                match v2.typ {
                    6 => {
                        let v2_val = v2.as_bool();
                        v_val == v2_val
                    }
                    _ => false,
                }
            }
            7 => {
                let v_val = v.as_string();
                match v2.typ {
                    7 => {
                        let v2_val = v2.as_string();
                        v_val == v2_val
                    }
                    _ => false,
                }
            }
            8 => {
                let v_val = v.as_object();
                match v2.typ {
                    8 => {
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
            9 => {
                let v_val = v.as_array();
                match v2.typ {
                    9 => {
                        let v2_val = v2.as_array();
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
                                return true;
                            } else {
                                return false;
                            }
                        });
                    }
                    _ => false,
                }
            }
            10 => {
                let v_val = v.as_func();
                match v2.typ {
                    10 => {
                        let v2_val = v2.as_func();
                        v_val.borrow().start == v2_val.borrow().start
                            && v_val.borrow().end == v2_val.borrow().end
                    }
                    _ => false,
                }
            }
            _ => false,
        };
    }
    fn is_ge(&self, v: Val, v2: Val) -> bool {
        return match v.typ {
            1 | 2 | 3 => {
                let v_val = match v.typ {
                    1 => v.as_i16() as i64,
                    2 => v.as_i32() as i64,
                    3 => v.as_i64() as i64,
                    _ => 0,
                };
                match v2.typ {
                    1 | 2 | 3 => {
                        let v2_val = match v2.typ {
                            1 => v2.as_i16() as i64,
                            2 => v2.as_i32() as i64,
                            3 => v2.as_i64() as i64,
                            _ => 0,
                        };
                        v_val > v2_val
                    }
                    4 | 5 => {
                        let v_val_temp = v_val as f64;
                        let v2_val = match v2.typ {
                            4 => v2.as_f32() as f64,
                            5 => v2.as_f64() as f64,
                            _ => 0.0,
                        };
                        v_val_temp > v2_val
                    }
                    _ => panic!(
                        "elpian error: numerical and non numerical values are not comparable unless it is just equality check"
                    ),
                }
            }
            4 | 5 => {
                let v_val = match v.typ {
                    4 => v.as_f32() as f64,
                    5 => v.as_f64() as f64,
                    _ => 0.0,
                };
                match v2.typ {
                    1 | 2 | 3 => {
                        let v2_val = match v2.typ {
                            1 => v2.as_i16() as f64,
                            2 => v2.as_i32() as f64,
                            3 => v2.as_i64() as f64,
                            _ => 0.0,
                        };
                        v_val > v2_val
                    }
                    4 | 5 => {
                        let v2_val = match v2.typ {
                            4 => v2.as_f32() as f64,
                            5 => v2.as_f64() as f64,
                            _ => 0.0,
                        };
                        v_val > v2_val
                    }
                    _ => panic!(
                        "elpian error: numerical and non numerical values are not comparable unless it is just equality check"
                    ),
                }
            }
            6 => {
                let v_val = v.as_bool();
                match v2.typ {
                    6 => {
                        let v2_val = v2.as_bool();
                        v_val > v2_val
                    }
                    _ => panic!(
                        "elpian error: boolean and non boolean values are not comparable unless it is just equality check"
                    ),
                }
            }
            7 => {
                let v_val = v.as_string();
                match v2.typ {
                    6 => {
                        let v2_val = v2.as_string();
                        v_val > v2_val
                    }
                    _ => panic!(
                        "elpian error: string and non string values are not comparable unless it is just equality check"
                    ),
                }
            }
            8 => {
                let v_val = v.as_object();
                match v2.typ {
                    6 => {
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
            9 => {
                let v_val = v.as_array();
                match v2.typ {
                    9 => {
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
                        return counter1 > counter2;
                    }
                    _ => panic!(
                        "elpian error: array and non array values are not comparable unless it is just equality check"
                    ),
                }
            }
            10 => panic!(
                "elpian error: function types are not comparable unless it is just equality check"
            ),
            _ => panic!("elpian error: unknown types are not comparable"),
        };
    }
    fn is_gee(&self, v: Val, v2: Val) -> bool {
        return match v.typ {
            1 | 2 | 3 => {
                let v_val = match v.typ {
                    1 => v.as_i16() as i64,
                    2 => v.as_i32() as i64,
                    3 => v.as_i64() as i64,
                    _ => 0,
                };
                match v2.typ {
                    1 | 2 | 3 => {
                        let v2_val = match v2.typ {
                            1 => v2.as_i16() as i64,
                            2 => v2.as_i32() as i64,
                            3 => v2.as_i64() as i64,
                            _ => 0,
                        };
                        v_val >= v2_val
                    }
                    4 | 5 => {
                        let v_val_temp = v_val as f64;
                        let v2_val = match v2.typ {
                            4 => v2.as_f32() as f64,
                            5 => v2.as_f64() as f64,
                            _ => 0.0,
                        };
                        v_val_temp >= v2_val
                    }
                    _ => panic!(
                        "elpian error: numerical and non numerical values are not comparable unless it is just equality check"
                    ),
                }
            }
            4 | 5 => {
                let v_val = match v.typ {
                    4 => v.as_f32() as f64,
                    5 => v.as_f64() as f64,
                    _ => 0.0,
                };
                match v2.typ {
                    1 | 2 | 3 => {
                        let v2_val = match v2.typ {
                            1 => v2.as_i16() as f64,
                            2 => v2.as_i32() as f64,
                            3 => v2.as_i64() as f64,
                            _ => 0.0,
                        };
                        v_val >= v2_val
                    }
                    4 | 5 => {
                        let v2_val = match v2.typ {
                            4 => v2.as_f32() as f64,
                            5 => v2.as_f64() as f64,
                            _ => 0.0,
                        };
                        v_val >= v2_val
                    }
                    _ => panic!(
                        "elpian error: numerical and non numerical values are not comparable unless it is just equality check"
                    ),
                }
            }
            6 => {
                let v_val = v.as_bool();
                match v2.typ {
                    6 => {
                        let v2_val = v2.as_bool();
                        v_val >= v2_val
                    }
                    _ => panic!(
                        "elpian error: boolean and non boolean values are not comparable unless it is just equality check"
                    ),
                }
            }
            7 => {
                let v_val = v.as_string();
                match v2.typ {
                    6 => {
                        let v2_val = v2.as_string();
                        v_val >= v2_val
                    }
                    _ => panic!(
                        "elpian error: string and non string values are not comparable unless it is just equality check"
                    ),
                }
            }
            8 => {
                let v_val = v.as_object();
                match v2.typ {
                    6 => {
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
            9 => {
                let v_val = v.as_array();
                match v2.typ {
                    9 => {
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
                        return counter1 >= counter2;
                    }
                    _ => panic!(
                        "elpian error: array and non array values are not comparable unless it is just equality check"
                    ),
                }
            }
            10 => panic!(
                "elpian error: function types are not comparable unless it is just equality check"
            ),
            _ => panic!("elpian error: unknown types are not comparable"),
        };
    }
    fn is_le(&self, v: Val, v2: Val) -> bool {
        return match v.typ {
            1 | 2 | 3 => {
                let v_val = match v.typ {
                    1 => v.as_i16() as i64,
                    2 => v.as_i32() as i64,
                    3 => v.as_i64() as i64,
                    _ => 0,
                };
                match v2.typ {
                    1 | 2 | 3 => {
                        let v2_val = match v2.typ {
                            1 => v2.as_i16() as i64,
                            2 => v2.as_i32() as i64,
                            3 => v2.as_i64() as i64,
                            _ => 0,
                        };
                        v_val < v2_val
                    }
                    4 | 5 => {
                        let v_val_temp = v_val as f64;
                        let v2_val = match v2.typ {
                            4 => v2.as_f32() as f64,
                            5 => v2.as_f64() as f64,
                            _ => 0.0,
                        };
                        v_val_temp < v2_val
                    }
                    _ => panic!(
                        "elpian error: numerical and non numerical values are not comparable unless it is just equality check"
                    ),
                }
            }
            4 | 5 => {
                let v_val = match v.typ {
                    4 => v.as_f32() as f64,
                    5 => v.as_f64() as f64,
                    _ => 0.0,
                };
                match v2.typ {
                    1 | 2 | 3 => {
                        let v2_val = match v2.typ {
                            1 => v2.as_i16() as f64,
                            2 => v2.as_i32() as f64,
                            3 => v2.as_i64() as f64,
                            _ => 0.0,
                        };
                        v_val < v2_val
                    }
                    4 | 5 => {
                        let v2_val = match v2.typ {
                            4 => v2.as_f32() as f64,
                            5 => v2.as_f64() as f64,
                            _ => 0.0,
                        };
                        v_val < v2_val
                    }
                    _ => panic!(
                        "elpian error: numerical and non numerical values are not comparable unless it is just equality check"
                    ),
                }
            }
            6 => {
                let v_val = v.as_bool();
                match v2.typ {
                    6 => {
                        let v2_val = v2.as_bool();
                        v_val < v2_val
                    }
                    _ => panic!(
                        "elpian error: boolean and non boolean values are not comparable unless it is just equality check"
                    ),
                }
            }
            7 => {
                let v_val = v.as_string();
                match v2.typ {
                    6 => {
                        let v2_val = v2.as_string();
                        v_val < v2_val
                    }
                    _ => panic!(
                        "elpian error: string and non string values are not comparable unless it is just equality check"
                    ),
                }
            }
            8 => {
                let v_val = v.as_object();
                match v2.typ {
                    6 => {
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
            9 => {
                let v_val = v.as_array();
                match v2.typ {
                    9 => {
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
                        return counter1 < counter2;
                    }
                    _ => panic!(
                        "elpian error: array and non array values are not comparable unless it is just equality check"
                    ),
                }
            }
            10 => panic!(
                "elpian error: function types are not comparable unless it is just equality check"
            ),
            _ => panic!("elpian error: unknown types are not comparable"),
        };
    }
    fn is_lee(&self, v: Val, v2: Val) -> bool {
        return match v.typ {
            1 | 2 | 3 => {
                let v_val = match v.typ {
                    1 => v.as_i16() as i64,
                    2 => v.as_i32() as i64,
                    3 => v.as_i64() as i64,
                    _ => 0,
                };
                match v2.typ {
                    1 | 2 | 3 => {
                        let v2_val = match v2.typ {
                            1 => v2.as_i16() as i64,
                            2 => v2.as_i32() as i64,
                            3 => v2.as_i64() as i64,
                            _ => 0,
                        };
                        v_val <= v2_val
                    }
                    4 | 5 => {
                        let v_val_temp = v_val as f64;
                        let v2_val = match v2.typ {
                            4 => v2.as_f32() as f64,
                            5 => v2.as_f64() as f64,
                            _ => 0.0,
                        };
                        v_val_temp <= v2_val
                    }
                    _ => panic!(
                        "elpian error: numerical and non numerical values are not comparable unless it is just equality check"
                    ),
                }
            }
            4 | 5 => {
                let v_val = match v.typ {
                    4 => v.as_f32() as f64,
                    5 => v.as_f64() as f64,
                    _ => 0.0,
                };
                match v2.typ {
                    1 | 2 | 3 => {
                        let v2_val = match v2.typ {
                            1 => v2.as_i16() as f64,
                            2 => v2.as_i32() as f64,
                            3 => v2.as_i64() as f64,
                            _ => 0.0,
                        };
                        v_val <= v2_val
                    }
                    4 | 5 => {
                        let v2_val = match v2.typ {
                            4 => v2.as_f32() as f64,
                            5 => v2.as_f64() as f64,
                            _ => 0.0,
                        };
                        v_val <= v2_val
                    }
                    _ => panic!(
                        "elpian error: numerical and non numerical values are not comparable unless it is just equality check"
                    ),
                }
            }
            6 => {
                let v_val = v.as_bool();
                match v2.typ {
                    6 => {
                        let v2_val = v2.as_bool();
                        v_val <= v2_val
                    }
                    _ => panic!(
                        "elpian error: boolean and non boolean values are not comparable unless it is just equality check"
                    ),
                }
            }
            7 => {
                let v_val = v.as_string();
                match v2.typ {
                    6 => {
                        let v2_val = v2.as_string();
                        v_val <= v2_val
                    }
                    _ => panic!(
                        "elpian error: string and non string values are not comparable unless it is just equality check"
                    ),
                }
            }
            8 => {
                let v_val = v.as_object();
                match v2.typ {
                    6 => {
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
            9 => {
                let v_val = v.as_array();
                match v2.typ {
                    9 => {
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
                        return counter1 <= counter2;
                    }
                    _ => panic!(
                        "elpian error: array and non array values are not comparable unless it is just equality check"
                    ),
                }
            }
            10 => panic!(
                "elpian error: function types are not comparable unless it is just equality check"
            ),
            _ => panic!("elpian error: unknown types are not comparable"),
        };
    }
    fn define(&mut self, id_name: String, val: Val) {
        self.ctx.define_val_globally(id_name, val);
    }
    fn assign(&mut self, id_name: String, val: Val) {
        self.ctx.update_val_globally(id_name, val);
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
        if continue_exec {
            if self.pending_func_result_value.typ != 254 {
                let returned_val = self.pending_func_result_value.clone();
                self.pending_func_result_value = Val {
                    typ: 254,
                    data: Rc::new(RefCell::new(Box::new(0))),
                };
                if !self.registers.is_empty() {
                    main_reg = Some(returned_val);
                    is_reg_state_final = false;
                }
            }
        }
        loop {
            if main_reg.is_some() {
                if !self.registers.is_empty() {
                    if self.registers.last().unwrap().borrow().get_type() == OperationTypes::ArrExpr
                    {
                        if self.registers.last().unwrap().borrow().get_state()
                            == ExecStates::ArrExprExtractInfo
                            || self.registers.last().unwrap().borrow().get_state()
                                == ExecStates::ArrExprExtractItem
                        {
                            self.registers.last().unwrap().borrow_mut().set_state(
                                ExecStates::ArrExprExtractItem,
                                Box::new(main_reg.clone().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final =
                                self.registers.last().unwrap().borrow_mut().get_state()
                                    == ExecStates::ArrExprFinished;
                            continue;
                        }
                    } else if self.registers.last().unwrap().borrow().get_type()
                        == OperationTypes::ObjExpr
                    {
                        if self.registers.last().unwrap().borrow().get_state()
                            == ExecStates::ObjExprExtractInfo
                            || self.registers.last().unwrap().borrow().get_state()
                                == ExecStates::ObjExprExtractProp
                        {
                            self.registers.last().unwrap().borrow_mut().set_state(
                                ExecStates::ObjExprExtractProp,
                                Box::new(main_reg.clone().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final =
                                self.registers.last().unwrap().borrow_mut().get_state()
                                    == ExecStates::ObjExprFinished;
                            continue;
                        }
                    } else if self.registers.last().unwrap().borrow().get_type()
                        == OperationTypes::CallFunc
                    {
                        if self.registers.last().unwrap().borrow().get_state()
                            == ExecStates::CallFuncStarted
                        {
                            let arg_count = self.extract_i32() as usize;
                            self.registers.last().unwrap().borrow_mut().set_state(
                                ExecStates::CallFuncExtractFunc,
                                Box::new((main_reg.clone().unwrap(), arg_count)),
                            );
                            main_reg = None;
                            is_reg_state_final =
                                self.registers.last().unwrap().borrow_mut().get_state()
                                    == ExecStates::CallFuncFinished;
                            continue;
                        } else if self.registers.last().unwrap().borrow().get_state()
                            == ExecStates::CallFuncExtractFunc
                            || self.registers.last().unwrap().borrow().get_state()
                                == ExecStates::CallFuncExtractParam
                        {
                            self.registers.last().unwrap().borrow_mut().set_state(
                                ExecStates::CallFuncExtractParam,
                                Box::new(main_reg.clone().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final =
                                self.registers.last().unwrap().borrow_mut().get_state()
                                    == ExecStates::CallFuncFinished;
                            continue;
                        }
                    } else if self.registers.last().unwrap().borrow().get_type()
                        == OperationTypes::ReturnVal
                    {
                        if self.registers.last().unwrap().borrow().get_state()
                            == ExecStates::ReturnValStarted
                        {
                            self.registers.last().unwrap().borrow_mut().set_state(
                                ExecStates::ReturnValFinished,
                                Box::new(main_reg.clone().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final =
                                self.registers.last().unwrap().borrow_mut().get_state()
                                    == ExecStates::ReturnValFinished;
                            continue;
                        }
                    } else if self.registers.last().unwrap().borrow().get_type()
                        == OperationTypes::DefineVar
                    {
                        if self.registers.last().unwrap().borrow().get_state()
                            == ExecStates::DefineVarExtractName
                        {
                            self.registers.last().unwrap().borrow_mut().set_state(
                                ExecStates::DefineVarExtractValue,
                                Box::new(main_reg.clone().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final =
                                self.registers.last().unwrap().borrow_mut().get_state()
                                    == ExecStates::DefineVarExtractValue;
                            continue;
                        }
                    } else if self.registers.last().unwrap().borrow().get_type()
                        == OperationTypes::AssignVar
                    {
                        if self.registers.last().unwrap().borrow().get_state()
                            == ExecStates::AssignVarExtractName
                        {
                            if self.registers.last().unwrap().borrow().get_data()[1].as_i16() == 1 {
                                self.registers.last().unwrap().borrow_mut().set_state(
                                    ExecStates::AssignVarExtractValue,
                                    Box::new(main_reg.clone().unwrap()),
                                );
                                main_reg = None;
                                is_reg_state_final =
                                    self.registers.last().unwrap().borrow_mut().get_state()
                                        == ExecStates::AssignVarExtractValue;
                                continue;
                            } else if self.registers.last().unwrap().borrow().get_data()[1].as_i16()
                                == 2
                            {
                                self.registers.last().unwrap().borrow_mut().set_state(
                                    ExecStates::AssignVarExtractIndex,
                                    Box::new(main_reg.clone().unwrap()),
                                );
                                main_reg = None;
                                is_reg_state_final =
                                    self.registers.last().unwrap().borrow_mut().get_state()
                                        == ExecStates::AssignVarExtractValue;
                                continue;
                            }
                        } else if self.registers.last().unwrap().borrow().get_state()
                            == ExecStates::AssignVarExtractIndex
                        {
                            self.registers.last().unwrap().borrow_mut().set_state(
                                ExecStates::AssignVarExtractValue,
                                Box::new(main_reg.clone().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final =
                                self.registers.last().unwrap().borrow_mut().get_state()
                                    == ExecStates::AssignVarExtractValue;
                            continue;
                        }
                    } else if self.registers.last().unwrap().borrow().get_type()
                        == OperationTypes::IfStmt
                    {
                        if self.registers.last().unwrap().borrow().get_state()
                            == ExecStates::IfStmtIsConditioned
                        {
                            self.registers.last().unwrap().borrow_mut().set_state(
                                ExecStates::IfStmtFinished,
                                Box::new(main_reg.clone().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final =
                                self.registers.last().unwrap().borrow_mut().get_state()
                                    == ExecStates::IfStmtFinished;
                            continue;
                        }
                    } else if self.registers.last().unwrap().borrow().get_type()
                        == OperationTypes::LoopStmt
                    {
                        if self.registers.last().unwrap().borrow().get_state()
                            == ExecStates::LoopStmtStarted
                        {
                            self.registers.last().unwrap().borrow_mut().set_state(
                                ExecStates::LoopStmtFinished,
                                Box::new(main_reg.clone().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final =
                                self.registers.last().unwrap().borrow_mut().get_state()
                                    == ExecStates::LoopStmtFinished;
                            continue;
                        }
                    } else if self.registers.last().unwrap().borrow().get_type()
                        == OperationTypes::SwitchStmt
                    {
                        if self.registers.last().unwrap().borrow().get_state()
                            == ExecStates::SwitchStmtStarted
                        {
                            let branch_after_start = self.extract_i64() as usize;
                            let case_count = self.extract_i64() as usize;
                            self.registers.last().unwrap().borrow_mut().set_state(
                                ExecStates::SwitchStmtExtractVal,
                                Box::new((
                                    main_reg.clone().unwrap(),
                                    branch_after_start,
                                    case_count,
                                )),
                            );
                            main_reg = None;
                            is_reg_state_final =
                                self.registers.last().unwrap().borrow_mut().get_state()
                                    == ExecStates::SwitchStmtFinished;
                            continue;
                        } else if self.registers.last().unwrap().borrow().get_state()
                            == ExecStates::SwitchStmtExtractVal
                            || self.registers.last().unwrap().borrow().get_state()
                                == ExecStates::SwitchStmtExtractCase
                        {
                            let branch_true_start = self.extract_i64() as usize;
                            let branch_true_end = self.extract_i64() as usize;
                            self.registers.last().unwrap().borrow_mut().set_state(
                                ExecStates::SwitchStmtExtractCase,
                                Box::new((
                                    main_reg.clone().unwrap(),
                                    branch_true_start,
                                    branch_true_end,
                                )),
                            );
                            main_reg = None;
                            is_reg_state_final =
                                self.registers.last().unwrap().borrow_mut().get_state()
                                    == ExecStates::SwitchStmtFinished;
                            continue;
                        }
                    } else if self.registers.last().unwrap().borrow().get_type()
                        == OperationTypes::Arithmetic
                    {
                        if self.registers.last().unwrap().borrow().get_state()
                            == ExecStates::ArithmeticExtractOp
                        {
                            self.registers.last().unwrap().borrow_mut().set_state(
                                ExecStates::ArithmeticExtractArg1,
                                Box::new(main_reg.clone().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final =
                                self.registers.last().unwrap().borrow_mut().get_state()
                                    == ExecStates::ArithmeticExtractArg2;
                            continue;
                        } else if self.registers.last().unwrap().borrow().get_state()
                            == ExecStates::ArithmeticExtractArg1
                        {
                            self.registers.last().unwrap().borrow_mut().set_state(
                                ExecStates::ArithmeticExtractArg2,
                                Box::new(main_reg.clone().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final =
                                self.registers.last().unwrap().borrow_mut().get_state()
                                    == ExecStates::ArithmeticExtractArg2;
                            continue;
                        }
                    } else if self.registers.last().unwrap().borrow().get_type()
                        == OperationTypes::Indexer
                    {
                        if self.registers.last().unwrap().borrow().get_state()
                            == ExecStates::IndexerStarted
                        {
                            self.registers.last().unwrap().borrow_mut().set_state(
                                ExecStates::IndexerExtractVarName,
                                Box::new(main_reg.clone().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final =
                                self.registers.last().unwrap().borrow_mut().get_state()
                                    == ExecStates::IndexerExtractIndex;
                            continue;
                        } else if self.registers.last().unwrap().borrow().get_state()
                            == ExecStates::IndexerExtractVarName
                        {
                            self.registers.last().unwrap().borrow_mut().set_state(
                                ExecStates::IndexerExtractIndex,
                                Box::new(main_reg.clone().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final =
                                self.registers.last().unwrap().borrow_mut().get_state()
                                    == ExecStates::IndexerExtractIndex;
                            continue;
                        }
                    } else if self.registers.last().unwrap().borrow().get_type()
                        == OperationTypes::NotVal
                    {
                        if self.registers.last().unwrap().borrow().get_state()
                            == ExecStates::NotValStarted
                        {
                            self.registers.last().unwrap().borrow_mut().set_state(
                                ExecStates::NotValFinished,
                                Box::new(main_reg.clone().unwrap()),
                            );
                            main_reg = None;
                            is_reg_state_final =
                                self.registers.last().unwrap().borrow_mut().get_state()
                                    == ExecStates::NotValFinished;
                            continue;
                        }
                    } else if self.registers.last().unwrap().borrow().get_type()
                        == OperationTypes::CondBrch
                    {
                        if self.registers.last().unwrap().borrow().get_state()
                            == ExecStates::CondBranchStarted
                        {
                            let tb = self.extract_i64();
                            let fb = self.extract_i64();
                            self.registers.last().unwrap().borrow_mut().set_state(
                                ExecStates::CondBranchFinished,
                                Box::new((main_reg.clone().unwrap(), tb, fb)),
                            );
                            main_reg = None;
                            is_reg_state_final =
                                self.registers.last().unwrap().borrow_mut().get_state()
                                    == ExecStates::CondBranchFinished;
                            continue;
                        }
                    } else if self.registers.last().unwrap().borrow().get_type()
                        == OperationTypes::CastOprt
                    {
                        if self.registers.last().unwrap().borrow().get_state()
                            == ExecStates::CastOprtStarted
                        {
                            let tt = self.extract_str();
                            self.registers.last().unwrap().borrow_mut().set_state(
                                ExecStates::CastOprtFinished,
                                Box::new((main_reg.clone().unwrap(), tt)),
                            );
                            main_reg = None;
                            is_reg_state_final =
                                self.registers.last().unwrap().borrow_mut().get_state()
                                    == ExecStates::CastOprtFinished;
                            continue;
                        }
                    }
                } else {
                    main_reg = None;
                }
            } else if is_reg_state_final {
                if !self.registers.is_empty() {
                    if self.registers.last().unwrap().borrow().get_state()
                        == ExecStates::ArrExprFinished
                    {
                        let regs = self.registers.last().unwrap().borrow().get_data().clone();
                        let items_vec = regs[1].clone();
                        self.registers.pop();
                        main_reg = Some(items_vec);
                        is_reg_state_final = false;
                        continue;
                    } else if self.registers.last().unwrap().borrow().get_state()
                        == ExecStates::ObjExprFinished
                    {
                        let regs = self.registers.last().unwrap().borrow().get_data().clone();
                        let typ_id = regs[0].as_i64();
                        let props_vec = regs[2].as_array();
                        let mut props_map = HashMap::new();
                        for i in (0..props_vec.borrow().data.len()).step_by(2) {
                            props_map.insert(
                                props_vec.borrow().data[i].as_string(),
                                props_vec.borrow().data[i + 1].clone(),
                            );
                        }
                        let result = Val {
                            typ: 8,
                            data: Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(
                                Object::new(typ_id, ValGroup::new(props_map)),
                            ))))),
                        };
                        self.registers.pop();
                        main_reg = Some(result);
                        is_reg_state_final = false;
                        continue;
                    } else if self.registers.last().unwrap().borrow().get_state()
                        == ExecStates::CallFuncFinished
                    {
                        let regs = self.registers.last().unwrap().borrow().get_data().clone();
                        let is_native = regs[1].as_bool();
                        if !is_native {
                            let func = regs[0].as_func().clone();
                            let expected_params = func.borrow().params.clone();
                            let provided_args = regs[3].as_array().borrow().data.clone();
                            let mut args = HashMap::new();
                            for (i, param_name) in expected_params.iter().enumerate() {
                                let arg = provided_args.get(i).cloned().unwrap_or_else(|| {
                                    Val::new(0, Rc::new(RefCell::new(Box::new(0))))
                                });
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
                            self.registers
                                .push(Rc::new(RefCell::new(Box::new(DummyOp::new()))));
                            is_reg_state_final = false;
                            continue;
                        } else {
                            let mut args = HashMap::new();
                            let arg1 = regs[3].as_array().borrow().data[0].clone();
                            // if !self.allowed_api.contains_key(&arg1.as_string().clone()) {
                            //     panic!("elpian error: this api access is locked");
                            // }
                            args.insert("apiName".to_string(), arg1.clone());
                            let arg2 = regs[3].as_array().borrow().data[1].clone();
                            args.insert("input".to_string(), arg2.clone());
                            self.cb_counter += 1;
                            let cb_id = self.cb_counter;
                            self.registers.pop();
                            self.reserved_host_call = Some((
                                0x02,
                                cb_id,
                                Val {
                                    typ: 9,
                                    data: Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(
                                        Array::new(vec![
                                            args["apiName"].clone(),
                                            Val {
                                                typ: 1,
                                                data: Rc::new(RefCell::new(Box::new(
                                                    self.executor_id,
                                                ))),
                                            },
                                            args["input"].clone(),
                                        ]),
                                    ))))),
                                },
                            ));
                            break;
                        }
                    } else if self.registers.last().unwrap().borrow().get_state()
                        == ExecStates::ReturnValFinished
                    {
                        let data = self.registers.last().unwrap().borrow().get_data();
                        let returned_val = data[0].clone();
                        self.registers.pop();
                        self.pointer = self.end_at;
                        self.pending_func_result_value = returned_val;
                        is_reg_state_final = false;
                        continue;
                    } else if self.registers.last().unwrap().borrow().get_state()
                        == ExecStates::DefineVarExtractValue
                    {
                        let regs = self.registers.last().unwrap().borrow().get_data().clone();
                        let var_name = regs[0].as_string();
                        let var_value = regs[1].clone();
                        self.registers.pop();
                        self.define(var_name.clone(), var_value.clone());
                        is_reg_state_final = false;
                        continue;
                    } else if self.registers.last().unwrap().borrow().get_state()
                        == ExecStates::AssignVarExtractValue
                    {
                        let regs = self.registers.last().unwrap().borrow().get_data().clone();
                        let var_name = regs[0].as_string();
                        let assign_target_type = regs[1].as_i16();
                        let data = regs[3].clone();
                        if assign_target_type == 1 {
                            self.assign(var_name.clone(), data);
                        } else if assign_target_type == 2 {
                            let index = regs[2].clone();
                            self.pointer += 1;
                            let indexed = self.ctx.find_val_globally(var_name);
                            if index.typ == 7 {
                                if indexed.typ == 8 {
                                    let obj = indexed.as_object();
                                    obj.borrow_mut().data.data.insert(index.as_string(), data);
                                } else {
                                    panic!(
                                    "elpian error: non object value can not be indexed by string"
                                );
                                }
                            } else if index.typ >= 1 && index.typ <= 3 {
                                if indexed.typ == 9 {
                                    let arr = indexed.as_array();
                                    if index.typ == 1 {
                                        arr.borrow_mut().data[index.as_i16() as usize] = data;
                                    } else if index.typ == 2 {
                                        arr.borrow_mut().data[index.as_i32() as usize] = data;
                                    } else {
                                        arr.borrow_mut().data[index.as_i64() as usize] = data;
                                    }
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
                    } else if self.registers.last().unwrap().borrow().get_state()
                        == ExecStates::IfStmtFinished
                    {
                        let regs = self.registers.last().unwrap().borrow().get_data().clone();
                        let has_condition = regs[0].as_bool();
                        let cond_val = regs[1].clone();
                        let mut condition = false;
                        if has_condition {
                            if cond_val.typ == 6 {
                                condition = cond_val.as_bool();
                            }
                        }
                        if !has_condition {
                            let branch_true_start = self.extract_i64() as usize;
                            let branch_true_end = self.extract_i64() as usize;
                            let branch_after_start = self.extract_i64() as usize;
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
                            let branch_true_start = self.extract_i64() as usize;
                            let branch_true_end = self.extract_i64() as usize;
                            let branch_next_start = self.extract_i64() as usize;
                            let branch_after_start = self.extract_i64() as usize;
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
                    } else if self.registers.last().unwrap().borrow().get_state()
                        == ExecStates::LoopStmtFinished
                    {
                        let regs = self.registers.last().unwrap().borrow().get_data().clone();
                        let cond_val = regs[0].clone();
                        let mut condition = false;
                        if cond_val.typ == 6 {
                            condition = cond_val.as_bool();
                        }
                        let branch_true_start = self.extract_i64() as usize;
                        let branch_true_end = self.extract_i64() as usize;
                        let branch_after_start = self.extract_i64() as usize;
                        if condition {
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
                    } else if self.registers.last().unwrap().borrow().get_state()
                        == ExecStates::SwitchStmtFinished
                    {
                        let regs = self.registers.last().unwrap().borrow().get_data().clone();
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
                    } else if self.registers.last().unwrap().borrow().get_state()
                        == ExecStates::ArithmeticExtractArg2
                    {
                        let regs = self.registers.last().unwrap().borrow().get_data().clone();
                        let op = regs[0].as_i16();
                        let arg1 = regs[1].clone();
                        let arg2 = regs[2].clone();
                        self.registers.pop();
                        match op {
                            1 => {
                                main_reg = Some(Val {
                                    typ: 6,
                                    data: Rc::new(RefCell::new(Box::new(self.is_eq(arg1, arg2)))),
                                });
                            }
                            2 => {
                                main_reg = Some(Val {
                                    typ: 6,
                                    data: Rc::new(RefCell::new(Box::new(self.is_ge(arg1, arg2)))),
                                });
                            }
                            3 => {
                                main_reg = Some(Val {
                                    typ: 6,
                                    data: Rc::new(RefCell::new(Box::new(self.is_gee(arg1, arg2)))),
                                });
                            }
                            4 => {
                                main_reg = Some(Val {
                                    typ: 6,
                                    data: Rc::new(RefCell::new(Box::new(self.is_le(arg1, arg2)))),
                                });
                            }
                            5 => {
                                main_reg = Some(Val {
                                    typ: 6,
                                    data: Rc::new(RefCell::new(Box::new(self.is_lee(arg1, arg2)))),
                                });
                            }
                            6 => {
                                main_reg = Some(Val {
                                    typ: 6,
                                    data: Rc::new(RefCell::new(Box::new(!self.is_eq(arg1, arg2)))),
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
                            _ => {}
                        }
                        is_reg_state_final = false;
                        continue;
                    } else if self.registers.last().unwrap().borrow().get_state()
                        == ExecStates::IndexerExtractIndex
                    {
                        let regs = self.registers.last().unwrap().borrow().get_data().clone();
                        let indexed = regs[0].clone();
                        let index = regs[1].clone();
                        self.registers.pop();
                        if index.typ == 7 {
                            if indexed.typ == 8 {
                                let obj_ref = indexed.as_object();
                                let obj = obj_ref.borrow();
                                if let Some(o) = obj.data.data.get(&index.as_string()).clone() {
                                    main_reg = Some(o.clone());
                                } else {
                                    main_reg = Some(Val {
                                        typ: 0,
                                        data: Rc::new(RefCell::new(Box::new(0))),
                                    });
                                }
                            } else {
                                println!(
                                    "elpian error: non object value can not be indexed by string"
                                );
                                main_reg = Some(Val {
                                    typ: 0,
                                    data: Rc::new(RefCell::new(Box::new(0))),
                                });
                            }
                        } else if index.typ >= 1 && index.typ <= 3 {
                            if indexed.typ == 9 {
                                let arr = indexed.as_array();
                                if index.typ == 1 {
                                    if let Some(o) =
                                        arr.borrow().data.get(index.as_i16() as usize).clone()
                                    {
                                        main_reg = Some(o.clone());
                                    } else {
                                        main_reg = Some(Val {
                                            typ: 0,
                                            data: Rc::new(RefCell::new(Box::new(0))),
                                        });
                                    }
                                } else if index.typ == 2 {
                                    if let Some(o) =
                                        arr.borrow().data.get(index.as_i32() as usize).clone()
                                    {
                                        main_reg = Some(o.clone());
                                    } else {
                                        main_reg = Some(Val {
                                            typ: 0,
                                            data: Rc::new(RefCell::new(Box::new(0))),
                                        });
                                    }
                                } else {
                                    if let Some(o) =
                                        arr.borrow().data.get(index.as_i64() as usize).clone()
                                    {
                                        main_reg = Some(o.clone());
                                    } else {
                                        main_reg = Some(Val {
                                            typ: 0,
                                            data: Rc::new(RefCell::new(Box::new(0))),
                                        });
                                    }
                                }
                            } else {
                                println!(
                                    "elpian error: non object value can not be indexed by string"
                                );
                                main_reg = Some(Val {
                                    typ: 0,
                                    data: Rc::new(RefCell::new(Box::new(0))),
                                });
                            }
                        } else {
                            println!(
                            "elpian error: types other than integer and string can not be used to index anything"
                        );
                            main_reg = Some(Val {
                                typ: 0,
                                data: Rc::new(RefCell::new(Box::new(0))),
                            });
                        }
                        is_reg_state_final = false;
                        continue;
                    } else if self.registers.last().unwrap().borrow().get_state()
                        == ExecStates::NotValFinished
                    {
                        let data = self.registers.last().unwrap().borrow().get_data();
                        let val = data[0].clone();
                        self.registers.pop();
                        if val.typ == 6 {
                            main_reg = Some(Val {
                                typ: 6,
                                data: Rc::new(RefCell::new(Box::new(!val.as_bool()))),
                            });
                        } else {
                            panic!(
                            "elpian error: not operator (!) can not be applied to non-bool value"
                        );
                        }
                        is_reg_state_final = false;
                        continue;
                    } else if self.registers.last().unwrap().borrow().get_state()
                        == ExecStates::CondBranchFinished
                    {
                        let regs = self.registers.last().unwrap().borrow().get_data().clone();
                        let condition = regs[0].as_bool();
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
                    } else if self.registers.last().unwrap().borrow().get_state()
                        == ExecStates::CastOprtFinished
                    {
                        let regs = self.registers.last().unwrap().borrow().get_data().clone();
                        let data = regs[0].clone();
                        let target_type = regs[1].as_string();
                        if target_type == "i16" {
                            match data.typ {
                                1 => {
                                    main_reg = Some(Val {
                                        typ: 1,
                                        data: Rc::new(RefCell::new(Box::new(data.as_i16() as i16))),
                                    });
                                }
                                2 => {
                                    main_reg = Some(Val {
                                        typ: 1,
                                        data: Rc::new(RefCell::new(Box::new(data.as_i32() as i16))),
                                    });
                                }
                                3 => {
                                    main_reg = Some(Val {
                                        typ: 1,
                                        data: Rc::new(RefCell::new(Box::new(data.as_i64() as i16))),
                                    });
                                }
                                4 => {
                                    main_reg = Some(Val {
                                        typ: 1,
                                        data: Rc::new(RefCell::new(Box::new(data.as_f32() as i16))),
                                    });
                                }
                                5 => {
                                    main_reg = Some(Val {
                                        typ: 1,
                                        data: Rc::new(RefCell::new(Box::new(data.as_f64() as i16))),
                                    });
                                }
                                6 => {
                                    main_reg =
                                        Some(Val {
                                            typ: 1,
                                            data: Rc::new(RefCell::new(Box::new(
                                                if data.as_bool() { 1 } else { 0 } as i16,
                                            ))),
                                        });
                                }
                                7 => {
                                    main_reg = Some(Val {
                                        typ: 1,
                                        data: Rc::new(RefCell::new(Box::new(
                                            data.as_string().parse::<i16>().unwrap(),
                                        ))),
                                    });
                                }
                                _ => {
                                    main_reg = Some(Val {
                                        typ: 0,
                                        data: Rc::new(RefCell::new(Box::new(0))),
                                    });
                                }
                            }
                        } else if target_type == "i32" {
                            match data.typ {
                                1 => {
                                    main_reg = Some(Val {
                                        typ: 2,
                                        data: Rc::new(RefCell::new(Box::new(data.as_i16() as i32))),
                                    });
                                }
                                2 => {
                                    main_reg = Some(Val {
                                        typ: 2,
                                        data: Rc::new(RefCell::new(Box::new(data.as_i32() as i32))),
                                    });
                                }
                                3 => {
                                    main_reg = Some(Val {
                                        typ: 2,
                                        data: Rc::new(RefCell::new(Box::new(data.as_i64() as i32))),
                                    });
                                }
                                4 => {
                                    main_reg = Some(Val {
                                        typ: 2,
                                        data: Rc::new(RefCell::new(Box::new(data.as_f32() as i32))),
                                    });
                                }
                                5 => {
                                    main_reg = Some(Val {
                                        typ: 2,
                                        data: Rc::new(RefCell::new(Box::new(data.as_f64() as i32))),
                                    });
                                }
                                6 => {
                                    main_reg =
                                        Some(Val {
                                            typ: 2,
                                            data: Rc::new(RefCell::new(Box::new(
                                                if data.as_bool() { 1 } else { 0 } as i32,
                                            ))),
                                        });
                                }
                                7 => {
                                    main_reg = Some(Val {
                                        typ: 2,
                                        data: Rc::new(RefCell::new(Box::new(
                                            data.as_string().parse::<i32>().unwrap(),
                                        ))),
                                    });
                                }
                                _ => {
                                    main_reg = Some(Val {
                                        typ: 0,
                                        data: Rc::new(RefCell::new(Box::new(0))),
                                    });
                                }
                            }
                        } else if target_type == "i64" {
                            match data.typ {
                                1 => {
                                    main_reg = Some(Val {
                                        typ: 3,
                                        data: Rc::new(RefCell::new(Box::new(data.as_i16() as i64))),
                                    });
                                }
                                2 => {
                                    main_reg = Some(Val {
                                        typ: 3,
                                        data: Rc::new(RefCell::new(Box::new(data.as_i32() as i64))),
                                    });
                                }
                                3 => {
                                    main_reg = Some(Val {
                                        typ: 3,
                                        data: Rc::new(RefCell::new(Box::new(data.as_i64() as i64))),
                                    });
                                }
                                4 => {
                                    main_reg = Some(Val {
                                        typ: 3,
                                        data: Rc::new(RefCell::new(Box::new(data.as_f32() as i64))),
                                    });
                                }
                                5 => {
                                    main_reg = Some(Val {
                                        typ: 3,
                                        data: Rc::new(RefCell::new(Box::new(data.as_f64() as i64))),
                                    });
                                }
                                6 => {
                                    main_reg =
                                        Some(Val {
                                            typ: 3,
                                            data: Rc::new(RefCell::new(Box::new(
                                                if data.as_bool() { 1 } else { 0 } as i64,
                                            ))),
                                        });
                                }
                                7 => {
                                    main_reg = Some(Val {
                                        typ: 3,
                                        data: Rc::new(RefCell::new(Box::new(
                                            data.as_string().parse::<i64>().unwrap(),
                                        ))),
                                    });
                                }
                                _ => {
                                    main_reg = Some(Val {
                                        typ: 0,
                                        data: Rc::new(RefCell::new(Box::new(0))),
                                    });
                                }
                            }
                        } else if target_type == "f32" {
                            match data.typ {
                                1 => {
                                    main_reg = Some(Val {
                                        typ: 4,
                                        data: Rc::new(RefCell::new(Box::new(data.as_i16() as f32))),
                                    });
                                }
                                2 => {
                                    main_reg = Some(Val {
                                        typ: 4,
                                        data: Rc::new(RefCell::new(Box::new(data.as_i32() as f32))),
                                    });
                                }
                                3 => {
                                    main_reg = Some(Val {
                                        typ: 4,
                                        data: Rc::new(RefCell::new(Box::new(data.as_i64() as f32))),
                                    });
                                }
                                4 => {
                                    main_reg = Some(Val {
                                        typ: 4,
                                        data: Rc::new(RefCell::new(Box::new(data.as_f32() as f32))),
                                    });
                                }
                                5 => {
                                    main_reg = Some(Val {
                                        typ: 4,
                                        data: Rc::new(RefCell::new(Box::new(data.as_f64() as f32))),
                                    });
                                }
                                6 => {
                                    main_reg =
                                        Some(Val {
                                            typ: 4,
                                            data: Rc::new(RefCell::new(Box::new(
                                                if data.as_bool() { 1 } else { 0 } as f32,
                                            ))),
                                        });
                                }
                                7 => {
                                    main_reg = Some(Val {
                                        typ: 4,
                                        data: Rc::new(RefCell::new(Box::new(
                                            data.as_string().parse::<f32>().unwrap(),
                                        ))),
                                    });
                                }
                                _ => {
                                    main_reg = Some(Val {
                                        typ: 0,
                                        data: Rc::new(RefCell::new(Box::new(0))),
                                    });
                                }
                            }
                        } else if target_type == "f64" {
                            match data.typ {
                                1 => {
                                    main_reg = Some(Val {
                                        typ: 5,
                                        data: Rc::new(RefCell::new(Box::new(data.as_i16() as f64))),
                                    });
                                }
                                2 => {
                                    main_reg = Some(Val {
                                        typ: 5,
                                        data: Rc::new(RefCell::new(Box::new(data.as_i32() as f64))),
                                    });
                                }
                                3 => {
                                    main_reg = Some(Val {
                                        typ: 5,
                                        data: Rc::new(RefCell::new(Box::new(data.as_i64() as f64))),
                                    });
                                }
                                4 => {
                                    main_reg = Some(Val {
                                        typ: 5,
                                        data: Rc::new(RefCell::new(Box::new(data.as_f32() as f64))),
                                    });
                                }
                                5 => {
                                    main_reg = Some(Val {
                                        typ: 5,
                                        data: Rc::new(RefCell::new(Box::new(data.as_f64() as f64))),
                                    });
                                }
                                6 => {
                                    main_reg =
                                        Some(Val {
                                            typ: 5,
                                            data: Rc::new(RefCell::new(Box::new(
                                                if data.as_bool() { 1 } else { 0 } as f64,
                                            ))),
                                        });
                                }
                                7 => {
                                    main_reg = Some(Val {
                                        typ: 5,
                                        data: Rc::new(RefCell::new(Box::new(
                                            data.as_string().parse::<f64>().unwrap(),
                                        ))),
                                    });
                                }
                                _ => {
                                    main_reg = Some(Val {
                                        typ: 0,
                                        data: Rc::new(RefCell::new(Box::new(0))),
                                    });
                                }
                            }
                        } else if target_type == "bool" {
                            match data.typ {
                                1 => {
                                    main_reg = Some(Val {
                                        typ: 6,
                                        data: Rc::new(RefCell::new(Box::new(data.as_i16() > 0))),
                                    });
                                }
                                2 => {
                                    main_reg = Some(Val {
                                        typ: 6,
                                        data: Rc::new(RefCell::new(Box::new(data.as_i32() > 0))),
                                    });
                                }
                                3 => {
                                    main_reg = Some(Val {
                                        typ: 6,
                                        data: Rc::new(RefCell::new(Box::new(data.as_i64() > 0))),
                                    });
                                }
                                4 => {
                                    main_reg = Some(Val {
                                        typ: 6,
                                        data: Rc::new(RefCell::new(Box::new(data.as_f32() > 0.0))),
                                    });
                                }
                                5 => {
                                    main_reg = Some(Val {
                                        typ: 6,
                                        data: Rc::new(RefCell::new(Box::new(data.as_f64() > 0.0))),
                                    });
                                }
                                6 => {
                                    main_reg = Some(Val {
                                        typ: 6,
                                        data: Rc::new(RefCell::new(Box::new(data.as_bool()))),
                                    });
                                }
                                7 => {
                                    main_reg = Some(Val {
                                        typ: 6,
                                        data: Rc::new(RefCell::new(Box::new(
                                            data.as_string() == "true",
                                        ))),
                                    });
                                }
                                _ => {
                                    main_reg = Some(Val {
                                        typ: 0,
                                        data: Rc::new(RefCell::new(Box::new(0))),
                                    });
                                }
                            }
                        } else if target_type == "string" {
                            match data.typ {
                                1 => {
                                    main_reg = Some(Val {
                                        typ: 7,
                                        data: Rc::new(RefCell::new(Box::new(
                                            data.as_i16().to_string(),
                                        ))),
                                    });
                                }
                                2 => {
                                    main_reg = Some(Val {
                                        typ: 7,
                                        data: Rc::new(RefCell::new(Box::new(
                                            data.as_i32().to_string(),
                                        ))),
                                    });
                                }
                                3 => {
                                    main_reg = Some(Val {
                                        typ: 7,
                                        data: Rc::new(RefCell::new(Box::new(
                                            data.as_i64().to_string(),
                                        ))),
                                    });
                                }
                                4 => {
                                    main_reg = Some(Val {
                                        typ: 7,
                                        data: Rc::new(RefCell::new(Box::new(
                                            data.as_f32().to_string(),
                                        ))),
                                    });
                                }
                                5 => {
                                    main_reg = Some(Val {
                                        typ: 7,
                                        data: Rc::new(RefCell::new(Box::new(
                                            data.as_f64().to_string(),
                                        ))),
                                    });
                                }
                                6 => {
                                    main_reg = Some(Val {
                                        typ: 7,
                                        data: Rc::new(RefCell::new(Box::new(
                                            data.as_bool().to_string(),
                                        ))),
                                    });
                                }
                                7 => {
                                    main_reg = Some(Val {
                                        typ: 7,
                                        data: Rc::new(RefCell::new(Box::new(data.as_string()))),
                                    });
                                }
                                8 => {
                                    main_reg = Some(Val {
                                        typ: 7,
                                        data: Rc::new(RefCell::new(Box::new(data.stringify()))),
                                    });
                                }
                                9 => {
                                    main_reg = Some(Val {
                                        typ: 7,
                                        data: Rc::new(RefCell::new(Box::new(data.stringify()))),
                                    });
                                }
                                _ => {
                                    main_reg = Some(Val {
                                        typ: 0,
                                        data: Rc::new(RefCell::new(Box::new(0))),
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
                    self.ctx.pop_scope();
                    if is_partial_exec && (self.ctx.memory.len() == 1) {
                        return self.pending_func_result_value.clone();
                    }
                    if !self.registers.is_empty()
                        && self.registers.last().unwrap().borrow().get_type()
                            == OperationTypes::Dummy
                    {
                        self.registers.pop();
                    }
                    if !self.ctx.memory.is_empty() {
                        self.pointer = self.ctx.memory.last().unwrap().borrow().frozen_pointer;
                        self.end_at = self.ctx.memory.last().unwrap().borrow().frozen_end;
                        if self.pending_func_result_value.typ != 254 {
                            let returned_val = self.pending_func_result_value.clone();
                            self.pending_func_result_value = Val {
                                typ: 254,
                                data: Rc::new(RefCell::new(Box::new(0))),
                            };
                            while self.ctx.memory.last().unwrap().borrow().tag != "funcBody" {
                                self.ctx.pop_scope();
                            }
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
            let unit: u8 = self.program[self.pointer];
            self.pointer += 1;
            match unit {
                // ----------------------------------
                // arithmetic operators:
                // equality operator
                0xf0 => {
                    let state_holder = Arithmetic::new();
                    self.registers
                        .push(Rc::new(RefCell::new(Box::new(state_holder))));
                    self.registers
                        .last()
                        .unwrap()
                        .borrow_mut()
                        .set_state(ExecStates::ArithmeticExtractOp, Box::new(1 as i16));
                }
                // ge operator
                0xf1 => {
                    let state_holder = Arithmetic::new();
                    self.registers
                        .push(Rc::new(RefCell::new(Box::new(state_holder))));
                    self.registers
                        .last()
                        .unwrap()
                        .borrow_mut()
                        .set_state(ExecStates::ArithmeticExtractOp, Box::new(2 as i16));
                }
                // gee operator
                0xf2 => {
                    let state_holder = Arithmetic::new();
                    self.registers
                        .push(Rc::new(RefCell::new(Box::new(state_holder))));
                    self.registers
                        .last()
                        .unwrap()
                        .borrow_mut()
                        .set_state(ExecStates::ArithmeticExtractOp, Box::new(3 as i16));
                }
                // le operator
                0xf3 => {
                    let state_holder = Arithmetic::new();
                    self.registers
                        .push(Rc::new(RefCell::new(Box::new(state_holder))));
                    self.registers
                        .last()
                        .unwrap()
                        .borrow_mut()
                        .set_state(ExecStates::ArithmeticExtractOp, Box::new(4 as i16));
                }
                // lee operator
                0xf4 => {
                    let state_holder = Arithmetic::new();
                    self.registers
                        .push(Rc::new(RefCell::new(Box::new(state_holder))));
                    self.registers
                        .last()
                        .unwrap()
                        .borrow_mut()
                        .set_state(ExecStates::ArithmeticExtractOp, Box::new(5 as i16));
                }
                // inequality operator
                0xf5 => {
                    let state_holder = Arithmetic::new();
                    self.registers
                        .push(Rc::new(RefCell::new(Box::new(state_holder))));
                    self.registers
                        .last()
                        .unwrap()
                        .borrow_mut()
                        .set_state(ExecStates::ArithmeticExtractOp, Box::new(6 as i16));
                }
                // sum operator
                0xf6 => {
                    let state_holder = Arithmetic::new();
                    self.registers
                        .push(Rc::new(RefCell::new(Box::new(state_holder))));
                    self.registers
                        .last()
                        .unwrap()
                        .borrow_mut()
                        .set_state(ExecStates::ArithmeticExtractOp, Box::new(7 as i16));
                }
                // subtract operator
                0xf7 => {
                    let state_holder = Arithmetic::new();
                    self.registers
                        .push(Rc::new(RefCell::new(Box::new(state_holder))));
                    self.registers
                        .last()
                        .unwrap()
                        .borrow_mut()
                        .set_state(ExecStates::ArithmeticExtractOp, Box::new(8 as i16));
                }
                // multiply operator
                0xf8 => {
                    let state_holder = Arithmetic::new();
                    self.registers
                        .push(Rc::new(RefCell::new(Box::new(state_holder))));
                    self.registers
                        .last()
                        .unwrap()
                        .borrow_mut()
                        .set_state(ExecStates::ArithmeticExtractOp, Box::new(9 as i16));
                }
                // division operator
                0xf9 => {
                    let state_holder = Arithmetic::new();
                    self.registers
                        .push(Rc::new(RefCell::new(Box::new(state_holder))));
                    self.registers
                        .last()
                        .unwrap()
                        .borrow_mut()
                        .set_state(ExecStates::ArithmeticExtractOp, Box::new(10 as i16));
                }
                // mod operator
                0xfa => {
                    let state_holder = Arithmetic::new();
                    self.registers
                        .push(Rc::new(RefCell::new(Box::new(state_holder))));
                    self.registers
                        .last()
                        .unwrap()
                        .borrow_mut()
                        .set_state(ExecStates::ArithmeticExtractOp, Box::new(11 as i16));
                }
                // power operator
                0xfb => {
                    let state_holder = Arithmetic::new();
                    self.registers
                        .push(Rc::new(RefCell::new(Box::new(state_holder))));
                    self.registers
                        .last()
                        .unwrap()
                        .borrow_mut()
                        .set_state(ExecStates::ArithmeticExtractOp, Box::new(12 as i16));
                }
                // not operator
                0xfc => {
                    let state_holder = NotValue::new();
                    self.registers
                        .push(Rc::new(RefCell::new(Box::new(state_holder))));
                }
                // cast operation
                0xfd => {
                    let state_holder = CastOp::new();
                    self.registers
                        .push(Rc::new(RefCell::new(Box::new(state_holder))));
                }
                // ----------------------------------
                // program operators:
                // data indexer
                0x0c => {
                    let state_holder = IndexerValue::new();
                    self.registers
                        .push(Rc::new(RefCell::new(Box::new(state_holder))));
                }
                // function call
                0x0d => {
                    let state_holder = CallFunction::new();
                    self.registers
                        .push(Rc::new(RefCell::new(Box::new(state_holder))));
                }
                // definition statement
                0x0e => {
                    if self.program[self.pointer] == 0x0b {
                        self.pointer += 1;
                        let state_holder = DefineVariable::new();
                        self.registers
                            .push(Rc::new(RefCell::new(Box::new(state_holder))));
                        let var_name = self.extract_str();
                        self.registers
                            .last()
                            .unwrap()
                            .borrow_mut()
                            .set_state(ExecStates::DefineVarExtractName, Box::new(var_name));
                    }
                }
                // assignment statement
                0x0f => {
                    if self.program[self.pointer] == 0x0c {
                        self.pointer += 1;
                        let state_holder = AssignVariable::new();
                        self.registers
                            .push(Rc::new(RefCell::new(Box::new(state_holder))));
                        let var_name = self.extract_str();
                        self.registers.last().unwrap().borrow_mut().set_state(
                            ExecStates::AssignVarExtractName,
                            Box::new((var_name, 2 as i16)),
                        );
                    } else if self.program[self.pointer] == 0x0b {
                        self.pointer += 1;
                        let state_holder = AssignVariable::new();
                        self.registers
                            .push(Rc::new(RefCell::new(Box::new(state_holder))));
                        let var_name = self.extract_str();
                        self.registers.last().unwrap().borrow_mut().set_state(
                            ExecStates::AssignVarExtractName,
                            Box::new((var_name, 1 as i16)),
                        );
                    }
                }
                // if statement
                0x10 => {
                    let state_holder = IfStmt::new();
                    self.registers
                        .push(Rc::new(RefCell::new(Box::new(state_holder))));
                    let has_condition = self.program[self.pointer] == 0x01;
                    self.pointer += 1;
                    if has_condition {
                        self.registers
                            .last()
                            .unwrap()
                            .borrow_mut()
                            .set_state(ExecStates::IfStmtIsConditioned, Box::new(has_condition));
                    } else {
                        self.registers
                            .last()
                            .unwrap()
                            .borrow_mut()
                            .set_state(ExecStates::IfStmtIsConditioned, Box::new(has_condition));
                        self.registers.last().unwrap().borrow_mut().set_state(
                            ExecStates::IfStmtFinished,
                            Box::new(Val {
                                typ: 6,
                                data: Rc::new(RefCell::new(Box::new(true))),
                            }),
                        );
                        main_reg = None;
                        is_reg_state_final = true;
                        continue;
                    }
                }
                // loop statement
                0x11 => {
                    let state_holder = LoopStmt::new();
                    self.registers
                        .push(Rc::new(RefCell::new(Box::new(state_holder))));
                }
                // switch case statement
                0x12 => {
                    let state_holder = SwitchStmt::new();
                    self.registers
                        .push(Rc::new(RefCell::new(Box::new(state_holder))));
                }
                // function definiton
                0x13 => {
                    let func_name = self.extract_str();
                    let param_count = self.extract_i32();
                    let mut param_names = vec![];
                    for _i in 0..param_count {
                        let p_name = self.extract_str();
                        param_names.push(p_name);
                    }
                    let func_start = self.extract_i64() as usize;
                    let func_end = self.extract_i64() as usize;
                    let func = Function::new(func_name.clone(), func_start, func_end, param_names);
                    self.define(
                        func_name.clone(),
                        Val {
                            typ: 10,
                            data: Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(
                                func.clone(),
                            ))))),
                        },
                    );
                    self.pointer = func_end;
                }
                // return command
                0x14 => {
                    let state_holder = ReturnValue::new();
                    self.registers
                        .push(Rc::new(RefCell::new(Box::new(state_holder))));
                }
                // jump command
                0x15 => {
                    let dest = self.extract_i64() as usize;
                    self.pointer = dest;
                }
                // conditional branch
                0x16 => {
                    let state_holder = CondBranch::new();
                    self.registers
                        .push(Rc::new(RefCell::new(Box::new(state_holder))));
                }
                // ----------------------------------
                // expressions
                // data expressions
                1 | 2 | 3 | 4 | 5 | 6 | 7 | 10 | 11 => {
                    println!("{}", unit);
                    self.pointer -= 1;
                    let val = self.extract_val();
                    main_reg = Some(val);
                    continue;
                }
                // object expressions
                8 => {
                    println!("{}", unit);
                    let typ = self.extract_i64();
                    let props_len = self.extract_i32();
                    self.registers
                        .push(Rc::new(RefCell::new(Box::new(ObjectExpr::new()))));
                    self.registers
                        .last()
                        .unwrap()
                        .borrow_mut()
                        .set_state(ExecStates::ObjExprExtractInfo, Box::new((typ, props_len)));
                    if self.registers.last().unwrap().borrow().get_state()
                        == ExecStates::ObjExprFinished
                    {
                        main_reg = None;
                        is_reg_state_final = true;
                        continue;
                    }
                }
                // array expressions
                9 => {
                    let arr_len = self.extract_i32();
                    self.registers
                        .push(Rc::new(RefCell::new(Box::new(ArrayExpr::new()))));
                    self.registers
                        .last()
                        .unwrap()
                        .borrow_mut()
                        .set_state(ExecStates::ArrExprExtractInfo, Box::new(arr_len));
                    if self.registers.last().unwrap().borrow().get_state()
                        == ExecStates::ArrExprFinished
                    {
                        main_reg = None;
                        is_reg_state_final = true;
                        continue;
                    }
                }
                // ----------------------------------
                // No-Op
                _ => {}
            }
        }
        Val::new(0, Rc::new(RefCell::new(Box::new(0))))
    }
}
