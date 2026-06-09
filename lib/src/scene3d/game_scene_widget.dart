/// Flutter widget that renders a 3D scene using the pure-Dart engine.
///
/// Replaces [BevySceneWidget] for platform-independent 3D rendering.
/// Uses [Scene3DRenderer] + [SceneParser] to parse JSON and render via Canvas.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'core.dart';
import 'renderer.dart';
import 'scene_parser.dart';
import '../models/elpian_node.dart';
import '../diagnostics/elpian_trace.dart';

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

  /// Stable key to prevent reparsing when scene JSON is structurally unchanged.
  final String? sceneKey;

  /// Resolution scale for the 3D layer (0..1]. Values < 1 rasterize the scene
  /// into a smaller offscreen image that is then upscaled to fill the widget,
  /// trading sharpness for far less fill/overdraw — a large win for the CPU
  /// painter on high-DPI screens. 1.0 renders at native resolution.
  final double renderScale;

  const GameSceneWidget({
    super.key,
    this.sceneJson,
    this.sceneMap,
    this.fps = 60,
    this.interactive = true,
    this.autoStart = true,
    this.backgroundColor = const Color(0xFF141420),
    this.onFrameRendered,
    this.sceneKey,
    this.renderScale = 1.0,
  }) : assert(sceneJson != null || sceneMap != null,
            'Either sceneJson or sceneMap must be provided');

  /// Process-wide map of scene identity → a stable [GlobalKey], so the SAME
  /// scene (same `sceneKey`/`staticKey`) keeps its [State] — renderer, ticker,
  /// and cached scene layer — across navigation. Without it, every route change
  /// rebuilds the widget at a fresh tree position, `initState` re-runs, and the
  /// scene is re-created and cold-rendered from scratch (the dominant per-nav
  /// cost). The builds during a navigation are sequential (the FutureBuilder
  /// shows the previous screen, then the next), never simultaneous, so reusing
  /// one GlobalKey per identity cannot collide.
  static final Map<String, GlobalKey> _sceneKeyRegistry = <String, GlobalKey>{};

  static GlobalKey? _stableKeyFor(String? identity) {
    if (identity == null || identity.isEmpty) return null;
    return _sceneKeyRegistry[identity] ??= GlobalKey();
  }

  /// Build from a ElpianNode (for JSON GUI integration).
  static Widget build(ElpianNode node, List<Widget> children) {
    final props = node.props;
    final sceneData = props['scene'] ?? props['sceneJson'];
    final fps = (props['fps'] as num?)?.toInt() ?? 60;
    final interactive = props['interactive'] as bool? ?? true;
    // A `fit` request ("cover"/"contain"/…) means the embedder wants the scene
    // to fill its container (the server pairs it with `style: width/height
    // 100%`). Honour it by dropping the fixed design pixels so the scene paints
    // at the real container size — otherwise a desktop-framed canvas shows only
    // empty sky on a phone. The design width/height stay a fallback for the
    // unsized (no-`fit`) case.
    final fit = props['fit']?.toString();
    final responsive = fit != null && fit.isNotEmpty && fit != 'none';
    final width = responsive ? null : (props['width'] as num?)?.toDouble();
    final height = responsive ? null : (props['height'] as num?)?.toDouble();
    final sceneKey = props['sceneKey']?.toString();
    final renderScale = (props['renderScale'] as num?)?.toDouble() ?? 1.0;

    // Identity that survives a route change: prefer an explicit sceneKey, else
    // the scaffold's `staticKey` (the same city/world background is shared by
    // every screen built on it). Drives [_stableKeyFor] so the scene's State is
    // preserved across navigation instead of torn down and re-created.
    final sceneStaticKey =
        sceneData is Map<String, dynamic> ? sceneData['staticKey']?.toString() : null;
    final identity = (sceneKey != null && sceneKey.isNotEmpty)
        ? sceneKey
        : sceneStaticKey;
    final stableKey = _stableKeyFor(identity);

    Widget scene;
    if (sceneData is Map<String, dynamic>) {
      scene = GameSceneWidget(
        key: stableKey,
        sceneMap: sceneData,
        fps: fps,
        interactive: interactive,
        sceneKey: sceneKey,
        renderScale: renderScale,
      );
    } else {
      scene = GameSceneWidget(
        key: stableKey,
        sceneJson: sceneData?.toString() ?? '{"world":[]}',
        fps: fps,
        interactive: interactive,
        sceneKey: sceneKey,
        renderScale: renderScale,
      );
    }

    if (width != null || height != null) {
      return SizedBox(width: width, height: height, child: scene);
    }

    return scene;
  }

  @override
  State<GameSceneWidget> createState() => _GameSceneWidgetState();

  /// Number of distinct `staticKey`s currently held in the process-wide static
  /// scene cache. Exposed for tests that assert navigation reuse (a second
  /// screen with the same `staticKey` must NOT grow the cache).
  @visibleForTesting
  static int debugStaticSceneCacheSize() =>
      _GameSceneWidgetState._staticSceneCache.length;

  /// Drop all cached static scenes (test isolation).
  @visibleForTesting
  static void debugClearStaticSceneCache() =>
      _GameSceneWidgetState._staticSceneCache.clear();
}

class _GameSceneWidgetState extends State<GameSceneWidget>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final Scene3DRenderer _renderer;
  late ParsedScene _scene;
  Duration _lastFrameTime = Duration.zero;

  // Repaint throttle: the ticker fires at display refresh, but we only need to
  // re-rasterize at the target fps. Accumulate elapsed time and repaint when a
  // frame interval has passed.
  double _repaintAccum = 0;

  // Cached static sub-scene (parsed once, reused every frame). The game ships a
  // huge unchanging world under `staticWorld` keyed by `staticKey`; only the
  // small dynamic `world` is re-parsed per frame and merged in.
  ParsedScene? _staticScene;
  String? _staticKey;

  // Process-wide cache of parsed+baked static sub-scenes, keyed by `staticKey`.
  //
  // The baked geometry the renderer stores on each static node (`renderCache`,
  // world-space lit triangles) is independent of the camera/viewport, so it is
  // safe to share the same static [ParsedScene] across widget instances. This
  // is what makes navigation cheap: opening a panel (which mounts a brand-new
  // GameSceneWidget for the same city) reuses the already-baked island/sky
  // scaffold instead of re-parsing and re-lighting thousands of triangles.
  static final Map<String, ParsedScene> _staticSceneCache =
      <String, ParsedScene>{};

  // Camera interaction state
  Offset _lastPointerPos = Offset.zero;
  double _orbitYaw = 0;
  double _orbitPitch = 0;
  double _orbitDistance = 0;
  Vec3 _orbitTarget = Vec3.zero;
  bool _orbitInitialized = false;

  /// Set whenever the scene must be repainted on the next tick even though the
  /// renderer reported no dynamic content (a fresh parse, a camera drag, …).
  /// Starts true so the very first frame always paints. See [_onTick].
  bool _dirty = true;

  /// Bumped only on the ticks that actually repaint the 3D layer. The painter
  /// keys [CustomPainter.shouldRepaint] off it, so an unrelated parent rebuild
  /// (a HUD poll, a client-component re-render) reuses the cached scene layer
  /// (via the surrounding `RepaintBoundary`) instead of re-rasterizing it.
  int _frameToken = 0;

  @override
  void initState() {
    super.initState();
    ElpianTrace.mark('GameScene initState (NEW renderer + state)');
    _renderer = Scene3DRenderer();
    _parseScene();

    _ticker = createTicker(_onTick);
    if (widget.autoStart) {
      _ticker.start();
    }
  }

  void _parseScene() {
    final _sw = ElpianTrace.enabled ? (Stopwatch()..start()) : null;
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

    // Parse (and cache) the static world once, keyed by `staticKey`. Marking
    // its nodes `isStatic` lets the renderer bake their world-space lit
    // geometry and only re-project it each frame.
    final staticWorld = json['staticWorld'];
    if (staticWorld is List) {
      final key = json['staticKey']?.toString();
      if (key != null && key.isNotEmpty) {
        // Keyed: reuse the process-wide baked static scene across widgets so
        // navigation between screens with the same scaffold never re-bakes.
        final cached = _staticSceneCache[key] ??= _parseStaticWorld(staticWorld);
        _staticScene = cached;
        _staticKey = key;
      } else if (_staticScene == null || key != _staticKey) {
        // Unkeyed: parse once per widget instance.
        _staticScene = _parseStaticWorld(staticWorld);
        _staticKey = key;
      }
    } else {
      _staticScene = null;
      _staticKey = null;
    }

    if (_staticScene == null) {
      _scene = SceneParser.parse(json);
    } else {
      // Only the dynamic `world` is parsed each frame; merge with cached static.
      final dyn = SceneParser.parse(json, ensureLight: false);
      _scene = ParsedScene(
        camera: dyn.camera,
        environment: _staticScene!.environment,
        lights: <Light3D>[..._staticScene!.lights, ...dyn.lights],
        nodes: <SceneNode>[..._staticScene!.nodes, ...dyn.nodes],
      );
    }

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

    // A freshly parsed scene must paint at least once.
    _dirty = true;

    if (_sw != null) {
      _sw.stop();
      final staticCached =
          _staticKey != null && _staticSceneCache.containsKey(_staticKey);
      ElpianTrace.mark('_parseScene done ${_sw.elapsedMilliseconds}ms '
          '(staticKey=$_staticKey, staticCacheHit=$staticCached, '
          'nodes=${_scene.nodes.length})');
    }
  }

  /// Parse a `staticWorld` node list into a [ParsedScene] and flag every node
  /// (and its descendants) static so the renderer bakes + caches its lit
  /// world-space geometry.
  static ParsedScene _parseStaticWorld(List<dynamic> staticWorld) {
    final parsed = SceneParser.parse({'world': staticWorld});
    for (final n in parsed.nodes) {
      _markStatic(n);
    }
    return parsed;
  }

  /// Recursively flag a parsed static node (and its children) so the renderer
  /// bakes and caches its world-space lit geometry.
  static void _markStatic(SceneNode node) {
    node.isStatic = true;
    for (final c in node.children) {
      _markStatic(c);
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

    // Throttle re-rasterization to the target fps even though the ticker fires
    // at display refresh — avoids redundantly re-drawing the whole scene.
    final interval = widget.fps > 0 ? 1.0 / widget.fps : 0.0;
    _repaintAccum += cappedDt;
    if (_repaintAccum + 1e-6 < interval) return;
    _repaintAccum = 0;

    // Idle-repaint gating: a software-rasterized frame of this scene costs
    // 50–130ms of MAIN-THREAD CPU. Re-running it every tick for a scene that
    // never changes (fixed camera, no animation/particles — e.g. the city/menu
    // screens) saturates the UI thread and makes every tap/navigation lag by
    // seconds. So only repaint when something actually changed: a pending edit
    // (_dirty), or the last frame contained time-varying content (an animated
    // camera, particles, a keyframe/glTF animation, or a model still loading).
    if (!_dirty && !_renderer.hadDynamicContent) {
      return;
    }
    _dirty = false;
    _frameToken++;

    setState(() {});
    widget.onFrameRendered?.call();
  }

  @override
  void didUpdateWidget(GameSceneWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sceneKey != null && widget.sceneKey == oldWidget.sceneKey) {
      return;
    }
    if (widget.sceneJson != oldWidget.sceneJson ||
        widget.sceneMap != oldWidget.sceneMap ||
        widget.sceneKey != oldWidget.sceneKey) {
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
    // The user is dragging the camera — repaint the next frame.
    _dirty = true;
  }

  @override
  Widget build(BuildContext context) {
    Widget child = CustomPaint(
      painter: _GameScenePainter(
        renderer: _renderer,
        scene: _scene,
        renderScale: widget.renderScale.clamp(0.1, 1.0),
        frameToken: _frameToken,
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
  final double renderScale;
  final int frameToken;

  const _GameScenePainter({
    required this.renderer,
    required this.scene,
    this.renderScale = 1.0,
    this.frameToken = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (renderScale >= 0.999 || size.isEmpty) {
      _renderTo(canvas, size);
      return;
    }

    // Rasterize the 3D layer into a smaller offscreen image, then upscale it to
    // fill the widget. This cuts fill/overdraw cost roughly by renderScale².
    final rw = math.max(1, (size.width * renderScale).round());
    final rh = math.max(1, (size.height * renderScale).round());
    final recorder = ui.PictureRecorder();
    final inner = Canvas(recorder);
    _renderTo(inner, Size(rw.toDouble(), rh.toDouble()));
    final picture = recorder.endRecording();
    final image = picture.toImageSync(rw, rh);
    final paint = Paint()
      ..filterQuality = FilterQuality.low
      ..isAntiAlias = false;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, rw.toDouble(), rh.toDouble()),
      Offset.zero & size,
      paint,
    );
    image.dispose();
    picture.dispose();
  }

  void _renderTo(Canvas canvas, Size size) {
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
  bool shouldRepaint(_GameScenePainter oldDelegate) =>
      oldDelegate.frameToken != frameToken ||
      oldDelegate.scene != scene ||
      oldDelegate.renderScale != renderScale;
}
