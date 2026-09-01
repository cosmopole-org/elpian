/// The engine façade a `Scene3D` hands you — Elpian's equivalent of Victor's
/// `GD` + `G3`.
///
/// One controller owns one surface's view into the embedded Godot world: the
/// handle allocator, the callback registry, the pending op batch, and the
/// transport binding. Every 3D operation an app performs goes through here.
///
/// ## Why this is fast
///
/// Ops are **batched automatically**. `enqueue` appends to a pending list that
/// is flushed once per frame (or when a read forces it), so building a hundred
/// nodes costs *one* channel crossing rather than a hundred. Handles are
/// allocated on this side, so creates and property writes never wait for a
/// reply — only genuine reads ([request]) do, and a read flushes the pending
/// batch first so ordering is preserved.
///
/// Callers who want an explicit boundary can use [beginBatch] / [endBatch].
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'godot_binding.dart';
import 'godot_object.dart';
import 'godot_values.dart';
import 'protocol.dart';

/// Drives the embedded Godot engine for one `Scene3D` surface.
class GodotController extends ChangeNotifier {
  GodotController({GodotBinding? binding, int? surfaceId})
      : _binding = binding ?? resolveGodotBinding(),
        surfaceId = surfaceId ?? _nextSurfaceId++ {
    _binding.onSignal = _dispatchSignal;
  }

  static int _nextSurfaceId = 1;

  /// Identifies this surface to the engine, so several `Scene3D` widgets can
  /// share one world with their own viewports.
  final int surfaceId;

  final GodotBinding _binding;
  final HandleAllocator _handles = HandleAllocator();
  final Map<int, GodotSignalCallback> _callbacks = {};
  final List<Op> _pending = [];

  int _nextCallbackId = 1;
  bool _explicitBatch = false;
  bool _flushScheduled = false;
  bool _disposed = false;
  bool _mounted = false;

  /// Whether a real engine is behind this controller. When false the widget
  /// shows its placeholder and ops are recorded but never rendered.
  bool get isLive => _binding.isLive;

  /// The transport, for diagnostics and tests.
  @visibleForTesting
  GodotBinding get binding => _binding;

  /// Ops queued but not yet flushed.
  @visibleForTesting
  int get pendingOps => _pending.length;

  /// The scene root the engine binds to this surface. Everything you build
  /// belongs under here.
  late final GodotObject root = GodotObject(this, HandleAllocator.selfHandle);

  // -------------------------------------------------------------------------
  // Op submission
  // -------------------------------------------------------------------------

  /// Queue an op for the next flush. The fire-and-forget path.
  void enqueue(Op op) {
    if (_disposed) return;
    _pending.add(op);
    if (!_explicitBatch) _scheduleFlush();
  }

  /// Submit an op that produces a value, flushing anything queued before it so
  /// the engine observes ops in the order they were issued.
  Future<Object?> request(Op op) async {
    if (_disposed) return null;
    final batch = [..._pending, op];
    _pending.clear();
    final replies = await _binding.send(batch);
    if (replies.length < batch.length) return null;
    final reply = replies[batch.length - 1];
    if (isWireError(reply)) {
      throw GodotOpException(wireErrorMessage(reply) ?? 'engine error', op: op);
    }
    return unmarshal(reply);
  }

  /// Open an explicit batch: ops queue until [endBatch], crossing once.
  ///
  /// Automatic per-frame flushing already batches; use this when you want a
  /// hard boundary (a whole scene build, a physics step's worth of writes).
  void beginBatch() => _explicitBatch = true;

  /// Close an explicit batch and flush it.
  Future<void> endBatch() async {
    _explicitBatch = false;
    await flush();
  }

  /// Send everything queued now.
  Future<void> flush() async {
    if (_pending.isEmpty || _disposed) return;
    final batch = List<Op>.of(_pending);
    _pending.clear();
    _binding.post(batch);
  }

  /// The scheduler, when one exists.
  ///
  /// A controller is usable without a Flutter binding at all (a plain Dart
  /// test, a headless build step), so this must not assert.
  SchedulerBinding? get _scheduler {
    try {
      return SchedulerBinding.instance;
    } catch (_) {
      return null;
    }
  }

  void _scheduleFlush() {
    if (_flushScheduled) return;
    _flushScheduled = true;

    final scheduler = _scheduler;
    if (scheduler != null && scheduler.schedulerPhase != SchedulerPhase.idle) {
      // Mid-frame: coalesce everything this frame produces into one crossing.
      scheduler.addPostFrameCallback((_) {
        _flushScheduled = false;
        flush();
      });
      return;
    }

    // Outside a frame — a timer, an await, a test. A post-frame callback would
    // stall here until something else happened to schedule a frame, so flush at
    // the end of the current microtask drain instead. That still coalesces a
    // whole synchronous scene build into one crossing.
    scheduleMicrotask(() {
      _flushScheduled = false;
      flush();
    });
  }

  // -------------------------------------------------------------------------
  // Object creation — the `GD` facade
  // -------------------------------------------------------------------------

  /// Instantiate **any** `ClassDB` class by name.
  ///
  /// The handle is allocated here, so the returned object is immediately usable
  /// — no await, no round trip.
  GodotObject create(String className) {
    final handle = _handles.allocate();
    enqueue({OpKey.create: className, OpKey.def: handle});
    return GodotObject(this, handle);
  }

  /// Create a node and set properties on it in the same batch.
  GodotObject createWith(String className, Map<String, Object?> properties) {
    final node = create(className);
    node.setAll(properties);
    return node;
  }

  /// An engine singleton by name (`RenderingServer`, `Input`, `Engine`, …).
  GodotObject singleton(String name) {
    final handle = _handles.allocate();
    enqueue({OpKey.singleton: name, OpKey.def: handle});
    return GodotObject(this, handle);
  }

  /// The `SceneTree`.
  GodotObject tree() {
    final handle = _handles.allocate();
    enqueue({OpKey.tree: true, OpKey.def: handle});
    return GodotObject(this, handle);
  }

  /// Load a resource by path (`res://…`, `user://…`).
  GodotObject load(String path) {
    final handle = _handles.allocate();
    enqueue({OpKey.load: path, OpKey.def: handle});
    return GodotObject(this, handle);
  }

  /// Add a node under this surface's root — the usual last step of building.
  void mount(GodotObject node) => root.addChild(node);

  /// Any `@GlobalScope` or class constant by name, e.g. `KEY_ESCAPE`,
  /// `Environment.BG_COLOR`.
  Future<Object?> constant(String name) => request({OpKey.constant: name});

  /// Evaluate a Godot `Expression` with named inputs.
  Future<Object?> eval(String expression,
          [List<String>? names, List<Object?>? values]) =>
      request({
        OpKey.expr: expression,
        OpKey.names: names ?? const [],
        OpKey.values: marshalArgs(values),
      });

  /// Every class name `ClassDB` knows.
  Future<List<String>> classes() async {
    final reply = await request({OpKey.classes: true});
    return reply is List ? [for (final c in reply) '$c'] : const [];
  }

  /// A class's methods, properties and signals.
  Future<Map<String, Object?>> classInfo(String className) async {
    final reply = await request({OpKey.classInfo: className});
    return reply is Map ? reply.map((k, v) => MapEntry('$k', v)) : const {};
  }

  /// Engine-side diagnostics.
  Future<Object?> audit() => request({OpKey.audit: true});

  /// Transport counters (`pushed` / `polls` / `drained`).
  Future<Map<String, Object?>?> stats() => _binding.stats();

  // Named singletons — the ones scene code reaches for constantly.
  GodotObject renderingServer() => singleton('RenderingServer');
  GodotObject physicsServer3D() => singleton('PhysicsServer3D');
  GodotObject physicsServer2D() => singleton('PhysicsServer2D');
  GodotObject audioServer() => singleton('AudioServer');
  GodotObject displayServer() => singleton('DisplayServer');
  GodotObject input() => singleton('Input');
  GodotObject engine() => singleton('Engine');
  GodotObject os() => singleton('OS');
  GodotObject time() => singleton('Time');
  GodotObject projectSettings() => singleton('ProjectSettings');
  GodotObject resourceLoader() => singleton('ResourceLoader');

  // -------------------------------------------------------------------------
  // Callbacks
  // -------------------------------------------------------------------------

  int registerCallback(GodotSignalCallback callback) {
    final id = _nextCallbackId++;
    _callbacks[id] = callback;
    return id;
  }

  void unregisterCallback(int id) => _callbacks.remove(id);

  /// Wrap a Dart closure as a Godot `Callable` for APIs that take one.
  GCallable callable(GodotSignalCallback callback) =>
      GCallable(registerCallback(callback));

  void _dispatchSignal(int callbackId, List<Object?> args) {
    final callback = _callbacks[callbackId];
    if (callback == null) return;
    callback([for (final a in args) unmarshal(a)]);
  }

  /// Drop a handle without freeing the object.
  void releaseHandle(int handle) => enqueue({OpKey.free: handle, 'weak': true});

  // -------------------------------------------------------------------------
  // Surface lifecycle
  // -------------------------------------------------------------------------

  /// Bind this controller's root to a rendering surface. Called by `Scene3D`.
  Future<void> attachSurface() async {
    if (_mounted || _disposed) return;
    _mounted = true;
    await flush();
    await _binding.mountSurface(surfaceId, root.handle);
    notifyListeners();
  }

  Future<void> detachSurface() async {
    if (!_mounted) return;
    _mounted = false;
    await _binding.releaseSurface(surfaceId);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pending.clear();
    _callbacks.clear();
    detachSurface();
    _binding.onSignal = null;
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // G3 — the 3D convenience layer
  // -------------------------------------------------------------------------

  /// Ergonomic 3D constructors, composed from the reflective bridge.
  late final Godot3D g3 = Godot3D(this);
}

/// The `G3` layer: ergonomic constructors for the nodes every 3D scene needs.
///
/// Each returns a plain [GodotObject], so anything these helpers do not cover is
/// still reachable through `create` / `set` / `call`.
class Godot3D {
  Godot3D(this.c);

  final GodotController c;

  /// A bare `Node3D` group with an optional transform.
  GodotObject node({
    Object? position,
    Object? rotation,
    Object? scale,
    bool? visible,
  }) {
    final n = c.create('Node3D');
    setTransform(n,
        position: position, rotation: rotation, scale: scale, visible: visible);
    return n;
  }

  /// A `StandardMaterial3D`.
  GodotObject material({
    GodotColor? color,
    num? metallic,
    num? roughness,
    GodotColor? emission,
    num? emissionEnergy,
    bool transparency = false,
  }) {
    final m = c.create('StandardMaterial3D');
    m.set('albedo_color', color ?? const GodotColor(0.8, 0.82, 0.9, 1.0));
    if (metallic != null) m.set('metallic', GFloat(metallic));
    if (roughness != null) m.set('roughness', GFloat(roughness));
    if (emission != null) {
      m.set('emission_enabled', true);
      m.set('emission', emission);
      if (emissionEnergy != null) {
        m.set('emission_energy_multiplier', GFloat(emissionEnergy));
      }
    }
    if (transparency) {
      m.set('transparency', const GInt(1)); // TRANSPARENCY_ALPHA
    }
    return m;
  }

  /// A primitive mesh *resource* — `box` `sphere` `cylinder` `capsule` `plane`
  /// `prism` `torus`. Unknown shapes fall back to a box, matching the bridge.
  GodotObject primitive(String shape, {Map<String, Object?> options = const {}}) {
    num n(String key, num fallback) {
      final v = options[key];
      return v is num ? v : fallback;
    }

    switch (shape) {
      case 'sphere':
        final mesh = c.create('SphereMesh');
        final r = n('radius', 0.5);
        mesh.set('radius', GFloat(r));
        mesh.set('height', GFloat(n('height', r * 2)));
        return mesh;
      case 'cylinder':
        final mesh = c.create('CylinderMesh');
        final r = n('radius', 0.5);
        mesh.set('top_radius', GFloat(n('topRadius', r)));
        mesh.set('bottom_radius', GFloat(n('bottomRadius', r)));
        mesh.set('height', GFloat(n('height', 1.0)));
        return mesh;
      case 'capsule':
        final mesh = c.create('CapsuleMesh');
        mesh.set('radius', GFloat(n('radius', 0.4)));
        mesh.set('height', GFloat(n('height', 1.4)));
        return mesh;
      case 'plane':
        final mesh = c.create('PlaneMesh');
        mesh.set('size', Vector2(n('width', 2).toDouble(), n('depth', 2).toDouble()));
        return mesh;
      case 'prism':
        final mesh = c.create('PrismMesh');
        mesh.set('size', vec3(options['size'], 1, 1, 1));
        return mesh;
      case 'torus':
        final mesh = c.create('TorusMesh');
        mesh.set('inner_radius', GFloat(n('innerRadius', 0.3)));
        mesh.set('outer_radius', GFloat(n('outerRadius', 0.6)));
        return mesh;
      default:
        final mesh = c.create('BoxMesh');
        mesh.set('size', vec3(options['size'], 1, 1, 1));
        return mesh;
    }
  }

  /// A `MeshInstance3D` with a primitive mesh, a material and a transform.
  GodotObject mesh(
    String shape, {
    Map<String, Object?> options = const {},
    GodotObject? material,
  }) {
    final mi = c.create('MeshInstance3D');
    final prim = primitive(shape, options: options);
    prim.set(
      'material',
      material ??
          this.material(
            color: options['color'] as GodotColor?,
            metallic: options['metallic'] as num?,
            roughness: options['roughness'] as num?,
            emission: options['emission'] as GodotColor?,
            emissionEnergy: options['emissionEnergy'] as num?,
            transparency: options['transparency'] == true,
          ),
    );
    mi.set('mesh', prim);
    setTransform(mi,
        position: options['position'],
        rotation: options['rotation'],
        scale: options['scale'],
        visible: options['visible'] as bool?);
    return mi;
  }

  /// A `Camera3D`. `current` defaults to true so a scene has a view.
  GodotObject camera({
    num? fov,
    bool current = true,
    Object? position,
    Object? rotation,
  }) {
    final cam = c.create('Camera3D');
    if (fov != null) cam.set('fov', GFloat(fov));
    if (current) cam.set('current', true);
    setTransform(cam, position: position, rotation: rotation);
    return cam;
  }

  GodotObject dirLight({
    GodotColor? color,
    num energy = 1.0,
    bool shadow = false,
    Object? rotation,
    Object? position,
  }) {
    final l = c.create('DirectionalLight3D');
    l.set('light_color', color ?? const GodotColor(1.0, 0.98, 0.92, 1.0));
    l.set('light_energy', GFloat(energy));
    if (shadow) l.set('shadow_enabled', true);
    setTransform(l, position: position, rotation: rotation);
    return l;
  }

  GodotObject omniLight({
    GodotColor? color,
    num energy = 1.0,
    num? range,
    Object? position,
  }) {
    final l = c.create('OmniLight3D');
    l.set('light_color', color ?? const GodotColor(1, 1, 1, 1));
    l.set('light_energy', GFloat(energy));
    if (range != null) l.set('omni_range', GFloat(range));
    setTransform(l, position: position);
    return l;
  }

  GodotObject spotLight({
    GodotColor? color,
    num energy = 1.0,
    num? range,
    num? angle,
    Object? position,
    Object? rotation,
  }) {
    final l = c.create('SpotLight3D');
    l.set('light_color', color ?? const GodotColor(1, 1, 1, 1));
    l.set('light_energy', GFloat(energy));
    if (range != null) l.set('spot_range', GFloat(range));
    if (angle != null) l.set('spot_angle', GFloat(angle));
    setTransform(l, position: position, rotation: rotation);
    return l;
  }

  /// A `WorldEnvironment` + `Environment`, so a scene is lit and framed before
  /// you add explicit lights.
  ///
  /// The two background/ambient enum values are written numerically to keep
  /// this synchronous: `Environment.BG_COLOR` is 1 and
  /// `AMBIENT_SOURCE_COLOR` is 3. Reading them through [GodotController.constant]
  /// would make every environment build await a round trip.
  GodotObject environment({GodotColor? bg, GodotColor? ambient, num ambientEnergy = 0.6}) {
    final we = c.create('WorldEnvironment');
    final env = c.create('Environment');
    env.set('background_mode', const GInt(1)); // BG_COLOR
    env.set('background_color', bg ?? const GodotColor(0.05, 0.06, 0.09, 1.0));
    env.set('ambient_light_source', const GInt(3)); // AMBIENT_SOURCE_COLOR
    env.set('ambient_light_color', ambient ?? const GodotColor(0.5, 0.55, 0.7, 1.0));
    env.set('ambient_light_energy', GFloat(ambientEnergy));
    we.set('environment', env);
    return we;
  }

  /// Instantiate a `PackedScene` by path (`res://….tscn`, an imported `.glb`).
  Future<GodotObject?> instanceScene(String path) async {
    final packed = c.load(path);
    final instance = await packed.call('instantiate');
    if (instance is GodotRef) return GodotObject(c, instance.id);
    return null;
  }

  /// Apply `position` / `rotation` (degrees) / `scale` / `visible` to a Node3D.
  ///
  /// Each accepts a `Vector3`, a `[x, y, z]` list, or a scalar (uniform).
  void setTransform(
    GodotObject node, {
    Object? position,
    Object? rotation,
    Object? scale,
    bool? visible,
  }) {
    if (position != null) node.set('position', vec3(position, 0, 0, 0));
    if (rotation != null) {
      node.set('rotation_degrees', vec3(rotation, 0, 0, 0));
    }
    if (scale != null) node.set('scale', vec3(scale, 1, 1, 1));
    if (visible != null) node.set('visible', visible);
  }

  /// Coerce a loose value into a [Vector3]: a `Vector3`, an `[x,y,z]` list, a
  /// scalar (uniform), or the given default.
  static Vector3 vec3(Object? v, num dx, num dy, num dz) {
    if (v is Vector3) return v;
    if (v is num) return Vector3(v.toDouble(), v.toDouble(), v.toDouble());
    if (v is List && v.length >= 3) {
      return Vector3(
        (v[0] as num).toDouble(),
        (v[1] as num).toDouble(),
        (v[2] as num).toDouble(),
      );
    }
    return Vector3(dx.toDouble(), dy.toDouble(), dz.toDouble());
  }
}
