# Elpian 2D Graphics Reference

Complete reference for Elpian's 2D UI element system. All elements are defined in JSON and rendered via Bevy (Rust/desktop) or Flutter (Dart/mobile).

## Scene Structure

A scene JSON has two top-level arrays — `ui` for 2D elements and `world` for 3D elements:

```json
{
  "ui": [ /* 2D UI nodes */ ],
  "world": [ /* 3D world nodes */ ]
}
```

Each UI node is a tagged JSON object with a `"type"` field that determines the element kind.

---

## Core UI Elements

### container

Basic layout container for grouping child elements.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `style` | StyleDef | {} | Layout and visual styling |
| `children` | JsonNode[] | [] | Child elements |
| `background_color` | ColorDef? | null | Background fill color |

```json
{
  "type": "container",
  "background_color": {"r": 0.95, "g": 0.95, "b": 0.95, "a": 1.0},
  "style": {
    "flex_direction": "Column",
    "justify_content": "Center",
    "align_items": "Center",
    "width": 300.0,
    "height": 200.0,
    "padding": {"top": 16, "right": 16, "bottom": 16, "left": 16}
  },
  "children": []
}
```

**Bevy mapping:** `Node` + `BackgroundColor`

---

### text

Display text content.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `text` | String | *required* | Text content to display |
| `style` | StyleDef | {} | Layout styling |
| `font_size` | f32? | null | Font size in pixels |
| `color` | ColorDef? | null | Text color |

```json
{
  "type": "text",
  "text": "Hello, Elpian!",
  "font_size": 24.0,
  "color": {"r": 0.1, "g": 0.1, "b": 0.1, "a": 1.0}
}
```

**Bevy mapping:** `Text` + `TextFont` + `TextColor`

---

### button

Interactive clickable button.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `label` | String | *required* | Button text |
| `style` | StyleDef | {} | Layout styling |
| `action` | String? | null | Callback identifier |
| `normal_color` | ColorDef? | null | Default background color |
| `hover_color` | ColorDef? | null | Background on hover |
| `pressed_color` | ColorDef? | null | Background when pressed |
| `glass` | bool | false | Enable glass morphism effect |
| `glass_opacity` | f32 | 0.0 | Glass effect opacity |

```json
{
  "type": "button",
  "label": "Click Me",
  "action": "on_click_handler",
  "normal_color": {"r": 0.2, "g": 0.6, "b": 1.0, "a": 1.0},
  "glass": true,
  "glass_opacity": 0.2
}
```

**Bevy mapping:** `Button` + `RoundedBackground` + `Elevation`

---

### image

Display an image asset.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `path` | String | *required* | Asset file path |
| `style` | StyleDef | {} | Layout styling |

```json
{
  "type": "image",
  "path": "assets/logo.png"
}
```

**Bevy mapping:** `ImageNode`

---

### slider

Range selection input.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `min` | f32 | 0.0 | Minimum value |
| `max` | f32 | 100.0 | Maximum value |
| `value` | f32 | 0.0 | Current value |
| `style` | StyleDef | {} | Layout styling |
| `on_change` | String? | null | Change callback identifier |

```json
{
  "type": "slider",
  "min": 0.0,
  "max": 100.0,
  "value": 50.0,
  "on_change": "on_volume_change"
}
```

**Bevy mapping:** `Slider` + `SliderHandle`

---

### checkbox

Boolean toggle input.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `label` | String | *required* | Checkbox label text |
| `checked` | bool | false | Initial checked state |
| `style` | StyleDef | {} | Layout styling |
| `on_change` | String? | null | Change callback identifier |

```json
{
  "type": "checkbox",
  "label": "Accept terms",
  "checked": false,
  "on_change": "on_terms_toggle"
}
```

**Bevy mapping:** `Checkbox` + `Button` + `Text`

---

### radio

Mutually exclusive selection option.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `label` | String | *required* | Radio button label |
| `group` | String | *required* | Group identifier for mutual exclusion |
| `checked` | bool | false | Initial selected state |
| `style` | StyleDef | {} | Layout styling |
| `on_change` | String? | null | Change callback identifier |

```json
{
  "type": "radio",
  "label": "Option A",
  "group": "my_group",
  "checked": true
}
```

**Bevy mapping:** `RadioButton` + `Button` + `Text`

---

### textinput

Text field for user input.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `placeholder` | String | "" | Placeholder text |
| `value` | String | "" | Initial text value |
| `style` | StyleDef | {} | Layout styling |
| `on_change` | String? | null | Change callback identifier |

```json
{
  "type": "textinput",
  "placeholder": "Enter your name...",
  "value": "",
  "on_change": "on_name_input"
}
```

**Bevy mapping:** `TextInputComponent` + `Text`

---

### progressbar

Visual progress indicator.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `value` | f32 | 0.0 | Current progress |
| `max` | f32 | 100.0 | Maximum value |
| `style` | StyleDef | {} | Layout styling |
| `bar_color` | ColorDef? | null | Progress bar fill color |
| `background_color` | ColorDef? | null | Background track color |

```json
{
  "type": "progressbar",
  "value": 65.0,
  "max": 100.0,
  "bar_color": {"r": 0.2, "g": 0.8, "b": 0.4, "a": 1.0}
}
```

**Bevy mapping:** `ProgressBarComponent` + `ProgressBarFill`

---

## Material Design Components

### fab

Floating Action Button — primary action button with elevation.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `icon` | String | *required* | Icon identifier |
| `action` | String? | null | Click callback |
| `style` | StyleDef | {} | Layout styling |
| `fab_type` | FABType | FAB | Size variant: `Small`, `FAB`, `ExtendedFAB`, `Large` |
| `color` | ColorDef? | null | Background color |
| `elevation` | u32 | 0 | Material elevation level |
| `glass` | bool | false | Glass morphism effect |
| `glass_opacity` | f32 | 0.0 | Glass opacity |

```json
{
  "type": "fab",
  "icon": "add",
  "fab_type": "Large",
  "color": {"r": 0.4, "g": 0.2, "b": 0.8, "a": 1.0},
  "elevation": 3
}
```

**Bevy mapping:** `FloatingActionButton` + `Button` + `RoundedBackground` + `Elevation`

---

### card

Elevated content container with rounded corners and shadow.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `children` | JsonNode[] | [] | Card content elements |
| `style` | StyleDef | {} | Layout styling |
| `elevation` | u32 | 1 | Shadow elevation level |
| `corner_radius` | f32 | 12.0 | Border radius in pixels |
| `background_color` | ColorDef? | null | Card background |
| `on_click` | String? | null | Click callback |
| `outlined` | bool | false | Use outlined style instead of elevated |
| `glass` | bool | false | Glass morphism effect |
| `glass_opacity` | f32 | 0.12 | Glass opacity |

```json
{
  "type": "card",
  "elevation": 2,
  "corner_radius": 16.0,
  "background_color": {"r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0},
  "children": [
    {"type": "text", "text": "Card Title", "font_size": 18.0},
    {"type": "text", "text": "Card body content goes here."}
  ]
}
```

**Bevy mapping:** `Card` + `RoundedBackground` + `Elevation`

---

### chip

Compact labeled button for filters, input, or suggestions.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `label` | String | *required* | Chip text |
| `style` | StyleDef | {} | Layout styling |
| `chip_type` | ChipType | Assist | Variant: `Input`, `Filter`, `Suggestion`, `Assist` |
| `icon` | String? | null | Leading icon |
| `selected` | bool | false | Selected state |
| `color` | ColorDef? | null | Chip color |
| `on_click` | String? | null | Click callback |

```json
{
  "type": "chip",
  "label": "Technology",
  "chip_type": "Filter",
  "selected": true
}
```

**Bevy mapping:** `Chip` + `Button` + `Text`

---

### appbar

Top navigation bar.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `title` | String | *required* | Bar title text |
| `style` | StyleDef | {} | Layout styling |
| `app_bar_type` | AppBarType | Center | Variant: `Center`, `Small`, `Medium`, `Large` |
| `navigation_icon` | String? | null | Leading icon (e.g. menu/back) |
| `actions` | AppBarAction[] | [] | Trailing action buttons |
| `background_color` | ColorDef? | null | Bar background |
| `elevation` | u32 | 0 | Shadow elevation |
| `glass` | bool | false | Glass morphism effect |
| `glass_opacity` | f32 | 0.0 | Glass opacity |

**AppBarAction:**

| Property | Type | Description |
|---|---|---|
| `icon` | String | Action icon identifier |
| `tooltip` | String | Hover tooltip text |
| `action` | String? | Click callback |

```json
{
  "type": "appbar",
  "title": "My App",
  "app_bar_type": "Center",
  "background_color": {"r": 0.2, "g": 0.5, "b": 1.0, "a": 1.0},
  "navigation_icon": "menu",
  "actions": [
    {"icon": "search", "tooltip": "Search", "action": "on_search"},
    {"icon": "settings", "tooltip": "Settings"}
  ]
}
```

**Bevy mapping:** `AppBar` + `RoundedBackground` + `Text` + `Elevation`

---

### dialog

Modal dialog container.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `title` | String | *required* | Dialog title |
| `content` | JsonNode[] | [] | Dialog body elements |
| `actions` | DialogAction[] | [] | Action buttons |
| `style` | StyleDef | {} | Layout styling |
| `dismissible` | bool | false | Allow dismissing by tapping outside |
| `glass` | bool | false | Glass morphism background |
| `glass_opacity` | f32 | 0.0 | Glass opacity |

**DialogAction:**

| Property | Type | Description |
|---|---|---|
| `label` | String | Button text |
| `action` | String? | Click callback |
| `is_primary` | bool | Whether this is the primary action |

```json
{
  "type": "dialog",
  "title": "Confirm Action",
  "dismissible": true,
  "content": [
    {"type": "text", "text": "Are you sure you want to proceed?"}
  ],
  "actions": [
    {"label": "Cancel", "action": "on_cancel"},
    {"label": "Confirm", "action": "on_confirm", "is_primary": true}
  ]
}
```

**Bevy mapping:** `Dialog` + `RoundedBackground` + `Text`

---

### menu

Dropdown/popup menu.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `items` | MenuItem[] | [] | Menu items |
| `style` | StyleDef | {} | Layout styling |
| `elevation` | u32 | 0 | Shadow elevation |
| `glass` | bool | false | Glass morphism effect |
| `glass_opacity` | f32 | 0.0 | Glass opacity |

**MenuItem:**

| Property | Type | Description |
|---|---|---|
| `label` | String | Item text |
| `icon` | String? | Item icon |
| `action` | String? | Click callback |
| `sub_items` | MenuItem[] | Nested submenu items |

```json
{
  "type": "menu",
  "elevation": 2,
  "items": [
    {"label": "Cut", "icon": "cut", "action": "on_cut"},
    {"label": "Copy", "icon": "copy", "action": "on_copy"},
    {"label": "Paste", "icon": "paste", "action": "on_paste"},
    {"label": "More", "sub_items": [
      {"label": "Select All", "action": "on_select_all"}
    ]}
  ]
}
```

**Bevy mapping:** `Menu` + `RoundedBackground`

---

### bottomsheet

Modal content panel from the bottom of the screen.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `content` | JsonNode[] | [] | Sheet content elements |
| `style` | StyleDef | {} | Layout styling |
| `height` | f32? | null | Sheet height in pixels |
| `dismissible` | bool | false | Swipe to dismiss |

```json
{
  "type": "bottomsheet",
  "height": 300.0,
  "dismissible": true,
  "content": [
    {"type": "text", "text": "Bottom Sheet Title", "font_size": 20.0}
  ]
}
```

**Bevy mapping:** `BottomSheet` + `Node`

---

### snackbar

Brief notification message.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `message` | String | *required* | Notification text |
| `action` | String? | null | Action callback |
| `duration_ms` | u32 | 4000 | Display duration in milliseconds |
| `style` | StyleDef | {} | Layout styling |
| `glass` | bool | false | Glass morphism effect |
| `glass_opacity` | f32 | 0.35 | Glass opacity |

```json
{
  "type": "snackbar",
  "message": "Item deleted",
  "action": "on_undo",
  "duration_ms": 5000
}
```

**Bevy mapping:** `Snackbar` + `RoundedBackground` + `Text`

---

### switch

Toggle switch control.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `enabled` | bool | false | On/off state |
| `style` | StyleDef | {} | Layout styling |
| `on_change` | String? | null | Change callback |
| `icon_enabled` | String? | null | Icon shown when on |
| `icon_disabled` | String? | null | Icon shown when off |

```json
{
  "type": "switch",
  "enabled": true,
  "on_change": "on_dark_mode_toggle",
  "icon_enabled": "dark_mode",
  "icon_disabled": "light_mode"
}
```

**Bevy mapping:** `SwitchComponent` + `Button`

---

### tabs

Tabbed interface container.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `tabs` | TabItem[] | [] | Tab definitions |
| `style` | StyleDef | {} | Layout styling |
| `selected_index` | usize | 0 | Active tab index |
| `on_change` | String? | null | Tab change callback |
| `tab_type` | TabType | Fixed | `Fixed` or `Scrollable` |

**TabItem:**

| Property | Type | Description |
|---|---|---|
| `label` | String | Tab label text |
| `icon` | String? | Tab icon |
| `content` | JsonNode[] | Tab body content |
| `badge_count` | u32? | Optional badge number |

```json
{
  "type": "tabs",
  "tab_type": "Fixed",
  "selected_index": 0,
  "tabs": [
    {"label": "Home", "icon": "home", "content": [
      {"type": "text", "text": "Home tab content"}
    ]},
    {"label": "Profile", "icon": "person", "badge_count": 3, "content": [
      {"type": "text", "text": "Profile tab content"}
    ]}
  ]
}
```

**Bevy mapping:** `Tabs` + `Button` + children

---

### badge

Small count or label indicator.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `count` | u32? | null | Numeric badge value |
| `label` | String | *required* | Badge text |
| `style` | StyleDef | {} | Layout styling |
| `color` | ColorDef? | null | Badge color |

```json
{
  "type": "badge",
  "label": "New",
  "count": 5,
  "color": {"r": 1.0, "g": 0.0, "b": 0.0, "a": 1.0}
}
```

**Bevy mapping:** `Badge` + `Text`

---

### tooltip

Help text shown on hover.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `message` | String | *required* | Tooltip text |
| `position` | TooltipPosition | Top | `Top`, `Bottom`, `Left`, `Right` |
| `style` | StyleDef | {} | Layout styling |
| `glass` | bool | false | Glass morphism effect |
| `glass_opacity` | f32 | 0.0 | Glass opacity |

```json
{
  "type": "tooltip",
  "message": "Click to save your progress",
  "position": "Bottom"
}
```

**Bevy mapping:** `Tooltip` + `RoundedBackground` + `Text`

---

### rating

Star/icon rating input.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `value` | f32 | 0.0 | Current rating |
| `max` | u32 | 5 | Maximum rating |
| `style` | StyleDef | {} | Layout styling |
| `on_change` | String? | null | Change callback |
| `read_only` | bool | false | Display only (no interaction) |

```json
{
  "type": "rating",
  "value": 3.5,
  "max": 5,
  "read_only": true
}
```

**Bevy mapping:** `Rating` + `Node`

---

### segment

Segmented button group with single or multi-select.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `options` | SegmentOption[] | [] | Button options |
| `selected_index` | usize | 0 | Active option index |
| `style` | StyleDef | {} | Layout styling |
| `on_change` | String? | null | Change callback |
| `multiple_selection` | bool | false | Allow multiple selections |

**SegmentOption:**

| Property | Type | Description |
|---|---|---|
| `label` | String | Option text |
| `icon` | String? | Option icon |
| `selected` | bool | Selected state |

```json
{
  "type": "segment",
  "multiple_selection": false,
  "options": [
    {"label": "Day", "selected": true},
    {"label": "Week"},
    {"label": "Month"}
  ]
}
```

**Bevy mapping:** `SegmentedButton` + `Button`

---

### iconbutton

Icon-only button.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `icon` | String | *required* | Icon identifier |
| `style` | StyleDef | {} | Layout styling |
| `action` | String? | null | Click callback |
| `tooltip` | String? | null | Hover tooltip text |

```json
{
  "type": "iconbutton",
  "icon": "favorite",
  "action": "on_favorite",
  "tooltip": "Add to favorites"
}
```

**Bevy mapping:** `IconButton` + `Button`

---

### divider

Visual separator line.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `style` | StyleDef | {} | Layout styling |
| `thickness` | f32 | 0.0 | Line thickness in pixels |
| `color` | ColorDef? | null | Line color |

```json
{
  "type": "divider",
  "thickness": 1.0,
  "color": {"r": 0.8, "g": 0.8, "b": 0.8, "a": 1.0}
}
```

**Bevy mapping:** `Divider` + `Node`

---

### list

Vertical list container.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `items` | JsonNode[] | [] | List item elements |
| `style` | StyleDef | {} | Layout styling |

```json
{
  "type": "list",
  "items": [
    {"type": "text", "text": "Item 1"},
    {"type": "text", "text": "Item 2"},
    {"type": "text", "text": "Item 3"}
  ]
}
```

**Bevy mapping:** `ListComponent` + `Node`

---

### drawer

Side navigation drawer.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `content` | JsonNode[] | [] | Drawer content elements |
| `style` | StyleDef | {} | Layout styling |
| `open` | bool | false | Drawer visibility |
| `width` | f32? | null | Drawer width in pixels |

```json
{
  "type": "drawer",
  "open": true,
  "width": 280.0,
  "content": [
    {"type": "text", "text": "Navigation", "font_size": 20.0},
    {"type": "divider", "thickness": 1.0},
    {"type": "list", "items": [
      {"type": "text", "text": "Home"},
      {"type": "text", "text": "Settings"}
    ]}
  ]
}
```

**Bevy mapping:** `Drawer` + `Node`

---

## Style System (StyleDef)

All UI elements accept a `style` property with the following fields:

### Layout

| Property | Type | Description |
|---|---|---|
| `width` | DimensionDef? | Element width |
| `height` | DimensionDef? | Element height |
| `min_width` | DimensionDef? | Minimum width |
| `min_height` | DimensionDef? | Minimum height |
| `max_width` | DimensionDef? | Maximum width |
| `max_height` | DimensionDef? | Maximum height |

### Spacing

| Property | Type | Description |
|---|---|---|
| `padding` | RectDef? | Inner spacing `{top, right, bottom, left}` |
| `margin` | RectDef? | Outer spacing `{top, right, bottom, left}` |
| `border` | RectDef? | Border widths `{top, right, bottom, left}` |

### Flexbox

| Property | Type | Values |
|---|---|---|
| `flex_direction` | FlexDirection? | `Row`, `Column`, `RowReverse`, `ColumnReverse` |
| `justify_content` | JustifyContent? | `FlexStart`, `FlexEnd`, `Center`, `SpaceBetween`, `SpaceAround`, `SpaceEvenly` |
| `align_items` | AlignItems? | `FlexStart`, `FlexEnd`, `Center`, `Stretch` |

### Positioning

| Property | Type | Description |
|---|---|---|
| `position_type` | PositionType? | `Relative` or `Absolute` |
| `top` | DimensionDef? | Top offset |
| `bottom` | DimensionDef? | Bottom offset |
| `left` | DimensionDef? | Left offset |
| `right` | DimensionDef? | Right offset |

### Material Design

| Property | Type | Description |
|---|---|---|
| `elevation` | u32? | Shadow elevation level |
| `corner_radius` | f32? | Border radius in pixels |
| `shadow_color` | ColorDef? | Shadow color |
| `border_color` | ColorDef? | Border stroke color |
| `border_width` | f32? | Border stroke width |
| `opacity` | f32? | Element opacity (0.0-1.0) |
| `rotation` | f32? | Z-axis rotation in degrees |
| `scale` | f32? | Uniform scale factor |

---

## Shared Types

### DimensionDef

Dimensions can be pixels, percentages, or auto:

```json
300.0              // Pixels (f32)
"50%"              // Percentage (String)
"Auto"             // Auto-sized
```

### RectDef

Edge insets for padding, margin, and border:

```json
{
  "top": 10.0,
  "right": 16.0,
  "bottom": 10.0,
  "left": 16.0
}
```

All fields default to `0.0`.

### ColorDef

RGBA color with channels from 0.0 to 1.0:

```json
{"r": 0.2, "g": 0.6, "b": 1.0, "a": 1.0}
```

Default: `{"r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0}` (white, fully opaque).

---

## Complete Example

```json
{
  "ui": [
    {
      "type": "container",
      "style": {
        "flex_direction": "Column",
        "align_items": "Center",
        "width": 400.0,
        "padding": {"top": 24, "right": 24, "bottom": 24, "left": 24}
      },
      "children": [
        {
          "type": "appbar",
          "title": "My Dashboard",
          "app_bar_type": "Center",
          "background_color": {"r": 0.1, "g": 0.3, "b": 0.7, "a": 1.0},
          "actions": [
            {"icon": "notifications", "tooltip": "Alerts"}
          ]
        },
        {
          "type": "card",
          "elevation": 2,
          "corner_radius": 12.0,
          "children": [
            {"type": "text", "text": "Welcome Back!", "font_size": 22.0},
            {"type": "text", "text": "You have 3 new messages."},
            {"type": "progressbar", "value": 75.0, "max": 100.0},
            {
              "type": "container",
              "style": {"flex_direction": "Row", "justify_content": "SpaceAround"},
              "children": [
                {"type": "button", "label": "View", "action": "on_view"},
                {"type": "button", "label": "Dismiss", "action": "on_dismiss"}
              ]
            }
          ]
        },
        {
          "type": "tabs",
          "tab_type": "Fixed",
          "tabs": [
            {"label": "Overview", "content": [
              {"type": "text", "text": "Overview content"}
            ]},
            {"label": "Details", "content": [
              {"type": "text", "text": "Detail content"}
            ]}
          ]
        }
      ]
    }
  ]
}
```

---

## Element Summary Table

| Element | Type Tag | Bevy Component(s) |
|---|---|---|
| Container | `container` | `Node` + `BackgroundColor` |
| Text | `text` | `Text` + `TextFont` + `TextColor` |
| Button | `button` | `Button` + `RoundedBackground` + `Elevation` |
| Image | `image` | `ImageNode` |
| Slider | `slider` | `Slider` + `SliderHandle` |
| Checkbox | `checkbox` | `Checkbox` + `Button` + `Text` |
| Radio | `radio` | `RadioButton` + `Button` + `Text` |
| Text Input | `textinput` | `TextInputComponent` + `Text` |
| Progress Bar | `progressbar` | `ProgressBarComponent` + `ProgressBarFill` |
| FAB | `fab` | `FloatingActionButton` + `Button` + `RoundedBackground` + `Elevation` |
| Card | `card` | `Card` + `RoundedBackground` + `Elevation` |
| Chip | `chip` | `Chip` + `Button` + `Text` |
| App Bar | `appbar` | `AppBar` + `RoundedBackground` + `Text` + `Elevation` |
| Dialog | `dialog` | `Dialog` + `RoundedBackground` + `Text` |
| Menu | `menu` | `Menu` + `RoundedBackground` |
| Bottom Sheet | `bottomsheet` | `BottomSheet` + `Node` |
| Snackbar | `snackbar` | `Snackbar` + `RoundedBackground` + `Text` |
| Switch | `switch` | `SwitchComponent` + `Button` |
| Tabs | `tabs` | `Tabs` + `Button` + children |
| Badge | `badge` | `Badge` + `Text` |
| Tooltip | `tooltip` | `Tooltip` + `RoundedBackground` + `Text` |
| Rating | `rating` | `Rating` + `Node` |
| Segmented Button | `segment` | `SegmentedButton` + `Button` |
| Icon Button | `iconbutton` | `IconButton` + `Button` |
| Divider | `divider` | `Divider` + `Node` |
| List | `list` | `ListComponent` + `Node` |
| Drawer | `drawer` | `Drawer` + `Node` |
