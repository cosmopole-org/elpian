import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Event types supported by the system
enum ElpianEventType {
  // Mouse/Touch Events
  click,
  doubleClick,
  longPress,
  tap,
  tapDown,
  tapUp,
  tapCancel,
  
  // Pointer Events
  pointerDown,
  pointerUp,
  pointerMove,
  pointerEnter,
  pointerExit,
  pointerHover,
  pointerCancel,
  
  // Drag Events
  dragStart,
  drag,
  dragEnd,
  dragEnter,
  dragLeave,
  dragOver,
  drop,
  
  // Focus Events
  focus,
  blur,
  focusIn,
  focusOut,
  
  // Input Events
  input,
  change,
  submit,
  
  // Keyboard Events
  keyDown,
  keyUp,
  keyPress,
  
  // Scroll Events
  scroll,
  
  // Form Events
  reset,
  select,
  
  // UI Events
  resize,
  load,
  unload,
  
  // Touch Events
  touchStart,
  touchMove,
  touchEnd,
  touchCancel,
  
  // Gesture Events
  swipeLeft,
  swipeRight,
  swipeUp,
  swipeDown,
  pinchStart,
  pinchUpdate,
  pinchEnd,
  scaleStart,
  scaleUpdate,
  scaleEnd,
  rotateStart,
  rotateUpdate,
  rotateEnd,
  
  // Custom Events
  custom,
}

/// Event phase for event propagation
enum EventPhase {
  none,
  capturing,
  atTarget,
  bubbling,
}

/// Base event class
class ElpianEvent {
  final String type;
  final ElpianEventType eventType;
  final dynamic target;
  final dynamic currentTarget;
  final DateTime timestamp;
  final EventPhase phase;
  final Map<String, dynamic> data;
  
  bool _propagationStopped = false;
  bool _immediatePropagationStopped = false;
  bool _defaultPrevented = false;
  
  ElpianEvent({
    required this.type,
    required this.eventType,
    this.target,
    this.currentTarget,
    DateTime? timestamp,
    this.phase = EventPhase.none,
    this.data = const {},
  }) : timestamp = timestamp ?? DateTime.now();
  
  /// Stop event from bubbling up the tree
  void stopPropagation() {
    _propagationStopped = true;
  }
  
  /// Stop event from triggering other listeners on the same element
  void stopImmediatePropagation() {
    _immediatePropagationStopped = true;
    _propagationStopped = true;
  }
  
  /// Prevent default action
  void preventDefault() {
    _defaultPrevented = true;
  }
  
  bool get isPropagationStopped => _propagationStopped;
  bool get isImmediatePropagationStopped => _immediatePropagationStopped;
  bool get isDefaultPrevented => _defaultPrevented;
  
  /// Check if event is in bubbling phase
  bool get bubbles => true;
  
  /// Check if event can be cancelled
  bool get cancelable => true;
  
  ElpianEvent copyWith({
    dynamic currentTarget,
    EventPhase? phase,
  }) {
    return ElpianEvent(
      type: type,
      eventType: eventType,
      target: target,
      currentTarget: currentTarget ?? this.currentTarget,
      timestamp: timestamp,
      phase: phase ?? this.phase,
      data: data,
    );
  }
}

/// Mouse/Pointer event with position information
class ElpianPointerEvent extends ElpianEvent {
  final Offset position;
  final Offset localPosition;
  final Offset delta;
  final int buttons;
  final double pressure;
  final double distance;
  final int pointerId;
  
  ElpianPointerEvent({
    required super.type,
    required super.eventType,
    super.target,
    super.currentTarget,
    super.timestamp,
    super.phase,
    super.data,
    required this.position,
    required this.localPosition,
    this.delta = Offset.zero,
    this.buttons = 0,
    this.pressure = 1.0,
    this.distance = 0.0,
    this.pointerId = 0,
  });
  
  @override
  ElpianPointerEvent copyWith({
    dynamic currentTarget,
    EventPhase? phase,
  }) {
    return ElpianPointerEvent(
      type: type,
      eventType: eventType,
      target: target,
      currentTarget: currentTarget ?? this.currentTarget,
      timestamp: timestamp,
      phase: phase ?? this.phase,
      data: data,
      position: position,
      localPosition: localPosition,
      delta: delta,
      buttons: buttons,
      pressure: pressure,
      distance: distance,
      pointerId: pointerId,
    );
  }
}

/// Keyboard event
class ElpianKeyboardEvent extends ElpianEvent {
  final String key;
  final int keyCode;
  final bool altKey;
  final bool ctrlKey;
  final bool shiftKey;
  final bool metaKey;
  
  ElpianKeyboardEvent({
    required super.type,
    required super.eventType,
    super.target,
    super.currentTarget,
    super.timestamp,
    super.phase,
    super.data,
    required this.key,
    required this.keyCode,
    this.altKey = false,
    this.ctrlKey = false,
    this.shiftKey = false,
    this.metaKey = false,
  });
  
  @override
  ElpianKeyboardEvent copyWith({
    dynamic currentTarget,
    EventPhase? phase,
  }) {
    return ElpianKeyboardEvent(
      type: type,
      eventType: eventType,
      target: target,
      currentTarget: currentTarget ?? this.currentTarget,
      timestamp: timestamp,
      phase: phase ?? this.phase,
      data: data,
      key: key,
      keyCode: keyCode,
      altKey: altKey,
      ctrlKey: ctrlKey,
      shiftKey: shiftKey,
      metaKey: metaKey,
    );
  }
}

/// Input event for form controls
class ElpianInputEvent extends ElpianEvent {
  final dynamic value;
  final String? inputType;
  final bool isComposing;
  
  ElpianInputEvent({
    required super.type,
    required super.eventType,
    super.target,
    super.currentTarget,
    super.timestamp,
    super.phase,
    super.data,
    this.value,
    this.inputType,
    this.isComposing = false,
  });
  
  @override
  ElpianInputEvent copyWith({
    dynamic currentTarget,
    EventPhase? phase,
  }) {
    return ElpianInputEvent(
      type: type,
      eventType: eventType,
      target: target,
      currentTarget: currentTarget ?? this.currentTarget,
      timestamp: timestamp,
      phase: phase ?? this.phase,
      data: data,
      value: value,
      inputType: inputType,
      isComposing: isComposing,
    );
  }
}

/// Gesture event for complex gestures
class ElpianGestureEvent extends ElpianEvent {
  final Offset velocity;
  final double scale;
  final double rotation;
  final Offset focalPoint;
  
  ElpianGestureEvent({
    required super.type,
    required super.eventType,
    super.target,
    super.currentTarget,
    super.timestamp,
    super.phase,
    super.data,
    this.velocity = Offset.zero,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.focalPoint = Offset.zero,
  });
  
  @override
  ElpianGestureEvent copyWith({
    dynamic currentTarget,
    EventPhase? phase,
  }) {
    return ElpianGestureEvent(
      type: type,
      eventType: eventType,
      target: target,
      currentTarget: currentTarget ?? this.currentTarget,
      timestamp: timestamp,
      phase: phase ?? this.phase,
      data: data,
      velocity: velocity,
      scale: scale,
      rotation: rotation,
      focalPoint: focalPoint,
    );
  }
}

/// Event listener callback type
typedef ElpianEventListener = void Function(ElpianEvent event);

/// Event listener configuration
class EventListenerConfig {
  final ElpianEventListener listener;
  final bool capture;
  final bool once;
  final bool passive;
  
  const EventListenerConfig({
    required this.listener,
    this.capture = false,
    this.once = false,
    this.passive = false,
  });
}

/// Event target mixin for objects that can dispatch events
mixin ElpianEventTarget {
  final Map<String, List<EventListenerConfig>> _eventListeners = {};
  
  /// Add event listener
  void addEventListener(
    String type, 
    ElpianEventListener listener, {
    bool capture = false,
    bool once = false,
    bool passive = false,
  }) {
    final config = EventListenerConfig(
      listener: listener,
      capture: capture,
      once: once,
      passive: passive,
    );
    
    if (_eventListeners.containsKey(type)) {
      _eventListeners[type]!.add(config);
    } else {
      _eventListeners[type] = [config];
    }
  }
  
  /// Remove event listener
  void removeEventListener(String type, ElpianEventListener listener) {
    if (_eventListeners.containsKey(type)) {
      _eventListeners[type]!.removeWhere((config) => config.listener == listener);
      if (_eventListeners[type]!.isEmpty) {
        _eventListeners.remove(type);
      }
    }
  }
  
  /// Remove all event listeners
  void removeAllEventListeners([String? type]) {
    if (type != null) {
      _eventListeners.remove(type);
    } else {
      _eventListeners.clear();
    }
  }
  
  /// Dispatch event to this target
  bool dispatchEvent(ElpianEvent event) {
    final listeners = _eventListeners[event.type];
    if (listeners == null || listeners.isEmpty) {
      return !event.isDefaultPrevented;
    }
    
    final listenersToRemove = <EventListenerConfig>[];
    
    for (final config in List.from(listeners)) {
      // Check if we should execute this listener based on phase
      if (config.capture && event.phase != EventPhase.capturing) continue;
      if (!config.capture && event.phase == EventPhase.capturing) continue;
      
      // Execute listener
      try {
        config.listener(event);
      } catch (e) {
        debugPrint('Error in event listener: $e');
      }
      
      // Mark for removal if once
      if (config.once) {
        listenersToRemove.add(config);
      }
      
      // Stop if immediate propagation stopped
      if (event.isImmediatePropagationStopped) break;
    }
    
    // Remove once listeners
    for (final config in listenersToRemove) {
      listeners.remove(config);
    }
    
    return !event.isDefaultPrevented;
  }
  
  /// Check if has event listener
  bool hasEventListener(String type) {
    return _eventListeners.containsKey(type) && _eventListeners[type]!.isNotEmpty;
  }
  
  /// Get listener count
  int getListenerCount([String? type]) {
    if (type != null) {
      return _eventListeners[type]?.length ?? 0;
    }
    return _eventListeners.values.fold(0, (sum, list) => sum + list.length);
  }
}

/// Global event bus for broadcasting events
class EventBus with ElpianEventTarget {
  static final EventBus _instance = EventBus._internal();
  factory EventBus() => _instance;
  EventBus._internal();
  
  /// Broadcast event to all subscribers
  void broadcast(ElpianEvent event) {
    dispatchEvent(event);
  }
  
  /// Subscribe to events
  void subscribe(String type, ElpianEventListener listener) {
    addEventListener(type, listener);
  }
  
  /// Unsubscribe from events
  void unsubscribe(String type, ElpianEventListener listener) {
    removeEventListener(type, listener);
  }
}

/// Event delegation manager
class EventDelegation {
  final Map<String, Map<String, List<ElpianEventListener>>> _delegatedListeners = {};
  
  /// Delegate event from child selector to handler
  void delegate(
    String eventType,
    String selector,
    ElpianEventListener handler,
  ) {
    if (!_delegatedListeners.containsKey(eventType)) {
      _delegatedListeners[eventType] = {};
    }
    
    if (!_delegatedListeners[eventType]!.containsKey(selector)) {
      _delegatedListeners[eventType]![selector] = [];
    }
    
    _delegatedListeners[eventType]![selector]!.add(handler);
  }
  
  /// Check if event matches delegated selector
  bool matchesSelector(dynamic target, String selector) {
    // Simplified selector matching
    // In production, this would be more sophisticated
    if (selector.startsWith('#')) {
      return target.id == selector.substring(1);
    } else if (selector.startsWith('.')) {
      return target.classes?.contains(selector.substring(1)) ?? false;
    } else {
      return target.tagName == selector;
    }
  }
  
  /// Handle delegated event
  void handleEvent(ElpianEvent event) {
    final handlers = _delegatedListeners[event.type];
    if (handlers == null) return;
    
    for (final entry in handlers.entries) {
      if (matchesSelector(event.target, entry.key)) {
        for (final handler in entry.value) {
          handler(event);
          if (event.isImmediatePropagationStopped) return;
        }
      }
    }
  }
}

/// Event utilities
class EventUtils {
  /// Create event from Flutter tap details
  static ElpianPointerEvent fromTapDownDetails(
    TapDownDetails details, {
    required String elementId,
    required ElpianEventType eventType,
  }) {
    return ElpianPointerEvent(
      type: eventType.name,
      eventType: eventType,
      target: elementId,
      position: details.globalPosition,
      localPosition: details.localPosition,
    );
  }
  
  /// Create event from Flutter drag details
  static ElpianPointerEvent fromDragUpdateDetails(
    DragUpdateDetails details, {
    required String elementId,
  }) {
    return ElpianPointerEvent(
      type: ElpianEventType.drag.name,
      eventType: ElpianEventType.drag,
      target: elementId,
      position: details.globalPosition,
      localPosition: details.localPosition,
      delta: details.delta,
    );
  }
  
  /// Create event from Flutter scale details
  static ElpianGestureEvent fromScaleUpdateDetails(
    ScaleUpdateDetails details, {
    required String elementId,
  }) {
    return ElpianGestureEvent(
      type: ElpianEventType.scaleUpdate.name,
      eventType: ElpianEventType.scaleUpdate,
      target: elementId,
      scale: details.scale,
      rotation: details.rotation,
      focalPoint: details.focalPoint,
    );
  }
  
  /// Debounce event handler
  static ElpianEventListener debounce(
    ElpianEventListener listener,
    Duration duration,
  ) {
    DateTime? lastCall;
    
    return (event) {
      final now = DateTime.now();
      if (lastCall == null || now.difference(lastCall!) > duration) {
        lastCall = now;
        listener(event);
      }
    };
  }
  
  /// Throttle event handler
  static ElpianEventListener throttle(
    ElpianEventListener listener,
    Duration duration,
  ) {
    bool canCall = true;
    
    return (event) {
      if (canCall) {
        canCall = false;
        listener(event);
        Future.delayed(duration, () => canCall = true);
      }
    };
  }
}
