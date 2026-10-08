import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import 'elpian_scaffold.dart';

/// `AppBar`, with its slots filled from children.
///
/// A child goes into a slot by `props.slot`: `title` (replaces the
/// `props.title` text), `leading`, `actions` / `action` (one action each),
/// `bottom` (e.g. a tab bar; sized from its `style.height`, default 48) and
/// `flexibleSpace`. Unslotted children are actions too.
///
/// Props: `title`, `centerTitle`, `elevation`, `scrolledUnderElevation`,
/// `automaticallyImplyLeading`, `primary`, `titleSpacing`. Style:
/// `backgroundColor`, `color` (foreground), `height` (toolbar height),
/// `fontSize` / `fontWeight` for the title text.
class ElpianAppBar {
  static Widget build(ElpianNode node, List<Widget> children) {
    Widget? title;
    Widget? leading;
    Widget? flexibleSpace;
    PreferredSizeWidget? bottom;
    final actions = <Widget>[];

    for (var i = 0; i < node.children.length && i < children.length; i++) {
      final childNode = node.children[i];
      final widget = children[i];
      switch (childNode.props['slot']) {
        case 'title':
          title = widget;
          break;
        case 'leading':
          leading = widget;
          break;
        case 'flexibleSpace':
          flexibleSpace = widget;
          break;
        case 'bottom':
          bottom = ElpianScaffold.preferredSized(widget, childNode,
              fallbackHeight: kTextTabBarHeight);
          break;
        default:
          actions.add(widget);
      }
    }

    final style = node.style;
    final textTitle = node.props['title']?.toString();
    title ??= textTitle == null
        ? null
        : Text(
            textTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (style?.fontSize != null || style?.fontWeight != null)
                ? TextStyle(
                    fontSize: style?.fontSize, fontWeight: style?.fontWeight)
                : null,
          );

    bool? flag(String key) {
      final v = node.props[key];
      return v is bool ? v : null;
    }

    return AppBar(
      title: title,
      leading: leading,
      actions: actions.isEmpty ? null : actions,
      bottom: bottom,
      flexibleSpace: flexibleSpace,
      centerTitle: flag('centerTitle'),
      automaticallyImplyLeading: flag('automaticallyImplyLeading') ?? true,
      primary: flag('primary') ?? true,
      elevation: (node.props['elevation'] as num?)?.toDouble(),
      scrolledUnderElevation:
          (node.props['scrolledUnderElevation'] as num?)?.toDouble(),
      titleSpacing: (node.props['titleSpacing'] as num?)?.toDouble(),
      toolbarHeight: style?.height,
      backgroundColor: style?.backgroundColor,
      foregroundColor: style?.color,
    );
  }
}
