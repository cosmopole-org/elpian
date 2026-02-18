import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianPositioned {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    
    return Positioned(
      top: node.style?.top,
      right: node.style?.right,
      bottom: node.style?.bottom,
      left: node.style?.left,
      child: child,
    );
  }
}
