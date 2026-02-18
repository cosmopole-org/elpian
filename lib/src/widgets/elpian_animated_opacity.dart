import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianAnimatedOpacity {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    
    return AnimatedOpacity(
      opacity: node.style?.opacity ?? 1.0,
      duration: node.style?.transitionDuration ?? const Duration(milliseconds: 200),
      child: child,
    );
  }
}
