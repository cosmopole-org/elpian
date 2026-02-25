import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';
import 'html_embed.dart';

class HtmlObject {
  static Widget build(ElpianNode node, List<Widget> children) {
    final data = node.props['data'] as String? ?? '';

    final normalizedNode = node.copyWith(
      props: {
        ...node.props,
        'src': data,
      },
    );

    Widget result = HtmlEmbed.build(normalizedNode, children);

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
