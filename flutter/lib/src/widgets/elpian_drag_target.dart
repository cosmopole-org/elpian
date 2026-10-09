import 'package:flutter/material.dart';
import '../core/node_events.dart';
import '../css/css_parser.dart';
import '../css/css_properties.dart';
import '../models/css_style.dart';
import '../models/elpian_node.dart';

/// `DragTarget`: receives what a `Draggable` drops on it.
///
/// Props: `accepts` (or `accept`) — a value or list of values the target
/// takes; anything else is rejected (omit to accept everything).
/// `activeStyle` / `rejectStyle` — CSS style maps applied while an
/// acceptable / unacceptable item hovers over the target.
///
/// Events (data carries the dragged `data`): `dragenter` when an acceptable
/// item arrives, `dragover` as it moves (with its position), `dragleave` when
/// it leaves, and `drop` followed by `accept` when it is released on the
/// target. A rejected item reports `dragreject` instead of `dragenter`.
class ElpianDragTarget {
  static Widget build(ElpianNode node, List<Widget> children) {
    final e = NodeEvents(node);
    final child = children.isEmpty
        ? Container()
        : children.length == 1
            ? children.first
            : Column(mainAxisSize: MainAxisSize.min, children: children);
    final accepts = node.props['accepts'] ?? node.props['accept'];
    final activeStyle = _style(node.props['activeStyle']);
    final rejectStyle = _style(node.props['rejectStyle']);

    bool acceptable(Object? data) {
      if (accepts == null) return true;
      final allowed = accepts is List ? accepts : [accepts];
      return allowed.any((a) => a == data || '$a' == '$data');
    }

    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) {
        final ok = acceptable(details.data);
        e.emit(ok ? 'dragenter' : 'dragreject', data: {'data': details.data});
        return ok;
      },
      onMove: e.has('dragover')
          ? (details) {
              if (!acceptable(details.data)) return;
              e.pointer('dragover',
                  position: details.offset, data: {'data': details.data});
            }
          : null,
      onLeave: (data) => e.emit('dragleave', data: {'data': data}),
      onAcceptWithDetails: (details) {
        final payload = {
          'data': details.data,
          'offset': NodeEvents.offsetJson(details.offset),
        };
        e.pointer('drop', position: details.offset, data: payload);
        e.emit('accept', data: payload);
      },
      builder: (context, candidates, rejected) {
        if (candidates.isNotEmpty && activeStyle != null) {
          return CSSProperties.applyStyle(child, activeStyle);
        }
        if (rejected.isNotEmpty && rejectStyle != null) {
          return CSSProperties.applyStyle(child, rejectStyle);
        }
        return child;
      },
    );
  }

  static CSSStyle? _style(Object? raw) =>
      raw is Map ? CSSParser.parse(Map<String, dynamic>.from(raw)) : null;
}
