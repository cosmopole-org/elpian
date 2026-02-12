import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../css/css_properties.dart';

class StacIcon {
  static Widget build(StacNode node, List<Widget> children) {
    // final iconName = node.props['icon'] as String? ?? 'star';
    final size = node.style?.fontSize ?? 24.0;
    final color = node.style?.color;
    
    Widget result = Icon(
      Icons.star,
      size: size,
      color: color,
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
