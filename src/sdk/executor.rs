use crate::sdk::{
    context::Context,
    data::{Array, Function, Object, Val, ValGroup},
};
use std::{
    cell::RefCell,
    collections::HashMap,
    rc::Rc,
    sync::mpsc::{self, Sender},
    thread,
};

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
    fn extract_i16(&mut self) -> i16 {
        let num_bytes: [u8; 2] = self.program[self.pointer..(self.pointer + 2)]
            .try_into()
            .unwrap();
        self.pointer += 2;
        i16::from_le_bytes(num_bytes)
    }
    fn extract_i32(&mut self) -> i32 {
        let num_bytes: [u8; 4] = self.program[self.pointer..(self.pointer + 4)]
            .try_into()
            .unwrap();
        self.pointer += 4;
        i32::from_le_bytes(num_bytes)
    }
    fn extract_i64(&mut self) -> i64 {
        let num_bytes: [u8; 8] = self.program[self.pointer..(self.pointer + 8)]
            .try_into()
            .unwrap();
        self.pointer += 8;
        i64::from_le_bytes(num_bytes)
    }
    fn extract_f32(&mut self) -> f32 {
        let num_bytes: [u8; 4] = self.program[self.pointer..(self.pointer + 4)]
            .try_into()
            .unwrap();
        self.pointer += 4;
        f32::from_le_bytes(num_bytes)
    }
    fn extract_f64(&mut self) -> f64 {
        let num_bytes: [u8; 8] = self.program[self.pointer..(self.pointer + 8)]
            .try_into()
            .unwrap();
        self.pointer += 8;
        f64::from_le_bytes(num_bytes)
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
        let length = i32::from_le_bytes(len_bytes) as usize;
        let str_bytes = self.program[self.pointer..(self.pointer + length)].to_vec();
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
        Function::new(start, end)
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
                let d = self.ctx.find_val_globally(id);
                if d.is_empty() {
                    panic!("elpian error: undefined reference");
                }
                Val {
                    typ: 11,
                    data: Rc::new(RefCell::new(Box::new(d))),
                }
            }
            _ => Val {
                typ: 0,
                data: Rc::new(RefCell::new(Box::new(0))),
            },
        }
    }
    fn resolve_expr_and_assign(&mut self, assign: bool, data: Val) -> Val {
        if self.program[self.pointer] == 0x01 {
            self.pointer += 1;
            let val = self.extract_val();
            if assign {
                if val.typ == 11 {
                    let refer = val.as_refer();
                    refer.borrow_mut().typ = data.clone().typ;
                    refer.borrow_mut().data = data.clone().data;
                } else {
                    panic!("elpian error: non reference value can not be indexed");
                }
                return data;
            } else {
                if val.typ == 11 {
                    let v = val.as_refer();
                    let v_inner = v.borrow();
                    return v_inner.clone();
                } else {
                    return val;
                }
            }
        } else if self.program[self.pointer] == 0x02 {
            self.pointer += 1;
            let arr_id_name = self.extract_str();
            let index = self.resolve_expr();
            if index.typ == 7 {
                let indexed = self.ctx.find_val_globally(arr_id_name);
                if indexed.typ == 11 {
                    let refer = indexed.as_refer();
                    let val = refer.borrow_mut();
                    if val.typ == 7 {
                        let mut obj = val.as_object();
                        if assign {
                            obj.data.data.insert(index.as_string(), data);
                        }
                        return obj.data.data.get(&index.as_string()).unwrap().clone();
                    } else {
                        panic!("elpian error: non object value can not be indexed by string");
                    }
                } else {
                    panic!("elpian error: non reference value can not be indexed");
                }
            }
        }
        Val {
            typ: 0,
            data: Rc::new(RefCell::new(Box::new(0))),
        }
    }
    fn resolve_expr(&mut self) -> Val {
        self.resolve_expr_and_assign(
            false,
            Val {
                typ: 0,
                data: Rc::new(RefCell::new(Box::new(0))),
            },
        )
    }
    fn assign(&mut self, id_name: String, val: Val) {
        self.ctx.put_val_globally(id_name, val);
    }

    pub fn run_from(&mut self, start: usize, end: usize) -> Val {
        self.pointer = start;
        loop {
            if self.pointer == end {
                break;
            }
            let unit: u8 = self.program[self.pointer];
            self.pointer += 1;
            match unit {
                0x01 => {
                    if self.program[self.pointer] == 0x01 {
                        self.pointer += 1;
                        let var_name = self.extract_str();
                        let data = self.resolve_expr();
                        self.assign(var_name, data);
                    } else if self.program[self.pointer] == 0x02 {
                        self.pointer += 1;
                        let arr_id_name = self.extract_str();
                        let index = self.resolve_expr();
                        let data = self.resolve_expr();
                        if index.typ == 7 {
                            let indexed = self.ctx.find_val_globally(arr_id_name);
                            if indexed.typ == 11 {
                                let refer = indexed.as_refer();
                                let val = refer.borrow_mut();
                                if val.typ == 7 {
                                    let mut obj = val.as_object();
                                    obj.data.data.insert(index.as_string(), data);
                                    return obj.data.data.get(&index.as_string()).unwrap().clone();
                                } else {
                                    panic!(
                                        "elpian error: non object value can not be indexed by string"
                                    );
                                }
                            } else {
                                panic!("elpian error: non reference value can not be indexed");
                            }
                        }
                    }
                }
                _ => {}
            }
        }
        Val::new(0, Rc::new(RefCell::new(Box::new(0))))
    }
}
