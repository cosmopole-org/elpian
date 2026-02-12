import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../css/css_properties.dart';

class StacRow {
  static Widget build(StacNode node, List<Widget> children) {
    Widget result = Row(
      mainAxisAlignment: CSSProperties.getMainAxisAlignment(node.style?.justifyContent),
      crossAxisAlignment: CSSProperties.getCrossAxisAlignment(node.style?.alignItems),
      mainAxisSize: MainAxisSize.min,
      children: children,
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
