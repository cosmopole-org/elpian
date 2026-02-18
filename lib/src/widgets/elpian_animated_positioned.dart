import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianAnimatedPositioned {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : const SizedBox.shrink();
    final duration = node.style?.transitionDuration ?? const Duration(milliseconds: 300);
    final curve = node.style?.transitionCurve ?? Curves.linear;

    return AnimatedPositioned(
      top: node.style?.top,
      right: node.style?.right,
      bottom: node.style?.bottom,
      left: node.style?.left,
      width: node.style?.width,
      height: node.style?.height,
      duration: duration,
      curve: curve,
      child: child,
    );
  }
}
