//! Do the two widget surfaces agree about what a widget is?
//!
//! `gui.js` unified where a widget is *declared* — one registry entry, from
//! which both the declarative `Button({...})` and the imperative
//! `GUI.button({...})` are generated. `ui.js`'s older kit, `VUI.button(...)`,
//! is a third thing: an independent implementation of the same widgets, kept
//! because mini apps are written against it.
//!
//! Nothing compared them. This does, by recording the Godot class each surface
//! builds. The recording works by bracketing each call with a sentinel
//! `GD.create`: `GD` is a class with `static create`, and the subset resolves
//! statics by name at compile time, so there is no function value a guest could
//! wrap. The sentinel rides the same op stream as the real creations, which
//! makes the segmentation exact — no assumption about ordering between the op
//! seam and the emit seam.
//!
//! What it compares is the whole ordered *construction trace*: every class the
//! call creates, in order. That is stricter than comparing the returned node's
//! class and it is what actually decides whether a mini app gets the same
//! widget — a `Button` styled with four `StyleBoxFlat`s is a different widget
//! from a `Button` styled with one, however identical their types.
//!
//! A divergence is not automatically a bug. The two have different calling
//! conventions, and some differ on purpose: VUI returns a `{node, setValue}`
//! handle for stateful widgets where the registry returns a bare node, and the
//! registry's containers accept many children where VUI's take one. The
//! differences that are intended are listed in the test; anything else fails.

use std::cell::RefCell;
use std::rc::Rc;

use elpian_godot::GodotSurface;
use elpian_godot::{GuestLang, VmManager};
use serde_json::Value;

/// The marker a probe writes into the op stream before each call.
const SENTINEL: &str = "__ElpianParityProbe__";

#[derive(Default)]
struct MockEngine {
    /// Every class name passed to `new`, in order — sentinels included.
    created: Vec<String>,
}

struct Guest {
    mock: Rc<RefCell<MockEngine>>,
    machine: String,
}

impl Drop for Guest {
    fn drop(&mut self) {
        elpian_vm::api::destroy_vm_tree(&self.machine);
    }
}

impl Guest {
    fn created(&self) -> Vec<String> {
        self.mock.borrow().created.clone()
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
    mgr.set_bridge(Some(Box::new(move |name: &str, args: &[Value]| {
        fn note(m: &mut MockEngine, op: &Value) {
            if let Some(cls) = op.get("new").and_then(|v| v.as_str()) {
                m.created.push(cls.to_string());
            }
        }
        let mut m = sink.borrow_mut();
        match name {
            "godot.op" => {
                let op = args.first().cloned().unwrap_or(Value::Null);
                note(&mut m, &op);
                // Reads must answer with *something*: a widget that styles
                // itself by reading a value back must not see an error.
                if op.get("get").is_some() || op.get("method").is_some() {
                    return Some(Value::Null);
                }
                Some(Value::Bool(true))
            }
            "godot.batch" => {
                if let Some(Value::Array(list)) = args.first() {
                    for op in list {
                        note(&mut m, op);
                    }
                }
                Some(Value::Bool(true))
            }
            _ => None,
        }
    })));

    let _ = mgr.run_root();
    mgr.settle();
    assert_eq!(
        elpian_vm::api::trap_reason(machine),
        None,
        "{machine} trapped"
    );
    Guest {
        mock,
        machine: machine.to_string(),
    }
}

/// The widgets both surfaces provide, with a call to each.
///
/// Written out rather than derived, because the two have genuinely different
/// calling conventions — `VUI.text(str, opts)` against `GUI.text({children})`,
/// `VUI.center({child})` against `GUI.center({children})`. That mismatch is
/// half of what makes the two hard to keep in step, and generating the calls
/// would hide the very thing this test exists to show.
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

/// The guest program: a sentinel, then the call, for every side of every pair.
fn program() -> String {
    let mut src = String::new();
    for (name, vui, gui) in PAIRS {
        for (side, call) in [("vui", vui), ("gui", gui)] {
            src.push_str(&format!(
                "GD.create(\"{SENTINEL}{name}.{side}\");\n\
                 try {{ {call}; }} catch (e) {{ GD.create(\"{SENTINEL}!\" + e); }}\n"
            ));
        }
    }
    src
}

/// Split the recorded creations on sentinels, giving each probe the ordered
/// `A+B+C` trace of what it built.
fn segments(created: &[String]) -> Vec<(String, String)> {
    let mut out: Vec<(String, String)> = Vec::new();
    for cls in created {
        match cls.strip_prefix(SENTINEL) {
            Some(label) if !label.starts_with('!') => out.push((label.to_string(), String::new())),
            Some(err) => {
                if let Some(last) = out.last_mut() {
                    last.1 = format!("<error: {}>", &err[1..]);
                }
            }
            None => {
                if let Some(last) = out.last_mut() {
                    if !last.1.starts_with('<') {
                        if !last.1.is_empty() {
                            last.1.push('+');
                        }
                        last.1.push_str(cls);
                    }
                }
            }
        }
    }
    for seg in out.iter_mut() {
        if seg.1.is_empty() {
            seg.1 = "<none>".into();
        }
    }
    out
}

#[test]
fn both_widget_surfaces_build_the_same_widget_except_where_recorded() {
    let g = boot("widget-parity", &program());
    let segs = segments(&g.created());
    assert_eq!(
        segs.len(),
        PAIRS.len() * 2,
        "every probe should have run; got {segs:?}"
    );

    let rows: Vec<(&str, String, String)> = PAIRS
        .iter()
        .enumerate()
        .map(|(i, (name, _, _))| (*name, segs[i * 2].1.clone(), segs[i * 2 + 1].1.clone()))
        .collect();

    // Neither surface may fail outright. A widget that throws where its twin
    // builds a node is not a difference of convention.
    let broken: Vec<String> = rows
        .iter()
        .filter(|(_, v, u)| v.starts_with('<') || u.starts_with('<'))
        .map(|(n, v, u)| format!("  {n:<10} VUI {v}\n             GUI {u}"))
        .collect();
    assert!(
        broken.is_empty(),
        "a widget surface failed to build a node:\n{}",
        broken.join("\n")
    );

    // Where the older imperative kit and the registry genuinely build different
    // things, and why.
    //
    // The list is short, and that is the finding: the reconciler's widget
    // driver already reuses VUI for styling and typography — 10 of its 13
    // builders call into it — so what the two duplicate is node construction
    // and prop application, not the design system. Every divergence below is
    // one extra node the registry builds because its calling convention is
    // wider, not a second opinion about what the widget looks like.
    //
    // Pinned so the list can only change deliberately: a widget drifting into
    // it is a regression that would otherwise be invisible.
    let known_divergent: &[(&str, &str)] = &[
        // The registry pads children in a MarginContainer of its own; VUI
        // leaves padding to the style box on the surface.
        ("panel", "registry adds a MarginContainer for child padding"),
        ("card", "registry adds a MarginContainer for child padding"),
        // `Scroll({children: [...]})` takes many children and needs a box to
        // put them in; `VUI.scroll({child})` takes exactly one.
        (
            "scroll",
            "registry adds a VBoxContainer to hold several children",
        ),
        // The registry gives the checkbox its own label node; VUI expects the
        // caller to place one beside it.
        (
            "checkbox",
            "registry builds the label, VUI leaves it to the caller",
        ),
    ];

    let mut unexpected = Vec::new();
    let mut converged = Vec::new();
    for (name, vui, gui) in &rows {
        let listed = known_divergent.iter().any(|(n, _)| n == name);
        match (vui == gui, listed) {
            (false, false) => unexpected.push(format!(
                "  {name:<10} VUI      {vui}\n             registry {gui}"
            )),
            (true, true) => converged.push(*name),
            _ => {}
        }
    }

    assert!(
        unexpected.is_empty(),
        "these widgets' two surfaces build different things, and that is not \
         recorded as intentional:\n{}\n\nBoth are supposed to be the same \
         widget. Where they differ, one of them is what a mini app gets and the \
         other is what it gets somewhere else.",
        unexpected.join("\n")
    );
    assert!(
        converged.is_empty(),
        "these widgets no longer diverge — drop them from `known_divergent` so \
         the list keeps meaning something: {converged:?}"
    );
}
