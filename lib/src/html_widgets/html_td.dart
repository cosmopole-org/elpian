import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

class HtmlTd {
  static Widget build(ElpianNode node, List<Widget> children) {
    final text = node.props['text'] as String? ?? '';
    final child = children.isNotEmpty ? children.first : Text(text);
    
    Widget result = Container(
      padding: const EdgeInsets.all(8.0),
      child: child,
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
