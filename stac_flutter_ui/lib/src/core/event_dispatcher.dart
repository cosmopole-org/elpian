import 'dart:ui';

import 'package:flutter/material.dart';

import 'event_system.dart';
import '../models/stac_node.dart';

/// Event dispatcher that handles event propagation through the widget tree
class EventDispatcher {
  static final EventDispatcher _instance = EventDispatcher._internal();
  factory EventDispatcher() => _instance;
  EventDispatcher._internal();
  
  final Map<String, StacNode> _nodeRegistry = {};
  final Map<String, String?> _parentRegistry = {};
  final EventBus _eventBus = EventBus();
  
  /// Global event callback for all events
  StacEventListener? globalEventHandler;
  
  /// Register a node in the tree
  void registerNode(String id, StacNode node, {String? parentId}) {
    _nodeRegistry[id] = node;
    _parentRegistry[id] = parentId;
  }
  
  /// Unregister a node
  void unregisterNode(String id) {
    _nodeRegistry.remove(id);
    _parentRegistry.remove(id);
  }
  
  /// Get node by ID
  StacNode? getNode(String id) {
    return _nodeRegistry[id];
  }
  
  /// Get parent chain for event bubbling
  List<String> _getParentChain(String elementId) {
    final chain = <String>[];
    String? currentId = elementId;
    
    while (currentId != null) {
      chain.add(currentId);
      currentId = _parentRegistry[currentId];
    }
    
    return chain;
  }
  
  /// Dispatch event with full propagation (capturing -> target -> bubbling)
  void dispatchEvent(StacEvent event, String elementId) {
    // Get the parent chain
    final chain = _getParentChain(elementId);
    
    if (chain.isEmpty) {
      // Call global handler if exists
      globalEventHandler?.call(event);
      return;
    }
    
    // CAPTURING PHASE: from root to target
    for (var i = chain.length - 1; i > 0; i--) {
      final nodeId = chain[i];
      final node = _nodeRegistry[nodeId];
      
      if (node == null) continue;
      
      final capturingEvent = event.copyWith(
        currentTarget: nodeId,
        phase: EventPhase.capturing,
      );
      
      _dispatchToNode(node, capturingEvent);
      
      if (capturingEvent.isPropagationStopped) {
        globalEventHandler?.call(capturingEvent);
        return;
      }
    }
    
    // AT TARGET PHASE
    final targetNode = _nodeRegistry[elementId];
    if (targetNode != null) {
      final targetEvent = event.copyWith(
        currentTarget: elementId,
        phase: EventPhase.atTarget,
      );
      
      _dispatchToNode(targetNode, targetEvent);
      
      if (targetEvent.isPropagationStopped) {
        globalEventHandler?.call(targetEvent);
        return;
      }
      
      // Use targetEvent for bubbling phase
      event = targetEvent;
    }
    
    // BUBBLING PHASE: from target to root
    for (var i = 1; i < chain.length; i++) {
      final nodeId = chain[i];
      final node = _nodeRegistry[nodeId];
      
      if (node == null) continue;
      
      final bubblingEvent = event.copyWith(
        currentTarget: nodeId,
        phase: EventPhase.bubbling,
      );
      
      _dispatchToNode(node, bubblingEvent);
      
      if (bubblingEvent.isPropagationStopped) {
        globalEventHandler?.call(bubblingEvent);
        return;
      }
    }
    
    // Broadcast to event bus
    _eventBus.broadcast(event);
    
    // Call global handler
    globalEventHandler?.call(event);
  }
  
  /// Dispatch event to a specific node
  void _dispatchToNode(StacNode node, StacEvent event) {
    if (node.events == null) return;
    
    final eventHandlers = node.events![event.type];
    if (eventHandlers == null) return;
    
    // If it's a function, call it
    if (eventHandlers is Function) {
      try {
        if (eventHandlers is Function(StacEvent)) {
          eventHandlers(event);
        } else if (eventHandlers is Function()) {
          eventHandlers();
        }
      } catch (e) {
        debugPrint('Error executing event handler: $e');
      }
    }
  }
  
  /// Quick dispatch methods for common events
  void dispatchClick(String elementId, {Offset? position}) {
    final event = position != null
        ? StacPointerEvent(
            type: 'click',
            eventType: StacEventType.click,
            target: elementId,
            position: position,
            localPosition: position,
          )
        : StacEvent(
            type: 'click',
            eventType: StacEventType.click,
            target: elementId,
          );
    
    dispatchEvent(event, elementId);
  }
  
  void dispatchChange(String elementId, dynamic value) {
    final event = StacInputEvent(
      type: 'change',
      eventType: StacEventType.change,
      target: elementId,
      value: value,
    );
    
    dispatchEvent(event, elementId);
  }
  
  void dispatchInput(String elementId, dynamic value) {
    final event = StacInputEvent(
      type: 'input',
      eventType: StacEventType.input,
      target: elementId,
      value: value,
    );
    
    dispatchEvent(event, elementId);
  }
  
  void dispatchSubmit(String elementId) {
    final event = StacEvent(
      type: 'submit',
      eventType: StacEventType.submit,
      target: elementId,
    );
    
    dispatchEvent(event, elementId);
  }
  
  void dispatchFocus(String elementId) {
    final event = StacEvent(
      type: 'focus',
      eventType: StacEventType.focus,
      target: elementId,
    );
    
    dispatchEvent(event, elementId);
  }
  
  void dispatchBlur(String elementId) {
    final event = StacEvent(
      type: 'blur',
      eventType: StacEventType.blur,
      target: elementId,
    );
    
    dispatchEvent(event, elementId);
  }
  
  void dispatchKeyDown(String elementId, String key, int keyCode) {
    final event = StacKeyboardEvent(
      type: 'keydown',
      eventType: StacEventType.keyDown,
      target: elementId,
      key: key,
      keyCode: keyCode,
    );
    
    dispatchEvent(event, elementId);
  }
  
  void dispatchKeyUp(String elementId, String key, int keyCode) {
    final event = StacKeyboardEvent(
      type: 'keyup',
      eventType: StacEventType.keyUp,
      target: elementId,
      key: key,
      keyCode: keyCode,
    );
    
    dispatchEvent(event, elementId);
  }
  
  void dispatchDragStart(String elementId, Offset position) {
    final event = StacPointerEvent(
      type: 'dragstart',
      eventType: StacEventType.dragStart,
      target: elementId,
      position: position,
      localPosition: position,
    );
    
    dispatchEvent(event, elementId);
  }
  
  void dispatchDrag(String elementId, Offset position, Offset delta) {
    final event = StacPointerEvent(
      type: 'drag',
      eventType: StacEventType.drag,
      target: elementId,
      position: position,
      localPosition: position,
      delta: delta,
    );
    
    dispatchEvent(event, elementId);
  }
  
  void dispatchDragEnd(String elementId, Offset position) {
    final event = StacPointerEvent(
      type: 'dragend',
      eventType: StacEventType.dragEnd,
      target: elementId,
      position: position,
      localPosition: position,
    );
    
    dispatchEvent(event, elementId);
  }
  
  void dispatchPointerDown(String elementId, PointerDownEvent details) {
    final event = StacPointerEvent(
      type: 'pointerdown',
      eventType: StacEventType.pointerDown,
      target: elementId,
      position: details.position,
      localPosition: details.localPosition,
      buttons: details.buttons,
      pressure: details.pressure,
      distance: details.distance,
      pointerId: details.pointer,
    );
    
    dispatchEvent(event, elementId);
  }
  
  void dispatchPointerUp(String elementId, PointerUpEvent details) {
    final event = StacPointerEvent(
      type: 'pointerup',
      eventType: StacEventType.pointerUp,
      target: elementId,
      position: details.position,
      localPosition: details.localPosition,
      pointerId: details.pointer,
    );
    
    dispatchEvent(event, elementId);
  }
  
  void dispatchPointerMove(String elementId, PointerMoveEvent details) {
    final event = StacPointerEvent(
      type: 'pointermove',
      eventType: StacEventType.pointerMove,
      target: elementId,
      position: details.position,
      localPosition: details.localPosition,
      delta: details.delta,
      pointerId: details.pointer,
    );
    
    dispatchEvent(event, elementId);
  }
  
  void dispatchGesture(String elementId, StacEventType type, {
    Offset? velocity,
    double? scale,
    double? rotation,
    Offset? focalPoint,
  }) {
    final event = StacGestureEvent(
      type: type.name,
      eventType: type,
      target: elementId,
      velocity: velocity ?? Offset.zero,
      scale: scale ?? 1.0,
      rotation: rotation ?? 0.0,
      focalPoint: focalPoint ?? Offset.zero,
    );
    
    dispatchEvent(event, elementId);
  }
  
  /// Subscribe to global events
  void onGlobalEvent(StacEventListener listener) {
    globalEventHandler = listener;
  }
  
  /// Subscribe to specific event type globally
  void onEventType(StacEventType type, StacEventListener listener) {
    _eventBus.addEventListener(type.name, listener);
  }
  
  /// Clear all registrations
  void clear() {
    _nodeRegistry.clear();
    _parentRegistry.clear();
  }
  
  /// Get statistics
  Map<String, int> getStats() {
    return {
      'nodes': _nodeRegistry.length,
      'parents': _parentRegistry.length,
    };
  }
}

