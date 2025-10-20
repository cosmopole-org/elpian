use crate::sdk::{context::Context, data::Val};
use std::{sync::{mpsc::{self, Sender}, Arc}, thread};

pub struct Executor {
    pointer: usize,
    ctx: Context,
    program: Vec<u8>,
}

impl Executor {
    pub fn create(program: Vec<u8>, vm_send: Sender<(u8, i64, Val)>) -> Sender<(u8, i64, String)> {
        let (tasks_send, tasks_recv) = mpsc::channel::<(u8, i64, String)>();
        thread::spawn(move || {
            let mut ex = Executor {
                pointer: 0,
                ctx: Context::new(),
                program,
            };
            loop {
                let (op_code, cb_id, payload) = tasks_recv.recv().unwrap();
                match op_code {
                    0x00 => {
                        break;
                    }
                    0x01 => {
                        let val = ex.ctx.find_val_in_first_scope(payload);
                        if !val.is_empty() {
                            let func = val.as_func();
                            let result = ex.run_from(func.start, func.end);
                            vm_send.clone().send((0x01, cb_id, result)).unwrap();
                        }
                    }
                    _ => {}
                }
            }
        });
        tasks_send.clone()
    }
    pub fn run_from(&mut self, start: usize, end: usize) -> Val {
        self.pointer = start;
        loop {
            if self.pointer == end {
                break;
            }
            let unit: u8 = *self.program.get(self.pointer).unwrap();
            match unit {
                0x01 => {
                    self.pointer += 1;
                }
                _ => {}
            }
        }
        Val::new(0, Arc::new(Box::new(0)))
    }
}
