import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianAnimatedSlide {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : const SizedBox.shrink();
    final offset = node.style?.slideEnd ?? Offset.zero;
    final duration = node.style?.transitionDuration ?? const Duration(milliseconds: 300);
    final curve = node.style?.transitionCurve ?? Curves.linear;

    return AnimatedSlide(
      offset: offset,
      duration: duration,
      curve: curve,
      child: child,
    );
  }
}
