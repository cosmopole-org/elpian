import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../css/css_properties.dart';

class HtmlNav {
  static Widget build(StacNode node, List<Widget> children) {
    final gap = node.style?.gap ?? 0;

    Widget result = Row(
      mainAxisAlignment: CSSProperties.getMainAxisAlignment(
        node.style?.justifyContent ?? 'space-around',
      ),
      crossAxisAlignment: CSSProperties.getCrossAxisAlignment(
        node.style?.alignItems,
      ),
      mainAxisSize: MainAxisSize.max,
      children: _addGap(children, gap),
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }

  static List<Widget> _addGap(List<Widget> children, double gap) {
    if (gap <= 0 || children.length <= 1) return children;
    final result = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      result.add(children[i]);
      if (i < children.length - 1) {
        result.add(SizedBox(width: gap));
      }
    }
    return result;
  }
}
