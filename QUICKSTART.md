# Elpian UI - Quick Start Guide

## Overview

Elpian UI is a high-performance Flutter engine that renders HTML, CSS, Flutter DSL, and 3D scene graphs from JSON and markup formats. It combines multiple rendering paradigms into a single library:

- **60+ Flutter Widgets** - Full widget library with CSS styling support
- **70+ HTML Elements** - Complete HTML5 element rendering
- **150+ CSS Properties** - Flexbox, grid, transforms, shadows, animations
- **Canvas 2D API** - 50+ drawing commands for custom graphics
- **3D Scene Graphs** - JSON-defined 3D scenes via Bevy or pure-Dart renderer
- **Elpian VM** - Sandboxed Rust VM for scripting UI logic via FFI/WASM
- **DOM API** - Full DOM manipulation with query selectors and events
- **JSON Stylesheets** - Reusable style definitions with media queries

## Getting Started

### 1. Add the dependency

```yaml
# pubspec.yaml
dependencies:
  elpian_ui:
    path: ./path/to/elpian
```

### 2. Install dependencies

```bash
flutter pub get
```

### 3. Run the example

```bash
flutter run -t lib/example/landing_page_example.dart
```

## Basic Usage

```dart
import 'package:elpian_ui/elpian_ui.dart';

final engine = ElpianEngine();

final json = {
  'type': 'div',
  'style': {
    'padding': '20',
    'backgroundColor': '#F5F5F5',
  },
  'children': [
    {
      'type': 'h1',
      'props': {'text': 'Hello World'},
      'style': {
        'color': '#2196F3',
        'fontSize': 32,
        'fontWeight': 'bold',
      },
    },
  ],
};

Widget myUI = engine.renderFromJson(json);
```

## Supported Features

### Flutter Widgets (60+)

**Layout:** Container, Column, Row, Stack, Positioned, Expanded, Flexible, Center, Padding, Align, SizedBox, Wrap, AspectRatio, FractionallySizedBox, FittedBox, ConstrainedBox, LimitedBox, OverflowBox, Baseline, Spacer, IndexedStack, RotatedBox, DecoratedBox, ClipRRect

**UI Controls:** Button, TextField, Checkbox, Radio, Switch, Slider, Chip, Badge, CircularProgressIndicator, LinearProgressIndicator

**Interaction:** InkWell, GestureDetector, Tooltip, Dismissible, Draggable, DragTarget, Hero

**Visual:** Image, Icon, Card, Divider, VerticalDivider, Opacity, Transform

**Animation:** AnimatedContainer, AnimatedOpacity, AnimatedAlign, AnimatedPadding, AnimatedPositioned, AnimatedScale, AnimatedRotation, AnimatedSlide, AnimatedSize, AnimatedSwitcher, AnimatedCrossFade, AnimatedDefaultTextStyle, AnimatedGradient, FadeTransition, SlideTransition, ScaleTransition, RotationTransition, SizeTransition, TweenAnimationBuilder, StaggeredAnimation, Shimmer, Pulse

**Scrolling:** ListView, GridView

**App Structure:** Scaffold, AppBar

### HTML Elements (70+)

div, span, h1-h6, p, a, button, input, img, ul, ol, li, table, tr, td, th, form, label, select, option, textarea, section, article, header, footer, nav, aside, main, video, audio, canvas, iframe, strong, em, code, pre, blockquote, hr, br, figure, figcaption, mark, del, ins, sub, sup, small, abbr, cite, kbd, samp, var, details, summary, dialog, progress, meter, time, data, output, fieldset, legend, datalist, optgroup, picture, source, track, embed, object, param, map, area

### CSS Properties (150+)

**Layout:** width, height, min/max dimensions, padding, margin, display, position, overflow

**Flexbox:** flex-direction, flex-wrap, justify-content, align-items, gap, flex-grow/shrink

**Grid:** grid-template-columns/rows, grid-gap, grid-column/row

**Typography:** color, font-size, font-weight, font-style, font-family, letter-spacing, line-height, text-align, text-decoration, text-transform, text-overflow

**Background:** background-color, gradient (linear/radial), background-image/size/position

**Border:** border, border-radius, border-width/style/color, outline

**Effects:** opacity, box-shadow, text-shadow, blur, brightness, contrast, grayscale, saturate

**Transform:** rotate, scale, translate, skew, perspective

**Animation:** transition-duration/delay/curve, animation properties

## Custom Widget Registration

```dart
engine.registerWidget('MyCustomWidget', (node, children) {
  return Container(
    child: Text('Custom: ${node.props['data']}'),
  );
});
```

## Project Structure

```
elpian/
├── lib/
│   ├── elpian_ui.dart       # Main library export
│   ├── src/
│   │   ├── core/            # Engine, registry, event system
│   │   ├── models/          # ElpianNode, CSSStyle
│   │   ├── parser/          # JSON parser
│   │   ├── css/             # CSS parser, stylesheets
│   │   ├── canvas/          # 2D Canvas API
│   │   ├── widgets/         # Flutter widget builders
│   │   ├── html_widgets/    # HTML element builders
│   │   ├── bevy/            # Bevy 3D scene (Rust FFI)
│   │   ├── scene3d/         # Pure-Dart 3D renderer
│   │   └── vm/              # Elpian VM integration
│   └── example/             # Demo applications
├── rust/                    # Rust VM + Bevy crate
├── rust_builder/            # Flutter FFI plugin
├── test/                    # Unit tests
├── web/                     # Web assets
└── pubspec.yaml
```

## Next Steps

1. Explore the example apps in `lib/example/`
2. See `lib/example/example_dsl.json` and `lib/example/landing_page.json` for JSON structure examples
3. Read the detailed docs: [FEATURES.md](FEATURES.md), [EVENT_SYSTEM.md](EVENT_SYSTEM.md), [CANVAS_API.md](CANVAS_API.md)
4. Check [VM_INTEGRATION.md](VM_INTEGRATION.md) for Rust VM scripting
5. See [2d_graphics.md](2d_graphics.md) and [3d_graphics.md](3d_graphics.md) for scene graph rendering

## Testing

```bash
flutter test
```
