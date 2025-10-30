use std::{
    cell::RefCell,
    collections::HashMap,
    rc::Rc,
    sync::{
        Arc, Mutex,
        mpsc::{self, Sender},
    },
};

#[cfg(not(target_arch = "wasm32"))]
use std::thread;

use wasm_bindgen::prelude::wasm_bindgen;

use crate::sdk::{compiler, data::Val, executor::Executor};

#[wasm_bindgen]
extern "C" {
    #[wasm_bindgen(js_namespace = console)]
    fn log(s: &str);
    #[wasm_bindgen(js_namespace = console, js_name = log)]
    fn log_u32(a: u32);
    #[wasm_bindgen(js_namespace = console, js_name = log)]
    fn log_many(a: &str, b: &str);
}

pub struct VM {
    pub program: Vec<u8>,
    pub executors: Arc<Mutex<Vec<Sender<(u8, i64, Val)>>>>,
    callbacks: Arc<Mutex<HashMap<i64, Sender<Val>>>>,
    cb_id_counter: i64,
    single_thread_executor: Option<Rc<RefCell<Executor>>>,
}

impl VM {
    #[cfg(not(target_arch = "wasm32"))]
    pub fn create_multi_threaded(
        program: Vec<u8>,
        execuror_count: i32,
        func_group: Vec<String>,
    ) -> Self {
        let executors: Arc<Mutex<Vec<Sender<(u8, i64, Val)>>>> = Arc::new(Mutex::new(vec![]));
        let callbacks: Arc<Mutex<HashMap<i64, Sender<Val>>>> = Arc::new(Mutex::new(HashMap::new()));
        let executorsw_clone_0 = executors.clone();
        for i in 0..execuror_count {
            let callbacks_clone = callbacks.clone();
            let (vm_send, vm_recv) = mpsc::channel::<(u8, i64, Val)>();
            let executors_clone = executors.clone();
            thread::spawn(move || {
                loop {
                    let (op_code, cb_id, payload) = vm_recv.recv().unwrap();
                    match op_code {
                        0x01 => {
                            let cbs = callbacks_clone.lock().unwrap();
                            let sender = cbs.get(&cb_id).unwrap();
                            let res = sender.send(payload);
                            if !res.is_ok() {
                                println!("{:#?}", res.err());
                            }
                        }
                        0x02 => {
                            let params = payload.as_array().borrow().data.clone();
                            if params[0].as_string() == "println" {
                                println!("{}", params[2].stringify());
                                executors_clone.lock().unwrap()[params[1].as_i16() as usize]
                                    .send((
                                        0x03,
                                        cb_id,
                                        Val {
                                            typ: 0,
                                            data: Rc::new(RefCell::new(Box::new(0))),
                                        },
                                    ))
                                    .unwrap();
                                continue;
                            }
                            executors_clone.lock().unwrap()[params[1].as_i16() as usize]
                                .send((
                                    0x03,
                                    cb_id,
                                    Val {
                                        typ: 0,
                                        data: Rc::new(RefCell::new(Box::new(0))),
                                    },
                                ))
                                .unwrap();
                        }
                        _ => {}
                    }
                }
            });
            executors
                .lock()
                .unwrap()
                .push(Executor::create_in_multi_thread(
                    program.clone(),
                    i as i16,
                    vm_send,
                    func_group.clone(),
                ));
        }
        VM {
            program,
            executors: executorsw_clone_0,
            callbacks: callbacks,
            cb_id_counter: 0,
            single_thread_executor: None,
        }
    }
    #[cfg(target_arch = "wasm32")]
    pub fn create_single_threaded(program: Vec<u8>, func_group: Vec<String>) -> Self {
        let callbacks: Arc<Mutex<HashMap<i64, Sender<Val>>>> = Arc::new(Mutex::new(HashMap::new()));
        VM {
            program: program.clone(),
            executors: Arc::new(Mutex::new(vec![])),
            callbacks: callbacks,
            cb_id_counter: 0,
            single_thread_executor: Some(Rc::new(RefCell::new(Executor::create_in_single_thread(
                program.clone(),
                0,
                func_group.clone(),
            )))),
        }
    }
    pub fn compile_and_create(
        program: serde_json::Value,
        execuror_count: i32,
        func_group: Vec<String>,
    ) -> Self {
        let byte_code = compiler::compile(program, 0);
        if execuror_count == 1 {
            #[cfg(not(target_arch = "wasm32"))]
            return Self::create_multi_threaded(byte_code, execuror_count, func_group);
            #[cfg(target_arch = "wasm32")]
            return Self::create_single_threaded(byte_code, func_group);
        } else {
            #[cfg(not(target_arch = "wasm32"))]
            return Self::create_multi_threaded(byte_code, execuror_count, func_group);
            #[cfg(target_arch = "wasm32")]
            return Self::create_single_threaded(byte_code, func_group);
        }
    }
    pub fn print_memory(&mut self) {
        if self.single_thread_executor.is_none() {
            self.executors.lock().unwrap().iter().for_each(|ex| {
                ex.send((
                    0x02,
                    0,
                    Val {
                        typ: 7,
                        data: Rc::new(RefCell::new(Box::new("".to_string()))),
                    },
                ))
                .unwrap();
            });
        } else {
            self.single_thread_executor
                .clone()
                .unwrap()
                .borrow_mut()
                .single_thread_operation(
                    0x02,
                    0,
                    Val {
                        typ: 7,
                        data: Rc::new(RefCell::new(Box::new("".to_string()))),
                    },
                );
        }
    }
    pub fn run(&mut self) -> Val {
        self.run_func("")
    }
    fn handle_executor_request(&mut self, op_code: u8, cb_id: i64, payload: Val) -> Val {
        match op_code {
            0x01 => {
                return payload;
            }
            0x02 => {
                let params = payload.as_array().borrow().data.clone();
                if params[0].as_string() == "println" {
                    #[cfg(target_arch = "wasm32")]
                    log(&params[2].stringify());
                    #[cfg(not(target_arch = "wasm32"))]
                    println!("{}", params[2].stringify());
                    let res = self
                        .single_thread_executor
                        .as_ref()
                        .unwrap()
                        .borrow_mut()
                        .single_thread_operation(
                            0x03,
                            cb_id,
                            Val {
                                typ: 0,
                                data: Rc::new(RefCell::new(Box::new(0))),
                            },
                        );
                    return self.handle_executor_request(res.0, res.1, res.2);
                }
                let res = self
                    .single_thread_executor
                    .as_ref()
                    .unwrap()
                    .borrow_mut()
                    .single_thread_operation(
                        0x03,
                        cb_id,
                        Val {
                            typ: 0,
                            data: Rc::new(RefCell::new(Box::new(0))),
                        },
                    );
                return self.handle_executor_request(res.0, res.1, res.2);
            }
            _ => {
                return Val {
                    typ: 0,
                    data: Rc::new(RefCell::new(Box::new(0))),
                };
            }
        }
    }
    pub fn run_func(&mut self, func_name: &str) -> Val {
        self.cb_id_counter += 1;
        let cb_id = self.cb_id_counter;
        if func_name.is_empty() {
            if self.single_thread_executor.is_none() {
                let (result_send, result_recv) = mpsc::channel::<Val>();
                {
                    self.callbacks.lock().unwrap().insert(cb_id, result_send);
                }
                self.executors
                    .lock()
                    .unwrap()
                    .get(0)
                    .unwrap()
                    .send((
                        0x01,
                        cb_id,
                        Val {
                            typ: 0,
                            data: Rc::new(RefCell::new(Box::new(0))),
                        },
                    ))
                    .unwrap();
                let result = result_recv.recv().unwrap();
                result
            } else {
                let res = self
                    .single_thread_executor
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
                    );
                return self.handle_executor_request(res.0, res.1, res.2);
            }
        } else {
            if self.single_thread_executor.is_none() {
                let (result_send, result_recv) = mpsc::channel::<Val>();
                {
                    self.callbacks.lock().unwrap().insert(cb_id, result_send);
                }
                self.executors
                    .lock()
                    .unwrap()
                    .get(0)
                    .unwrap()
                    .send((
                        0x01,
                        cb_id,
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(func_name.to_string()))),
                        },
                    ))
                    .unwrap();
                let result = result_recv.recv().unwrap();
                result
            } else {
                let res = self
                    .single_thread_executor
                    .clone()
                    .unwrap()
                    .borrow_mut()
                    .single_thread_operation(
                        0x01,
                        cb_id,
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(func_name.to_string()))),
                        },
                    );
                return self.handle_executor_request(res.0, res.1, res.2);
            }
        }
    }
}
