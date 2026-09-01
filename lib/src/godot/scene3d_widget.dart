/// `Scene3D` — an embedded Godot viewport as an ordinary Flutter widget.
///
/// Two ways to drive it, and you can use both at once:
///
///   * **declaratively**, with [initialScene] — the JSON DSL in `scene_dsl.dart`
///     builds the starting world;
///   * **imperatively**, with a [GodotSceneController] you own, whose
///     [GodotSceneController.godot] exposes the full reflective Godot API for
///     everything afterwards.
///
/// ```dart
/// final controller = GodotSceneController();
///
/// Scene3D(
///   controller: controller,
///   initialScene: const {
///     'environment': {'bg': '#0d1117'},
///     'camera': {'position': [0, 3, 8], 'rotation': [-18, 0, 0]},
///     'lights': [{'type': 'directional', 'shadow': true, 'rotation': [-50, -30, 0]}],
///     'nodes': [{'type': 'mesh', 'shape': 'torus', 'id': 'ring', 'color': '#6699ff'}],
///   },
///   onReady: (scene) {
///     final ring = scene.require('ring');
///     ring.set('scale', const Vector3(1.4, 1.4, 1.4));
///   },
/// )
/// ```
///
/// When no Godot artifact is present on the platform the widget renders
/// [placeholder] instead of a viewport and the controller still records ops, so
/// a `Scene3D` is safe to place in any tree — the surrounding 2D app is
/// unaffected.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/elpian_node.dart';
import 'godot_binding.dart';
import 'godot_controller.dart';
import 'godot_object.dart';
import 'scene_dsl.dart';
import 'scene_taps.dart';

/// Owns a scene's engine controller and its built nodes across rebuilds.
///
/// Create one in your `State` and dispose it there; passing the same controller
/// to a rebuilt `Scene3D` keeps the world alive.
class GodotSceneController extends ChangeNotifier {
  GodotSceneController({GodotBinding? binding})
      : godot = GodotController(binding: binding);

  /// The full engine API — `create`, `singleton`, `g3`, batching, callbacks.
  final GodotController godot;

  GodotScene? _scene;
  bool _disposed = false;

  /// The nodes built from `initialScene`, once built.
  GodotScene? get scene => _scene;

  /// Whether a real engine is behind this controller.
  bool get isLive => godot.isLive;

  /// A node from the initial scene by its DSL `id`, or null before the scene
  /// is built.
  GodotObject? node(String id) => _scene?.byId(id);

  void _adopt(GodotScene scene) {
    _scene = scene;
    if (!_disposed) notifyListeners();
  }

  /// Replace the world with a new DSL scene, discarding the previous one.
  GodotScene replaceScene(Map<String, Object?> json) {
    for (final root in _scene?.roots ?? const <GodotObject>[]) {
      root.queueFree();
    }
    final built = SceneDsl(godot).build(json);
    _adopt(built);
    return built;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    godot.dispose();
    super.dispose();
  }
}

/// An embedded Godot 3D viewport.
class Scene3D extends StatefulWidget {
  const Scene3D({
    super.key,
    this.controller,
    this.initialScene,
    this.onReady,
    this.placeholder,
    this.width,
    this.height,
    this.clickable = false,
    this.tapProps,
  });

  /// The controller to drive this scene. When null the widget owns one for its
  /// lifetime.
  final GodotSceneController? controller;

  /// The declarative starting world. Built once, when the surface attaches.
  final Map<String, Object?>? initialScene;

  /// Called after [initialScene] is built and the surface is attached.
  final void Function(GodotScene scene)? onReady;

  /// Shown when no Godot engine is available on this platform.
  final Widget? placeholder;

  final double? width;
  final double? height;

  /// Report taps on this surface to [ElpianSceneTaps] — the hook server-driven
  /// UI uses to turn a 3D tap into navigation.
  final bool clickable;

  /// The props delivered to [ElpianSceneTaps] when [clickable] and tapped.
  final Map<String, dynamic>? tapProps;

  /// Build a `Scene3D` from an Elpian node — the registry entry point.
  ///
  /// Reads `initialScene` (or a bare `scene` / `world`) from props, plus
  /// `width`/`height` and the `clickable` / tap props the scene-tap hook uses.
  static Widget build(ElpianNode node, List<Widget> children) {
    final props = node.props;
    final scene = props['initialScene'] ?? props['scene'] ?? props['world'];
    return Scene3D(
      key: node.key == null ? null : ValueKey(node.key),
      initialScene: scene is Map
          ? scene.map((k, v) => MapEntry('$k', v))
          : (scene is List ? {'nodes': scene} : null),
      width: (props['width'] as num?)?.toDouble() ?? node.style?.width,
      height: (props['height'] as num?)?.toDouble() ?? node.style?.height,
      clickable: props['clickable'] == true,
      tapProps: props,
      placeholder: children.isNotEmpty ? children.first : null,
    );
  }

  @override
  State<Scene3D> createState() => _Scene3DState();
}

class _Scene3DState extends State<Scene3D> {
  GodotSceneController? _owned;
  bool _attached = false;

  GodotSceneController get _controller => widget.controller ?? _owned!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) _owned = GodotSceneController();
    // Attaching touches the platform channel, so it must not run during build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _attach());
  }

  Future<void> _attach() async {
    if (_attached || !mounted) return;
    _attached = true;

    final controller = _controller;
    final json = widget.initialScene;
    GodotScene? built;
    if (json != null && controller.scene == null) {
      built = SceneDsl(controller.godot).build(json);
      controller._adopt(built);
    }

    await controller.godot.attachSurface();
    if (!mounted) return;

    final scene = built ?? controller.scene;
    if (scene != null) widget.onReady?.call(scene);
  }

  @override
  void didUpdateWidget(Scene3D oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A guest program drives this widget declaratively: it re-renders the node
    // with a new `initialScene` rather than calling the controller. Without
    // this the world would be built once and never change, which makes the
    // whole DSL path inert after first paint.
    //
    // Only rebuild when the scene actually differs — a parent rebuilding for
    // unrelated reasons must not tear down and re-create the world.
    final next = widget.initialScene;
    if (next != null &&
        !_sceneEquals(oldWidget.initialScene, next) &&
        _attached) {
      _controller.replaceScene(next);
      widget.onReady?.call(_controller.scene!);
    }
  }

  /// Structural comparison of two scene descriptions.
  ///
  /// `identical` is too weak (a guest re-emits a fresh map every render) and
  /// `==` on nested maps is reference equality, so neither detects a real
  /// change. Comparing the encoded form is exact and cheap next to rebuilding
  /// a 3D world.
  static bool _sceneEquals(Map<String, Object?>? a, Map<String, Object?>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    return jsonEncode(a) == jsonEncode(b);
  }

  @override
  void dispose() {
    // Only tear down a controller this widget created; a caller-supplied one
    // outlives the widget by design.
    _owned?.dispose();
    _owned = null;
    if (widget.controller != null && _attached) {
      widget.controller!.godot.detachSurface();
    }
    super.dispose();
  }

  void _handleTap() {
    if (!widget.clickable) return;
    ElpianSceneTaps.handler?.call(widget.tapProps ?? const {});
  }

  @override
  Widget build(BuildContext context) {
    Widget surface = _controller.isLive
        ? _viewport()
        : (widget.placeholder ?? const _Scene3DPlaceholder());

    if (widget.clickable) {
      surface = GestureDetector(onTap: _handleTap, child: surface);
    }

    if (widget.width != null || widget.height != null) {
      surface = SizedBox(
        width: widget.width,
        height: widget.height,
        child: surface,
      );
    }
    return surface;
  }

  /// The native viewport hosting this surface's Godot render target.
  Widget _viewport() {
    final params = <String, dynamic>{'surfaceId': _controller.godot.surfaceId};
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidView(
          viewType: GodotChannels.viewType,
          creationParams: params,
          creationParamsCodec: const StandardMessageCodec(),
          // The Godot view consumes its own gestures; without this the
          // surrounding Flutter scroll views would steal every drag.
          gestureRecognizers: const {},
        );
      case TargetPlatform.iOS:
        return UiKitView(
          viewType: GodotChannels.viewType,
          creationParams: params,
          creationParamsCodec: const StandardMessageCodec(),
        );
      default:
        return widget.placeholder ?? const _Scene3DPlaceholder();
    }
  }
}

/// What a `Scene3D` shows where no engine is available.
///
/// Deliberately quiet and self-explanatory rather than an error: a 2D app with
/// a 3D panel should still be usable on a platform without the Godot artifact.
class _Scene3DPlaceholder extends StatelessWidget {
  const _Scene3DPlaceholder();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF10141D), Color(0xFF1A2233)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.view_in_ar_outlined, size: 36, color: Colors.white24),
              SizedBox(height: 8),
              Text(
                '3D unavailable on this platform',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
      );
}
