# JSON Stylesheet Documentation

## Overview

The STAC Flutter UI library now supports defining CSS stylesheets entirely in JSON format. This allows you to create reusable style definitions, responsive designs, and complete design systems using a declarative JSON structure.

## Basic Structure

```json
{
  "rules": [
    {
      "selector": ".my-class",
      "styles": {
        "backgroundColor": "#FF0000",
        "padding": "16",
        "borderRadius": 8
      }
    }
  ],
  "mediaQueries": [
    {
      "query": "min-width: 768",
      "rules": [...]
    }
  ],
  "variables": {
    "primary-color": "#2196F3"
  },
  "keyframes": [
    {
      "name": "fadeIn",
      "frames": [...]
    }
  ]
}
```

## Usage

### Loading a Stylesheet

```dart
final engine = StacEngine();

// Load from JSON
engine.loadStylesheet({
  'rules': [
    {
      'selector': '.card',
      'styles': {
        'padding': '16',
        'backgroundColor': '#FFFFFF',
        'borderRadius': 8,
      }
    }
  ]
});

// Or use builder pattern
final builder = JsonStylesheetBuilder()
  .addRule('.card', {
    'padding': '16',
    'backgroundColor': '#FFFFFF',
    'borderRadius': 8,
  })
  .addRule('.button', {
    'backgroundColor': '#2196F3',
    'color': '#FFFFFF',
  });

engine.loadStylesheetFromBuilder(builder);
```

### Using Stylesheet Classes

```json
{
  "type": "div",
  "props": {
    "className": "card"
  },
  "children": [
    {
      "type": "Button",
      "props": {
        "text": "Click Me",
        "className": "button"
      }
    }
  ]
}
```

## Selectors

### Tag Selectors

```json
{
  "selector": "h1",
  "styles": {
    "fontSize": 32,
    "fontWeight": "bold"
  }
}
```

### Class Selectors

```json
{
  "selector": ".my-class",
  "styles": {
    "color": "#FF0000"
  }
}
```

### ID Selectors

```json
{
  "selector": "#unique-id",
  "styles": {
    "backgroundColor": "#0000FF"
  }
}
```

### Multiple Classes

```json
{
  "type": "div",
  "props": {
    "className": "card shadow rounded"
  }
}
```

## Complete Style Properties

### Layout Properties

```json
{
  "width": 300,
  "height": 200,
  "minWidth": 100,
  "maxWidth": 500,
  "minHeight": 100,
  "maxHeight": 500
}
```

### Spacing

```json
{
  "padding": "16",
  "paddingTop": "8",
  "paddingRight": "16",
  "paddingBottom": "8",
  "paddingLeft": "16",
  "margin": "16",
  "marginTop": "8",
  "marginRight": "16",
  "marginBottom": "8",
  "marginLeft": "16"
}
```

### Positioning

```json
{
  "position": "absolute",
  "top": "10",
  "right": "10",
  "bottom": "10",
  "left": "10",
  "zIndex": 100
}
```

### Flexbox

```json
{
  "display": "flex",
  "flexDirection": "row",
  "justifyContent": "space-between",
  "alignItems": "center",
  "alignContent": "stretch",
  "flexWrap": "wrap",
  "gap": 16,
  "rowGap": 12,
  "columnGap": 16,
  "flex": 1,
  "flexGrow": 1,
  "flexShrink": 0,
  "order": 1
}
```

### Grid Layout

```json
{
  "display": "grid",
  "gridTemplateColumns": "repeat(3, 1fr)",
  "gridTemplateRows": "auto",
  "gridGap": 16,
  "gridColumnGap": 16,
  "gridRowGap": 16,
  "gridColumn": "1 / 3",
  "gridRow": "1 / 2"
}
```

### Typography

```json
{
  "color": "#212121",
  "fontSize": 16,
  "fontWeight": "bold",
  "fontStyle": "italic",
  "fontFamily": "Roboto",
  "letterSpacing": 1.2,
  "wordSpacing": 2.0,
  "lineHeight": 1.5,
  "textAlign": "center",
  "textDecoration": "underline",
  "textDecorationColor": "#FF0000",
  "textDecorationStyle": "solid",
  "textOverflow": "ellipsis",
  "textTransform": "uppercase"
}
```

### Background

```json
{
  "backgroundColor": "#FFFFFF",
  "backgroundImage": "url('image.png')",
  "backgroundSize": "cover",
  "backgroundPosition": "center",
  "backgroundRepeat": "no-repeat",
  "gradient": {
    "type": "linear",
    "colors": ["#FF0000", "#00FF00", "#0000FF"],
    "begin": "topLeft",
    "end": "bottomRight"
  }
}
```

### Borders

```json
{
  "border": "1px solid #E0E0E0",
  "borderRadius": 8,
  "borderTopLeftRadius": 8,
  "borderTopRightRadius": 8,
  "borderBottomLeftRadius": 8,
  "borderBottomRightRadius": 8,
  "borderWidth": 2,
  "borderColor": "#E0E0E0",
  "borderStyle": "solid"
}
```

### Shadows

```json
{
  "boxShadow": [
    {
      "color": "rgba(0,0,0,0.1)",
      "offset": {"x": 0, "y": 2},
      "blur": 4,
      "spread": 0
    }
  ],
  "textShadow": [
    {
      "color": "rgba(0,0,0,0.5)",
      "offset": {"x": 1, "y": 1},
      "blur": 2
    }
  ]
}
```

### Transforms

```json
{
  "rotate": 45,
  "rotateX": 15,
  "rotateY": 30,
  "rotateZ": 45,
  "scale": 1.2,
  "scaleX": 1.1,
  "scaleY": 1.3,
  "translateX": 10,
  "translateY": 20,
  "skewX": 5,
  "skewY": 10
}
```

### Effects

```json
{
  "opacity": 0.8,
  "blur": 2,
  "brightness": 1.2,
  "contrast": 1.1,
  "grayscale": 0.5,
  "hueRotate": 90,
  "invert": 0.2,
  "saturate": 1.5,
  "sepia": 0.3
}
```

### Animation

```json
{
  "transitionDuration": "300ms",
  "transitionDelay": "100ms",
  "transitionCurve": "ease-in-out",
  "animationDuration": "1s",
  "animationDelay": "500ms",
  "animationIterationCount": 3,
  "animationDirection": "alternate"
}
```

## Media Queries

### Responsive Design

```json
{
  "mediaQueries": [
    {
      "query": "min-width: 768",
      "rules": [
        {
          "selector": ".container",
          "styles": {
            "padding": "40"
          }
        }
      ]
    },
    {
      "query": "min-width: 1024",
      "rules": [
        {
          "selector": ".container",
          "styles": {
            "maxWidth": 1200
          }
        }
      ]
    }
  ]
}
```

## CSS Variables

```json
{
  "variables": {
    "primary-color": "#2196F3",
    "secondary-color": "#757575",
    "spacing-unit": 8,
    "border-radius": 4
  }
}
```

## Keyframe Animations

```json
{
  "keyframes": [
    {
      "name": "fadeIn",
      "frames": [
        {
          "offset": 0,
          "styles": {"opacity": 0}
        },
        {
          "offset": 1,
          "styles": {"opacity": 1}
        }
      ]
    },
    {
      "name": "slideIn",
      "frames": [
        {
          "offset": 0,
          "styles": {"translateX": -100}
        },
        {
          "offset": 1,
          "styles": {"translateX": 0}
        }
      ]
    }
  ]
}
```

## Builder Pattern

### Creating Stylesheets Programmatically

```dart
final stylesheet = JsonStylesheetBuilder()
  // Basic rules
  .addRule('.card', {
    'backgroundColor': '#FFFFFF',
    'padding': '16',
    'borderRadius': 8,
  })
  
  // Button styles
  .addRule('.btn-primary', {
    'backgroundColor': '#2196F3',
    'color': '#FFFFFF',
    'padding': '12 24',
  })
  
  // Media query
  .addMediaQuery('min-width: 768', [
    {
      'selector': '.card',
      'styles': {'padding': '24'}
    }
  ])
  
  // Variables
  .addVariable('primary-color', '#2196F3')
  .addVariable('spacing-unit', 8)
  
  // Build
  .build();

engine.loadStylesheet(stylesheet);
```

## Style Presets

### Using Built-in Presets

```dart
import 'package:stac_flutter_ui/stac_flutter_ui.dart';

final stylesheet = JsonStylesheetBuilder()
  .addRule('.flex-center', StylePresets.flexCenter)
  .addRule('.flex-row', StylePresets.flexRow)
  .addRule('.card', StylePresets.card())
  .addRule('.btn', StylePresets.button())
  .addRule('.grid', StylePresets.grid(columns: 'repeat(4, 1fr)'))
  .build();
```

### Available Presets

- `StylePresets.flexCenter` - Centered flexbox
- `StylePresets.flexRow` - Horizontal flex layout
- `StylePresets.flexColumn` - Vertical flex layout
- `StylePresets.card()` - Card component
- `StylePresets.button()` - Button component
- `StylePresets.textTruncate` - Text ellipsis
- `StylePresets.absoluteCenter` - Absolute centering
- `StylePresets.fullSize` - 100% width and height
- `StylePresets.elevation(level)` - Material elevation
- `StylePresets.gradient()` - Gradient background
- `StylePresets.grid()` - Grid layout

## Complete Example

```dart
import 'package:flutter/material.dart';
import 'package:stac_flutter_ui/stac_flutter_ui.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  final StacEngine engine = StacEngine();

  MyApp({super.key}) {
    // Load comprehensive stylesheet
    engine.loadStylesheet({
      'rules': [
        // Typography
        {
          'selector': 'h1',
          'styles': {
            'fontSize': 32,
            'fontWeight': 'bold',
            'color': '#212121',
          }
        },
        
        // Components
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
        
        // Layout
        {
          'selector': '.container',
          'styles': {
            'padding': '20',
            'maxWidth': 1200,
          }
        },
        
        {
          'selector': '.grid',
          'styles': {
            'display': 'grid',
            'gridTemplateColumns': 'repeat(3, 1fr)',
            'gridGap': 16,
          }
        },
      ],
      
      'mediaQueries': [
        {
          'query': 'min-width: 768',
          'rules': [
            {
              'selector': '.container',
              'styles': {'padding': '40'}
            }
          ]
        }
      ],
      
      'variables': {
        'primary-color': '#2196F3',
        'spacing-unit': 8,
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ui = {
      'type': 'div',
      'props': {'className': 'container'},
      'children': [
        {
          'type': 'h1',
          'props': {'text': 'Styled with JSON Stylesheet'}
        },
        {
          'type': 'div',
          'props': {'className': 'grid'},
          'children': [
            {
              'type': 'div',
              'props': {'className': 'card'},
              'children': [
                {'type': 'p', 'props': {'text': 'Card 1'}}
              ]
            },
            {
              'type': 'div',
              'props': {'className': 'card'},
              'children': [
                {'type': 'p', 'props': {'text': 'Card 2'}}
              ]
            },
          ]
        }
      ]
    };

    return MaterialApp(
      home: Scaffold(
        body: engine.renderFromJson(ui),
      ),
    );
  }
}
```

## Best Practices

1. **Use Semantic Class Names** - `.card`, `.button`, `.header`
2. **Create Utility Classes** - `.m-2`, `.p-3`, `.text-center`
3. **Leverage Variables** - Define colors and spacing once
4. **Use Media Queries** - Build responsive designs
5. **Combine Classes** - `className: "card shadow rounded"`
6. **Separate Concerns** - Keep styles in stylesheet, structure in UI JSON

## Advantages

✅ **Reusable** - Define once, use everywhere
✅ **Maintainable** - Change styles in one place
✅ **Consistent** - Enforce design system
✅ **Responsive** - Built-in media query support
✅ **Type-Safe** - Full Dart validation
✅ **Flexible** - Override with inline styles when needed
✅ **Familiar** - CSS-like syntax in JSON

## Style Priority

1. **Inline styles** (highest priority)
2. **ID selectors** (#unique-id)
3. **Class selectors** (.my-class)
4. **Tag selectors** (div, h1)
5. **Default styles** (lowest priority)

## Converting CSS to JSON

Use the built-in converter:

```dart
final cssText = '''
  .card {
    padding: 16px;
    background-color: #FFFFFF;
  }
  
  h1 {
    font-size: 32px;
  }
''';

final jsonStylesheet = JsonStylesheetParser.cssToJson(cssText);
engine.loadStylesheet(jsonStylesheet);
```

This comprehensive JSON stylesheet system makes it easy to build consistent, maintainable, and responsive UIs entirely from JSON!
