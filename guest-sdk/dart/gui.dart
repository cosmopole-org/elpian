// =============================================================================
// gui.dart — the Elpian GUI SDK for Dart
// =============================================================================
//
// The Dart twin of `gui.js`: everything a mini app written in Dart needs to
// draw itself, in one file, reached with one import.
//
//     import 'gui.dart';
//
//     class Counter extends StatefulWidget {
//       State createState() => CounterState();
//     }
//     class CounterState extends State {
//       int n = 0;
//       Widget build(BuildContext context) => Column(children: [
//         Text('count: $n'),
//         ElevatedButton(child: Text('+1'), onPressed: () => setState(() { n = n + 1; })),
//       ]);
//     }
//     void main() => runApp(Counter());
//
// ## Why one file
//
// This was two libraries that never met. `godot.dart` was the engine
// transport — `GD`/`GObj` addressing Godot reflectively through `ClassDB` over
// the `godot.op` seam, building a *retained* scene graph the engine paints.
// `flutter.dart` was a Flutter-shaped widget library with its own two-phase
// layout that paints *immediately* through `dart:ui`. Two rendering models,
// two composers in two different Rust crates, and no program could use both.
//
// They are one file now and the two are deleted, exactly as `gui.js` merged
// the four JavaScript preludes. A Dart guest gets one import and one
// vocabulary; the two backends remain two backends, because they genuinely
// render differently, but they now share a namespace, a value-type layer and
// a composer — and a widget written against one can sit inside the other.
//
// ## The two backends, and when to reach for each
//
//   * The **widget layer** (§3–§6) is the default. `StatelessWidget`,
//     `StatefulWidget`, `setState`, `runApp` — ordinary Flutter, painted
//     through `dart:ui`. Portable, and what a UI-shaped mini app wants.
//   * The **engine layer** (§1) is for anything the widget layer cannot
//     express: 3D, shaders, physics, or any Godot class at all. `GD.create`
//     reaches every registered class reflectively, so its coverage is complete
//     by construction rather than by hand-wrapping.
//
// The seam between them is §7: `Scene3D` and `Canvas` are widgets on the
// outside and controllers over the engine on the inside, so a Flutter tree can
// embed a 3D world without either backend knowing about the other.
//
// ## Layout
//
//   §1  Engine transport      GD / GObj, marshaling, callbacks, value types
//   §2  Painting values       Color, Offset, Size, EdgeInsets, TextStyle, …
//   §3  Widgets               Widget / StatelessWidget / StatefulWidget / State
//   §4  Layout and painting   the two-phase layout pass and the dart:ui seam
//   §5  The widget set        the Material-shaped widgets an app builds with
//   §6  App scaffolding       runApp, MaterialApp, Scaffold, the frame binding
//   §7  Scene3D and Canvas    engine-backed widgets and their controllers
//   §8  Theme                 design tokens shared by both backends
//   §9  The GUI namespace     what a mini app actually reaches for

// =============================================================================
// §1  Engine transport — GD, GObj, and the Godot op protocol
// =============================================================================

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
// =============================================================================
// §2  Painting values
// =============================================================================

// ---------------------------------------------------------------------------
// Color — one type, two vocabularies
// ---------------------------------------------------------------------------
//
// The two libraries merged into this file each had a `Color`, and they meant
// different things. The engine's was four doubles, matching Godot's own
// `Color`; the widget layer's was a packed 0xAARRGGBB int, matching Flutter's.
// Both are the idiom of the API they belong to, and both are written all over
// existing guests, so neither could simply win.
//
// This is one class that answers to both. Channels are stored as doubles —
// that is the lossless form, and the one the engine marshaller writes — and
// the packed int is derived on read. The unnamed constructor dispatches on
// arity, which is unambiguous because the two forms never shared one:
//
//     Color(0xFF2196F3)              // Flutter: one packed ARGB int
//     Color(1.0, 0.5, 0.25, 1.0)     // Godot:   r, g, b, a
//
// Everything else — the named constructors, `value`, the channel accessors —
// works whichever way the color was built, so a widget can tint a Godot node
// and an engine color can go to `dart:ui` with no conversion at the call site.
//
// The fields are assigned in the constructor *body* rather than an initializer
// list. `dart2elpian` parses `: field = expr` and then erases it, so an
// initializer list here would compile and leave every channel unset.
class Color {
  var r;
  var g;
  var b;
  var a;

  /// The packed 0xAARRGGBB form, which is what the `dart:ui` seam takes.
  ///
  /// A stored field rather than a getter: it is read once per painted node per
  /// frame, and the widget layer reads it as `color.value` — a plain property
  /// access, which is what it was before the merge.
  var value;

  Color(x, [g_, b_, a_]) {
    if (g_ == null) {
      // One argument: a packed 0xAARRGGBB int.
      this.a = ((x ~/ 16777216) % 256) / 255.0;
      this.r = ((x ~/ 65536) % 256) / 255.0;
      this.g = ((x ~/ 256) % 256) / 255.0;
      this.b = (x % 256) / 255.0;
    } else {
      this.r = x;
      this.g = g_;
      this.b = b_;
      this.a = a_ == null ? 1.0 : a_;
    }
    this.value = (__c8(this.a) * 16777216) +
        (__c8(this.r) * 65536) +
        (__c8(this.g) * 256) +
        __c8(this.b);
  }

  /// Opaque color from three 0.0–1.0 channels.
  static Color rgb(double r, double g, double b) => Color(r, g, b, 1.0);

  /// From a 0xAARRGGBB int, e.g. `Color.hex(0xFF2196F3)`.
  static Color hex(int argb) => Color(argb);

  /// From 8-bit alpha/red/green/blue channels.
  static Color fromARGB(int a, int r, int g, int b) =>
      Color(r / 255.0, g / 255.0, b / 255.0, a / 255.0);

  /// From 8-bit r/g/b and a 0.0–1.0 opacity.
  static Color fromRGBO(int r, int g, int b, double opacity) =>
      Color(r / 255.0, g / 255.0, b / 255.0, opacity);

  int alpha() => __c8(this.a);
  int red() => __c8(this.r);
  int green() => __c8(this.g);
  int blue() => __c8(this.b);

  /// A copy of this color with the given opacity (0.0–1.0).
  Color withOpacity(double opacity) => Color(this.r, this.g, this.b, opacity);
}

/// One 0.0–1.0 channel as an 8-bit value, rounded rather than truncated so a
/// color built from a packed int and read back yields that same int.
int __c8(double v) {
  var n = (v * 255.0 + 0.5).toInt();
  if (n < 0) { return 0; }
  if (n > 255) { return 255; }
  return n;
}

// =============================================================================
// §3  Widgets, layout, painting and the app — the Flutter-shaped layer
// =============================================================================

// =============================================================================
// flutter.dart — a self-contained Flutter widget library for the Elpian VM
// =============================================================================
//
// This is real, idiomatic Flutter-style Dart: the widget classes, painting
// value types, and layout protocol an app imports and builds against. It is
// modelled closely on the public API of the real framework
// (`package:flutter/widgets.dart` + `painting/` + `rendering/`) — same class
// names, same constructor shapes, same composition idioms — but reimplemented
// in the subset the Elpian front-end compiles, so a whole app runs on the VM
// with no ahead-of-time compilation and no JIT.
//
// An app uses it exactly like Flutter:
//
//     import 'flutter.dart';
//
//     class MyApp extends StatelessWidget {
//       const MyApp();
//       Widget build(BuildContext context) {
//         return MaterialApp(
//           home: Scaffold(
//             backgroundColor: Colors.blueGrey,
//             body: Center(child: Text('Hello', style: TextStyle(fontSize: 32.0))),
//           ),
//         );
//       }
//     }
//     void main() => runApp(MyApp());
//
// Rendering: instead of RenderObjects talking to the GPU, each widget lowers
// itself to a `dart:ui` scene (drawRect/drawCircle/drawParagraph) via the host
// bridge; the engine rasterizes that scene. Layout is a real two-phase pass —
// `layout(constraints)` sizes and positions, `paint(offset)` emits — mirroring
// RenderBox. State is retained across frames and `setState` schedules a repaint,
// so the app is fully interactive.

// =============================================================================
// SECTION 1 — foundation
// =============================================================================

/// A [Widget]'s identity across rebuilds. (Position-based reconciliation is used
/// here, so keys are accepted for API compatibility but not yet load-bearing.)
class Key {
  final String value;
  const Key(this.value);
}

class ValueKey extends Key {
  const ValueKey(String value) { this.value = value; }
}

/// A handle to a widget's location in the tree. Minimal here: enough for
/// `build(BuildContext context)` signatures to read like Flutter.
class BuildContext {
  var widget;
  BuildContext();
}

// =============================================================================
// SECTION 2 — painting: geometry value types
// =============================================================================

/// An immutable 2D floating-point offset (a point or a vector), like
/// `dart:ui`'s [Offset].
class Offset {
  final double dx;
  final double dy;
  const Offset(this.dx, this.dy);
  static Offset zero() => Offset(0.0, 0.0);
  Offset translate(double tx, double ty) => Offset(dx + tx, dy + ty);
}

/// An immutable width/height pair, like `dart:ui`'s [Size].
class Size {
  final double width;
  final double height;
  const Size(this.width, this.height);
  static Size zero() => Size(0.0, 0.0);
  static Size square(double d) => Size(d, d);
}

/// Immutable layout constraints: a box's width is in `[minWidth, maxWidth]` and
/// height in `[minHeight, maxHeight]`. Mirrors `rendering`'s [BoxConstraints].
class BoxConstraints {
  final double minWidth;
  final double maxWidth;
  final double minHeight;
  final double maxHeight;
  const BoxConstraints(this.minWidth, this.maxWidth, this.minHeight, this.maxHeight);

  /// Constraints forcing exactly [size].
  static BoxConstraints tight(Size size) =>
      BoxConstraints(size.width, size.width, size.height, size.height);

  /// Constraints allowing anything up to [size].
  static BoxConstraints loose(Size size) =>
      BoxConstraints(0.0, size.width, 0.0, size.height);

  double clampW(double w) {
    if (w < minWidth) { return minWidth; }
    if (w > maxWidth) { return maxWidth; }
    return w;
  }

  double clampH(double h) {
    if (h < minHeight) { return minHeight; }
    if (h > maxHeight) { return maxHeight; }
    return h;
  }

  Size constrain(Size size) => Size(clampW(size.width), clampH(size.height));

  /// A copy with the max bounds reduced by [dw] x [dh] (min clamped to 0).
  BoxConstraints deflate(double dw, double dh) {
    var mw = maxWidth - dw;
    var mh = maxHeight - dh;
    if (mw < 0.0) { mw = 0.0; }
    if (mh < 0.0) { mh = 0.0; }
    return BoxConstraints(0.0, mw, 0.0, mh);
  }

  BoxConstraints get loosen => BoxConstraints(0.0, maxWidth, 0.0, maxHeight);
}

/// An immutable rectangle from left/top/right/bottom, like `dart:ui`'s [Rect].
class Rect {
  final double left;
  final double top;
  final double right;
  final double bottom;
  const Rect(this.left, this.top, this.right, this.bottom);
  static Rect fromLTWH(double l, double t, double w, double h) => Rect(l, t, l + w, t + h);
}

/// Offsets for the four edges of a box, like `painting`'s [EdgeInsets].
class EdgeInsets {
  final double left;
  final double top;
  final double right;
  final double bottom;
  // Precomputed axis totals (fields rather than getters, computed once).
  double horizontal;
  double vertical;
  EdgeInsets(this.left, this.top, this.right, this.bottom) {
    horizontal = left + right;
    vertical = top + bottom;
  }
  static EdgeInsets all(double v) => EdgeInsets(v, v, v, v);
  static EdgeInsets symmetric(double horizontal, double vertical) =>
      EdgeInsets(horizontal, vertical, horizontal, vertical);
  static EdgeInsets only(double left, double top, double right, double bottom) =>
      EdgeInsets(left, top, right, bottom);
  static EdgeInsets fromLTRB(double l, double t, double r, double b) => EdgeInsets(l, t, r, b);
  static EdgeInsets zero() => EdgeInsets(0.0, 0.0, 0.0, 0.0);
}

/// A point within a rectangle, with x and y in the range -1.0 to 1.0, like
/// `painting`'s [Alignment]. -1 is left/top, 0 is center, 1 is right/bottom.
class Alignment {
  final double x;
  final double y;
  const Alignment(this.x, this.y);
  // The nine canonical alignments.
  static Alignment topLeft() => Alignment(-1.0, -1.0);
  static Alignment topCenter() => Alignment(0.0, -1.0);
  static Alignment topRight() => Alignment(1.0, -1.0);
  static Alignment centerLeft() => Alignment(-1.0, 0.0);
  static Alignment center() => Alignment(0.0, 0.0);
  static Alignment centerRight() => Alignment(1.0, 0.0);
  static Alignment bottomLeft() => Alignment(-1.0, 1.0);
  static Alignment bottomCenter() => Alignment(0.0, 1.0);
  static Alignment bottomRight() => Alignment(1.0, 1.0);

  /// The offset that positions a child of [child] inside a box of [parent],
  /// per this alignment (mirrors Alignment.alongOffset / inscribe).
  Offset withinRect(Size parent, Size child) {
    var fx = (x + 1.0) / 2.0;
    var fy = (y + 1.0) / 2.0;
    return Offset((parent.width - child.width) * fx, (parent.height - child.height) * fy);
  }
}

// =============================================================================
// SECTION 3 — painting: colors, borders, text style
// =============================================================================

/// An immutable 32-bit ARGB color, like `dart:ui`'s [Color].

/// The Material color palette — a subset of the real `Colors` class. Each entry
/// is a fully-opaque ARGB constant, reached as `Colors.blue` etc.
class Colors {
  static const Color transparent = Color(0x00000000);
  static const Color black = Color(0xFF000000);
  static const Color white = Color(0xFFFFFFFF);
  static const Color red = Color(0xFFF44336);
  static const Color pink = Color(0xFFE91E63);
  static const Color purple = Color(0xFF9C27B0);
  static const Color indigo = Color(0xFF3F51B5);
  static const Color blue = Color(0xFF2196F3);
  static const Color lightBlue = Color(0xFF03A9F4);
  static const Color cyan = Color(0xFF00BCD4);
  static const Color teal = Color(0xFF009688);
  static const Color green = Color(0xFF4CAF50);
  static const Color lightGreen = Color(0xFF8BC34A);
  static const Color lime = Color(0xFFCDDC39);
  static const Color yellow = Color(0xFFFFEB3B);
  static const Color amber = Color(0xFFFFC107);
  static const Color orange = Color(0xFFFF9800);
  static const Color deepOrange = Color(0xFFFF5722);
  static const Color brown = Color(0xFF795548);
  static const Color grey = Color(0xFF9E9E9E);
  static const Color blueGrey = Color(0xFF607D8B);
}

/// A uniform corner radius, like `painting`'s [BorderRadius].
class BorderRadius {
  final double radius;
  const BorderRadius(this.radius);
  static BorderRadius circular(double r) => BorderRadius(r);
  static BorderRadius zero() => BorderRadius(0.0);
}

/// A box background: a fill color and optional rounded corners, a small slice of
/// `painting`'s [BoxDecoration].
class BoxDecoration {
  var color;
  var borderRadius;
  BoxDecoration({this.color, this.borderRadius});
}

/// How to weight glyphs. In the real framework this is a rich class; here it is
/// an enum whose values flow through to the paragraph style.
enum FontWeight { normal, bold }

/// Whether and how to align text horizontally, like `dart:ui`'s [TextAlign].
enum TextAlign { left, right, center }

/// An immutable style for a run of text, a subset of `painting`'s [TextStyle].
class TextStyle {
  var fontSize;
  var color;
  var fontWeight;
  TextStyle({this.fontSize, this.color, this.fontWeight});
}

// =============================================================================
// SECTION 4 — layout enums
// =============================================================================

/// The direction in which boxes flow, like `painting`'s [Axis].
enum Axis { horizontal, vertical }

/// How the children of a [Row]/[Column] are placed along the main axis.
enum MainAxisAlignment { start, end, center, spaceBetween, spaceAround, spaceEvenly }

/// How the children of a [Row]/[Column] are placed along the cross axis.
enum CrossAxisAlignment { start, end, center, stretch }

/// Whether a [Row]/[Column] shrink-wraps or expands along its main axis.
enum MainAxisSize { min, max }

// =============================================================================
// SECTION 5 — the widget framework
// =============================================================================

/// The base class for everything that describes part of the UI. Concrete
/// widgets either *compose* other widgets (via [build]) or *render* themselves
/// (by overriding the layout/paint protocol). Mirrors `widgets`'s [Widget].
abstract class Widget {
  var key;

  // ---- render protocol (a simplified, faithful stand-in for RenderBox) ----
  // The computed size, valid after `layout`.
  var size;

  /// Refresh transient expanded children from config children. Called once per
  /// frame before layout; must NOT mutate configuration.
  void inflate() {}

  /// Size this widget under [constraints], laying out and positioning children.
  /// Returns and records [size]. The default is a zero-size box.
  Size layout(BoxConstraints constraints) {
    this.size = constraints.constrain(Size.zero());
    return this.size;
  }

  /// Emit this widget's paint ops at [offset] (its top-left in the view), then
  /// paint children. Called after [layout].
  void paint(Offset offset) {}
}

/// A widget that describes its UI by composing others, and has no mutable state.
/// Subclasses implement [build]. Mirrors `widgets`'s [StatelessWidget].
abstract class StatelessWidget extends Widget {
  Widget build(BuildContext context) { return null; }
}

/// A widget with mutable [State] that persists across rebuilds. Subclasses
/// implement [createState]. Mirrors `widgets`'s [StatefulWidget].
abstract class StatefulWidget extends Widget {
  State createState() { return null; }
}

/// The logic and mutable state for a [StatefulWidget]. Mirrors `widgets`'s
/// [State]: `initState`, `build`, and `setState` (which requests a repaint).
abstract class State {
  var widget;

  void initState() {}

  Widget build(BuildContext context) { return null; }

  /// Notify the framework that internal state changed, running [fn] and
  /// scheduling a rebuild + repaint.
  void setState(Function fn) {
    fn();
    __markNeedsBuild();
  }
}

// =============================================================================
// SECTION 6 — the binding: runApp, the frame pipeline, and hit-testing
// =============================================================================

// The retained application root and per-frame scratch state.
var __rootWidget = null;
var __states = [];
var __locCounter = 0;
var __hits = [];
var __needsBuild = false;
var __context = null;

// Logical view size (the tight constraints handed to the root each frame).
double __viewWidth = 400.0;
double __viewHeight = 800.0;

/// Mark the tree dirty and ask the engine to schedule another frame — the
/// mechanism behind [State.setState].
void __markNeedsBuild() {
  __needsBuild = true;
  askHost("dart:ui/scheduleFrame", []);
}

/// Persistent [State] lookup, matched to a [StatefulWidget] by build-order
/// index (position-based reconciliation, like Flutter without keys), so state
/// survives across frames.
State __stateFor(StatefulWidget w) {
  var idx = __locCounter;
  __locCounter = __locCounter + 1;
  if (idx < __states.length) {
    var existing = __states[idx];
    existing.widget = w;
    return existing;
  }
  var st = w.createState();
  st.widget = w;
  st.initState();
  __states.add(st);
  return st;
}

/// Resolve a widget to a concrete render widget: repeatedly `build` Stateless /
/// Stateful widgets until a render widget remains, then inflate its children.
Widget expand(Widget w) {
  var cur = w;
  var done = false;
  while (!done) {
    if (cur is StatelessWidget) {
      cur = cur.build(__context);
    } else if (cur is StatefulWidget) {
      var st = __stateFor(cur);
      cur = st.build(__context);
    } else {
      done = true;
    }
  }
  if (cur == null) { cur = SizedBox(); }
  cur.inflate();
  return cur;
}

/// Attach [app] as the root of the widget tree and schedule the first frame.
/// The engine then drives `onBeginFrame`/`onDrawFrame`; taps arrive via
/// `onPointerEvent`. Mirrors `widgets`'s [runApp].
void runApp(Widget app) {
  __context = BuildContext();
  __rootWidget = app;
  __markNeedsBuild();
}

// ---- engine binding handlers (invoked by the runtime) ----

void onBeginFrame(t) {}

void onDrawFrame() {
  if (__rootWidget == null) { return; }
  __needsBuild = false;
  __locCounter = 0;
  __hits = [];

  var tree = expand(__rootWidget);
  var constraints = BoxConstraints.tight(Size(__viewWidth, __viewHeight));
  tree.layout(constraints);

  askHost("dart:ui/PictureRecorder.beginRecording", []);
  tree.paint(Offset.zero());
  var pic = askHost("dart:ui/PictureRecorder.endRecording", []);
  var scene = askHost("dart:ui/Picture.toScene", [pic]);
  askHost("dart:ui/FlutterView.render", [scene]);
}

void onPointerEvent(e) {
  var phase = e["phase"];
  // A tap completes on pointer-up; ignore intermediate down/move events.
  if (phase != "up") { return; }
  var x = e["x"];
  var y = e["y"];
  // Hit rects are recorded front-to-back during paint; scan back-to-front so
  // the topmost detector wins.
  var i = __hits.length - 1;
  while (i >= 0) {
    var h = __hits[i];
    if (x >= h["x0"] && x <= h["x1"] && y >= h["y0"] && y <= h["y1"]) {
      var cb = h["onTap"];
      if (cb != null) { cb(); }
      return;
    }
    i = i - 1;
  }
}

/// Record a tappable region for hit-testing (used by [GestureDetector]).
void __addHit(Offset offset, Size size, Function onTap) {
  __hits.add({
    "x0": offset.dx,
    "y0": offset.dy,
    "x1": offset.dx + size.width,
    "y1": offset.dy + size.height,
    "onTap": onTap,
  });
}

// Low-level paint helpers over the dart:ui bridge.
void __fillRect(Offset offset, Size size, int color) {
  askHost("dart:ui/Canvas.drawRect",
      [offset.dx, offset.dy, offset.dx + size.width, offset.dy + size.height, color]);
}

// =============================================================================
// SECTION 7 — basic render widgets
// =============================================================================

/// A box with a fixed [width]/[height] that sizes its optional child to match.
/// Mirrors `widgets`'s [SizedBox].
class SizedBox extends Widget {
  var width;
  var height;
  var child;
  var exChild;
  SizedBox({this.width, this.height, this.child});
  static SizedBox shrink() => SizedBox(width: 0.0, height: 0.0);

  void inflate() {
    if (child != null) { exChild = expand(child); } else { exChild = null; }
  }

  Size layout(BoxConstraints c) {
    var w = width ?? 0.0;
    var h = height ?? 0.0;
    if (exChild != null) {
      var cs = exChild.layout(BoxConstraints.tight(Size(c.clampW(w), c.clampH(h))));
      if (width == null) { w = cs.width; }
      if (height == null) { h = cs.height; }
    }
    this.size = c.constrain(Size(w, h));
    return this.size;
  }

  void paint(Offset offset) {
    if (exChild != null) { exChild.paint(offset); }
  }
}

/// A convenience box that combines painting (color/decoration), positioning
/// (padding/alignment) and sizing (width/height) around a child. This is the
/// workhorse container, mirroring `widgets`'s [Container].
class Container extends Widget {
  var width;
  var height;
  var color;
  var decoration;
  var padding;
  var alignment;
  var child;
  var exChild;
  var childOffset;
  Container({this.width, this.height, this.color, this.decoration, this.padding,
             this.alignment, this.child});

  void inflate() {
    if (child != null) { exChild = expand(child); } else { exChild = null; }
  }

  Size layout(BoxConstraints c) {
    var pad = padding ?? EdgeInsets.zero();
    var childSize = Size.zero();
    if (exChild != null) {
      var inner = c.deflate(pad.horizontal, pad.vertical);
      childSize = exChild.layout(inner);
    }
    var w = width ?? (childSize.width + pad.horizontal);
    var h = height ?? (childSize.height + pad.vertical);
    this.size = c.constrain(Size(w, h));

    // Position the child: centered by [alignment] within the padded area, else
    // at the padding origin.
    if (exChild != null) {
      var innerW = this.size.width - pad.horizontal;
      var innerH = this.size.height - pad.vertical;
      var ox = pad.left;
      var oy = pad.top;
      if (alignment != null) {
        var slack = alignment.withinRect(Size(innerW, innerH), childSize);
        ox = pad.left + slack.dx;
        oy = pad.top + slack.dy;
      }
      this.childOffset = Offset(ox, oy);
    }
    return this.size;
  }

  void paint(Offset offset) {
    var fill = color;
    if (fill == null && decoration != null) { fill = decoration.color; }
    if (fill != null) { __fillRect(offset, this.size, fill.value); }
    if (exChild != null) {
      exChild.paint(offset.translate(this.childOffset.dx, this.childOffset.dy));
    }
  }
}

/// A box that paints a [BoxDecoration] behind its child, mirroring `widgets`'s
/// [DecoratedBox].
class DecoratedBox extends Widget {
  var decoration;
  var child;
  var exChild;
  DecoratedBox({this.decoration, this.child});
  void inflate() { if (child != null) { exChild = expand(child); } else { exChild = null; } }
  Size layout(BoxConstraints c) {
    var s = Size.zero();
    if (exChild != null) { s = exChild.layout(c); }
    this.size = c.constrain(s);
    return this.size;
  }
  void paint(Offset offset) {
    if (decoration != null && decoration.color != null) {
      __fillRect(offset, this.size, decoration.color.value);
    }
    if (exChild != null) { exChild.paint(offset); }
  }
}

/// A box painted with a single [color], mirroring `widgets`'s [ColoredBox].
class ColoredBox extends Widget {
  var color;
  var child;
  var exChild;
  ColoredBox({this.color, this.child});
  void inflate() { if (child != null) { exChild = expand(child); } else { exChild = null; } }
  Size layout(BoxConstraints c) {
    var s = Size(c.maxWidth, c.maxHeight);
    if (exChild != null) { s = exChild.layout(c); }
    this.size = c.constrain(s);
    return this.size;
  }
  void paint(Offset offset) {
    if (color != null) { __fillRect(offset, this.size, color.value); }
    if (exChild != null) { exChild.paint(offset); }
  }
}

/// Insets its child by [padding], mirroring `widgets`'s [Padding].
class Padding extends Widget {
  var padding;
  var child;
  var exChild;
  var childOffset;
  Padding({this.padding, this.child});
  void inflate() { if (child != null) { exChild = expand(child); } else { exChild = null; } }
  Size layout(BoxConstraints c) {
    var pad = padding ?? EdgeInsets.zero();
    var childSize = Size.zero();
    if (exChild != null) { childSize = exChild.layout(c.deflate(pad.horizontal, pad.vertical)); }
    this.childOffset = Offset(pad.left, pad.top);
    this.size = c.constrain(Size(childSize.width + pad.horizontal, childSize.height + pad.vertical));
    return this.size;
  }
  void paint(Offset offset) {
    if (exChild != null) { exChild.paint(offset.translate(this.childOffset.dx, this.childOffset.dy)); }
  }
}

/// Centers its child within itself, mirroring `widgets`'s [Center].
class Center extends Widget {
  var child;
  var exChild;
  var childOffset;
  Center({this.child});
  void inflate() { if (child != null) { exChild = expand(child); } else { exChild = null; } }
  Size layout(BoxConstraints c) {
    // Fill the incoming max, place the child in the middle.
    this.size = Size(c.maxWidth, c.maxHeight);
    if (exChild != null) {
      var cs = exChild.layout(c.loosen);
      this.childOffset = Offset((this.size.width - cs.width) / 2.0, (this.size.height - cs.height) / 2.0);
    } else {
      this.childOffset = Offset.zero();
    }
    return this.size;
  }
  void paint(Offset offset) {
    if (exChild != null) { exChild.paint(offset.translate(this.childOffset.dx, this.childOffset.dy)); }
  }
}

/// Aligns its child within itself per an [Alignment], mirroring `widgets`'s
/// [Align].
class Align extends Widget {
  var alignment;
  var child;
  var exChild;
  var childOffset;
  Align({this.alignment, this.child});
  void inflate() { if (child != null) { exChild = expand(child); } else { exChild = null; } }
  Size layout(BoxConstraints c) {
    this.size = Size(c.maxWidth, c.maxHeight);
    if (exChild != null) {
      var cs = exChild.layout(c.loosen);
      var a = alignment ?? Alignment.center();
      this.childOffset = a.withinRect(this.size, cs);
    } else {
      this.childOffset = Offset.zero();
    }
    return this.size;
  }
  void paint(Offset offset) {
    if (exChild != null) { exChild.paint(offset.translate(this.childOffset.dx, this.childOffset.dy)); }
  }
}

/// A child of a [Row]/[Column] that flexes to fill available main-axis space,
/// mirroring `widgets`'s [Flexible]/[Expanded].
class Flexible extends Widget {
  var flex;
  var child;
  var exChild;
  Flexible({this.flex, this.child});
  void inflate() { if (child != null) { exChild = expand(child); } else { exChild = null; } }
  Size layout(BoxConstraints c) {
    var s = Size.zero();
    if (exChild != null) { s = exChild.layout(c); }
    this.size = c.constrain(s);
    return this.size;
  }
  void paint(Offset offset) {
    if (exChild != null) { exChild.paint(offset); }
  }
}

/// A [Flexible] that fills all available space (flex fit tight).
class Expanded extends Flexible {
  Expanded({int flex, Widget child}) { this.flex = flex; this.child = child; }
}

/// A flex layout base for [Row] and [Column]. Lays out non-flexible children
/// first, then distributes the remaining main-axis extent to [Expanded]/
/// [Flexible] children by flex weight — a faithful sketch of RenderFlex.
abstract class Flex extends Widget {
  var direction;
  var children;
  var mainAxisAlignment;
  var crossAxisAlignment;
  var mainAxisSize;
  var exKids;
  var offsets;

  void inflate() {
    exKids = [];
    if (children != null) {
      for (var c in children) { exKids.add(expand(c)); }
    }
  }

  bool __isHorizontal() { return direction == Axis.horizontal; }

  double __mainOf(Size s) { if (__isHorizontal()) { return s.width; } return s.height; }
  double __crossOf(Size s) { if (__isHorizontal()) { return s.height; } return s.width; }

  /// Constraints for a child spanning `[mainMin, mainMax]` on the main axis;
  /// the cross axis is tight to [maxCross] when stretching, else loose.
  BoxConstraints __childConstraints(double mainMin, double mainMax, double maxCross, bool stretch) {
    var crossMin = stretch ? maxCross : 0.0;
    if (__isHorizontal()) { return BoxConstraints(mainMin, mainMax, crossMin, maxCross); }
    return BoxConstraints(crossMin, maxCross, mainMin, mainMax);
  }

  Size layout(BoxConstraints c) {
    var horizontal = __isHorizontal();
    var maxMain = horizontal ? c.maxWidth : c.maxHeight;
    var maxCross = horizontal ? c.maxHeight : c.maxWidth;
    var stretch = crossAxisAlignment == CrossAxisAlignment.stretch;

    // Pass 1: total flex and the size taken by inflexible children.
    var totalFlex = 0;
    var usedMain = 0.0;
    var maxChildCross = 0.0;
    for (var ch in exKids) {
      if (ch is Flexible) {
        totalFlex = totalFlex + (ch.flex ?? 1);
      } else {
        var cs = ch.layout(__childConstraints(0.0, maxMain, maxCross, stretch));
        usedMain = usedMain + __mainOf(cs);
        if (__crossOf(cs) > maxChildCross) { maxChildCross = __crossOf(cs); }
      }
    }

    // Pass 2: hand each flex child its share of the leftover main extent.
    if (totalFlex > 0) {
      var free = maxMain - usedMain;
      if (free < 0.0) { free = 0.0; }
      for (var ch in exKids) {
        if (ch is Flexible) {
          var share = free * ((ch.flex ?? 1) / totalFlex);
          var cs = ch.layout(__childConstraints(share, share, maxCross, stretch));
          usedMain = usedMain + __mainOf(cs);
          if (__crossOf(cs) > maxChildCross) { maxChildCross = __crossOf(cs); }
        }
      }
    }

    // Main extent: shrink-wrap unless MainAxisSize.max or something flexes.
    var wantMax = (mainAxisSize == MainAxisSize.max) || totalFlex > 0;
    var mainExtent = wantMax ? maxMain : usedMain;
    var crossExtent = maxChildCross;
    if (crossAxisAlignment == CrossAxisAlignment.stretch) { crossExtent = maxCross; }

    this.size = horizontal ? Size(mainExtent, crossExtent) : Size(crossExtent, mainExtent);
    this.size = c.constrain(this.size);

    // Placement: distribute leading/between space per mainAxisAlignment.
    var count = exKids.length;
    var slack = __mainOf(this.size) - usedMain;
    if (slack < 0.0) { slack = 0.0; }
    var leading = 0.0;
    var between = 0.0;
    var main = mainAxisAlignment ?? MainAxisAlignment.start;
    if (main == MainAxisAlignment.end) { leading = slack; }
    if (main == MainAxisAlignment.center) { leading = slack / 2.0; }
    if (main == MainAxisAlignment.spaceBetween && count > 1) { between = slack / (count - 1); }
    if (main == MainAxisAlignment.spaceAround && count > 0) {
      between = slack / count;
      leading = between / 2.0;
    }
    if (main == MainAxisAlignment.spaceEvenly && count > 0) {
      between = slack / (count + 1);
      leading = between;
    }

    this.offsets = [];
    var cursor = leading;
    for (var ch in exKids) {
      var cm = __mainOf(ch.size);
      var cc = __crossOf(ch.size);
      var crossPos = __crossPos(crossExtent, cc);
      var off = horizontal ? Offset(cursor, crossPos) : Offset(crossPos, cursor);
      this.offsets.add(off);
      cursor = cursor + cm + between;
    }
    return this.size;
  }

  double __crossPos(double crossExtent, double childCross) {
    var a = crossAxisAlignment ?? CrossAxisAlignment.center;
    if (a == CrossAxisAlignment.start) { return 0.0; }
    if (a == CrossAxisAlignment.end) { return crossExtent - childCross; }
    if (a == CrossAxisAlignment.stretch) { return 0.0; }
    return (crossExtent - childCross) / 2.0; // center
  }

  void paint(Offset offset) {
    var i = 0;
    while (i < exKids.length) {
      var off = this.offsets[i];
      exKids[i].paint(offset.translate(off.dx, off.dy));
      i = i + 1;
    }
  }
}

/// Lays its children out vertically, mirroring `widgets`'s [Column].
class Column extends Flex {
  Column({List children, MainAxisAlignment mainAxisAlignment,
          CrossAxisAlignment crossAxisAlignment, MainAxisSize mainAxisSize}) {
    this.direction = Axis.vertical;
    this.children = children;
    this.mainAxisAlignment = mainAxisAlignment;
    this.crossAxisAlignment = crossAxisAlignment;
    this.mainAxisSize = mainAxisSize;
  }
}

/// Lays its children out horizontally, mirroring `widgets`'s [Row].
class Row extends Flex {
  Row({List children, MainAxisAlignment mainAxisAlignment,
       CrossAxisAlignment crossAxisAlignment, MainAxisSize mainAxisSize}) {
    this.direction = Axis.horizontal;
    this.children = children;
    this.mainAxisAlignment = mainAxisAlignment;
    this.crossAxisAlignment = crossAxisAlignment;
    this.mainAxisSize = mainAxisSize;
  }
}

/// An empty flexible spacer that eats free space in a [Row]/[Column], mirroring
/// `widgets`'s [Spacer].
class Spacer extends Expanded {
  Spacer() { this.flex = 1; this.child = SizedBox(); }
}

/// Overlays its children, sized to the biggest, mirroring `widgets`'s [Stack].
/// (Non-positioned children are top-left aligned; [Positioned] places explicitly.)
class Stack extends Widget {
  var children;
  var alignment;
  var exKids;
  var offsets;
  Stack({this.children, this.alignment});

  void inflate() {
    exKids = [];
    if (children != null) {
      for (var c in children) { exKids.add(expand(c)); }
    }
  }

  Size layout(BoxConstraints c) {
    var w = 0.0;
    var h = 0.0;
    for (var ch in exKids) {
      var cs = ch.layout(c.loosen);
      if (ch is Positioned) {
        // A positioned child does not affect the stack's size.
      } else {
        if (cs.width > w) { w = cs.width; }
        if (cs.height > h) { h = cs.height; }
      }
    }
    this.size = c.constrain(Size(w, h));
    var a = alignment ?? Alignment.topLeft();
    this.offsets = [];
    for (var ch in exKids) {
      if (ch is Positioned) {
        this.offsets.add(Offset(ch.left ?? 0.0, ch.top ?? 0.0));
      } else {
        this.offsets.add(a.withinRect(this.size, ch.size));
      }
    }
    return this.size;
  }

  void paint(Offset offset) {
    var i = 0;
    while (i < exKids.length) {
      var off = this.offsets[i];
      exKids[i].paint(offset.translate(off.dx, off.dy));
      i = i + 1;
    }
  }
}

/// Positions its child at explicit [left]/[top] within a [Stack], mirroring
/// `widgets`'s [Positioned].
class Positioned extends Widget {
  var left;
  var top;
  var child;
  var exChild;
  Positioned({this.left, this.top, this.child});
  void inflate() { if (child != null) { exChild = expand(child); } else { exChild = null; } }
  Size layout(BoxConstraints c) {
    var s = Size.zero();
    if (exChild != null) { s = exChild.layout(c.loosen); }
    this.size = s;
    return this.size;
  }
  void paint(Offset offset) {
    if (exChild != null) { exChild.paint(offset); }
  }
}

/// A run of text with a [TextStyle], mirroring `widgets`'s [Text]. Text is
/// measured with a monospace-ish estimate (the engine provides exact metrics in
/// the full binding); it lowers to a `drawParagraph` scene op.
class Text extends Widget {
  var data;
  var style;
  var textAlign;
  Text(this.data, {this.style, this.textAlign});

  double __fontSize() {
    if (style != null && style.fontSize != null) { return style.fontSize; }
    return 14.0;
  }

  int __color() {
    if (style != null && style.color != null) { return style.color.value; }
    return 4278190080; // opaque black
  }

  Size layout(BoxConstraints c) {
    var fs = __fontSize();
    var w = data.length * fs * 0.58;
    this.size = c.constrain(Size(w, fs * 1.4));
    return this.size;
  }

  void paint(Offset offset) {
    var fs = __fontSize();
    askHost("dart:ui/Canvas.drawParagraph", [data, offset.dx, offset.dy + fs, fs, __color()]);
  }
}

/// A simple square glyph stand-in (the real [Icon] rasterizes a font glyph);
/// here it paints a rounded swatch so icon-bearing layouts render.
class Icon extends Widget {
  var codePoint;
  var color;
  var iconSize;
  Icon(this.codePoint, {this.color, this.iconSize});
  Size layout(BoxConstraints c) {
    var s = iconSize ?? 24.0;
    this.size = c.constrain(Size(s, s));
    return this.size;
  }
  void paint(Offset offset) {
    var col = color ?? Colors.black;
    __fillRect(offset, this.size, col.value);
  }
}

/// A thin horizontal rule, mirroring `material`'s [Divider].
class Divider extends Widget {
  var color;
  var thickness;
  Divider({this.color, this.thickness});
  Size layout(BoxConstraints c) {
    this.size = Size(c.maxWidth, thickness ?? 1.0);
    return this.size;
  }
  void paint(Offset offset) {
    var col = color ?? Colors.grey;
    __fillRect(offset, this.size, col.value);
  }
}

/// Recognizes taps on its child, mirroring `widgets`'s [GestureDetector]. On a
/// pointer-up inside the child's box, [onTap] runs.
class GestureDetector extends Widget {
  var onTap;
  var child;
  var exChild;
  GestureDetector({this.onTap, this.child});
  void inflate() { if (child != null) { exChild = expand(child); } else { exChild = null; } }
  Size layout(BoxConstraints c) {
    var s = Size.zero();
    if (exChild != null) { s = exChild.layout(c); }
    this.size = c.constrain(s);
    return this.size;
  }
  void paint(Offset offset) {
    __addHit(offset, this.size, onTap);
    if (exChild != null) { exChild.paint(offset); }
  }
}

// =============================================================================
// SECTION 8 — Material-style app shells
// =============================================================================

/// The top-level Material application wrapper. Minimal here: it simply mounts
/// its [home]. Mirrors `material`'s [MaterialApp].
class MaterialApp extends StatelessWidget {
  var home;
  var title;
  MaterialApp({this.home, this.title});
  Widget build(BuildContext context) {
    return home ?? SizedBox();
  }
}

/// A top app bar with a [title], a colored band across the top of a [Scaffold].
/// Mirrors `material`'s [AppBar].
class AppBar extends StatelessWidget {
  var title;
  var backgroundColor;
  var barHeight;
  AppBar({this.title, this.backgroundColor, this.barHeight});
  Widget build(BuildContext context) {
    return Container(
      height: barHeight ?? 56.0,
      color: backgroundColor ?? Colors.blue,
      padding: EdgeInsets.symmetric(16.0, 8.0),
      alignment: Alignment.centerLeft(),
      child: title,
    );
  }
}

/// The basic Material visual layout structure: an optional [appBar] pinned to
/// the top and a [body] filling the rest, over a [backgroundColor]. Mirrors
/// `material`'s [Scaffold].
class Scaffold extends StatelessWidget {
  var appBar;
  var body;
  var backgroundColor;
  Scaffold({this.appBar, this.body, this.backgroundColor});
  Widget build(BuildContext context) {
    var col;
    if (appBar != null) {
      col = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [appBar, Expanded(child: body ?? SizedBox())],
      );
    } else {
      col = body ?? SizedBox();
    }
    return Container(
      width: __viewWidth,
      height: __viewHeight,
      color: backgroundColor ?? Colors.white,
      child: col,
    );
  }
}

/// A Material card: a rounded, colored surface with padding around its child.
/// Mirrors `material`'s [Card].
class Card extends StatelessWidget {
  var color;
  var child;
  var margin;
  Card({this.color, this.child, this.margin});
  Widget build(BuildContext context) {
    return Padding(
      padding: margin ?? EdgeInsets.all(8.0),
      child: DecoratedBox(
        decoration: BoxDecoration(color: color ?? Colors.white, borderRadius: BorderRadius.circular(8.0)),
        child: child,
      ),
    );
  }
}

/// A filled, tappable Material button with a label, mirroring `material`'s
/// [ElevatedButton].
class ElevatedButton extends StatelessWidget {
  var onPressed;
  var child;
  var color;
  ElevatedButton({this.onPressed, this.child, this.color});
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        color: color ?? Colors.blue,
        padding: EdgeInsets.symmetric(20.0, 12.0),
        alignment: Alignment.center(),
        child: child,
      ),
    );
  }
}

/// A flat, tappable text button, mirroring `material`'s [TextButton].
class TextButton extends StatelessWidget {
  var onPressed;
  var child;
  TextButton({this.onPressed, this.child});
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Padding(padding: EdgeInsets.symmetric(16.0, 8.0), child: child),
    );
  }
}
// =============================================================================
// §4  Canvas — the 2D drawing widget and its controller
// =============================================================================
//
// Immediate-mode 2D drawing as a widget, the twin of `gui.js`'s Canvas. A
// component owns a [CanvasController] and paints through it:
//
//     class Chart extends StatefulWidget { State createState() => ChartState(); }
//     class ChartState extends State {
//       Widget build(BuildContext context) {
//         return Canvas(width: 200.0, height: 80.0, painter: (c) {
//           c.rect(0.0, 0.0, 200.0, 80.0, Color(0xFF11202B));
//           c.line(0.0, 80.0, 200.0, 0.0, Color(0xFF52C0AE), 2.0);
//         });
//       }
//     }
//
// Unlike the JavaScript twin, this needs no display list: the widget layer is
// already a retained tree replayed once per frame, so the painter is simply
// called during paint and its calls go straight to the `dart:ui` recorder that
// is already open. Buffering here would add a copy and change nothing.

/// Draws on the canvas the widget owns. Handed to the painter callback during
/// paint; it is only live for that call.
class CanvasController {
  var ox;
  var oy;
  var w;
  var h;
  var live;

  CanvasController(ox_, oy_, w_, h_) {
    this.ox = ox_;
    this.oy = oy_;
    this.w = w_;
    this.h = h_;
    this.live = true;
  }

  /// Width of the drawing area, in logical pixels.
  double width() => this.w;

  /// Height of the drawing area, in logical pixels.
  double height() => this.h;

  /// A filled rectangle, in canvas-local coordinates.
  CanvasController rect(double x, double y, double w_, double h_, Color color) {
    this.__assertLive('rect');
    askHost('dart:ui/Canvas.drawRect',
        [this.ox + x, this.oy + y, this.ox + x + w_, this.oy + y + h_, color.value]);
    return this;
  }

  /// A filled circle, in canvas-local coordinates.
  CanvasController circle(double x, double y, double radius, Color color) {
    this.__assertLive('circle');
    askHost('dart:ui/Canvas.drawCircle',
        [this.ox + x, this.oy + y, radius, color.value]);
    return this;
  }

  /// A line from (x1,y1) to (x2,y2). [width_] is the stroke, in pixels.
  CanvasController line(double x1, double y1, double x2, double y2, Color color,
      [double width_ = 1.0]) {
    return this.polyline([x1, y1, x2, y2], color, width_);
  }

  /// A polyline through a flat `[x0, y0, x1, y1, …]`.
  ///
  /// Flat rather than a list of pairs because it crosses the host seam as one
  /// list: a list of two-element lists costs an object per point.
  CanvasController polyline(List points, Color color, [double width_ = 1.0]) {
    this.__assertLive('polyline');
    if (points.length < 4) { return this; }
    var path = askHost('dart:ui/Path.create', []);
    askHost('dart:ui/Path.moveTo', [path, this.ox + points[0], this.oy + points[1]]);
    var i = 2;
    while (i + 1 < points.length) {
      askHost('dart:ui/Path.lineTo', [path, this.ox + points[i], this.oy + points[i + 1]]);
      i = i + 2;
    }
    // style 1 is stroke; a fill would close the polyline into a polygon.
    var paint = askHost('dart:ui/Paint.create', [color.value, width_, 1]);
    askHost('dart:ui/Canvas.drawPath', [path, paint]);
    return this;
  }

  /// A closed, filled polygon through a flat `[x0, y0, …]`.
  CanvasController polygon(List points, Color color) {
    this.__assertLive('polygon');
    if (points.length < 6) { return this; }
    var path = askHost('dart:ui/Path.create', []);
    askHost('dart:ui/Path.moveTo', [path, this.ox + points[0], this.oy + points[1]]);
    var i = 2;
    while (i + 1 < points.length) {
      askHost('dart:ui/Path.lineTo', [path, this.ox + points[i], this.oy + points[i + 1]]);
      i = i + 2;
    }
    askHost('dart:ui/Path.close', [path]);
    var paint = askHost('dart:ui/Paint.create', [color.value, 0.0, 0]);
    askHost('dart:ui/Canvas.drawPath', [path, paint]);
    return this;
  }

  /// Text at (x, y), where y is the baseline-ish top of the run.
  CanvasController text(double x, double y, String str, Color color,
      [double size = 14.0]) {
    this.__assertLive('text');
    askHost('dart:ui/Canvas.drawParagraph',
        [str, this.ox + x, this.oy + y, size, color.value]);
    return this;
  }

  /// Called by the widget once the painter returns, so a controller kept past
  /// the frame reports rather than drawing into a closed recorder.
  void dispose() { this.live = false; }

  void __assertLive(String what) {
    if (!this.live) {
      throw 'gui: CanvasController.$what after the frame it belonged to';
    }
  }
}

/// A fixed-size drawing surface. [painter] is called with a [CanvasController]
/// during paint, every frame.
class Canvas extends Widget {
  var width;
  var height;
  var painter;

  Canvas({this.width = 0.0, this.height = 0.0, this.painter});

  Size layout(BoxConstraints constraints) {
    this.size = constraints.constrain(Size(this.width, this.height));
    return this.size;
  }

  void paint(Offset offset) {
    if (this.painter == null) { return; }
    var c = CanvasController(offset.dx, offset.dy, this.size.width, this.size.height);
    this.painter(c);
    c.dispose();
  }
}

// =============================================================================
// §5  Scene3D — the 3D world and its controller
// =============================================================================
//
// The engine-backed half of the SDK, and the twin of `gui.js`'s Scene3D. This
// one is not a widget: the widget layer paints through `dart:ui`, and a Godot
// viewport is not something that layer can composite. A Dart guest on the
// Godot host drives a scene through the controller directly:
//
//     var scene = Scene3DController(GD.host());
//     scene.camera.moveTo(0.0, 3.0, 8.0);
//     scene.camera.lookAt(0.0, 0.0, 0.0);
//     scene.spawn('MeshInstance3D', {'position': [0.0, 0.0, 0.0]});
//
// The controller is the point. Without it a scene is built by scattering
// `GD.create` calls through app code, which means nodes nobody owns — leaked
// when the screen goes away, duplicated when it is rebuilt. A controller owns
// what it spawns and frees it on [dispose].
class Scene3DController {
  var root;
  var spawned;
  var camera;
  var disposed;
  var __world;

  Scene3DController(root_) {
    this.root = root_;
    this.spawned = [];
    this.camera = Scene3DCamera(this);
    this.disposed = false;
    this.__world = null;
  }

  /// The `Node3D` every spawned object is parented under. Created on first use,
  /// so an empty scene costs nothing.
  GObj world() {
    if (this.__world == null) {
      this.__world = GD.create('Node3D');
      this.root.call('add_child', [this.__world]);
    }
    return this.__world;
  }

  /// Add a node of [className] to the scene.
  ///
  /// [props] may carry `position`, `rotation` and `scale` as `[x, y, z]`, plus
  /// any property the class itself accepts.
  GObj spawn(String className, [Map props]) {
    this.__assertLive('spawn');
    var node = GD.create(className);
    this.world().call('add_child', [node]);
    this.spawned.add(node);
    if (props != null) { this.configure(node, props); }
    return node;
  }

  /// Apply [props] to a node that already exists. Split out from [spawn] so a
  /// caller can move something without rebuilding it.
  GObj configure(GObj node, Map props) {
    if (node == null || props == null) { return node; }
    for (var k in props.keys) {
      var v = props[k];
      if (k == 'position' || k == 'rotation' || k == 'scale') {
        node.set(k, __guiVec3(v));
      } else {
        node.set(k, v);
      }
    }
    return node;
  }

  /// Free one node this controller spawned.
  void remove(GObj node) {
    if (node == null) { return; }
    var keep = [];
    var i = 0;
    while (i < this.spawned.length) {
      if (this.spawned[i] != node) { keep.add(this.spawned[i]); }
      i = i + 1;
    }
    this.spawned = keep;
    node.queueFree();
  }

  /// Add a light. A scene with no light renders black, which reads as a broken
  /// screen rather than a missing light — so this is worth having to hand.
  GObj light(String kind, [Map props]) {
    var cls = 'OmniLight3D';
    if (kind == 'directional') { cls = 'DirectionalLight3D'; }
    if (kind == 'spot') { cls = 'SpotLight3D'; }
    return this.spawn(cls, props);
  }

  /// Named environments, so a scene gets sensible lighting from one call
  /// rather than six lines of setup every time.
  void environment(String name) {
    var env = GD.create('Environment');
    if (name == 'day') {
      env.set('background_mode', GInt(2));
      env.set('ambient_light_energy', GFloat(1.0));
    } else if (name == 'night') {
      env.set('background_mode', GInt(1));
      env.set('ambient_light_energy', GFloat(0.15));
    } else if (name == 'studio') {
      env.set('background_mode', GInt(1));
      env.set('ambient_light_energy', GFloat(0.6));
    }
    var holder = GD.create('WorldEnvironment');
    holder.set('environment', env);
    this.world().call('add_child', [holder]);
    this.spawned.add(holder);
  }

  /// Free everything this controller owns. Calling it twice is harmless.
  void dispose() {
    if (this.disposed) { return; }
    this.disposed = true;
    var i = 0;
    while (i < this.spawned.length) {
      this.spawned[i].queueFree();
      i = i + 1;
    }
    this.spawned = [];
    if (this.__world != null) {
      this.__world.queueFree();
      this.__world = null;
    }
    this.camera.dispose();
  }

  void __assertLive(String what) {
    if (this.disposed) {
      throw 'gui: Scene3DController.$what after the scene was disposed';
    }
  }
}

/// The scene's camera. Created lazily: a scene used as a backdrop does not need
/// one, and Godot supplies a default view without it.
class Scene3DCamera {
  var scene;
  var node;

  Scene3DCamera(scene_) {
    this.scene = scene_;
    this.node = null;
  }

  /// The `Camera3D`, creating it and making it current on first use.
  GObj ensure() {
    if (this.node == null) {
      this.node = GD.create('Camera3D');
      this.scene.world().call('add_child', [this.node]);
      this.node.set('current', true);
    }
    return this.node;
  }

  Scene3DCamera moveTo(double x, double y, double z) {
    this.ensure().set('position', Vector3(x, y, z));
    return this;
  }

  Scene3DCamera lookAt(double x, double y, double z) {
    // `look_at` needs an up vector; Y-up is Godot's own convention and is what
    // a caller passing three numbers means.
    this.ensure().call('look_at', [Vector3(x, y, z), Vector3(0.0, 1.0, 0.0)]);
    return this;
  }

  /// Vertical field of view, in degrees.
  Scene3DCamera fov(double degrees) {
    this.ensure().set('fov', GFloat(degrees));
    return this;
  }

  void dispose() {
    if (this.node != null) {
      this.node.queueFree();
      this.node = null;
    }
  }
}

/// `[x, y, z]`, a single number, or a Vector3 — all mean a position.
Vector3 __guiVec3(v) {
  if (v == null) { return Vector3(0.0, 0.0, 0.0); }
  if (v is List) {
    return Vector3(v[0], v[1], v[2]);
  }
  if (v is Vector3) { return v; }
  return Vector3(v, v, v);
}

// =============================================================================
// §6  Theme — design tokens shared by both backends
// =============================================================================
//
// The Material 3 token set `gui.js` exposes as `VUI.theme()`, in the shape a
// Dart guest wants. Tokens rather than widgets: the widget layer already has
// its own Material-shaped widgets (§3), and what was missing was a single
// agreed palette for them and for anything drawn on a [Canvas] or spawned into
// a [Scene3DController] to share.
class GuiTheme {
  var primary;
  var onPrimary;
  var surface;
  var surfaceContainer;
  var onSurface;
  var onSurfaceVariant;
  var outline;
  var error;
  var radiusS;
  var radiusM;
  var radiusL;
  var minTouch;

  GuiTheme.dark() {
    this.primary = Color(0xFF52C0AE);
    this.onPrimary = Color(0xFF06251F);
    this.surface = Color(0xFF0D1413);
    this.surfaceContainer = Color(0xFF141D1B);
    this.onSurface = Color(0xFFDEE7E3);
    this.onSurfaceVariant = Color(0xFFA0AFA9);
    this.outline = Color(0xFF253230);
    this.error = Color(0xFFE0725A);
    this.radiusS = 8.0;
    this.radiusM = 12.0;
    this.radiusL = 16.0;
    this.minTouch = 48.0;
  }

  GuiTheme.light() {
    this.primary = Color(0xFF0F6E62);
    this.onPrimary = Color(0xFFFFFFFF);
    this.surface = Color(0xFFF6F8F7);
    this.surfaceContainer = Color(0xFFFFFFFF);
    this.onSurface = Color(0xFF14201E);
    this.onSurfaceVariant = Color(0xFF46564F);
    this.outline = Color(0xFFD6DEDA);
    this.error = Color(0xFFA3341F);
    this.radiusS = 8.0;
    this.radiusM = 12.0;
    this.radiusL = 16.0;
    this.minTouch = 48.0;
  }
}

var __guiTheme = null;

// =============================================================================
// §7  The GUI namespace
// =============================================================================
//
// What a mini app reaches for, gathered under one name so the SDK has an entry
// point rather than a scattering of top-level functions. Everything here is
// also available directly; this is the index, not a wrapper.
class GUI {
  /// The active theme, dark until something says otherwise.
  static GuiTheme theme() {
    if (__guiTheme == null) { __guiTheme = GuiTheme.dark(); }
    return __guiTheme;
  }

  /// Replace the active theme. Widgets built afterwards use it.
  static GuiTheme useTheme(GuiTheme t) {
    __guiTheme = t;
    return t;
  }

  /// Mount [app] as the root of the widget tree and schedule the first frame.
  static void mount(Widget app) { runApp(app); }

  /// Drive a Godot 3D scene under [parent] (`GD.host()` by default).
  static Scene3DController scene3d([GObj parent]) {
    return Scene3DController(parent == null ? GD.host() : parent);
  }
}
