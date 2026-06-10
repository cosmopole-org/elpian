import 'package:flutter/material.dart';
import '../core/resources.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

class HtmlImg {
  static Widget build(ElpianNode node, List<Widget> children) {
    final rawSrc = node.props['src'] as String? ?? '';
    final alt = node.props['alt'] as String? ?? '';

    // Server-driven UIs reference images root-relatively ("/icons/x.png"):
    // resolve against the server origin (ElpianResources.baseUrl / the page
    // origin on web) and load over the network. Only explicit `asset:` srcs
    // target the Flutter asset bundle.
    final src = ElpianResources.resolve(rawSrc);

    // D5: when a display size is known from the style, decode the image at that
    // size instead of full resolution — large source images otherwise decode at
    // their native pixel dimensions, wasting decode CPU and image-cache memory.
    final w = node.style?.width;
    final h = node.style?.height;
    final cacheWidth = (w != null && w > 0) ? w.round() : null;
    final cacheHeight = (h != null && h > 0) ? h.round() : null;

    Widget result = ElpianResources.isNetwork(src)
      ? Image.network(src,
          cacheWidth: cacheWidth,
          cacheHeight: cacheHeight,
          errorBuilder: (_, __, ___) => Text(alt))
      : Image.asset(src.startsWith('asset:') ? src.substring(6) : src,
          cacheWidth: cacheWidth,
          cacheHeight: cacheHeight,
          errorBuilder: (_, __, ___) => Text(alt));

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
