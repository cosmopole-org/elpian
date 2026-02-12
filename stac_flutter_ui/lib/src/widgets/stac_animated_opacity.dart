import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacAnimatedOpacity {
  static Widget build(StacNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    
    return AnimatedOpacity(
      opacity: node.style?.opacity ?? 1.0,
      duration: node.style?.transitionDuration ?? const Duration(milliseconds: 200),
      child: child,
    );
  }
}
