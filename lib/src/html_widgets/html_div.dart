import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_parser.dart';
import '../css/css_properties.dart';
import '../models/css_style.dart';

class HtmlDiv {
  static Widget build(ElpianNode node, List<Widget> children) {
    if (children.isEmpty) {
      Widget result = const SizedBox.shrink();
      if (node.style != null) {
        result = CSSProperties.applyStyle(result, node.style);
      }
      return result;
    }

    // CSS positioning: when any direct child is `position: absolute|fixed` it is
    // taken out of flow and overlaid, while the remaining children still lay out
    // normally (the city/world stage floats a navbar + HUD over a full-bleed 3D
    // scene; the auth screen floats decorative blobs behind a centred column).
    // The engine otherwise dropped `position` entirely, so absolute children
    // were laid out in flow — inflating the layout and, for the stage, framing a
    // desktop-sized canvas that showed only empty sky on phones.
    final positioned = _buildPositioned(node, children);
    if (positioned != null) {
      Widget result = Container(child: positioned);
      if (node.style != null) {
        result = CSSProperties.applyStyle(result, node.style);
      }
      return result;
    }

    Widget result = Container(child: _buildFlow(node, children));

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }

  /// Lay [children] out in document flow per the div's `display`/`flexDirection`
  /// (flex row/column/wrap, single child, or a default column).
  static Widget _buildFlow(ElpianNode node, List<Widget> children) {
    final display = node.style?.display;
    final flexDirection = node.style?.flexDirection;
    final flexWrap = node.style?.flexWrap;
    final gap = node.style?.gap ?? 0;

    if (display == 'flex' || display == 'inline-flex') {
      final isRow = flexDirection == null ||
          flexDirection == 'row' ||
          flexDirection == 'row-reverse';
      final isWrap = flexWrap == 'wrap' || flexWrap == 'wrap-reverse';

      if (isWrap) {
        return Wrap(
          direction: isRow ? Axis.horizontal : Axis.vertical,
          spacing: gap,
          runSpacing: node.style?.rowGap ?? gap,
          alignment: _getWrapAlignment(node.style?.justifyContent),
          crossAxisAlignment: _getWrapCrossAlignment(node.style?.alignItems),
          children: children,
        );
      } else if (isRow) {
        return Row(
          mainAxisAlignment: CSSProperties.getMainAxisAlignment(
            node.style?.justifyContent,
          ),
          crossAxisAlignment: CSSProperties.getCrossAxisAlignment(
            node.style?.alignItems,
          ),
          mainAxisSize: MainAxisSize.max,
          children: _addGap(children, gap, Axis.horizontal),
        );
      }
      return Column(
        mainAxisAlignment: CSSProperties.getMainAxisAlignment(
          node.style?.justifyContent,
        ),
        crossAxisAlignment: CSSProperties.getCrossAxisAlignment(
          node.style?.alignItems,
        ),
        mainAxisSize: MainAxisSize.max,
        children: _addGap(children, gap, Axis.vertical),
      );
    } else if (children.length == 1) {
      return children.first;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: _addGap(children, gap, Axis.vertical),
    );
  }

  /// Build a [Stack] when any direct child is `position: absolute|fixed`:
  /// in-flow children keep their flex/flow layout as the stack's base layer, and
  /// the positioned children overlay on top via [Positioned] (CSS semantics).
  /// Returns null when there is nothing positioned, so the caller uses plain
  /// flow layout.
  ///
  /// Child styles are read from their inline `style` map (the common case for
  /// server-driven overlay screens). Positioned children paint in ascending
  /// `zIndex` (stable), so DOM order no longer dictates paint order.
  static Widget? _buildPositioned(ElpianNode node, List<Widget> children) {
    final nodes = node.children;
    if (nodes.length != children.length) return null;

    final styles = <CSSStyle?>[];
    var hasPositioned = false;
    for (final child in nodes) {
      final raw = child.props['style'];
      final style = raw is Map<String, dynamic> ? CSSParser.parse(raw) : child.style;
      styles.add(style);
      final pos = style?.position;
      if (pos == 'absolute' || pos == 'fixed') hasPositioned = true;
    }
    if (!hasPositioned) return null;

    // In-flow (non-positioned) children form the stack's base layer, laid out
    // exactly as they would be without any positioned siblings.
    final flowChildren = <Widget>[];
    final positionedOrder = <int>[];
    for (var i = 0; i < children.length; i++) {
      final pos = styles[i]?.position;
      if (pos == 'absolute' || pos == 'fixed') {
        positionedOrder.add(i);
      } else {
        flowChildren.add(children[i]);
      }
    }
    positionedOrder.sort((a, b) {
      final za = styles[a]?.zIndex ?? 0;
      final zb = styles[b]?.zIndex ?? 0;
      final cmp = za.compareTo(zb);
      return cmp != 0 ? cmp : a.compareTo(b); // stable on ties
    });

    final stackChildren = <Widget>[];
    if (flowChildren.isNotEmpty) {
      stackChildren.add(_buildFlow(node, flowChildren));
    }
    for (final i in positionedOrder) {
      final style = styles[i]!;
      final hasLeftRight = style.left != null && style.right != null;
      final hasTopBottom = style.top != null && style.bottom != null;
      stackChildren.add(Positioned(
        top: style.top,
        left: style.left,
        right: style.right,
        bottom: style.bottom,
        // Positioned forbids over-constraining one axis (left+right+width).
        width: hasLeftRight ? null : style.width,
        height: hasTopBottom ? null : style.height,
        child: children[i],
      ));
    }

    // Loose fit (default): when the div has its own explicit size the tight
    // constraints already force the stack to fill (the full-screen stage);
    // otherwise it sizes to its in-flow base layer (CSS-like).
    return Stack(clipBehavior: Clip.hardEdge, children: stackChildren);
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
