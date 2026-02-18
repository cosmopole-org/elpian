import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../css/css_properties.dart';

class HtmlAbbr {
  static Widget build(StacNode node, List<Widget> children) {
    final text = node.props['text'] as String? ?? '';
    final title = node.props['title'] as String? ?? '';
    
    Widget result = Tooltip(
      message: title,
      child: Text(text, style: const TextStyle(decoration: TextDecoration.underline)),
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
