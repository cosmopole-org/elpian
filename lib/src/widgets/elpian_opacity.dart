import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianOpacity {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    final opacity = node.style?.opacity ?? node.props['opacity'] as double? ?? 1.0;
    
    return Opacity(
      opacity: opacity,
      child: child,
    );
  }
}
