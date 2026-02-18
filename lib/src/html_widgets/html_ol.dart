import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../css/css_properties.dart';

class HtmlOl {
  static Widget build(StacNode node, List<Widget> children) {
    Widget result = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children.asMap().entries.map((entry) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${entry.key + 1}. '),
            Expanded(child: entry.value),
          ],
        );
      }).toList(),
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
