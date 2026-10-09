import 'package:flutter/material.dart';
import '../core/node_events.dart';
import '../models/elpian_node.dart';

/// `Draggable`: drag the child (carrying `props.data`) onto a `DragTarget`.
///
/// Children: the content, plus optional `props.slot` children `feedback`
/// (what follows the pointer; defaults to a translucent copy of the content
/// at its laid-out size) and `childWhenDragging` (left in place while
/// dragging; defaults to the content, faded when `props.fadeWhileDragging`).
///
/// Props: `data` (any JSON value handed to the target), `axis`
/// (`horizontal` / `vertical`), `longPress` (start with a long press),
/// `feedbackOpacity` (default 0.85), `maxSimultaneousDrags`.
///
/// Events (data always carries `data`): `dragstart`; `drag` with the pointer
/// position and delta; `dragend` with `{accepted, velocity, offset}`;
/// `dragcomplete` when a target accepted the drop, `dragcancel` when none did.
class ElpianDraggable {
  static Widget build(ElpianNode node, List<Widget> children) {
    return _ElpianDraggable(
        node: node, events: NodeEvents(node), children: children);
  }
}

class _ElpianDraggable extends StatefulWidget {
  const _ElpianDraggable({
    required this.node,
    required this.children,
    required this.events,
  });

  final ElpianNode node;
  final List<Widget> children;
  final NodeEvents events;

  @override
  State<_ElpianDraggable> createState() => _ElpianDraggableState();
}

class _ElpianDraggableState extends State<_ElpianDraggable> {
  final GlobalKey _contentKey = GlobalKey();

  /// The content's size when the drag began, so the default feedback (laid
  /// out in the overlay, unconstrained) looks like what was picked up.
  final ValueNotifier<Size?> _size = ValueNotifier<Size?>(null);

  @override
  void dispose() {
    _size.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final e = widget.events;
    final data = node.props['data'];

    Widget? feedbackSlot;
    Widget? whileDraggingSlot;
    final content = <Widget>[];
    for (var i = 0;
        i < node.children.length && i < widget.children.length;
        i++) {
      switch (node.children[i].props['slot']) {
        case 'feedback':
          feedbackSlot = widget.children[i];
          break;
        case 'childWhenDragging':
          whileDraggingSlot = widget.children[i];
          break;
        default:
          content.add(widget.children[i]);
      }
    }
    final child = content.isEmpty
        ? Container()
        : content.length == 1
            ? content.first
            : Column(mainAxisSize: MainAxisSize.min, children: content);

    final opacity = (node.props['feedbackOpacity'] as num?)?.toDouble() ?? 0.85;
    final feedback = Material(
      type: MaterialType.transparency,
      child: feedbackSlot ??
          ValueListenableBuilder<Size?>(
            valueListenable: _size,
            builder: (_, size, __) => Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: size == null
                  ? child
                  : SizedBox.fromSize(size: size, child: child),
            ),
          ),
    );
    final childWhenDragging = whileDraggingSlot ??
        (node.props['fadeWhileDragging'] == true
            ? Opacity(opacity: 0.3, child: child)
            : null);

    final axis = switch (node.props['axis']) {
      'horizontal' => Axis.horizontal,
      'vertical' => Axis.vertical,
      _ => null,
    };
    final maxDrags = (node.props['maxSimultaneousDrags'] as num?)?.toInt();
    Map<String, dynamic> payload([Map<String, dynamic> extra = const {}]) =>
        {'data': data, ...extra};

    void onStarted() {
      _size.value = _contentKey.currentContext?.size;
      e.emit('dragstart', data: payload());
    }

    void onUpdate(DragUpdateDetails d) {
      if (!e.has('drag')) return;
      e.pointer('drag',
          position: d.globalPosition,
          localPosition: d.localPosition,
          delta: d.delta,
          data: payload());
    }

    void onEnd(DraggableDetails d) {
      e.emit('dragend',
          data: payload({
            'accepted': d.wasAccepted,
            'velocity': NodeEvents.offsetJson(d.velocity.pixelsPerSecond),
            'offset': NodeEvents.offsetJson(d.offset),
          }));
    }

    void onCompleted() {
      if (e.has('dragcomplete')) e.emit('dragcomplete', data: payload());
    }

    void onCanceled(Velocity v, Offset o) {
      if (e.has('dragcancel')) {
        e.emit('dragcancel',
            data: payload({'offset': NodeEvents.offsetJson(o)}));
      }
    }

    final keyed = KeyedSubtree(key: _contentKey, child: child);
    if (node.props['longPress'] == true) {
      return LongPressDraggable<Object>(
        data: data ?? e.id,
        feedback: feedback,
        childWhenDragging: childWhenDragging,
        axis: axis,
        maxSimultaneousDrags: maxDrags,
        onDragStarted: onStarted,
        onDragUpdate: onUpdate,
        onDragEnd: onEnd,
        onDragCompleted: onCompleted,
        onDraggableCanceled: onCanceled,
        child: keyed,
      );
    }
    return Draggable<Object>(
      data: data ?? e.id,
      feedback: feedback,
      childWhenDragging: childWhenDragging,
      axis: axis,
      maxSimultaneousDrags: maxDrags,
      onDragStarted: onStarted,
      onDragUpdate: onUpdate,
      onDragEnd: onEnd,
      onDragCompleted: onCompleted,
      onDraggableCanceled: onCanceled,
      child: keyed,
    );
  }
}
