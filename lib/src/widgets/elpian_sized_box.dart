import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianSizedBox {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : null;
    
    return SizedBox(
      width: node.style?.width,
      height: node.style?.height,
      child: child,
    );
  }
}
