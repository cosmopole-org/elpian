import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

class HtmlImg {
  static Widget build(ElpianNode node, List<Widget> children) {
    final src = node.props['src'] as String? ?? '';
    final alt = node.props['alt'] as String? ?? '';
    
    Widget result = src.startsWith('http') 
      ? Image.network(src, errorBuilder: (_, __, ___) => Text(alt))
      : Image.asset(src, errorBuilder: (_, __, ___) => Text(alt));

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
