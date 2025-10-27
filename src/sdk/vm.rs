use std::{
    cell::RefCell,
    collections::HashMap,
    rc::Rc,
    sync::{
        Arc, Mutex,
        mpsc::{self, Sender},
    },
    thread,
};

use crate::sdk::{compiler, data::Val, executor::Executor};

pub struct VM {
    pub program: Vec<u8>,
    pub executors: Arc<Mutex<Vec<Sender<(u8, i64, Val)>>>>,
    callbacks: Arc<Mutex<HashMap<i64, Sender<Val>>>>,
    cb_id_counter: i64,
}

impl VM {
    pub fn create(program: Vec<u8>, execuror_count: i32, func_group: Vec<String>) -> Self {
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
            executors.lock().unwrap().push(Executor::create(
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
        }
    }
    pub fn compile_and_create(
        program: serde_json::Value,
        execuror_count: i32,
        func_group: Vec<String>,
    ) -> Self {
        let byte_code = compiler::compile(program, 0);
        Self::create(byte_code, execuror_count, func_group)
    }
    pub fn print_memory(&mut self) {
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
    }
    pub fn run(&mut self) -> Val {
        self.run_func("")
    }
    pub fn run_func(&mut self, func_name: &str) -> Val {
        self.cb_id_counter += 1;
        let cb_id = self.cb_id_counter;
        let (result_send, result_recv) = mpsc::channel::<Val>();
        {
            self.callbacks.lock().unwrap().insert(cb_id, result_send);
        }
        if func_name.is_empty() {
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
        } else {
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
        }
        let result = result_recv.recv().unwrap();
        result
    }
}
