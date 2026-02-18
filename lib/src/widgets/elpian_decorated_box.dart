import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianDecoratedBox {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    
    return DecoratedBox(
      decoration: BoxDecoration(
        color: node.style?.backgroundColor,
        gradient: node.style?.gradient,
        border: node.style?.border,
        borderRadius: node.style?.borderRadius,
        boxShadow: node.style?.boxShadow,
      ),
      child: child,
    );
  }
}
