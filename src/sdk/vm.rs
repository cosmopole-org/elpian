use std::{
    collections::HashMap,
    sync::{
        Arc, Mutex,
        mpsc::{self, Sender},
    },
    thread,
};

use crate::sdk::{data::Val, executor::Executor};

pub struct VM {
    pub program: Vec<u8>,
    pub executors: Vec<Sender<(u8, i64, String)>>,
    callbacks: Arc<Mutex<HashMap<i64, Sender<Val>>>>,
    cb_id_counter: i64,
}

impl VM {
    pub fn new(program: Vec<u8>, execuror_count: i32) -> Self {
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
            executors.push(Executor::create(program.clone(), vm_send));
        }
        VM {
            program,
            executors: executors,
            callbacks: Arc::new(Mutex::new(HashMap::new())),
            cb_id_counter: 0,
        }
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
