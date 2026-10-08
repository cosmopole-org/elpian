//! Call the C ABI by name with JSON arguments.
//!
//! Hosts that cannot bind every export one by one — the Android JNI bridge
//! ([`crate::jni`]) and the native cores' generic `governance(symbol, args)`
//! — go through here. Each call runs the very same `extern "C"` function a C
//! caller would reach, so panic containment, the error slot and the JSON
//! shapes are identical whichever way a host comes in.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use serde_json::Value;

use crate::abi::*;

fn arg_str(args: &[Value], i: usize) -> CString {
    let s = match args.get(i) {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Null) | None => String::new(),
        Some(other) => other.to_string(),
    };
    CString::new(s.replace('\0', "")).unwrap_or_default()
}

fn arg_i64(args: &[Value], i: usize) -> i64 {
    match args.get(i) {
        Some(Value::Number(n)) => n
            .as_i64()
            .or_else(|| n.as_f64().map(|f| f as i64))
            .unwrap_or(0),
        Some(Value::Bool(b)) => i64::from(*b),
        Some(Value::String(s)) => s.trim().parse().unwrap_or(0),
        _ => 0,
    }
}

fn arg_bool(args: &[Value], i: usize) -> bool {
    match args.get(i) {
        Some(Value::Bool(b)) => *b,
        Some(Value::Number(n)) => n.as_f64().unwrap_or(0.0) != 0.0,
        Some(Value::String(s)) => s == "true" || s == "1",
        _ => false,
    }
}

/// Take ownership of a string the ABI returned.
///
/// # Safety
/// `ptr` is NULL or was returned by this library and not yet freed.
unsafe fn take(ptr: *mut c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    let s = CStr::from_ptr(ptr).to_string_lossy().into_owned();
    elpian_free_string(ptr);
    s
}

/// The reason the last call on this thread failed, or an empty string.
pub fn last_error() -> String {
    // SAFETY: the slot is a valid NUL-terminated string owned by the library.
    unsafe {
        CStr::from_ptr(elpian_last_error())
            .to_string_lossy()
            .into_owned()
    }
}

/// Create a VM from compiled bytecode.
pub fn create_from_bytecode(id: &str, bytes: &[u8]) -> bool {
    let id = CString::new(id.replace('\0', "")).unwrap_or_default();
    // SAFETY: both regions are valid for the duration of the call.
    unsafe { elpian_create_vm_from_bytecode(id.as_ptr(), bytes.as_ptr(), bytes.len()) != 0 }
}

/// Run the export named `symbol` with `args`.
///
/// Integer-returning exports (`elpian_create_vm_from_ast`, `elpian_vm_exists`,
/// …) answer `"true"`/`"false"`; string-returning ones answer their JSON.
/// `None` means no export has that name.
pub fn call(symbol: &str, args: &[Value]) -> Option<String> {
    let s = |i| arg_str(args, i);
    let b = |r: i32| (if r != 0 { "true" } else { "false" }).to_string();
    // SAFETY: every pointer handed over is a live CString owned by this frame;
    // every returned string is freed exactly once by `take`.
    unsafe {
        Some(match symbol {
            "elpian_init" => {
                elpian_init();
                "true".to_string()
            }
            "elpian_create_vm_from_ast" => {
                b(elpian_create_vm_from_ast(s(0).as_ptr(), s(1).as_ptr()))
            }
            "elpian_create_vm_from_code" => {
                b(elpian_create_vm_from_code(s(0).as_ptr(), s(1).as_ptr()))
            }
            "elpian_validate_ast" => b(elpian_validate_ast(s(0).as_ptr())),
            "elpian_destroy_vm" => b(elpian_destroy_vm(s(0).as_ptr())),
            "elpian_vm_exists" => b(elpian_vm_exists(s(0).as_ptr())),
            "elpian_execute" => take(elpian_execute(s(0).as_ptr())),
            "elpian_execute_func" => take(elpian_execute_func(
                s(0).as_ptr(),
                s(1).as_ptr(),
                arg_i64(args, 2),
            )),
            "elpian_execute_func_with_input" => take(elpian_execute_func_with_input(
                s(0).as_ptr(),
                s(1).as_ptr(),
                s(2).as_ptr(),
                arg_i64(args, 3),
            )),
            "elpian_continue_execution" => {
                take(elpian_continue_execution(s(0).as_ptr(), s(1).as_ptr()))
            }
            "elpian_deliver_host_message" => take(elpian_deliver_host_message(
                s(0).as_ptr(),
                s(1).as_ptr(),
                arg_i64(args, 2),
            )),
            "elpian_limits" => take(elpian_limits(s(0).as_ptr())),
            "elpian_usage" => take(elpian_usage(s(0).as_ptr())),
            "elpian_subtree_usage" => take(elpian_subtree_usage(s(0).as_ptr())),
            "elpian_local_capabilities" => take(elpian_local_capabilities(s(0).as_ptr())),
            "elpian_effective_capabilities" => take(elpian_effective_capabilities(s(0).as_ptr())),
            "elpian_state" => take(elpian_state(s(0).as_ptr())),
            "elpian_pause" => take(elpian_pause(s(0).as_ptr())),
            "elpian_resume" => take(elpian_resume(s(0).as_ptr())),
            "elpian_terminate" => take(elpian_terminate(s(0).as_ptr())),
            "elpian_tree" => take(elpian_tree(s(0).as_ptr())),
            "elpian_terminate_tree" => take(elpian_terminate_tree(s(0).as_ptr())),
            "elpian_pause_tree" => take(elpian_pause_tree(s(0).as_ptr())),
            "elpian_destroy_tree" => take(elpian_destroy_tree(s(0).as_ptr())),
            "elpian_snapshot" => take(elpian_snapshot(s(0).as_ptr())),
            "elpian_set_limits" => take(elpian_set_limits(s(0).as_ptr(), s(1).as_ptr())),
            "elpian_set_capability" => take(elpian_set_capability(
                s(0).as_ptr(),
                s(1).as_ptr(),
                i32::from(arg_bool(args, 2)),
            )),
            "elpian_set_capabilities" => {
                take(elpian_set_capabilities(s(0).as_ptr(), s(1).as_ptr()))
            }
            "elpian_sandbox_capabilities" => {
                take(elpian_sandbox_capabilities(s(0).as_ptr(), s(1).as_ptr()))
            }
            "elpian_capability_allows" => {
                take(elpian_capability_allows(s(0).as_ptr(), s(1).as_ptr()))
            }
            "elpian_charge_storage" => take(elpian_charge_storage(s(0).as_ptr(), arg_i64(args, 1))),
            "elpian_adopt" => take(elpian_adopt(s(0).as_ptr(), s(1).as_ptr())),
            "elpian_enforce_tree_budgets" => take(elpian_enforce_tree_budgets()),
            _ => return None,
        })
    }
}

/// [`call`] with the arguments as a JSON array string.
pub fn call_json(symbol: &str, args_json: &str) -> Option<String> {
    let args = match serde_json::from_str::<Value>(args_json) {
        Ok(Value::Array(a)) => a,
        Ok(Value::Null) | Err(_) => Vec::new(),
        Ok(other) => vec![other],
    };
    call(symbol, &args)
}

/// C face of [`call_json`], for hosts that prefer one generic entry point (the
/// iOS native core's `governance(symbol, args)`). Returns NULL when no export
/// has that name; otherwise a string to release with `elpian_free_string`.
///
/// # Safety
/// Both pointers are NULL or NUL-terminated strings valid for this call.
#[no_mangle]
pub unsafe extern "C" fn elpian_call_json(
    symbol: *const c_char,
    args_json: *const c_char,
) -> *mut c_char {
    let read = |p: *const c_char| {
        if p.is_null() {
            String::new()
        } else {
            CStr::from_ptr(p).to_string_lossy().into_owned()
        }
    };
    match call_json(&read(symbol), &read(args_json)) {
        Some(out) => CString::new(out.replace('\0', ""))
            .unwrap_or_default()
            .into_raw(),
        None => std::ptr::null_mut(),
    }
}
