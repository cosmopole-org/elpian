# JSON Schema Quick Reference

## Root Structure
```json
{
  "ui": [/* array of UI nodes */],
  "world": [/* array of 3D nodes */]
}
```

## UI Node Types

### Container
```json
{
  "type": "container",
  "id": "string (optional)",
  "style": StyleDef,
  "background_color": ColorDef (optional),
  "children": [/* array of UI nodes */]
}
```

### Text
```json
{
  "type": "text",
  "id": "string (optional)",
  "text": "string",
  "font_size": number (optional, default: 24),
  "color": ColorDef (optional),
  "style": StyleDef (optional)
}
```

### Button
```json
{
  "type": "button",
  "id": "string (optional)",
  "label": "string",
  "action": "string (optional)",
  "style": StyleDef (optional)
}
```

### Image
```json
{
  "type": "image",
  "id": "string (optional)",
  "path": "string",
  "style": StyleDef (optional)
}
```

### Slider
```json
{
  "type": "slider",
  "id": "string (optional)",
  "min": number (default: 0),
  "max": number (default: 100),
  "value": number (default: 0),
  "on_change": "string (optional)",
  "style": StyleDef (optional)
}
```

### Checkbox
```json
{
  "type": "checkbox",
  "id": "string (optional)",
  "label": "string",
  "checked": boolean (default: false),
  "on_change": "string (optional)",
  "style": StyleDef (optional)
}
```

### Radio Button
```json
{
  "type": "radio",
  "id": "string (optional)",
  "label": "string",
  "group": "string",
  "checked": boolean (default: false),
  "on_change": "string (optional)",
  "style": StyleDef (optional)
}
```

### Text Input
```json
{
  "type": "textinput",
  "id": "string (optional)",
  "placeholder": "string (default: empty)",
  "value": "string (default: empty)",
  "on_change": "string (optional)",
  "style": StyleDef (optional)
}
```

### Progress Bar
```json
{
  "type": "progressbar",
  "id": "string (optional)",
  "value": number (default: 0),
  "max": number (default: 100),
  "bar_color": ColorDef (optional),
  "background_color": ColorDef (optional),
  "style": StyleDef (optional)
}
```

## 3D Node Types

### Mesh3D
```json
{
  "type": "mesh3d",
  "id": "string (optional)",
  "mesh": MeshType,
  "material": MaterialDef (optional),
  "transform": TransformDef (optional)
}
```

### Light
```json
{
  "type": "light",
  "id": "string (optional)",
  "light_type": "Point" | "Directional" | "Spot",
  "color": ColorDef (optional),
  "intensity": number (optional),
  "transform": TransformDef (optional)
}
```

### Camera
```json
{
  "type": "camera",
  "id": "string (optional)",
  "camera_type": "Perspective" | "Orthographic",
  "transform": TransformDef (optional),
  "animation": AnimationDef (optional)
}
```

### Audio
```json
{
  "type": "audio",
  "id": "string (optional)",
  "path": "string",
  "volume": number (0.0-1.0, default: 1.0),
  "looping": boolean (default: false),
  "autoplay": boolean (default: true),
  "spatial": boolean (default: false),
  "transform": TransformDef (optional, required if spatial is true)
}
```

### Particles
```json
{
  "type": "particles",
  "id": "string (optional)",
  "transform": TransformDef,
  "emission_rate": number (default: 10.0),
  "lifetime": number (default: 1.0),
  "color": ColorDef,
  "size": number (default: 0.1),
  "velocity": Vec3Def,
  "gravity": Vec3Def
}
```

## Common Definitions

### StyleDef
```json
{
  "width": DimensionDef (optional),
  "height": DimensionDef (optional),
  "min_width": DimensionDef (optional),
  "min_height": DimensionDef (optional),
  "max_width": DimensionDef (optional),
  "max_height": DimensionDef (optional),
  "padding": RectDef (optional),
  "margin": RectDef (optional),
  "border": RectDef (optional),
  "flex_direction": "Row" | "Column" | "RowReverse" | "ColumnReverse" (optional),
  "justify_content": "FlexStart" | "FlexEnd" | "Center" | "SpaceBetween" | "SpaceAround" | "SpaceEvenly" (optional),
  "align_items": "FlexStart" | "FlexEnd" | "Center" | "Stretch" (optional),
  "position_type": "Relative" | "Absolute" (optional),
  "top": DimensionDef (optional),
  "bottom": DimensionDef (optional),
  "left": DimensionDef (optional),
  "right": DimensionDef (optional)
}
```

### DimensionDef
Can be one of:
- `number` - pixels (e.g., `100`)
- `"string%"` - percentage (e.g., `"50%"`)
- `"Auto"` - automatic sizing

### RectDef
```json
{
  "top": number,
  "bottom": number,
  "left": number,
  "right": number
}
```

### ColorDef
```json
{
  "r": number (0.0-1.0),
  "g": number (0.0-1.0),
  "b": number (0.0-1.0),
  "a": number (0.0-1.0, optional, default: 1.0)
}
```

### MeshType
Can be one of:
- `"Cube"` - unit cube
- `{"Sphere": {"radius": number, "subdivisions": number}}` - sphere with custom parameters
- `{"Plane": {"size": number}}` - square plane
- `{"Capsule": {"radius": number, "depth": number}}` - capsule shape
- `{"Cylinder": {"radius": number, "height": number}}` - cylinder
- `{"File": {"path": "string"}}` - load from GLTF, OBJ, or other file

### MaterialDef
```json
{
  "base_color": ColorDef (optional),
  "base_color_texture": "string" (optional),
  "emissive": ColorDef (optional),
  "emissive_texture": "string" (optional),
  "metallic": number (0.0-1.0, optional),
  "roughness": number (0.0-1.0, optional),
  "metallic_roughness_texture": "string" (optional),
  "normal_map_texture": "string" (optional)
}
```

### AnimationDef
```json
{
  "animation_type": AnimationType,
  "duration": number (seconds),
  "looping": boolean (default: false),
  "easing": EasingType (default: "Linear")
}
```

### AnimationType
Can be one of:
```json
{"type": "Rotate", "axis": Vec3Def, "degrees": number}
{"type": "Translate", "from": Vec3Def, "to": Vec3Def}
{"type": "Scale", "from": Vec3Def, "to": Vec3Def}
{"type": "Bounce", "height": number}
{"type": "Pulse", "min_scale": number, "max_scale": number}
```

### EasingType
One of: `"Linear"`, `"EaseIn"`, `"EaseOut"`, `"EaseInOut"`, `"Bounce"`

### TransformDef
```json
{
  "position": Vec3Def (optional),
  "rotation": Vec3Def (optional, in degrees),
  "scale": Vec3Def (optional)
}
```

### Vec3Def
```json
{
  "x": number,
  "y": number,
  "z": number
}
```

## Common Patterns

### Centered Container
```json
{
  "type": "container",
  "style": {
    "width": "100%",
    "height": "100%",
    "justify_content": "Center",
    "align_items": "Center"
  }
}
```

### Full-Screen Overlay
```json
{
  "type": "container",
  "style": {
    "width": "100%",
    "height": "100%",
    "position_type": "Absolute"
  },
  "background_color": {"r": 0, "g": 0, "b": 0, "a": 0.5}
}
```

### Row of Buttons
```json
{
  "type": "container",
  "style": {
    "flex_direction": "Row",
    "justify_content": "Center"
  },
  "children": [
    {"type": "button", "label": "Button 1"},
    {"type": "button", "label": "Button 2"},
    {"type": "button", "label": "Button 3"}
  ]
}
```

### Basic 3D Scene
```json
{
  "world": [
    {
      "type": "camera",
      "camera_type": "Perspective",
      "transform": {
        "position": {"x": 0, "y": 2, "z": 5}
      }
    },
    {
      "type": "light",
      "light_type": "Directional",
      "intensity": 3000
    },
    {
      "type": "mesh3d",
      "mesh": "Cube",
      "material": {
        "base_color": {"r": 0.8, "g": 0.2, "b": 0.2, "a": 1.0}
      }
    }
  ]
}
```
