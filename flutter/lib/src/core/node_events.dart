import 'package:flutter/widgets.dart';

import '../models/elpian_node.dart';
import 'elpian_services.dart';
import 'event_dispatcher.dart';
import 'event_system.dart';

/// The element id the engine registers a node under — the same id
/// `EventEnabledWidget` uses, so events dispatched by a builder reach the
/// handlers the node declares.
String elementIdOf(ElpianNode node) => node.key ?? 'element_${node.hashCode}';

/// Dispatches a node's events from inside its own builder.
///
/// Captures the dispatcher of the mini app being rendered **at build time**
/// (see [ElpianServices]), so a callback that fires later still reaches the
/// right app.
class NodeEvents {
  NodeEvents(this.node)
      : dispatcher = ElpianServices.current.events,
        id = elementIdOf(node);

  /// Events of [node] dispatched through [dispatcher] under [id] (for nodes
  /// the engine does not render itself, e.g. image-map areas).
  NodeEvents.forDispatcher(this.node, this.dispatcher, this.id);

  final ElpianNode node;
  final EventDispatcher dispatcher;
  final String id;

  /// Whether the node declares a handler for [type].
  bool has(String type) => node.events?.containsKey(type) ?? false;

  /// Whether the node declares a handler for any of [types].
  bool hasAny(Iterable<String> types) => types.any(has);

  static const Map<String, ElpianEventType> _types = {
    'click': ElpianEventType.click,
    'tap': ElpianEventType.tap,
    'doubletap': ElpianEventType.doubleClick,
    'longpress': ElpianEventType.longPress,
    'tapdown': ElpianEventType.tapDown,
    'tapup': ElpianEventType.tapUp,
    'tapcancel': ElpianEventType.tapCancel,
    'pointerenter': ElpianEventType.pointerEnter,
    'pointerexit': ElpianEventType.pointerExit,
    'pointerhover': ElpianEventType.pointerHover,
    'dragstart': ElpianEventType.dragStart,
    'drag': ElpianEventType.drag,
    'dragend': ElpianEventType.dragEnd,
    'dragenter': ElpianEventType.dragEnter,
    'dragleave': ElpianEventType.dragLeave,
    'dragover': ElpianEventType.dragOver,
    'drop': ElpianEventType.drop,
    'focus': ElpianEventType.focus,
    'blur': ElpianEventType.blur,
    'change': ElpianEventType.change,
    'input': ElpianEventType.input,
    'swipeleft': ElpianEventType.swipeLeft,
    'swiperight': ElpianEventType.swipeRight,
    'swipeup': ElpianEventType.swipeUp,
    'swipedown': ElpianEventType.swipeDown,
    'scalestart': ElpianEventType.scaleStart,
    'scaleupdate': ElpianEventType.scaleUpdate,
    'scaleend': ElpianEventType.scaleEnd,
    'pinchstart': ElpianEventType.pinchStart,
    'pinchupdate': ElpianEventType.pinchUpdate,
    'pinchend': ElpianEventType.pinchEnd,
    'rotatestart': ElpianEventType.rotateStart,
    'rotateupdate': ElpianEventType.rotateUpdate,
    'rotateend': ElpianEventType.rotateEnd,
  };

  /// The [ElpianEventType] for an event name ([ElpianEventType.custom] for
  /// names without one).
  static ElpianEventType typeOf(String type) =>
      _types[type] ?? ElpianEventType.custom;

  /// Dispatch a plain event of [type] carrying [data].
  void emit(String type, {Map<String, dynamic> data = const {}}) {
    dispatcher.dispatchEvent(
      ElpianEvent(type: type, eventType: typeOf(type), target: id, data: data),
      id,
    );
  }

  /// Dispatch a positioned event of [type].
  void pointer(
    String type, {
    required Offset position,
    Offset? localPosition,
    Offset delta = Offset.zero,
    Map<String, dynamic> data = const {},
  }) {
    dispatcher.dispatchEvent(
      ElpianPointerEvent(
        type: type,
        eventType: typeOf(type),
        target: id,
        position: position,
        localPosition: localPosition ?? position,
        delta: delta,
        data: data,
      ),
      id,
    );
  }

  /// Dispatch a gesture event of [type].
  void gesture(
    String type, {
    Offset velocity = Offset.zero,
    double scale = 1.0,
    double rotation = 0.0,
    Offset focalPoint = Offset.zero,
    Map<String, dynamic> data = const {},
  }) {
    dispatcher.dispatchEvent(
      ElpianGestureEvent(
        type: type,
        eventType: typeOf(type),
        target: id,
        velocity: velocity,
        scale: scale,
        rotation: rotation,
        focalPoint: focalPoint,
        data: data,
      ),
      id,
    );
  }

  /// A primary activation: `tap` then `click`, so handlers declared under
  /// either name run (as `HtmlButton` does).
  void activate() {
    if (has('tap')) emit('tap');
    dispatcher.dispatchClick(id);
  }

  /// Report the end of a fling as a swipe in its dominant direction, if it
  /// was fast enough and the node listens for that direction.
  void swipe(Velocity velocity, {double minSpeed = 100}) {
    final v = velocity.pixelsPerSecond;
    if (v.distance < minSpeed) return;
    final String type;
    if (v.dx.abs() >= v.dy.abs()) {
      type = v.dx < 0 ? 'swipeleft' : 'swiperight';
    } else {
      type = v.dy < 0 ? 'swipeup' : 'swipedown';
    }
    if (has(type)) gesture(type, velocity: v);
  }

  static Map<String, dynamic> offsetJson(Offset o) => {'x': o.dx, 'y': o.dy};

  /// A [GestureDetector] that recognises every gesture the node declares an
  /// event for and dispatches it. Only declared gestures are attached, so
  /// e.g. a node without `doubletap` does not delay its taps waiting for a
  /// second one. [alwaysTap] attaches tap even when undeclared (so the tap
  /// still bubbles to ancestors).
  Widget detector(
    Widget child, {
    HitTestBehavior behavior = HitTestBehavior.opaque,
    bool alwaysTap = false,
  }) {
    const scaleEvents = [
      'scalestart',
      'scaleupdate',
      'scaleend',
      'pinchstart',
      'pinchupdate',
      'pinchend',
      'rotatestart',
      'rotateupdate',
      'rotateend',
    ];
    const panEvents = ['dragstart', 'drag', 'dragend'];
    const swipeEvents = ['swipeleft', 'swiperight', 'swipeup', 'swipedown'];
    final usesScale = hasAny(scaleEvents);
    final usesPan = hasAny(panEvents);
    final usesSwipe = hasAny(swipeEvents);
    // Flutter forbids pan and scale recognisers together (scale is a superset
    // of pan), and pan beside horizontal+vertical drags; route accordingly.
    final panViaScale = usesScale && usesPan;
    final swipeViaPan = usesSwipe && (usesPan || usesScale);

    var multiTouch = false;

    return GestureDetector(
      behavior: behavior,
      onTap: alwaysTap || hasAny(['tap', 'click']) ? activate : null,
      onDoubleTap: has('doubletap') ? () => emit('doubletap') : null,
      onLongPress: has('longpress') ? () => emit('longpress') : null,
      onLongPressStart: has('longpressstart')
          ? (d) => pointer('longpressstart',
              position: d.globalPosition, localPosition: d.localPosition)
          : null,
      onLongPressMoveUpdate: has('longpressmove')
          ? (d) => pointer('longpressmove',
              position: d.globalPosition, localPosition: d.localPosition)
          : null,
      onLongPressEnd: has('longpressend')
          ? (d) => pointer('longpressend',
              position: d.globalPosition, localPosition: d.localPosition)
          : null,
      onTapDown: has('tapdown')
          ? (d) => pointer('tapdown',
              position: d.globalPosition, localPosition: d.localPosition)
          : null,
      onTapUp: has('tapup')
          ? (d) => pointer('tapup',
              position: d.globalPosition, localPosition: d.localPosition)
          : null,
      onTapCancel: has('tapcancel') ? () => emit('tapcancel') : null,
      onSecondaryTapUp: hasAny(['secondarytap', 'contextmenu'])
          ? (d) {
              for (final t in ['secondarytap', 'contextmenu']) {
                if (has(t)) {
                  pointer(t,
                      position: d.globalPosition,
                      localPosition: d.localPosition);
                }
              }
            }
          : null,
      onPanStart: usesPan && !usesScale
          ? (d) => pointer('dragstart',
              position: d.globalPosition, localPosition: d.localPosition)
          : null,
      onPanUpdate: usesPan && !usesScale
          ? (d) => pointer('drag',
              position: d.globalPosition,
              localPosition: d.localPosition,
              delta: d.delta)
          : null,
      onPanEnd: usesPan && !usesScale
          ? (d) {
              if (has('dragend')) {
                pointer('dragend',
                    position: d.globalPosition,
                    localPosition: d.localPosition,
                    data: {'velocity': offsetJson(d.velocity.pixelsPerSecond)});
              }
              if (usesSwipe) swipe(d.velocity);
            }
          : null,
      onPanCancel: usesPan && !usesScale && has('dragend')
          ? () => pointer('dragend', position: Offset.zero)
          : null,
      onHorizontalDragEnd: usesSwipe && !swipeViaPan
          ? (d) => swipe(d.velocity, minSpeed: 1)
          : null,
      onVerticalDragEnd: usesSwipe && !swipeViaPan
          ? (d) => swipe(d.velocity, minSpeed: 1)
          : null,
      onScaleStart: usesScale
          ? (d) {
              multiTouch = d.pointerCount > 1;
              if (has('scalestart')) {
                gesture('scalestart', focalPoint: d.focalPoint);
              }
              if (multiTouch && has('pinchstart')) {
                gesture('pinchstart', focalPoint: d.focalPoint);
              }
              if (multiTouch && has('rotatestart')) {
                gesture('rotatestart', focalPoint: d.focalPoint);
              }
              if (panViaScale && has('dragstart')) {
                pointer('dragstart',
                    position: d.focalPoint, localPosition: d.localFocalPoint);
              }
            }
          : null,
      onScaleUpdate: usesScale
          ? (d) {
              if (has('scaleupdate')) {
                gesture('scaleupdate',
                    scale: d.scale,
                    rotation: d.rotation,
                    focalPoint: d.focalPoint);
              }
              if (d.pointerCount > 1) {
                if (!multiTouch) {
                  multiTouch = true;
                  if (has('pinchstart')) {
                    gesture('pinchstart', focalPoint: d.focalPoint);
                  }
                  if (has('rotatestart')) {
                    gesture('rotatestart', focalPoint: d.focalPoint);
                  }
                }
                if (has('pinchupdate')) {
                  gesture('pinchupdate',
                      scale: d.scale, focalPoint: d.focalPoint);
                }
                if (has('rotateupdate')) {
                  gesture('rotateupdate',
                      rotation: d.rotation, focalPoint: d.focalPoint);
                }
              }
              if (panViaScale && has('drag')) {
                pointer('drag',
                    position: d.focalPoint,
                    localPosition: d.localFocalPoint,
                    delta: d.focalPointDelta);
              }
            }
          : null,
      onScaleEnd: usesScale
          ? (d) {
              if (has('scaleend')) {
                gesture('scaleend', velocity: d.velocity.pixelsPerSecond);
              }
              if (multiTouch && has('pinchend')) gesture('pinchend');
              if (multiTouch && has('rotateend')) gesture('rotateend');
              multiTouch = false;
              if (panViaScale && has('dragend')) {
                pointer('dragend',
                    position: Offset.zero,
                    data: {'velocity': offsetJson(d.velocity.pixelsPerSecond)});
              }
              if (usesSwipe && d.pointerCount == 0) swipe(d.velocity);
            }
          : null,
      child: child,
    );
  }
}
