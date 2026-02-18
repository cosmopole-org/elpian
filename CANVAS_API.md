# Canvas API Documentation

## Overview

The Elpian UI library includes a comprehensive Canvas API based on Flutter's Skia graphics engine. This provides full 2D drawing capabilities through a familiar, HTML5 Canvas-like API that can be defined entirely in JSON.

## Features

✅ **50+ Drawing Commands** - Complete canvas drawing API
✅ **Paths & Shapes** - Lines, curves, rectangles, circles, polygons
✅ **Text Rendering** - Full text support with fonts and styles
✅ **Gradients** - Linear and radial gradients
✅ **Transformations** - Translate, rotate, scale, transform matrix
✅ **Compositing** - Global alpha and blend modes
✅ **State Management** - Save/restore canvas state
✅ **JSON-Based** - Define entire canvases in JSON
✅ **Builder Pattern** - Programmatic canvas construction
✅ **Presets** - Common shapes (stars, polygons, arrows)

## Basic Usage

### JSON DSL

```json
{
  "type": "Canvas",
  "props": {
    "width": 400,
    "height": 300,
    "commands": [
      {
        "type": "fillStyle",
        "params": {"color": "#FF0000"}
      },
      {
        "type": "fillRect",
        "params": {"x": 50, "y": 50, "width": 100, "height": 80}
      }
    ]
  }
}
```

### Builder Pattern

```dart
import 'package:elpian_ui/elpian_ui.dart';

final commands = CanvasBuilder()
  .fillStyle('#FF0000')
  .fillRect(50, 50, 100, 80)
  .strokeStyle('#0000FF')
  .lineWidth(3)
  .strokeRect(170, 50, 100, 80)
  .build();

final canvas = {
  'type': 'Canvas',
  'props': {
    'width': 400.0,
    'height': 300.0,
    'commands': commands,
  }
};
```

## Drawing Commands

### Path Operations

#### beginPath()
Start a new path.

```dart
CanvasBuilder().beginPath()
```

```json
{"type": "beginPath", "params": {}}
```

#### moveTo(x, y)
Move pen to position without drawing.

```dart
.moveTo(50, 50)
```

```json
{"type": "moveTo", "params": {"x": 50, "y": 50}}
```

#### lineTo(x, y)
Draw line to position.

```dart
.lineTo(150, 100)
```

#### quadraticCurveTo(cpx, cpy, x, y)
Draw quadratic bezier curve.

```dart
.quadraticCurveTo(100, 20, 150, 100)
```

#### bezierCurveTo(cp1x, cp1y, cp2x, cp2y, x, y)
Draw cubic bezier curve.

```dart
.bezierCurveTo(100, 20, 150, 180, 200, 100)
```

#### arc(x, y, radius, startAngle, endAngle, counterclockwise)
Draw circular arc.

```dart
.arc(100, 100, 50, 0, math.pi * 2)
```

#### closePath()
Close current path.

```dart
.closePath()
```

### Shapes

#### fillRect(x, y, width, height)
Draw filled rectangle.

```dart
.fillRect(50, 50, 100, 80)
```

#### strokeRect(x, y, width, height)
Draw outlined rectangle.

```dart
.strokeRect(50, 50, 100, 80)
```

#### clearRect(x, y, width, height)
Clear rectangular area.

```dart
.clearRect(50, 50, 100, 80)
```

#### rect(x, y, width, height)
Add rectangle to path.

```dart
.beginPath()
.rect(50, 50, 100, 80)
.fill()
```

#### roundRect(x, y, width, height, radius)
Add rounded rectangle to path.

```dart
.roundRect(50, 50, 100, 80, 10)
```

#### circle(x, y, radius)
Add circle to path.

```dart
.circle(100, 100, 50)
```

#### fillCircle(x, y, radius)
Draw filled circle.

```dart
.fillCircle(100, 100, 50)
```

#### strokeCircle(x, y, radius)
Draw outlined circle.

```dart
.strokeCircle(100, 100, 50)
```

#### ellipse(x, y, radiusX, radiusY)
Add ellipse to path.

```dart
.ellipse(100, 100, 80, 50)
```

### Path Drawing

#### fill()
Fill current path.

```dart
.beginPath()
.circle(100, 100, 50)
.fill()
```

#### stroke()
Stroke current path.

```dart
.beginPath()
.circle(100, 100, 50)
.stroke()
```

#### clip()
Clip to current path.

```dart
.clip()
```

### Text

#### fillText(text, x, y)
Draw filled text.

```dart
.fillText('Hello World', 50, 50)
```

#### strokeText(text, x, y)
Draw outlined text.

```dart
.strokeText('Hello World', 50, 50)
```

#### font(font)
Set font style.

```dart
.font('bold 24px Arial')
```

Format: `[style] [weight] size[px] family`
Examples:
- `'16px Arial'`
- `'bold 20px Helvetica'`
- `'italic 18px Times'`
- `'bold italic 24px Georgia'`

### Styles

#### fillStyle(color)
Set fill color or gradient.

```dart
.fillStyle('#FF0000')
.fillStyle('rgb(255, 0, 0)')
.fillStyle('rgba(255, 0, 0, 0.5)')
```

#### strokeStyle(color)
Set stroke color or gradient.

```dart
.strokeStyle('#0000FF')
```

#### lineWidth(width)
Set line width.

```dart
.lineWidth(3)
```

#### lineCap(cap)
Set line cap style: `'butt'`, `'round'`, `'square'`.

```dart
.lineCap('round')
```

#### lineJoin(join)
Set line join style: `'miter'`, `'round'`, `'bevel'`.

```dart
.lineJoin('round')
```

#### globalAlpha(alpha)
Set global transparency (0-1).

```dart
.globalAlpha(0.5)
```

### Gradients

#### createLinearGradient(id, x0, y0, x1, y1, colors, [stops])
Create linear gradient.

```dart
.createLinearGradient(
  'grad1',
  0, 0, 200, 0,
  ['#FF0000', '#00FF00', '#0000FF'],
  [0, 0.5, 1]
)
```

#### createRadialGradient(id, x, y, radius, colors, [stops])
Create radial gradient.

```dart
.createRadialGradient(
  'grad2',
  100, 100, 80,
  ['#FF0000', '#0000FF'],
)
```

#### fillGradient(gradientId)
Use gradient as fill.

```dart
.fillGradient('grad1')
```

#### strokeGradient(gradientId)
Use gradient as stroke.

```dart
.strokeGradient('grad1')
```

### Transformations

#### save()
Save canvas state.

```dart
.save()
```

#### restore()
Restore canvas state.

```dart
.restore()
```

#### translate(x, y)
Translate coordinate system.

```dart
.translate(100, 50)
```

#### rotate(angle)
Rotate coordinate system (radians).

```dart
.rotate(math.pi / 4)  // 45 degrees
```

#### scale(x, [y])
Scale coordinate system.

```dart
.scale(2, 2)      // Scale both axes
.scale(1.5)       // Scale uniformly
```

## Complete Examples

### Drawing Shapes

```dart
final commands = CanvasBuilder()
  // Filled rectangle
  .fillStyle('#FF5722')
  .fillRect(20, 20, 100, 80)
  
  // Stroked rectangle
  .strokeStyle('#2196F3')
  .lineWidth(3)
  .strokeRect(140, 20, 100, 80)
  
  // Rounded rectangle
  .fillStyle('#4CAF50')
  .beginPath()
  .roundRect(260, 20, 100, 80, 10)
  .fill()
  
  // Circle
  .fillStyle('#9C27B0')
  .fillCircle(70, 150, 40)
  
  .build();
```

### Bezier Curves

```dart
final commands = CanvasBuilder()
  .strokeStyle('#2196F3')
  .lineWidth(3)
  .beginPath()
  .moveTo(50, 100)
  .bezierCurveTo(100, 20, 150, 180, 200, 100)
  .stroke()
  .build();
```

### Gradients

```dart
final commands = CanvasBuilder()
  // Create gradient
  .createLinearGradient(
    'sunset',
    50, 75, 350, 75,
    ['#FF6B6B', '#4ECDC4', '#45B7D1'],
  )
  
  // Use gradient
  .fillGradient('sunset')
  .fillRect(50, 25, 300, 100)
  .build();
```

### Text Rendering

```dart
final commands = CanvasBuilder()
  .fillStyle('#212121')
  .font('24px Arial')
  .fillText('Hello Canvas!', 50, 50)
  
  .font('bold 32px Arial')
  .fillStyle('#2196F3')
  .fillText('Large Text', 50, 100)
  
  .strokeStyle('#FF5722')
  .lineWidth(2)
  .font('bold 28px Arial')
  .strokeText('Outlined', 50, 150)
  .build();
```

### Transformations

```dart
final commands = CanvasBuilder()
  .fillStyle('#2196F3')
  .fillRect(50, 50, 60, 60)
  
  .save()
  .translate(150, 50)
  .rotate(math.pi / 4)
  .fillStyle('#FF5722')
  .fillRect(-30, -30, 60, 60)
  .restore()
  
  .save()
  .translate(280, 50)
  .scale(1.5, 1.5)
  .fillStyle('#4CAF50')
  .fillRect(0, 0, 40, 40)
  .restore()
  .build();
```

## Canvas Presets

### Star

```dart
final commands = CanvasPresets.star(
  100, 100, 60,  // x, y, radius
  points: 5,
  innerRadius: 0.5,
  fillColor: '#FFD700',
  strokeColor: '#FF6B00',
);
```

### Polygon

```dart
final commands = CanvasPresets.polygon(
  150, 100, 60,  // x, y, radius
  sides: 6,
  fillColor: '#FF4081',
  strokeColor: '#C51162',
);
```

### Arrow

```dart
final commands = CanvasPresets.arrow(
  50, 100, 200, 100,  // x1, y1, x2, y2
  headLength: 15,
  headWidth: 10,
  color: '#2196F3',
);
```

## JSON DSL Format

### Complete Canvas Definition

```json
{
  "type": "Canvas",
  "props": {
    "width": 400,
    "height": 300,
    "backgroundColor": "#FFFFFF",
    "commands": [
      {
        "type": "fillStyle",
        "params": {"color": "#FF0000"}
      },
      {
        "type": "fillRect",
        "params": {"x": 50, "y": 50, "width": 100, "height": 80}
      },
      {
        "type": "strokeStyle",
        "params": {"color": "#0000FF"}
      },
      {
        "type": "lineWidth",
        "params": {"width": 3}
      },
      {
        "type": "strokeRect",
        "params": {"x": 170, "y": 50, "width": 100, "height": 80}
      }
    ]
  }
}
```

### With Gradients

```json
{
  "type": "Canvas",
  "props": {
    "width": 400,
    "height": 200,
    "commands": [
      {
        "type": "createLinearGradient",
        "params": {
          "id": "grad1",
          "x0": 0,
          "y0": 0,
          "x1": 400,
          "y1": 0,
          "colors": ["#FF6B6B", "#4ECDC4", "#45B7D1"]
        }
      },
      {
        "type": "setFillStyle",
        "params": {"gradientId": "grad1"}
      },
      {
        "type": "fillRect",
        "params": {"x": 0, "y": 0, "width": 400, "height": 200}
      }
    ]
  }
}
```

## Performance Tips

1. **Batch Operations** - Group similar operations together
2. **Minimize State Changes** - Reduce save/restore calls
3. **Use Paths Efficiently** - Reuse paths when possible
4. **Optimize Gradients** - Create gradients once, use multiple times
5. **Limit Complexity** - Break complex drawings into simpler parts

## Supported Commands Reference

### Path Commands (15)
- beginPath, moveTo, lineTo
- quadraticCurveTo, bezierCurveTo
- arc, arcTo, ellipse
- rect, roundRect, circle
- closePath, fill, stroke
- clip

### Shape Commands (8)
- fillRect, strokeRect, clearRect
- fillCircle, strokeCircle
- fillPolygon, strokePolygon

### Text Commands (3)
- fillText, strokeText
- setFont, setTextAlign, setTextBaseline

### Style Commands (15)
- setFillStyle, setStrokeStyle
- setLineWidth, setLineCap, setLineJoin
- setMiterLimit, setLineDash, setLineDashOffset
- setShadowBlur, setShadowColor
- setShadowOffsetX, setShadowOffsetY
- setGlobalAlpha, setGlobalCompositeOperation

### Transform Commands (8)
- save, restore
- translate, rotate, scale
- transform, setTransform, resetTransform

### Gradient Commands (4)
- createLinearGradient, createRadialGradient
- addColorStop, createPattern

## Browser Compatibility

The Canvas API follows HTML5 Canvas specification and provides equivalent functionality to the browser canvas element. All commands work the same way as in HTML5 Canvas, making it easy to port web canvas code to Flutter.

## Advanced Usage

### Animation

Combine with state management for animated canvases:

```dart
class AnimatedCanvas extends StatefulWidget {
  @override
  State<AnimatedCanvas> createState() => _AnimatedCanvasState();
}

class _AnimatedCanvasState extends State<AnimatedCanvas>
    with SingleTickerProviderStateMixin {
  late AnimationController controller;
  
  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
  }
  
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final commands = CanvasBuilder()
          .save()
          .translate(200, 100)
          .rotate(controller.value * 2 * math.pi)
          .fillStyle('#2196F3')
          .fillRect(-25, -25, 50, 50)
          .restore()
          .build();
        
        return ElpianCanvas(
          commands: commands,
          width: 400,
          height: 200,
        );
      },
    );
  }
}
```

This comprehensive Canvas API enables full 2D graphics capabilities entirely through JSON configuration!
