<p align="center">
  <h1 align="center">Elpian UI</h1>
  <p align="center">
    <strong>A high-performance Flutter engine that renders HTML, CSS, Flutter DSL, Canvas 2D, and 3D scene graphs from JSON into native widgets.</strong>
  </p>
  <p align="center">
    <a href="#-quick-start">Quick Start</a> &bull;
    <a href="#-features">Features</a> &bull;
    <a href="#-code-examples">Examples</a> &bull;
    <a href="#-documentation">Docs</a> &bull;
    <a href="#-platform-support">Platforms</a>
  </p>
</p>

---

Define your entire UI in JSON. Render it natively in Flutter. Elpian bridges the gap between web-style markup and native mobile/desktop performance &mdash; supporting everything from simple layouts to full 3D scenes and scripted application logic.

```dart
final widget = ElpianEngine().renderFromJson({
  'type': 'div',
  'style': {'padding': '24', 'backgroundColor': '#1E1E2E', 'borderRadius': 16},
  'children': [
    {'type': 'h1', 'props': {'text': 'Hello, Elpian'}, 'style': {'color': '#CDD6F4', 'fontSize': 28}}
  ]
});
```

## At a Glance

| | |
|---|---|
| **201** Dart source files | **17** Rust source files |
| **60+** Flutter widgets | **70+** HTML5 elements |
| **150+** CSS properties | **50+** Canvas 2D commands |
| **40+** event types | **22** animation widgets |
| **6** platforms supported | **13** example apps included |

---

## 🖼️ Demo Screenshots

<p align="center">
  <img src="example/IMG_20260226_161047_415.jpg" alt="Elpian landing page" width="31%" />
  <img src="example/Screenshot_20260225_185558_Chrome.jpg" alt="QuickJS calculator demo" width="31%" />
  <img src="example/Screenshot_20260225_185705_Chrome.jpg" alt="QuickJS whiteboard demo" width="31%" />
</p>

<p align="center">
  <img src="example/Screenshot_20260226_161118_Telegram.jpg" alt="3D scene demo" width="48%" />
</p>

> These screenshots highlight real Elpian examples: landing UI rendering, QuickJS calculator + whiteboard, 3D scene graph rendering, and Canvas API primitives.

---

## &#x2728; Features

### &#x1F3D7;&#xFE0F; Rendering Engines

| Engine | Description |
|--------|-------------|
| **Flutter DSL** | 60+ Flutter widgets rendered from JSON &mdash; layout, controls, animation, interaction |
| **HTML Rendering** | 70+ HTML5 semantic elements &mdash; `div`, `section`, `form`, `table`, `video`, and more |
| **CSS Engine** | 150+ CSS properties &mdash; flexbox, grid, transforms, animations, filters, variables |
| **Canvas 2D** | Full 2D graphics API with paths, shapes, gradients, text, and transforms |
| **3D Scene Graphs** | JSON-defined 3D worlds rendered via **Bevy** (Rust/GPU) or a pure-Dart fallback |
| **Elpian VM** | Sandboxed Rust bytecode VM with FFI (native) and WASM (web) for scripting UI logic |

### &#x2699;&#xFE0F; Core Systems

- **JSON Stylesheets** &mdash; CSS-like rules in JSON with media queries, variables, keyframe animations, and cascade
- **DOM API** &mdash; `getElementById`, `querySelector`, `appendChild`, style & class management, and more
- **Event System** &mdash; 40+ event types with capturing, bubbling, delegation, debounce, and throttle
- **Widget Registry** &mdash; 200+ pre-registered builders, plus custom widget registration
- **QuickJS Runtime** &mdash; Embedded JavaScript engine for scripting alongside the Rust VM

---

## &#x1F680; Quick Start

### Installation

Add Elpian to your `pubspec.yaml`:

```yaml
dependencies:
  elpian_ui:
    path: ./path/to/elpian
```

```bash
flutter pub get
```

### Run the demo

```bash
flutter run -t lib/example/landing_page_example.dart
```

---

## &#x1F4BB; Code Examples

### Render UI from JSON

```dart
import 'package:elpian_ui/elpian_ui.dart';

final engine = ElpianEngine();

final widget = engine.renderFromJson({
  'type': 'div',
  'style': {
    'padding': '20',
    'backgroundColor': '#2196F3',
    'borderRadius': 12,
    'boxShadow': [{'color': 'rgba(0,0,0,0.2)', 'offset': {'x': 0, 'y': 4}, 'blur': 8}]
  },
  'children': [
    {
      'type': 'h1',
      'props': {'text': 'Hello World'},
      'style': {'color': 'white', 'fontSize': 32, 'fontWeight': 'bold'}
    }
  ]
});
```

### JSON Stylesheets

```dart
engine.loadStylesheet({
  'rules': [
    {
      'selector': '.card',
      'styles': {
        'backgroundColor': '#FFFFFF',
        'padding': '20',
        'borderRadius': 12,
        'boxShadow': [{'color': 'rgba(0,0,0,0.1)', 'offset': {'x': 0, 'y': 2}, 'blur': 8}],
      }
    },
    {
      'selector': '.btn-primary',
      'styles': {'backgroundColor': '#2196F3', 'color': '#FFFFFF', 'padding': '12 24'}
    }
  ],
  'mediaQueries': [
    {
      'query': 'min-width: 768',
      'rules': [{'selector': '.card', 'styles': {'padding': '40'}}]
    }
  ]
});

final ui = engine.renderFromJson({
  'type': 'div',
  'props': {'className': 'card'},
  'children': [
    {'type': 'Button', 'props': {'text': 'Click Me', 'className': 'btn-primary'}}
  ]
});
```

### Event Handling

```dart
engine.setGlobalEventHandler((event) {
  print('Event: ${event.type} on ${event.target}');
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

### DOM Manipulation

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

// Convert to renderable widget
final node = element?.toElpianNode();
```

### 3D Scene Graphs

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

Mesh primitives: **Box**, **Sphere**, **Plane**, **Cylinder**, **Capsule**, **Torus**
Materials: PBR with color, metallic, roughness
Lighting: Point, Directional, Spot with shadows

### VM-Driven UI

#### QuickJS runtime sample (`ElpianRuntime.quickJs`)

```dart
ElpianVmWidget.fromCode(
  machineId: 'quickjs-counter-demo',
  runtime: ElpianRuntime.quickJs,
  code: r'''
let count = 0;

function renderCounter() {
  askHost('render', JSON.stringify({
    type: 'Column',
    props: { style: { padding: '20', backgroundColor: '#f5f7ff' } },
    children: [
      { type: 'Text', props: { text: `QuickJS Count: ${count}` } },
      { type: 'Button', props: { text: 'Increment' }, events: { tap: 'increment' } }
    ]
  }));
}

function increment() {
  count += 1;
  askHost('println', `Count changed to ${count}`);
  renderCounter();
}

renderCounter();
''',
)
```

#### Elpian AST VM sample (`ElpianRuntime.elpian`)

```dart
ElpianVmWidget.fromAst(
  machineId: 'vm-ast-counter',
  astJson: jsonEncode({
    'type': 'program',
    'data': {'body': [
      {
        'type': 'definition',
        'data': {
          'leftSide': {
            'type': 'identifier',
            'data': {'name': 'view'}
          },
          'rightSide': {
            'type': 'object',
            'data': {
              'value': {
                'type': {'type': 'string', 'data': {'value': 'Text'}},
                'props': {
                  'type': 'object',
                  'data': {
                    'value': {
                      'text': {
                        'type': 'string',
                        'data': {'value': 'Hello from Elpian AST VM!'}
                      }
                    }
                  }
                }
              }
            }
          }
        }
      },
      {
        'type': 'host_call',
        'data': {
          'name': 'render',
          'args': [
            {'type': 'identifier', 'data': {'name': 'view'}}
          ]
        }
      }
    ]}
  }),
)
```

### Custom Widget Registration

```dart
engine.registerWidget('MyCustomCard', (node, children) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4)),
      ],
    ),
    child: Column(children: children),
  );
});
```

---

## &#x1F9E9; Widget & Element Coverage

<details>
<summary><strong>&#x1F4D0; Layout Widgets (30+)</strong></summary>

Container, Column, Row, Stack, Positioned, Expanded, Flexible, Wrap, Center, Align, Padding, SizedBox, AspectRatio, FractionallySizedBox, FittedBox, LimitedBox, ConstrainedBox, OverflowBox, Baseline, Spacer, IndexedStack, RotatedBox, DecoratedBox, ClipRRect

</details>

<details>
<summary><strong>&#x1F39B;&#xFE0F; UI Controls (15+)</strong></summary>

Button, TextField, Checkbox, Radio, Switch, Slider, Chip, Badge, CircularProgressIndicator, LinearProgressIndicator, Divider, VerticalDivider

</details>

<details>
<summary><strong>&#x1F3AC; Animation Widgets (22)</strong></summary>

AnimatedContainer, AnimatedOpacity, AnimatedCrossFade, AnimatedSwitcher, AnimatedAlign, AnimatedPadding, AnimatedPositioned, AnimatedScale, AnimatedRotation, AnimatedSlide, AnimatedSize, AnimatedDefaultTextStyle, AnimatedGradient, FadeTransition, SlideTransition, ScaleTransition, RotationTransition, SizeTransition, TweenAnimationBuilder, StaggeredAnimation, Shimmer, Pulse

</details>

<details>
<summary><strong>&#x1F446; Interaction Widgets (10+)</strong></summary>

InkWell, GestureDetector, Tooltip, Dismissible, Draggable, DragTarget, Opacity, Transform, Hero

</details>

<details>
<summary><strong>&#x1F310; HTML5 Elements (70+)</strong></summary>

**Document:** div, span, section, article, header, footer, nav, aside, main

**Typography:** h1-h6, p, strong, em, mark, small, del, ins, sub, sup, abbr, cite, kbd, samp, var, code, pre, blockquote, br, hr, time, data

**Lists:** ul, ol, li &bull; **Tables:** table, tr, td, th

**Forms:** form, input, button, select, option, optgroup, textarea, label, fieldset, legend, datalist, output, progress, meter

**Media:** img, picture, source, figure, figcaption, video, audio, track, canvas, iframe, embed, object, param, map, area

**Interactive:** a, details, summary, dialog

</details>

<details>
<summary><strong>&#x1F3A8; CSS Properties (150+)</strong></summary>

**Box Model (25):** width, height, min/max dimensions, padding, margin, box-sizing, overflow

**Positioning (10):** position (relative/absolute/fixed/sticky), top, right, bottom, left, z-index, float, clear

**Flexbox (20):** display, flex-direction, flex-wrap, justify-content, align-items, align-content, align-self, gap, order, flex-grow/shrink/basis

**Grid (15):** grid-template-columns/rows/areas, grid-auto-columns/rows/flow, grid-column/row/area, grid-gap, justify-items/self

**Typography (25):** color, font-size/weight/style/family, letter-spacing, word-spacing, line-height, text-align/decoration/transform/overflow, white-space

**Background (10):** background-color/image/size/position/repeat/attachment/clip/origin, linear & radial gradients

**Border (20):** border, border-width/style/color per side, border-radius per corner, outline, border-collapse/spacing

**Transform (20):** rotate, scale, translate, skew per axis, perspective, transform-origin/style, backface-visibility

**Effects (15):** opacity, visibility, box-shadow, text-shadow, drop-shadow, blur, brightness, contrast, grayscale, hue-rotate, invert, saturate, sepia, backdrop-blur

**Animation (12):** transition-duration/delay/property/timing-function, animation-name/duration/delay/timing-function/iteration-count/direction/fill-mode/play-state

</details>

---

## &#x1F30D; Platform Support

| Platform | 2D / HTML / CSS | Canvas 2D | 3D (Bevy GPU) | 3D (Dart) | VM |
|:--------:|:---------------:|:---------:|:-------------:|:---------:|:--:|
| Android | &#x2705; | &#x2705; | &#x2705; FFI | &#x2705; | &#x2705; FFI |
| iOS | &#x2705; | &#x2705; | &#x2705; FFI | &#x2705; | &#x2705; FFI |
| Web | &#x2705; | &#x2705; | &#x2705; WASM | &#x2705; | &#x2705; WASM |
| macOS | &#x2705; | &#x2705; | &#x2705; FFI | &#x2705; | &#x2705; FFI |
| Linux | &#x2705; | &#x2705; | &#x2705; FFI | &#x2705; | &#x2705; FFI |
| Windows | &#x2705; | &#x2705; | &#x2705; FFI | &#x2705; | &#x2705; FFI |

---

## &#x1F4C1; Project Structure

```
elpian/
├── lib/
│   ├── elpian_ui.dart              # Main library export
│   ├── src/
│   │   ├── core/                   # Engine, widget registry, event system, DOM API
│   │   ├── models/                 # ElpianNode, CSSStyle data models
│   │   ├── parser/                 # JSON parser
│   │   ├── css/                    # CSS parser, stylesheets, JSON stylesheet engine
│   │   ├── canvas/                 # 2D Canvas API
│   │   ├── widgets/                # 60+ Flutter widget builders
│   │   ├── html_widgets/           # 70+ HTML element builders
│   │   ├── bevy/                   # Bevy 3D scene integration (Rust FFI)
│   │   ├── scene3d/                # Pure-Dart 3D renderer (fallback)
│   │   └── vm/                     # Elpian VM + QuickJS integration
│   └── example/                    # 13 demo applications
├── rust/                           # Rust VM + Bevy crate (compiler, executor, FFI)
├── rust_builder/                   # Flutter FFI plugin (all platforms)
├── test/                           # Unit & integration tests
├── web/                            # Web assets, WASM loader, PWA manifest
├── .github/workflows/              # CI/CD: build WASM + deploy to GitHub Pages
└── pubspec.yaml
```

---

## &#x1F4D6; Documentation

| Document | Description |
|:---------|:------------|
| [QUICKSTART.md](QUICKSTART.md) | &#x26A1; Getting started guide |
| [FEATURES.md](FEATURES.md) | &#x1F4CB; Complete feature set reference |
| [EVENT_SYSTEM.md](EVENT_SYSTEM.md) | &#x1F4E1; Event handling & propagation |
| [JSON_STYLESHEET.md](JSON_STYLESHEET.md) | &#x1F3A8; JSON stylesheet system |
| [CANVAS_API.md](CANVAS_API.md) | &#x1F58C;&#xFE0F; 2D Canvas drawing API |
| [VM_LOGIC.md](VM_LOGIC.md) | &#x1F9F0; Rust VM AST & API reference |
| [2D_GRAPHICS.md](2D_GRAPHICS.md) | &#x1F5BC;&#xFE0F; 2D UI element reference |
| [3D_GRAPHICS.md](3D_GRAPHICS.md) | &#x1F4E6; 3D scene graph reference |

---

## &#x1F527; Use Cases

- **&#x2601;&#xFE0F; Server-Driven UI** &mdash; Render complete interfaces from backend JSON configs
- **&#x1F4DD; Dynamic Forms** &mdash; Generate forms from schema definitions at runtime
- **&#x1F4F0; Content Management** &mdash; Render CMS content with full CSS styling
- **&#x1F500; A/B Testing** &mdash; Switch UI variants without shipping app updates
- **&#x1F3D7;&#xFE0F; No-Code Builders** &mdash; Visual UI builders that output JSON for Elpian to render
- **&#x1F4CA; 3D Visualization** &mdash; Product viewers, data viz, interactive scenes
- **&#x1F4DC; Scripted Applications** &mdash; VM-driven apps with dynamic logic and rendering

---

## &#x1F3C3; Running Tests

```bash
flutter test
```

---

## &#x1F4C4; License

MIT License
