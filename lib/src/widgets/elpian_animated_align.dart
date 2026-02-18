import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianAnimatedAlign {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : null;
    final alignment = node.style?.alignmentEnd ?? node.style?.alignment ?? Alignment.center;
    final duration = node.style?.transitionDuration ?? const Duration(milliseconds: 300);
    final curve = node.style?.transitionCurve ?? Curves.linear;

    return AnimatedAlign(
      alignment: alignment,
      duration: duration,
      curve: curve,
      child: child,
    );
  }
}
