# Changelog

All notable changes to the Bevy JSON UI/3D Converter will be documented in this file.

## [0.2.0] - 2025-02-03

### Added - Major Feature Release 🎉

#### UI Components
- **Slider**: Interactive slider component with min/max values and change callbacks
- **Checkbox**: Boolean toggle with label and change events
- **Radio Button**: Exclusive selection buttons with group support
- **Text Input**: Text input field with placeholder support (visual representation)
- **Progress Bar**: Visual progress indicator with customizable colors

#### Animation System
- **Rotate Animation**: Rotate objects around any axis with configurable degrees
- **Translate Animation**: Move objects from one position to another
- **Scale Animation**: Scale objects between two sizes
- **Bounce Animation**: Bouncing effect with configurable height
- **Pulse Animation**: Pulsing/breathing effect between min and max scale
- **Easing Functions**: Linear, EaseIn, EaseOut, EaseInOut, Bounce
- **Looping Support**: Animations can loop infinitely or play once
- **Apply to Any 3D Object**: Meshes, lights, and cameras can all be animated

#### Particle System
- **Particle Emitters**: Configurable particle emission rate
- **Particle Physics**: Velocity and gravity for realistic motion
- **Particle Lifetime**: Control how long particles exist
- **Visual Customization**: Color, size, and emissive properties
- **Multiple Emitters**: Support for multiple simultaneous particle systems

#### Audio Support
- **Background Music**: Non-spatial audio playback
- **Spatial Audio**: 3D positioned sound with distance attenuation
- **Playback Control**: Volume, looping, and autoplay settings
- **File Format Support**: OGG, MP3, WAV, and other formats supported by Bevy

#### 3D Enhancements
- **Custom Mesh Loading**: Load meshes from GLTF, OBJ, and other file formats
- **Texture Support**:
  - Base color textures
  - Emissive textures
  - Metallic/roughness textures
  - Normal map textures
- **File-based Meshes**: Define mesh paths in JSON instead of only primitives

#### Developer Tools
- **JSON Validation**: Comprehensive validation system that checks:
  - Required fields
  - Value ranges (colors, scales, etc.)
  - Type correctness
  - Logical consistency (min < max, etc.)
- **Hot Reloading**: Watch JSON files and automatically reload scenes on changes
  - Live editing without recompilation
  - File system watcher integration
  - Automatic entity cleanup and respawn
- **Event System**: Custom event handling for interactive components
  - Event callbacks in JSON
  - Rust-side event listeners
  - Event logging for debugging

#### Documentation
- **Comprehensive README**: Updated with all new features and examples
- **Schema Reference**: Complete JSON schema documentation
- **Advanced Usage Guide**: Tutorials for animations, particles, audio, and more
- **Example Demos**: 
  - Advanced UI demo showcasing all new components
  - Animations demo with particles and effects

### Changed

- **spawn_world** signature now requires `asset_server: &AssetServer` parameter for file loading support
- **MaterialDef** expanded to include texture paths
- **MeshType** now supports file-based mesh loading
- **Plugin** now registers all new systems (animations, particles, events, etc.)
- All 3D node types (Mesh3D, Light, Camera) now support optional animation

### Technical Details

#### New Modules
- `components.rs`: Defines all component types for UI, animations, particles, and audio
- `systems.rs`: Contains all update systems for animations, particles, and interactions
- `validation.rs`: JSON schema validation logic
- `hot_reload.rs`: File watching and hot reload functionality

#### New Dependencies
- `notify`: For file system watching
- `jsonschema`: For JSON schema validation

#### Performance Considerations
- Particle systems use efficient spawning with timers
- Animations use delta time for smooth, frame-rate independent motion
- Hot reloading only triggers when files actually change
- Validation happens once at load time, not every frame

## [0.1.0] - Initial Release

### Added
- Basic UI components (Container, Text, Button, Image)
- Flexbox layout system
- 3D primitive meshes (Cube, Sphere, Plane, Capsule, Cylinder)
- PBR materials (base color, metallic, roughness, emissive)
- Lighting (Point, Directional, Spot)
- Cameras (Perspective, Orthographic)
- Transform support (position, rotation, scale)
- JSON scene loading
- Basic plugin system
