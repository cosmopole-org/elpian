import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../css/css_properties.dart';

class HtmlLabel {
  static Widget build(StacNode node, List<Widget> children) {
    final text = node.props['text'] as String? ?? '';
    
    Widget result = Text(text, style: const TextStyle(fontWeight: FontWeight.w500));

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
