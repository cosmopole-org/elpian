import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';
import '../models/css_style.dart';

class HtmlSub {
  static Widget build(ElpianNode node, List<Widget> children) {
    final text = node.props['text'] as String? ?? '';
    
    final defaultStyle = const CSSStyle(
      fontSize: 10,
    );
    
    final mergedStyle = node.style ?? defaultStyle;
    Widget result = Text(text, style: CSSProperties.createTextStyle(mergedStyle));

    return result;
  }
}
