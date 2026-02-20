# 🎨 Elpian 2D Graphics & UI Reference

Complete reference for Elpian's 2D rendering engine. All UI is defined in JSON and rendered as native Flutter widgets. Elpian supports three rendering modes: **Flutter DSL widgets**, **HTML5 semantic elements**, and a **Canvas 2D drawing API**.

---

## 📑 Table of Contents

1. [⚙️ How It Works](#how-it-works)
2. [🧩 Flutter DSL Widgets](#flutter-dsl-widgets)
3. [🌐 HTML5 Elements](#html5-elements)
4. [🎛️ CSS Properties Reference](#css-properties-reference)
5. [✏️ Canvas 2D API](#canvas-2d-api)
6. [🎬 Animation Widgets](#animation-widgets)
7. [📦 Complete Examples](#complete-examples)

---

## ⚙️ How It Works

Elpian renders UI from JSON definitions. Each node has a `type` field that maps to a registered widget builder:

```json
{
  "type": "Column",
  "children": [
    {
      "type": "Text",
      "props": { "data": "Hello, Elpian!" },
      "style": { "fontSize": "24", "fontWeight": "bold", "color": "#1a1a1a" }
    },
    {
      "type": "Button",
      "props": { "text": "Click Me" },
      "style": { "backgroundColor": "#2196F3", "padding": "12 24", "borderRadius": "8" }
    }
  ]
}
```

The `ElpianEngine` parses JSON nodes, resolves CSS styles (including JSON stylesheet rules), and builds Flutter widget trees.

### Node Structure

Every JSON node follows this format:

| Field | Type | Description |
|-------|------|-------------|
| `type` | String | Widget type name (case-sensitive) |
| `props` | Map | Widget-specific properties |
| `style` | Map | CSS properties for styling |
| `children` | List | Child nodes |
| `id` | String? | Optional element ID for DOM queries |
| `class` | String? | CSS class names (space-separated) |
| `events` | Map? | Event handler mappings |

---

## 🧩 Flutter DSL Widgets

### 📐 Layout Widgets

#### Container

Basic layout container with decoration and sizing support.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `width` | double | null | Container width |
| `height` | double | null | Container height |
| `padding` | EdgeInsets | null | Inner padding |
| `margin` | EdgeInsets | null | Outer margin |
| `alignment` | Alignment | null | Child alignment |

All visual properties (background, border, shadow) come from CSS `style`.

```json
{
  "type": "Container",
  "style": {
    "width": "300", "height": "200",
    "backgroundColor": "#f5f5f5",
    "borderRadius": "12",
    "padding": "16",
    "boxShadow": "0 2 8 rgba(0,0,0,0.1)"
  },
  "children": [...]
}
```

---

#### Column

Vertical layout — arranges children top to bottom.

| Property | Source | Description |
|----------|--------|-------------|
| `justifyContent` | CSS style | Main axis alignment |
| `alignItems` | CSS style | Cross axis alignment |
| `gap` | CSS style | Spacing between children |

```json
{
  "type": "Column",
  "style": { "justifyContent": "center", "alignItems": "center", "gap": "8" },
  "children": [...]
}
```

---

#### Row

Horizontal layout — arranges children left to right.

| Property | Source | Description |
|----------|--------|-------------|
| `justifyContent` | CSS style | Main axis alignment |
| `alignItems` | CSS style | Cross axis alignment |
| `gap` | CSS style | Spacing between children |

```json
{
  "type": "Row",
  "style": { "justifyContent": "space-between", "alignItems": "center", "gap": "12" },
  "children": [...]
}
```

---

#### Stack

Layered layout — children are overlaid on top of each other.

```json
{
  "type": "Stack",
  "style": { "alignment": "center" },
  "children": [
    { "type": "Image", "props": { "src": "background.jpg" } },
    { "type": "Positioned", "style": { "bottom": "16", "right": "16" }, "children": [...] }
  ]
}
```

---

#### Positioned

Absolutely positioned child within a `Stack`. Uses CSS `top`, `right`, `bottom`, `left`.

```json
{ "type": "Positioned", "style": { "top": "10", "left": "20" }, "children": [...] }
```

---

#### Expanded

Fills remaining space in a `Column` or `Row`.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `flex` | int | 1 | Flex factor |

```json
{ "type": "Expanded", "props": { "flex": 2 }, "children": [...] }
```

---

#### Flexible

Occupies a proportional share of available space.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `flex` | int | 1 | Flex factor |

---

#### Center

Centers its child within the available space.

```json
{ "type": "Center", "children": [{ "type": "Text", "props": { "data": "Centered" } }] }
```

---

#### Padding

Adds inner spacing around its child. Uses CSS `padding`.

```json
{ "type": "Padding", "style": { "padding": "16 24" }, "children": [...] }
```

---

#### Align

Positions its child within itself. Uses CSS `alignment`.

```json
{ "type": "Align", "style": { "alignment": "topRight" }, "children": [...] }
```

---

#### SizedBox

Fixed-size box. Uses CSS `width` and `height`.

```json
{ "type": "SizedBox", "style": { "width": "100", "height": "50" } }
```

---

#### Wrap

Wraps children into multiple rows/columns when they overflow.

| Property | Source | Default | Description |
|----------|--------|---------|-------------|
| `gap` | CSS style | 8.0 | Horizontal spacing |
| `rowGap` | CSS style | 8.0 | Vertical spacing |

```json
{
  "type": "Wrap",
  "style": { "gap": "8", "rowGap": "8" },
  "children": [
    { "type": "Chip", "props": { "label": "Tag 1" } },
    { "type": "Chip", "props": { "label": "Tag 2" } },
    { "type": "Chip", "props": { "label": "Tag 3" } }
  ]
}
```

---

#### ListView

Scrollable vertical list.

```json
{
  "type": "ListView",
  "children": [
    { "type": "Text", "props": { "data": "Item 1" } },
    { "type": "Text", "props": { "data": "Item 2" } }
  ]
}
```

---

#### GridView

Grid layout with configurable column count.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `crossAxisCount` | int | 2 | Number of columns |

```json
{
  "type": "GridView",
  "props": { "crossAxisCount": 3 },
  "children": [...]
}
```

---

#### Other Layout Widgets

| Widget | Key Properties | Description |
|--------|---------------|-------------|
| `AspectRatio` | `aspectRatio` (default: 1.0) | Constrains child to an aspect ratio |
| `FractionallySizedBox` | `widthFactor`, `heightFactor` | Sizes child as a fraction of parent |
| `FittedBox` | — | Scales child to fit within constraints |
| `ConstrainedBox` | CSS `minWidth`, `maxWidth`, `minHeight`, `maxHeight` | Applies size constraints |
| `LimitedBox` | CSS `maxWidth`, `maxHeight` | Limits size when unconstrained |
| `OverflowBox` | CSS `alignment`, `minWidth`, `maxWidth` | Allows child to exceed parent bounds |
| `Baseline` | `baseline` (default: 0.0) | Aligns child to a text baseline |
| `IndexedStack` | `index` (default: 0) | Shows one child at a time |
| `RotatedBox` | `quarterTurns` (default: 0) | Rotates child by 90° increments |
| `Spacer` | `flex` (default: 1) | Fills empty space in flex layouts |

---

### 📝 Content Widgets

#### Text

Displays styled text content.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `data` or `text` | String | '' | Text content |
| `textAlign` | TextAlign | null | Text alignment |
| `maxLines` | int | null | Max visible lines |
| `overflow` | TextOverflow | null | Overflow behavior |
| `softWrap` | bool | null | Enable soft wrapping |

Text appearance is controlled via CSS style: `fontSize`, `fontWeight`, `fontFamily`, `fontStyle`, `color`, `letterSpacing`, `lineHeight`, `textDecoration`, `textShadow`.

```json
{
  "type": "Text",
  "props": { "data": "Hello World", "textAlign": "center", "maxLines": 2 },
  "style": { "fontSize": "18", "fontWeight": "bold", "color": "#333" }
}
```

---

#### Image

Displays an image from a URL or asset path.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `src` | String | '' | Image URL or asset path |
| `fit` | BoxFit | contain | How to scale the image |

```json
{ "type": "Image", "props": { "src": "https://example.com/photo.jpg", "fit": "cover" } }
```

---

#### Icon

Displays a Material Design icon.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `icon` | String | 'star' | Icon name |
| `size` | double | 24.0 | Icon size |

Supports 170+ Material icons: `arrow_back`, `search`, `home`, `settings`, `favorite`, `star`, `add`, `delete`, `edit`, `share`, `check`, `phone`, `email`, `person`, `menu`, `close`, `refresh`, `visibility`, `lock`, `notifications`, and many more.

```json
{ "type": "Icon", "props": { "icon": "favorite", "size": 32 }, "style": { "color": "red" } }
```

---

### 🔘 Input Widgets

#### Button

Elevated button with text label.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `text` | String | 'Button' | Button text |

```json
{
  "type": "Button",
  "props": { "text": "Submit" },
  "style": { "backgroundColor": "#4CAF50", "color": "white", "borderRadius": "8", "padding": "12 24" }
}
```

---

#### TextField

Text input field.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `hint` | String | '' | Placeholder text |

```json
{ "type": "TextField", "props": { "hint": "Enter your name..." } }
```

---

#### Checkbox

Boolean toggle.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `value` | bool | false | Checked state |

---

#### Radio

Mutually exclusive selection.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `value` | dynamic | null | Radio value |
| `groupValue` | dynamic | null | Current group selection |

---

#### Switch

Toggle switch.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `value` | bool | false | On/off state |

---

#### Slider

Range input.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `value` | double | 0.5 | Current value |
| `min` | double | 0.0 | Minimum |
| `max` | double | 1.0 | Maximum |

```json
{ "type": "Slider", "props": { "value": 0.7, "min": 0, "max": 1 } }
```

---

### 🏗️ Structure Widgets

#### Scaffold

App-level structure with AppBar and body.

```json
{
  "type": "Scaffold",
  "children": [
    { "type": "AppBar", "props": { "title": "My App" } },
    { "type": "Column", "children": [...] }
  ]
}
```

---

#### AppBar

Top navigation bar.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `title` | String | '' | Bar title |

---

#### Card

Elevated content container.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `elevation` | double | 1.0 | Shadow elevation |

```json
{
  "type": "Card",
  "props": { "elevation": 4 },
  "style": { "borderRadius": "12", "padding": "16" },
  "children": [...]
}
```

---

### 💬 Feedback Widgets

| Widget | Key Properties | Description |
|--------|---------------|-------------|
| `Tooltip` | `message` (default: '') | Hover tooltip |
| `Badge` | `label` (default: '') | Small count/label indicator |
| `Chip` | `label` (default: '') | Compact labeled element |
| `Divider` | CSS `borderColor`, `borderWidth`, `height` | Horizontal separator |
| `VerticalDivider` | CSS `borderColor`, `borderWidth`, `width` | Vertical separator |
| `CircularProgressIndicator` | `value` (null = indeterminate) | Circular progress |
| `LinearProgressIndicator` | `value` (null = indeterminate) | Linear progress |

---

### 👆 Interaction Widgets

| Widget | Key Properties | Description |
|--------|---------------|-------------|
| `InkWell` | — | Material ripple effect on tap |
| `GestureDetector` | — | Handles tap, double-tap, long-press |
| `Dismissible` | — | Swipe-to-dismiss |
| `Draggable` | `data` | Makes child draggable |
| `DragTarget` | — | Receives dragged items |
| `Hero` | `tag` (default: 'hero') | Shared element transition |

---

### ✨ Visual Effect Widgets

| Widget | Key Properties | Description |
|--------|---------------|-------------|
| `Opacity` | `opacity` (default: 1.0) | Adjusts child transparency |
| `Transform` | CSS `rotate`, `scale`, `transform` | Applies geometric transforms |
| `ClipRRect` | CSS `borderRadius` (default: 8.0) | Clips child with rounded corners |
| `DecoratedBox` | CSS `backgroundColor`, `gradient`, `border`, `boxShadow` | Decorative wrapper |

---

### ✏️ Canvas Widget

Draws 2D graphics using a command-based API. See [Canvas 2D API](#canvas-2d-api).

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `width` | double | null | Canvas width |
| `height` | double | null | Canvas height |
| `backgroundColor` | Color | null | Background fill |
| `commands` | List | [] | Drawing commands |

```json
{
  "type": "Canvas",
  "props": {
    "width": 400, "height": 300,
    "commands": [
      { "command": "setFillStyle", "color": "#FF6B35" },
      { "command": "fillRect", "x": 50, "y": 50, "width": 100, "height": 80 },
      { "command": "setFillStyle", "color": "#004E89" },
      { "command": "fillCircle", "x": 250, "y": 150, "radius": 60 }
    ]
  }
}
```

---

### 🌍 3D Scene Widgets

| Widget | Aliases | Description |
|--------|---------|-------------|
| `BevyScene` | `Bevy3D`, `Scene3D` | Bevy FFI or pure-Dart 3D renderer |
| `GameScene` | `Game3D` | Pure-Dart Canvas-based 3D renderer |

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `scene` / `sceneJson` | Map / String | null | Scene definition |
| `width` | double | null | Render width |
| `height` | double | null | Render height |
| `fps` | int | 60 | Target frames per second |
| `interactive` | bool | true | Enable touch/pointer events |
| `fit` | String | 'contain' | Box fit mode |
| `autoStart` | bool | true | Auto-start render loop |

See [3D_GRAPHICS.md](3D_GRAPHICS.md) for the complete 3D scene format.

---

## 🌐 HTML5 Elements

Elpian supports 76 HTML5 elements rendered as native Flutter widgets. All elements accept CSS styling.

### 🏛️ Structural Elements

| Element | Default Layout | Description |
|---------|---------------|-------------|
| `div` | Column/Row/Wrap | Generic container (supports flex layout) |
| `section` | Column | Semantic section |
| `article` | Column | Article content |
| `aside` | Column | Sidebar content |
| `header` | Column (full width) | Page/section header |
| `footer` | Column (full width) | Page/section footer |
| `main` | Column | Main content area |
| `nav` | Row (space-around) | Navigation bar |
| `figure` | Column | Illustration container |
| `form` | Column | Form container |

All structural elements support flex layout properties: `display`, `flexDirection`, `flexWrap`, `gap`, `rowGap`, `justifyContent`, `alignItems`.

```json
{
  "type": "div",
  "style": {
    "display": "flex",
    "flexDirection": "row",
    "gap": "12",
    "justifyContent": "center",
    "alignItems": "center",
    "padding": "16",
    "backgroundColor": "#f0f0f0"
  },
  "children": [...]
}
```

---

### 🔤 Text Elements

#### Headings (h1–h6)

| Element | Default Font Size | Default Margin |
|---------|------------------|----------------|
| `h1` | 32px | vertical 16px |
| `h2` | 28px | vertical 14px |
| `h3` | 24px | vertical 12px |
| `h4` | 20px | vertical 10px |
| `h5` | 16px | vertical 8px |
| `h6` | 14px | vertical 6px |

All headings default to **bold** weight and accept `text`, `color`, `fontSize`, `fontWeight`, `fontFamily`, `letterSpacing`, `lineHeight`, `textAlign`, `textDecoration`.

```json
{ "type": "h1", "props": { "text": "Page Title" }, "style": { "color": "#1a1a1a" } }
```

---

#### Paragraph and Inline Text

| Element | Default Styling | Description |
|---------|----------------|-------------|
| `p` | margin: vertical 8px | Paragraph text |
| `span` | — | Inline text wrapper |
| `strong` | fontWeight: bold | Bold emphasis |
| `em` | fontStyle: italic | Italic emphasis |
| `a` | color: blue, underline | Hyperlink (`href` prop) |
| `code` | monospace, #F5F5F5 bg | Code snippet |
| `kbd` | monospace, #EEE bg, radius 3 | Keyboard input |
| `samp` | monospace | Sample output |
| `var` | italic | Variable name |
| `mark` | yellow background | Highlighted text |
| `small` | fontSize: 12 | Smaller text |
| `sub` | fontSize: 10 | Subscript |
| `sup` | fontSize: 10 | Superscript |
| `del` | lineThrough decoration | Deleted text |
| `ins` | underline decoration | Inserted text |
| `cite` | italic | Citation |
| `abbr` | underline + tooltip (`title` prop) | Abbreviation |
| `data` | — | Machine-readable data |
| `time` | — | Time/date display |

```json
{
  "type": "p",
  "props": { "text": "This is a paragraph with " },
  "children": [
    { "type": "strong", "props": { "text": "bold" } },
    { "type": "span", "props": { "text": " and " } },
    { "type": "em", "props": { "text": "italic" } },
    { "type": "span", "props": { "text": " text." } }
  ]
}
```

---

#### Block Text

| Element | Description |
|---------|-------------|
| `blockquote` | Block quote with left border (padding 16, margin vertical 8, 4px grey left border) |
| `pre` | Preformatted text (monospace, preserves whitespace) |

---

### 📋 List Elements

| Element | Description |
|---------|-------------|
| `ul` | Unordered list (Column) |
| `ol` | Ordered list with auto-numbering (1, 2, 3...) |
| `li` | List item with bullet point (•) |

```json
{
  "type": "ul",
  "children": [
    { "type": "li", "props": { "text": "First item" } },
    { "type": "li", "props": { "text": "Second item" } },
    { "type": "li", "props": { "text": "Third item" } }
  ]
}
```

---

### 📊 Table Elements

| Element | Description |
|---------|-------------|
| `table` | Table layout with borders |
| `tr` | Table row |
| `td` | Table data cell (padding: 8) |
| `th` | Table header cell (padding: 8, bold) |

```json
{
  "type": "table",
  "children": [
    { "type": "tr", "children": [
      { "type": "th", "props": { "text": "Name" } },
      { "type": "th", "props": { "text": "Age" } }
    ]},
    { "type": "tr", "children": [
      { "type": "td", "props": { "text": "Alice" } },
      { "type": "td", "props": { "text": "30" } }
    ]}
  ]
}
```

---

### 📝 Form Elements

| Element | Key Properties | Description |
|---------|---------------|-------------|
| `input` | `type` ('text'/'checkbox'/'radio'), `placeholder` | Input field |
| `textarea` | `placeholder` | Multi-line text (maxLines: 5) |
| `button` | `text` (default: 'Button') | Form button |
| `select` | — | Dropdown selector |
| `option` | `text` | Select option |
| `optgroup` | `label` | Option group with bold label |
| `label` | `text` | Form label (fontWeight: w500) |
| `fieldset` | — | Group with border (padding 16, grey border, radius 4) |
| `legend` | `text` | Fieldset title (bold) |
| `output` | `text` | Output display (padding 8, grey border, radius 4) |
| `datalist` | — | Hidden suggestion list |

```json
{
  "type": "form",
  "children": [
    { "type": "label", "props": { "text": "Email" } },
    { "type": "input", "props": { "type": "text", "placeholder": "you@example.com" } },
    { "type": "label", "props": { "text": "Message" } },
    { "type": "textarea", "props": { "placeholder": "Type here..." } },
    { "type": "button", "props": { "text": "Send" } }
  ]
}
```

---

### 🖼️ Media Elements

| Element | Key Properties | Description |
|---------|---------------|-------------|
| `img` | `src`, `alt` | Image (network or asset) |
| `picture` | — | Responsive image container |
| `video` | — | Video placeholder (black bg with play icon) |
| `audio` | — | Audio placeholder (play icon + progress bar) |
| `canvas` | — | Canvas drawing area (white bg) |
| `iframe` | `src` | Embedded frame placeholder |
| `embed` | `src` | Embedded content placeholder |
| `object` | `data` | Embedded object placeholder |
| `source` | — | Hidden media source metadata |
| `track` | — | Hidden text track metadata |
| `param` | — | Hidden object parameter |

---

### 🔽 Interactive Elements

| Element | Description |
|---------|-------------|
| `details` | Expandable disclosure widget (ExpansionTile) |
| `summary` | Details summary heading (bold) |
| `dialog` | Modal dialog (padding 16) |

---

### 📈 Progress Elements

| Element | Key Properties | Description |
|---------|---------------|-------------|
| `progress` | `value`, `max` (default: 1.0) | Linear progress bar |
| `meter` | `value`, `min` (0), `max` (1.0) | Measurement gauge (green) |

---

### ➖ Break Elements

| Element | Description |
|---------|-------------|
| `br` | Line break (16px vertical space) |
| `hr` | Horizontal rule (Divider) |

---

### Remaining HTML Elements

| Element | Description |
|---------|-------------|
| `figcaption` | Figure caption (italic, grey, 14px) |
| `map` | Image map container |
| `area` | Image map clickable region |

---

## 🎛️ CSS Properties Reference

Elpian's CSS engine supports 150+ properties. Properties can be written in `camelCase` or `kebab-case`.

### 📏 Layout & Sizing

| Property | Values | Description |
|----------|--------|-------------|
| `width` | number | Element width |
| `height` | number | Element height |
| `min-width` / `minWidth` | number | Minimum width |
| `max-width` / `maxWidth` | number | Maximum width |
| `min-height` / `minHeight` | number | Minimum height |
| `max-height` / `maxHeight` | number | Maximum height |
| `padding` | number / "t r b l" | Inner spacing |
| `margin` | number / "t r b l" | Outer spacing |
| `display` | 'flex', 'grid', 'inline-flex' | Display mode |
| `position` | 'relative', 'absolute' | Positioning mode |
| `top`, `right`, `bottom`, `left` | number | Position offsets |
| `z-index` / `zIndex` | number | Stacking order |
| `overflow` | 'hidden', 'visible', 'scroll' | Content overflow |
| `alignment` | 'center', 'topLeft', 'bottomRight', etc. | Widget alignment |

### 📐 Flexbox

| Property | Values | Description |
|----------|--------|-------------|
| `flex-direction` / `flexDirection` | 'row', 'column', 'row-reverse', 'column-reverse' | Layout direction |
| `justify-content` / `justifyContent` | 'flex-start', 'flex-end', 'center', 'space-between', 'space-around', 'space-evenly' | Main axis alignment |
| `align-items` / `alignItems` | 'flex-start', 'flex-end', 'center', 'stretch' | Cross axis alignment |
| `flex-wrap` / `flexWrap` | 'wrap', 'wrap-reverse', 'nowrap' | Wrap behavior |
| `gap` | number | Space between items |
| `flex` | number | Flex grow factor |

### 🔠 Typography

| Property | Values | Description |
|----------|--------|-------------|
| `color` | color string | Text color |
| `font-size` / `fontSize` | number | Font size in pixels |
| `font-weight` / `fontWeight` | 'bold', 'normal', '100'–'900', 'w100'–'w900' | Font weight |
| `font-style` / `fontStyle` | 'italic', 'normal' | Font style |
| `font-family` / `fontFamily` | string | Font family name |
| `letter-spacing` / `letterSpacing` | number | Character spacing |
| `word-spacing` / `wordSpacing` | number | Word spacing |
| `line-height` / `lineHeight` | number | Line height |
| `text-align` / `textAlign` | 'left', 'right', 'center', 'justify', 'start', 'end' | Text alignment |
| `text-decoration` / `textDecoration` | 'underline', 'overline', 'linethrough', 'none' | Text decoration |
| `text-overflow` / `textOverflow` | 'ellipsis', 'clip', 'fade', 'visible' | Overflow behavior |
| `text-transform` / `textTransform` | string | Text transformation |
| `text-shadow` / `textShadow` | shadow value | Text shadow |

### 🖌️ Background & Borders

| Property | Values | Description |
|----------|--------|-------------|
| `background-color` / `backgroundColor` | color | Background color |
| `background-image` / `backgroundImage` | URL string | Background image |
| `background-size` / `backgroundSize` | 'fill', 'contain', 'cover', 'fitWidth', 'fitHeight', 'none', 'scaleDown' | Image scaling |
| `background-position` / `backgroundPosition` | alignment string | Image position |
| `gradient` | gradient definition | Linear/radial/sweep gradient |
| `border` | border shorthand | Border styling |
| `border-color` / `borderColor` | color | Border color |
| `border-width` / `borderWidth` | number | Border width |
| `border-style` / `borderStyle` | 'solid', 'none' | Border style |
| `border-radius` / `borderRadius` | number | Corner rounding |
| `box-shadow` / `boxShadow` | shadow values | Box shadow |

### ✨ Visual Effects

| Property | Values | Description |
|----------|--------|-------------|
| `opacity` | 0.0–1.0 | Element transparency |
| `visible` | bool | Visibility |
| `cursor` | string | Cursor style |
| `pointer-events` / `pointerEvents` | string | Pointer event behavior |

### 🔄 Transforms

| Property | Values | Description |
|----------|--------|-------------|
| `rotate` | degrees | Rotation |
| `scale` | number | Uniform scale |
| `translate` | `{x, y}` | 2D translation |
| `transform` | 16-element array | Full Matrix4 transform |

### 🎨 Color Formats

Elpian supports multiple color formats:

```
#RRGGBB           → "#2196F3"
#RRGGBBAA          → "#2196F380"
rgb(r, g, b)       → "rgb(33, 150, 243)"
rgba(r, g, b, a)   → "rgba(33, 150, 243, 0.5)"
hsl(h, s%, l%)     → "hsl(207, 90%, 54%)"
hsla(h, s%, l%, a) → "hsla(207, 90%, 54%, 0.5)"
named              → "red", "blue", "transparent", "deepPurple", etc.
```

**Named colors:** transparent, black, white, red, green, blue, yellow, orange, purple, pink, grey, gray, brown, cyan, indigo, lime, teal, amber, deepOrange, deepPurple, lightBlue, lightGreen, blueGrey.

---

## ✏️ Canvas 2D API

The Canvas widget accepts drawing commands as a JSON array. Each command has a `command` field and command-specific parameters.

### Path Commands

| Command | Parameters | Description |
|---------|-----------|-------------|
| `beginPath` | — | Start a new path |
| `moveTo` | `x`, `y` | Move to point |
| `lineTo` | `x`, `y` | Line to point |
| `quadraticCurveTo` | `cpx`, `cpy`, `x`, `y` | Quadratic Bezier curve |
| `bezierCurveTo` | `cp1x`, `cp1y`, `cp2x`, `cp2y`, `x`, `y` | Cubic Bezier curve |
| `arc` | `x`, `y`, `radius`, `startAngle`, `endAngle`, `counterclockwise` | Arc |
| `arcTo` | `x`, `y`, `radius` | Arc to point |
| `ellipse` | `x`, `y`, `radiusX`, `radiusY` | Ellipse |
| `rect` | `x`, `y`, `width`, `height` | Rectangle path |
| `roundRect` | `x`, `y`, `width`, `height`, `radius` | Rounded rectangle path |
| `circle` | `x`, `y`, `radius` | Circle path |
| `closePath` | — | Close current path |
| `fill` | — | Fill current path |
| `stroke` | — | Stroke current path |
| `clip` | — | Clip to current path |

### Shape Commands

| Command | Parameters | Description |
|---------|-----------|-------------|
| `fillRect` | `x`, `y`, `width`, `height` | Filled rectangle |
| `strokeRect` | `x`, `y`, `width`, `height` | Rectangle outline |
| `clearRect` | `x`, `y`, `width`, `height` | Clear rectangular area |
| `fillCircle` | `x`, `y`, `radius` | Filled circle |
| `strokeCircle` | `x`, `y`, `radius` | Circle outline |
| `fillPolygon` | `points` (array) | Filled polygon |
| `strokePolygon` | `points` (array) | Polygon outline |

### Text Commands

| Command | Parameters | Description |
|---------|-----------|-------------|
| `fillText` | `text`, `x`, `y` | Filled text |
| `strokeText` | `text`, `x`, `y` | Text outline |
| `setFont` | `fontString` (e.g. "16px Arial") | Set font |
| `setTextAlign` | `align` | Set text alignment |
| `setTextBaseline` | `baseline` | Set text baseline |

### Style Commands

| Command | Parameters | Description |
|---------|-----------|-------------|
| `setFillStyle` | `color` or `gradientId` | Set fill color/gradient |
| `setStrokeStyle` | `color` or `gradientId` | Set stroke color/gradient |
| `setLineWidth` | `width` | Set line thickness |
| `setLineCap` | `cap` ('butt', 'round', 'square') | Line cap style |
| `setLineJoin` | `join` ('miter', 'round', 'bevel') | Line join style |
| `setMiterLimit` | `limit` | Miter limit |
| `setLineDash` | `dashArray` (list of numbers) | Dash pattern |
| `setLineDashOffset` | `offset` | Dash offset |
| `setGlobalAlpha` | `alpha` (0.0–1.0) | Global opacity |
| `setGlobalCompositeOperation` | `mode` | Blend mode |

### Shadow Commands

| Command | Parameters | Description |
|---------|-----------|-------------|
| `setShadowBlur` | `blur` | Shadow blur radius |
| `setShadowColor` | `color` | Shadow color |
| `setShadowOffsetX` | `offsetX` | Shadow X offset |
| `setShadowOffsetY` | `offsetY` | Shadow Y offset |

### Gradient Commands

| Command | Parameters | Description |
|---------|-----------|-------------|
| `createLinearGradient` | `id`, `x0`, `y0`, `x1`, `y1`, `colors`, `stops` | Create linear gradient |
| `createRadialGradient` | `id`, `x`, `y`, `r`, `colors`, `stops` | Create radial gradient |
| `addColorStop` | `gradientId`, `offset`, `color` | Add color stop to gradient |

### Transform Commands

| Command | Parameters | Description |
|---------|-----------|-------------|
| `save` | — | Save graphics state |
| `restore` | — | Restore graphics state |
| `translate` | `x`, `y` | Translate origin |
| `rotate` | `angle` | Rotate (radians) |
| `scale` | `x`, `y` | Scale axes |
| `transform` | — | Apply custom transform |
| `setTransform` | — | Set transform matrix |
| `resetTransform` | — | Reset to identity |

### Canvas Example

```json
{
  "type": "Canvas",
  "props": {
    "width": 400,
    "height": 300,
    "commands": [
      { "command": "save" },
      { "command": "createLinearGradient", "id": "sky", "x0": 0, "y0": 0, "x1": 0, "y1": 300,
        "colors": ["#87CEEB", "#E0F0FF"], "stops": [0, 1] },
      { "command": "setFillStyle", "gradientId": "sky" },
      { "command": "fillRect", "x": 0, "y": 0, "width": 400, "height": 300 },

      { "command": "setFillStyle", "color": "#228B22" },
      { "command": "fillRect", "x": 0, "y": 200, "width": 400, "height": 100 },

      { "command": "setFillStyle", "color": "#FFD700" },
      { "command": "fillCircle", "x": 320, "y": 60, "radius": 40 },

      { "command": "setFillStyle", "color": "#8B4513" },
      { "command": "fillRect", "x": 170, "y": 130, "width": 20, "height": 70 },
      { "command": "setFillStyle", "color": "#2E8B57" },
      { "command": "fillCircle", "x": 180, "y": 120, "radius": 35 },

      { "command": "restore" }
    ]
  }
}
```

---

## 🎬 Animation Widgets

Elpian includes 22 animation widgets grouped into three categories.

### 🔀 Implicit Animations

These animate automatically when their style properties change.

| Widget | Key CSS Properties | Default Duration | Description |
|--------|-------------------|-----------------|-------------|
| `AnimatedContainer` | `width`, `height`, `padding`, `margin`, `backgroundColor`, `borderRadius` | 200ms | Animated container |
| `AnimatedOpacity` | `opacity` | 200ms | Animated opacity |
| `AnimatedAlign` | `alignment`, `alignmentEnd` | 300ms | Animated alignment |
| `AnimatedPadding` | `padding` | 300ms | Animated padding |
| `AnimatedPositioned` | `top`, `right`, `bottom`, `left`, `width`, `height` | 300ms | Animated position |
| `AnimatedScale` | `scale` | 300ms | Animated scale |
| `AnimatedRotation` | `rotate` | 300ms | Animated rotation |
| `AnimatedSlide` | `slideEnd` | 300ms | Animated slide |
| `AnimatedSize` | — | 300ms | Animated size changes |
| `AnimatedDefaultTextStyle` | text style properties | 300ms | Animated text style |
| `AnimatedCrossFade` | `showFirst` (bool, default: true) | 300ms | Cross-fade between two children |
| `AnimatedSwitcher` | `transitionType` ('fade', 'scale', 'rotation', 'slide') | 300ms | Animated child switching |

**Common CSS properties for implicit animations:**
- `transition-duration` / `transitionDuration` — Duration in ms or s
- `transition-curve` / `transitionCurve` — Easing function

### 🎯 Explicit Transitions

Controller-based animations that play on build.

| Widget | Key CSS Properties | Default | Description |
|--------|-------------------|---------|-------------|
| `FadeTransition` | `fadeBegin`, `fadeEnd` | 0.0 → 1.0 | Fade in/out |
| `SlideTransition` | `slideBegin`, `slideEnd` | (-1,0) → (0,0) | Slide in/out |
| `ScaleTransition` | `scaleBegin`, `scaleEnd` | 0.0 → 1.0 | Scale in/out |
| `RotationTransition` | `rotationBegin`, `rotationEnd` | 0.0 → 1.0 | Rotation |
| `SizeTransition` | `axis` ('horizontal'/'vertical') | 0.0 → 1.0 | Size reveal |

**Common CSS properties for explicit animations:**
- `animation-duration` / `animationDuration` — Duration
- `transition-curve` / `transitionCurve` — Easing
- `animation-repeat` / `animationRepeat` — Loop (boolean)
- `animation-auto-reverse` / `animationAutoReverse` — Reverse on complete

### 🌊 Custom Animations

| Widget | Key CSS Properties | Default Duration | Description |
|--------|-------------------|-----------------|-------------|
| `TweenAnimationBuilder` | `tweenType` ('opacity', 'scale', 'rotation', 'translateX', 'translateY') | 300ms | Tween-based animation |
| `StaggeredAnimation` | `staggerDelay` (default: 100ms) | 1000ms | Staggered child fade-in + slide |
| `Shimmer` | `shimmerBaseColor`, `shimmerHighlightColor` | 1500ms | Loading shimmer effect |
| `Pulse` | `scaleBegin`, `scaleEnd` | 1000ms | Repeating pulse (1.0 → 1.05) |
| `AnimatedGradient` | `gradientColors` | 2000ms | Animated gradient background |

### 📉 Supported Easing Curves

```
linear, ease, easeIn, easeOut, easeInOut,
bounce, bounceIn, bounceOut, bounceInOut,
elastic, elasticIn, elasticOut, elasticInOut,
decelerate, fastOutSlowIn, slowMiddle,
easeInCubic, easeOutCubic, easeInOutCubic,
easeInQuart, easeOutQuart, easeInOutQuart,
easeInQuint, easeOutQuint, easeInOutQuint,
easeInExpo, easeOutExpo, easeInOutExpo,
easeInCirc, easeOutCirc, easeInOutCirc,
easeInBack, easeOutBack, easeInOutBack
```

---

## 📦 Complete Examples

### Responsive Card Layout

```json
{
  "type": "Column",
  "style": { "padding": "16", "gap": "16", "alignItems": "center" },
  "children": [
    {
      "type": "h1",
      "props": { "text": "Dashboard" },
      "style": { "color": "#1a1a1a" }
    },
    {
      "type": "Row",
      "style": { "gap": "16", "flexWrap": "wrap", "justifyContent": "center" },
      "children": [
        {
          "type": "Card",
          "props": { "elevation": 2 },
          "style": { "width": "200", "padding": "16", "borderRadius": "12" },
          "children": [
            { "type": "Icon", "props": { "icon": "person", "size": 48 }, "style": { "color": "#2196F3" } },
            { "type": "Text", "props": { "data": "Users" }, "style": { "fontSize": "14", "color": "#666" } },
            { "type": "Text", "props": { "data": "1,234" }, "style": { "fontSize": "24", "fontWeight": "bold" } }
          ]
        },
        {
          "type": "Card",
          "props": { "elevation": 2 },
          "style": { "width": "200", "padding": "16", "borderRadius": "12" },
          "children": [
            { "type": "Icon", "props": { "icon": "shopping_cart", "size": 48 }, "style": { "color": "#4CAF50" } },
            { "type": "Text", "props": { "data": "Orders" }, "style": { "fontSize": "14", "color": "#666" } },
            { "type": "Text", "props": { "data": "567" }, "style": { "fontSize": "24", "fontWeight": "bold" } }
          ]
        }
      ]
    }
  ]
}
```

### HTML5 Article Page

```json
{
  "type": "article",
  "style": { "padding": "24", "maxWidth": "800" },
  "children": [
    { "type": "h1", "props": { "text": "Getting Started with Elpian" } },
    {
      "type": "p",
      "children": [
        { "type": "span", "props": { "text": "Elpian is a " } },
        { "type": "strong", "props": { "text": "high-performance UI engine" } },
        { "type": "span", "props": { "text": " that renders " } },
        { "type": "em", "props": { "text": "JSON definitions" } },
        { "type": "span", "props": { "text": " as native Flutter widgets." } }
      ]
    },
    { "type": "h2", "props": { "text": "Features" } },
    {
      "type": "ul",
      "children": [
        { "type": "li", "props": { "text": "60+ Flutter DSL widgets" } },
        { "type": "li", "props": { "text": "76 HTML5 elements" } },
        { "type": "li", "props": { "text": "150+ CSS properties" } },
        { "type": "li", "props": { "text": "Canvas 2D drawing API" } }
      ]
    },
    { "type": "h2", "props": { "text": "Example Code" } },
    {
      "type": "pre",
      "children": [
        { "type": "code", "props": { "text": "engine.render({\"type\": \"Text\", \"props\": {\"data\": \"Hello!\"}});" } }
      ]
    },
    { "type": "hr" },
    {
      "type": "blockquote",
      "props": { "text": "Elpian enables server-driven UI with full CSS styling support." }
    }
  ]
}
```

### Form with Validation

```json
{
  "type": "Card",
  "props": { "elevation": 4 },
  "style": { "padding": "24", "borderRadius": "16", "maxWidth": "400" },
  "children": [
    { "type": "h2", "props": { "text": "Sign Up" }, "style": { "textAlign": "center" } },
    {
      "type": "Column",
      "style": { "gap": "12" },
      "children": [
        { "type": "label", "props": { "text": "Full Name" } },
        { "type": "TextField", "props": { "hint": "John Doe" } },
        { "type": "label", "props": { "text": "Email" } },
        { "type": "TextField", "props": { "hint": "john@example.com" } },
        { "type": "SizedBox", "style": { "height": "8" } },
        {
          "type": "Row",
          "style": { "gap": "8", "alignItems": "center" },
          "children": [
            { "type": "Checkbox", "props": { "value": false } },
            { "type": "Text", "props": { "data": "I agree to the terms" } }
          ]
        },
        {
          "type": "Button",
          "props": { "text": "Create Account" },
          "style": {
            "backgroundColor": "#6200EE",
            "color": "white",
            "padding": "14 0",
            "borderRadius": "8",
            "width": "1000"
          }
        }
      ]
    }
  ]
}
```

---

## 📊 Widget Summary Table

### Flutter DSL Widgets (81 types)

| Category | Widgets |
|----------|---------|
| **Layout** | Container, Column, Row, Stack, Positioned, Expanded, Flexible, Center, Padding, Align, SizedBox, Wrap, ListView, GridView, AspectRatio, FractionallySizedBox, FittedBox, ConstrainedBox, LimitedBox, OverflowBox, Baseline, IndexedStack, RotatedBox, Spacer |
| **Content** | Text, Image, Icon |
| **Input** | Button, TextField, Checkbox, Radio, Switch, Slider |
| **Structure** | Scaffold, AppBar, Card |
| **Feedback** | Tooltip, Badge, Chip, Divider, VerticalDivider, CircularProgressIndicator, LinearProgressIndicator |
| **Interaction** | InkWell, GestureDetector, Dismissible, Draggable, DragTarget, Hero |
| **Visual** | Opacity, Transform, ClipRRect, DecoratedBox |
| **Animation (Implicit)** | AnimatedContainer, AnimatedOpacity, AnimatedCrossFade, AnimatedSwitcher, AnimatedAlign, AnimatedPadding, AnimatedPositioned, AnimatedScale, AnimatedRotation, AnimatedSlide, AnimatedSize, AnimatedDefaultTextStyle |
| **Animation (Explicit)** | FadeTransition, SlideTransition, ScaleTransition, RotationTransition, SizeTransition |
| **Animation (Custom)** | TweenAnimationBuilder, StaggeredAnimation, Shimmer, Pulse, AnimatedGradient |
| **Canvas** | Canvas |
| **3D** | BevyScene (Bevy3D, Scene3D), GameScene (Game3D) |

### HTML5 Elements (76 types)

| Category | Elements |
|----------|----------|
| **Structural** | div, section, article, aside, header, footer, main, nav, figure, form |
| **Headings** | h1, h2, h3, h4, h5, h6 |
| **Text** | p, span, strong, em, a, code, kbd, samp, var, mark, small, sub, sup, del, ins, cite, abbr, data, time |
| **Block** | blockquote, pre |
| **List** | ul, ol, li |
| **Table** | table, tr, td, th |
| **Form** | input, textarea, button, select, option, optgroup, label, fieldset, legend, output, datalist |
| **Media** | img, picture, video, audio, canvas, iframe, embed, object, source, track, param |
| **Interactive** | details, summary, dialog |
| **Progress** | progress, meter |
| **Break** | br, hr |
| **Other** | figcaption, map, area |
