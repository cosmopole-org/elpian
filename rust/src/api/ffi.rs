/// FFI layer that exposes the VM API as C-compatible functions
/// for dart:ffi on native platforms.
///
/// All functions use C strings (null-terminated UTF-8) for data exchange.
/// The VmExecResult is serialized as JSON across the boundary.
///
/// Memory: Strings returned from Rust must be freed by calling `elpian_free_string`.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use serde_json::json;

use super::{
    continue_execution, create_vm_from_ast, create_vm_from_code, destroy_vm, execute_vm,
    execute_vm_func, execute_vm_func_with_input, init_vm_system, validate_ast, vm_exists,
    VmExecResult,
};

/// Helper: convert C string pointer to Rust String.
unsafe fn c_str_to_string(ptr: *const c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    CStr::from_ptr(ptr).to_string_lossy().into_owned()
}

/// Helper: convert Rust String to C string pointer.
/// Caller must free with `elpian_free_string`.
fn string_to_c_str(s: String) -> *mut c_char {
    CString::new(s).unwrap_or_default().into_raw()
}

/// Helper: serialize VmExecResult to JSON C string.
fn result_to_c_str(r: VmExecResult) -> *mut c_char {
    let json = json!({
        "hasHostCall": r.has_host_call,
        "hostCallData": r.host_call_data,
        "resultValue": r.result_value,
    });
    string_to_c_str(json.to_string())
}

// ── Public FFI Functions ────────────────────────────────────────────

/// Free a string previously returned by any elpian_* function.
#[unsafe(no_mangle)]
pub extern "C" fn elpian_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            drop(CString::from_raw(ptr));
        }
    }
}

/// Initialize the VM subsystem.
#[unsafe(no_mangle)]
pub extern "C" fn elpian_init() {
    init_vm_system();
}

/// Create a VM from AST JSON. Returns 1 on success, 0 on failure.
#[unsafe(no_mangle)]
pub extern "C" fn elpian_create_vm_from_ast(
    machine_id: *const c_char,
    ast_json: *const c_char,
) -> i32 {
    let mid = unsafe { c_str_to_string(machine_id) };
    let ast = unsafe { c_str_to_string(ast_json) };
    if create_vm_from_ast(mid, ast) { 1 } else { 0 }
}

/// Create a VM from source code. Returns 1 on success, 0 on failure.
#[unsafe(no_mangle)]
pub extern "C" fn elpian_create_vm_from_code(
    machine_id: *const c_char,
    code: *const c_char,
) -> i32 {
    let mid = unsafe { c_str_to_string(machine_id) };
    let c = unsafe { c_str_to_string(code) };
    if create_vm_from_code(mid, c) { 1 } else { 0 }
}

/// Validate AST JSON. Returns 1 if valid, 0 if not.
#[unsafe(no_mangle)]
pub extern "C" fn elpian_validate_ast(ast_json: *const c_char) -> i32 {
    let ast = unsafe { c_str_to_string(ast_json) };
    if validate_ast(ast) { 1 } else { 0 }
}

/// Execute a VM's main program. Returns JSON string (must be freed).
#[unsafe(no_mangle)]
pub extern "C" fn elpian_execute(machine_id: *const c_char) -> *mut c_char {
    let mid = unsafe { c_str_to_string(machine_id) };
    result_to_c_str(execute_vm(mid))
}

/// Execute a named function. Returns JSON string (must be freed).
#[unsafe(no_mangle)]
pub extern "C" fn elpian_execute_func(
    machine_id: *const c_char,
    func_name: *const c_char,
    cb_id: i64,
) -> *mut c_char {
    let mid = unsafe { c_str_to_string(machine_id) };
    let fname = unsafe { c_str_to_string(func_name) };
    result_to_c_str(execute_vm_func(mid, fname, cb_id))
}

/// Execute a named function with input. Returns JSON string (must be freed).
#[unsafe(no_mangle)]
pub extern "C" fn elpian_execute_func_with_input(
    machine_id: *const c_char,
    func_name: *const c_char,
    input_json: *const c_char,
    cb_id: i64,
) -> *mut c_char {
    let mid = unsafe { c_str_to_string(machine_id) };
    let fname = unsafe { c_str_to_string(func_name) };
    let input = unsafe { c_str_to_string(input_json) };
    result_to_c_str(execute_vm_func_with_input(mid, fname, input, cb_id))
}

/// Continue execution after host call. Returns JSON string (must be freed).
#[unsafe(no_mangle)]
pub extern "C" fn elpian_continue_execution(
    machine_id: *const c_char,
    input_json: *const c_char,
) -> *mut c_char {
    let mid = unsafe { c_str_to_string(machine_id) };
    let input = unsafe { c_str_to_string(input_json) };
    result_to_c_str(continue_execution(mid, input))
}

/// Destroy a VM. Returns 1 if found and destroyed, 0 if not found.
#[unsafe(no_mangle)]
pub extern "C" fn elpian_destroy_vm(machine_id: *const c_char) -> i32 {
    let mid = unsafe { c_str_to_string(machine_id) };
    if destroy_vm(mid) { 1 } else { 0 }
}

/// Check if a VM exists. Returns 1 if exists, 0 if not.
#[unsafe(no_mangle)]
pub extern "C" fn elpian_vm_exists(machine_id: *const c_char) -> i32 {
    let mid = unsafe { c_str_to_string(machine_id) };
    if vm_exists(mid) { 1 } else { 0 }
}
