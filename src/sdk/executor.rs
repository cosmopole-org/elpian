use crate::sdk::{
    context::Context,
    data::{Array, Function, Object, Val, ValGroup},
};
use core::panic;
use std::{
    cell::RefCell,
    collections::HashMap,
    i16,
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
                                let result = ex.run_from(func.start, func.end);
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
                        let mut val2 = arg2.as_array();
                        val2.data.insert(0, arg1);
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
                        let val2 = arg2.as_object().stringify();
                        val1 = val1.replace(&val2, "");
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(val1))),
                        }
                    }
                    9 => {
                        let val2 = arg2.as_array().stringify();
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
                let mut val1 = arg1.as_object();
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
                        let mut val1_temp = val1.stringify();
                        let val2 = arg2.as_string();
                        val1_temp = val1_temp.replace(&val2, "");
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(val1_temp))),
                        }
                    }
                    8 => {
                        let val2 = arg2.as_object();
                        val2.data.data.iter().for_each(|(k, v)| {
                            if val1.data.data.contains_key(k) {
                                let v2 = val1.data.data.get(k).unwrap();
                                if v.typ == v2.typ {
                                    if match v.typ {
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
                                    } {
                                        val1.data.data.remove(&k.clone());
                                    }
                                }
                            }
                        });
                        Val {
                            typ: 8,
                            data: Rc::new(RefCell::new(Box::new(val2))),
                        }
                    }
                    9 => {
                        let mut val2 = arg2.as_array();
                        val2.data.insert(0, arg1);
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
            9 => {
                let mut val1 = arg1.as_array();
                match arg2.typ {
                    1 | 2 | 3 | 4 | 5 | 6 | 8 => {
                        val1.data.push(arg2);
                        Val {
                            typ: 9,
                            data: Rc::new(RefCell::new(Box::new(val1))),
                        }
                    }
                    7 => {
                        let val1_temp = val1.stringify();
                        let val2 = arg2.as_string();
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(format!("{}{}", val1_temp, val2)))),
                        }
                    }
                    9 => {
                        let mut val2 = arg2.as_array();
                        val1.data.append(&mut val2.data);
                        Val {
                            typ: 9,
                            data: Rc::new(RefCell::new(Box::new(val1))),
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
            10 => {
                panic!("function can not be summed with anything");
            }
            _ => {
                panic!("can not sum unknown type with anything");
            }
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
                        let mut val2 = arg2.as_array();
                        val2.data.insert(0, arg1);
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
                        let mut val2 = arg2.as_array();
                        val2.data.insert(0, arg1);
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
                        let mut val2 = arg2.as_array();
                        val2.data.insert(0, arg1);
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
                        let val2 = arg2.as_object().stringify();
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(format!("{}{}", val1, val2)))),
                        }
                    }
                    9 => {
                        let val2 = arg2.as_array().stringify();
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
                let mut val1 = arg1.as_object();
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
                        let val1_temp = val1.stringify();
                        let val2 = arg2.as_string();
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(format!("{}{}", val1_temp, val2)))),
                        }
                    }
                    8 => {
                        let val2 = arg2.as_object();
                        val2.data.data.iter().for_each(|(k, v)| {
                            val1.data.data.insert(k.clone(), v.clone());
                        });
                        Val {
                            typ: 8,
                            data: Rc::new(RefCell::new(Box::new(val2))),
                        }
                    }
                    9 => {
                        let mut val2 = arg2.as_array();
                        val2.data.insert(0, arg1);
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
                let mut val1 = arg1.as_array();
                match arg2.typ {
                    1 | 2 | 3 | 4 | 5 | 6 | 8 => {
                        val1.data.push(arg2);
                        Val {
                            typ: 9,
                            data: Rc::new(RefCell::new(Box::new(val1))),
                        }
                    }
                    7 => {
                        let val1_temp = val1.stringify();
                        let val2 = arg2.as_string();
                        Val {
                            typ: 7,
                            data: Rc::new(RefCell::new(Box::new(format!("{}{}", val1_temp, val2)))),
                        }
                    }
                    9 => {
                        let mut val2 = arg2.as_array();
                        val1.data.append(&mut val2.data);
                        Val {
                            typ: 9,
                            data: Rc::new(RefCell::new(Box::new(val1))),
                        }
                    }
                    10 => {
                        panic!("elpian error: function and array can not be summed");
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
    fn resolve_expr(&mut self) -> Val {
        if self.program[self.pointer] == 0x0c {
            self.pointer += 1;
            let indexed_id_name = self.extract_str();
            let indexed = self.ctx.find_val_globally(indexed_id_name);
            let index = self.resolve_expr();
            if index.typ == 7 {
                if indexed.typ == 11 {
                    let refer = indexed.as_refer();
                    let val = refer.borrow_mut();
                    if val.typ == 8 {
                        let obj = val.as_object();
                        return obj.data.data.get(&index.as_string()).unwrap().clone();
                    } else {
                        panic!("elpian error: non object value can not be indexed by string");
                    }
                } else {
                    panic!("elpian error: non reference value can not be indexed");
                }
            } else if index.typ >= 1 && index.typ <= 3 {
                if indexed.typ == 10 {
                    let refer = indexed.as_refer();
                    let val = refer.borrow_mut();
                    if val.typ == 9 {
                        let arr = val.as_array();
                        if index.typ == 1 {
                            return arr.data.get(index.as_i16() as usize).unwrap().clone();
                        } else if index.typ == 2 {
                            return arr.data.get(index.as_i32() as usize).unwrap().clone();
                        } else {
                            return arr.data.get(index.as_i64() as usize).unwrap().clone();
                        }
                    } else {
                        panic!("elpian error: non object value can not be indexed by string");
                    }
                } else {
                    panic!("elpian error: non reference value can not be indexed");
                }
            } else {
                panic!(
                    "elpian error: types other than integer and string can not be used to index anything"
                );
            }
        } else if self.program[self.pointer] == 0x10 {
            self.pointer += 1;
            let arg1 = self.resolve_expr();
            let arg2 = self.resolve_expr();
            return self.operate_sum(arg1, arg2);
        } else {
            let val = self.extract_val();
            if val.typ == 11 {
                let v = val.as_refer();
                let v_inner = v.borrow();
                return v_inner.clone();
            } else {
                return val;
            }
        }
    }
    fn define(&mut self, id_name: String, val: Val) {
        self.ctx.define_val_globally(id_name, val);
    }
    fn assign(&mut self, id_name: String, val: Val) {
        self.ctx.update_val_globally(id_name, val);
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
                    if self.program[self.pointer] == 0x0b {
                        self.pointer += 1;
                        let var_name = self.extract_str();
                        let data = self.resolve_expr();
                        self.define(var_name, data);
                    }
                }
                0x02 => {
                    if self.program[self.pointer] == 0x0c {
                        self.pointer += 1;
                        let indexed_id_name = self.extract_str();
                        let indexed = self.ctx.find_val_globally(indexed_id_name);
                        let index = self.resolve_expr();
                        let data = self.resolve_expr();
                        if index.typ == 7 {
                            if indexed.typ == 11 {
                                let refer = indexed.as_refer();
                                let val = refer.borrow_mut();
                                if val.typ == 8 {
                                    let mut obj = val.as_object();
                                    obj.data.data.insert(index.as_string(), data);
                                } else {
                                    panic!(
                                        "elpian error: non object value can not be indexed by string"
                                    );
                                }
                            } else {
                                panic!("elpian error: non reference value can not be indexed");
                            }
                        } else if index.typ >= 1 && index.typ <= 3 {
                            if indexed.typ == 10 {
                                let refer = indexed.as_refer();
                                let val = refer.borrow_mut();
                                if val.typ == 9 {
                                    let mut arr = val.as_array();
                                    if index.typ == 1 {
                                        arr.data[index.as_i16() as usize] = data;
                                    } else if index.typ == 2 {
                                        arr.data[index.as_i32() as usize] = data;
                                    } else {
                                        arr.data[index.as_i64() as usize] = data;
                                    }
                                } else {
                                    panic!(
                                        "elpian error: non object value can not be indexed by string"
                                    );
                                }
                            } else {
                                panic!("elpian error: non reference value can not be indexed");
                            }
                        } else {
                            panic!(
                                "elpian error: types other than integer and string can not be used to index anything"
                            );
                        }
                    } else if self.program[self.pointer] == 0x0b {
                        self.pointer += 1;
                        let var_name = self.extract_str();
                        let data = self.resolve_expr();
                        self.assign(var_name, data);
                    }
                }
                _ => {}
            }
        }
        Val::new(0, Rc::new(RefCell::new(Box::new(0))))
    }
}
