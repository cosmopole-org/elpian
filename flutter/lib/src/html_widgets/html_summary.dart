import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

/// `<summary>`: the always-visible, bold label of a `<details>` (which adds
/// the disclosure marker and the toggling). Text and inline children flow
/// together.
class HtmlSummary {
  static Widget build(ElpianNode node, List<Widget> children) {
    final text = node.props['text']?.toString() ?? '';
    final textStyle = const TextStyle(fontWeight: FontWeight.bold)
        .merge(CSSProperties.createTextStyle(node.style));

    Widget result = children.isEmpty
        ? Text(text, style: textStyle)
        : DefaultTextStyle.merge(
            style: const TextStyle(fontWeight: FontWeight.bold),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (text.isNotEmpty) Text(text, style: textStyle),
                ...children,
              ],
            ),
          );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
