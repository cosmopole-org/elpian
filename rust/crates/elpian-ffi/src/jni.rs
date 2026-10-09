//! The JNI face of the C ABI, for the Android native core
//! (`dev.elpian.android.vm.ElpianVmNative` in native/android).
//!
//! Three entry points cover the whole surface: a by-name call with JSON
//! arguments (see [`crate::dispatch`]), bytecode creation (bytes do not
//! travel as JSON) and the per-thread error slot. Built only with the `jni`
//! feature, so desktop and Flutter builds carry no JNI symbols.

use ::jni::objects::{JByteArray, JClass, JString};
use ::jni::sys::{jboolean, jstring, JNI_FALSE, JNI_TRUE};
use ::jni::JNIEnv;

use crate::dispatch;

fn read(env: &mut JNIEnv, s: &JString) -> String {
    if s.is_null() {
        return String::new();
    }
    env.get_string(s).map(|j| j.into()).unwrap_or_default()
}

fn make(env: &mut JNIEnv, s: &str) -> jstring {
    env.new_string(s)
        .map(|j| j.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// `external fun nativeCall(symbol: String, argsJson: String): String?`
#[no_mangle]
pub extern "system" fn Java_dev_elpian_android_vm_ElpianVmNative_nativeCall<'l>(
    mut env: JNIEnv<'l>,
    _class: JClass<'l>,
    symbol: JString<'l>,
    args_json: JString<'l>,
) -> jstring {
    let symbol = read(&mut env, &symbol);
    let args = read(&mut env, &args_json);
    match dispatch::call_json(&symbol, &args) {
        Some(out) => make(&mut env, &out),
        None => std::ptr::null_mut(),
    }
}

/// `external fun nativeCreateFromBytecode(id: String, bytes: ByteArray): Boolean`
#[no_mangle]
pub extern "system" fn Java_dev_elpian_android_vm_ElpianVmNative_nativeCreateFromBytecode<'l>(
    mut env: JNIEnv<'l>,
    _class: JClass<'l>,
    id: JString<'l>,
    bytes: JByteArray<'l>,
) -> jboolean {
    let id = read(&mut env, &id);
    let data = if bytes.is_null() {
        Vec::new()
    } else {
        env.convert_byte_array(&bytes).unwrap_or_default()
    };
    if dispatch::create_from_bytecode(&id, &data) {
        JNI_TRUE
    } else {
        JNI_FALSE
    }
}

/// `external fun nativeLastError(): String`
#[no_mangle]
pub extern "system" fn Java_dev_elpian_android_vm_ElpianVmNative_nativeLastError<'l>(
    mut env: JNIEnv<'l>,
    _class: JClass<'l>,
) -> jstring {
    let e = dispatch::last_error();
    make(&mut env, &e)
}
