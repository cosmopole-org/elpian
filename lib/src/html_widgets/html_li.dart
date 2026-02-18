import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

class HtmlLi {
  static Widget build(ElpianNode node, List<Widget> children) {
    final text = node.props['text'] as String? ?? '';
    final child = children.isNotEmpty ? children.first : Text(text);
    
    final bulletStyle = node.style != null
        ? CSSProperties.createTextStyle(node.style)
        : null;

    Widget result = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('• ', style: bulletStyle),
        Expanded(child: child),
      ],
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
