import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../css/css_properties.dart';
import '../models/css_style.dart';

class HtmlKbd {
  static Widget build(StacNode node, List<Widget> children) {
    final text = node.props['text'] as String? ?? '';
    
    final defaultStyle = const CSSStyle(
      fontFamily: 'monospace',
      backgroundColor: Color(0xFFEEEEEE),
      padding: EdgeInsets.all(4),
      borderRadius: BorderRadius.all(Radius.circular(3)),
    );
    
    final mergedStyle = node.style ?? defaultStyle;
    Widget result = Text(text, style: CSSProperties.createTextStyle(mergedStyle));
    result = CSSProperties.applyStyle(result, mergedStyle);

    return result;
  }
}
