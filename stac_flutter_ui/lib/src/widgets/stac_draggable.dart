import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacDraggable {
  static Widget build(StacNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    
    return Draggable(
      data: node.props['data'],
      feedback: child,
      child: child,
    );
  }
}
