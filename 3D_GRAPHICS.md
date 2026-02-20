# Elpian 3D Graphics Reference (Complete Schema + Examples)

This file is a full 3D DSL reference with:

- full prop schema for each 3D world element,
- shared type schemas (`mesh`, `material`, `transform`, `animation`, `physics`, vectors/colors),
- per-element practical examples,
- feature-rich real-world scene examples at the end.

> Scene contract:

```json
{
  "ui": [],
  "world": []
}
```

`world` is a list of 3D nodes.

---

## 1) 3D world elements (full props schema)

## `mesh3d`

Renderable geometry node. Can include children for hierarchical transforms.

| Prop | Type | Required | Default | Description |
|---|---|---|---|---|
| `type` | `"mesh3d"` | Yes | - | Node tag. |
| `id` | `String?` | No | `null` | Optional id for selection/debugging. |
| `mesh` | `MeshType` | Yes | - | Primitive or file mesh. |
| `material` | `MaterialDef` | No | `{}` | Surface/PBR settings. |
| `transform` | `TransformDef` | No | `{}` | Position/rotation/scale. |
| `animation` | `AnimationDef?` or list (parser path) | No | `null` | Runtime animation. |
| `children` | `List<Node>` | No | `[]` | Child nodes inheriting parent transform. |

Example:

```json
{
  "type": "mesh3d",
  "id": "hero",
  "mesh": {"shape": "File", "path": "models/robot.gltf"},
  "material": {
    "base_color": {"r": 0.95, "g": 0.95, "b": 1.0, "a": 1.0},
    "metallic": 0.6,
    "roughness": 0.25
  },
  "transform": {
    "position": {"x": 0, "y": 0.8, "z": 0},
    "rotation": {"x": 0, "y": 180, "z": 0},
    "scale": {"x": 1, "y": 1, "z": 1}
  },
  "animation": {
    "animation_type": {"type": "Rotate", "axis": {"x": 0, "y": 1, "z": 0}, "degrees": 360},
    "duration": 8.0,
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

Example:

```json
{
  "type": "light",
  "id": "sun",
  "light_type": "Directional",
  "color": {"r": 1.0, "g": 0.97, "b": 0.92, "a": 1.0},
  "intensity": 1.2,
  "transform": {
    "rotation": {"x": -40, "y": 25, "z": 0}
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

Example:

```json
{
  "type": "camera",
  "camera_type": "Perspective",
  "transform": {
    "position": {"x": 0, "y": 6, "z": 14},
    "rotation": {"x": -18, "y": 0, "z": 0}
  },
  "fov": 60,
  "near": 0.1,
  "far": 1500
}
```

---

## `particles`

Particle emitter node.

| Prop | Type | Required | Default | Description |
|---|---|---|---|---|
| `type` | `"particles"` | Yes | - | Node tag. |
| `id` | `String?` | No | `null` | Optional id. |
| `transform` | `TransformDef` | No | `{}` | Emitter transform. |
| `emission_rate` | `f32` | No | `10.0` | Particles per second. |
| `lifetime` | `f32` | No | `1.0` | Particle lifetime. |
| `color` | `ColorDef` | No | white | Particle color. |
| `size` | `f32` | No | `0.1` | Particle size scalar. |
| `velocity` | `Vec3Def` | No | `{x:0,y:0,z:0}` | Initial velocity. |
| `gravity` | `Vec3Def` | No | `{x:0,y:-9.8,z:0}` | Gravity acceleration. |
| `emitter` | parser-specific object | No | parser default | Optional advanced emitter config in parser path. |

Example:

```json
{
  "type": "particles",
  "id": "smoke",
  "transform": {"position": {"x": 2, "y": 0.2, "z": -1}},
  "emission_rate": 35,
  "lifetime": 2.4,
  "size": 0.16,
  "color": {"r": 0.8, "g": 0.82, "b": 0.86, "a": 0.9},
  "velocity": {"x": 0.0, "y": 1.7, "z": 0.1},
  "gravity": {"x": 0.0, "y": -0.5, "z": 0.0}
}
```

---

## `environment`

Global environment settings.

| Prop | Type | Required | Default | Description |
|---|---|---|---|---|
| `type` | `"environment"` | Yes | - | Node tag. |
| `id` | `String?` | No | `null` | Optional id. |
| `ambient_light` | `ColorDef?` | No | runtime default | Ambient color. |
| `ambient_intensity` | `f32` | No | `0.8` (schema) / parser default varies | Ambient strength. |
| `fog_enabled` | `bool` | No | `false` | Enable fog. |
| `fog_color` | `ColorDef?` | No | runtime default | Fog color. |
| `fog_distance` | `f32` | No | `100.0` | Fog far distance / fog end. |
| `fog_type` | parser enum | No | `none` | Parser path fog model (`none`, `linear`, `exponential`). |
| `fog_near` | `f32?` parser | No | parser default | Fog start distance. |
| `fog_density` | `f32?` parser | No | parser default | Exponential fog density. |
| `gravity` | `Vec3Def?` parser | No | parser default | Global gravity vector. |
| `sky_color_top` | `Vec3Def?/ColorDef?` parser | No | parser default | Sky gradient top. |
| `sky_color_bottom` | `Vec3Def?/ColorDef?` parser | No | parser default | Sky gradient bottom. |

Example:

```json
{
  "type": "environment",
  "ambient_light": {"r": 0.42, "g": 0.44, "b": 0.5, "a": 1.0},
  "ambient_intensity": 0.28,
  "fog_enabled": true,
  "fog_color": {"r": 0.74, "g": 0.78, "b": 0.86, "a": 1.0},
  "fog_distance": 180,
  "fog_type": "linear",
  "fog_near": 25,
  "fog_density": 0.015
}
```

---

## `group`

Grouping node for transform hierarchy.

| Prop | Type | Required | Default | Description |
|---|---|---|---|---|
| `type` | `"group"` | Yes | - | Node tag. |
| `id` | `String?` | No | `null` | Optional id. |
| `transform` | `TransformDef` | No | `{}` | Parent transform. |
| `children` | `List<Node>` | No | `[]` | Child world nodes. |

Example:

```json
{
  "type": "group",
  "id": "windmill",
  "transform": {"position": {"x": 0, "y": 0, "z": 0}},
  "children": [
    {"type": "mesh3d", "id": "tower", "mesh": {"shape": "Cylinder", "radius": 0.6, "height": 6}},
    {"type": "mesh3d", "id": "blades", "mesh": "Cube", "transform": {"position": {"x": 0, "y": 3, "z": 0}}, "animation": {"animation_type": {"type": "Rotate", "axis": {"x": 0, "y": 0, "z": 1}, "degrees": 360}, "duration": 2.2, "looping": true}}
  ]
}
```

---

## `terrain` (schema path)

Height-based terrain mesh.

| Prop | Type | Required | Default | Description |
|---|---|---|---|---|
| `type` | `"terrain"` | Yes | - | Node tag. |
| `id` | `String?` | No | `null` | Optional id. |
| `size` | `f32` | No | `100.0` | Terrain width/length. |
| `height` | `f32` | No | `0.0` | Height amplitude. |
| `subdivisions` | `u32` | No | `0` | Resolution. |
| `heightmap` | `String?` | No | `null` | Heightmap texture path. |
| `material` | `MaterialDef` | No | `{}` | Terrain material. |
| `transform` | `TransformDef` | No | `{}` | Placement transform. |
| `physics` | `PhysicsDef?` (portable extension) | No | `null` | Optional collision/physics. |

Example:

```json
{
  "type": "terrain",
  "id": "island",
  "size": 240,
  "height": 38,
  "subdivisions": 128,
  "heightmap": "textures/island_height.png",
  "material": {
    "base_color_texture": "textures/terrain_albedo.png",
    "normal_map_texture": "textures/terrain_normal.png",
    "roughness": 0.9
  }
}
```

---

## `skybox` (schema path)

Background/cubemap sky.

| Prop | Type | Required | Default | Description |
|---|---|---|---|---|
| `type` | `"skybox"` | Yes | - | Node tag. |
| `id` | `String?` | No | `null` | Optional id. |
| `texture_path` | `String?` | No | `null` | Cubemap/sky texture. |
| `color` | `ColorDef?` | No | `null` | Color fallback/tint. |
| `rotation` | `Vec3Def?` | No | `null` | Sky rotation in degrees. |
| `brightness` | `f32` | No | `1.0` | Intensity multiplier. |

Example:

```json
{
  "type": "skybox",
  "texture_path": "textures/sunset_sky.hdr",
  "rotation": {"x": 0, "y": 35, "z": 0},
  "brightness": 1.15
}
```

---

## `water` (schema path)

Water plane with wave controls.

| Prop | Type | Required | Default | Description |
|---|---|---|---|---|
| `type` | `"water"` | Yes | - | Node tag. |
| `id` | `String?` | No | `null` | Optional id. |
| `size` | `Vec3Def` | No | `{0,0,0}` | Plane dimensions. |
| `transform` | `TransformDef` | No | `{}` | Placement transform. |
| `wave_amplitude` | `f32` | No | `0.5` | Wave height. |
| `wave_frequency` | `f32` | No | `1.0` | Wave speed/frequency. |
| `water_color` | `ColorDef?` | No | renderer default | Water tint. |
| `transparency` | `f32` | No | `0.7` | Alpha/transparency. |

Example:

```json
{
  "type": "water",
  "id": "lake",
  "size": {"x": 180, "y": 0, "z": 120},
  "transform": {"position": {"x": 0, "y": -2, "z": 0}},
  "wave_amplitude": 0.22,
  "wave_frequency": 1.8,
  "water_color": {"r": 0.1, "g": 0.42, "b": 0.72, "a": 1.0},
  "transparency": 0.58
}
```

---

## `rigidbody` (schema path)

Physics-enabled body with mesh.

| Prop | Type | Required | Default | Description |
|---|---|---|---|---|
| `type` | `"rigidbody"` | Yes | - | Node tag. |
| `id` | `String?` | No | `null` | Optional id. |
| `mesh` | `MeshType` | Yes | - | Collision/render mesh source. |
| `material` | `MaterialDef` | No | `{}` | Surface material. |
| `transform` | `TransformDef` | No | `{}` | Initial transform. |
| `physics` | `PhysicsDef` | No | defaults | Physics parameters. |

Example:

```json
{
  "type": "rigidbody",
  "id": "crate-01",
  "mesh": {"shape": "Cube"},
  "material": {
    "base_color_texture": "textures/metal_crate_albedo.png",
    "normal_map_texture": "textures/metal_crate_normal.png",
    "roughness": 0.65
  },
  "transform": {"position": {"x": 0, "y": 8, "z": -2}},
  "physics": {
    "mass": 4.0,
    "friction": 0.45,
    "restitution": 0.15,
    "gravity_scale": 1.0,
    "use_gravity": true,
    "collider_type": "Box"
  }
}
```

---

## `text3d` (parser path)

Text node type accepted by pure-Dart scene parser.

| Prop | Type | Required | Default | Description |
|---|---|---|---|---|
| `type` | `"text3d"` | Yes | - | Node tag. |
| `id` | `String?` | No | `null` | Optional id. |
| `name` | `String?` | No | `null` | Text content/name depending renderer usage. |
| `transform` | `TransformDef` | No | `{}` | Position/rotation/scale. |
| `material` | `MaterialDef?` | No | `null` | Optional color/material styling. |
| `animation` | `AnimationDef?` | No | `null` | Optional animation. |

Example:

```json
{
  "type": "text3d",
  "id": "welcome-sign",
  "name": "Welcome to Elpian World",
  "transform": {
    "position": {"x": 0, "y": 3.5, "z": -8},
    "rotation": {"x": 0, "y": 0, "z": 0},
    "scale": {"x": 1.4, "y": 1.4, "z": 1.4}
  }
}
```

---

## 2) Shared type schemas

## `Vec3Def`

| Prop | Type | Required | Default | Description |
|---|---|---|---|---|
| `x` | `f32` | No | `0.0` | X component |
| `y` | `f32` | No | `0.0` | Y component |
| `z` | `f32` | No | `0.0` | Z component |

Example: `{"x": 1.0, "y": 2.0, "z": 3.0}`

## `ColorDef`

| Prop | Type | Required | Default | Description |
|---|---|---|---|---|
| `r` | `f32` | No | `1.0` | Red channel (0..1) |
| `g` | `f32` | No | `1.0` | Green channel (0..1) |
| `b` | `f32` | No | `1.0` | Blue channel (0..1) |
| `a` | `f32` | No | `1.0` | Alpha channel (0..1) |

Example: `{"r": 0.2, "g": 0.6, "b": 1.0, "a": 1.0}`

## `TransformDef`

| Prop | Type | Required | Default | Description |
|---|---|---|---|---|
| `position` | `Vec3Def?` | No | `null` | World position |
| `rotation` | `Vec3Def?` | No | `null` | Euler degrees |
| `scale` | `Vec3Def?` | No | `null` | Non-uniform scale |

Example:

```json
{
  "position": {"x": 3, "y": 2, "z": -7},
  "rotation": {"x": 0, "y": 35, "z": 0},
  "scale": {"x": 1, "y": 1, "z": 1}
}
```

## `MeshType`

Supported forms:

- named: `"Cube"`
- parameterized object with `shape`:
  - `Sphere`: `radius`, `subdivisions`
  - `Plane`: `size`
  - `Capsule`: `radius`, `depth`
  - `Cylinder`: `radius`, `height`
  - `Cone`: `radius`, `height`
  - `Torus`: `radius`, `tube_radius`
  - `Icosphere`: `radius`, `subdivisions` (parser/runtime depending)
  - `UvSphere`: `radius`, `sectors`, `stacks` (parser/runtime depending)
  - `Grid`: `width`, `height`, `spacing` (parser/runtime depending)
  - `File`: `path`

Examples:

```json
"Cube"
```

```json
{"shape": "Sphere", "radius": 1.4, "subdivisions": 24}
```

```json
{"shape": "File", "path": "models/ship.gltf"}
```

## `MaterialDef`

| Prop | Type | Required | Default | Description |
|---|---|---|---|---|
| `base_color` | `ColorDef?` | No | `null` | Albedo/tint color |
| `base_color_texture` | `String?` | No | `null` | Base color texture path |
| `emissive` | `ColorDef?` | No | `null` | Emissive color |
| `emissive_texture` | `String?` | No | `null` | Emissive map path |
| `metallic` | `f32?` | No | `null` | Metallic value |
| `roughness` | `f32?` | No | `null` | Roughness value |
| `metallic_roughness_texture` | `String?` | No | `null` | MR texture |
| `normal_map_texture` | `String?` | No | `null` | Normal map path |
| `ambient_occlusion_texture` | `String?` | No | `null` | AO texture |
| `height_map_texture` | `String?` | No | `null` | Height/parallax map |
| `parallax_depth` | `f32?` | No | `null` | Parallax depth |
| `alpha_mode` | `AlphaMode?` | No | `null` | `Opaque` / `Mask` / `Blend` |
| `double_sided` | `bool` | No | `false` | Render both faces |
| `ior` | `f32?` | No | `null` | Index of refraction |

Example:

```json
{
  "base_color": {"r": 0.9, "g": 0.92, "b": 1.0, "a": 1.0},
  "base_color_texture": "textures/panel_albedo.png",
  "normal_map_texture": "textures/panel_normal.png",
  "metallic": 0.75,
  "roughness": 0.22,
  "alpha_mode": "Opaque",
  "double_sided": false
}
```

## `AnimationDef`

| Prop | Type | Required | Default | Description |
|---|---|---|---|---|
| `animation_type` | `AnimationType` | Yes | - | Animation mode |
| `duration` | `f32` | No | `1.0` | Seconds |
| `looping` | `bool` | No | `false` | Loop toggle |
| `easing` | `EasingType` | No | `Linear` | Timing curve |

`AnimationType` schemas:

- `Rotate`: `{ "type": "Rotate", "axis": Vec3Def, "degrees": f32 }`
- `Translate`: `{ "type": "Translate", "from": Vec3Def, "to": Vec3Def }`
- `Scale`: `{ "type": "Scale", "from": Vec3Def, "to": Vec3Def }`
- `Bounce`: `{ "type": "Bounce", "height": f32 }`
- `Pulse`: `{ "type": "Pulse", "min_scale": f32, "max_scale": f32 }`

Examples:

```json
{"animation_type": {"type": "Rotate", "axis": {"x": 0, "y": 1, "z": 0}, "degrees": 360}, "duration": 5.0, "looping": true, "easing": "Linear"}
```

```json
{"animation_type": {"type": "Translate", "from": {"x": -4, "y": 0, "z": 0}, "to": {"x": 4, "y": 0, "z": 0}}, "duration": 2.2, "looping": true, "easing": "EaseInOut"}
```

## `PhysicsDef`

| Prop | Type | Required | Default | Description |
|---|---|---|---|---|
| `mass` | `f32` | No | `1.0` | Body mass |
| `friction` | `f32` | No | `0.3` | Contact friction |
| `restitution` | `f32` | No | `0.0` | Bounciness |
| `gravity_scale` | `f32` | No | `1.0` | Gravity multiplier |
| `use_gravity` | `bool` | No | `true` | Enable gravity |
| `collider_type` | `ColliderType` | No | `Box` | `Box`, `Sphere`, `Capsule`, `Mesh` |

Example:

```json
{
  "mass": 2.5,
  "friction": 0.42,
  "restitution": 0.2,
  "gravity_scale": 1.0,
  "use_gravity": true,
  "collider_type": "Box"
}
```

---

## 3) Feature-rich real-world 3D DSL examples

These are large, practical scene snippets you can directly adapt.

### Example A: Sci-fi hangar with dynamic lights, particles, and rotating ship

```json
{
  "world": [
    {"type": "environment", "ambient_intensity": 0.2, "fog_enabled": true, "fog_color": {"r": 0.06, "g": 0.08, "b": 0.12, "a": 1}, "fog_distance": 180},
    {"type": "camera", "camera_type": "Perspective", "transform": {"position": {"x": 0, "y": 8, "z": 24}, "rotation": {"x": -10, "y": 0, "z": 0}}},
    {"type": "light", "id": "key-light", "light_type": "Directional", "intensity": 1.4, "transform": {"rotation": {"x": -38, "y": 22, "z": 0}}},
    {"type": "light", "id": "rim-light", "light_type": "Point", "color": {"r": 0.3, "g": 0.6, "b": 1.0, "a": 1}, "intensity": 0.8, "transform": {"position": {"x": -8, "y": 6, "z": -3}}},

    {"type": "mesh3d", "id": "hangar-floor", "mesh": {"shape": "Plane", "size": 120}, "material": {"base_color": {"r": 0.1, "g": 0.11, "b": 0.14, "a": 1}, "roughness": 0.9}},

    {"type": "group", "id": "ship-rig", "transform": {"position": {"x": 0, "y": 3, "z": 0}}, "children": [
      {"type": "mesh3d", "id": "ship-body", "mesh": {"shape": "File", "path": "models/starfighter.gltf"}, "material": {"metallic": 0.85, "roughness": 0.25}, "animation": {"animation_type": {"type": "Rotate", "axis": {"x": 0, "y": 1, "z": 0}, "degrees": 360}, "duration": 18, "looping": true}},
      {"type": "particles", "id": "engine-smoke", "transform": {"position": {"x": 0, "y": -1, "z": -4}}, "emission_rate": 45, "lifetime": 1.8, "size": 0.12, "color": {"r": 0.85, "g": 0.9, "b": 1.0, "a": 0.8}, "velocity": {"x": 0, "y": 0.5, "z": -1.8}, "gravity": {"x": 0, "y": -0.15, "z": 0}}
    ]}
  ]
}
```

### Example B: Outdoor world (terrain + water + skybox + foliage-like instancing pattern)

```json
{
  "world": [
    {"type": "environment", "ambient_light": {"r": 0.55, "g": 0.58, "b": 0.62, "a": 1}, "ambient_intensity": 0.35, "fog_enabled": true, "fog_color": {"r": 0.78, "g": 0.82, "b": 0.9, "a": 1}, "fog_distance": 320},
    {"type": "skybox", "texture_path": "textures/sky_morning.hdr", "brightness": 1.05},
    {"type": "camera", "camera_type": "Perspective", "transform": {"position": {"x": 0, "y": 22, "z": 38}, "rotation": {"x": -22, "y": 0, "z": 0}}},
    {"type": "light", "light_type": "Directional", "intensity": 1.3, "transform": {"rotation": {"x": -45, "y": 30, "z": 0}}},

    {"type": "terrain", "id": "main-terrain", "size": 600, "height": 80, "subdivisions": 256, "heightmap": "textures/mountain_height.png", "material": {"base_color_texture": "textures/grass_rock_albedo.png", "normal_map_texture": "textures/grass_rock_normal.png", "roughness": 0.95}},
    {"type": "water", "id": "river", "size": {"x": 500, "y": 0, "z": 60}, "transform": {"position": {"x": 0, "y": 3, "z": 40}}, "wave_amplitude": 0.18, "wave_frequency": 1.3, "water_color": {"r": 0.12, "g": 0.45, "b": 0.7, "a": 1}, "transparency": 0.62},

    {"type": "group", "id": "rocks", "children": [
      {"type": "mesh3d", "mesh": {"shape": "File", "path": "models/rock_01.gltf"}, "transform": {"position": {"x": -24, "y": 9, "z": 12}, "scale": {"x": 2.2, "y": 2.2, "z": 2.2}}},
      {"type": "mesh3d", "mesh": {"shape": "File", "path": "models/rock_02.gltf"}, "transform": {"position": {"x": -16, "y": 7, "z": 6}, "scale": {"x": 1.8, "y": 1.8, "z": 1.8}}},
      {"type": "mesh3d", "mesh": {"shape": "File", "path": "models/rock_03.gltf"}, "transform": {"position": {"x": -8, "y": 6, "z": 1}, "scale": {"x": 1.6, "y": 1.6, "z": 1.6}}}
    ]}
  ]
}
```

### Example C: Physics puzzle arena (rigid bodies + static geometry)

```json
{
  "world": [
    {"type": "environment", "ambient_intensity": 0.24},
    {"type": "camera", "camera_type": "Perspective", "transform": {"position": {"x": 0, "y": 14, "z": 28}, "rotation": {"x": -18, "y": 0, "z": 0}}},
    {"type": "light", "light_type": "Directional", "intensity": 1.1, "transform": {"rotation": {"x": -42, "y": -15, "z": 0}}},

    {"type": "mesh3d", "id": "ground", "mesh": {"shape": "Plane", "size": 80}, "material": {"base_color": {"r": 0.2, "g": 0.2, "b": 0.22, "a": 1}, "roughness": 0.95}},

    {"type": "rigidbody", "id": "ball", "mesh": {"shape": "Sphere", "radius": 1.0, "subdivisions": 24}, "transform": {"position": {"x": -4, "y": 12, "z": 0}}, "physics": {"mass": 1.0, "friction": 0.3, "restitution": 0.75, "use_gravity": true, "collider_type": "Sphere"}},
    {"type": "rigidbody", "id": "crate-a", "mesh": "Cube", "transform": {"position": {"x": 0, "y": 16, "z": 0}}, "physics": {"mass": 3.0, "friction": 0.5, "restitution": 0.1, "use_gravity": true, "collider_type": "Box"}},
    {"type": "rigidbody", "id": "crate-b", "mesh": "Cube", "transform": {"position": {"x": 3, "y": 19, "z": 0}}, "physics": {"mass": 3.0, "friction": 0.5, "restitution": 0.1, "use_gravity": true, "collider_type": "Box"}},

    {"type": "mesh3d", "id": "goal-ring", "mesh": {"shape": "Torus", "radius": 2.2, "tube_radius": 0.2}, "transform": {"position": {"x": 14, "y": 3, "z": 0}}, "material": {"base_color": {"r": 1, "g": 0.8, "b": 0.1, "a": 1}, "emissive": {"r": 0.3, "g": 0.2, "b": 0.0, "a": 1}}}
  ]
}
```

### Example D: Data-center digital twin (grouped machines + alarms + text3d labels)

```json
{
  "world": [
    {"type": "environment", "ambient_intensity": 0.22, "fog_enabled": true, "fog_color": {"r": 0.2, "g": 0.24, "b": 0.3, "a": 1}, "fog_distance": 220},
    {"type": "camera", "camera_type": "Perspective", "mode": "orbit", "orbit_radius": 36, "orbit_speed": 8, "transform": {"position": {"x": 0, "y": 16, "z": 36}}},
    {"type": "light", "light_type": "Directional", "intensity": 1.0, "transform": {"rotation": {"x": -50, "y": 20, "z": 0}}},

    {"type": "mesh3d", "id": "floor", "mesh": {"shape": "Plane", "size": 140}, "material": {"base_color": {"r": 0.08, "g": 0.09, "b": 0.11, "a": 1}, "roughness": 0.98}},

    {"type": "group", "id": "rack-row-a", "children": [
      {"type": "mesh3d", "id": "rack-a1", "mesh": {"shape": "File", "path": "models/server_rack.gltf"}, "transform": {"position": {"x": -16, "y": 0, "z": -8}}},
      {"type": "mesh3d", "id": "rack-a2", "mesh": {"shape": "File", "path": "models/server_rack.gltf"}, "transform": {"position": {"x": -8, "y": 0, "z": -8}}},
      {"type": "mesh3d", "id": "rack-a3", "mesh": {"shape": "File", "path": "models/server_rack.gltf"}, "transform": {"position": {"x": 0, "y": 0, "z": -8}}}
    ]},

    {"type": "mesh3d", "id": "alarm-beacon", "mesh": {"shape": "Sphere", "radius": 0.4, "subdivisions": 20}, "transform": {"position": {"x": -8, "y": 4.5, "z": -8}}, "material": {"base_color": {"r": 1, "g": 0.15, "b": 0.15, "a": 1}, "emissive": {"r": 1, "g": 0.1, "b": 0.1, "a": 1}}, "animation": {"animation_type": {"type": "Pulse", "min_scale": 0.8, "max_scale": 1.3}, "duration": 0.9, "looping": true, "easing": "EaseInOut"}},

    {"type": "text3d", "id": "label-a", "name": "Rack A2 · Overheat", "transform": {"position": {"x": -8, "y": 6.2, "z": -8}}},

    {"type": "particles", "id": "heat-smoke", "transform": {"position": {"x": -8, "y": 4.8, "z": -8}}, "emission_rate": 22, "lifetime": 1.6, "size": 0.1, "color": {"r": 1, "g": 0.7, "b": 0.5, "a": 0.7}, "velocity": {"x": 0, "y": 1.1, "z": 0}, "gravity": {"x": 0, "y": -0.1, "z": 0}}
  ]
}
```

---

## 4) Portability and authoring notes

1. For best cross-renderer compatibility, start with `environment`, `camera`, `light`, `mesh3d`, `group`, and `particles`.
2. Add `terrain`, `skybox`, `water`, `rigidbody`, and `text3d` when your target runtime path supports them.
3. Keep asset paths relative and consistent (`models/...`, `textures/...`).
4. For large scenes, split authoring logically into reusable groups (`group` nodes for props/sets/rigs).
5. Keep simulation tuning data (physics, animation durations, fog, lighting) in JSON so VM logic can swap presets at runtime.

---

## 5) Extended coverage for engine-specific 3D features (beyond base schema)

This section documents additional runtime features exposed by the pure-Dart `scene3d` core/parser and by software renderer mesh generation paths. Use these when your target runtime supports them.

### 5.1 Parser-level `SceneNode` extended fields

In parser/runtime, each node can additionally carry:

| Prop | Type | Description |
|---|---|---|
| `name` | `String?` | Optional display/debug name |
| `visible` | `bool` | Node visibility toggle |
| `text` | `String?` | Text payload (not only `text3d`) |
| `text_size` | `double?` | Text size hint |
| `extra` | `Map<String,dynamic>?` | Arbitrary metadata/extensions |

Example:

```json
{
  "type": "mesh3d",
  "id": "crate-42",
  "name": "Objective Crate",
  "visible": true,
  "text": "Loot",
  "text_size": 14,
  "extra": {
    "team": "blue",
    "interactable": true,
    "questId": "Q-17"
  },
  "mesh": "Cube"
}
```

### 5.2 Extended `Material3D` (parser/runtime)

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

Example:

```json
{
  "material": {
    "base_color": {"r": 0.16, "g": 0.76, "b": 0.91, "a": 1.0},
    "emissive": {"r": 0.10, "g": 0.45, "b": 0.60, "a": 1.0},
    "emissive_strength": 2.2,
    "alpha_mode": "blend",
    "alpha": 0.85,
    "alpha_cutoff": 0.5,
    "wireframe": false,
    "unlit": false,
    "texture": "stripes",
    "texture_color2": {"r": 0.03, "g": 0.05, "b": 0.08, "a": 1.0},
    "texture_scale": 4.0,
    "metallic": 0.4,
    "roughness": 0.25
  }
}
```

### 5.3 Extended animation capabilities (parser/runtime)

Besides shared animation modes (`Rotate`, `Translate`, `Scale`, `Bounce`, `Pulse`), runtime supports additional modes:

- `Orbit` (radius/height circular motion)
- `Swing` (oscillating axis rotation)
- `Shake` (randomized jitter)
- `Float` (sinusoidal Y translation)
- `Spin` (continuous XYZ angular speed)

Extended easing values also include: `Elastic`, `Back`, `Sine`.

Examples:

```json
{
  "animation": {
    "animation_type": {
      "type": "Orbit",
      "radius": 5.0,
      "height": 2.0
    },
    "duration": 6.0,
    "looping": true,
    "easing": "Sine",
    "delay": 0.2
  }
}
```

```json
{
  "animation": [
    {
      "animation_type": {"type": "Float", "amplitude": 0.35},
      "duration": 2.4,
      "looping": true,
      "easing": "EaseInOut"
    },
    {
      "animation_type": {
        "type": "Spin",
        "speed": {"x": 0.0, "y": 65.0, "z": 0.0}
      },
      "duration": 1.0,
      "looping": true,
      "easing": "Linear"
    }
  ]
}
```

### 5.4 Advanced particle emitter object (parser/runtime)

When using `type: "particles"`, parser/runtime can consume an advanced `emitter` object:

| Prop | Type | Description |
|---|---|---|
| `shape` | `point|sphere|cone|box|ring` | Spawn shape |
| `emit_rate` | `double` | Per-second emission |
| `lifetime` | `double` | Particle life |
| `start_color` / `end_color` | `ColorDef` | Lifetime color interpolation |
| `start_size` / `end_size` | `double` | Lifetime size interpolation |
| `start_alpha` / `end_alpha` | `double` | Lifetime alpha interpolation |
| `gravity` | `Vec3Def` | Particle gravity |
| `wind` | `Vec3Def` | Constant wind force |
| `spread` | `double` | Emission cone spread degrees |
| `speed` | `double` | Base initial speed |
| `speed_variance` | `double` | Randomized speed variation |
| `max_particles` | `int` | Upper particle pool cap |
| `world_space` | `bool` | Simulate in world vs local space |
| `blend_mode` | `String` | Blend model hint |
| `burst_count` | `double` | Burst particles |
| `prewarm` | `bool` | Pre-spawn on start |

Example:

```json
{
  "type": "particles",
  "id": "fireworks",
  "transform": {"position": {"x": 0, "y": 8, "z": 0}},
  "emitter": {
    "shape": "sphere",
    "emit_rate": 120,
    "lifetime": 2.0,
    "start_color": {"r": 1.0, "g": 0.45, "b": 0.12, "a": 1.0},
    "end_color": {"r": 0.15, "g": 0.1, "b": 0.3, "a": 0.0},
    "start_size": 0.12,
    "end_size": 0.0,
    "start_alpha": 1.0,
    "end_alpha": 0.0,
    "gravity": {"x": 0, "y": -2.0, "z": 0},
    "wind": {"x": 0.8, "y": 0, "z": 0.2},
    "spread": 170,
    "speed": 4.5,
    "speed_variance": 1.6,
    "max_particles": 900,
    "world_space": true,
    "blend_mode": "additive",
    "burst_count": 30,
    "prewarm": true
  }
}
```

### 5.5 Extended rigidbody/physics fields (parser/runtime)

Parser/runtime rigidbody parser accepts additional keys beyond base schema:

| Prop | Type | Description |
|---|---|---|
| `velocity` | `Vec3Def` | Initial linear velocity |
| `is_static` | `bool` | Static body toggle |
| `collider` | `sphere|box|plane` | Collider family |
| `collider_radius` | `double` | Sphere radius |
| `collider_size` | `Vec3Def` | Box collider size |

Example:

```json
{
  "physics": {
    "velocity": {"x": 1.5, "y": 0.0, "z": 0.0},
    "mass": 10.0,
    "restitution": 0.05,
    "friction": 0.8,
    "is_static": false,
    "use_gravity": true,
    "collider": "box",
    "collider_size": {"x": 1.2, "y": 0.8, "z": 1.2}
  }
}
```

### 5.6 Mesh support notes by runtime path

Portable/shared documented meshes remain preferred (`Cube`, `Sphere`, `Plane`, `Capsule`, `Cylinder`, `Cone`, `Torus`, `File`).

Additional software-renderer/runtime mesh generators may include shapes such as:

- `Pyramid`
- `Wedge`
- `IcoSphere`
- `Billboard`

Use these selectively and feature-detect if you need strict cross-runtime parity.

---

## 6) More feature-rich real-world game scene examples

### Example E: Open-world driving checkpoint race

```json
{
  "world": [
    {"type": "environment", "ambient_intensity": 0.34, "fog_enabled": true, "fog_color": {"r": 0.76, "g": 0.8, "b": 0.86, "a": 1}, "fog_distance": 420},
    {"type": "skybox", "texture_path": "textures/cloudy_day.hdr", "brightness": 1.0},
    {"type": "camera", "camera_type": "Perspective", "mode": "follow", "transform": {"position": {"x": 0, "y": 10, "z": 18}}, "near": 0.1, "far": 3000},
    {"type": "light", "light_type": "Directional", "intensity": 1.25, "transform": {"rotation": {"x": -44, "y": 28, "z": 0}}},

    {"type": "terrain", "size": 1500, "height": 110, "subdivisions": 320, "heightmap": "textures/race_height.png", "material": {"base_color_texture": "textures/race_ground_albedo.png", "normal_map_texture": "textures/race_ground_normal.png", "roughness": 0.9}},

    {"type": "mesh3d", "id": "player-car", "mesh": {"shape": "File", "path": "models/sports_car.gltf"}, "transform": {"position": {"x": 0, "y": 5, "z": 0}, "scale": {"x": 1, "y": 1, "z": 1}}, "animation": [{"animation_type": {"type": "Float", "amplitude": 0.06}, "duration": 1.8, "looping": true, "easing": "Sine"}]},

    {"type": "group", "id": "checkpoints", "children": [
      {"type": "mesh3d", "id": "cp1", "mesh": {"shape": "Torus", "radius": 4.2, "tube_radius": 0.2}, "transform": {"position": {"x": 90, "y": 10, "z": 40}}, "material": {"base_color": {"r": 0.1, "g": 0.8, "b": 1.0, "a": 1}, "emissive": {"r": 0.05, "g": 0.4, "b": 0.6, "a": 1}}, "animation": {"animation_type": {"type": "Spin", "speed": {"x": 0, "y": 40, "z": 0}}, "duration": 1.0, "looping": true}},
      {"type": "mesh3d", "id": "cp2", "mesh": {"shape": "Torus", "radius": 4.2, "tube_radius": 0.2}, "transform": {"position": {"x": 210, "y": 14, "z": -35}}, "material": {"base_color": {"r": 1.0, "g": 0.75, "b": 0.2, "a": 1}, "emissive": {"r": 0.5, "g": 0.2, "b": 0.0, "a": 1}}}
    ]}
  ]
}
```

### Example F: Stealth mission level (volumetric mood + patrol paths)

```json
{
  "world": [
    {"type": "environment", "ambient_intensity": 0.12, "fog_enabled": true, "fog_type": "exponential", "fog_density": 0.03, "fog_color": {"r": 0.05, "g": 0.07, "b": 0.09, "a": 1}},
    {"type": "camera", "camera_type": "Perspective", "transform": {"position": {"x": 0, "y": 9, "z": 22}, "rotation": {"x": -14, "y": 0, "z": 0}}},
    {"type": "light", "id": "moon", "light_type": "Directional", "color": {"r": 0.6, "g": 0.7, "b": 1.0, "a": 1}, "intensity": 0.45, "transform": {"rotation": {"x": -55, "y": -10, "z": 0}}},

    {"type": "mesh3d", "id": "yard", "mesh": {"shape": "Plane", "size": 220}, "material": {"base_color": {"r": 0.08, "g": 0.1, "b": 0.1, "a": 1}, "roughness": 1.0}},

    {"type": "group", "id": "guards", "children": [
      {"type": "mesh3d", "id": "guard-1", "mesh": {"shape": "File", "path": "models/guard.gltf"}, "transform": {"position": {"x": -20, "y": 0, "z": -12}}, "animation": {"animation_type": {"type": "Translate", "from": {"x": -20, "y": 0, "z": -12}, "to": {"x": 20, "y": 0, "z": -12}}, "duration": 7.0, "looping": true, "easing": "EaseInOut"}},
      {"type": "light", "id": "guard-spot", "light_type": "Spot", "intensity": 0.8, "transform": {"position": {"x": -20, "y": 3, "z": -12}, "rotation": {"x": -40, "y": 0, "z": 0}}}
    ]},

    {"type": "particles", "id": "mist", "transform": {"position": {"x": 0, "y": 0.5, "z": 0}}, "emitter": {"shape": "box", "emit_rate": 80, "lifetime": 5.0, "start_color": {"r": 0.7, "g": 0.8, "b": 0.9, "a": 0.28}, "end_color": {"r": 0.4, "g": 0.5, "b": 0.6, "a": 0.0}, "start_size": 0.4, "end_size": 0.9, "spread": 15, "speed": 0.35, "speed_variance": 0.2, "wind": {"x": 0.12, "y": 0, "z": 0.04}, "max_particles": 600, "blend_mode": "alpha"}}
  ]
}
```

### Example G: Action boss arena (projectiles, hazards, debris physics)

```json
{
  "world": [
    {"type": "environment", "ambient_intensity": 0.18, "fog_enabled": true, "fog_color": {"r": 0.18, "g": 0.12, "b": 0.12, "a": 1}, "fog_distance": 150},
    {"type": "camera", "camera_type": "Perspective", "mode": "orbit", "orbit_radius": 26, "orbit_speed": 6, "transform": {"position": {"x": 0, "y": 14, "z": 26}}},
    {"type": "light", "light_type": "Directional", "intensity": 1.15, "transform": {"rotation": {"x": -47, "y": 18, "z": 0}}},

    {"type": "mesh3d", "id": "arena-floor", "mesh": {"shape": "Cylinder", "radius": 24, "height": 1}, "transform": {"position": {"x": 0, "y": -0.5, "z": 0}}, "material": {"base_color": {"r": 0.22, "g": 0.18, "b": 0.16, "a": 1}, "roughness": 0.95}},

    {"type": "mesh3d", "id": "boss-core", "mesh": {"shape": "Sphere", "radius": 2.2, "subdivisions": 32}, "transform": {"position": {"x": 0, "y": 4, "z": 0}}, "material": {"base_color": {"r": 0.7, "g": 0.12, "b": 0.16, "a": 1}, "emissive": {"r": 0.8, "g": 0.15, "b": 0.2, "a": 1}, "emissive_strength": 2.8}, "animation": [{"animation_type": {"type": "Pulse", "min_scale": 0.92, "max_scale": 1.14}, "duration": 0.9, "looping": true, "easing": "Back"}]},

    {"type": "group", "id": "projectile-ring", "children": [
      {"type": "mesh3d", "id": "orb-1", "mesh": {"shape": "Sphere", "radius": 0.35, "subdivisions": 16}, "animation": {"animation_type": {"type": "Orbit", "radius": 6.5, "height": 3.0}, "duration": 2.8, "looping": true, "easing": "Linear"}},
      {"type": "mesh3d", "id": "orb-2", "mesh": {"shape": "Sphere", "radius": 0.35, "subdivisions": 16}, "animation": {"animation_type": {"type": "Orbit", "radius": 6.5, "height": 3.0}, "duration": 2.8, "looping": true, "easing": "Linear", "delay": 0.9}}
    ]},

    {"type": "rigidbody", "id": "debris-a", "mesh": "Cube", "transform": {"position": {"x": -5, "y": 12, "z": 2}}, "physics": {"mass": 1.2, "friction": 0.5, "restitution": 0.25, "use_gravity": true, "collider_type": "Box"}},
    {"type": "rigidbody", "id": "debris-b", "mesh": "Cube", "transform": {"position": {"x": 3, "y": 14, "z": -4}}, "physics": {"mass": 1.4, "friction": 0.45, "restitution": 0.3, "use_gravity": true, "collider_type": "Box"}},

    {"type": "particles", "id": "lava-sparks", "transform": {"position": {"x": 0, "y": 0.1, "z": 0}}, "emitter": {"shape": "ring", "emit_rate": 95, "lifetime": 1.4, "start_color": {"r": 1.0, "g": 0.55, "b": 0.1, "a": 1}, "end_color": {"r": 0.3, "g": 0.1, "b": 0.05, "a": 0}, "start_size": 0.1, "end_size": 0.0, "spread": 70, "speed": 3.2, "speed_variance": 1.0, "max_particles": 700}}
  ]
}
```
