import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

class ElpianImage {
  static Widget build(ElpianNode node, List<Widget> children) {
    final src = node.props['src'] as String? ?? '';
    final fit = node.props['fit'] as BoxFit? ?? BoxFit.contain;

    // D5: decode at the styled display size when known (see html_img.dart).
    final w = node.style?.width;
    final h = node.style?.height;
    final cacheWidth = (w != null && w > 0) ? w.round() : null;
    final cacheHeight = (h != null && h > 0) ? h.round() : null;

    Widget result = src.startsWith('http')
      ? Image.network(src, fit: fit, cacheWidth: cacheWidth, cacheHeight: cacheHeight)
      : Image.asset(src, fit: fit, cacheWidth: cacheWidth, cacheHeight: cacheHeight);

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
