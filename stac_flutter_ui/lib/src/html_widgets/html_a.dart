import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../css/css_properties.dart';
import '../models/css_style.dart';

class HtmlA {
  static Widget build(StacNode node, List<Widget> children) {
    final text = node.props['text'] as String? ?? '';
    final href = node.props['href'] as String? ?? '#';
    
    final defaultStyle = const CSSStyle(
      color: Colors.blue,
      textDecoration: TextDecoration.underline,
    );
    
    final mergedStyle = node.style ?? defaultStyle;
    final textStyle = CSSProperties.createTextStyle(mergedStyle);

    Widget result = GestureDetector(
      onTap: () {
        debugPrint('Link clicked: $href');
      },
      child: Text(text, style: textStyle),
    );

    result = CSSProperties.applyStyle(result, mergedStyle);
  
    return result;
  }
}
