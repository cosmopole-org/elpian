import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianExpanded {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    final flex = node.props['flex'] as int? ?? 1;
    
    return Expanded(
      flex: flex,
      child: child,
    );
  }
}
