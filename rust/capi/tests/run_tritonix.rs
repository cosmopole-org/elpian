//! Verifies the Tritonix game client (client/build/guest.js) COMPILES in the
//! js2elpian subset and RUNS on the Elpian VM — mounting the VReact app over
//! godot.js + net.js + ui.js + react.js.

use std::sync::{Arc, Mutex};
use elpian_godot::{GuestLang, VmManager};
use serde_json::{json, Value};

#[derive(Default)]
struct Mock {
    next_handle: i64,
    creates: std::collections::HashMap<String, usize>,
}
impl Mock {
    fn exec(&mut self, op: &Value) -> Value {
        if op.get("chk").is_some() { return json!(true); }
        if op.get("connect").is_some() { return Value::Null; }
        if op.get("set").is_some() { return Value::Null; }
        if let Some(class) = op.get("new").and_then(|v| v.as_str()) {
            *self.creates.entry(class.to_string()).or_insert(0) += 1;
            return op.get("def").cloned().unwrap_or_else(|| { self.next_handle -= 1; json!(self.next_handle) });
        }
        if let Some(m) = op.get("method").and_then(|v| v.as_str()) {
            if m == "get_root" || m == "get_parent" || m == "create_tween" {
                self.next_handle -= 1;
                return json!({"obj": self.next_handle, "class": "Object"});
            }
            return Value::Null;
        }
        if op.get("singleton").is_some() || op.get("tree").is_some() || op.get("self").is_some()
            || op.get("load").is_some() || op.get("get").is_some() {
            self.next_handle -= 1;
            return op.get("def").cloned().unwrap_or_else(|| json!(self.next_handle));
        }
        if op.get("const").is_some() || op.get("expr").is_some() { return json!(1); }
        Value::Null
    }
    fn created(&self, c: &str) -> usize { *self.creates.get(c).unwrap_or(&0) }
}

const GUEST: &str = include_str!("tritonix_guest.js");

#[test]
fn tritonix_client_compiles_and_mounts() {
    let mock = Arc::new(Mutex::new(Mock::default()));
    let mut mgr = VmManager::new_root_lang("tritonix".to_string(), GUEST, GuestLang::Js, true, 0, 0)
        .expect("tritonix guest must COMPILE in the js2elpian subset");
    let hooked = mock.clone();
    mgr.set_bridge(Some(Box::new(move |name, args| {
        let mut m = hooked.lock().unwrap();
        match name {
            "godot.op" => Some(m.exec(args.first().unwrap_or(&Value::Null))),
            "godot.batch" => {
                let ops = args.first().and_then(|v| v.as_array()).cloned().unwrap_or_default();
                Some(Value::Array(ops.iter().map(|op| m.exec(op)).collect()))
            }
            _ => None,
        }
    })));
    mgr.run_root().expect("mountApp(<RootLayout/>) must run on the Elpian VM");
    let m = mock.lock().unwrap();
    // The VReact app must have created its CanvasLayer app shell.
    assert!(m.created("CanvasLayer") >= 1, "no VUI app shell (CanvasLayer) created");
    println!("tritonix guest booted; created {} distinct godot classes", m.creates.len());
}

// The Casual-UI-pack skin (VUI.useTextures + buttonStyle/styleBox) must build
// StyleBoxTexture nine-patches on the VM. Drive it directly with a tiny guest so
// we don't need to mock the backend to render a button.
const SKIN_GUEST: &str = "import 'godot.js';\nimport 'ui.js';\n\
VUI.use(VUI.themeDark());\n\
VUI.useTextures({ button: { normal: 'res://assets/ui/button_normal.png', hover: 'res://assets/ui/button_hover.png', pressed: 'res://assets/ui/button_pressed.png', margin: 12 }, panel: { texture: 'res://assets/ui/panel.png', margin: 20 } });\n\
let app = VUI.app({ design: [1280, 720] });\n\
app.push(VUI.button('Play', { kind: 'filled' }));\n";

#[test]
fn tritonix_ui_kit_skin_engages() {
    let mock = Arc::new(Mutex::new(Mock::default()));
    let mut mgr = VmManager::new_root_lang("tritonix-skin".to_string(), SKIN_GUEST, GuestLang::Js, true, 0, 0)
        .expect("skin guest must COMPILE");
    let hooked = mock.clone();
    mgr.set_bridge(Some(Box::new(move |name, args| {
        let mut m = hooked.lock().unwrap();
        match name {
            "godot.op" => Some(m.exec(args.first().unwrap_or(&Value::Null))),
            "godot.batch" => {
                let ops = args.first().and_then(|v| v.as_array()).cloned().unwrap_or_default();
                Some(Value::Array(ops.iter().map(|op| m.exec(op)).collect()))
            }
            _ => None,
        }
    })));
    mgr.run_root().expect("skin guest must run");
    let m = mock.lock().unwrap();
    assert!(
        m.created("StyleBoxTexture") >= 1,
        "UI-kit skin did not engage (no StyleBoxTexture created)"
    );
    println!("skin engaged: {} StyleBoxTexture created", m.created("StyleBoxTexture"));
}
