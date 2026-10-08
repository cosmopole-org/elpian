import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

class HtmlTable {
  static Widget build(ElpianNode node, List<Widget> children) {
    Widget result = Table(
      border: TableBorder.all(),
      children: const [],
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
