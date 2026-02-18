import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianClipRRect {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    final borderRadius = node.style?.borderRadius ?? BorderRadius.circular(8.0);
    
    return ClipRRect(
      borderRadius: borderRadius,
      child: child,
    );
  }
}
