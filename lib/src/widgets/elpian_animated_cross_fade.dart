import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianAnimatedCrossFade {
  static Widget build(ElpianNode node, List<Widget> children) {
    final showFirst = node.props['showFirst'] as bool? ?? true;
    final duration =
        node.style?.transitionDuration ?? const Duration(milliseconds: 300);
    final curve = node.style?.transitionCurve ?? Curves.linear;

    final firstChild =
        children.isNotEmpty ? children.first : const SizedBox.shrink();
    final secondChild =
        children.length > 1 ? children[1] : const SizedBox.shrink();

    return AnimatedCrossFade(
      firstChild: firstChild,
      secondChild: secondChild,
      crossFadeState:
          showFirst ? CrossFadeState.showFirst : CrossFadeState.showSecond,
      duration: duration,
      firstCurve: curve,
      secondCurve: curve,
      sizeCurve: curve,
    );
  }
}
