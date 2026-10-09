import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

/// `<td>`: a table data cell. `colspan` / `rowspan` / `width` are read by the
/// table; the cell itself fills its whole grid slot, padded (8px unless the
/// style sets padding) and aligned per `text-align` and `vertical-align`
/// (`top`, `middle` — the default —, `bottom`; or the `valign` attribute).
class HtmlTd {
  static Widget build(ElpianNode node, List<Widget> children) =>
      buildCell(node, children, header: false);

  /// Shared by `<td>` and `<th>` (bold, centred by default).
  static Widget buildCell(ElpianNode node, List<Widget> children,
      {required bool header}) {
    final style = node.style;
    final text = node.props['text']?.toString() ?? '';
    final baseText = CSSProperties.createTextStyle(style);
    final textStyle = header
        ? const TextStyle(fontWeight: FontWeight.bold).merge(baseText)
        : baseText;

    Widget content;
    if (children.isEmpty) {
      content = Text(text, style: textStyle, textAlign: style?.textAlign);
    } else {
      final parts = [
        if (text.isNotEmpty) Text(text, style: textStyle),
        ...children,
      ];
      content = parts.length == 1
          ? parts.first
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: parts,
            );
      if (header) {
        content = DefaultTextStyle.merge(
          style: const TextStyle(fontWeight: FontWeight.bold),
          child: content,
        );
      }
    }

    final x = switch (style?.textAlign) {
      TextAlign.center => 0.0,
      TextAlign.right || TextAlign.end => 1.0,
      TextAlign.left || TextAlign.start || TextAlign.justify => -1.0,
      _ => header ? 0.0 : -1.0,
    };
    final valign =
        (style?.verticalAlign ?? node.props['valign'])?.toString() ?? 'middle';
    final y = switch (valign) {
      'top' || 'baseline' || 'text-top' => -1.0,
      'bottom' || 'text-bottom' => 1.0,
      _ => 0.0,
    };

    Widget result = Align(alignment: Alignment(x, y), child: content);
    if (style?.padding == null) {
      result = Padding(padding: const EdgeInsets.all(8.0), child: result);
    }
    if (style != null) {
      result = CSSProperties.applyStyle(result, style);
    }
    return result;
  }
}
