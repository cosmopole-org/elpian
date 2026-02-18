import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../css/css_properties.dart';

class HtmlFigure {
  static Widget build(StacNode node, List<Widget> children) {
    Widget result = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
