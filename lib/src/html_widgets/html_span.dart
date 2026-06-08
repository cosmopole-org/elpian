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
      // The multi-child branch above already lays content out in a centred
      // [Wrap]; the bare-text branch is a lone child, so let `applyStyle` centre
      // it when the span is a fixed-size flex box (e.g. a `✕` close glyph).
      result = CSSProperties.applyStyle(
        result,
        node.style,
        layoutHandled: children.isNotEmpty,
      );
    }

    return result;
  }
}
