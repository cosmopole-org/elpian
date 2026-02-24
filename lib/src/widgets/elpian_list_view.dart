import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

class ElpianListView {
  static Widget build(ElpianNode node, List<Widget> children) {
    final scrollable = node.props['scrollable'];
    final bool isScrollable = scrollable is bool ? scrollable : true;

    Widget result = ListView(
      shrinkWrap: true,
      physics: isScrollable ? null : const NeverScrollableScrollPhysics(),
      primary: isScrollable ? null : false,
      children: children,
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
