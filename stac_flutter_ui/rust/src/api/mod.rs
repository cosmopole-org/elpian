pub mod ffi;
pub mod wasm_ffi;

use std::collections::HashMap;
use std::sync::Mutex;

use once_cell::sync::Lazy;
use serde_json::{Value, json};

use crate::sdk::compiler;
use crate::sdk::vm::VM;

// Thread-safe VM storage for FRB
static VMS: Lazy<Mutex<HashMap<String, VM>>> = Lazy::new(|| Mutex::new(HashMap::new()));

/// Result of a VM execution step.
/// When the VM needs to call a host function, it pauses and returns
/// the host call data as JSON. The Dart side processes it and calls
/// `continue_execution` with the result.
#[derive(Debug, Clone)]
pub struct VmExecResult {
    /// Whether the VM is paused waiting for a host call response
    pub has_host_call: bool,
    /// JSON string of the host call request: {"machineId", "apiName", "payload"}
    pub host_call_data: String,
    /// Stringified result value (only meaningful when has_host_call is false)
    pub result_value: String,
}

/// Initialize the VM subsystem. Call once at app startup.
pub fn init_vm_system() {
    // Force initialization of the lazy static
    drop(VMS.lock().unwrap());
}

/// Create a new VM instance from an AST JSON string.
///
/// The AST follows the Elpian compiler format with node types like
/// "program", "definition", "assignment", "functionCall", etc.
pub fn create_vm_from_ast(machine_id: String, ast_json: String) -> bool {
    let ast_obj: Value = match serde_json::from_str(&ast_json) {
        Ok(v) => v,
        Err(_) => return false,
    };
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
    let mut vms = VMS.lock().unwrap();
    vms.insert(machine_id, vm);
    true
}

/// Create a new VM instance from source code string.
pub fn create_vm_from_code(machine_id: String, code: String) -> bool {
    let vm = VM::compile_and_create_of_code(
        machine_id.clone(),
        code,
        1,
        vec![
            "println".to_string(),
            "stringify".to_string(),
            "render".to_string(),
            "updateApp".to_string(),
        ],
    );
    let mut vms = VMS.lock().unwrap();
    vms.insert(machine_id, vm);
    true
}

/// Validate an AST JSON string without creating a VM.
pub fn validate_ast(ast_json: String) -> bool {
    let ast_obj: Value = match serde_json::from_str(&ast_json) {
        Ok(v) => v,
        Err(_) => return false,
    };
    compiler::compile_ast(ast_obj, 0);
    true
}

/// Compile source code to AST JSON (for debugging/inspection).
pub fn compile_code_to_ast(code: String) -> String {
    let bytecode = compiler::compile_code(code);
    json!({ "bytecodeLength": bytecode.len() }).to_string()
}

/// Execute the main program of a VM.
/// Returns a VmExecResult indicating either completion or a pending host call.
pub fn execute_vm(machine_id: String) -> VmExecResult {
    let mut vms = VMS.lock().unwrap();
    if let Some(vm) = vms.get_mut(&machine_id) {
        if vm.is_exec_processing() {
            return VmExecResult {
                has_host_call: false,
                host_call_data: String::new(),
                result_value: "\"vm_busy\"".to_string(),
            };
        }
        vm.run();
        if let Some(ref hcd) = vm.sending_host_call_data {
            let data = hcd.clone();
            vm.sending_host_call_data = None;
            return VmExecResult {
                has_host_call: true,
                host_call_data: data,
                result_value: String::new(),
            };
        }
        VmExecResult {
            has_host_call: false,
            host_call_data: String::new(),
            result_value: "\"done\"".to_string(),
        }
    } else {
        VmExecResult {
            has_host_call: false,
            host_call_data: String::new(),
            result_value: "\"vm_not_found\"".to_string(),
        }
    }
}

/// Execute a named function in the VM.
pub fn execute_vm_func(machine_id: String, func_name: String, cb_id: i64) -> VmExecResult {
    let mut vms = VMS.lock().unwrap();
    if let Some(vm) = vms.get_mut(&machine_id) {
        if vm.is_exec_processing() {
            return VmExecResult {
                has_host_call: false,
                host_call_data: String::new(),
                result_value: "\"vm_busy\"".to_string(),
            };
        }
        let res = vm.run_func_with_input(&func_name, None, cb_id);
        if let Some(ref hcd) = vm.sending_host_call_data {
            let data = hcd.clone();
            vm.sending_host_call_data = None;
            return VmExecResult {
                has_host_call: true,
                host_call_data: data,
                result_value: String::new(),
            };
        }
        VmExecResult {
            has_host_call: false,
            host_call_data: String::new(),
            result_value: res.stringify(),
        }
    } else {
        VmExecResult {
            has_host_call: false,
            host_call_data: String::new(),
            result_value: "\"vm_not_found\"".to_string(),
        }
    }
}

/// Execute a named function with JSON input in the VM.
pub fn execute_vm_func_with_input(
    machine_id: String,
    func_name: String,
    input_json: String,
    cb_id: i64,
) -> VmExecResult {
    let mut vms = VMS.lock().unwrap();
    if let Some(vm) = vms.get_mut(&machine_id) {
        if vm.is_exec_processing() {
            return VmExecResult {
                has_host_call: false,
                host_call_data: String::new(),
                result_value: "\"vm_busy\"".to_string(),
            };
        }
        let res = vm.run_func_with_input(&func_name, Some(&input_json), cb_id);
        if let Some(ref hcd) = vm.sending_host_call_data {
            let data = hcd.clone();
            vm.sending_host_call_data = None;
            return VmExecResult {
                has_host_call: true,
                host_call_data: data,
                result_value: String::new(),
            };
        }
        VmExecResult {
            has_host_call: false,
            host_call_data: String::new(),
            result_value: res.stringify(),
        }
    } else {
        VmExecResult {
            has_host_call: false,
            host_call_data: String::new(),
            result_value: "\"vm_not_found\"".to_string(),
        }
    }
}

/// Continue VM execution after a host call response.
/// The input_json should be a typed value like {"type":"string","data":{"value":"hello"}}
pub fn continue_execution(machine_id: String, input_json: String) -> VmExecResult {
    let mut vms = VMS.lock().unwrap();
    if let Some(vm) = vms.get_mut(&machine_id) {
        vm.continue_run(input_json);
        if let Some(ref hcd) = vm.sending_host_call_data {
            let data = hcd.clone();
            vm.sending_host_call_data = None;
            return VmExecResult {
                has_host_call: true,
                host_call_data: data,
                result_value: String::new(),
            };
        }
        VmExecResult {
            has_host_call: false,
            host_call_data: String::new(),
            result_value: "\"done\"".to_string(),
        }
    } else {
        VmExecResult {
            has_host_call: false,
            host_call_data: String::new(),
            result_value: "\"vm_not_found\"".to_string(),
        }
    }
}

/// Destroy a VM instance and free its resources.
pub fn destroy_vm(machine_id: String) -> bool {
    let mut vms = VMS.lock().unwrap();
    vms.remove(&machine_id).is_some()
}

/// Check if a VM exists.
pub fn vm_exists(machine_id: String) -> bool {
    let vms = VMS.lock().unwrap();
    vms.contains_key(&machine_id)
}
