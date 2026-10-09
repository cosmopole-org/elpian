import 'package:flutter/material.dart';

import '../core/widget_registry.dart';
import '../css/css_properties.dart';
import '../models/elpian_node.dart';

/// The HTML sectioning elements — `<article>`, `<aside>`, `<main>`,
/// `<section>`, `<header>`, `<footer>`.
///
/// These differ only in tag name and in whether they stretch to the full width
/// of their parent. They had six near-identical files: article, aside, main and
/// section were byte-for-byte identical apart from the class name, and header
/// and footer differed from them by one `SizedBox` wrapper. The same private
/// `_addGap` helper was copy-pasted into each.
///
/// One builder, registered under six names, is what that always was.
class HtmlSemanticContainer {
  /// A builder for a sectioning element.
  ///
  /// [fullWidth] wraps the result so it stretches across its parent, which is
  /// what `<header>` and `<footer>` want and what the flow elements do not.
  static ElpianWidgetBuilder builder({bool fullWidth = false}) {
    return (node, children) => _build(node, children, fullWidth: fullWidth);
  }

  static Widget _build(
    ElpianNode node,
    List<Widget> children, {
    required bool fullWidth,
  }) {
    if (children.isEmpty) {
      Widget empty = const SizedBox.shrink();
      if (node.style != null) {
        empty =
            CSSProperties.applyStyle(empty, node.style, layoutHandled: true);
      }
      return empty;
    }

    final display = node.style?.display;
    final gap = node.style?.gap ?? 0;
    final isFlex = display == 'flex' || display == 'inline-flex';

    Widget child;
    if (isFlex) {
      final flexDirection = node.style?.flexDirection;
      final isRow = flexDirection == null ||
          flexDirection == 'row' ||
          flexDirection == 'row-reverse';
      final mainAxisAlignment =
          CSSProperties.getMainAxisAlignment(node.style?.justifyContent);
      final crossAxisAlignment =
          CSSProperties.getCrossAxisAlignment(node.style?.alignItems);

      child = isRow
          ? Row(
              mainAxisAlignment: mainAxisAlignment,
              crossAxisAlignment: crossAxisAlignment,
              mainAxisSize: MainAxisSize.max,
              children: withGaps(children, gap, Axis.horizontal),
            )
          : Column(
              mainAxisAlignment: mainAxisAlignment,
              crossAxisAlignment: crossAxisAlignment,
              mainAxisSize: MainAxisSize.max,
              children: withGaps(children, gap, Axis.vertical),
            );
    } else {
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: withGaps(children, gap, Axis.vertical),
      );
    }

    Widget result =
        fullWidth ? SizedBox(width: double.infinity, child: child) : child;

    if (node.style != null) {
      result =
          CSSProperties.applyStyle(result, node.style, layoutHandled: true);
    }
    return result;
  }

  /// Insert `gap` spacers between [children] along [axis].
  ///
  /// Shared rather than private: the same helper was copy-pasted into eight
  /// element files. CSS `gap` on a flex container is spacing *between* items,
  /// so nothing is added before the first or after the last.
  static List<Widget> withGaps(
    List<Widget> children,
    double gap,
    Axis axis,
  ) {
    if (gap <= 0 || children.length <= 1) return children;
    final spaced = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      spaced.add(children[i]);
      if (i < children.length - 1) {
        spaced.add(SizedBox(
          width: axis == Axis.horizontal ? gap : 0,
          height: axis == Axis.vertical ? gap : 0,
        ));
      }
    }
    return spaced;
  }
}
