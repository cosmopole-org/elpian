import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianTweenAnimationBuilder {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : const SizedBox();
    final duration = node.style?.animationDuration ??
        node.style?.transitionDuration ??
        const Duration(milliseconds: 300);
    final curve = node.style?.transitionCurve ?? Curves.linear;
    final begin = node.style?.animationFrom ?? 0.0;
    final end = node.style?.animationTo ?? 1.0;
    final tweenType = node.props['tweenType'] as String? ?? 'opacity';

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: begin, end: end),
      duration: duration,
      curve: curve,
      builder: (context, value, childWidget) {
        switch (tweenType) {
          case 'opacity':
            return Opacity(opacity: value.clamp(0.0, 1.0), child: childWidget);
          case 'scale':
            return Transform.scale(scale: value, child: childWidget);
          case 'rotation':
            return Transform.rotate(angle: value * 3.14159 * 2, child: childWidget);
          case 'translateX':
            return Transform.translate(offset: Offset(value, 0), child: childWidget);
          case 'translateY':
            return Transform.translate(offset: Offset(0, value), child: childWidget);
          default:
            return Opacity(opacity: value.clamp(0.0, 1.0), child: childWidget);
        }
      },
      child: child,
    );
  }
}
