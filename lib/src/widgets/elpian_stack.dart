import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

class ElpianStack {
  static Widget build(ElpianNode node, List<Widget> children) {
    Widget result = Stack(
      alignment: node.style?.alignment as Alignment? ?? Alignment.center,
      children: children,
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
