import 'dart:ui' as ui;
import 'package:flutter/material.dart';

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
  Matrix4 transform;

  CanvasState({
    Paint? fillPaint,
    Paint? strokePaint,
    this.fillColor = Colors.black,
    this.strokeColor = Colors.black,
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
      transform: transform.clone(),
    );
  }
}

/// Gradient definition
class CanvasGradient {
  final String id;
  final List<Color> colors;
  final List<double> stops;
  final Offset? start;
  final Offset? end;
  final Offset? center;
  final double? radius;
  final bool isRadial;

  CanvasGradient({
    required this.id,
    required this.colors,
    required this.stops,
    this.start,
    this.end,
    this.center,
    this.radius,
    this.isRadial = false,
  });

  Shader createShader(Rect bounds) {
    if (isRadial) {
      return ui.Gradient.radial(
        center ?? bounds.center,
        radius ?? bounds.width / 2,
        colors,
        stops,
      );
    } else {
      return ui.Gradient.linear(
        start ?? bounds.topLeft,
        end ?? bounds.bottomRight,
        colors,
        stops,
      );
    }
  }
}

/// Canvas API executor
class CanvasAPIExecutor {
  final List<CanvasCommand> commands = [];
  final List<CanvasState> stateStack = [];
  final Map<String, CanvasGradient> gradients = {};
  final Map<String, ui.Image> images = {};

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
    currentState = CanvasState();
    currentPath = Path();
  }

  /// Execute all commands
  void execute(Canvas canvas, Size size) {
    for (final command in commands) {
      _executeCommand(canvas, size, command);
    }
  }

  /// Execute a subset of commands (incremental rendering)
  void executeCommands(Canvas canvas, Size size, List<CanvasCommand> subset) {
    for (final command in subset) {
      _executeCommand(canvas, size, command);
    }
  }

  void _executeCommand(Canvas canvas, Size size, CanvasCommand command) {
    final params = command.params;

    switch (command.type) {
      // Path operations
      case CanvasCommandType.moveTo:
        currentPath.moveTo(
          _getDouble(params, 'x'),
          _getDouble(params, 'y'),
        );
        break;

      case CanvasCommandType.lineTo:
        currentPath.lineTo(
          _getDouble(params, 'x'),
          _getDouble(params, 'y'),
        );
        break;

      case CanvasCommandType.quadraticCurveTo:
        currentPath.quadraticBezierTo(
          _getDouble(params, 'cpx'),
          _getDouble(params, 'cpy'),
          _getDouble(params, 'x'),
          _getDouble(params, 'y'),
        );
        break;

      case CanvasCommandType.bezierCurveTo:
        currentPath.cubicTo(
          _getDouble(params, 'cp1x'),
          _getDouble(params, 'cp1y'),
          _getDouble(params, 'cp2x'),
          _getDouble(params, 'cp2y'),
          _getDouble(params, 'x'),
          _getDouble(params, 'y'),
        );
        break;

      case CanvasCommandType.arc:
        _drawArc(params);
        break;

      case CanvasCommandType.arcTo:
        currentPath.arcToPoint(
          Offset(_getDouble(params, 'x'), _getDouble(params, 'y')),
          radius: Radius.circular(_getDouble(params, 'radius', 0)),
        );
        break;

      case CanvasCommandType.rect:
        currentPath.addRect(Rect.fromLTWH(
          _getDouble(params, 'x'),
          _getDouble(params, 'y'),
          _getDouble(params, 'width'),
          _getDouble(params, 'height'),
        ));
        break;

      case CanvasCommandType.roundRect:
        currentPath.addRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(
            _getDouble(params, 'x'),
            _getDouble(params, 'y'),
            _getDouble(params, 'width'),
            _getDouble(params, 'height'),
          ),
          Radius.circular(_getDouble(params, 'radius', 0)),
        ));
        break;

      case CanvasCommandType.circle:
        currentPath.addOval(Rect.fromCircle(
          center: Offset(_getDouble(params, 'x'), _getDouble(params, 'y')),
          radius: _getDouble(params, 'radius'),
        ));
        break;

      case CanvasCommandType.ellipse:
        currentPath.addOval(Rect.fromCenter(
          center: Offset(_getDouble(params, 'x'), _getDouble(params, 'y')),
          width: _getDouble(params, 'radiusX') * 2,
          height: _getDouble(params, 'radiusY') * 2,
        ));
        break;

      // Shape operations
      case CanvasCommandType.fillRect:
        canvas.drawRect(
          Rect.fromLTWH(
            _getDouble(params, 'x'),
            _getDouble(params, 'y'),
            _getDouble(params, 'width'),
            _getDouble(params, 'height'),
          ),
          _getFillPaint(),
        );
        break;

      case CanvasCommandType.strokeRect:
        canvas.drawRect(
          Rect.fromLTWH(
            _getDouble(params, 'x'),
            _getDouble(params, 'y'),
            _getDouble(params, 'width'),
            _getDouble(params, 'height'),
          ),
          _getStrokePaint(),
        );
        break;

      case CanvasCommandType.clearRect:
        // C: drawRect with BlendMode.clear avoids the offscreen layer that
        // saveLayer/restore would allocate. Same result: the region is cleared
        // to transparent.
        canvas.drawRect(
          Rect.fromLTWH(
            _getDouble(params, 'x'),
            _getDouble(params, 'y'),
            _getDouble(params, 'width'),
            _getDouble(params, 'height'),
          ),
          _clearPaint,
        );
        break;

      case CanvasCommandType.fillCircle:
        canvas.drawCircle(
          Offset(_getDouble(params, 'x'), _getDouble(params, 'y')),
          _getDouble(params, 'radius'),
          _getFillPaint(),
        );
        break;

      case CanvasCommandType.strokeCircle:
        canvas.drawCircle(
          Offset(_getDouble(params, 'x'), _getDouble(params, 'y')),
          _getDouble(params, 'radius'),
          _getStrokePaint(),
        );
        break;

      // Text operations
      case CanvasCommandType.fillText:
        _drawText(canvas, params, true);
        break;

      case CanvasCommandType.strokeText:
        _drawText(canvas, params, false);
        break;

      // Path control
      case CanvasCommandType.beginPath:
        currentPath = Path();
        break;

      case CanvasCommandType.closePath:
        currentPath.close();
        break;

      case CanvasCommandType.fill:
        canvas.drawPath(currentPath, _getFillPaint());
        break;

      case CanvasCommandType.stroke:
        canvas.drawPath(currentPath, _getStrokePaint());
        break;

      case CanvasCommandType.clip:
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
        currentState.transform.translate(
          _getDouble(params, 'x'),
          _getDouble(params, 'y'),
        );
        canvas.translate(
          _getDouble(params, 'x'),
          _getDouble(params, 'y'),
        );
        break;

      case CanvasCommandType.rotate:
        final angle = _getDouble(params, 'angle');
        currentState.transform.rotateZ(angle);
        canvas.rotate(angle);
        break;

      case CanvasCommandType.scale:
        canvas.scale(
          _getDouble(params, 'x'),
          _getDouble(params, 'y', _getDouble(params, 'x')),
        );
        break;

      // Style operations
      case CanvasCommandType.setFillStyle:
        _setFillStyle(params);
        break;

      case CanvasCommandType.setStrokeStyle:
        _setStrokeStyle(params);
        break;

      case CanvasCommandType.setLineWidth:
        currentState.lineWidth = _getDouble(params, 'width');
        break;

      case CanvasCommandType.setLineCap:
        currentState.lineCap = _parseLineCap(params['cap'] as String?);
        break;

      case CanvasCommandType.setLineJoin:
        currentState.lineJoin = _parseLineJoin(params['join'] as String?);
        break;

      case CanvasCommandType.setGlobalAlpha:
        currentState.globalAlpha = _getDouble(params, 'alpha', 1.0);
        break;

      // Gradient operations
      case CanvasCommandType.createLinearGradient:
        _createLinearGradient(params);
        break;

      case CanvasCommandType.createRadialGradient:
        _createRadialGradient(params);
        break;

      default:
        debugPrint('Unhandled canvas command: ${command.type}');
    }
  }

  void _drawArc(Map<String, dynamic> params) {
    final x = _getDouble(params, 'x');
    final y = _getDouble(params, 'y');
    final radius = _getDouble(params, 'radius');
    final startAngle = _getDouble(params, 'startAngle');
    final endAngle = _getDouble(params, 'endAngle');
    final counterclockwise = params['counterclockwise'] as bool? ?? false;

    final rect = Rect.fromCircle(center: Offset(x, y), radius: radius);
    final sweepAngle =
        counterclockwise ? startAngle - endAngle : endAngle - startAngle;

    currentPath.arcTo(rect, startAngle, sweepAngle, false);
  }

  void _drawText(Canvas canvas, Map<String, dynamic> params, bool fill) {
    final text = params['text'] as String? ?? '';
    final x = _getDouble(params, 'x');
    final y = _getDouble(params, 'y');

    final textSpan = TextSpan(
      text: text,
      style: _parseTextStyle(fill),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textAlign: currentState.textAlign,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    textPainter.paint(canvas, Offset(x, y));
  }

  TextStyle _parseTextStyle(bool fill) {
    // Parse font string (e.g., "16px Arial") once per distinct font; only the
    // color below varies per draw.
    final parsed =
        _fontCache[currentState.font] ??= _ParsedFont.parse(currentState.font);

    return TextStyle(
      fontSize: parsed.size,
      fontFamily: parsed.family,
      color:
          fill ? currentState.fillPaint.color : currentState.strokePaint.color,
      fontWeight: parsed.bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: parsed.italic ? FontStyle.italic : FontStyle.normal,
    );
  }

  void _setFillStyle(Map<String, dynamic> params) {
    if (params.containsKey('color')) {
      final color = _parseColor(params['color']);
      currentState.fillColor = color;
      currentState.fillPaint
        ..color = color
        ..shader = null;
    } else if (params.containsKey('gradientId')) {
      final gradient = gradients[params['gradientId']];
      if (gradient != null) {
        currentState.fillPaint.shader = gradient.createShader(Rect.largest);
      }
    }
  }

  void _setStrokeStyle(Map<String, dynamic> params) {
    if (params.containsKey('color')) {
      final color = _parseColor(params['color']);
      currentState.strokeColor = color;
      currentState.strokePaint
        ..color = color
        ..shader = null;
    } else if (params.containsKey('gradientId')) {
      final gradient = gradients[params['gradientId']];
      if (gradient != null) {
        currentState.strokePaint.shader = gradient.createShader(Rect.largest);
      }
    }
  }

  void _createLinearGradient(Map<String, dynamic> params) {
    final id = params['id'] as String;
    final colors =
        (params['colors'] as List).map((c) => _parseColor(c)).toList();
    final stops = params['stops'] as List<double>?;

    gradients[id] = CanvasGradient(
      id: id,
      colors: colors,
      stops:
          stops ?? List.generate(colors.length, (i) => i / (colors.length - 1)),
      start: Offset(_getDouble(params, 'x0'), _getDouble(params, 'y0')),
      end: Offset(_getDouble(params, 'x1'), _getDouble(params, 'y1')),
      isRadial: false,
    );
  }

  void _createRadialGradient(Map<String, dynamic> params) {
    final id = params['id'] as String;
    final colors =
        (params['colors'] as List).map((c) => _parseColor(c)).toList();
    final stops = params['stops'] as List<double>?;

    gradients[id] = CanvasGradient(
      id: id,
      colors: colors,
      stops:
          stops ?? List.generate(colors.length, (i) => i / (colors.length - 1)),
      center: Offset(_getDouble(params, 'x'), _getDouble(params, 'y')),
      radius: _getDouble(params, 'r'),
      isRadial: true,
    );
  }

  Paint _getFillPaint() {
    final alpha = currentState.globalAlpha;
    return currentState.fillPaint
      // Derive from the base color every time so globalAlpha doesn't compound
      // across draws. Skip the allocation entirely when fully opaque.
      ..color = alpha >= 1.0
          ? currentState.fillColor
          : currentState.fillColor.withOpacity(alpha)
      ..blendMode = currentState.blendMode;
  }

  Paint _getStrokePaint() {
    final alpha = currentState.globalAlpha;
    return currentState.strokePaint
      ..strokeWidth = currentState.lineWidth
      ..strokeCap = currentState.lineCap
      ..strokeJoin = currentState.lineJoin
      ..color = alpha >= 1.0
          ? currentState.strokeColor
          : currentState.strokeColor.withOpacity(alpha)
      ..blendMode = currentState.blendMode;
  }

  double _getDouble(Map<String, dynamic> params, String key,
      [double defaultValue = 0.0]) => switch (params[key]) {
    double v => v,
    int v => v.toDouble(),
    String v => double.tryParse(v) ?? defaultValue,
    _ => defaultValue,
  };

  Color _parseColor(dynamic value) {
    if (value is Color) return value;
    if (value is int) return Color(value);
    if (value is String) {
      if (value.startsWith('#')) {
        final hex = value.substring(1);
        if (hex.length == 6) {
          return Color(int.parse('FF$hex', radix: 16));
        } else if (hex.length == 8) {
          return Color(int.parse(hex, radix: 16));
        }
      } else if (value.startsWith('rgb')) {
        // Parse rgb(r,g,b) or rgba(r,g,b,a)
        final match =
            RegExp(r'rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)')
                .firstMatch(value);
        if (match != null) {
          final r = int.parse(match.group(1)!);
          final g = int.parse(match.group(2)!);
          final b = int.parse(match.group(3)!);
          final a = match.group(4) != null
              ? (double.parse(match.group(4)!) * 255).toInt()
              : 255;
          return Color.fromARGB(a, r, g, b);
        }
      }
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

  StrokeJoin _parseLineJoin(String? join) => _lineJoinMap[join] ?? StrokeJoin.miter;
}

/// Parsed components of a Canvas 2D `font` string, cached per distinct string (C).
class _ParsedFont {
  final double size;
  final String family;
  final bool bold;
  final bool italic;

  const _ParsedFont(this.size, this.family, this.bold, this.italic);

  factory _ParsedFont.parse(String font) {
    final parts = font.split(' ');
    double size = 10;
    String family = 'sans-serif';
    for (final part in parts) {
      if (part.endsWith('px')) {
        size = double.tryParse(part.replaceAll('px', '')) ?? 10;
      } else if (!part.contains('bold') && !part.contains('italic')) {
        family = part;
      }
    }
    return _ParsedFont(
      size,
      family,
      font.contains('bold'),
      font.contains('italic'),
    );
  }
}
