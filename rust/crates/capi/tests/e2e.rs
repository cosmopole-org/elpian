//! End-to-end tests of the Elpian↔Godot bridge protocol with a mock engine.
//!
//! These run REAL guest programs — the `godot.dart` prelude composed ahead of
//! test Dart source, compiled by dart2elpian, executed on the real VM — against
//! a mock C++ controller implemented in Rust behind the host hook. What the
//! mock sees is byte-for-byte what the GDExtension's `GodotController` sees, so
//! these tests pin the wire protocol from the guest side: op shapes, tagged
//! value marshaling, handle discipline, batching, signal/callable dispatch.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use elpian_dart_runtime::governance::{DartCapabilitySet, ResourceMeter};
use elpian_dart_runtime::runtime::DartRuntime;
use elpian_godot::compose_godot_program;
use serde_json::{json, Value};

/// A tiny fake engine: an object table plus a recording of every op received.
#[derive(Default)]
struct MockGodot {
    objects: HashMap<i64, MockObj>,
    op_calls: usize,
    batch_calls: usize,
    connections: Vec<(i64, String, i64)>, // (object, signal, cbId)
    loads: Vec<String>,
    ops_seen: Vec<Value>,
    self_actions: Vec<Value>, // ops addressing the host node / tree with an action
}

#[derive(Default, Clone)]
struct MockObj {
    class: String,
    props: HashMap<String, Value>,
}

impl MockGodot {
    fn exec_op(&mut self, op: &Value) -> Value {
        self.ops_seen.push(op.clone());
        if let Some(cls) = op.get("new").and_then(|v| v.as_str()) {
            let id = op.get("def").and_then(|v| v.as_i64()).unwrap_or(0);
            self.objects.insert(
                id,
                MockObj {
                    class: cls.into(),
                    props: HashMap::new(),
                },
            );
            return json!(id);
        }
        if let Some(name) = op.get("singleton").and_then(|v| v.as_str()) {
            let id = op.get("def").and_then(|v| v.as_i64()).unwrap_or(0);
            self.objects.insert(
                id,
                MockObj {
                    class: name.into(),
                    props: HashMap::new(),
                },
            );
            return json!(id);
        }
        if op.get("tree").is_some() || op.get("self").is_some() {
            // Mirror the C++ dispatcher: "self"/"tree" with an action key only
            // selects the target — the action below must still execute. A bare
            // bind op registers the handle and returns it.
            let has_action = [
                "connect",
                "disconnect",
                "method",
                "get",
                "set",
                "geti",
                "seti",
            ]
            .iter()
            .any(|k| op.get(*k).is_some());
            if !has_action {
                let id = op.get("def").and_then(|v| v.as_i64()).unwrap_or(0);
                self.objects.insert(
                    id,
                    MockObj {
                        class: "SceneTree".into(),
                        props: HashMap::new(),
                    },
                );
                return json!(id);
            }
            self.self_actions.push(op.clone());
        }
        if let Some(path) = op.get("load").and_then(|v| v.as_str()) {
            let id = op.get("def").and_then(|v| v.as_i64()).unwrap_or(0);
            self.loads.push(path.to_string());
            self.objects.insert(
                id,
                MockObj {
                    class: "Resource".into(),
                    props: HashMap::new(),
                },
            );
            return json!(id);
        }
        if let Some(name) = op.get("const").and_then(|v| v.as_str()) {
            return match name {
                "KEY_ESCAPE" => json!(4194305),
                "Node.PROCESS_MODE_ALWAYS" => json!(3),
                _ => json!(0),
            };
        }
        if let Some(sig) = op.get("connect").and_then(|v| v.as_str()) {
            let id = op.get("ref").and_then(|v| v.as_i64()).unwrap_or(0);
            let cb = op.get("cb").and_then(|v| v.as_i64()).unwrap_or(0);
            self.connections.push((id, sig.to_string(), cb));
            return Value::Null;
        }
        if let Some(prop) = op.get("set").and_then(|v| v.as_str()) {
            let id = op.get("ref").and_then(|v| v.as_i64()).unwrap_or(0);
            let value = op.get("value").cloned().unwrap_or(Value::Null);
            if let Some(o) = self.objects.get_mut(&id) {
                o.props.insert(prop.to_string(), value);
            }
            return Value::Null;
        }
        if let Some(prop) = op.get("get").and_then(|v| v.as_str()) {
            let id = op.get("ref").and_then(|v| v.as_i64()).unwrap_or(0);
            return self
                .objects
                .get(&id)
                .and_then(|o| o.props.get(prop).cloned())
                .unwrap_or(Value::Null);
        }
        if let Some(method) = op.get("method").and_then(|v| v.as_str()) {
            // Canned method results the tests assert on.
            return match method {
                "get_name" => json!("mock-node"),
                "get_position" => json!({"vec2": [3.0, 4.0]}),
                "get_transform" => json!({"xform2d": [1.0, 0.0, 0.0, 1.0, 9.0, 8.0]}),
                "get_data" => json!({"u8": "AQID"}), // bytes [1,2,3]
                "get_child" => json!({"obj": -7, "class": "Sprite2D"}),
                "get_meta" => json!({"dict": {"hp": 100, "boss": true}}),
                _ => Value::Null,
            };
        }
        if op.get("free").is_some() {
            let id = op.get("free").and_then(|v| v.as_i64()).unwrap_or(0);
            self.objects.remove(&id);
            return Value::Null;
        }
        if op.get("classes").is_some() {
            return json!(["Object", "Node", "Node2D"]);
        }
        Value::Null
    }
}

/// Build a runtime running `user_source` (with the prelude composed ahead)
/// against a fresh mock engine; returns (runtime, shared mock).
fn boot(user_source: &str) -> (DartRuntime, Arc<Mutex<MockGodot>>) {
    static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
    let mock = Arc::new(Mutex::new(MockGodot::default()));
    let program = compose_godot_program(user_source);
    let mut rt = DartRuntime::from_dart(
        format!(
            "mock-godot-{}",
            NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
        ),
        &program,
        DartCapabilitySet::full(),
        ResourceMeter::unbounded(),
    )
    .expect("guest program must compile (prelude + test source)");
    let hooked = mock.clone();
    rt.set_host_hook(Box::new(move |name, args| {
        let mut m = hooked.lock().unwrap();
        match name {
            "godot.op" => {
                m.op_calls += 1;
                let op = args.first().cloned().unwrap_or(Value::Null);
                Some(m.exec_op(&op))
            }
            "godot.batch" => {
                m.batch_calls += 1;
                let ops = args
                    .first()
                    .and_then(|v| v.as_array())
                    .cloned()
                    .unwrap_or_default();
                Some(Value::Array(ops.iter().map(|op| m.exec_op(op)).collect()))
            }
            _ => None,
        }
    }));
    (rt, mock)
}

#[test]
fn create_set_get_call_roundtrip() {
    let (mut rt, mock) = boot(
        r#"
void main() {
  var node = GD.create("Node2D");
  node.set("position", Vector2(3.0, 4.0));
  var p = node.get("position");
  askHost("test.emit", [p.x + p.y]);
  askHost("test.emit", [node.call("get_name", [])]);
}
"#,
    );
    rt.run().unwrap();
    // Whole floats may cross the JSON seam as ints (7.0 → "7"), so compare
    // numerically rather than by JSON type tag.
    assert_eq!(rt.emitted()[0].as_f64(), Some(7.0));
    assert_eq!(rt.emitted()[1], json!("mock-node"));
    let m = mock.lock().unwrap();
    assert_eq!(m.objects.get(&1).unwrap().class, "Node2D");
    let pos = m.objects.get(&1).unwrap().props.get("position").unwrap();
    let xy: Vec<f64> = pos["vec2"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_f64().unwrap())
        .collect();
    assert_eq!(xy, vec![3.0, 4.0]);
}

#[test]
fn every_value_shape_round_trips() {
    let (mut rt, _mock) = boot(
        r#"
void main() {
  var n = GD.create("Node3D");
  n.set("v3", Vector3(1.0, 2.0, 3.0));
  n.set("col", Color(0.1, 0.2, 0.3, 1.0));
  n.set("rect", Rect2(0.0, 0.0, 10.0, 20.0));
  n.set("quat", Quaternion.identity());
  n.set("xf", Transform3D.translated(5.0, 6.0, 7.0));
  n.set("path", NodePath("/root/Main"));
  n.set("bytes", Packed.f32([0.5, 1.5]));
  n.set("rid", GRid(77));

  var v3 = n.get("v3");
  askHost("test.emit", [v3.x + v3.y + v3.z]);
  var c = n.get("col");
  askHost("test.emit", [c.a]);
  var xf = n.get("xf");
  askHost("test.emit", [xf.m[9]]);
  var np = n.get("path");
  askHost("test.emit", [np.value]);
  var rid = n.get("rid");
  askHost("test.emit", [rid.id]);

  var t = n.call("get_transform", []);
  askHost("test.emit", [t.m[4]]);
  var child = n.call("get_child", [0]);
  askHost("test.emit", [child.cls]);
  var meta = n.call("get_meta", []);
  askHost("test.emit", [meta["hp"]]);
}
"#,
    );
    rt.run().unwrap();
    let e = rt.emitted();
    assert_eq!(e[0].as_f64(), Some(6.0));
    assert_eq!(e[1].as_f64(), Some(1.0));
    assert_eq!(e[2].as_f64(), Some(5.0));
    assert_eq!(e[3], json!("/root/Main"));
    assert_eq!(e[4].as_f64(), Some(77.0));
    assert_eq!(e[5].as_f64(), Some(9.0));
    assert_eq!(e[6], json!("Sprite2D"));
    assert_eq!(e[7].as_f64(), Some(100.0));
}

#[test]
fn batching_coalesces_ops_into_one_host_call() {
    let (mut rt, mock) = boot(
        r#"
void main() {
  GD.beginBatch();
  var a = GD.create("Sprite2D");
  var b = GD.create("Sprite2D");
  var c = GD.create("Sprite2D");
  a.set("position", Vector2(1.0, 1.0));
  b.set("position", Vector2(2.0, 2.0));
  c.set("position", Vector2(3.0, 3.0));
  var results = GD.endBatch();
  askHost("test.emit", [results[0]]);
}
"#,
    );
    rt.run().unwrap();
    let m = mock.lock().unwrap();
    assert_eq!(
        m.op_calls, 0,
        "batched ops must not cross the seam individually"
    );
    assert_eq!(m.batch_calls, 1, "one batch = one host call");
    assert_eq!(m.objects.len(), 3);
    assert_eq!(rt.emitted(), &[json!(1)]); // first op's result: handle id 1
}

#[test]
fn signals_dispatch_to_dart_closures() {
    let (mut rt, mock) = boot(
        r#"
void main() {
  var btn = GD.create("Button");
  btn.connect("pressed", (args) {
    askHost("test.emit", ["pressed got " + args[0]]);
  });
}
"#,
    );
    rt.run().unwrap();
    let cb_id = {
        let m = mock.lock().unwrap();
        assert_eq!(m.connections.len(), 1);
        assert_eq!(m.connections[0].1, "pressed");
        m.connections[0].2
    };
    // Simulate the native SignalRelay flushing one emission into the VM.
    rt.invoke_handler("__godotDispatch", json!([cb_id, ["clicked"]]));
    assert_eq!(rt.emitted(), &[json!("pressed got clicked")]);
}

#[test]
fn closures_marshal_as_live_callables() {
    let (mut rt, mock) = boot(
        r#"
void main() {
  var tween = GD.create("Tween");
  tween.call("tween_callback", [(args) {
    askHost("test.emit", ["callable ran"]);
  }]);
}
"#,
    );
    rt.run().unwrap();
    let cb_id = {
        let m = mock.lock().unwrap();
        let call_op = m
            .ops_seen
            .iter()
            .find(|op| op.get("method").and_then(|v| v.as_str()) == Some("tween_callback"))
            .expect("method op recorded");
        let args = call_op.get("args").and_then(|v| v.as_array()).unwrap();
        args[0]
            .get("callable")
            .and_then(|v| v.as_i64())
            .expect("closure became a callable tag")
    };
    rt.invoke_handler("__godotDispatch", json!([cb_id, []]));
    assert_eq!(rt.emitted(), &[json!("callable ran")]);
}

#[test]
fn engine_lifecycle_events_reach_registered_handlers() {
    let (mut rt, _mock) = boot(
        r#"
var frames = 0;
void main() {
  GD.onReady((arg) {
    askHost("test.emit", ["ready"]);
  });
  GD.onProcess((delta) {
    frames = frames + 1;
    askHost("test.emit", ["frame " + frames + " dt " + delta]);
  });
}
"#,
    );
    rt.run().unwrap();
    rt.invoke_handler("__godotEvent", json!(["_ready", Value::Null]));
    rt.invoke_handler("__godotEvent", json!(["_process", 0.016]));
    rt.invoke_handler("__godotEvent", json!(["_process", 0.017]));
    assert_eq!(
        rt.emitted(),
        &[
            json!("ready"),
            json!("frame 1 dt 0.016"),
            json!("frame 2 dt 0.017")
        ]
    );
}

#[test]
fn singletons_constants_and_loads() {
    let (mut rt, mock) = boot(
        r#"
void main() {
  var rs = GD.renderingServer();
  rs.call("set_default_clear_color", [Color(0.0, 0.0, 0.0, 1.0)]);
  askHost("test.emit", [GD.constant("KEY_ESCAPE")]);
  var scene = GD.load("res://player.tscn");
  scene.call("instantiate", []);
}
"#,
    );
    rt.run().unwrap();
    assert_eq!(rt.emitted(), &[json!(4194305)]);
    let m = mock.lock().unwrap();
    assert_eq!(m.loads, vec!["res://player.tscn".to_string()]);
    assert_eq!(m.objects.get(&1).unwrap().class, "RenderingServer");
}

#[test]
fn gtimer_rides_the_vm_event_loop() {
    let (mut rt, _mock) = boot(
        r#"
void main() {
  GTimer.after(0, () {
    askHost("test.emit", ["timer fired"]);
  });
}
"#,
    );
    rt.run().unwrap(); // run() drains the event loop, so the timer fires
    assert_eq!(rt.emitted(), &[json!("timer fired")]);
}

#[test]
fn mount_targets_the_host_node_with_add_child() {
    // Regression: {"self": true, "method": "add_child", …} (GD.mount) must be
    // an add_child CALL on the hosting node, not a bare self-bind that drops
    // the action — the dropped mount left every demo scene node orphaned and
    // the exported game showing nothing but the clear color.
    let (mut rt, mock) = boot(
        r#"
void main() {
  var spinner = GD.create("Polygon2D");
  GD.mount(spinner);
}
"#,
    );
    rt.run().unwrap();
    let m = mock.lock().unwrap();
    let mount = m
        .self_actions
        .iter()
        .find(|op| op.get("method").and_then(|v| v.as_str()) == Some("add_child"))
        .expect("GD.mount must issue add_child addressed to the hosting node");
    assert_eq!(
        mount["args"][0]["ref"].as_i64(),
        Some(1),
        "add_child must receive the mounted node's handle"
    );
}

// ---- the C ABI itself (what the GDExtension actually links) ----------------

mod capi_surface {
    use super::*;
    use elpian_godot::*;
    use std::ffi::{c_char, c_void, CStr, CString};

    /// A minimal C host: answers `godot.op` `{const: …}` with 42, echoes
    /// everything else as null. Also proves the free-callback contract.
    extern "C" fn host(
        _user: *mut c_void,
        api_name: *const c_char,
        args_json: *const c_char,
    ) -> *mut c_char {
        let name = unsafe { CStr::from_ptr(api_name) }.to_str().unwrap();
        let args: Value =
            serde_json::from_str(unsafe { CStr::from_ptr(args_json) }.to_str().unwrap()).unwrap();
        let reply = if name == "godot.op" && args[0].get("const").is_some() {
            json!(42)
        } else if name == "godot.op" && args[0].get("new").is_some() {
            args[0]["def"].clone()
        } else {
            Value::Null
        };
        CString::new(reply.to_string()).unwrap().into_raw()
    }

    extern "C" fn host_free(_user: *mut c_void, s: *mut c_char) {
        unsafe { drop(CString::from_raw(s)) };
    }

    #[test]
    fn ffi_boot_run_log_teardown() {
        // SAFETY: the elpian_godot_* exports are `unsafe extern "C"`; every
        // pointer below is a live handle or a CString owned by this scope.
        unsafe {
            let src = CString::new(
                r#"
    void main() {
      var v = GD.constant("ANY");
      print("constant was " + v);
      var n = GD.create("Node");
      print("handle " + n.id);
    }
    "#,
            )
            .unwrap();
            let rt = elpian_godot_new(src.as_ptr(), 1, 0, 0);
            assert!(
                !rt.is_null(),
                "boot failed: {:?}",
                CStr::from_ptr(elpian_godot_last_error())
            );
            elpian_godot_set_host(rt, Some(host), Some(host_free), std::ptr::null_mut());
            assert_eq!(
                elpian_godot_run(rt),
                0,
                "run failed: {:?}",
                CStr::from_ptr(elpian_godot_last_error())
            );

            let log_ptr = elpian_godot_take_log(rt);
            assert!(!log_ptr.is_null());
            let log: Value =
                serde_json::from_str(CStr::from_ptr(log_ptr).to_str().unwrap()).unwrap();
            elpian_godot_string_free(log_ptr);
            assert_eq!(log, json!(["constant was 42", "handle 1"]));
            // Drained: nothing new.
            assert!(elpian_godot_take_log(rt).is_null());

            // Lifecycle event through the C surface.
            let name = CString::new("__godotEvent").unwrap();
            let arg = CString::new(r#"["_process", 0.016]"#).unwrap();
            assert_eq!(elpian_godot_invoke(rt, name.as_ptr(), arg.as_ptr()), 0);
            assert_eq!(elpian_godot_pump(rt, 16), 0);

            elpian_godot_free(rt);
        }
    }

    #[test]
    fn ffi_compile_error_reports() {
        // SAFETY: the elpian_godot_* exports are `unsafe extern "C"`; every
        // pointer below is a live handle or a CString owned by this scope.
        unsafe {
            let src = CString::new("void main( {").unwrap();
            let rt = elpian_godot_new(src.as_ptr(), 1, 0, 0);
            assert!(rt.is_null());
            let err = CStr::from_ptr(elpian_godot_last_error()).to_str().unwrap();
            assert!(err.contains("compile"), "unexpected error: {err}");
        }
    }
}

// ---- engine-callback re-entrancy (the web-export boot freeze) ---------------

mod reentrant_engine_callback {
    use super::*;
    use elpian_godot::*;
    use std::ffi::{c_char, c_void, CStr, CString};
    use std::sync::atomic::{AtomicPtr, Ordering};

    /// The runtime handle, published so the host callback can re-enter the C
    /// ABI mid-turn — exactly what the GDExtension node does when the engine
    /// fires a notification (e.g. NOTIFICATION_CHILD_ORDER_CHANGED while the
    /// guest mounts its UI) from inside one of the guest's own ops.
    static RT: AtomicPtr<ElpianGodotRuntime> = AtomicPtr::new(std::ptr::null_mut());

    extern "C" fn host(
        _user: *mut c_void,
        api_name: *const c_char,
        args_json: *const c_char,
    ) -> *mut c_char {
        let name = unsafe { CStr::from_ptr(api_name) }.to_str().unwrap();
        let args: Value =
            serde_json::from_str(unsafe { CStr::from_ptr(args_json) }.to_str().unwrap()).unwrap();
        if name == "godot.op" && args[0]["const"] == json!("REENTER") {
            let rt = RT.load(Ordering::SeqCst);
            let fn_name = CString::new("__godotEvent").unwrap();
            let arg = CString::new(r#"["_notification", 24]"#).unwrap();
            // SAFETY: `rt` is the live runtime published by the test that
            // installed this callback, and both names are owned CStrings.
            unsafe { elpian_godot_invoke(rt, fn_name.as_ptr(), arg.as_ptr()) };
            return CString::new("42").unwrap().into_raw();
        }
        CString::new("null").unwrap().into_raw()
    }

    extern "C" fn host_free(_user: *mut c_void, s: *mut c_char) {
        unsafe { drop(CString::from_raw(s)) };
    }

    /// The guest schedules a microtask, then makes an op during which the
    /// "engine" re-enters the runtime. The re-entrant delivery necessarily
    /// bounces off the busy VM — but it must NOT consume the queued microtask
    /// with it: the task must still run once the turn completes. (Unguarded,
    /// the re-entrant drain ate VReact's one-shot render-flush microtask on
    /// the web export, freezing the TritonLand boot gate forever.)
    #[test]
    fn microtasks_survive_reentrant_engine_callbacks() {
        // SAFETY: the elpian_godot_* exports are `unsafe extern "C"`; every
        // pointer below is a live handle or a CString owned by this scope.
        unsafe {
            let src = CString::new(
                r#"
    __cbReg.push(function () { print("microtask ran"); });
    askHost("dart:async/scheduleMicrotask", [__cbReg.length - 1]);
    var v = askHost("godot.op", [{ "const": "REENTER" }]);
    print("op answered " + v);
    "#,
            )
            .unwrap();
            let lang = CString::new("js").unwrap();
            let rt = elpian_godot_new_lang(src.as_ptr(), lang.as_ptr(), 1, 0, 0);
            assert!(
                !rt.is_null(),
                "boot failed: {:?}",
                CStr::from_ptr(elpian_godot_last_error())
            );
            RT.store(rt, Ordering::SeqCst);
            elpian_godot_set_host(rt, Some(host), Some(host_free), std::ptr::null_mut());
            assert_eq!(
                elpian_godot_run(rt),
                0,
                "run failed: {:?}",
                CStr::from_ptr(elpian_godot_last_error())
            );
            // The frame pump is the fallback drain for anything the boot run left
            // queued (the run's own trailing drain already suffices; this mirrors
            // the node's per-frame call).
            elpian_godot_pump(rt, 16);

            let log_ptr = elpian_godot_take_log(rt);
            assert!(!log_ptr.is_null(), "guest produced no output at all");
            let log: Value =
                serde_json::from_str(CStr::from_ptr(log_ptr).to_str().unwrap()).unwrap();
            elpian_godot_string_free(log_ptr);
            let lines: Vec<String> = log
                .as_array()
                .unwrap()
                .iter()
                .map(|v| v.as_str().unwrap_or_default().to_string())
                .collect();
            assert!(
                lines.iter().any(|l| l.contains("op answered 42")),
                "the re-entered op never completed; log: {lines:?}"
            );
            assert!(
                lines.iter().any(|l| l.contains("microtask ran")),
                "the microtask scheduled before the re-entrant callback was \
                 consumed unrun; log: {lines:?}"
            );

            RT.store(std::ptr::null_mut(), Ordering::SeqCst);
            elpian_godot_free(rt);
        }
    }
}
