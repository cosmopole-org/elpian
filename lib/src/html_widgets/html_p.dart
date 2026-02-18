import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';
import '../models/css_style.dart';

class HtmlP {
  static Widget build(ElpianNode node, List<Widget> children) {
    final text = node.props['text'] as String? ?? '';

    final mergedStyle = CSSStyle(
      margin: node.style?.margin ?? const EdgeInsets.symmetric(vertical: 8.0),
      color: node.style?.color,
      fontSize: node.style?.fontSize,
      fontWeight: node.style?.fontWeight,
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

    Widget result;
    if (children.isNotEmpty) {
      // Support inline children (span, strong, em, a inside p)
      final widgets = <Widget>[];
      if (text.isNotEmpty) {
        widgets.add(Text(text, style: textStyle));
      }
      widgets.addAll(children);
      result = Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: widgets,
      );
    } else {
      result = Text(text, style: textStyle, textAlign: mergedStyle.textAlign);
    }
    result = CSSProperties.applyStyle(result, mergedStyle);

    return result;
  }
}
