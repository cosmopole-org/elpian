import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../css/css_properties.dart';

class StacListView {
  static Widget build(StacNode node, List<Widget> children) {
    Widget result = ListView(
      children: children,
      shrinkWrap: true,
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
