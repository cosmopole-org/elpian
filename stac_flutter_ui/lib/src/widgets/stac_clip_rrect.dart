import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacClipRRect {
  static Widget build(StacNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    final borderRadius = node.style?.borderRadius ?? BorderRadius.circular(8.0);
    
    return ClipRRect(
      borderRadius: borderRadius,
      child: child,
    );
  }
}
