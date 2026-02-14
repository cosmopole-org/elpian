/// WASM FFI layer for web platform.
/// Uses wasm-bindgen to expose the VM API to JavaScript/Dart on web.
#[cfg(target_arch = "wasm32")]
mod wasm {
    use wasm_bindgen::prelude::*;
    use serde_json::json;

    use crate::api::{
        continue_execution, create_vm_from_ast, create_vm_from_code, destroy_vm, execute_vm,
        execute_vm_func, execute_vm_func_with_input, init_vm_system, validate_ast, vm_exists,
        VmExecResult,
    };

    fn result_to_json(r: VmExecResult) -> String {
        json!({
            "hasHostCall": r.has_host_call,
            "hostCallData": r.host_call_data,
            "resultValue": r.result_value,
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
    pub fn elpian_wasm_validate_ast(ast_json: String) -> bool {
        validate_ast(ast_json)
    }

    #[wasm_bindgen]
    pub fn elpian_wasm_execute(machine_id: String) -> String {
        result_to_json(execute_vm(machine_id))
    }

    #[wasm_bindgen]
    pub fn elpian_wasm_execute_func(machine_id: String, func_name: String, cb_id: i64) -> String {
        result_to_json(execute_vm_func(machine_id, func_name, cb_id))
    }

    #[wasm_bindgen]
    pub fn elpian_wasm_execute_func_with_input(
        machine_id: String,
        func_name: String,
        input_json: String,
        cb_id: i64,
    ) -> String {
        result_to_json(execute_vm_func_with_input(machine_id, func_name, input_json, cb_id))
    }

    #[wasm_bindgen]
    pub fn elpian_wasm_continue_execution(machine_id: String, input_json: String) -> String {
        result_to_json(continue_execution(machine_id, input_json))
    }

    #[wasm_bindgen]
    pub fn elpian_wasm_destroy_vm(machine_id: String) -> bool {
        destroy_vm(machine_id)
    }

    #[wasm_bindgen]
    pub fn elpian_wasm_vm_exists(machine_id: String) -> bool {
        vm_exists(machine_id)
    }
}
