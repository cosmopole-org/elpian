// =============================================================================
// gui.js — the Elpian GUI SDK
// =============================================================================
//
// Everything a mini app needs to draw itself: the engine transport, the Flutter
// surface, state, rendering, scoping, widgets, styling, 3D scenes and 2D
// canvases. One file, one import, one vocabulary.
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
// ## Why one file
//
// This was five: `godot.js` (the engine transport), `flutter.js` (the embedded
// Flutter surface), `ui.js` (VUI, the widget kit), `react.js` (VReact, the
// reconciler), and a `gui.js` layered on top that composed them. A mini app
// picked a combination and had to know which layer owned which name.
//
// They are one file now, and the other four are deleted. There is no import
// chain to resolve, no question about which prelude a symbol comes from, and —
// the reason the split cost more than it bought — no way for two layers to hold
// different ideas about the same widget. A widget is defined once, in the
// registry (§5), and both the declarative `Button({…})` and the imperative
// `GUI.button({…})` are generated from that entry. `GUI.defineWidget` gives a
// mini app the same deal for widgets of its own.
//
// The cost is honest and worth stating: a guest that only wants the engine
// bridge, or only `net.js`, now carries the whole SDK. `prelude_cost.rs` pins
// what that is so it cannot grow unnoticed.
//
// ## Layout
//
//   §1  Engine transport      GD / GObj, marshaling, callbacks, value types
//   §2  Flutter surface       FL, driving an embedded Flutter engine
//   §3  Theme and widget kit  VUI: M3 tokens, fonts, metrics, imperative widgets
//   §4  Reactive core         VReact: elements, hooks, scheduler, reconciler
//   §5  Widget registry       one definition per widget, two surfaces
//   §6  Components            the Component base class, class and function
//   §7  Scene3D               the 3D widget and its controller
//   §8  Canvas                the 2D drawing widget and its controller
//   §9  Imperative facade     GUI.*, generated from the registry
//   §10 Scoping               named regions within one mini app
//   §11 The GUI namespace     what a mini app actually reaches for
//
// Sections §1–§4 are the four preludes, carried over whole with their own
// documentation intact — they are the layers this SDK is built out of, and
// their chapter comments are the reference for the wire protocol, the design
// system and the reconciliation model respectively.
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
// §1  Engine transport — GD, GObj, and the Godot op protocol
// =============================================================================

// =============================================================================
// godot.js — the Elpian guest library for driving the FULL Godot engine, in JS
// =============================================================================
//
// The JavaScript twin of `godot.dart`: the same wire protocol, the same
// reflective op vocabulary, the same handle/callback model — expressed in the
// Elpian-JS subset the `js2elpian` front-end compiles. A JS guest program is
// composed AFTER this prelude (its `import 'godot.js';` line is stripped; the
// prelude IS the import) and drives the identical C++ GodotController:
//
//   * instantiate any registered class      (GD.create('Button'))
//   * bind any engine singleton             (GD.singleton('DisplayServer'))
//   * call any method on any object         (node.call('add_child', [child]))
//   * read / write any property             (node.set('position', Vector2(4, 2)))
//   * read any class / global constant      (GD.constant('DisplayServer.SCREEN_PORTRAIT'))
//   * connect any signal to a JS closure    (btn.connect('pressed', (a) => { ... }))
//   * hand any Godot API a JS Callable      (GD.callable((a) => { ... }))
//   * load any resource                     (GD.load('res://thing.tscn'))
//   * evaluate any expression / utility fn  (GD.eval('clamp(x, 0.0, 1.0)', ...))
//   * introspect everything                 (GD.classes(), GD.classInfo('Control'))
//   * batch any number of ops into ONE
//     seam crossing                         (GD.beginBatch() ... GD.endBatch())
//
// Language notes (the honest constraints of the subset):
//   * there is no first-class null — an absent value is 0, and `x == null`
//     is therefore also true for a numeric zero;
//   * type tests are the `__isType(v, 'T')` intrinsic (lowered to the VM's
//     native typeTest opcode) — 'num' / 'String' / 'bool' / 'List' / 'Map' /
//     'Function' or any class name declared in the program;
//   * iterate lists with C-style `for` + `.length`; iterate a map's keys with
//     `m.keys` (a Dart-style getter member on plain maps — not a call).
//
// Everything else — ids, batching, marshaling, error convention — matches
// godot.dart exactly; see that file (and victor/bridge/README.md) for the
// protocol chapter and the performance model.

// ---------------------------------------------------------------------------
// async glue — the VM event-loop seam (timers / microtasks re-enter here)
// ---------------------------------------------------------------------------
// A pure-JS guest has no dart2elpian emitter prelude, so the dispatch table the
// host's `__dartDispatch` invocations index into is defined here instead.

var __cbReg = [];

function __dartDispatch(a) {
  var fn = __cbReg[a[0]];
  fn();
}

// Console output: surfaces on the Godot console prefixed `[elpian]` (the Dart
// front-end lowers its `print` to the same host call; here it is a function).
function print(v) {
  askHost("log", ["" + v]);
}

function __later(fn) {
  var id = __cbReg.length;
  __cbReg.push(fn);
  askHost("dart:async/scheduleMicrotask", [id]);
}

// ---------------------------------------------------------------------------
// internals: ids, callback table, batch buffer
// ---------------------------------------------------------------------------

var __gdNextId = 1; // guest-side handle allocator (positive ids)
var __gdNextCb = 1; // callback ids for signals / Callables
var __gdCallbacks = {}; // cbId -> JS closure

// When non-null, ops are appended here instead of crossing the seam; flushed
// as one `godot.batch` host call by GD.endBatch().
var __gdBatch = null;

function __gdAllocId() {
  var id = __gdNextId;
  __gdNextId = __gdNextId + 1;
  return id;
}

function __gdRegisterCb(cb) {
  var id = __gdNextCb;
  __gdNextCb = __gdNextCb + 1;
  __gdCallbacks["cb" + id] = cb;
  return id;
}

// Run one op: immediately (one `godot.op` host call), or queue it when a
// batch is open. Batched ops return null — read results after endBatch().
function __gdRun(op) {
  if (__gdBatch != null && __isType(__gdBatch, "list")) {
    __gdBatch.push(op);
    return null;
  }
  return __gdUnmarshal(askHost("godot.op", [op]));
}

// ---------------------------------------------------------------------------
// marshaling: JS values -> tagged JSON the C++ controller turns into Variants
// ---------------------------------------------------------------------------

// Convert one JS argument into its wire shape. Scalars pass through; bridge
// value-types tag themselves; GObj handles become {"ref": id}; closures become
// live Godot Callables; lists/maps marshal recursively.
function __gdMarshal(v) {
  // Scalars first: null is represented as 0 in the VM, so the numeric /
  // string / bool checks must run before the null check or `0` would marshal
  // as null.
  if (__isType(v, "number")) {
    return v;
  }
  if (__isType(v, "string")) {
    return v;
  }
  if (__isType(v, "bool")) {
    return v;
  }
  if (v == null) {
    return null;
  }
  if (__isType(v, "GObj")) {
    return { ref: v.id };
  }
  if (__isType(v, "Vector2")) {
    return { vec2: [v.x, v.y] };
  }
  if (__isType(v, "Vector2i")) {
    return { vec2i: [v.x, v.y] };
  }
  if (__isType(v, "Vector3")) {
    return { vec3: [v.x, v.y, v.z] };
  }
  if (__isType(v, "Vector3i")) {
    return { vec3i: [v.x, v.y, v.z] };
  }
  if (__isType(v, "Vector4")) {
    return { vec4: [v.x, v.y, v.z, v.w] };
  }
  if (__isType(v, "Vector4i")) {
    return { vec4i: [v.x, v.y, v.z, v.w] };
  }
  if (__isType(v, "Color")) {
    return { color: [v.r, v.g, v.b, v.a] };
  }
  if (__isType(v, "Rect2")) {
    return { rect2: [v.x, v.y, v.w, v.h] };
  }
  if (__isType(v, "Rect2i")) {
    return { rect2i: [v.x, v.y, v.w, v.h] };
  }
  if (__isType(v, "Plane")) {
    return { plane: [v.nx, v.ny, v.nz, v.d] };
  }
  if (__isType(v, "Quaternion")) {
    return { quat: [v.x, v.y, v.z, v.w] };
  }
  if (__isType(v, "AABB")) {
    return { aabb: [v.px, v.py, v.pz, v.sx, v.sy, v.sz] };
  }
  if (__isType(v, "Basis")) {
    return { basis: v.rows };
  }
  if (__isType(v, "Transform2D")) {
    return { xform2d: v.m };
  }
  if (__isType(v, "Transform3D")) {
    return { xform3d: v.m };
  }
  if (__isType(v, "Projection")) {
    return { proj: v.m };
  }
  if (__isType(v, "StringName")) {
    return { sname: v.value };
  }
  if (__isType(v, "NodePath")) {
    return { npath: v.value };
  }
  if (__isType(v, "GRid")) {
    return { rid: v.id };
  }
  if (__isType(v, "GSignal")) {
    return { sig: [__gdMarshal(v.source), v.name] };
  }
  if (__isType(v, "GInt")) {
    return { int: v.value };
  }
  if (__isType(v, "GFloat")) {
    return { float: v.value };
  }
  if (__isType(v, "GDict")) {
    let pairs = [];
    for (let i = 0; i < v.entries.length; i++) {
      pairs.push([__gdMarshal(v.entries[i][0]), __gdMarshal(v.entries[i][1])]);
    }
    return { dictv: pairs };
  }
  if (__isType(v, "GCallable")) {
    return { callable: v.cbId };
  }
  if (__isType(v, "Packed")) {
    let out = {};
    out[v.tag] = v.data;
    return out;
  }
  if (__isType(v, "function")) {
    // A bare JS closure handed to any Godot API becomes a Callable bound to
    // the native SignalRelay; invocations are queued and dispatched back into
    // the VM (fire-and-forget — see the README's reentrancy note).
    return { callable: __gdRegisterCb(v) };
  }
  if (__isType(v, "list")) {
    let out = [];
    for (let i = 0; i < v.length; i++) {
      out.push(__gdMarshal(v[i]));
    }
    return out;
  }
  if (__isType(v, "map")) {
    // A plain JS object becomes a Godot Dictionary (values marshal recursively).
    let out = {};
    let ks = v.keys;
    for (let i = 0; i < ks.length; i++) {
      out["" + ks[i]] = __gdMarshal(v[ks[i]]);
    }
    return { dict: out };
  }
  return v;
}

// Marshal an argument list (null-safe: absent -> []).
function __gdMarshalList(args) {
  if (args == null) {
    return [];
  }
  let out = [];
  for (let i = 0; i < args.length; i++) {
    out.push(__gdMarshal(args[i]));
  }
  return out;
}

// Convert one host reply into JS values: tagged shapes become bridge
// value-types, {"obj": id, "class": c} becomes a GObj proxy, containers
// convert recursively, scalars pass through.
function __gdUnmarshal(v) {
  if (__isType(v, "number")) {
    return v;
  }
  if (__isType(v, "string")) {
    return v;
  }
  if (__isType(v, "bool")) {
    return v;
  }
  if (v == null) {
    return null;
  }
  if (__isType(v, "list")) {
    let out = [];
    for (let i = 0; i < v.length; i++) {
      out.push(__gdUnmarshal(v[i]));
    }
    return out;
  }
  if (__isType(v, "map")) {
    if (v["__dart_error__"] != null) {
      return v; // the bridge-wide failure shape; check GD.isError(r)
    }
    if (v["obj"] != null) {
      return new GObj(v["obj"], v["class"] ?? "Object");
    }
    if (v["vec2"] != null) {
      return new Vector2(v["vec2"][0], v["vec2"][1]);
    }
    if (v["vec2i"] != null) {
      return new Vector2i(v["vec2i"][0], v["vec2i"][1]);
    }
    if (v["vec3"] != null) {
      return new Vector3(v["vec3"][0], v["vec3"][1], v["vec3"][2]);
    }
    if (v["vec3i"] != null) {
      return new Vector3i(v["vec3i"][0], v["vec3i"][1], v["vec3i"][2]);
    }
    if (v["vec4"] != null) {
      return new Vector4(v["vec4"][0], v["vec4"][1], v["vec4"][2], v["vec4"][3]);
    }
    if (v["vec4i"] != null) {
      return new Vector4i(v["vec4i"][0], v["vec4i"][1], v["vec4i"][2], v["vec4i"][3]);
    }
    if (v["color"] != null) {
      return new Color(v["color"][0], v["color"][1], v["color"][2], v["color"][3]);
    }
    if (v["rect2"] != null) {
      return new Rect2(v["rect2"][0], v["rect2"][1], v["rect2"][2], v["rect2"][3]);
    }
    if (v["rect2i"] != null) {
      return new Rect2i(v["rect2i"][0], v["rect2i"][1], v["rect2i"][2], v["rect2i"][3]);
    }
    if (v["plane"] != null) {
      return new Plane(v["plane"][0], v["plane"][1], v["plane"][2], v["plane"][3]);
    }
    if (v["quat"] != null) {
      return new Quaternion(v["quat"][0], v["quat"][1], v["quat"][2], v["quat"][3]);
    }
    if (v["aabb"] != null) {
      let a = v["aabb"];
      return new AABB(a[0], a[1], a[2], a[3], a[4], a[5]);
    }
    if (v["basis"] != null) {
      return new Basis(v["basis"]);
    }
    if (v["xform2d"] != null) {
      return new Transform2D(v["xform2d"]);
    }
    if (v["xform3d"] != null) {
      return new Transform3D(v["xform3d"]);
    }
    if (v["proj"] != null) {
      return new Projection(v["proj"]);
    }
    if (v["sname"] != null) {
      return new StringName(v["sname"]);
    }
    if (v["npath"] != null) {
      return new NodePath(v["npath"]);
    }
    if (v["rid"] != null) {
      return new GRid(v["rid"]);
    }
    if (v["u8"] != null) {
      return new Packed("u8", v["u8"]);
    }
    if (v["i32"] != null) {
      return new Packed("i32", v["i32"]);
    }
    if (v["i64"] != null) {
      return new Packed("i64", v["i64"]);
    }
    if (v["f32"] != null) {
      return new Packed("f32", v["f32"]);
    }
    if (v["f64"] != null) {
      return new Packed("f64", v["f64"]);
    }
    if (v["strs"] != null) {
      return new Packed("strs", v["strs"]);
    }
    if (v["pv2"] != null) {
      return new Packed("pv2", v["pv2"]);
    }
    if (v["pv3"] != null) {
      return new Packed("pv3", v["pv3"]);
    }
    if (v["pv4"] != null) {
      return new Packed("pv4", v["pv4"]);
    }
    if (v["pcol"] != null) {
      return new Packed("pcol", v["pcol"]);
    }
    if (v["dict"] != null) {
      let src = v["dict"];
      let out = {};
      let ks = src.keys;
      for (let i = 0; i < ks.length; i++) {
        out[ks[i]] = __gdUnmarshal(src[ks[i]]);
      }
      return out;
    }
    if (v["dictv"] != null) {
      let d = new GDict();
      for (let i = 0; i < v["dictv"].length; i++) {
        d.put(__gdUnmarshal(v["dictv"][i][0]), __gdUnmarshal(v["dictv"][i][1]));
      }
      return d;
    }
    return v;
  }
  return v;
}

// ---------------------------------------------------------------------------
// host -> guest dispatch (signals, callables, engine lifecycle events)
// ---------------------------------------------------------------------------

// Native side invokes __godotDispatch([cbId, [args...]]) to deliver a bridged
// signal emission or Callable invocation to its registered JS closure. The
// closure receives the (unmarshaled) signal-argument list.
function __godotDispatch(args) {
  let cb = __gdCallbacks["cb" + args[0]];
  if (cb != null) {
    cb(__gdUnmarshal(args[1]));
  }
}

// Engine lifecycle handlers, registered via GD.onReady/onProcess/...; the
// native ElpianVM node invokes __godotEvent(["_process", payload]) per hook.
var __gdHandlers = {};

function __godotEvent(args) {
  let h = __gdHandlers[args[0]];
  if (h != null) {
    h(__gdUnmarshal(args[1]));
  }
}

function __gdSingletonRaw(name) {
  let id = __gdAllocId();
  __gdRun({ singleton: name, def: id });
  return new GObj(id, name);
}

// ---------------------------------------------------------------------------
// GD — the engine facade
// ---------------------------------------------------------------------------

class GD {
  // ---- raw reflective core (everything else is sugar over these) ----------

  // Execute one raw bridge op — the full-power escape hatch.
  static op(m) {
    return __gdRun(m);
  }

  // Open a batch: all following ops queue locally.
  static beginBatch() {
    __gdBatch = [];
  }

  // Flush the open batch as ONE host call; returns the per-op result list.
  static endBatch() {
    let b = __gdBatch;
    __gdBatch = null;
    if (b == null) {
      return [];
    }
    return __gdUnmarshal(askHost("godot.batch", [b]));
  }

  // Marshal any JS value to its wire shape (for hand-built raw ops).
  static m(v) {
    return __gdMarshal(v);
  }

  // Whether a bridge reply is the protocol's failure shape (JS has no
  // exceptions in the subset, so failed ops surface as this map).
  static isError(r) {
    if (__isType(r, "map")) {
      return r["__dart_error__"] != null;
    }
    return false;
  }

  // ---- objects -------------------------------------------------------------

  // Instantiate any ClassDB-registered class by name.
  static create(cls) {
    let id = __gdAllocId();
    __gdRun({ new: cls, def: id });
    return new GObj(id, cls);
  }

  // Bind any engine singleton by name: 'RenderingServer', 'DisplayServer',
  // 'Input', 'Engine', 'OS', 'Time', 'ProjectSettings', ...
  static singleton(name) {
    return __gdSingletonRaw(name);
  }

  // The SceneTree driving the game (root viewport, groups, timers, pausing).
  static tree() {
    let id = __gdAllocId();
    __gdRun({ tree: true, def: id });
    return new GObj(id, "SceneTree");
  }

  // The native ElpianVM Node hosting this program — mount point for guest-
  // created nodes (GD.mount(n) == GD.host().call('add_child', [n])).
  static host() {
    let id = __gdAllocId();
    __gdRun({ self: true, def: id });
    return new GObj(id, "ElpianVM");
  }

  // Load any resource (scene, texture, script, shader, audio, mesh, ...).
  static load(path) {
    let id = __gdAllocId();
    __gdRun({ load: path, def: id });
    return new GObj(id, "Resource");
  }

  // Add a node under the hosting ElpianVM node (enters the scene tree).
  static mount(node) {
    __gdRun({ self: true, method: "add_child", args: [__gdMarshal(node)] });
  }

  // ---- values / reflection -------------------------------------------------

  // Any class or global constant / enum value by dotted name:
  // GD.constant('Control.PRESET_FULL_RECT'), GD.constant('KEY_ESCAPE').
  static constant(name) {
    return __gdRun({ const: name });
  }

  // Evaluate any Godot Expression — reaches every @GlobalScope utility
  // function and constructor by name. names/values bind expression inputs.
  static eval(expr, names, values) {
    return __gdRun({
      expr: expr,
      names: names ?? [],
      values: __gdMarshalList(values),
    });
  }

  // Wrap a JS closure as a Godot Callable value (for APIs that take one:
  // tweens, SceneTree.timer timeouts, ...).
  static callable(cb) {
    return new GCallable(__gdRegisterCb(cb));
  }

  // Every class registered in ClassDB (the machine-checked coverage universe).
  static classes() {
    return __gdRun({ classes: true });
  }

  // Full reflection for one class: methods, properties, signals, constants.
  static classInfo(cls) {
    return __gdRun({ classinfo: cls });
  }

  // Walk ALL of ClassDB and verify every class/method/property/signal is
  // addressable through this bridge — the "no exceptions" audit.
  static audit() {
    return __gdRun({ audit: true });
  }

  // ---- engine lifecycle hooks ----------------------------------------------

  // Run cb when the hosting node enters the tree and is ready.
  static onReady(cb) {
    __gdHandlers["_ready"] = cb;
  }

  // Run cb every rendered frame with the frame delta (seconds).
  static onProcess(cb) {
    __gdHandlers["_process"] = cb;
  }

  // Run cb every physics tick with the fixed delta (seconds).
  static onPhysicsProcess(cb) {
    __gdHandlers["_physics_process"] = cb;
  }

  // Run cb for every InputEvent (receives a GObj proxy of the event).
  static onInput(cb) {
    __gdHandlers["_input"] = cb;
  }

  // Run cb for unhandled input events.
  static onUnhandledInput(cb) {
    __gdHandlers["_unhandled_input"] = cb;
  }

  // Run cb with each Object.notification(what) integer on the host node.
  static onNotification(cb) {
    __gdHandlers["_notification"] = cb;
  }

  // Run cb just before the hosting node exits the tree (teardown).
  static onExit(cb) {
    __gdHandlers["_exit_tree"] = cb;
  }

  // ---- frequently-used singletons (sugar; any name works via singleton()) --

  static input() {
    return __gdSingletonRaw("Input");
  }
  static renderingServer() {
    return __gdSingletonRaw("RenderingServer");
  }
  static physicsServer2D() {
    return __gdSingletonRaw("PhysicsServer2D");
  }
  static physicsServer3D() {
    return __gdSingletonRaw("PhysicsServer3D");
  }
  static audioServer() {
    return __gdSingletonRaw("AudioServer");
  }
  static displayServer() {
    return __gdSingletonRaw("DisplayServer");
  }
  static engine() {
    return __gdSingletonRaw("Engine");
  }
  static os() {
    return __gdSingletonRaw("OS");
  }
  static time() {
    return __gdSingletonRaw("Time");
  }
  static projectSettings() {
    return __gdSingletonRaw("ProjectSettings");
  }
  static resourceLoader() {
    return __gdSingletonRaw("ResourceLoader");
  }
}

// ---------------------------------------------------------------------------
// GObj — the universal object proxy (any Godot Object, Node, Resource, server)
// ---------------------------------------------------------------------------

class GObj {
  constructor(id, cls) {
    this.id = id;
    this.cls = cls;
  }

  // Call ANY method by name. n.call('add_child', [child]),
  // tween.call('tween_property', [...]).
  call(method, args) {
    return __gdRun({ ref: this.id, method: method, args: __gdMarshalList(args) });
  }

  // Read ANY property. node.get('position') -> Vector2.
  get(prop) {
    return __gdRun({ ref: this.id, get: prop });
  }

  // Write ANY property. node.set('modulate', new Color(1, 0, 0, 1)).
  set(prop, value) {
    __gdRun({ ref: this.id, set: prop, value: __gdMarshal(value) });
  }

  // Read a nested sub-property path (Object.get_indexed): 'position:x'.
  getIndexed(path) {
    return __gdRun({ ref: this.id, geti: path });
  }

  // Write a nested sub-property path: n.setIndexed('position:x', 10.0).
  setIndexed(path, value) {
    __gdRun({ ref: this.id, seti: path, value: __gdMarshal(value) });
  }

  // Connect ANY signal to a JS closure; returns the callback id (keep it to
  // disconnect). flags = Object.CONNECT_* bitmask (0 = default).
  connect(signal, cb, flags) {
    let cbId = __gdRegisterCb(cb);
    __gdRun({ ref: this.id, connect: signal, cb: cbId, flags: flags ?? 0 });
    return cbId;
  }

  // Disconnect a connection made with connect().
  disconnect(signal, cbId) {
    __gdRun({ ref: this.id, disconnect: signal, cb: cbId });
  }

  // Emit ANY signal with arguments.
  emitSignal(signal, args) {
    let a = [];
    a.push({ sname: signal });
    if (args != null) {
      for (let i = 0; i < args.length; i++) {
        a.push(__gdMarshal(args[i]));
      }
    }
    return __gdRun({ ref: this.id, method: "emit_signal", args: a });
  }

  // A first-class reference to one of this object's signals.
  signal(name) {
    return new GSignal(this, name);
  }

  // Node.queue_free() — safe deletion at end of frame (also drops the handle).
  queueFree() {
    __gdRun({ free: this.id, mode: "queue" });
  }

  // Immediate Object.free() / memdelete (also drops the handle).
  freeNow() {
    __gdRun({ free: this.id, mode: "now" });
  }

  // Drop only the bridge handle (unreferences a RefCounted; never deletes a
  // plain Object). Use for resources/objects the engine still owns.
  release() {
    __gdRun({ free: this.id, mode: "handle" });
  }
}

// A Callable wire value produced by GD.callable() (rarely needed directly —
// bare closures marshal automatically).
class GCallable {
  constructor(cbId) {
    this.cbId = cbId;
  }
}

// A first-class Signal value (marshals to Godot's Signal Variant).
class GSignal {
  constructor(source, name) {
    this.source = source;
    this.name = name;
  }
}

// ---------------------------------------------------------------------------
// value types — the full Godot Variant vocabulary
// ---------------------------------------------------------------------------

class Vector2 {
  constructor(x, y) {
    this.x = x;
    this.y = y;
  }
  static zero() {
    return new Vector2(0.0, 0.0);
  }
  static one() {
    return new Vector2(1.0, 1.0);
  }
  plus(o) {
    return new Vector2(this.x + o.x, this.y + o.y);
  }
  minus(o) {
    return new Vector2(this.x - o.x, this.y - o.y);
  }
  times(s) {
    return new Vector2(this.x * s, this.y * s);
  }
  dot(o) {
    return this.x * o.x + this.y * o.y;
  }
  lengthSquared() {
    return this.x * this.x + this.y * this.y;
  }
}

class Vector2i {
  constructor(x, y) {
    this.x = x;
    this.y = y;
  }
}

class Vector3 {
  constructor(x, y, z) {
    this.x = x;
    this.y = y;
    this.z = z;
  }
  static zero() {
    return new Vector3(0.0, 0.0, 0.0);
  }
  static one() {
    return new Vector3(1.0, 1.0, 1.0);
  }
  plus(o) {
    return new Vector3(this.x + o.x, this.y + o.y, this.z + o.z);
  }
  minus(o) {
    return new Vector3(this.x - o.x, this.y - o.y, this.z - o.z);
  }
  times(s) {
    return new Vector3(this.x * s, this.y * s, this.z * s);
  }
  dot(o) {
    return this.x * o.x + this.y * o.y + this.z * o.z;
  }
  cross(o) {
    return new Vector3(
      this.y * o.z - this.z * o.y,
      this.z * o.x - this.x * o.z,
      this.x * o.y - this.y * o.x
    );
  }
  lengthSquared() {
    return this.x * this.x + this.y * this.y + this.z * this.z;
  }
}

class Vector3i {
  constructor(x, y, z) {
    this.x = x;
    this.y = y;
    this.z = z;
  }
}

class Vector4 {
  constructor(x, y, z, w) {
    this.x = x;
    this.y = y;
    this.z = z;
    this.w = w;
  }
}

class Vector4i {
  constructor(x, y, z, w) {
    this.x = x;
    this.y = y;
    this.z = z;
    this.w = w;
  }
}

class Color {
  constructor(r, g, b, a) {
    this.r = r;
    this.g = g;
    this.b = b;
    this.a = a;
  }
  static rgb(r, g, b) {
    return new Color(r, g, b, 1.0);
  }
  // From a 0xAARRGGBB int (Flutter-style), e.g. Color.hex(0xFF2196F3 as dec).
  static hex(argb) {
    let aa = (intDiv(argb, 16777216) % 256) / 255.0;
    let rr = (intDiv(argb, 65536) % 256) / 255.0;
    let gg = (intDiv(argb, 256) % 256) / 255.0;
    let bb = (argb % 256) / 255.0;
    return new Color(rr, gg, bb, aa);
  }
  withAlpha(a) {
    return new Color(this.r, this.g, this.b, a);
  }
  // Linear blend toward another color, t in [0, 1].
  mix(o, t) {
    return new Color(
      this.r + (o.r - this.r) * t,
      this.g + (o.g - this.g) * t,
      this.b + (o.b - this.b) * t,
      this.a + (o.a - this.a) * t
    );
  }
  // Additive lighten / darken (clamped by the engine on write).
  lighter(k) {
    return new Color(this.r + k, this.g + k, this.b + k, this.a);
  }
  darker(k) {
    return new Color(this.r - k, this.g - k, this.b - k, this.a);
  }
}

class Rect2 {
  constructor(x, y, w, h) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
  }
}

class Rect2i {
  constructor(x, y, w, h) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
  }
}

class Plane {
  constructor(nx, ny, nz, d) {
    this.nx = nx;
    this.ny = ny;
    this.nz = nz;
    this.d = d;
  }
}

class Quaternion {
  constructor(x, y, z, w) {
    this.x = x;
    this.y = y;
    this.z = z;
    this.w = w;
  }
  static identity() {
    return new Quaternion(0.0, 0.0, 0.0, 1.0);
  }
}

class AABB {
  constructor(px, py, pz, sx, sy, sz) {
    this.px = px;
    this.py = py;
    this.pz = pz;
    this.sx = sx;
    this.sy = sy;
    this.sz = sz;
  }
}

// Row-major 9 floats [xx,xy,xz, yx,yy,yz, zx,zy,zz].
class Basis {
  constructor(rows) {
    this.rows = rows;
  }
  static identity() {
    return new Basis([1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]);
  }
}

// Column-vector 6 floats [ax,ay, bx,by, ox,oy] (x-axis, y-axis, origin).
class Transform2D {
  constructor(m) {
    this.m = m;
  }
  static identity() {
    return new Transform2D([1.0, 0.0, 0.0, 1.0, 0.0, 0.0]);
  }
  static translated(x, y) {
    return new Transform2D([1.0, 0.0, 0.0, 1.0, x, y]);
  }
}

// Basis rows then origin: 12 floats [xx..zz, ox,oy,oz].
class Transform3D {
  constructor(m) {
    this.m = m;
  }
  static identity() {
    return new Transform3D([1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0]);
  }
  static translated(x, y, z) {
    return new Transform3D([1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, x, y, z]);
  }
}

// Column-major 16 floats.
class Projection {
  constructor(m) {
    this.m = m;
  }
}

class StringName {
  constructor(value) {
    this.value = value;
  }
}

class NodePath {
  constructor(value) {
    this.value = value;
  }
}

// A server-side resource id (RenderingServer/PhysicsServer handles).
class GRid {
  constructor(id) {
    this.id = id;
  }
}

// Force integer typing for an ambiguous numeric argument.
class GInt {
  constructor(value) {
    this.value = value;
  }
}

// Force float typing for an ambiguous numeric argument.
class GFloat {
  constructor(value) {
    this.value = value;
  }
}

// A Godot Dictionary with non-string (or order-sensitive) keys.
class GDict {
  constructor() {
    this.entries = [];
  }
  put(k, v) {
    this.entries.push([k, v]);
  }
}

// A packed array wire value. tag: u8 (base64 String) | i32 | i64 | f32 |
// f64 | strs | pv2 | pv3 | pv4 | pcol (flat number lists).
class Packed {
  constructor(tag, data) {
    this.tag = tag;
    this.data = data;
  }
  static bytesBase64(b64) {
    return new Packed("u8", b64);
  }
  static i32(v) {
    return new Packed("i32", v);
  }
  static i64(v) {
    return new Packed("i64", v);
  }
  static f32(v) {
    return new Packed("f32", v);
  }
  static f64(v) {
    return new Packed("f64", v);
  }
  static strings(v) {
    return new Packed("strs", v);
  }
  static vector2s(flatXY) {
    return new Packed("pv2", flatXY);
  }
  static vector3s(flatXYZ) {
    return new Packed("pv3", flatXYZ);
  }
  static vector4s(flatXYZW) {
    return new Packed("pv4", flatXYZW);
  }
  static colors(flatRGBA) {
    return new Packed("pcol", flatRGBA);
  }
}

// ---------------------------------------------------------------------------
// VMs — orchestrating the multi-VM tree (same contract as godot.dart)
// ---------------------------------------------------------------------------

// Handlers: "message" -> cb(senderId, msg);
// "notify" / "notify:<kind>" -> cb(kind, vmId, detail).
var __vmHandlers = {};

// The manager delivers child notifications here:
// ["trapped", vmId, reason] or ["terminated", vmId, reason].
function __vmNotify(args) {
  let h = __vmHandlers["notify:" + args[0]];
  if (h != null) {
    h(args[0], args[1], args[2]);
    return;
  }
  let all = __vmHandlers["notify"];
  if (all != null) {
    all(args[0], args[1], args[2]);
  }
}

// The manager delivers inter-VM messages here: [senderVmId, message].
function __vmMessage(args) {
  let h = __vmHandlers["message"];
  if (h != null) {
    h(args[0], args[1]);
  }
}

function __vmSpawnRaw(source, node, options) {
  let opts = {};
  if (options != null) {
    let ks = options.keys;
    for (let i = 0; i < ks.length; i++) {
      opts[ks[i]] = options[ks[i]];
    }
  }
  opts["node"] = node.id;
  let r = askHost("vm.spawn", [source, opts]);
  if (__isType(r, "number")) {
    return r; // the child's vm id
  }
  if (__isType(r, "map")) {
    return r; // an {__dart_error__: ...} failure
  }
  // A capability-denied call short-circuits to the VM's typed null; normalize
  // so `== null` works for callers.
  return null;
}

// Control handle over one VM in the caller's subtree. Obtained from
// VMs.spawn(...) or VMs.of(id). Every verb is authorized against the VM tree.
class VmController {
  constructor(id) {
    this.id = id;
  }

  // ---- lifecycle -----------------------------------------------------------

  // Suspend the VM and its whole subtree: no events, no timers, no messages.
  pause() {
    return askHost("vm.pause", [this.id]);
  }

  // Resume a paused subtree exactly where it stopped.
  resume() {
    return askHost("vm.resume", [this.id]);
  }

  // Terminate the VM and its whole descendant subtree.
  terminate() {
    return askHost("vm.terminate", [this.id]);
  }

  // {id, label, state, trap, paused, alive}.
  state() {
    return askHost("vm.state", [this.id]);
  }

  // ---- resources -----------------------------------------------------------

  usage() {
    return askHost("vm.usage", [this.id]);
  }

  usageTree() {
    return askHost("vm.usageTree", [this.id]);
  }

  limits() {
    return askHost("vm.limits", [this.id]);
  }

  setLimits(limits) {
    return askHost("vm.setLimits", [this.id, limits]);
  }

  // ---- permissions ---------------------------------------------------------

  setPermission(name, allowed) {
    return askHost("vm.setPermission", [this.id, name, allowed]);
  }

  permissions() {
    return askHost("vm.permissions", [this.id]);
  }

  grant(obj) {
    return askHost("vm.grant", [this.id, obj.id]);
  }

  // ---- messaging / introspection --------------------------------------------

  send(msg) {
    return askHost("vm.send", [this.id, msg]);
  }

  children() {
    return askHost("vm.list", [this.id]);
  }
}

// The multi-VM orchestration facade. A spawned child inherits its parent's
// guest language by default; pass options.lang = 'js' | 'dart' to override.
class VMs {
  // Instantiate and boot a new child VM running source, sandboxed to node.
  // Returns a VmController, or null when denied/failed.
  static spawn(source, node, options) {
    let r = __vmSpawnRaw(source, node, options);
    if (__isType(r, "number")) {
      return new VmController(r);
    }
    return null;
  }

  // Like spawn but returns the raw reply: the child's vm id (num) on success,
  // an {__dart_error__: ...} map on failure, or null when vm_manage is off.
  static trySpawn(source, node, options) {
    return __vmSpawnRaw(source, node, options);
  }

  // Whether a vm.* reply is an error map.
  static isError(r) {
    if (__isType(r, "map")) {
      return r["__dart_error__"] != null;
    }
    return false;
  }

  // A control handle for an already-known vm id.
  static of(id) {
    return new VmController(id);
  }

  // This VM's own identity: {id, parent, label, scene, node}.
  static info() {
    return askHost("vm.info", []);
  }

  // The caller's direct children: [{id, label, paused, alive}, ...].
  static children() {
    return askHost("vm.list", []);
  }

  // Send a message up to the parent VM (delivered to its onMessage).
  static sendParent(msg) {
    let i = askHost("vm.info", []);
    if (i != null && i["parent"] != null) {
      return askHost("vm.send", [i["parent"], msg]);
    }
    return null;
  }

  // Receive inter-VM messages: cb(senderVmId, message).
  static onMessage(cb) {
    __vmHandlers["message"] = cb;
  }

  // Receive every child notification: cb(kind, vmId, detail).
  static onNotify(cb) {
    __vmHandlers["notify"] = cb;
  }

  // Only 'trapped' notifications (a child hit its own resource governor).
  static onChildTrapped(cb) {
    __vmHandlers["notify:trapped"] = cb;
  }

  // Only 'terminated' notifications (a child branch was removed).
  static onChildTerminated(cb) {
    __vmHandlers["notify:terminated"] = cb;
  }
}

// ---------------------------------------------------------------------------
// GTimer — timers riding the VM's own event loop, pumped once per engine frame
// ---------------------------------------------------------------------------
// Callbacks take NO parameters (the VM's __dartDispatch invokes them
// argument-free). Named GTimer so it cannot shadow Godot's own Timer node.

class GTimer {
  constructor(id) {
    this.id = id;
  }

  // Run cb every `milliseconds` until cancelled.
  static periodic(milliseconds, cb) {
    __cbReg.push(cb);
    return new GTimer(askHost("dart:async/Timer.periodic", [__cbReg.length - 1, milliseconds]));
  }

  // Run cb once after `milliseconds`.
  static after(milliseconds, cb) {
    __cbReg.push(cb);
    return new GTimer(askHost("dart:async/Timer", [__cbReg.length - 1, milliseconds]));
  }

  cancel() {
    return askHost("dart:async/Timer.cancel", [this.id]);
  }
}

// ---------------------------------------------------------------------------
// G3 — a small 3D convenience layer over the reflective bridge.
// ---------------------------------------------------------------------------
// Everything G3 builds is a plain Godot node/resource created with GD.create;
// it is sugar, not a new capability (a raw guest can do all of this by hand).
// It exists so hand-written JS guests AND the VReact 3D host drivers share one
// correct vocabulary for meshes, materials, lights, cameras and — crucially —
// the 2D<->3D viewport bridge (SubViewportContainer + SubViewport) that lets a
// 3D world live inside a 2D Control UI. All names/properties match Godot 4.

// Read a numeric option with a default. The VM has ONE representation for
// 0 / null / an absent member, and it type-checks as num — so test for
// absence (== null) FIRST or every absent option silently becomes 0
// (zero-radius cylinders, black lights, …).
function __g3num(v, d) {
  if (v == null) {
    return d;
  }
  if (__isType(v, "number")) {
    return v;
  }
  return d;
}

// Coerce an option into a Vector3: a [x,y,z] list, a scalar (uniform), a
// Vector3, or a default (dx,dy,dz).
function __g3vec(v, dx, dy, dz) {
  if (v == null) {
    return new Vector3(dx, dy, dz);
  }
  if (__isType(v, "Vector3")) {
    return v;
  }
  if (__isType(v, "number")) {
    return new Vector3(v, v, v);
  }
  if (__isType(v, "list")) {
    let x = v.length > 0 ? v[0] : dx;
    let y = v.length > 1 ? v[1] : dy;
    let z = v.length > 2 ? v[2] : dz;
    return new Vector3(x, y, z);
  }
  return new Vector3(dx, dy, dz);
}


// G3 is an object namespace (not a class) so its methods can call each other by
// name — `G3.mesh` composes `G3.primitive`/`G3.material`/`G3.setTransform`, the
// same sibling-dispatch pattern VUI uses. (Class *static* methods cannot call
// one another in this subset.)
var G3 = {};

// A StandardMaterial3D from { color, metallic, roughness, emission,
// emissionEnergy, transparency }.
G3.material = (o) => {
  o = o ?? {};
  let m = GD.create("StandardMaterial3D");
  let col = o.color;
  if (col == null) {
    col = new Color(0.8, 0.82, 0.9, 1.0);
  }
  m.set("albedo_color", col);
  if (o.metallic != null) {
    m.set("metallic", GFloat(o.metallic));
  }
  if (o.roughness != null) {
    m.set("roughness", GFloat(o.roughness));
  }
  if (o.emission != null) {
    m.set("emission_enabled", true);
    m.set("emission", o.emission);
    if (o.emissionEnergy != null) {
      m.set("emission_energy_multiplier", GFloat(o.emissionEnergy));
    }
  }
  if (o.transparency == true) {
    m.set("transparency", GInt(1)); // BaseMaterial3D.TRANSPARENCY_ALPHA
  }
  return m;
};

// A primitive mesh RESOURCE (BoxMesh/SphereMesh/…) from a shape name + dims.
G3.primitive = (shape, o) => {
  o = o ?? {};
  let mesh = null;
  if (shape == "sphere") {
    mesh = GD.create("SphereMesh");
    let r = __g3num(o.radius, 0.5);
    mesh.set("radius", GFloat(r));
    mesh.set("height", GFloat(__g3num(o.height, r * 2.0)));
  } else if (shape == "cylinder") {
    mesh = GD.create("CylinderMesh");
    let r = __g3num(o.radius, 0.5);
    mesh.set("top_radius", GFloat(__g3num(o.topRadius, r)));
    mesh.set("bottom_radius", GFloat(__g3num(o.bottomRadius, r)));
    mesh.set("height", GFloat(__g3num(o.height, 1.0)));
  } else if (shape == "capsule") {
    mesh = GD.create("CapsuleMesh");
    mesh.set("radius", GFloat(__g3num(o.radius, 0.4)));
    mesh.set("height", GFloat(__g3num(o.height, 1.4)));
  } else if (shape == "plane") {
    mesh = GD.create("PlaneMesh");
    mesh.set("size", new Vector2(__g3num(o.width, 2.0), __g3num(o.depth, 2.0)));
  } else if (shape == "prism") {
    mesh = GD.create("PrismMesh");
    mesh.set("size", __g3vec(o.size, 1.0, 1.0, 1.0));
  } else if (shape == "torus") {
    mesh = GD.create("TorusMesh");
    mesh.set("inner_radius", GFloat(__g3num(o.innerRadius, 0.3)));
    mesh.set("outer_radius", GFloat(__g3num(o.outerRadius, 0.6)));
  } else {
    mesh = GD.create("BoxMesh");
    mesh.set("size", __g3vec(o.size, 1.0, 1.0, 1.0));
  }
  return mesh;
};

// A MeshInstance3D with a primitive mesh + material + transform.
G3.mesh = (shape, o) => {
  o = o ?? {};
  let mi = GD.create("MeshInstance3D");
  let prim = G3.primitive(shape, o);
  let mat = o.material;
  if (mat == null) {
    mat = G3.material(o);
  }
  prim.set("material", mat);
  mi.set("mesh", prim);
  G3.setTransform(mi, o);
  return mi;
};

// A bare Node3D (a 3D group) with an optional transform.
G3.node = (o) => {
  let n = GD.create("Node3D");
  G3.setTransform(n, o);
  return n;
};

G3.camera = (o) => {
  o = o ?? {};
  let c = GD.create("Camera3D");
  if (o.fov != null) {
    c.set("fov", GFloat(o.fov));
  }
  if (o.current != false) {
    c.set("current", true);
  }
  G3.setTransform(c, o);
  return c;
};

G3.dirLight = (o) => {
  o = o ?? {};
  let l = GD.create("DirectionalLight3D");
  l.set("light_color", o.color ?? new Color(1.0, 0.98, 0.92, 1.0));
  l.set("light_energy", GFloat(__g3num(o.energy, 1.0)));
  if (o.shadow == true) {
    l.set("shadow_enabled", true);
  }
  G3.setTransform(l, o);
  return l;
};

G3.omniLight = (o) => {
  o = o ?? {};
  let l = GD.create("OmniLight3D");
  l.set("light_color", o.color ?? new Color(1.0, 1.0, 1.0, 1.0));
  l.set("light_energy", GFloat(__g3num(o.energy, 1.0)));
  if (o.range != null) {
    l.set("omni_range", GFloat(o.range));
  }
  G3.setTransform(l, o);
  return l;
};

G3.spotLight = (o) => {
  o = o ?? {};
  let l = GD.create("SpotLight3D");
  l.set("light_color", o.color ?? new Color(1.0, 1.0, 1.0, 1.0));
  l.set("light_energy", GFloat(__g3num(o.energy, 1.0)));
  if (o.range != null) {
    l.set("spot_range", GFloat(o.range));
  }
  if (o.angle != null) {
    l.set("spot_angle", GFloat(o.angle));
  }
  G3.setTransform(l, o);
  return l;
};

// A WorldEnvironment + Environment (color background + ambient light) so a 3D
// scene is lit and framed even before you add explicit lights.
G3.environment = (o) => {
  o = o ?? {};
  let we = GD.create("WorldEnvironment");
  let env = GD.create("Environment");
  env.set("background_mode", GD.constant("Environment.BG_COLOR"));
  env.set("background_color", o.bg ?? new Color(0.05, 0.06, 0.09, 1.0));
  env.set("ambient_light_source", GD.constant("Environment.AMBIENT_SOURCE_COLOR"));
  env.set("ambient_light_color", o.ambient ?? new Color(0.5, 0.55, 0.7, 1.0));
  env.set("ambient_light_energy", GFloat(__g3num(o.ambientEnergy, 0.6)));
  we.set("environment", env);
  return we;
};

// The 2D<->3D bridge: a SubViewportContainer (a Control you place in the UI)
// wrapping a SubViewport (where 3D nodes live). Returns { container, viewport }.
// Pass picking: true to enable physics object picking inside the viewport
// (bodies/areas then receive `input_event` for taps/clicks/drags).
G3.viewport = (o) => {
  o = o ?? {};
  let vpc = GD.create("SubViewportContainer");
  vpc.set("stretch", true);
  let vp = GD.create("SubViewport");
  vp.set("own_world_3d", true);
  if (o.transparent == true) {
    vp.set("transparent_bg", true);
  }
  vp.set("render_target_update_mode", GD.constant("SubViewport.UPDATE_ALWAYS"));
  if (o.msaa == true) {
    vp.set("msaa_3d", GInt(2)); // Viewport.MSAA_4X
  }
  if (o.picking == true) {
    vp.set("physics_object_picking", true);
    vp.set("physics_object_picking_sort", true);
  }
  vpc.call("add_child", [vp]);
  return { container: vpc, viewport: vp };
};

// Apply { position, rotation(deg), scale, visible } to any Node3D.
G3.setTransform = (node, o) => {
  o = o ?? {};
  if (o.position != null) {
    node.set("position", __g3vec(o.position, 0.0, 0.0, 0.0));
  }
  if (o.rotation != null) {
    node.set("rotation_degrees", __g3vec(o.rotation, 0.0, 0.0, 0.0));
  }
  if (o.scale != null) {
    node.set("scale", __g3vec(o.scale, 1.0, 1.0, 1.0));
  }
  if (o.visible != null) {
    node.set("visible", o.visible == true);
  }
};

// ---------------------------------------------------------------------------
// G3 — models & scenes (GLTF/GLB), instancing, picking
// ---------------------------------------------------------------------------

// Instantiate a PackedScene resource by path (res://…tscn / an imported .glb).
G3.instanceScene = (path) => {
  let ps = GD.load(path);
  if (ps == null || GD.isError(ps)) {
    return null;
  }
  let node = ps.call("instantiate");
  if (node == null || GD.isError(node)) {
    return null;
  }
  return node;
};

// Load a glTF / GLB model and return its root Node3D, or null on failure.
//
//   G3.gltf("res://assets/models/buildings/town_hall.glb")
//   G3.gltf("user://cache/hero.glb")
//   G3.gltf({ base64: b64 })            // raw GLB bytes fetched over the net
//
// A res:// path uses the import pipeline when available (GD.load of an
// imported scene) and falls back to GLTFDocument parsing of the raw file, so
// models work both inside an exported project and from loose asset folders.
// Options: { position, rotation, scale, visible } apply to the returned root.
G3.gltf = (src, o) => {
  o = o ?? {};
  let root = null;
  if (__isType(src, "map")) {
    if (src.base64 != null) {
      let doc = GD.create("GLTFDocument");
      let state = GD.create("GLTFState");
      let buf = new Packed("u8", src.base64);
      let err = doc.call("append_from_buffer", [buf, "", state]);
      if (!GD.isError(err) && err == 0) {
        root = doc.call("generate_scene", [state]);
      }
    }
  } else {
    let path = "" + src;
    if (path.startsWith("res://")) {
      root = G3.instanceScene(path);
    }
    if (root == null || GD.isError(root)) {
      let doc = GD.create("GLTFDocument");
      let state = GD.create("GLTFState");
      let err = doc.call("append_from_file", [path, state]);
      if (!GD.isError(err) && err == 0) {
        root = doc.call("generate_scene", [state]);
      }
    }
  }
  if (root == null || GD.isError(root)) {
    return null;
  }
  G3.setTransform(root, o);
  return root;
};

// Fit a freshly loaded model to a target height: scales the node uniformly so
// its AABB height equals `targetHeight` (mirrors the web client's
// "targetHeight" model-normalisation convention). Requires the node to be in
// the tree (AABB is computed from visual instances).
// Max mesh AABB height in a node subtree (local mesh space, depth-limited).
// GLB scene roots are plain Node3Ds with no get_aabb of their own, so the
// height is derived from their MeshInstance3D descendants.
function __g3MeshHeight(node, depth, scaleAcc) {
  if (node == null || depth > 10) {
    return 0.0;
  }
  // Accumulate node scales down the tree — GLB exports routinely bake unit
  // conversions (cm -> m) as node scale, so a mesh's LOCAL AABB says nothing
  // about its rendered size without them.
  let acc = scaleAcc;
  let sc = node.get("scale");
  if (sc != null && !GD.isError(sc) && __isType(sc, "Vector3")) {
    acc = acc * sc.y;
  }
  let best = 0.0;
  if (node.call("has_method", ["get_aabb"]) == true) {
    let aabb = node.call("get_aabb");
    if (aabb != null && !GD.isError(aabb) && __isType(aabb, "AABB")) {
      let h0 = aabb.sy * acc;
      if (h0 > best) {
        best = h0;
      }
    }
  }
  let n = node.call("get_child_count");
  if (n == null || GD.isError(n)) {
    return best;
  }
  for (let i = 0; i < n; i++) {
    let h = __g3MeshHeight(node.call("get_child", [GInt(i)]), depth + 1, acc);
    if (h > best) {
      best = h;
    }
  }
  return best;
}

G3.fitHeight = (node, targetHeight) => {
  // The node's own scale participates via the walk; fitHeight REPLACES the
  // root scale, so measure the subtree below with the root normalized to 1.
  let sy = __g3MeshHeight(node, 0, 1.0);
  let rootSc = node.get("scale");
  if (rootSc != null && !GD.isError(rootSc) && __isType(rootSc, "Vector3")) {
    if (rootSc.y > 0.0) {
      sy = sy / rootSc.y;
    }
  }
  if (sy > 0.0) {
    let k = targetHeight / sy;
    // Clamp against degenerate AABBs (an empty mesh must not explode the
    // scale and swallow the camera).
    if (k < 0.001) {
      k = 0.001;
    }
    if (k > 1000.0) {
      k = 1000.0;
    }
    node.set("scale", new Vector3(k, k, k));
  }
  return node;
};

// Cast a physics ray from a camera through a screen point in its viewport.
// Returns the intersect dictionary ({position, normal, collider, …}) or null.
G3.raycast = (viewport, camera, x, y, dist) => {
  let from = camera.call("project_ray_origin", [new Vector2(x, y)]);
  let dir = camera.call("project_ray_normal", [new Vector2(x, y)]);
  if (from == null || dir == null || GD.isError(from) || GD.isError(dir)) {
    return null;
  }
  let d = __g3num(dist, 2000.0);
  let to = new Vector3(from.x + dir.x * d, from.y + dir.y * d, from.z + dir.z * d);
  let world = viewport.call("get_world_3d");
  if (world == null || GD.isError(world)) {
    return null;
  }
  let space = world.call("get_direct_space_state");
  if (space == null || GD.isError(space)) {
    return null;
  }
  let q = GD.eval(
    "PhysicsRayQueryParameters3D.create(f, t)",
    ["f", "t"],
    [from, to]
  );
  if (q == null || GD.isError(q)) {
    return null;
  }
  let hit = space.call("intersect_ray", [q]);
  if (hit == null || GD.isError(hit)) {
    return null;
  }
  return hit;
};
// =============================================================================
// §2  Flutter surface — FL, driving an embedded Flutter engine
// =============================================================================

// =============================================================================
// flutter.js — FL: drive an embedded, real Flutter engine from an Elpian VM
// =============================================================================
//
// This is the guest half of the **Flutter UI bridge** — the twin of
// `godot.js`/`godot.dart`, but targeting a real `libflutter` engine embedded in
// the GDExtension (see `extension/src/flutter_controller.*` and
// `godot/FLUTTER.md`) instead of ClassDB. Where `GD` reaches every Godot class
// reflectively, `FL` speaks a small **declarative widget-tree op protocol**: the
// guest describes a widget tree as plain data, ships it over the `flutter.op`
// seam, and a fixed AOT-compiled Flutter "interpreter app" running inside the
// embedded engine reconciles that data into real Flutter widgets and paints
// them. No JIT, no codegen on the guest side — App-Store-legal, exactly like the
// rest of this repo.
//
//     import 'flutter.js';
//
//     var count = 0;
//     function App() {
//       return FL.scaffold({
//         appBar: FL.appBar(FL.text('Counter')),
//         body: FL.center(FL.column([
//           FL.text('Taps: ' + count, { size: 32 }),
//           FL.filledButton('Tap me', function () { count = count + 1; }),
//         ])),
//       });
//     }
//     var view = FL.mount(GD.host(), App, { design: [720, 1280] });
//
// The framework owns the render loop: `mount` takes a *builder* (a function
// returning the current widget tree), calls it for the first paint, and calls
// it again after every widget event — so a handler just mutates the state the
// builder reads (here `count`) and returns. State changed from outside an event
// (a timer, a network reply) calls `view.update()` (or `view.setState(fn)`).
//
// Composition: this prelude is layered *after* `godot.js` (an `import
// 'flutter.js';` line pulls it in), so it reuses that prelude's callback
// registry (`__gdRegisterCb` / `__gdCallbacks`) and marshaling. Widget event
// handlers therefore route back through the very same namespaced-callable path
// the Godot bridge uses: a handler becomes a `{"callable": cbId}` wire tag, the
// Rust VmManager rewrites the id into the owning VM's namespace, the C++
// FlutterController queues `(cb, args)` on an engine event, and the node flushes
// it as `__godotDispatch([cb, [args…]])` — which reaches the right VM even deep
// in a spawned subtree. One dispatch path, one sandbox model, for both UIs.
//
// ---------------------------------------------------------------------------
// The op protocol (mirrors godot.op — one seam, `flutter.op`/`flutter.batch`)
// ---------------------------------------------------------------------------
//   {"newview": true, "def": id, "parent": {"ref": nodeHandle}, "opts": {…}}
//                                     spin up an engine + a surface node under
//                                     `parent` (a Godot node in the VM sandbox)
//   {"render": viewId, "tree": <serialized widget tree>}
//                                     reconcile the view to this widget tree
//                                     (emitted by the framework's flush, not by
//                                     the app directly)
//   {"call": viewId, "channel": s, "msg": v}
//                                     send a raw platform message to the app
//   {"resize": viewId, "size": [w,h], "dpr": r}  drive metrics explicitly
//   {"disposeview": viewId}           tear the engine + surface down
//
// A serialized widget node is `{"t": type, "p": props, "c": [children…]}` (plus
// optional `"k": key for keyed reconciliation). Event handlers inside `p` are
// replaced with `{"callable": cbId}` tags at render time (see __flReify).

// The set of engine views this VM owns.
var __flViews = {};
var __flNextView = 1;

// ---------------------------------------------------------------------------
// Widget construction — every widget is just `{t, p, c}` data
// ---------------------------------------------------------------------------

// The universal element factory: __flEl('Padding', {all: 8}, [child]). The AOT
// interpreter app owns the `type -> real Flutter widget` mapping, so new widget
// types need no change here — only in the app.
function __flEl(type, props, children) {
  let node = { t: type, p: props == null ? {} : props };
  if (children != null) {
    // A list of children stays a list; a single child (a widget map or a bare
    // string) is wrapped. Use the VM's neutral type tag, never `.length` — a
    // widget map is not a list and probing it for `.length` is an error.
    if (__isType(children, "list")) {
      node.c = children;
    } else {
      node.c = [children];
    }
  }
  return node;
}

// ---------------------------------------------------------------------------
// Reify a tree for the wire: turn function-valued props into callable tags,
// reusing this view's callback slots across renders so re-rendering a tree does
// not leak an unbounded number of cb ids (the retained-reconciliation trick —
// the same idea react.js uses for its host callbacks).
// ---------------------------------------------------------------------------

function __flReify(view, node) {
  return __flReifyValue(view, node);
}

// Reify ANY value for the wire, so an event handler or a widget is reachable in
// EVERY position — a prop value, an element of a prop array (`children`,
// `actions`, `slivers`, `tabs`, …), or a value nested in a prop map. This is
// what makes the guest side complete by construction: any widget type built
// with `FL.el(type, props, children)` and any handler on any prop is expressed
// uniformly, with no per-widget code here.
//
//   * a function            → a `{callable: id}` tag (a durable slot, reused
//                             across renders so cb ids stay bounded);
//   * a widget node (has a string `t`) → reified {t, k?, p, c};
//   * a list                → each element reified;
//   * any other map          → each value reified (catches handlers/widgets
//                             nested inside a value object);
//   * a scalar               → passed through.
function __flReifyValue(view, v) {
  if (v == null) {
    return null;
  }
  // Use the VM's neutral type tags (list/map/function) — never `.length`, since
  // a map is not an array even if it answers to a length probe.
  if (__isType(v, "function")) {
    return { callable: __flSlot(view, v) };
  }
  if (__isType(v, "list")) {
    let arr = [];
    for (let i = 0; i < v.length; i++) {
      arr.push(__flReifyValue(view, v[i]));
    }
    return arr;
  }
  if (__isType(v, "map")) {
    // Widget node: a map carrying a string type tag `t`.
    if (__isType(v.t, "string")) {
      let out = { t: v.t };
      if (v.k != null) {
        out.k = v.k;
      }
      if (v.p != null) {
        let p = {};
        for (let key in v.p) {
          p[key] = __flReifyValue(view, v.p[key]);
        }
        out.p = p;
      }
      if (v.c != null) {
        let kids = [];
        for (let i = 0; i < v.c.length; i++) {
          kids.push(__flReifyValue(view, v.c[i]));
        }
        out.c = kids;
      }
      return out;
    }
    // Any other map (a value object): reify each value so a handler or widget
    // nested inside it (a custom decoration, a route map, …) is still reached.
    let m = {};
    for (let key in v) {
      m[key] = __flReifyValue(view, v[key]);
    }
    return m;
  }
  // Scalars (number / string / bool) pass through.
  return v;
}

// Hand back a stable cb id for a handler in this render pass, reusing a slot
// allocated on a previous render when possible (so cb ids stay bounded by the
// tree's peak handler count instead of growing every frame).
//
// The durable closure registered here is the framework's event driver: it runs
// the widget's current handler (which only MUTATES app state) and then asks the
// framework to re-render (`__flSchedule`). This "handler mutates, framework
// renders" split is exactly VReact's setState → drain model, and it is load
// bearing: the durable closure is created once at top level, so the re-render's
// `view`-method call is never lexically inside a dispatch-time closure — the one
// shape that trips the front-end's closure capture on a resumed turn.
function __flSlot(view, fn) {
  let idx = view._hidx;
  view._hidx = idx + 1;
  if (idx < view._handlers.length) {
    view._handlers[idx] = fn;
    return view._cbids[idx];
  }
  view._handlers.push(fn);
  let cbid = __gdRegisterCb(function (a) {
    let handler = view._handlers[idx];
    if (handler != null) {
      handler(a);
    }
    __flSchedule(view);
  });
  view._cbids.push(cbid);
  return cbid;
}

// Coalesce a re-render: mark the view dirty and, if no flush is already queued,
// schedule ONE on the VM event loop. Many events in a turn collapse to a single
// reify + `flutter.op` crossing at the next microtask.
function __flSchedule(view) {
  if (view._scheduled) {
    return;
  }
  view._scheduled = true;
  __later(function () {
    view._scheduled = false;
    __flFlush(view);
  });
}

// The framework render step: build the tree from the app's builder, reify it,
// and ship it. A top-level function (never a method reached from a dispatch-time
// closure) so the reify's engine crossing runs on solid ground.
function __flFlush(view) {
  if (view.builder == null) {
    return;
  }
  view._hidx = 0;
  let reified = __flReify(view, view.builder());
  askHost("flutter.op", [{ render: view.id, tree: reified }]);
}

// ---------------------------------------------------------------------------
// FLView — one embedded Flutter engine + one surface node in the scene
// ---------------------------------------------------------------------------

class FLView {
  constructor(id, builder) {
    this.id = id;
    this.builder = builder; // () -> root widget tree, called by the framework
    this._handlers = [];
    this._cbids = [];
    this._hidx = 0;
    this._scheduled = false;
  }

  // Request a re-render. Handlers normally never call this — mutating app state
  // and returning is enough, since the framework re-renders after every event —
  // but a state change from OUTSIDE an event (a `GTimer` tick, a network reply)
  // calls `update()` to schedule a coalesced flush.
  update() {
    __flSchedule(this);
  }

  // Flutter-style convenience: run `fn` (mutate state), then re-render.
  setState(fn) {
    if (fn != null) {
      fn();
    }
    __flSchedule(this);
  }

  // Swap the root builder and re-render (e.g. navigate to another screen).
  setBuilder(builder) {
    this.builder = builder;
    __flSchedule(this);
  }

  // Send a raw platform-channel message to the app (escape hatch for custom
  // channels the interpreter app understands).
  call(channel, msg) {
    return __gdUnmarshal(askHost("flutter.op", [{ call: this.id, channel: channel, msg: msg }]));
  }

  // Explicitly drive window metrics (normally the surface node reports these
  // from its own resize/DPI automatically).
  resize(w, h, dpr) {
    return __gdUnmarshal(askHost("flutter.op", [{ resize: this.id, size: [w, h], dpr: dpr }]));
  }

  // Tear down the engine and remove the surface node.
  dispose() {
    delete __flViews["v" + this.id];
    return __gdUnmarshal(askHost("flutter.op", [{ disposeview: this.id }]));
  }
}

// ===========================================================================
// Canvas / CustomPainter — the full dart:ui drawing surface, as a display list.
// ===========================================================================
//
// A painter is recorded to a serializable **display list** (a list of op maps)
// exactly the way the elpis protocol / `dart/src/dart_ui.rs` record a `dart:ui`
// scene: the guest issues Canvas calls into an `FLCanvas`, they become pure
// data, and the host's `_ReplayPainter` replays them onto the REAL Flutter
// `Canvas`. No closures live in the list, so it ships as plain data and repaints
// on any re-render.
//
//     FL.customPaint([300, 200], function (cv) {
//       var p = FL.paint({ color: [1, 0, 0, 1], style: 'stroke', strokeWidth: 4 });
//       cv.drawCircle(150, 100, 60, p);
//       var path = FL.path().moveTo(0, 0).lineTo(300, 200).close();
//       cv.drawPath(path, FL.paint({ color: [0, 0, 1, 1] }));
//     })
//
// Geometry on the wire: Offset = [x,y]; Rect = [left,top,right,bottom] (LTRB —
// use FL.ltwh(l,t,w,h) if you think in width/height); RRect = {rect:[…],
// radius:n} or {rect, tl,tr,bl,br}; Color = [r,g,b,a] (0..1) or a 0xAARRGGBB int.

// Normalize a path argument to plain data (an FLPath, or an already-plain map).
function __flPathData(p) {
  if (p == null) {
    return null;
  }
  if (p._verbs != null) {
    return { verbs: p._verbs, fillType: p._fillType };
  }
  return p;
}

// A Path builder — records verbs; every dart:ui Path method is present.
class FLPath {
  constructor() {
    this._verbs = [];
    this._fillType = "nonZero";
  }
  moveTo(x, y) { this._verbs.push(["moveTo", x, y]); return this; }
  lineTo(x, y) { this._verbs.push(["lineTo", x, y]); return this; }
  relativeMoveTo(dx, dy) { this._verbs.push(["rMoveTo", dx, dy]); return this; }
  relativeLineTo(dx, dy) { this._verbs.push(["rLineTo", dx, dy]); return this; }
  quadraticBezierTo(x1, y1, x2, y2) { this._verbs.push(["quadTo", x1, y1, x2, y2]); return this; }
  relativeQuadraticBezierTo(x1, y1, x2, y2) { this._verbs.push(["rQuadTo", x1, y1, x2, y2]); return this; }
  cubicTo(x1, y1, x2, y2, x3, y3) { this._verbs.push(["cubicTo", x1, y1, x2, y2, x3, y3]); return this; }
  relativeCubicTo(x1, y1, x2, y2, x3, y3) { this._verbs.push(["rCubicTo", x1, y1, x2, y2, x3, y3]); return this; }
  conicTo(x1, y1, x2, y2, w) { this._verbs.push(["conicTo", x1, y1, x2, y2, w]); return this; }
  relativeConicTo(x1, y1, x2, y2, w) { this._verbs.push(["rConicTo", x1, y1, x2, y2, w]); return this; }
  arcTo(rect, startAngle, sweepAngle, forceMoveTo) {
    this._verbs.push(["arcTo", rect, startAngle, sweepAngle, forceMoveTo == true]);
    return this;
  }
  arcToPoint(x, y, opts) {
    let o = opts == null ? {} : opts;
    this._verbs.push(["arcToPoint", x, y, o.radiusX == null ? 0 : o.radiusX, o.radiusY == null ? 0 : o.radiusY, o.rotation == null ? 0 : o.rotation, o.largeArc == true, o.clockwise != false]);
    return this;
  }
  addRect(rect) { this._verbs.push(["addRect", rect]); return this; }
  addRRect(rrect) { this._verbs.push(["addRRect", rrect]); return this; }
  addOval(rect) { this._verbs.push(["addOval", rect]); return this; }
  addArc(rect, startAngle, sweepAngle) { this._verbs.push(["addArc", rect, startAngle, sweepAngle]); return this; }
  addPolygon(points, close) { this._verbs.push(["addPolygon", points, close == true]); return this; }
  addPath(path, dx, dy) { this._verbs.push(["addPath", __flPathData(path), dx == null ? 0 : dx, dy == null ? 0 : dy]); return this; }
  close() { this._verbs.push(["close"]); return this; }
  reset() { this._verbs = []; return this; }
  fillType(t) { this._fillType = t; return this; }
  data() { return { verbs: this._verbs, fillType: this._fillType }; }
}

// The Canvas recorder — every dart:ui Canvas method, each pushing one op.
class FLCanvas {
  constructor() {
    this._ops = [];
  }
  // ---- layers / transform / clip ----
  save() { this._ops.push({ op: "save" }); return this; }
  saveLayer(rect, paint) { this._ops.push({ op: "saveLayer", rect: rect, paint: paint }); return this; }
  restore() { this._ops.push({ op: "restore" }); return this; }
  restoreToCount(count) { this._ops.push({ op: "restoreToCount", count: count }); return this; }
  translate(dx, dy) { this._ops.push({ op: "translate", dx: dx, dy: dy }); return this; }
  scale(sx, sy) { this._ops.push({ op: "scale", sx: sx, sy: sy == null ? sx : sy }); return this; }
  rotate(radians) { this._ops.push({ op: "rotate", radians: radians }); return this; }
  skew(sx, sy) { this._ops.push({ op: "skew", sx: sx, sy: sy }); return this; }
  transform(matrix16) { this._ops.push({ op: "transform", matrix: matrix16 }); return this; }
  clipRect(rect, opts) {
    let o = opts == null ? {} : opts;
    this._ops.push({ op: "clipRect", rect: rect, clipOp: o.op == null ? "intersect" : o.op, aa: o.aa != false });
    return this;
  }
  clipRRect(rrect, aa) { this._ops.push({ op: "clipRRect", rrect: rrect, aa: aa != false }); return this; }
  clipPath(path, aa) { this._ops.push({ op: "clipPath", path: __flPathData(path), aa: aa != false }); return this; }
  // ---- draws ----
  drawColor(color, blendMode) { this._ops.push({ op: "drawColor", color: color, blend: blendMode == null ? "srcOver" : blendMode }); return this; }
  drawPaint(paint) { this._ops.push({ op: "drawPaint", paint: paint }); return this; }
  drawLine(p1, p2, paint) { this._ops.push({ op: "drawLine", p1: p1, p2: p2, paint: paint }); return this; }
  drawRect(rect, paint) { this._ops.push({ op: "drawRect", rect: rect, paint: paint }); return this; }
  drawRRect(rrect, paint) { this._ops.push({ op: "drawRRect", rrect: rrect, paint: paint }); return this; }
  drawDRRect(outer, inner, paint) { this._ops.push({ op: "drawDRRect", outer: outer, inner: inner, paint: paint }); return this; }
  drawOval(rect, paint) { this._ops.push({ op: "drawOval", rect: rect, paint: paint }); return this; }
  drawCircle(cx, cy, radius, paint) { this._ops.push({ op: "drawCircle", cx: cx, cy: cy, radius: radius, paint: paint }); return this; }
  drawArc(rect, startAngle, sweepAngle, useCenter, paint) { this._ops.push({ op: "drawArc", rect: rect, start: startAngle, sweep: sweepAngle, useCenter: useCenter == true, paint: paint }); return this; }
  drawPath(path, paint) { this._ops.push({ op: "drawPath", path: __flPathData(path), paint: paint }); return this; }
  drawImage(src, dx, dy, paint) { this._ops.push({ op: "drawImage", src: src, dx: dx, dy: dy, paint: paint }); return this; }
  drawImageRect(src, srcRect, dstRect, paint) { this._ops.push({ op: "drawImageRect", src: src, srcRect: srcRect, dstRect: dstRect, paint: paint }); return this; }
  drawImageNine(src, center, dstRect, paint) { this._ops.push({ op: "drawImageNine", src: src, center: center, dstRect: dstRect, paint: paint }); return this; }
  drawParagraph(paragraph, dx, dy) { this._ops.push({ op: "drawParagraph", paragraph: paragraph, dx: dx, dy: dy }); return this; }
  drawPoints(mode, points, paint) { this._ops.push({ op: "drawPoints", mode: mode == null ? "points" : mode, points: points, paint: paint }); return this; }
  drawShadow(path, color, elevation, transparentOccluder) { this._ops.push({ op: "drawShadow", path: __flPathData(path), color: color, elevation: elevation, transparentOccluder: transparentOccluder == true }); return this; }
  drawVertices(vertices, blendMode, paint) { this._ops.push({ op: "drawVertices", vertices: vertices, blend: blendMode == null ? "srcOver" : blendMode, paint: paint }); return this; }
  drawAtlas(src, transforms, rects, colors, blendMode, cullRect, paint) { this._ops.push({ op: "drawAtlas", src: src, transforms: transforms, rects: rects, colors: colors, blend: blendMode, cullRect: cullRect, paint: paint }); return this; }
}

// ---------------------------------------------------------------------------
// FL — the facade
// ---------------------------------------------------------------------------

class FL {
  // Mount a Flutter UI under a Godot node `parent` (any GObj in this VM's
  // sandbox). `builder` is a function returning the root widget tree; the
  // framework calls it now and after every event, so a handler need only mutate
  // the state the builder reads. `opts`: { design: [w,h], transparent: bool,
  // gpu: bool }. Returns an FLView. The C++ controller creates the engine and a
  // surface node child of `parent`, so the UI composites over whatever 2D/3D
  // world lives there.
  //
  //     var count = 0;
  //     function App() {
  //       return FL.scaffold({ body: FL.center(FL.column([
  //         FL.text('Taps: ' + count, { size: 32 }),
  //         FL.filledButton('Tap me', function () { count = count + 1; }),
  //       ])) });
  //     }
  //     var view = FL.mount(GD.host(), App, { design: [720, 1280] });
  static mount(parent, builder, opts) {
    let id = __flNextView;
    __flNextView = __flNextView + 1;
    let ref = parent == null ? null : { ref: parent.id };
    // Detect whether the embedded Flutter engine is actually available: a
    // successful newview replies with the (numeric) view handle; a build with
    // no libflutter (the placeholder, and every web export) replies with an
    // error which the front-end surfaces as a throw. Return null so callers can
    // fall back to a native UI (see bridge/project/scripts/flutter_3d_demo.js).
    let ok = false;
    try {
      let reply = __gdUnmarshal(askHost("flutter.op", [{ newview: true, def: id, parent: ref, opts: opts == null ? {} : opts }]));
      ok = __isType(reply, "number");
    } catch (e) {
      ok = false;
    }
    if (!ok) {
      return null;
    }
    let view = new FLView(id, builder);
    __flViews["v" + id] = view;
    __flFlush(view); // initial paint
    return view;
  }

  // True when the embedded Flutter engine is available in this build. Probes by
  // mounting a throwaway view under `parent` and disposing it.
  static available(parent) {
    let v = FL.mount(parent, function () { return FL.el("SizedBox", {}); }, {});
    if (v == null) {
      return false;
    }
    v.dispose();
    return true;
  }

  // Raw op escape hatch, symmetrical with GD.op.
  static op(m) {
    return __gdUnmarshal(askHost("flutter.op", [m]));
  }

  // ---- widget sugar (thin: every one is __flEl(type, props, children)) -----
  static el(t, p, c) {
    return __flEl(t, p, c);
  }
  static app(p) {
    return __flEl("MaterialApp", p);
  }
  static scaffold(p) {
    return __flEl("Scaffold", p);
  }
  static appBar(title) {
    return __flEl("AppBar", { title: title });
  }
  static text(s, p) {
    return __flEl("Text", { data: s, style: p == null ? {} : p });
  }
  static column(children) {
    return __flEl("Column", {}, children);
  }
  static row(children) {
    return __flEl("Row", {}, children);
  }
  static stack(children) {
    return __flEl("Stack", {}, children);
  }
  static center(child) {
    return __flEl("Center", {}, [child]);
  }
  static padding(all, child) {
    return __flEl("Padding", { all: all }, [child]);
  }
  static container(p, child) {
    return __flEl("Container", p, child == null ? null : [child]);
  }
  static sizedBox(w, h, child) {
    return __flEl("SizedBox", { width: w, height: h }, child == null ? null : [child]);
  }
  static expanded(child) {
    return __flEl("Expanded", {}, [child]);
  }
  static listView(children) {
    return __flEl("ListView", {}, children);
  }
  static image(src, p) {
    return __flEl("Image", { src: src, opts: p == null ? {} : p });
  }
  static icon(name, p) {
    return __flEl("Icon", { name: name, opts: p == null ? {} : p });
  }
  static filledButton(label, onTap) {
    return __flEl("FilledButton", { label: label, onTap: onTap });
  }
  static textButton(label, onTap) {
    return __flEl("TextButton", { label: label, onTap: onTap });
  }
  static iconButton(name, onTap) {
    return __flEl("IconButton", { name: name, onTap: onTap });
  }
  static textField(p) {
    return __flEl("TextField", p == null ? {} : p);
  }
  static switchTile(value, onChanged) {
    return __flEl("Switch", { value: value, onChanged: onChanged });
  }
  static slider(value, onChanged, p) {
    let props = p == null ? {} : p;
    props.value = value;
    props.onChanged = onChanged;
    return __flEl("Slider", props);
  }

  // More content / layout sugar (all thin over __flEl; FL.el reaches anything
  // the host registry knows, so this list is convenience, not the coverage
  // boundary — see FLUTTER.md).
  static align(alignment, child) {
    return __flEl("Align", { alignment: alignment }, [child]);
  }
  static positioned(p, child) {
    return __flEl("Positioned", p, [child]);
  }
  static wrap(children, p) {
    return __flEl("Wrap", p == null ? {} : p, children);
  }
  static flexible(child, flex) {
    return __flEl("Flexible", { flex: flex == null ? 1 : flex }, [child]);
  }
  static aspectRatio(ratio, child) {
    return __flEl("AspectRatio", { aspectRatio: ratio }, [child]);
  }
  static opacity(value, child) {
    return __flEl("Opacity", { opacity: value }, [child]);
  }
  static clip(shape, child) {
    return __flEl(shape == null ? "ClipRRect" : shape, {}, [child]);
  }
  static card(child, p) {
    return __flEl("Card", p == null ? {} : p, [child]);
  }
  static listTile(p) {
    return __flEl("ListTile", p == null ? {} : p);
  }
  static chip(label, p) {
    let props = p == null ? {} : p;
    props.label = label;
    return __flEl("Chip", props);
  }
  static checkbox(value, onChanged) {
    return __flEl("Checkbox", { value: value, onChanged: onChanged });
  }
  static radio(value, groupValue, onChanged) {
    return __flEl("Radio", { value: value, groupValue: groupValue, onChanged: onChanged });
  }
  static dropdown(value, items, onChanged) {
    return __flEl("DropdownButton", { value: value, items: items, onChanged: onChanged });
  }
  static scroll(child, p) {
    return __flEl("SingleChildScrollView", p == null ? {} : p, [child]);
  }
  static gridView(children, p) {
    return __flEl("GridView", p == null ? {} : p, children);
  }
  static pageView(children, p) {
    return __flEl("PageView", p == null ? {} : p, children);
  }
  static tabs(tabs, views, p) {
    let props = p == null ? {} : p;
    props.tabs = tabs;
    props.views = views;
    return __flEl("TabScaffold", props);
  }
  static circularProgress(p) {
    return __flEl("CircularProgressIndicator", p == null ? {} : p);
  }
  static linearProgress(p) {
    return __flEl("LinearProgressIndicator", p == null ? {} : p);
  }
  static divider(p) {
    return __flEl("Divider", p == null ? {} : p);
  }
  static circleAvatar(p) {
    return __flEl("CircleAvatar", p == null ? {} : p);
  }
  static tooltip(message, child) {
    return __flEl("Tooltip", { message: message }, [child]);
  }
  static hero(tag, child) {
    return __flEl("Hero", { tag: tag }, [child]);
  }
  static animatedContainer(p, child) {
    return __flEl("AnimatedContainer", p == null ? {} : p, child == null ? null : [child]);
  }

  // =========================================================================
  // The full event surface. Every gesture / pointer / keyboard / focus / drag
  // / scroll / value callback is reachable — a handler is just a function-valued
  // prop, converted to a `{callable}` tag by the reifier and dispatched back
  // through the same path Godot signals use. The host decodes each callback's
  // details into a JSON argument the handler receives.
  // =========================================================================

  // GestureDetector — the complete tap / double-tap / long-press / drag / pan /
  // scale / force-press / secondary / tertiary callback set. Pass any subset in
  // `handlers`; unknown keys are ignored by the host.
  //
  //   onTapDown onTapUp onTap onTapCancel
  //   onSecondaryTap onSecondaryTapDown onSecondaryTapUp onSecondaryTapCancel
  //   onTertiaryTapDown onTertiaryTapUp onTertiaryTapCancel
  //   onDoubleTap onDoubleTapDown onDoubleTapCancel
  //   onLongPress onLongPressStart onLongPressMoveUpdate onLongPressUp onLongPressEnd
  //   onVerticalDragStart onVerticalDragUpdate onVerticalDragEnd onVerticalDragDown onVerticalDragCancel
  //   onHorizontalDragStart onHorizontalDragUpdate onHorizontalDragEnd onHorizontalDragDown onHorizontalDragCancel
  //   onPanStart onPanUpdate onPanEnd onPanDown onPanCancel
  //   onScaleStart onScaleUpdate onScaleEnd
  //   onForcePressStart onForcePressPeak onForcePressUpdate onForcePressEnd
  static gestures(child, handlers) {
    let p = handlers == null ? {} : handlers;
    p.child = child;
    return __flEl("GestureDetector", p);
  }

  // InkWell — Material tap feedback: onTap onTapDown onTapUp onTapCancel
  // onDoubleTap onLongPress onSecondaryTap onHover onFocusChange onHighlightChanged.
  static inkWell(child, handlers) {
    let p = handlers == null ? {} : handlers;
    p.child = child;
    return __flEl("InkWell", p);
  }

  // Listener — raw pointer events: onPointerDown onPointerMove onPointerUp
  // onPointerHover onPointerCancel onPointerSignal onPointerPanZoomStart
  // onPointerPanZoomUpdate onPointerPanZoomEnd.
  static listener(child, handlers) {
    let p = handlers == null ? {} : handlers;
    p.child = child;
    return __flEl("Listener", p);
  }

  // MouseRegion — hover: onEnter onExit onHover (+ cursor).
  static mouseRegion(child, handlers) {
    let p = handlers == null ? {} : handlers;
    p.child = child;
    return __flEl("MouseRegion", p);
  }

  // Focus — keyboard focus + key events: onFocusChange onKeyEvent (+ autofocus).
  static focus(child, handlers) {
    let p = handlers == null ? {} : handlers;
    p.child = child;
    return __flEl("Focus", p);
  }

  // KeyboardListener — every hardware key: onKeyEvent (down/up/repeat, with
  // logical/physical key, character, and modifier flags in the details).
  static keyboard(child, onKeyEvent, p) {
    let props = p == null ? {} : p;
    props.child = child;
    props.onKeyEvent = onKeyEvent;
    return __flEl("KeyboardListener", props);
  }

  // NotificationListener — scroll & custom notifications bubbling up:
  // onNotification (ScrollStart/Update/End/Metrics, OverscrollNotification, …).
  static notificationListener(child, onNotification) {
    return __flEl("NotificationListener", { child: child, onNotification: onNotification });
  }

  // Draggable / DragTarget — drag & drop.
  //   Draggable handlers: onDragStarted onDragUpdate onDragEnd onDraggableCanceled onDragCompleted
  //   DragTarget handlers: onWillAccept onAccept onAcceptWithDetails onLeave onMove
  static draggable(child, feedback, handlers) {
    let p = handlers == null ? {} : handlers;
    p.child = child;
    p.feedback = feedback;
    return __flEl("Draggable", p);
  }
  static dragTarget(builderChild, handlers) {
    let p = handlers == null ? {} : handlers;
    p.child = builderChild;
    return __flEl("DragTarget", p);
  }

  // Dismissible — swipe to dismiss: onDismissed confirmDismiss onResize onUpdate.
  static dismissible(key, child, handlers) {
    let p = handlers == null ? {} : handlers;
    p.dismissKey = key;
    p.child = child;
    return __flEl("Dismissible", p);
  }

  // RefreshIndicator — pull to refresh: onRefresh.
  static refreshIndicator(child, onRefresh) {
    return __flEl("RefreshIndicator", { child: child, onRefresh: onRefresh });
  }

  // PopScope — intercept back navigation: onPopInvoked (+ canPop).
  static popScope(child, onPopInvoked, canPop) {
    return __flEl("PopScope", { child: child, onPopInvoked: onPopInvoked, canPop: canPop });
  }

  // Form / fields — onChanged onSaved validator onFieldSubmitted onEditingComplete.
  static form(child, onChanged) {
    return __flEl("Form", { child: child, onChanged: onChanged });
  }

  // =========================================================================
  // Canvas / CustomPainter
  // =========================================================================

  // Paint a custom drawing at `size` = [w, h]. `painter(cv)` receives an
  // FLCanvas and issues drawing ops; they are recorded to a display list the
  // host replays onto the real Flutter Canvas. `opts` may add `child`,
  // `foreground: true` (draw over the child), `isComplex`, `willChange`.
  static customPaint(size, painter, opts) {
    let cv = new FLCanvas();
    if (painter != null) {
      painter(cv);
    }
    let p = opts == null ? {} : opts;
    p.size = size;
    if (p.foreground == true) {
      p.foregroundOps = cv._ops;
    } else {
      p.ops = cv._ops;
    }
    return __flEl("CustomPaint", p);
  }

  // Alias reading like dart:ui's PictureRecorder → Canvas flow.
  static canvas(size, painter, opts) {
    return FL.customPaint(size, painter, opts);
  }

  // A Paint descriptor. Recognized keys: color, blendMode, style('fill'|'stroke'),
  // strokeWidth, strokeCap('butt'|'round'|'square'), strokeJoin('miter'|'round'|
  // 'bevel'), strokeMiterLimit, isAntiAlias, shader (a gradient descriptor),
  // maskFilter ({style:'normal'|'solid'|'outer'|'inner', sigma}), blur (sigma
  // shortcut), colorFilter, filterQuality, invertColors.
  static paint(props) {
    return props == null ? {} : props;
  }

  // A fresh Path builder.
  static path() {
    return new FLPath();
  }

  // Geometry helpers.
  static ltwh(l, t, w, h) {
    return [l, t, l + w, t + h];
  }
  static rrect(rect, radius) {
    return { rect: rect, radius: radius };
  }

  // Shaders (a Paint's `shader`).
  static linearGradient(from, to, colors, stops, tileMode) {
    return { type: "linear", from: from, to: to, colors: colors, stops: stops, tileMode: tileMode };
  }
  static radialGradient(center, radius, colors, stops, tileMode) {
    return { type: "radial", center: center, radius: radius, colors: colors, stops: stops, tileMode: tileMode };
  }
  static sweepGradient(center, colors, stops, startAngle, endAngle) {
    return { type: "sweep", center: center, colors: colors, stops: stops, startAngle: startAngle, endAngle: endAngle };
  }

  // A Paragraph descriptor for cv.drawParagraph: { text, maxWidth, style,
  // align('left'|'center'|'right'|'justify') }.
  static paragraph(text, maxWidth, style, align) {
    return { text: text, maxWidth: maxWidth, style: style == null ? {} : style, align: align };
  }
}
// =============================================================================
// §3  Theme and widget kit — VUI
// =============================================================================

// =============================================================================
// ui.js — VUI: the Victor UI kit. A full widget toolkit in pure JavaScript,
// built on Godot Control nodes over the Elpian↔Godot bridge.
// =============================================================================
//
// Import it after godot.js (`import 'godot.js'; import 'ui.js';` — the import
// lines are markers the composer resolves; there is no module system). Every
// widget is a real, retained Godot Control node created reflectively through
// the bridge: VUI does not paint per frame — Godot renders the retained scene,
// and the guest only reacts to signals.
//
//   let app  = VUI.app({ responsive: true });
//   let page = VUI.column({
//     gap: 16, pad: 20,
//     children: [
//       VUI.heading("Hello"),
//       VUI.button("Tap me", { onTap: () => VUI.toast("hi!") }),
//     ],
//   });
//   app.push(page);
//
// ## The design system
//
// VUI follows Material Design 3 (the Flutter widget design language):
//
//   * COLOR — a full M3 scheme: primary/secondary/tertiary (+ their
//     containers and on- roles), error, five surface-container steps,
//     outline/outlineVariant, inverse roles and a scrim. Legacy token names
//     (bg, surface2, text, textDim, danger, …) remain as aliases so existing
//     guests keep working.
//   * TYPE — a dp-true scale (display 36 / headline 28 / title 22/16 /
//     body 16/14 / label 12) rendered with a real app font when one is
//     installed (VUI.installFonts / the `fonts` app option): body + medium +
//     bold weights with an emoji fallback, Flutter-style.
//   * SHAPE — radius steps 8/12/16/28/full; buttons are stadium-shaped, cards
//     round 16, dialogs 28, sheets round the top 28.
//   * ELEVATION — five shadow levels (VUI.styleBox `shadow: 1..5`).
//   * TOUCH — every control meets a 48dp minimum target.
//
// ## Responsive, mobile-first layout
//
// `VUI.app({ responsive: true })` sizes the UI in device-independent pixels:
// the window content-scale factor is derived from the real screen scale
// (devicePixelRatio on web, DPI/160 on Android), so `16` means 16dp on every
// device — exactly Flutter's logical-pixel model. `VUI.metrics()` reports the
// live logical viewport + Material breakpoints (compact < 600dp ≤ medium <
// 840dp ≤ expanded), and `VUI.onResize(cb)` fires on every window resize.
// The legacy fixed-design mode (`design: [w, h]`) still works for guests
// that want a scaled canvas instead.
//
// ## The pieces
//
//   theme      — themeDark / themeLight / use / theme (M3 design tokens)
//   fonts      — installFonts (body/emoji TTFs → app-wide Theme font)
//   root       — app (CanvasLayer + full-rect page + overlay, responsive dp
//                mode or fixed-design content-scale mode)
//   layout     — column, row, grid, scroll, margin, center, panel, spacer,
//                divider, expand
//   content    — text, heading, title, caption, icon, badge, chip, avatar,
//                card, stat, listTile
//   controls   — button, iconButton, fab, field, toggle, checkbox, slider,
//                progress, dropdown, textarea
//   structure  — appBar, tabs, bottomNav, dialog, sheet, toast, window,
//                webview (external URL in an in-app overlay / OS browser)
//   motion     — tween, fade, slideY (Godot Tweens over the bridge)
//
// ## Conventions
//
//   * Factories take one options map and return the widget's Godot node
//     (a GObj), or a HANDLE — a plain object whose `.node` is the GObj and
//     whose closures read/drive the widget (`toggle`, `tabs`, `progress`, …).
//     Anywhere a child is accepted, both shapes work.
//   * Widget state lives in per-widget state OBJECTS mutated in place (the
//     front-end's closures capture locals by value, so a reassigned local
//     would go stale — a mutated object never does).
//   * There is no first-class null in the subset: an absent option reads as 0
//     (falsy), and `x ?? d` also replaces an explicit 0. Options that must
//     distinguish 0 (slider minimums, tab index 0, …) are therefore read with
//     `__vuiNum(v, d)` which only defaults a true absence… of which the VM has
//     one representation — so pass such values explicitly when they matter.
//   * Colors are Color(r, g, b, a) floats (hex literals are not in the
//     subset).
//
// Everything below is ordinary Elpian-JS: it compiles with js2elpian and runs
// on the VM with no privileged access — the kit is user-space code, the same
// seam any guest program uses. Read it as living documentation of the bridge.

// ---------------------------------------------------------------------------
// namespace + tiny helpers
// ---------------------------------------------------------------------------

var VUI = {};

// The active theme (set by VUI.use; defaults to the dark theme on first read).
var __vuiThemeState = { t: null };

// The app singleton created by VUI.app (root/overlay mount points, design
// size, toast/dialog bookkeeping, open-overlay count).
var __vuiApp = {
  layer: null,
  root: null,
  overlay: null,
  w: 412.0,
  h: 915.0,
  toast: null,
  overlays: 0,
};

// Live viewport metrics (kept fresh by the app root's resize hook).
var __vuiViewport = { w: 412.0, h: 915.0, scale: 1.0, cbs: [] };

// Installed app fonts: FontFile/FontVariation handles (null until
// VUI.installFonts runs; widgets fall back to the engine default font).
var __vuiFonts = { regular: null, medium: null, bold: null, emoji: null };

// Unwrap a widget (GObj or handle) to its GObj node.
function __vuiNode(x) {
  if (x == null) {
    return null;
  }
  if (__isType(x, "GObj")) {
    return x;
  }
  if (__isType(x, "map")) {
    if (x["node"] != null) {
      return x["node"];
    }
  }
  if (x.node != null) {
    return x.node;
  }
  return x;
}

// Read a numeric option with a default. The VM has ONE representation for
// 0 / null / an absent member (see the conventions note), so an absent option
// and an explicit 0 are indistinguishable: both take the default. Pass -1 (or
// any negative) where an explicit zero is meant — sinks clamp negatives to 0.
function __vuiNum(v, d) {
  if (v == null) {
    return d;
  }
  if (__isType(v, "number")) {
    return v;
  }
  return d;
}

// Clamp a spacing/size value: negatives are the explicit-zero sentinel.
function __vuiPx(v) {
  if (v < 0) {
    return 0;
  }
  return v;
}

function __vuiAddAll(parent, children) {
  if (children == null) {
    return;
  }
  for (let i = 0; i < children.length; i++) {
    let c = __vuiNode(children[i]);
    if (c != null) {
      parent.call("add_child", [c]);
    }
  }
}

// Anchor a Control to its parent's full rect (manual anchors — no engine
// constant lookups on the hot construction path).
function __vuiFullRect(n) {
  n.set("anchor_left", GFloat(0.0));
  n.set("anchor_top", GFloat(0.0));
  n.set("anchor_right", GFloat(1.0));
  n.set("anchor_bottom", GFloat(1.0));
  n.set("offset_left", GFloat(0.0));
  n.set("offset_top", GFloat(0.0));
  n.set("offset_right", GFloat(0.0));
  n.set("offset_bottom", GFloat(0.0));
}

function __vuiMinSize(n, w, h) {
  n.set("custom_minimum_size", new Vector2(w, h));
}

// Control.SIZE_EXPAND_FILL == 3 (SIZE_FILL 1 | SIZE_EXPAND 2) — stable API.
function __vuiExpandH(n) {
  n.set("size_flags_horizontal", GInt(3));
}
function __vuiExpandV(n) {
  n.set("size_flags_vertical", GInt(3));
}

// Blend a Material state layer onto a base color: hover ≈ 8%, pressed ≈ 12%
// of the layer color composited over the base.
function __vuiLayer(base, layer, opacity) {
  return new Color(
    base.r + (layer.r - base.r) * opacity,
    base.g + (layer.g - base.g) * opacity,
    base.b + (layer.b - base.b) * opacity,
    base.a
  );
}

// ---------------------------------------------------------------------------
// theme — Material 3 design tokens
// ---------------------------------------------------------------------------
//
// The token object carries the full M3 color scheme plus shape / type /
// structure metrics, all in dp. Legacy names (bg, surface2/3, text, textDim,
// textFaint, primaryDim, accent, danger) are kept as aliases of the scheme
// roles so pre-M3 guests render correctly without changes.

VUI.themeDark = () => {
  let t = {
    name: "victor-dark",
    dark: true,
    // primary
    primary: new Color(0.651, 0.784, 1.0, 1.0), // #A6C8FF
    onPrimary: new Color(0.043, 0.188, 0.373, 1.0), // #0B305F
    primaryContainer: new Color(0.153, 0.278, 0.467, 1.0), // #274777
    onPrimaryContainer: new Color(0.839, 0.89, 1.0, 1.0), // #D6E3FF
    // secondary
    secondary: new Color(0.745, 0.776, 0.863, 1.0), // #BEC6DC
    onSecondary: new Color(0.157, 0.188, 0.247, 1.0), // #28303F
    secondaryContainer: new Color(0.243, 0.278, 0.349, 1.0), // #3E4759
    onSecondaryContainer: new Color(0.855, 0.886, 0.976, 1.0), // #DAE2F9
    // tertiary (teal)
    tertiary: new Color(0.525, 0.824, 0.804, 1.0),
    onTertiary: new Color(0.0, 0.216, 0.2, 1.0),
    tertiaryContainer: new Color(0.122, 0.306, 0.294, 1.0),
    onTertiaryContainer: new Color(0.635, 0.949, 0.925, 1.0),
    // error
    error: new Color(1.0, 0.706, 0.671, 1.0), // #FFB4AB
    onError: new Color(0.412, 0.0, 0.02, 1.0), // #690005
    errorContainer: new Color(0.576, 0.0, 0.039, 1.0), // #93000A
    onErrorContainer: new Color(1.0, 0.855, 0.839, 1.0), // #FFDAD6
    // surfaces
    surface: new Color(0.063, 0.078, 0.094, 1.0), // #101418
    surfaceBright: new Color(0.212, 0.227, 0.243, 1.0),
    surfaceContainerLowest: new Color(0.043, 0.059, 0.071, 1.0),
    surfaceContainerLow: new Color(0.094, 0.11, 0.125, 1.0), // #181C20
    surfaceContainer: new Color(0.11, 0.125, 0.141, 1.0), // #1C2024
    surfaceContainerHigh: new Color(0.149, 0.165, 0.18, 1.0), // #262A2E
    surfaceContainerHighest: new Color(0.192, 0.208, 0.224, 1.0), // #313539
    onSurface: new Color(0.882, 0.886, 0.91, 1.0), // #E1E2E8
    onSurfaceVariant: new Color(0.765, 0.776, 0.812, 1.0), // #C3C6CF
    outline: new Color(0.553, 0.569, 0.6, 1.0), // #8D9199
    outlineVariant: new Color(0.263, 0.278, 0.306, 1.0), // #43474E
    inverseSurface: new Color(0.882, 0.886, 0.91, 1.0),
    inverseOnSurface: new Color(0.18, 0.192, 0.208, 1.0),
    inversePrimary: new Color(0.251, 0.373, 0.565, 1.0),
    scrim: new Color(0.0, 0.0, 0.0, 0.45),
    // extended status roles
    success: new Color(0.42, 0.85, 0.56, 1.0),
    warning: new Color(1.0, 0.72, 0.35, 1.0),
    info: new Color(0.49, 0.75, 1.0, 1.0),
    // shape
    radiusXS: 4,
    radiusS: 8,
    radiusM: 12,
    radiusL: 16,
    radiusXL: 28,
    radiusFull: 999,
    space: 4.0,
    // type scale (dp)
    fontXS: 12,
    fontS: 14,
    fontM: 16,
    fontL: 22,
    fontXL: 28,
    fontXXL: 36,
    // structure (dp)
    barHeight: 64.0,
    navHeight: 80.0,
    controlHeight: 48.0,
    fieldHeight: 56.0,
    minTouch: 48.0,
  };
  return __vuiThemeAliases(t);
};

VUI.themeLight = () => {
  let t = VUI.themeDark();
  t.name = "victor-light";
  t.dark = false;
  t.primary = new Color(0.251, 0.373, 0.565, 1.0); // #405F90
  t.onPrimary = new Color(1.0, 1.0, 1.0, 1.0);
  t.primaryContainer = new Color(0.839, 0.89, 1.0, 1.0); // #D6E3FF
  t.onPrimaryContainer = new Color(0.0, 0.106, 0.243, 1.0);
  t.secondary = new Color(0.337, 0.369, 0.443, 1.0);
  t.onSecondary = new Color(1.0, 1.0, 1.0, 1.0);
  t.secondaryContainer = new Color(0.855, 0.886, 0.976, 1.0);
  t.onSecondaryContainer = new Color(0.075, 0.11, 0.169, 1.0);
  t.tertiary = new Color(0.161, 0.42, 0.408, 1.0);
  t.onTertiary = new Color(1.0, 1.0, 1.0, 1.0);
  t.tertiaryContainer = new Color(0.733, 0.925, 0.906, 1.0);
  t.onTertiaryContainer = new Color(0.0, 0.125, 0.114, 1.0);
  t.error = new Color(0.729, 0.102, 0.102, 1.0); // #BA1A1A
  t.onError = new Color(1.0, 1.0, 1.0, 1.0);
  t.errorContainer = new Color(1.0, 0.855, 0.839, 1.0);
  t.onErrorContainer = new Color(0.255, 0.0, 0.008, 1.0);
  t.surface = new Color(0.976, 0.976, 1.0, 1.0); // #F9F9FF
  t.surfaceBright = new Color(0.976, 0.976, 1.0, 1.0);
  t.surfaceContainerLowest = new Color(1.0, 1.0, 1.0, 1.0);
  t.surfaceContainerLow = new Color(0.953, 0.953, 0.98, 1.0);
  t.surfaceContainer = new Color(0.929, 0.929, 0.957, 1.0);
  t.surfaceContainerHigh = new Color(0.906, 0.91, 0.933, 1.0);
  t.surfaceContainerHighest = new Color(0.882, 0.886, 0.91, 1.0);
  t.onSurface = new Color(0.098, 0.11, 0.125, 1.0); // #191C20
  t.onSurfaceVariant = new Color(0.263, 0.278, 0.306, 1.0);
  t.outline = new Color(0.451, 0.467, 0.498, 1.0);
  t.outlineVariant = new Color(0.765, 0.776, 0.812, 1.0);
  t.inverseSurface = new Color(0.18, 0.192, 0.208, 1.0);
  t.inverseOnSurface = new Color(0.941, 0.941, 0.969, 1.0);
  t.inversePrimary = new Color(0.651, 0.784, 1.0, 1.0);
  t.scrim = new Color(0.0, 0.0, 0.0, 0.4);
  t.success = new Color(0.11, 0.53, 0.25, 1.0);
  t.warning = new Color(0.62, 0.42, 0.0, 1.0);
  t.info = new Color(0.13, 0.42, 0.75, 1.0);
  return __vuiThemeAliases(t);
};

// Refresh the legacy alias tokens from the scheme roles. Call after mutating
// scheme roles in place (a re-skin) so pre-M3 guests keep matching colors.
function __vuiThemeAliases(t) {
  t.bg = t.surface;
  t.surface2 = t.surfaceContainerHigh;
  t.surface3 = t.surfaceContainerHighest;
  t.text = t.onSurface;
  t.textDim = t.onSurfaceVariant;
  t.textFaint = t.outline;
  t.primaryDim = t.primary.withAlpha(0.14);
  t.accent = t.tertiary;
  t.danger = t.error;
  return t;
}
VUI.themeAliases = (t) => {
  return __vuiThemeAliases(t);
};

// Install a theme (call before building widgets; existing nodes keep the
// styles they were built with — the kit is retained, not reactive).
VUI.use = (t) => {
  __vuiThemeState.t = t;
  return t;
};

// The active theme (auto-installs the dark theme on first use).
VUI.theme = () => {
  if (__vuiThemeState.t == null) {
    __vuiThemeState.t = VUI.themeDark();
  }
  return __vuiThemeState.t;
};

// ---------------------------------------------------------------------------
// fonts — a real app typeface (Flutter-style), loaded at runtime
// ---------------------------------------------------------------------------
//
// VUI.installFonts({ body: "res://…/Roboto.ttf", emoji: "res://…/Emoji.ttf" })
// loads TTF/OTF fonts over the bridge, builds regular / medium / bold
// variations (real weight axes when the font is variable, synthetic emphasis
// otherwise), chains the emoji font as a fallback so emoji glyphs render
// everywhere, and installs the result as the app-wide Theme default font.
// Idempotent; safe to call before VUI.app.

// The OpenType `wght` axis tag: ('w'<<24)|('g'<<16)|('h'<<8)|('t').
var __VUI_WGHT_TAG = 2003265652;

function __vuiFontVariation(base, weight, embolden) {
  let v = GD.create("FontVariation");
  v.set("base_font", base);
  let axes = new GDict();
  axes.put(GInt(__VUI_WGHT_TAG), GInt(weight));
  v.set("variation_opentype", axes);
  if (embolden > 0.0) {
    // A touch of synthetic emphasis so static (non-variable) fonts still get
    // a visible weight step.
    v.set("variation_embolden", GFloat(embolden));
  }
  return v;
}

// Load one TTF/OTF into a FontFile, or null when it can't be read. Exported
// packs carry imported fonts only as res://.godot/imported/*.fontdata — the
// raw file is stripped even when the export preset's include filter matches
// it — so res:// paths must go through the import pipeline (GD.load, which
// follows the .import remap). Raw-file loading remains the fallback for
// loose files (user:// downloads, editor runs, packs with unimported fonts).
function __vuiLoadFontFile(path) {
  let p = "" + path;
  if (p.startsWith("res://")) {
    let r = GD.load(p);
    let cls = r.call("get_class");
    if (!GD.isError(cls) && cls == "FontFile") {
      return r;
    }
  }
  let f = GD.create("FontFile");
  let err = f.call("load_dynamic_font", [p]);
  if (GD.isError(err) || err != 0) {
    return null;
  }
  return f;
}

VUI.installFonts = (o) => {
  o = o ?? {};
  if (__vuiFonts.regular != null) {
    return __vuiFonts;
  }
  if (o.body == null) {
    return __vuiFonts;
  }
  let body = __vuiLoadFontFile(o.body);
  if (body == null) {
    return __vuiFonts;
  }
  body.set("antialiasing", GInt(1)); // grayscale AA
  body.set("hinting", GInt(1)); // light hinting
  body.set("subpixel_positioning", GInt(1));
  if (o.emoji != null) {
    let emoji = __vuiLoadFontFile(o.emoji);
    if (emoji != null) {
      __vuiFonts.emoji = emoji;
      body.set("fallbacks", [emoji]);
    }
  }
  __vuiFonts.regular = body;
  __vuiFonts.medium = __vuiFontVariation(body, 500, 0.0);
  __vuiFonts.bold = __vuiFontVariation(body, 700, 0.12);

  // App-wide install: the root window Theme's default font.
  let th = GD.create("Theme");
  th.set("default_font", body);
  th.set("default_font_size", GInt(VUI.theme().fontM));
  let win = GD.tree().call("get_root");
  if (win != null && !GD.isError(win)) {
    win.set("theme", th);
  }
  return __vuiFonts;
};

// The installed fonts (regular/medium/bold/emoji — entries are null until
// VUI.installFonts has run).
VUI.fonts = () => {
  return __vuiFonts;
};

// Apply a font weight to a themed Control ("medium" | "bold"); no-op when no
// app font is installed or the weight is absent.
function __vuiFontFor(weight) {
  if (weight == "bold") {
    return __vuiFonts.bold;
  }
  if (weight == "medium") {
    return __vuiFonts.medium;
  }
  return null;
}

function __vuiApplyWeight(n, weight) {
  // Weight variant when asked; otherwise the regular app font. Applying the
  // font explicitly on every text node (rather than relying on the root
  // Theme) keeps the typeface + emoji fallback intact on every platform.
  let f = __vuiFontFor(weight);
  if (f == null) {
    f = __vuiFonts.regular;
  }
  if (f != null) {
    n.set("theme_override_fonts/font", f);
  }
}

// ---------------------------------------------------------------------------
// style plumbing
// ---------------------------------------------------------------------------

// Material elevation → StyleBoxFlat shadow parameters (size, alpha, y-offset).
function __vuiElevation(level) {
  if (level <= 0) {
    return { size: 0, alpha: 0.0, y: 0.0 };
  }
  if (level == 1) {
    return { size: 6, alpha: 0.2, y: 2.0 };
  }
  if (level == 2) {
    return { size: 10, alpha: 0.22, y: 3.0 };
  }
  if (level == 3) {
    return { size: 14, alpha: 0.24, y: 4.0 };
  }
  if (level == 4) {
    return { size: 18, alpha: 0.26, y: 6.0 };
  }
  return { size: 24, alpha: 0.3, y: 8.0 };
}

// ---- optional texture skin (e.g. the Casual UI / Kenney UI packs) ----------
// A guest installs a skin with VUI.useTextures({...}); thereafter buttons,
// fields and skinned panels render with the pack's nine-patch textures. Every
// path is looked up with GD.load and silently ignored if missing, so the kit
// degrades to its flat Material look when the assets are absent.
var __vuiSkin = null;

// skin = {
//   button: { normal, hover, pressed, margin, padX, padY },
//   panel:  { texture, margin }, card: { texture, margin },
//   field:  { normal, focus, margin },
// }  — each *value is a res:// path to a nine-patch PNG.
VUI.useTextures = (skin) => {
  __vuiSkin = skin;
};
VUI.skin = () => {
  return __vuiSkin;
};

// Build a StyleBoxTexture from a texture path (returns null if it can't load).
function __vuiSkinBox(path, o) {
  o = o ?? {};
  if (path == null) {
    return null;
  }
  let tex = GD.load(path);
  if (tex == null || GD.isError(tex)) {
    return null;
  }
  let sb = GD.create("StyleBoxTexture");
  sb.set("texture", tex);
  let m = __vuiNum(o.margin, 12);
  sb.set("texture_margin_left", GFloat(__vuiNum(o.marginL, m)));
  sb.set("texture_margin_top", GFloat(__vuiNum(o.marginT, m)));
  sb.set("texture_margin_right", GFloat(__vuiNum(o.marginR, m)));
  sb.set("texture_margin_bottom", GFloat(__vuiNum(o.marginB, m)));
  let padX = __vuiNum(o.padX, -1);
  let padY = __vuiNum(o.padY, -1);
  if (padX >= 0) {
    sb.set("content_margin_left", GFloat(padX));
    sb.set("content_margin_right", GFloat(padX));
  }
  if (padY >= 0) {
    sb.set("content_margin_top", GFloat(padY));
    sb.set("content_margin_bottom", GFloat(padY));
  }
  if (o.modulate != null) {
    sb.set("modulate_color", o.modulate);
  }
  return sb;
}

// A StyleBoxFlat from options: { bg, radius, radiusTL/TR/BL/BR, border,
// borderColor, borderB (bottom-only width), pad, padX, padY, padL/T/R/B,
// shadow (elevation level 1..5 — or raw px when > 5), shadowColor, shadowY }.
VUI.styleBox = (o) => {
  o = o ?? {};
  // Skinned panels/cards: use the pack nine-patch, tinted by the bg colour.
  if (o.skin != null && __vuiSkin != null && __vuiSkin[o.skin] != null) {
    let sk = __vuiSkin[o.skin];
    let box = __vuiSkinBox(sk.texture, {
      margin: sk.margin,
      padX: __vuiNum(o.padX, __vuiNum(o.pad, -1)),
      padY: __vuiNum(o.padY, __vuiNum(o.pad, -1)),
      modulate: o.bg,
    });
    if (box != null) {
      return box;
    }
  }
  let sb = GD.create("StyleBoxFlat");
  if (o.bg != null) {
    sb.set("bg_color", o.bg);
  } else {
    sb.set("bg_color", new Color(0.0, 0.0, 0.0, 0.0));
  }
  let r = __vuiNum(o.radius, -1);
  if (r >= 0) {
    sb.set("corner_radius_top_left", GInt(__vuiNum(o.radiusTL, r)));
    sb.set("corner_radius_top_right", GInt(__vuiNum(o.radiusTR, r)));
    sb.set("corner_radius_bottom_left", GInt(__vuiNum(o.radiusBL, r)));
    sb.set("corner_radius_bottom_right", GInt(__vuiNum(o.radiusBR, r)));
    // Round pills stay smooth at any size.
    sb.set("corner_detail", GInt(12));
  }
  let bw = __vuiNum(o.border, 0);
  if (bw > 0) {
    sb.set("border_width_left", GInt(bw));
    sb.set("border_width_top", GInt(bw));
    sb.set("border_width_right", GInt(bw));
    sb.set("border_width_bottom", GInt(bw));
  }
  let bb = __vuiNum(o.borderB, 0);
  if (bb > 0) {
    sb.set("border_width_bottom", GInt(bb));
  }
  if ((bw > 0 || bb > 0) && o.borderColor != null) {
    sb.set("border_color", o.borderColor);
  }
  let padX = __vuiNum(o.padX, __vuiNum(o.pad, -1));
  let padY = __vuiNum(o.padY, __vuiNum(o.pad, -1));
  if (padX >= 0) {
    sb.set("content_margin_left", GFloat(__vuiNum(o.padL, padX)));
    sb.set("content_margin_right", GFloat(__vuiNum(o.padR, padX)));
  }
  if (padY >= 0) {
    sb.set("content_margin_top", GFloat(__vuiNum(o.padT, padY)));
    sb.set("content_margin_bottom", GFloat(__vuiNum(o.padB, padY)));
  }
  let sh = __vuiNum(o.shadow, 0);
  if (sh > 0) {
    let e = __vuiElevation(sh);
    if (sh > 5) {
      // Raw pixel size for callers predating elevation levels.
      e = { size: sh, alpha: 0.26, y: sh * 0.4 };
    }
    sb.set("shadow_size", GInt(e.size));
    sb.set("shadow_color", o.shadowColor ?? new Color(0.0, 0.0, 0.0, e.alpha));
    sb.set("shadow_offset", new Vector2(0.0, __vuiNum(o.shadowY, e.y)));
  }
  sb.set("anti_aliasing", true);
  return sb;
};

// A StyleBoxEmpty (fully transparent, no margins) — for ghost buttons and
// invisible hit areas.
VUI.styleEmpty = () => {
  return GD.create("StyleBoxEmpty");
};

// A crisp filled circle as a texture, generated on the fly (radial
// GradientTexture2D — no image assets anywhere in the kit). Used for slider
// grabbers and anywhere a round sprite is handy.
VUI.circleTexture = (size, color) => {
  let g = GD.create("Gradient");
  g.set("offsets", Packed.f32([0.0, 0.78, 0.86, 1.0]));
  g.set(
    "colors",
    Packed.colors([
      color.r, color.g, color.b, color.a,
      color.r, color.g, color.b, color.a,
      color.r, color.g, color.b, 0.0,
      color.r, color.g, color.b, 0.0,
    ])
  );
  let t = GD.create("GradientTexture2D");
  t.set("gradient", g);
  t.set("fill", GInt(1)); // GradientTexture2D.FILL_RADIAL
  t.set("fill_from", new Vector2(0.5, 0.5));
  t.set("fill_to", new Vector2(0.5, 1.0));
  t.set("width", GInt(size));
  t.set("height", GInt(size));
  return t;
};

// ---------------------------------------------------------------------------
// motion — Godot Tweens over the bridge
// ---------------------------------------------------------------------------

// A fresh Tween bound to a node (kills nothing; chain tween_property calls on
// the returned GObj).
VUI.tween = (node) => {
  return node.call("create_tween");
};

// Tween one property: VUI.animate(node, 'position', Vector2(...), 180).
VUI.animate = (node, prop, to, ms) => {
  let tw = node.call("create_tween");
  if (tw == null || GD.isError(tw)) {
    return null;
  }
  tw.call("set_trans", [GInt(3)]); // Tween.TRANS_QUART — snappy
  tw.call("set_ease", [GInt(2)]); // Tween.EASE_IN_OUT
  tw.call("tween_property", [node, new NodePath(prop), to, GFloat(ms / 1000.0)]);
  return tw;
};

// Fade a Control's alpha to `a` over ms.
VUI.fade = (node, a, ms) => {
  return VUI.animate(node, "modulate:a", GFloat(a), ms);
};

// ---------------------------------------------------------------------------
// the app root — a full-screen 2D page inside any (2D or 3D) scene
// ---------------------------------------------------------------------------
//
// VUI.app creates a CanvasLayer on the hosting node: CanvasLayers composite
// over the viewport, so the 2D UI covers the screen even when the scene root
// is a Node3D world — the 3D environment keeps existing (and can render, or
// not) underneath the page. Options:
//
//   responsive: true — dp mode (the default when no design size is given):
//             the content scale factor tracks the device pixel ratio, so all
//             kit dimensions are device-independent pixels and the layout
//             REFLOWS on resize instead of scaling. Flutter's logical pixels.
//   design:   [w, h] — legacy fixed-design mode: the window content-scales so
//             coordinates in this space fit any screen.
//   portrait: true — lock the screen to portrait: on handheld devices via
//             DisplayServer.screen_set_orientation, on desktop by sizing the
//             window itself to a portrait shape.
//   bg:       page background color (theme bg when omitted; pass false to
//             leave the world visible behind the UI).
//   fonts:    { body, emoji } — TTF paths handed to VUI.installFonts.
//
// Returns the app handle: { layer, root, overlay, w, h, push(widget) }.

// Compute the device scale factor (dp mode): the display server's screen
// scale (devicePixelRatio on web) with a DPI/160 fallback for platforms that
// report scale 1 with a real DPI (Android), clamped to [1, 4].
function __vuiDeviceScale() {
  let ds = GD.displayServer();
  let s = ds.call("screen_get_scale", []);
  let scale = 1.0;
  if (!GD.isError(s) && __isType(s, "number") && s > 0.0) {
    scale = s;
  }
  if (scale <= 1.01) {
    let dpi = ds.call("screen_get_dpi", []);
    if (!GD.isError(dpi) && __isType(dpi, "number") && dpi >= 180) {
      scale = dpi / 160.0;
    }
  }
  if (scale < 1.0) {
    scale = 1.0;
  }
  if (scale > 4.0) {
    scale = 4.0;
  }
  return scale;
}

function __vuiRefreshMetrics(win) {
  let sz = win.get("size");
  if (sz == null || GD.isError(sz)) {
    return;
  }
  let sc = __vuiViewport.scale;
  __vuiViewport.w = sz.x / sc;
  __vuiViewport.h = sz.y / sc;
  __vuiApp.w = __vuiViewport.w;
  __vuiApp.h = __vuiViewport.h;
}

// The live logical viewport: { w, h, scale, compact, medium, expanded,
// portrait } — Material window size classes on the logical width.
VUI.metrics = () => {
  let w = __vuiViewport.w;
  let h = __vuiViewport.h;
  return {
    w: w,
    h: h,
    scale: __vuiViewport.scale,
    compact: w < 600.0,
    medium: w >= 600.0 && w < 840.0,
    expanded: w >= 840.0,
    portrait: h >= w,
  };
};

// Subscribe to viewport changes; returns an unsubscribe closure.
VUI.onResize = (cb) => {
  __vuiViewport.cbs.push(cb);
  return () => {
    let out = [];
    for (let i = 0; i < __vuiViewport.cbs.length; i++) {
      if (__vuiViewport.cbs[i] != cb) {
        out.push(__vuiViewport.cbs[i]);
      }
    }
    __vuiViewport.cbs = out;
  };
};

function __vuiFireResize() {
  for (let i = 0; i < __vuiViewport.cbs.length; i++) {
    __vuiViewport.cbs[i](VUI.metrics());
  }
}

VUI.app = (o) => {
  o = o ?? {};
  let t = VUI.theme();
  if (o.fonts != null) {
    VUI.installFonts(o.fonts);
  }

  let win = GD.tree().call("get_root");
  let responsive = o.responsive == true || o.design == null;

  if (responsive) {
    // dp mode: scale factor = device pixel ratio; layout reflows on resize.
    let scale = __vuiDeviceScale();
    __vuiViewport.scale = scale;
    if (win != null && !GD.isError(win)) {
      win.set("content_scale_size", new Vector2i(0, 0));
      win.set("content_scale_mode", GD.constant("Window.CONTENT_SCALE_MODE_CANVAS_ITEMS"));
      win.set("content_scale_aspect", GD.constant("Window.CONTENT_SCALE_ASPECT_EXPAND"));
      win.set("content_scale_factor", GFloat(scale));
      __vuiRefreshMetrics(win);
      win.connect("size_changed", (a) => {
        __vuiRefreshMetrics(win);
        __vuiFireResize();
      });
    }
  } else {
    let dw = o.design[0];
    let dh = o.design[1];
    __vuiApp.w = dw;
    __vuiApp.h = dh;
    __vuiViewport.w = dw;
    __vuiViewport.h = dh;
    if (win != null && !GD.isError(win)) {
      win.set("content_scale_size", new Vector2i(dw, dh));
      win.set("content_scale_mode", GD.constant("Window.CONTENT_SCALE_MODE_CANVAS_ITEMS"));
      win.set("content_scale_aspect", GD.constant("Window.CONTENT_SCALE_ASPECT_EXPAND"));
    }
  }

  if (o.portrait == true) {
    let os = GD.os();
    let mobile = os.call("has_feature", ["mobile"]);
    if (mobile == true) {
      GD.displayServer().call("screen_set_orientation", [
        GD.constant("DisplayServer.SCREEN_PORTRAIT"),
      ]);
    } else if (o.design != null) {
      // Desktop preview: make the window itself portrait at the design size.
      GD.displayServer().call("window_set_size", [new Vector2i(o.design[0], o.design[1])]);
    }
  }

  let layer = GD.create("CanvasLayer");
  GD.mount(layer);

  // The page root: a full-rect Control carrying the background. PASS-through
  // for input: sandboxed game VMs render on layers below the app shell, and
  // taps that hit no actual widget must reach them — every interactive VUI
  // control STOPs for itself.
  let root = GD.create("Control");
  root.set("name", "VuiRoot");
  root.set("mouse_filter", GInt(2)); // MOUSE_FILTER_IGNORE
  __vuiFullRect(root);
  layer.call("add_child", [root]);
  if (o.bg != false) {
    let bgPanel = GD.create("Panel");
    __vuiFullRect(bgPanel);
    bgPanel.set("theme_override_styles/panel", VUI.styleBox({ bg: o.bg ?? t.bg }));
    bgPanel.set("mouse_filter", GInt(2)); // MOUSE_FILTER_IGNORE
    root.call("add_child", [bgPanel]);
  }

  // The overlay: dialogs, sheets and toasts mount here, always on top.
  let overlay = GD.create("Control");
  overlay.set("name", "VuiOverlay");
  __vuiFullRect(overlay);
  overlay.set("mouse_filter", GInt(2)); // ignore until something is shown
  layer.call("add_child", [overlay]);

  __vuiApp.layer = layer;
  __vuiApp.root = root;
  __vuiApp.overlay = overlay;

  return {
    layer: layer,
    node: root,
    root: root,
    overlay: overlay,
    w: __vuiApp.w,
    h: __vuiApp.h,
    // Mount a full-screen page widget.
    push: (widget) => {
      let n = __vuiNode(widget);
      __vuiFullRect(n);
      __vuiApp.root.call("add_child", [n]);
      return n;
    },
  };
};

// ---------------------------------------------------------------------------
// layout
// ---------------------------------------------------------------------------

function __vuiWrapPad(inner, pad) {
  if (pad == null) {
    return inner;
  }
  let m = GD.create("MarginContainer");
  let p = __vuiPx(__vuiNum(pad, 0));
  m.set("theme_override_constants/margin_left", GInt(p));
  m.set("theme_override_constants/margin_top", GInt(p));
  m.set("theme_override_constants/margin_right", GInt(p));
  m.set("theme_override_constants/margin_bottom", GInt(p));
  m.call("add_child", [inner]);
  return m;
}

// Vertical stack: { gap, pad, children, expand }.
VUI.column = (o) => {
  o = o ?? {};
  let box = GD.create("VBoxContainer");
  box.set("theme_override_constants/separation", GInt(__vuiPx(__vuiNum(o.gap, 12))));
  __vuiAddAll(box, o.children);
  if (o.expand == true) {
    __vuiExpandH(box);
    __vuiExpandV(box);
  }
  return __vuiWrapPad(box, o.pad);
};

// Horizontal stack: { gap, pad, children, expand }.
VUI.row = (o) => {
  o = o ?? {};
  let box = GD.create("HBoxContainer");
  box.set("theme_override_constants/separation", GInt(__vuiPx(__vuiNum(o.gap, 12))));
  __vuiAddAll(box, o.children);
  if (o.expand == true) {
    __vuiExpandH(box);
  }
  return __vuiWrapPad(box, o.pad);
};

// Grid: { cols, gap, children }.
VUI.grid = (o) => {
  o = o ?? {};
  let g = GD.create("GridContainer");
  g.set("columns", GInt(__vuiNum(o.cols, 2)));
  let gap = __vuiPx(__vuiNum(o.gap, 12));
  g.set("theme_override_constants/h_separation", GInt(gap));
  g.set("theme_override_constants/v_separation", GInt(gap));
  __vuiAddAll(g, o.children);
  return g;
};

// Style a ScrollContainer's bars as thin, subtle Material scrollbars.
VUI.scrollbarStyle = (sc) => {
  let t = VUI.theme();
  let names = ["get_h_scroll_bar", "get_v_scroll_bar"];
  for (let i = 0; i < names.length; i++) {
    let bar = sc.call(names[i]);
    if (bar == null || GD.isError(bar)) {
      continue;
    }
    bar.set("custom_minimum_size", new Vector2(4.0, 4.0));
    bar.set("theme_override_styles/scroll", VUI.styleBox({ bg: t.onSurface.withAlpha(0.06), radius: t.radiusFull }));
    bar.set("theme_override_styles/grabber", VUI.styleBox({ bg: t.outline.withAlpha(0.55), radius: t.radiusFull }));
    bar.set("theme_override_styles/grabber_highlight", VUI.styleBox({ bg: t.outline, radius: t.radiusFull }));
    bar.set("theme_override_styles/grabber_pressed", VUI.styleBox({ bg: t.primary, radius: t.radiusFull }));
  }
};

// Scrollable area: { child, horizontal }. The child expands to the scroll
// width so columns lay out naturally.
VUI.scroll = (o) => {
  o = o ?? {};
  let sc = GD.create("ScrollContainer");
  __vuiExpandH(sc);
  __vuiExpandV(sc);
  sc.set("horizontal_scroll_mode", GInt(o.horizontal == true ? 1 : 0));
  VUI.scrollbarStyle(sc);
  let c = __vuiNode(o.child);
  if (c != null) {
    __vuiExpandH(c);
    sc.call("add_child", [c]);
  }
  return sc;
};

// Uniform padding around one child: { pad, child }.
VUI.margin = (o) => {
  o = o ?? {};
  let c = __vuiNode(o.child);
  let m = __vuiWrapPad(c, __vuiNum(o.pad, 16));
  return m;
};

// Center one child both ways: { child }.
VUI.center = (o) => {
  o = o ?? {};
  let c = GD.create("CenterContainer");
  __vuiExpandH(c);
  __vuiExpandV(c);
  let n = __vuiNode(o.child);
  if (n != null) {
    c.call("add_child", [n]);
  }
  return c;
};

// A styled surface wrapping children: { bg, radius, border, borderColor, pad,
// gap, children, child, shadow }.
VUI.panel = (o) => {
  o = o ?? {};
  let t = VUI.theme();
  let p = GD.create("PanelContainer");
  p.set(
    "theme_override_styles/panel",
    VUI.styleBox({
      bg: o.bg ?? t.surfaceContainerLow,
      radius: __vuiNum(o.radius, t.radiusL),
      border: __vuiNum(o.border, 0),
      borderColor: o.borderColor,
      pad: __vuiNum(o.pad, 16),
      shadow: __vuiNum(o.shadow, 0),
    })
  );
  if (o.child != null) {
    p.call("add_child", [__vuiNode(o.child)]);
  } else if (o.children != null) {
    let col = GD.create("VBoxContainer");
    col.set("theme_override_constants/separation", GInt(__vuiPx(__vuiNum(o.gap, 12))));
    __vuiAddAll(col, o.children);
    p.call("add_child", [col]);
  }
  return p;
};

// Flexible empty space (soaks up leftover room in a row/column).
VUI.spacer = () => {
  let s = GD.create("Control");
  __vuiExpandH(s);
  __vuiExpandV(s);
  s.set("mouse_filter", GInt(2));
  return s;
};

// A hairline separator: { vertical, inset }.
VUI.divider = (o) => {
  o = o ?? {};
  let t = VUI.theme();
  let d = GD.create("Panel");
  d.set("theme_override_styles/panel", VUI.styleBox({ bg: t.outlineVariant, radius: 1 }));
  if (o.vertical == true) {
    __vuiMinSize(d, 1.0, 8.0);
    __vuiExpandV(d);
  } else {
    __vuiMinSize(d, 8.0, 1.0);
    __vuiExpandH(d);
  }
  d.set("mouse_filter", GInt(2));
  return d;
};

// Mark a widget to expand-fill its parent container; returns it.
VUI.expand = (w) => {
  let n = __vuiNode(w);
  __vuiExpandH(n);
  __vuiExpandV(n);
  return w;
};

// Fixed-size box around nothing (a strut): { w, h }.
VUI.gap = (o) => {
  o = o ?? {};
  let s = GD.create("Control");
  __vuiMinSize(s, __vuiNum(o.w, 0.0), __vuiNum(o.h, 0.0));
  s.set("mouse_filter", GInt(2));
  return s;
};

// ---------------------------------------------------------------------------
// content
// ---------------------------------------------------------------------------

// A text label: (str, { size, color, dim, faint, weight: 'medium'|'bold',
// align: 'left|center|right', wrap, expand }).
VUI.text = (str, o) => {
  o = o ?? {};
  let t = VUI.theme();
  let l = GD.create("Label");
  l.set("text", "" + str);
  l.set("theme_override_font_sizes/font_size", GInt(__vuiNum(o.size, t.fontM)));
  let color = o.color;
  if (color == null) {
    color = t.onSurface;
    if (o.dim == true) {
      color = t.onSurfaceVariant;
    }
    if (o.faint == true) {
      color = t.outline;
    }
  }
  l.set("theme_override_colors/font_color", color);
  __vuiApplyWeight(l, o.weight);
  if (o.align == "center") {
    l.set("horizontal_alignment", GInt(1));
  } else if (o.align == "right") {
    l.set("horizontal_alignment", GInt(2));
  }
  if (o.wrap == true) {
    l.set("autowrap_mode", GInt(3)); // TextServer.AUTOWRAP_WORD_SMART
    __vuiExpandH(l);
  }
  if (o.expand == true) {
    __vuiExpandH(l);
  }
  return l;
};

// Headline (28dp, medium weight).
VUI.heading = (str, o) => {
  o = o ?? {};
  let t = VUI.theme();
  o.size = __vuiNum(o.size, t.fontXL);
  o.weight = o.weight ?? "medium";
  return VUI.text(str, o);
};

// Title (22dp, medium weight).
VUI.title = (str, o) => {
  o = o ?? {};
  let t = VUI.theme();
  o.size = __vuiNum(o.size, t.fontL);
  o.weight = o.weight ?? "medium";
  return VUI.text(str, o);
};

VUI.caption = (str, o) => {
  o = o ?? {};
  let t = VUI.theme();
  o.size = __vuiNum(o.size, t.fontXS);
  if (o.color == null) {
    o.dim = true;
  }
  return VUI.text(str, o);
};

// A unicode glyph as an icon: (glyph, { size, color }).
VUI.icon = (glyph, o) => {
  o = o ?? {};
  let t = VUI.theme();
  o.size = __vuiNum(o.size, t.fontL);
  o.align = o.align ?? "center";
  return VUI.text(glyph, o);
};

// A tiny status pill: (str, { color, textColor }).
VUI.badge = (str, o) => {
  o = o ?? {};
  let t = VUI.theme();
  let p = GD.create("PanelContainer");
  p.set(
    "theme_override_styles/panel",
    VUI.styleBox({ bg: o.color ?? t.primary, radius: t.radiusFull, padX: 10, padY: 2 })
  );
  p.call("add_child", [
    VUI.text(str, { size: 11, color: o.textColor ?? t.onPrimary, weight: "medium" }),
  ]);
  return p;
};

// A selectable Material chip: (str, { selected, glyph, onTap }). Returns a
// handle { node, setSelected(b), isSelected() }.
VUI.chip = (str, o) => {
  o = o ?? {};
  let t = VUI.theme();
  let st = { on: o.selected == true };
  let b = GD.create("Button");
  let label = "" + str;
  if (o.glyph != null) {
    label = o.glyph + " " + label;
  }
  b.set("text", label);
  b.set("theme_override_font_sizes/font_size", GInt(t.fontS));
  __vuiApplyWeight(b, "medium");
  b.set("focus_mode", GInt(0));
  __vuiMinSize(b, 0.0, 32.0);

  let offSb = VUI.styleBox({
    radius: t.radiusS, padX: 16, padY: 6,
    border: 1, borderColor: t.outline,
  });
  let offHover = VUI.styleBox({
    bg: __vuiLayer(t.surface, t.onSurfaceVariant, 0.08),
    radius: t.radiusS, padX: 16, padY: 6,
    border: 1, borderColor: t.outline,
  });
  let onSb = VUI.styleBox({ bg: t.secondaryContainer, radius: t.radiusS, padX: 16, padY: 6 });
  let onHover = VUI.styleBox({
    bg: __vuiLayer(t.secondaryContainer, t.onSecondaryContainer, 0.08),
    radius: t.radiusS, padX: 16, padY: 6,
  });
  let apply = () => {
    b.set("theme_override_styles/normal", st.on ? onSb : offSb);
    b.set("theme_override_styles/hover", st.on ? onHover : offHover);
    b.set("theme_override_styles/pressed", st.on ? onHover : offHover);
    b.set("theme_override_colors/font_color", st.on ? t.onSecondaryContainer : t.onSurfaceVariant);
    b.set("theme_override_colors/font_hover_color", st.on ? t.onSecondaryContainer : t.onSurface);
    b.set("theme_override_colors/font_pressed_color", st.on ? t.onSecondaryContainer : t.onSurface);
  };
  apply();
  b.connect("pressed", (a) => {
    st.on = !st.on;
    apply();
    if (o.onTap != null) {
      o.onTap(st.on);
    }
  });
  return {
    node: b,
    isSelected: () => st.on,
    setSelected: (v) => {
      st.on = v == true;
      apply();
    },
  };
};

// A circular initials avatar: (initials, { color, textColor, size }).
VUI.avatar = (initials, o) => {
  o = o ?? {};
  let t = VUI.theme();
  let d = __vuiNum(o.size, 40.0);
  let p = GD.create("PanelContainer");
  __vuiMinSize(p, d, d);
  p.set(
    "theme_override_styles/panel",
    VUI.styleBox({ bg: o.color ?? t.primaryContainer, radius: t.radiusFull })
  );
  let l = VUI.text(initials, {
    size: d * 0.4,
    color: o.textColor ?? t.onPrimaryContainer,
    align: "center",
    weight: "medium",
  });
  l.set("vertical_alignment", GInt(1)); // centered
  p.call("add_child", [l]);
  return p;
};

// An elevated content card (Material Card): { children, child, gap, pad,
// accent, variant: 'elevated'|'filled'|'outlined' }.
VUI.card = (o) => {
  o = o ?? {};
  let t = VUI.theme();
  let variant = o.variant ?? "elevated";
  if (variant == "filled") {
    o.bg = o.bg ?? t.surfaceContainerHighest;
    o.shadow = __vuiNum(o.shadow, 0);
  } else if (variant == "outlined") {
    o.bg = o.bg ?? t.surface;
    o.border = __vuiNum(o.border, 1);
    o.borderColor = o.borderColor ?? t.outlineVariant;
    o.shadow = __vuiNum(o.shadow, 0);
  } else {
    o.bg = o.bg ?? t.surfaceContainerLow;
    o.shadow = __vuiNum(o.shadow, 1);
  }
  o.radius = __vuiNum(o.radius, t.radiusM);
  o.pad = __vuiNum(o.pad, 16);
  if (o.accent != null) {
    o.border = 1;
    o.borderColor = o.accent;
  }
  return VUI.panel(o);
};

// A dashboard stat tile: { label, value, glyph, accent }. Returns a handle
// { node, setValue(v) }.
VUI.stat = (o) => {
  o = o ?? {};
  let t = VUI.theme();
  let accent = o.accent ?? t.primary;
  let valueLabel = VUI.text("" + (o.value ?? ""), { size: 24, color: t.onSurface, weight: "medium" });
  let children = [];
  if (o.glyph != null) {
    children.push(
      VUI.row({
        gap: 8,
        children: [
          VUI.icon(o.glyph, { size: t.fontM, color: accent }),
          VUI.caption(o.label ?? ""),
        ],
      })
    );
  } else {
    children.push(VUI.caption(o.label ?? ""));
  }
  children.push(valueLabel);
  let card = VUI.panel({
    bg: t.surfaceContainerLow,
    radius: t.radiusM,
    pad: 16,
    gap: 4,
    shadow: 1,
    children: children,
  });
  __vuiExpandH(card);
  return {
    node: card,
    setValue: (v) => {
      valueLabel.set("text", "" + v);
    },
  };
};

// A tappable Material list tile: { leading (glyph), leadingColor, title,
// subtitle, trailing (string or widget), onTap }.
VUI.listTile = (o) => {
  o = o ?? {};
  let t = VUI.theme();
  let b = GD.create("Button");
  b.set("focus_mode", GInt(0));
  let normal = VUI.styleBox({ bg: t.surfaceContainerLow, radius: t.radiusM });
  let hover = VUI.styleBox({ bg: __vuiLayer(t.surfaceContainerLow, t.onSurface, 0.08), radius: t.radiusM });
  let pressed = VUI.styleBox({ bg: __vuiLayer(t.surfaceContainerLow, t.onSurface, 0.12), radius: t.radiusM });
  b.set("theme_override_styles/normal", normal);
  b.set("theme_override_styles/hover", hover);
  b.set("theme_override_styles/pressed", pressed);
  __vuiMinSize(b, 0.0, o.subtitle != null ? 72.0 : 56.0);
  __vuiExpandH(b);

  let content = GD.create("MarginContainer");
  __vuiFullRect(content);
  content.set("theme_override_constants/margin_left", GInt(16));
  content.set("theme_override_constants/margin_right", GInt(16));
  content.set("theme_override_constants/margin_top", GInt(8));
  content.set("theme_override_constants/margin_bottom", GInt(8));
  content.set("mouse_filter", GInt(2)); // let the button take the clicks

  let items = [];
  if (o.leading != null) {
    let iconWrap = GD.create("PanelContainer");
    __vuiMinSize(iconWrap, 40.0, 40.0);
    iconWrap.set(
      "theme_override_styles/panel",
      VUI.styleBox({ bg: t.surfaceContainerHigh, radius: t.radiusFull })
    );
    let ic = VUI.icon(o.leading, { size: t.fontM, color: o.leadingColor ?? t.primary });
    ic.set("vertical_alignment", GInt(1));
    iconWrap.call("add_child", [ic]);
    let iconCenter = GD.create("CenterContainer");
    iconCenter.set("mouse_filter", GInt(2));
    iconCenter.call("add_child", [iconWrap]);
    items.push(iconCenter);
  }
  let mid = [];
  mid.push(VUI.text(o.title ?? "", { size: t.fontM }));
  if (o.subtitle != null) {
    mid.push(VUI.text(o.subtitle, { size: t.fontS, dim: true }));
  }
  let midCol = VUI.column({ gap: 2, children: mid });
  __vuiExpandH(midCol);
  let midCenter = GD.create("VBoxContainer");
  midCenter.set("alignment", GInt(1));
  midCenter.set("mouse_filter", GInt(2));
  midCenter.call("add_child", [__vuiNode(midCol)]);
  __vuiExpandH(midCenter);
  items.push(midCenter);
  if (o.trailing != null) {
    if (__isType(o.trailing, "string")) {
      let tr = VUI.text(o.trailing, { size: t.fontXS, faint: true });
      tr.set("vertical_alignment", GInt(1));
      items.push(tr);
    } else {
      items.push(__vuiNode(o.trailing));
    }
  }
  let rowBox = GD.create("HBoxContainer");
  rowBox.set("theme_override_constants/separation", GInt(16));
  rowBox.set("mouse_filter", GInt(2));
  __vuiAddAll(rowBox, items);
  content.call("add_child", [rowBox]);
  b.call("add_child", [content]);

  if (o.onTap != null) {
    b.connect("pressed", (a) => {
      o.onTap();
    });
  }
  return b;
};

// ---------------------------------------------------------------------------
// controls
// ---------------------------------------------------------------------------

// Style an existing Godot Button as one of the Material button kinds. Shared
// by VUI.button and the VReact <button> driver so both render identically.
// (b, kind: 'filled'|'tonal'|'elevated'|'outline'|'ghost'|'text'|'danger',
//  { radius, padX })
VUI.buttonStyle = (b, kind, o) => {
  o = o ?? {};
  let t = VUI.theme();
  if (kind == null) {
    kind = "filled";
  }
  // Stadium shape (Material 3 buttons are fully rounded).
  let radius = __vuiNum(o.radius, t.radiusFull);
  let padX = __vuiNum(o.padX, 24);
  let disabledSb = VUI.styleBox({
    bg: t.onSurface.withAlpha(0.12), radius: radius, padX: padX,
  });
  let setColors = (color) => {
    b.set("theme_override_colors/font_color", color);
    b.set("theme_override_colors/font_hover_color", color);
    b.set("theme_override_colors/font_pressed_color", color);
    b.set("theme_override_colors/font_hover_pressed_color", color);
    b.set("theme_override_colors/font_focus_color", color);
    b.set("theme_override_colors/font_disabled_color", t.onSurface.withAlpha(0.38));
  };
  // Skinned buttons: nine-patch texture tinted per kind. Falls through to the
  // flat Material look for ghost/outline (kept light) or when the pack is absent.
  if (
    __vuiSkin != null &&
    __vuiSkin.button != null &&
    kind != "ghost" &&
    kind != "outline" &&
    kind != "outlined" &&
    kind != "text"
  ) {
    let sk = __vuiSkin.button;
    let tint = t.primary;
    let font = t.onPrimary;
    if (kind == "tonal") { tint = t.secondaryContainer; font = t.onSecondaryContainer; }
    else if (kind == "elevated") { tint = t.surfaceContainerLow; font = t.primary; }
    else if (kind == "danger") { tint = t.error; font = t.onError; }
    let py = __vuiNum(sk.padY, 10);
    let n = __vuiSkinBox(sk.normal, { margin: sk.margin, padX: padX, padY: py, modulate: tint });
    if (n != null) {
      let h = __vuiSkinBox(sk.hover ?? sk.normal, { margin: sk.margin, padX: padX, padY: py, modulate: __vuiLayer(tint, font, 0.08) });
      let p = __vuiSkinBox(sk.pressed ?? sk.normal, { margin: sk.margin, padX: padX, padY: py, modulate: __vuiLayer(tint, font, 0.14) });
      b.set("theme_override_styles/normal", n);
      b.set("theme_override_styles/hover", h ?? n);
      b.set("theme_override_styles/pressed", p ?? n);
      b.set("theme_override_styles/disabled", __vuiSkinBox(sk.normal, { margin: sk.margin, padX: padX, padY: py, modulate: t.onSurface.withAlpha(0.3) }) ?? disabledSb);
      b.set("theme_override_styles/focus", VUI.styleEmpty());
      setColors(font);
      return;
    }
  }
  if (kind == "filled") {
    b.set("theme_override_styles/normal", VUI.styleBox({ bg: t.primary, radius: radius, padX: padX }));
    b.set("theme_override_styles/hover", VUI.styleBox({ bg: __vuiLayer(t.primary, t.onPrimary, 0.08), radius: radius, padX: padX }));
    b.set("theme_override_styles/pressed", VUI.styleBox({ bg: __vuiLayer(t.primary, t.onPrimary, 0.12), radius: radius, padX: padX }));
    setColors(t.onPrimary);
  } else if (kind == "tonal") {
    b.set("theme_override_styles/normal", VUI.styleBox({ bg: t.secondaryContainer, radius: radius, padX: padX }));
    b.set("theme_override_styles/hover", VUI.styleBox({ bg: __vuiLayer(t.secondaryContainer, t.onSecondaryContainer, 0.08), radius: radius, padX: padX }));
    b.set("theme_override_styles/pressed", VUI.styleBox({ bg: __vuiLayer(t.secondaryContainer, t.onSecondaryContainer, 0.12), radius: radius, padX: padX }));
    setColors(t.onSecondaryContainer);
  } else if (kind == "elevated") {
    b.set("theme_override_styles/normal", VUI.styleBox({ bg: t.surfaceContainerLow, radius: radius, padX: padX, shadow: 1 }));
    b.set("theme_override_styles/hover", VUI.styleBox({ bg: __vuiLayer(t.surfaceContainerLow, t.primary, 0.08), radius: radius, padX: padX, shadow: 2 }));
    b.set("theme_override_styles/pressed", VUI.styleBox({ bg: __vuiLayer(t.surfaceContainerLow, t.primary, 0.12), radius: radius, padX: padX, shadow: 1 }));
    setColors(t.primary);
  } else if (kind == "danger") {
    b.set("theme_override_styles/normal", VUI.styleBox({ bg: t.error, radius: radius, padX: padX }));
    b.set("theme_override_styles/hover", VUI.styleBox({ bg: __vuiLayer(t.error, t.onError, 0.08), radius: radius, padX: padX }));
    b.set("theme_override_styles/pressed", VUI.styleBox({ bg: __vuiLayer(t.error, t.onError, 0.12), radius: radius, padX: padX }));
    setColors(t.onError);
  } else if (kind == "outline" || kind == "outlined") {
    b.set("theme_override_styles/normal", VUI.styleBox({ radius: radius, padX: padX, border: 1, borderColor: t.outline }));
    b.set("theme_override_styles/hover", VUI.styleBox({ radius: radius, padX: padX, border: 1, borderColor: t.outline, bg: t.primary.withAlpha(0.08) }));
    b.set("theme_override_styles/pressed", VUI.styleBox({ radius: radius, padX: padX, border: 1, borderColor: t.primary, bg: t.primary.withAlpha(0.12) }));
    setColors(t.primary);
    disabledSb = VUI.styleBox({ radius: radius, padX: padX, border: 1, borderColor: t.onSurface.withAlpha(0.12) });
  } else {
    // ghost / text button
    b.set("theme_override_styles/normal", VUI.styleBox({ radius: radius, padX: padX }));
    b.set("theme_override_styles/hover", VUI.styleBox({ bg: t.primary.withAlpha(0.08), radius: radius, padX: padX }));
    b.set("theme_override_styles/pressed", VUI.styleBox({ bg: t.primary.withAlpha(0.12), radius: radius, padX: padX }));
    setColors(t.primary);
    disabledSb = VUI.styleBox({ radius: radius, padX: padX });
  }
  b.set("theme_override_styles/disabled", disabledSb);
  b.set("theme_override_styles/focus", VUI.styleEmpty());
};

// The button. (text, { kind: 'filled'|'tonal'|'elevated'|'outline'|'ghost'|
// 'danger', glyph, onTap, wide, height, fontSize, radius }).
VUI.button = (text, o) => {
  o = o ?? {};
  let t = VUI.theme();
  let h = __vuiNum(o.height, t.controlHeight);
  let b = GD.create("Button");
  let label = "" + text;
  if (o.glyph != null) {
    label = o.glyph + "  " + label;
  }
  b.set("text", label);
  b.set("theme_override_font_sizes/font_size", GInt(__vuiNum(o.fontSize, t.fontS)));
  __vuiApplyWeight(b, "medium");
  b.set("focus_mode", GInt(0));
  __vuiMinSize(b, __vuiNum(o.minWidth, 0.0), h);
  if (o.wide == true) {
    __vuiExpandH(b);
  }
  VUI.buttonStyle(b, o.kind, o);
  if (o.disabled == true) {
    b.set("disabled", true);
  }
  if (o.onTap != null) {
    b.connect("pressed", (a) => {
      o.onTap();
    });
  }
  return b;
};

// A round icon-only button: (glyph, { onTap, size, color, bg, kind }).
VUI.iconButton = (glyph, o) => {
  o = o ?? {};
  let t = VUI.theme();
  let d = __vuiNum(o.size, 48.0);
  let b = GD.create("Button");
  b.set("text", glyph);
  b.set("theme_override_font_sizes/font_size", GInt(d * 0.44));
  b.set("focus_mode", GInt(0));
  __vuiMinSize(b, d, d);
  let kind = o.kind ?? "standard";
  if (kind == "filled") {
    b.set("theme_override_styles/normal", VUI.styleBox({ bg: o.bg ?? t.primary, radius: t.radiusFull }));
    b.set("theme_override_styles/hover", VUI.styleBox({ bg: __vuiLayer(o.bg ?? t.primary, t.onPrimary, 0.08), radius: t.radiusFull }));
    b.set("theme_override_styles/pressed", VUI.styleBox({ bg: __vuiLayer(o.bg ?? t.primary, t.onPrimary, 0.12), radius: t.radiusFull }));
    b.set("theme_override_colors/font_color", o.color ?? t.onPrimary);
    b.set("theme_override_colors/font_hover_color", o.color ?? t.onPrimary);
    b.set("theme_override_colors/font_pressed_color", o.color ?? t.onPrimary);
  } else if (kind == "tonal") {
    b.set("theme_override_styles/normal", VUI.styleBox({ bg: o.bg ?? t.secondaryContainer, radius: t.radiusFull }));
    b.set("theme_override_styles/hover", VUI.styleBox({ bg: __vuiLayer(o.bg ?? t.secondaryContainer, t.onSecondaryContainer, 0.08), radius: t.radiusFull }));
    b.set("theme_override_styles/pressed", VUI.styleBox({ bg: __vuiLayer(o.bg ?? t.secondaryContainer, t.onSecondaryContainer, 0.12), radius: t.radiusFull }));
    b.set("theme_override_colors/font_color", o.color ?? t.onSecondaryContainer);
    b.set("theme_override_colors/font_hover_color", o.color ?? t.onSecondaryContainer);
    b.set("theme_override_colors/font_pressed_color", o.color ?? t.onSecondaryContainer);
  } else {
    // standard: transparent with a state layer, like Flutter's IconButton.
    if (o.bg != null) {
      b.set("theme_override_styles/normal", VUI.styleBox({ bg: o.bg, radius: t.radiusFull }));
    } else {
      b.set("theme_override_styles/normal", VUI.styleBox({ radius: t.radiusFull }));
    }
    b.set("theme_override_styles/hover", VUI.styleBox({ bg: t.onSurface.withAlpha(0.08), radius: t.radiusFull }));
    b.set("theme_override_styles/pressed", VUI.styleBox({ bg: t.onSurface.withAlpha(0.12), radius: t.radiusFull }));
    b.set("theme_override_colors/font_color", o.color ?? t.onSurfaceVariant);
    b.set("theme_override_colors/font_hover_color", o.color ?? t.onSurface);
    b.set("theme_override_colors/font_pressed_color", t.primary);
  }
  b.set("theme_override_styles/focus", VUI.styleEmpty());
  if (o.onTap != null) {
    b.connect("pressed", (a) => {
      o.onTap();
    });
  }
  return b;
};

// A floating action button: (glyph, { onTap, size, bg, color }). Material FAB
// — 56dp, radius 16, primaryContainer, elevation 3.
VUI.fab = (glyph, o) => {
  o = o ?? {};
  let t = VUI.theme();
  let d = __vuiNum(o.size, 56.0);
  let b = GD.create("Button");
  b.set("text", glyph);
  b.set("theme_override_font_sizes/font_size", GInt(d * 0.42));
  b.set("focus_mode", GInt(0));
  __vuiMinSize(b, d, d);
  let bg = o.bg ?? t.primaryContainer;
  let fg = o.color ?? t.onPrimaryContainer;
  b.set("theme_override_styles/normal", VUI.styleBox({ bg: bg, radius: t.radiusL, shadow: 3 }));
  b.set("theme_override_styles/hover", VUI.styleBox({ bg: __vuiLayer(bg, fg, 0.08), radius: t.radiusL, shadow: 4 }));
  b.set("theme_override_styles/pressed", VUI.styleBox({ bg: __vuiLayer(bg, fg, 0.12), radius: t.radiusL, shadow: 3 }));
  b.set("theme_override_styles/focus", VUI.styleEmpty());
  b.set("theme_override_colors/font_color", fg);
  b.set("theme_override_colors/font_hover_color", fg);
  b.set("theme_override_colors/font_pressed_color", fg);
  if (o.onTap != null) {
    b.connect("pressed", (a) => {
      o.onTap();
    });
  }
  return b;
};

// Style an existing LineEdit as a Material filled text field. Shared by
// VUI.field and the VReact <input> driver.
VUI.fieldStyle = (e) => {
  let t = VUI.theme();
  e.set("theme_override_font_sizes/font_size", GInt(t.fontM));
  if (__vuiFonts.regular != null) {
    e.set("theme_override_fonts/font", __vuiFonts.regular);
  }
  __vuiMinSize(e, 0.0, t.fieldHeight);
  // Skinned input: pack nine-patch for normal + focus states.
  if (__vuiSkin != null && __vuiSkin.field != null) {
    let sk = __vuiSkin.field;
    let n = __vuiSkinBox(sk.normal, { margin: sk.margin, padX: 16, padY: 8, modulate: t.surfaceContainerHighest });
    if (n != null) {
      e.set("theme_override_styles/normal", n);
      e.set("theme_override_styles/focus", __vuiSkinBox(sk.focus ?? sk.normal, { margin: sk.margin, padX: 16, padY: 8, modulate: t.surface }) ?? n);
      e.set("theme_override_colors/font_color", t.onSurface);
      e.set("theme_override_colors/font_placeholder_color", t.onSurfaceVariant.withAlpha(0.7));
      e.set("theme_override_colors/caret_color", t.primary);
      e.set("theme_override_colors/selection_color", t.primary.withAlpha(0.3));
      return;
    }
  }
  e.set(
    "theme_override_styles/normal",
    VUI.styleBox({
      bg: t.surfaceContainerHighest,
      radiusTL: t.radiusXS, radiusTR: t.radiusXS, radiusBL: 0, radiusBR: 0, radius: 0,
      padX: 16, borderB: 1, borderColor: t.onSurfaceVariant,
    })
  );
  e.set(
    "theme_override_styles/focus",
    VUI.styleBox({
      bg: t.surfaceContainerHighest,
      radiusTL: t.radiusXS, radiusTR: t.radiusXS, radiusBL: 0, radiusBR: 0, radius: 0,
      padX: 16, borderB: 2, borderColor: t.primary,
    })
  );
  e.set("theme_override_colors/font_color", t.onSurface);
  e.set("theme_override_colors/font_placeholder_color", t.onSurfaceVariant.withAlpha(0.7));
  e.set("theme_override_colors/caret_color", t.primary);
  e.set("theme_override_colors/selection_color", t.primary.withAlpha(0.3));
};

// A text input: { placeholder, label, value, obscure, onChanged(text),
// onSubmit(text) }. Material filled field; a `label` renders a small heading
// above (the retained kit has no floating animation). Returns a handle
// { node, getText(), setText(v) }.
VUI.field = (o) => {
  o = o ?? {};
  let t = VUI.theme();
  let e = GD.create("LineEdit");
  let st = { text: "" + (o.value ?? "") };
  if (o.placeholder != null) {
    e.set("placeholder_text", o.placeholder);
  }
  if (st.text != "") {
    e.set("text", st.text);
  }
  if (o.obscure == true) {
    e.set("secret", true);
  }
  __vuiExpandH(e);
  VUI.fieldStyle(e);
  e.connect("text_changed", (args) => {
    st.text = args[0];
    if (o.onChanged != null) {
      o.onChanged(args[0]);
    }
  });
  if (o.onSubmit != null) {
    e.connect("text_submitted", (args) => {
      st.text = args[0];
      o.onSubmit(args[0]);
    });
  }
  let node = e;
  if (o.label != null) {
    node = __vuiNode(
      VUI.column({
        gap: 6,
        children: [VUI.text(o.label, { size: t.fontXS, color: t.primary, weight: "medium" }), e],
      })
    );
  }
  return {
    node: node,
    edit: e,
    getText: () => st.text,
    setText: (v) => {
      st.text = "" + v;
      e.set("text", st.text);
    },
  };
};

// An animated Material switch: { value, onChanged(bool) }. Pill track +
// sliding knob (52×32, 24dp thumb), tweened over the bridge. Returns a handle
// { node, isOn(), setOn(v) }.
VUI.toggle = (o) => {
  o = o ?? {};
  let t = VUI.theme();
  let w = 52.0;
  let h = 32.0;
  let knobD = 24.0;
  let inset = (h - knobD) / 2.0;
  let st = { on: o.value == true };

  let b = GD.create("Button");
  b.set("focus_mode", GInt(0));
  __vuiMinSize(b, w, h);
  b.set("theme_override_styles/normal", VUI.styleEmpty());
  b.set("theme_override_styles/hover", VUI.styleEmpty());
  b.set("theme_override_styles/pressed", VUI.styleEmpty());
  b.set("theme_override_styles/focus", VUI.styleEmpty());

  let offTrack = VUI.styleBox({ bg: t.surfaceContainerHighest, radius: t.radiusFull, border: 2, borderColor: t.outline });
  let onTrack = VUI.styleBox({ bg: t.primary, radius: t.radiusFull });
  let track = GD.create("Panel");
  __vuiFullRect(track);
  track.set("mouse_filter", GInt(2));
  track.set("theme_override_styles/panel", st.on ? onTrack : offTrack);
  b.call("add_child", [track]);

  let offKnob = VUI.styleBox({ bg: t.outline, radius: t.radiusFull });
  let onKnob = VUI.styleBox({ bg: t.onPrimary, radius: t.radiusFull, shadow: 1 });
  let knob = GD.create("Panel");
  __vuiMinSize(knob, knobD, knobD);
  knob.set("size", new Vector2(knobD, knobD));
  knob.set("mouse_filter", GInt(2));
  knob.set("theme_override_styles/panel", st.on ? onKnob : offKnob);
  let xOff = inset;
  let xOn = w - knobD - inset;
  knob.set("position", new Vector2(st.on ? xOn : xOff, inset));
  b.call("add_child", [knob]);

  let apply = (animate) => {
    track.set("theme_override_styles/panel", st.on ? onTrack : offTrack);
    knob.set("theme_override_styles/panel", st.on ? onKnob : offKnob);
    let target = new Vector2(st.on ? xOn : xOff, inset);
    if (animate == true) {
      VUI.animate(knob, "position", target, 140);
    } else {
      knob.set("position", target);
    }
  };
  b.connect("pressed", (a) => {
    st.on = !st.on;
    apply(true);
    if (o.onChanged != null) {
      o.onChanged(st.on);
    }
  });
  return {
    node: b,
    isOn: () => st.on,
    setOn: (v) => {
      st.on = v == true;
      apply(false);
    },
  };
};

// A checkbox with a label: { label, value, onChanged(bool) }. Returns a
// handle { node, isChecked(), setChecked(v) }.
VUI.checkbox = (o) => {
  o = o ?? {};
  let t = VUI.theme();
  let st = { on: o.value == true };
  let d = 22.0;

  let b = GD.create("Button");
  b.set("focus_mode", GInt(0));
  b.set("theme_override_styles/normal", VUI.styleEmpty());
  b.set("theme_override_styles/hover", VUI.styleEmpty());
  b.set("theme_override_styles/pressed", VUI.styleEmpty());
  b.set("theme_override_styles/focus", VUI.styleEmpty());
  __vuiMinSize(b, 0.0, t.minTouch);

  let boxOff = VUI.styleBox({ radius: t.radiusXS, border: 2, borderColor: t.onSurfaceVariant });
  let boxOn = VUI.styleBox({ bg: t.primary, radius: t.radiusXS });
  let box = GD.create("PanelContainer");
  __vuiMinSize(box, d, d);
  box.set("mouse_filter", GInt(2));
  box.set("theme_override_styles/panel", st.on ? boxOn : boxOff);
  let mark = VUI.text("✓", { size: t.fontS, color: t.onPrimary, align: "center", weight: "bold" });
  mark.set("vertical_alignment", GInt(1));
  mark.set("visible", st.on);
  box.call("add_child", [mark]);

  let boxCenter = GD.create("CenterContainer");
  boxCenter.set("mouse_filter", GInt(2));
  boxCenter.call("add_child", [box]);

  let items = [boxCenter];
  if (o.label != null) {
    let lab = VUI.text(o.label, { size: t.fontS });
    lab.set("vertical_alignment", GInt(1));
    items.push(lab);
  }
  let rowBox = GD.create("HBoxContainer");
  rowBox.set("theme_override_constants/separation", GInt(12));
  rowBox.set("mouse_filter", GInt(2));
  __vuiFullRect(rowBox);
  __vuiAddAll(rowBox, items);
  b.call("add_child", [rowBox]);

  let apply = () => {
    box.set("theme_override_styles/panel", st.on ? boxOn : boxOff);
    mark.set("visible", st.on);
  };
  b.connect("pressed", (a) => {
    st.on = !st.on;
    apply();
    if (o.onChanged != null) {
      o.onChanged(st.on);
    }
  });
  return {
    node: b,
    isChecked: () => st.on,
    setChecked: (v) => {
      st.on = v == true;
      apply();
    },
  };
};

// Style an existing HSlider like a Material slider. Shared with the VReact
// <slider> driver.
VUI.sliderStyle = (s) => {
  let t = VUI.theme();
  __vuiMinSize(s, 0.0, t.minTouch);
  // The groove…
  s.set(
    "theme_override_styles/slider",
    VUI.styleBox({ bg: t.surfaceContainerHighest, radius: t.radiusFull, padY: 3 })
  );
  // …the filled part…
  s.set(
    "theme_override_styles/grabber_area",
    VUI.styleBox({ bg: t.primary, radius: t.radiusFull })
  );
  s.set(
    "theme_override_styles/grabber_area_highlight",
    VUI.styleBox({ bg: t.primary, radius: t.radiusFull })
  );
  // …and a code-generated round thumb (no image assets).
  let grabber = VUI.circleTexture(22, t.primary);
  let grabberHi = VUI.circleTexture(26, __vuiLayer(t.primary, t.onPrimary, 0.1));
  s.set("theme_override_icons/grabber", grabber);
  s.set("theme_override_icons/grabber_disabled", grabber);
  s.set("theme_override_icons/grabber_highlight", grabberHi);
};

// A slider: { min, max, value, step, onChanged(value) }. Returns a handle
// { node, getValue(), setValue(v) }.
VUI.slider = (o) => {
  o = o ?? {};
  let s = GD.create("HSlider");
  let st = { value: __vuiNum(o.value, 0.0) };
  s.set("min_value", GFloat(__vuiNum(o.min, 0.0)));
  s.set("max_value", GFloat(__vuiNum(o.max, 100.0)));
  if (o.step != null) {
    s.set("step", GFloat(o.step));
  }
  s.set("value", GFloat(st.value));
  s.set("focus_mode", GInt(0));
  __vuiExpandH(s);
  VUI.sliderStyle(s);
  s.connect("value_changed", (args) => {
    st.value = args[0];
    if (o.onChanged != null) {
      o.onChanged(args[0]);
    }
  });
  return {
    node: s,
    getValue: () => st.value,
    setValue: (v) => {
      st.value = v;
      s.set("value", GFloat(v));
    },
  };
};

// A progress bar: { value, max, height, color }. Returns a handle
// { node, setValue(v) }.
VUI.progress = (o) => {
  o = o ?? {};
  let t = VUI.theme();
  let p = GD.create("ProgressBar");
  p.set("min_value", GFloat(0.0));
  p.set("max_value", GFloat(__vuiNum(o.max, 100.0)));
  p.set("value", GFloat(__vuiNum(o.value, 0.0)));
  p.set("show_percentage", false);
  __vuiMinSize(p, 0.0, __vuiNum(o.height, 6.0));
  __vuiExpandH(p);
  p.set(
    "theme_override_styles/background",
    VUI.styleBox({ bg: t.surfaceContainerHighest, radius: t.radiusFull })
  );
  p.set(
    "theme_override_styles/fill",
    VUI.styleBox({ bg: o.color ?? t.primary, radius: t.radiusFull })
  );
  return {
    node: p,
    setValue: (v) => {
      p.set("value", GFloat(v));
    },
  };
};

// ---------------------------------------------------------------------------
// structure
// ---------------------------------------------------------------------------

// The top app bar (Material small top app bar): { title, subtitle, leading
// (widget), actions: [widget], bg, flat }.
VUI.appBar = (o) => {
  o = o ?? {};
  let t = VUI.theme();
  let bar = GD.create("PanelContainer");
  __vuiMinSize(bar, 0.0, t.barHeight);
  bar.set(
    "theme_override_styles/panel",
    VUI.styleBox({
      bg: o.bg ?? t.surfaceContainer,
      radius: 0,
      padX: 16,
      padY: 8,
      shadow: o.flat == true ? 0 : 1,
    })
  );
  let items = [];
  if (o.leading != null) {
    items.push(__vuiNode(o.leading));
  }
  let titleCol = [];
  titleCol.push(VUI.text(o.title ?? "", { size: t.fontL, weight: "medium" }));
  if (o.subtitle != null) {
    titleCol.push(VUI.caption(o.subtitle));
  }
  let midInner = VUI.column({ gap: 0, children: titleCol });
  let mid = GD.create("VBoxContainer");
  mid.set("alignment", GInt(1));
  mid.call("add_child", [__vuiNode(midInner)]);
  __vuiExpandH(mid);
  items.push(mid);
  if (o.actions != null) {
    for (let i = 0; i < o.actions.length; i++) {
      items.push(__vuiNode(o.actions[i]));
    }
  }
  let rowBox = GD.create("HBoxContainer");
  rowBox.set("theme_override_constants/separation", GInt(12));
  __vuiAddAll(rowBox, items);
  bar.call("add_child", [rowBox]);
  return bar;
};

// A Material segmented button strip: { items: [label], index, onSelect(i) }.
// Returns a handle { node, select(i), getIndex() }.
VUI.tabs = (o) => {
  o = o ?? {};
  let t = VUI.theme();
  let st = { index: __vuiNum(o.index, 0), buttons: [] };
  let wrap = GD.create("PanelContainer");
  wrap.set(
    "theme_override_styles/panel",
    VUI.styleBox({ radius: t.radiusFull, pad: 4, bg: t.surfaceContainerHigh })
  );
  let rowBox = GD.create("HBoxContainer");
  rowBox.set("theme_override_constants/separation", GInt(4));
  wrap.call("add_child", [rowBox]);

  let onSb = VUI.styleBox({ bg: t.secondaryContainer, radius: t.radiusFull, padX: 16, padY: 8 });
  let offSb = VUI.styleBox({ radius: t.radiusFull, padX: 16, padY: 8 });
  let offHover = VUI.styleBox({ bg: t.onSurface.withAlpha(0.08), radius: t.radiusFull, padX: 16, padY: 8 });

  let applyAll = () => {
    for (let i = 0; i < st.buttons.length; i++) {
      let selected = i == st.index;
      let bb = st.buttons[i];
      bb.set("theme_override_styles/normal", selected ? onSb : offSb);
      bb.set("theme_override_styles/hover", selected ? onSb : offHover);
      bb.set("theme_override_styles/pressed", selected ? onSb : offHover);
      bb.set("theme_override_colors/font_color", selected ? t.onSecondaryContainer : t.onSurfaceVariant);
      bb.set("theme_override_colors/font_hover_color", selected ? t.onSecondaryContainer : t.onSurface);
      bb.set("theme_override_colors/font_pressed_color", selected ? t.onSecondaryContainer : t.onSurface);
    }
  };
  let items = o.items ?? [];
  for (let i = 0; i < items.length; i++) {
    // A fresh `let` per iteration: each closure captures its own index.
    let idx = i;
    let b = GD.create("Button");
    b.set("text", "" + items[i]);
    b.set("theme_override_font_sizes/font_size", GInt(t.fontS));
    __vuiApplyWeight(b, "medium");
    b.set("focus_mode", GInt(0));
    b.set("theme_override_styles/focus", VUI.styleEmpty());
    __vuiMinSize(b, 0.0, 40.0);
    __vuiExpandH(b);
    b.connect("pressed", (a) => {
      st.index = idx;
      applyAll();
      if (o.onSelect != null) {
        o.onSelect(idx);
      }
    });
    st.buttons.push(b);
    rowBox.call("add_child", [b]);
  }
  applyAll();
  return {
    node: wrap,
    getIndex: () => st.index,
    select: (i) => {
      st.index = i;
      applyAll();
      if (o.onSelect != null) {
        o.onSelect(i);
      }
    },
  };
};

// The Material navigation bar: { items: [{glyph, label}], index, onSelect(i) }.
// 80dp bar on surfaceContainer; the active item gets a secondaryContainer
// indicator pill behind its icon. Returns a handle { node, select(i),
// getIndex() }.
VUI.bottomNav = (o) => {
  o = o ?? {};
  let t = VUI.theme();
  let st = { index: __vuiNum(o.index, 0), glyphs: [], labels: [], pills: [] };
  let bar = GD.create("PanelContainer");
  __vuiMinSize(bar, 0.0, t.navHeight);
  bar.set(
    "theme_override_styles/panel",
    VUI.styleBox({ bg: t.surfaceContainer, radius: 0, padY: 10 })
  );
  let rowBox = GD.create("HBoxContainer");
  rowBox.set("theme_override_constants/separation", GInt(0));
  bar.call("add_child", [rowBox]);

  let pillOn = VUI.styleBox({ bg: t.secondaryContainer, radius: t.radiusFull });
  let pillOff = VUI.styleEmpty();

  let applyAll = () => {
    for (let i = 0; i < st.glyphs.length; i++) {
      let selected = i == st.index;
      st.pills[i].set("theme_override_styles/panel", selected ? pillOn : pillOff);
      st.glyphs[i].set(
        "theme_override_colors/font_color",
        selected ? t.onSecondaryContainer : t.onSurfaceVariant
      );
      st.labels[i].set(
        "theme_override_colors/font_color",
        selected ? t.onSurface : t.onSurfaceVariant
      );
    }
  };
  let items = o.items ?? [];
  for (let i = 0; i < items.length; i++) {
    let idx = i;
    let b = GD.create("Button");
    b.set("focus_mode", GInt(0));
    b.set("theme_override_styles/normal", VUI.styleEmpty());
    b.set("theme_override_styles/hover", VUI.styleEmpty());
    b.set("theme_override_styles/pressed", VUI.styleEmpty());
    b.set("theme_override_styles/focus", VUI.styleEmpty());
    __vuiExpandH(b);

    // The icon sits inside a 56×30 indicator pill.
    let glyph = VUI.icon(items[i]["glyph"] ?? "•", { size: 18, color: t.onSurfaceVariant });
    glyph.set("vertical_alignment", GInt(1));
    let pill = GD.create("PanelContainer");
    __vuiMinSize(pill, 56.0, 30.0);
    pill.set("mouse_filter", GInt(2));
    pill.set("theme_override_styles/panel", pillOff);
    pill.call("add_child", [glyph]);
    let pillCenter = GD.create("CenterContainer");
    pillCenter.set("mouse_filter", GInt(2));
    pillCenter.call("add_child", [pill]);

    let label = VUI.text(items[i]["label"] ?? "", {
      size: t.fontXS, color: t.onSurfaceVariant, align: "center", weight: "medium",
    });
    let col = GD.create("VBoxContainer");
    col.set("theme_override_constants/separation", GInt(4));
    col.set("mouse_filter", GInt(2));
    __vuiFullRect(col);
    col.set("alignment", GInt(1)); // centered
    col.call("add_child", [pillCenter]);
    col.call("add_child", [label]);
    b.call("add_child", [col]);

    b.connect("pressed", (a) => {
      st.index = idx;
      applyAll();
      if (o.onSelect != null) {
        o.onSelect(idx);
      }
    });
    st.glyphs.push(glyph);
    st.labels.push(label);
    st.pills.push(pill);
    rowBox.call("add_child", [b]);
  }
  applyAll();
  return {
    node: bar,
    getIndex: () => st.index,
    select: (i) => {
      st.index = i;
      applyAll();
      if (o.onSelect != null) {
        o.onSelect(i);
      }
    },
  };
};

// ---- overlay helpers (dialogs / sheets / toasts mount on the app overlay) --
//
// The overlay only captures input while at least one modal is up; a counter
// keeps stacked modals honest (a dialog above a sheet, …).

function __vuiOverlayOn() {
  __vuiApp.overlays = __vuiApp.overlays + 1;
  __vuiApp.overlay.set("mouse_filter", GInt(0)); // MOUSE_FILTER_STOP
}

function __vuiOverlayOff() {
  __vuiApp.overlays = __vuiApp.overlays - 1;
  if (__vuiApp.overlays <= 0) {
    __vuiApp.overlays = 0;
    __vuiApp.overlay.set("mouse_filter", GInt(2)); // MOUSE_FILTER_IGNORE
  }
}

// A dimmed full-screen scrim button; onTap dismisses.
function __vuiScrim(onTap) {
  let t = VUI.theme();
  let s = GD.create("Button");
  __vuiFullRect(s);
  s.set("focus_mode", GInt(0));
  s.set("theme_override_styles/normal", VUI.styleBox({ bg: t.scrim }));
  s.set("theme_override_styles/hover", VUI.styleBox({ bg: t.scrim }));
  s.set("theme_override_styles/pressed", VUI.styleBox({ bg: t.scrim }));
  s.set("theme_override_styles/focus", VUI.styleEmpty());
  s.connect("pressed", (a) => {
    onTap();
  });
  return s;
}

// A modal Material dialog: { title, body (string or widget), actions:
// [{text, kind, onTap}], width, dismissible }. Shows immediately; returns
// { close() }.
VUI.dialog = (o) => {
  o = o ?? {};
  let t = VUI.theme();
  let m = VUI.metrics();
  let maxW = m.w - 48.0;
  if (maxW > 560.0) {
    maxW = 560.0;
  }
  let w = __vuiNum(o.width, maxW);
  if (w > m.w - 24.0) {
    w = m.w - 24.0;
  }
  let holder = GD.create("Control");
  __vuiFullRect(holder);
  __vuiApp.overlay.call("add_child", [holder]);
  __vuiOverlayOn();

  let closed = { done: false };
  let close = () => {
    if (closed.done) {
      return;
    }
    closed.done = true;
    VUI.fade(holder, 0.0, 130);
    GTimer.after(150, () => {
      holder.queueFree();
    });
    __vuiOverlayOff();
  };

  holder.call("add_child", [__vuiScrim(() => {
    if (o.dismissible != false) {
      close();
    }
  })]);

  let children = [];
  if (o.title != null) {
    children.push(VUI.text(o.title, { size: 24, weight: "medium" }));
  }
  if (o.body != null) {
    if (__isType(o.body, "string")) {
      children.push(VUI.text(o.body, { size: t.fontS, dim: true, wrap: true }));
    } else {
      children.push(__vuiNode(o.body));
    }
  }
  if (o.actions != null) {
    let btns = [VUI.spacer()];
    for (let i = 0; i < o.actions.length; i++) {
      let spec = o.actions[i];
      btns.push(
        VUI.button(spec["text"] ?? "OK", {
          kind: spec["kind"] ?? "ghost",
          height: 40.0,
          onTap: () => {
            close();
            if (spec["onTap"] != null) {
              spec["onTap"]();
            }
          },
        })
      );
    }
    children.push(VUI.row({ gap: 8, children: btns }));
  }

  let card = VUI.panel({
    bg: t.surfaceContainerHigh,
    radius: t.radiusXL,
    pad: 24,
    gap: 16,
    shadow: 3,
    children: children,
  });
  // Centered at a fixed width via anchors + symmetric offsets.
  card.set("anchor_left", GFloat(0.5));
  card.set("anchor_right", GFloat(0.5));
  card.set("anchor_top", GFloat(0.5));
  card.set("anchor_bottom", GFloat(0.5));
  card.set("offset_left", GFloat(0.0 - w / 2.0));
  card.set("offset_right", GFloat(w / 2.0));
  card.set("grow_horizontal", GInt(2)); // GROW_DIRECTION_BOTH
  card.set("grow_vertical", GInt(2));
  holder.call("add_child", [card]);

  // Entrance: fade the whole holder in.
  holder.set("modulate", new Color(1.0, 1.0, 1.0, 0.0));
  VUI.fade(holder, 1.0, 150);

  return { node: holder, close: close };
};

// A Material bottom sheet: { title, children, dismissible }. Returns
// { close() }.
VUI.sheet = (o) => {
  o = o ?? {};
  let t = VUI.theme();
  let holder = GD.create("Control");
  __vuiFullRect(holder);
  __vuiApp.overlay.call("add_child", [holder]);
  __vuiOverlayOn();

  let closed = { done: false };
  let close = () => {
    if (closed.done) {
      return;
    }
    closed.done = true;
    VUI.fade(holder, 0.0, 150);
    GTimer.after(170, () => {
      holder.queueFree();
    });
    __vuiOverlayOff();
  };

  holder.call("add_child", [__vuiScrim(() => {
    if (o.dismissible != false) {
      close();
    }
  })]);

  let children = [];
  // The grab handle (32×4, outline-tinted).
  let handleBar = GD.create("Panel");
  __vuiMinSize(handleBar, 32.0, 4.0);
  handleBar.set("theme_override_styles/panel", VUI.styleBox({ bg: t.outlineVariant, radius: t.radiusFull }));
  let handleCenter = GD.create("CenterContainer");
  handleCenter.call("add_child", [handleBar]);
  children.push(handleCenter);
  if (o.title != null) {
    children.push(VUI.title(o.title));
  }
  if (o.children != null) {
    for (let i = 0; i < o.children.length; i++) {
      children.push(o.children[i]);
    }
  }

  let card = VUI.panel({
    bg: t.surfaceContainer,
    radius: 0,
    pad: 20,
    gap: 16,
    children: children,
  });
  // Pin to the bottom edge, full width, rounded top corners.
  card.set(
    "theme_override_styles/panel",
    VUI.styleBox({ bg: t.surfaceContainer, radiusTL: t.radiusXL, radiusTR: t.radiusXL, radius: 0, pad: 20, shadow: 2 })
  );
  card.set("anchor_left", GFloat(0.0));
  card.set("anchor_right", GFloat(1.0));
  card.set("anchor_top", GFloat(1.0));
  card.set("anchor_bottom", GFloat(1.0));
  card.set("grow_vertical", GInt(0)); // GROW_DIRECTION_BEGIN — grow upward
  holder.call("add_child", [card]);

  holder.set("modulate", new Color(1.0, 1.0, 1.0, 0.0));
  VUI.fade(holder, 1.0, 150);

  return { node: holder, close: close };
};

// Style an existing OptionButton like a Material filled field/menu anchor.
// Shared with the VReact <select> driver. Also restyles its popup menu.
VUI.dropdownStyle = (e) => {
  let t = VUI.theme();
  e.set("theme_override_font_sizes/font_size", GInt(t.fontM));
  if (__vuiFonts.regular != null) {
    e.set("theme_override_fonts/font", __vuiFonts.regular);
  }
  __vuiMinSize(e, 0.0, t.fieldHeight);
  e.set("theme_override_styles/normal", VUI.styleBox({
    bg: t.surfaceContainerHighest,
    radiusTL: t.radiusXS, radiusTR: t.radiusXS, radiusBL: 0, radiusBR: 0, radius: 0,
    padX: 16, borderB: 1, borderColor: t.onSurfaceVariant,
  }));
  e.set("theme_override_styles/hover", VUI.styleBox({
    bg: __vuiLayer(t.surfaceContainerHighest, t.onSurface, 0.06),
    radiusTL: t.radiusXS, radiusTR: t.radiusXS, radiusBL: 0, radiusBR: 0, radius: 0,
    padX: 16, borderB: 1, borderColor: t.onSurfaceVariant,
  }));
  e.set("theme_override_styles/pressed", VUI.styleBox({
    bg: t.surfaceContainerHighest,
    radiusTL: t.radiusXS, radiusTR: t.radiusXS, radiusBL: 0, radiusBR: 0, radius: 0,
    padX: 16, borderB: 2, borderColor: t.primary,
  }));
  e.set("theme_override_styles/focus", VUI.styleEmpty());
  e.set("theme_override_colors/font_color", t.onSurface);
  e.set("theme_override_colors/font_hover_color", t.onSurface);
  e.set("theme_override_colors/font_pressed_color", t.onSurface);
  // The popup menu: an elevated Material menu surface.
  let popup = e.call("get_popup");
  if (popup != null && !GD.isError(popup)) {
    popup.set(
      "theme_override_styles/panel",
      VUI.styleBox({ bg: t.surfaceContainerHigh, radius: t.radiusXS, pad: 8, shadow: 2 })
    );
    popup.set("theme_override_font_sizes/font_size", GInt(t.fontM));
    popup.set("theme_override_colors/font_color", t.onSurface);
    popup.set("theme_override_colors/font_hover_color", t.onSurface);
    popup.set(
      "theme_override_styles/hover",
      VUI.styleBox({ bg: t.onSurface.withAlpha(0.08), radius: t.radiusXS })
    );
  }
};

// A dropdown selector (OptionButton): { items: [label], index, onSelect(i) }.
// Returns a handle { node, getIndex(), select(i) }.
VUI.dropdown = (o) => {
  o = o ?? {};
  let st = { index: __vuiNum(o.index, 0) };
  let e = GD.create("OptionButton");
  e.set("focus_mode", GInt(0));
  VUI.dropdownStyle(e);
  let items = o.items ?? [];
  for (let i = 0; i < items.length; i++) {
    e.call("add_item", ["" + items[i], GInt(i)]);
  }
  if (items.length > 0) {
    e.call("select", [GInt(st.index)]);
  }
  e.connect("item_selected", (a) => {
    st.index = a[0];
    if (o.onSelect != null) {
      o.onSelect(a[0]);
    }
  });
  return {
    node: e,
    getIndex: () => st.index,
    select: (i) => {
      st.index = i;
      e.call("select", [GInt(i)]);
    },
  };
};

// Style an existing TextEdit as a Material filled multiline field. Shared
// with the VReact <textarea> driver.
VUI.textareaStyle = (e) => {
  let t = VUI.theme();
  e.set("theme_override_font_sizes/font_size", GInt(t.fontM));
  if (__vuiFonts.regular != null) {
    e.set("theme_override_fonts/font", __vuiFonts.regular);
  }
  e.set(
    "theme_override_styles/normal",
    VUI.styleBox({
      bg: t.surfaceContainerHighest,
      radiusTL: t.radiusXS, radiusTR: t.radiusXS, radiusBL: 0, radiusBR: 0, radius: 0,
      pad: 14, borderB: 1, borderColor: t.onSurfaceVariant,
    })
  );
  e.set(
    "theme_override_styles/focus",
    VUI.styleBox({
      bg: t.surfaceContainerHighest,
      radiusTL: t.radiusXS, radiusTR: t.radiusXS, radiusBL: 0, radiusBR: 0, radius: 0,
      pad: 14, borderB: 2, borderColor: t.primary,
    })
  );
  e.set("theme_override_colors/font_color", t.onSurface);
  e.set("theme_override_colors/font_placeholder_color", t.onSurfaceVariant.withAlpha(0.7));
  e.set("theme_override_colors/caret_color", t.primary);
  e.set("theme_override_colors/selection_color", t.primary.withAlpha(0.3));
};

// A multiline text input (TextEdit): { placeholder, value, height,
// onChanged(text) }. Returns a handle { node, getText(), setText(v) }.
VUI.textarea = (o) => {
  o = o ?? {};
  let t = VUI.theme();
  let st = { text: "" + (o.value ?? "") };
  let e = GD.create("TextEdit");
  if (o.placeholder != null) {
    e.set("placeholder_text", o.placeholder);
  }
  if (st.text != "") {
    e.set("text", st.text);
  }
  e.set("wrap_mode", GInt(1));
  __vuiMinSize(e, 0.0, __vuiNum(o.height, 120.0));
  __vuiExpandH(e);
  VUI.textareaStyle(e);
  e.connect("text_changed", (a) => {
    st.text = "" + e.get("text");
    if (o.onChanged != null) {
      o.onChanged(st.text);
    }
  });
  return {
    node: e,
    getText: () => st.text,
    setText: (v) => {
      st.text = "" + v;
      e.set("text", st.text);
    },
  };
};

// A draggable, closable floating window (the desktop-game "panel window"
// idiom): { title, subtitle, accent (Color), width, height, x, y, child,
// children, gap, onClose }. Mounts on the app overlay; returns
// { node, close(), setTitle(v) }. Drag the title bar to move it.
VUI.window = (o) => {
  o = o ?? {};
  let t = VUI.theme();
  let w = __vuiNum(o.width, __vuiApp.w - 80.0);
  let h = __vuiNum(o.height, 0.0);
  let accent = o.accent ?? t.primary;

  let holder = GD.create("PanelContainer");
  holder.set(
    "theme_override_styles/panel",
    VUI.styleBox({ bg: t.surfaceContainerLow, radius: t.radiusL, shadow: 4 })
  );
  holder.set("position", new Vector2(__vuiNum(o.x, 40.0), __vuiNum(o.y, 60.0)));
  __vuiMinSize(holder, w, h);

  let closed = { done: false };
  let close = () => {
    if (closed.done) {
      return;
    }
    closed.done = true;
    holder.queueFree();
    if (o.onClose != null) {
      o.onClose();
    }
  };

  let titleLabel = VUI.text(o.title ?? "", { size: t.fontM, color: accent, weight: "medium" });
  __vuiExpandH(titleLabel);
  let closeBtn = VUI.iconButton("✕", { size: 40.0, onTap: close });

  // Title bar doubles as the drag handle.
  let bar = GD.create("PanelContainer");
  bar.set(
    "theme_override_styles/panel",
    VUI.styleBox({ bg: t.surfaceContainerHigh, radiusTL: t.radiusL, radiusTR: t.radiusL, radius: 0, padX: 16, padY: 8 })
  );
  let barRow = GD.create("HBoxContainer");
  barRow.set("theme_override_constants/separation", GInt(12));
  let titleItems = [titleLabel];
  if (o.subtitle != null) {
    let col = VUI.column({ gap: 2, children: [titleLabel, VUI.caption(o.subtitle)] });
    __vuiExpandH(col);
    titleItems = [col];
  }
  __vuiAddAll(barRow, titleItems);
  barRow.call("add_child", [closeBtn]);
  bar.call("add_child", [barRow]);

  let drag = { on: false };
  bar.connect("gui_input", (a) => {
    let ev = a[0];
    if (ev == null || !__isType(ev, "GObj")) {
      return;
    }
    if (ev.cls == "InputEventMouseButton" || ev.cls == "InputEventScreenTouch") {
      drag.on = ev.get("pressed") == true;
    } else if (ev.cls == "InputEventMouseMotion" || ev.cls == "InputEventScreenDrag") {
      if (drag.on) {
        let rel = ev.get("relative");
        let pos = holder.get("position");
        holder.set("position", new Vector2(pos.x + rel.x, pos.y + rel.y));
      }
    }
  });

  let bodyChildren = [];
  if (o.child != null) {
    bodyChildren.push(o.child);
  }
  if (o.children != null) {
    for (let i = 0; i < o.children.length; i++) {
      bodyChildren.push(o.children[i]);
    }
  }
  let body = VUI.column({ gap: __vuiNum(o.gap, 12), pad: 16, children: bodyChildren });

  let frame = GD.create("VBoxContainer");
  frame.set("theme_override_constants/separation", GInt(0));
  frame.call("add_child", [bar]);
  if (h > 0.0) {
    frame.call("add_child", [__vuiNode(VUI.scroll({ child: body }))]);
  } else {
    frame.call("add_child", [__vuiNode(body)]);
  }
  holder.call("add_child", [frame]);

  __vuiApp.overlay.call("add_child", [holder]);
  return {
    node: holder,
    close: close,
    setTitle: (v) => {
      titleLabel.set("text", "" + v);
    },
  };
};

// A snackbar / toast: (msg, { kind: 'info'|'success'|'warning'|'danger',
// ms }). Material snackbar — inverse surface, bottom of the screen.
// Auto-dismisses; a new toast replaces the previous one.
VUI.toast = (msg, o) => {
  o = o ?? {};
  let t = VUI.theme();
  if (__vuiApp.toast != null) {
    __vuiApp.toast.queueFree();
    __vuiApp.toast = null;
  }
  let accent = t.info;
  let glyph = "ℹ";
  if (o.kind == "success") {
    accent = t.success;
    glyph = "✓";
  } else if (o.kind == "warning") {
    accent = t.warning;
    glyph = "!";
  } else if (o.kind == "danger") {
    accent = t.danger;
    glyph = "✕";
  }
  let p = GD.create("PanelContainer");
  p.set(
    "theme_override_styles/panel",
    VUI.styleBox({ bg: t.inverseSurface, radius: t.radiusS, padX: 16, padY: 12, shadow: 3 })
  );
  let rowBox = GD.create("HBoxContainer");
  rowBox.set("theme_override_constants/separation", GInt(10));
  rowBox.call("add_child", [VUI.icon(glyph, { size: t.fontM, color: accent })]);
  let msgLabel = VUI.text("" + msg, { size: t.fontS, color: t.inverseOnSurface });
  rowBox.call("add_child", [msgLabel]);
  p.call("add_child", [rowBox]);

  // Bottom-center strip, above the nav bar.
  p.set("anchor_left", GFloat(0.0));
  p.set("anchor_right", GFloat(1.0));
  p.set("anchor_top", GFloat(1.0));
  p.set("anchor_bottom", GFloat(1.0));
  p.set("offset_left", GFloat(16.0));
  p.set("offset_right", GFloat(-16.0));
  p.set("offset_top", GFloat(0.0 - t.navHeight - 76.0));
  p.set("offset_bottom", GFloat(0.0 - t.navHeight - 16.0));
  p.set("grow_vertical", GInt(0)); // GROW_DIRECTION_BEGIN — taller toasts grow up
  p.set("mouse_filter", GInt(2));
  __vuiApp.overlay.call("add_child", [p]);
  __vuiApp.toast = p;

  p.set("modulate", new Color(1.0, 1.0, 1.0, 0.0));
  VUI.fade(p, 1.0, 160);
  GTimer.after(__vuiNum(o.ms, 2200), () => {
    // Only dismiss if this toast is still the live one.
    if (__vuiApp.toast != null) {
      if (__vuiApp.toast.id == p.id) {
        VUI.fade(p, 0.0, 200);
        GTimer.after(220, () => {
          p.queueFree();
        });
        __vuiApp.toast = null;
      }
    }
  });
  return p;
};

// ===========================================================================
// VUI webview — open an external URL over the running app.
// ===========================================================================
//
// One API, a ladder of OS-NATIVE surfaces (no bundled browser engine, so the
// export stays small). In order of preference:
//
//   1. WEB export — via the JavaScriptBridge. SAME-ORIGIN content gets a
//      real DOM <iframe> layered over the Godot canvas with a slim title
//      bar (title, open-in-new-tab, close); CROSS-ORIGIN content opens in
//      a NEW TAB instead — browsers block third-party cookies inside
//      cross-origin iframes, which breaks session-based apps (a framed
//      BigBlueButton loads but cannot authenticate: "Oops, something went
//      wrong"). Both are pure DOM: closing never crosses back into the VM.
//      Because the tab must be opened inside a user gesture to escape
//      popup blockers, a tap handler that fetches the URL ASYNCHRONOUSLY
//      calls VUI.webviewPrepare() first (synchronously, in the gesture) to
//      reserve the tab; VUI.webview() then navigates it when the URL
//      arrives, and VUI.cancelWebviewPrepare() discards it on error.
//      `prefer: "overlay" | "tab" | "auto"` (default auto = by origin)
//      overrides the choice.
//   2. ANDROID — the `ElpianWebView` Godot plugin (bridge/android/webview),
//      which overlays the platform's system WebView (Chromium) with the same
//      title bar and grants camera/microphone to the page once the app holds
//      the runtime permissions.
//   3. DESKTOP — the `WebView` Control from the godot_wry GDExtension
//      (WebView2 on Windows, WKWebView on macOS, WebKitGTK on Linux —
//      the OS webview, a few MB of glue), mounted full-screen on the app
//      overlay under a VUI title bar. Present only when the export bundles
//      the addon (bridge/tools/fetch-godot-wry.sh).
//   4. Anything else — the system browser via OS.shell_open.
//
// It is the intended surface for embedded web content the engine cannot
// render itself: video-conference rooms (BigBlueButton/Jitsi), payment
// pages, OAuth flows, docs. Each in-app surface carries the media
// permissions (camera, microphone, fullscreen) conferencing frontends
// require — subject to the platform webview's own WebRTC support.
//
//   VUI.webview({ url: "https://…", title: "My room", prefer: "auto" })
//     -> "webview" (DOM iframe) | "tab" (browser tab, web export)
//      | "native" (Android/desktop webview) | "browser" (OS browser)
//      | "" (nothing could open)
//   VUI.webviewOpenDeferred({ fetchUrl, jsonField, title, failMessage })
//     -> web only, call INSIDE the tap: opens a tab that fetches the JSON
//        endpoint itself and navigates to jsonField's value — the pattern
//        for destination URLs that arrive asynchronously ("tab" | "").
//        Preferred over prepare+webview: the app tab is throttled to a
//        halt the moment the new tab takes focus, so an app-side fetch
//        can never finish; the self-resolving tab does not care.
//   VUI.webviewPrepare()   -> web only: reserve a tab NOW (call in the tap)
//   VUI.cancelWebviewPrepare() -> discard an unused reserved tab
//   VUI.closeWebview()  -> closes an open in-app surface (any kind)

function __vuiJsBridgeEval(code) {
  // Returns the eval result as a string, or null when there is no working
  // JavaScriptBridge (non-web platform, headless test, mock engine).
  try {
    let js = GD.singleton("JavaScriptBridge");
    let r = js.call("eval", [code]);
    if (r == null || GD.isError(r)) { return null; }
    return "" + r;
  } catch (e) { return null; }
}

// Reserve a browser tab NOW, while still inside the user gesture, so a later
// VUI.webview (after an async URL fetch) can navigate it without tripping the
// popup blocker. No-op off the web export. The placeholder shows a minimal
// "Opening…" page so the blank tab explains itself.
VUI.webviewPrepare = () => {
  let r = __vuiJsBridgeEval(
    "(function(){try{" +
    "if(window.__vuiPendingTab&&!window.__vuiPendingTab.closed){return 1;}" +
    "var w=window.open('about:blank','_blank');if(!w){return 0;}" +
    "window.__vuiPendingTab=w;" +
    "try{var d=w.document;d.title='Opening\\u2026';" +
    "d.body.style.cssText='background:#0b0b10;color:#fff;font:16px system-ui,sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;';" +
    "d.body.textContent='Opening\\u2026';}catch(e){}" +
    "return 1;}catch(e){return 0;}})()");
  return r != null && r == "1";
};

// Discard a reserved-but-unused tab (call on the error path of the fetch).
VUI.cancelWebviewPrepare = () => {
  let r = __vuiJsBridgeEval(
    "(function(){var w=window.__vuiPendingTab;window.__vuiPendingTab=null;" +
    "if(w&&!w.closed){try{w.close();}catch(e){}return 1;}return 0;})()");
  return r != null && r == "1";
};

// Open a SELF-RESOLVING tab, synchronously inside the tap gesture: the tab
// fetches `fetchUrl` (a same-origin JSON endpoint) browser-side and navigates
// itself to the value of `jsonField`. This is the right shape whenever the
// destination URL must be fetched AFTER the tap, because the reserve-then-
// navigate pattern deadlocks on the web export: opening a tab backgrounds the
// Godot page, whose main loop the browser throttles to a halt — the app-side
// fetch never completes and the reserved tab waits forever (and the app looks
// frozen). Here the tab needs nothing further from the app.
//
// On failure the tab shows `failMessage` plus the endpoint's message/
// warnings. Returns "tab" when the tab launched, "" otherwise (non-web
// surface, popup blocked) — callers then fall back to the async
// fetch + VUI.webview flow, which is fine off the web (native surfaces and
// shell_open need no user-gesture tab).
VUI.webviewOpenDeferred = (o) => {
  o = o ?? {};
  let fetchUrl = "" + (o.fetchUrl ?? "");
  if (fetchUrl == "") { return ""; }
  let jsonField = "" + (o.jsonField ?? "url");
  let title = "" + (o.title ?? "Opening…");
  let failMsg = "" + (o.failMessage ?? "Could not open");
  // The tab's config rides direct property assignment on the child window —
  // the injected <script> below is a CONSTANT string, so nothing user-
  // supplied is ever spliced into markup.
  let code = "(function(){try{" +
    "var w=window.open('about:blank','_blank');if(!w){return 0;}" +
    "w.__vuiCfg={u:" + JSON.stringify(fetchUrl) + ",f:" + JSON.stringify(jsonField) +
    ",t:" + JSON.stringify(title) + ",e:" + JSON.stringify(failMsg) + "};" +
    "var d=w.document;d.open();" +
    "d.write('<!doctype html><html><head><meta charset=\"utf-8\"></head>" +
    "<body style=\"background:#0b0b10;color:#fff;font:16px system-ui,sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;\">" +
    "<div id=\"m\">Opening\\u2026</div>" +
    "<scr'+'ipt>(function(){var c=window.__vuiCfg||{};document.title=c.t||\"Opening\";" +
    "function fail(m){document.getElementById(\"m\").textContent=(c.e||\"Failed\")+(m?(\": \"+m):\"\");}" +
    "fetch(c.u,{headers:{Accept:\"application/json\"}}).then(function(r){return r.json();}).then(function(j){" +
    "var u=j&&j[c.f];if(u){location.replace(u);return;}" +
    "var m=(j&&(j.message||j.error))||\"\";" +
    "if(!m&&j&&j.warnings&&j.warnings.length&&j.warnings[0].message){m=j.warnings[0].message;}" +
    "fail(m);}).catch(function(err){fail(\"\"+err);});})();</scr'+'ipt></body></html>');" +
    "d.close();return 1;}catch(e){return 0;}})()";
  let r = __vuiJsBridgeEval(code);
  if (r != null && r == "1") { return "tab"; }
  return "";
};

// Open native surface, if any (Android plugin overlay / desktop WebView node).
var __vuiWebviewNative = { node: null, android: false };

function __vuiEngineHasSingleton(name) {
  try {
    let e = GD.singleton("Engine");
    let r = e.call("has_singleton", [name]);
    return r == true;
  } catch (err) { return false; }
}

function __vuiClassExists(cls) {
  try {
    let cdb = GD.singleton("ClassDB");
    let r = cdb.call("class_exists", [cls]);
    return r == true;
  } catch (err) { return false; }
}

// Android: the ElpianWebView Godot plugin overlays the system WebView on top
// of the game activity (title bar + close handled natively, like the DOM
// path — closing never needs to cross back into the VM).
function __vuiOpenAndroidWebview(url, title) {
  if (!__vuiEngineHasSingleton("ElpianWebView")) { return false; }
  try {
    let p = GD.singleton("ElpianWebView");
    let r = p.call("open", [url, title]);
    if (GD.isError(r)) { return false; }
    __vuiWebviewNative.android = true;
    return true;
  } catch (err) { return false; }
}

// Desktop: godot_wry's `WebView` Control (the OS-native webview). The native
// view renders on top of the canvas inside its rect, so the VUI title bar
// lives ABOVE it in a column and stays visible/clickable.
function __vuiOpenWryWebview(url, title) {
  if (!__vuiClassExists("WebView")) { return false; }
  if (__vuiApp.overlay == null) { return false; }
  let view = null;
  try { view = GD.create("WebView"); } catch (err) { return false; }
  if (view == null || GD.isError(view)) { return false; }
  VUI.closeWebview(); // at most one in-app surface at a time
  let t = VUI.theme();
  view.set("full_window_size", false); // respect the Control rect, not the window
  view.set("autoplay", true);          // conference audio/video without a click
  view.set("focused_when_created", true);
  view.set("url", url);
  let bar = VUI.panel({ bg: t.surfaceContainer, radius: 0, pad: 10, child: VUI.row({ gap: 10, children: [
    VUI.expand(VUI.text("" + title, { size: t.fontM, weight: "medium" })),
    VUI.button("Open in browser", { kind: "tonal", onTap: () => {
      try { GD.singleton("OS").call("shell_open", [url]); } catch (e) { }
    } }),
    VUI.button("Close", { kind: "filled", onTap: () => { VUI.closeWebview(); } }),
  ] }) });
  let col = VUI.column({ gap: 0, expand: true, children: [bar, VUI.expand(view)] });
  let holder = GD.create("PanelContainer");
  holder.set("theme_override_styles/panel", VUI.styleBox({ bg: t.surface, radius: 0 }));
  __vuiFullRect(holder);
  holder.call("add_child", [col]);
  __vuiApp.overlay.call("add_child", [holder]);
  __vuiWebviewNative.node = holder;
  return true;
}

VUI.webview = (o) => {
  o = o ?? {};
  let url = "" + (o.url ?? "");
  if (url == "") { return ""; }
  let title = "" + (o.title ?? url);
  let prefer = "" + (o.prefer ?? "auto"); // "auto" | "tab" | "overlay"
  if (prefer != "tab" && prefer != "overlay") { prefer = "auto"; }
  // One self-contained browser-side snippet decides the web surface:
  //   returns 2 — opened in a tab (cross-origin content: third-party-cookie
  //               blocking breaks session apps like BigBlueButton inside a
  //               cross-origin iframe, so those get a top-level tab, using
  //               the gesture-reserved __vuiPendingTab when present);
  //   returns 1 — DOM <iframe> overlay (same-origin content, an explicit
  //               prefer:"overlay", or a popup-blocked tab fallback);
  //   returns 0 — no DOM to work with.
  // The overlay is built with createElement (no innerHTML) and idempotent:
  // reopening replaces any previous overlay.
  let code = "(function(){" +
    "var u=" + JSON.stringify(url) + ",t=" + JSON.stringify(title) + ",m=" + JSON.stringify(prefer) + ";" +
    "if(!document||!document.body){return 0;}" +
    "var wantTab=(m==='tab');" +
    "if(m==='auto'){try{wantTab=(new URL(u,location.href)).origin!==location.origin;}catch(e){}}" +
    "if(wantTab){" +
    "var p=window.__vuiPendingTab;window.__vuiPendingTab=null;" +
    "if(p&&!p.closed){try{p.location.replace(u);p.focus();return 2;}catch(e){try{p.close();}catch(e2){}}}" +
    "var nw=window.open(u,'_blank');if(nw){return 2;}" +
    "}" +
    "var old=document.getElementById('vui-webview');if(old){old.parentNode.removeChild(old);}" +
    "var w=document.createElement('div');w.id='vui-webview';" +
    "w.style.cssText='position:fixed;top:0;left:0;right:0;bottom:0;z-index:2147483000;display:flex;flex-direction:column;background:#0b0b10;';" +
    "var b=document.createElement('div');" +
    "b.style.cssText='height:46px;display:flex;align-items:center;gap:10px;padding:0 12px;background:#15151d;color:#fff;font:500 14px system-ui,sans-serif;flex:none;';" +
    "var s=document.createElement('span');s.textContent=t;" +
    "s.style.cssText='flex:1;overflow:hidden;white-space:nowrap;text-overflow:ellipsis;';" +
    "var a=document.createElement('a');a.textContent='Open in new tab';a.href=u;a.target='_blank';a.rel='noopener';" +
    "a.style.cssText='color:#9aa4ff;text-decoration:none;font-size:13px;flex:none;';" +
    "var x=document.createElement('button');x.textContent='\\u2715 Close';" +
    "x.style.cssText='flex:none;border:0;border-radius:8px;padding:8px 14px;background:#343446;color:#fff;font:500 13px system-ui,sans-serif;cursor:pointer;';" +
    "x.onclick=function(){w.parentNode.removeChild(w);};" +
    "var f=document.createElement('iframe');f.src=u;" +
    "f.allow='camera; microphone; display-capture; fullscreen; autoplay; clipboard-write; speaker-selection';" +
    "f.setAttribute('allowfullscreen','');" +
    "f.style.cssText='flex:1;width:100%;border:0;background:#fff;';" +
    "b.appendChild(s);b.appendChild(a);b.appendChild(x);w.appendChild(b);w.appendChild(f);" +
    "document.body.appendChild(w);return 1;})()";
  let r = __vuiJsBridgeEval(code);
  if (r != null && r == "2") { return "tab"; }
  if (r != null && r == "1") { return "webview"; }
  // Not the web export: try the OS-native in-app webviews.
  if (__vuiOpenAndroidWebview(url, title)) { return "native"; }
  if (__vuiOpenWryWebview(url, title)) { return "native"; }
  // No in-app surface available: hand the URL to the platform browser.
  try {
    let os = GD.singleton("OS");
    let res = os.call("shell_open", [url]);
    if (!GD.isError(res)) { return "browser"; }
  } catch (e) { }
  return "";
};

VUI.closeWebview = () => {
  let closed = false;
  let r = __vuiJsBridgeEval(
    "(function(){var w=document.getElementById('vui-webview');" +
    "if(w){w.parentNode.removeChild(w);return 1;}return 0;})()");
  if (r != null && r == "1") { closed = true; }
  if (__vuiWebviewNative.android == true) {
    try {
      let p = GD.singleton("ElpianWebView");
      let res = p.call("close", []);
      if (res == true) { closed = true; }
    } catch (e) { }
    __vuiWebviewNative.android = false;
  }
  if (__vuiWebviewNative.node != null) {
    try { __vuiWebviewNative.node.queueFree(); closed = true; } catch (e) { }
    __vuiWebviewNative.node = null;
  }
  return closed;
};

// ===========================================================================
// VUI canvas — a Flutter-CustomPainter-equivalent drawing surface, NATIVE.
// ===========================================================================
//
// Renders via `RenderingServer.canvas_item_add_*` on a Control's canvas-item
// RID. Those commands are RETAINED and can be issued at ANY time (unlike
// `CanvasItem.draw_*`, which only work inside the draw phase, and the bridged
// `draw` signal, which is delivered deferred) — so the guest can (re)paint
// whenever it likes. The `VuiCanvas` object MIRRORS the `FLCanvas` method
// surface (drawArc/drawCircle/drawLine/drawRect/drawRRect/drawOval/drawPath/
// save/translate/rotate/scale/restore/drawParagraph/…), so a single painter
// function works unchanged on both the real-Flutter path and this native path.
// Geometry matches FL: Offset = [x,y]; Rect = [l,t,r,b]; Color = [r,g,b,a].

var __vuiCanvasPaint = {}; // node.id -> repaint closure (for animation)
var __vuiRS = null;
function __vuiRenderingServer() {
  if (__vuiRS == null) {
    __vuiRS = GD.singleton("RenderingServer");
  }
  return __vuiRS;
}

function __vuiV2(a) {
  return new Vector2(a[0], a[1]);
}
function __vuiPaintColor(paint, def) {
  if (paint == null) {
    return def;
  }
  let c = paint.color;
  if (c == null) {
    return def;
  }
  if (__isType(c, "list")) {
    return new Color(c[0], c[1], c[2], c.length > 3 ? c[3] : 1.0);
  }
  return def;
}
function __vuiPaintStroke(paint) {
  return paint != null && paint.style == "stroke";
}
function __vuiPaintWidth(paint) {
  return paint != null && paint.strokeWidth != null ? paint.strokeWidth : 1.0;
}

// 2D transform helpers (Transform2D = [xx, xy, yx, yy, ox, oy]).
function __vuiTId() { return [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]; }
function __vuiTMul(a, b) {
  return [
    a[0] * b[0] + a[2] * b[1],
    a[1] * b[0] + a[3] * b[1],
    a[0] * b[2] + a[2] * b[3],
    a[1] * b[2] + a[3] * b[3],
    a[0] * b[4] + a[2] * b[5] + a[4],
    a[1] * b[4] + a[3] * b[5] + a[5],
  ];
}

// Sample an arc/ellipse into a flat [x,y,x,y,…] point list.
function __vuiArcPts(cx, cy, rx, ry, start, sweep, includeCenter) {
  let steps = sweep < 0 ? -sweep : sweep;
  let n = steps / 0.18;
  n = n < 8 ? 8 : (n > 128 ? 128 : (n - n % 1.0));
  let pts = [];
  if (includeCenter) {
    pts.push(cx);
    pts.push(cy);
  }
  for (let i = 0; i <= n; i++) {
    let a = start + sweep * (i / n);
    pts.push(cx + cos(a) * rx);
    pts.push(cy + sin(a) * ry);
  }
  return pts;
}

class VuiCanvas {
  constructor(node) {
    this.node = node;
    this.item = node.call("get_canvas_item");
    this.rs = __vuiRenderingServer();
    this._stack = [];
    this._x = __vuiTId();
  }

  clear() {
    this.rs.call("canvas_item_clear", [this.item]);
    this._stack = [];
    this._x = __vuiTId();
  }

  // ---- transform stack ----
  _apply() {
    this.rs.call("canvas_item_add_set_transform", [this.item, new Transform2D(this._x)]);
  }
  save() { this._stack.push(this._x); }
  saveLayer(rect, paint) { this._stack.push(this._x); }
  restore() {
    if (this._stack.length > 0) {
      this._x = this._stack.pop();
    }
    this._apply();
  }
  translate(dx, dy) { this._x = __vuiTMul(this._x, [1.0, 0.0, 0.0, 1.0, dx, dy]); this._apply(); }
  rotate(a) { let c = cos(a); let s = sin(a); this._x = __vuiTMul(this._x, [c, s, -s, c, 0.0, 0.0]); this._apply(); }
  scale(sx, sy) { this._x = __vuiTMul(this._x, [sx, 0.0, 0.0, sy == null ? sx : sy, 0.0, 0.0]); this._apply(); }
  transform(m16) { /* 4x4 not supported in 2D canvas; ignore z/w */ }
  clipRect(rect, opts) { /* per-command clipping is unavailable in RS immediate mode */ }
  clipRRect(rrect, aa) {}
  clipPath(path, aa) {}

  // ---- polyline / polygon helpers ----
  _stroke(flatPts, color, width, closed) {
    let pts = flatPts;
    if (closed && pts.length >= 4) {
      pts = pts.slice(0);
      pts.push(pts[0]);
      pts.push(pts[1]);
    }
    this.rs.call("canvas_item_add_polyline", [
      this.item, Packed.vector2s(pts), Packed.colors([color.r, color.g, color.b, color.a]),
      width, true,
    ]);
  }
  _fill(flatPts, color) {
    this.rs.call("canvas_item_add_polygon", [
      this.item, Packed.vector2s(flatPts), Packed.colors([color.r, color.g, color.b, color.a]),
    ]);
  }

  // ---- draws ----
  drawColor(color, blend) {
    let sz = this.node.get("size");
    let col = __isType(color, "list") ? new Color(color[0], color[1], color[2], color.length > 3 ? color[3] : 1.0) : color;
    this.rs.call("canvas_item_add_rect", [this.item, new Rect2(0.0, 0.0, sz.x, sz.y), col]);
  }
  drawPaint(paint) {
    let sz = this.node.get("size");
    this.rs.call("canvas_item_add_rect", [this.item, new Rect2(0.0, 0.0, sz.x, sz.y), __vuiPaintColor(paint, new Color(0, 0, 0, 1))]);
  }
  drawLine(p1, p2, paint) {
    this.rs.call("canvas_item_add_line", [this.item, __vuiV2(p1), __vuiV2(p2), __vuiPaintColor(paint, new Color(1, 1, 1, 1)), __vuiPaintWidth(paint), true]);
  }
  drawRect(rect, paint) {
    let col = __vuiPaintColor(paint, new Color(1, 1, 1, 1));
    let l = rect[0]; let t = rect[1]; let r = rect[2]; let b = rect[3];
    if (__vuiPaintStroke(paint)) {
      this._stroke([l, t, r, t, r, b, l, b], col, __vuiPaintWidth(paint), true);
    } else {
      this.rs.call("canvas_item_add_rect", [this.item, new Rect2(l, t, r - l, b - t), col]);
    }
  }
  drawRRect(rrect, paint) {
    let rect = rrect.rect;
    let rad = rrect.radius == null ? 0.0 : rrect.radius;
    let l = rect[0]; let t = rect[1]; let r = rect[2]; let b = rect[3];
    let pts = [];
    let push = (cx, cy, a0, a1) => {
      let arc = __vuiArcPts(cx, cy, rad, rad, a0, a1 - a0, false);
      for (let i = 0; i < arc.length; i++) { pts.push(arc[i]); }
    };
    let HALF = 3.14159265358979 * 0.5;
    push(r - rad, t + rad, -HALF, 0.0);
    push(r - rad, b - rad, 0.0, HALF);
    push(l + rad, b - rad, HALF, 3.14159265358979);
    push(l + rad, t + rad, 3.14159265358979, 3.14159265358979 + HALF);
    let col = __vuiPaintColor(paint, new Color(1, 1, 1, 1));
    if (__vuiPaintStroke(paint)) { this._stroke(pts, col, __vuiPaintWidth(paint), true); } else { this._fill(pts, col); }
  }
  drawOval(rect, paint) {
    let cx = (rect[0] + rect[2]) * 0.5; let cy = (rect[1] + rect[3]) * 0.5;
    let rx = (rect[2] - rect[0]) * 0.5; let ry = (rect[3] - rect[1]) * 0.5;
    let pts = __vuiArcPts(cx, cy, rx, ry, 0.0, 6.28318530718, false);
    let col = __vuiPaintColor(paint, new Color(1, 1, 1, 1));
    if (__vuiPaintStroke(paint)) { this._stroke(pts, col, __vuiPaintWidth(paint), false); } else { this._fill(pts, col); }
  }
  drawCircle(cx, cy, radius, paint) {
    let col = __vuiPaintColor(paint, new Color(1, 1, 1, 1));
    if (__vuiPaintStroke(paint)) {
      this._stroke(__vuiArcPts(cx, cy, radius, radius, 0.0, 6.28318530718, false), col, __vuiPaintWidth(paint), false);
    } else {
      this.rs.call("canvas_item_add_circle", [this.item, new Vector2(cx, cy), radius, col]);
    }
  }
  drawArc(rect, start, sweep, useCenter, paint) {
    let cx = (rect[0] + rect[2]) * 0.5; let cy = (rect[1] + rect[3]) * 0.5;
    let rx = (rect[2] - rect[0]) * 0.5; let ry = (rect[3] - rect[1]) * 0.5;
    let col = __vuiPaintColor(paint, new Color(1, 1, 1, 1));
    if (__vuiPaintStroke(paint)) {
      this._stroke(__vuiArcPts(cx, cy, rx, ry, start, sweep, false), col, __vuiPaintWidth(paint), false);
    } else {
      this._fill(__vuiArcPts(cx, cy, rx, ry, start, sweep, useCenter == true), col);
    }
  }
  drawPath(path, paint) {
    let verbs = (path != null && path.verbs != null) ? path.verbs : [];
    let col = __vuiPaintColor(paint, new Color(1, 1, 1, 1));
    let stroke = __vuiPaintStroke(paint);
    let w = __vuiPaintWidth(paint);
    let sub = [];
    let cx = 0.0; let cy = 0.0;
    let flush = (closed) => {
      if (sub.length >= 4) { if (stroke) { this._stroke(sub, col, w, closed); } else { this._fill(sub, col); } }
      sub = [];
    };
    for (let i = 0; i < verbs.length; i++) {
      let v = verbs[i];
      let k = v[0];
      if (k == "moveTo") { flush(false); cx = v[1]; cy = v[2]; sub.push(cx); sub.push(cy); }
      else if (k == "lineTo") { cx = v[1]; cy = v[2]; sub.push(cx); sub.push(cy); }
      else if (k == "quadTo") {
        let x1 = v[1]; let y1 = v[2]; let x2 = v[3]; let y2 = v[4];
        for (let s = 1; s <= 12; s++) { let tt = s / 12.0; let u = 1.0 - tt;
          sub.push(u * u * cx + 2 * u * tt * x1 + tt * tt * x2);
          sub.push(u * u * cy + 2 * u * tt * y1 + tt * tt * y2); }
        cx = x2; cy = y2;
      }
      else if (k == "cubicTo") {
        let x1 = v[1]; let y1 = v[2]; let x2 = v[3]; let y2 = v[4]; let x3 = v[5]; let y3 = v[6];
        for (let s = 1; s <= 16; s++) { let tt = s / 16.0; let u = 1.0 - tt;
          sub.push(u*u*u*cx + 3*u*u*tt*x1 + 3*u*tt*tt*x2 + tt*tt*tt*x3);
          sub.push(u*u*u*cy + 3*u*u*tt*y1 + 3*u*tt*tt*y2 + tt*tt*tt*y3); }
        cx = x3; cy = y3;
      }
      else if (k == "addRect") { let r = v[1]; this.drawRect(r, paint); }
      else if (k == "addOval") { this.drawOval(v[1], paint); }
      else if (k == "close") { flush(true); }
    }
    flush(false);
  }
  drawParagraph(para, dx, dy) {
    let m = para == null ? {} : para;
    let style = m.style == null ? {} : m.style;
    let size = style.size == null ? 16.0 : style.size;
    let col = style.color != null && __isType(style.color, "list")
      ? new Color(style.color[0], style.color[1], style.color[2], style.color.length > 3 ? style.color[3] : 1.0)
      : new Color(1, 1, 1, 1);
    let font = this.node.call("get_theme_default_font");
    if (font != null && !GD.isError(font)) {
      // pos.y is the baseline; nudge down by the font size for top-anchored text.
      font.call("draw_string", [this.item, new Vector2(dx, dy + size), "" + (m.text == null ? "" : m.text), GInt(1), GFloat(m.maxWidth == null ? -1.0 : m.maxWidth), GInt(size), col]);
    }
  }
  drawPoints(mode, points, paint) {
    let col = __vuiPaintColor(paint, new Color(1, 1, 1, 1));
    let w = __vuiPaintWidth(paint);
    for (let i = 0; i < points.length; i++) {
      this.rs.call("canvas_item_add_circle", [this.item, __vuiV2(points[i]), w * 0.6, col]);
    }
  }
  drawShadow(path, color, elevation, occ) { /* soft shadow omitted in the native path */ }
}

// VUI.canvas({ size:[w,h], paint: (cv)=>{…}, expand }) -> a Control that paints
// `paint` via VuiCanvas. Repaint (for animation) with VUI.repaint(node).
VUI.canvas = (o) => {
  o = o ?? {};
  let node = GD.create("Control");
  let w = o.size != null ? o.size[0] : 100.0;
  let h = o.size != null ? o.size[1] : 100.0;
  __vuiMinSize(node, w, h);
  node.set("mouse_filter", GInt(o.interactive == true ? 0 : 2));
  if (o.expand == true) { __vuiExpandH(node); }
  let cv = new VuiCanvas(node);
  let painter = o.paint;
  __vuiCanvasPaint["c" + node.id] = () => {
    cv.clear();
    if (painter != null) { painter(cv); }
  };
  __vuiCanvasPaint["c" + node.id]();
  return node;
};

// Re-run a VUI.canvas node's painter (call from a per-frame handler to animate).
VUI.repaint = (node) => {
  if (node == null) { return; }
  let f = __vuiCanvasPaint["c" + node.id];
  if (f != null) { f(); }
};

// ===========================================================================
// VUI gestures — the Flutter event surface on a Godot Control.
// ===========================================================================
//
// Wraps `child` in a Control that STOPs for input and translates Godot's
// `gui_input` / `mouse_entered` / `mouse_exited` into the Flutter callback
// vocabulary, each firing with a details object:
//   onTapDown/onTapUp/onTap · onSecondaryTap · onDoubleTap · onLongPress
//   onPanStart/onPanUpdate({dx,dy,x,y})/onPanEnd · onEnter/onExit/onHover({x,y})
//   onScroll({dy}) (mouse wheel). Works with mouse AND touch.
VUI.gestures = (child, handlers) => {
  handlers = handlers ?? {};
  let box = GD.create("Control");
  box.set("mouse_filter", GInt(0)); // STOP: receive input
  if (child != null) {
    __vuiFullRect(child);
    box.call("add_child", [child]);
  }
  let st = { down: false, sx: 0.0, sy: 0.0, moved: false, taps: 0, longTimer: null };
  let fire = (name, detail) => { let h = handlers[name]; if (h != null) { h(detail == null ? {} : detail); } };

  box.connect("gui_input", (ev) => {
    let mb = ev.call("is_class", ["InputEventMouseButton"]);
    let mm = ev.call("is_class", ["InputEventMouseMotion"]);
    let st_touch = ev.call("is_class", ["InputEventScreenTouch"]);
    let sd = ev.call("is_class", ["InputEventScreenDrag"]);
    if (mb == true || st_touch == true) {
      let pressed = ev.get("pressed");
      let pos = ev.get("position");
      let btn = mb == true ? ev.get("button_index") : 1;
      if (mb == true && (btn == 4 || btn == 5)) {
        // wheel up/down
        if (pressed == true) { fire("onScroll", { dy: btn == 5 ? 1.0 : -1.0 }); }
        return;
      }
      if (pressed == true) {
        st.down = true; st.moved = false; st.sx = pos.x; st.sy = pos.y;
        fire("onTapDown", { x: pos.x, y: pos.y });
        fire("onPanStart", { x: pos.x, y: pos.y });
        if (handlers.onLongPress != null) {
          st.longTimer = GTimer.after(500, () => { if (st.down && !st.moved) { fire("onLongPress", { x: pos.x, y: pos.y }); } });
        }
      } else {
        st.down = false;
        fire("onTapUp", { x: pos.x, y: pos.y });
        fire("onPanEnd", { x: pos.x, y: pos.y });
        if (!st.moved) {
          if (mb == true && btn == 2) { fire("onSecondaryTap", { x: pos.x, y: pos.y }); }
          else {
            fire("onTap", { x: pos.x, y: pos.y });
            st.taps = st.taps + 1;
            let mine = st.taps;
            GTimer.after(260, () => { if (st.taps == mine) { st.taps = 0; } });
            if (st.taps >= 2) { st.taps = 0; fire("onDoubleTap", { x: pos.x, y: pos.y }); }
          }
        }
      }
    } else if (mm == true || sd == true) {
      let rel = ev.get("relative");
      let pos = ev.get("position");
      if (st.down) {
        if (rel.x > 1.5 || rel.x < -1.5 || rel.y > 1.5 || rel.y < -1.5) { st.moved = true; }
        fire("onPanUpdate", { dx: rel.x, dy: rel.y, x: pos.x, y: pos.y });
      } else {
        fire("onHover", { x: pos.x, y: pos.y });
      }
    }
  });
  box.connect("mouse_entered", () => fire("onEnter", {}));
  box.connect("mouse_exited", () => fire("onExit", {}));
  return box;
};

// ===========================================================================
// A few more Flutter-parity layout widgets (thin over Godot containers).
// ===========================================================================

// Absolute-positioning stack (Flutter Stack). Children can be VUI.positioned.
VUI.stack = (o) => {
  o = o ?? {};
  let c = GD.create("Control");
  c.set("mouse_filter", GInt(2));
  let kids = o.children ?? [];
  for (let i = 0; i < kids.length; i++) { c.call("add_child", [__vuiNodeOf(kids[i])]); }
  return c;
};
// Position a child within a VUI.stack via anchors/offsets (Flutter Positioned).
VUI.positioned = (o) => {
  o = o ?? {};
  let n = __vuiNodeOf(o.child);
  // left/top/right/bottom in px from the corresponding edges.
  if (o.left != null) { n.set("anchor_left", GFloat(0.0)); n.set("offset_left", GFloat(__vuiPx(o.left))); }
  if (o.top != null) { n.set("anchor_top", GFloat(0.0)); n.set("offset_top", GFloat(__vuiPx(o.top))); }
  if (o.right != null) { n.set("anchor_right", GFloat(1.0)); n.set("offset_right", GFloat(-__vuiPx(o.right))); }
  if (o.bottom != null) { n.set("anchor_bottom", GFloat(1.0)); n.set("offset_bottom", GFloat(-__vuiPx(o.bottom))); }
  if (o.width != null) { n.set("offset_right", GFloat((o.left != null ? __vuiPx(o.left) : 0.0) + __vuiPx(o.width))); }
  if (o.height != null) { n.set("offset_bottom", GFloat((o.top != null ? __vuiPx(o.top) : 0.0) + __vuiPx(o.height))); }
  return n;
};
VUI.align = (o) => {
  o = o ?? {};
  let c = GD.create("Control");
  c.set("mouse_filter", GInt(2));
  __vuiFullRect(c);
  let child = __vuiNodeOf(o.child);
  c.call("add_child", [child]);
  // alignment [-1..1] mapped to Godot anchors; default center.
  let ax = o.alignment != null ? (o.alignment[0] + 1.0) * 0.5 : 0.5;
  let ay = o.alignment != null ? (o.alignment[1] + 1.0) * 0.5 : 0.5;
  child.set("anchor_left", GFloat(ax)); child.set("anchor_top", GFloat(ay));
  child.set("anchor_right", GFloat(ax)); child.set("anchor_bottom", GFloat(ay));
  return c;
};
VUI.aspectRatio = (o) => {
  o = o ?? {};
  let c = GD.create("AspectRatioContainer");
  c.set("ratio", GFloat(__vuiNum(o.ratio, 1.0)));
  if (o.child != null) { c.call("add_child", [__vuiNodeOf(o.child)]); }
  return c;
};
VUI.wrap = (o) => {
  o = o ?? {};
  let c = GD.create("FlowContainer");
  c.set("theme_override_constants/h_separation", GInt(__vuiPx(__vuiNum(o.spacing, 8))));
  c.set("theme_override_constants/v_separation", GInt(__vuiPx(__vuiNum(o.runSpacing, 8))));
  let kids = o.children ?? [];
  for (let i = 0; i < kids.length; i++) { c.call("add_child", [__vuiNodeOf(kids[i])]); }
  return c;
};
VUI.image = (o) => {
  o = o ?? {};
  let tr = GD.create("TextureRect");
  if (o.texture != null) { tr.set("texture", o.texture); }
  tr.set("expand_mode", GInt(1)); // IGNORE_SIZE
  tr.set("stretch_mode", GInt(o.cover == true ? 6 : 5)); // KEEP_ASPECT_COVERED / KEEP_ASPECT_CENTERED
  __vuiMinSize(tr, __vuiNum(o.width, 0.0), __vuiNum(o.height, 0.0));
  return tr;
};

// Resolve a value that is already a node (GObj) or a VUI descriptor to a node.
function __vuiNodeOf(x) {
  if (x == null) { return GD.create("Control"); }
  return __vuiNode(x);
}
// =============================================================================
// §4  Reactive core — VReact
// =============================================================================

// =============================================================================
// react.js — VReact: a React-compatible runtime for the Victor engine.
// =============================================================================
//
// The third guest library in the stack. Composed AFTER `godot.js` (the engine
// bridge) and `ui.js` (the VUI widget kit), it turns the Elpian VM into a
// React renderer whose "DOM" is the retained Godot scene graph:
//
//     import 'godot.js';
//     import 'ui.js';
//     import 'react.js';
//
//     function Counter(props) {
//       let s = useState(0);
//       let n = s[0]; let set = s[1];
//       return _jsxs("column", { gap: 16, children: [
//         _jsx("heading", { children: "Count: " + n }),
//         _jsx("button", { onPress: () => { set(n + 1); }, children: "Increment" }),
//       ]});
//     }
//     VictorClient.mountApp(_jsx(Counter, {}), { portrait: true });
//
// A developer never writes those `_jsx(...)` calls by hand: they author an
// ordinary Next.js + React project (JSX, hooks, components) and the Victor
// toolchain (`templates/victor-nextjs/tools/build.mjs`) transpiles the JSX with
// Babel's automatic runtime and flattens the modules into the single-file guest
// program the composer expects. This file is the runtime those programs call
// into. It is authored entirely in the `js2elpian` subset — so, like `ui.js`,
// it is user-space code with no privileged access.
//
// ## What it is (and is not)
//
// VReact is a faithful, from-scratch reimplementation of React's *programming
// model* — element factory, function components, the full hook surface, and a
// keyed reconciler that mutates retained host nodes — NOT a port of Facebook's
// `react` + `react-reconciler` packages. Those packages cannot run here: they
// rely on `Object.assign`, spread, generators, `Map`/`Set`, prototypes and a
// dozen other constructs the no-JIT Elpian bytecode subset does not model (see
// the subset chapter in `js2elpian/src/lib.rs`). VReact stands to React exactly
// as Preact does: same public API and semantics, an independent, tiny core.
// A component written against VReact IS ordinary React — the hook rules, the
// deps arrays, the reconciliation guarantees all hold.
//
// ## The rendering model
//
// React's host config here targets Godot `Control` nodes instead of the DOM.
// Every intrinsic element (`"column"`, `"text"`, `"button"`, `"input"`, …, plus
// the web aliases `"div"`, `"span"`, `"img"`, …) is a *host driver* that
// creates a real retained Godot node, patches its properties on update, and
// routes its signals back into event props. The reconciler diffs the element
// tree on each render and applies the minimal set of node mutations — Godot
// paints the retained scene; the VM only reacts. Event handlers are bound once
// through a stable indirection (the baked signal closure reads the *current*
// prop off the persistent instance), so re-renders never re-wire signals.
//
// ## The honest constraints of the subset (documented, not hidden)
//
//   * There is no first-class null: an absent value reads as 0 and `x == null`
//     is also true for a numeric 0. A literal numeric `0` therefore cannot be
//     rendered as a text child (React would render "0") — use `"" + n` or a
//     string. Every other value renders normally.
//   * Deps arrays are compared with `==` (the VM lowers `===` to it), i.e.
//     value identity for scalars and reference identity for objects — the same
//     contract as `Object.is` for the cases apps rely on.
//   * A single `<Context.Provider>` per context is supported app-wide; nesting
//     two providers of the *same* context with different values is not (the
//     value lives on the context object). Distinct contexts nest freely.
//
// Everything else — the hooks, keys, fragments, refs, effects and their
// cleanup ordering — behaves as you expect from React.

// ---------------------------------------------------------------------------
// element model
// ---------------------------------------------------------------------------

// A VReact element. Tagged so the reconciler can tell an element apart from an
// arbitrary props map or a plain value child.
var __VR_ELEMENT = "__vreact_element__";
var __VR_FRAGMENT = "__vreact_fragment__";
var __VR_PORTAL = "__vreact_portal__";

function __vrIsElement(x) {
  if (__isType(x, "map")) {
    return x[__VR_ELEMENT] == true;
  }
  return false;
}

// The JSX automatic-runtime entry points. Babel lowers `<tag .../>` to
// `_jsx(type, props, key)` and `<tag>{a}{b}</tag>` to `_jsxs(...)`; both land
// here. `children` already lives inside `props`, so there are no variadic
// arguments (which the subset could not express).
function jsx(type, props, key) {
  let p = props;
  if (p == null) {
    p = {};
  }
  return {
    __vreact_element__: true,
    type: type,
    props: p,
    key: key == null ? null : key,
    ref: p.ref == null ? null : p.ref,
  };
}

// `_jsxs` is `_jsx` with an array `children`; the reconciler flattens both, so
// they share one implementation.
function jsxs(type, props, key) {
  return jsx(type, props, key);
}

// Classic `React.createElement(type, props, childrenArray)` — provided for
// programmatic construction. The JSX transform uses the automatic runtime
// above; this variant takes children as a single array (no rest params).
function createElement(type, props, children) {
  let p = props;
  if (p == null) {
    p = {};
  }
  if (children != null) {
    p.children = children;
  }
  return jsx(type, p, p.key);
}

// Aliases Babel's automatic runtime references verbatim (it emits `_jsx`,
// `_jsxs`, `_jsxDEV`, `_Fragment`). Defining them as globals here means the
// stripped `import … from "react/jsx-runtime"` lines resolve to the runtime.
var _jsx = jsx;
var _jsxs = jsxs;
var _jsxDEV = jsx;
var Fragment = __VR_FRAGMENT;
var _Fragment = __VR_FRAGMENT;

// ---------------------------------------------------------------------------
// runtime state: current fiber, scheduler queues, effect queues
// ---------------------------------------------------------------------------

// The instance currently rendering (the hook dispatch target) and its hook
// cursor. React's "rules of hooks" hold because dispatch is index-based.
var __vrCur = null;
var __vrHookIndex = 0;

// Instances marked dirty by a setState/dispatch, drained on the next microtask.
var __vrDirty = [];
var __vrFlushScheduled = false;

// Effects whose deps changed this commit, run after the tree is mutated.
var __vrPendingEffects = [];
var __vrEffectsScheduled = false;

// Monotonic id source for useId().
var __vrIdSeq = 0;

// True while a commit is mutating the tree — setState during this phase is
// coalesced into the same flush rather than starting a nested one.
var __vrRendering = false;

// ---------------------------------------------------------------------------
// scheduling
// ---------------------------------------------------------------------------

function __vrScheduleUpdate(inst) {
  // Mark and enqueue once; the flush dedupes and skips instances whose
  // ancestor is already scheduled.
  if (inst.dirty == true) {
    return;
  }
  inst.dirty = true;
  __vrDirty.push(inst);
  if (!__vrFlushScheduled) {
    __vrFlushScheduled = true;
    __later(__vrFlush);
  }
}

function __vrFlush() {
  __vrFlushScheduled = false;
  // Drain the dirty set. setState inside a render re-enqueues, so loop until
  // the queue is empty (bounded in practice by the app's convergence).
  let guard = 0;
  while (__vrDirty.length > 0 && guard < 10000) {
    guard = guard + 1;
    let work = __vrDirty;
    __vrDirty = [];
    for (let i = 0; i < work.length; i++) {
      let inst = work[i];
      if (inst.dirty == true && inst.alive == true) {
        inst.dirty = false;
        __vrRerender(inst);
      } else {
        inst.dirty = false;
      }
    }
  }
  __vrScheduleEffects();
}

function __vrRerender(inst) {
  __vrRendering = true;
  __vrRenderComponent(inst);
  // A re-rendered component may have changed how many host nodes it produces;
  // re-sync the nearest host container so ordering/insertion stays correct.
  __vrSyncFrom(inst.hostContainer);
  __vrRendering = false;
}

// ---------------------------------------------------------------------------
// deps comparison (shared by useEffect / useMemo / useCallback / …)
// ---------------------------------------------------------------------------

function __vrDepsEqual(a, b) {
  // A null deps array means "no deps given" → always stale (re-run).
  if (a == null) {
    return false;
  }
  if (b == null) {
    return false;
  }
  if (a.length != b.length) {
    return false;
  }
  for (let i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

// ---------------------------------------------------------------------------
// hooks
// ---------------------------------------------------------------------------

function __vrHook(initialiser) {
  let inst = __vrCur;
  let idx = __vrHookIndex;
  __vrHookIndex = idx + 1;
  // Hooks are visited in a stable order, so a slot is new exactly when the
  // cursor reaches the end of the list. (An out-of-bounds array read does not
  // return null in the VM, so length — not a null check — is the reliable
  // "not yet created" test.)
  if (idx < inst.hooks.length) {
    return inst.hooks[idx];
  }
  let h = initialiser();
  inst.hooks.push(h);
  return h;
}

function useState(initial) {
  let inst = __vrCur;
  let make = () => {
    let v = initial;
    if (__isType(initial, "function")) {
      v = initial();
    }
    let hook = { state: v, setState: null };
    hook.setState = (next) => {
      let value = next;
      if (__isType(next, "function")) {
        value = next(hook.state);
      }
      if (hook.state != value) {
        hook.state = value;
        __vrScheduleUpdate(inst);
      }
    };
    return hook;
  };
  let h = __vrHook(make);
  let out = [];
  out.push(h.state);
  out.push(h.setState);
  return out;
}

function useReducer(reducer, initialArg, init) {
  let inst = __vrCur;
  let make = () => {
    let s = initialArg;
    if (init != null && __isType(init, "function")) {
      s = init(initialArg);
    }
    let hook = { state: s, dispatch: null };
    hook.dispatch = (action) => {
      let value = reducer(hook.state, action);
      if (hook.state != value) {
        hook.state = value;
        __vrScheduleUpdate(inst);
      }
    };
    return hook;
  };
  let h = __vrHook(make);
  let out = [];
  out.push(h.state);
  out.push(h.dispatch);
  return out;
}

function useRef(initial) {
  let h = __vrHook(() => {
    return { current: initial };
  });
  return h;
}

function useMemo(factory, deps) {
  let h = __vrHook(() => {
    return { value: null, deps: null, primed: false };
  });
  if (!h.primed || !__vrDepsEqual(h.deps, deps)) {
    h.value = factory();
    h.deps = deps;
    h.primed = true;
  }
  return h.value;
}

function useCallback(fn, deps) {
  let h = __vrHook(() => {
    return { value: null, deps: null, primed: false };
  });
  if (!h.primed || !__vrDepsEqual(h.deps, deps)) {
    h.value = fn;
    h.deps = deps;
    h.primed = true;
  }
  return h.value;
}

// Effects (passive) and layout effects. Both register a job that the commit
// phase runs after the tree is mutated; layout effects run synchronously at the
// end of the commit, passive effects on the following microtask. Here they
// share the queue and the microtask drain (documented approximation — the
// cleanup/re-run ordering that apps depend on is preserved).
function __vrEffectImpl(create, deps, isLayout) {
  let h = __vrHook(() => {
    return { kind: "effect", create: null, cleanup: null, deps: null, pending: false, layout: isLayout };
  });
  h.create = create;
  if (!__vrDepsEqual(h.deps, deps)) {
    h.deps = deps;
    if (!h.pending) {
      h.pending = true;
      __vrPendingEffects.push(h);
    }
  }
}

function useEffect(create, deps) {
  __vrEffectImpl(create, deps, false);
}

function useLayoutEffect(create, deps) {
  __vrEffectImpl(create, deps, true);
}

function useInsertionEffect(create, deps) {
  __vrEffectImpl(create, deps, true);
}

function useImperativeHandle(ref, create, deps) {
  useEffect(() => {
    if (ref != null) {
      if (__isType(ref, "function")) {
        ref(create());
      } else {
        ref.current = create();
      }
    }
    return () => {
      if (ref != null && !__isType(ref, "function")) {
        ref.current = null;
      }
    };
  }, deps);
}

function useId() {
  let h = __vrHook(() => {
    __vrIdSeq = __vrIdSeq + 1;
    return { id: "vr-" + __vrIdSeq };
  });
  return h.id;
}

function useSyncExternalStore(subscribe, getSnapshot) {
  let s = useState(() => {
    return getSnapshot();
  });
  let value = s[0];
  let set = s[1];
  useEffect(() => {
    let check = () => {
      set(getSnapshot());
    };
    // Prime once in case the store changed between render and subscribe.
    check();
    let unsub = subscribe(check);
    return () => {
      if (unsub != null && __isType(unsub, "function")) {
        unsub();
      }
    };
  }, [subscribe]);
  return value;
}

// Concurrent hooks: the Elpian VM renders synchronously, so transitions and
// deferred values resolve immediately — API-compatible, no tearing.
function useTransition() {
  let out = [];
  out.push(false);
  out.push((cb) => {
    if (__isType(cb, "function")) {
      cb();
    }
  });
  return out;
}

function useDeferredValue(value) {
  return value;
}

function useDebugValue(v) {
  // no-op (devtools hook)
}

// useFrame(cb) — run cb(deltaSeconds) every rendered frame, the react-three-
// fiber idiom for imperative animation (rotate a mesh via its ref, step a
// simulation, …). A single GD.onProcess handler fans out to every registered
// callback; the callback always reads the latest closure through a ref, so it
// never goes stale across renders. Registration is cleaned up on unmount.
var __vrFrameCbs = [];
var __vrFrameInstalled = false;

function __vrInstallFrame() {
  if (__vrFrameInstalled) {
    return;
  }
  __vrFrameInstalled = true;
  GD.onProcess((d) => {
    let cbs = __vrFrameCbs;
    for (let i = 0; i < cbs.length; i++) {
      cbs[i](d);
    }
  });
}

function useFrame(cb) {
  let ref = useRef(cb);
  ref.current = cb;
  useEffect(() => {
    __vrInstallFrame();
    let wrapper = (d) => {
      ref.current(d);
    };
    __vrFrameCbs.push(wrapper);
    return () => {
      let out = [];
      for (let i = 0; i < __vrFrameCbs.length; i++) {
        if (__vrFrameCbs[i] != wrapper) {
          out.push(__vrFrameCbs[i]);
        }
      }
      __vrFrameCbs = out;
    };
  }, []);
}

// The live logical viewport (VUI.metrics()): { w, h, scale, compact, medium,
// expanded, portrait }. The component re-renders on every window resize, so
// responsive layouts just branch on the returned metrics.
function useViewport() {
  let s = useState(0);
  let setTick = s[1];
  useEffect(() => {
    let un = VUI.onResize((m) => {
      setTick((v) => v + 1);
    });
    return un;
  }, []);
  return VUI.metrics();
}

// ---------------------------------------------------------------------------
// context
// ---------------------------------------------------------------------------

function createContext(defaultValue) {
  let ctx = {
    __vrcontext: true,
    _value: defaultValue,
    _default: defaultValue,
    _subs: [],
    Provider: null,
    Consumer: null,
  };
  ctx.Provider = (props) => {
    let v = props.value;
    if (ctx._value != v) {
      ctx._value = v;
      __vrNotifyContext(ctx);
    }
    return props.children;
  };
  ctx.Consumer = (props) => {
    // <Context.Consumer>{value => ...}</Context.Consumer>
    let render = props.children;
    if (__isType(render, "function")) {
      return render(ctx._value);
    }
    return null;
  };
  return ctx;
}

function useContext(ctx) {
  let inst = __vrCur;
  // Subscribe this instance to future provider updates.
  let subs = ctx._subs;
  let found = false;
  for (let i = 0; i < subs.length; i++) {
    if (subs[i] == inst) {
      found = true;
    }
  }
  if (!found) {
    subs.push(inst);
  }
  return ctx._value;
}

function __vrNotifyContext(ctx) {
  let subs = ctx._subs;
  for (let i = 0; i < subs.length; i++) {
    let inst = subs[i];
    if (inst.alive == true) {
      __vrScheduleUpdate(inst);
    }
  }
}

// ---------------------------------------------------------------------------
// component helpers: memo / forwardRef / StrictMode
// ---------------------------------------------------------------------------

// forwardRef: the wrapped component receives (props, ref). React 19 keeps ref
// in props; we pass it explicitly for the classic two-arg signature.
function forwardRef(render) {
  let wrapper = (props) => {
    return render(props, props.ref);
  };
  return wrapper;
}

// memo: a shallow-props gate implemented purely with hooks (no reconciler
// special-case, no mutation of the function value). When the incoming props are
// shallow-equal to the previous render's, it returns the cached element so the
// subtree reconciles as a no-op.
function memo(component, areEqual) {
  let wrapped = (props) => {
    let last = useRef(null);
    let lastEl = useRef(null);
    if (last.current != null) {
      let same = false;
      if (areEqual != null && __isType(areEqual, "function")) {
        same = areEqual(last.current, props);
      } else {
        same = __vrShallowEqualProps(last.current, props);
      }
      if (same == true) {
        return lastEl.current;
      }
    }
    last.current = props;
    let el = component(props);
    lastEl.current = el;
    return el;
  };
  return wrapped;
}

var StrictMode = __VR_FRAGMENT;

function __vrShallowEqualProps(a, b) {
  if (a == b) {
    return true;
  }
  if (a == null || b == null) {
    return false;
  }
  let ka = a.keys;
  let kb = b.keys;
  if (ka.length != kb.length) {
    return false;
  }
  for (let i = 0; i < ka.length; i++) {
    let k = ka[i];
    if (a[k] != b[k]) {
      return false;
    }
  }
  return true;
}

// ---------------------------------------------------------------------------
// children normalisation
// ---------------------------------------------------------------------------

// Flatten a children value into a linear array of renderables (elements and
// string text nodes), dropping null / boolean (and, per the subset caveat,
// numeric 0). Numbers become text; arrays flatten recursively.
function __vrNormalize(children) {
  let out = [];
  __vrNormalizeInto(out, children);
  return out;
}

function __vrNormalizeInto(out, ch) {
  if (ch == null) {
    return;
  }
  if (__isType(ch, "bool")) {
    return;
  }
  if (__isType(ch, "list")) {
    for (let i = 0; i < ch.length; i++) {
      __vrNormalizeInto(out, ch[i]);
    }
    return;
  }
  if (__isType(ch, "number")) {
    out.push("" + ch);
    return;
  }
  if (__isType(ch, "string")) {
    out.push(ch);
    return;
  }
  // an element (or any other map-shaped value we treat as one)
  out.push(ch);
}

// ---------------------------------------------------------------------------
// instances (the committed tree)
// ---------------------------------------------------------------------------
//
// kind:
//   "roothost" — the synthetic root wrapping the mount container
//   "host"     — an intrinsic element backed by a Godot node
//   "comp"     — a function component (owns hooks)
//   "frag"     — a fragment / provider / array of children
//   "text"     — a raw string, backed by a Label
//
// Shared fields: element, key, kind, childInstances, hostContainer, alive.
// A "host"/"roothost" also has: tag, driver, node, container, attached, props.
// A "comp" also has: fn, hooks, props.
// A "text" also has: node, value.

function __vrElementKey(child) {
  if (__vrIsElement(child)) {
    return child.key;
  }
  return null;
}

function __vrElementType(child) {
  if (__vrIsElement(child)) {
    return child.type;
  }
  return "__text__";
}

// Two children are "the same" (updatable in place) when their type and key
// match. Differing type or key means unmount-and-remount.
function __vrSameType(inst, child) {
  if (inst.kind == "text") {
    return !__vrIsElement(child);
  }
  if (!__vrIsElement(child)) {
    return false;
  }
  return inst.element != null && inst.element.type == child.type;
}

// ---------------------------------------------------------------------------
// mounting
// ---------------------------------------------------------------------------

function __vrMount(child, hostContainer) {
  if (!__vrIsElement(child)) {
    // a text node
    let node = __vrDriverText("" + child);
    return {
      kind: "text",
      value: "" + child,
      node: node,
      childInstances: [],
      hostContainer: hostContainer,
      alive: true,
      element: null,
      key: null,
    };
  }

  let type = child.type;

  if (__isType(type, "function")) {
    let inst = {
      kind: "comp",
      fn: type,
      element: child,
      props: child.props,
      key: child.key,
      hooks: [],
      childInstances: [],
      hostContainer: hostContainer,
      alive: true,
      dirty: false,
      // Set by a layer above this one (gui.js) when the component is a class
      // rather than a function. VReact never sets it and never reads the
      // instance; it only knows to call the hooks below at the two moments a
      // class component needs them.
      hasClass: false,
      classInstance: null,
    };
    __vrRenderComponent(inst);
    return inst;
  }

  if (type == __VR_FRAGMENT) {
    let inst = {
      kind: "frag",
      element: child,
      key: child.key,
      childInstances: [],
      hostContainer: hostContainer,
      alive: true,
    };
    __vrReconcileChildren(inst, __vrNormalize(child.props.children), hostContainer);
    return inst;
  }

  // an intrinsic host element
  let inst = {
    kind: "host",
    tag: type,
    element: child,
    props: child.props,
    key: child.key,
    node: null,
    container: null,
    attached: [],
    childInstances: [],
    hostContainer: hostContainer,
    alive: true,
  };
  __vrDriverCreate(inst);
  if (inst.ref == null) {
    inst.ref = child.ref;
  }
  // Only container hosts adopt element children; leaf hosts (text, button,
  // camera, …) fold their children into a prop (label text) inside the driver,
  // so reconciling them would build orphan nodes.
  if (inst.container != null) {
    __vrReconcileChildren(inst, __vrNormalize(child.props.children), inst);
    __vrSyncFrom(inst);
  }
  __vrApplyHostRef(inst);
  return inst;
}

// Class-component hooks, installed by a layer above VReact.
//
// `gui.js` renders class components through this same reconciler. Rather than
// teaching the reconciler what a class is — which would put a second component
// model inside a file whose whole point is that there is one — it installs two
// callbacks here and marks the fiber with `hasClass`.
//
// Null when react.js is used on its own, which is the ordinary case: a guest
// importing only react.js gets function components and pays nothing for a
// model it is not using.
var __vrClassHooks = null;

/// Install the class-component hooks. `hooks` is `{ commit, unmount }`.
function __vrInstallClassHooks(hooks) {
  __vrClassHooks = hooks;
}

function __vrRenderComponent(inst) {
  __vrCur = inst;
  __vrHookIndex = 0;
  // `inst.fn` is read here rather than hoisted into a local: a class
  // component's hook rebinds it per render, and a stale local would call the
  // previous render's closure.
  let out = inst.fn(inst.props);
  __vrCur = null;
  __vrReconcileChildren(inst, __vrNormalize(out), inst.hostContainer);
  if (inst.hasClass == true && __vrClassHooks != null) {
    __vrClassHooks.commit(inst);
  }
}

// ---------------------------------------------------------------------------
// updating
// ---------------------------------------------------------------------------

function __vrUpdate(inst, child, hostContainer) {
  if (!__vrSameType(inst, child)) {
    // replace: unmount the old subtree, mount a fresh one
    __vrUnmount(inst);
    return __vrMount(child, hostContainer);
  }

  if (inst.kind == "text") {
    let v = "" + child;
    if (inst.value != v) {
      inst.value = v;
      inst.node.set("text", v);
    }
    return inst;
  }

  if (inst.kind == "comp") {
    inst.element = child;
    inst.props = child.props;
    __vrRenderComponent(inst);
    return inst;
  }

  if (inst.kind == "frag") {
    inst.element = child;
    __vrReconcileChildren(inst, __vrNormalize(child.props.children), hostContainer);
    return inst;
  }

  // host
  let oldProps = inst.props;
  inst.element = child;
  inst.props = child.props;
  __vrDriverUpdate(inst, oldProps, child.props);
  if (inst.container != null) {
    __vrReconcileChildren(inst, __vrNormalize(child.props.children), inst);
    __vrSyncFrom(inst);
  }
  if (inst.ref != child.ref) {
    inst.ref = child.ref;
    __vrApplyHostRef(inst);
  }
  return inst;
}

// ---------------------------------------------------------------------------
// child reconciliation (keyed, with positional fallback)
// ---------------------------------------------------------------------------

function __vrReconcileChildren(parent, newChildren, hostContainer) {
  let old = parent.childInstances;
  let used = [];
  for (let i = 0; i < old.length; i++) {
    used.push(false);
  }
  let matched = [];
  for (let i = 0; i < newChildren.length; i++) {
    matched.push(-1);
  }

  // Pass 1 — keyed matches.
  for (let i = 0; i < newChildren.length; i++) {
    let key = __vrElementKey(newChildren[i]);
    if (key != null) {
      for (let j = 0; j < old.length; j++) {
        if (!used[j] && old[j].key == key && __vrSameType(old[j], newChildren[i])) {
          matched[i] = j;
          used[j] = true;
          j = old.length;
        }
      }
    }
  }

  // Pass 2 — positional matches for the still-unmatched, keyless children.
  let cursor = 0;
  for (let i = 0; i < newChildren.length; i++) {
    if (matched[i] < 0 && __vrElementKey(newChildren[i]) == null) {
      while (cursor < old.length && (used[cursor] || old[cursor].key != null)) {
        cursor = cursor + 1;
      }
      if (cursor < old.length && __vrSameType(old[cursor], newChildren[i])) {
        matched[i] = cursor;
        used[cursor] = true;
        cursor = cursor + 1;
      }
    }
  }

  // Build the next child-instance list.
  let next = [];
  for (let i = 0; i < newChildren.length; i++) {
    if (matched[i] >= 0) {
      let inst = old[matched[i]];
      next.push(__vrUpdate(inst, newChildren[i], hostContainer));
    } else {
      next.push(__vrMount(newChildren[i], hostContainer));
    }
  }

  // Unmount everything left over.
  for (let j = 0; j < old.length; j++) {
    if (!used[j]) {
      __vrUnmount(old[j]);
    }
  }

  parent.childInstances = next;
}

// ---------------------------------------------------------------------------
// unmounting
// ---------------------------------------------------------------------------

function __vrUnmount(inst) {
  inst.alive = false;

  if (inst.hasClass == true && __vrClassHooks != null) {
    __vrClassHooks.unmount(inst);
  }

  // Run effect cleanups for a component's own hooks (deepest first would be
  // ideal; this order is adequate for the cleanup contract apps rely on).
  if (inst.kind == "comp") {
    let hooks = inst.hooks;
    for (let i = 0; i < hooks.length; i++) {
      let h = hooks[i];
      if (h != null && h.kind == "effect") {
        if (h.cleanup != null && __isType(h.cleanup, "function")) {
          h.cleanup();
          h.cleanup = null;
        }
      }
    }
  }

  let cs = inst.childInstances;
  for (let i = 0; i < cs.length; i++) {
    __vrUnmount(cs[i]);
  }

  // Free the Godot node backing a host/text instance.
  if (inst.kind == "host" || inst.kind == "text") {
    if (inst.node != null) {
      inst.node.queueFree();
    }
  }
}

// ---------------------------------------------------------------------------
// host-node collection + container synchronisation
// ---------------------------------------------------------------------------

// Collect, in order, the top-level Godot nodes an instance contributes to its
// enclosing host container. Recursion stops at host/text nodes (a host manages
// its own children internally).
function __vrCollect(inst, out) {
  if (inst.kind == "host" || inst.kind == "text") {
    out.push(inst.node);
    return;
  }
  let cs = inst.childInstances;
  for (let i = 0; i < cs.length; i++) {
    __vrCollect(cs[i], out);
  }
}

function __vrSameNodes(a, b) {
  if (a.length != b.length) {
    return false;
  }
  for (let i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

// Handle-id equality. On the web bridge a handle re-marshaled from the engine
// (e.g. get_parent's return) can carry a generation bit at 2^32, so compare
// the low 32 bits only.
function __vrIdEq(a, b) {
  if (a == null || b == null) {
    return false;
  }
  return a % 4294967296 == b % 4294967296;
}

// The current parent of a node, or null when it has none / the handle is
// already freed (a freed handle's op errors — swallowed here on purpose).
function __vrParentOf(n) {
  let p = null;
  try {
    p = n.call("get_parent", []);
  } catch (e) {
    return null;
  }
  if (p == null) {
    return null;
  }
  if (GD.isError(p)) {
    return null;
  }
  if (p.id == null) {
    return null;
  }
  return p;
}

// Reconcile a host instance's container to hold exactly its flattened child
// nodes, in order. Kept nodes are detached and re-appended (Godot preserves
// their state); unmounted nodes were already queue-freed. Skips work entirely
// when the ordered node set is unchanged.
//
// Parent-aware on both sides: a node that moved to ANOTHER container this pass
// must not be ripped out of it (only detach nodes still under this container),
// and a wanted node still sitting under a previous parent must be detached
// there first — Godot refuses add_child on a parented node, which used to make
// whole subtrees silently disappear on screen transitions.
function __vrSyncFrom(hostInst) {
  if (hostInst == null) {
    return;
  }
  let container = hostInst.container;
  if (container == null) {
    return;
  }
  let want = [];
  let cs = hostInst.childInstances;
  for (let i = 0; i < cs.length; i++) {
    __vrCollect(cs[i], want);
  }
  let prev = hostInst.attached;
  if (prev == null) {
    prev = [];
  }
  if (__vrSameNodes(prev, want)) {
    return;
  }
  for (let i = 0; i < prev.length; i++) {
    let pp = __vrParentOf(prev[i]);
    if (pp != null && __vrIdEq(pp.id, container.id)) {
      container.call("remove_child", [prev[i]]);
    }
  }
  for (let i = 0; i < want.length; i++) {
    let wp = __vrParentOf(want[i]);
    if (wp != null) {
      wp.call("remove_child", [want[i]]);
    }
    container.call("add_child", [want[i]]);
  }
  hostInst.attached = want;
}

// ---------------------------------------------------------------------------
// refs on host elements
// ---------------------------------------------------------------------------

function __vrApplyHostRef(inst) {
  let ref = inst.ref;
  if (ref == null) {
    return;
  }
  if (__isType(ref, "function")) {
    ref(inst.node);
  } else {
    ref.current = inst.node;
  }
}

// ---------------------------------------------------------------------------
// effect commit
// ---------------------------------------------------------------------------

function __vrScheduleEffects() {
  if (__vrPendingEffects.length == 0) {
    return;
  }
  if (!__vrEffectsScheduled) {
    __vrEffectsScheduled = true;
    __later(__vrRunEffects);
  }
}

function __vrRunEffects() {
  __vrEffectsScheduled = false;
  let q = __vrPendingEffects;
  __vrPendingEffects = [];
  for (let i = 0; i < q.length; i++) {
    let h = q[i];
    if (h.pending == true) {
      h.pending = false;
      if (h.cleanup != null && __isType(h.cleanup, "function")) {
        h.cleanup();
        h.cleanup = null;
      }
      let c = h.create();
      if (c != null && __isType(c, "function")) {
        h.cleanup = c;
      } else {
        h.cleanup = null;
      }
    }
  }
}

// ===========================================================================
// HOST DRIVERS — the React "host config": intrinsic tags → Godot Control nodes
// ===========================================================================
//
// Each host instance gets a `node` (the outer node attached to its parent) and
// a `container` (the node its children attach into — often the same node; for
// padded/scroll wrappers it is an inner box). Leaves have `container == null`.
// Drivers reuse VUI's theme + style helpers so React output matches the kit.

// Resolve a colour: a Color passes through, a theme token name maps to the
// active theme, an "#rrggbb"/"#rrggbbaa" string parses via Godot's Color.html.
function __vrColor(v) {
  if (v == null) {
    return null;
  }
  if (__isType(v, "Color")) {
    return v;
  }
  let t = VUI.theme();
  if (__isType(v, "string")) {
    if (v == "primary") { return t.primary; }
    if (v == "accent") { return t.accent; }
    if (v == "danger") { return t.danger; }
    if (v == "success") { return t.success; }
    if (v == "warning") { return t.warning; }
    if (v == "info") { return t.info; }
    if (v == "text") { return t.text; }
    if (v == "textDim" || v == "muted") { return t.textDim; }
    if (v == "surface") { return t.surface; }
    if (v == "bg") { return t.bg; }
    return __vrColorHtml(v);
  }
  return null;
}

// One hex nibble → 0..15, or -1 (accepts both cases; no case builtin needed).
function __vrHexDigit(ch) {
  let lower = "0123456789abcdef";
  let upper = "0123456789ABCDEF";
  let i = lower.indexOf(ch);
  if (i >= 0) {
    return i;
  }
  return upper.indexOf(ch);
}

// Parse "#rgb", "#rrggbb" or "#rrggbbaa" in pure JS (the subset has no hex
// literals, and the engine's Expression cannot reach Color.html). Returns
// null on anything unparseable so callers fall back to their own default.
function __vrColorHtml(hex) {
  let s = "" + hex;
  if (s.startsWith("#")) {
    s = s.substring(1, s.length);
  }
  if (s.length == 3) {
    let r3 = __vrHexDigit(s.substring(0, 1));
    let g3 = __vrHexDigit(s.substring(1, 2));
    let b3 = __vrHexDigit(s.substring(2, 3));
    if (r3 < 0 || g3 < 0 || b3 < 0) {
      return null;
    }
    return new Color((r3 * 17) / 255.0, (g3 * 17) / 255.0, (b3 * 17) / 255.0, 1.0);
  }
  if (s.length != 6 && s.length != 8) {
    return null;
  }
  let vals = [];
  for (let i = 0; i < s.length; i = i + 2) {
    let hi = __vrHexDigit(s.substring(i, i + 1));
    let lo = __vrHexDigit(s.substring(i + 1, i + 2));
    if (hi < 0 || lo < 0) {
      return null;
    }
    vals.push((hi * 16 + lo) / 255.0);
  }
  let alpha = 1.0;
  if (vals.length == 4) {
    alpha = vals[3];
  }
  return new Color(vals[0], vals[1], vals[2], alpha);
}

// Call a possibly-absent event prop with an argument.
function __vrCall(fn, arg) {
  if (fn != null && __isType(fn, "function")) {
    fn(arg);
  }
}

function __vrCall0(fn) {
  if (fn != null && __isType(fn, "function")) {
    fn();
  }
}

// Read a numeric prop with a default. The VM's single 0/null/absent value
// means an absent prop and an explicit 0 both take the default; pass -1 for
// an explicit zero (spacing sinks clamp negatives to 0).
function __vrNum(v, d) {
  if (v == null) {
    return d;
  }
  if (__isType(v, "number")) {
    return v;
  }
  return d;
}

function __vrPx(v) {
  if (v < 0) {
    return 0;
  }
  return v;
}

// The subset of style-object keys we understand (so `style={{...}}` from an
// ordinary React component maps onto Godot properties).
function __vrApplyStyle(inst, style) {
  if (style == null) {
    return;
  }
  let node = inst.node;
  if (style.width != null) {
    __vrSetMinSize(node, __vrNum(style.width, 0.0), -1.0);
  }
  if (style.height != null) {
    __vrSetMinSize(node, -1.0, __vrNum(style.height, 0.0));
  }
  if (style.flexGrow != null && style.flexGrow != 0) {
    node.set("size_flags_horizontal", GInt(3));
    node.set("size_flags_vertical", GInt(3));
  }
  if (style.opacity != null) {
    node.set("modulate", new Color(1.0, 1.0, 1.0, __vrNum(style.opacity, 1.0)));
  }
  if (style.backgroundColor != null && inst.container != null) {
    let c = __vrColor(style.backgroundColor);
    if (c != null) {
      __vrSetPanelBg(inst, c);
    }
  }
}

function __vrSetMinSize(node, w, h) {
  let cur = node.get("custom_minimum_size");
  let cw = 0.0;
  let chh = 0.0;
  if (__isType(cur, "Vector2")) {
    cw = cur.x;
    chh = cur.y;
  }
  if (w >= 0.0) {
    cw = w;
  }
  if (h >= 0.0) {
    chh = h;
  }
  node.set("custom_minimum_size", new Vector2(cw, chh));
}

function __vrSetPanelBg(inst, color) {
  // Only meaningful when the outer node is a Panel/PanelContainer.
  inst.node.set("theme_override_styles/panel", VUI.styleBox({ bg: color, radius: VUI.theme().radiusM }));
}

// ---- the text driver (raw string children + <text>/<span>/<p>) -------------

function __vrDriverText(str) {
  let t = VUI.theme();
  let l = GD.create("Label");
  l.set("text", "" + str);
  l.set("theme_override_font_sizes/font_size", GInt(t.fontM));
  l.set("theme_override_colors/font_color", t.text);
  return l;
}

// ---- collect a text value out of children (for <text>, <button>, …) --------

function __vrTextOf(props) {
  let kids = __vrNormalize(props.children);
  let s = "";
  for (let i = 0; i < kids.length; i++) {
    if (!__vrIsElement(kids[i])) {
      s = s + kids[i];
    }
  }
  return s;
}

// ---------------------------------------------------------------------------
// driver dispatch
// ---------------------------------------------------------------------------

// Container tags whose element children become real child instances. Everything
// else is a leaf whose text children collapse into a string.
function __vrIsContainerTag(tag) {
  if (tag == "view") { return true; }
  if (tag == "div") { return true; }
  if (tag == "column") { return true; }
  if (tag == "vstack") { return true; }
  if (tag == "row") { return true; }
  if (tag == "hstack") { return true; }
  if (tag == "stack") { return true; }
  if (tag == "scroll") { return true; }
  if (tag == "center") { return true; }
  if (tag == "panel") { return true; }
  if (tag == "card") { return true; }
  if (tag == "grid") { return true; }
  if (tag == "section") { return true; }
  if (tag == "main") { return true; }
  if (tag == "header") { return true; }
  if (tag == "footer") { return true; }
  if (tag == "nav") { return true; }
  if (tag == "ul") { return true; }
  if (tag == "ol") { return true; }
  if (tag == "li") { return true; }
  return false;
}

// ---------------------------------------------------------------------------
// 3D host tags — Node3D-family elements + the <scene3d> viewport bridge, all
// built through G3 (godot.js). A <scene3d> is a Control that embeds a 3D world;
// every other 3D tag is a Node3D that lives inside one.
// ---------------------------------------------------------------------------

function __vrIs3DTag(tag) {
  if (tag == "scene3d") { return true; }
  if (tag == "viewport3d") { return true; }
  if (tag == "canvas3d") { return true; }
  if (tag == "node3d") { return true; }
  if (tag == "spatial") { return true; }
  if (tag == "group3d") { return true; }
  if (tag == "mesh") { return true; }
  if (tag == "box") { return true; }
  if (tag == "sphere") { return true; }
  if (tag == "cylinder") { return true; }
  if (tag == "capsule") { return true; }
  if (tag == "plane3d") { return true; }
  if (tag == "torus") { return true; }
  if (tag == "prism") { return true; }
  if (tag == "camera3d") { return true; }
  if (tag == "camera") { return true; }
  if (tag == "directionallight") { return true; }
  if (tag == "sun") { return true; }
  if (tag == "omnilight") { return true; }
  if (tag == "pointlight") { return true; }
  if (tag == "spotlight") { return true; }
  if (tag == "environment") { return true; }
  if (tag == "worldenvironment") { return true; }
  if (tag == "staticbody3d") { return true; }
  if (tag == "rigidbody3d") { return true; }
  if (tag == "characterbody3d") { return true; }
  if (tag == "area3d") { return true; }
  if (tag == "collisionshape3d") { return true; }
  if (tag == "gltf") { return true; }
  if (tag == "model") { return true; }
  if (tag == "node") { return true; }
  return false;
}

function __vr3dMeshOpts(props) {
  return {
    size: props.size,
    radius: props.radius,
    height: props.height,
    width: props.width,
    depth: props.depth,
    topRadius: props.topRadius,
    bottomRadius: props.bottomRadius,
    innerRadius: props.innerRadius,
    outerRadius: props.outerRadius,
    color: __vrColor(props.color),
    metallic: props.metallic,
    roughness: props.roughness,
    emission: __vrColor(props.emission),
    emissionEnergy: props.emissionEnergy,
    transparency: props.transparency,
    position: props.position,
    rotation: props.rotation,
    scale: props.scale,
    visible: props.visible,
  };
}

function __vr3dCollisionShape(props) {
  let shape = props.shape;
  if (shape == "sphere") {
    let s = GD.create("SphereShape3D");
    s.set("radius", GFloat(__vrNum(props.radius, 0.5)));
    return s;
  }
  if (shape == "capsule") {
    let s = GD.create("CapsuleShape3D");
    s.set("radius", GFloat(__vrNum(props.radius, 0.4)));
    s.set("height", GFloat(__vrNum(props.height, 1.4)));
    return s;
  }
  let s = GD.create("BoxShape3D");
  s.set("size", new Vector3(__vrNum(props.width, 1.0), __vrNum(props.height, 1.0), __vrNum(props.depth, 1.0)));
  return s;
}

// Wire 3D pick/input events onto a body/area host: `input_event` fires when
// the enclosing <scene3d picking> viewport picks the body. The handler reads
// the CURRENT props off the instance, so re-renders never re-wire the signal.
function __vrWire3DPick(inst) {
  let p = inst.props;
  if (p.onPick == null && p.onInputEvent == null && p.onPress == null) {
    return;
  }
  inst.node.set("input_ray_pickable", true);
  inst.node.connect("input_event", (a) => {
    // a = [camera, event, event_position, normal, shape_idx]
    let cur = inst.props;
    let ev = a[1];
    let evCls = "";
    if (__isType(ev, "GObj")) {
      evCls = ev.cls;
    }
    let info = {
      camera: a[0],
      event: ev,
      eventClass: evCls,
      position: a[2],
      normal: a[3],
      node: inst.node,
    };
    __vrCall(cur.onInputEvent, info);
    // onPick / onPress: only on press of a button/touch (not motion).
    if (cur.onPick != null || cur.onPress != null) {
      let pressed = GD.eval(
        "e.pressed if (e is InputEventMouseButton or e is InputEventScreenTouch) else false",
        ["e"],
        [ev]
      );
      if (pressed == true) {
        __vrCall(cur.onPick, info);
        __vrCall(cur.onPress, info);
      }
    }
  });
  if (p.onHover != null) {
    inst.node.connect("mouse_entered", (a) => {
      __vrCall(inst.props.onHover, true);
    });
    inst.node.connect("mouse_exited", (a) => {
      __vrCall(inst.props.onHover, false);
    });
  }
}

function __vrCreate3D(inst, tag, props) {
  if (tag == "scene3d" || tag == "viewport3d" || tag == "canvas3d") {
    let v = G3.viewport({ transparent: props.transparent, msaa: props.msaa, picking: props.picking });
    inst.node = v.container;
    inst.container = v.viewport;
    inst.viewport = v.viewport;
    v.container.set("size_flags_horizontal", GInt(3));
    v.container.set("size_flags_vertical", GInt(3));
    if (props.height != null) {
      __vrSetMinSize(v.container, __vrNum(props.width, 0.0), __vrNum(props.height, 320.0));
    } else if (props.grow == true || props.expand == true) {
      __vrSetMinSize(v.container, __vrNum(props.width, 0.0), 0.0);
    } else {
      __vrSetMinSize(v.container, __vrNum(props.width, 0.0), 320.0);
    }
    // Raw viewport input hook (camera drags, wheel zoom, hover): receives the
    // GObj InputEvent for every event the embedded world sees.
    if (props.onInput != null) {
      v.viewport.connect("gui_focus_changed", (a) => {});
      v.container.connect("gui_input", (a) => {
        __vrCall(inst.props.onInput, a[0]);
      });
    }
    return;
  }
  if (tag == "gltf" || tag == "model") {
    // A Node3D wrapper holding the loaded model, so src swaps and element
    // children (lights, extra meshes, bodies) reconcile against the wrapper.
    let wrap = G3.node({ position: props.position, rotation: props.rotation, scale: props.scale, visible: props.visible });
    inst.node = wrap;
    inst.container = wrap;
    inst.modelSrc = null;
    inst.modelNode = null;
    if (props.src != null) {
      let m = G3.gltf(props.src, { scale: props.modelScale, rotation: props.modelRotation });
      if (m != null) {
        wrap.call("add_child", [m]);
        inst.modelSrc = props.src;
        inst.modelNode = m;
        if (props.targetHeight != null) {
          G3.fitHeight(m, __vrNum(props.targetHeight, 1.0));
        }
      }
    }
    return;
  }
  if (tag == "node3d" || tag == "spatial" || tag == "group3d") {
    let n = G3.node({ position: props.position, rotation: props.rotation, scale: props.scale, visible: props.visible });
    inst.node = n;
    inst.container = n;
    return;
  }
  if (tag == "mesh" || tag == "box" || tag == "sphere" || tag == "cylinder" || tag == "capsule" || tag == "plane3d" || tag == "torus" || tag == "prism") {
    let shape = props.shape;
    if (shape == null) {
      shape = tag == "mesh" ? "box" : tag;
    }
    if (shape == "plane3d") {
      shape = "plane";
    }
    let mi = G3.mesh(shape, __vr3dMeshOpts(props));
    inst.node = mi;
    inst.container = mi;
    inst.meshShape = shape;
    return;
  }
  if (tag == "camera3d" || tag == "camera") {
    let c = G3.camera({ fov: props.fov, current: props.current, position: props.position, rotation: props.rotation, scale: props.scale });
    inst.node = c;
    inst.container = null;
    return;
  }
  if (tag == "directionallight" || tag == "sun") {
    let l = G3.dirLight({ color: __vrColor(props.color), energy: props.energy, shadow: props.shadow, position: props.position, rotation: props.rotation });
    inst.node = l;
    inst.container = null;
    return;
  }
  if (tag == "omnilight" || tag == "pointlight") {
    let l = G3.omniLight({ color: __vrColor(props.color), energy: props.energy, range: props.range, position: props.position });
    inst.node = l;
    inst.container = null;
    return;
  }
  if (tag == "spotlight") {
    let l = G3.spotLight({ color: __vrColor(props.color), energy: props.energy, range: props.range, angle: props.angle, position: props.position, rotation: props.rotation });
    inst.node = l;
    inst.container = null;
    return;
  }
  if (tag == "environment" || tag == "worldenvironment") {
    let e = G3.environment({ bg: __vrColor(props.bg), ambient: __vrColor(props.ambient), ambientEnergy: props.ambientEnergy });
    inst.node = e;
    inst.container = null;
    return;
  }
  if (tag == "staticbody3d" || tag == "rigidbody3d" || tag == "characterbody3d" || tag == "area3d") {
    let cls = "StaticBody3D";
    if (tag == "rigidbody3d") { cls = "RigidBody3D"; }
    else if (tag == "characterbody3d") { cls = "CharacterBody3D"; }
    else if (tag == "area3d") { cls = "Area3D"; }
    let b = GD.create(cls);
    G3.setTransform(b, { position: props.position, rotation: props.rotation, scale: props.scale, visible: props.visible });
    inst.node = b;
    inst.container = b;
    __vrWire3DPick(inst);
    return;
  }
  if (tag == "collisionshape3d") {
    let cs = GD.create("CollisionShape3D");
    let shape = __vr3dCollisionShape(props);
    if (shape != null) {
      cs.set("shape", shape);
    }
    G3.setTransform(cs, { position: props.position, rotation: props.rotation });
    inst.node = cs;
    inst.container = null;
    return;
  }
  // generic reflective escape hatch: <node type="AnyGodotClass" .../> — any
  // engine class becomes a host element, a container so it can hold children.
  let cls = props.type ?? "Node";
  let n = GD.create(cls);
  G3.setTransform(n, { position: props.position, rotation: props.rotation, scale: props.scale, visible: props.visible });
  inst.node = n;
  inst.container = n;
}

function __vrUpdate3D(inst, oldProps, props) {
  let tag = inst.tag;
  // Declarative transform (only sets the props that are present).
  G3.setTransform(inst.node, { position: props.position, rotation: props.rotation, scale: props.scale, visible: props.visible });

  if (tag == "gltf" || tag == "model") {
    if (props.src != inst.modelSrc) {
      if (inst.modelNode != null) {
        inst.modelNode.queueFree();
        inst.modelNode = null;
      }
      inst.modelSrc = props.src;
      if (props.src != null) {
        let m = G3.gltf(props.src, { scale: props.modelScale, rotation: props.modelRotation });
        if (m != null) {
          inst.node.call("add_child", [m]);
          inst.modelNode = m;
          if (props.targetHeight != null) {
            G3.fitHeight(m, __vrNum(props.targetHeight, 1.0));
          }
        }
      }
    }
    return;
  }

  if (tag == "mesh" || tag == "box" || tag == "sphere" || tag == "cylinder" || tag == "capsule" || tag == "plane3d" || tag == "torus" || tag == "prism") {
    if (props.color != oldProps.color || props.emission != oldProps.emission || props.roughness != oldProps.roughness || props.metallic != oldProps.metallic) {
      let prim = inst.node.get("mesh");
      if (prim != null && !GD.isError(prim)) {
        prim.set("material", G3.material(__vr3dMeshOpts(props)));
      }
    }
    return;
  }
  if (tag == "camera3d" || tag == "camera") {
    if (props.fov != oldProps.fov && props.fov != null) {
      inst.node.set("fov", GFloat(props.fov));
    }
    if (props.current != oldProps.current) {
      inst.node.set("current", props.current == true);
    }
    return;
  }
  if (tag == "directionallight" || tag == "sun" || tag == "omnilight" || tag == "pointlight" || tag == "spotlight") {
    if (props.color != oldProps.color) {
      let c = __vrColor(props.color);
      if (c != null) {
        inst.node.set("light_color", c);
      }
    }
    if (props.energy != oldProps.energy && props.energy != null) {
      inst.node.set("light_energy", GFloat(props.energy));
    }
    return;
  }
}

function __vrDriverCreate(inst) {
  let tag = inst.tag;
  let props = inst.props;
  let t = VUI.theme();

  if (__vrIs3DTag(tag)) {
    __vrCreate3D(inst, tag, props);
    return;
  }

  if (__vrIsContainerTag(tag)) {
    __vrCreateContainer(inst, tag, props, t);
    return;
  }

  // ----- leaves -----
  if (tag == "text" || tag == "span" || tag == "p" || tag == "label" || tag == "paragraph") {
    let l = GD.create("Label");
    inst.node = l;
    inst.container = null;
    __vrApplyTextProps(inst, null, props, t.fontM, false);
    return;
  }
  if (tag == "heading" || tag == "h1" || tag == "h2" || tag == "h3" || tag == "title") {
    let size = t.fontXL;
    if (tag == "h2" || tag == "title") { size = t.fontL; }
    if (tag == "h3") { size = t.fontM; }
    let l = GD.create("Label");
    inst.node = l;
    inst.container = null;
    __vrApplyTextProps(inst, null, props, size, false);
    if (props.weight == null) {
      // Headlines default to the medium weight, Material-style.
      let hf = VUI.fonts();
      if (hf.medium != null) {
        l.set("theme_override_fonts/font", hf.medium);
      }
    }
    return;
  }
  if (tag == "caption" || tag == "small" || tag == "muted") {
    let l = GD.create("Label");
    inst.node = l;
    inst.container = null;
    __vrApplyTextProps(inst, null, props, t.fontXS, true);
    return;
  }
  if (tag == "icon") {
    let l = GD.create("Label");
    inst.node = l;
    inst.container = null;
    l.set("horizontal_alignment", GInt(1));
    __vrApplyTextProps(inst, null, props, __vrNum(props.size, t.fontL), false);
    return;
  }
  if (tag == "button") {
    __vrCreateButton(inst, props, t);
    return;
  }
  if (tag == "input" || tag == "field" || tag == "textinput") {
    __vrCreateField(inst, props, t);
    return;
  }
  if (tag == "textarea") {
    __vrCreateTextArea(inst, props, t);
    return;
  }
  if (tag == "select" || tag == "dropdown" || tag == "option") {
    __vrCreateSelect(inst, props, t);
    return;
  }
  if (tag == "richtext") {
    __vrCreateRichText(inst, props, t);
    return;
  }
  if (tag == "image" || tag == "img") {
    __vrCreateImage(inst, props, t);
    return;
  }
  if (tag == "progress") {
    __vrCreateProgress(inst, props, t);
    return;
  }
  if (tag == "slider") {
    __vrCreateSlider(inst, props, t);
    return;
  }
  if (tag == "switch" || tag == "toggle") {
    __vrCreateSwitch(inst, props, t);
    return;
  }
  if (tag == "checkbox") {
    __vrCreateCheckbox(inst, props, t);
    return;
  }
  if (tag == "divider" || tag == "hr") {
    __vrCreateDivider(inst, props, t);
    return;
  }
  if (tag == "spacer") {
    let c = GD.create("Control");
    c.set("size_flags_horizontal", GInt(3));
    c.set("size_flags_vertical", GInt(3));
    inst.node = c;
    inst.container = null;
    return;
  }
  if (tag == "chip") {
    let handle = VUI.chip(__vrTextOf(props), {
      selected: props.selected == true,
      glyph: props.glyph,
      onTap: (on) => {
        __vrCall(inst.props.onChange, on);
        __vrCall0(inst.props.onPress);
      },
    });
    inst.node = handle.node;
    inst.container = null;
    inst.chipHandle = handle;
    return;
  }
  if (tag == "badge") {
    inst.node = VUI.badge(__vrTextOf(props), {
      color: __vrColor(props.color),
      textColor: __vrColor(props.textColor),
    });
    inst.container = null;
    return;
  }
  if (tag == "avatar") {
    inst.node = VUI.avatar(__vrTextOf(props), {
      color: __vrColor(props.color),
      textColor: __vrColor(props.textColor),
      size: props.size,
    });
    inst.container = null;
    return;
  }
  if (tag == "fab") {
    inst.node = VUI.fab(props.glyph ?? __vrTextOf(props), {
      size: props.size,
      bg: __vrColor(props.bg),
      color: __vrColor(props.color),
      onTap: () => {
        __vrCall0(inst.props.onPress);
        __vrCall0(inst.props.onClick);
        __vrCall0(inst.props.onTap);
      },
    });
    inst.container = null;
    return;
  }
  if (tag == "tile" || tag == "listtile") {
    inst.node = VUI.listTile({
      leading: props.leading,
      leadingColor: __vrColor(props.leadingColor),
      title: props.title ?? __vrTextOf(props),
      subtitle: props.subtitle,
      trailing: props.trailing,
      onTap: () => {
        __vrCall0(inst.props.onPress);
        __vrCall0(inst.props.onClick);
        __vrCall0(inst.props.onTap);
      },
    });
    inst.container = null;
    return;
  }

  // Unknown tag → a plain transparent container so the tree still renders.
  __vrCreateContainer(inst, "view", props, t);
}

function __vrCreateContainer(inst, tag, props, t) {
  let box = null;
  let container = null;
  let outer = null;

  if (tag == "row" || tag == "hstack") {
    box = GD.create("HBoxContainer");
    box.set("theme_override_constants/separation", GInt(__vrPx(__vrNum(props.gap, 12))));
    container = box;
    outer = box;
  } else if (tag == "grid") {
    box = GD.create("GridContainer");
    box.set("columns", GInt(__vrNum(props.cols, 2)));
    let g = __vrPx(__vrNum(props.gap, 12));
    box.set("theme_override_constants/h_separation", GInt(g));
    box.set("theme_override_constants/v_separation", GInt(g));
    container = box;
    outer = box;
  } else if (tag == "scroll") {
    let sc = GD.create("ScrollContainer");
    sc.set("size_flags_horizontal", GInt(3));
    let horizontal = props.horizontal == true;
    VUI.scrollbarStyle(sc);
    let inner = null;
    if (horizontal) {
      // A horizontal strip: HBox content, h-scroll on (bar hidden — chips
      // strips scroll by touch/drag), v-scroll off, natural height.
      sc.set("horizontal_scroll_mode", GInt(3)); // SCROLL_MODE_SHOW_NEVER
      sc.set("vertical_scroll_mode", GInt(0));
      inner = GD.create("HBoxContainer");
      inner.set("size_flags_vertical", GInt(3));
      if (props.height != null) {
        __vrSetMinSize(sc, -1.0, __vrNum(props.height, 48.0));
      }
    } else {
      sc.set("size_flags_vertical", GInt(3));
      inner = GD.create("VBoxContainer");
      inner.set("size_flags_horizontal", GInt(3));
    }
    inner.set("theme_override_constants/separation", GInt(__vrPx(__vrNum(props.gap, 12))));
    // pad on a scroll = content padding INSIDE the scroll area. Handled here
    // (margin between sc and inner) — the generic pad wrapper below must not
    // touch scroll: it used to wrap the already-parented inner, whose add
    // failed and left the scroll body empty.
    if (props.pad != null) {
      let sm = __vrPad(inner, __vrNum(props.pad, 0));
      sm.set("size_flags_horizontal", GInt(3));
      sm.set("size_flags_vertical", GInt(3));
      sc.call("add_child", [sm]);
    } else {
      sc.call("add_child", [inner]);
    }
    container = inner;
    outer = sc;
  } else if (tag == "center") {
    let c = GD.create("CenterContainer");
    // Centering needs room: fill the parent by default (like VUI.center).
    c.set("size_flags_horizontal", GInt(3));
    c.set("size_flags_vertical", GInt(3));
    container = c;
    outer = c;
  } else if (tag == "stack") {
    let c = GD.create("Control");
    container = c;
    outer = c;
  } else if (tag == "panel" || tag == "card") {
    let pc = GD.create("PanelContainer");
    // Material surfaces: a card is an elevated surfaceContainerLow container
    // (Flutter Card), a panel is the same surface without the shadow.
    // variant="filled" -> surfaceContainerHighest, flat; "outlined" ->
    // surface + hairline outline.
    let bg = t.surfaceContainerLow;
    let shadow = tag == "card" ? 1 : 0;
    if (props.variant == "filled") {
      bg = t.surfaceContainerHighest;
      shadow = 0;
    } else if (props.variant == "outlined") {
      bg = t.surface;
      shadow = 0;
    }
    if (props.shadow != null) {
      shadow = __vrNum(props.shadow, shadow);
    }
    if (props.bg != null) {
      let c = __vrColor(props.bg);
      if (c != null) {
        bg = c;
      }
    }
    let radius = __vrNum(props.radius, tag == "card" ? t.radiusM : t.radiusL);
    let border = __vrNum(props.border, 0);
    let borderColor = __vrColor(props.borderColor) ?? __vrColor(props.accent);
    if (props.variant == "outlined" && border == 0) {
      border = 1;
      if (borderColor == null) {
        borderColor = t.outlineVariant;
      }
    }
    if (props.accent != null && border == 0) {
      border = 1;
    }
    pc.set(
      "theme_override_styles/panel",
      VUI.styleBox({ bg: bg, radius: radius, shadow: shadow, border: border, borderColor: borderColor, skin: tag })
    );
    let inner = GD.create("VBoxContainer");
    inner.set("theme_override_constants/separation", GInt(__vrPx(__vrNum(props.gap, 12))));
    let pad = __vrNum(props.pad, 16);
    let wrap = __vrPad(inner, pad);
    pc.call("add_child", [wrap]);
    container = inner;
    outer = pc;
  } else {
    // view / div / column / vstack / section / …  → a vertical box
    box = GD.create("VBoxContainer");
    box.set("theme_override_constants/separation", GInt(__vrPx(__vrNum(props.gap, 12))));
    container = box;
    outer = box;
  }

  // Optional padding wrapper for the simple box containers. Scroll handles its
  // pad internally (its container is already parented to the ScrollContainer).
  if (props.pad != null && tag != "panel" && tag != "card" && tag != "scroll") {
    let wrap = __vrPad(container, __vrNum(props.pad, 0));
    outer = wrap;
  }

  inst.node = outer;
  inst.container = container;

  if (props.grow == true || props.expand == true) {
    outer.set("size_flags_horizontal", GInt(3));
    outer.set("size_flags_vertical", GInt(3));
  }
  __vrApplyStyle(inst, props.style);
}

function __vrPad(inner, pad) {
  if (pad == null || pad <= 0) {
    return inner;
  }
  let m = GD.create("MarginContainer");
  m.set("theme_override_constants/margin_left", GInt(pad));
  m.set("theme_override_constants/margin_top", GInt(pad));
  m.set("theme_override_constants/margin_right", GInt(pad));
  m.set("theme_override_constants/margin_bottom", GInt(pad));
  m.call("add_child", [inner]);
  return m;
}

// ---- text props (shared by text/heading/caption/icon) ----------------------

function __vrApplyTextProps(inst, oldProps, props, defaultSize, dim) {
  let t = VUI.theme();
  let l = inst.node;
  l.set("text", __vrTextOf(props));
  l.set("theme_override_font_sizes/font_size", GInt(__vrNum(props.size, defaultSize)));
  let color = __vrColor(props.color);
  if (color == null) {
    color = t.text;
    if (dim == true || props.dim == true) {
      color = t.textDim;
    }
    if (props.faint == true) {
      color = t.textFaint;
    }
  }
  l.set("theme_override_colors/font_color", color);
  // Explicit app font on every label (weight variant or regular) — theme
  // inheritance alone can miss, and the emoji fallback rides on this font.
  let wf = VUI.fonts();
  if (props.weight == "bold" && wf.bold != null) {
    l.set("theme_override_fonts/font", wf.bold);
  } else if (props.weight == "medium" && wf.medium != null) {
    l.set("theme_override_fonts/font", wf.medium);
  } else if (wf.regular != null) {
    l.set("theme_override_fonts/font", wf.regular);
  }
  if (props.align == "center") {
    l.set("horizontal_alignment", GInt(1));
  } else if (props.align == "right") {
    l.set("horizontal_alignment", GInt(2));
  } else if (props.align == "left") {
    l.set("horizontal_alignment", GInt(0));
  }
  if (props.wrap == true) {
    l.set("autowrap_mode", GInt(3));
    l.set("size_flags_horizontal", GInt(3));
  }
  if (props.grow == true || props.expand == true) {
    l.set("size_flags_horizontal", GInt(3));
  }
}

// ---- button ----------------------------------------------------------------

function __vrCreateButton(inst, props, t) {
  let b = GD.create("Button");
  inst.node = b;
  inst.container = null;
  b.set("focus_mode", GInt(0));
  __vrStyleButton(b, props, t);
  b.set("text", __vrTextOf(props));
  b.set("theme_override_font_sizes/font_size", GInt(__vrNum(props.fontSize, t.fontS)));
  let bFont = VUI.fonts();
  if (bFont.medium != null) {
    b.set("theme_override_fonts/font", bFont.medium);
  }
  if (props.disabled == true) {
    b.set("disabled", true);
  }
  __vrSetMinSize(b, __vrNum(props.minWidth, 0.0), __vrNum(props.height, t.controlHeight));
  if (props.wide == true || props.grow == true) {
    b.set("size_flags_horizontal", GInt(3));
  }
  // Stable signal binding: the closure reads the CURRENT prop off `inst`.
  b.connect("pressed", (a) => {
    let p = inst.props;
    __vrCall0(p.onPress);
    __vrCall0(p.onClick);
    __vrCall0(p.onTap);
  });
}

function __vrStyleButton(b, props, t) {
  // One source of truth: the shared Material button styler in ui.js.
  VUI.buttonStyle(b, props.kind, { radius: props.radius, padX: props.padX });
}

// ---- field (text input) ----------------------------------------------------

function __vrCreateField(inst, props, t) {
  let e = GD.create("LineEdit");
  inst.node = e;
  inst.container = null;
  inst.fieldValue = "" + (props.value ?? props.defaultValue ?? "");
  if (props.placeholder != null) {
    e.set("placeholder_text", props.placeholder);
  }
  if (inst.fieldValue != "") {
    e.set("text", inst.fieldValue);
  }
  if (props.obscure == true || props.type == "password") {
    e.set("secret", true);
  }
  e.set("size_flags_horizontal", GInt(3));
  VUI.fieldStyle(e);
  if (props.height != null) {
    __vrSetMinSize(e, 0.0, __vrNum(props.height, t.fieldHeight));
  }
  e.connect("text_changed", (a) => {
    inst.fieldValue = a[0];
    __vrCall(inst.props.onChange, a[0]);
    __vrCall(inst.props.onChanged, a[0]);
  });
  e.connect("text_submitted", (a) => {
    inst.fieldValue = a[0];
    __vrCall(inst.props.onSubmit, a[0]);
  });
}

// ---- textarea (multiline input) ---------------------------------------------

function __vrCreateTextArea(inst, props, t) {
  let e = GD.create("TextEdit");
  inst.node = e;
  inst.container = null;
  inst.fieldValue = "" + (props.value ?? props.defaultValue ?? "");
  if (props.placeholder != null) {
    e.set("placeholder_text", props.placeholder);
  }
  if (inst.fieldValue != "") {
    e.set("text", inst.fieldValue);
  }
  e.set("wrap_mode", GInt(1)); // TextEdit.LINE_WRAPPING_BOUNDARY
  __vrSetMinSize(e, 0.0, __vrNum(props.height, 120.0));
  e.set("size_flags_horizontal", GInt(3));
  VUI.textareaStyle(e);
  e.connect("text_changed", (a) => {
    let v = inst.node.get("text");
    inst.fieldValue = "" + v;
    __vrCall(inst.props.onChange, inst.fieldValue);
    __vrCall(inst.props.onChanged, inst.fieldValue);
  });
}

// ---- select / dropdown -------------------------------------------------------

function __vrApplySelectItems(inst, props, t) {
  let e = inst.node;
  e.call("clear");
  let items = props.options ?? props.items ?? [];
  inst.selectValues = [];
  for (let i = 0; i < items.length; i++) {
    let it = items[i];
    let label = it;
    let value = it;
    if (__isType(it, "map")) {
      label = it.label ?? ("" + it.value);
      value = it.value ?? it.label;
    }
    e.call("add_item", ["" + label, GInt(i)]);
    inst.selectValues.push(value);
  }
  let idx = __vrNum(props.index, -1);
  if (idx < 0 && props.value != null) {
    for (let i = 0; i < inst.selectValues.length; i++) {
      if (inst.selectValues[i] == props.value) {
        idx = i;
      }
    }
  }
  if (idx >= 0) {
    e.call("select", [GInt(idx)]);
  }
}

function __vrCreateSelect(inst, props, t) {
  let e = GD.create("OptionButton");
  inst.node = e;
  inst.container = null;
  e.set("focus_mode", GInt(0));
  VUI.dropdownStyle(e);
  __vrSetMinSize(e, __vrNum(props.minWidth, 0.0), __vrNum(props.height, t.fieldHeight));
  if (props.wide == true || props.grow == true) {
    e.set("size_flags_horizontal", GInt(3));
  }
  __vrApplySelectItems(inst, props, t);
  e.connect("item_selected", (a) => {
    let i = a[0];
    let value = null;
    if (inst.selectValues != null && i >= 0 && i < inst.selectValues.length) {
      value = inst.selectValues[i];
    }
    __vrCall(inst.props.onChange, value);
    __vrCall(inst.props.onSelect, i);
  });
}

// ---- richtext (BBCode) --------------------------------------------------------

function __vrCreateRichText(inst, props, t) {
  let l = GD.create("RichTextLabel");
  inst.node = l;
  inst.container = null;
  l.set("bbcode_enabled", true);
  l.set("fit_content", true);
  l.set("text", props.markup ?? __vrTextOf(props));
  l.set("theme_override_font_sizes/normal_font_size", GInt(__vrNum(props.size, t.fontM)));
  l.set("theme_override_colors/default_color", __vrColor(props.color) ?? t.text);
  l.set("size_flags_horizontal", GInt(3));
  if (props.height != null) {
    __vrSetMinSize(l, 0.0, __vrNum(props.height, 0.0));
  }
}

// ---- image -----------------------------------------------------------------

function __vrCreateImage(inst, props, t) {
  let r = GD.create("TextureRect");
  inst.node = r;
  inst.container = null;
  r.set("expand_mode", GInt(1));
  r.set("stretch_mode", GInt(5));
  let src = props.src ?? props.url;
  if (src != null) {
    let tex = GD.load(src);
    if (!GD.isError(tex)) {
      r.set("texture", tex);
    }
  }
  __vrSetMinSize(r, __vrNum(props.width, 0.0), __vrNum(props.height, 0.0));
}

// ---- progress --------------------------------------------------------------

function __vrCreateProgress(inst, props, t) {
  let p = GD.create("ProgressBar");
  inst.node = p;
  inst.container = null;
  p.set("min_value", GFloat(0.0));
  p.set("max_value", GFloat(__vrNum(props.max, 100.0)));
  p.set("value", GFloat(__vrNum(props.value, 0.0)));
  p.set("show_percentage", false);
  __vrSetMinSize(p, 0.0, __vrNum(props.height, 6.0));
  p.set("size_flags_horizontal", GInt(3));
  p.set(
    "theme_override_styles/background",
    VUI.styleBox({ bg: t.surfaceContainerHighest, radius: t.radiusFull })
  );
  p.set(
    "theme_override_styles/fill",
    VUI.styleBox({ bg: __vrColor(props.color) ?? t.primary, radius: t.radiusFull })
  );
}

// ---- slider ----------------------------------------------------------------

function __vrCreateSlider(inst, props, t) {
  let s = GD.create("HSlider");
  inst.node = s;
  inst.container = null;
  s.set("min_value", GFloat(__vrNum(props.min, 0.0)));
  s.set("max_value", GFloat(__vrNum(props.max, 100.0)));
  s.set("step", GFloat(__vrNum(props.step, 1.0)));
  s.set("value", GFloat(__vrNum(props.value, 0.0)));
  s.set("focus_mode", GInt(0));
  VUI.sliderStyle(s);
  s.set("size_flags_horizontal", GInt(3));
  s.connect("value_changed", (a) => {
    __vrCall(inst.props.onChange, a[0]);
    __vrCall(inst.props.onChanged, a[0]);
  });
}

// ---- switch / checkbox -----------------------------------------------------

function __vrCreateSwitch(inst, props, t) {
  // The Material switch from the kit (pill track + animated knob); the handle
  // is kept on the instance so prop updates can drive it.
  let handle = VUI.toggle({
    value: props.checked == true || props.value == true,
    onChanged: (on) => {
      __vrCall(inst.props.onChange, on);
      __vrCall(inst.props.onChanged, on);
    },
  });
  let label = __vrTextOf(props);
  if (label != "") {
    let rowBox = GD.create("HBoxContainer");
    rowBox.set("theme_override_constants/separation", GInt(12));
    let lab = GD.create("Label");
    lab.set("text", label);
    lab.set("theme_override_font_sizes/font_size", GInt(t.fontS));
    lab.set("theme_override_colors/font_color", t.onSurface);
    lab.set("vertical_alignment", GInt(1));
    lab.set("size_flags_horizontal", GInt(3));
    rowBox.call("add_child", [lab]);
    rowBox.call("add_child", [handle.node]);
    inst.node = rowBox;
  } else {
    inst.node = handle.node;
  }
  inst.container = null;
  inst.toggleHandle = handle;
}

function __vrCreateCheckbox(inst, props, t) {
  // The Material checkbox from the kit.
  let handle = VUI.checkbox({
    value: props.checked == true || props.value == true,
    label: __vrTextOf(props),
    onChanged: (on) => {
      __vrCall(inst.props.onChange, on);
      __vrCall(inst.props.onChanged, on);
    },
  });
  inst.node = handle.node;
  inst.container = null;
  inst.toggleHandle = handle;
}

// ---- divider ---------------------------------------------------------------

function __vrCreateDivider(inst, props, t) {
  let d = GD.create("Panel");
  inst.node = d;
  inst.container = null;
  if (props.vertical == true) {
    __vrSetMinSize(d, __vrNum(props.thickness, 1.0), 8.0);
    d.set("size_flags_vertical", GInt(3));
  } else {
    __vrSetMinSize(d, 0.0, __vrNum(props.thickness, 1.0));
    d.set("size_flags_horizontal", GInt(3));
  }
  d.set("mouse_filter", GInt(2));
  d.set("theme_override_styles/panel", VUI.styleBox({ bg: __vrColor(props.color) ?? t.outlineVariant, radius: 1 }));
}

// ---------------------------------------------------------------------------
// driver update: patch a host node's props in place
// ---------------------------------------------------------------------------

function __vrDriverUpdate(inst, oldProps, props) {
  let tag = inst.tag;
  let t = VUI.theme();

  if (__vrIs3DTag(tag)) {
    __vrUpdate3D(inst, oldProps, props);
    return;
  }

  if (__vrIsContainerTag(tag)) {
    if (props.grow == true || props.expand == true) {
      inst.node.set("size_flags_horizontal", GInt(3));
      inst.node.set("size_flags_vertical", GInt(3));
    }
    if (tag == "grid" && props.cols != oldProps.cols) {
      inst.container.set("columns", GInt(__vrNum(props.cols, 2)));
    }
    __vrApplyStyle(inst, props.style);
    return;
  }

  if (tag == "text" || tag == "span" || tag == "p" || tag == "label" || tag == "paragraph") {
    __vrApplyTextProps(inst, oldProps, props, VUI.theme().fontM, false);
    return;
  }
  if (tag == "heading" || tag == "h1" || tag == "h2" || tag == "h3" || tag == "title") {
    __vrApplyTextProps(inst, oldProps, props, VUI.theme().fontXL, false);
    return;
  }
  if (tag == "caption" || tag == "small" || tag == "muted") {
    __vrApplyTextProps(inst, oldProps, props, VUI.theme().fontXS, true);
    return;
  }
  if (tag == "icon") {
    __vrApplyTextProps(inst, oldProps, props, __vrNum(props.size, t.fontL), false);
    return;
  }
  if (tag == "button") {
    inst.node.set("text", __vrTextOf(props));
    if (props.kind != oldProps.kind) {
      __vrStyleButton(inst.node, props, t);
    }
    if (props.disabled != oldProps.disabled) {
      inst.node.set("disabled", props.disabled == true);
    }
    return;
  }
  if (tag == "input" || tag == "field" || tag == "textinput" || tag == "textarea") {
    // Controlled input: push value when the prop diverges from the widget.
    if (props.value != null && ("" + props.value) != inst.fieldValue) {
      inst.fieldValue = "" + props.value;
      inst.node.set("text", inst.fieldValue);
    }
    if (props.placeholder != oldProps.placeholder && props.placeholder != null) {
      inst.node.set("placeholder_text", props.placeholder);
    }
    // Keep secrecy in sync on reuse (a reconciled password field must not
    // leave the next occupant masked, and vice versa).
    let secret = props.obscure == true || props.type == "password";
    let oldSecret = oldProps.obscure == true || oldProps.type == "password";
    if (secret != oldSecret) {
      inst.node.set("secret", secret);
    }
    return;
  }
  if (tag == "select" || tag == "dropdown" || tag == "option") {
    if (props.options != oldProps.options || props.items != oldProps.items || props.index != oldProps.index || props.value != oldProps.value) {
      __vrApplySelectItems(inst, props, t);
    }
    return;
  }
  if (tag == "richtext") {
    inst.node.set("text", props.markup ?? __vrTextOf(props));
    return;
  }
  if (tag == "image" || tag == "img") {
    let src = props.src ?? props.url;
    let osrc = oldProps.src ?? oldProps.url;
    if (src != null && src != osrc) {
      let tex = GD.load(src);
      if (!GD.isError(tex)) {
        inst.node.set("texture", tex);
      }
    }
    return;
  }
  if (tag == "progress") {
    inst.node.set("max_value", GFloat(__vrNum(props.max, 100.0)));
    inst.node.set("value", GFloat(__vrNum(props.value, 0.0)));
    return;
  }
  if (tag == "slider") {
    inst.node.set("max_value", GFloat(__vrNum(props.max, 100.0)));
    inst.node.set("min_value", GFloat(__vrNum(props.min, 0.0)));
    if (props.value != oldProps.value) {
      inst.node.set("value", GFloat(__vrNum(props.value, 0.0)));
    }
    return;
  }
  if (tag == "chip") {
    if (inst.chipHandle != null && props.selected != oldProps.selected) {
      inst.chipHandle.setSelected(props.selected == true);
    }
    return;
  }
  if (tag == "switch" || tag == "toggle" || tag == "checkbox") {
    let on = props.checked == true || props.value == true;
    if (inst.toggleHandle != null) {
      if (tag == "checkbox") {
        if (inst.toggleHandle.isChecked() != on) {
          inst.toggleHandle.setChecked(on);
        }
      } else {
        if (inst.toggleHandle.isOn() != on) {
          inst.toggleHandle.setOn(on);
        }
      }
    }
    return;
  }
}

// ===========================================================================
// PUBLIC API — the React namespace + the VictorClient renderer entry points
// ===========================================================================

var React = {
  createElement: createElement,
  Fragment: __VR_FRAGMENT,
  StrictMode: __VR_FRAGMENT,
  useState: useState,
  useReducer: useReducer,
  useEffect: useEffect,
  useLayoutEffect: useLayoutEffect,
  useInsertionEffect: useInsertionEffect,
  useRef: useRef,
  useMemo: useMemo,
  useCallback: useCallback,
  useContext: useContext,
  createContext: createContext,
  useImperativeHandle: useImperativeHandle,
  useId: useId,
  useSyncExternalStore: useSyncExternalStore,
  useTransition: useTransition,
  useDeferredValue: useDeferredValue,
  useDebugValue: useDebugValue,
  useFrame: useFrame,
  useViewport: useViewport,
  memo: memo,
  forwardRef: forwardRef,
};

// Render an element tree into an existing Godot container node (a GObj that
// accepts add_child). Returns a root handle with update()/unmount().
function __vrRenderRoot(element, container) {
  let root = {
    kind: "roothost",
    node: container,
    container: container,
    attached: [],
    childInstances: [],
    hostContainer: null,
    alive: true,
    element: null,
  };
  root.hostContainer = root;
  __vrReconcileChildren(root, __vrNormalize(element), root);
  __vrSyncFrom(root);
  __vrScheduleEffects();
  return {
    root: root,
    render: (next) => {
      __vrReconcileChildren(root, __vrNormalize(next), root);
      __vrSyncFrom(root);
      __vrScheduleEffects();
    },
    unmount: () => {
      let cs = root.childInstances;
      for (let i = 0; i < cs.length; i++) {
        __vrUnmount(cs[i]);
      }
      root.childInstances = [];
      __vrSyncFrom(root);
    },
  };
}

// The ReactDOM-equivalent client surface.
var VictorClient = {
  // createRoot(container).render(<App/>)  — the React 18 root API.
  createRoot: (container) => {
    let node = __vuiNode(container);
    let handle = null;
    return {
      render: (element) => {
        if (handle == null) {
          handle = __vrRenderRoot(element, node);
        } else {
          handle.render(element);
        }
      },
      unmount: () => {
        if (handle != null) {
          handle.unmount();
        }
      },
    };
  },

  // Legacy render(<App/>, container).
  render: (element, container) => {
    return __vrRenderRoot(element, __vuiNode(container));
  },

  // The one-call bootstrap the Next.js template's entry uses: set the theme,
  // create the full-screen VUI app (CanvasLayer + page), and mount the React
  // tree into it. Returns { app, root } so callers can reach the VUI app.
  mountApp: (element, options) => {
    let o = options;
    if (o == null) {
      o = {};
    }
    if (o.theme == "light") {
      VUI.use(VUI.themeLight());
    } else {
      VUI.use(VUI.themeDark());
    }
    let app = VUI.app(o);
    // A vertical mount box fills the page so React children stack naturally.
    let mount = GD.create("VBoxContainer");
    mount.set("theme_override_constants/separation", GInt(0));
    app.push(mount);
    let handle = __vrRenderRoot(element, mount);
    return { app: app, root: handle, mount: mount };
  },
};

// A tiny convenience namespace for Victor-specific extras a React app may want
// (theme access, colour parsing, the raw engine + kit if it drops down a level).
var Victor = {
  theme: () => {
    return VUI.theme();
  },
  useTheme: () => {
    // dark by default; the theme object is a plain value
    return VUI.theme();
  },
  color: (v) => {
    return __vrColor(v);
  },
  toast: (msg, o) => {
    VUI.toast(msg, o);
  },
  dialog: (o) => {
    VUI.dialog(o);
  },
  onFrame: (cb) => {
    __vrInstallFrame();
    __vrFrameCbs.push(cb);
  },
  useFrame: useFrame,
  useViewport: useViewport,
  metrics: () => {
    return VUI.metrics();
  },
  // 3D building blocks for imperative use (inside useFrame, refs, escape hatch).
  g3: () => {
    return G3;
  },
  interval: (ms, cb) => {
    return GTimer.periodic(ms, cb);
  },
  timeout: (ms, cb) => {
    return GTimer.after(ms, cb);
  },
};

// ---------------------------------------------------------------------------
// primitive components — capitalised host wrappers so a component tree reads
// like React Native (`<View>`, `<Text>`, `<Button>` …) as well as web tags.
// ---------------------------------------------------------------------------

function View(props) { return jsx("view", props); }
function Row(props) { return jsx("row", props); }
function Column(props) { return jsx("column", props); }
function Stack(props) { return jsx("stack", props); }
function Scroll(props) { return jsx("scroll", props); }
function Center(props) { return jsx("center", props); }
function Panel(props) { return jsx("panel", props); }
function Card(props) { return jsx("card", props); }
function Grid(props) { return jsx("grid", props); }
function Text(props) { return jsx("text", props); }
function Heading(props) { return jsx("heading", props); }
function Caption(props) { return jsx("caption", props); }
function Icon(props) { return jsx("icon", props); }
function Button(props) { return jsx("button", props); }
function TextInput(props) { return jsx("input", props); }
function Image(props) { return jsx("image", props); }
function Progress(props) { return jsx("progress", props); }
function Slider(props) { return jsx("slider", props); }
function Switch(props) { return jsx("switch", props); }
function Checkbox(props) { return jsx("checkbox", props); }
function Divider(props) { return jsx("divider", props); }
function Spacer(props) { return jsx("spacer", props); }

function TextArea(props) { return jsx("textarea", props); }
function Chip(props) { return jsx("chip", props); }
function BadgePill(props) { return jsx("badge", props); }
function Avatar(props) { return jsx("avatar", props); }
function Fab(props) { return jsx("fab", props); }
function ListTile(props) { return jsx("tile", props); }
function Select(props) { return jsx("select", props); }
function RichText(props) { return jsx("richtext", props); }

// 3D primitives (the 2D<->3D bridge and the Node3D family).
function Scene3D(props) { return jsx("scene3d", props); }
function GltfModel(props) { return jsx("gltf", props); }
function Node3D(props) { return jsx("node3d", props); }
function Mesh(props) { return jsx("mesh", props); }
function Box(props) { return jsx("box", props); }
function Sphere(props) { return jsx("sphere", props); }
function Cylinder(props) { return jsx("cylinder", props); }
function Capsule(props) { return jsx("capsule", props); }
function Plane3D(props) { return jsx("plane3d", props); }
function Torus(props) { return jsx("torus", props); }
function Camera3D(props) { return jsx("camera3d", props); }
function DirectionalLight(props) { return jsx("directionallight", props); }
function OmniLight(props) { return jsx("omnilight", props); }
function SpotLight(props) { return jsx("spotlight", props); }
function Environment3D(props) { return jsx("environment", props); }
function StaticBody3D(props) { return jsx("staticbody3d", props); }
function Area3D(props) { return jsx("area3d", props); }
function CollisionShape3D(props) { return jsx("collisionshape3d", props); }
// =============================================================================
// §5  The widget registry
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
// appear, because §6 and §9 generate them from this table.
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
// §5b  The built-in widgets
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
// §6  Components — class and function, one reconciler
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
// §7  Scene3D — the 3D widget and its controller
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
// §8  Canvas — the 2D drawing widget and its controller
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
// §9  The imperative facade
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
// §10 Scoping
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
// §11 The GUI namespace
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
