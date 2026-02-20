# 🌍 Elpian 3D Graphics Reference

Complete reference for Elpian's 3D scene system. Scenes are defined in JSON and rendered via **Bevy** (Rust/GPU with native FFI or WASM) or the **pure-Dart Canvas renderer** (software fallback). The Dart renderer automatically activates when the Rust library is unavailable.

---

## 📑 Table of Contents

1. [🏗️ Scene Structure](#scene-structure)
2. [🧱 Scene Nodes](#scene-nodes)
3. [🔷 Mesh Generators](#mesh-generators)
4. [🎨 Material System](#material-system)
5. [💡 Lighting](#lighting)
6. [📷 Camera System](#camera-system)
7. [🎬 Animations](#animations)
8. [🔥 Particle System](#particle-system)
9. [⚡ Physics](#physics)
10. [🌅 Environment](#environment)
11. [🖥️ Rendering Pipeline](#rendering-pipeline)
12. [🧩 Widget Integration](#widget-integration)
13. [📦 Complete Examples](#complete-examples)

---

## 🏗️ Scene Structure

A 3D scene is a JSON object with a `"world"` array containing scene nodes:

```json
{
  "world": [
    { "type": "environment", ... },
    { "type": "camera", ... },
    { "type": "light", ... },
    { "type": "mesh3d", ... }
  ]
}
```

Scenes can also include a `"ui"` array for 2D overlay elements (see [2D_GRAPHICS.md](2D_GRAPHICS.md)):

```json
{
  "ui": [ /* 2D elements */ ],
  "world": [ /* 3D elements */ ]
}
```

---

## 🧱 Scene Nodes

## `mesh3d`

Renderable 3D geometry with materials, transforms, and optional animation.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `id` | String? | null | Node identifier |
| `mesh` | MeshType | *required* | Geometry primitive |
| `material` | MaterialDef | {} | PBR material properties |
| `transform` | TransformDef | {} | Position, rotation, scale |
| `animation` | AnimationDef? | null | Animation definition |

```json
{
  "type": "mesh3d",
  "id": "hero",
  "mesh": {"shape": "File", "path": "models/robot.gltf"},
  "material": {
    "base_color": { "r": 0.8, "g": 0.2, "b": 0.1, "a": 1.0 },
    "metallic": 0.5,
    "roughness": 0.3
  },
  "transform": {
    "position": { "x": 0, "y": 2, "z": 0 },
    "scale": { "x": 2, "y": 2, "z": 2 }
  },
  "animation": {
    "animation_type": { "type": "Rotate", "axis": { "x": 0, "y": 1, "z": 0 }, "degrees": 360 },
    "duration": 4.0,
    "looping": true,
    "easing": "Linear"
  }
}
```

---

## `light`

Light source node.

| Prop | Type | Required | Default | Description |
|---|---|---|---|---|
| `type` | `"light"` | Yes | - | Node tag. |
| `id` | `String?` | No | `null` | Optional id. |
| `light_type` | `LightType` | Yes | - | `Point`, `Directional`, `Spot` (and parser supports area in core runtime). |
| `color` | `ColorDef?` | No | renderer default | Light tint. |
| `intensity` | `f32?` | No | renderer default | Light power/illuminance. |
| `transform` | `TransformDef` | No | `{}` | Position and direction basis via rotation. |
| `animation` | `AnimationDef?` | No | `null` | Optional animated light motion. |
| `range` | `f32?` (parser path) | No | parser default | Distance falloff range. |
| `inner_cone_angle` | `f32?` (spot/parser) | No | parser default | Spot inner cone. |
| `outer_cone_angle` | `f32?` (spot/parser) | No | parser default | Spot outer cone. |
| `cast_shadow` | `bool?` (parser path) | No | `false` | Enable shadow casting. |

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `id` | String? | null | Node identifier |
| `light_type` | String | *required* | `Point`, `Directional`, `Spot`, or `Area` |
| `color` | ColorDef | white | Light color |
| `intensity` | float | 1.0 | Brightness multiplier |
| `range` | float | null | Attenuation distance (Point/Spot) |
| `inner_cone_angle` | float | null | Inner spotlight angle |
| `outer_cone_angle` | float | null | Outer spotlight angle |
| `cast_shadow` | bool | false | Enable shadow casting |
| `transform` | TransformDef | {} | Position and direction |
| `animation` | AnimationDef? | null | Animation definition |

**Light Types:**

| Type | Behavior | Key Parameters |
|------|----------|---------------|
| `Directional` | Parallel rays (sun/moon) | `intensity`, `direction` (rotation) |
| `Point` | Omnidirectional from a point | `intensity`, `range`, position |
| `Spot` | Cone-shaped beam | `intensity`, `range`, `inner_cone_angle`, `outer_cone_angle` |
| `Area` | Area light source | `intensity`, position |

```json
{
  "type": "light",
  "id": "sun",
  "light_type": "Directional",
  "color": { "r": 1.0, "g": 0.95, "b": 0.8, "a": 1.0 },
  "intensity": 1.5,
  "cast_shadow": true,
  "transform": {
    "rotation": { "x": -45, "y": 30, "z": 0 }
  }
}
```

```json
{
  "type": "light",
  "light_type": "Point",
  "color": { "r": 1.0, "g": 0.6, "b": 0.2, "a": 1.0 },
  "intensity": 500.0,
  "range": 20.0,
  "transform": {
    "position": { "x": -3, "y": 4, "z": 0 }
  }
}
```

---

## `camera`

View/projection node.

| Prop | Type | Required | Default | Description |
|---|---|---|---|---|
| `type` | `"camera"` | Yes | - | Node tag. |
| `id` | `String?` | No | `null` | Optional id. |
| `camera_type` | `CameraType` | No | `Perspective` | Projection mode. |
| `transform` | `TransformDef` | No | `{}` | Camera placement/orientation. |
| `fov` | `f32?` | No | runtime default | Vertical field-of-view (perspective). |
| `near` | `f32?` | No | runtime default | Near clipping plane. |
| `far` | `f32?` | No | runtime default | Far clipping plane. |
| `animation` | `AnimationDef?` | No | `null` | Optional camera animation. |
| `ortho_size` | `f32?` (parser path) | No | parser default | Orthographic half-size. |
| `mode` | `String?` (parser path) | No | `fixed` | `fixed`, `orbit`, `first_person`, `follow`, `flythrough`. |
| `orbit_speed` | `f32?` (parser) | No | parser default | Orbit speed. |
| `orbit_radius` | `f32?` (parser) | No | parser default | Orbit radius. |

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `id` | String? | null | Node identifier |
| `camera_type` | String | 'Perspective' | `Perspective` or `Orthographic` |
| `mode` | String | 'Fixed' | Camera behavior mode |
| `fov` | float | null | Field of view (degrees) |
| `near` | float | null | Near clipping plane |
| `far` | float | null | Far clipping plane |
| `ortho_size` | float | null | Orthographic view size |
| `orbit_speed` | float | null | Orbit rotation speed |
| `follow_offset` | Vec3Def? | null | Follow mode offset |
| `shake_amount` | float | null | Camera shake intensity |
| `shake_decay` | float | null | Camera shake decay rate |
| `transform` | TransformDef | {} | Camera position and orientation |
| `animation` | AnimationDef? | null | Animation definition |

**Camera Modes:**

| Mode | Description |
|------|-------------|
| `Fixed` | Stationary camera |
| `Orbit` | Orbits around target with adjustable speed/radius |
| `FirstPerson` | First-person view |
| `Follow` | Follows target with offset |
| `Flythrough` | Flying camera |

```json
{
  "type": "camera",
  "camera_type": "Perspective",
  "mode": "Orbit",
  "fov": 60,
  "orbit_speed": 0.5,
  "transform": {
    "position": { "x": 0, "y": 5, "z": 10 },
    "rotation": { "x": -20, "y": 0, "z": 0 }
  }
}
```

---

### particles

Particle system emitter with configurable shapes and behaviors.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `id` | String? | null | Node identifier |
| `emitter_shape` | String | 'Point' | `Point`, `Sphere`, `Cone`, `Box`, `Ring` |
| `emission_rate` | float | 10.0 | Particles per second |
| `lifetime` | float | 1.0 | Particle lifespan (seconds) |
| `start_color` | ColorDef | white | Initial particle color |
| `end_color` | ColorDef? | null | Final particle color |
| `start_size` | float | 0.1 | Initial particle size |
| `end_size` | float? | null | Final particle size |
| `start_alpha` | float | 1.0 | Initial opacity |
| `end_alpha` | float? | null | Final opacity |
| `speed` | float | 1.0 | Initial particle speed |
| `speed_variance` | float | 0.0 | Speed randomization |
| `spread` | float | 0.0 | Emission angle spread |
| `gravity` | Vec3Def | {0, -9.8, 0} | Gravity vector |
| `wind` | Vec3Def? | null | Wind force |
| `max_particles` | int | 100 | Maximum particle count |
| `world_space` | bool | false | Emit in world space |
| `blend_mode` | String | 'normal' | `normal` or `additive` |
| `burst_count` | int | 0 | Particles per burst |
| `prewarm` | bool | false | Initialize with aged particles |
| `transform` | TransformDef | {} | Emitter position |

```json
{
  "type": "particles",
  "emitter_shape": "Cone",
  "emission_rate": 50.0,
  "lifetime": 3.0,
  "start_color": { "r": 1.0, "g": 0.8, "b": 0.0, "a": 1.0 },
  "end_color": { "r": 1.0, "g": 0.0, "b": 0.0, "a": 0.0 },
  "start_size": 0.15,
  "end_size": 0.05,
  "speed": 4.0,
  "spread": 0.5,
  "gravity": { "x": 0, "y": -2, "z": 0 },
  "max_particles": 200,
  "transform": { "position": { "x": 0, "y": 0, "z": 0 } }
}
```

---

### environment

Global scene environment settings.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `ambient_color` | ColorDef | white | Ambient light color |
| `ambient_intensity` | float | 0.3 | Ambient light strength |
| `sky_color_top` | ColorDef? | null | Zenith sky color |
| `sky_color_bottom` | ColorDef? | null | Horizon sky color |
| `fog_type` | String | 'none' | `none`, `linear`, `exponential` |
| `fog_color` | ColorDef? | null | Fog color |
| `fog_near` | float | null | Linear fog start distance |
| `fog_far` | float | null | Linear fog end distance |
| `fog_density` | float | null | Exponential fog density |
| `gravity` | Vec3Def | {0, -9.8, 0} | World gravity vector |

```json
{
  "type": "environment",
  "ambient_color": { "r": 0.3, "g": 0.3, "b": 0.4, "a": 1.0 },
  "ambient_intensity": 0.4,
  "sky_color_top": { "r": 0.1, "g": 0.15, "b": 0.4, "a": 1.0 },
  "sky_color_bottom": { "r": 0.5, "g": 0.6, "b": 0.8, "a": 1.0 },
  "fog_type": "linear",
  "fog_color": { "r": 0.7, "g": 0.7, "b": 0.8, "a": 1.0 },
  "fog_near": 50.0,
  "fog_far": 200.0
}
```

---

### group

Container node for organizing scene hierarchy.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `id` | String? | null | Node identifier |
| `children` | SceneNode[] | [] | Child nodes |
| `transform` | TransformDef | {} | Group transform (applied to children) |
| `visible` | bool | true | Group visibility |

```json
{
  "type": "group",
  "transform": { "position": { "x": 5, "y": 0, "z": 0 } },
  "children": [
    { "type": "mesh3d", "mesh": "Cube", ... },
    { "type": "mesh3d", "mesh": { "Sphere": { "radius": 0.5, "subdivisions": 16 } }, ... }
  ]
}
```

---

### text3d

3D text rendering.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `id` | String? | null | Node identifier |
| `text` | String | *required* | Text content |
| `transform` | TransformDef | {} | Text position |
| `material` | MaterialDef | {} | Text material |

---

## 🔷 Mesh Generators

Built-in geometry primitives available for `mesh3d` nodes.

### Primitive Meshes

| Mesh | JSON | Parameters | Description |
|------|------|-----------|-------------|
| Cube | `"Cube"` | none | Unit cube |
| Sphere | `{"Sphere": {...}}` | `radius`, `subdivisions` | UV sphere |
| IcoSphere | `{"IcoSphere": {...}}` | `radius`, `subdivisions` | Icosphere |
| Plane | `{"Plane": {...}}` | `size`, `subdivisions` | Flat plane |
| Cylinder | `{"Cylinder": {...}}` | `radius`, `height`, `segments` | Cylinder |
| Cone | `{"Cone": {...}}` | `radius`, `height`, `segments` | Cone |
| Torus | `{"Torus": {...}}` | `radius`, `tube_radius`, `segments` | Donut shape |
| Capsule | `{"Capsule": {...}}` | `radius`, `depth` | Spherocylinder |
| Pyramid | `{"Pyramid": {...}}` | `base`, `height` | 4-sided pyramid |
| Wedge | `{"Wedge": {...}}` | parameters | Wedge/ramp shape |
| Heightmap | `{"Heightmap": {...}}` | `heights` (array), `width`, `depth` | Height field mesh |
| Billboard | `{"Billboard": {...}}` | `width`, `height` | Camera-facing quad |

### Examples

```json
"Cube"
```

```json
{ "Sphere": { "radius": 2.0, "subdivisions": 32 } }
```

```json
{ "Torus": { "radius": 3.0, "tube_radius": 0.5 } }
```

```json
{ "Capsule": { "radius": 0.5, "depth": 2.0 } }
```

```json
{ "Cylinder": { "radius": 1.0, "height": 3.0, "segments": 24 } }
```

---

## 🎨 Material System

PBR (Physically Based Rendering) material properties for mesh3d nodes.

### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `base_color` | ColorDef | white | Albedo/diffuse color |
| `metallic` | float | 0.0 | Metallic factor (0.0–1.0) |
| `roughness` | float | 0.5 | Surface roughness (0.0–1.0) |
| `emissive` | ColorDef? | null | Self-illumination color |
| `emissive_strength` | float | 1.0 | Emissive intensity multiplier |
| `alpha` | float | 1.0 | Transparency (0.0–1.0) |
| `alpha_mode` | String | 'opaque' | `opaque`, `blend`, `cutoff` |
| `alpha_cutoff` | float | 0.5 | Cutoff threshold |
| `double_sided` | bool | false | Render both faces |
| `wireframe` | bool | false | Wireframe rendering |
| `unlit` | bool | false | Ignore lighting |

### Procedural Textures

The Dart renderer supports procedural texture generation:

| Texture Type | Parameters | Description |
|-------------|-----------|-------------|
| `checkerboard` | `texture_color2`, `texture_scale` | Alternating color grid |
| `gradient` | `texture_color2` | UV-based color gradient |
| `noise` | `texture_color2`, `texture_scale` | Perlin-like noise pattern |
| `stripes` | `texture_color2`, `texture_scale` | Horizontal stripe pattern |
| `none` | — | Solid color (default) |

```json
{
  "base_color": { "r": 0.8, "g": 0.2, "b": 0.1, "a": 1.0 },
  "metallic": 0.7,
  "roughness": 0.3,
  "emissive": { "r": 0.1, "g": 0.0, "b": 0.0, "a": 1.0 },
  "alpha_mode": "opaque",
  "double_sided": false
}
```

### Alpha Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| `opaque` | Fully opaque | Solid objects |
| `cutoff` | Binary transparency (opaque or invisible) | Leaves, fences, cutouts |
| `blend` | Per-pixel alpha blending | Glass, smoke, water |

---

## 💡 Lighting

The Dart renderer implements Blinn-Phong shading with PBR-inspired material interaction.

### Lighting Model

For each vertex, lighting is computed as:

```
color = ambient + diffuse + specular
```

- **Ambient**: `ambient_color * ambient_intensity * base_color`
- **Diffuse**: `light_color * intensity * max(0, N·L) * base_color`
  - Lambert diffuse model
  - Point/Spot lights use inverse-square distance attenuation
- **Specular**: `light_color * intensity * pow(max(0, N·H), shininess)`
  - Blinn-Phong specular with half-vector
  - `shininess` derived from roughness: `pow(2, (1 - roughness) * 10)`
  - Specular strength scaled by metallic factor
- **Spot lights**: Additional cone falloff between inner and outer angle

### Shadow Support

The Bevy (Rust/GPU) renderer supports real-time shadows. The Dart renderer does not include shadow mapping.

| Prop | Type | Required | Default | Description |
|---|---|---|---|---|
| `r` | `f32` | No | `1.0` | Red channel (0..1) |
| `g` | `f32` | No | `1.0` | Green channel (0..1) |
| `b` | `f32` | No | `1.0` | Blue channel (0..1) |
| `a` | `f32` | No | `1.0` | Alpha channel (0..1) |

Example: `{"r": 0.2, "g": 0.6, "b": 1.0, "a": 1.0}`

## 📷 Camera System

### Camera Types

| Type | Projection | Description |
|------|-----------|-------------|
| `Perspective` | Perspective with FOV | Standard 3D perspective |
| `Orthographic` | Parallel projection | No perspective distortion |

### Camera Modes

| Mode | Description | Key Properties |
|------|-------------|---------------|
| `Fixed` | Stationary camera | `position`, `target` |
| `Orbit` | Auto-orbits around target | `orbit_speed`, `position` |
| `FirstPerson` | First-person view | `position`, direction |
| `Follow` | Tracks a target with offset | `follow_offset`, `target` |
| `Flythrough` | Free-flying camera | `position`, direction |

### Orbit Camera Example

```json
{
  "type": "camera",
  "camera_type": "Perspective",
  "mode": "Orbit",
  "fov": 60,
  "near": 0.1,
  "far": 1000,
  "orbit_speed": 0.3,
  "transform": {
    "position": { "x": 0, "y": 8, "z": 15 }
  }
}
```

---

## 🎬 Animations

### Animation Types

| Type | Parameters | Description |
|------|-----------|-------------|
| `Rotate` | `axis` (Vec3), `degrees` (float) | Rotate around an axis |
| `Translate` | `from` (Vec3), `to` (Vec3) | Move between two points |
| `Scale` | `from` (Vec3), `to` (Vec3) | Scale between two sizes |
| `Bounce` | `height` (float) | Bounce up and down |
| `Pulse` | `min_scale` (float), `max_scale` (float) | Scale pulsing |
| `Orbit` | parameters | Orbital movement |
| `Swing` | parameters | Swinging rotation |
| `Shake` | parameters | Random vibration |
| `Float` | parameters | Floating vertical motion |
| `Spin` | parameters | Continuous spinning |

### Animation Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `animation_type` | AnimationType | *required* | Animation kind |
| `duration` | float | 1.0 | Duration in seconds |
| `looping` | bool | false | Repeat the animation |
| `easing` | String | 'Linear' | Timing function |
| `delay` | float | 0.0 | Delay before start |

### Easing Types

`Linear`, `EaseIn`, `EaseOut`, `EaseInOut`, `Bounce`, `Elastic`, `Back`, `Sine`

### Examples

**Continuous Y-axis rotation:**
```json
{
  "animation_type": { "type": "Rotate", "axis": { "x": 0, "y": 1, "z": 0 }, "degrees": 360 },
  "duration": 4.0,
  "looping": true,
  "easing": "Linear"
}
```

**Bouncing:**
```json
{
  "animation_type": { "type": "Bounce", "height": 2.0 },
  "duration": 2.0,
  "looping": true,
  "easing": "EaseInOut"
}
```

**Translate back and forth:**
```json
{
  "animation_type": {
    "type": "Translate",
    "from": { "x": -5, "y": 0, "z": 0 },
    "to": { "x": 5, "y": 0, "z": 0 }
  },
  "duration": 3.0,
  "looping": true,
  "easing": "EaseInOut"
}
```

**Pulsing:**
```json
{
  "animation_type": { "type": "Pulse", "min_scale": 0.8, "max_scale": 1.2 },
  "duration": 1.5,
  "looping": true,
  "easing": "EaseInOut"
}
```

### Keyframe Channels

The Dart renderer supports keyframe animation tracks for position, rotation, and scale with linear interpolation between keyframes.

---

## 🔥 Particle System

### Emitter Shapes

| Shape | Description |
|-------|-------------|
| `Point` | Emit from a single point |
| `Sphere` | Emit from a spherical volume |
| `Cone` | Emit in a conical direction |
| `Box` | Emit from a cubic volume |
| `Ring` | Emit from a ring shape |

### Particle Properties

Each particle has:
- Position, velocity (affected by gravity/wind)
- Color (interpolated from `start_color` to `end_color`)
- Size (interpolated from `start_size` to `end_size`)
- Alpha (interpolated from `start_alpha` to `end_alpha`)
- Life/lifetime tracking
- Rotation and rotation speed

### Blend Modes

| Mode | Description |
|------|-------------|
| `normal` | Standard alpha blending |
| `additive` | Additive blending (fire, sparks, glows) |

### Fire Effect Example

```json
{
  "type": "particles",
  "emitter_shape": "Cone",
  "emission_rate": 80.0,
  "lifetime": 1.5,
  "start_color": { "r": 1.0, "g": 0.8, "b": 0.0, "a": 1.0 },
  "end_color": { "r": 1.0, "g": 0.0, "b": 0.0, "a": 0.0 },
  "start_size": 0.3,
  "end_size": 0.05,
  "speed": 3.0,
  "speed_variance": 1.0,
  "spread": 0.3,
  "gravity": { "x": 0, "y": 1, "z": 0 },
  "blend_mode": "additive",
  "max_particles": 300,
  "transform": { "position": { "x": 0, "y": 0, "z": 0 } }
}
```

---

## ⚡ Physics

Basic rigid-body physics simulation in the Dart renderer.

### RigidBody Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `velocity` | Vec3Def | {0,0,0} | Linear velocity |
| `angular_velocity` | Vec3Def | {0,0,0} | Rotational velocity |
| `mass` | float | 1.0 | Object mass |
| `restitution` | float | 0.0 | Bounciness (0.0–1.0) |
| `friction` | float | 0.3 | Surface friction |
| `is_static` | bool | false | Immovable object |
| `use_gravity` | bool | true | Apply gravity |
| `collider_type` | String | 'Box' | `Sphere`, `Box`, `Plane` |

### Physics Features

- Gravity application
- Friction damping
- Ground collision with velocity reflection
- Basic sphere/box/plane colliders

### Example C: Physics puzzle arena (rigid bodies + static geometry)

```json
{
  "world": [
    {"type": "environment", "ambient_intensity": 0.24},
    {"type": "camera", "camera_type": "Perspective", "transform": {"position": {"x": 0, "y": 14, "z": 28}, "rotation": {"x": -18, "y": 0, "z": 0}}},
    {"type": "light", "light_type": "Directional", "intensity": 1.1, "transform": {"rotation": {"x": -42, "y": -15, "z": 0}}},

    {"type": "mesh3d", "id": "ground", "mesh": {"shape": "Plane", "size": 80}, "material": {"base_color": {"r": 0.2, "g": 0.2, "b": 0.22, "a": 1}, "roughness": 0.95}},

## 🌅 Environment

### 🌤️ Sky Rendering

The Dart renderer supports a two-color gradient sky:

```json
{
  "type": "environment",
  "sky_color_top": { "r": 0.1, "g": 0.15, "b": 0.4, "a": 1.0 },
  "sky_color_bottom": { "r": 0.5, "g": 0.6, "b": 0.8, "a": 1.0 }
}
```

### 🌫️ Fog

| Fog Type | Parameters | Description |
|----------|-----------|-------------|
| `none` | — | No fog |
| `linear` | `fog_near`, `fog_far`, `fog_color` | Linear distance fog |
| `exponential` | `fog_density`, `fog_color` | Exponential density fog |

Fog blends fragment colors toward the fog color based on distance from the camera.

Base schema material keys are supported, plus additional parser/runtime material controls:

| Prop | Type | Description |
|---|---|---|
| `emissive_strength` | `double` | Strength multiplier for emissive output |
| `alpha` | `double` | Explicit alpha fallback when not using `base_color.a` |
| `alpha_cutoff` | `double` | Alpha threshold for cutoff mode |
| `wireframe` | `bool` | Draw in wireframe style |
| `unlit` | `bool` | Skip lighting and render flat/unlit |
| `texture` | `String` | Procedural texture mode: `none`, `checkerboard`, `gradient`, `noise`, `stripes` |
| `texture_color2` | `ColorDef` | Secondary color for procedural texture modes |
| `texture_scale` | `double` | UV texture repetition/scale |

## 🖥️ Rendering Pipeline

### Bevy (Rust/GPU)

1. Scene JSON parsed into Bevy ECS entities
2. GPU-accelerated rendering with PBR materials
3. Real-time shadow mapping
4. Native FFI (Android/iOS/Desktop) or WASM (Web)
5. Frame buffer sent to Flutter via texture

### Dart (Pure-Dart Canvas Renderer)

The software renderer processes each frame:

1. **Scene Update**: Update camera (orbit, follow, animation), evaluate node animations, step particle system, step physics
2. **Vertex Processing**: Transform vertices to world space, compute per-vertex normals
3. **Lighting**: Per-vertex Blinn-Phong with PBR material parameters
4. **Texture Sampling**: Procedural texture evaluation (checkerboard, gradient, noise, stripes)
5. **Projection**: Perspective divide and screen-space mapping
6. **Clipping**: Near-plane polygon clipping (Sutherland-Hodgman)
7. **Culling**: Back-face culling (unless `double_sided`)
8. **Fog**: Distance-based fog blending
9. **Sorting**: Painter's algorithm (back-to-front depth sorting)
10. **Rasterization**: Canvas path drawing with filled polygons

### Math Library

The Dart renderer includes a complete 3D math library:

| Class | Features |
|-------|----------|
| `Vec2` | 2D vectors with dot product, length, operations |
| `Vec3` | 3D vectors with cross product, normalize, lerp, reflect |
| `Vec4` | 4D homogeneous vectors with perspective divide |
| `Quaternion` | Quaternion rotations, slerp, Euler conversion, axis-angle |
| `Mat4` | 4x4 matrices: identity, translate, scale, rotate, perspective, ortho, lookAt |
| `AABB` | Axis-aligned bounding boxes with intersection tests |
| `Ray` | Ray casting with sphere and plane intersection |

---

## 🧩 Widget Integration

### BevyScene / Bevy3D / Scene3D

Renders 3D scenes using Bevy FFI when available, falls back to pure-Dart renderer.

```json
{
  "type": "BevyScene",
  "props": {
    "width": 800,
    "height": 600,
    "fps": 60,
    "interactive": true,
    "fit": "contain",
    "scene": {
      "world": [...]
    }
  }
}
```

### GameScene / Game3D

Always uses the pure-Dart Canvas-based renderer.

```json
{
  "type": "GameScene",
  "props": {
    "fps": 30,
    "interactive": true,
    "autoStart": true,
    "scene": {
      "world": [...]
    }
  }
}
```

### Widget Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `scene` / `sceneJson` | Map / String | null | Scene definition |
| `width` | double | null | Render width |
| `height` | double | null | Render height |
| `fps` | int | 60 | Target frames per second |
| `interactive` | bool | true | Enable touch/pointer input |
| `fit` | String | 'contain' | `fill`, `cover`, `contain`, `fitWidth`, `fitHeight`, `none`, `scaleDown` |
| `autoStart` | bool | true | Auto-start render loop |

---

## 📐 Shared Type Definitions

### TransformDef

Position, rotation, and scale in 3D space.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `position` | Vec3Def? | null | World position (x, y, z) |
| `rotation` | Vec3Def? | null | Euler angles in degrees (x, y, z) |
| `scale` | Vec3Def? | null | Scale multipliers (x, y, z) |

Transform composition order: **Scale → Rotate → Translate (TRS)**.

```json
{
  "position": { "x": 5.0, "y": 2.0, "z": 0.0 },
  "rotation": { "x": 0, "y": 45, "z": 0 },
  "scale": { "x": 2.0, "y": 1.0, "z": 1.5 }
}
```

### Vec3Def

3D vector with x, y, z components (all default to 0.0):

```json
{ "x": 1.0, "y": 2.0, "z": 3.0 }
```

### ColorDef

RGBA color with channels from 0.0 to 1.0:

```json
{ "r": 0.2, "g": 0.6, "b": 1.0, "a": 1.0 }
```

Default: `{ "r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0 }` (white).

    {"type": "group", "id": "checkpoints", "children": [
      {"type": "mesh3d", "id": "cp1", "mesh": {"shape": "Torus", "radius": 4.2, "tube_radius": 0.2}, "transform": {"position": {"x": 90, "y": 10, "z": 40}}, "material": {"base_color": {"r": 0.1, "g": 0.8, "b": 1.0, "a": 1}, "emissive": {"r": 0.05, "g": 0.4, "b": 0.6, "a": 1}}, "animation": {"animation_type": {"type": "Spin", "speed": {"x": 0, "y": 40, "z": 0}}, "duration": 1.0, "looping": true}},
      {"type": "mesh3d", "id": "cp2", "mesh": {"shape": "Torus", "radius": 4.2, "tube_radius": 0.2}, "transform": {"position": {"x": 210, "y": 14, "z": -35}}, "material": {"base_color": {"r": 1.0, "g": 0.75, "b": 0.2, "a": 1}, "emissive": {"r": 0.5, "g": 0.2, "b": 0.0, "a": 1}}}
    ]}
  ]
}
```

## 📦 Complete Examples

### Outdoor Scene

```json
{
  "world": [
    {
      "type": "environment",
      "ambient_color": { "r": 0.3, "g": 0.3, "b": 0.4, "a": 1.0 },
      "ambient_intensity": 0.4,
      "sky_color_top": { "r": 0.1, "g": 0.2, "b": 0.6, "a": 1.0 },
      "sky_color_bottom": { "r": 0.6, "g": 0.7, "b": 0.9, "a": 1.0 },
      "fog_type": "linear",
      "fog_color": { "r": 0.7, "g": 0.7, "b": 0.8, "a": 1.0 },
      "fog_near": 50.0,
      "fog_far": 200.0
    },
    {
      "type": "camera",
      "camera_type": "Perspective",
      "mode": "Orbit",
      "fov": 60,
      "orbit_speed": 0.2,
      "transform": {
        "position": { "x": 0, "y": 8, "z": 15 },
        "rotation": { "x": -25, "y": 0, "z": 0 }
      }
    },
    {
      "type": "light",
      "light_type": "Directional",
      "color": { "r": 1.0, "g": 0.95, "b": 0.8, "a": 1.0 },
      "intensity": 1.5,
      "cast_shadow": true,
      "transform": {
        "rotation": { "x": -50, "y": 30, "z": 0 }
      }
    },
    {
      "type": "light",
      "light_type": "Point",
      "color": { "r": 1.0, "g": 0.6, "b": 0.2, "a": 1.0 },
      "intensity": 500.0,
      "range": 15.0,
      "transform": {
        "position": { "x": -3, "y": 4, "z": 0 }
      }
    },
    {
      "type": "mesh3d",
      "mesh": { "Plane": { "size": 80.0, "subdivisions": 4 } },
      "material": {
        "base_color": { "r": 0.35, "g": 0.55, "b": 0.2, "a": 1.0 },
        "roughness": 0.95,
        "texture_type": "noise",
        "texture_color2": { "r": 0.25, "g": 0.45, "b": 0.15, "a": 1.0 },
        "texture_scale": 5.0
      },
      "transform": {
        "position": { "x": 0, "y": 0, "z": 0 }
      }
    },
    {
      "type": "mesh3d",
      "mesh": "Cube",
      "material": {
        "base_color": { "r": 0.7, "g": 0.7, "b": 0.75, "a": 1.0 },
        "metallic": 0.1,
        "roughness": 0.6
      },
      "transform": {
        "position": { "x": 0, "y": 1, "z": 0 },
        "scale": { "x": 2, "y": 2, "z": 2 }
      }
    },
    {
      "type": "mesh3d",
      "mesh": { "Sphere": { "radius": 1.0, "subdivisions": 24 } },
      "material": {
        "base_color": { "r": 0.9, "g": 0.2, "b": 0.2, "a": 1.0 },
        "metallic": 0.8,
        "roughness": 0.15
      },
      "transform": {
        "position": { "x": 0, "y": 5, "z": 0 }
      },
      "animation": {
        "animation_type": { "type": "Bounce", "height": 2.0 },
        "duration": 2.0,
        "looping": true,
        "easing": "EaseInOut"
      }
    },
    {
      "type": "mesh3d",
      "mesh": { "Torus": { "radius": 3.0, "tube_radius": 0.4 } },
      "material": {
        "base_color": { "r": 1.0, "g": 0.84, "b": 0.0, "a": 1.0 },
        "metallic": 0.9,
        "roughness": 0.1
      },
      "transform": {
        "position": { "x": 0, "y": 3, "z": 0 }
      },
      "animation": {
        "animation_type": { "type": "Rotate", "axis": { "x": 1, "y": 0, "z": 0 }, "degrees": 360 },
        "duration": 6.0,
        "looping": true,
        "easing": "Linear"
      }
    },
    {
      "type": "particles",
      "emitter_shape": "Point",
      "emission_rate": 30.0,
      "lifetime": 3.0,
      "start_color": { "r": 1.0, "g": 0.5, "b": 0.0, "a": 1.0 },
      "end_color": { "r": 1.0, "g": 0.0, "b": 0.0, "a": 0.0 },
      "start_size": 0.15,
      "end_size": 0.02,
      "speed": 4.0,
      "gravity": { "x": 0, "y": -2, "z": 0 },
      "blend_mode": "additive",
      "transform": { "position": { "x": 5, "y": 0, "z": -3 } }
    }
  ]
}
```

### Product Showcase (Orbiting Camera)

```json
{
  "world": [
    {
      "type": "environment",
      "ambient_color": { "r": 0.9, "g": 0.9, "b": 1.0, "a": 1.0 },
      "ambient_intensity": 0.6
    },
    {
      "type": "camera",
      "camera_type": "Perspective",
      "mode": "Orbit",
      "fov": 45,
      "orbit_speed": 0.15,
      "transform": {
        "position": { "x": 0, "y": 3, "z": 6 }
      }
    },
    {
      "type": "light",
      "light_type": "Directional",
      "color": { "r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0 },
      "intensity": 2.0,
      "transform": { "rotation": { "x": -40, "y": 45, "z": 0 } }
    },
    {
      "type": "mesh3d",
      "mesh": { "Sphere": { "radius": 1.5, "subdivisions": 32 } },
      "material": {
        "base_color": { "r": 0.95, "g": 0.95, "b": 0.97, "a": 1.0 },
        "metallic": 1.0,
        "roughness": 0.05,
        "texture_type": "checkerboard",
        "texture_color2": { "r": 0.85, "g": 0.85, "b": 0.87, "a": 1.0 },
        "texture_scale": 8.0
      },
      "transform": { "position": { "x": 0, "y": 1.5, "z": 0 } },
      "animation": {
        "animation_type": { "type": "Rotate", "axis": { "x": 0, "y": 1, "z": 0 }, "degrees": 360 },
        "duration": 10.0,
        "looping": true,
        "easing": "Linear"
      }
    },
    {
      "type": "mesh3d",
      "mesh": { "Plane": { "size": 10.0 } },
      "material": {
        "base_color": { "r": 0.2, "g": 0.2, "b": 0.22, "a": 1.0 },
        "metallic": 0.3,
        "roughness": 0.8
      },
      "transform": { "position": { "x": 0, "y": 0, "z": 0 } }
    }
  ]
}
```

### Example G: Action boss arena (projectiles, hazards, debris physics)

## 📊 Element Summary Table

| Element | Type Tag | Rendering |
|---------|----------|-----------|
| Mesh | `mesh3d` | 12 primitive generators + PBR material |
| Light | `light` | Directional, Point, Spot, Area |
| Camera | `camera` | Perspective/Orthographic with 5 modes |
| Particles | `particles` | 5 emitter shapes, color/size interpolation |
| Environment | `environment` | Ambient, sky gradient, fog |
| Group | `group` | Hierarchical transform container |
| Text3D | `text3d` | 3D text rendering |

### Feature Comparison

| Feature | Bevy (Rust/GPU) | Dart (Canvas) |
|---------|----------------|---------------|
| Mesh primitives | All 12 | All 12 |
| PBR materials | Full GPU PBR | Blinn-Phong approximation |
| Procedural textures | — | 4 types (checkerboard, gradient, noise, stripes) |
| Lighting | All types + shadows | All types, no shadows |
| Camera modes | All 5 | All 5 |
| Animations | All 10 types | All 10 types |
| Particles | Full GPU | Software particles |
| Physics | — | Basic rigid bodies |
| Fog | Full | Linear + exponential |
| GLTF loading | Full | Simplified (nodes + materials) |
| Performance | GPU-accelerated | Software rasterization |
