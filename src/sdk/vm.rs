use std::{cell::RefCell, collections::HashMap, rc::Rc, sync::Arc};

use serde_json::{Value, json};
// use wasm_bindgen::prelude::wasm_bindgen;

use crate::sdk::{compiler, data::Val, executor::Executor};

use crate::sdk::data::{Array, Object, ValGroup};

pub struct CallbackHolder {
    pub callback: Box<dyn Fn(String) -> String>,
}

pub struct VM {
    machine_id: String,
    pub program: Vec<u8>,
    single_thread_executor: Option<Arc<Rc<RefCell<Executor>>>>,
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
        VM {
            machine_id,
            program: program.clone(),
            single_thread_executor: Some(Arc::new(Rc::new(RefCell::new(
                Executor::create_in_single_thread(program.clone(), 0, func_group.clone()),
            )))),
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
        return Self::compile_and_create_of_bytecode(machine_id, byte_code, func_group);
    }
    pub fn compile_and_create_of_code(
        machine_id: String,
        program: String,
        _executor_count: i32,
        func_group: Vec<String>,
    ) -> Self {
        let byte_code = compiler::compile_code(program);
        return Self::compile_and_create_of_bytecode(machine_id, byte_code, func_group);
    }
    pub fn print_memory(&mut self) {}
    pub fn run(&mut self) -> Val {
        self.run_func_with_input("", None, 0)
    }
    pub fn is_exec_processing(&self) -> bool {
        self.single_thread_executor
            .clone()
            .unwrap()
            .borrow()
            .processing
    }
    pub fn run_func_with_input(&mut self, func_name: &str, input: Option<&str>, cb_id: i64) -> Val {
        if func_name.is_empty() {
            let res: Option<(u8, i64, Val)>;
            {
                res = Some(
                    self.single_thread_executor
                        .clone()
                        .unwrap()
                        .borrow_mut()
                        .single_thread_operation(
                            0x01,
                            cb_id,
                            Val {
                                typ: 0,
                                data: Rc::new(RefCell::new(Box::new(0))),
                            },
                        ),
                );
            }
            let r = res.clone().unwrap();
            return self.handle_executor_request(r.0, r.1, r.2);
        } else {
            if input.is_none() {
                let res: Option<(u8, i64, Val)>;
                {
                    res = Some(
                        self.single_thread_executor
                            .clone()
                            .unwrap()
                            .borrow_mut()
                            .single_thread_operation(
                                0x01,
                                cb_id,
                                Val {
                                    typ: 9,
                                    data: Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(
                                        Array::new(vec![
                                            Val {
                                                typ: 7,
                                                data: Rc::new(RefCell::new(Box::new(
                                                    func_name.to_string(),
                                                ))),
                                            },
                                            Val {
                                                typ: 0,
                                                data: Rc::new(RefCell::new(Box::new(0))),
                                            },
                                        ]),
                                    ))))),
                                },
                            ),
                    );
                }
                let r = res.clone().unwrap();
                return self.handle_executor_request(r.0, r.1, r.2);
            } else {
                let value: Value = serde_json::from_str(input.unwrap()).unwrap();
                let res: Option<(u8, i64, Val)>;
                {
                    res = Some(
                        self.single_thread_executor
                            .clone()
                            .unwrap()
                            .borrow_mut()
                            .single_thread_operation(
                                0x01,
                                cb_id,
                                Val {
                                    typ: 9,
                                    data: Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(
                                        Array::new(vec![
                                            Val {
                                                typ: 7,
                                                data: Rc::new(RefCell::new(Box::new(
                                                    func_name.to_string(),
                                                ))),
                                            },
                                            self.convert_json_value_to_val(value),
                                        ]),
                                    ))))),
                                },
                            ),
                    );
                }
                let r = res.clone().unwrap();
                return self.handle_executor_request(r.0, r.1, r.2);
            }
        }
    }
    pub fn continue_run(&mut self, res_raw: String) -> Val {
        let res_json: Value = serde_json::from_str(&res_raw).unwrap();
        let res = self.convert_json_value_to_val(res_json);
        let res_next: (u8, i64, Val);
        {
            res_next = self
                .single_thread_executor
                .as_ref()
                .unwrap()
                .borrow_mut()
                .single_thread_operation(0x03, self.pending_host_call_id, res);
        }
        return self.handle_executor_request(res_next.0, res_next.1, res_next.2);
    }
    fn convert_json_value_to_val(&self, val: Value) -> Val {
        match val["type"].as_str().unwrap() {
            "i16" => {
                return Val {
                    typ: 1,
                    data: Rc::new(RefCell::new(Box::new(
                        val["data"]["value"].as_i64().unwrap() as i16,
                    ))),
                };
            }
            "i32" => {
                return Val {
                    typ: 2,
                    data: Rc::new(RefCell::new(Box::new(
                        val["data"]["value"].as_i64().unwrap() as i32,
                    ))),
                };
            }
            "i64" => {
                return Val {
                    typ: 3,
                    data: Rc::new(RefCell::new(Box::new(
                        val["data"]["value"].as_i64().unwrap() as i64,
                    ))),
                };
            }
            "f32" => {
                return Val {
                    typ: 4,
                    data: Rc::new(RefCell::new(Box::new(
                        val["data"]["value"].as_f64().unwrap() as f32,
                    ))),
                };
            }
            "f64" => {
                return Val {
                    typ: 5,
                    data: Rc::new(RefCell::new(Box::new(
                        val["data"]["value"].as_f64().unwrap() as f64,
                    ))),
                };
            }
            "bool" => {
                return Val {
                    typ: 6,
                    data: Rc::new(RefCell::new(Box::new(
                        val["data"]["value"].as_bool().unwrap(),
                    ))),
                };
            }
            "string" => {
                return Val {
                    typ: 7,
                    data: Rc::new(RefCell::new(Box::new(
                        val["data"]["value"].as_str().unwrap().to_string(),
                    ))),
                };
            }
            "object" => {
                let mut obj_map = HashMap::new();
                for (k, v) in val["data"]["value"].as_object().unwrap().iter() {
                    obj_map.insert(k.clone(), self.convert_json_value_to_val(v.clone()));
                }
                return Val {
                    typ: 8,
                    data: Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(Object::new(
                        -2,
                        ValGroup::new(obj_map),
                    )))))),
                };
            }
            "array" => {
                let mut array_vec = vec![];
                for item in val["data"]["value"].as_array().unwrap().iter() {
                    array_vec.push(self.convert_json_value_to_val(item.clone()));
                }
                return Val {
                    typ: 9,
                    data: Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(Array::new(
                        array_vec,
                    )))))),
                };
            }
            _ => {
                return Val {
                    typ: 0,
                    data: Rc::new(RefCell::new(Box::new(0))),
                };
            }
        }
    }
    fn handle_executor_request(&mut self, op_code: u8, cb_id: i64, payload: Val) -> Val {
        match op_code {
            0x01 => {
                return payload;
            }
            0x02 => {
                let params = payload.as_array().borrow().data.clone();
                self.pending_host_call_id = cb_id;
                self.sending_host_call_data = Some(
                    json!({
                            "machineId": self.machine_id,
                            "apiName": params[0].as_string(),
                            "payload": params[2].stringify()})
                    .to_string(),
                );
                return Val {
                    typ: 253,
                    data: Rc::new(RefCell::new(Box::new(0))),
                };
            }
            _ => {
                return Val {
                    typ: 0,
                    data: Rc::new(RefCell::new(Box::new(0))),
                };
            }
        }
    }
}

// #[wasm_bindgen]
// extern "C" {
//     #[wasm_bindgen(js_namespace = console)]
//     fn log(s: &str);

//     #[wasm_bindgen(js_namespace = console, js_name = log)]
//     fn log_u32(a: u32);

//     #[wasm_bindgen(js_namespace = console, js_name = log)]
//     fn log_many(a: &str, b: &str);

//     #[wasm_bindgen(js_namespace = env, js_name = ask_host)]
//     fn ask_host(payload: String) -> String;
// }
