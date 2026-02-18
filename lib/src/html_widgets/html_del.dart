import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../css/css_properties.dart';
import '../models/css_style.dart';

class HtmlDel {
  static Widget build(StacNode node, List<Widget> children) {
    final text = node.props['text'] as String? ?? '';
    
    final defaultStyle = const CSSStyle(
      textDecoration: TextDecoration.lineThrough,
    );
    
    final mergedStyle = node.style ?? defaultStyle;
    Widget result = Text(text, style: CSSProperties.createTextStyle(mergedStyle));
    result = CSSProperties.applyStyle(result, mergedStyle);

    return result;
  }
}
