import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

class ElpianListView {
  static Widget build(ElpianNode node, List<Widget> children) {
    final scrollable = node.props['scrollable'];
    final bool isScrollable = scrollable is bool ? scrollable : true;

    // `scrollDirection: horizontal` scrolls a row. A horizontal ListView needs
    // a bounded height, which a list inside a column does not have, so a
    // horizontal list is a scrolling Row sized by its tallest child.
    if (node.props['scrollDirection'] == 'horizontal') {
      Widget row = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: isScrollable ? null : const NeverScrollableScrollPhysics(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );
      if (node.style != null) row = CSSProperties.applyStyle(row, node.style);
      return row;
    }

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
