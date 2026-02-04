# Features Showcase

This document provides a comprehensive overview of all features available in the Bevy JSON UI/3D Converter.

## Table of Contents
1. [UI Components](#ui-components)
2. [3D Objects & Rendering](#3d-objects--rendering)
3. [Animation System](#animation-system)
4. [Particle Systems](#particle-systems)
5. [Audio](#audio)
6. [Developer Tools](#developer-tools)

---

## UI Components

### Basic Components

#### Container
Flexbox-based layout container with full CSS-like controls.

**Features:**
- Flexbox direction (Row, Column, RowReverse, ColumnReverse)
- Justify content (FlexStart, FlexEnd, Center, SpaceBetween, SpaceAround, SpaceEvenly)
- Align items (FlexStart, FlexEnd, Center, Stretch)
- Padding, margins, borders
- Background colors with alpha
- Nested children support

#### Text
Customizable text elements.

**Features:**
- Font size control
- Color customization (RGBA)
- Style inheritance
- Automatic wrapping

#### Button
Interactive button with visual feedback.

**Features:**
- Customizable labels
- Hover states (automatic)
- Press states (automatic)
- Action callbacks
- Custom colors

#### Image
Display images from assets.

**Features:**
- Asset path support
- Style-based sizing
- Aspect ratio preservation

### Advanced Components

#### Slider
Interactive value selector.

**Features:**
- Configurable min/max range
- Current value display
- Draggable handle
- Change event callbacks
- Custom styling

**Use Cases:**
- Volume controls
- Brightness settings
- Game difficulty
- Parameter adjustments

#### Checkbox
Boolean toggle with label.

**Features:**
- Checked/unchecked states
- Visual feedback
- Labels
- Change event callbacks
- Group management

**Use Cases:**
- Settings toggles
- Feature enablement
- Multi-selection lists
- Preferences

#### Radio Button
Exclusive selection within groups.

**Features:**
- Group-based exclusivity
- Visual selection indicator
- Labels
- Change events
- State persistence

**Use Cases:**
- Difficulty selection
- Character choice
- Mode selection
- Option lists

#### Text Input
Text entry field.

**Features:**
- Placeholder text
- Current value display
- Focus indication
- Change callbacks
- Validation support

**Use Cases:**
- Name entry
- Search boxes
- Chat input
- Configuration

#### Progress Bar
Visual progress indicator.

**Features:**
- Current/max value
- Customizable colors (bar & background)
- Percentage-based display
- Dynamic updates

**Use Cases:**
- Loading screens
- Health bars
- Experience meters
- Download progress

---

## 3D Objects & Rendering

### Primitive Meshes

#### Cube
Basic cubic mesh.

#### Sphere
Customizable sphere with subdivision control.
- Radius adjustment
- Subdivision levels for smoothness

#### Plane
Flat square surface.
- Size customization
- Perfect for ground planes

#### Capsule
Pill-shaped 3D object.
- Radius and depth control
- Great for characters

#### Cylinder
Cylindrical mesh.
- Radius and height customization
- Useful for pillars, trees

### Custom Meshes

#### File Loading
Load meshes from external files.

**Supported Formats:**
- GLTF/GLB
- OBJ
- Other Bevy-supported formats

**Features:**
- Direct file path specification
- Automatic loading
- Asset server integration

### Materials

#### PBR Properties
Physically-based rendering support.

**Properties:**
- Base color (RGBA)
- Metallic (0.0-1.0)
- Roughness (0.0-1.0)
- Emissive color

#### Texture Support
Comprehensive texture mapping.

**Texture Types:**
- Base color textures
- Emissive textures
- Metallic/roughness combined
- Normal maps

### Lighting

#### Point Light
Omnidirectional light source.
- Position-based
- Intensity control
- Color customization
- Falloff distance

#### Directional Light
Sun-like directional lighting.
- Direction-based
- No position falloff
- Illuminance control
- Shadow casting

#### Spot Light
Focused cone light.
- Position and direction
- Cone angle
- Intensity control
- Great for spotlights

### Cameras

#### Perspective Camera
Standard 3D camera.
- Field of view
- Position and rotation
- Look-at point

#### Orthographic Camera
2D/isometric projection.
- No perspective distortion
- Perfect for 2D games
- Strategy games

---

## Animation System

### Animation Types

#### Rotate
Spin objects around an axis.

**Parameters:**
- Axis vector (x, y, z)
- Rotation degrees
- Duration
- Looping
- Easing

**Example Use Cases:**
- Spinning coins
- Rotating platforms
- Planet rotation
- Propellers

#### Translate
Move from point A to point B.

**Parameters:**
- From position
- To position
- Duration
- Looping
- Easing

**Example Use Cases:**
- Elevators
- Moving platforms
- Patrol routes
- Cutscene movement

#### Scale
Grow or shrink objects.

**Parameters:**
- From scale
- To scale
- Duration
- Looping
- Easing

**Example Use Cases:**
- Powerup collection
- Object spawning
- Destruction effects
- Emphasis

#### Bounce
Bouncing up and down motion.

**Parameters:**
- Bounce height
- Duration
- Looping
- Easing

**Example Use Cases:**
- Collectible items
- Jump pads
- Interactive objects
- Attention grabbers

#### Pulse
Breathing/pulsing scale effect.

**Parameters:**
- Min scale
- Max scale
- Duration
- Looping
- Easing

**Example Use Cases:**
- Highlighted items
- Selection indicators
- Heartbeat effects
- Alert indicators

### Easing Functions

**Linear**: Constant speed throughout
**EaseIn**: Start slow, accelerate
**EaseOut**: Start fast, decelerate
**EaseInOut**: Smooth acceleration and deceleration
**Bounce**: Spring-like bounce effect

### Can Animate
- Meshes (all types)
- Lights (all types)
- Cameras

---

## Particle Systems

### Emitter Properties

**Emission Rate**: Particles per second
**Particle Lifetime**: How long each particle lives
**Color**: RGBA color of particles
**Size**: Particle size
**Initial Velocity**: Starting direction and speed
**Gravity**: Gravity effect on particles

### Physics Simulation

Particles simulate realistic physics:
- Velocity-based motion
- Gravity acceleration
- Lifetime management
- Automatic cleanup

### Use Cases

- Fire effects
- Water fountains
- Smoke
- Magic spells
- Explosions
- Snow/rain
- Sparks
- Dust clouds

---

## Audio

### Background Audio

Non-spatial audio playback.

**Features:**
- Volume control (0.0-1.0)
- Looping support
- Autoplay option
- Multiple audio formats

**Use Cases:**
- Background music
- Menu sounds
- System notifications
- UI feedback

### Spatial Audio

3D positioned sound.

**Features:**
- Position-based attenuation
- Distance falloff
- Direction awareness
- Volume control

**Use Cases:**
- Ambient sounds
- Environmental audio
- Character sounds
- Interactive objects

### Supported Formats
- OGG Vorbis
- MP3
- WAV
- FLAC
- Other Bevy-supported formats

---

## Developer Tools

### JSON Validation

**Pre-Load Validation:**
- Schema compliance
- Required field checks
- Type validation
- Range validation
- Logical consistency

**Runtime Validation:**
- Prevents crashes
- Clear error messages
- File and line reporting
- Helpful suggestions

**Validates:**
- Color ranges (0.0-1.0)
- Positive dimensions
- Min < Max constraints
- Non-zero vectors
- Path existence
- File formats

### Hot Reloading

**File Watching:**
- Automatic detection of changes
- Configurable watch paths
- Debounced updates
- Cross-platform support

**Reload Process:**
- Despawn old entities
- Clear resources
- Reload JSON
- Respawn entities
- Maintain game state

**Benefits:**
- Instant feedback
- No recompilation
- Rapid iteration
- Designer-friendly

### Event System

**Component Events:**
- Button clicks
- Checkbox toggles
- Radio selections
- Slider changes
- Text input updates

**Event Data:**
- Event type
- Event ID
- Associated data
- Timestamp

**Rust Integration:**
- EventReader system
- Type-safe events
- Pattern matching
- Custom handlers

### Error Handling

**Comprehensive Errors:**
- File not found
- Parse errors
- Validation failures
- Missing assets
- Invalid references

**Error Messages:**
- Clear descriptions
- Context information
- Suggested fixes
- Line numbers (when applicable)

---

## Performance Characteristics

### Optimizations

**UI System:**
- Efficient flexbox layout
- Minimal recomputation
- Cached styles

**3D Rendering:**
- Standard Bevy pipelines
- Material instancing
- Efficient mesh handling

**Animations:**
- Delta-time based
- Frame-rate independent
- Minimal overhead

**Particles:**
- Efficient spawning
- Automatic cleanup
- Pooling support

### Scalability

**UI:**
- Handles hundreds of elements
- Nested layouts supported
- Responsive updates

**3D:**
- Standard Bevy performance
- Mesh instancing available
- LOD support (via custom meshes)

**Particles:**
- Thousands of particles
- Physics-based simulation
- Automatic lifecycle

---

## Integration

### Mixing JSON and Code

You can combine JSON-defined scenes with Rust code:
- Load JSON for structure
- Add components in Rust
- Modify at runtime
- Custom systems

### Asset Pipeline

Works with Bevy's asset system:
- Standard asset paths
- Hot reloading support
- Asset preprocessing
- Format conversion

### Extensibility

Easy to extend:
- Add custom component types
- Create new animation types
- Define custom easing functions
- Implement custom validators

---

## Best Practices

### UI Design
1. Use containers for layout
2. Leverage flexbox for responsive design
3. Keep nesting reasonable (<5 levels)
4. Use consistent spacing

### 3D Scenes
1. Balance primitive vs custom meshes
2. Use textures for visual detail
3. Optimize particle counts
4. Proper lighting setup

### Animations
1. Choose appropriate easing
2. Set reasonable durations
3. Use looping wisely
4. Test performance

### Performance
1. Limit particle emitters
2. Reuse materials when possible
3. Optimize mesh complexity
4. Profile regularly

---

## Future Roadmap

See [CHANGELOG.md](CHANGELOG.md) for completed features and [README.md](README.md) for upcoming enhancements.
