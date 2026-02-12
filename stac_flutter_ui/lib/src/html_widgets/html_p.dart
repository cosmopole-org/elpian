import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../css/css_properties.dart';
import '../models/css_style.dart';

class HtmlP {
  static Widget build(StacNode node, List<Widget> children) {
    final text = node.props['text'] as String? ?? '';
    
    final defaultStyle = const CSSStyle(
      margin: EdgeInsets.symmetric(vertical: 8.0),
    );
    
    final mergedStyle = node.style ?? defaultStyle;
    final textStyle = CSSProperties.createTextStyle(mergedStyle);

    Widget result = Text(text, style: textStyle);
    result = CSSProperties.applyStyle(result, mergedStyle);

    return result;
  }
}
