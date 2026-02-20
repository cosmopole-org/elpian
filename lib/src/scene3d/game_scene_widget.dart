/// Flutter widget that renders a 3D scene using the pure-Dart engine.
///
/// Replaces [BevySceneWidget] for platform-independent 3D rendering.
/// Uses [Scene3DRenderer] + [SceneParser] to parse JSON and render via Canvas.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'core.dart';
import 'renderer.dart';
import 'scene_parser.dart';
import '../models/elpian_node.dart';

/// A Flutter widget that renders a 3D scene from a JSON definition
/// using a pure-Dart Canvas-based renderer.
///
/// Works on all Flutter platforms (mobile, desktop, web) without
/// any native library or WASM compilation.
class GameSceneWidget extends StatefulWidget {
  /// JSON string defining the 3D scene.
  final String? sceneJson;

  /// JSON map defining the 3D scene (alternative to sceneJson).
  final Map<String, dynamic>? sceneMap;

  /// Target frames per second.
  final int fps;

  /// Whether to forward touch/pointer events for camera control.
  final bool interactive;

  /// Whether to start the render loop automatically.
  final bool autoStart;

  /// Background color shown behind the sky gradient.
  final Color backgroundColor;

  /// Callback invoked after each frame is rendered.
  final VoidCallback? onFrameRendered;

  const GameSceneWidget({
    super.key,
    this.sceneJson,
    this.sceneMap,
    this.fps = 60,
    this.interactive = true,
    this.autoStart = true,
    this.backgroundColor = const Color(0xFF141420),
    this.onFrameRendered,
  }) : assert(sceneJson != null || sceneMap != null,
            'Either sceneJson or sceneMap must be provided');

  /// Build from a ElpianNode (for JSON GUI integration).
  static Widget build(ElpianNode node, List<Widget> children) {
    final props = node.props;
    final sceneData = props['scene'] ?? props['sceneJson'];
    final fps = (props['fps'] as num?)?.toInt() ?? 60;
    final interactive = props['interactive'] as bool? ?? true;

    if (sceneData is Map<String, dynamic>) {
      return GameSceneWidget(
        sceneMap: sceneData,
        fps: fps,
        interactive: interactive,
      );
    }

    return GameSceneWidget(
      sceneJson: sceneData?.toString() ?? '{"world":[]}',
      fps: fps,
      interactive: interactive,
    );
  }

  @override
  State<GameSceneWidget> createState() => _GameSceneWidgetState();
}

class _GameSceneWidgetState extends State<GameSceneWidget>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final Scene3DRenderer _renderer;
  late ParsedScene _scene;
  Duration _lastFrameTime = Duration.zero;

  // Camera interaction state
  Offset _lastPointerPos = Offset.zero;
  double _orbitYaw = 0;
  double _orbitPitch = 0;
  double _orbitDistance = 0;
  Vec3 _orbitTarget = Vec3.zero;
  bool _orbitInitialized = false;

  @override
  void initState() {
    super.initState();
    _renderer = Scene3DRenderer();
    _parseScene();

    _ticker = createTicker(_onTick);
    if (widget.autoStart) {
      _ticker.start();
    }
  }

  void _parseScene() {
    Map<String, dynamic> json;
    try {
      if (widget.sceneJson != null) {
        json = jsonDecode(widget.sceneJson!) as Map<String, dynamic>;
      } else {
        json = widget.sceneMap ?? {'world': []};
      }
    } catch (_) {
      json = {'world': []};
    }
    _scene = SceneParser.parse(json);

    // Initialize orbit from camera position
    if (!_orbitInitialized) {
      final cam = _scene.camera;
      _orbitTarget = cam.target;
      final delta = cam.position - cam.target;
      _orbitDistance = delta.length;
      if (_orbitDistance > 0.001) {
        _orbitPitch = math.asin((delta.y / _orbitDistance).clamp(-1.0, 1.0));
        _orbitYaw = math.atan2(delta.x, delta.z);
      }
      _orbitInitialized = true;
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;

    final dt = _lastFrameTime == Duration.zero
        ? 1.0 / widget.fps
        : (elapsed - _lastFrameTime).inMicroseconds / 1000000.0;
    _lastFrameTime = elapsed;
    final cappedDt = dt.clamp(0.0, 0.1);

    _renderer.advanceTime(cappedDt);
    setState(() {});
    widget.onFrameRendered?.call();
  }

  @override
  void didUpdateWidget(GameSceneWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sceneJson != oldWidget.sceneJson ||
        widget.sceneMap != oldWidget.sceneMap) {
      _parseScene();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onScaleStart(ScaleStartDetails details) {
    _lastPointerPos = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final pos = details.localFocalPoint;
    final delta = pos - _lastPointerPos;
    _lastPointerPos = pos;

    if (details.pointerCount > 1) {
      // Pinch to zoom
      _orbitDistance *= (1.0 / details.scale).clamp(0.5, 2.0);
      _orbitDistance = _orbitDistance.clamp(1.0, 100.0);
    } else {
      // Drag to orbit
      _orbitYaw -= delta.dx * 0.005;
      _orbitPitch = (_orbitPitch + delta.dy * 0.005).clamp(-1.4, 1.4);
    }

    // Update camera position from orbit parameters
    _scene.camera.position = Vec3(
      _orbitTarget.x + _orbitDistance * math.cos(_orbitPitch) * math.sin(_orbitYaw),
      _orbitTarget.y + _orbitDistance * math.sin(_orbitPitch),
      _orbitTarget.z + _orbitDistance * math.cos(_orbitPitch) * math.cos(_orbitYaw),
    );
    _scene.camera.target = _orbitTarget;
  }

  @override
  Widget build(BuildContext context) {
    Widget child = CustomPaint(
      painter: _GameScenePainter(
        renderer: _renderer,
        scene: _scene,
      ),
      size: Size.infinite,
    );

    if (widget.interactive) {
      child = GestureDetector(
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        child: child,
      );
    }

    return RepaintBoundary(
      child: Container(
        color: widget.backgroundColor,
        child: child,
      ),
    );
  }
}

/// CustomPainter that delegates to Scene3DRenderer.
class _GameScenePainter extends CustomPainter {
  final Scene3DRenderer renderer;
  final ParsedScene scene;

  const _GameScenePainter({
    required this.renderer,
    required this.scene,
  });

  @override
  void paint(Canvas canvas, Size size) {
    renderer.render(
      canvas,
      size,
      camera: scene.camera,
      environment: scene.environment,
      lights: scene.lights,
      nodes: scene.nodes,
    );
  }

  @override
  bool shouldRepaint(_GameScenePainter oldDelegate) => true;
}
