import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianAnimatedPadding {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : null;
    final padding = node.style?.padding ?? EdgeInsets.zero;
    final duration = node.style?.transitionDuration ?? const Duration(milliseconds: 300);
    final curve = node.style?.transitionCurve ?? Curves.linear;

    return AnimatedPadding(
      padding: padding,
      duration: duration,
      curve: curve,
      child: child,
    );
  }
}
