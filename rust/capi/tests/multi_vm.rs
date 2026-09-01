//! End-to-end tests of the multi-VM tree: REAL guest programs (prelude + test
//! Dart, compiled by dart2elpian, executed on real VMs) driving the
//! [`elpian_godot::VmManager`] against a mock engine plugged into the bridge
//! seam. What the mock sees is byte-for-byte what the C++ `GodotController`
//! sees, so these tests pin the multi-VM wire contract:
//!
//! * spawn/boot of child VMs into the shared scene, sandbox-tag stamping;
//! * guest-forged `__sbx` keys being stripped (a VM cannot fake its sandbox);
//! * callback-id namespacing and dispatch routing back to the owning VM;
//! * hierarchical permissions (revoke propagates, grants a parent lacks are
//!   inert) including on-the-fly changes;
//! * lifecycle binding (terminating a parent kills the whole subtree),
//!   pause/resume gating of event delivery;
//! * a hung child trapped by its own per-turn budget + parent notification;
//! * the aggregate-budget rule killing a whole branch;
//! * spawn rejection when the assigned node lies outside the parent sandbox;
//! * parent↔child messaging.

use std::cell::RefCell;
use std::collections::HashSet;
use std::rc::Rc;

use elpian_godot::{VmManager, ROOT_VM};
use serde_json::{json, Value};

/// A tiny fake engine behind the bridge seam.
#[derive(Default)]
struct MockEngine {
    /// Every op received (batch ops flattened), in order.
    ops: Vec<Value>,
    /// Node handles the `chk` containment probe should reject.
    chk_reject: HashSet<i64>,
    /// (handle, sandbox) pairs shared via the `grant` op.
    grants: Vec<(i64, i64)>,
    /// (ref, signal, global-cb) recorded from connect ops.
    connections: Vec<(i64, String, i64)>,
}

impl MockEngine {
    fn exec(&mut self, op: &Value) -> Value {
        self.ops.push(op.clone());
        if let Some(c) = op.get("chk").and_then(|v| v.as_i64()) {
            return json!(!self.chk_reject.contains(&c));
        }
        if let Some(g) = op.get("grant").and_then(|v| v.as_i64()) {
            let sbx = op.get("sbx").and_then(|v| v.as_i64()).unwrap_or(0);
            self.grants.push((g, sbx));
            return json!(true);
        }
        if let Some(sig) = op.get("connect").and_then(|v| v.as_str()) {
            let r = op.get("ref").and_then(|v| v.as_i64()).unwrap_or(0);
            let cb = op.get("cb").and_then(|v| v.as_i64()).unwrap_or(0);
            self.connections.push((r, sig.to_string(), cb));
            return Value::Null;
        }
        if op.get("new").is_some() || op.get("singleton").is_some() || op.get("load").is_some() {
            return json!(op.get("def").and_then(|v| v.as_i64()).unwrap_or(0));
        }
        Value::Null
    }
}

fn install_bridge(mgr: &mut VmManager, mock: &Rc<RefCell<MockEngine>>) {
    let hooked = mock.clone();
    mgr.set_bridge(Some(Box::new(move |name, args| {
        let mut m = hooked.borrow_mut();
        match name {
            "godot.op" => {
                let op = args.first().cloned().unwrap_or(Value::Null);
                Some(m.exec(&op))
            }
            "godot.batch" => {
                let ops = args.first().and_then(|v| v.as_array()).cloned().unwrap_or_default();
                Some(Value::Array(ops.iter().map(|op| m.exec(op)).collect()))
            }
            _ => None,
        }
    })));
}

/// Boot a manager whose root runs `root_source`, bridged to a fresh mock.
fn boot(root_source: &str) -> (VmManager, Rc<RefCell<MockEngine>>) {
    static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
    let mock = Rc::new(RefCell::new(MockEngine::default()));
    let mut mgr = VmManager::new_root(
        format!(
            "multi-vm-{}",
            NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
        ),
        root_source,
        true,
        0,
        0,
    )
    .expect("root program must compile");
    install_bridge(&mut mgr, &mock);
    mgr.run_root().expect("root main() runs");
    (mgr, mock)
}

fn emitted(mgr: &mut VmManager, vm: u64) -> Vec<Value> {
    mgr.runtime_mut(vm).map(|rt| rt.emitted().to_vec()).unwrap_or_default()
}

/// Escape a (plain) Dart source string for embedding into a Dart string
/// literal — apply once per nesting level.
/// A guest handle id as it reaches the engine: namespaced into the owning
/// VM's id space ((vm<<32)|local — see manager::encode_handle). Every VM's
/// prelude counts from 1, so un-namespaced ids would collide across VMs.
fn ns(vm: i64, id: i64) -> i64 {
    (vm << 32) | id
}

fn dq(source: &str) -> String {
    source.replace('\\', "\\\\").replace('"', "\\\"")
}

/// A trivial child that builds a node inside its sandbox and reports in.
const CHILD_BASIC: &str = r#"void main() { var s = GD.create("Sprite2D"); s.set("visible", true); askHost("test.emit", ["child-ran"]); }"#;

#[test]
fn spawn_boots_child_and_stamps_its_ops_with_its_sandbox() {
    let (mut mgr, mock) = boot(&format!(
        r#"
void main() {{
  var pod = GD.create("Node3D");
  var child = VMs.spawn("{}", pod, {{"label": "worker"}});
  askHost("test.emit", [child.id]);
}}
"#,
        dq(CHILD_BASIC)
    ));
    // Root emitted the child's id; the child booted and ran within run_root().
    assert_eq!(emitted(&mut mgr, ROOT_VM), vec![json!(2)]);
    assert_eq!(emitted(&mut mgr, 2), vec![json!("child-ran")]);
    assert!(mgr.vm_alive(2));

    let m = mock.borrow();
    // Root ops carry no sandbox tag (whole-scene role)…
    let root_new =
        m.ops.iter().find(|op| op.get("new").and_then(|v| v.as_str()) == Some("Node3D")).unwrap();
    assert!(root_new.get("__sbx").is_none(), "root is unrestricted");
    // …the child's ops are stamped with its assigned node handle (the pod,
    // guest handle 1 from the root's allocator, namespaced into vm 1's space).
    let child_new =
        m.ops.iter().find(|op| op.get("new").and_then(|v| v.as_str()) == Some("Sprite2D")).unwrap();
    assert_eq!(child_new.get("__sbx"), Some(&json!(ns(1, 1))), "child ops confined to its pod");
    let child_set = m.ops.iter().find(|op| op.get("set").is_some()).unwrap();
    assert_eq!(child_set.get("__sbx"), Some(&json!(ns(1, 1))));
    // The containment probe ran against the parent's (unrestricted) view.
    assert!(m.ops.iter().any(|op| op.get("chk").is_some()));
}

#[test]
fn guest_forged_sandbox_tags_are_stripped_and_restamped() {
    // The child tries to smuggle its own __sbx (999) into a raw op. The
    // manager must strip the forged key and stamp the real sandbox.
    let child = r#"void main() { GD.op({"new": "Node", "def": 50, "__sbx": 999}); }"#;
    let (_mgr, mock) = boot(&format!(
        r#"
void main() {{
  var pod = GD.create("Node3D");
  VMs.spawn("{}", pod, null);
}}
"#,
        dq(child)
    ));
    let m = mock.borrow();
    let forged = m
        .ops
        .iter()
        .find(|op| op.get("def").and_then(|v| v.as_i64()) == Some(ns(2, 50)))
        .unwrap();
    assert_eq!(
        forged.get("__sbx"),
        Some(&json!(ns(1, 1))),
        "forged tag replaced by the real sandbox"
    );
}

#[test]
fn callback_ids_are_namespaced_and_dispatch_routes_to_the_owning_vm() {
    let child = r#"void main() { var b = GD.create("Button"); b.connect("pressed", (args) { askHost("test.emit", ["child saw " + args[0]]); }); }"#;
    let (mut mgr, mock) = boot(&format!(
        r#"
void main() {{
  var pod = GD.create("Node3D");
  var btn = GD.create("Button");
  btn.connect("pressed", (args) {{ askHost("test.emit", ["root saw " + args[0]]); }});
  VMs.spawn("{}", pod, null);
}}
"#,
        dq(child)
    ));
    let (root_cb, child_cb) = {
        let m = mock.borrow();
        assert_eq!(m.connections.len(), 2);
        (m.connections[0].2, m.connections[1].2)
    };
    // Global ids carry the owning vm in the high 32 bits; both were local cb 1.
    assert_eq!(root_cb >> 32, 1, "root's callback namespaced under vm 1");
    assert_eq!(child_cb >> 32, 2, "child's callback namespaced under vm 2");
    assert_eq!(root_cb & 0xFFFF_FFFF, child_cb & 0xFFFF_FFFF, "both were local id 1");

    // The engine fires both; each lands in its own VM.
    mgr.invoke("__godotDispatch", json!([root_cb, ["ping"]]));
    mgr.invoke("__godotDispatch", json!([child_cb, ["pong"]]));
    assert_eq!(emitted(&mut mgr, ROOT_VM), vec![json!("root saw ping")]);
    assert_eq!(emitted(&mut mgr, 2), vec![json!("child saw pong")]);
}

#[test]
fn revoking_vm_manage_stops_a_child_from_spawning() {
    // The child tries to spawn a grandchild twice: once while permitted, then
    // after the root revokes its vm_manage on the fly (the executor
    // short-circuits every vm.* call to null).
    let grandchild = r#"void main() { askHost("test.emit", ["grandchild-ran"]); }"#;
    let child = format!(
        r#"var pod2 = null; void main() {{ pod2 = GD.create("Node3D"); var g = VMs.trySpawn("{gc}", pod2, null); askHost("test.emit", [g]); }} void again(a) {{ var g = VMs.trySpawn("{gc}", pod2, null); askHost("test.emit", [g == null]); }}"#,
        gc = dq(grandchild)
    );
    let (mut mgr, _mock) = boot(&format!(
        r#"
var child = null;
void main() {{
  var pod = GD.create("Node3D");
  child = VMs.spawn("{}", pod, null);
}}
void revoke(a) {{
  child.setPermission("vm_manage", false);
}}
"#,
        dq(&child)
    ));
    // First attempt succeeded: the child emitted the grandchild's vm id (3),
    // and the grandchild booted.
    assert_eq!(emitted(&mut mgr, 2), vec![json!(3)]);
    assert_eq!(emitted(&mut mgr, 3), vec![json!("grandchild-ran")]);

    // Root revokes vm_manage on the child, then the child tries again.
    mgr.invoke("revoke", Value::Null);
    mgr.runtime_mut(2).unwrap().deliver_event("again", Value::Null);
    mgr.settle();
    let e = emitted(&mut mgr, 2);
    assert_eq!(e.len(), 2);
    assert_eq!(e[1], json!(true), "vm.spawn short-circuited to null after revoke");
    assert_eq!(mgr.vm_ids().len(), 3, "no fourth VM was created");
}

#[test]
fn permission_revocation_propagates_to_the_whole_subtree() {
    // root -> child -> grandchild; revoking vm_manage on the CHILD must strip
    // it from the grandchild too (effective = AND over ancestors), and
    // re-granting restores it.
    let ggchild = r#"void main() { askHost("test.emit", ["leaf"]); }"#;
    let grandchild = format!(
        r#"var pod3 = null; void main() {{ pod3 = GD.create("Node3D"); askHost("test.emit", ["gc-ran"]); }} void trySpawnLeaf(a) {{ var g = VMs.trySpawn("{}", pod3, null); askHost("test.emit", [g == null]); }}"#,
        dq(ggchild)
    );
    let child = format!(
        r#"void main() {{ var pod2 = GD.create("Node3D"); VMs.spawn("{}", pod2, null); }}"#,
        dq(&grandchild)
    );
    let (mut mgr, _mock) = boot(&format!(
        r#"
var child = null;
void main() {{
  var pod = GD.create("Node3D");
  child = VMs.spawn("{}", pod, null);
}}
void revoke(a) {{ child.setPermission("vm_manage", false); }}
void grant(a) {{ child.setPermission("vm_manage", true); }}
"#,
        dq(&child)
    ));
    assert_eq!(emitted(&mut mgr, 3), vec![json!("gc-ran")]);

    // Revoke on the middle VM: the grandchild (vm 3) loses spawn too.
    mgr.invoke("revoke", Value::Null);
    mgr.runtime_mut(3).unwrap().deliver_event("trySpawnLeaf", Value::Null);
    mgr.settle();
    assert_eq!(
        emitted(&mut mgr, 3),
        vec![json!("gc-ran"), json!(true)],
        "null reply: denied"
    );

    // Re-grant on the middle VM: the grandchild can spawn again.
    mgr.invoke("grant", Value::Null);
    mgr.runtime_mut(3).unwrap().deliver_event("trySpawnLeaf", Value::Null);
    mgr.settle();
    let e = emitted(&mut mgr, 3);
    assert_eq!(e[2], json!(false), "spawn works again");
    assert_eq!(emitted(&mut mgr, 4), vec![json!("leaf")], "the new leaf booted");
}

#[test]
fn terminating_a_parent_kills_the_whole_subtree() {
    let grandchild = r#"void main() { askHost("test.emit", ["gc"]); }"#;
    let child = format!(
        r#"void main() {{ var pod2 = GD.create("Node3D"); VMs.spawn("{}", pod2, null); }}"#,
        dq(grandchild)
    );
    let (mut mgr, _mock) = boot(&format!(
        r#"
var child = null;
void main() {{
  VMs.onChildTerminated((kind, vmId, detail) {{
    askHost("test.emit", ["exit " + vmId]);
  }});
  var pod = GD.create("Node3D");
  child = VMs.spawn("{}", pod, null);
}}
void kill(a) {{ child.terminate(); }}
"#,
        dq(&child)
    ));
    assert!(mgr.vm_alive(2) && mgr.vm_alive(3));
    let child_machine = mgr.machine_of(3).unwrap();
    assert!(elpian_vm::api::vm_exists(child_machine.clone()));

    mgr.invoke("kill", Value::Null);
    assert!(!mgr.vm_alive(2), "child removed");
    assert!(!mgr.vm_alive(3), "grandchild removed with it");
    assert!(
        !elpian_vm::api::vm_exists(child_machine),
        "grandchild's registry entry destroyed"
    );
    // The parent (root) was notified of the removed branch root.
    assert_eq!(emitted(&mut mgr, ROOT_VM), vec![json!("exit 2")]);
}

#[test]
fn paused_vms_receive_no_events_until_resumed() {
    let child = r#"void main() { GD.onProcess((d) { askHost("test.emit", ["tick"]); }); }"#;
    let (mut mgr, _mock) = boot(&format!(
        r#"
var child = null;
void main() {{
  var pod = GD.create("Node3D");
  child = VMs.spawn("{}", pod, null);
}}
void pauseChild(a) {{ child.pause(); }}
void resumeChild(a) {{ child.resume(); }}
"#,
        dq(child)
    ));
    mgr.invoke("__godotEvent", json!(["_process", 0.016]));
    assert_eq!(emitted(&mut mgr, 2).len(), 1, "one tick before pause");

    mgr.invoke("pauseChild", Value::Null);
    mgr.invoke("__godotEvent", json!(["_process", 0.016]));
    mgr.invoke("__godotEvent", json!(["_process", 0.016]));
    assert_eq!(emitted(&mut mgr, 2).len(), 1, "no ticks while paused");

    mgr.invoke("resumeChild", Value::Null);
    mgr.invoke("__godotEvent", json!(["_process", 0.016]));
    assert_eq!(emitted(&mut mgr, 2).len(), 2, "ticks resume");
}

#[test]
fn a_hung_child_traps_on_its_own_budget_and_the_parent_is_notified() {
    // The child spins forever; its per-turn instruction cap cuts it off and
    // the parent's __vmNotify sees a 'trapped' notification.
    let child = r#"void main() { var i = 0; while (true) { i = i + 1; } }"#;
    let (mut mgr, _mock) = boot(&format!(
        r#"
void main() {{
  VMs.onChildTrapped((kind, vmId, detail) {{
    askHost("test.emit", ["trapped " + vmId]);
  }});
  var pod = GD.create("Node3D");
  VMs.spawn("{}", pod, {{"label": "runaway", "limits": {{"instructionsPerTurn": 20000}}}});
}}
"#,
        dq(child)
    ));
    assert_eq!(emitted(&mut mgr, ROOT_VM), vec![json!("trapped 2")]);
    assert!(!mgr.vm_alive(2), "trapped child is no longer schedulable");
    assert!(
        elpian_vm::api::trap_reason(&mgr.machine_of(2).unwrap()).is_some(),
        "trap reason preserved for the parent to inspect"
    );
}

#[test]
fn aggregate_budget_overrun_kills_the_whole_branch() {
    // The middle VM gets a lifetime instruction budget; its own work stays
    // under it, but its child's work counts against it too — the branch
    // (middle + worker) is terminated together and the root notified.
    let worker = r#"void main() { var i = 0; while (i < 60000) { i = i + 1; } askHost("test.emit", ["worked"]); }"#;
    let middle = format!(
        r#"void main() {{ var pod2 = GD.create("Node3D"); VMs.spawn("{}", pod2, null); askHost("test.emit", ["middle-up"]); }}"#,
        dq(worker)
    );
    let (mut mgr, _mock) = boot(&format!(
        r#"
void main() {{
  VMs.onNotify((kind, vmId, detail) {{
    askHost("test.emit", [kind + " " + vmId]);
  }});
  var pod = GD.create("Node3D");
  VMs.spawn("{}", pod, {{"label": "middle", "limits": {{"instructions": 50000}}}});
}}
"#,
        dq(&middle)
    ));
    assert!(!mgr.vm_alive(2), "middle VM terminated by the aggregate rule");
    assert!(!mgr.vm_alive(3), "worker terminated with its parent");
    let root_events = emitted(&mut mgr, ROOT_VM);
    assert!(
        root_events.iter().any(|e| e == &json!("terminated 2")),
        "root notified of the branch removal, got {root_events:?}"
    );
}

#[test]
fn spawn_is_rejected_when_the_node_is_outside_the_parent_sandbox() {
    // The containment probe (the `chk` op the manager issues before adopting
    // the child) is primed to reject the root's first guest handle.
    let mock = Rc::new(RefCell::new(MockEngine::default()));
    mock.borrow_mut().chk_reject.insert(ns(1, 1));
    let mut mgr = VmManager::new_root(
        "multi-vm-reject".to_string(),
        &format!(
            r#"
void main() {{
  var pod = GD.create("Node3D");
  var r = VMs.trySpawn("{}", pod, null);
  askHost("test.emit", [VMs.isError(r)]);
}}
"#,
            dq(CHILD_BASIC)
        ),
        true,
        0,
        0,
    )
    .unwrap();
    install_bridge(&mut mgr, &mock);
    mgr.run_root().unwrap();
    assert_eq!(emitted(&mut mgr, ROOT_VM), vec![json!(true)], "spawn errored");
    assert_eq!(mgr.vm_ids().len(), 1, "no child VM was created");
}

#[test]
fn parent_and_child_exchange_messages() {
    let child = r#"void main() { VMs.onMessage((sender, msg) { askHost("test.emit", ["from " + sender + ": " + msg]); VMs.sendParent("ack " + msg); }); }"#;
    let (mut mgr, _mock) = boot(&format!(
        r#"
var child = null;
void main() {{
  VMs.onMessage((sender, msg) {{
    askHost("test.emit", ["reply from " + sender + ": " + msg]);
  }});
  var pod = GD.create("Node3D");
  child = VMs.spawn("{}", pod, null);
}}
void ping(a) {{ child.send("hello"); }}
"#,
        dq(child)
    ));
    mgr.invoke("ping", Value::Null);
    assert_eq!(emitted(&mut mgr, 2), vec![json!("from 1: hello")]);
    assert_eq!(emitted(&mut mgr, ROOT_VM), vec![json!("reply from 2: ack hello")]);
}

#[test]
fn scene_permission_lifts_the_sandbox_and_revocation_restores_it() {
    let child = r#"void main() { GD.create("Node2D"); } void makeMore(a) { GD.create("Node2D"); }"#;
    let (mut mgr, mock) = boot(&format!(
        r#"
var child = null;
void main() {{
  var pod = GD.create("Node3D");
  child = VMs.spawn("{}", pod, null);
}}
void liftSandbox(a) {{ child.setPermission("scene", true); }}
void dropSandbox(a) {{ child.setPermission("scene", false); }}
"#,
        dq(child)
    ));
    let tags = |mock: &Rc<RefCell<MockEngine>>| {
        let m = mock.borrow();
        m.ops
            .iter()
            .filter(|op| op.get("new").and_then(|v| v.as_str()) == Some("Node2D"))
            .map(|op| op.get("__sbx").cloned())
            .collect::<Vec<_>>()
    };
    assert_eq!(tags(&mock), vec![Some(json!(ns(1, 1)))], "sandboxed at boot");

    mgr.invoke("liftSandbox", Value::Null);
    mgr.runtime_mut(2).unwrap().deliver_event("makeMore", Value::Null);
    assert_eq!(tags(&mock)[1], None, "scene access lifts the tag");

    mgr.invoke("dropSandbox", Value::Null);
    mgr.runtime_mut(2).unwrap().deliver_event("makeMore", Value::Null);
    assert_eq!(tags(&mock)[2], Some(json!(ns(1, 1))), "revocation restores the sandbox");
}

#[test]
fn usage_and_state_are_visible_across_the_tree() {
    let child = r#"void main() { var i = 0; while (i < 5000) { i = i + 1; } }"#;
    let (mut mgr, _mock) = boot(&format!(
        r#"
var child = null;
void main() {{
  var pod = GD.create("Node3D");
  child = VMs.spawn("{}", pod, {{"label": "meter"}});
}}
void report(a) {{
  var u = child.usage();
  var t = VMs.of(1).usageTree();
  var s = child.state();
  askHost("test.emit", [u["instructions"] > 4999]);
  askHost("test.emit", [t["instructions"] > u["instructions"]]);
  askHost("test.emit", [s["label"]]);
  askHost("test.emit", [s["alive"]]);
}}
"#,
        dq(child)
    ));
    mgr.invoke("report", Value::Null);
    assert_eq!(
        emitted(&mut mgr, ROOT_VM),
        vec![json!(true), json!(true), json!("meter"), json!(true)]
    );
}

#[test]
fn free_ops_are_namespaced_like_their_defs() {
    // queue_free must reach the engine under the SAME namespaced id the node
    // was created with — for the root VM and for children alike. Before the
    // `free` key joined rewrite_handles, the op carried the guest-LOCAL id,
    // resolved to nothing, and the node silently lived forever (the immortal
    // sheet-scrim bug: an invisible full-screen Button eating every tap).
    use elpian_godot::GuestLang;
    let child_src = "function main() { let n = GD.create('Node3D'); n.queueFree(); } main();";
    let root_src = r#"
        import 'godot.js';
        function main() {
          let junk = GD.create("Node3D");
          junk.queueFree();
          let pod = GD.create("Node3D");
          let child = VMs.spawn(__CHILD__, pod, { lang: "js", label: "freer" });
          print("spawned=" + (child != null));
        }
        main();
    "#
    .replace("__CHILD__", &format!("{:?}", child_src));
    let mock = Rc::new(RefCell::new(MockEngine::default()));
    let mut mgr = VmManager::new_root_lang(
        "multi-vm-free-ns".into(),
        &root_src,
        GuestLang::Js,
        true,
        0,
        0,
    )
    .expect("root program must compile");
    install_bridge(&mut mgr, &mock);
    mgr.run_root().expect("root main() runs");
    for _ in 0..10 {
        mgr.pump(16).expect("pump");
    }
    let log = mgr.take_log().join("\n");
    assert!(log.contains("spawned=true"), "spawn failed: {log}");

    let ops = mock.borrow().ops.clone();
    let defs: HashSet<i64> = ops
        .iter()
        .filter(|o| o.get("new").is_some())
        .filter_map(|o| o.get("def").and_then(|v| v.as_i64()))
        .collect();
    let frees: Vec<i64> = ops
        .iter()
        .filter_map(|o| o.get("free").and_then(|v| v.as_i64()))
        .collect();
    assert!(!frees.is_empty(), "no free ops reached the engine: {ops:?}");
    for f in &frees {
        assert!(
            defs.contains(f),
            "free op id {f} does not match any created def {defs:?} — the node it names can never be resolved"
        );
    }
    assert!(
        frees.iter().any(|f| (f >> 32) == 2),
        "no free op from the child VM's id space arrived: {frees:?}"
    );
}
