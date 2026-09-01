//! Repro: a one-shot GTimer scheduled in the same turn as VMs.spawn must
//! still fire (the sheet-close queueFree and toast dismiss depend on it).
use std::cell::RefCell;
use std::rc::Rc;
use elpian_godot::{GuestLang, VmManager};
use serde_json::{json, Value};

fn boot(id: &str, src: &str) -> VmManager {
    let mut mgr = VmManager::new_root_lang(id.into(), src, GuestLang::Js, true, 0, 0).unwrap();
    let calls: Rc<RefCell<u64>> = Rc::new(RefCell::new(0));
    let c = calls.clone();
    mgr.set_bridge(Some(Box::new(move |_n, a| {
        *c.borrow_mut() += 1;
        let op = a.first().cloned().unwrap_or(Value::Null);
        if op.get("chk").is_some() {
            return Some(json!(true));
        }
        if let Some(list) = op.as_array() {
            return Some(Value::Array(list.iter().map(|_| Value::Null).collect()));
        }
        Some(Value::Null)
    })));
    mgr.run_root().unwrap();
    mgr
}

#[test]
fn one_shot_timer_scheduled_beside_spawn_still_fires() {
    let src = r#"
        import 'godot.js';
        function main() {
          let pod = GD.create("Node3D");
          GTimer.after(170, () => { print("timer-170 fired"); });
          let child = VMs.spawn("function main() { print('child up'); } main();", pod, { lang: "js", label: "t" });
          print("spawned ok=" + (child != null));
          GTimer.after(120, () => { print("timer-120 fired"); });
        }
        main();
    "#;
    let mut mgr = boot("timer-spawn-a", src);
    for _ in 0..40 {
        mgr.pump(16).expect("pump");
    }
    let log = mgr.take_log().join("\n");
    eprintln!("LOG:\n{log}");
    assert!(log.contains("spawned ok=true"), "spawn failed: {log}");
    assert!(log.contains("timer-170 fired"), "pre-spawn one-shot timer was dropped: {log}");
    assert!(log.contains("timer-120 fired"), "post-spawn one-shot timer was dropped: {log}");
}

#[test]
fn one_shot_timer_beside_spawn_in_dispatch_turn_fires() {
    // The app's game-launch pattern: one engine callable turn both closes the
    // games sheet (GTimer.after -> queueFree) and spawns the game VM. The
    // timer must still fire afterwards.
    let src = r#"
        import 'godot.js';
        var btn = null;
        function main() {
          btn = GD.create("Button");
          btn.connect("pressed", (a) => {
            print("tile tapped");
            GTimer.after(170, () => { print("sheet-free timer fired"); });
            let pod = GD.create("Node3D");
            let child = VMs.spawn("function main() { print('game up'); } main();", pod, { lang: "js", label: "game" });
            print("spawned ok=" + (child != null));
            GTimer.after(2500, () => { print("toast-dismiss timer fired"); });
          });
        }
        main();
    "#;
    let mut mgr = VmManager::new_root_lang("timer-spawn-c".into(), src, GuestLang::Js, true, 0, 0).unwrap();
    let ops: Rc<RefCell<Vec<Value>>> = Rc::new(RefCell::new(Vec::new()));
    let sink = ops.clone();
    mgr.set_bridge(Some(Box::new(move |_n, a| {
        let op = a.first().cloned().unwrap_or(Value::Null);
        if let Some(list) = op.as_array() {
            for o in list {
                sink.borrow_mut().push(o.clone());
            }
            return Some(Value::Array(list.iter().map(|_| Value::Null).collect()));
        }
        sink.borrow_mut().push(op.clone());
        if op.get("chk").is_some() {
            return Some(json!(true));
        }
        Some(Value::Null)
    })));
    mgr.run_root().unwrap();
    let cb = ops
        .borrow()
        .iter()
        .find(|o| o.get("connect").and_then(|v| v.as_str()) == Some("pressed"))
        .and_then(|o| o.get("cb"))
        .and_then(|v| v.as_i64())
        .expect("no pressed connect op captured");
    mgr.invoke("__godotDispatch", json!([cb, [0]]));
    for _ in 0..200 {
        mgr.pump(16).expect("pump");
    }
    let log = mgr.take_log().join("\n");
    eprintln!("LOG:\n{log}");
    assert!(log.contains("tile tapped"), "callable was not delivered: {log}");
    assert!(log.contains("spawned ok=true"), "spawn failed: {log}");
    assert!(log.contains("game up"), "child VM did not boot: {log}");
    assert!(
        log.contains("sheet-free timer fired"),
        "one-shot timer scheduled beside a spawn in a dispatch turn was dropped: {log}"
    );
    assert!(
        log.contains("toast-dismiss timer fired"),
        "one-shot timer scheduled after a spawn in a dispatch turn was dropped: {log}"
    );
}

#[test]
fn one_shot_timer_scheduled_in_callable_dispatch_turn_fires() {
    let src = r#"
        import 'godot.js';
        var btn = null;
        function main() {
          btn = GD.create("Button");
          btn.connect("pressed", (a) => {
            print("pressed handler");
            GTimer.after(120, () => { print("dispatch-turn timer fired"); });
          });
        }
        main();
    "#;
    let mut mgr = VmManager::new_root_lang("timer-spawn-b".into(), src, GuestLang::Js, true, 0, 0).unwrap();
    let ops: Rc<RefCell<Vec<Value>>> = Rc::new(RefCell::new(Vec::new()));
    let sink = ops.clone();
    mgr.set_bridge(Some(Box::new(move |_n, a| {
        let op = a.first().cloned().unwrap_or(Value::Null);
        if let Some(list) = op.as_array() {
            for o in list {
                sink.borrow_mut().push(o.clone());
            }
            return Some(Value::Array(list.iter().map(|_| Value::Null).collect()));
        }
        sink.borrow_mut().push(op.clone());
        if op.get("chk").is_some() {
            return Some(json!(true));
        }
        Some(Value::Null)
    })));
    mgr.run_root().unwrap();
    // The engine emits the callable with the cb id exactly as it appeared in
    // the (sanitized, namespaced) connect op.
    let cb = ops
        .borrow()
        .iter()
        .find(|o| o.get("connect").and_then(|v| v.as_str()) == Some("pressed"))
        .and_then(|o| o.get("cb"))
        .and_then(|v| v.as_i64())
        .expect("no pressed connect op captured");
    mgr.invoke("__godotDispatch", json!([cb, [0]]));
    for _ in 0..40 {
        mgr.pump(16).expect("pump");
    }
    let log = mgr.take_log().join("\n");
    eprintln!("LOG:\n{log}");
    assert!(log.contains("pressed handler"), "callable was not delivered: {log}");
    assert!(
        log.contains("dispatch-turn timer fired"),
        "one-shot timer scheduled during a __godotDispatch turn was dropped: {log}"
    );
}
