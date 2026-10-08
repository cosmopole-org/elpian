import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

/// `<sub>`: subscript — smaller text (`font-size: smaller`, i.e. 5/6 of the
/// surrounding text unless the style sets a size) shifted below the
/// baseline.
class HtmlSub {
  static Widget build(ElpianNode node, List<Widget> children) =>
      HtmlScript(node: node, superscript: false, children: children);
}

/// Shared `<sub>` / `<sup>` rendering.
///
/// The text keeps its own baseline for layout (so a baseline-aligned row of
/// inline runs stays aligned) and is *painted* shifted — down by ~1/4 em for
/// subscripts, up by ~2/5 em for superscripts — with matching space reserved
/// below / above so the shifted glyphs never overlap neighbouring lines.
class HtmlScript extends StatelessWidget {
  const HtmlScript({
    super.key,
    required this.node,
    required this.children,
    required this.superscript,
  });

  final ElpianNode node;
  final List<Widget> children;
  final bool superscript;

  @override
  Widget build(BuildContext context) {
    final inherited = DefaultTextStyle.of(context).style.fontSize ?? 14;
    final fontSize = node.style?.fontSize ?? inherited * 5 / 6;
    final style =
        (CSSProperties.createTextStyle(node.style) ?? const TextStyle())
            .copyWith(fontSize: fontSize);
    final text = node.props['text']?.toString() ?? '';

    Widget content = children.isEmpty
        ? Text(text, style: style)
        : DefaultTextStyle.merge(
            style: TextStyle(fontSize: fontSize),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                if (text.isNotEmpty) Text(text, style: style),
                ...children,
              ],
            ),
          );

    final shift = superscript ? -fontSize * 0.4 : fontSize * 0.25;
    content = Transform.translate(offset: Offset(0, shift), child: content);
    content = Padding(
      padding: superscript
          ? EdgeInsets.only(top: -shift)
          : EdgeInsets.only(bottom: shift),
      child: content,
    );

    if (node.style != null) {
      content = CSSProperties.applyStyle(content, node.style);
    }
    return content;
  }
}
