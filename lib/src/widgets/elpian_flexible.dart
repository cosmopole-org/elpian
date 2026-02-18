import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianFlexible {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    final flex = node.props['flex'] as int? ?? 1;
    
    return Flexible(
      flex: flex,
      child: child,
    );
  }
}
