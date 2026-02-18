import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

class HtmlTextarea {
  static Widget build(ElpianNode node, List<Widget> children) {
    final placeholder = node.props['placeholder'] as String? ?? '';
    
    Widget result = TextField(
      maxLines: 5,
      decoration: InputDecoration(
        hintText: placeholder,
        border: const OutlineInputBorder(),
      ),
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
