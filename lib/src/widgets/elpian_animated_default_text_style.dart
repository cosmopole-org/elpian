import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

class ElpianAnimatedDefaultTextStyle {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : const SizedBox.shrink();
    final textStyle = CSSProperties.createTextStyle(node.style) ?? const TextStyle();
    final duration = node.style?.transitionDuration ?? const Duration(milliseconds: 300);
    final curve = node.style?.transitionCurve ?? Curves.linear;

    return AnimatedDefaultTextStyle(
      style: textStyle,
      duration: duration,
      curve: curve,
      child: child,
    );
  }
}
