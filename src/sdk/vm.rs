use std::{
    collections::HashMap,
    sync::{
        Arc, Mutex,
        mpsc::{self, Sender},
    },
    thread,
};

use crate::sdk::{compiler, data::Val, executor::Executor};

pub struct VM {
    pub program: Vec<u8>,
    pub executors: Vec<Sender<(u8, i64, String)>>,
    callbacks: Arc<Mutex<HashMap<i64, Sender<Val>>>>,
    cb_id_counter: i64,
}

impl VM {
    pub fn create(program: Vec<u8>, execuror_count: i32, func_group: Vec<String>) -> Self {
        let mut executors: Vec<Sender<(u8, i64, String)>> = vec![];
        let callbacks: Arc<Mutex<HashMap<i64, Sender<Val>>>> = Arc::new(Mutex::new(HashMap::new()));
        for _ in 0..execuror_count {
            let callbacks_clone = callbacks.clone();
            let (vm_send, vm_recv) = mpsc::channel::<(u8, i64, Val)>();
            thread::spawn(move || {
                let (op_code, cb_id, payload) = vm_recv.recv().unwrap();
                match op_code {
                    0x01 => {
                        let cbs = callbacks_clone.lock().unwrap();
                        let sender = cbs.get(&cb_id).unwrap();
                        sender.send(payload).unwrap();
                    }
                    _ => {}
                }
            });
            executors.push(Executor::create(program.clone(), vm_send, func_group.clone()));
        }
        VM {
            program,
            executors: executors,
            callbacks: callbacks,
            cb_id_counter: 0,
        }
    }
    pub fn compile_and_create(program: serde_json::Value, execuror_count: i32, func_group: Vec<String>) -> Self {
        let byte_code = compiler::compile(program);
        Self::create(byte_code, execuror_count, func_group)
    }
    pub fn print_memory(&mut self) {
        self.executors.iter().for_each(|ex| {
            ex.send((0x02, 0, "".to_string())).unwrap();
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
        self.executors
            .get(0)
            .unwrap()
            .send((0x01, cb_id, func_name.to_string()))
            .unwrap();
        let result = result_recv.recv().unwrap();
        result
    }
}
