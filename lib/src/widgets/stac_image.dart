import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../css/css_properties.dart';

class StacImage {
  static Widget build(StacNode node, List<Widget> children) {
    final src = node.props['src'] as String? ?? '';
    final fit = node.props['fit'] as BoxFit? ?? BoxFit.contain;
    
    Widget result = src.startsWith('http') 
      ? Image.network(src, fit: fit)
      : Image.asset(src, fit: fit);

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
