use std::{cell::RefCell, collections::HashMap, rc::Rc};

use serde_json::{Value, json};

use crate::sdk::{compiler, data::Val, executor::Executor};

use crate::sdk::data::{Array, Object, ValGroup};

pub struct CallbackHolder {
    pub callback: Box<dyn Fn(String) -> String>,
}

pub struct VM {
    machine_id: String,
    pub program: Vec<u8>,
    single_thread_executor: Option<Rc<RefCell<Executor>>>,
    pending_host_call_id: i64,
    pub sending_host_call_data: Option<String>,
}

unsafe impl Send for VM {}
unsafe impl Sync for VM {}

impl VM {
    pub fn compile_and_create_of_bytecode(
        machine_id: String,
        program: Vec<u8>,
        func_group: Vec<String>,
    ) -> Self {
        let executor = Executor::create_in_single_thread(program.clone(), 0, func_group);
        VM {
            machine_id,
            program,
            single_thread_executor: Some(Rc::new(RefCell::new(executor))),
            pending_host_call_id: 0,
            sending_host_call_data: None,
        }
    }
    pub fn compile_and_create_of_ast(
        machine_id: String,
        program: serde_json::Value,
        _executor_count: i32,
        func_group: Vec<String>,
    ) -> Self {
        let byte_code = compiler::compile_ast(program, 0);
        Self::compile_and_create_of_bytecode(machine_id, byte_code, func_group)
    }
    pub fn compile_and_create_of_code(
        machine_id: String,
        program: String,
        _executor_count: i32,
        func_group: Vec<String>,
    ) -> Self {
        let byte_code = compiler::compile_code(program);
        Self::compile_and_create_of_bytecode(machine_id, byte_code, func_group)
    }
    pub fn print_memory(&mut self) {}
    pub fn run(&mut self) -> Val {
        self.run_func_with_input("", None, 0)
    }
    pub fn is_exec_processing(&self) -> bool {
        self.single_thread_executor
            .as_ref()
            .unwrap()
            .borrow()
            .processing
    }
    pub fn run_func_with_input(&mut self, func_name: &str, input: Option<&str>, cb_id: i64) -> Val {
        let payload = if func_name.is_empty() {
            Val::new(0, Rc::new(RefCell::new(Box::new(0))))
        } else {
            let input_val = match input {
                Some(json_str) => {
                    let value: Value = serde_json::from_str(json_str).unwrap();
                    self.convert_json_value_to_val(value)
                }
                None => Val::new(0, Rc::new(RefCell::new(Box::new(0)))),
            };
            Val::new(
                9,
                Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(
                    Array::new(vec![
                        Val::new(7, Rc::new(RefCell::new(Box::new(func_name.to_string())))),
                        input_val,
                    ]),
                ))))),
            )
        };
        let r = self
            .single_thread_executor
            .as_ref()
            .unwrap()
            .borrow_mut()
            .single_thread_operation(0x01, cb_id, payload);
        self.handle_executor_request(r.0, r.1, r.2)
    }
    pub fn continue_run(&mut self, res_raw: String) -> Val {
        let res_json: Value = serde_json::from_str(&res_raw).unwrap();
        let res = self.convert_json_value_to_val(res_json);
        let res_next = self
            .single_thread_executor
            .as_ref()
            .unwrap()
            .borrow_mut()
            .single_thread_operation(0x03, self.pending_host_call_id, res);
        self.handle_executor_request(res_next.0, res_next.1, res_next.2)
    }
    fn convert_json_value_to_val(&self, val: Value) -> Val {
        match val["type"].as_str().unwrap() {
            "i16" => Val::new(1, Rc::new(RefCell::new(Box::new(val["data"]["value"].as_i64().unwrap() as i16)))),
            "i32" => Val::new(2, Rc::new(RefCell::new(Box::new(val["data"]["value"].as_i64().unwrap() as i32)))),
            "i64" => Val::new(3, Rc::new(RefCell::new(Box::new(val["data"]["value"].as_i64().unwrap())))),
            "f32" => Val::new(4, Rc::new(RefCell::new(Box::new(val["data"]["value"].as_f64().unwrap() as f32)))),
            "f64" => Val::new(5, Rc::new(RefCell::new(Box::new(val["data"]["value"].as_f64().unwrap())))),
            "bool" => Val::new(6, Rc::new(RefCell::new(Box::new(val["data"]["value"].as_bool().unwrap())))),
            "string" => Val::new(7, Rc::new(RefCell::new(Box::new(val["data"]["value"].as_str().unwrap().to_string())))),
            "object" => {
                let mut obj_map = HashMap::new();
                for (k, v) in val["data"]["value"].as_object().unwrap().iter() {
                    obj_map.insert(k.clone(), self.convert_json_value_to_val(v.clone()));
                }
                Val::new(
                    8,
                    Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(Object::new(-2, ValGroup::new(obj_map))))))),
                )
            }
            "array" => {
                let items: Vec<Val> = val["data"]["value"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .map(|item| self.convert_json_value_to_val(item.clone()))
                    .collect();
                Val::new(
                    9,
                    Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(Array::new(items)))))),
                )
            }
            _ => Val::new(0, Rc::new(RefCell::new(Box::new(0)))),
        }
    }
    fn handle_executor_request(&mut self, op_code: u8, cb_id: i64, payload: Val) -> Val {
        match op_code {
            0x01 => payload,
            0x02 => {
                let params = payload.as_array().borrow().data.clone();
                self.pending_host_call_id = cb_id;
                self.sending_host_call_data = Some(
                    json!({
                        "machineId": self.machine_id,
                        "apiName": params[0].as_string(),
                        "payload": params[2].stringify(),
                    })
                    .to_string(),
                );
                Val::new(253, Rc::new(RefCell::new(Box::new(0))))
            }
            _ => Val::new(0, Rc::new(RefCell::new(Box::new(0)))),
        }
    }
}
