import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianOverflowBox {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    
    return OverflowBox(
      alignment: node.style?.alignment ?? Alignment.center,
      minWidth: node.style?.minWidth,
      maxWidth: node.style?.maxWidth,
      minHeight: node.style?.minHeight,
      maxHeight: node.style?.maxHeight,
      child: child,
    );
  }
}
