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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LightNode {
    #[serde(default)]
    pub id: Option<String>,
    pub light_type: LightType,
    #[serde(default)]
    pub color: Option<ColorDef>,
    #[serde(default)]
    pub intensity: Option<f32>,
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

fn default_emission_rate() -> f32 { 10.0 }
fn default_one() -> f32 { 1.0 }
fn default_particle_size() -> f32 { 0.1 }
fn default_gravity() -> Vec3Def { Vec3Def { x: 0.0, y: -9.8, z: 0.0 } }

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

fn default_terrain_size() -> f32 { 100.0 }

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

fn default_wave_amp() -> f32 { 0.5 }
fn default_water_transparency() -> f32 { 0.7 }

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
    #[serde(default)]
    pub ambient_light: Option<ColorDef>,
    #[serde(default = "default_ambient_intensity")]
    pub ambient_intensity: f32,
    #[serde(default)]
    pub fog_enabled: bool,
    #[serde(default)]
    pub fog_color: Option<ColorDef>,
    #[serde(default = "default_fog_distance")]
    pub fog_distance: f32,
}

fn default_ambient_intensity() -> f32 { 0.8 }
fn default_fog_distance() -> f32 { 100.0 }

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
        Self { r: 1.0, g: 1.0, b: 1.0, a: 1.0 }
    }
}

fn default_alpha() -> f32 { 1.0 }

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
        Self { x: 0.0, y: 0.0, z: 0.0 }
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
        let translation = self.position.as_ref()
            .map(|p| glam::Vec3::new(p.x, p.y, p.z))
            .unwrap_or(glam::Vec3::ZERO);

        let rotation = self.rotation.as_ref()
            .map(|r| glam::Quat::from_euler(
                glam::EulerRot::XYZ,
                r.x.to_radians(),
                r.y.to_radians(),
                r.z.to_radians(),
            ))
            .unwrap_or(glam::Quat::IDENTITY);

        let scale = self.scale.as_ref()
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
    Sphere { #[serde(default = "default_one")] radius: f32, #[serde(default = "default_subdivisions")] subdivisions: u32 },
    Plane { #[serde(default = "default_one")] size: f32 },
    Capsule { #[serde(default = "default_half")] radius: f32, #[serde(default = "default_one")] depth: f32 },
    Cylinder { #[serde(default = "default_half")] radius: f32, #[serde(default = "default_one")] height: f32 },
    Cone { #[serde(default = "default_half")] radius: f32, #[serde(default = "default_one")] height: f32 },
    Torus { #[serde(default = "default_one")] radius: f32, #[serde(default = "default_quarter")] tube_radius: f32 },
    File { path: String },
}

fn default_subdivisions() -> u32 { 16 }
fn default_half() -> f32 { 0.5 }
fn default_quarter() -> f32 { 0.25 }

// ── Material Types ───────────────────────────────────────────────────

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct MaterialDef {
    #[serde(default)]
    pub base_color: Option<ColorDef>,
    #[serde(default)]
    pub base_color_texture: Option<String>,
    #[serde(default)]
    pub emissive: Option<ColorDef>,
    #[serde(default)]
    pub metallic: Option<f32>,
    #[serde(default)]
    pub roughness: Option<f32>,
    #[serde(default)]
    pub normal_map_texture: Option<String>,
    #[serde(default)]
    pub alpha_mode: Option<AlphaMode>,
    #[serde(default)]
    pub double_sided: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum AlphaMode {
    Opaque,
    Mask,
    Blend,
}

// ── Light Types ──────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum LightType {
    Point,
    Directional,
    Spot,
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
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum AnimationType {
    Rotate { axis: Vec3Def, degrees: f32 },
    Translate { from: Vec3Def, to: Vec3Def },
    Scale { from: Vec3Def, to: Vec3Def },
    Bounce { height: f32 },
    Pulse { min_scale: f32, max_scale: f32 },
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub enum EasingType {
    #[default]
    Linear,
    EaseIn,
    EaseOut,
    EaseInOut,
    Bounce,
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

fn default_friction() -> f32 { 0.3 }
fn default_true() -> bool { true }

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
