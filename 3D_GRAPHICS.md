# Elpian 3D Graphics Reference

Complete reference for Elpian's 3D scene system. Scenes are defined in JSON and rendered via Bevy (Rust/GPU) or the pure-Dart Canvas renderer (Flutter/mobile).

## Scene Structure

3D elements live in the `"world"` array of a scene JSON:

```json
{
  "ui": [ /* 2D UI nodes */ ],
  "world": [ /* 3D world nodes */ ]
}
```

Each world node is a tagged JSON object with a `"type"` field.

---

## 3D Elements

### mesh3d

Renderable 3D geometry with materials.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `mesh` | MeshType | *required* | Geometry primitive or file |
| `material` | MaterialDef | {} | PBR material properties |
| `transform` | TransformDef | {} | Position, rotation, scale |
| `animation` | AnimationDef? | null | Animation definition |

```json
{
  "type": "mesh3d",
  "mesh": "Cube",
  "material": {
    "base_color": {"r": 0.8, "g": 0.2, "b": 0.1, "a": 1.0},
    "metallic": 0.5,
    "roughness": 0.3
  },
  "transform": {
    "position": {"x": 0, "y": 2, "z": 0},
    "scale": {"x": 2, "y": 2, "z": 2}
  },
  "animation": {
    "animation_type": {"type": "Rotate", "axis": {"x": 0, "y": 1, "z": 0}, "degrees": 360},
    "duration": 4.0,
    "looping": true,
    "easing": "Linear"
  }
}
```

**Bevy mapping:** `Mesh3d` + `MeshMaterial3d` + `Transform`

---

### light

Illumination source for the scene.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `light_type` | LightType | *required* | `Point`, `Directional`, or `Spot` |
| `color` | ColorDef? | null | Light color |
| `intensity` | f32? | null | Light intensity (candela for point, illuminance for directional) |
| `transform` | TransformDef | {} | Position and direction |
| `animation` | AnimationDef? | null | Animation definition |

```json
{
  "type": "light",
  "light_type": "Directional",
  "color": {"r": 1.0, "g": 0.95, "b": 0.8, "a": 1.0},
  "intensity": 1000.0,
  "transform": {
    "position": {"x": 10, "y": 10, "z": 5},
    "rotation": {"x": -45, "y": 30, "z": 0}
  }
}
```

**Light types:**

| Type | Behavior | Key Properties |
|---|---|---|
| `Point` | Omnidirectional from a point | `intensity` (candela), position |
| `Directional` | Parallel rays (sun/moon) | `intensity` (illuminance), rotation |
| `Spot` | Cone-shaped beam | `intensity`, position, rotation |

**Bevy mapping:** `PointLight` / `DirectionalLight` / `SpotLight` + `Transform`

---

### camera

Scene viewpoint.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `camera_type` | CameraType | *required* | `Perspective` or `Orthographic` |
| `transform` | TransformDef | {} | Camera position and orientation |
| `animation` | AnimationDef? | null | Animation definition |

```json
{
  "type": "camera",
  "camera_type": "Perspective",
  "transform": {
    "position": {"x": 0, "y": 5, "z": 10},
    "rotation": {"x": -20, "y": 0, "z": 0}
  }
}
```

**Bevy mapping:** `Camera3d` + `Transform` + `Projection`

---

### audio

Audio playback (supports spatial 3D audio).

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `path` | String | *required* | Audio file path |
| `volume` | f32 | 1.0 | Volume level (0.0-1.0) |
| `looping` | bool | false | Loop playback |
| `autoplay` | bool | true | Start playing automatically |
| `spatial` | bool | false | Enable 3D spatial audio |
| `transform` | TransformDef? | null | Position for spatial audio |

```json
{
  "type": "audio",
  "path": "sounds/ambient.ogg",
  "volume": 0.7,
  "looping": true,
  "spatial": true,
  "transform": {"position": {"x": 5, "y": 0, "z": 3}}
}
```

**Bevy mapping:** `AudioPlayer` + `AudioComponent`

---

### particles

Particle system emitter.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `transform` | TransformDef | {} | Emitter position |
| `emission_rate` | f32 | 10.0 | Particles emitted per second |
| `lifetime` | f32 | 1.0 | Particle lifespan in seconds |
| `color` | ColorDef | white | Particle color |
| `size` | f32 | 0.1 | Particle size |
| `velocity` | Vec3Def | {0, 1, 0} | Initial velocity vector |
| `gravity` | Vec3Def | {0, -9.8, 0} | Gravity acceleration |

```json
{
  "type": "particles",
  "transform": {"position": {"x": 0, "y": 5, "z": 0}},
  "emission_rate": 50.0,
  "lifetime": 2.0,
  "color": {"r": 1.0, "g": 0.8, "b": 0.0, "a": 1.0},
  "size": 0.15,
  "velocity": {"x": 0, "y": 3, "z": 0},
  "gravity": {"x": 0, "y": -9.8, "z": 0}
}
```

**Bevy mapping:** `ParticleEmitter` + `Particle`

---

### terrain

Height-based landscape surface.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `size` | f32 | 0.0 | Terrain plane size |
| `height` | f32 | 0.0 | Maximum height variation |
| `subdivisions` | u32 | 0 | Mesh resolution (grid divisions) |
| `heightmap` | String? | null | Heightmap texture path |
| `material` | MaterialDef | {} | Surface material |
| `transform` | TransformDef | {} | Position in world |
| `physics` | PhysicsDef? | null | Collision settings |

```json
{
  "type": "terrain",
  "size": 100.0,
  "height": 20.0,
  "subdivisions": 64,
  "heightmap": "textures/heightmap.png",
  "material": {
    "base_color": {"r": 0.3, "g": 0.6, "b": 0.2, "a": 1.0},
    "roughness": 0.9
  },
  "physics": {"use_gravity": false, "collider_type": "Mesh"}
}
```

**Bevy mapping:** `Terrain` + `Mesh3d` + `MeshMaterial3d`

---

### skybox

Background sky environment.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `texture_path` | String | *required* | Cubemap texture path |
| `rotation` | Vec3Def? | null | Sky rotation (Euler degrees) |
| `brightness` | f32 | 1.0 | Sky brightness multiplier |

```json
{
  "type": "skybox",
  "texture_path": "textures/sky_cubemap.png",
  "brightness": 1.2,
  "rotation": {"x": 0, "y": 45, "z": 0}
}
```

**Bevy mapping:** `SkyboxComponent`

---

### foliage

Vegetation elements (trees, grass, bushes).

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `foliage_type` | FoliageType | *required* | `Trees`, `Grass`, `Bushes`, or `Custom {model_path}` |
| `density` | f32 | 0.0 | Placement density |
| `color_variation` | f32 | 0.0 | Color variance (0.0-1.0) |
| `transform` | TransformDef | {} | Base position |
| `material` | MaterialDef | {} | Foliage material |

```json
{
  "type": "foliage",
  "foliage_type": "Trees",
  "density": 0.5,
  "color_variation": 0.2,
  "transform": {"position": {"x": 0, "y": 0, "z": 0}},
  "material": {
    "base_color": {"r": 0.2, "g": 0.7, "b": 0.15, "a": 1.0}
  }
}
```

**Bevy mapping:** `Foliage` + `Mesh3d` + `MeshMaterial3d`

---

### decal

Surface-projected texture overlay.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `texture` | String | *required* | Decal texture path |
| `transform` | TransformDef | {} | Decal position and orientation |
| `size` | Vec3Def | {0,0,0} | Decal dimensions |
| `sort_order` | i32 | 0 | Rendering order |

```json
{
  "type": "decal",
  "texture": "textures/blood_splatter.png",
  "transform": {"position": {"x": 3, "y": 0.01, "z": -2}},
  "size": {"x": 2, "y": 2, "z": 2},
  "sort_order": 1
}
```

**Bevy mapping:** `Decal` + `Transform`

---

### billboard

Screen-facing or axis-aligned sprite in 3D space.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `texture` | String | *required* | Billboard texture path |
| `transform` | TransformDef | {} | Billboard position |
| `size` | Vec3Def | {0,0,0} | Billboard dimensions |
| `billboard_type` | BillboardType | ScreenAligned | `ScreenAligned`, `AxisAligned`, `Cylindrical` |

```json
{
  "type": "billboard",
  "texture": "textures/tree_sprite.png",
  "billboard_type": "Cylindrical",
  "transform": {"position": {"x": 10, "y": 3, "z": -5}},
  "size": {"x": 4, "y": 6, "z": 1}
}
```

**Bevy mapping:** `Billboard` + `Transform`

---

### water

Animated water surface with wave effects.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `size` | Vec3Def | {0,0,0} | Water plane dimensions |
| `transform` | TransformDef | {} | Water position |
| `wave_amplitude` | f32 | 0.5 | Wave height |
| `wave_frequency` | f32 | 1.0 | Wave oscillation speed |
| `water_color` | ColorDef? | null | Water tint color |
| `transparency` | f32 | 0.7 | Water alpha (0.0-1.0) |

```json
{
  "type": "water",
  "size": {"x": 50, "y": 0, "z": 50},
  "transform": {"position": {"x": 0, "y": -1, "z": 0}},
  "wave_amplitude": 0.3,
  "wave_frequency": 1.5,
  "water_color": {"r": 0.1, "g": 0.4, "b": 0.8, "a": 1.0},
  "transparency": 0.6
}
```

**Bevy mapping:** `Water` + `Mesh3d` + `MeshMaterial3d`

---

### rigidbody

Physics-enabled 3D object.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `mesh` | MeshType | *required* | Object geometry |
| `material` | MaterialDef | {} | PBR material |
| `transform` | TransformDef | {} | Initial position/rotation/scale |
| `physics` | PhysicsDef | defaults | Physics simulation properties |

```json
{
  "type": "rigidbody",
  "mesh": {"Sphere": {"radius": 0.5, "subdivisions": 16}},
  "material": {
    "base_color": {"r": 0.9, "g": 0.1, "b": 0.1, "a": 1.0},
    "metallic": 0.8,
    "roughness": 0.2
  },
  "transform": {"position": {"x": 0, "y": 10, "z": 0}},
  "physics": {
    "mass": 2.0,
    "restitution": 0.7,
    "friction": 0.3,
    "use_gravity": true,
    "collider_type": "Sphere"
  }
}
```

**Bevy mapping:** `RigidBodyComponent` + `Mesh3d` + `MeshMaterial3d` + `Physics`

---

### environment

Global scene environment settings.

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | String? | null | Optional identifier |
| `ambient_light` | ColorDef? | null | Ambient light color |
| `ambient_intensity` | f32 | 0.8 | Ambient light intensity |
| `fog_enabled` | bool | false | Enable distance fog |
| `fog_color` | ColorDef? | null | Fog color |
| `fog_distance` | f32 | 100.0 | Fog start distance |

```json
{
  "type": "environment",
  "ambient_light": {"r": 0.4, "g": 0.4, "b": 0.5, "a": 1.0},
  "ambient_intensity": 0.3,
  "fog_enabled": true,
  "fog_color": {"r": 0.7, "g": 0.7, "b": 0.8, "a": 1.0},
  "fog_distance": 150.0
}
```

**Bevy mapping:** `Environment` component

---

## Shared Type Definitions

### MeshType

Built-in geometry primitives:

| Mesh | JSON | Parameters |
|---|---|---|
| Cube | `"Cube"` | none |
| Sphere | `{"Sphere": {...}}` | `radius` (f32), `subdivisions` (u32) |
| Plane | `{"Plane": {...}}` | `size` (f32) |
| Capsule | `{"Capsule": {...}}` | `radius` (f32), `depth` (f32) |
| Cylinder | `{"Cylinder": {...}}` | `radius` (f32), `height` (f32) |
| Cone | `{"Cone": {...}}` | `radius` (f32), `height` (f32) |
| Torus | `{"Torus": {...}}` | `radius` (f32), `tube_radius` (f32) |
| Icosphere | `{"Icosphere": {...}}` | `radius` (f32), `subdivisions` (u32) |
| UvSphere | `{"UvSphere": {...}}` | `radius` (f32), `sectors` (u32), `stacks` (u32) |
| Grid | `{"Grid": {...}}` | `width` (u32), `height` (u32), `spacing` (f32) |
| File | `{"File": {...}}` | `path` (String) — loads .obj, .gltf, etc. |

Examples:

```json
"Cube"
{"Sphere": {"radius": 2.0, "subdivisions": 32}}
{"Torus": {"radius": 3.0, "tube_radius": 0.5}}
{"File": {"path": "models/character.gltf"}}
```

---

### MaterialDef

PBR (Physically Based Rendering) material properties:

| Property | Type | Default | Description |
|---|---|---|---|
| `base_color` | ColorDef? | null | Albedo/diffuse color |
| `base_color_texture` | String? | null | Albedo texture path |
| `emissive` | ColorDef? | null | Self-illumination color |
| `emissive_texture` | String? | null | Emissive texture path |
| `metallic` | f32? | null | Metallic factor (0.0-1.0) |
| `roughness` | f32? | null | Surface roughness (0.0-1.0) |
| `metallic_roughness_texture` | String? | null | Combined metallic/roughness map |
| `normal_map_texture` | String? | null | Normal map for surface detail |
| `ambient_occlusion_texture` | String? | null | AO texture |
| `height_map_texture` | String? | null | Parallax/height map |
| `parallax_depth` | f32? | null | Parallax mapping depth |
| `alpha_mode` | AlphaMode? | null | `Opaque`, `Mask`, or `Blend` |
| `double_sided` | bool | false | Render both faces |
| `ior` | f32? | null | Index of refraction |

**Alpha modes:**

| Mode | Description | Use Case |
|---|---|---|
| `Opaque` | Fully opaque, no transparency | Solid objects |
| `Mask` | Binary transparency (opaque or invisible) | Leaves, fences, cutouts |
| `Blend` | Per-pixel alpha transparency | Glass, smoke, water |

Example:

```json
{
  "base_color": {"r": 0.8, "g": 0.2, "b": 0.1, "a": 1.0},
  "base_color_texture": "textures/diffuse.png",
  "metallic": 0.7,
  "roughness": 0.3,
  "normal_map_texture": "textures/normal.png",
  "emissive": {"r": 0.1, "g": 0.0, "b": 0.0, "a": 1.0},
  "alpha_mode": "Opaque",
  "double_sided": false
}
```

---

### TransformDef

Position, rotation, and scale in 3D space:

| Property | Type | Default | Description |
|---|---|---|---|
| `position` | Vec3Def? | null | World position (x, y, z) |
| `rotation` | Vec3Def? | null | Euler angles in degrees (x, y, z) |
| `scale` | Vec3Def? | null | Scale multipliers (x, y, z) |

Transform composition order: **Scale -> Rotate -> Translate (TRS)**.

```json
{
  "position": {"x": 5.0, "y": 2.0, "z": 0.0},
  "rotation": {"x": 0, "y": 45, "z": 0},
  "scale": {"x": 2.0, "y": 1.0, "z": 1.5}
}
```

---

### Vec3Def

3D vector with x, y, z components (all default to 0.0):

```json
{"x": 1.0, "y": 2.0, "z": 3.0}
```

---

### ColorDef

RGBA color with channels from 0.0 to 1.0:

```json
{"r": 0.2, "g": 0.6, "b": 1.0, "a": 1.0}
```

Default: `{"r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0}` (white).

---

### AnimationDef

Defines animated behavior for 3D elements:

| Property | Type | Default | Description |
|---|---|---|---|
| `animation_type` | AnimationType | *required* | Animation kind and parameters |
| `duration` | f32 | 0.0 | Duration in seconds |
| `looping` | bool | false | Repeat the animation |
| `easing` | EasingType | Linear | Timing function |

**Animation types:**

| Type | Parameters | Description |
|---|---|---|
| `Rotate` | `axis` (Vec3Def), `degrees` (f32) | Rotate around an axis |
| `Translate` | `from` (Vec3Def), `to` (Vec3Def) | Move between two points |
| `Scale` | `from` (Vec3Def), `to` (Vec3Def) | Scale between two sizes |
| `Bounce` | `height` (f32) | Bounce up and down |
| `Pulse` | `min_scale` (f32), `max_scale` (f32) | Scale pulsing |

**Easing types:** `Linear`, `EaseIn`, `EaseOut`, `EaseInOut`, `Bounce`

Examples:

```json
// Continuous Y-axis rotation
{
  "animation_type": {"type": "Rotate", "axis": {"x": 0, "y": 1, "z": 0}, "degrees": 360},
  "duration": 4.0,
  "looping": true,
  "easing": "Linear"
}

// Translate back and forth
{
  "animation_type": {
    "type": "Translate",
    "from": {"x": -5, "y": 0, "z": 0},
    "to": {"x": 5, "y": 0, "z": 0}
  },
  "duration": 3.0,
  "looping": true,
  "easing": "EaseInOut"
}

// Pulsing effect
{
  "animation_type": {"type": "Pulse", "min_scale": 0.8, "max_scale": 1.2},
  "duration": 1.5,
  "looping": true,
  "easing": "EaseInOut"
}
```

---

### PhysicsDef

Physics simulation properties for rigid bodies:

| Property | Type | Default | Description |
|---|---|---|---|
| `mass` | f32 | 1.0 | Object mass |
| `friction` | f32 | 0.3 | Surface friction coefficient |
| `restitution` | f32 | 0.0 | Bounciness (0.0 = no bounce, 1.0 = full) |
| `gravity_scale` | f32 | 1.0 | Gravity multiplier |
| `use_gravity` | bool | true | Enable gravity for this object |
| `collider_type` | ColliderType | Box | `Box`, `Sphere`, `Capsule`, `Mesh` |

```json
{
  "mass": 5.0,
  "friction": 0.5,
  "restitution": 0.8,
  "use_gravity": true,
  "collider_type": "Sphere"
}
```

---

## Rendering Pipeline

### Bevy (Rust/GPU)

1. `JsonScene::load_from_file()` parses JSON into `SceneDef`
2. `JsonToBevy::spawn_world()` creates Bevy ECS entities for each node
3. `animation_system` updates transforms each frame
4. `particle_system` spawns/updates/removes particles
5. `water_system` animates wave displacement
6. Bevy's built-in rendering pipeline handles GPU rasterization, lighting, and shadows

### Dart (Flutter/Canvas)

1. `SceneParser::parse()` creates `ParsedScene` with nodes, lights, and camera
2. `Scene3DRenderer::render()` per frame:
   - Update camera (orbit, follow, animation)
   - Transform vertices to world/clip space
   - Evaluate animations
   - Per-vertex lighting (Lambertian diffuse + Blinn-Phong specular)
   - Near-plane clipping (Sutherland-Hodgman)
   - Perspective divide and screen mapping
   - Back-face culling (unless `double_sided`)
   - Fog blending
   - Painter's algorithm sorting (back-to-front)
   - Canvas rasterization

---

## Complete Scene Example

```json
{
  "world": [
    {
      "type": "environment",
      "ambient_light": {"r": 0.3, "g": 0.3, "b": 0.4, "a": 1.0},
      "ambient_intensity": 0.4,
      "fog_enabled": true,
      "fog_distance": 200.0
    },
    {
      "type": "camera",
      "camera_type": "Perspective",
      "transform": {
        "position": {"x": 0, "y": 8, "z": 15},
        "rotation": {"x": -25, "y": 0, "z": 0}
      }
    },
    {
      "type": "light",
      "light_type": "Directional",
      "color": {"r": 1.0, "g": 0.95, "b": 0.8, "a": 1.0},
      "intensity": 1500.0,
      "transform": {
        "rotation": {"x": -50, "y": 30, "z": 0}
      }
    },
    {
      "type": "light",
      "light_type": "Point",
      "color": {"r": 1.0, "g": 0.6, "b": 0.2, "a": 1.0},
      "intensity": 500.0,
      "transform": {
        "position": {"x": -3, "y": 4, "z": 0}
      }
    },
    {
      "type": "terrain",
      "size": 80.0,
      "subdivisions": 32,
      "material": {
        "base_color": {"r": 0.35, "g": 0.55, "b": 0.2, "a": 1.0},
        "roughness": 0.95
      },
      "physics": {"use_gravity": false, "collider_type": "Mesh"}
    },
    {
      "type": "mesh3d",
      "mesh": "Cube",
      "material": {
        "base_color": {"r": 0.7, "g": 0.7, "b": 0.75, "a": 1.0},
        "metallic": 0.1,
        "roughness": 0.6
      },
      "transform": {
        "position": {"x": 0, "y": 1, "z": 0},
        "scale": {"x": 2, "y": 2, "z": 2}
      }
    },
    {
      "type": "mesh3d",
      "mesh": {"Sphere": {"radius": 1.0, "subdivisions": 24}},
      "material": {
        "base_color": {"r": 0.9, "g": 0.2, "b": 0.2, "a": 1.0},
        "metallic": 0.8,
        "roughness": 0.15
      },
      "transform": {
        "position": {"x": 0, "y": 5, "z": 0}
      },
      "animation": {
        "animation_type": {"type": "Bounce", "height": 2.0},
        "duration": 2.0,
        "looping": true,
        "easing": "EaseInOut"
      }
    },
    {
      "type": "mesh3d",
      "mesh": {"Torus": {"radius": 3.0, "tube_radius": 0.4}},
      "material": {
        "base_color": {"r": 1.0, "g": 0.84, "b": 0.0, "a": 1.0},
        "metallic": 0.9,
        "roughness": 0.1
      },
      "transform": {
        "position": {"x": 0, "y": 3, "z": 0}
      },
      "animation": {
        "animation_type": {"type": "Rotate", "axis": {"x": 1, "y": 0, "z": 0}, "degrees": 360},
        "duration": 6.0,
        "looping": true,
        "easing": "Linear"
      }
    },
    {
      "type": "particles",
      "transform": {"position": {"x": 5, "y": 0, "z": -3}},
      "emission_rate": 30.0,
      "lifetime": 3.0,
      "color": {"r": 1.0, "g": 0.5, "b": 0.0, "a": 1.0},
      "size": 0.1,
      "velocity": {"x": 0, "y": 4, "z": 0},
      "gravity": {"x": 0, "y": -2, "z": 0}
    },
    {
      "type": "water",
      "size": {"x": 30, "y": 0, "z": 30},
      "transform": {"position": {"x": 20, "y": -0.5, "z": 0}},
      "wave_amplitude": 0.2,
      "wave_frequency": 1.0,
      "water_color": {"r": 0.1, "g": 0.3, "b": 0.7, "a": 1.0},
      "transparency": 0.5
    }
  ]
}
```

---

## Element Summary Table

| Element | Type Tag | Bevy Component(s) |
|---|---|---|
| Mesh | `mesh3d` | `Mesh3d` + `MeshMaterial3d` + `Transform` |
| Light | `light` | `PointLight` / `DirectionalLight` / `SpotLight` + `Transform` |
| Camera | `camera` | `Camera3d` + `Transform` + `Projection` |
| Audio | `audio` | `AudioPlayer` + `AudioComponent` |
| Particles | `particles` | `ParticleEmitter` + `Particle` |
| Terrain | `terrain` | `Terrain` + `Mesh3d` + `MeshMaterial3d` |
| Skybox | `skybox` | `SkyboxComponent` |
| Foliage | `foliage` | `Foliage` + `Mesh3d` + `MeshMaterial3d` |
| Decal | `decal` | `Decal` + `Transform` |
| Billboard | `billboard` | `Billboard` + `Transform` |
| Water | `water` | `Water` + `Mesh3d` + `MeshMaterial3d` |
| Rigid Body | `rigidbody` | `RigidBodyComponent` + `Mesh3d` + `MeshMaterial3d` + `Physics` |
| Environment | `environment` | `Environment` component |
