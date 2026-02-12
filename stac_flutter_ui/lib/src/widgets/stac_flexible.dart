import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacFlexible {
  static Widget build(StacNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    final flex = node.props['flex'] as int? ?? 1;
    
    return Flexible(
      flex: flex,
      child: child,
    );
  }
}
