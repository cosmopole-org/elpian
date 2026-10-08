import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';
import 'html_embedded_content.dart';

class HtmlIframe {
  static Widget build(ElpianNode node, List<Widget> children) {
    final src = node.props['src'] as String? ?? '';

    Widget result = HtmlEmbeddedContent(url: src, label: 'iframe');

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
