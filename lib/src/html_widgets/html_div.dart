import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_parser.dart';
import '../css/css_properties.dart';
import '../css/stylesheet.dart';
import '../models/css_style.dart';

class HtmlDiv {
  static Widget build(ElpianNode node, List<Widget> children) {
    if (children.isEmpty) {
      Widget result = const SizedBox.shrink();
      if (node.style != null) {
        result = CSSProperties.applyStyle(result, node.style, layoutHandled: true);
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
        result = CSSProperties.applyStyle(result, node.style, layoutHandled: true);
      }
      return result;
    }

    Widget result = Container(child: _buildFlow(node, children));

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style, layoutHandled: true);
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

    if (display == 'grid' || display == 'inline-grid') {
      return _buildGrid(node, children);
    }

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
      return _buildColumn(
        node,
        children,
        gap: gap,
        mainAxisAlignment: CSSProperties.getMainAxisAlignment(
          node.style?.justifyContent,
        ),
        mainAxisSize: MainAxisSize.max,
      );
    } else if (children.length == 1) {
      return children.first;
    }
    return _buildColumn(
      node,
      children,
      gap: gap,
      mainAxisAlignment: MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
    );
  }

  /// Build a column, reproducing CSS's default cross-axis `stretch` for flex
  /// columns (and block-flow stacks) whose `align-items` is **unset**.
  ///
  /// Flutter's [Column] defaults the cross axis to `start`, which shrink-wraps
  /// every child to its content width. In CSS a column's children fill the
  /// cross axis by default, so row-children get the full parent width and their
  /// `justify-content` / `space-between` actually has room to push items apart
  /// (this is finding #4: collapsed space-between rows, badges sitting on text,
  /// flex spacers and progress bars collapsing).
  ///
  /// We can't simply use [CrossAxisAlignment.stretch] because it throws on an
  /// unbounded width **and** clobbers children that set an explicit `width`
  /// (e.g. the auth card). Instead we give each width-less child an infinite
  /// width — but only when:
  ///   * the author left `align-items` unset (so `center`/`start` columns such
  ///     as the auth screen are left exactly as-is), and
  ///   * the laid-out widgets line up 1:1 with the source nodes (so we can read
  ///     each child's declared width), and
  ///   * the column actually has a bounded width (checked at layout time).
  static Widget _buildColumn(
    ElpianNode node,
    List<Widget> children, {
    required double gap,
    required MainAxisAlignment mainAxisAlignment,
    required MainAxisSize mainAxisSize,
  }) {
    final alignItems = node.style?.alignItems;

    final canStretch =
        alignItems == null && node.children.length == children.length;
    if (!canStretch) {
      return Column(
        mainAxisAlignment: mainAxisAlignment,
        crossAxisAlignment: CSSProperties.getCrossAxisAlignment(alignItems),
        mainAxisSize: mainAxisSize,
        children: _addGap(children, gap, Axis.vertical),
      );
    }

    // Children that already declare an explicit width keep it; the rest fill.
    final fill = [
      for (final child in node.children) _childStyle(child)?.width == null,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.maxWidth.isFinite;
        final laidOut = <Widget>[
          for (var i = 0; i < children.length; i++)
            bounded && fill[i]
                ? SizedBox(width: double.infinity, child: children[i])
                : children[i],
        ];
        return Column(
          mainAxisAlignment: mainAxisAlignment,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: mainAxisSize,
          children: _addGap(laidOut, gap, Axis.vertical),
        );
      },
    );
  }

  /// Resolve a child node's **fully cascaded** style — the stylesheet
  /// (tag/class/id + matching `@media`, honouring `!important`) merged with the
  /// node's inline style. Reading only the inline `style` here meant a
  /// positioned child whose geometry comes from a class (e.g. the responsive
  /// `.game-window`: a floating window on desktop, full-screen via the mobile
  /// `@media` override) was laid out from its inline drag offset alone — so
  /// panels never went full-screen on phones. Falls back to the inline map (or
  /// the pre-parsed [ElpianNode.style]) when the node carries no class/id.
  static CSSStyle? _childStyle(ElpianNode child) {
    final className = child.props['className'];
    final inline = child.props['style'];
    final inlineMap = inline is Map<String, dynamic> ? inline : null;
    if (className != null || child.key != null) {
      final classes = className is String
          ? className.split(' ')
          : (className as List?)?.cast<String>();
      final computed = GlobalStylesheetManager().getComputedStyleMap(
        tagName: child.type,
        id: child.key,
        classes: classes,
        inlineStyles: inlineMap,
      );
      if (computed.isNotEmpty) return CSSParser.parse(computed);
    }
    if (inlineMap != null) return CSSParser.parse(inlineMap);
    return child.style;
  }

  /// Lay out a `display:grid` container (finding #6). The engine has no real
  /// CSS-grid solver, so DOM-order children were dropping into a vertical
  /// stack. We support the two `grid-template-columns` shapes the builders
  /// actually emit and map them to a responsive [Wrap]:
  ///   * `repeat(auto-fill|auto-fit, minmax(<min>px, 1fr))` — pack as many
  ///     equal columns of at least `<min>` as fit the available width, then
  ///     stretch them to fill it (the `tileGrid` shape).
  ///   * `repeat(<n>, 1fr)` / an explicit `1fr 1fr …` track list — a fixed
  ///     column count.
  /// Anything else falls back to an intrinsic-width [Wrap] (still better than a
  /// forced single column). Column/row gaps come from `grid-gap`/`gap`.
  static Widget _buildGrid(ElpianNode node, List<Widget> children) {
    final style = node.style;
    final baseGap = style?.gridGap ?? style?.gap ?? 0;
    final colGap = style?.gridColumnGap ?? baseGap;
    final rowGap = style?.gridRowGap ?? baseGap;
    final spec = _parseGridColumns(style?.gridTemplateColumns);

    if (spec == null) {
      return Wrap(spacing: colGap, runSpacing: rowGap, children: children);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        if (!maxW.isFinite) {
          // No width to divide — fall back to natural wrapping.
          return Wrap(spacing: colGap, runSpacing: rowGap, children: children);
        }

        int cols;
        if (spec.fixedCount != null) {
          cols = spec.fixedCount!;
        } else {
          final min = spec.minItemWidth ?? maxW;
          cols = ((maxW + colGap) / (min + colGap)).floor();
        }
        if (cols < 1) cols = 1;
        if (cols > children.length && children.isNotEmpty) {
          cols = children.length;
        }

        final itemWidth = (maxW - colGap * (cols - 1)) / cols;
        return Wrap(
          spacing: colGap,
          runSpacing: rowGap,
          children: [
            for (final child in children)
              SizedBox(
                width: itemWidth > 0 ? itemWidth : 0,
                child: child,
              ),
          ],
        );
      },
    );
  }

  /// Parse the subset of `grid-template-columns` syntax the builders use into
  /// either a fixed column count or a minimum item width. Returns null when the
  /// value is absent or unrecognised.
  static _GridColumnSpec? _parseGridColumns(String? template) {
    if (template == null) return null;
    final value = template.trim().toLowerCase();
    if (value.isEmpty) return null;

    // repeat(auto-fill|auto-fit, minmax(<min>px, 1fr))
    final autoMin = RegExp(
      r'repeat\(\s*auto-(?:fill|fit)\s*,\s*minmax\(\s*([\d.]+)px\s*,',
    ).firstMatch(value);
    if (autoMin != null) {
      final min = double.tryParse(autoMin.group(1)!);
      if (min != null) return _GridColumnSpec(minItemWidth: min);
    }

    // repeat(<n>, …)
    final repeatN = RegExp(r'repeat\(\s*(\d+)\s*,').firstMatch(value);
    if (repeatN != null) {
      final n = int.tryParse(repeatN.group(1)!);
      if (n != null && n > 0) return _GridColumnSpec(fixedCount: n);
    }

    // An explicit track list ("1fr 1fr 1fr", "120px 1fr", …): count the tracks.
    if (!value.contains('repeat') && !value.contains('minmax')) {
      final tracks =
          value.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).length;
      if (tracks > 0) return _GridColumnSpec(fixedCount: tracks);
    }

    return null;
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
      final style = _childStyle(child);
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
      // The in-flow base layer behaves like block content of a positioned
      // container: it fills the available WIDTH (so `justify/alignItems:center`
      // actually centres, and full-width children stretch) while still sizing
      // its HEIGHT to content (which is what gives a loose Stack its size). Wrap
      // it to the incoming max width when that's bounded; otherwise leave it to
      // shrink-wrap (an unbounded stack has no width to fill).
      final base = _buildFlow(node, flowChildren);
      stackChildren.add(
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth.isFinite
              ? SizedBox(width: constraints.maxWidth, child: base)
              : base,
        ),
      );
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

/// Resolved column intent for [HtmlDiv._buildGrid]: either a fixed number of
/// columns or a minimum per-item width for responsive packing.
class _GridColumnSpec {
  const _GridColumnSpec({this.fixedCount, this.minItemWidth});
  final int? fixedCount;
  final double? minItemWidth;
}
