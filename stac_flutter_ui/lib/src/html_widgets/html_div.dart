import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../css/css_properties.dart';

class HtmlDiv {
  static Widget build(StacNode node, List<Widget> children) {
    Widget child = children.isEmpty 
      ? const SizedBox.shrink()
      : (children.length == 1 ? children.first : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: children,
        ));
    
    Widget result = Container(child: child);

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
