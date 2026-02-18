import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianDraggable {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    
    return Draggable(
      data: node.props['data'],
      feedback: child,
      child: child,
    );
  }
}
