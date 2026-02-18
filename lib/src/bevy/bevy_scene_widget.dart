import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'bevy_scene_controller.dart';
import 'bevy_scene_api.dart'
    if (dart.library.js_interop) 'bevy_scene_api_web.dart';
import 'dart_scene_renderer.dart';
import '../models/elpian_node.dart';

/// A Flutter widget that renders a Bevy 3D scene from JSON.
///
/// This widget supports two rendering paths:
/// 1. **FFI path** (native/WASM): Uses the Rust software renderer via FFI
/// 2. **Dart path** (fallback): Pure-Dart Canvas-based 3D renderer
///
/// The Dart fallback activates automatically when the native library is
/// unavailable, ensuring the 3D scene renders on all platforms including
/// Flutter web / GitHub Pages without requiring Rust compilation.
class BevySceneWidget extends StatefulWidget {
  /// JSON string defining the 3D scene.
  final String? sceneJson;

  /// JSON map defining the 3D scene (alternative to sceneJson).
  final Map<String, dynamic>? sceneMap;

  /// Render width in pixels. If null, uses the widget's layout width.
  final double? width;

  /// Render height in pixels. If null, uses the widget's layout height.
  final double? height;

  /// Target frames per second for the render loop.
  final int fps;

  /// Whether to forward touch/pointer events to the scene.
  final bool interactive;

  /// Whether to start the render loop automatically.
  final bool autoStart;

  /// Background color shown while the scene is loading.
  final Color backgroundColor;

  /// Callback invoked when a frame is rendered.
  final VoidCallback? onFrameRendered;

  /// Callback invoked when the scene is loaded.
  final ValueChanged<BevySceneController>? onSceneCreated;

  /// Unique scene identifier. Auto-generated if not provided.
  final String? sceneId;

  /// How the rendered image should fit within the widget bounds.
  final BoxFit fit;

  const BevySceneWidget({
    super.key,
    this.sceneJson,
    this.sceneMap,
    this.width,
    this.height,
    this.fps = 60,
    this.interactive = true,
    this.autoStart = true,
    this.backgroundColor = Colors.black,
    this.onFrameRendered,
    this.onSceneCreated,
    this.sceneId,
    this.fit = BoxFit.contain,
  }) : assert(sceneJson != null || sceneMap != null,
            'Either sceneJson or sceneMap must be provided');

  /// Build a BevySceneWidget from a ElpianNode (for JSON GUI integration).
  static Widget build(ElpianNode node, List<Widget> children) {
    final props = node.props;
    final sceneData = props['scene'] ?? props['sceneJson'];
    final width = (props['width'] as num?)?.toDouble();
    final height = (props['height'] as num?)?.toDouble();
    final fps = (props['fps'] as num?)?.toInt() ?? 60;
    final interactive = props['interactive'] as bool? ?? true;
    final fit = _parseFit(props['fit'] as String?);

    if (sceneData is Map<String, dynamic>) {
      return BevySceneWidget(
        sceneMap: sceneData,
        width: width,
        height: height,
        fps: fps,
        interactive: interactive,
        fit: fit,
      );
    }

    return BevySceneWidget(
      sceneJson: sceneData?.toString() ?? '{"world":[]}',
      width: width,
      height: height,
      fps: fps,
      interactive: interactive,
      fit: fit,
    );
  }

  static BoxFit _parseFit(String? fit) {
    switch (fit) {
      case 'fill': return BoxFit.fill;
      case 'cover': return BoxFit.cover;
      case 'fitWidth': return BoxFit.fitWidth;
      case 'fitHeight': return BoxFit.fitHeight;
      case 'none': return BoxFit.none;
      case 'scaleDown': return BoxFit.scaleDown;
      default: return BoxFit.contain;
    }
  }

  @override
  State<BevySceneWidget> createState() => _BevySceneWidgetState();
}

class _BevySceneWidgetState extends State<BevySceneWidget>
    with SingleTickerProviderStateMixin {
  BevySceneController? _controller;
  late final Ticker _ticker;
  ui.Image? _currentImage;
  bool _isInitialized = false;
  Duration _lastFrameTime = Duration.zero;
  Offset _lastTouchPosition = Offset.zero;

  /// True when using the pure-Dart fallback renderer.
  bool _useDartRenderer = false;
  DartSceneRenderer? _dartRenderer;
  Map<String, dynamic>? _parsedScene;

  static int _globalSceneCounter = 0;
  static bool _systemInitialized = false;
  static bool _ffiAvailable = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _parseSceneJson();

    // Try to initialize FFI; fall back to Dart renderer on failure
    _tryInitFFI();

    // Start rendering after first layout
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initScene();
    });
  }

  void _parseSceneJson() {
    try {
      if (widget.sceneJson != null) {
        _parsedScene = jsonDecode(widget.sceneJson!) as Map<String, dynamic>;
      } else if (widget.sceneMap != null) {
        _parsedScene = widget.sceneMap;
      }
    } catch (_) {
      _parsedScene = {'world': []};
    }
  }

  void _tryInitFFI() {
    if (_systemInitialized) {
      if (!_ffiAvailable) {
        _useDartRenderer = true;
        _dartRenderer = DartSceneRenderer();
      }
      return;
    }

    try {
      BevySceneController.initialize();
      _systemInitialized = true;
      _ffiAvailable = true;
    } catch (_) {
      // FFI library not available - use Dart renderer
      _systemInitialized = true;
      _ffiAvailable = false;
      _useDartRenderer = true;
      _dartRenderer = DartSceneRenderer();
    }
  }

  void _initScene() {
    if (!mounted) return;

    if (_useDartRenderer) {
      // Dart renderer path: start animation loop immediately
      _isInitialized = true;
      if (widget.autoStart && !_ticker.isActive) {
        _ticker.start();
      }
      // Force first paint
      setState(() {});
      return;
    }

    // FFI path
    final renderBox = context.findRenderObject() as RenderBox?;
    final size = renderBox?.size ?? const Size(512, 512);
    final renderWidth = (widget.width ?? size.width).toInt().clamp(1, 4096);
    final renderHeight = (widget.height ?? size.height).toInt().clamp(1, 4096);

    final id = widget.sceneId ?? 'bevy_scene_${_globalSceneCounter++}';
    _controller = BevySceneController(sceneId: id);

    final json = widget.sceneJson ?? jsonEncode(widget.sceneMap);
    bool success;
    try {
      success = _controller!.loadScene(
        json!,
        width: renderWidth,
        height: renderHeight,
      );
    } catch (_) {
      // FFI call failed at runtime; fall back to Dart renderer
      _useDartRenderer = true;
      _dartRenderer = DartSceneRenderer();
      _ffiAvailable = false;
      _isInitialized = true;
      if (widget.autoStart && !_ticker.isActive) {
        _ticker.start();
      }
      setState(() {});
      return;
    }

    if (success) {
      _isInitialized = true;
      widget.onSceneCreated?.call(_controller!);
      _controller!.renderFrame(deltaTime: 0);
      _updateImage();
      if (widget.autoStart && !_ticker.isActive) {
        _ticker.start();
      }
    } else {
      // Scene creation failed; fall back to Dart renderer
      _useDartRenderer = true;
      _dartRenderer = DartSceneRenderer();
      _isInitialized = true;
      if (widget.autoStart && !_ticker.isActive) {
        _ticker.start();
      }
      setState(() {});
    }
  }

  void _onTick(Duration elapsed) {
    if (!_isInitialized || !mounted) return;

    final deltaTime = _lastFrameTime == Duration.zero
        ? 1.0 / widget.fps
        : (elapsed - _lastFrameTime).inMicroseconds / 1000000.0;
    _lastFrameTime = elapsed;
    final cappedDelta = deltaTime.clamp(0.0, 0.1);

    if (_useDartRenderer) {
      // Advance animation clock, then trigger repaint
      _dartRenderer!.advanceTime(cappedDelta);
      setState(() {});
      widget.onFrameRendered?.call();
    } else {
      _controller?.renderFrame(deltaTime: cappedDelta);
      _updateImage();
    }
  }

  void _updateImage() {
    final frame = _controller?.getFrame();
    if (frame == null || frame.isEmpty) return;

    ui.decodeImageFromPixels(
      frame.pixels,
      frame.width,
      frame.height,
      ui.PixelFormat.rgba8888,
      (ui.Image image) {
        if (!mounted) {
          image.dispose();
          return;
        }
        final oldImage = _currentImage;
        setState(() {
          _currentImage = image;
        });
        oldImage?.dispose();
        widget.onFrameRendered?.call();
      },
    );
  }

  @override
  void didUpdateWidget(BevySceneWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.sceneJson != oldWidget.sceneJson ||
        widget.sceneMap != oldWidget.sceneMap) {
      _parseSceneJson();
      if (!_useDartRenderer) {
        final json = widget.sceneJson ?? jsonEncode(widget.sceneMap);
        _controller?.updateScene(json!);
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _currentImage?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child;

    if (_useDartRenderer && _isInitialized) {
      // Pure-Dart Canvas renderer
      child = CustomPaint(
        painter: _DartScenePainter(
          renderer: _dartRenderer!,
          scene: _parsedScene ?? {'world': []},
          backgroundColor: widget.backgroundColor,
        ),
        size: Size(
          widget.width ?? double.infinity,
          widget.height ?? double.infinity,
        ),
      );
    } else if (_currentImage != null) {
      // FFI renderer
      child = CustomPaint(
        painter: _BevyScenePainter(
          image: _currentImage!,
          fit: widget.fit,
        ),
        size: Size(
          widget.width ?? double.infinity,
          widget.height ?? double.infinity,
        ),
      );
    } else {
      child = Container(
        color: widget.backgroundColor,
        width: widget.width,
        height: widget.height,
      );
    }

    // Wrap with gesture detector for interactive scenes
    if (widget.interactive && _isInitialized) {
      child = GestureDetector(
        onScaleStart: (details) {
          _lastTouchPosition = details.localFocalPoint;
          _controller?.sendTouchDown(
            details.localFocalPoint.dx,
            details.localFocalPoint.dy,
          );
        },
        onScaleUpdate: (details) {
          final pos = details.localFocalPoint;
          final delta = pos - _lastTouchPosition;
          _lastTouchPosition = pos;

          if (details.pointerCount > 1) {
            _controller?.sendMouseWheel(
              pos.dx, pos.dy,
              deltaY: details.scale - 1.0,
            );
          } else {
            _controller?.sendTouchMove(
              pos.dx, pos.dy,
              deltaX: delta.dx,
              deltaY: delta.dy,
            );
          }
        },
        onScaleEnd: (details) {
          _controller?.sendTouchUp(
            _lastTouchPosition.dx,
            _lastTouchPosition.dy,
          );
        },
        child: child,
      );
    }

    return RepaintBoundary(child: child);
  }
}

/// CustomPainter for the pure-Dart 3D renderer path.
/// Renders the scene directly to Canvas on every paint call.
class _DartScenePainter extends CustomPainter {
  final DartSceneRenderer renderer;
  final Map<String, dynamic> scene;
  final Color backgroundColor;

  const _DartScenePainter({
    required this.renderer,
    required this.scene,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // The renderer already advanced its elapsed time in _onTick,
    // so we paint with deltaTime=0 (just draw current state).
    renderer.renderScene(canvas, size, scene, 0);
  }

  @override
  bool shouldRepaint(_DartScenePainter oldDelegate) => true;
}

/// CustomPainter for the FFI renderer path (renders a pixel-buffer image).
class _BevyScenePainter extends CustomPainter {
  final ui.Image image;
  final BoxFit fit;

  const _BevyScenePainter({
    required this.image,
    required this.fit,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(
      0, 0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final dst = _applyFit(fit, src, Offset.zero & size);
    canvas.drawImageRect(
      image, src, dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  Rect _applyFit(BoxFit fit, Rect src, Rect dst) {
    final srcAspect = src.width / src.height;
    final dstAspect = dst.width / dst.height;
    switch (fit) {
      case BoxFit.fill: return dst;
      case BoxFit.contain:
        if (srcAspect > dstAspect) {
          final h = dst.width / srcAspect;
          return Rect.fromLTWH(dst.left, dst.top + (dst.height - h) / 2, dst.width, h);
        } else {
          final w = dst.height * srcAspect;
          return Rect.fromLTWH(dst.left + (dst.width - w) / 2, dst.top, w, dst.height);
        }
      case BoxFit.cover:
        if (srcAspect < dstAspect) {
          final h = dst.width / srcAspect;
          return Rect.fromLTWH(dst.left, dst.top + (dst.height - h) / 2, dst.width, h);
        } else {
          final w = dst.height * srcAspect;
          return Rect.fromLTWH(dst.left + (dst.width - w) / 2, dst.top, w, dst.height);
        }
      case BoxFit.fitWidth:
        final h = dst.width / srcAspect;
        return Rect.fromLTWH(dst.left, dst.top + (dst.height - h) / 2, dst.width, h);
      case BoxFit.fitHeight:
        final w = dst.height * srcAspect;
        return Rect.fromLTWH(dst.left + (dst.width - w) / 2, dst.top, w, dst.height);
      case BoxFit.none:
        return Rect.fromLTWH(
          dst.left + (dst.width - src.width) / 2,
          dst.top + (dst.height - src.height) / 2,
          src.width, src.height,
        );
      case BoxFit.scaleDown:
        if (src.width <= dst.width && src.height <= dst.height) {
          return Rect.fromLTWH(
            dst.left + (dst.width - src.width) / 2,
            dst.top + (dst.height - src.height) / 2,
            src.width, src.height,
          );
        }
        return _applyFit(BoxFit.contain, src, dst);
    }
  }

  @override
  bool shouldRepaint(_BevyScenePainter oldDelegate) {
    return image != oldDelegate.image;
  }
}
