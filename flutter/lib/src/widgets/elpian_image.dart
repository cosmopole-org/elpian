import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

class ElpianImage {
  static Widget build(ElpianNode node, List<Widget> children) {
    final src = node.props['src'] as String? ?? '';
    final fit = parseBoxFit(node.props['fit']) ?? BoxFit.contain;
    final alt = node.props['alt'] as String?;

    // D5: decode at the styled display size when known (see html_img.dart).
    final w = node.style?.width;
    final h = node.style?.height;
    final cacheWidth = (w != null && w > 0) ? w.round() : null;
    final cacheHeight = (h != null && h > 0) ? h.round() : null;

    Widget result = src.startsWith('http')
        ? Image.network(src,
            fit: fit,
            semanticLabel: alt,
            cacheWidth: cacheWidth,
            cacheHeight: cacheHeight,
            // A broken URL renders an empty box of the requested size rather
            // than throwing into the frame.
            errorBuilder: (context, error, stack) =>
                SizedBox(width: w, height: h))
        : Image.asset(src,
            fit: fit,
            semanticLabel: alt,
            cacheWidth: cacheWidth,
            cacheHeight: cacheHeight);

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}

/// A `fit` prop: a [BoxFit], or its CSS / A2UI spelling (`contain`, `cover`,
/// `fill`, `none`, `scaleDown` / `scale-down`, `fitWidth`, `fitHeight`).
BoxFit? parseBoxFit(Object? fit) {
  if (fit is BoxFit) return fit;
  if (fit is! String) return null;
  switch (fit.replaceAll('-', '').toLowerCase()) {
    case 'contain':
      return BoxFit.contain;
    case 'cover':
      return BoxFit.cover;
    case 'fill':
      return BoxFit.fill;
    case 'none':
      return BoxFit.none;
    case 'scaledown':
      return BoxFit.scaleDown;
    case 'fitwidth':
      return BoxFit.fitWidth;
    case 'fitheight':
      return BoxFit.fitHeight;
  }
  return null;
}
