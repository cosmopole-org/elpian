//! wasm-bindgen API used by the Flutter web loader.

use serde_json::json;
use wasm_bindgen::prelude::*;

use super::{
    continue_execution, create_vm_from_ast, create_vm_from_bytecode, create_vm_from_code,
    deliver_host_message, destroy_vm, execute_vm, execute_vm_func, execute_vm_func_with_input,
    init_vm_system, validate_ast, vm_exists, VmExecResult,
};

fn result_json(result: VmExecResult) -> String {
    json!({
        "hasHostCall": result.has_host_call,
        "hostCallData": result.host_call_data,
        "resultValue": result.result_value,
    })
    .to_string()
}

#[wasm_bindgen]
pub fn elpian_wasm_init() {
    init_vm_system();
}

#[wasm_bindgen]
pub fn elpian_wasm_create_vm_from_ast(machine_id: String, ast_json: String) -> bool {
    create_vm_from_ast(machine_id, ast_json)
}

#[wasm_bindgen]
pub fn elpian_wasm_create_vm_from_code(machine_id: String, code: String) -> bool {
    create_vm_from_code(machine_id, code)
}

#[wasm_bindgen]
pub fn elpian_wasm_create_vm_from_bytecode(machine_id: String, bytecode: &[u8]) -> bool {
    create_vm_from_bytecode(machine_id, bytecode.to_vec())
}

#[wasm_bindgen]
pub fn elpian_wasm_validate_ast(ast_json: String) -> bool {
    validate_ast(ast_json)
}

#[wasm_bindgen]
pub fn elpian_wasm_execute(machine_id: String) -> String {
    result_json(execute_vm(machine_id))
}

#[wasm_bindgen]
pub fn elpian_wasm_execute_func(machine_id: String, name: String, cb_id: i32) -> String {
    result_json(execute_vm_func(machine_id, name, cb_id as i64))
}

#[wasm_bindgen]
pub fn elpian_wasm_execute_func_with_input(
    machine_id: String,
    name: String,
    input_json: String,
    cb_id: i32,
) -> String {
    result_json(execute_vm_func_with_input(
        machine_id,
        name,
        input_json,
        cb_id as i64,
    ))
}

#[wasm_bindgen]
pub fn elpian_wasm_continue_execution(machine_id: String, input_json: String) -> String {
    result_json(continue_execution(machine_id, input_json))
}

#[wasm_bindgen]
pub fn elpian_wasm_deliver_host_message(
    machine_id: String,
    message_json: String,
    cb_id: i32,
) -> String {
    result_json(deliver_host_message(machine_id, message_json, cb_id as i64))
}

#[wasm_bindgen]
pub fn elpian_wasm_destroy_vm(machine_id: String) -> bool {
    destroy_vm(machine_id)
}

#[wasm_bindgen]
pub fn elpian_wasm_vm_exists(machine_id: String) -> bool {
    vm_exists(machine_id)
}
