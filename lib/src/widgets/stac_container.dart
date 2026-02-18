import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../css/css_properties.dart';

class StacContainer {
  static Widget build(StacNode node, List<Widget> children) {
    Widget? child;
    if (children.isNotEmpty) {
      child = children.length == 1
          ? children.first
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: children,
            );
    }

    Widget result = Container(
      width: node.props['width'] as double?,
      height: node.props['height'] as double?,
      padding: node.props['padding'] as EdgeInsets?,
      margin: node.props['margin'] as EdgeInsets?,
      alignment: node.props['alignment'] as Alignment?,
      decoration: node.props['decoration'] as BoxDecoration?,
      child: child,
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
