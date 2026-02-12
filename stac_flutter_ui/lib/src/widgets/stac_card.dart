import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../css/css_properties.dart';

class StacCard {
  static Widget build(StacNode node, List<Widget> children) {
    final child = children.isNotEmpty 
      ? (children.length == 1 ? children.first : Column(children: children))
      : null;
    
    Widget result = Card(
      elevation: node.props['elevation'] as double? ?? 1.0,
      child: child,
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
