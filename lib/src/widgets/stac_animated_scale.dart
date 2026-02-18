import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacAnimatedScale {
  static Widget build(StacNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : const SizedBox.shrink();
    final scale = node.style?.scale ?? 1.0;
    final duration = node.style?.transitionDuration ?? const Duration(milliseconds: 300);
    final curve = node.style?.transitionCurve ?? Curves.linear;

    return AnimatedScale(
      scale: scale,
      duration: duration,
      curve: curve,
      child: child,
    );
  }
}
