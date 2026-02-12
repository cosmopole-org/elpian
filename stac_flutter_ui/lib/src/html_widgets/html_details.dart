import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../css/css_properties.dart';

class HtmlDetails {
  static Widget build(StacNode node, List<Widget> children) {
    Widget result = ExpansionTile(
      title: const Text('Details'),
      children: children,
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
