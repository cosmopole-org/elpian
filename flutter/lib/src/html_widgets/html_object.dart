import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';
import 'html_embed.dart';

/// `<object data type>`: embedded content, typed like `<embed>` (image,
/// video, audio, else a web view). Its `<param name value>` children are
/// passed to non-image content as query parameters of `data`. Without
/// `data`, its other children are the fallback content and are shown
/// instead.
class HtmlObject {
  static Widget build(ElpianNode node, List<Widget> children) {
    final data = node.props['data']?.toString() ?? '';

    if (data.isEmpty) {
      final fallback = [
        for (var i = 0; i < node.children.length && i < children.length; i++)
          if (node.children[i].type != 'param') children[i],
      ];
      if (fallback.isNotEmpty) {
        Widget result = fallback.length == 1
            ? fallback.first
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: fallback,
              );
        if (node.style != null) {
          result = CSSProperties.applyStyle(result, node.style);
        }
        return result;
      }
    }

    final normalizedNode = node.copyWith(
      props: {
        ...node.props,
        'src': withParams(node, data),
      },
    );

    // HtmlEmbed applies the node's style.
    return HtmlEmbed.build(normalizedNode, children);
  }

  /// [data] with the object's `<param>`s appended as query parameters
  /// (images take none).
  static String withParams(ElpianNode node, String data) {
    final params = node.children
        .where((c) =>
            c.type == 'param' && (c.props['name']?.toString() ?? '').isNotEmpty)
        .toList();
    final type = (node.props['type'] ?? '').toString().toLowerCase();
    if (params.isEmpty ||
        data.isEmpty ||
        HtmlEmbed.looksLikeImage(type, data)) {
      return data;
    }
    final query = params
        .map((p) => '${Uri.encodeQueryComponent(p.props['name'].toString())}='
            '${Uri.encodeQueryComponent(p.props['value']?.toString() ?? '')}')
        .join('&');
    return data + (data.contains('?') ? '&' : '?') + query;
  }
}
