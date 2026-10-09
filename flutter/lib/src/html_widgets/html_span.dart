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

    // Honour `text-overflow`/`white-space` so a label can truncate with an
    // ellipsis instead of overflowing its (e.g. flex-shrunk) box. `nowrap` pins
    // it to one line — the canonical "ellipsis a title that's too narrow" idiom;
    // these only engage when the author opts in, so default wrapping is intact.
    final overflow = node.style?.textOverflow;
    final maxLines = node.style?.whiteSpace == 'nowrap' ? 1 : null;
    Text textWidget(String value) => Text(
          value,
          style: textStyle,
          overflow: overflow,
          maxLines: maxLines,
          softWrap: maxLines == 1 ? false : null,
        );

    Widget result;
    if (children.isNotEmpty) {
      final widgets = <Widget>[];
      if (text.isNotEmpty) {
        widgets.add(textWidget(text));
      }
      widgets.addAll(children);
      result = Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: widgets,
      );
    } else {
      result = textWidget(text);
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
