//! wasm-bindgen API used by the Flutter web loader.
//!
//! The executor remains an rlib in `elpian-vm`; this adapter alone owns the
//! browser cdylib so its output cannot collide with `elpian-ffi`'s native
//! `libelpian_vm` artifact.

use elpian_vm::api::govern;
use elpian_vm::api::{
    continue_execution, create_vm_from_ast, create_vm_from_bytecode, create_vm_from_code,
    deliver_host_message, destroy_vm, execute_vm, execute_vm_func, execute_vm_func_with_input,
    init_vm_system, validate_ast, vm_exists, VmExecResult,
};
use serde_json::json;
use wasm_bindgen::prelude::*;

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

// The twin of the C ABI's governance surface, so a mini app running on the web
// is governed exactly as it is natively. Everything crosses as JSON strings.
macro_rules! wasm_govern {
    ($name:ident, $call:path) => {
        #[wasm_bindgen]
        pub fn $name(machine_id: String) -> String {
            $call(&machine_id).to_string()
        }
    };
}

wasm_govern!(elpian_wasm_limits, govern::limits_json);
wasm_govern!(elpian_wasm_usage, govern::usage_json);
wasm_govern!(elpian_wasm_subtree_usage, govern::subtree_usage_json);
wasm_govern!(
    elpian_wasm_local_capabilities,
    govern::local_capabilities_json
);
wasm_govern!(
    elpian_wasm_effective_capabilities,
    govern::effective_capabilities_json
);
wasm_govern!(elpian_wasm_state, govern::state_json);
wasm_govern!(elpian_wasm_pause, govern::pause_json);
wasm_govern!(elpian_wasm_resume, govern::resume_json);
wasm_govern!(elpian_wasm_terminate, govern::terminate_json);
wasm_govern!(elpian_wasm_tree, govern::tree_json);
wasm_govern!(elpian_wasm_terminate_tree, govern::terminate_tree_json);
wasm_govern!(elpian_wasm_pause_tree, govern::pause_tree_json);
wasm_govern!(elpian_wasm_destroy_tree, govern::destroy_tree_json);
wasm_govern!(elpian_wasm_snapshot, govern::snapshot_json);

#[wasm_bindgen]
pub fn elpian_wasm_set_limits(machine_id: String, limits_json: String) -> String {
    govern::set_limits_json(&machine_id, &limits_json).to_string()
}

#[wasm_bindgen]
pub fn elpian_wasm_set_capability(machine_id: String, capability: String, allowed: bool) -> String {
    govern::set_capability_json(&machine_id, &capability, allowed).to_string()
}

#[wasm_bindgen]
pub fn elpian_wasm_set_capabilities(machine_id: String, caps_json: String) -> String {
    govern::set_capabilities_json(&machine_id, &caps_json).to_string()
}

#[wasm_bindgen]
pub fn elpian_wasm_sandbox_capabilities(machine_id: String, granted_json: String) -> String {
    govern::sandbox_capabilities_json(&machine_id, &granted_json).to_string()
}

#[wasm_bindgen]
pub fn elpian_wasm_capability_allows(machine_id: String, api_name: String) -> String {
    govern::capability_allows_json(&machine_id, &api_name).to_string()
}

#[wasm_bindgen]
pub fn elpian_wasm_charge_storage(machine_id: String, delta: i32) -> String {
    govern::charge_storage_json(&machine_id, delta as i64).to_string()
}

#[wasm_bindgen]
pub fn elpian_wasm_adopt(parent_id: String, child_id: String) -> String {
    govern::adopt_json(&parent_id, &child_id).to_string()
}

#[wasm_bindgen]
pub fn elpian_wasm_enforce_tree_budgets() -> String {
    govern::enforce_tree_budgets_json().to_string()
}
