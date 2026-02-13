import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../css/css_properties.dart';
import '../models/css_style.dart';

class HtmlEm {
  static Widget build(StacNode node, List<Widget> children) {
    final text = node.props['text'] as String? ?? '';

    // Merge defaults with custom style
    final mergedStyle = CSSStyle(
      fontStyle: node.style?.fontStyle ?? FontStyle.italic,
      color: node.style?.color,
      fontSize: node.style?.fontSize,
      fontWeight: node.style?.fontWeight,
      fontFamily: node.style?.fontFamily,
      letterSpacing: node.style?.letterSpacing,
      backgroundColor: node.style?.backgroundColor,
      padding: node.style?.padding,
      opacity: node.style?.opacity,
    );

    Widget result = Text(text, style: CSSProperties.createTextStyle(mergedStyle));

    result = CSSProperties.applyStyle(result, mergedStyle);

    return result;
  }
}
