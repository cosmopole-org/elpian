import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/elpian_node.dart';
import 'event_system.dart';
import 'event_dispatcher.dart';

/// Wrapper widget that adds event handling capabilities to any widget
class EventEnabledWidget extends StatefulWidget {
  final Widget child;
  final ElpianNode node;
  final String? parentId;
  
  const EventEnabledWidget({
    Key? key,
    required this.child,
    required this.node,
    this.parentId,
  }) : super(key: key);
  
  @override
  State<EventEnabledWidget> createState() => _EventEnabledWidgetState();
}

class _EventEnabledWidgetState extends State<EventEnabledWidget> {
  final EventDispatcher _dispatcher = EventDispatcher();
  late final String _elementId;
  final FocusNode _focusNode = FocusNode();
  
  @override
  void initState() {
    super.initState();
    _elementId = widget.node.key ?? 'element_${widget.node.hashCode}';
    
    // Register node in dispatcher
    _dispatcher.registerNode(_elementId, widget.node, parentId: widget.parentId);
    
    // Setup focus listener
    _focusNode.addListener(_onFocusChange);
  }
  
  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _dispatcher.unregisterNode(_elementId);
    super.dispose();
  }
  
  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _dispatcher.dispatchFocus(_elementId);
    } else {
      _dispatcher.dispatchBlur(_elementId);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    Widget result = widget.child;
    
    // Check if node has any events defined
    if (widget.node.events == null || widget.node.events!.isEmpty) {
      return result;
    }
    
    final events = widget.node.events!;
    
    // Wrap with GestureDetector for tap/click events
    if (_hasAnyEvent(events, [
      'click', 'tap', 'doubletap', 'longpress',
      'tapdown', 'tapup', 'tapcancel',
      'drag', 'dragstart', 'dragend',
      'swipeleft', 'swiperight', 'swipeup', 'swipedown',
    ])) {
      result = GestureDetector(
        onTap: events.containsKey('click') || events.containsKey('tap')
            ? () {
                if (events.containsKey('tap')) {
                  _dispatcher.dispatchEvent(
                    ElpianEvent(
                      type: 'tap',
                      eventType: ElpianEventType.tap,
                      target: _elementId,
                    ),
                    _elementId,
                  );
                }
                if (events.containsKey('click')) {
                  _dispatcher.dispatchClick(_elementId);
                }
              }
            : null,
        onDoubleTap: events.containsKey('doubletap')
            ? () => _dispatcher.dispatchEvent(
                ElpianEvent(
                  type: 'doubletap',
                  eventType: ElpianEventType.doubleClick,
                  target: _elementId,
                ),
                _elementId,
              )
            : null,
        onLongPress: events.containsKey('longpress')
            ? () => _dispatcher.dispatchEvent(
                ElpianEvent(
                  type: 'longpress',
                  eventType: ElpianEventType.longPress,
                  target: _elementId,
                ),
                _elementId,
              )
            : null,
        onTapDown: events.containsKey('tapdown')
            ? (details) => _dispatcher.dispatchEvent(
                ElpianPointerEvent(
                  type: 'tapdown',
                  eventType: ElpianEventType.tapDown,
                  target: _elementId,
                  position: details.globalPosition,
                  localPosition: details.localPosition,
                ),
                _elementId,
              )
            : null,
        onTapUp: events.containsKey('tapup')
            ? (details) => _dispatcher.dispatchEvent(
                ElpianPointerEvent(
                  type: 'tapup',
                  eventType: ElpianEventType.tapUp,
                  target: _elementId,
                  position: details.globalPosition,
                  localPosition: details.localPosition,
                ),
                _elementId,
              )
            : null,
        onTapCancel: events.containsKey('tapcancel')
            ? () => _dispatcher.dispatchEvent(
                ElpianEvent(
                  type: 'tapcancel',
                  eventType: ElpianEventType.tapCancel,
                  target: _elementId,
                ),
                _elementId,
              )
            : null,
        onPanStart: events.containsKey('dragstart')
            ? (details) => _dispatcher.dispatchDragStart(
                _elementId,
                details.globalPosition,
              )
            : null,
        onPanUpdate: events.containsKey('drag')
            ? (details) => _dispatcher.dispatchDrag(
                _elementId,
                details.globalPosition,
                details.delta,
              )
            : null,
        onPanEnd: events.containsKey('dragend')
            ? (details) => _dispatcher.dispatchDragEnd(
                _elementId,
                Offset.zero,
              )
            : null,
        onHorizontalDragEnd: _hasAnyEvent(events, ['swipeleft', 'swiperight'])
            ? (details) {
                if (details.primaryVelocity! < 0) {
                  _dispatcher.dispatchEvent(
                    ElpianGestureEvent(
                      type: 'swipeleft',
                      eventType: ElpianEventType.swipeLeft,
                      target: _elementId,
                      velocity: Offset(details.primaryVelocity!, 0),
                    ),
                    _elementId,
                  );
                } else {
                  _dispatcher.dispatchEvent(
                    ElpianGestureEvent(
                      type: 'swiperight',
                      eventType: ElpianEventType.swipeRight,
                      target: _elementId,
                      velocity: Offset(details.primaryVelocity!, 0),
                    ),
                    _elementId,
                  );
                }
              }
            : null,
        onVerticalDragEnd: _hasAnyEvent(events, ['swipeup', 'swipedown'])
            ? (details) {
                if (details.primaryVelocity! < 0) {
                  _dispatcher.dispatchEvent(
                    ElpianGestureEvent(
                      type: 'swipeup',
                      eventType: ElpianEventType.swipeUp,
                      target: _elementId,
                      velocity: Offset(0, details.primaryVelocity!),
                    ),
                    _elementId,
                  );
                } else {
                  _dispatcher.dispatchEvent(
                    ElpianGestureEvent(
                      type: 'swipedown',
                      eventType: ElpianEventType.swipeDown,
                      target: _elementId,
                      velocity: Offset(0, details.primaryVelocity!),
                    ),
                    _elementId,
                  );
                }
              }
            : null,
        child: result,
      );
    }
    
    // Wrap with Listener for pointer events
    if (_hasAnyEvent(events, [
      'pointerdown', 'pointerup', 'pointermove',
      'pointerenter', 'pointerexit', 'pointerhover',
    ])) {
      result = Listener(
        onPointerDown: events.containsKey('pointerdown')
            ? (details) => _dispatcher.dispatchPointerDown(_elementId, details)
            : null,
        onPointerUp: events.containsKey('pointerup')
            ? (details) => _dispatcher.dispatchPointerUp(_elementId, details)
            : null,
        onPointerMove: events.containsKey('pointermove')
            ? (details) => _dispatcher.dispatchPointerMove(_elementId, details)
            : null,
        child: result,
      );
    }
    
    // Wrap with MouseRegion for hover events
    if (_hasAnyEvent(events, ['pointerenter', 'pointerexit', 'pointerhover'])) {
      result = MouseRegion(
        onEnter: events.containsKey('pointerenter')
            ? (event) => _dispatcher.dispatchEvent(
                ElpianPointerEvent(
                  type: 'pointerenter',
                  eventType: ElpianEventType.pointerEnter,
                  target: _elementId,
                  position: event.position,
                  localPosition: event.localPosition,
                ),
                _elementId,
              )
            : null,
        onExit: events.containsKey('pointerexit')
            ? (event) => _dispatcher.dispatchEvent(
                ElpianPointerEvent(
                  type: 'pointerexit',
                  eventType: ElpianEventType.pointerExit,
                  target: _elementId,
                  position: event.position,
                  localPosition: event.localPosition,
                ),
                _elementId,
              )
            : null,
        onHover: events.containsKey('pointerhover')
            ? (event) => _dispatcher.dispatchEvent(
                ElpianPointerEvent(
                  type: 'pointerhover',
                  eventType: ElpianEventType.pointerHover,
                  target: _elementId,
                  position: event.position,
                  localPosition: event.localPosition,
                ),
                _elementId,
              )
            : null,
        child: result,
      );
    }
    
    // Wrap with Focus for keyboard events
    if (_hasAnyEvent(events, ['focus', 'blur', 'keydown', 'keyup'])) {
      result = Focus(
        focusNode: _focusNode,
        onKeyEvent: _hasAnyEvent(events, ['keydown', 'keyup'])
            ? (node, event) {
                if (event is KeyDownEvent && events.containsKey('keydown')) {
                  _dispatcher.dispatchKeyDown(
                    _elementId,
                    event.logicalKey.keyLabel,
                    event.logicalKey.keyId,
                  );
                  return KeyEventResult.handled;
                }
                if (event is KeyUpEvent && events.containsKey('keyup')) {
                  _dispatcher.dispatchKeyUp(
                    _elementId,
                    event.logicalKey.keyLabel,
                    event.logicalKey.keyId,
                  );
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              }
            : null,
        child: result,
      );
    }
    
    return result;
  }
  
  bool _hasAnyEvent(Map<String, dynamic> events, List<String> eventNames) {
    return eventNames.any((name) => events.containsKey(name));
  }
}

/// Extension to easily wrap widgets with event handling
extension EventExtension on Widget {
  Widget withEvents(ElpianNode node, {String? parentId}) {
    return EventEnabledWidget(
      node: node,
      parentId: parentId,
      child: this,
    );
  }
}
