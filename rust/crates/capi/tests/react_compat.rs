//! Does the React runtime still work on the current Elpian?
//!
//! `react.js` is 2,600 lines of hook machinery and a keyed reconciler that
//! mutates retained Godot nodes. It was exercised by exactly one thing — the
//! Tritonix fixture, which imports it and checks the program *compiles*. Nobody
//! had checked that `useState` schedules a re-render, that a state update in
//! one component leaves its siblings alone, that the reconciler reuses nodes
//! instead of rebuilding the tree, or that effects and cleanups run.
//!
//! Two things worth knowing before reading these:
//!
//! * Every guest is written in React's own vocabulary (`createElement(Text,
//!   …)`), never by calling `VUI.*` imperatively. Mixing the two hands a React
//!   element to a function expecting a Godot node, and the tree silently comes
//!   out empty.
//! * Every guest is bounded, by host-call meter and instruction ceiling. A
//!   React test that loops — an oscillating reducer, an effect that
//!   re-schedules itself — would otherwise run until the machine dies rather
//!   than failing.

use std::cell::RefCell;
use std::rc::Rc;

use elpian_godot::GodotSurface;
use elpian_godot::{GuestLang, VmManager, ROOT_VM};
use serde_json::{json, Value};

/// A fake Godot behind the bridge seam.
#[derive(Default)]
struct MockEngine {
    ops: Vec<Value>,
}

impl MockEngine {
    /// How many nodes of `class` were created over the whole run. Keeping this
    /// flat across re-renders is the reconciler's job.
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

/// A booted guest, which tears its VM tree down when the test ends.
///
/// The VM registry is process-global and a `VmManager` does not clear it when
/// dropped, so without this every test's compiled prelude — ~250 KB of
/// bytecode each — stays resident for the whole run.
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
    let source = format!("import 'react.js';\n{program}");

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
// Hooks
// ---------------------------------------------------------------------------

#[test]
fn use_state_holds_a_value_and_its_setter_schedules_a_rerender() {
    let mut g = boot(
        "react-usestate",
        r#"
function Counter() {
  var s = useState(0);
  askHost("test.emit", ["render:" + s[0]]);
  if (s[0] === 0) { s[1](1); }
  return createElement(Text, { children: "" + s[0] });
}
VictorClient.render(createElement(Counter, null), GD.create("Control"));
"#,
    );

    assert_eq!(
        g.emitted(),
        vec![json!("render:0"), json!("render:1")],
        "a state update should schedule exactly one re-render"
    );
}

#[test]
fn setting_state_to_the_same_value_does_not_rerender() {
    let mut g = boot(
        "react-bailout",
        r#"
var renders = 0;
function Same() {
  var s = useState(7);
  renders = renders + 1;
  askHost("test.emit", ["render:" + renders]);
  if (renders < 3) { s[1](7); }
  return createElement(Text, { children: "x" });
}
VictorClient.render(createElement(Same, null), GD.create("Control"));
"#,
    );

    assert_eq!(
        g.emitted(),
        vec![json!("render:1")],
        "setting the same value must bail out, not loop"
    );
}

#[test]
fn use_reducer_dispatches_through_the_reducer() {
    let mut g = boot(
        "react-reducer",
        r#"
function reducer(state, action) {
  if (action === "inc") { return state + 1; }
  return state;
}
var steps = 0;
function App() {
  var r = useReducer(reducer, 10);
  askHost("test.emit", [r[0]]);
  steps = steps + 1;
  if (steps < 3) { r[1]("inc"); }
  return createElement(Text, { children: "r" });
}
VictorClient.render(createElement(App, null), GD.create("Control"));
"#,
    );

    assert_eq!(g.emitted(), vec![json!(10), json!(11), json!(12)]);
}

#[test]
fn use_memo_holds_its_value_across_renders() {
    let mut g = boot(
        "react-memo",
        r#"
var computed = 0;
function App() {
  var s = useState(0);
  var stable = useMemo(function () { computed = computed + 1; return 42; }, []);
  askHost("test.emit", ["n=" + s[0] + " computed=" + computed + " memo=" + stable]);
  if (s[0] < 2) { s[1](s[0] + 1); }
  return createElement(Text, { children: "m" });
}
VictorClient.render(createElement(App, null), GD.create("Control"));
"#,
    );

    let out = g.lines();
    assert_eq!(out.len(), 3, "three renders: {out:?}");
    for (i, line) in out.iter().enumerate() {
        assert!(
            line.contains("computed=1"),
            "useMemo with [] deps recomputed on render {i}: {line}"
        );
        assert!(line.contains("memo=42"), "memo lost its value: {line}");
    }
}

#[test]
fn use_ref_persists_across_renders() {
    let mut g = boot(
        "react-ref",
        r#"
function App() {
  var s = useState(0);
  var r = useRef(0);
  r.current = r.current + 1;
  askHost("test.emit", ["ref=" + r.current]);
  if (s[0] < 2) { s[1](s[0] + 1); }
  return createElement(Text, { children: "r" });
}
VictorClient.render(createElement(App, null), GD.create("Control"));
"#,
    );

    assert_eq!(
        g.emitted(),
        vec![json!("ref=1"), json!("ref=2"), json!("ref=3")]
    );
}

#[test]
fn an_effect_runs_after_the_render_that_scheduled_it() {
    let mut g = boot(
        "react-effect-order",
        r#"
function App() {
  useEffect(function () { askHost("test.emit", ["effect"]); }, []);
  askHost("test.emit", ["render"]);
  return createElement(Text, { children: "e" });
}
VictorClient.render(createElement(App, null), GD.create("Control"));
"#,
    );

    assert_eq!(
        g.emitted(),
        vec![json!("render"), json!("effect")],
        "an effect must run after its render, not during it"
    );
}

#[test]
fn an_effect_with_empty_deps_runs_once_however_often_the_component_renders() {
    let mut g = boot(
        "react-effect-once",
        r#"
function App() {
  var s = useState(0);
  useEffect(function () { askHost("test.emit", ["mounted"]); }, []);
  if (s[0] < 3) { s[1](s[0] + 1); }
  return createElement(Text, { children: "o" });
}
VictorClient.render(createElement(App, null), GD.create("Control"));
"#,
    );

    let mounts = g
        .emitted()
        .iter()
        .filter(|v| *v == &json!("mounted"))
        .count();
    assert_eq!(mounts, 1, "an effect with [] deps must run exactly once");
}

#[test]
fn a_dependency_change_cleans_up_before_the_effect_reruns() {
    // Driven from a deferred callback rather than during render: an update
    // *during* render makes every pass drain before the commit, so only the
    // final effect runs — correct React behaviour, but not what this checks.
    let mut g = boot(
        "react-effect-cleanup",
        r#"
var bump = null;
function App() {
  var s = useState(0);
  bump = s[1];
  useEffect(function () {
    askHost("test.emit", ["effect:" + s[0]]);
    return function () { askHost("test.emit", ["cleanup:" + s[0]]); };
  }, [s[0]]);
  return createElement(Text, { children: "e" });
}
VictorClient.render(createElement(App, null), GD.create("Control"));
__later(function () { bump(1); });
"#,
    );

    assert_eq!(
        g.lines(),
        vec!["effect:0", "cleanup:0", "effect:1"],
        "a dependency change must clean up the old effect before running the new"
    );
}

#[test]
fn context_reaches_a_nested_consumer() {
    let mut g = boot(
        "react-context",
        r#"
var Theme = createContext("light");
function Leaf() {
  askHost("test.emit", [useContext(Theme)]);
  return createElement(Text, { children: "leaf" });
}
function Middle() { return createElement(Leaf, null); }
function App() {
  return createElement(Theme.Provider, { value: "dark" },
    createElement(Middle, null));
}
VictorClient.render(createElement(App, null), GD.create("Control"));
"#,
    );

    assert_eq!(g.emitted(), vec![json!("dark")]);
}

// ---------------------------------------------------------------------------
// Re-render isolation
// ---------------------------------------------------------------------------

#[test]
fn a_state_update_rerenders_only_the_component_that_owns_it() {
    let mut g = boot(
        "react-isolation",
        r#"
function Quiet() {
  askHost("test.emit", ["quiet"]);
  return createElement(Text, { children: "quiet" });
}
function Noisy() {
  var s = useState(0);
  askHost("test.emit", ["noisy:" + s[0]]);
  if (s[0] < 2) { s[1](s[0] + 1); }
  return createElement(Text, { children: "noisy" });
}
function App() {
  return createElement(Column, { children: [
    createElement(Quiet, null),
    createElement(Noisy, null),
  ] });
}
VictorClient.render(createElement(App, null), GD.create("Control"));
"#,
    );

    let out = g.lines();
    let quiet = out.iter().filter(|s| *s == "quiet").count();
    let noisy = out.iter().filter(|s| s.starts_with("noisy")).count();

    assert_eq!(
        quiet, 1,
        "a sibling with no state of its own must not re-render: {out:?}"
    );
    assert_eq!(noisy, 3, "the owner should render three times: {out:?}");
}

#[test]
fn memo_stops_a_rerender_when_props_are_unchanged() {
    let mut g = boot(
        "react-memo-component",
        r#"
var Child = memo(function (props) {
  askHost("test.emit", ["child:" + props.label]);
  return createElement(Text, { children: props.label });
});
function App() {
  var s = useState(0);
  askHost("test.emit", ["app:" + s[0]]);
  if (s[0] < 2) { s[1](s[0] + 1); }
  return createElement(Column, { children: [
    createElement(Child, { label: "fixed" }),
  ] });
}
VictorClient.render(createElement(App, null), GD.create("Control"));
"#,
    );

    let out = g.lines();
    let child = out.iter().filter(|s| s.starts_with("child")).count();
    assert_eq!(
        child, 1,
        "a memo'd child with unchanged props must render once: {out:?}"
    );
}

// ---------------------------------------------------------------------------
// The reconciler
// ---------------------------------------------------------------------------

#[test]
fn rerendering_updates_a_node_in_place_instead_of_rebuilding_it() {
    let g = boot(
        "react-reuse",
        r#"
function App() {
  var s = useState("a");
  if (s[0] === "a") { s[1]("b"); }
  return createElement(Text, { children: s[0] });
}
VictorClient.render(createElement(App, null), GD.create("Control"));
"#,
    );

    let m = g.ops();
    let labels = m.created("Label");
    assert!(
        labels <= 1,
        "the reconciler rebuilt the node instead of updating it: {labels} Labels"
    );
    assert_eq!(m.freed(), 0, "nothing should have been freed");
}

#[test]
fn a_keyed_list_reorders_without_recreating_its_items() {
    let g = boot(
        "react-keys",
        r#"
function App() {
  var s = useState(0);
  var items = s[0] === 0 ? ["a", "b", "c"] : ["c", "a", "b"];
  if (s[0] === 0) { s[1](1); }
  var kids = [];
  for (var i = 0; i < items.length; i++) {
    kids.push(createElement(Text, { key: items[i], children: items[i] }));
  }
  return createElement(Column, { children: kids });
}
VictorClient.render(createElement(App, null), GD.create("Control"));
"#,
    );

    let labels = g.ops().created("Label");
    assert!(
        labels <= 3,
        "a keyed reorder recreated items: {labels} Labels for 3 keys"
    );
}

#[test]
fn removing_a_child_frees_its_node_and_runs_its_cleanup() {
    let mut g = boot(
        "react-unmount",
        r#"
function Child() {
  useEffect(function () {
    return function () { askHost("test.emit", ["child-cleanup"]); };
  }, []);
  return createElement(Text, { children: "child" });
}
var hide = null;
function App() {
  var s = useState(true);
  hide = s[1];
  return createElement(Column, {
    children: s[0] ? [createElement(Child, null)] : [],
  });
}
VictorClient.render(createElement(App, null), GD.create("Control"));
__later(function () { hide(false); });
"#,
    );

    assert!(
        g.emitted().contains(&json!("child-cleanup")),
        "an unmounting component must run its effect cleanups"
    );
    assert!(g.ops().freed() > 0, "removing a child should free its node");
}
