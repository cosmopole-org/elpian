import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacAnimatedRotation {
  static Widget build(StacNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : const SizedBox.shrink();
    final turns = (node.style?.rotate ?? 0.0) / 360.0;
    final duration = node.style?.transitionDuration ?? const Duration(milliseconds: 300);
    final curve = node.style?.transitionCurve ?? Curves.linear;

    return AnimatedRotation(
      turns: turns,
      duration: duration,
      curve: curve,
      child: child,
    );
  }
}
