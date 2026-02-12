import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../css/css_properties.dart';

class HtmlSpan {
  static Widget build(StacNode node, List<Widget> children) {
    final text = node.props['text'] as String? ?? '';
    
    TextStyle? textStyle;
    if (node.style != null) {
      textStyle = CSSProperties.createTextStyle(node.style);
    }

    Widget result = Text(text, style: textStyle);

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
