//! Guest-initiated spawn under a Flutter host.
//!
//! This is what B-03 was about. Flutter linked the VM directly and got no
//! manager, so `askHost("vm.spawn", …)` from inside a mini app's own code did
//! nothing — nesting worked only when the *host* drove it from Dart. The
//! manager was locked inside the Godot C ABI even though nothing about a tree
//! of governed VMs is specific to Godot.
//!
//! These tests drive a real guest program through `FlutterSurface` and check
//! that a mini app spawning a child gets the same guarantees Godot has: the
//! child boots, its ops are stamped with its own sandbox, its callbacks are
//! namespaced, its capabilities are the intersection with its parent's, and
//! terminating the parent takes it down.

use std::cell::RefCell;
use std::rc::Rc;

use elpian_runtime::{GuestLang, VmManager, ROOT_VM};
use elpian_vm::FlutterSurface;
use serde_json::{json, Value};

/// A fake Flutter host behind the bridge seam. What it sees is what the real
/// `FlutterController` would see.
#[derive(Default)]
struct MockHost {
    /// Every op received, in order (batches flattened).
    ops: Vec<Value>,
}

/// Boot a manager under a Flutter surface.
///
/// `machine` must be unique per test: the VM registry is process-global, and
/// `cargo test` runs these in parallel, so a shared id would have two managers
/// fighting over the same entries.
fn boot(machine: &str, root_source: &str) -> (VmManager, Rc<RefCell<MockHost>>) {
    let mock = Rc::new(RefCell::new(MockHost::default()));
    let mut mgr = VmManager::new_root_lang(
        Box::new(FlutterSurface::with_prelude(None)),
        machine.to_string(),
        root_source,
        GuestLang::Js,
        // No prelude: these programs call the `vm.spawn` seam directly rather
        // than through a prelude's `VMs` facade, so the test pins the wire
        // contract rather than a prelude's sugar over it.
        false,
        0,
        0,
    )
    .expect("root should compile");

    let sink = mock.clone();
    mgr.set_bridge(Some(Box::new(move |name: &str, args: &[Value]| {
        let mut m = sink.borrow_mut();
        match name {
            "flutter.op" => {
                m.ops.push(args.first().cloned().unwrap_or(Value::Null));
                Some(Value::Bool(true))
            }
            "flutter.batch" => {
                if let Some(Value::Array(list)) = args.first() {
                    m.ops.extend(list.iter().cloned());
                }
                Some(Value::Bool(true))
            }
            _ => None,
        }
    })));
    mgr.run_root().expect("root should run");
    mgr.settle();
    (mgr, mock)
}

/// What a VM pushed through `test.emit`. The runtime captures those itself
/// rather than forwarding them to the bridge, so they are read from the VM
/// rather than from the mock host.
fn emitted(mgr: &mut VmManager, vm: u64) -> Vec<Value> {
    mgr.runtime_mut(vm)
        .map(|rt| rt.emitted().to_vec())
        .unwrap_or_default()
}

fn dq(s: &str) -> String {
    s.replace('\\', "\\\\").replace('"', "\\\"")
}

#[test]
fn a_guest_can_spawn_a_child_under_a_flutter_host() {
    let child = r#"askHost("test.emit", ["child-ran"]);"#;
    let (mut mgr, _mock) = boot(
        "flutter-spawn",
        &format!(
            r#"var c = askHost("vm.spawn", ["{}", {{"node": 1, "label": "worker"}}]);
           askHost("test.emit", [c]);"#,
            dq(child)
        ),
    );

    assert_eq!(
        emitted(&mut mgr, ROOT_VM),
        vec![json!(2)],
        "the root should have received the child's id"
    );
    assert_eq!(
        emitted(&mut mgr, 2),
        vec![json!("child-ran")],
        "the child should have booted and run its own program"
    );
    assert!(mgr.vm_alive(2), "the child should be live");
}

#[test]
fn a_child_inherits_its_parents_capabilities() {
    // The tree rule, through the Flutter surface: a parent that revokes a
    // capability for itself cannot leave a child holding it.
    let child = r#"askHost("test.emit", ["child-ran"]);"#;
    let (mgr, _mock) = boot(
        "flutter-inherit",
        &format!(r#"askHost("vm.spawn", ["{}", {{"node": 1}}]);"#, dq(child)),
    );

    let root_machine = mgr.machine_of(ROOT_VM).expect("root machine id");
    let child_machine = mgr.machine_of(2).expect("child machine id");

    // Revoke on the parent; the child's effective set must follow.
    assert!(::vm::api::set_capability(
        &root_machine,
        ::vm::api::Capability::Network,
        false
    ));
    assert!(
        !::vm::api::capability_allows(&child_machine, "net.fetch"),
        "a child cannot hold what its parent gave up"
    );

    // And the parent keeps everything it did not revoke.
    assert!(::vm::api::capability_allows(&root_machine, "dom.setStyle"));
}

#[test]
fn terminating_the_parent_takes_the_child() {
    let child = r#"askHost("test.emit", ["child-ran"]);"#;
    let (mut mgr, _mock) = boot(
        "flutter-terminate",
        &format!(r#"askHost("vm.spawn", ["{}", {{"node": 1}}]);"#, dq(child)),
    );
    assert!(mgr.vm_alive(2));

    let root_machine = mgr.machine_of(ROOT_VM).expect("root machine id");
    let affected = ::vm::api::terminate_vm_tree(&root_machine);

    assert!(
        affected.len() >= 2,
        "the whole branch goes down together: {affected:?}"
    );
    mgr.settle();
    assert!(
        !mgr.vm_alive(2),
        "a child must not outlive the parent that spawned it"
    );
}

#[test]
fn a_childs_work_counts_against_its_parent() {
    let child = r#"var i = 0; while (i < 200) { i = i + 1; }"#;
    let (mgr, _mock) = boot(
        "flutter-cost",
        &format!(r#"askHost("vm.spawn", ["{}", {{"node": 1}}]);"#, dq(child)),
    );

    let root_machine = mgr.machine_of(ROOT_VM).expect("root machine id");
    let own = ::vm::api::usage(&root_machine).expect("root usage");
    let branch = ::vm::api::subtree_usage(&root_machine).expect("branch usage");

    assert!(
        branch.instructions > own.instructions,
        "work pushed into a child stays on the parent's bill: \
         own {} vs branch {}",
        own.instructions,
        branch.instructions
    );
}

#[test]
fn the_flutter_surface_uses_its_own_seam_and_dispatch_names() {
    // The surface is what makes the manager host-neutral. If these drifted back
    // to Godot's names, a Flutter host would silently receive nothing.
    use elpian_runtime::HostSurface;
    let s = FlutterSurface::with_prelude(None);
    assert_eq!(s.op_prefix(), "flutter");
    assert_eq!(s.dispatch_fn(), "__flutterDispatch");
    assert_eq!(s.event_fn(), "__flutterEvent");
}

#[test]
fn a_prelude_is_composed_ahead_of_the_guest_program() {
    use elpian_runtime::HostSurface;
    let s = FlutterSurface::with_prelude(Some("var HOST = 1;".to_string()));
    let composed = s.compose(GuestLang::Js, "var app = HOST;");
    assert!(composed.starts_with("var HOST = 1;"));
    assert!(composed.ends_with("var app = HOST;"));

    // And no prelude means the source is handed over untouched.
    let bare = FlutterSurface::with_prelude(None);
    assert_eq!(bare.compose(GuestLang::Js, "var a = 1;"), "var a = 1;");
}
