import 'package:flutter/material.dart';
import '../core/node_events.dart';
import '../css/css_parser.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

/// `InkWell`: a Material ink response whose gestures are dispatched as the
/// node's events — `tap`/`click` (always, so ancestors see the click
/// bubble), and when declared `doubletap`, `longpress`, `tapdown`, `tapup`,
/// `tapcancel`, `secondarytap`/`contextmenu`, hover (`pointerenter` /
/// `pointerexit` / `hover`) and `focus`/`blur`.
///
/// Ink colours come from `props.splashColor` / `highlightColor` /
/// `hoverColor` / `focusColor`; the ripple is clipped to `style.borderRadius`.
/// `props.disabled: true` turns the ink response off.
class ElpianInkWell {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isEmpty
        ? Container()
        : children.length == 1
            ? children.first
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              );
    final e = NodeEvents(node);
    final hovers = e.hasAny(['pointerenter', 'pointerexit', 'hover']);
    final enabled = node.props['disabled'] != true;

    Widget result = InkWell(
      onTap: enabled ? e.activate : null,
      onDoubleTap:
          enabled && e.has('doubletap') ? () => e.emit('doubletap') : null,
      onLongPress:
          enabled && e.has('longpress') ? () => e.emit('longpress') : null,
      onTapDown: enabled && e.has('tapdown')
          ? (d) => e.pointer('tapdown',
              position: d.globalPosition, localPosition: d.localPosition)
          : null,
      onTapUp: enabled && e.has('tapup')
          ? (d) => e.pointer('tapup',
              position: d.globalPosition, localPosition: d.localPosition)
          : null,
      onTapCancel:
          enabled && e.has('tapcancel') ? () => e.emit('tapcancel') : null,
      onSecondaryTapUp: enabled && e.hasAny(['secondarytap', 'contextmenu'])
          ? (d) {
              for (final t in ['secondarytap', 'contextmenu']) {
                if (e.has(t)) {
                  e.pointer(t,
                      position: d.globalPosition,
                      localPosition: d.localPosition);
                }
              }
            }
          : null,
      onHover: hovers
          ? (hovering) {
              final t = hovering ? 'pointerenter' : 'pointerexit';
              if (e.has(t)) e.emit(t);
              if (e.has('hover')) {
                e.emit('hover', data: {'hovering': hovering});
              }
            }
          : null,
      onFocusChange: e.hasAny(['focus', 'blur'])
          ? (focused) {
              final t = focused ? 'focus' : 'blur';
              if (e.has(t)) e.emit(t);
            }
          : null,
      splashColor: CSSParser.parseColor(node.props['splashColor']),
      highlightColor: CSSParser.parseColor(node.props['highlightColor']),
      hoverColor: CSSParser.parseColor(node.props['hoverColor']),
      focusColor: CSSParser.parseColor(node.props['focusColor']),
      borderRadius: node.style?.borderRadius,
      child: child,
    );

    // Ink paints on the nearest Material; a transparent one here keeps the
    // ripple above any background the style decorates the InkWell with, and
    // lets an InkWell render outside a Material ancestor at all.
    result = Material(type: MaterialType.transparency, child: result);

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
