import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

class ElpianRow {
  static Widget build(ElpianNode node, List<Widget> children) {
    final style = node.style;
    final gap = style?.gap ?? 0;
    final flexWrap = style?.flexWrap;
    final wraps = flexWrap == 'wrap' || flexWrap == 'wrap-reverse';

    Widget result;
    if (wraps) {
      // CSS `flex-wrap: wrap` lets items flow onto multiple lines — Flutter's
      // Wrap, not Row, models this. Wrap manages its own spacing, so the gap is
      // applied via spacing/runSpacing rather than inserted SizedBoxes.
      result = Wrap(
        direction: Axis.horizontal,
        spacing: gap,
        runSpacing: gap,
        alignment: _wrapMainAlignment(style?.justifyContent),
        crossAxisAlignment: _wrapCrossAlignment(style?.alignItems),
        verticalDirection: flexWrap == 'wrap-reverse'
            ? VerticalDirection.up
            : VerticalDirection.down,
        children: children,
      );
    } else {
      final cross = CSSProperties.getCrossAxisAlignment(style?.alignItems);
      Row flex(CrossAxisAlignment crossAxisAlignment) => Row(
            mainAxisAlignment:
                CSSProperties.getMainAxisAlignment(style?.justifyContent),
            crossAxisAlignment: crossAxisAlignment,
            mainAxisSize: MainAxisSize.max,
            children: _addGap(children, gap),
          );
      // `stretch` needs a bounded cross axis — Flutter throws on an unbounded
      // one (a row inside a scrolling column). There CSS stretch has
      // nothing to fill, so fall back to start alignment instead.
      result = cross == CrossAxisAlignment.stretch
          ? LayoutBuilder(
              builder: (context, constraints) => flex(
                  constraints.maxHeight.isFinite
                      ? CrossAxisAlignment.stretch
                      : CrossAxisAlignment.start),
            )
          : flex(cross);
    }

    if (style != null) {
      result = CSSProperties.applyStyle(result, style);
    }

    return result;
  }

  static WrapAlignment _wrapMainAlignment(String? justifyContent) {
    switch (justifyContent) {
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
      case 'flex-start':
      case 'start':
      default:
        return WrapAlignment.start;
    }
  }

  static WrapCrossAlignment _wrapCrossAlignment(String? alignItems) {
    switch (alignItems) {
      case 'center':
        return WrapCrossAlignment.center;
      case 'flex-end':
      case 'end':
        return WrapCrossAlignment.end;
      case 'flex-start':
      case 'start':
      default:
        return WrapCrossAlignment.start;
    }
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
