import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

class ElpianTextField {
  static Widget build(ElpianNode node, List<Widget> children) {
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
