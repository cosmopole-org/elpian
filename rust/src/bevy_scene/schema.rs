//! JSON 3D scene schema compatible with the Bevy renderer in src/graphics/schema.rs.
//!
//! This module provides serde-deserializable types that mirror the JSON format
//! used by the main Bevy-based renderer. Scenes defined in this format can be
//! rendered by the embedded software renderer for Flutter integration, or by
//! the standalone Bevy application.

use serde::{Deserialize, Serialize};

// ── Top-Level Scene ──────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SceneDef {
    #[serde(default)]
    pub ui: Vec<JsonNode>,
    #[serde(default)]
    pub world: Vec<JsonNode>,
}

/// The full scene document emitted by the game: a baked `staticWorld` (keyed by
/// `staticKey`, sent once and reused) plus the per-frame dynamic `world`. The
/// manager caches the parsed static world by key and only re-parses `world` each
/// tick (P3 frame splicing). `SceneDef` alone drops the static fields, so this is
/// the type used at the create/update boundary.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct SceneDoc {
    #[serde(default, rename = "staticKey")]
    pub static_key: Option<String>,
    #[serde(default, rename = "staticWorld")]
    pub static_world: Vec<JsonNode>,
    #[serde(default)]
    pub world: Vec<JsonNode>,
    #[serde(default)]
    pub ui: Vec<JsonNode>,
}

// ── Node Types ───────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum JsonNode {
    // UI Elements
    #[serde(rename = "container")]
    Container(ContainerNode),
    #[serde(rename = "text")]
    Text(TextNode),
    #[serde(rename = "button")]
    Button(ButtonNode),
    #[serde(rename = "image")]
    Image(ImageNode),

    // 3D World Elements
    #[serde(rename = "mesh3d")]
    Mesh3D(Mesh3DNode),
    #[serde(rename = "model3d", alias = "gltf")]
    Model3D(Model3DNode),
    #[serde(rename = "light")]
    Light(LightNode),
    #[serde(rename = "camera")]
    Camera(CameraNode),
    #[serde(rename = "particles")]
    Particles(ParticleNode),
    #[serde(rename = "terrain")]
    Terrain(TerrainNode),
    #[serde(rename = "skybox")]
    Skybox(SkyboxNode),
    #[serde(rename = "water")]
    Water(WaterNode),
    #[serde(rename = "rigidbody")]
    RigidBody(RigidBodyNode),
    #[serde(rename = "environment")]
    Environment(EnvironmentNode),

    // Scene composition
    #[serde(rename = "group")]
    Group(GroupNode),
}

// ── UI Nodes ─────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContainerNode {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub style: StyleDef,
    #[serde(default)]
    pub children: Vec<JsonNode>,
    #[serde(default)]
    pub background_color: Option<ColorDef>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TextNode {
    #[serde(default)]
    pub id: Option<String>,
    pub text: String,
    #[serde(default)]
    pub style: StyleDef,
    #[serde(default)]
    pub font_size: Option<f32>,
    #[serde(default)]
    pub color: Option<ColorDef>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ButtonNode {
    #[serde(default)]
    pub id: Option<String>,
    pub label: String,
    #[serde(default)]
    pub style: StyleDef,
    #[serde(default)]
    pub action: Option<String>,
    #[serde(default)]
    pub normal_color: Option<ColorDef>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImageNode {
    #[serde(default)]
    pub id: Option<String>,
    pub path: String,
    #[serde(default)]
    pub style: StyleDef,
}

// ── 3D World Nodes ───────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Mesh3DNode {
    #[serde(default)]
    pub id: Option<String>,
    pub mesh: MeshType,
    #[serde(default)]
    pub material: MaterialDef,
    #[serde(default)]
    pub transform: TransformDef,
    #[serde(default)]
    pub animation: Option<AnimationDef>,
    #[serde(default)]
    pub children: Vec<JsonNode>,
}

/// A streamed glTF/GLB model node (parity with scene3d's `model3d`). The model
/// bytes are supplied out-of-band (FFI feed / host bridge) and looked up by `model`
/// URL; until they resolve, the renderer draws a tinted capsule placeholder.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Model3DNode {
    #[serde(default)]
    pub id: Option<String>,
    /// Model URL/key used to look up the decoded glTF in the model cache.
    pub model: String,
    /// Playback time (seconds) used to sample the animation clip.
    #[serde(default)]
    pub anim_time: f32,
    /// Clip selector: a name (string) or an index (number). `None` = first clip.
    #[serde(default)]
    pub animation: Option<StringOrIndex>,
    /// Multiplicative tint applied to the model's base color.
    #[serde(default)]
    pub tint: Option<ColorDef>,
    #[serde(default)]
    pub emissive: Option<ColorDef>,
    #[serde(default)]
    pub emissive_strength: Option<f32>,
    #[serde(default)]
    pub transform: TransformDef,
    #[serde(default)]
    pub children: Vec<JsonNode>,
}

/// An animation clip selector accepted as either a clip name or a numeric index.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum StringOrIndex {
    Index(u32),
    Name(String),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LightNode {
    #[serde(default)]
    pub id: Option<String>,
    pub light_type: LightType,
    #[serde(default)]
    pub color: Option<ColorDef>,
    #[serde(default)]
    pub intensity: Option<f32>,
    /// Effective reach of a point/spot light. Past this distance the light
    /// contributes nothing (parity with scene3d's point-light `range`).
    #[serde(default)]
    pub range: Option<f32>,
    #[serde(default)]
    pub transform: TransformDef,
    #[serde(default)]
    pub animation: Option<AnimationDef>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CameraNode {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default = "default_camera_type")]
    pub camera_type: CameraType,
    #[serde(default)]
    pub transform: TransformDef,
    #[serde(default)]
    pub fov: Option<f32>,
    #[serde(default)]
    pub near: Option<f32>,
    #[serde(default)]
    pub far: Option<f32>,
    #[serde(default)]
    pub animation: Option<AnimationDef>,
}

fn default_camera_type() -> CameraType {
    CameraType::Perspective
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParticleNode {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub transform: TransformDef,
    #[serde(default = "default_emission_rate")]
    pub emission_rate: f32,
    #[serde(default = "default_one")]
    pub lifetime: f32,
    #[serde(default)]
    pub color: ColorDef,
    #[serde(default = "default_particle_size")]
    pub size: f32,
    #[serde(default)]
    pub velocity: Vec3Def,
    #[serde(default = "default_gravity")]
    pub gravity: Vec3Def,
}

fn default_emission_rate() -> f32 {
    10.0
}
fn default_one() -> f32 {
    1.0
}
fn default_particle_size() -> f32 {
    0.1
}
fn default_gravity() -> Vec3Def {
    Vec3Def {
        x: 0.0,
        y: -9.8,
        z: 0.0,
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerrainNode {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default = "default_terrain_size")]
    pub size: f32,
    #[serde(default)]
    pub height: f32,
    #[serde(default)]
    pub subdivisions: u32,
    #[serde(default)]
    pub heightmap: Option<String>,
    #[serde(default)]
    pub material: MaterialDef,
    #[serde(default)]
    pub transform: TransformDef,
}

fn default_terrain_size() -> f32 {
    100.0
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkyboxNode {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub texture_path: Option<String>,
    #[serde(default)]
    pub color: Option<ColorDef>,
    #[serde(default)]
    pub rotation: Option<Vec3Def>,
    #[serde(default = "default_one")]
    pub brightness: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WaterNode {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub size: Vec3Def,
    #[serde(default)]
    pub transform: TransformDef,
    #[serde(default = "default_wave_amp")]
    pub wave_amplitude: f32,
    #[serde(default = "default_one")]
    pub wave_frequency: f32,
    #[serde(default)]
    pub water_color: Option<ColorDef>,
    #[serde(default = "default_water_transparency")]
    pub transparency: f32,
}

fn default_wave_amp() -> f32 {
    0.5
}
fn default_water_transparency() -> f32 {
    0.7
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RigidBodyNode {
    #[serde(default)]
    pub id: Option<String>,
    pub mesh: MeshType,
    #[serde(default)]
    pub material: MaterialDef,
    #[serde(default)]
    pub transform: TransformDef,
    #[serde(default)]
    pub physics: PhysicsDef,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnvironmentNode {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default, alias = "ambient_color")]
    pub ambient_light: Option<ColorDef>,
    #[serde(default = "default_ambient_intensity")]
    pub ambient_intensity: f32,
    #[serde(default)]
    pub fog_enabled: bool,
    /// Fog falloff model: `"linear"` (near→distance ramp) — when present, fog is
    /// implicitly enabled even if `fog_enabled` is omitted.
    #[serde(default)]
    pub fog_type: Option<String>,
    #[serde(default)]
    pub fog_color: Option<ColorDef>,
    /// Distance at which linear fog begins (no fog closer than this).
    #[serde(default)]
    pub fog_near: Option<f32>,
    #[serde(default = "default_fog_distance")]
    pub fog_distance: f32,
    /// Vertical sky gradient endpoints used to clear the framebuffer.
    #[serde(default)]
    pub sky_color_top: Option<ColorDef>,
    #[serde(default)]
    pub sky_color_bottom: Option<ColorDef>,
}

fn default_ambient_intensity() -> f32 {
    0.8
}
fn default_fog_distance() -> f32 {
    100.0
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupNode {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub transform: TransformDef,
    #[serde(default)]
    pub children: Vec<JsonNode>,
}

// ── Shared Types ─────────────────────────────────────────────────────

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct StyleDef {
    #[serde(default)]
    pub width: Option<String>,
    #[serde(default)]
    pub height: Option<String>,
    #[serde(default)]
    pub padding: Option<RectDef>,
    #[serde(default)]
    pub margin: Option<RectDef>,
    #[serde(default)]
    pub flex_direction: Option<String>,
    #[serde(default)]
    pub justify_content: Option<String>,
    #[serde(default)]
    pub align_items: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RectDef {
    #[serde(default)]
    pub top: f32,
    #[serde(default)]
    pub bottom: f32,
    #[serde(default)]
    pub left: f32,
    #[serde(default)]
    pub right: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ColorDef {
    #[serde(default)]
    pub r: f32,
    #[serde(default)]
    pub g: f32,
    #[serde(default)]
    pub b: f32,
    #[serde(default = "default_alpha")]
    pub a: f32,
}

impl Default for ColorDef {
    fn default() -> Self {
        Self {
            r: 1.0,
            g: 1.0,
            b: 1.0,
            a: 1.0,
        }
    }
}

fn default_alpha() -> f32 {
    1.0
}

impl ColorDef {
    pub fn to_rgba_u8(&self) -> [u8; 4] {
        [
            (self.r.clamp(0.0, 1.0) * 255.0) as u8,
            (self.g.clamp(0.0, 1.0) * 255.0) as u8,
            (self.b.clamp(0.0, 1.0) * 255.0) as u8,
            (self.a.clamp(0.0, 1.0) * 255.0) as u8,
        ]
    }

    pub fn to_vec3(&self) -> glam::Vec3 {
        glam::Vec3::new(self.r, self.g, self.b)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Vec3Def {
    #[serde(default)]
    pub x: f32,
    #[serde(default)]
    pub y: f32,
    #[serde(default)]
    pub z: f32,
}

impl Default for Vec3Def {
    fn default() -> Self {
        Self {
            x: 0.0,
            y: 0.0,
            z: 0.0,
        }
    }
}

impl Vec3Def {
    pub fn to_glam(&self) -> glam::Vec3 {
        glam::Vec3::new(self.x, self.y, self.z)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransformDef {
    #[serde(default)]
    pub position: Option<Vec3Def>,
    #[serde(default)]
    pub rotation: Option<Vec3Def>, // Euler angles in degrees
    #[serde(default)]
    pub scale: Option<Vec3Def>,
}

impl Default for TransformDef {
    fn default() -> Self {
        Self {
            position: None,
            rotation: None,
            scale: None,
        }
    }
}

impl TransformDef {
    pub fn to_mat4(&self) -> glam::Mat4 {
        let translation = self
            .position
            .as_ref()
            .map(|p| glam::Vec3::new(p.x, p.y, p.z))
            .unwrap_or(glam::Vec3::ZERO);

        let rotation = self
            .rotation
            .as_ref()
            .map(|r| {
                glam::Quat::from_euler(
                    glam::EulerRot::XYZ,
                    r.x.to_radians(),
                    r.y.to_radians(),
                    r.z.to_radians(),
                )
            })
            .unwrap_or(glam::Quat::IDENTITY);

        let scale = self
            .scale
            .as_ref()
            .map(|s| glam::Vec3::new(s.x, s.y, s.z))
            .unwrap_or(glam::Vec3::ONE);

        glam::Mat4::from_scale_rotation_translation(scale, rotation, translation)
    }
}

// ── Mesh Types ───────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum MeshType {
    Named(MeshTypeName),
    Parameterized(MeshTypeParam),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MeshTypeName {
    Cube,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "shape")]
pub enum MeshTypeParam {
    Sphere {
        #[serde(default = "default_one")]
        radius: f32,
        // `segments` is the scene3d/glTF spelling; accept it as an alias so the
        // same DSL drives both renderers.
        #[serde(default = "default_subdivisions", alias = "segments")]
        subdivisions: u32,
    },
    Plane {
        #[serde(default = "default_one")]
        size: f32,
    },
    Capsule {
        #[serde(default = "default_half")]
        radius: f32,
        #[serde(default = "default_one")]
        depth: f32,
    },
    Cylinder {
        #[serde(default = "default_half")]
        radius: f32,
        #[serde(default = "default_one")]
        height: f32,
        #[serde(default = "default_radial_segments")]
        segments: u32,
    },
    Cone {
        #[serde(default = "default_half")]
        radius: f32,
        #[serde(default = "default_one")]
        height: f32,
        #[serde(default = "default_radial_segments")]
        segments: u32,
    },
    Torus {
        #[serde(default = "default_one")]
        radius: f32,
        #[serde(default = "default_quarter")]
        tube_radius: f32,
    },
    File {
        path: String,
    },
}

fn default_subdivisions() -> u32 {
    16
}
fn default_radial_segments() -> u32 {
    16
}
fn default_half() -> f32 {
    0.5
}
fn default_quarter() -> f32 {
    0.25
}

// ── Material Types ───────────────────────────────────────────────────

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct MaterialDef {
    #[serde(default)]
    pub base_color: Option<ColorDef>,
    #[serde(default)]
    pub base_color_texture: Option<String>,
    #[serde(default)]
    pub emissive: Option<ColorDef>,
    /// Multiplier applied to `emissive` (parity with the scene3d renderer's
    /// `emissive_strength`). Lets neon / glow surfaces push past 1.0.
    #[serde(default)]
    pub emissive_strength: Option<f32>,
    #[serde(default)]
    pub metallic: Option<f32>,
    #[serde(default)]
    pub roughness: Option<f32>,
    #[serde(default)]
    pub normal_map_texture: Option<String>,
    #[serde(default)]
    pub alpha_mode: Option<AlphaMode>,
    /// Explicit scalar opacity (0..1). Takes precedence over `base_color.a`.
    #[serde(default)]
    pub alpha: Option<f32>,
    #[serde(default)]
    pub double_sided: bool,
    /// Skip lighting and output `base_color*texture (+ emissive)` directly —
    /// used for paint markings, neon, tracers and other self-lit surfaces.
    #[serde(default)]
    pub unlit: bool,
    /// Procedural texture kind: `"noise" | "checkerboard" | "stripes" | "gradient"`.
    #[serde(default)]
    pub texture: Option<String>,
    /// Secondary color the procedural texture blends toward.
    #[serde(default)]
    pub texture_color2: Option<ColorDef>,
    /// UV scale (tiling) for the procedural texture.
    #[serde(default)]
    pub texture_scale: Option<f32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum AlphaMode {
    #[serde(alias = "opaque", alias = "OPAQUE")]
    Opaque,
    #[serde(alias = "mask", alias = "MASK")]
    Mask,
    #[serde(alias = "blend", alias = "BLEND")]
    Blend,
}

// ── Light Types ──────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum LightType {
    Point,
    Directional,
    Spot,
    /// Documented in 3D_GRAPHICS.md; shaded as an omnidirectional point
    /// source (the closest software-rasterizer approximation).
    Area,
}

// ── Camera Types ─────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum CameraType {
    Perspective,
    Orthographic,
}

// ── Animation Types ──────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnimationDef {
    pub animation_type: AnimationType,
    #[serde(default = "default_one")]
    pub duration: f32,
    #[serde(default)]
    pub looping: bool,
    #[serde(default)]
    pub easing: EasingType,
    /// Seconds to wait before the animation starts (parity with scene3d).
    #[serde(default)]
    pub delay: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum AnimationType {
    Rotate {
        #[serde(default = "default_axis_y")]
        axis: Vec3Def,
        #[serde(default = "default_degrees")]
        degrees: f32,
    },
    Translate {
        #[serde(default)]
        from: Vec3Def,
        #[serde(default = "default_axis_y")]
        to: Vec3Def,
    },
    Scale {
        #[serde(default = "default_vec_one")]
        from: Vec3Def,
        #[serde(default = "default_vec_two")]
        to: Vec3Def,
    },
    Bounce {
        #[serde(default = "default_bounce_height")]
        height: f32,
    },
    Pulse {
        #[serde(default = "default_pulse_min")]
        min_scale: f32,
        #[serde(default = "default_pulse_max")]
        max_scale: f32,
    },
    Orbit {
        #[serde(default = "default_orbit_radius")]
        radius: f32,
        #[serde(default)]
        height: f32,
    },
    Swing {
        #[serde(default = "default_swing_angle")]
        angle: f32,
        #[serde(default = "default_axis_z")]
        axis: Vec3Def,
    },
    Shake {
        #[serde(default = "default_shake_intensity")]
        intensity: f32,
    },
    Float {
        #[serde(default = "default_float_amplitude")]
        amplitude: f32,
    },
    Spin {
        #[serde(default = "default_spin_speed")]
        speed: Vec3Def,
    },
}

fn default_axis_y() -> Vec3Def {
    Vec3Def { x: 0.0, y: 1.0, z: 0.0 }
}
fn default_axis_z() -> Vec3Def {
    Vec3Def { x: 0.0, y: 0.0, z: 1.0 }
}
fn default_vec_one() -> Vec3Def {
    Vec3Def { x: 1.0, y: 1.0, z: 1.0 }
}
fn default_vec_two() -> Vec3Def {
    Vec3Def { x: 2.0, y: 2.0, z: 2.0 }
}
fn default_degrees() -> f32 {
    360.0
}
fn default_bounce_height() -> f32 {
    1.5
}
fn default_pulse_min() -> f32 {
    0.8
}
fn default_pulse_max() -> f32 {
    1.2
}
fn default_orbit_radius() -> f32 {
    3.0
}
fn default_swing_angle() -> f32 {
    45.0
}
fn default_shake_intensity() -> f32 {
    0.1
}
fn default_float_amplitude() -> f32 {
    0.5
}
fn default_spin_speed() -> Vec3Def {
    Vec3Def { x: 0.0, y: 90.0, z: 0.0 }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub enum EasingType {
    #[default]
    Linear,
    EaseIn,
    EaseOut,
    EaseInOut,
    Bounce,
    Elastic,
    Back,
    Sine,
}

// ── Physics Types ────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PhysicsDef {
    #[serde(default = "default_one")]
    pub mass: f32,
    #[serde(default = "default_friction")]
    pub friction: f32,
    #[serde(default)]
    pub restitution: f32,
    #[serde(default = "default_one")]
    pub gravity_scale: f32,
    #[serde(default = "default_true")]
    pub use_gravity: bool,
    #[serde(default)]
    pub collider_type: ColliderType,
}

fn default_friction() -> f32 {
    0.3
}
fn default_true() -> bool {
    true
}

impl Default for PhysicsDef {
    fn default() -> Self {
        Self {
            mass: 1.0,
            friction: 0.3,
            restitution: 0.0,
            gravity_scale: 1.0,
            use_gravity: true,
            collider_type: ColliderType::default(),
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub enum ColliderType {
    #[default]
    Box,
    Sphere,
    Capsule,
    Mesh,
}

// ── Input Events ─────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InputEvent {
    pub event_type: InputEventType,
    pub x: f32,
    pub y: f32,
    #[serde(default)]
    pub delta_x: f32,
    #[serde(default)]
    pub delta_y: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum InputEventType {
    TouchDown,
    TouchMove,
    TouchUp,
    MouseMove,
    MouseWheel,
}
