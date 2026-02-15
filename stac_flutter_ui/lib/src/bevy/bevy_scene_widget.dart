import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'bevy_scene_controller.dart';
import 'bevy_scene_api.dart'
    if (dart.library.js_interop) 'bevy_scene_api_web.dart';
import '../models/stac_node.dart';

/// A Flutter widget that renders a Bevy 3D scene from JSON.
///
/// This widget creates a high-performance bridge between the Rust-based
/// Bevy 3D renderer and Flutter's widget system. It supports:
///
/// - JSON-defined 3D scenes (meshes, lights, cameras, particles, etc.)
/// - Real-time animation with configurable FPS
/// - Touch/gesture input forwarding
/// - Dynamic scene updates
/// - Automatic resize handling
/// - Cross-platform support (mobile, desktop, web)
///
/// Usage:
/// ```dart
/// BevySceneWidget(
///   sceneJson: '{"world": [{"type": "mesh3d", "mesh": "Cube", ...}]}',
///   width: 800,
///   height: 600,
///   fps: 60,
///   interactive: true,
/// )
/// ```
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

  /// Build a BevySceneWidget from a StacNode (for JSON GUI integration).
  static Widget build(StacNode node, List<Widget> children) {
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
      case 'fill':
        return BoxFit.fill;
      case 'cover':
        return BoxFit.cover;
      case 'fitWidth':
        return BoxFit.fitWidth;
      case 'fitHeight':
        return BoxFit.fitHeight;
      case 'none':
        return BoxFit.none;
      case 'scaleDown':
        return BoxFit.scaleDown;
      default:
        return BoxFit.contain;
    }
  }

  @override
  State<BevySceneWidget> createState() => _BevySceneWidgetState();
}

class _BevySceneWidgetState extends State<BevySceneWidget>
    with SingleTickerProviderStateMixin {
  late final BevySceneController _controller;
  late final Ticker _ticker;
  ui.Image? _currentImage;
  bool _isInitialized = false;
  Duration _lastFrameTime = Duration.zero;
  Offset _lastTouchPosition = Offset.zero;

  static int _globalSceneCounter = 0;
  static bool _systemInitialized = false;

  @override
  void initState() {
    super.initState();

    // Initialize the Bevy scene subsystem once
    if (!_systemInitialized) {
      BevySceneController.initialize();
      _systemInitialized = true;
    }

    final id = widget.sceneId ?? 'bevy_scene_${_globalSceneCounter++}';
    _controller = BevySceneController(sceneId: id);

    _ticker = createTicker(_onTick);

    // Load scene after first layout
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initScene();
    });
  }

  void _initScene() {
    if (!mounted) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    final size = renderBox?.size ?? const Size(512, 512);

    final renderWidth = (widget.width ?? size.width).toInt().clamp(1, 4096);
    final renderHeight = (widget.height ?? size.height).toInt().clamp(1, 4096);

    final json = widget.sceneJson ?? _encodeSceneMap(widget.sceneMap!);
    final success = _controller.loadScene(
      json,
      width: renderWidth,
      height: renderHeight,
    );

    if (success) {
      _isInitialized = true;
      widget.onSceneCreated?.call(_controller);

      // Render first frame immediately
      _controller.renderFrame(deltaTime: 0);
      _updateImage();

      // Start render loop if autoStart is enabled
      if (widget.autoStart && !_ticker.isActive) {
        _ticker.start();
      }
    }
  }

  String _encodeSceneMap(Map<String, dynamic> map) {
    // Use a simple JSON encode; the Rust side handles parsing
    try {
      return _jsonEncode(map);
    } catch (_) {
      return '{"world":[]}';
    }
  }

  // Inline JSON encode to avoid importing dart:convert at top level
  String _jsonEncode(Object? value) {
    if (value == null) return 'null';
    if (value is String) return '"${_escapeString(value)}"';
    if (value is num || value is bool) return value.toString();
    if (value is List) {
      return '[${value.map(_jsonEncode).join(',')}]';
    }
    if (value is Map) {
      final entries = value.entries
          .map((e) => '"${_escapeString(e.key.toString())}":${_jsonEncode(e.value)}')
          .join(',');
      return '{$entries}';
    }
    return '"$value"';
  }

  String _escapeString(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
  }

  void _onTick(Duration elapsed) {
    if (!_isInitialized || !mounted) return;

    // Calculate delta time
    final deltaTime = _lastFrameTime == Duration.zero
        ? 1.0 / widget.fps
        : (elapsed - _lastFrameTime).inMicroseconds / 1000000.0;
    _lastFrameTime = elapsed;

    // Cap delta time to avoid huge jumps (e.g., after tab switch)
    final cappedDelta = deltaTime.clamp(0.0, 0.1);

    // Render frame
    _controller.renderFrame(deltaTime: cappedDelta);
    _updateImage();
  }

  void _updateImage() {
    final frame = _controller.getFrame();
    if (frame == null || frame.isEmpty) return;

    // Decode RGBA pixels into a dart:ui Image
    _decodePixelsToImage(frame.pixels, frame.width, frame.height);
  }

  void _decodePixelsToImage(Uint8List pixels, int width, int height) {
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
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

    // Update scene if JSON changed
    if (widget.sceneJson != oldWidget.sceneJson ||
        widget.sceneMap != oldWidget.sceneMap) {
      final json = widget.sceneJson ?? _encodeSceneMap(widget.sceneMap!);
      _controller.updateScene(json);
    }

    // Handle FPS change (ticker rate is fixed; fps controls frame skip)
    // Handle resize
    if (widget.width != oldWidget.width || widget.height != oldWidget.height) {
      if (widget.width != null && widget.height != null) {
        _controller.resize(
          width: widget.width!.toInt(),
          height: widget.height!.toInt(),
        );
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _currentImage?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child;

    if (_currentImage != null) {
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
    if (widget.interactive) {
      // Use onScale* instead of onPan* because Flutter does not allow
      // both pan and scale gesture recognizers on the same GestureDetector
      // (scale is a superset of pan).
      child = GestureDetector(
        onScaleStart: (details) {
          _lastTouchPosition = details.localFocalPoint;
          _controller.sendTouchDown(
            details.localFocalPoint.dx,
            details.localFocalPoint.dy,
          );
        },
        onScaleUpdate: (details) {
          final pos = details.localFocalPoint;
          final delta = pos - _lastTouchPosition;
          _lastTouchPosition = pos;

          if (details.pointerCount > 1) {
            // Multi-touch: treat as zoom/scroll
            _controller.sendMouseWheel(
              pos.dx,
              pos.dy,
              deltaY: details.scale - 1.0,
            );
          } else {
            // Single touch: treat as drag/pan
            _controller.sendTouchMove(
              pos.dx,
              pos.dy,
              deltaX: delta.dx,
              deltaY: delta.dy,
            );
          }
        },
        onScaleEnd: (details) {
          _controller.sendTouchUp(
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

/// Custom painter that efficiently renders the Bevy scene's pixel output.
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
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );

    final dst = _applyFit(fit, src, Offset.zero & size);

    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  Rect _applyFit(BoxFit fit, Rect src, Rect dst) {
    final srcAspect = src.width / src.height;
    final dstAspect = dst.width / dst.height;

    switch (fit) {
      case BoxFit.fill:
        return dst;
      case BoxFit.contain:
        if (srcAspect > dstAspect) {
          final h = dst.width / srcAspect;
          return Rect.fromLTWH(
              dst.left, dst.top + (dst.height - h) / 2, dst.width, h);
        } else {
          final w = dst.height * srcAspect;
          return Rect.fromLTWH(
              dst.left + (dst.width - w) / 2, dst.top, w, dst.height);
        }
      case BoxFit.cover:
        if (srcAspect < dstAspect) {
          final h = dst.width / srcAspect;
          return Rect.fromLTWH(
              dst.left, dst.top + (dst.height - h) / 2, dst.width, h);
        } else {
          final w = dst.height * srcAspect;
          return Rect.fromLTWH(
              dst.left + (dst.width - w) / 2, dst.top, w, dst.height);
        }
      case BoxFit.fitWidth:
        final h = dst.width / srcAspect;
        return Rect.fromLTWH(
            dst.left, dst.top + (dst.height - h) / 2, dst.width, h);
      case BoxFit.fitHeight:
        final w = dst.height * srcAspect;
        return Rect.fromLTWH(
            dst.left + (dst.width - w) / 2, dst.top, w, dst.height);
      case BoxFit.none:
        return Rect.fromLTWH(
            dst.left + (dst.width - src.width) / 2,
            dst.top + (dst.height - src.height) / 2,
            src.width,
            src.height);
      case BoxFit.scaleDown:
        if (src.width <= dst.width && src.height <= dst.height) {
          return Rect.fromLTWH(
              dst.left + (dst.width - src.width) / 2,
              dst.top + (dst.height - src.height) / 2,
              src.width,
              src.height);
        }
        return _applyFit(BoxFit.contain, src, dst);
    }
  }

  @override
  bool shouldRepaint(_BevyScenePainter oldDelegate) {
    return image != oldDelegate.image;
  }
}
