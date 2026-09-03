// =============================================================================
// gui.js — the Elpian GUI SDK
// =============================================================================
//
// Everything a mini app needs to draw itself: state, rendering, scoping,
// widgets, styling, 3D scenes and 2D canvases. One import, one vocabulary.
//
//     import 'gui.js';
//
//     class CounterImpl extends Component {
//       constructor(props) { super(props); this.state = { n: 0 }; }
//       render() {
//         return Column({ gap: 8, children: [
//           Text({ children: "count: " + this.state.n }),
//           Button({ onPress: () => this.setState({ n: this.state.n + 1 }),
//                    children: "+1" }),
//         ]});
//       }
//     }
//     const Counter = GUI.component(CounterImpl);
//     GUI.mount(Counter);
//
// ## What this is, and what it composes
//
// The SDK is four layers a guest used to import in combination, and one file —
// this one — that unifies them:
//
//     godot.js   the engine transport: GD/GObj, marshaling, callbacks
//     flutter.js FL, driving an embedded Flutter engine
//     ui.js      VUI: theme, typography, metrics, and an imperative widget kit
//     react.js   VReact: elements, hooks, the scheduler and the reconciler
//     gui.js     ← this file: the widget registry, components, controllers
//
// Importing `gui.js` pulls all five in; the composer resolves the chain, so a
// mini app writes one import line and gets one vocabulary. The four layers
// remain their own files and their own tests — this is a *composition*, not a
// copy of them. (It was briefly a copy: gui.js carried its own inlined
// duplicate of all four, which is how you end up with two of everything again
// one file down.)
//
// ## What it adds: one list of what exists
//
// `ui.js` and `react.js` both build widgets, in two different shapes. VUI's
// factories are imperative — `VUI.slider({...})` hands back a
// `{node, setValue}` handle — while the reconciler's driver builds a node it
// can then patch across renders and rebind signals on. They already share
// their styling (`VUI.styleBox`, `fieldStyle`, `sliderStyle`, `fonts`), and
// for a few widgets the driver calls the VUI factory outright. What they did
// not share was a *list*: each knew its own set of widgets, and neither knew
// the other's.
//
// So the two could disagree about what existed rather than about what a
// button looked like. A widget added to one was simply absent from the other,
// silently, and a guest found out by getting nothing back.
//
// Here a widget is registered **once** (§1) and both surfaces are generated
// from that entry:
//
//   * the declarative one, `Button({...})`, which the reconciler drives;
//   * the imperative one, `GUI.button({...})`, which returns a node directly.
//
// Adding a widget is one registry entry, and both appear. `GUI.defineWidget`
// gives a mini app the same deal for widgets of its own.
//
// `widget_parity.rs` measures the two against each other — same node class,
// per widget, with every remaining difference in the scaffolding around it
// named — so "they agree" is a checked property rather than an intention.
//
// ## Layout
//
//   §1  Widget registry       one definition per widget, two surfaces
//   §2  Components            the Component base class, class and function
//   §3  Scene3D               the 3D widget and its controller
//   §4  Canvas                the 2D drawing widget and its controller
//   §5  Imperative facade     GUI.*, generated from the registry
//   §6  Scoping               named regions within one mini app
//   §7  The GUI namespace     what a mini app actually reaches for
//
// ## Class and function components
//
// Every widget is available both ways, because both are the right answer
// somewhere. A function component is the shortest thing that can work; a class
// component is what you want once a widget owns lifecycle, imperative handles
// or a controller (a Scene3D driving a camera, a Canvas holding a draw list).
// They render through the same reconciler and compose freely.
//
// ## Scoping
//
// A mini app's tree is isolated by construction: every node it creates is
// stamped with its sandbox by the host, and every callback id is namespaced to
// its VM. `GUI.scope()` adds the *guest-side* half — a named subtree whose
// state, styles and controllers are its own, so one part of an app cannot
// reach into another's.
// =============================================================================
// §1  The widget registry
// =============================================================================
//
// One definition per widget, used by both surfaces.
//
// Before this there was no such list. `ui.js` knew the widgets its factories
// covered and `react.js` knew the tags its driver handled, and the two sets
// were maintained apart — a widget in one and not the other was invisible
// until a guest asked for it. (The bodies were never as divided as the lists:
// the driver already styles through `VUI.styleBox` and friends, and delegates
// `checkbox`, `switch` and `center` to the kit outright.) Here a widget is one
// object:
//
//     GUI.defineWidget("badge", {
//       container: false,
//       create: (props, theme) => { …build and return a Godot node… },
//       update: (node, prev, props, theme) => { …apply changed props… },
//     });
//
// and both `Badge({...})` (declarative) and `GUI.badge({...})` (imperative)
// appear, because §2 and §5 generate them from this table.
//
// `update` is what makes the declarative path cheap: the reconciler calls it
// with the previous props so a re-render mutates the node it already has
// instead of rebuilding the subtree. A widget that omits `update` is rebuilt
// on every change, which is correct but wasteful — so every widget here has
// one.

var __guiWidgets = {};

/// Register a widget. See the module header for the shape.
///
/// `name` is the intrinsic tag the element model uses (`"button"`), and the
/// component and facade names are derived from it (`Button`, `GUI.button`).
function defineWidget(name, spec) {
  if (name == null || name === "") {
    throw "gui: a widget needs a name";
  }
  if (spec == null || !__isType(spec.create, "function")) {
    throw "gui: widget '" + name + "' needs a create(props, theme) function";
  }
  __guiWidgets[name] = {
    name: name,
    // Container widgets take element children the reconciler mounts as real
    // child instances. Leaves collapse their children into text.
    container: spec.container == true,
    create: spec.create,
    update: __isType(spec.update, "function") ? spec.update : null,
    // Called before the node is freed, for widgets holding host resources
    // (a Scene3D's viewport, a Canvas's draw list).
    dispose: __isType(spec.dispose, "function") ? spec.dispose : null,
    // Optional controller factory. When present, the widget's instance gets a
    // `controller` a component can reach through a ref — how Scene3D and
    // Canvas expose imperative operations without leaking their nodes.
    controller: __isType(spec.controller, "function") ? spec.controller : null,
  };
  return __guiWidgets[name];
}

/// The registered widget for `name`, or null.
function widgetFor(name) {
  return __guiWidgets[name];
}

/// Every registered widget name. Used to generate the two surfaces, and useful
/// to a host that wants to know what a mini app can draw.
function widgetNames() {
  let out = [];
  for (let k in __guiWidgets) {
    out.push(k);
  }
  return out;
}

/// Whether `tag` is a container. The reconciler asks this to decide whether an
/// element's children are mounted or collapsed into text.
function __guiIsContainer(tag) {
  let w = __guiWidgets[tag];
  if (w == null) {
    return false;
  }
  return w.container;
}
// =============================================================================
// §1b  The built-in widgets
// =============================================================================
//
// Every widget the SDK ships, registered once.
//
// The bodies delegate to the driver `react.js` already carries (`__vrDriverCreate` /
// `__vrDriverUpdate`), which is the implementation that was already there and
// is covered by the React tests. Registering them rather than rewriting them is
// deliberate: the duplication being removed is *two* implementations of each
// widget, and adding a third to fix that would be an odd way to go about it.
//
// What changes is where a widget is *defined*. Both surfaces — the declarative
// `Button({...})` and the imperative `GUI.button({...})` — now come from this
// table, so there is one list of what exists, one place to add to, and no way
// for the two to disagree about what a button is.

/// The active theme, as the widget bodies want it.
function __guiTheme() {
  return VUI.theme();
}

/// Replace the theme. Widgets built afterwards use it; already-built nodes keep
/// the styling they were given, which is why an app sets its theme before it
/// mounts rather than during.
function __guiSetTheme(t) {
  return VUI.theme(t);
}

/// A minimal instance for the driver to fill in.
///
/// The driver was written against the reconciler's fiber, which carries far
/// more than creating a node needs. This is the subset it actually reads, so
/// the imperative path can use the same code without pretending to be a fiber.
function __guiDriverInstance(tag, props) {
  return {
    kind: "host",
    tag: tag,
    props: props == null ? {} : props,
    node: null,
    container: null,
    childInstances: [],
    hooks: [],
    alive: true,
  };
}

/// Register `tag` as a widget whose create/update run through the driver.
function __guiRegisterDriverWidget(tag, isContainer) {
  defineWidget(tag, {
    container: isContainer,
    create: (props) => {
      let inst = __guiDriverInstance(tag, props);
      __vrDriverCreate(inst);
      // The driver distinguishes the node it built from the node children go
      // into — a card's outer panel versus its inner column. Callers want the
      // outer one, and `addChild` on it is routed by the driver.
      if (inst.container != null && inst.container !== inst.node) {
        inst.node.__guiSlot = inst.container;
      }
      return inst.node;
    },
    update: (node, prev, props) => {
      let inst = __guiDriverInstance(tag, props);
      inst.node = node;
      inst.container = node.__guiSlot == null ? node : node.__guiSlot;
      __vrDriverUpdate(inst, prev, props);
      return node;
    },
  });
}

// The widget set, and whether each takes element children.
//
// Kept as one table rather than a call per widget so the shape of the SDK is
// readable at a glance — and so a reviewer can see immediately that a tag the
// driver handles is registered, or that it is not.
var __GUI_CONTAINERS = [
  "view", "column", "row", "stack", "scroll", "center",
  "panel", "card", "grid",
];

var __GUI_LEAVES = [
  "text", "heading", "caption", "icon",
  "button", "input", "textarea", "select",
  "image", "progress", "slider", "switch", "checkbox", "divider", "spacer",
  "richtext",
];

for (let i = 0; i < __GUI_CONTAINERS.length; i++) {
  __guiRegisterDriverWidget(__GUI_CONTAINERS[i], true);
}
for (let i = 0; i < __GUI_LEAVES.length; i++) {
  __guiRegisterDriverWidget(__GUI_LEAVES[i], false);
}
// =============================================================================
// §2  Components — class and function, one reconciler
// =============================================================================
//
// A function component is a function from props to elements. A class component
// is an object with `render()`, `state` and `setState()`. Both are the right
// answer somewhere: a function is the shortest thing that can work, and a class
// is what you want once a widget owns lifecycle, an imperative handle or a
// controller — a Scene3D driving a camera, a Canvas holding a draw list.
//
// They are not two systems. A class component is rendered by the same
// reconciler as a function one: the machinery calls `__guiRenderClass`, which
// keeps the instance on the fiber and calls `render()`. `setState` schedules
// through the same queue as `useState`, so an update from either kind
// coalesces with the other's in one flush.

/// The base class a class component extends.
///
///     class Counter extends Component {
///       state = { n: 0 };
///       componentDidMount() { this.timer = GUI.every(1000, () => this.tick()); }
///       componentWillUnmount() { this.timer.cancel(); }
///       tick() { this.setState({ n: this.state.n + 1 }); }
///       render() { return Text({ children: "" + this.state.n }); }
///     }
class Component {
  /// The marker `__guiIsClassComponent` reads. Inherited by every subclass, so
  /// a component is recognised for extending Component rather than for being
  /// named or registered anywhere.
  static isGuiComponent = true;

  constructor(props) {
    this.props = props == null ? {} : props;
    this.state = {};
    // Set by the reconciler when it mounts this instance. Not for a component
    // to touch; it is how `setState` finds its way back into the scheduler.
    this.__fiber = null;
    this.__mounted = false;
    // Updates queued by `setState` and applied before the next render, so
    // `this.state` never changes underneath a render that is already running.
    this.__pending = null;
  }

  /// Merge `patch` into `state` and schedule a re-render.
  ///
  /// Merges rather than replaces, so `setState({a: 1})` leaves `b` alone —
  /// the behaviour a reader coming from React expects. Passing a function
  /// gives you the current state, for an update that depends on it.
  setState(patch) {
    // Resolved against what state *will* be, so two setState calls in one turn
    // compose: `setState(s => ({n: s.n + 1}))` twice adds two.
    let effective = this.__effectiveState();
    let next = __isType(patch, "function") ? patch(effective) : patch;
    if (next == null) {
      return;
    }
    let changed = false;
    for (let k in next) {
      if (effective[k] !== next[k]) {
        if (this.__pending == null) {
          this.__pending = {};
        }
        this.__pending[k] = next[k];
        changed = true;
      }
    }
    // Nothing moved: skip the render rather than doing a whole pass to
    // discover the tree is identical. Same bail-out `useState` does.
    if (!changed) {
      return;
    }
    // Scheduled as soon as the fiber exists, which is before the first commit.
    // `setState` during the initial render is legal — it is how a component
    // derives state from props — and gating on `__mounted` silently dropped it.
    if (this.__fiber != null) {
      __vrScheduleUpdate(this.__fiber);
    }
  }

  /// Force a re-render even though state did not change. For a component
  /// reading something the reconciler cannot see — a controller's internals,
  /// an external store without a subscription.
  forceUpdate() {
    if (this.__fiber != null) {
      __vrScheduleUpdate(this.__fiber);
    }
  }

  /// `state` with any queued updates folded in — what the next render will
  /// see. Not for a component to read; `render` already gets it as `state`.
  __effectiveState() {
    if (this.__pending == null) {
      return this.state;
    }
    let merged = __guiShallowCopy(this.state);
    for (let k in this.__pending) {
      merged[k] = this.__pending[k];
    }
    return merged;
  }

  /// Fold queued updates into `state`. Called by the reconciler immediately
  /// before `render`, which is what makes `this.state` stable for the whole of
  /// a render pass.
  ///
  /// Applying eagerly inside `setState` instead looks simpler and is wrong: a
  /// component that reads `this.state.n` twice around a `setState` would see
  /// two different values in one render, and a child built after the call
  /// would receive props from a state its parent had not rendered yet.
  __flushPending() {
    if (this.__pending == null) {
      return;
    }
    for (let k in this.__pending) {
      this.state[k] = this.__pending[k];
    }
    this.__pending = null;
  }

  // ---- Lifecycle. Override what you need; the defaults do nothing. -------

  /// After the component's nodes are in the tree. Start timers, subscribe,
  /// reach for a controller through a ref.
  componentDidMount() {}

  /// After a re-render has been applied. `prevProps` and `prevState` are what
  /// they were before it.
  componentDidUpdate(prevProps, prevState) {}

  /// Before the component's nodes are freed. Cancel timers, unsubscribe.
  /// Anything not released here leaks for the life of the mini app.
  componentWillUnmount() {}

  /// Return false to skip a re-render. The class-component equivalent of
  /// wrapping a function component in `memo`.
  shouldComponentUpdate(nextProps, nextState) {
    return true;
  }

  render() {
    throw "gui: " + (this.constructor == null ? "a component" : "this component")
      + " must implement render()";
  }
}

/// Wrap a class component so it can be used anywhere a function component can.
///
///     const Counter = component(class extends Component {
///       state = { n: 0 };
///       render() { return Text({ children: "" + this.state.n }); }
///     });
///
///     // then, indistinguishable from a function component:
///     Counter({ label: "hits" })
///     createElement(Counter, { label: "hits" })
///
/// ## Why the wrap is needed
///
/// The reconciler cannot tell a class from a function on its own, and the
/// reason is worth stating because it is not obvious.
///
/// A class in this subset is not an object. Its statics are resolved *by name,
/// at compile time* — `Counter.isGuiComponent` compiles to a lookup in a
/// companion table the compiler builds for the identifier `Counter`. The moment
/// the class is passed as a value the name is gone, so `type.isGuiComponent`
/// inside the reconciler reads nothing. `Type.prototype` is null and a class
/// object cannot be assigned to, so there is no marker to leave either.
///
/// `instanceof` does work, but only on an instance — and constructing one
/// speculatively is not an option: `new fn(props)` on a *function* component
/// would run its body, and its hooks, before we knew what it was.
///
/// So the class is handed over once, at its definition, where its name is still
/// in scope. Everything after that is uniform.
function classComponent(type) {
  // A function component passes straight through, so `component()` can be
  // applied to either without the caller checking first.
  if (!__isType(type, "function")) {
    throw "gui: component() needs a class or a function";
  }
  // The reconciler needs no register of these: `__guiRenderClassOn` marks the
  // fiber it renders on, and the fiber is what the commit and unmount hooks
  // are handed. Keeping a list of every wrapper ever minted would also mean
  // never releasing one, in a runtime whose whole job is to be bounded.
  return (props) => {
    // Rendered through the fiber the reconciler is currently on, so the
    // instance, its state and its lifecycle all live where hooks do.
    return __guiRenderClassOn(__vrCur, type, props);
  };
}

/// Render a class component on `fiber`, constructing its instance the first
/// time and reusing it afterwards.
///
/// Reusing the instance is what makes `this.state` and `this.timer` persist
/// across renders — the same guarantee hooks give a function component.
function __guiRenderClassOn(fiber, type, props) {
  if (fiber == null) {
    throw "gui: a class component was rendered outside a render pass";
  }
  let inst = fiber.classInstance;
  if (inst == null) {
    inst = new type(props);
    inst.__fiber = fiber;
    fiber.classInstance = inst;
    fiber.pendingMount = true;
  } else {
    inst.__flushPending();
    let prevProps = inst.props;
    let prevState = __guiShallowCopy(inst.state);
    if (!inst.shouldComponentUpdate(props, inst.state)) {
      fiber.skippedRender = true;
      return fiber.lastRendered;
    }
    inst.props = props;
    fiber.prevProps = prevProps;
    fiber.prevState = prevState;
  }
  let out = inst.render();
  fiber.lastRendered = out;
  fiber.hasClass = true;
  return out;
}

/// Run the lifecycle callbacks a commit owes a class component.
///
/// Called after the fiber's nodes are in the tree, so `componentDidMount` can
/// measure them or reach a controller — the whole point of the hook.
function __guiCommitClass(fiber) {
  let inst = fiber.classInstance;
  if (inst == null) {
    return;
  }
  if (fiber.pendingMount == true) {
    fiber.pendingMount = false;
    inst.__mounted = true;
    inst.componentDidMount();
    return;
  }
  if (fiber.skippedRender == true) {
    fiber.skippedRender = false;
    return;
  }
  inst.componentDidUpdate(fiber.prevProps, fiber.prevState);
}

/// Tear a class component down before its nodes are freed.
function __guiUnmountClass(fiber) {
  let inst = fiber.classInstance;
  if (inst == null) {
    return;
  }
  if (inst.__mounted) {
    inst.componentWillUnmount();
  }
  inst.__mounted = false;
  inst.__fiber = null;
  fiber.classInstance = null;
}

// Hand the two hooks to the reconciler. From here on a class component is
// rendered by exactly the same machinery as a function one: VReact calls
// `commit` where it would flush effects and `unmount` where it would run their
// cleanups, so an update from `setState` coalesces with one from `useState` in
// a single flush rather than racing it.
__vrInstallClassHooks({ commit: __guiCommitClass, unmount: __guiUnmountClass });

function __guiShallowCopy(o) {
  let out = {};
  if (o == null) {
    return out;
  }
  for (let k in o) {
    out[k] = o[k];
  }
  return out;
}

// ---------------------------------------------------------------------------
// Generated components
// ---------------------------------------------------------------------------
//
// Every registered widget becomes a function component. `Button({...})` is a
// function returning an element, so it composes exactly like one a mini app
// writes itself — no special case in the reconciler for "built-in" widgets.
//
// A component for a widget added later appears too: `defineWidget` then
// `GUI.component("badge")` gives you `Badge` without editing this file.

/// The component for a widget name, or the wrapper for a class component.
///
/// One entry point for both because a caller thinks in terms of "give me
/// something I can render", not in terms of which mechanism is behind it.
function componentFor(nameOrClass) {
  if (__isType(nameOrClass, "function")) {
    return classComponent(nameOrClass);
  }
  let w = widgetFor(nameOrClass);
  if (w == null) {
    throw "gui: no widget named '" + nameOrClass + "'";
  }
  return (props) => jsx(nameOrClass, props);
}

/// Bind every registered widget onto `target` under its capitalised name, so a
/// guest gets `Text`, `Column`, `Button`… without naming each one here.
function __guiBindComponents(target) {
  let names = widgetNames();
  for (let i = 0; i < names.length; i++) {
    let n = names[i];
    target[__guiCapitalise(n)] = componentFor(n);
  }
  return target;
}

function __guiCapitalise(s) {
  if (s == null || s.length == 0) {
    return s;
  }
  return s.substring(0, 1).toUpperCase() + s.substring(1);
}
// =============================================================================
// §3  Scene3D — the 3D widget and its controller
// =============================================================================
//
// A 3D world as one widget. `Scene3D` mounts a viewport and hands its
// controller to whoever asked for it; everything else — the camera, the
// environment, spawning and moving objects — goes through that controller
// rather than through loose `GD.create` calls scattered across a component.
//
//     class World extends Component {
//       componentDidMount() {
//         let s = this.scene;
//         s.camera.moveTo(0, 3, 8);
//         s.camera.lookAt(0, 0, 0);
//         this.cube = s.spawn("MeshInstance3D", { position: [0, 0, 0] });
//       }
//       componentWillUnmount() { /* the controller frees what it spawned */ }
//       render() {
//         return Scene3D({ ref: (c) => { this.scene = c; }, environment: "day" });
//       }
//     }
//
// The controller is the point. Before it, a 3D scene was built by reaching into
// the raw `GD` surface from render code, which meant nodes created during a
// render that the reconciler knew nothing about — leaked on unmount, duplicated
// on re-render. A `Scene3DController` owns what it spawns and frees it when its
// widget goes away.

/// Drives one 3D scene. Handed to a component through `ref`.
class Scene3DController {
  constructor(root) {
    /// The `SubViewport` the scene renders into.
    this.root = root;
    /// Everything spawned through this controller, so unmount can free it.
    /// A node created behind the controller's back is not in here and will
    /// outlive the widget.
    this.spawned = [];
    this.camera = new Scene3DCamera(this);
    this.disposed = false;
    this.__world = null;
  }

  /// The `Node3D` every spawned object is parented under. Created on first use
  /// so an empty scene costs nothing.
  world() {
    if (this.__world == null) {
      this.__world = GD.create("Node3D");
      __guiAdd(this.root, this.__world);
    }
    return this.__world;
  }

  /// Add a node of `className` to the scene.
  ///
  /// `props` may carry `position`, `rotation` and `scale` as `[x, y, z]`, plus
  /// any property the class itself accepts.
  spawn(className, props) {
    this.__assertLive("spawn");
    let node = GD.create(className);
    __guiAdd(this.world(), node);
    this.spawned.push(node);
    if (props != null) {
      this.configure(node, props);
    }
    return node;
  }

  /// Apply `props` to an existing node. Split out from [spawn] so a component
  /// can move something it already has without rebuilding it.
  configure(node, props) {
    if (node == null || props == null) {
      return node;
    }
    for (let k in props) {
      let v = props[k];
      if (k === "position") {
        node.set("position", __guiVec3(v));
      } else if (k === "rotation") {
        node.set("rotation", __guiVec3(v));
      } else if (k === "scale") {
        node.set("scale", __guiVec3(v));
      } else {
        node.set(k, v);
      }
    }
    return node;
  }

  /// Free one node this controller spawned.
  remove(node) {
    if (node == null) {
      return;
    }
    let keep = [];
    for (let i = 0; i < this.spawned.length; i++) {
      if (this.spawned[i] !== node) {
        keep.push(this.spawned[i]);
      }
    }
    this.spawned = keep;
    node.queueFree();
  }

  /// Add a light. A scene with no light renders black, which reads as a broken
  /// widget rather than a missing light — so this is worth having to hand.
  light(kind, props) {
    let cls = kind === "directional" ? "DirectionalLight3D"
            : kind === "spot" ? "SpotLight3D"
            : "OmniLight3D";
    return this.spawn(cls, props);
  }

  /// Free everything this controller owns. Called when the widget unmounts;
  /// calling it twice is harmless.
  dispose() {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    for (let i = 0; i < this.spawned.length; i++) {
      this.spawned[i].queueFree();
    }
    this.spawned = [];
    if (this.__world != null) {
      this.__world.queueFree();
      this.__world = null;
    }
    this.camera.dispose();
  }

  __assertLive(what) {
    if (this.disposed) {
      throw "gui: Scene3DController." + what + " after the scene was disposed";
    }
  }
}

/// The scene's camera. Created lazily: a scene used only as a backdrop does not
/// need one, and Godot supplies a default view without it.
class Scene3DCamera {
  constructor(scene) {
    this.scene = scene;
    this.node = null;
  }

  /// The `Camera3D`, creating and making it current on first use.
  ensure() {
    if (this.node == null) {
      this.node = GD.create("Camera3D");
      __guiAdd(this.scene.world(), this.node);
      this.node.set("current", true);
    }
    return this.node;
  }

  moveTo(x, y, z) {
    this.ensure().set("position", new Vector3(x, y, z));
    return this;
  }

  lookAt(x, y, z) {
    // `look_at` needs an up vector; Y-up matches Godot's own convention and is
    // what a caller passing three numbers means.
    this.ensure().call("look_at", [new Vector3(x, y, z), new Vector3(0, 1, 0)]);
    return this;
  }

  /// Vertical field of view, in degrees.
  fov(degrees) {
    this.ensure().set("fov", degrees);
    return this;
  }

  dispose() {
    if (this.node != null) {
      this.node.queueFree();
      this.node = null;
    }
  }
}

/// Parent `child` under `parent`.
///
/// `GObj` exposes the engine reflectively — `call(method, args)` — rather than
/// wrapping each method by hand, so there is no `addChild`. Named here because
/// the SDK does this constantly and `call("add_child", [x])` at every site
/// reads as engine plumbing rather than as structure.
function __guiAdd(parent, child) {
  if (parent == null || child == null) {
    return child;
  }
  parent.call("add_child", [child]);
  return child;
}

/// `[x, y, z]`, a number, or a Vector3 — all mean a position.
function __guiVec3(v) {
  if (v == null) {
    return new Vector3(0, 0, 0);
  }
  if (__isType(v, "array")) {
    return new Vector3(__vrNum(v[0], 0), __vrNum(v[1], 0), __vrNum(v[2], 0));
  }
  if (__isType(v, "number")) {
    return new Vector3(v, v, v);
  }
  return v;
}

defineWidget("scene3d", {
  container: true,
  controller: (node) => new Scene3DController(node),
  create: (props, theme) => {
    // A SubViewport renders the 3D world; the container puts it on screen and
    // sizes it like any other widget.
    let holder = GD.create("SubViewportContainer");
    holder.set("stretch", true);
    let viewport = GD.create("SubViewport");
    viewport.set("own_world_3d", true);
    __guiAdd(holder, viewport);
    // The controller hangs off the holder so update and dispose can find it
    // without a second lookup table.
    holder.__scene = new Scene3DController(viewport);
    if (props != null && props.environment != null) {
      __guiApplyEnvironment(holder.__scene, props.environment);
    }
    __guiApplySize(holder, props);
    return holder;
  },
  update: (node, prev, props, theme) => {
    let changedEnv = prev == null || prev.environment !== props.environment;
    if (changedEnv && props.environment != null) {
      __guiApplyEnvironment(node.__scene, props.environment);
    }
    __guiApplySize(node, props);
    return node;
  },
  dispose: (node) => {
    if (node.__scene != null) {
      node.__scene.dispose();
      node.__scene = null;
    }
  },
});

/// Named environments, so a scene gets sensible lighting from one prop rather
/// than six lines of setup every time.
function __guiApplyEnvironment(scene, name) {
  if (scene == null || name == null) {
    return;
  }
  let env = GD.create("Environment");
  if (name === "day") {
    env.set("background_mode", 2);
    env.set("ambient_light_energy", 1.0);
  } else if (name === "night") {
    env.set("background_mode", 1);
    env.set("ambient_light_energy", 0.15);
  } else if (name === "studio") {
    env.set("background_mode", 1);
    env.set("ambient_light_energy", 0.6);
  }
  let holder = GD.create("WorldEnvironment");
  holder.set("environment", env);
  __guiAdd(scene.world(), holder);
}
// =============================================================================
// §4  Canvas — the 2D drawing widget and its controller
// =============================================================================
//
// Immediate-mode 2D drawing, packaged the same way as Scene3D: a widget that
// owns a surface, and a controller that draws on it.
//
//     class Chart extends Component {
//       componentDidMount() { this.redraw(); }
//       componentDidUpdate() { this.redraw(); }
//       redraw() {
//         let c = this.canvas;
//         c.clear();
//         c.rect(0, 0, 100, 40, "#2b6cb0");
//         c.line(0, 40, 100, 0, "#e2e8f0", 2);
//         c.commit();
//       }
//       render() { return Canvas({ ref: (c) => { this.canvas = c; }, width: 100, height: 40 }); }
//     }
//
// Drawing is retained, not immediate: calls accumulate into a display list and
// `commit()` submits it. A chart redrawing on every state change would
// otherwise cross the host seam once per primitive, which is the difference
// between one op and several hundred per frame.

/// Draws on one canvas surface. Handed to a component through `ref`.
class CanvasController {
  constructor(node) {
    /// The `Control` that paints the display list.
    this.node = node;
    /// Accumulated commands, submitted by [commit].
    this.commands = [];
    this.disposed = false;
  }

  /// Drop everything drawn so far. The usual first call of a redraw.
  clear() {
    this.__assertLive("clear");
    this.commands = [];
    return this;
  }

  /// A filled rectangle.
  rect(x, y, w, h, color) {
    return this.__push({ op: "rect", x: x, y: y, w: w, h: h, color: color });
  }

  /// A rectangle outline. `width` is the stroke, in pixels.
  strokeRect(x, y, w, h, color, width) {
    return this.__push({
      op: "rect", x: x, y: y, w: w, h: h, color: color,
      filled: false, width: __vrNum(width, 1),
    });
  }

  /// A line from (x1,y1) to (x2,y2).
  line(x1, y1, x2, y2, color, width) {
    return this.__push({
      op: "line", x1: x1, y1: y1, x2: x2, y2: y2,
      color: color, width: __vrNum(width, 1),
    });
  }

  /// A filled circle.
  circle(x, y, radius, color) {
    return this.__push({ op: "circle", x: x, y: y, r: radius, color: color });
  }

  /// A polyline through `points`, given as a flat `[x0, y0, x1, y1, …]`.
  ///
  /// Flat rather than a list of pairs because it crosses the host seam as one
  /// array: a list of two-element arrays costs an object per point.
  polyline(points, color, width) {
    return this.__push({
      op: "polyline", points: points, color: color, width: __vrNum(width, 1),
    });
  }

  /// Text at (x, y). `size` is the font size in pixels.
  text(x, y, str, color, size) {
    return this.__push({
      op: "text", x: x, y: y, text: "" + str, color: color,
      size: __vrNum(size, 14),
    });
  }

  /// Submit the display list. Nothing appears until this is called.
  commit() {
    this.__assertLive("commit");
    this.node.call("__gui_draw", [this.commands]);
    return this;
  }

  /// How many commands are queued. Useful to a component deciding whether a
  /// redraw is worth committing at all.
  ///
  /// A method rather than a getter because the subset has no property
  /// accessors — a `get length()` compiles, but reading it yields the
  /// function's name rather than calling it, which fails silently.
  count() {
    return this.commands.length;
  }

  dispose() {
    this.disposed = true;
    this.commands = [];
  }

  __push(cmd) {
    this.__assertLive(cmd.op);
    this.commands.push(cmd);
    return this;
  }

  __assertLive(what) {
    if (this.disposed) {
      throw "gui: CanvasController." + what + " after the canvas was disposed";
    }
  }
}

defineWidget("canvas", {
  container: false,
  controller: (node) => new CanvasController(node),
  create: (props, theme) => {
    let node = GD.create("Control");
    node.__canvas = new CanvasController(node);
    __guiApplySize(node, props);
    return node;
  },
  update: (node, prev, props, theme) => {
    __guiApplySize(node, props);
    return node;
  },
  dispose: (node) => {
    if (node.__canvas != null) {
      node.__canvas.dispose();
      node.__canvas = null;
    }
  },
});

/// Apply `width`/`height` to a node, in the one place both Canvas and Scene3D
/// need it.
function __guiApplySize(node, props) {
  if (node == null || props == null) {
    return node;
  }
  let w = __vrNum(props.width, -1);
  let h = __vrNum(props.height, -1);
  if (w >= 0 || h >= 0) {
    node.set("custom_minimum_size", new Vector2(w < 0 ? 0 : w, h < 0 ? 0 : h));
  }
  return node;
}
// =============================================================================
// §5  The imperative facade
// =============================================================================
//
// Not every use of a widget wants a render tree. A one-off dialog, a debug
// overlay, a node handed to something outside the reconciler's world — those
// want a node back, now.
//
// `GUI.button({...})` builds one directly from the *same* registry entry the
// declarative `Button({...})` uses, which is the whole point: previously the
// imperative kit (`VUI.button`) and the declarative driver each had their own
// implementation of every widget, and fixing one fixed only one.
//
// A node built this way is yours. The reconciler does not know about it, so
// nothing frees it for you — call `node.free()`, or parent it under something
// the reconciler owns.

/// Build a widget node directly, outside any render tree.
function buildWidget(name, props) {
  let w = widgetFor(name);
  if (w == null) {
    throw "gui: no widget named '" + name + "'";
  }
  let node = w.create(props == null ? {} : props, __guiTheme());
  // Containers accept `children` as already-built nodes here, not elements —
  // this side of the SDK has no elements.
  if (w.container && props != null && props.children != null) {
    let kids = __isType(props.children, "array") ? props.children : [props.children];
    for (let i = 0; i < kids.length; i++) {
      if (kids[i] != null) {
        __guiAdd(node, kids[i]);
      }
    }
  }
  return node;
}

/// Bind an imperative builder for every registered widget onto `target`.
function __guiBindBuilders(target) {
  let names = widgetNames();
  for (let i = 0; i < names.length; i++) {
    let n = names[i];
    target[n] = (props) => buildWidget(n, props);
  }
  return target;
}

// =============================================================================
// §6  Scoping
// =============================================================================
//
// The host already isolates one mini app from another: every node it creates is
// stamped with its sandbox, and every callback id is namespaced to its VM. A
// mini app cannot reach a sibling's tree however it tries.
//
// A scope is the *guest-side* half of that, one level down: a named region
// inside one app whose state and controllers are its own. It is what lets a
// shell mini app host a panel without the panel's keys, styles or controllers
// colliding with the shell's.

/// A named region of one mini app's UI.
class Scope {
  constructor(name, parent) {
    this.name = name;
    this.parent = parent == null ? null : parent;
    /// Values stored under this scope, by key.
    this.values = {};
    /// Controllers created inside it, disposed together with it.
    this.owned = [];
    this.children = [];
    this.disposed = false;
    if (this.parent != null) {
      this.parent.children.push(this);
    }
  }

  /// The scope's fully qualified path, e.g. `"app/settings/theme"`. Used to
  /// namespace anything that needs a globally unique name.
  path() {
    if (this.parent == null) {
      return this.name;
    }
    return this.parent.path() + "/" + this.name;
  }

  /// A child scope. Disposing this one disposes it too.
  child(name) {
    return new Scope(name, this);
  }

  /// Read a value, falling back to enclosing scopes.
  ///
  /// Reading through the parent is what makes a scope useful for shared
  /// context — a theme set on the root is visible everywhere below without
  /// being copied into each one.
  get(key) {
    if (this.values[key] !== undefined) {
      return this.values[key];
    }
    if (this.parent != null) {
      return this.parent.get(key);
    }
    return null;
  }

  /// Write a value into *this* scope, shadowing any enclosing one.
  set(key, value) {
    this.values[key] = value;
    return this;
  }

  /// Hand a controller to the scope so it is disposed when the scope is.
  own(controller) {
    this.owned.push(controller);
    return controller;
  }

  /// Dispose this scope, its children and everything it owns. Children first,
  /// so a parent's teardown never runs while a child still holds a reference
  /// into it.
  dispose() {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    for (let i = 0; i < this.children.length; i++) {
      this.children[i].dispose();
    }
    this.children = [];
    for (let i = 0; i < this.owned.length; i++) {
      let c = this.owned[i];
      if (c != null && __isType(c.dispose, "function")) {
        c.dispose();
      }
    }
    this.owned = [];
    this.values = {};
  }
}

var __guiRootScope = new Scope("app", null);

// =============================================================================
// §7  The GUI namespace
// =============================================================================

var GUI = {
  // -- Rendering ------------------------------------------------------------

  /// Render `element` into `container`, returning a root with `render()` and
  /// `unmount()`.
  render: (element, container) => __vrRenderRoot(element, container),

  /// Render a component as the whole app, into a fresh full-rect container.
  ///
  /// The shortest thing that works: `GUI.mount(Counter)`.
  mount: (type, props) => {
    let host = GD.create("Control");
    host.set("anchors_preset", 15);
    __guiAdd(GD.tree(), host);
    return __vrRenderRoot(createElement(type, props == null ? {} : props), host);
  },

  // -- Components and widgets ----------------------------------------------

  Component: Component,
  createElement: createElement,
  Fragment: __VR_FRAGMENT,

  /// Wrap a class component, or fetch a widget's component by name.
  ///
  ///     const Counter = GUI.component(class extends Component { … });
  ///
  /// A class is handed over here rather than detected — see `classComponent`
  /// for why the subset leaves no other option.
  component: componentFor,
  /// Register a widget; both surfaces pick it up.
  defineWidget: defineWidget,
  /// Every registered widget name.
  widgets: widgetNames,
  /// Build a widget node directly, outside any render tree.
  build: buildWidget,

  // -- State ----------------------------------------------------------------

  useState: useState,
  useReducer: useReducer,
  useEffect: useEffect,
  useLayoutEffect: useLayoutEffect,
  useMemo: useMemo,
  useCallback: useCallback,
  useRef: useRef,
  useContext: useContext,
  createContext: createContext,
  memo: memo,
  forwardRef: forwardRef,

  // -- Scoping --------------------------------------------------------------

  /// The mini app's root scope.
  scope: () => __guiRootScope,
  Scope: Scope,

  // -- 3D and 2D ------------------------------------------------------------

  Scene3DController: Scene3DController,
  CanvasController: CanvasController,

  // -- Styling --------------------------------------------------------------

  /// The active theme. Widgets read it; an app replaces it to restyle
  /// everything at once.
  theme: () => __guiTheme(),
  setTheme: (t) => __guiSetTheme(t),

  // -- Timing ---------------------------------------------------------------

  /// Run `fn` once, after `ms`.
  after: (ms, fn) => GTimer.after(ms, fn),
  /// Run `fn` every `ms` until cancelled.
  every: (ms, fn) => GTimer.periodic(ms, fn),
  /// Run `fn` on the next turn of the event loop.
  soon: (fn) => __later(fn),

  // -- Escape hatches -------------------------------------------------------
  //
  // The raw engine surface, for what the widget set does not cover. Reaching
  // past the widgets is expected — the SDK is not trying to be the only way to
  // talk to the host, only the best one for the cases it covers.

  GD: GD,
};

// Both surfaces are generated from the one registry, at load, so a widget
// registered above appears in each without being named twice.
__guiBindComponents(GUI);
__guiBindBuilders(GUI);
