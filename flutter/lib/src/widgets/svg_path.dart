import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Parse SVG path data (`M`, `L`, `H`, `V`, `C`, `S`, `Q`, `T`, `A`, `Z`, in
/// absolute and relative forms) into a [Path]. Malformed data ends the path at
/// the last complete command rather than throwing.
Path parseSvgPath(String data) {
  final path = Path();
  final tokens = RegExp(
          r'[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?')
      .allMatches(data)
      .map((m) => m[0]!)
      .toList();
  var i = 0;
  var cx = 0.0, cy = 0.0; // current point
  var sx = 0.0, sy = 0.0; // subpath start
  double? lcx, lcy; // last cubic control point (for S)
  double? lqx, lqy; // last quadratic control point (for T)
  String? command;

  bool isCommand(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  bool hasNumber() => i < tokens.length && !isCommand(tokens[i]);
  double next() => double.parse(tokens[i++]);
  // Arc flags may be written without separators ("a1 1 0 011 1"); the
  // tokenizer reads "011" as one number, so split such runs.
  int flag() {
    final t = tokens[i];
    if (t.length > 1 && (t[0] == '0' || t[0] == '1') && !t.contains('.')) {
      tokens[i] = t.substring(1);
      return t[0] == '1' ? 1 : 0;
    }
    i++;
    return double.parse(t) != 0 ? 1 : 0;
  }

  try {
    while (i < tokens.length) {
      if (isCommand(tokens[i])) {
        command = tokens[i++];
      } else if (command == null) {
        break;
      }
      final c = command;
      final rel = c == c.toLowerCase();
      final ox = rel ? cx : 0.0, oy = rel ? cy : 0.0;
      switch (c.toUpperCase()) {
        case 'M':
          cx = ox + next();
          cy = oy + next();
          path.moveTo(cx, cy);
          sx = cx;
          sy = cy;
          // Further pairs are implicit line-tos.
          command = rel ? 'l' : 'L';
          lcx = lcy = lqx = lqy = null;
        case 'L':
          cx = ox + next();
          cy = oy + next();
          path.lineTo(cx, cy);
          lcx = lcy = lqx = lqy = null;
        case 'H':
          cx = ox + next();
          path.lineTo(cx, cy);
          lcx = lcy = lqx = lqy = null;
        case 'V':
          cy = oy + next();
          path.lineTo(cx, cy);
          lcx = lcy = lqx = lqy = null;
        case 'C':
          final x1 = ox + next(), y1 = oy + next();
          final x2 = ox + next(), y2 = oy + next();
          cx = ox + next();
          cy = oy + next();
          path.cubicTo(x1, y1, x2, y2, cx, cy);
          lcx = x2;
          lcy = y2;
          lqx = lqy = null;
        case 'S':
          final x1 = lcx != null ? 2 * cx - lcx : cx;
          final y1 = lcy != null ? 2 * cy - lcy : cy;
          final x2 = ox + next(), y2 = oy + next();
          cx = ox + next();
          cy = oy + next();
          path.cubicTo(x1, y1, x2, y2, cx, cy);
          lcx = x2;
          lcy = y2;
          lqx = lqy = null;
        case 'Q':
          final x1 = ox + next(), y1 = oy + next();
          cx = ox + next();
          cy = oy + next();
          path.quadraticBezierTo(x1, y1, cx, cy);
          lqx = x1;
          lqy = y1;
          lcx = lcy = null;
        case 'T':
          final x1 = lqx != null ? 2 * cx - lqx : cx;
          final y1 = lqy != null ? 2 * cy - lqy : cy;
          cx = ox + next();
          cy = oy + next();
          path.quadraticBezierTo(x1, y1, cx, cy);
          lqx = x1;
          lqy = y1;
          lcx = lcy = null;
        case 'A':
          final rx = next().abs(), ry = next().abs();
          final rotation = next();
          final large = flag();
          final sweep = flag();
          cx = ox + next();
          cy = oy + next();
          path.arcToPoint(
            Offset(cx, cy),
            radius: Radius.elliptical(rx, ry),
            rotation: rotation,
            largeArc: large == 1,
            clockwise: sweep == 1,
          );
          lcx = lcy = lqx = lqy = null;
        case 'Z':
          path.close();
          cx = sx;
          cy = sy;
          lcx = lcy = lqx = lqy = null;
          // Z takes no arguments; a number after it starts an implicit L.
          if (hasNumber()) command = rel ? 'l' : 'L';
          continue;
        default:
          return path;
      }
    }
  } catch (_) {
    // Truncated or malformed data: keep what parsed.
  }
  return path;
}

/// An icon drawn from SVG path data in a 24x24 viewBox, scaled to [size].
class SvgPathIcon extends StatelessWidget {
  const SvgPathIcon(
      {super.key, required this.path, this.size = 24, this.color});

  final String path;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color =
        this.color ?? IconTheme.of(context).color ?? const Color(0xFF000000);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SvgPathPainter(path, color)),
    );
  }
}

class _SvgPathPainter extends CustomPainter {
  _SvgPathPainter(this.data, this.color);

  final String data;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width, size.height) / 24;
    canvas.save();
    canvas.scale(scale);
    canvas.drawPath(parseSvgPath(data), Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SvgPathPainter old) =>
      old.data != data || old.color != color;
}
