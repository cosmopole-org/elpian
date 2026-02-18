import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

class HtmlCanvas {
  static Widget build(ElpianNode node, List<Widget> children) {
    Widget result = Container(
      color: Colors.white,
      child: CustomPaint(
        painter: _CanvasPainter(),
      ),
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}

class _CanvasPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Custom painting logic here
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
