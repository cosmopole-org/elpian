import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../css/css_properties.dart';

class HtmlDiv {
  static Widget build(StacNode node, List<Widget> children) {
    if (children.isEmpty) {
      Widget result = const SizedBox.shrink();
      if (node.style != null) {
        result = CSSProperties.applyStyle(result, node.style);
      }
      return result;
    }

    // Determine layout based on display and flexDirection styles
    final display = node.style?.display;
    final flexDirection = node.style?.flexDirection;
    final flexWrap = node.style?.flexWrap;
    final gap = node.style?.gap ?? 0;

    Widget child;

    if (display == 'flex' || display == 'inline-flex') {
      final isRow = flexDirection == null ||
          flexDirection == 'row' ||
          flexDirection == 'row-reverse';
      final isWrap = flexWrap == 'wrap' || flexWrap == 'wrap-reverse';

      if (isWrap) {
        child = Wrap(
          direction: isRow ? Axis.horizontal : Axis.vertical,
          spacing: gap,
          runSpacing: node.style?.rowGap ?? gap,
          alignment: _getWrapAlignment(node.style?.justifyContent),
          crossAxisAlignment: _getWrapCrossAlignment(node.style?.alignItems),
          children: children,
        );
      } else if (isRow) {
        child = Row(
          mainAxisAlignment: CSSProperties.getMainAxisAlignment(
            node.style?.justifyContent,
          ),
          crossAxisAlignment: CSSProperties.getCrossAxisAlignment(
            node.style?.alignItems,
          ),
          mainAxisSize: MainAxisSize.min,
          children: _addGap(children, gap, Axis.horizontal),
        );
      } else {
        child = Column(
          mainAxisAlignment: CSSProperties.getMainAxisAlignment(
            node.style?.justifyContent,
          ),
          crossAxisAlignment: CSSProperties.getCrossAxisAlignment(
            node.style?.alignItems,
          ),
          mainAxisSize: MainAxisSize.min,
          children: _addGap(children, gap, Axis.vertical),
        );
      }
    } else if (children.length == 1) {
      child = children.first;
    } else {
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: _addGap(children, gap, Axis.vertical),
      );
    }

    Widget result = Container(child: child);

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

  static WrapAlignment _getWrapAlignment(String? justifyContent) {
    switch (justifyContent?.toLowerCase()) {
      case 'center':
        return WrapAlignment.center;
      case 'flex-end':
      case 'end':
        return WrapAlignment.end;
      case 'space-between':
        return WrapAlignment.spaceBetween;
      case 'space-around':
        return WrapAlignment.spaceAround;
      case 'space-evenly':
        return WrapAlignment.spaceEvenly;
      default:
        return WrapAlignment.start;
    }
  }

  static WrapCrossAlignment _getWrapCrossAlignment(String? alignItems) {
    switch (alignItems?.toLowerCase()) {
      case 'center':
        return WrapCrossAlignment.center;
      case 'flex-end':
      case 'end':
        return WrapCrossAlignment.end;
      default:
        return WrapCrossAlignment.start;
    }
  }
}
