# Quick Start Guide

## Get Running in 5 Steps

### 1. Test the Examples

```bash
cd bevy-json-ui

# Run the basic UI demo
cargo run --example ui_demo

# Run the 3D demo
cargo run --example 3d_demo

# Run the advanced UI components demo (NEW!)
cargo run --example advanced_ui_demo

# Run the animations & particles demo (NEW!)
cargo run --example animations_demo
```

### 2. Modify the JSON Files

The example JSON files are in `examples/`:
- `ui_example.json` - Basic UI with buttons and text
- `3d_example.json` - 3D scene with meshes and lights
- `combined_example.json` - Both UI and 3D together
- `advanced_ui.json` - Sliders, checkboxes, radio buttons, progress bars (NEW!)
- `animations.json` - Animations and particle systems (NEW!)

Open any of these in your editor and change:
- Colors
- Positions
- Text content
- Mesh types
- Layout properties
- Animation parameters
- Particle effects

Then run the example again to see your changes!

### 3. Create Your Own Scene

Create a new file `examples/my_scene.json`:

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
      "background_color": {"r": 0.05, "g": 0.05, "b": 0.1, "a": 1.0},
      "children": [
        {
          "type": "text",
          "text": "My First JSON UI!",
          "font_size": 60,
          "color": {"r": 0.2, "g": 0.8, "b": 1.0, "a": 1.0}
        }
      ]
    }
  ],
  "world": []
}
```

Create `examples/my_demo.rs`:

```rust
use bevy::prelude::*;
use bevy_json_ui::{JsonScene, JsonScenePlugin};

fn main() {
    App::new()
        .add_plugins(DefaultPlugins)
        .add_plugins(JsonScenePlugin)
        .add_systems(Startup, setup)
        .run();
}

fn setup(mut commands: Commands, asset_server: Res<AssetServer>) {
    JsonScene::load_from_file("examples/my_scene.json")
        .expect("Failed to load scene")
        .spawn_ui(&mut commands, &asset_server)
        .expect("Failed to spawn UI");
}
```

Add to `Cargo.toml`:

```toml
[[example]]
name = "my_demo"
path = "examples/my_demo.rs"
```

Run it:

```bash
cargo run --example my_demo
```

## What's Next?

- Check `SCHEMA_REFERENCE.md` for the complete JSON schema
- Read `README.md` for detailed documentation
- Experiment with the example JSON files
- Mix JSON scenes with Rust code for game logic

## Common Customizations

### Change Button Colors

In your JSON:
```json
{
  "type": "button",
  "label": "My Button",
  "normal_color": {"r": 0.2, "g": 0.6, "b": 0.2, "a": 1.0},
  "hover_color": {"r": 0.3, "g": 0.8, "b": 0.3, "a": 1.0},
  "pressed_color": {"r": 0.1, "g": 0.4, "b": 0.1, "a": 1.0}
}
```

### Add Padding/Margins

```json
{
  "style": {
    "padding": {"top": 20, "bottom": 20, "left": 20, "right": 20},
    "margin": {"top": 10, "bottom": 10, "left": 10, "right": 10}
  }
}
```

### Create a Row Layout

```json
{
  "type": "container",
  "style": {
    "flex_direction": "Row",
    "justify_content": "SpaceBetween"
  },
  "children": [/* your items */]
}
```

### Add a 3D Mesh

```json
{
  "world": [
    {
      "type": "mesh3d",
      "mesh": {"Sphere": {"radius": 1.0, "subdivisions": 32}},
      "material": {
        "base_color": {"r": 0.8, "g": 0.2, "b": 0.8, "a": 1.0},
        "metallic": 0.5,
        "roughness": 0.3
      },
      "transform": {
        "position": {"x": 0, "y": 1, "z": 0}
      }
    }
  ]
}
```

### Add Animation (NEW!)

```json
{
  "type": "mesh3d",
  "mesh": "Cube",
  "transform": {
    "position": {"x": 0, "y": 1, "z": 0}
  },
  "animation": {
    "animation_type": {
      "type": "Rotate",
      "axis": {"x": 0, "y": 1, "z": 0},
      "degrees": 360
    },
    "duration": 3.0,
    "looping": true,
    "easing": "Linear"
  }
}
```

### Add Particle System (NEW!)

```json
{
  "type": "particles",
  "transform": {
    "position": {"x": 0, "y": 1, "z": 0}
  },
  "emission_rate": 20.0,
  "lifetime": 2.0,
  "color": {"r": 0.2, "g": 0.7, "b": 1.0, "a": 1.0},
  "size": 0.1,
  "velocity": {"x": 0, "y": 3, "z": 0},
  "gravity": {"x": 0, "y": -9.8, "z": 0}
}
```

### Add a Checkbox (NEW!)

```json
{
  "type": "checkbox",
  "label": "Enable Sound",
  "checked": true,
  "on_change": "sound_toggle"
}
```

### Add a Slider (NEW!)

```json
{
  "type": "slider",
  "min": 0,
  "max": 100,
  "value": 75,
  "on_change": "volume_changed"
}
```

## Advanced Features

### Enable Hot Reloading

Edit your main.rs to automatically reload when JSON changes:

```rust
use bevy_json_ui::enable_hot_reload;

fn main() {
    let mut app = App::new();
    app.add_plugins(DefaultPlugins)
       .add_plugins(JsonScenePlugin);
    
    enable_hot_reload(&mut app, "examples/my_scene.json")
        .expect("Failed to enable hot reload");
    
    app.run();
}
```

Now edit the JSON file while running - changes apply instantly!

### Listen to Events

```rust
use bevy_json_ui::ComponentEvent;

fn handle_events(mut events: EventReader<ComponentEvent>) {
    for event in events.read() {
        println!("Event: {} - {}", event.event_type, event.data);
    }
}

// Add to your app:
app.add_systems(Update, handle_events);
```

Happy coding! 🎮
