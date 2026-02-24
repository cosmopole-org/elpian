use std::{cell::RefCell, collections::HashMap, rc::Rc};

use serde_json::{json, Value};

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
                    let trimmed = json_str.trim();
                    if trimmed.is_empty() {
                        Val::new(0, Rc::new(RefCell::new(Box::new(0))))
                    } else {
                        match serde_json::from_str::<Value>(trimmed) {
                            Ok(value) => self.convert_json_value_to_val(value),
                            Err(_) => {
                                // Fallback: treat non-JSON payloads as plain strings.
                                Val::new(7, Rc::new(RefCell::new(Box::new(trimmed.to_string()))))
                            }
                        }
                    }
                }
                None => Val::new(0, Rc::new(RefCell::new(Box::new(0)))),
            };
            Val::new(
                9,
                Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(Array::new(
                    vec![
                        Val::new(7, Rc::new(RefCell::new(Box::new(func_name.to_string())))),
                        input_val,
                    ],
                )))))),
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
        let maybe_typed_value = val
            .as_object()
            .and_then(|obj| obj.get("type").and_then(Value::as_str).map(|t| (obj, t)));

        if let Some((obj, typ)) = maybe_typed_value {
            let data_value = obj
                .get("data")
                .and_then(Value::as_object)
                .and_then(|data| data.get("value"))
                .cloned()
                .unwrap_or(Value::Null);

            match typ {
                "null" => return Val::new(0, Rc::new(RefCell::new(Box::new(0)))),
                "i16" => {
                    if let Some(v) = data_value.as_i64() {
                        return Val::new(1, Rc::new(RefCell::new(Box::new(v as i16))));
                    }
                }
                "i32" => {
                    if let Some(v) = data_value.as_i64() {
                        return Val::new(2, Rc::new(RefCell::new(Box::new(v as i32))));
                    }
                }
                "i64" => {
                    if let Some(v) = data_value.as_i64() {
                        return Val::new(3, Rc::new(RefCell::new(Box::new(v))));
                    }
                }
                "f32" => {
                    if let Some(v) = data_value.as_f64() {
                        return Val::new(4, Rc::new(RefCell::new(Box::new(v as f32))));
                    }
                }
                "f64" => {
                    if let Some(v) = data_value.as_f64() {
                        return Val::new(5, Rc::new(RefCell::new(Box::new(v))));
                    }
                }
                "bool" => {
                    if let Some(v) = data_value.as_bool() {
                        return Val::new(6, Rc::new(RefCell::new(Box::new(v))));
                    }
                }
                "string" => {
                    if let Some(v) = data_value.as_str() {
                        return Val::new(7, Rc::new(RefCell::new(Box::new(v.to_string()))));
                    }
                }
                "object" => {
                    if let Some(map) = data_value.as_object() {
                        let mut obj_map = HashMap::new();
                        for (k, v) in map.iter() {
                            obj_map.insert(k.clone(), self.convert_json_value_to_val(v.clone()));
                        }
                        return Val::new(
                            8,
                            Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(Object::new(
                                -2,
                                ValGroup::new(obj_map),
                            )))))),
                        );
                    }
                }
                "array" => {
                    if let Some(items) = data_value.as_array() {
                        let vals: Vec<Val> = items
                            .iter()
                            .map(|item| self.convert_json_value_to_val(item.clone()))
                            .collect();
                        return Val::new(
                            9,
                            Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(Array::new(
                                vals,
                            )))))),
                        );
                    }
                }
                _ => {}
            }
        }

        match val {
            Value::Null => Val::new(0, Rc::new(RefCell::new(Box::new(0)))),
            Value::Bool(v) => Val::new(6, Rc::new(RefCell::new(Box::new(v)))),
            Value::Number(n) => {
                if let Some(i) = n.as_i64() {
                    Val::new(3, Rc::new(RefCell::new(Box::new(i))))
                } else {
                    Val::new(
                        5,
                        Rc::new(RefCell::new(Box::new(n.as_f64().unwrap_or(0.0)))),
                    )
                }
            }
            Value::String(s) => Val::new(7, Rc::new(RefCell::new(Box::new(s)))),
            Value::Array(items) => {
                let vals: Vec<Val> = items
                    .into_iter()
                    .map(|item| self.convert_json_value_to_val(item))
                    .collect();
                Val::new(
                    9,
                    Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(Array::new(
                        vals,
                    )))))),
                )
            }
            Value::Object(map) => {
                let mut obj_map = HashMap::new();
                for (k, v) in map.into_iter() {
                    obj_map.insert(k, self.convert_json_value_to_val(v));
                }
                Val::new(
                    8,
                    Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(Object::new(
                        -2,
                        ValGroup::new(obj_map),
                    )))))),
                )
            }
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
