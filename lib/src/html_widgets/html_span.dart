import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

class HtmlSpan {
  static Widget build(ElpianNode node, List<Widget> children) {
    final text = node.props['text'] as String? ?? '';

    TextStyle? textStyle;
    if (node.style != null) {
      textStyle = CSSProperties.createTextStyle(node.style);
    }

    Widget result;
    if (children.isNotEmpty) {
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
      result = Text(text, style: textStyle);
    }

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
