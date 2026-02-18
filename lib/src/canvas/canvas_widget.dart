import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'canvas_api.dart';

/// Canvas widget that renders drawing commands
class ElpianCanvas extends StatefulWidget {
  final List<Map<String, dynamic>> commands;
  final double? width;
  final double? height;
  final Color? backgroundColor;
  final Function(CanvasAPIExecutor)? onReady;
  
  const ElpianCanvas({
    Key? key,
    required this.commands,
    this.width,
    this.height,
    this.backgroundColor,
    this.onReady,
  }) : super(key: key);

  @override
  State<ElpianCanvas> createState() => _ElpianCanvasState();
}

class _ElpianCanvasState extends State<ElpianCanvas> {
  late CanvasAPIExecutor executor;
  
  @override
  void initState() {
    super.initState();
    _initExecutor();
  }
  
  @override
  void didUpdateWidget(ElpianCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.commands != oldWidget.commands) {
      _initExecutor();
    }
  }
  
  void _initExecutor() {
    executor = CanvasAPIExecutor();
    
    // Parse and add commands
    for (final cmdJson in widget.commands) {
      final command = CanvasCommand.fromJson(cmdJson);
      executor.addCommand(command);
    }
    
    // Notify ready
    widget.onReady?.call(executor);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: widget.backgroundColor,
      child: CustomPaint(
        painter: CanvasPainter(executor),
        size: Size(
          widget.width ?? double.infinity,
          widget.height ?? double.infinity,
        ),
      ),
    );
  }
}

/// Custom painter that executes canvas commands
class CanvasPainter extends CustomPainter {
  final CanvasAPIExecutor executor;
  
  CanvasPainter(this.executor);

  @override
  void paint(Canvas canvas, Size size) {
    executor.execute(canvas, size);
  }

  @override
  bool shouldRepaint(CanvasPainter oldDelegate) {
    return executor != oldDelegate.executor;
  }
}

/// Canvas builder for JSON DSL
class CanvasBuilder {
  final List<Map<String, dynamic>> _commands = [];
  
  /// Begin a new path
  CanvasBuilder beginPath() {
    _commands.add({'type': 'beginPath', 'params': {}});
    return this;
  }
  
  /// Move to point
  CanvasBuilder moveTo(double x, double y) {
    _commands.add({
      'type': 'moveTo',
      'params': {'x': x, 'y': y}
    });
    return this;
  }
  
  /// Line to point
  CanvasBuilder lineTo(double x, double y) {
    _commands.add({
      'type': 'lineTo',
      'params': {'x': x, 'y': y}
    });
    return this;
  }
  
  /// Quadratic curve
  CanvasBuilder quadraticCurveTo(double cpx, double cpy, double x, double y) {
    _commands.add({
      'type': 'quadraticCurveTo',
      'params': {'cpx': cpx, 'cpy': cpy, 'x': x, 'y': y}
    });
    return this;
  }
  
  /// Bezier curve
  CanvasBuilder bezierCurveTo(
    double cp1x, double cp1y,
    double cp2x, double cp2y,
    double x, double y,
  ) {
    _commands.add({
      'type': 'bezierCurveTo',
      'params': {
        'cp1x': cp1x, 'cp1y': cp1y,
        'cp2x': cp2x, 'cp2y': cp2y,
        'x': x, 'y': y,
      }
    });
    return this;
  }
  
  /// Arc
  CanvasBuilder arc(
    double x, double y, double radius,
    double startAngle, double endAngle,
    {bool counterclockwise = false}
  ) {
    _commands.add({
      'type': 'arc',
      'params': {
        'x': x, 'y': y, 'radius': radius,
        'startAngle': startAngle, 'endAngle': endAngle,
        'counterclockwise': counterclockwise,
      }
    });
    return this;
  }
  
  /// Rectangle
  CanvasBuilder rect(double x, double y, double width, double height) {
    _commands.add({
      'type': 'rect',
      'params': {'x': x, 'y': y, 'width': width, 'height': height}
    });
    return this;
  }
  
  /// Rounded rectangle
  CanvasBuilder roundRect(
    double x, double y, double width, double height, double radius,
  ) {
    _commands.add({
      'type': 'roundRect',
      'params': {
        'x': x, 'y': y,
        'width': width, 'height': height,
        'radius': radius,
      }
    });
    return this;
  }
  
  /// Circle
  CanvasBuilder circle(double x, double y, double radius) {
    _commands.add({
      'type': 'circle',
      'params': {'x': x, 'y': y, 'radius': radius}
    });
    return this;
  }
  
  /// Ellipse
  CanvasBuilder ellipse(double x, double y, double radiusX, double radiusY) {
    _commands.add({
      'type': 'ellipse',
      'params': {'x': x, 'y': y, 'radiusX': radiusX, 'radiusY': radiusY}
    });
    return this;
  }
  
  /// Close path
  CanvasBuilder closePath() {
    _commands.add({'type': 'closePath', 'params': {}});
    return this;
  }
  
  /// Fill path
  CanvasBuilder fill() {
    _commands.add({'type': 'fill', 'params': {}});
    return this;
  }
  
  /// Stroke path
  CanvasBuilder stroke() {
    _commands.add({'type': 'stroke', 'params': {}});
    return this;
  }
  
  /// Fill rectangle
  CanvasBuilder fillRect(double x, double y, double width, double height) {
    _commands.add({
      'type': 'fillRect',
      'params': {'x': x, 'y': y, 'width': width, 'height': height}
    });
    return this;
  }
  
  /// Stroke rectangle
  CanvasBuilder strokeRect(double x, double y, double width, double height) {
    _commands.add({
      'type': 'strokeRect',
      'params': {'x': x, 'y': y, 'width': width, 'height': height}
    });
    return this;
  }
  
  /// Clear rectangle
  CanvasBuilder clearRect(double x, double y, double width, double height) {
    _commands.add({
      'type': 'clearRect',
      'params': {'x': x, 'y': y, 'width': width, 'height': height}
    });
    return this;
  }
  
  /// Fill circle
  CanvasBuilder fillCircle(double x, double y, double radius) {
    _commands.add({
      'type': 'fillCircle',
      'params': {'x': x, 'y': y, 'radius': radius}
    });
    return this;
  }
  
  /// Stroke circle
  CanvasBuilder strokeCircle(double x, double y, double radius) {
    _commands.add({
      'type': 'strokeCircle',
      'params': {'x': x, 'y': y, 'radius': radius}
    });
    return this;
  }
  
  /// Fill text
  CanvasBuilder fillText(String text, double x, double y) {
    _commands.add({
      'type': 'fillText',
      'params': {'text': text, 'x': x, 'y': y}
    });
    return this;
  }
  
  /// Stroke text
  CanvasBuilder strokeText(String text, double x, double y) {
    _commands.add({
      'type': 'strokeText',
      'params': {'text': text, 'x': x, 'y': y}
    });
    return this;
  }
  
  /// Save state
  CanvasBuilder save() {
    _commands.add({'type': 'save', 'params': {}});
    return this;
  }
  
  /// Restore state
  CanvasBuilder restore() {
    _commands.add({'type': 'restore', 'params': {}});
    return this;
  }
  
  /// Translate
  CanvasBuilder translate(double x, double y) {
    _commands.add({
      'type': 'translate',
      'params': {'x': x, 'y': y}
    });
    return this;
  }
  
  /// Rotate
  CanvasBuilder rotate(double angle) {
    _commands.add({
      'type': 'rotate',
      'params': {'angle': angle}
    });
    return this;
  }
  
  /// Scale
  CanvasBuilder scale(double x, [double? y]) {
    _commands.add({
      'type': 'scale',
      'params': {'x': x, 'y': y ?? x}
    });
    return this;
  }
  
  /// Set fill style
  CanvasBuilder fillStyle(String color) {
    _commands.add({
      'type': 'setFillStyle',
      'params': {'color': color}
    });
    return this;
  }
  
  /// Set stroke style
  CanvasBuilder strokeStyle(String color) {
    _commands.add({
      'type': 'setStrokeStyle',
      'params': {'color': color}
    });
    return this;
  }
  
  /// Set line width
  CanvasBuilder lineWidth(double width) {
    _commands.add({
      'type': 'setLineWidth',
      'params': {'width': width}
    });
    return this;
  }
  
  /// Set line cap
  CanvasBuilder lineCap(String cap) {
    _commands.add({
      'type': 'setLineCap',
      'params': {'cap': cap}
    });
    return this;
  }
  
  /// Set line join
  CanvasBuilder lineJoin(String join) {
    _commands.add({
      'type': 'setLineJoin',
      'params': {'join': join}
    });
    return this;
  }
  
  /// Set global alpha
  CanvasBuilder globalAlpha(double alpha) {
    _commands.add({
      'type': 'setGlobalAlpha',
      'params': {'alpha': alpha}
    });
    return this;
  }
  
  /// Set font
  CanvasBuilder font(String font) {
    _commands.add({
      'type': 'setFont',
      'params': {'font': font}
    });
    return this;
  }
  
  /// Create linear gradient
  CanvasBuilder createLinearGradient(
    String id,
    double x0, double y0,
    double x1, double y1,
    List<String> colors,
    [List<double>? stops]
  ) {
    _commands.add({
      'type': 'createLinearGradient',
      'params': {
        'id': id,
        'x0': x0, 'y0': y0,
        'x1': x1, 'y1': y1,
        'colors': colors,
        if (stops != null) 'stops': stops,
      }
    });
    return this;
  }
  
  /// Create radial gradient
  CanvasBuilder createRadialGradient(
    String id,
    double x, double y, double r,
    List<String> colors,
    [List<double>? stops]
  ) {
    _commands.add({
      'type': 'createRadialGradient',
      'params': {
        'id': id,
        'x': x, 'y': y, 'r': r,
        'colors': colors,
        if (stops != null) 'stops': stops,
      }
    });
    return this;
  }
  
  /// Use gradient as fill
  CanvasBuilder fillGradient(String gradientId) {
    _commands.add({
      'type': 'setFillStyle',
      'params': {'gradientId': gradientId}
    });
    return this;
  }
  
  /// Use gradient as stroke
  CanvasBuilder strokeGradient(String gradientId) {
    _commands.add({
      'type': 'setStrokeStyle',
      'params': {'gradientId': gradientId}
    });
    return this;
  }
  
  /// Clip to current path
  CanvasBuilder clip() {
    _commands.add({'type': 'clip', 'params': {}});
    return this;
  }
  
  /// Build commands list
  List<Map<String, dynamic>> build() {
    return _commands;
  }
  
  /// Clear commands
  CanvasBuilder clear() {
    _commands.clear();
    return this;
  }
}

/// Canvas presets for common shapes
class CanvasPresets {
  /// Draw a star
  static List<Map<String, dynamic>> star(
    double x, double y, double radius,
    {int points = 5, double innerRadius = 0.5, String? fillColor, String? strokeColor}
  ) {
    final builder = CanvasBuilder();
    
    if (fillColor != null) builder.fillStyle(fillColor);
    if (strokeColor != null) builder.strokeStyle(strokeColor);
    
    builder.beginPath();
    
    for (int i = 0; i < points * 2; i++) {
      final angle = (i * math.pi / points) - math.pi / 2;
      final r = i.isEven ? radius : radius * innerRadius;
      final px = x + r * math.cos(angle);
      final py = y + r * math.sin(angle);
      
      if (i == 0) {
        builder.moveTo(px, py);
      } else {
        builder.lineTo(px, py);
      }
    }
    
    builder.closePath();
    if (fillColor != null) builder.fill();
    if (strokeColor != null) builder.stroke();
    
    return builder.build();
  }
  
  /// Draw a polygon
  static List<Map<String, dynamic>> polygon(
    double x, double y, double radius,
    {int sides = 6, String? fillColor, String? strokeColor}
  ) {
    final builder = CanvasBuilder();
    
    if (fillColor != null) builder.fillStyle(fillColor);
    if (strokeColor != null) builder.strokeStyle(strokeColor);
    
    builder.beginPath();
    
    for (int i = 0; i <= sides; i++) {
      final angle = (i * 2 * math.pi / sides) - math.pi / 2;
      final px = x + radius * math.cos(angle);
      final py = y + radius * math.sin(angle);
      
      if (i == 0) {
        builder.moveTo(px, py);
      } else {
        builder.lineTo(px, py);
      }
    }
    
    if (fillColor != null) builder.fill();
    if (strokeColor != null) builder.stroke();
    
    return builder.build();
  }
  
  /// Draw an arrow
  static List<Map<String, dynamic>> arrow(
    double x1, double y1, double x2, double y2,
    {double headLength = 10, double headWidth = 10, String? color}
  ) {
    final builder = CanvasBuilder();
    
    if (color != null) builder.strokeStyle(color);
    
    // Line
    builder.beginPath()
      .moveTo(x1, y1)
      .lineTo(x2, y2)
      .stroke();
    
    // Arrow head
    final angle = math.atan2(y2 - y1, x2 - x1);
    builder.beginPath()
      .moveTo(x2, y2)
      .lineTo(
        x2 - headLength * math.cos(angle - math.pi / 6),
        y2 - headLength * math.sin(angle - math.pi / 6),
      )
      .moveTo(x2, y2)
      .lineTo(
        x2 - headLength * math.cos(angle + math.pi / 6),
        y2 - headLength * math.sin(angle + math.pi / 6),
      )
      .stroke();
    
    return builder.build();
  }
}
