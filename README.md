# STAC Flutter UI

A professional, production-ready Server-driven UI library for Flutter with comprehensive HTML element support, full CSS properties integration, DOM-like API, and CSS stylesheet rendering.

## 🚀 Features

### Core Capabilities
- **60+ Flutter Widgets** - Complete widget library including animations, layouts, and UI controls
- **70+ HTML Elements** - Full HTML5 element support with semantic tags
- **150+ CSS Properties** - Comprehensive CSS support including:
  - **Flexbox** - Complete flexbox layout system
  - **Grid** - CSS Grid layout properties
  - **Transforms** - 2D/3D transforms (rotate, scale, translate, skew)
  - **Animations** - Transitions and animations
  - **Filters** - Blur, brightness, contrast, grayscale, etc.
  - **Gradients** - Linear and radial gradients
  - **Shadows** - Box shadows and text shadows
  - **Typography** - Complete text styling
  - **Positioning** - Absolute, relative, fixed, sticky
  - **Spacing** - Padding, margin with all variants
  - **Borders** - All border properties and radius
  - **Background** - Colors, images, gradients, repeat
  
### Advanced Features
- **🎯 Complete Event System** - DOM-like event handling with bubbling/capturing
- **📝 JSON Stylesheet Parser** - Define complete CSS stylesheets in JSON format
- **🎨 Canvas API** - Full 2D graphics with 50+ drawing commands
- **DOM-like API** - Full DOM manipulation API similar to JavaScript
- **CSS Stylesheet Renderer** - Parse and apply CSS stylesheets globally
- **Media Queries** - Responsive design support
- **JSON DSL** - Render any UI from JSON configuration
- **Extensible Architecture** - Easy custom widget registration
- **Type-safe** - Full Dart type safety
- **Production Ready** - Comprehensive testing and examples

## 📦 Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  stac_flutter_ui:
    path: ./path/to/stac_flutter_ui
```

## 🎯 Quick Start

### Basic Usage

```dart
import 'package:stac_flutter_ui/stac_flutter_ui.dart';

final engine = StacEngine();

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
final engine = StacEngine();

// Load stylesheet from JSON
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

// Use classes in UI
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

**Stylesheet Features:**
- ✅ Tag, Class, and ID selectors
- ✅ All 150+ CSS properties
- ✅ Media queries for responsive design
- ✅ CSS variables
- ✅ Keyframe animations
- ✅ Builder pattern
- ✅ Style presets

### Event Handling

```dart
final engine = StacEngine();

// Setup global event handler to receive ALL events
engine.setGlobalEventHandler((event) {
  print('Event: ${event.type}');
  print('Target: ${event.target}');
  print('Phase: ${event.phase}');
  
  if (event is StacPointerEvent) {
    print('Position: ${event.position}');
  }
});

// Render UI with events
final widget = engine.renderFromJson({
  'type': 'Button',
  'key': 'my-button',
  'props': {'text': 'Click Me'},
  'events': {
    'click': (event) {
      // Handle click
    },
    'longpress': (event) {
      // Handle long press
    }
  }
});
```

### Event Types Supported

**40+ Event Types:**
- Click, Double Click, Long Press, Tap
- Pointer Events (down, up, move, enter, exit, hover)
- Drag Events (start, drag, end)
- Swipe Gestures (left, right, up, down)
- Focus/Blur Events
- Input/Change Events
- Keyboard Events
- Touch Events
- Scale/Rotate/Pinch Gestures

**Event Features:**
- ✅ Event Bubbling & Capturing
- ✅ stopPropagation() & preventDefault()
- ✅ Event Delegation
- ✅ Custom Events
- ✅ Event Bus
- ✅ Debounce & Throttle utilities

### DOM API Usage

```dart
// Create DOM instance
final dom = StacDOM();

// Create elements
final container = dom.createElement('div', id: 'main', classes: ['container']);
final title = dom.createElement('h1');
title.textContent = 'Dynamic Content';
title.setStyle('color', '#2196F3');

// Manipulate DOM
container.appendChild(title);

// Query elements
final element = dom.getElementById('main');
final byClass = dom.getElementsByClassName('container');
final byTag = dom.getElementsByTagName('h1');
final querySelector = dom.querySelector('#main .title');

// Add/Remove classes
element?.addClass('active');
element?.removeClass('inactive');
element?.toggleClass('visible');

// Event handling
element?.addEventListener('click', () {
  print('Element clicked!');
});

// Convert to StacNode for rendering
final node = element?.toStacNode();
```

### CSS Stylesheet

```dart
// Create stylesheet
final stylesheet = CSSStylesheet();

// Parse CSS
stylesheet.parseCSS('''
  .card {
    padding: 16px;
    margin: 8px;
    background-color: white;
    border-radius: 8px;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
  }
  
  .primary-button {
    background-color: #2196F3;
    color: white;
    padding: 12px 24px;
  }
  
  h1 {
    font-size: 32px;
    font-weight: bold;
  }
''');

// Get computed style
final style = stylesheet.getComputedStyle(
  tagName: 'button',
  classes: ['primary-button'],
  id: 'submit-btn',
);

// Add rules programmatically
stylesheet.addRule('.error', {
  'color': '#F44336',
  'border': '1px solid #F44336'
});
```

## 📚 Comprehensive Widget List

### Flutter Widgets (60+)

**Layout:**
- Container, Column, Row, Stack, Positioned
- Wrap, Center, Align, Padding, SizedBox
- Expanded, Flexible, Spacer
- AspectRatio, FractionallySizedBox, FittedBox
- ConstrainedBox, LimitedBox, OverflowBox
- Baseline, IndexedStack

**UI Controls:**
- Button, TextField, Checkbox, Radio, Switch, Slider
- DropdownButton (Select), Chip, Badge
- CircularProgressIndicator, LinearProgressIndicator

**Visual:**
- Image, Icon, Card, Divider, VerticalDivider
- Opacity, Transform, ClipRRect, DecoratedBox
- AnimatedContainer, AnimatedOpacity
- RotatedBox, Hero

**Interaction:**
- InkWell, GestureDetector, Tooltip
- Dismissible, Draggable, DragTarget

**Scrolling:**
- ListView, GridView

**App Structure:**
- Scaffold, AppBar

### HTML Elements (70+)

**Document Structure:**
- html, head, body, div, span, section, article
- header, footer, nav, aside, main

**Typography:**
- h1-h6, p, strong, em, mark, small
- del, ins, sub, sup, abbr, cite
- code, pre, kbd, samp, var

**Lists:**
- ul, ol, li

**Tables:**
- table, thead, tbody, tfoot, tr, td, th
- caption, col, colgroup

**Forms:**
- form, input, button, select, option, optgroup
- textarea, label, fieldset, legend
- datalist, output, progress, meter

**Media:**
- img, picture, source, figure, figcaption
- video, audio, track, canvas
- iframe, embed, object, param

**Interactive:**
- a, details, summary, dialog

**Semantic:**
- time, data, map, area

**Formatting:**
- br, hr, blockquote

## 🎨 CSS Properties Reference

### Layout & Box Model (40+)
```css
width, height, min-width, max-width, min-height, max-height
padding, padding-top, padding-right, padding-bottom, padding-left
margin, margin-top, margin-right, margin-bottom, margin-left
box-sizing, overflow, overflow-x, overflow-y
display, position, top, right, bottom, left, z-index
```

### Flexbox (15+)
```css
display: flex
flex-direction, flex-wrap, flex-basis
flex, flex-grow, flex-shrink
justify-content, align-items, align-content, align-self
gap, row-gap, column-gap
order
```

### Grid (15+)
```css
display: grid
grid-template-columns, grid-template-rows, grid-template-areas
grid-auto-columns, grid-auto-rows, grid-auto-flow
grid-column, grid-row, grid-area
grid-column-gap, grid-row-gap, grid-gap
justify-items, justify-self, align-items, align-self
```

### Typography (20+)
```css
color, font-size, font-weight, font-style, font-family
letter-spacing, word-spacing, line-height
text-align, text-decoration, text-decoration-color
text-decoration-style, text-decoration-thickness
text-transform, text-overflow, white-space
vertical-align, text-baseline
```

### Background (10+)
```css
background-color, background-image, background-size
background-position, background-repeat, background-attachment
background-clip, background-origin
gradient (linear, radial)
```

### Border (15+)
```css
border, border-width, border-style, border-color
border-top, border-right, border-bottom, border-left
border-radius, border-top-left-radius, border-top-right-radius
border-bottom-left-radius, border-bottom-right-radius
border-collapse, border-spacing
outline, outline-width, outline-style, outline-color, outline-offset
```

### Transform (15+)
```css
transform, transform-origin, transform-style
rotate, rotate-x, rotate-y, rotate-z
scale, scale-x, scale-y
translate, translate-x, translate-y
skew-x, skew-y
perspective, perspective-origin, backface-visibility
```

### Effects (15+)
```css
opacity, visibility
box-shadow, text-shadow, drop-shadow
blur, brightness, contrast, grayscale
hue-rotate, invert, saturate, sepia
backdrop-color, backdrop-blur
```

### Animation (10+)
```css
transition-duration, transition-delay, transition-property
transition-timing-function
animation-name, animation-duration, animation-delay
animation-timing-function, animation-iteration-count
animation-direction, animation-fill-mode, animation-play-state
```

### Other (10+)
```css
clip-behavior, clip-path, shape
object-fit, object-position
cursor, pointer-events, user-select, touch-action
list-style-type, list-style-position, list-style-image
resize, float, clear, direction
```

## 💡 Advanced Examples

### Flexbox Layout

```json
{
  "type": "div",
  "style": {
    "display": "flex",
    "flexDirection": "row",
    "justifyContent": "space-between",
    "alignItems": "center",
    "gap": 16
  },
  "children": [
    {
      "type": "div",
      "style": {"flex": 1, "padding": "16"},
      "children": [{"type": "p", "props": {"text": "Item 1"}}]
    },
    {
      "type": "div",
      "style": {"flex": 2, "padding": "16"},
      "children": [{"type": "p", "props": {"text": "Item 2"}}]
    }
  ]
}
```

### Transforms & Animations

```json
{
  "type": "div",
  "style": {
    "width": 100,
    "height": 100,
    "backgroundColor": "#2196F3",
    "rotate": 45,
    "scale": 1.2,
    "translateX": 20,
    "translateY": 10,
    "opacity": 0.8,
    "borderRadius": 12,
    "boxShadow": [{
      "color": "rgba(0,0,0,0.3)",
      "offset": {"x": 0, "y": 8},
      "blur": 16
    }],
    "transitionDuration": "300ms",
    "transitionCurve": "ease-in-out"
  }
}
```

### Gradients

```json
{
  "type": "div",
  "style": {
    "width": 300,
    "height": 200,
    "gradient": {
      "type": "linear",
      "colors": ["#FF6B6B", "#4ECDC4", "#45B7D1"],
      "begin": "topLeft",
      "end": "bottomRight"
    },
    "borderRadius": 16
  }
}
```

## 🔧 Custom Widget Registration

```dart
final engine = StacEngine();

// Register custom widget
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

// Use in JSON
final json = {
  'type': 'MyCustomCard',
  'children': [...]
};
```

## 📖 API Reference

### StacEngine
Main rendering engine for converting JSON DSL to Flutter widgets.

**Methods:**
- `render(StacNode node)` - Render a StacNode to Widget
- `renderFromJson(Map<String, dynamic> json)` - Render from JSON
- `registerWidget(String type, WidgetBuilder builder)` - Register custom widget

### StacDOM
DOM-like API for element manipulation.

**Methods:**
- `getElementById(String id)` - Get element by ID
- `getElementsByClassName(String className)` - Get elements by class
- `getElementsByTagName(String tagName)` - Get elements by tag
- `querySelector(String selector)` - Query single element
- `querySelectorAll(String selector)` - Query all matching elements
- `createElement(String tagName, {String? id, List<String>? classes})` - Create element
- `removeElement(StacElement element)` - Remove element

### StacElement
Represents a DOM element.

**Properties:**
- `tagName`, `id`, `classes`, `parent`, `children`
- `textContent`, `innerHTML`, `attributes`, `style`

**Methods:**
- `appendChild(StacElement child)`
- `removeChild(StacElement child)`
- `insertBefore(StacElement newChild, StacElement? ref)`
- `replaceChild(StacElement newChild, StacElement oldChild)`
- `setAttribute(String name, dynamic value)`
- `getAttribute(String name)`
- `setStyle(String property, dynamic value)`
- `addClass(String className)`
- `removeClass(String className)`
- `toggleClass(String className)`
- `addEventListener(String event, Function callback)`
- `clone({bool deep = false})`
- `toStacNode()`

### CSSStylesheet
CSS stylesheet parser and manager.

**Methods:**
- `parseCSS(String cssString)` - Parse CSS string
- `addRule(String selector, Map<String, dynamic> styles)` - Add rule
- `removeRule(String selector)` - Remove rule
- `getComputedStyle({...})` - Get computed style
- `toCSS()` - Export to CSS string

## 🧪 Testing

Run tests:
```bash
flutter test
```

## 📝 License

MIT License

## 🤝 Contributing

Contributions welcome! This library includes:
- 130+ widget/element implementations
- 150+ CSS properties
- DOM API with 20+ methods
- Stylesheet system with media queries
- Comprehensive examples and documentation
