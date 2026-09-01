/// The declarative scene DSL — the JSON a `Scene3D` widget takes to build its
/// initial world.
///
/// The controller is the imperative, complete API; this is the declarative
/// front door for the common case. A scene is a tree of nodes:
///
/// ```json
/// {
///   "environment": { "bg": "#0d1117", "ambient": "#8894b0" },
///   "camera":      { "position": [0, 3, 8], "rotation": [-18, 0, 0], "fov": 55 },
///   "lights":  [ { "type": "directional", "energy": 1.3, "shadow": true,
///                  "rotation": [-50, -30, 0] } ],
///   "nodes":   [ { "type": "mesh", "shape": "torus", "id": "ring",
///                  "color": "#6699ff", "position": [0, 1, 0],
///                  "children": [ … ] } ]
/// }
/// ```
///
/// Everything the DSL builds is an ordinary Godot node, so anything it does not
/// express is reachable afterwards through the controller — `scene.byId('ring')`
/// hands back the [GodotObject] and the full reflective API applies.
///
/// The whole build is issued inside one explicit batch, so a scene of any size
/// costs a single crossing.
library;

import 'godot_controller.dart';
import 'godot_object.dart';
import 'godot_values.dart';

/// The result of building a DSL scene: the created nodes, addressable by the
/// `id` the DSL gave them.
class GodotScene {
  GodotScene(this.controller, this.nodesById, this.roots);

  final GodotController controller;
  final Map<String, GodotObject> nodesById;

  /// Top-level nodes, in declaration order.
  final List<GodotObject> roots;

  /// A node by its DSL `id`, or null.
  GodotObject? byId(String id) => nodesById[id];

  /// A node by its DSL `id`, throwing if absent — for code that knows the id
  /// exists and wants a clear failure if the DSL changes underneath it.
  GodotObject require(String id) {
    final node = nodesById[id];
    if (node == null) {
      throw ArgumentError.value(id, 'id', 'no node with this id in the scene');
    }
    return node;
  }
}

/// Builds a scene from its JSON description.
class SceneDsl {
  SceneDsl(this.controller);

  final GodotController controller;

  /// Build [json] under the controller's root.
  ///
  /// Returns immediately: handles are allocated on this side, so the scene is
  /// addressable before the engine has rendered a frame of it.
  GodotScene build(Map<String, Object?> json) {
    final byId = <String, GodotObject>{};
    final roots = <GodotObject>[];

    controller.beginBatch();
    try {
      final env = json['environment'];
      if (env is Map) {
        final node = _environment(env.cast<String, Object?>());
        controller.mount(node);
        roots.add(node);
      }

      final camera = json['camera'];
      if (camera is Map) {
        final node = _camera(camera.cast<String, Object?>());
        controller.mount(node);
        roots.add(node);
        _register(byId, camera, node);
      }

      final lights = json['lights'];
      if (lights is List) {
        for (final light in lights) {
          if (light is! Map) continue;
          final spec = light.cast<String, Object?>();
          final node = _light(spec);
          controller.mount(node);
          roots.add(node);
          _register(byId, spec, node);
        }
      }

      final nodes = json['nodes'];
      if (nodes is List) {
        for (final entry in nodes) {
          if (entry is! Map) continue;
          final node = _node(entry.cast<String, Object?>(), byId);
          if (node == null) continue;
          controller.mount(node);
          roots.add(node);
        }
      }
    } finally {
      // Always close the batch, even if a malformed spec threw: leaving it open
      // would silently stall every later op on this controller.
      controller.endBatch();
    }

    return GodotScene(controller, byId, roots);
  }

  void _register(
      Map<String, GodotObject> byId, Map spec, GodotObject node) {
    final id = spec['id'];
    if (id is String && id.isNotEmpty) byId[id] = node;
  }

  GodotObject _environment(Map<String, Object?> spec) => controller.g3.environment(
        bg: parseColor(spec['bg']),
        ambient: parseColor(spec['ambient']),
        ambientEnergy: spec['ambientEnergy'] as num? ?? 0.6,
      );

  GodotObject _camera(Map<String, Object?> spec) => controller.g3.camera(
        fov: spec['fov'] as num?,
        current: spec['current'] != false,
        position: spec['position'],
        rotation: spec['rotation'],
      );

  GodotObject _light(Map<String, Object?> spec) {
    final g3 = controller.g3;
    switch (spec['type']) {
      case 'omni':
      case 'point':
        return g3.omniLight(
          color: parseColor(spec['color']),
          energy: spec['energy'] as num? ?? 1.0,
          range: spec['range'] as num?,
          position: spec['position'],
        );
      case 'spot':
        return g3.spotLight(
          color: parseColor(spec['color']),
          energy: spec['energy'] as num? ?? 1.0,
          range: spec['range'] as num?,
          angle: spec['angle'] as num?,
          position: spec['position'],
          rotation: spec['rotation'],
        );
      default:
        return g3.dirLight(
          color: parseColor(spec['color']),
          energy: spec['energy'] as num? ?? 1.0,
          shadow: spec['shadow'] == true,
          position: spec['position'],
          rotation: spec['rotation'],
        );
    }
  }

  /// Build one node and its subtree. Returns null for a spec that names no
  /// buildable type, so one bad entry does not abort the whole scene.
  GodotObject? _node(Map<String, Object?> spec, Map<String, GodotObject> byId) {
    final type = spec['type'] as String? ?? 'node';
    GodotObject node;

    switch (type) {
      case 'mesh':
        node = controller.g3.mesh(
          spec['shape'] as String? ?? 'box',
          options: {
            ...spec,
            if (spec['color'] != null) 'color': parseColor(spec['color']),
            if (spec['emission'] != null)
              'emission': parseColor(spec['emission']),
          },
        );
      case 'node':
      case 'group':
        node = controller.g3.node(
          position: spec['position'],
          rotation: spec['rotation'],
          scale: spec['scale'],
          visible: spec['visible'] as bool?,
        );
      case 'camera':
        node = _camera(spec);
      case 'light':
        node = _light(spec);
      default:
        // Any other value is taken as a raw ClassDB class name, so the DSL
        // reaches the whole engine rather than a curated list.
        node = controller.create(type);
        controller.g3.setTransform(
          node,
          position: spec['position'],
          rotation: spec['rotation'],
          scale: spec['scale'],
          visible: spec['visible'] as bool?,
        );
    }

    final props = spec['props'];
    if (props is Map) {
      node.setAll({
        for (final e in props.entries) '${e.key}': _coerceProp(e.value),
      });
    }

    _register(byId, spec, node);

    final children = spec['children'];
    if (children is List) {
      for (final child in children) {
        if (child is! Map) continue;
        final built = _node(child.cast<String, Object?>(), byId);
        if (built != null) node.addChild(built);
      }
    }

    return node;
  }

  /// Property values pass through untouched except colour strings, which are
  /// far too common in scene JSON to require a wrapper.
  Object? _coerceProp(Object? value) {
    if (value is String && _looksLikeColor(value)) {
      return parseColor(value) ?? value;
    }
    return value;
  }
}

bool _looksLikeColor(String v) => v.startsWith('#') && (v.length == 7 || v.length == 9 || v.length == 4);

/// Parse a colour from the DSL: `"#RRGGBB"`, `"#RRGGBBAA"`, `"#RGB"`, an
/// `[r,g,b(,a)]` list of 0..1 doubles, or an existing [GodotColor].
GodotColor? parseColor(Object? value) {
  if (value == null) return null;
  if (value is GodotColor) return value;

  if (value is List && value.length >= 3) {
    double at(int i, double fallback) =>
        i < value.length && value[i] is num ? (value[i] as num).toDouble() : fallback;
    return GodotColor(at(0, 0), at(1, 0), at(2, 0), at(3, 1));
  }

  if (value is String && value.startsWith('#')) {
    var hex = value.substring(1);
    // #RGB → #RRGGBB
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length != 6 && hex.length != 8) return null;
    final rgb = int.tryParse(hex.substring(0, 6), radix: 16);
    if (rgb == null) return null;
    var alpha = 1.0;
    if (hex.length == 8) {
      final a = int.tryParse(hex.substring(6, 8), radix: 16);
      if (a != null) alpha = a / 255.0;
    }
    return GodotColor.hex(rgb, alpha);
  }

  return null;
}
