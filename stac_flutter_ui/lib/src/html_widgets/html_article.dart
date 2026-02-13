import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../css/css_properties.dart';

class HtmlArticle {
  static Widget build(StacNode node, List<Widget> children) {
    if (children.isEmpty) {
      Widget result = const SizedBox.shrink();
      if (node.style != null) {
        result = CSSProperties.applyStyle(result, node.style);
      }
      return result;
    }

    final display = node.style?.display;
    final flexDirection = node.style?.flexDirection;
    final gap = node.style?.gap ?? 0;

    Widget child;

    if (display == 'flex' || display == 'inline-flex') {
      final isRow = flexDirection == null ||
          flexDirection == 'row' ||
          flexDirection == 'row-reverse';
      if (isRow) {
        child = Row(
          mainAxisAlignment: CSSProperties.getMainAxisAlignment(node.style?.justifyContent),
          crossAxisAlignment: CSSProperties.getCrossAxisAlignment(node.style?.alignItems),
          mainAxisSize: MainAxisSize.min,
          children: _addGap(children, gap, Axis.horizontal),
        );
      } else {
        child = Column(
          mainAxisAlignment: CSSProperties.getMainAxisAlignment(node.style?.justifyContent),
          crossAxisAlignment: CSSProperties.getCrossAxisAlignment(node.style?.alignItems),
          mainAxisSize: MainAxisSize.min,
          children: _addGap(children, gap, Axis.vertical),
        );
      }
    } else {
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: _addGap(children, gap, Axis.vertical),
      );
    }

    Widget result = child;

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }

  static List<Widget> _addGap(List<Widget> children, double gap, Axis axis) {
    if (gap <= 0 || children.length <= 1) return children;
    final result = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      result.add(children[i]);
      if (i < children.length - 1) {
        result.add(SizedBox(
          width: axis == Axis.horizontal ? gap : 0,
          height: axis == Axis.vertical ? gap : 0,
        ));
      }
    }
    return result;
  }
}
