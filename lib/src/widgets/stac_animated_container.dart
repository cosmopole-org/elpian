import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacAnimatedContainer {
  static Widget build(StacNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : null;
    
    return AnimatedContainer(
      duration: node.style?.transitionDuration ?? const Duration(milliseconds: 200),
      curve: node.style?.transitionCurve ?? Curves.linear,
      width: node.style?.width,
      height: node.style?.height,
      padding: node.style?.padding,
      margin: node.style?.margin,
      decoration: BoxDecoration(
        color: node.style?.backgroundColor,
        borderRadius: node.style?.borderRadius,
      ),
      child: child,
    );
  }
}
