//! The by-name dispatcher the native cores (JNI, Swift) go through.

use elpian_vm::dispatch;
use serde_json::{json, Value};

#[test]
fn unknown_symbol_is_none() {
    assert!(dispatch::call("elpian_no_such_export", &[]).is_none());
}

#[test]
fn create_execute_and_govern_by_name() {
    dispatch::call("elpian_init", &[]).unwrap();
    let ast = json!({"type": "program", "body": []}).to_string();
    let created = dispatch::call(
        "elpian_create_vm_from_ast",
        &[json!("dispatch-vm"), json!(ast)],
    )
    .unwrap();
    assert_eq!(created, "true", "create failed: {}", dispatch::last_error());
    assert_eq!(
        dispatch::call_json("elpian_vm_exists", r#"["dispatch-vm"]"#).unwrap(),
        "true"
    );
    let run: Value =
        serde_json::from_str(&dispatch::call("elpian_execute", &[json!("dispatch-vm")]).unwrap())
            .unwrap();
    assert_eq!(run["hasHostCall"], json!(false));
    let usage: Value =
        serde_json::from_str(&dispatch::call_json("elpian_usage", r#"["dispatch-vm"]"#).unwrap())
            .unwrap();
    assert!(usage.is_object());
    let cap = dispatch::call(
        "elpian_set_capability",
        &[json!("dispatch-vm"), json!("network"), json!(false)],
    )
    .unwrap();
    assert!(serde_json::from_str::<Value>(&cap).is_ok());
    assert_eq!(
        dispatch::call("elpian_destroy_vm", &[json!("dispatch-vm")]).unwrap(),
        "true"
    );
    assert_eq!(
        dispatch::call("elpian_vm_exists", &[json!("dispatch-vm")]).unwrap(),
        "false"
    );
}
