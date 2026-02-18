# Elpian UI - Complete Feature Set

## Project Statistics

- **Total Dart Files:** 155+
- **Flutter Widgets:** 60+
- **HTML Elements:** 70+
- **CSS Properties:** 150+
- **Event Types:** 40+
- **Canvas Commands:** 50+

## Core Components

### 1. Rendering Engine (ElpianEngine)
- JSON DSL to Flutter widget conversion
- Widget registry system with 200+ registered builders
- CSS style parsing and application
- Custom widget registration
- Event system integration with global handler
- JSON stylesheet loading and class resolution

### 2. Event System
- **Event Types**: 40+ (click, drag, swipe, keyboard, pointer, gesture, focus, input, etc.)
- **Event Phases**: Capturing, At Target, Bubbling
- **Event Objects**: ElpianEvent, ElpianPointerEvent, ElpianKeyboardEvent, ElpianInputEvent, ElpianGestureEvent
- **Event Dispatcher**: Tree-aware event propagation
- **Event Bus**: Global event broadcasting
- **Event Delegation**: Efficient parent-level event handling
- **Utilities**: Debounce and throttle helpers
- **Control**: stopPropagation(), preventDefault(), stopImmediatePropagation()

### 3. DOM API (ElpianDOM)
- Element creation, deletion, and tree manipulation
- Query selectors (getElementById, getElementsByClassName, querySelector, querySelectorAll)
- Style and class management (addClass, removeClass, toggleClass, setStyle)
- Event listener registration
- Conversion to ElpianNode for rendering

### 4. CSS System
- **CSSParser** - Parse CSS properties from maps and JSON
- **JsonStylesheetParser** - Complete JSON stylesheet support
- **CSSStylesheet** - Global stylesheet management with cascade
- **Media Queries** - Responsive design with breakpoints
- **CSS Variables** - Reusable design tokens
- **Keyframe Animations** - Declarative animation definitions
- **JsonStylesheetBuilder** - Programmatic stylesheet construction
- **StylePresets** - Pre-built style patterns (flexCenter, card, button, grid, elevation)

### 5. Canvas 2D API
- 50+ drawing commands (paths, shapes, text, gradients, transforms)
- JSON-based canvas definitions
- Builder pattern for programmatic construction
- Canvas presets (star, polygon, arrow)
- Animation support with Flutter's animation system

### 6. 3D Scene Rendering
- JSON-defined 3D scene graphs
- Bevy renderer (Rust/GPU) for native and WASM platforms
- Pure-Dart canvas renderer for software rendering
- Mesh primitives: Box, Sphere, Plane, Cylinder, Capsule, Torus
- PBR materials with color, metallic, roughness
- Point/Directional/Spot lights with shadows
- Camera with perspective projection
- Transform hierarchy (translation, rotation, scale)

### 7. Elpian VM
- Sandboxed Rust VM with bytecode compiler and executor
- Native FFI for Android, iOS, macOS, Linux, Windows
- WASM via wasm-bindgen for web
- Host call protocol (render, updateApp, println, stringify)
- ElpianVmWidget for declarative VM-driven UIs
- Custom host handlers for app-specific APIs

## Widget Categories

### Layout Widgets (30+)
Container, Column, Row, Stack, Positioned, Expanded, Flexible, Wrap, Center, Align, Padding, SizedBox, AspectRatio, FractionallySizedBox, FittedBox, LimitedBox, ConstrainedBox, OverflowBox, Baseline, Spacer, IndexedStack, RotatedBox, DecoratedBox, ClipRRect

### UI Control Widgets (15+)
Button, TextField, Checkbox, Radio, Switch, Slider, Chip, Badge, CircularProgressIndicator, LinearProgressIndicator, Divider, VerticalDivider

### Interaction Widgets (10+)
InkWell, GestureDetector, Tooltip, Dismissible, Draggable, DragTarget, Opacity, Transform

### Animation Widgets (22)
AnimatedContainer, AnimatedOpacity, AnimatedCrossFade, AnimatedSwitcher, AnimatedAlign, AnimatedPadding, AnimatedPositioned, AnimatedScale, AnimatedRotation, AnimatedSlide, AnimatedSize, AnimatedDefaultTextStyle, AnimatedGradient, FadeTransition, SlideTransition, ScaleTransition, RotationTransition, SizeTransition, TweenAnimationBuilder, StaggeredAnimation, Shimmer, Pulse

### Scrolling Widgets
ListView, GridView

### App Structure
Scaffold, AppBar, Hero

## HTML Elements (70+)

**Document Structure:** div, span, section, article, header, footer, nav, aside, main

**Typography:** h1-h6, p, strong, em, mark, small, del, ins, sub, sup, abbr, cite, kbd, samp, var, code, pre, blockquote, br, hr, time, data

**Lists:** ul, ol, li

**Tables:** table, tr, td, th

**Forms:** form, input, button, select, option, optgroup, textarea, label, fieldset, legend, datalist, output, progress, meter

**Media:** img, picture, source, figure, figcaption, video, audio, track, canvas, iframe, embed, object, param, map, area

**Interactive:** a, details, summary, dialog

## CSS Properties (150+)

### Box Model (25)
width, height, min-width, max-width, min-height, max-height, padding (+ directional), margin (+ directional), box-sizing, overflow, overflow-x, overflow-y

### Positioning (10)
position (relative, absolute, fixed, sticky), top, right, bottom, left, z-index, float, clear

### Flexbox (20)
display, flex-direction, flex-wrap, flex-basis, flex, flex-grow, flex-shrink, justify-content, align-items, align-content, align-self, gap, row-gap, column-gap, order

### Grid (15)
grid-template-columns, grid-template-rows, grid-template-areas, grid-auto-columns, grid-auto-rows, grid-auto-flow, grid-column, grid-row, grid-area, grid-column-gap, grid-row-gap, grid-gap, justify-items, justify-self

### Typography (25)
color, font-size, font-weight, font-style, font-family, letter-spacing, word-spacing, line-height, text-align, text-decoration, text-decoration-color, text-decoration-style, text-decoration-thickness, text-transform, text-overflow, white-space, vertical-align, text-baseline

### Background (10)
background-color, background-image, background-size, background-position, background-repeat, background-attachment, background-clip, background-origin, gradient (linear, radial)

### Border (20)
border, border-width, border-style, border-color, border-top/right/bottom/left, border-radius (+ corners), border-collapse, border-spacing, outline, outline-width, outline-style, outline-color, outline-offset

### Transform (20)
transform, transform-origin, transform-style, rotate, rotate-x/y/z, scale, scale-x/y, translate, translate-x/y, skew-x/y, perspective, perspective-origin, backface-visibility

### Effects (15)
opacity, visibility, box-shadow, text-shadow, drop-shadow, blur, brightness, contrast, grayscale, hue-rotate, invert, saturate, sepia, backdrop-color, backdrop-blur

### Animation (12)
transition-duration, transition-delay, transition-property, transition-timing-function, animation-name, animation-duration, animation-delay, animation-timing-function, animation-iteration-count, animation-direction, animation-fill-mode, animation-play-state

## DOM API Methods

### Query (8)
getElementById, getElementsByClassName, getElementsByTagName, querySelector, querySelectorAll, createElement, removeElement, clear

### Manipulation (10)
appendChild, removeChild, insertBefore, replaceChild, getAttribute, setAttribute, removeAttribute, hasAttribute, clone, toElpianNode

### Style & Class (8)
setStyle, getStyle, setStyleObject, computedStyle, addClass, removeClass, hasClass, toggleClass

### Events (3)
addEventListener, removeEventListener, dispatchEvent

## Use Cases

- **Server-Driven UI** - Render UIs from backend JSON configurations
- **Dynamic Forms** - Generate forms from schema definitions
- **Content Management** - Render CMS content with proper styling
- **A/B Testing** - Switch UI variants without app updates
- **No-Code Builders** - Visual UI builders with JSON output
- **3D Visualization** - Product viewers, data visualization, game scenes
- **Scripted UIs** - VM-driven applications with dynamic logic

## Platform Support

| Platform | 2D/HTML/CSS | Canvas | 3D (Bevy) | 3D (Dart) | VM |
|----------|-------------|--------|-----------|-----------|-----|
| Android  | Yes | Yes | Yes (FFI) | Yes | Yes (FFI) |
| iOS      | Yes | Yes | Yes (FFI) | Yes | Yes (FFI) |
| Web      | Yes | Yes | Yes (WASM) | Yes | Yes (WASM) |
| macOS    | Yes | Yes | Yes (FFI) | Yes | Yes (FFI) |
| Linux    | Yes | Yes | Yes (FFI) | Yes | Yes (FFI) |
| Windows  | Yes | Yes | Yes (FFI) | Yes | Yes (FFI) |
