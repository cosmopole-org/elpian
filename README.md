# Bevy JSON UI/3D Converter

A feature-rich JSON to Bevy converter that allows you to define UI layouts and 3D scenes using declarative JSON files. Build complex Bevy interfaces and 3D worlds without writing Rust code!

## Features

### UI Support ✨
- **Flexbox Layout**: Full flexbox support with justify-content, align-items, flex-direction
- **Basic Components**: Containers, Text, Buttons, Images
- **Advanced Components**: Sliders, Checkboxes, Radio Buttons, Text Inputs, Progress Bars
- **Styling**: Width, height, padding, margin, borders, positioning
- **Colors**: RGBA color support for all visual elements
- **Nested Structures**: Unlimited nesting of UI components
- **Interactive Elements**: Buttons, checkboxes, radio buttons with hover/press states
- **Event Handling**: JSON-defined event callbacks for all interactive components

### 3D Support 🎮
- **Primitives**: Cubes, Spheres, Planes, Capsules, Cylinders
- **File Loading**: Load custom meshes from GLTF, OBJ files
- **Materials**: Base color, metallic, roughness, emissive properties
- **Textures**: Support for base color, emissive, metallic/roughness, and normal maps
- **Lighting**: Point lights, Directional lights, Spot lights
- **Cameras**: Perspective and Orthographic cameras
- **Transforms**: Position, rotation (Euler angles), scale

### Animation System 🎬
- **Animation Types**: Rotate, Translate, Scale, Bounce, Pulse
- **Easing Functions**: Linear, EaseIn, EaseOut, EaseInOut, Bounce
- **Looping**: Support for looping and one-shot animations
- **Apply to Any Object**: Meshes, lights, cameras can all be animated

### Particle System ✨
- **Customizable Emitters**: Control emission rate, particle lifetime, size
- **Physics**: Velocity and gravity for realistic particle motion
- **Visual Properties**: Color and emissive properties
- **Multiple Emitters**: Create complex particle effects

### Audio Support 🔊
- **Background Music**: Non-spatial audio playback
- **Sound Effects**: Spatial 3D audio with position
- **Control**: Volume, looping, autoplay settings

### Developer Tools 🛠️
- **JSON Validation**: Comprehensive validation before spawning
- **Hot Reloading**: Auto-reload scenes when JSON files change
- **Error Messages**: Detailed error reporting for malformed JSON
- **Type Safety**: Strongly-typed schema with Rust validation

## Installation

Add to your `Cargo.toml`:

```toml
[dependencies]
bevy = "0.15"
bevy-json-ui = { path = "path/to/bevy-json-ui" }
```

## Quick Start

### 1. Add the Plugin

```rust
use bevy::prelude::*;
use bevy_json_ui::JsonScenePlugin;

fn main() {
    App::new()
        .add_plugins(DefaultPlugins)
        .add_plugins(JsonScenePlugin)
        .run();
}
```

### 2. Create a JSON Scene File

```json
{
  "ui": [
    {
      "type": "container",
      "style": {
        "width": "100%",
        "height": "100%",
        "justify_content": "Center",
        "align_items": "Center"
      },
      "background_color": { "r": 0.1, "g": 0.1, "b": 0.15, "a": 1.0 },
      "children": [
        {
          "type": "text",
          "text": "Hello from JSON!",
          "font_size": 48,
          "color": { "r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0 }
        }
      ]
    }
  ],
  "world": []
}
```

### 3. Load and Spawn

```rust
fn setup(mut commands: Commands, asset_server: Res<AssetServer>) {
    let scene = JsonScene::load_from_file("my_scene.json")
        .expect("Failed to load scene");
    
    scene.spawn_ui(&mut commands, &asset_server)
        .expect("Failed to spawn UI");
}
```

## JSON Schema Reference

### UI Elements

#### Container
```json
{
  "type": "container",
  "id": "optional_id",
  "style": { /* StyleDef */ },
  "background_color": { "r": 0.5, "g": 0.5, "b": 0.5, "a": 1.0 },
  "children": [ /* array of child nodes */ ]
}
```

#### Text
```json
{
  "type": "text",
  "id": "optional_id",
  "text": "Your text here",
  "font_size": 24,
  "color": { "r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0 },
  "style": { /* StyleDef */ }
}
```

#### Button
```json
{
  "type": "button",
  "id": "optional_id",
  "label": "Click Me",
  "action": "optional_action_id",
  "style": { /* StyleDef */ }
}
```

#### Image
```json
{
  "type": "image",
  "id": "optional_id",
  "path": "path/to/image.png",
  "style": { /* StyleDef */ }
}
```

### Style Definition

```json
{
  "width": 500,              // pixels
  "height": "50%",           // percentage
  "min_width": 100,
  "max_width": 1000,
  "padding": { "top": 10, "bottom": 10, "left": 10, "right": 10 },
  "margin": { "top": 5, "bottom": 5, "left": 5, "right": 5 },
  "flex_direction": "Row",   // Row, Column, RowReverse, ColumnReverse
  "justify_content": "Center", // FlexStart, FlexEnd, Center, SpaceBetween, SpaceAround, SpaceEvenly
  "align_items": "Center",   // FlexStart, FlexEnd, Center, Stretch
  "position_type": "Relative", // Relative, Absolute
  "top": 0,
  "left": 0
}
```

### 3D Elements

#### Mesh
```json
{
  "type": "mesh3d",
  "id": "optional_id",
  "mesh": "Cube",  // or Sphere, Plane, Capsule, Cylinder
  "material": {
    "base_color": { "r": 0.8, "g": 0.2, "b": 0.2, "a": 1.0 },
    "metallic": 0.5,
    "roughness": 0.5,
    "emissive": { "r": 0.0, "g": 0.0, "b": 0.0, "a": 1.0 }
  },
  "transform": {
    "position": { "x": 0, "y": 1, "z": 0 },
    "rotation": { "x": 0, "y": 45, "z": 0 },  // degrees
    "scale": { "x": 1, "y": 1, "z": 1 }
  }
}
```

#### Parametric Meshes
```json
{
  "mesh": {
    "Sphere": { "radius": 0.5, "subdivisions": 32 }
  }
}
```

```json
{
  "mesh": {
    "Plane": { "size": 10.0 }
  }
}
```

```json
{
  "mesh": {
    "Capsule": { "radius": 0.3, "depth": 1.0 }
  }
}
```

```json
{
  "mesh": {
    "Cylinder": { "radius": 0.5, "height": 2.0 }
  }
}
```

#### Light
```json
{
  "type": "light",
  "id": "optional_id",
  "light_type": "Point",  // Point, Directional, Spot
  "color": { "r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0 },
  "intensity": 1000.0,
  "transform": {
    "position": { "x": 0, "y": 5, "z": 0 },
    "rotation": { "x": -45, "y": 0, "z": 0 }
  }
}
```

#### Camera
```json
{
  "type": "camera",
  "id": "optional_id",
  "camera_type": "Perspective",  // Perspective, Orthographic
  "transform": {
    "position": { "x": 0, "y": 2, "z": 5 },
    "rotation": { "x": -20, "y": 0, "z": 0 }
  }
}
```

## Examples

### Run UI Demo
```bash
cargo run --example ui_demo
```

This demonstrates:
- Complex nested layouts
- Multiple buttons with interactions
- Text with custom fonts and colors
- Flexbox positioning
- Background colors and styling

### Run Advanced UI Demo
```bash
cargo run --example advanced_ui_demo
```

This demonstrates:
- Sliders for value selection
- Checkboxes for boolean options
- Radio buttons for exclusive choices
- Progress bars for loading/status
- Text inputs (visual representation)
- Event callbacks

### Run 3D Demo
```bash
cargo run --example 3d_demo
```

This demonstrates:
- Multiple 3D primitives
- Different materials and colors
- Multiple light sources
- Camera setup
- Animated rotations (added in Rust code)

### Run Animations Demo
```bash
cargo run --example animations_demo
```

This demonstrates:
- Rotation animations
- Bouncing animations
- Pulsing/scaling animations
- Multiple particle emitters
- Particle physics (gravity, velocity)
- Animated lights

## Advanced Usage

### Animations

Add animations to any 3D object (mesh, light, or camera):

```json
{
  "type": "mesh3d",
  "mesh": "Cube",
  "transform": {
    "position": { "x": 0, "y": 1, "z": 0 }
  },
  "animation": {
    "animation_type": {
      "type": "Rotate",
      "axis": { "x": 0, "y": 1, "z": 0 },
      "degrees": 360
    },
    "duration": 3.0,
    "looping": true,
    "easing": "Linear"
  }
}
```

Available animation types:
- **Rotate**: Rotate around an axis
- **Translate**: Move from one position to another
- **Scale**: Scale from one size to another
- **Bounce**: Bounce up and down
- **Pulse**: Pulse between min and max scale

Easing options: `Linear`, `EaseIn`, `EaseOut`, `EaseInOut`, `Bounce`

### Particle Systems

Create particle emitters:

```json
{
  "type": "particles",
  "transform": {
    "position": { "x": 0, "y": 1, "z": 0 }
  },
  "emission_rate": 20.0,
  "lifetime": 2.0,
  "color": { "r": 0.2, "g": 0.7, "b": 1.0, "a": 1.0 },
  "size": 0.1,
  "velocity": { "x": 0, "y": 3, "z": 0 },
  "gravity": { "x": 0, "y": -9.8, "z": 0 }
}
```

### Audio

Add background music or spatial audio:

```json
{
  "type": "audio",
  "path": "sounds/background_music.ogg",
  "volume": 0.8,
  "looping": true,
  "autoplay": true,
  "spatial": false
}
```

For 3D spatial audio, set `"spatial": true` and add a transform:

```json
{
  "type": "audio",
  "path": "sounds/explosion.ogg",
  "volume": 1.0,
  "spatial": true,
  "transform": {
    "position": { "x": 5, "y": 1, "z": 0 }
  }
}
```

### Custom Meshes and Textures

Load custom meshes from files:

```json
{
  "type": "mesh3d",
  "mesh": {
    "File": {
      "path": "models/character.gltf"
    }
  }
}
```

Add textures to materials:

```json
{
  "material": {
    "base_color_texture": "textures/wood_diffuse.png",
    "normal_map_texture": "textures/wood_normal.png",
    "metallic_roughness_texture": "textures/wood_mr.png"
  }
}
```

### Event Handling

Interactive components can trigger events:

```json
{
  "type": "checkbox",
  "label": "Enable sound",
  "checked": true,
  "on_change": "sound_toggle"
}
```

Listen for events in your Rust code:

```rust
fn handle_events(mut events: EventReader<ComponentEvent>) {
    for event in events.read() {
        match event.event_id.as_str() {
            "sound_toggle" => {
                println!("Sound toggled: {}", event.data);
            }
            _ => {}
        }
    }
}
```

### Hot Reloading

Enable hot reloading to automatically reload scenes when JSON files change:

```rust
use bevy_json_ui::enable_hot_reload;

fn main() {
    let mut app = App::new();
    app.add_plugins(DefaultPlugins)
       .add_plugins(JsonScenePlugin);
    
    // Enable hot reloading
    enable_hot_reload(&mut app, "examples/my_scene.json")
        .expect("Failed to setup hot reload");
    
    app.run();
}
```

Now edit the JSON file while the app is running and see changes instantly!

### JSON Validation

Validation happens automatically when loading scenes. To validate manually:

```rust
use bevy_json_ui::JsonValidator;

let scene = JsonScene::load_from_file("scene.json")?;
// Validation already happened

// Or validate separately:
JsonValidator::validate_scene(&scene.scene)?;
```

### Loading from String
```rust
let json = r#"
{
  "ui": [...],
  "world": [...]
}
"#;

let scene = JsonScene::load_from_str(json)?;
```

### Mixing JSON and Code
```rust
fn setup(
    mut commands: Commands,
    asset_server: Res<AssetServer>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    // Load JSON scene
    let scene = JsonScene::load_from_file("scene.json")?;
    
    // Spawn UI from JSON
    scene.spawn_ui(&mut commands, &asset_server)?;
    
    // Spawn 3D world from JSON
    let entities = scene.spawn_world(&mut commands, &mut meshes, &mut materials, &asset_server)?;
    
    // Add additional components to spawned entities
    for entity in entities {
        commands.entity(entity).insert(MyCustomComponent);
    }
    
    // Add purely code-based entities
    commands.spawn((
        // Your custom Bevy components
    ));
}
```

## Use Cases

- **Rapid Prototyping**: Design UI layouts without recompiling
- **Designer-Developer Workflow**: Designers can modify JSON while developers write game logic
- **Data-Driven UI**: Load different UIs based on game state
- **Scene Definition**: Define 3D levels and environments in JSON
- **Modding Support**: Allow users to customize UI/scenes via JSON
- **A/B Testing**: Easy to swap between different UI configurations

## Roadmap

### Completed ✅
- [x] Animation support (Rotate, Translate, Scale, Bounce, Pulse)
- [x] Event handling in JSON (on_change callbacks)
- [x] More UI components (sliders, checkboxes, radio buttons, text inputs, progress bars)
- [x] Custom mesh loading from files (GLTF, OBJ support)
- [x] Texture support for materials (base color, emissive, metallic/roughness, normal maps)
- [x] Audio elements (background music and spatial audio)
- [x] Particle systems (customizable emitters with physics)
- [x] JSON schema validation (comprehensive validation before spawning)
- [x] Hot reloading (watch files and auto-reload on changes)

### Future Enhancements 🚀
- [ ] Timeline-based animation sequences
- [ ] Sprite animation support
- [ ] UI state management system
- [ ] Visual node editor for JSON generation
- [ ] Animation curves editor
- [ ] Shader/material customization via JSON
- [ ] Physics integration (colliders, rigidbodies)
- [ ] Networking/multiplayer scene synchronization
- [ ] Asset bundling and compression
- [ ] Performance profiling tools

## License

MIT or Apache-2.0 (your choice)

## Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues.
