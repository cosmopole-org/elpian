# Event System Documentation

## Overview

The Elpian UI library includes a comprehensive event handling system inspired by JavaScript DOM events and Flutter's gesture system. It supports event bubbling, capturing, delegation, and provides a unified API for handling all types of user interactions.

## Event Types

### Mouse/Touch Events
- `click` - Single tap/click
- `doubleClick` - Double tap/click
- `longPress` - Long press gesture
- `tap`, `tapDown`, `tapUp`, `tapCancel` - Detailed tap events

### Pointer Events
- `pointerDown`, `pointerUp`, `pointerMove` - Raw pointer events
- `pointerEnter`, `pointerExit` - Mouse enter/exit
- `pointerHover` - Mouse hover
- `pointerCancel` - Pointer cancelled

### Drag Events
- `dragStart`, `drag`, `dragEnd` - Drag gestures
- `dragEnter`, `dragLeave`, `dragOver` - Drag targets
- `drop` - Drop event

### Focus Events
- `focus`, `blur` - Focus gained/lost
- `focusIn`, `focusOut` - Focus with bubbling

### Input Events
- `input` - Input value changed
- `change` - Value committed
- `submit` - Form submitted

### Keyboard Events
- `keyDown`, `keyUp`, `keyPress` - Keyboard input

### Gesture Events
- `swipeLeft`, `swipeRight`, `swipeUp`, `swipeDown` - Swipe gestures
- `pinchStart`, `pinchUpdate`, `pinchEnd` - Pinch gestures
- `scaleStart`, `scaleUpdate`, `scaleEnd` - Scale gestures
- `rotateStart`, `rotateUpdate`, `rotateEnd` - Rotation gestures

### Other Events
- `scroll` - Scroll event
- `resize` - Size changed
- `load`, `unload` - Lifecycle events
- `custom` - Custom events

## Event Phases

Events propagate through three phases:

1. **Capturing Phase** - From root to target
2. **At Target Phase** - At the event target
3. **Bubbling Phase** - From target back to root

## Basic Usage

### Adding Event Handlers in JSON

```json
{
  "type": "Button",
  "key": "my-button",
  "props": {"text": "Click Me"},
  "events": {
    "click": "function",
    "pointerenter": "function",
    "pointerleave": "function"
  }
}
```

### Setting Up Global Event Handler

```dart
final engine = ElpianEngine();

// Receive ALL events that occur in the widget tree
engine.setGlobalEventHandler((event) {
  print('Event: ${event.type}');
  print('Target: ${event.target}');
  print('Current Target: ${event.currentTarget}');
  print('Phase: ${event.phase}');
  
  // Access event-specific data
  if (event is ElpianPointerEvent) {
    print('Position: ${event.position}');
  }
});
```

### Subscribing to Specific Event Types

```dart
// Listen only to click events
engine.onEventType(ElpianEventType.click, (event) {
  print('Click event from: ${event.target}');
});

// Listen only to input events
engine.onEventType(ElpianEventType.input, (event) {
  if (event is ElpianInputEvent) {
    print('Input value: ${event.value}');
  }
});
```

## Event Objects

### Base ElpianEvent

All events inherit from `ElpianEvent`:

```dart
class ElpianEvent {
  final String type;              // Event type name
  final ElpianEventType eventType;  // Event type enum
  final dynamic target;           // Original target
  final dynamic currentTarget;    // Current target in propagation
  final DateTime timestamp;       // When event occurred
  final EventPhase phase;         // Current phase
  final Map<String, dynamic> data; // Additional data
  
  // Control methods
  void stopPropagation();
  void stopImmediatePropagation();
  void preventDefault();
  
  // State properties
  bool get isPropagationStopped;
  bool get isImmediatePropagationStopped;
  bool get isDefaultPrevented;
}
```

### ElpianPointerEvent

For mouse/touch/pointer events:

```dart
class ElpianPointerEvent extends ElpianEvent {
  final Offset position;        // Global position
  final Offset localPosition;   // Local position
  final Offset delta;           // Movement delta
  final int buttons;            // Button state
  final double pressure;        // Touch pressure
  final double distance;        // Hover distance
  final int pointerId;          // Pointer identifier
}
```

### ElpianKeyboardEvent

For keyboard events:

```dart
class ElpianKeyboardEvent extends ElpianEvent {
  final String key;          // Key name
  final int keyCode;         // Key code
  final bool altKey;         // Alt pressed
  final bool ctrlKey;        // Ctrl pressed
  final bool shiftKey;       // Shift pressed
  final bool metaKey;        // Meta/Cmd pressed
}
```

### ElpianInputEvent

For form input events:

```dart
class ElpianInputEvent extends ElpianEvent {
  final dynamic value;       // Input value
  final bool isComposing;    // Composition state
}
```

### ElpianGestureEvent

For complex gestures:

```dart
class ElpianGestureEvent extends ElpianEvent {
  final Offset velocity;     // Gesture velocity
  final double scale;        // Scale factor
  final double rotation;     // Rotation angle
  final Offset focalPoint;   // Focal point
}
```

## Event Propagation

### Event Bubbling

Events bubble up from the target to the root:

```json
{
  "type": "div",
  "key": "grandparent",
  "events": {
    "click": "function"  // Will receive bubbled events
  },
  "children": [
    {
      "type": "div",
      "key": "parent",
      "events": {
        "click": "function"  // Will receive bubbled events
      },
      "children": [
        {
          "type": "button",
          "key": "child",
          "events": {
            "click": "function"  // Event originates here
          }
        }
      ]
    }
  ]
}
```

When the button is clicked, the event:
1. Captures from grandparent → parent → child
2. Fires at child (at target)
3. Bubbles from child → parent → grandparent

### Stopping Propagation

```dart
engine.setGlobalEventHandler((event) {
  // Stop event from bubbling further
  if (event.currentTarget == 'parent') {
    event.stopPropagation();
  }
  
  // Stop other listeners on same element
  if (event.type == 'click') {
    event.stopImmediatePropagation();
  }
  
  // Prevent default action
  if (event.type == 'submit') {
    event.preventDefault();
  }
});
```

## Advanced Features

### Event Delegation

Handle events from child elements at a parent level:

```dart
final delegation = EventDelegation();

// Handle clicks from all buttons
delegation.delegate('click', 'Button', (event) {
  print('Button clicked: ${event.target}');
});

// Handle clicks from elements with specific class
delegation.delegate('click', '.my-class', (event) {
  print('Element with my-class clicked');
});
```

### Event Utilities

#### Debouncing

```dart
final debouncedHandler = EventUtils.debounce(
  (event) => print('Debounced event'),
  const Duration(milliseconds: 300),
);

engine.onEventType(ElpianEventType.input, debouncedHandler);
```

#### Throttling

```dart
final throttledHandler = EventUtils.throttle(
  (event) => print('Throttled event'),
  const Duration(milliseconds: 100),
);

engine.onEventType(ElpianEventType.scroll, throttledHandler);
```

### Event Bus

For global event broadcasting:

```dart
final eventBus = EventBus();

// Subscribe to events
eventBus.subscribe('custom-event', (event) {
  print('Custom event received');
});

// Broadcast events
eventBus.broadcast(ElpianEvent(
  type: 'custom-event',
  eventType: ElpianEventType.custom,
  data: {'message': 'Hello World'},
));
```

## Complete Example

```dart
import 'package:flutter/material.dart';
import 'package:elpian_ui/elpian_ui.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final ElpianEngine engine = ElpianEngine();
  final List<String> eventLog = [];

  @override
  void initState() {
    super.initState();
    
    // Setup global event handler
    engine.setGlobalEventHandler((event) {
      setState(() {
        eventLog.add('${event.type}: ${event.target} [${event.phase}]');
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final json = {
      'type': 'Column',
      'key': 'root',
      'events': {
        'click': (e) => print('Root clicked'),
      },
      'children': [
        {
          'type': 'Button',
          'key': 'btn-1',
          'props': {'text': 'Click Me'},
          'events': {
            'click': (e) => print('Button 1 clicked'),
            'pointerenter': (e) => print('Mouse entered button 1'),
            'pointerleave': (e) => print('Mouse left button 1'),
          },
        },
        {
          'type': 'div',
          'key': 'draggable',
          'events': {
            'dragstart': (e) => print('Drag started'),
            'drag': (e) => print('Dragging...'),
            'dragend': (e) => print('Drag ended'),
          },
          'children': [
            {
              'type': 'Text',
              'props': {'text': 'Drag me!'},
            },
          ],
        },
        {
          'type': 'TextField',
          'key': 'input-1',
          'events': {
            'input': (e) {
              if (e is ElpianInputEvent) {
                print('Input: ${e.value}');
              }
            },
            'change': (e) => print('Value changed'),
            'focus': (e) => print('Focused'),
            'blur': (e) => print('Blurred'),
          },
        },
      ],
    };

    return MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            Expanded(
              child: engine.renderFromJson(json),
            ),
            SizedBox(
              width: 300,
              child: ListView.builder(
                itemCount: eventLog.length,
                itemBuilder: (context, index) {
                  return Text(eventLog[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

## Event Handler Registration

### In JSON DSL

```json
{
  "type": "Button",
  "key": "my-button",
  "events": {
    "click": "handler",
    "longpress": "handler"
  }
}
```

### Programmatically with DOM API

```dart
final dom = ElpianDOM();
final element = dom.getElementById('my-button');

element?.addEventListener('click', (event) {
  print('Button clicked!');
  event.stopPropagation();
});

element?.addEventListener('click', (event) {
  print('Another click handler');
}, capture: true, once: true);
```

## Event Listener Options

```dart
element.addEventListener('click', handler,
  capture: true,    // Listen in capture phase
  once: true,       // Remove after first call
  passive: true,    // Won't call preventDefault
);
```

## Best Practices

1. **Use Event Delegation** - For handling many similar elements
2. **Stop Propagation Wisely** - Only when necessary
3. **Debounce/Throttle** - For high-frequency events (scroll, resize, input)
4. **Clean Up Listeners** - Remove listeners when elements are destroyed
5. **Use Type-Safe Events** - Check event types before accessing properties
6. **Log Selectively** - Use global handler for debugging, not production
7. **Prevent Default Carefully** - Only when you need to override default behavior

## Performance Tips

- Avoid adding too many event listeners
- Use event delegation for repeated elements
- Throttle/debounce high-frequency events
- Remove unused event listeners
- Use passive listeners when possible

## Debugging

```dart
// Log all events
engine.setGlobalEventHandler((event) {
  debugPrint('''
    Event: ${event.type}
    Target: ${event.target}
    Current: ${event.currentTarget}
    Phase: ${event.phase}
    Stopped: ${event.isPropagationStopped}
  ''');
});

// Get event statistics
final stats = engine.eventDispatcher.getStats();
print('Registered nodes: ${stats['nodes']}');
```

## TypeScript/JavaScript Developers

If you're familiar with DOM events in JavaScript, here's a comparison:

| JavaScript | Elpian UI |
|------------|-----------------|
| `addEventListener('click', fn)` | `events: {'click': fn}` or `element.addEventListener('click', fn)` |
| `event.stopPropagation()` | `event.stopPropagation()` |
| `event.preventDefault()` | `event.preventDefault()` |
| `event.target` | `event.target` |
| `event.currentTarget` | `event.currentTarget` |
| `event.bubbles` | `event.bubbles` |
| Event bubbling | ✅ Supported |
| Event capturing | ✅ Supported |
| Event delegation | ✅ Supported via `EventDelegation` |
| Custom events | ✅ Supported via `EventBus` |

The API is designed to feel familiar to web developers while leveraging Flutter's powerful gesture system!
