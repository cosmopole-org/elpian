//! Stable C ABI used by the Flutter engine on native platforms.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use serde_json::json;

use super::{
    continue_execution, create_vm_from_ast, create_vm_from_bytecode, create_vm_from_code,
    deliver_host_message, destroy_vm, execute_vm, execute_vm_func, execute_vm_func_with_input,
    init_vm_system, validate_ast, vm_exists, VmExecResult,
};

unsafe fn read_string(ptr: *const c_char) -> String {
    if ptr.is_null() {
        String::new()
    } else {
        CStr::from_ptr(ptr).to_string_lossy().into_owned()
    }
}

fn return_string(value: String) -> *mut c_char {
    CString::new(value.replace('\0', "")).unwrap().into_raw()
}

fn return_result(result: VmExecResult) -> *mut c_char {
    return_string(
        json!({
            "hasHostCall": result.has_host_call,
            "hostCallData": result.host_call_data,
            "resultValue": result.result_value,
        })
        .to_string(),
    )
}

#[no_mangle]
pub extern "C" fn elpian_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            drop(CString::from_raw(ptr));
        }
    }
}

#[no_mangle]
pub extern "C" fn elpian_init() {
    init_vm_system();
}

#[no_mangle]
pub extern "C" fn elpian_create_vm_from_ast(id: *const c_char, ast: *const c_char) -> i32 {
    bool_to_i32(create_vm_from_ast(unsafe { read_string(id) }, unsafe {
        read_string(ast)
    }))
}

#[no_mangle]
pub extern "C" fn elpian_create_vm_from_code(id: *const c_char, code: *const c_char) -> i32 {
    bool_to_i32(create_vm_from_code(unsafe { read_string(id) }, unsafe {
        read_string(code)
    }))
}

#[no_mangle]
pub extern "C" fn elpian_create_vm_from_bytecode(
    id: *const c_char,
    bytes: *const u8,
    length: usize,
) -> i32 {
    if bytes.is_null() && length != 0 {
        return 0;
    }
    let bytecode = if length == 0 {
        Vec::new()
    } else {
        unsafe { std::slice::from_raw_parts(bytes, length) }.to_vec()
    };
    bool_to_i32(create_vm_from_bytecode(
        unsafe { read_string(id) },
        bytecode,
    ))
}

#[no_mangle]
pub extern "C" fn elpian_validate_ast(ast: *const c_char) -> i32 {
    bool_to_i32(validate_ast(unsafe { read_string(ast) }))
}

#[no_mangle]
pub extern "C" fn elpian_execute(id: *const c_char) -> *mut c_char {
    return_result(execute_vm(unsafe { read_string(id) }))
}

#[no_mangle]
pub extern "C" fn elpian_execute_func(
    id: *const c_char,
    name: *const c_char,
    callback_id: i64,
) -> *mut c_char {
    return_result(execute_vm_func(
        unsafe { read_string(id) },
        unsafe { read_string(name) },
        callback_id,
    ))
}

#[no_mangle]
pub extern "C" fn elpian_execute_func_with_input(
    id: *const c_char,
    name: *const c_char,
    input: *const c_char,
    callback_id: i64,
) -> *mut c_char {
    return_result(execute_vm_func_with_input(
        unsafe { read_string(id) },
        unsafe { read_string(name) },
        unsafe { read_string(input) },
        callback_id,
    ))
}

#[no_mangle]
pub extern "C" fn elpian_continue_execution(
    id: *const c_char,
    input: *const c_char,
) -> *mut c_char {
    return_result(continue_execution(unsafe { read_string(id) }, unsafe {
        read_string(input)
    }))
}

#[no_mangle]
pub extern "C" fn elpian_deliver_host_message(
    id: *const c_char,
    message: *const c_char,
    callback_id: i64,
) -> *mut c_char {
    return_result(deliver_host_message(
        unsafe { read_string(id) },
        unsafe { read_string(message) },
        callback_id,
    ))
}

#[no_mangle]
pub extern "C" fn elpian_destroy_vm(id: *const c_char) -> i32 {
    bool_to_i32(destroy_vm(unsafe { read_string(id) }))
}

#[no_mangle]
pub extern "C" fn elpian_vm_exists(id: *const c_char) -> i32 {
    bool_to_i32(vm_exists(unsafe { read_string(id) }))
}

fn bool_to_i32(value: bool) -> i32 {
    if value {
        1
    } else {
        0
    }
}
