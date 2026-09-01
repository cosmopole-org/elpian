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
