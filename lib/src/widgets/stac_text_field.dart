import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../css/css_properties.dart';

class StacTextField {
  static Widget build(StacNode node, List<Widget> children) {
    final hint = node.props['hint'] as String? ?? '';
    
    Widget result = TextField(
      decoration: InputDecoration(hintText: hint),
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
