//! Stable C ABI used by the Flutter engine on native platforms.
//!
//! # Panic containment
//!
//! Every exported function is a boundary between Rust and a foreign caller,
//! and the Elpian executor panics on guest faults — a mini app evaluating
//! `{} - 1` raises `"object and integer can not be subtracted"` as a `panic!`,
//! not as a trap. Letting that unwind out of an `extern "C"` frame is
//! undefined behaviour, and in practice aborts the whole host application: an
//! untrusted mini app could kill the app it runs inside with a type error.
//!
//! So every body here runs inside [`guard`], which catches the unwind, records
//! the reason in a thread-local slot readable via [`elpian_last_error`], and
//! returns a well-formed failure value to the caller. A guest fault stays a
//! guest fault.
//!
//! # Safety
//!
//! The functions taking `*const c_char` are `unsafe` because they dereference
//! pointers the caller supplies. The contract for every one of them is:
//!
//! * each pointer is either NULL (read as the empty string) or points at a
//!   NUL-terminated byte string that stays valid for the duration of the call;
//! * `elpian_create_vm_from_bytecode`'s `bytes`/`length` pair describes a
//!   readable region, or `bytes` is NULL and `length` is 0;
//! * every `*mut c_char` returned is owned by the caller and must be released
//!   with [`elpian_free_string`], exactly once.
//!
//! Marking them `unsafe` does not change the emitted symbol or the ABI, so the
//! Dart bindings are unaffected.

use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};

use serde_json::json;

use super::{
    continue_execution, create_vm_from_ast, create_vm_from_bytecode, create_vm_from_code,
    deliver_host_message, destroy_vm, execute_vm, execute_vm_func, execute_vm_func_with_input,
    init_vm_system, validate_ast, vm_exists, VmExecResult,
};

thread_local! {
    /// The reason the most recent call on this thread failed, as a C string.
    /// Empty when the last call succeeded.
    static LAST_ERROR: RefCell<CString> = RefCell::new(CString::default());
}

fn set_last_error(message: &str) {
    let c = CString::new(message.replace('\0', " ")).unwrap_or_default();
    LAST_ERROR.with(|e| *e.borrow_mut() = c);
}

fn clear_last_error() {
    LAST_ERROR.with(|e| *e.borrow_mut() = CString::default());
}

/// Extract a readable reason from the payload `panic!` unwound with.
fn panic_message(payload: &(dyn std::any::Any + Send)) -> String {
    if let Some(s) = payload.downcast_ref::<&str>() {
        (*s).to_string()
    } else if let Some(s) = payload.downcast_ref::<String>() {
        s.clone()
    } else {
        "unknown panic payload".to_string()
    }
}

/// Run `body` with unwinding contained.
///
/// On a panic the reason is stored for [`elpian_last_error`] and `on_panic` is
/// returned, so the caller always receives a well-formed value. `AssertUnwindSafe`
/// is sound here for the same reason `lock_tolerant` is (see `crate::api`): the
/// registries hold plain data that stays coherent across an executor unwind,
/// and the offending VM can be destroyed afterwards.
fn guard<T>(what: &str, on_panic: T, body: impl FnOnce() -> T) -> T {
    match catch_unwind(AssertUnwindSafe(body)) {
        Ok(value) => {
            clear_last_error();
            value
        }
        Err(payload) => {
            set_last_error(&format!("{what}: {}", panic_message(payload.as_ref())));
            on_panic
        }
    }
}

/// # Safety
/// `ptr` is NULL or points at a NUL-terminated string valid for this call.
unsafe fn read_string(ptr: *const c_char) -> String {
    if ptr.is_null() {
        String::new()
    } else {
        CStr::from_ptr(ptr).to_string_lossy().into_owned()
    }
}

fn return_string(value: String) -> *mut c_char {
    match CString::new(value.replace('\0', "")) {
        Ok(c) => c.into_raw(),
        // Unreachable — interior NULs were just stripped — but a boundary
        // function must never panic, so fall back to an empty string.
        Err(_) => CString::default().into_raw(),
    }
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

/// The result handed back when a call was stopped by a guest fault. Shaped
/// exactly like a normal completion so the Dart side's parser cannot trip on
/// it; the reason is in [`elpian_last_error`].
fn trapped_result(what: &str) -> *mut c_char {
    return_string(
        json!({
            "hasHostCall": false,
            "hostCallData": "",
            "resultValue": format!("\"elpian: {what} stopped by a guest fault\""),
        })
        .to_string(),
    )
}

/// The reason the most recent call on this thread failed, or an empty string.
///
/// The returned pointer is owned by the library and stays valid until the next
/// call on this thread. Do **not** pass it to [`elpian_free_string`].
#[no_mangle]
pub extern "C" fn elpian_last_error() -> *const c_char {
    LAST_ERROR.with(|e| e.borrow().as_ptr())
}

/// Release a string returned by any of the `*mut c_char` functions here.
///
/// # Safety
/// `ptr` is NULL, or a pointer this library returned and has not yet freed.
#[no_mangle]
pub unsafe extern "C" fn elpian_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}

#[no_mangle]
pub extern "C" fn elpian_init() {
    guard("elpian_init", (), init_vm_system);
}

/// # Safety
/// See the module-level contract.
#[no_mangle]
pub unsafe extern "C" fn elpian_create_vm_from_ast(id: *const c_char, ast: *const c_char) -> i32 {
    let (id, ast) = (read_string(id), read_string(ast));
    guard("elpian_create_vm_from_ast", 0, || {
        bool_to_i32(create_vm_from_ast(id, ast))
    })
}

/// # Safety
/// See the module-level contract.
#[no_mangle]
pub unsafe extern "C" fn elpian_create_vm_from_code(id: *const c_char, code: *const c_char) -> i32 {
    let (id, code) = (read_string(id), read_string(code));
    guard("elpian_create_vm_from_code", 0, || {
        bool_to_i32(create_vm_from_code(id, code))
    })
}

/// # Safety
/// See the module-level contract; `bytes`/`length` must describe a readable
/// region, or `bytes` is NULL and `length` is 0.
#[no_mangle]
pub unsafe extern "C" fn elpian_create_vm_from_bytecode(
    id: *const c_char,
    bytes: *const u8,
    length: usize,
) -> i32 {
    if bytes.is_null() && length != 0 {
        set_last_error("elpian_create_vm_from_bytecode: NULL bytes with non-zero length");
        return 0;
    }
    let id = read_string(id);
    let bytecode = if length == 0 {
        Vec::new()
    } else {
        std::slice::from_raw_parts(bytes, length).to_vec()
    };
    guard("elpian_create_vm_from_bytecode", 0, || {
        bool_to_i32(create_vm_from_bytecode(id, bytecode))
    })
}

/// # Safety
/// See the module-level contract.
#[no_mangle]
pub unsafe extern "C" fn elpian_validate_ast(ast: *const c_char) -> i32 {
    let ast = read_string(ast);
    guard("elpian_validate_ast", 0, || bool_to_i32(validate_ast(ast)))
}

/// # Safety
/// See the module-level contract.
#[no_mangle]
pub unsafe extern "C" fn elpian_execute(id: *const c_char) -> *mut c_char {
    let id = read_string(id);
    guard("elpian_execute", trapped_result("execute"), || {
        return_result(execute_vm(id))
    })
}

/// # Safety
/// See the module-level contract.
#[no_mangle]
pub unsafe extern "C" fn elpian_execute_func(
    id: *const c_char,
    name: *const c_char,
    callback_id: i64,
) -> *mut c_char {
    let (id, name) = (read_string(id), read_string(name));
    guard(
        "elpian_execute_func",
        trapped_result("execute_func"),
        || return_result(execute_vm_func(id, name, callback_id)),
    )
}

/// # Safety
/// See the module-level contract.
#[no_mangle]
pub unsafe extern "C" fn elpian_execute_func_with_input(
    id: *const c_char,
    name: *const c_char,
    input: *const c_char,
    callback_id: i64,
) -> *mut c_char {
    let (id, name, input) = (read_string(id), read_string(name), read_string(input));
    guard(
        "elpian_execute_func_with_input",
        trapped_result("execute_func_with_input"),
        || return_result(execute_vm_func_with_input(id, name, input, callback_id)),
    )
}

/// # Safety
/// See the module-level contract.
#[no_mangle]
pub unsafe extern "C" fn elpian_continue_execution(
    id: *const c_char,
    input: *const c_char,
) -> *mut c_char {
    let (id, input) = (read_string(id), read_string(input));
    guard(
        "elpian_continue_execution",
        trapped_result("continue_execution"),
        || return_result(continue_execution(id, input)),
    )
}

/// # Safety
/// See the module-level contract.
#[no_mangle]
pub unsafe extern "C" fn elpian_deliver_host_message(
    id: *const c_char,
    message: *const c_char,
    callback_id: i64,
) -> *mut c_char {
    let (id, message) = (read_string(id), read_string(message));
    guard(
        "elpian_deliver_host_message",
        trapped_result("deliver_host_message"),
        || return_result(deliver_host_message(id, message, callback_id)),
    )
}

/// # Safety
/// See the module-level contract.
#[no_mangle]
pub unsafe extern "C" fn elpian_destroy_vm(id: *const c_char) -> i32 {
    let id = read_string(id);
    guard("elpian_destroy_vm", 0, || bool_to_i32(destroy_vm(id)))
}

/// # Safety
/// See the module-level contract.
#[no_mangle]
pub unsafe extern "C" fn elpian_vm_exists(id: *const c_char) -> i32 {
    let id = read_string(id);
    guard("elpian_vm_exists", 0, || bool_to_i32(vm_exists(id)))
}

fn bool_to_i32(value: bool) -> i32 {
    i32::from(value)
}
