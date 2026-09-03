//! Do the two widget surfaces agree about what a widget is?
//!
//! `gui.js` unified where a widget is *declared* — one registry entry, from
//! which both the declarative `Button({...})` and the imperative
//! `GUI.button({...})` are generated. `ui.js`'s older kit, `VUI.button(...)`,
//! is a third thing: an independent implementation of the same widgets, kept
//! because mini apps are written against it.
//!
//! Nothing compared them. This does, by recording the Godot class each surface
//! builds: the guest stamps a marker into the op stream before each probe, and
//! the ops between two markers are one widget's construction. (Wrapping
//! `GD.create` from inside the guest would read better, but `GD` is a class of
//! statics and the subset resolves those by name at compile time — there is no
//! function value there to wrap.) A divergence is not
//! automatically a bug — the two have different calling conventions, and some
//! deliberately differ (VUI returns a `{node, setValue}` handle for stateful
//! widgets where the registry returns a bare node). What the test pins is the
//! *node class*: if one builds a `Button` and the other a `Label`, they are not
//! the same widget however similar their props read, and a mini app gets
//! different behaviour depending on which vocabulary it happened to use.
//!
//! Everything runs in one VM. Booting a guest per widget was 34 VM trees for a
//! question that is really "what does this one call create", and the answer is
//! available from inside the guest for free.

use std::cell::RefCell;
use std::rc::Rc;

use elpian_godot::GodotSurface;
use elpian_godot::{GuestLang, VmManager, ROOT_VM};
use serde_json::Value;

/// The class name the guest creates to separate one probe from the next.
const MARK: &str = "__ProbeMark__";

#[derive(Default)]
struct MockEngine {
    /// Every class passed to `GD.create`, in order, markers included.
    created: Vec<String>,
}

struct Guest {
    mgr: VmManager,
    mock: Rc<RefCell<MockEngine>>,
    machine: String,
}

impl Drop for Guest {
    fn drop(&mut self) {
        elpian_vm::api::destroy_vm_tree(&self.machine);
    }
}

impl Guest {
    fn lines(&mut self) -> Vec<String> {
        self.mgr
            .runtime_mut(ROOT_VM)
            .map(|rt| {
                rt.emitted()
                    .iter()
                    .map(|v| v.as_str().unwrap_or("").to_string())
                    .collect()
            })
            .unwrap_or_default()
    }
}

fn boot(machine: &str, program: &str) -> Guest {
    let mock = Rc::new(RefCell::new(MockEngine::default()));
    let source = format!("import 'gui.js';\n{program}");

    let mut mgr = VmManager::new_root_lang(
        Box::new(GodotSurface),
        machine.to_string(),
        &source,
        GuestLang::Js,
        true,
        200_000,
        0,
    )
    .unwrap_or_else(|e| panic!("{machine} should compile: {e}"));

    elpian_vm::api::set_limits(
        machine,
        elpian_vm::api::ResourceLimits {
            max_instructions: Some(200_000_000),
            ..elpian_vm::api::ResourceLimits::unlimited()
        },
    );

    let sink = mock.clone();
    let note = move |op: &Value| {
        if let Some(cls) = op.get("new").and_then(|v| v.as_str()) {
            sink.borrow_mut().created.push(cls.to_string());
        }
    };
    mgr.set_bridge(Some(Box::new(
        move |name: &str, args: &[Value]| match name {
            "godot.op" => {
                let op = args.first().cloned().unwrap_or(Value::Null);
                note(&op);
                // Reads answer null; the kits tolerate it and carry on building.
                if op.get("get").is_some() || op.get("method").is_some() {
                    return Some(Value::Null);
                }
                Some(Value::Bool(true))
            }
            "godot.batch" => {
                if let Some(Value::Array(list)) = args.first() {
                    for op in list {
                        note(op);
                    }
                }
                Some(Value::Bool(true))
            }
            _ => None,
        },
    )));

    let _ = mgr.run_root();
    mgr.settle();
    assert_eq!(
        elpian_vm::api::trap_reason(machine),
        None,
        "{machine} trapped"
    );
    Guest {
        mgr,
        mock,
        machine: machine.to_string(),
    }
}

/// The widgets both surfaces provide, with a call to each.
///
/// Written out rather than derived, because the two have genuinely different
/// calling conventions — `VUI.text(str, opts)` against `GUI.text({children})`,
/// `VUI.center({child})` against `GUI.center({children})`. That mismatch is
/// half of what makes them hard to keep in step, and generating the calls
/// would hide the very thing this test is here to show.
const PAIRS: &[(&str, &str, &str)] = &[
    // (widget, the VUI call, the registry call)
    (
        "text",
        r#"VUI.text("hi")"#,
        r#"GUI.text({ children: "hi" })"#,
    ),
    (
        "heading",
        r#"VUI.heading("hi")"#,
        r#"GUI.heading({ children: "hi" })"#,
    ),
    (
        "caption",
        r#"VUI.caption("hi")"#,
        r#"GUI.caption({ children: "hi" })"#,
    ),
    (
        "button",
        r#"VUI.button("go")"#,
        r#"GUI.button({ children: "go" })"#,
    ),
    (
        "column",
        r#"VUI.column({ children: [] })"#,
        r#"GUI.column({ children: [] })"#,
    ),
    (
        "row",
        r#"VUI.row({ children: [] })"#,
        r#"GUI.row({ children: [] })"#,
    ),
    (
        "grid",
        r#"VUI.grid({ children: [] })"#,
        r#"GUI.grid({ children: [] })"#,
    ),
    (
        "panel",
        r#"VUI.panel({ children: [] })"#,
        r#"GUI.panel({ children: [] })"#,
    ),
    (
        "card",
        r#"VUI.card({ children: [] })"#,
        r#"GUI.card({ children: [] })"#,
    ),
    (
        "center",
        r#"VUI.center({ child: null })"#,
        r#"GUI.center({ children: [] })"#,
    ),
    (
        "scroll",
        r#"VUI.scroll({ child: null })"#,
        r#"GUI.scroll({ children: [] })"#,
    ),
    ("spacer", r#"VUI.spacer()"#, r#"GUI.spacer({})"#),
    ("divider", r#"VUI.divider({})"#, r#"GUI.divider({})"#),
    ("image", r#"VUI.image({})"#, r#"GUI.image({})"#),
    (
        "progress",
        r#"VUI.progress({ value: 50 })"#,
        r#"GUI.progress({ value: 50 })"#,
    ),
    (
        "slider",
        r#"VUI.slider({ value: 50 })"#,
        r#"GUI.slider({ value: 50 })"#,
    ),
    (
        "checkbox",
        r#"VUI.checkbox({ value: false })"#,
        r#"GUI.checkbox({})"#,
    ),
    ("textarea", r#"VUI.textarea({})"#, r#"GUI.textarea({})"#),
];

/// Build the guest program: intercept `GD.create`, then run each pair.
///
/// The *last* class created is taken as the widget's own. Not the first:
/// several VUI widgets build their styling (a `StyleBoxFlat`, a `Theme`) before
/// the node it is applied to, and a first-created reading would compare
/// stylesheets rather than widgets. The node a factory returns is the last
/// thing it makes in both kits.
fn program() -> String {
    let mut src = String::from(
        r#"
function __probe(label, f) {
  GD.create("__ProbeMark__");
  let err = "";
  try { f(); } catch (e) { err = "" + e; }
  askHost("test.emit", [label + "|" + err]);
}
"#,
    );
    for (name, vui, gui) in PAIRS {
        src.push_str(&format!("__probe(\"{name}.vui\", () => {{ {vui}; }});\n"));
        src.push_str(&format!("__probe(\"{name}.gui\", () => {{ {gui}; }});\n"));
    }
    src
}

/// Split the recorded classes into one segment per probe, in order.
fn segments(created: &[String]) -> Vec<Vec<String>> {
    let mut out: Vec<Vec<String>> = Vec::new();
    for cls in created {
        if cls == MARK {
            out.push(Vec::new());
        } else if let Some(last) = out.last_mut() {
            last.push(cls.clone());
        }
    }
    out
}

#[test]
fn the_two_widget_surfaces_build_the_same_node_for_every_shared_widget() {
    let mut g = boot("widget-parity", &program());
    let out = g.lines();
    assert_eq!(
        out.len(),
        PAIRS.len() * 2,
        "every probe should have reported; got {out:?}"
    );

    let created = g.mock.borrow().created.clone();
    let segs = segments(&created);
    assert_eq!(segs.len(), PAIRS.len() * 2, "one segment per probe");

    // Neither surface may fail outright. A widget that throws where its twin
    // builds a node is not a difference of convention.
    let failed: Vec<&String> = out.iter().filter(|l| !l.ends_with('|')).collect();
    assert!(failed.is_empty(), "a widget surface raised: {failed:?}");

    let mut wrong_class = Vec::new();
    let mut extra = Vec::new();
    for (i, (name, _, _)) in PAIRS.iter().enumerate() {
        let vui = &segs[i * 2];
        let gui = &segs[i * 2 + 1];
        // The widget's own node is the first thing either kit creates; the
        // style boxes, gradients and fonts that follow are what gets applied
        // to it.
        let (a, b) = (vui.first(), gui.first());
        if a != b {
            wrong_class.push(format!(
                "  {name:<10} VUI built {a:?}, the registry built {b:?}"
            ));
        } else if vui != gui {
            extra.push((name.to_string(), vui.clone(), gui.clone()));
        }
    }

    assert!(
        wrong_class.is_empty(),
        "these widgets' two surfaces build different Godot node classes:\n{}\n\n\
         Both are supposed to be the same widget. Where they differ, one of \
         them is what a mini app gets and the other is what it gets somewhere \
         else.",
        wrong_class.join("\n")
    );

    // Same node, different scaffolding around it. Each of these is a deliberate
    // difference between an imperative factory and one driven by a reconciler,
    // and each is named — so a widget acquiring an *unexplained* difference
    // fails here rather than being absorbed into a tolerance.
    let explained: &[(&str, &str)] = &[
        // The reconciler needs a stable node to add and remove children from
        // across renders; the imperative kit is handed its children once, at
        // construction, and needs no such slot.
        ("panel", "MarginContainer"),
        ("card", "MarginContainer"),
        ("scroll", "VBoxContainer"),
        // `VUI.checkbox` is called by both — the registry additionally renders
        // the `label` prop, which the imperative call above does not pass.
        ("checkbox", "Label"),
    ];

    let mut unexplained = Vec::new();
    for (name, vui, gui) in &extra {
        let diff: Vec<&String> = gui.iter().filter(|c| !vui.contains(c)).collect();
        let ok = explained
            .iter()
            .any(|(n, c)| n == name && diff.iter().all(|d| d.as_str() == *c));
        if !ok {
            unexplained.push(format!(
                "  {name:<10} VUI {vui:?}\n             GUI {gui:?}"
            ));
        }
    }
    assert!(
        unexplained.is_empty(),
        "these widgets build the same node but differ in what they build \
         around it, and the difference is not one of the recorded ones:\n{}",
        unexplained.join("\n")
    );

    let unused: Vec<&str> = explained
        .iter()
        .map(|(n, _)| *n)
        .filter(|n| !extra.iter().any(|(name, _, _)| name == n))
        .collect();
    assert!(
        unused.is_empty(),
        "these widgets no longer differ — drop them from `explained` so the \
         list keeps meaning something: {unused:?}"
    );
}
