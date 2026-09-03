//! The unified GUI SDK.
//!
//! `gui.js` is the SDK: the engine transport, the Flutter surface, the widget
//! kit and the reconciler merged into one file, plus the widget registry that
//! is the reason to merge them. As four separate preludes, `ui.js` and
//! `react.js` each carried their own list of which widgets existed — VUI's
//! factories against the driver's tags — with nothing keeping the two in step,
//! so a widget could be present in one and absent from the other. Here a widget is defined once and both surfaces are
//! generated from it. (Whether the two build the *same* node is measured
//! separately, in `widget_parity.rs`.)
//!
//! These check the parts that are new: class components, the registry driving
//! both surfaces, the Scene3D and Canvas controllers, and scoping.

use std::cell::RefCell;
use std::rc::Rc;

use elpian_godot::GodotSurface;
use elpian_godot::{GuestLang, VmManager, ROOT_VM};
use serde_json::{json, Value};

#[derive(Default)]
struct MockEngine {
    ops: Vec<Value>,
}

impl MockEngine {
    fn created(&self, class: &str) -> usize {
        self.ops
            .iter()
            .filter(|op| op.get("new").and_then(|v| v.as_str()) == Some(class))
            .count()
    }

    fn freed(&self) -> usize {
        self.ops
            .iter()
            .filter(|op| op.get("free").is_some())
            .count()
    }
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
    fn emitted(&mut self) -> Vec<Value> {
        self.mgr
            .runtime_mut(ROOT_VM)
            .map(|rt| rt.emitted().to_vec())
            .unwrap_or_default()
    }

    fn lines(&mut self) -> Vec<String> {
        self.emitted()
            .iter()
            .map(|v| v.as_str().unwrap_or("").to_string())
            .collect()
    }

    fn ops(&self) -> std::cell::Ref<'_, MockEngine> {
        self.mock.borrow()
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
        50_000,
        0,
    )
    .unwrap_or_else(|e| panic!("{machine} should compile: {e}"));

    elpian_vm::api::set_limits(
        machine,
        elpian_vm::api::ResourceLimits {
            max_instructions: Some(40_000_000),
            ..elpian_vm::api::ResourceLimits::unlimited()
        },
    );

    let sink = mock.clone();
    mgr.set_bridge(Some(Box::new(move |name: &str, args: &[Value]| {
        let mut m = sink.borrow_mut();
        match name {
            "godot.op" => {
                let op = args.first().cloned().unwrap_or(Value::Null);
                m.ops.push(op.clone());
                if op.get("get").is_some() || op.get("method").is_some() {
                    return Some(Value::Null);
                }
                Some(Value::Bool(true))
            }
            "godot.batch" => {
                if let Some(Value::Array(list)) = args.first() {
                    m.ops.extend(list.iter().cloned());
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
        "{machine} trapped while running"
    );

    Guest {
        mgr,
        mock,
        machine: machine.to_string(),
    }
}

// ---------------------------------------------------------------------------
// The registry — one definition, two surfaces
// ---------------------------------------------------------------------------

#[test]
fn every_widget_appears_as_both_a_component_and_a_builder() {
    // The property the merge exists for. A name in the registry must produce
    // both `Button` and `GUI.button`, with no second list to keep in step.
    let mut g = boot(
        "gui-both-surfaces",
        r#"
let names = GUI.widgets();
askHost("test.emit", ["widgets:" + names.length]);
let missing = [];
for (let i = 0; i < names.length; i++) {
  let n = names[i];
  let comp = n.substring(0, 1).toUpperCase() + n.substring(1);
  if (!__isType(GUI[comp], "function")) { missing.push("component " + comp); }
  if (!__isType(GUI[n], "function")) { missing.push("builder " + n); }
}
askHost("test.emit", ["missing:" + missing.length]);
"#,
    );

    let out = g.lines();
    let count: i64 = out[0].replace("widgets:", "").parse().unwrap_or(0);
    assert!(
        count >= 20,
        "the registry should carry the whole widget set, got {count}"
    );
    assert_eq!(
        out[1], "missing:0",
        "a widget is missing one of its surfaces"
    );
}

#[test]
fn a_widget_registered_at_runtime_gets_both_surfaces_too() {
    // Adding a widget is one registry entry, not an entry plus two bindings.
    let mut g = boot(
        "gui-define",
        r#"
GUI.defineWidget("marker", {
  container: false,
  create: (props) => { let n = GD.create("Label"); n.set("text", props.label); return n; },
});
let comp = GUI.component("marker");
askHost("test.emit", [__isType(comp, "function")]);
let node = GUI.build("marker", { label: "hi" });
askHost("test.emit", [node != null]);
"#,
    );

    assert_eq!(g.emitted(), vec![json!(true), json!(true)]);
}

#[test]
fn the_imperative_and_declarative_paths_build_the_same_widget() {
    // Both go through the registry, so both produce the same Godot class. When
    // The kit and the reconciler each had their own button; nothing checked this.
    let g = boot(
        "gui-same-widget",
        r#"
let imperative = GUI.text({ children: "a" });
GUI.render(Text({ children: "b" }), GD.create("Control"));
"#,
    );

    let m = g.ops();
    assert!(
        m.created("Label") >= 2,
        "both surfaces should have built a Label, saw {}",
        m.created("Label")
    );
}

// ---------------------------------------------------------------------------
// Class components
// ---------------------------------------------------------------------------

#[test]
fn a_class_component_renders_and_holds_state() {
    let mut g = boot(
        "gui-class-state",
        r#"
class CounterImpl extends Component {
  constructor(props) { super(props); this.state = { n: 0 }; }
  render() {
    askHost("test.emit", ["render:" + this.state.n]);
    if (this.state.n === 0) { this.setState({ n: 1 }); }
    return Text({ children: "" + this.state.n });
  }
}
const Counter = GUI.component(CounterImpl);
GUI.render(createElement(Counter, null), GD.create("Control"));
"#,
    );

    assert_eq!(
        g.emitted(),
        vec![json!("render:0"), json!("render:1")],
        "setState should schedule exactly one re-render"
    );
}

#[test]
fn set_state_merges_rather_than_replacing() {
    let mut g = boot(
        "gui-class-merge",
        r#"
class MImpl extends Component {
  constructor(props) { super(props); this.state = { a: 1, b: 2 }; }
  render() {
    askHost("test.emit", ["a=" + this.state.a + " b=" + this.state.b]);
    if (this.state.a === 1) { this.setState({ a: 9 }); }
    return Text({ children: "m" });
  }
}
const M = GUI.component(MImpl);
GUI.render(createElement(M, null), GD.create("Control"));
"#,
    );

    assert_eq!(
        g.emitted(),
        vec![json!("a=1 b=2"), json!("a=9 b=2")],
        "setState with one key must leave the others alone"
    );
}

#[test]
fn set_state_with_no_change_does_not_rerender() {
    let mut g = boot(
        "gui-class-bailout",
        r#"
class SImpl extends Component {
  constructor(props) { super(props); this.state = { n: 7 }; this.renders = 0; }
  render() {
    this.renders = this.renders + 1;
    askHost("test.emit", ["render:" + this.renders]);
    if (this.renders < 3) { this.setState({ n: 7 }); }
    return Text({ children: "s" });
  }
}
const S = GUI.component(SImpl);
GUI.render(createElement(S, null), GD.create("Control"));
"#,
    );

    assert_eq!(
        g.emitted(),
        vec![json!("render:1")],
        "an unchanged setState must bail out, not loop"
    );
}

#[test]
fn lifecycle_runs_in_order() {
    let mut g = boot(
        "gui-lifecycle",
        r#"
var hide = null;
class ChildImpl extends Component {
  componentDidMount() { askHost("test.emit", ["mount"]); }
  componentDidUpdate(prevProps, prevState) { askHost("test.emit", ["update"]); }
  componentWillUnmount() { askHost("test.emit", ["unmount"]); }
  render() { askHost("test.emit", ["render"]); return Text({ children: "c" }); }
}
const Child = GUI.component(ChildImpl);
class ShellImpl extends Component {
  constructor(props) { super(props); this.state = { show: true }; }
  render() {
    hide = () => { this.setState({ show: false }); };
    return Column({ children: this.state.show ? [createElement(Child, null)] : [] });
  }
}
const Shell = GUI.component(ShellImpl);
GUI.render(createElement(Shell, null), GD.create("Control"));
GUI.soon(() => { hide(); });
"#,
    );

    assert_eq!(
        g.lines(),
        vec!["render", "mount", "unmount"],
        "mount after the first render; unmount when the child goes away"
    );
}

#[test]
fn should_component_update_can_skip_a_render() {
    let mut g = boot(
        "gui-scu",
        r#"
class FrozenImpl extends Component {
  constructor(props) { super(props); this.state = { n: 0 }; }
  shouldComponentUpdate(nextProps, nextState) { return false; }
  render() {
    askHost("test.emit", ["render:" + this.state.n]);
    if (this.state.n === 0) { this.setState({ n: 1 }); }
    return Text({ children: "f" });
  }
}
const Frozen = GUI.component(FrozenImpl);
GUI.render(createElement(Frozen, null), GD.create("Control"));
"#,
    );

    assert_eq!(
        g.emitted(),
        vec![json!("render:0")],
        "shouldComponentUpdate returning false must skip the re-render"
    );
}

#[test]
fn class_and_function_components_compose() {
    // They are not two systems: one reconciler, one update queue.
    let mut g = boot(
        "gui-compose",
        r#"
function Leaf(props) {
  askHost("test.emit", ["leaf:" + props.label]);
  return Text({ children: props.label });
}
class BranchImpl extends Component {
  constructor(props) { super(props); this.state = { n: 0 }; }
  render() {
    askHost("test.emit", ["branch:" + this.state.n]);
    if (this.state.n === 0) { this.setState({ n: 1 }); }
    return Column({ children: [createElement(Leaf, { label: "" + this.state.n })] });
  }
}
const Branch = GUI.component(BranchImpl);
GUI.render(createElement(Branch, null), GD.create("Control"));
"#,
    );

    assert_eq!(
        g.lines(),
        vec!["branch:0", "leaf:0", "branch:1", "leaf:1"],
        "a class component's children re-render with it"
    );
}

// ---------------------------------------------------------------------------
// Scoping
// ---------------------------------------------------------------------------

#[test]
fn a_scope_reads_through_its_parent_and_shadows_it() {
    let mut g = boot(
        "gui-scope",
        r#"
let root = GUI.scope();
root.set("theme", "dark");
let panel = root.child("panel");
askHost("test.emit", [panel.get("theme")]);
panel.set("theme", "light");
askHost("test.emit", [panel.get("theme")]);
askHost("test.emit", [root.get("theme")]);
askHost("test.emit", [panel.path()]);
"#,
    );

    assert_eq!(
        g.emitted(),
        vec![
            json!("dark"),
            json!("light"),
            json!("dark"),
            json!("app/panel")
        ],
        "a child reads through, shadows locally, and does not write upward"
    );
}

#[test]
fn disposing_a_scope_disposes_its_children_and_what_they_own() {
    let mut g = boot(
        "gui-scope-dispose",
        r#"
let root = GUI.scope().child("region");
let inner = root.child("inner");
inner.own({ dispose: () => { askHost("test.emit", ["inner-disposed"]); } });
root.own({ dispose: () => { askHost("test.emit", ["root-disposed"]); } });
root.dispose();
"#,
    );

    assert_eq!(
        g.lines(),
        vec!["inner-disposed", "root-disposed"],
        "children dispose first, so a parent never tears down under a live child"
    );
}

// ---------------------------------------------------------------------------
// Scene3D and Canvas
// ---------------------------------------------------------------------------

#[test]
fn a_scene3d_controller_spawns_and_frees_what_it_owns() {
    let mut g = boot(
        "gui-scene3d",
        r#"
let holder = GUI.build("scene3d", { width: 100, height: 100 });
let scene = holder.__scene;
scene.camera.moveTo(0, 2, 5);
let cube = scene.spawn("MeshInstance3D", { position: [1, 0, 0] });
askHost("test.emit", [scene.spawned.length]);
scene.dispose();
askHost("test.emit", [scene.spawned.length]);
"#,
    );

    assert_eq!(
        g.emitted(),
        vec![json!(1), json!(0)],
        "the controller owns what it spawns and releases it on dispose"
    );
    let m = g.ops();
    assert!(
        m.created("Camera3D") >= 1,
        "the camera should have been created"
    );
    assert!(
        m.created("MeshInstance3D") >= 1,
        "the cube should have been created"
    );
    assert!(m.freed() > 0, "dispose should have freed the spawned nodes");
}

#[test]
fn using_a_disposed_scene_reports_rather_than_corrupting_it() {
    let mut g = boot(
        "gui-scene3d-disposed",
        r#"
let scene = GUI.build("scene3d", {}).__scene;
scene.dispose();
let caught = "none";
try { scene.spawn("MeshInstance3D", null); } catch (e) { caught = "" + e; }
askHost("test.emit", [caught.length > 0 && caught !== "none"]);
"#,
    );

    assert_eq!(
        g.emitted(),
        vec![json!(true)],
        "spawning into a disposed scene must report, not silently leak a node"
    );
}

#[test]
fn a_canvas_controller_accumulates_and_commits_one_display_list() {
    // Retained, not immediate: a chart redrawing every frame would otherwise
    // cross the host seam once per primitive.
    let mut g = boot(
        "gui-canvas",
        r#"
let canvas = GUI.build("canvas", { width: 100, height: 40 }).__canvas;
canvas.rect(0, 0, 10, 10, "white");
canvas.line(0, 0, 10, 10, "black", 2);
canvas.circle(5, 5, 3, "red");
askHost("test.emit", [canvas.count()]);
canvas.clear();
askHost("test.emit", [canvas.count()]);
"#,
    );

    assert_eq!(
        g.emitted(),
        vec![json!(3), json!(0)],
        "commands accumulate until cleared or committed"
    );
}

#[test]
fn canvas_commands_carry_their_parameters() {
    let mut g = boot(
        "gui-canvas-params",
        r#"
let canvas = GUI.build("canvas", {}).__canvas;
canvas.rect(1, 2, 3, 4, "grey");
canvas.text(5, 6, "hello", "blue", 12);
let a = canvas.commands[0];
let b = canvas.commands[1];
askHost("test.emit", [a.op + ":" + a.x + "," + a.y + "," + a.w + "," + a.h]);
askHost("test.emit", [b.op + ":" + b.text + ":" + b.size]);
"#,
    );

    assert_eq!(
        g.lines(),
        vec!["rect:1,2,3,4", "text:hello:12"],
        "a command should carry exactly what it was given"
    );
}
