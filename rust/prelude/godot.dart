// =============================================================================
// godot.dart — the Elpian guest library for driving the FULL Godot engine
// =============================================================================
//
// This is the Dart-side half of the Elpian↔Godot bridge. The native half is a
// C++ GDExtension (`victor/bridge/extension/`) whose `GodotController` is a
// **reflective interpreter** of a small, uniform "Godot op" protocol — the
// same paradigm as the CanvasKit/Skia bridge (`web-demo/canvaskit_bridge.js`):
// rather than hand-wrapping Godot's ~900 classes and ~12,000 methods (which
// would always lag the engine), every op addresses the engine **by name**
// through ClassDB, so coverage is *complete by construction*:
//
//   * instantiate any registered class      (`GD.create('RigidBody3D')`)
//   * bind any engine singleton             (`GD.singleton('RenderingServer')`)
//   * call any method on any object         (`node.call('add_child', [child])`)
//   * read / write any property             (`node.set('position', Vector2(4, 2))`)
//   * read any class / global constant      (`GD.constant('Node.NOTIFICATION_READY')`)
//   * connect any signal to a Dart closure  (`btn.connect('pressed', (a) { … })`)
//   * hand any Godot API a Dart Callable    (`GD.callable((a) { … })`)
//   * load any resource                     (`GD.load('res://player.tscn')`)
//   * evaluate any expression / utility fn  (`GD.eval('clamp(x, 0.0, 1.0)', …)`)
//   * introspect everything                 (`GD.classes()`, `GD.classInfo('Node2D')`)
//   * marshal every Variant shape            (vectors, transforms, colors, rects,
//                                             packed arrays, dictionaries, node
//                                             paths, RIDs, objects, callables)
//
// Anything Godot exposes — the scene tree, all 2D/3D nodes, the servers
// (RenderingServer, PhysicsServer2D/3D, NavigationServer2D/3D, AudioServer,
// DisplayServer, XRServer), Input, resources, shaders, tweens, viewports,
// multiplayer, GUI — is reachable with no exceptions, including classes added
// in future Godot versions.
//
// ## Performance model
//
// Crossing the VM↔host seam has a cost, so the bridge is built around three
// rules:
//   1. **Batching** — `GD.beginBatch()` … `GD.endBatch()` coalesces any number
//      of ops into ONE host call (`godot.batch`). Scene construction, per-frame
//      multi-op updates, and server (RID) command streams should batch.
//   2. **Retained scene graph** — Godot itself renders retained nodes; the
//      guest does *not* redraw per frame. Steady-state per-frame Dart work is
//      game logic plus a handful of property writes.
//   3. **Host-side handle table** — objects never cross the seam; 64-bit
//      handles do. The C++ side caches StringNames and method binds.
//
// ## Ids
//
// Guest-allocated handles (from `def`) are positive and count up; host-assigned
// handles (objects returned by calls) are negative and count down. Zero is
// never a valid handle.
//
// ## Errors
//
// A failed op resumes the guest with `{ "__dart_error__": … }`, which the
// front-end lowers back into a Dart `throw` — Godot errors are Dart exceptions.

// ---------------------------------------------------------------------------
// internals: ids, callback table, batch buffer
// ---------------------------------------------------------------------------

var __gdNextId = 1; // guest-side handle allocator (positive ids)
var __gdNextCb = 1; // callback ids for signals / Callables
var __gdCallbacks = {}; // cbId -> Dart closure

// When non-null, ops are appended here instead of crossing the seam; flushed
// as one `godot.batch` host call by GD.endBatch().
var __gdBatch = null;

int __gdAllocId() {
  var id = __gdNextId;
  __gdNextId = __gdNextId + 1;
  return id;
}

int __gdRegisterCb(Function cb) {
  var id = __gdNextCb;
  __gdNextCb = __gdNextCb + 1;
  __gdCallbacks["cb" + id] = cb;
  return id;
}

/// Run one op: immediately (one `godot.op` host call), or queue it when a
/// batch is open. Batched ops return null — read results after endBatch().
dynamic __gdRun(op) {
  if (__gdBatch != null) {
    __gdBatch.add(op);
    return null;
  }
  return __gdUnmarshal(askHost("godot.op", [op]));
}

// ---------------------------------------------------------------------------
// marshaling: Dart values -> tagged JSON the C++ controller turns into Variants
// ---------------------------------------------------------------------------

/// Convert one Dart argument into its wire shape. Scalars pass through;
/// bridge value-types tag themselves; GObj handles become `{"ref": id}`;
/// closures become live Godot Callables; lists/maps marshal recursively.
dynamic __gdMarshal(v) {
  // Scalars first: null is represented as 0 in the VM, so numeric/string/bool
  // checks must run before the null check or `0` would marshal as null.
  if (v is num) {
    return v;
  }
  if (v is String) {
    return v;
  }
  if (v is bool) {
    return v;
  }
  if (v == null) {
    return null;
  }
  if (v is GObj) {
    return {"ref": v.id};
  }
  if (v is Vector2) {
    return {"vec2": [v.x, v.y]};
  }
  if (v is Vector2i) {
    return {"vec2i": [v.x, v.y]};
  }
  if (v is Vector3) {
    return {"vec3": [v.x, v.y, v.z]};
  }
  if (v is Vector3i) {
    return {"vec3i": [v.x, v.y, v.z]};
  }
  if (v is Vector4) {
    return {"vec4": [v.x, v.y, v.z, v.w]};
  }
  if (v is Vector4i) {
    return {"vec4i": [v.x, v.y, v.z, v.w]};
  }
  if (v is Color) {
    return {"color": [v.r, v.g, v.b, v.a]};
  }
  if (v is Rect2) {
    return {"rect2": [v.x, v.y, v.w, v.h]};
  }
  if (v is Rect2i) {
    return {"rect2i": [v.x, v.y, v.w, v.h]};
  }
  if (v is Plane) {
    return {"plane": [v.nx, v.ny, v.nz, v.d]};
  }
  if (v is Quaternion) {
    return {"quat": [v.x, v.y, v.z, v.w]};
  }
  if (v is AABB) {
    return {"aabb": [v.px, v.py, v.pz, v.sx, v.sy, v.sz]};
  }
  if (v is Basis) {
    return {"basis": v.rows};
  }
  if (v is Transform2D) {
    return {"xform2d": v.m};
  }
  if (v is Transform3D) {
    return {"xform3d": v.m};
  }
  if (v is Projection) {
    return {"proj": v.m};
  }
  if (v is StringName) {
    return {"sname": v.value};
  }
  if (v is NodePath) {
    return {"npath": v.value};
  }
  if (v is GRid) {
    return {"rid": v.id};
  }
  if (v is GSignal) {
    return {"sig": [__gdMarshal(v.source), v.name]};
  }
  if (v is GInt) {
    return {"int": v.value};
  }
  if (v is GFloat) {
    return {"float": v.value};
  }
  if (v is GDict) {
    var pairs = [];
    for (var e in v.entries) {
      pairs.add([__gdMarshal(e[0]), __gdMarshal(e[1])]);
    }
    return {"dictv": pairs};
  }
  if (v is GCallable) {
    return {"callable": v.cbId};
  }
  if (v is Packed) {
    var out = {};
    out[v.tag] = v.data;
    return out;
  }
  if (v is Function) {
    // A bare Dart closure handed to any Godot API becomes a Callable bound to
    // the native SignalRelay; invocations are queued and dispatched back into
    // the VM (fire-and-forget — see the README's reentrancy note).
    return {"callable": __gdRegisterCb(v)};
  }
  if (v is List) {
    var out = [];
    for (var e in v) {
      out.add(__gdMarshal(e));
    }
    return out;
  }
  if (v is Map) {
    // A plain Dart map becomes a Godot Dictionary (values marshal recursively).
    var out = {};
    for (var k in v.keys) {
      out["" + k] = __gdMarshal(v[k]);
    }
    return {"dict": out};
  }
  return v;
}

/// Marshal an argument list (null-safe: absent -> []).
dynamic __gdMarshalList(args) {
  if (args == null) {
    return [];
  }
  var out = [];
  for (var a in args) {
    out.add(__gdMarshal(a));
  }
  return out;
}

/// Convert one host reply into Dart values: tagged shapes become bridge
/// value-types, `{"obj": id, "class": c}` becomes a GObj proxy, containers
/// convert recursively, scalars pass through.
dynamic __gdUnmarshal(v) {
  if (v is num) {
    return v;
  }
  if (v is String) {
    return v;
  }
  if (v is bool) {
    return v;
  }
  if (v == null) {
    return null;
  }
  if (v is List) {
    var out = [];
    for (var e in v) {
      out.add(__gdUnmarshal(e));
    }
    return out;
  }
  if (v is Map) {
    if (v["__dart_error__"] != null) {
      return v; // the front-end lowers this into a throw before user code sees it
    }
    if (v["obj"] != null) {
      return GObj(v["obj"], v["class"] ?? "Object");
    }
    if (v["vec2"] != null) {
      var a = v["vec2"];
      return Vector2(a[0], a[1]);
    }
    if (v["vec2i"] != null) {
      var a = v["vec2i"];
      return Vector2i(a[0], a[1]);
    }
    if (v["vec3"] != null) {
      var a = v["vec3"];
      return Vector3(a[0], a[1], a[2]);
    }
    if (v["vec3i"] != null) {
      var a = v["vec3i"];
      return Vector3i(a[0], a[1], a[2]);
    }
    if (v["vec4"] != null) {
      var a = v["vec4"];
      return Vector4(a[0], a[1], a[2], a[3]);
    }
    if (v["vec4i"] != null) {
      var a = v["vec4i"];
      return Vector4i(a[0], a[1], a[2], a[3]);
    }
    if (v["color"] != null) {
      var a = v["color"];
      return Color(a[0], a[1], a[2], a[3]);
    }
    if (v["rect2"] != null) {
      var a = v["rect2"];
      return Rect2(a[0], a[1], a[2], a[3]);
    }
    if (v["rect2i"] != null) {
      var a = v["rect2i"];
      return Rect2i(a[0], a[1], a[2], a[3]);
    }
    if (v["plane"] != null) {
      var a = v["plane"];
      return Plane(a[0], a[1], a[2], a[3]);
    }
    if (v["quat"] != null) {
      var a = v["quat"];
      return Quaternion(a[0], a[1], a[2], a[3]);
    }
    if (v["aabb"] != null) {
      var a = v["aabb"];
      return AABB(a[0], a[1], a[2], a[3], a[4], a[5]);
    }
    if (v["basis"] != null) {
      return Basis(v["basis"]);
    }
    if (v["xform2d"] != null) {
      return Transform2D(v["xform2d"]);
    }
    if (v["xform3d"] != null) {
      return Transform3D(v["xform3d"]);
    }
    if (v["proj"] != null) {
      return Projection(v["proj"]);
    }
    if (v["sname"] != null) {
      return StringName(v["sname"]);
    }
    if (v["npath"] != null) {
      return NodePath(v["npath"]);
    }
    if (v["rid"] != null) {
      return GRid(v["rid"]);
    }
    if (v["u8"] != null) {
      return Packed("u8", v["u8"]);
    }
    if (v["i32"] != null) {
      return Packed("i32", v["i32"]);
    }
    if (v["i64"] != null) {
      return Packed("i64", v["i64"]);
    }
    if (v["f32"] != null) {
      return Packed("f32", v["f32"]);
    }
    if (v["f64"] != null) {
      return Packed("f64", v["f64"]);
    }
    if (v["strs"] != null) {
      return Packed("strs", v["strs"]);
    }
    if (v["pv2"] != null) {
      return Packed("pv2", v["pv2"]);
    }
    if (v["pv3"] != null) {
      return Packed("pv3", v["pv3"]);
    }
    if (v["pv4"] != null) {
      return Packed("pv4", v["pv4"]);
    }
    if (v["pcol"] != null) {
      return Packed("pcol", v["pcol"]);
    }
    if (v["dict"] != null) {
      var src = v["dict"];
      var out = {};
      for (var k in src.keys) {
        out[k] = __gdUnmarshal(src[k]);
      }
      return out;
    }
    if (v["dictv"] != null) {
      var d = GDict();
      for (var e in v["dictv"]) {
        d.put(__gdUnmarshal(e[0]), __gdUnmarshal(e[1]));
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

/// Native side invokes `__godotDispatch([cbId, [args…]])` to deliver a bridged
/// signal emission or Callable invocation to its registered Dart closure. The
/// closure receives the (unmarshaled) signal-argument list.
void __godotDispatch(args) {
  var cb = __gdCallbacks["cb" + args[0]];
  if (cb != null) {
    cb(__gdUnmarshal(args[1]));
  }
}

// Engine lifecycle handlers, registered via GD.onReady/onProcess/…; the native
// ElpianVM node invokes `__godotEvent(["_process", payload])` at each hook.
var __gdHandlers = {};

void __godotEvent(args) {
  var h = __gdHandlers[args[0]];
  if (h != null) {
    h(__gdUnmarshal(args[1]));
  }
}

/// Bind an engine singleton (shared implementation for GD.singleton and the
/// named sugar accessors — see the note on static-call resolution there).
GObj __gdSingleton(String name) {
  var id = __gdAllocId();
  __gdRun({"singleton": name, "def": id});
  return GObj(id, name);
}

// ---------------------------------------------------------------------------
// GD — the engine facade
// ---------------------------------------------------------------------------

class GD {
  // ---- raw reflective core (everything else is sugar over these) ----------

  /// Execute one raw bridge op — the full-power escape hatch.
  static dynamic op(m) => __gdRun(m);

  /// Open a batch: all following ops queue locally.
  static void beginBatch() {
    __gdBatch = [];
  }

  /// Flush the open batch as ONE host call; returns the per-op result list.
  static dynamic endBatch() {
    var b = __gdBatch;
    __gdBatch = null;
    if (b == null) {
      return [];
    }
    return __gdUnmarshal(askHost("godot.batch", [b]));
  }

  /// Marshal any Dart value to its wire shape (for hand-built raw ops).
  static dynamic m(v) => __gdMarshal(v);

  // ---- objects -------------------------------------------------------------

  /// Instantiate any ClassDB-registered class by name.
  static GObj create(String cls) {
    var id = __gdAllocId();
    __gdRun({"new": cls, "def": id});
    return GObj(id, cls);
  }

  /// Bind any engine singleton by name: 'RenderingServer', 'PhysicsServer2D',
  /// 'PhysicsServer3D', 'NavigationServer2D/3D', 'AudioServer', 'DisplayServer',
  /// 'XRServer', 'Input', 'InputMap', 'Engine', 'OS', 'Time', 'ProjectSettings',
  /// 'ResourceLoader', 'ResourceSaver', 'ClassDB', 'Marshalls', 'TextServerManager', …
  static GObj singleton(String name) => __gdSingleton(name);

  /// The SceneTree driving the game (root viewport, groups, timers, pausing).
  static GObj tree() {
    var id = __gdAllocId();
    __gdRun({"tree": true, "def": id});
    return GObj(id, "SceneTree");
  }

  /// The native ElpianVM Node hosting this program — mount point for guest-
  /// created nodes (`GD.mount(n)` == `GD.host().call('add_child', [n])`).
  static GObj host() {
    var id = __gdAllocId();
    __gdRun({"self": true, "def": id});
    return GObj(id, "ElpianVM");
  }

  /// Load any resource (scene, texture, script, shader, audio, mesh, …).
  static GObj load(String path) {
    var id = __gdAllocId();
    __gdRun({"load": path, "def": id});
    return GObj(id, "Resource");
  }

  /// Add a node under the hosting ElpianVM node (enters the scene tree).
  static void mount(GObj node) {
    __gdRun({"self": true, "method": "add_child", "args": [__gdMarshal(node)]});
  }

  // ---- values / reflection ---------------------------------------------------

  /// Any class or global constant / enum value by dotted name:
  /// `GD.constant('Node.PROCESS_MODE_ALWAYS')`, `GD.constant('KEY_ESCAPE')`.
  static dynamic constant(String name) => __gdRun({"const": name});

  /// Evaluate any Godot Expression — reaches every @GlobalScope utility
  /// function and constructor by name. `names`/`values` bind expression inputs.
  static dynamic eval(String expr, [List names, List values]) => __gdRun({
        "expr": expr,
        "names": names ?? [],
        "values": __gdMarshalList(values),
      });

  /// Wrap a Dart closure as a Godot Callable value (for APIs that take one:
  /// tweens, SceneTree.timer timeouts, Array.map on the host side, …).
  static dynamic callable(Function cb) => GCallable(__gdRegisterCb(cb));

  /// Every class registered in ClassDB (the machine-checked coverage universe).
  static dynamic classes() => __gdRun({"classes": true});

  /// Full reflection for one class: methods, properties, signals, integer
  /// constants, enums, parent class.
  static dynamic classInfo(String cls) => __gdRun({"classinfo": cls});

  /// Walk ALL of ClassDB and verify every class/method/property/signal is
  /// addressable through this bridge — the "no exceptions" audit. Returns
  /// `{classes, methods, properties, signals, constants, unreachable: […]}`.
  static dynamic audit() => __gdRun({"audit": true});

  // ---- engine lifecycle hooks ----------------------------------------------

  /// Run [cb] when the hosting node enters the tree and is ready.
  static void onReady(Function cb) {
    __gdHandlers["_ready"] = cb;
  }

  /// Run [cb] every rendered frame with the frame delta (seconds).
  static void onProcess(Function cb) {
    __gdHandlers["_process"] = cb;
  }

  /// Run [cb] every physics tick with the fixed delta (seconds).
  static void onPhysicsProcess(Function cb) {
    __gdHandlers["_physics_process"] = cb;
  }

  /// Run [cb] for every InputEvent (receives a GObj proxy of the event).
  static void onInput(Function cb) {
    __gdHandlers["_input"] = cb;
  }

  /// Run [cb] for unhandled input events.
  static void onUnhandledInput(Function cb) {
    __gdHandlers["_unhandled_input"] = cb;
  }

  /// Run [cb] with each Object.notification(what) integer on the host node.
  static void onNotification(Function cb) {
    __gdHandlers["_notification"] = cb;
  }

  /// Run [cb] just before the hosting node exits the tree (teardown).
  static void onExit(Function cb) {
    __gdHandlers["_exit_tree"] = cb;
  }

  // ---- frequently-used singletons (sugar; any name works via singleton()) --

  // (Via the global helper: a bare static-to-static call does not resolve in
  // the front-end's emitter, and a `GD.` receiver inside class GD does not
  // either.)
  static GObj input() => __gdSingleton("Input");
  static GObj renderingServer() => __gdSingleton("RenderingServer");
  static GObj physicsServer2D() => __gdSingleton("PhysicsServer2D");
  static GObj physicsServer3D() => __gdSingleton("PhysicsServer3D");
  static GObj navigationServer2D() => __gdSingleton("NavigationServer2D");
  static GObj navigationServer3D() => __gdSingleton("NavigationServer3D");
  static GObj audioServer() => __gdSingleton("AudioServer");
  static GObj displayServer() => __gdSingleton("DisplayServer");
  static GObj xrServer() => __gdSingleton("XRServer");
  static GObj engine() => __gdSingleton("Engine");
  static GObj os() => __gdSingleton("OS");
  static GObj time() => __gdSingleton("Time");
  static GObj projectSettings() => __gdSingleton("ProjectSettings");
  static GObj resourceLoader() => __gdSingleton("ResourceLoader");
  static GObj resourceSaver() => __gdSingleton("ResourceSaver");
}

// ---------------------------------------------------------------------------
// GObj — the universal object proxy (any Godot Object, Node, Resource, server)
// ---------------------------------------------------------------------------

class GObj {
  final int id;
  final String cls;
  GObj(this.id, this.cls);

  /// Call ANY method by name. `n.call('add_child', [child])`,
  /// `rs.call('canvas_item_create')`, `tween.call('tween_property', […])`.
  dynamic call(String method, [List args]) => __gdRun({
        "ref": id,
        "method": method,
        "args": __gdMarshalList(args),
      });

  /// Read ANY property. `node.get('position')` -> Vector2.
  dynamic get(String prop) => __gdRun({"ref": id, "get": prop});

  /// Write ANY property. `node.set('modulate', Color(1,0,0,1))`.
  void set(String prop, value) {
    __gdRun({"ref": id, "set": prop, "value": __gdMarshal(value)});
  }

  /// Read a nested sub-property path (Object.get_indexed): 'position:x'.
  dynamic getIndexed(String path) => __gdRun({"ref": id, "geti": path});

  /// Write a nested sub-property path: `n.setIndexed('position:x', 10.0)`.
  void setIndexed(String path, value) {
    __gdRun({"ref": id, "seti": path, "value": __gdMarshal(value)});
  }

  /// Connect ANY signal to a Dart closure; returns the callback id (keep it to
  /// disconnect). `flags` = Object.CONNECT_* bitmask (0 = default).
  int connect(String signal, Function cb, [int flags]) {
    var cbId = __gdRegisterCb(cb);
    __gdRun({"ref": id, "connect": signal, "cb": cbId, "flags": flags ?? 0});
    return cbId;
  }

  /// Disconnect a connection made with [connect].
  void disconnect(String signal, int cbId) {
    __gdRun({"ref": id, "disconnect": signal, "cb": cbId});
  }

  /// Emit ANY signal with arguments.
  dynamic emitSignal(String signal, [List args]) {
    var a = [];
    a.add({"sname": signal});
    if (args != null) {
      for (var x in args) {
        a.add(__gdMarshal(x));
      }
    }
    return __gdRun({"ref": id, "method": "emit_signal", "args": a});
  }

  /// A first-class reference to one of this object's signals.
  GSignal signal(String name) => GSignal(this, name);

  /// Node.queue_free() — safe deletion at end of frame (also drops the handle).
  void queueFree() {
    __gdRun({"free": id, "mode": "queue"});
  }

  /// Immediate Object.free() / memdelete (also drops the handle).
  void freeNow() {
    __gdRun({"free": id, "mode": "now"});
  }

  /// Drop only the bridge handle (unreferences a RefCounted; never deletes a
  /// plain Object). Use for resources/objects the engine still owns.
  void release() {
    __gdRun({"free": id, "mode": "handle"});
  }
}

/// A Callable wire value produced by GD.callable() (rarely needed directly —
/// bare closures marshal automatically).
class GCallable {
  final int cbId;
  GCallable(this.cbId);
}

/// A first-class Signal value (marshals to Godot's Signal Variant).
class GSignal {
  final GObj source;
  final String name;
  GSignal(this.source, this.name);
}

// ---------------------------------------------------------------------------
// value types — the full Godot Variant vocabulary
// ---------------------------------------------------------------------------

class Vector2 {
  final double x;
  final double y;
  Vector2(this.x, this.y);
  static Vector2 zero() => Vector2(0.0, 0.0);
  static Vector2 one() => Vector2(1.0, 1.0);
  // Named plus/minus/times (not add/…): a user-class `add` would shadow the
  // front-end's List.add → push rewrite for every dynamic receiver in the
  // program (see dart2elpian's `resolve_member`).
  Vector2 plus(Vector2 o) => Vector2(x + o.x, y + o.y);
  Vector2 minus(Vector2 o) => Vector2(x - o.x, y - o.y);
  Vector2 times(double s) => Vector2(x * s, y * s);
  double dot(Vector2 o) => x * o.x + y * o.y;
  double lengthSquared() => x * x + y * y;
}

class Vector2i {
  final int x;
  final int y;
  Vector2i(this.x, this.y);
}

class Vector3 {
  final double x;
  final double y;
  final double z;
  Vector3(this.x, this.y, this.z);
  static Vector3 zero() => Vector3(0.0, 0.0, 0.0);
  static Vector3 one() => Vector3(1.0, 1.0, 1.0);
  Vector3 plus(Vector3 o) => Vector3(x + o.x, y + o.y, z + o.z);
  Vector3 minus(Vector3 o) => Vector3(x - o.x, y - o.y, z - o.z);
  Vector3 times(double s) => Vector3(x * s, y * s, z * s);
  double dot(Vector3 o) => x * o.x + y * o.y + z * o.z;
  Vector3 cross(Vector3 o) =>
      Vector3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double lengthSquared() => x * x + y * y + z * z;
}

class Vector3i {
  final int x;
  final int y;
  final int z;
  Vector3i(this.x, this.y, this.z);
}

class Vector4 {
  final double x;
  final double y;
  final double z;
  final double w;
  Vector4(this.x, this.y, this.z, this.w);
}

class Vector4i {
  final int x;
  final int y;
  final int z;
  final int w;
  Vector4i(this.x, this.y, this.z, this.w);
}

class Color {
  final double r;
  final double g;
  final double b;
  final double a;
  Color(this.r, this.g, this.b, this.a);
  static Color rgb(double r, double g, double b) => Color(r, g, b, 1.0);
  /// From a 0xAARRGGBB int (Flutter-style), e.g. Color.hex(0xFF2196F3).
  static Color hex(int argb) {
    var aa = ((argb ~/ 16777216) % 256) / 255.0;
    var rr = ((argb ~/ 65536) % 256) / 255.0;
    var gg = ((argb ~/ 256) % 256) / 255.0;
    var bb = (argb % 256) / 255.0;
    return Color(rr, gg, bb, aa);
  }
}

class Rect2 {
  final double x;
  final double y;
  final double w;
  final double h;
  Rect2(this.x, this.y, this.w, this.h);
}

class Rect2i {
  final int x;
  final int y;
  final int w;
  final int h;
  Rect2i(this.x, this.y, this.w, this.h);
}

class Plane {
  final double nx;
  final double ny;
  final double nz;
  final double d;
  Plane(this.nx, this.ny, this.nz, this.d);
}

class Quaternion {
  final double x;
  final double y;
  final double z;
  final double w;
  Quaternion(this.x, this.y, this.z, this.w);
  static Quaternion identity() => Quaternion(0.0, 0.0, 0.0, 1.0);
}

class AABB {
  final double px;
  final double py;
  final double pz;
  final double sx;
  final double sy;
  final double sz;
  AABB(this.px, this.py, this.pz, this.sx, this.sy, this.sz);
}

/// Row-major 9 floats [xx,xy,xz, yx,yy,yz, zx,zy,zz].
class Basis {
  final List rows;
  Basis(this.rows);
  static Basis identity() =>
      Basis([1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]);
}

/// Column-vector 6 floats [ax,ay, bx,by, ox,oy] (x-axis, y-axis, origin).
class Transform2D {
  final List m;
  Transform2D(this.m);
  static Transform2D identity() => Transform2D([1.0, 0.0, 0.0, 1.0, 0.0, 0.0]);
  static Transform2D translated(double x, double y) =>
      Transform2D([1.0, 0.0, 0.0, 1.0, x, y]);
}

/// Basis rows then origin: 12 floats [xx..zz, ox,oy,oz].
class Transform3D {
  final List m;
  Transform3D(this.m);
  static Transform3D identity() => Transform3D(
      [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0]);
  static Transform3D translated(double x, double y, double z) => Transform3D(
      [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, x, y, z]);
}

/// Column-major 16 floats.
class Projection {
  final List m;
  Projection(this.m);
}

class StringName {
  final String value;
  StringName(this.value);
}

class NodePath {
  final String value;
  NodePath(this.value);
}

/// A server-side resource id (RenderingServer/PhysicsServer handles).
class GRid {
  final int id;
  GRid(this.id);
}

/// Force integer typing for an ambiguous numeric argument.
class GInt {
  final int value;
  GInt(this.value);
}

/// Force float typing for an ambiguous numeric argument.
class GFloat {
  final double value;
  GFloat(this.value);
}

/// A Godot Dictionary with non-string (or order-sensitive) keys.
class GDict {
  var entries = [];
  GDict();
  void put(k, v) {
    entries.add([k, v]);
  }
}

/// A packed array wire value. tag ∈ u8 (base64 String) | i32 | i64 | f32 |
/// f64 | strs | pv2 | pv3 | pv4 | pcol (flat number lists).
class Packed {
  final String tag;
  final dynamic data;
  Packed(this.tag, this.data);
  static Packed bytesBase64(String b64) => Packed("u8", b64);
  static Packed i32(List v) => Packed("i32", v);
  static Packed i64(List v) => Packed("i64", v);
  static Packed f32(List v) => Packed("f32", v);
  static Packed f64(List v) => Packed("f64", v);
  static Packed strings(List v) => Packed("strs", v);
  static Packed vector2s(List flatXY) => Packed("pv2", flatXY);
  static Packed vector3s(List flatXYZ) => Packed("pv3", flatXYZ);
  static Packed vector4s(List flatXYZW) => Packed("pv4", flatXYZW);
  static Packed colors(List flatRGBA) => Packed("pcol", flatRGBA);
}

// ---------------------------------------------------------------------------
// VMs — orchestrating the multi-VM tree
// ---------------------------------------------------------------------------
//
// A program running on Elpian can instantiate further Elpian VMs into the SAME
// Godot scene and hold complete control of them: lifecycle (pause / resume /
// terminate), resource limits, capability permissions and messaging. The VM
// graph is a tree; every rule is hierarchical:
//
//   * terminating a VM terminates its whole descendant subtree;
//   * a VM's resource usage is accounted as its own PLUS its subtree's, and an
//     aggregate overrun of its own budget kills the whole branch;
//   * a VM's effective permissions are the AND of the grants along its
//     ancestor path — a parent can only confer what it holds, and on-the-fly
//     changes propagate to the whole subtree instantly.
//
// Every spawned VM is assigned a NODE in the shared scene (it must lie inside
// the parent's own sandbox) and all of its engine access is confined to that
// node's subtree. The parent can freely manipulate the child's nodes (they are
// inside its own sandbox); the child can never reach out. The root VM manages
// the whole scene and the inter-VM space; the `scene` permission confers that
// unrestricted role explicitly.
//
// Gated by the `vm_manage` capability: a VM whose parent revoked it gets null
// replies from every `vm.*` call (`VMs.spawn` then returns null).
//
// Failures reply as `{ "__dart_error__": … }` maps — check `VMs.isError(r)`.

// Handlers: "message" -> cb(senderId, msg);
// "notify" / "notify:<kind>" -> cb(kind, vmId, detail).
var __vmHandlers = {};

/// The manager delivers child notifications here:
/// `["trapped", vmId, reason]` (a child hit its own resource governor) or
/// `["terminated", vmId, reason]` (a child branch was removed).
void __vmNotify(args) {
  var h = __vmHandlers["notify:" + args[0]];
  if (h != null) {
    h(args[0], args[1], args[2]);
    return;
  }
  var all = __vmHandlers["notify"];
  if (all != null) {
    all(args[0], args[1], args[2]);
  }
}

/// The manager delivers inter-VM messages here: `[senderVmId, message]`.
void __vmMessage(args) {
  var h = __vmHandlers["message"];
  if (h != null) {
    h(args[0], args[1]);
  }
}

/// Shared spawn implementation (global helper: a static-to-static call does
/// not resolve in the front-end's emitter — see the GD singleton note).
dynamic __vmSpawnRaw(String source, GObj node, Map options) {
  var opts = {};
  if (options != null) {
    for (var k in options.keys) {
      opts[k] = options[k];
    }
  }
  opts["node"] = node.id;
  var r = askHost("vm.spawn", [source, opts]);
  if (r is num) {
    return r; // the child's vm id
  }
  if (r is Map) {
    return r; // an {__dart_error__: …} failure
  }
  // A capability-denied call short-circuits to the VM's typed null, which is
  // NOT the guest-level null; normalize so `== null` works for callers.
  return null;
}

/// Control handle over one VM in the caller's subtree. Obtained from
/// `VMs.spawn(...)` or `VMs.of(id)`. Every verb is authorized against the VM
/// tree: only the VM itself, or one of its ancestors, may steer it.
class VmController {
  final int id;
  VmController(this.id);

  // ---- lifecycle -----------------------------------------------------------

  /// Suspend the VM and its whole subtree: no events, no timers, no messages.
  /// A VM mid-turn parks at its next interpreter step, continuation intact.
  dynamic pause() => askHost("vm.pause", [id]);

  /// Resume a paused subtree exactly where it stopped.
  dynamic resume() => askHost("vm.resume", [id]);

  /// Terminate the VM and its whole descendant subtree (rule 1 of the tree).
  dynamic terminate() => askHost("vm.terminate", [id]);

  /// `{id, label, state, trap, paused, alive}`.
  dynamic state() => askHost("vm.state", [id]);

  // ---- resources -----------------------------------------------------------

  /// This VM's own live usage tally.
  dynamic usage() => askHost("vm.usage", [id]);

  /// Aggregate usage of the VM plus its whole descendant subtree — the figure
  /// its own budget is enforced against.
  dynamic usageTree() => askHost("vm.usageTree", [id]);

  /// Current limit policy (`{instructions, instructionsPerTurn, memoryBytes,
  /// storageBytes, callDepth}`, null = unbounded).
  dynamic limits() => askHost("vm.limits", [id]);

  /// Replace the limit policy on the fly (same keys as [limits]).
  dynamic setLimits(Map limits) => askHost("vm.setLimits", [id, limits]);

  // ---- permissions ---------------------------------------------------------

  /// Toggle one permission: a capability name ('network', 'storage', 'clock',
  /// 'randomness', 'gpu', 'logging', 'module_import', 'vm_manage', 'other') or
  /// 'scene' (whole-scene access). Effective permissions are recomputed for
  /// the VM's entire subtree immediately.
  dynamic setPermission(String name, bool allowed) =>
      askHost("vm.setPermission", [id, name, allowed]);

  /// `{scene, local: {…}, effective: {…}}`.
  dynamic permissions() => askHost("vm.permissions", [id]);

  /// Share one of the caller's bridge handles (a resource, an object) with
  /// this VM's sandbox, so it may use it despite the ownership isolation.
  dynamic grant(GObj obj) => askHost("vm.grant", [id, obj.id]);

  // ---- messaging / introspection --------------------------------------------

  /// Deliver a message to this VM's `VMs.onMessage` handler.
  dynamic send(msg) => askHost("vm.send", [id, msg]);

  /// Direct children of this VM: `[{id, label, paused, alive}, …]`.
  dynamic children() => askHost("vm.list", [id]);
}

/// The multi-VM orchestration facade.
class VMs {
  /// Instantiate and boot a new child VM running [source] (a guest program,
  /// with the full godot.dart prelude in scope), sandboxed to [node] — a node
  /// inside the caller's own sandbox that becomes the child's whole world.
  ///
  /// [options]:
  ///   'label'         — display name (logs, dashboards);
  ///   'limits'        — `{instructions, instructionsPerTurn, memoryBytes,
  ///                      storageBytes, callDepth}` resource budget, enforced
  ///                      against the child's aggregate subtree usage;
  ///   'permissions'   — `{capabilityName: bool, …}` local grants (ANDed with
  ///                      the caller's own effective set);
  ///   'maxHostCalls' / 'maxBytesMoved' — the child's host-seam meter;
  ///   'scene'         — grant whole-scene access (needs the caller to hold it).
  ///
  /// The child compiles now; its `main()` runs (and its `_ready` fires) within
  /// the current engine frame. Returns null when denied (`vm_manage` revoked)
  /// or failed — use [trySpawn] for the raw error reply.
  static VmController spawn(String source, GObj node, [Map options]) {
    var r = __vmSpawnRaw(source, node, options);
    if (r is num) {
      return VmController(r);
    }
    return null;
  }

  /// Like [spawn] but returns the raw reply: the child's vm id (num) on
  /// success, an `{__dart_error__: …}` map on failure, or null when the
  /// caller's `vm_manage` capability is off.
  static dynamic trySpawn(String source, GObj node, [Map options]) =>
      __vmSpawnRaw(source, node, options);

  /// Whether a `vm.*` reply is an error map.
  static bool isError(r) {
    if (r is Map) {
      return r["__dart_error__"] != null;
    }
    return false;
  }

  /// A control handle for an already-known vm id.
  static VmController of(int id) => VmController(id);

  /// This VM's own identity: `{id, parent, label, scene, node}`.
  static dynamic info() => askHost("vm.info", []);

  /// The caller's direct children: `[{id, label, paused, alive}, …]`.
  static dynamic children() => askHost("vm.list", []);

  /// Send a message up to the parent VM (delivered to its `onMessage`).
  static dynamic sendParent(msg) {
    var i = askHost("vm.info", []);
    if (i != null && i["parent"] != null) {
      return askHost("vm.send", [i["parent"], msg]);
    }
    return null;
  }

  /// Receive inter-VM messages: `cb(senderVmId, message)`.
  static void onMessage(Function cb) {
    __vmHandlers["message"] = cb;
  }

  /// Receive every child notification: `cb(kind, vmId, detail)` with kind
  /// 'trapped' or 'terminated'.
  static void onNotify(Function cb) {
    __vmHandlers["notify"] = cb;
  }

  /// Only 'trapped' notifications (a child hit its own resource governor —
  /// e.g. a hung child cut off by its per-turn instruction cap).
  static void onChildTrapped(Function cb) {
    __vmHandlers["notify:trapped"] = cb;
  }

  /// Only 'terminated' notifications (a child branch was removed).
  static void onChildTerminated(Function cb) {
    __vmHandlers["notify:terminated"] = cb;
  }
}

/// Timers riding the VM's own event loop (`dart:async` host hooks) — pumped
/// once per engine frame by the ElpianVM node. Callbacks take NO parameters
/// (the VM's `__dartDispatch` invokes them argument-free). Named GTimer so it
/// cannot shadow Godot's own `Timer` node (`GD.create('Timer')`).
class GTimer {
  final int id;
  GTimer(this.id);

  /// Run [cb] every [milliseconds] until cancelled.
  static GTimer periodic(int milliseconds, Function cb) {
    __cbReg.add(cb);
    return GTimer(
        askHost("dart:async/Timer.periodic", [__cbReg.length - 1, milliseconds]));
  }

  /// Run [cb] once after [milliseconds].
  static GTimer after(int milliseconds, Function cb) {
    __cbReg.add(cb);
    return GTimer(askHost("dart:async/Timer", [__cbReg.length - 1, milliseconds]));
  }

  bool cancel() => askHost("dart:async/Timer.cancel", [id]);
}
