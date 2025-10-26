use crate::sdk::{
    context::Context,
    data::{Array, Function, Object, Val, ValGroup},
};
use core::panic;
use std::{
    any::Any,
    cell::RefCell,
    collections::HashMap,
    i16,
    rc::Rc,
    sync::mpsc::{self, Sender},
    thread,
};

#[derive(Clone, PartialEq)]
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
}

#[derive(Clone, PartialEq)]
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
}

pub trait Operation {
    fn get_type(&self) -> OperationTypes;
    fn get_state(&self) -> ExecStates;
    fn set_state(&mut self, state: ExecStates, data: Box<dyn Any>);
    fn get_data(&self) -> Vec<Val>;
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
            assign_target_type: 0x00,
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
            if assign_target_type == 1 {
                if state != ExecStates::AssignVarExtractValue {
                    panic!("elpian error: wrong state set to assignment operation");
                }
            } else if assign_target_type == 2 {
                if state != ExecStates::AssignVarExtractIndex {
                    panic!("elpian error: wrong state set to assignment operation");
                }
            }
        } else if state == ExecStates::AssignVarExtractIndex {
            if self.assign_target_type == 0x0c {
                self.index = Some(*data.downcast::<Val>().unwrap());
            } else {
                panic!("elpian error: wrong state set to assignment operation");
            }
        } else if state == ExecStates::AssignVarExtractValue {
            self.var_value = Some(*data.downcast::<Val>().unwrap());
        }
    }

    fn get_data(&self) -> Vec<Val> {
        vec![
            Val {
                typ: 7,
                data: Rc::new(RefCell::new(Box::new(self.var_name.clone()))),
            },
            Val {
                typ: 6,
                data: Rc::new(RefCell::new(Box::new(self.assign_target_type))),
            },
            self.index.clone().unwrap(),
            self.var_value.clone().unwrap(),
        ]
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
                data: Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(Array::new(self.params.clone())))))),
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
    pub compairng_value: Option<Val>,
    pub branch_after_start: usize,
    pub case_count: usize,
    pub cases: Vec<(Val, usize, usize)>,
}

impl SwitchStmt {
    pub fn new() -> Self {
        SwitchStmt {
            typ: OperationTypes::LoopStmt,
            state: ExecStates::LoopStmtStarted,
            compairng_value: None,
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
            self.compairng_value = Some(comparing_val.clone());
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
        let case_info_packaged: Box<Vec<Val>> = Box::new(
            self.cases
                .iter()
                .map(|item| {
                    let mut case_info = HashMap::new();
                    case_info.insert("val".to_string(), item.0.clone());
                    case_info.insert("start".to_string(), item.0.clone());
                    case_info.insert("end".to_string(), item.0.clone());
                    return Val {
                        typ: 8,
                        data: Rc::new(RefCell::new(Box::new(Object::new(
                            -1,
                            ValGroup::new(case_info),
                        )))),
                    };
                })
                .collect(),
        );
        vec![
            self.compairng_value.clone().unwrap(),
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
                data: Rc::new(RefCell::new(case_info_packaged)),
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

pub struct Executor {
    pointer: usize,
    end_at: usize,
    ctx: Context,
    program: Vec<u8>,
    vm_send: Sender<(u8, i64, Val)>,
    callbacks: HashMap<i64, Sender<Val>>,
    cb_counter: i64,
    pending_func_result_position: usize,
    after_return_next_jump: usize,
    pending_func_result_value: Val,
    registers: Vec<Rc<RefCell<Box<dyn Operation>>>>,
}

impl Executor {
    pub fn create(
        program: Vec<u8>,
        vm_send: Sender<(u8, i64, Val)>,
        func_group: Vec<String>,
    ) -> Sender<(u8, i64, String)> {
        let (tasks_send, tasks_recv) = mpsc::channel::<(u8, i64, String)>();
        thread::spawn(move || {
            let mut program_payload: Vec<u8> = vec![];
            for func_name in func_group.iter() {
                program_payload.push(0x13);
                program_payload.append(&mut i32::to_be_bytes(func_name.len() as i32).to_vec());
                program_payload.append(&mut func_name.as_bytes().to_vec());
                program_payload.append(&mut i32::to_be_bytes(1).to_vec());
                let param_name = "input".to_string();
                program_payload.append(&mut i32::to_be_bytes(param_name.len() as i32).to_vec());
                program_payload.append(&mut param_name.as_bytes().to_vec());
                let mut func_body = vec![];
                func_body.push(0x0d);
                func_body.push(0x0b);
                let ask_host_call_name = "askHost".to_string();
                func_body.append(&mut i32::to_be_bytes(ask_host_call_name.len() as i32).to_vec());
                func_body.append(&mut ask_host_call_name.as_bytes().to_vec());
                func_body.append(&mut i32::to_be_bytes(2).to_vec());
                func_body.push(7);
                func_body.append(&mut i32::to_be_bytes(func_name.len() as i32).to_vec());
                func_body.append(&mut func_name.as_bytes().to_vec());
                func_body.push(0x0b);
                let arg_name = "input".to_string();
                func_body.append(&mut i32::to_be_bytes(arg_name.len() as i32).to_vec());
                func_body.append(&mut arg_name.as_bytes().to_vec());
                let func_start = program_payload.len() + 8 + 8;
                let func_end = func_start + func_body.len();
                program_payload.append(&mut i64::to_be_bytes(func_start as i64).to_vec());
                program_payload.append(&mut i64::to_be_bytes(func_end as i64).to_vec());
                program_payload.append(&mut func_body);
            }
            program_payload.append(&mut program.clone());
            let mut ex = Executor {
                pointer: 0,
                end_at: program_payload.len(),
                ctx: Context::new(),
                program: program_payload,
                vm_send: vm_send.clone(),
                cb_counter: 0,
                callbacks: HashMap::new(),
                pending_func_result_position: 0,
                after_return_next_jump: 0,
                pending_func_result_value: Val::new(254, Rc::new(RefCell::new(Box::new(0)))),
                registers: vec![],
            };
            loop {
                let (op_code, cb_id, payload) = tasks_recv.recv().unwrap();
                match op_code {
                    0x00 => {
                        println!("ending executor...");
                        break;
                    }
                    0x01 => {
                        println!("executor: run_func called");
                        if payload.is_empty() {
                            let result = ex.run_from(0, ex.program.len());
                            vm_send.clone().send((0x01, cb_id, result)).unwrap();
                        } else {
                            let val = ex.ctx.find_val_in_first_scope(payload);
                            if !val.is_empty() {
                                let func = val.as_func();
                                let result = ex.run_from(func.borrow().start, func.borrow().end);
                                vm_send.clone().send((0x01, cb_id, result)).unwrap();
                            }
                        }
                    }
                    0x02 => {
                        println!("executor: print_memory called");
                        ex.ctx.memory.iter().for_each(|scope| {
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
                    }
                    _ => {}
                }
            }
        });
        tasks_send.clone()
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
    fn extract_obj(&mut self) -> Object {
        let mut data: HashMap<String, Val> = HashMap::new();
        let typ = self.extract_i64();
        let props_len = self.extract_i32();
        for _ in 0..props_len {
            let prop_key = self.extract_str();
            let prop_val = self.extract_val();
            data.insert(prop_key, prop_val);
        }
        Object::new(typ, ValGroup::new(data))
    }
    fn extract_arr(&mut self) -> Array {
        let mut data: Vec<Val> = vec![];
        let arr_len = self.extract_i32();
        for _ in 0..arr_len {
            data.push(self.extract_val());
        }
        Array::new(data)
    }
    fn extract_func(&mut self) -> Function {
        let start = self.extract_i64() as usize;
        let end = self.extract_i64() as usize;
        let param_count = self.extract_i32();
        let mut params = vec![];
        for _i in 0..param_count {
            params.push(self.extract_str());
        }
        Function::new(start, end, params)
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
            0x08 => Val {
                typ: 8,
                data: Rc::new(RefCell::new(Box::new(self.extract_obj()))),
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
                typ: 1,
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
                        let val2 = arg2.as_array();
                        val2.borrow_mut().data.insert(0, arg1);
                        Val {
                            typ: 9,
                            data: Rc::new(RefCell::new(Box::new(val2))),
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
                        let val2 = arg2.as_array();
                        val2.borrow_mut().data.insert(0, arg1);
                        Val {
                            typ: 9,
                            data: Rc::new(RefCell::new(Box::new(val2))),
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
                        let val2 = arg2.as_array();
                        val2.borrow_mut().data.insert(0, arg1);
                        Val {
                            typ: 9,
                            data: Rc::new(RefCell::new(Box::new(val2))),
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
                        let val2 = arg2.as_array();
                        val2.borrow_mut().data.insert(0, arg1);
                        Val {
                            typ: 9,
                            data: Rc::new(RefCell::new(Box::new(val2))),
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
                        let val2 = arg2.as_array();
                        val1.borrow_mut().data.append(&mut val2.borrow_mut().data);
                        Val {
                            typ: 9,
                            data: Rc::new(RefCell::new(Box::new(val1))),
                        }
                    }
                    _ => {
                        panic!("elpian error: unknown data type and array can not be summed");
                    }
                }
            }
            10 => {
                panic!("function can not be summed with anything");
            }
            _ => {
                panic!("can not sum unknown type with anything");
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
                                if self.is_equal(v.clone(), v2.clone()) {
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
                                if self.is_equal(item.clone(), arg2.clone()) {
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
                                    if self.is_equal(item.clone(), item2.clone()) {
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
    fn is_equal(&self, v: Val, v2: Val) -> bool {
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
                            1 => v.as_i16() as i64,
                            2 => v.as_i32() as i64,
                            3 => v.as_i64() as i64,
                            _ => 0,
                        };
                        v_val == v2_val
                    }
                    4 | 5 => {
                        let v_val_temp = v_val as f64;
                        let v2_val = match v2.typ {
                            4 => v.as_f32() as f64,
                            5 => v.as_f64() as f64,
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
                            1 => v.as_i16() as f64,
                            2 => v.as_i32() as f64,
                            3 => v.as_i64() as f64,
                            _ => 0.0,
                        };
                        v_val == v2_val
                    }
                    4 | 5 => {
                        let v2_val = match v2.typ {
                            4 => v.as_f32() as f64,
                            5 => v.as_f64() as f64,
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
                    6 => {
                        let v2_val = v2.as_string();
                        v_val == v2_val
                    }
                    _ => false,
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
                            return v_val.borrow().data.data.iter().all(|(k, d)| {
                                self.is_equal(
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
                            if self.is_equal(
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
    fn define(&mut self, id_name: String, val: Val) {
        self.ctx.define_val_globally(id_name, val);
    }
    fn assign(&mut self, id_name: String, val: Val) {
        self.ctx.update_val_globally(id_name, val);
    }
    fn forward_state(&mut self, val: Option<Val>) {
        if self.registers.last().unwrap().borrow().get_type() == OperationTypes::CallFunc {
            if self.registers.last().unwrap().borrow().get_state() == ExecStates::CallFuncStarted {
                let arg_count = self.extract_i32() as usize;
                self.registers.last().unwrap().borrow_mut().set_state(
                    ExecStates::CallFuncExtractFunc,
                    Box::new((val.clone().unwrap(), arg_count)),
                );
                if self.registers.last().unwrap().borrow().get_state()
                    == ExecStates::CallFuncFinished
                {
                    self.forward_state(None);
                }
            } else if self.registers.last().unwrap().borrow().get_state()
                == ExecStates::CallFuncExtractFunc
                || self.registers.last().unwrap().borrow().get_state()
                    == ExecStates::CallFuncExtractParam
            {
                self.registers.last().unwrap().borrow_mut().set_state(
                    ExecStates::CallFuncExtractParam,
                    Box::new(val.clone().unwrap()),
                );
                if self.registers.last().unwrap().borrow().get_state()
                    == ExecStates::CallFuncFinished
                {
                    self.forward_state(None);
                }
            } else if self.registers.last().unwrap().borrow().get_state()
                == ExecStates::CallFuncFinished
            {
                let regs = self.registers.last().unwrap().borrow().get_data().clone();
                let is_native = regs[1].as_bool();
                if !is_native {
                    let func = regs[0].as_func().clone();
                    let arg_count = regs[2].as_i32() as usize;
                    if arg_count != func.borrow().params.len() {
                        panic!("elpian error: func params count is not correct");
                    }
                    let mut args = HashMap::new();
                    let mut i: usize = 0;
                    for arg in regs[3].as_array().borrow().data.iter() {
                        args.insert(func.borrow().params[i].clone(), arg.clone());
                        i += 1;
                    }
                    self.ctx
                        .memory
                        .last()
                        .unwrap()
                        .borrow_mut()
                        .update_frozen_pointer(self.pointer);
                    self.ctx.push_scope_with_args(
                        func.borrow().start,
                        func.borrow().start,
                        func.borrow().end,
                        args,
                    );
                    self.after_return_next_jump = self.pointer;
                    self.pointer = func.borrow().start;
                    self.end_at = func.borrow().end;
                } else {
                    let mut args = HashMap::new();
                    let arg = regs[3].as_array().borrow().data[0].clone();
                    args.insert("apiName".to_string(), arg);
                    let arg = regs[3].as_array().borrow().data[1].clone();
                    args.insert("input".to_string(), arg);
                    self.cb_counter += 1;
                    let cb_id = self.cb_counter;
                    let (cb_send, cb_recv) = mpsc::channel::<Val>();
                    self.callbacks.insert(cb_id, cb_send);
                    self.vm_send
                        .send((
                            0x02,
                            cb_id,
                            Val {
                                typ: 9,
                                data: Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(Array::new(vec![
                                    args["apiName"].clone(),
                                    args["input"].clone(),
                                ])))))),
                            },
                        ))
                        .unwrap();
                    let result = cb_recv.recv().unwrap();
                    // self.pending_func_result_value = result.clone();
                    // self.pointer = self.pending_func_result_position;
                    self.registers.pop();
                    self.forward_state(Some(result));
                }
            }
        } else if self.registers.last().unwrap().borrow().get_type() == OperationTypes::ReturnVal {
            if self.registers.last().unwrap().borrow().get_state() == ExecStates::ReturnValStarted {
                self.registers.last().unwrap().borrow_mut().set_state(
                    ExecStates::ReturnValFinished,
                    Box::new(val.clone().unwrap()),
                );
                self.forward_state(None);
            } else if self.registers.last().unwrap().borrow().get_state()
                == ExecStates::ReturnValFinished
            {
                let data = self.registers.last().unwrap().borrow().get_data();
                let returned_val = data[0].clone();
                self.registers.pop();
                self.pointer = self.end_at;
                self.pending_func_result_value = returned_val;
            }
        } else if self.registers.last().unwrap().borrow().get_type() == OperationTypes::DefineVar {
            if self.registers.last().unwrap().borrow().get_state()
                == ExecStates::DefineVarExtractName
            {
                self.registers.last().unwrap().borrow_mut().set_state(
                    ExecStates::DefineVarExtractValue,
                    Box::new(val.clone().unwrap()),
                );
                self.forward_state(None);
            } else if self.registers.last().unwrap().borrow().get_state()
                == ExecStates::DefineVarExtractValue
            {
                let regs = self.registers.last().unwrap().borrow().get_data().clone();
                let var_name = regs[0].as_string();
                let var_value = regs[1].clone();
                self.registers.pop();
                self.define(var_name.clone(), var_value.clone());
            }
        } else if self.registers.last().unwrap().borrow().get_type() == OperationTypes::AssignVar {
            if self.registers.last().unwrap().borrow().get_state()
                == ExecStates::AssignVarExtractName
            {
                if self.registers.last().unwrap().borrow().get_data()[1].as_i16() == 1 {
                    self.registers.last().unwrap().borrow_mut().set_state(
                        ExecStates::AssignVarExtractValue,
                        Box::new(val.clone().unwrap()),
                    );
                    self.forward_state(None);
                } else if self.registers.last().unwrap().borrow().get_data()[1].as_i16() == 2 {
                    self.registers.last().unwrap().borrow_mut().set_state(
                        ExecStates::AssignVarExtractIndex,
                        Box::new(val.clone().unwrap()),
                    );
                    self.forward_state(None);
                }
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
                            panic!("elpian error: non object value can not be indexed by string");
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
                            panic!("elpian error: non object value can not be indexed by string");
                        }
                    } else {
                        panic!(
                            "elpian error: types other than integer and string can not be used to index anything"
                        );
                    }
                }
                self.registers.pop();
            }
        } else if self.registers.last().unwrap().borrow().get_type() == OperationTypes::IfStmt {
            if self.registers.last().unwrap().borrow().get_state()
                == ExecStates::IfStmtIsConditioned
            {
                self.registers
                    .last()
                    .unwrap()
                    .borrow_mut()
                    .set_state(ExecStates::IfStmtFinished, Box::new(val.clone().unwrap()));
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
                    self.ctx
                        .push_scope(branch_true_start, branch_true_start, branch_true_end);
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
                        self.ctx
                            .push_scope(branch_true_start, branch_true_start, branch_true_end);
                        self.pointer = branch_true_start;
                        self.end_at = branch_true_end;
                    } else {
                        self.pointer = branch_next_start;
                    }
                }
                self.registers.pop();
            }
        } else if self.registers.last().unwrap().borrow().get_type() == OperationTypes::LoopStmt {
            if self.registers.last().unwrap().borrow().get_state() == ExecStates::LoopStmtStarted {
                self.registers
                    .last()
                    .unwrap()
                    .borrow_mut()
                    .set_state(ExecStates::LoopStmtFinished, Box::new(val.clone().unwrap()));
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
                    self.ctx
                        .push_scope(branch_true_start, branch_true_start, branch_true_end);
                    self.pointer = branch_true_start;
                    self.end_at = branch_true_end;
                } else {
                    self.pointer = branch_after_start;
                }
                self.registers.pop();
            }
        } else if self.registers.last().unwrap().borrow().get_type() == OperationTypes::SwitchStmt {
            if self.registers.last().unwrap().borrow().get_state() == ExecStates::SwitchStmtStarted
            {
                let branch_after_start = self.extract_i64() as usize;
                let case_count = self.extract_i64() as usize;
                self.registers.last().unwrap().borrow_mut().set_state(
                    ExecStates::SwitchStmtExtractVal,
                    Box::new((val.clone().unwrap(), branch_after_start, case_count)),
                );
            } else if self.registers.last().unwrap().borrow().get_state()
                == ExecStates::SwitchStmtExtractVal
                || self.registers.last().unwrap().borrow().get_state()
                    == ExecStates::SwitchStmtExtractCase
            {
                let branch_true_start = self.extract_i64() as usize;
                let branch_true_end = self.extract_i64() as usize;
                self.registers.last().unwrap().borrow_mut().set_state(
                    ExecStates::SwitchStmtExtractCase,
                    Box::new((val.clone().unwrap(), branch_true_start, branch_true_end)),
                );
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
                    if self.is_equal(comparing_val.clone(), case_val) {
                        matched = true;
                        self.ctx
                            .memory
                            .last()
                            .unwrap()
                            .borrow_mut()
                            .update_frozen_pointer(branch_after_start);
                        self.ctx
                            .push_scope(branch_true_start, branch_true_start, branch_true_end);
                        self.pointer = branch_true_start;
                        self.end_at = branch_true_end;
                    }
                }
                if !matched {
                    self.pointer = branch_after_start;
                }
                self.registers.pop();
            }
        } else if self.registers.last().unwrap().borrow().get_type() == OperationTypes::Arithmetic {
            if self.registers.last().unwrap().borrow().get_state()
                == ExecStates::ArithmeticExtractOp
            {
                self.registers.last().unwrap().borrow_mut().set_state(
                    ExecStates::ArithmeticExtractArg1,
                    Box::new(val.clone().unwrap()),
                );
            } else if self.registers.last().unwrap().borrow().get_state()
                == ExecStates::ArithmeticExtractArg1
            {
                self.registers.last().unwrap().borrow_mut().set_state(
                    ExecStates::ArithmeticExtractArg2,
                    Box::new(val.clone().unwrap()),
                );
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
                        self.forward_state(Some(Val {
                            typ: 6,
                            data: Rc::new(RefCell::new(Box::new(self.is_equal(arg1, arg2)))),
                        }));
                    }
                    2 => {
                        self.forward_state(Some(Val {
                            typ: 6,
                            data: Rc::new(RefCell::new(Box::new(self.operate_sum(arg1, arg2)))),
                        }));
                    }
                    3 => {
                        self.forward_state(Some(Val {
                            typ: 6,
                            data: Rc::new(RefCell::new(Box::new(
                                self.operate_subtract(arg1, arg2),
                            ))),
                        }));
                    }
                    _ => {}
                }
            }
        } else if self.registers.last().unwrap().borrow().get_type() == OperationTypes::Indexer {
            if self.registers.last().unwrap().borrow().get_state() == ExecStates::IndexerStarted {
                self.registers.last().unwrap().borrow_mut().set_state(
                    ExecStates::IndexerExtractVarName,
                    Box::new(val.clone().unwrap()),
                );
            } else if self.registers.last().unwrap().borrow().get_state()
                == ExecStates::IndexerExtractVarName
            {
                self.registers.last().unwrap().borrow_mut().set_state(
                    ExecStates::IndexerExtractIndex,
                    Box::new(val.clone().unwrap()),
                );
            } else if self.registers.last().unwrap().borrow().get_state()
                == ExecStates::IndexerExtractIndex
            {
                let regs = self.registers.last().unwrap().borrow().get_data().clone();
                let indexed = regs[0].clone();
                let index = regs[1].clone();
                self.registers.pop();
                if index.typ == 7 {
                    if indexed.typ == 8 {
                        let obj = indexed.as_object();
                        self.forward_state(Some(
                            obj.borrow()
                                .data
                                .data
                                .get(&index.as_string())
                                .unwrap()
                                .clone(),
                        ));
                    } else {
                        panic!("elpian error: non object value can not be indexed by string");
                    }
                } else if index.typ >= 1 && index.typ <= 3 {
                    if indexed.typ == 9 {
                        let arr = indexed.as_array();
                        if index.typ == 1 {
                            self.forward_state(Some(
                                arr.borrow()
                                    .data
                                    .get(index.as_i16() as usize)
                                    .unwrap()
                                    .clone(),
                            ));
                        } else if index.typ == 2 {
                            self.forward_state(Some(
                                arr.borrow()
                                    .data
                                    .get(index.as_i32() as usize)
                                    .unwrap()
                                    .clone(),
                            ));
                        } else {
                            self.forward_state(Some(
                                arr.borrow()
                                    .data
                                    .get(index.as_i64() as usize)
                                    .unwrap()
                                    .clone(),
                            ));
                        }
                    } else {
                        panic!("elpian error: non object value can not be indexed by string");
                    }
                } else {
                    panic!(
                        "elpian error: types other than integer and string can not be used to index anything"
                    );
                }
            }
        }
    }
    pub fn run_from(&mut self, start: usize, end: usize) -> Val {
        self.ctx.push_scope(start, start, end);
        self.pointer = start;
        self.end_at = end;
        loop {
            if self.pointer == self.end_at {
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
                self.ctx.pop_scope();
                if self.ctx.memory.len() > 0 {
                    self.pointer = self.ctx.memory.last().unwrap().borrow().frozen_pointer;
                    self.end_at = self.ctx.memory.last().unwrap().borrow().frozen_end;
                    if self.pending_func_result_value.typ != 254 {
                        self.pointer = self.pending_func_result_position;
                    }
                } else {
                    break;
                }
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
                        .set_state(ExecStates::ArithmeticExtractOp, Box::new(1));
                }
                // sum operator
                0xf1 => {
                    let state_holder = Arithmetic::new();
                    self.registers
                        .push(Rc::new(RefCell::new(Box::new(state_holder))));
                    self.registers
                        .last()
                        .unwrap()
                        .borrow_mut()
                        .set_state(ExecStates::ArithmeticExtractOp, Box::new(2));
                }
                // subtract operator
                0xf2 => {
                    let state_holder = Arithmetic::new();
                    self.registers
                        .push(Rc::new(RefCell::new(Box::new(state_holder))));
                    self.registers
                        .last()
                        .unwrap()
                        .borrow_mut()
                        .set_state(ExecStates::ArithmeticExtractOp, Box::new(3));
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
                            Box::new((var_name, 0x0c)),
                        );
                    } else if self.program[self.pointer] == 0x0b {
                        self.pointer += 1;
                        let state_holder = AssignVariable::new();
                        self.registers
                            .push(Rc::new(RefCell::new(Box::new(state_holder))));
                        let var_name = self.extract_str();
                        self.registers.last().unwrap().borrow_mut().set_state(
                            ExecStates::AssignVarExtractName,
                            Box::new((var_name, 0x0b)),
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
                    self.registers
                        .last()
                        .unwrap()
                        .borrow_mut()
                        .set_state(ExecStates::IfStmtIsConditioned, Box::new(has_condition));
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
                    let func = Function::new(func_start, func_end, param_names);
                    self.define(
                        func_name,
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
                // ----------------------------------
                // expressions
                // data expressions
                1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 => {
                    self.pointer -= 1;
                    let val = self.extract_val();
                    self.forward_state(Some(val));
                }
                // ----------------------------------
                // No-Op
                _ => {}
            }
        }
        Val::new(0, Rc::new(RefCell::new(Box::new(0))))
    }
}
