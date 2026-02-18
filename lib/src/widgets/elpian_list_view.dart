import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

class ElpianListView {
  static Widget build(ElpianNode node, List<Widget> children) {
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
