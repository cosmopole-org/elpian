use std::collections::HashMap;
use std::sync::{Arc, Condvar, Mutex};

use crate::sdk::compiler;
use crate::sdk::vm::VM;
use serde_json::Value;
use wasm_bindgen::prelude::wasm_bindgen;

static mut VMS: Option<HashMap<String, VM>> = None;
static mut TASKS: Option<HashMap<String, Vec<Arc<(Mutex<bool>, Condvar)>>>> = None;

#[wasm_bindgen]
extern "C" {
    #[wasm_bindgen(js_namespace = console)]
    fn log(s: &str);

    #[wasm_bindgen(js_namespace = console, js_name = log)]
    fn log_u32(a: u32);

    #[wasm_bindgen(js_namespace = console, js_name = log)]
    fn log_many(a: &str, b: &str);

    #[wasm_bindgen(js_namespace = env, js_name = ask_host)]
    fn ask_host(payload: String) -> String;
}

#[wasm_bindgen]
pub fn create_vm(machine_id: String, ast: String) {
    let ast_obj: Value = serde_json::from_str(&ast).unwrap();
    let vm = VM::compile_and_create_of_ast(
        machine_id.clone(),
        ast_obj,
        1,
        vec![
            "println".to_string(),
            "stringify".to_string(),
            "render".to_string(),
            "updateApp".to_string(),
        ],
    );
    unsafe {
        if let Some(ref mut map) = VMS {
            map.insert(machine_id.clone(), vm);
        }
        if let Some(ref mut map) = TASKS {
            map.insert(machine_id.clone(), vec![]);
        }
    }
}

#[wasm_bindgen]
pub fn validate_ast(ast: String) {
    let ast_obj: Value = serde_json::from_str(&ast).unwrap();
    compiler::compile_ast(ast_obj, 0);
}

#[wasm_bindgen]
pub fn compile_code(code: String) {
    compiler::compile_code(code);
}

#[wasm_bindgen]
pub fn execute(machine_id: String) {
    unsafe {
        if let Some(ref mut map) = VMS {
            let vm = map.get_mut(&machine_id.clone()).unwrap();
            if !vm.is_exec_processing() {
                vm.run();
                if !vm.sending_host_call_data.is_none() {
                    let shcd = vm.sending_host_call_data.clone().unwrap();
                    vm.sending_host_call_data = None;
                    ask_host(shcd);
                }
                if let Some(ref mut tasks_map) = TASKS {
                    let ts = tasks_map.get_mut(&machine_id.clone()).unwrap();
                    if !ts.is_empty() {
                        let task = ts.remove(0);
                        let lock = &task.0;
                        // let cv = &task.1;
                        let mut _started = lock.lock().unwrap();
                        *_started = true;
                        // cv.notify_one();
                    }
                }
            } else {
                if let Some(ref mut tasks_map) = TASKS {
                    let ts = tasks_map.get_mut(&machine_id.clone()).unwrap();
                    let cv = Condvar::new();
                    let mg: Mutex<bool> = Mutex::new(false);
                    let a = Arc::new((mg, cv));
                    ts.push(a.clone());
                    let _started = a.0.lock().unwrap();
                    // let _u = a.clone().1.wait(_started).unwrap();
                    // vm.run();
                    // if (!vm.sending_host_call_data.is_none()) {
                    //     let shcd = vm.sending_host_call_data.clone().unwrap();
                    //     vm.sending_host_call_data = None;
                    //     ask_host(shcd);
                    // }
                }
            }
        }
    }
}

#[wasm_bindgen]
pub fn execute_func(machine_id: String, func_name: String, cb_id: i64) -> String {
    unsafe {
        if let Some(ref mut map) = VMS {
            let vm = map.get_mut(&machine_id.clone()).unwrap();
            if !vm.is_exec_processing() {
                let vm = map.get_mut(&machine_id.clone()).unwrap();
                let res = vm.run_func_with_input(&func_name.clone(), None, cb_id);
                if !vm.sending_host_call_data.is_none() {
                    let shcd = vm.sending_host_call_data.clone().unwrap();
                    vm.sending_host_call_data = None;
                    ask_host(shcd);
                }
                if let Some(ref mut tasks_map) = TASKS {
                    let ts = tasks_map.get_mut(&machine_id.clone()).unwrap();
                    if !ts.is_empty() {
                        let task = ts.remove(0);
                        let lock = &task.0;
                        // let cv = &task.1;
                        let mut _started = lock.lock().unwrap();
                        *_started = true;
                        // cv.notify_one();
                    }
                }
                return res.stringify();
            } else {
                if let Some(ref mut tasks_map) = TASKS {
                    let ts = tasks_map.get_mut(&machine_id.clone()).unwrap();
                    let cv = Condvar::new();
                    let mg: Mutex<bool> = Mutex::new(false);
                    let a = Arc::new((mg, cv));
                    ts.push(a.clone());
                    let _started = a.0.lock().unwrap();
                    // let _u = a.clone().1.wait(_started).unwrap();
                    // let vm = map.get_mut(&machine_id.clone()).unwrap();
                    // let res = vm.run_func_with_input(&func_name.clone(), None, cb_id);
                    // if (!vm.sending_host_call_data.is_none()) {
                    //     let shcd = vm.sending_host_call_data.clone().unwrap();
                    //     vm.sending_host_call_data = None;
                    //     ask_host(shcd);
                    // }
                    // return res.stringify();
                    return "{}".to_string();
                } else {
                    return "{}".to_string();
                }
            }
        } else {
            return "{}".to_string();
        }
    }
}

#[wasm_bindgen]
pub fn execute_func_with_input(
    machine_id: String,
    func_name: String,
    input: String,
    cb_id: i64,
) -> String {
    unsafe {
        if let Some(ref mut map) = VMS {
            let vm = map.get_mut(&machine_id.clone()).unwrap();
            if !vm.is_exec_processing() {
                let vm = map.get_mut(&machine_id.clone()).unwrap();
                let res = vm.run_func_with_input(&func_name.clone(), Some(&input.clone()), cb_id);
                if !vm.sending_host_call_data.is_none() {
                    let shcd = vm.sending_host_call_data.clone().unwrap();
                    vm.sending_host_call_data = None;
                    ask_host(shcd);
                }
                if let Some(ref mut tasks_map) = TASKS {
                    let ts = tasks_map.get_mut(&machine_id.clone()).unwrap();
                    if !ts.is_empty() {
                        let task = ts.remove(0);
                        let lock = &task.0;
                        // let cv = &task.1;
                        let mut _started = lock.lock().unwrap();
                        *_started = true;
                        // cv.notify_one();
                    }
                }
                return res.stringify();
            } else {
                if let Some(ref mut tasks_map) = TASKS {
                    let ts = tasks_map.get_mut(&machine_id.clone()).unwrap();
                    let cv = Condvar::new();
                    let mg: Mutex<bool> = Mutex::new(false);
                    let a = Arc::new((mg, cv));
                    ts.push(a.clone());
                    let _started = a.0.lock().unwrap();
                    // let _u = a.clone().1.wait(_started).unwrap();
                    // let vm = map.get_mut(&machine_id.clone()).unwrap();
                    // let res =
                    //     vm.run_func_with_input(&func_name.clone(), Some(&input.clone()), cb_id);
                    // if (!vm.sending_host_call_data.is_none()) {
                    //     let shcd = vm.sending_host_call_data.clone().unwrap();
                    //     vm.sending_host_call_data = None;
                    //     ask_host(shcd);
                    // }
                    // return res.stringify();
                    return "{}".to_string();
                } else {
                    return "{}".to_string();
                }
            }
        } else {
            return "{}".to_string();
        }
    }
}

#[wasm_bindgen]
pub fn continue_exec_with_host_res(machine_id: String, input: String) {
    unsafe {
        if let Some(ref mut map) = VMS {
            let vm = map.get_mut(&machine_id.clone()).unwrap();
            vm.continue_run(input.clone());
            if !vm.sending_host_call_data.is_none() {
                let shcd = vm.sending_host_call_data.clone().unwrap();
                vm.sending_host_call_data = None;
                ask_host(shcd);
            }
        }
    }
}

pub fn init_app() {
    // Default utilities - feel free to customize
    unsafe {
        VMS = Some(HashMap::new());
        TASKS = Some(HashMap::new());
    }
}
