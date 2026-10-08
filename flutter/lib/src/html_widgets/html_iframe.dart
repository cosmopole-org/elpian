import 'package:flutter/material.dart';
import '../core/resources.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';
import 'html_embedded_content.dart';

/// `<iframe src | srcdoc>`: an embedded web page. On the web it is a real
/// `<iframe>` element (`allow`, `sandbox`, `referrerpolicy`, `loading`,
/// `allowfullscreen` and `title` are passed through); on Android, iOS and
/// macOS a web view; elsewhere a card that opens the URL. See
/// [HtmlEmbeddedContent].
class HtmlIframe {
  static const passThroughAttributes = [
    'allow',
    'sandbox',
    'referrerpolicy',
    'loading',
    'allowfullscreen',
    'title',
    'name',
  ];

  static Widget build(ElpianNode node, List<Widget> children) {
    final src = node.props['src']?.toString() ?? '';
    final srcdoc = node.props['srcdoc']?.toString();

    Widget result = HtmlEmbeddedContent(
      url: src.isEmpty ? src : ElpianResources.resolve(src),
      html: srcdoc,
      label: 'iframe',
      attributes: {
        for (final a in passThroughAttributes)
          if (node.props[a] != null && node.props[a] != false)
            a: node.props[a] == true ? '' : node.props[a].toString(),
      },
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
