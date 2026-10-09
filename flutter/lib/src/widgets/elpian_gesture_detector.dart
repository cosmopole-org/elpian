import 'package:flutter/material.dart';
import '../core/node_events.dart';
import '../models/elpian_node.dart';

/// `GestureDetector`: recognises every gesture the node declares an event for
/// — tap/click, doubletap, longpress (+ start/move/end), tapdown/up/cancel,
/// secondarytap/contextmenu, dragstart/drag/dragend, swipes, and
/// scale/pinch/rotate — and dispatches them as Elpian events.
///
/// `props.behavior` is the hit-test behaviour (`opaque` — the default —,
/// `translucent` or `deferToChild`).
class ElpianGestureDetector {
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

    final behavior = switch (node.props['behavior']) {
      'translucent' => HitTestBehavior.translucent,
      'deferToChild' => HitTestBehavior.deferToChild,
      _ => HitTestBehavior.opaque,
    };

    return NodeEvents(node).detector(child, behavior: behavior);
  }
}
