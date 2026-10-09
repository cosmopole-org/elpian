import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../css/css_parser.dart';
import '../css/css_properties.dart';
import 'canvas_image_cache.dart';

/// Canvas API drawing command types
enum CanvasCommandType {
  // Path operations
  moveTo,
  lineTo,
  quadraticCurveTo,
  bezierCurveTo,
  arc,
  arcTo,
  ellipse,
  rect,
  roundRect,

  // Shapes
  circle,
  fillRect,
  strokeRect,
  clearRect,
  fillCircle,
  strokeCircle,
  fillPolygon,
  strokePolygon,

  // Text
  fillText,
  strokeText,

  // Images
  drawImage,
  drawImageRect,

  // Path control
  beginPath,
  closePath,
  fill,
  stroke,
  clip,

  // Transform
  save,
  restore,
  translate,
  rotate,
  scale,
  transform,
  setTransform,
  resetTransform,

  // Styles
  setFillStyle,
  setStrokeStyle,
  setLineWidth,
  setLineCap,
  setLineJoin,
  setMiterLimit,
  setLineDash,
  setLineDashOffset,
  setShadowBlur,
  setShadowColor,
  setShadowOffsetX,
  setShadowOffsetY,
  setGlobalAlpha,
  setGlobalCompositeOperation,
  setFont,
  setTextAlign,
  setTextBaseline,

  // Gradients
  createLinearGradient,
  createRadialGradient,
  addColorStop,

  // Patterns
  createPattern,

  // Pixels
  putImageData,
  getImageData,
  createImageData,

  // Custom
  custom,
}

/// Canvas drawing command
class CanvasCommand {
  final CanvasCommandType type;
  final Map<String, dynamic> params;
  final String? id;

  const CanvasCommand({
    required this.type,
    this.params = const {},
    this.id,
  });

  factory CanvasCommand.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final type = CanvasCommandType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => CanvasCommandType.custom,
    );

    return CanvasCommand(
      type: type,
      params: json['params'] != null
          ? Map<String, dynamic>.from(json['params'] as Map)
          : {},
      id: json['id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'params': params,
        if (id != null) 'id': id,
      };
}

/// Canvas drawing state
class CanvasState {
  Paint fillPaint;
  Paint strokePaint;
  // Base (un-alpha'd) colors. Kept separate from the Paint's live color so that
  // applying globalAlpha each draw derives from the base instead of compounding
  // onto the previously-dimmed color (see _getFillPaint/_getStrokePaint).
  Color fillColor;
  Color strokeColor;

  /// The gradient / pattern the fill or stroke style names, if any. Resolved
  /// to a shader at draw time, so colour stops added after the style was set
  /// still apply (an HTML `CanvasGradient` is live in the same way).
  String? fillGradientId;
  String? strokeGradientId;
  String? fillPatternId;
  String? strokePatternId;
  double lineWidth;
  StrokeCap lineCap;
  StrokeJoin lineJoin;
  double miterLimit;
  List<double> lineDash;
  double lineDashOffset;
  double shadowBlur;
  Color shadowColor;
  double shadowOffsetX;
  double shadowOffsetY;
  double globalAlpha;
  BlendMode blendMode;
  String font;
  TextAlign textAlign;
  TextBaseline textBaseline;

  /// The canvas `textBaseline` keyword (`alphabetic`, `top`, `hanging`,
  /// `middle`, `ideographic`, `bottom`) — [textBaseline] can only model two.
  String textBaselineName;

  /// The current transform, relative to the canvas's own origin. Tracked so
  /// `setTransform` / `resetTransform` can replace it and pixel operations
  /// can ignore it.
  Matrix4 transform;

  CanvasState({
    Paint? fillPaint,
    Paint? strokePaint,
    this.fillColor = Colors.black,
    this.strokeColor = Colors.black,
    this.fillGradientId,
    this.strokeGradientId,
    this.fillPatternId,
    this.strokePatternId,
    this.lineWidth = 1.0,
    this.lineCap = StrokeCap.butt,
    this.lineJoin = StrokeJoin.miter,
    this.miterLimit = 10.0,
    this.lineDash = const [],
    this.lineDashOffset = 0.0,
    this.shadowBlur = 0.0,
    this.shadowColor = Colors.transparent,
    this.shadowOffsetX = 0.0,
    this.shadowOffsetY = 0.0,
    this.globalAlpha = 1.0,
    this.blendMode = BlendMode.srcOver,
    this.font = '10px sans-serif',
    this.textAlign = TextAlign.start,
    this.textBaseline = TextBaseline.alphabetic,
    this.textBaselineName = 'alphabetic',
    Matrix4? transform,
  })  : fillPaint = fillPaint ?? (Paint()..color = Colors.black),
        strokePaint = strokePaint ??
            (Paint()
              ..color = Colors.black
              ..style = PaintingStyle.stroke),
        transform = transform ?? Matrix4.identity();

  CanvasState copy() {
    return CanvasState(
      fillPaint: Paint()
        ..color = fillPaint.color
        ..shader = fillPaint.shader,
      strokePaint: Paint()
        ..color = strokePaint.color
        ..style = strokePaint.style
        ..shader = strokePaint.shader,
      fillColor: fillColor,
      strokeColor: strokeColor,
      fillGradientId: fillGradientId,
      strokeGradientId: strokeGradientId,
      fillPatternId: fillPatternId,
      strokePatternId: strokePatternId,
      lineWidth: lineWidth,
      lineCap: lineCap,
      lineJoin: lineJoin,
      miterLimit: miterLimit,
      lineDash: List.from(lineDash),
      lineDashOffset: lineDashOffset,
      shadowBlur: shadowBlur,
      shadowColor: shadowColor,
      shadowOffsetX: shadowOffsetX,
      shadowOffsetY: shadowOffsetY,
      globalAlpha: globalAlpha,
      blendMode: blendMode,
      font: font,
      textAlign: textAlign,
      textBaseline: textBaseline,
      textBaselineName: textBaselineName,
      transform: transform.clone(),
    );
  }
}

/// Gradient definition.
///
/// Linear gradients run from [start] to [end]. Radial gradients are the HTML
/// two-circle form: they end on the circle ([center], [radius]) and start on
/// the circle ([focal], [focalRadius]); with no focal circle they start at the
/// centre.
class CanvasGradient {
  final String id;
  final List<Color> colors;
  final List<double> stops;
  final Offset? start;
  final Offset? end;
  final Offset? center;
  final double? radius;
  final Offset? focal;
  final double focalRadius;
  final bool isRadial;

  final List<Color> _baseColors;
  final List<double> _baseStops;

  CanvasGradient({
    required this.id,
    required List<Color> colors,
    required List<double> stops,
    this.start,
    this.end,
    this.center,
    this.radius,
    this.focal,
    this.focalRadius = 0.0,
    this.isRadial = false,
  })  : colors = List<Color>.of(colors),
        stops = List<double>.of(stops),
        _baseColors = List<Color>.unmodifiable(colors),
        _baseStops = List<double>.unmodifiable(stops);

  /// `addColorStop`: insert a stop, keeping the stops sorted (a stop at an
  /// offset already present goes after it, as on an HTML canvas).
  void addColorStop(double offset, Color color) {
    final o = offset.clamp(0.0, 1.0);
    var i = stops.indexWhere((s) => s > o);
    if (i < 0) i = stops.length;
    stops.insert(i, o);
    colors.insert(i, color);
  }

  /// Drop stops added with [addColorStop] (a replay adds them again).
  void resetStops() {
    colors
      ..clear()
      ..addAll(_baseColors);
    stops
      ..clear()
      ..addAll(_baseStops);
  }

  Shader createShader(Rect bounds) {
    List<Color> c = colors;
    List<double>? s = stops.length == colors.length ? stops : null;
    if (c.isEmpty) {
      c = const [Colors.transparent, Colors.transparent];
      s = const [0.0, 1.0];
    } else if (c.length == 1) {
      c = [c.first, c.first];
      s = const [0.0, 1.0];
    } else {
      s ??= List.generate(c.length, (i) => i / (c.length - 1));
    }
    if (isRadial) {
      return ui.Gradient.radial(
        center ?? bounds.center,
        radius ?? bounds.width / 2,
        c,
        s,
        TileMode.clamp,
        null,
        focal,
        focalRadius,
      );
    } else {
      return ui.Gradient.linear(
        start ?? bounds.topLeft,
        end ?? bounds.bottomRight,
        c,
        s,
      );
    }
  }
}

/// A `createPattern` fill/stroke style: an image tiled per [repetition]
/// (`repeat`, `repeat-x`, `repeat-y`, `no-repeat`).
class CanvasPattern {
  final String id;
  final String src;
  final String repetition;

  const CanvasPattern({
    required this.id,
    required this.src,
    this.repetition = 'repeat',
  });
}

/// Pixel data held under an id by `createImageData` / `getImageData` /
/// `putImageData`.
///
/// Data built from bytes (`createImageData`, `putImageData` with `data`)
/// keeps unpremultiplied RGBA [pixels]. A `getImageData` snapshot keeps the
/// rasterised [image] instead — a canvas cannot read its pixels back
/// synchronously while it paints; [CanvasAPIExecutor.readImageData] turns
/// either into bytes for a host that needs them.
class CanvasImageData {
  final int width;
  final int height;
  final Uint8List? pixels;
  final ui.Image? image;

  CanvasImageData({
    required this.width,
    required this.height,
    this.pixels,
    this.image,
  });

  /// Transparent black, [width] × [height].
  factory CanvasImageData.blank(int width, int height) => CanvasImageData(
        width: width,
        height: height,
        pixels: Uint8List(width * height * 4),
      );

  void dispose() => image?.dispose();
}

/// A host-registered painter for `custom` commands.
typedef CanvasCustomPainter = void Function(
    Canvas canvas, Size size, Map<String, dynamic> params);

/// Canvas API executor
class CanvasAPIExecutor {
  CanvasAPIExecutor({CanvasImageCache? imageCache})
      : imageCache = imageCache ?? CanvasImageCache.shared;

  final List<CanvasCommand> commands = [];
  final List<CanvasState> stateStack = [];
  final Map<String, CanvasGradient> gradients = {};
  final Map<String, CanvasPattern> patterns = {};
  final Map<String, CanvasImageData> imageData = {};

  /// Images the host registered directly, by id. Looked up before
  /// [imageCache] for `drawImage` / `createPattern` sources.
  final Map<String, ui.Image> images = {};

  /// Where image sources are loaded and decoded.
  final CanvasImageCache imageCache;

  static final Map<String, CanvasCustomPainter> _customPainters = {};

  /// Register a painter for `custom` commands named [name]
  /// (`{type: 'custom', params: {name: …}}`). It runs inside a save/restore.
  static void registerPainter(String name, CanvasCustomPainter painter) {
    _customPainters[name] = painter;
  }

  static void unregisterPainter(String name) => _customPainters.remove(name);

  /// Reused paint for `clearRect` (C). A `drawRect` with `BlendMode.clear`
  /// clears the region to transparent without the offscreen layer that
  /// `saveLayer` allocates.
  static final Paint _clearPaint = Paint()..blendMode = BlendMode.clear;

  /// Cache of parsed font strings (C). The `font` string ("16px Arial bold") is
  /// otherwise re-split and scanned on every `fillText`/`strokeText`; only the
  /// draw color varies per call.
  final Map<String, _ParsedFont> _fontCache = {};

  CanvasState currentState = CanvasState();
  Path currentPath = Path();

  /// The current point of [currentPath] (Flutter's [Path] does not expose
  /// it); `null` when the path has none.
  Offset? _cur;

  /// The start of the current subpath (where `closePath` returns to).
  Offset? _subpathStart;

  /// Set when a draw was skipped because its image was still loading.
  bool _waitingForImages = false;

  /// Index into [commands] of the command executing now (for
  /// `getImageData`, which snapshots everything drawn before it).
  int _cursor = 0;

  /// Whether the last execution skipped a draw whose image is still loading
  /// — its owner should repaint when [imageCache] notifies.
  bool get waitingForImages => _waitingForImages;

  /// Add command
  void addCommand(CanvasCommand command) {
    commands.add(command);
  }

  /// Add multiple commands
  void addCommands(List<CanvasCommand> cmds) {
    commands.addAll(cmds);
  }

  /// Clear all commands
  void clear() {
    commands.clear();
    stateStack.clear();
    gradients.clear();
    patterns.clear();
    for (final d in imageData.values) {
      d.dispose();
    }
    imageData.clear();
    currentState = CanvasState();
    currentPath = Path();
    _cur = null;
    _subpathStart = null;
  }

  /// Reset the drawing state for a replay from the first command: a repaint
  /// must not inherit the path, transform or style the previous paint ended
  /// with.
  void _resetForReplay() {
    stateStack.clear();
    currentState = CanvasState();
    currentPath = Path();
    _cur = null;
    _subpathStart = null;
    _waitingForImages = false;
    for (final g in gradients.values) {
      g.resetStops();
    }
  }

  /// Execute all commands
  void execute(Canvas canvas, Size size) {
    _resetForReplay();
    for (var i = 0; i < commands.length; i++) {
      _cursor = i;
      _executeCommand(canvas, size, commands[i]);
    }
    _cursor = commands.length;
  }

  /// Execute a subset of commands (incremental rendering).
  ///
  /// Continues from the state the previous execution ended in. [canvas] is
  /// usually a fresh recorder layered over the earlier picture, so the
  /// transform in effect is re-applied first.
  void executeCommands(Canvas canvas, Size size, List<CanvasCommand> subset) {
    if (subset.isEmpty) return;
    if (!currentState.transform.isIdentity()) {
      canvas.transform(currentState.transform.storage);
    }
    var base = commands.length - subset.length;
    if (base < 0 || !identical(commands[base], subset.first)) {
      base = commands.indexOf(subset.first);
    }
    for (var i = 0; i < subset.length; i++) {
      _cursor = base < 0 ? commands.length : base + i;
      _executeCommand(canvas, size, subset[i]);
    }
    _cursor = commands.length;
  }

  /// The pixels held under [id] as unpremultiplied RGBA bytes (row-major,
  /// `width * height * 4`), or `null` if there is no such data.
  Future<Uint8List?> readImageData(String id) async {
    final data = imageData[id];
    if (data == null) return null;
    if (data.pixels != null) return Uint8List.fromList(data.pixels!);
    final bytes = await data.image!
        .toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    return bytes?.buffer.asUint8List();
  }

  void _executeCommand(Canvas canvas, Size size, CanvasCommand command) {
    final params = command.params;

    switch (command.type) {
      // Path operations
      case CanvasCommandType.moveTo:
        final p = _point(params);
        currentPath.moveTo(p.dx, p.dy);
        _cur = p;
        _subpathStart = p;
        break;

      case CanvasCommandType.lineTo:
        final p = _point(params);
        _ensureSubpath(p);
        currentPath.lineTo(p.dx, p.dy);
        _cur = p;
        break;

      case CanvasCommandType.quadraticCurveTo:
        final cp = Offset(_getDouble(params, 'cpx'), _getDouble(params, 'cpy'));
        _ensureSubpath(cp);
        final p = _point(params);
        currentPath.quadraticBezierTo(cp.dx, cp.dy, p.dx, p.dy);
        _cur = p;
        break;

      case CanvasCommandType.bezierCurveTo:
        final cp1 =
            Offset(_getDouble(params, 'cp1x'), _getDouble(params, 'cp1y'));
        _ensureSubpath(cp1);
        final p = _point(params);
        currentPath.cubicTo(
          cp1.dx,
          cp1.dy,
          _getDouble(params, 'cp2x'),
          _getDouble(params, 'cp2y'),
          p.dx,
          p.dy,
        );
        _cur = p;
        break;

      case CanvasCommandType.arc:
        _arc(params);
        break;

      case CanvasCommandType.arcTo:
        _arcTo(params);
        break;

      case CanvasCommandType.rect:
        final r = _rect(params);
        currentPath.addRect(r);
        _cur = r.topLeft;
        _subpathStart = r.topLeft;
        break;

      case CanvasCommandType.roundRect:
        final rr = _roundRect(params);
        currentPath.addRRect(rr);
        _cur = rr.outerRect.topLeft;
        _subpathStart = _cur;
        break;

      case CanvasCommandType.circle:
        final c = _point(params);
        final radius = _getDouble(params, 'radius').abs();
        currentPath.addOval(Rect.fromCircle(center: c, radius: radius));
        _cur = c + Offset(radius, 0);
        _subpathStart = _cur;
        break;

      case CanvasCommandType.ellipse:
        _ellipse(params);
        break;

      // Shape operations
      case CanvasCommandType.fillRect:
        final fillR = _rect(params);
        _fill(canvas, (c, paint) => c.drawRect(fillR, paint));
        break;

      case CanvasCommandType.strokeRect:
        _strokePath(canvas, Path()..addRect(_rect(params)));
        break;

      case CanvasCommandType.clearRect:
        // C: drawRect with BlendMode.clear avoids the offscreen layer that
        // saveLayer/restore would allocate. Same result: the region is cleared
        // to transparent.
        canvas.drawRect(_rect(params), _clearPaint);
        break;

      case CanvasCommandType.fillCircle:
        final fillC = _point(params);
        final fillCr = _getDouble(params, 'radius').abs();
        _fill(canvas, (c, paint) => c.drawCircle(fillC, fillCr, paint));
        break;

      case CanvasCommandType.strokeCircle:
        _strokePath(
          canvas,
          Path()
            ..addOval(Rect.fromCircle(
              center: _point(params),
              radius: _getDouble(params, 'radius').abs(),
            )),
        );
        break;

      case CanvasCommandType.fillPolygon:
      case CanvasCommandType.strokePolygon:
        final poly = _polygon(params);
        if (poly == null) break;
        if (command.type == CanvasCommandType.fillPolygon) {
          poly.fillType = _fillType(params);
          _fill(canvas, (c, paint) => c.drawPath(poly, paint));
        } else {
          _strokePath(canvas, poly);
        }
        break;

      // Text operations
      case CanvasCommandType.fillText:
        _drawText(canvas, params, true);
        break;

      case CanvasCommandType.strokeText:
        _drawText(canvas, params, false);
        break;

      // Images
      case CanvasCommandType.drawImage:
      case CanvasCommandType.drawImageRect:
        _drawImage(canvas, params, command.type);
        break;

      // Path control
      case CanvasCommandType.beginPath:
        currentPath = Path();
        _cur = null;
        _subpathStart = null;
        break;

      case CanvasCommandType.closePath:
        currentPath.close();
        _cur = _subpathStart;
        break;

      case CanvasCommandType.fill:
        currentPath.fillType = _fillType(params);
        final path = currentPath;
        _fill(canvas, (c, paint) => c.drawPath(path, paint));
        break;

      case CanvasCommandType.stroke:
        _strokePath(canvas, currentPath);
        break;

      case CanvasCommandType.clip:
        currentPath.fillType = _fillType(params);
        canvas.clipPath(currentPath);
        break;

      // Transform operations
      case CanvasCommandType.save:
        stateStack.add(currentState.copy());
        canvas.save();
        break;

      case CanvasCommandType.restore:
        if (stateStack.isNotEmpty) {
          currentState = stateStack.removeLast();
        }
        canvas.restore();
        break;

      case CanvasCommandType.translate:
        final tx = _getDouble(params, 'x');
        final ty = _getDouble(params, 'y');
        currentState.transform.translateByDouble(tx, ty, 0, 1);
        canvas.translate(tx, ty);
        break;

      case CanvasCommandType.rotate:
        final angle = _getDouble(params, 'angle');
        currentState.transform.rotateZ(angle);
        canvas.rotate(angle);
        break;

      case CanvasCommandType.scale:
        final sx = _getDouble(params, 'x', 1.0);
        final sy = _getDouble(params, 'y', sx);
        currentState.transform.multiply(Matrix4.diagonal3Values(sx, sy, 1.0));
        canvas.scale(sx, sy);
        break;

      case CanvasCommandType.transform:
        final m = _matrixFrom(params);
        currentState.transform.multiply(m);
        canvas.transform(m.storage);
        break;

      case CanvasCommandType.setTransform:
        _replaceTransform(canvas, _matrixFrom(params));
        break;

      case CanvasCommandType.resetTransform:
        _replaceTransform(canvas, Matrix4.identity());
        break;

      // Style operations
      case CanvasCommandType.setFillStyle:
        _setFillStyle(params);
        break;

      case CanvasCommandType.setStrokeStyle:
        _setStrokeStyle(params);
        break;

      case CanvasCommandType.setLineWidth:
        final width = _getDouble(params, 'width', currentState.lineWidth);
        // Like an HTML canvas, non-positive widths are ignored.
        if (width > 0) currentState.lineWidth = width;
        break;

      case CanvasCommandType.setLineCap:
        currentState.lineCap = _parseLineCap(params['cap'] as String?);
        break;

      case CanvasCommandType.setLineJoin:
        currentState.lineJoin = _parseLineJoin(params['join'] as String?);
        break;

      case CanvasCommandType.setGlobalAlpha:
        currentState.globalAlpha =
            _getDouble(params, 'alpha', 1.0).clamp(0.0, 1.0);
        break;

      case CanvasCommandType.setMiterLimit:
        currentState.miterLimit = _getDouble(params, 'limit', 10.0);
        break;

      case CanvasCommandType.setLineDash:
        final segments = params['segments'];
        final dash = segments is List
            ? segments
                .map((e) => e is num
                    ? e.toDouble()
                    : double.tryParse(e.toString()) ?? 0.0)
                .toList()
            : <double>[];
        // HTML: any negative / non-finite value makes the call a no-op.
        if (dash.any((d) => d < 0 || !d.isFinite)) break;
        currentState.lineDash = dash;
        break;

      case CanvasCommandType.setLineDashOffset:
        currentState.lineDashOffset = _getDouble(params, 'offset');
        break;

      case CanvasCommandType.setShadowBlur:
        currentState.shadowBlur = _getDouble(params, 'blur');
        break;

      case CanvasCommandType.setShadowColor:
        currentState.shadowColor = _parseColor(params['color']);
        break;

      case CanvasCommandType.setShadowOffsetX:
        currentState.shadowOffsetX =
            _getDouble(params, 'offset', _getDouble(params, 'x'));
        break;

      case CanvasCommandType.setShadowOffsetY:
        currentState.shadowOffsetY =
            _getDouble(params, 'offset', _getDouble(params, 'y'));
        break;

      case CanvasCommandType.setGlobalCompositeOperation:
        currentState.blendMode =
            _parseBlendMode(params['operation'] as String?);
        break;

      case CanvasCommandType.setFont:
        currentState.font = params['font'] as String? ?? currentState.font;
        break;

      case CanvasCommandType.setTextAlign:
        currentState.textAlign =
            _parseTextAlignName(params['align'] as String?);
        break;

      case CanvasCommandType.setTextBaseline:
        final name = params['baseline'] as String?;
        currentState.textBaselineName =
            _baselineNames.contains(name) ? name! : 'alphabetic';
        currentState.textBaseline = _parseTextBaselineName(name);
        break;

      // Gradient operations
      case CanvasCommandType.createLinearGradient:
        _createLinearGradient(params);
        break;

      case CanvasCommandType.createRadialGradient:
        _createRadialGradient(params);
        break;

      case CanvasCommandType.addColorStop:
        final gradient =
            gradients[(params['gradientId'] ?? params['id'])?.toString()];
        if (gradient == null) break;
        gradient.addColorStop(
            _getDouble(params, 'offset'), _parseColor(params['color']));
        break;

      case CanvasCommandType.createPattern:
        final id = params['id']?.toString();
        if (id == null) break;
        patterns[id] = CanvasPattern(
          id: id,
          src: (params['src'] ?? params['imageId'] ?? '').toString(),
          repetition: (params['repetition'] ?? 'repeat').toString(),
        );
        break;

      // Pixels
      case CanvasCommandType.createImageData:
        final id = params['id']?.toString();
        if (id == null) break;
        final w = _getDouble(params, 'width', 1).round().clamp(1, 8192);
        final h = _getDouble(params, 'height', 1).round().clamp(1, 8192);
        imageData.remove(id)?.dispose();
        imageData[id] = CanvasImageData.blank(w, h);
        break;

      case CanvasCommandType.getImageData:
        _getImageData(size, params);
        break;

      case CanvasCommandType.putImageData:
        _putImageData(canvas, params);
        break;

      case CanvasCommandType.custom:
        final painter = _customPainters[params['name']?.toString() ?? ''];
        if (painter != null) {
          canvas.save();
          try {
            painter(canvas, size, params);
          } catch (e) {
            debugPrint('Elpian canvas: custom painter failed: $e');
          }
          canvas.restore();
        }
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Paths
  // ---------------------------------------------------------------------------

  Offset _point(Map<String, dynamic> params) =>
      Offset(_getDouble(params, 'x'), _getDouble(params, 'y'));

  Rect _rect(Map<String, dynamic> params) => Rect.fromLTWH(
        _getDouble(params, 'x'),
        _getDouble(params, 'y'),
        _getDouble(params, 'width'),
        _getDouble(params, 'height'),
      );

  /// A path segment with no current point starts a subpath at [p] (HTML
  /// "ensure there is a subpath").
  void _ensureSubpath(Offset p) {
    if (_cur != null) return;
    currentPath.moveTo(p.dx, p.dy);
    _cur = p;
    _subpathStart = p;
  }

  RRect _roundRect(Map<String, dynamic> params) {
    final rect = _rect(params);
    final raw = params['radii'];
    List<Radius> radii;
    if (raw is List && raw.isNotEmpty) {
      final r = [
        for (final v in raw)
          Radius.circular(
              (v is num ? v.toDouble() : double.tryParse('$v') ?? 0).abs())
      ];
      // CSS-style 1/2/3/4-value shorthand: TL, TR, BR, BL.
      radii = switch (r.length) {
        1 => [r[0], r[0], r[0], r[0]],
        2 => [r[0], r[1], r[0], r[1]],
        3 => [r[0], r[1], r[2], r[1]],
        _ => [r[0], r[1], r[2], r[3]],
      };
    } else {
      final r = Radius.circular(_getDouble(params, 'radius').abs());
      radii = [r, r, r, r];
    }
    return RRect.fromRectAndCorners(
      rect,
      topLeft: radii[0],
      topRight: radii[1],
      bottomRight: radii[2],
      bottomLeft: radii[3],
    );
  }

  /// The signed sweep of an arc from [start] to [end], normalised the way the
  /// HTML canvas does: at most one full turn, in the requested direction.
  static double _sweep(double start, double end, bool counterclockwise) {
    const tau = 2 * math.pi;
    if (!counterclockwise) {
      if (end - start >= tau) return tau;
      return (end - start) % tau;
    }
    if (start - end >= tau) return -tau;
    return -((start - end) % tau);
  }

  /// Append an arc of [rect] to [path], splitting a full turn into halves
  /// (Skia treats a single 360° `arcTo` as degenerate).
  static void _appendArc(
      Path path, Rect rect, double start, double sweep, bool forceMoveTo) {
    if (sweep.abs() >= 2 * math.pi - 1e-9) {
      final half = sweep / 2;
      path.arcTo(rect, start, half, forceMoveTo);
      path.arcTo(rect, start + half, half, false);
    } else {
      path.arcTo(rect, start, sweep, forceMoveTo);
    }
  }

  void _arc(Map<String, dynamic> params) {
    final x = _getDouble(params, 'x');
    final y = _getDouble(params, 'y');
    final radius = _getDouble(params, 'radius').abs();
    final startAngle = _getDouble(params, 'startAngle');
    final endAngle = _getDouble(params, 'endAngle');
    final counterclockwise = params['counterclockwise'] == true;

    final rect = Rect.fromCircle(center: Offset(x, y), radius: radius);
    final sweep = _sweep(startAngle, endAngle, counterclockwise);
    final hadPoint = _cur != null;
    // HTML: a line joins the current point to the arc's start.
    _appendArc(currentPath, rect, startAngle, sweep, !hadPoint);
    if (!hadPoint) {
      _subpathStart = Offset(
          x + radius * math.cos(startAngle), y + radius * math.sin(startAngle));
    }
    final end = startAngle + sweep;
    _cur = Offset(x + radius * math.cos(end), y + radius * math.sin(end));
  }

  /// `arcTo`: the HTML tangent form `{x1, y1, x2, y2, radius}` — a line to
  /// the first tangent point, then an arc of [radius] tangent to both lines
  /// (current point → (x1,y1) and (x1,y1) → (x2,y2)). The older Flutter form
  /// `{x, y, radius, clockwise?, largeArc?}` (an arc to a point) still works.
  void _arcTo(Map<String, dynamic> params) {
    final radius = _getDouble(params, 'radius').abs();
    if (!params.containsKey('x1') && !params.containsKey('x2')) {
      final target = _point(params);
      if (_cur == null) {
        _ensureSubpath(target);
        return;
      }
      currentPath.arcToPoint(
        target,
        radius: Radius.circular(radius),
        clockwise: params['clockwise'] != false,
        largeArc: params['largeArc'] == true,
      );
      _cur = target;
      return;
    }

    final p1 = Offset(_getDouble(params, 'x1'), _getDouble(params, 'y1'));
    final p2 = Offset(_getDouble(params, 'x2'), _getDouble(params, 'y2'));
    _ensureSubpath(p1);
    final p0 = _cur!;

    final d1 = p1 - p0;
    final d2 = p2 - p1;
    final cross = d1.dx * d2.dy - d1.dy * d2.dx;
    if (p0 == p1 || p1 == p2 || radius == 0 || cross.abs() < 1e-9) {
      // Degenerate: a straight line to (x1, y1).
      currentPath.lineTo(p1.dx, p1.dy);
      _cur = p1;
      return;
    }

    // Unit vectors from the corner towards each neighbour.
    final u1 = (p0 - p1) / (p0 - p1).distance;
    final u2 = (p2 - p1) / (p2 - p1).distance;
    final cosTheta = (u1.dx * u2.dx + u1.dy * u2.dy).clamp(-1.0, 1.0);
    final halfAngle = math.acos(cosTheta) / 2;
    final tangentDistance = radius / math.tan(halfAngle);
    final t1 = p1 + u1 * tangentDistance;
    final t2 = p1 + u2 * tangentDistance;

    currentPath.lineTo(t1.dx, t1.dy);
    currentPath.arcToPoint(
      t2,
      radius: Radius.circular(radius),
      // The arc turns the same way the corner does; y grows downwards, so a
      // positive cross product is a clockwise turn on screen.
      clockwise: cross > 0,
    );
    _cur = t2;
  }

  void _ellipse(Map<String, dynamic> params) {
    final center = _point(params);
    final rx = _getDouble(params, 'radiusX').abs();
    final ry = _getDouble(params, 'radiusY').abs();
    final rotation = _getDouble(params, 'rotation');
    final hasAngles =
        params.containsKey('startAngle') || params.containsKey('endAngle');

    if (!hasAngles && rotation == 0) {
      // A whole, unrotated ellipse: a closed oval subpath.
      currentPath.addOval(
          Rect.fromCenter(center: center, width: rx * 2, height: ry * 2));
      _cur = center + Offset(rx, 0);
      _subpathStart = _cur;
      return;
    }

    final start = _getDouble(params, 'startAngle', 0);
    final end = _getDouble(params, 'endAngle', 2 * math.pi);
    final sweep = _sweep(start, end, params['counterclockwise'] == true);

    final arc = Path();
    _appendArc(
        arc,
        Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
        start,
        sweep,
        true);
    final m = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..rotateZ(rotation);
    final placed = arc.transform(m.storage);

    Offset pointAt(double a) {
      final px = rx * math.cos(a);
      final py = ry * math.sin(a);
      return center +
          Offset(px * math.cos(rotation) - py * math.sin(rotation),
              px * math.sin(rotation) + py * math.cos(rotation));
    }

    if (_cur != null) {
      // HTML: a line joins the current point to the ellipse's start.
      currentPath.extendWithPath(placed, Offset.zero);
    } else {
      currentPath.addPath(placed, Offset.zero);
      _subpathStart = pointAt(start);
    }
    _cur = pointAt(start + sweep);
  }

  /// Points as `[[x,y],…]`, `[{x,y},…]` or a flat `[x0,y0,x1,y1,…]`.
  static List<Offset> pointsOf(dynamic raw) {
    if (raw is! List || raw.isEmpty) return const [];
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;
    if (raw.first is num || raw.first is String) {
      return [
        for (var i = 0; i + 1 < raw.length; i += 2)
          Offset(n(raw[i]), n(raw[i + 1]))
      ];
    }
    return [
      for (final p in raw)
        if (p is List && p.length >= 2)
          Offset(n(p[0]), n(p[1]))
        else if (p is Map)
          Offset(n(p['x']), n(p['y']))
        else if (p is Offset)
          p
    ];
  }

  Path? _polygon(Map<String, dynamic> params) {
    final pts = pointsOf(params['points']);
    if (pts.length < 2) return null;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    if (params['closed'] != false) path.close();
    return path;
  }

  static PathFillType _fillType(Map<String, dynamic> params) =>
      params['fillRule'] == 'evenodd'
          ? PathFillType.evenOdd
          : PathFillType.nonZero;

  // ---------------------------------------------------------------------------
  // Transforms
  // ---------------------------------------------------------------------------

  /// `transform`/`setTransform` take the HTML `(a, b, c, d, e, f)` matrix.
  Matrix4 _matrixFrom(Map<String, dynamic> params) {
    final a = _getDouble(params, 'a', 1);
    final b = _getDouble(params, 'b');
    final c = _getDouble(params, 'c');
    final d = _getDouble(params, 'd', 1);
    final e = _getDouble(params, 'e');
    final f = _getDouble(params, 'f');
    // Column-major: (a b) is the first column, (c d) the second, (e f) the
    // translation.
    return Matrix4(
      a, b, 0, 0, //
      c, d, 0, 0, //
      0, 0, 1, 0, //
      e, f, 0, 1,
    );
  }

  /// Replace the current transform with [m]: undo the tracked transform and
  /// apply [m] in its place. A singular current transform cannot be undone;
  /// everything drawn under it is degenerate anyway, so the replacement is
  /// skipped (and reported) rather than corrupting the matrix further.
  void _replaceTransform(Canvas canvas, Matrix4 m) {
    final current = currentState.transform;
    if (!current.isIdentity()) {
      final inverse = Matrix4.tryInvert(current);
      if (inverse == null) {
        debugPrint('Elpian canvas: cannot replace a singular transform');
        return;
      }
      canvas.transform(inverse.storage);
    }
    if (!m.isIdentity()) canvas.transform(m.storage);
    currentState.transform = m.clone();
  }

  /// Run [draw] with the current transform cancelled (for pixel operations,
  /// which address canvas pixels, not user space).
  void _untransformed(Canvas canvas, void Function() draw) {
    final current = currentState.transform;
    if (current.isIdentity()) {
      draw();
      return;
    }
    final inverse = Matrix4.tryInvert(current);
    if (inverse == null) return;
    canvas.save();
    canvas.transform(inverse.storage);
    draw();
    canvas.restore();
  }

  // ---------------------------------------------------------------------------
  // Painting
  // ---------------------------------------------------------------------------

  /// Fill a shape, emitting its shadow first when one is active.
  void _fill(Canvas canvas, void Function(Canvas, Paint) draw) {
    final paint = _getFillPaint();
    _drawShadow(canvas, paint, draw);
    draw(canvas, paint);
  }

  /// Stroke [path] with the current line style, dashes and shadow.
  void _strokePath(Canvas canvas, Path path) {
    final dashed = _dashed(path);
    final paint = _getStrokePaint();
    _drawShadow(canvas, paint, (c, p) => c.drawPath(dashed, p));
    canvas.drawPath(dashed, paint);
  }

  /// The HTML shadow model: a blurred, offset copy drawn beneath the shape.
  /// The offset is in canvas units, unaffected by the current transform.
  void _drawShadow(
      Canvas canvas, Paint shape, void Function(Canvas, Paint) draw) {
    final shadow = _shadowPaint();
    if (shadow == null) return;
    shadow
      ..style = shape.style
      ..strokeWidth = shape.strokeWidth
      ..strokeCap = shape.strokeCap
      ..strokeJoin = shape.strokeJoin
      ..strokeMiterLimit = shape.strokeMiterLimit;
    final transform = currentState.transform;
    _untransformed(canvas, () {
      canvas.save();
      canvas.translate(currentState.shadowOffsetX, currentState.shadowOffsetY);
      if (!transform.isIdentity()) canvas.transform(transform.storage);
      draw(canvas, shadow);
      canvas.restore();
    });
  }

  /// [path] cut into the current dash pattern (or [path] itself when solid).
  Path _dashed(Path path) {
    var dash = currentState.lineDash;
    if (dash.isEmpty || dash.every((d) => d == 0)) return path;
    // HTML: an odd-length list is repeated to make it even.
    if (dash.length.isOdd) dash = [...dash, ...dash];
    final total = dash.fold<double>(0, (a, b) => a + b);
    final out = Path();
    for (final metric in path.computeMetrics()) {
      // Phase within the pattern at the start of this contour.
      var phase = currentState.lineDashOffset % total;
      var index = 0;
      while (phase >= dash[index]) {
        phase -= dash[index];
        index = (index + 1) % dash.length;
      }
      var remaining = dash[index] - phase;
      var distance = 0.0;
      while (distance < metric.length) {
        final segment = math.min(remaining, metric.length - distance);
        if (index.isEven && segment > 0) {
          out.addPath(
              metric.extractPath(distance, distance + segment), Offset.zero);
        }
        distance += segment;
        index = (index + 1) % dash.length;
        remaining = dash[index];
      }
    }
    return out;
  }

  void _drawText(Canvas canvas, Map<String, dynamic> params, bool fill) {
    final text = params['text']?.toString() ?? '';
    if (text.isEmpty) return;
    final x = _getDouble(params, 'x');
    final y = _getDouble(params, 'y');

    final painter = TextPainter(
      text: TextSpan(text: text, style: _parseTextStyle(fill)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    // `maxWidth`: squeeze the run horizontally to fit, as a canvas does.
    var scaleX = 1.0;
    final maxWidth = params['maxWidth'];
    if (maxWidth is num && maxWidth > 0 && painter.width > maxWidth) {
      scaleX = maxWidth / painter.width;
    }
    final width = painter.width * scaleX;

    // (x, y) is the anchor named by textAlign / textBaseline, as on an HTML
    // canvas: the default (start, alphabetic) puts the left end of the
    // baseline at (x, y).
    final dx = switch (currentState.textAlign) {
      TextAlign.center => -width / 2,
      TextAlign.right || TextAlign.end => -width,
      _ => 0.0,
    };
    final height = painter.height;
    final dy = switch (currentState.textBaselineName) {
      'top' || 'hanging' => 0.0,
      'middle' => -height / 2,
      'bottom' => -height,
      'ideographic' =>
        -painter.computeDistanceToActualBaseline(TextBaseline.ideographic),
      _ => -painter.computeDistanceToActualBaseline(TextBaseline.alphabetic),
    };

    canvas.save();
    canvas.translate(x + dx, y + dy);
    if (scaleX != 1.0) canvas.scale(scaleX, 1.0);
    painter.paint(canvas, Offset.zero);
    canvas.restore();
    painter.dispose();
  }

  TextStyle _parseTextStyle(bool fill) {
    // Parse font string (e.g., "16px Arial") once per distinct font; only the
    // color below varies per draw.
    final parsed =
        _fontCache[currentState.font] ??= _ParsedFont.parse(currentState.font);

    final alpha = currentState.globalAlpha;
    final base = fill ? currentState.fillColor : currentState.strokeColor;
    final color = alpha >= 1.0 ? base : base.withValues(alpha: base.a * alpha);

    final shadow = _shadowPaint() != null
        ? [
            Shadow(
              color: currentState.shadowColor
                  .withValues(alpha: currentState.shadowColor.a * alpha),
              offset: Offset(
                  currentState.shadowOffsetX, currentState.shadowOffsetY),
              blurRadius: currentState.shadowBlur / 2.0,
            ),
          ]
        : null;

    return TextStyle(
      fontSize: parsed.size,
      fontFamily: parsed.family,
      color: fill ? color : null,
      foreground: fill
          ? null
          : (Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = currentState.lineWidth
            ..strokeJoin = currentState.lineJoin
            ..color = color),
      fontWeight: parsed.bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: parsed.italic ? FontStyle.italic : FontStyle.normal,
      shadows: shadow,
    );
  }

  // ---------------------------------------------------------------------------
  // Images and pixels
  // ---------------------------------------------------------------------------

  /// The decoded image a source names, or `null` (and a note to repaint)
  /// while it loads.
  ui.Image? _image(String src) {
    if (src.isEmpty) return null;
    final registered = images[src];
    if (registered != null) return registered;
    final cached = imageCache.get(src);
    if (cached == null && imageCache.isLoading(src)) _waitingForImages = true;
    return cached;
  }

  /// `drawImage` in its three HTML forms — `(x, y)`, `(x, y, width, height)`
  /// and `(sx, sy, sw, sh, dx, dy, dw, dh)` — and `drawImageRect`
  /// (always the nine-argument form).
  void _drawImage(
      Canvas canvas, Map<String, dynamic> params, CanvasCommandType type) {
    final src = (params['src'] ?? params['imageId'] ?? '').toString();
    final image = _image(src);
    if (image == null) return;
    final iw = image.width.toDouble();
    final ih = image.height.toDouble();

    double v(String key, double fallback) =>
        params.containsKey(key) ? _getDouble(params, key, fallback) : fallback;

    Rect source;
    Rect dest;
    if (type == CanvasCommandType.drawImageRect || params.containsKey('sx')) {
      source = Rect.fromLTWH(v('sx', 0), v('sy', 0), v('sw', iw), v('sh', ih));
      dest = Rect.fromLTWH(
        v('dx', v('x', 0)),
        v('dy', v('y', 0)),
        v('dw', v('width', source.width)),
        v('dh', v('height', source.height)),
      );
    } else {
      source = Rect.fromLTWH(0, 0, iw, ih);
      dest = Rect.fromLTWH(
        v('dx', v('x', 0)),
        v('dy', v('y', 0)),
        v('dw', v('width', iw)),
        v('dh', v('height', ih)),
      );
    }
    if (source.width == 0 || source.height == 0 || dest.isEmpty) return;

    final paint = Paint()
      ..color = Color.fromRGBO(0, 0, 0, currentState.globalAlpha)
      ..blendMode = currentState.blendMode
      ..filterQuality = params['smoothing'] == false
          ? FilterQuality.none
          : FilterQuality.medium;
    _drawShadow(canvas, paint, (c, p) => c.drawRect(dest, p));
    canvas.drawImageRect(image, source, dest, paint);
  }

  /// `getImageData`: snapshot the region `(x, y, width, height)` of what
  /// has been drawn so far under `id`. A canvas cannot read back the picture
  /// it is recording, so the commands before this one are replayed into a
  /// separate picture and rasterised.
  void _getImageData(Size size, Map<String, dynamic> params) {
    final id = params['id']?.toString();
    if (id == null) return;
    final x = _getDouble(params, 'x');
    final y = _getDouble(params, 'y');
    final w = _getDouble(params, 'width', 1).round().clamp(1, 8192);
    final h = _getDouble(params, 'height', 1).round().clamp(1, 8192);

    final replay = CanvasAPIExecutor(imageCache: imageCache)
      ..images.addAll(images)
      ..addCommands(commands.sublist(0, _cursor.clamp(0, commands.length)));
    for (final entry in gradients.entries) {
      replay.gradients.putIfAbsent(
        entry.key,
        () => CanvasGradient(
          id: entry.value.id,
          colors: entry.value._baseColors,
          stops: entry.value._baseStops,
          start: entry.value.start,
          end: entry.value.end,
          center: entry.value.center,
          radius: entry.value.radius,
          focal: entry.value.focal,
          focalRadius: entry.value.focalRadius,
          isRadial: entry.value.isRadial,
        ),
      );
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(-x, -y);
    replay.execute(canvas, size);
    if (replay.waitingForImages) _waitingForImages = true;
    final picture = recorder.endRecording();
    try {
      final image = picture.toImageSync(w, h);
      imageData.remove(id)?.dispose();
      imageData[id] = CanvasImageData(width: w, height: h, image: image);
    } finally {
      picture.dispose();
      for (final d in replay.imageData.values) {
        d.dispose();
      }
    }
  }

  /// `putImageData`: write pixels at `(x, y)`, replacing what is there —
  /// no transform, alpha, shadow or compositing applies. The pixels are the
  /// data stored under `id`, or `data` (an RGBA byte list or base64 string,
  /// `width` × `height`; stored under `id` when one is given). The optional
  /// dirty rectangle `dirtyX/dirtyY/dirtyWidth/dirtyHeight` limits the copy.
  void _putImageData(Canvas canvas, Map<String, dynamic> params) {
    final id = params['id']?.toString();
    var data = id == null ? null : imageData[id];
    final bytes = _pixelsOf(params['data']);
    if (bytes != null) {
      final w = _getDouble(params, 'width', (data?.width ?? 1).toDouble())
          .round()
          .clamp(1, 8192);
      final defaultHeight = data?.height ?? (bytes.length / 4 / w).ceil();
      final h = _getDouble(params, 'height', defaultHeight.toDouble())
          .round()
          .clamp(1, 8192);
      final pixels = Uint8List(w * h * 4)
        ..setRange(0, math.min(w * h * 4, bytes.length), bytes);
      data = CanvasImageData(width: w, height: h, pixels: pixels);
      if (id != null) {
        imageData.remove(id)?.dispose();
        imageData[id] = data;
      }
    }
    if (data == null) return;

    final x = _getDouble(params, 'x', _getDouble(params, 'dx'));
    final y = _getDouble(params, 'y', _getDouble(params, 'dy'));
    var dirty =
        Rect.fromLTWH(0, 0, data.width.toDouble(), data.height.toDouble());
    if (params.containsKey('dirtyX') || params.containsKey('dirtyWidth')) {
      dirty = dirty.intersect(Rect.fromLTWH(
        _getDouble(params, 'dirtyX'),
        _getDouble(params, 'dirtyY'),
        _getDouble(params, 'dirtyWidth', data.width.toDouble()),
        _getDouble(params, 'dirtyHeight', data.height.toDouble()),
      ));
      if (dirty.width <= 0 || dirty.height <= 0) return;
    }

    final target = data;
    _untransformed(canvas, () {
      canvas.save();
      canvas.clipRect(dirty.shift(Offset(x, y)));
      final image = target.image;
      if (image != null) {
        canvas.drawImage(
            image, Offset(x, y), Paint()..blendMode = BlendMode.src);
      } else {
        _drawPixels(canvas, target, x, y, dirty);
      }
      canvas.restore();
    });
  }

  /// Paint unpremultiplied RGBA [data] at (x, y) synchronously: each run of
  /// equal pixels on a row becomes one flat-coloured quad of a vertex mesh.
  static void _drawPixels(
      Canvas canvas, CanvasImageData data, double x, double y, Rect dirty) {
    final px = data.pixels!;
    final positions = <double>[];
    final colors = <int>[];
    final x0 = dirty.left.floor().clamp(0, data.width);
    final x1 = dirty.right.ceil().clamp(0, data.width);
    final y0 = dirty.top.floor().clamp(0, data.height);
    final y1 = dirty.bottom.ceil().clamp(0, data.height);
    int argbAt(int col, int row) {
      final i = (row * data.width + col) * 4;
      return (px[i + 3] << 24) | (px[i] << 16) | (px[i + 1] << 8) | px[i + 2];
    }

    for (var row = y0; row < y1; row++) {
      var col = x0;
      while (col < x1) {
        final argb = argbAt(col, row);
        var end = col + 1;
        while (end < x1 && argbAt(end, row) == argb) {
          end++;
        }
        final l = x + col, r = x + end, t = y + row, b = y + row + 1;
        positions.addAll([l, t, r, t, r, b, l, t, r, b, l, b]);
        for (var k = 0; k < 6; k++) {
          colors.add(argb);
        }
        col = end;
      }
    }
    if (positions.isEmpty) return;
    final vertices = ui.Vertices.raw(
      VertexMode.triangles,
      Float32List.fromList(positions),
      colors: Int32List.fromList(colors),
    );
    // The paint is the blend "source" and the vertex colours the
    // "destination", so BlendMode.dst paints the vertex colours; the paint's
    // own BlendMode.src makes them replace the canvas pixels.
    canvas.drawVertices(
        vertices, BlendMode.dst, Paint()..blendMode = BlendMode.src);
    vertices.dispose();
  }

  /// RGBA bytes from a list of numbers or a base64 string.
  static Uint8List? _pixelsOf(dynamic data) {
    if (data is Uint8List) return data;
    if (data is List) {
      return Uint8List.fromList([
        for (final v in data)
          (v is num ? v.round() : int.tryParse('$v') ?? 0).clamp(0, 255)
      ]);
    }
    if (data is String && data.isNotEmpty) {
      try {
        return base64Decode(data);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Styles
  // ---------------------------------------------------------------------------

  void _setFillStyle(Map<String, dynamic> params) {
    final s = currentState;
    if (params.containsKey('color')) {
      final color = _parseColor(params['color']);
      s.fillColor = color;
      s.fillGradientId = null;
      s.fillPatternId = null;
      s.fillPaint
        ..color = color
        ..shader = null;
    } else if (params.containsKey('gradientId')) {
      final id = params['gradientId']?.toString();
      if (gradients.containsKey(id)) {
        s.fillGradientId = id;
        s.fillPatternId = null;
      }
    } else if (params.containsKey('patternId')) {
      final id = params['patternId']?.toString();
      if (patterns.containsKey(id)) {
        s.fillPatternId = id;
        s.fillGradientId = null;
      }
    }
  }

  void _setStrokeStyle(Map<String, dynamic> params) {
    final s = currentState;
    if (params.containsKey('color')) {
      final color = _parseColor(params['color']);
      s.strokeColor = color;
      s.strokeGradientId = null;
      s.strokePatternId = null;
      s.strokePaint
        ..color = color
        ..shader = null;
    } else if (params.containsKey('gradientId')) {
      final id = params['gradientId']?.toString();
      if (gradients.containsKey(id)) {
        s.strokeGradientId = id;
        s.strokePatternId = null;
      }
    } else if (params.containsKey('patternId')) {
      final id = params['patternId']?.toString();
      if (patterns.containsKey(id)) {
        s.strokePatternId = id;
        s.strokeGradientId = null;
      }
    }
  }

  /// The shader for a gradient or pattern style, or `null` for a plain
  /// colour. A pattern whose image is not loaded yet calls [unusable] so the
  /// draw paints nothing, as a canvas does with an unusable pattern.
  Shader? _shaderFor(
      String? gradientId, String? patternId, void Function() unusable) {
    if (gradientId != null) {
      return gradients[gradientId]?.createShader(Rect.largest);
    }
    if (patternId != null) {
      final pattern = patterns[patternId];
      final image = pattern == null ? null : _image(pattern.src);
      if (pattern == null || image == null) {
        unusable();
        return null;
      }
      final (tx, ty) = switch (pattern.repetition) {
        'repeat-x' => (TileMode.repeated, TileMode.decal),
        'repeat-y' => (TileMode.decal, TileMode.repeated),
        'no-repeat' => (TileMode.decal, TileMode.decal),
        _ => (TileMode.repeated, TileMode.repeated),
      };
      return ImageShader(image, tx, ty, Matrix4.identity().storage);
    }
    return null;
  }

  List<Color> _colorsOf(Map<String, dynamic> params) {
    final raw = params['colors'];
    return raw is List ? raw.map(_parseColor).toList() : <Color>[];
  }

  List<double> _stopsOf(Map<String, dynamic> params, int count) {
    final raw = params['stops'];
    if (raw is List && raw.length == count) {
      return raw
          .map((e) => (e is num ? e.toDouble() : double.tryParse('$e') ?? 0.0)
              .clamp(0.0, 1.0))
          .toList();
    }
    if (count <= 1) return List.filled(count, 0.0);
    return List.generate(count, (i) => i / (count - 1));
  }

  void _createLinearGradient(Map<String, dynamic> params) {
    final id = params['id']?.toString();
    if (id == null) return;
    final colors = _colorsOf(params);
    gradients[id] = CanvasGradient(
      id: id,
      colors: colors,
      stops: _stopsOf(params, colors.length),
      start: Offset(_getDouble(params, 'x0'), _getDouble(params, 'y0')),
      end: Offset(_getDouble(params, 'x1'), _getDouble(params, 'y1')),
      isRadial: false,
    );
  }

  /// Radial gradients take the Flutter one-circle form `{x, y, r}` or the
  /// HTML two-circle form `{x0, y0, r0, x1, y1, r1}`.
  void _createRadialGradient(Map<String, dynamic> params) {
    final id = params['id']?.toString();
    if (id == null) return;
    final colors = _colorsOf(params);
    final twoCircle = params.containsKey('x1') || params.containsKey('r1');
    gradients[id] = CanvasGradient(
      id: id,
      colors: colors,
      stops: _stopsOf(params, colors.length),
      center: twoCircle
          ? Offset(_getDouble(params, 'x1'), _getDouble(params, 'y1'))
          : Offset(_getDouble(params, 'x'), _getDouble(params, 'y')),
      radius: (twoCircle ? _getDouble(params, 'r1') : _getDouble(params, 'r'))
          .abs(),
      focal: twoCircle
          ? Offset(_getDouble(params, 'x0'), _getDouble(params, 'y0'))
          : null,
      focalRadius: twoCircle ? _getDouble(params, 'r0').abs() : 0.0,
      isRadial: true,
    );
  }

  static BlendMode _parseBlendMode(String? op) {
    switch (op) {
      case 'multiply':
        return BlendMode.multiply;
      case 'screen':
        return BlendMode.screen;
      case 'overlay':
        return BlendMode.overlay;
      case 'darken':
        return BlendMode.darken;
      case 'lighten':
        return BlendMode.lighten;
      case 'color-dodge':
        return BlendMode.colorDodge;
      case 'color-burn':
        return BlendMode.colorBurn;
      case 'hard-light':
        return BlendMode.hardLight;
      case 'soft-light':
        return BlendMode.softLight;
      case 'difference':
        return BlendMode.difference;
      case 'exclusion':
        return BlendMode.exclusion;
      case 'hue':
        return BlendMode.hue;
      case 'saturation':
        return BlendMode.saturation;
      case 'color':
        return BlendMode.color;
      case 'luminosity':
        return BlendMode.luminosity;
      case 'lighter':
        return BlendMode.plus; // additive
      case 'destination-out':
        return BlendMode.dstOut;
      case 'destination-over':
        return BlendMode.dstOver;
      case 'destination-in':
        return BlendMode.dstIn;
      case 'destination-atop':
        return BlendMode.dstATop;
      case 'source-in':
        return BlendMode.srcIn;
      case 'source-out':
        return BlendMode.srcOut;
      case 'source-atop':
        return BlendMode.srcATop;
      case 'copy':
        return BlendMode.src;
      case 'xor':
        return BlendMode.xor;
      case 'source-over':
      default:
        return BlendMode.srcOver;
    }
  }

  static TextAlign _parseTextAlignName(String? a) {
    switch (a) {
      case 'center':
        return TextAlign.center;
      case 'right':
        return TextAlign.right;
      case 'end':
        return TextAlign.end;
      case 'justify':
        return TextAlign.justify;
      case 'left':
        return TextAlign.left;
      case 'start':
      default:
        return TextAlign.start;
    }
  }

  static const _baselineNames = {
    'top',
    'hanging',
    'middle',
    'alphabetic',
    'ideographic',
    'bottom',
  };

  static TextBaseline _parseTextBaselineName(String? b) {
    // Flutter only models alphabetic/ideographic; the full keyword is kept in
    // CanvasState.textBaselineName for positioning.
    switch (b) {
      case 'ideographic':
      case 'bottom':
        return TextBaseline.ideographic;
      default:
        return TextBaseline.alphabetic;
    }
  }

  /// Returns a shadow paint if the current state has an active shadow, else
  /// null.
  Paint? _shadowPaint() {
    final s = currentState;
    final hasShadow = s.shadowColor.a != 0 &&
        (s.shadowBlur > 0 || s.shadowOffsetX != 0 || s.shadowOffsetY != 0);
    if (!hasShadow) return null;
    final baseAlpha = s.shadowColor.a;
    final paint = Paint()
      ..color = s.shadowColor.withValues(alpha: baseAlpha * s.globalAlpha)
      ..blendMode = s.blendMode;
    if (s.shadowBlur > 0) {
      // Canvas blur radius ≈ 2*sigma; convert to a Gaussian sigma.
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, s.shadowBlur / 2.0);
    }
    return paint;
  }

  Paint _getFillPaint() {
    final s = currentState;
    final alpha = s.globalAlpha;
    var unusable = false;
    final shader =
        _shaderFor(s.fillGradientId, s.fillPatternId, () => unusable = true);
    final paint = s.fillPaint
      ..shader = shader
      ..blendMode = s.blendMode;
    if (unusable) {
      paint.color = Colors.transparent;
    } else if (shader != null) {
      // With a shader only the paint's opacity matters.
      paint.color = Color.fromRGBO(0, 0, 0, alpha);
    } else {
      // Derive from the base color every time so globalAlpha doesn't compound
      // across draws. Skip the allocation entirely when fully opaque.
      paint.color = alpha >= 1.0
          ? s.fillColor
          : s.fillColor.withValues(alpha: s.fillColor.a * alpha);
    }
    return paint;
  }

  Paint _getStrokePaint() {
    final s = currentState;
    final alpha = s.globalAlpha;
    var unusable = false;
    final shader = _shaderFor(
        s.strokeGradientId, s.strokePatternId, () => unusable = true);
    final paint = s.strokePaint
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.lineWidth
      ..strokeCap = s.lineCap
      ..strokeJoin = s.lineJoin
      ..strokeMiterLimit = s.miterLimit
      ..shader = shader
      ..blendMode = s.blendMode;
    if (unusable) {
      paint.color = Colors.transparent;
    } else if (shader != null) {
      paint.color = Color.fromRGBO(0, 0, 0, alpha);
    } else {
      paint.color = alpha >= 1.0
          ? s.strokeColor
          : s.strokeColor.withValues(alpha: s.strokeColor.a * alpha);
    }
    return paint;
  }

  double _getDouble(Map<String, dynamic> params, String key,
          [double defaultValue = 0.0]) =>
      switch (params[key]) {
        double v when v.isFinite => v,
        int v => v.toDouble(),
        String v => double.tryParse(v.trim()) ?? defaultValue,
        _ => defaultValue,
      };

  Color _parseColor(dynamic value) {
    if (value is Color) return value;
    if (value is int) return Color(value);
    if (value is num) return Color(value.toInt());
    if (value is String) {
      final v = value.trim();
      if (v == 'transparent') return Colors.transparent;
      // #RRGGBB / #AARRGGBB (the executor's historical reading), plus the CSS
      // forms CSSParser understands (#rgb, rgb()/rgba(), hsl(), names).
      final parsed = CSSParser.parseColor(v);
      if (parsed != null) return parsed;
    }
    return Colors.black;
  }

  static const _lineCapMap = <String, StrokeCap>{
    'round': StrokeCap.round,
    'square': StrokeCap.square,
  };

  StrokeCap _parseLineCap(String? cap) => _lineCapMap[cap] ?? StrokeCap.butt;

  static const _lineJoinMap = <String, StrokeJoin>{
    'round': StrokeJoin.round,
    'bevel': StrokeJoin.bevel,
  };

  StrokeJoin _parseLineJoin(String? join) =>
      _lineJoinMap[join] ?? StrokeJoin.miter;
}

/// Parsed components of a Canvas 2D `font` string, cached per distinct string (C).
class _ParsedFont {
  final double size;
  final String? family;
  final bool bold;
  final bool italic;

  const _ParsedFont(this.size, this.family, this.bold, this.italic);

  static final _sizePattern =
      RegExp(r'^(\d+(?:\.\d+)?)(px|pt|em|rem)(?:/\S+)?$');

  /// A CSS `font` shorthand: `[style] [weight] size[/line-height] family…`.
  factory _ParsedFont.parse(String font) {
    final parts = font.trim().split(RegExp(r'\s+'));
    double size = 10;
    String family = 'sans-serif';
    for (var i = 0; i < parts.length; i++) {
      final match = _sizePattern.firstMatch(parts[i]);
      if (match == null) continue;
      final n = double.tryParse(match.group(1)!) ?? 10;
      size = switch (match.group(2)) {
        'pt' => n * 4 / 3,
        'em' || 'rem' => n * 16,
        _ => n,
      };
      if (i + 1 < parts.length) family = parts.sublist(i + 1).join(' ');
      break;
    }
    return _ParsedFont(
      size,
      CSSProperties.resolveFontFamily(family),
      RegExp(r'bold|\b[6-9]00\b').hasMatch(font),
      font.contains('italic') || font.contains('oblique'),
    );
  }
}
