import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../css/css_properties.dart';
import '../models/css_style.dart';

class HtmlCode {
  static Widget build(StacNode node, List<Widget> children) {
    final text = node.props['text'] as String? ?? '';
    
    final defaultStyle = const CSSStyle(
      fontFamily: 'monospace',
      backgroundColor: Color(0xFFF5F5F5),
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    );
    final mergedStyle = node.style ?? defaultStyle;
    
    Widget result = Text(text, style: CSSProperties.createTextStyle(mergedStyle));
    result = CSSProperties.applyStyle(result, mergedStyle);

    return result;
  }
}
