# Elpian UI

A high-performance Flutter UI engine that renders HTML, CSS, Flutter DSL, and 3D scene graphs from JSON and markup formats into native Flutter 2D/3D widgets.

## Features

### Rendering Engines
- **Flutter DSL** - 60+ Flutter widgets rendered from JSON definitions
- **HTML Rendering** - 70+ HTML5 elements with semantic tag support
- **CSS Engine** - 150+ CSS properties including flexbox, grid, transforms, animations, and filters
- **Canvas 2D** - Full 2D graphics API with 50+ drawing commands
- **3D Scene Graphs** - Define 3D scenes in JSON, rendered via Bevy (Rust/GPU) or pure-Dart canvas
- **Elpian VM** - Sandboxed Rust VM with FFI/WASM for scripting UI logic

### Core Capabilities
- **JSON Stylesheet Parser** - Define CSS stylesheets in JSON with media queries, variables, and keyframe animations
- **DOM API** - Full DOM manipulation API (getElementById, querySelector, appendChild, etc.)
- **Event System** - 40+ event types with bubbling, capturing, delegation, and custom events
- **Extensible Architecture** - Register custom widgets and host handlers

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  elpian_ui:
    path: ./path/to/elpian_ui
```

## Example App

This repository now includes a full cross-platform example app in `example/`.

```bash
cd example
flutter run
```

## Web Setup (for host apps)

If you use VM/QuickJS features on web, include these scripts in your app's `web/index.html`:

```html
<script type="module" src="assets/packages/elpian_ui/assets/web_runtime/elpian_wasm_loader.js"></script>
<script type="module" src="assets/packages/elpian_ui/assets/web_runtime/quickjs_web_runtime.js"></script>
```

## Quick Start

```dart
import 'package:elpian_ui/elpian_ui.dart';

final engine = ElpianEngine();

final widget = engine.renderFromJson({
  'type': 'div',
  'style': {
    'padding': '20',
    'backgroundColor': '#2196F3',
    'borderRadius': 12,
    'boxShadow': [{
      'color': 'rgba(0,0,0,0.2)',
      'offset': {'x': 0, 'y': 4},
      'blur': 8
    }]
  },
  'children': [
    {
      'type': 'h1',
      'props': {'text': 'Hello World'},
      'style': {
        'color': 'white',
        'fontSize': 32,
        'fontWeight': 'bold'
      }
    }
  ]
});
```

### JSON Stylesheet

```dart
final engine = ElpianEngine();

engine.loadStylesheet({
  'rules': [
    {
      'selector': '.card',
      'styles': {
        'backgroundColor': '#FFFFFF',
        'padding': '20',
        'borderRadius': 12,
        'boxShadow': [
          {
            'color': 'rgba(0,0,0,0.1)',
            'offset': {'x': 0, 'y': 2},
            'blur': 8,
          }
        ],
      }
    },
    {
      'selector': '.btn-primary',
      'styles': {
        'backgroundColor': '#2196F3',
        'color': '#FFFFFF',
        'padding': '12 24',
      }
    }
  ],
  'mediaQueries': [
    {
      'query': 'min-width: 768',
      'rules': [
        {
          'selector': '.card',
          'styles': {'padding': '40'}
        }
      ]
    }
  ]
});

final ui = engine.renderFromJson({
  'type': 'div',
  'props': {'className': 'card'},
  'children': [
    {
      'type': 'Button',
      'props': {'text': 'Click Me', 'className': 'btn-primary'}
    }
  ]
});
```

### Event Handling

```dart
final engine = ElpianEngine();

engine.setGlobalEventHandler((event) {
  print('Event: ${event.type}');
  print('Target: ${event.target}');
  if (event is ElpianPointerEvent) {
    print('Position: ${event.position}');
  }
});

final widget = engine.renderFromJson({
  'type': 'Button',
  'key': 'my-button',
  'props': {'text': 'Click Me'},
  'events': {
    'click': (event) { /* handle click */ },
    'longpress': (event) { /* handle long press */ }
  }
});
```

### DOM API

```dart
final dom = ElpianDOM();
final container = dom.createElement('div', id: 'main', classes: ['container']);
final title = dom.createElement('h1');
title.textContent = 'Dynamic Content';
title.setStyle('color', '#2196F3');
container.appendChild(title);

final element = dom.getElementById('main');
element?.addClass('active');
element?.addEventListener('click', () => print('Clicked!'));

final node = element?.toElpianNode();
```

### 3D Scene Rendering

```json
{
  "world": [
    {
      "type": "mesh3d",
      "mesh": {"Box": {"width": 2.0, "height": 2.0, "depth": 2.0}},
      "material": {"color": [0.2, 0.6, 1.0, 1.0]},
      "transform": {"translation": [0.0, 1.0, 0.0]}
    },
    {
      "type": "light",
      "light_type": "Point",
      "intensity": 1500.0,
      "transform": {"translation": [4.0, 8.0, 4.0]}
    },
    {
      "type": "camera",
      "transform": {"translation": [0.0, 5.0, 10.0]}
    }
  ]
}
```

### VM-Driven UI

```dart
ElpianVmWidget(
  machineId: 'my-app',
  code: r'''
    def view = {
      "type": "Column",
      "children": [
        {"type": "Text", "props": {"text": "Hello from VM!"}},
        {"type": "Button", "props": {"text": "Click me"}}
      ]
    }
    askHost("render", view)
  ''',
)
```

## Custom Widget Registration

```dart
final engine = ElpianEngine();

engine.registerWidget('MyCustomCard', (node, children) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.1),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(children: children),
  );
});
```

## Project Structure

```
elpian/
├── lib/
│   ├── elpian_ui.dart            # Main library export
│   ├── src/
│   │   ├── core/                 # ElpianEngine, widget registry, event system
│   │   ├── models/               # ElpianNode, CSSStyle data models
│   │   ├── parser/               # JSON parser
│   │   ├── css/                  # CSS parser, stylesheet, JSON stylesheet
│   │   ├── canvas/               # 2D Canvas API
│   │   ├── widgets/              # 60+ Flutter widget builders
│   │   ├── html_widgets/         # 70+ HTML element builders
│   │   ├── bevy/                 # Bevy 3D scene integration (Rust FFI)
│   │   ├── scene3d/              # Pure-Dart 3D renderer
│   │   └── vm/                   # Elpian VM (Rust FFI/WASM)
├── example/                      # Cross-platform example runner app
│   ├── lib/examples/             # All demo pages
│   └── assets/examples/          # Example JSON/JS assets
├── rust/                         # Rust VM + Bevy crate
├── rust_builder/                 # Flutter FFI plugin
├── test/                         # Unit tests
├── assets/web_runtime/           # Web runtime scripts + WASM bundle
└── pubspec.yaml
```

## Documentation

| Document | Description |
|----------|-------------|
| [QUICKSTART.md](QUICKSTART.md) | Getting started guide |
| [FEATURES.md](FEATURES.md) | Complete feature set reference |
| [EVENT_SYSTEM.md](EVENT_SYSTEM.md) | Event handling documentation |
| [JSON_STYLESHEET.md](JSON_STYLESHEET.md) | JSON stylesheet system |
| [CANVAS_API.md](CANVAS_API.md) | 2D Canvas drawing API |
| [VM_INTEGRATION.md](VM_INTEGRATION.md) | Rust VM and FFI integration |
| [2d_graphics.md](2d_graphics.md) | 2D UI element reference |
| [3d_graphics.md](3d_graphics.md) | 3D scene graph reference |
| [logic_vm.md](logic_vm.md) | VM AST and API reference |

## Testing

```bash
flutter test
```

## License

MIT License
