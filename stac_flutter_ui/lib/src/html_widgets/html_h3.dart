import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../css/css_properties.dart';
import '../models/css_style.dart';

class HtmlH3 {
  static Widget build(StacNode node, List<Widget> children) {
    final text = node.props['text'] as String? ?? '';

    final mergedStyle = CSSStyle(
      fontSize: node.style?.fontSize ?? 24.0,
      fontWeight: node.style?.fontWeight ?? FontWeight.bold,
      margin: node.style?.margin ?? const EdgeInsets.symmetric(vertical: 12.0),
      color: node.style?.color,
      fontFamily: node.style?.fontFamily,
      letterSpacing: node.style?.letterSpacing,
      lineHeight: node.style?.lineHeight,
      textAlign: node.style?.textAlign,
      textDecoration: node.style?.textDecoration,
      backgroundColor: node.style?.backgroundColor,
      padding: node.style?.padding,
      opacity: node.style?.opacity,
    );
    final textStyle = CSSProperties.createTextStyle(mergedStyle);

    Widget result = children.isNotEmpty
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [Text(text, style: textStyle), ...children],
          )
        : Text(text, style: textStyle, textAlign: mergedStyle.textAlign);
    result = CSSProperties.applyStyle(result, mergedStyle);

    return result;
  }
}
