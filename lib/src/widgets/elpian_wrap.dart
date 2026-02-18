import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

class ElpianWrap {
  static Widget build(ElpianNode node, List<Widget> children) {
    Widget result = Wrap(
      spacing: node.style?.gap ?? 8.0,
      runSpacing: node.style?.rowGap ?? 8.0,
      alignment: WrapAlignment.start,
      children: children,
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
