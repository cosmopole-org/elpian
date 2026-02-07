use bevy::prelude::*;
use crate::graphics::schema::{AnimationType, EasingType};

// ===== BASIC UI COMPONENTS =====
#[derive(Component)]
pub struct Slider {
    pub min: f32,
    pub max: f32,
    pub value: f32,
    pub on_change: Option<String>,
}

#[derive(Component)]
pub struct SliderHandle;

#[derive(Component)]
pub struct Checkbox {
    pub checked: bool,
    pub on_change: Option<String>,
}

#[derive(Component)]
pub struct RadioButton {
    pub group: String,
    pub checked: bool,
    pub on_change: Option<String>,
}

#[derive(Component)]
pub struct TextInputComponent {
    pub value: String,
    pub placeholder: String,
    pub on_change: Option<String>,
    pub focused: bool,
}

#[derive(Component)]
pub struct ProgressBarComponent {
    pub value: f32,
    pub max: f32,
}

#[derive(Component)]
pub struct ProgressBarFill;

// ===== MATERIAL DESIGN UI COMPONENTS =====

#[derive(Component)]
pub struct FloatingActionButton {
    pub action: Option<String>,
    pub fab_type: String,
    pub hovered: bool,
}

#[derive(Component)]
pub struct Card {
    pub elevation: u32,
    pub corner_radius: f32,
    pub on_click: Option<String>,
    pub outlined: bool,
}

#[derive(Component)]
pub struct Chip {
    pub chip_type: String,
    pub selected: bool,
    pub on_click: Option<String>,
}

#[derive(Component)]
pub struct AppBar {
    pub app_bar_type: String,
    pub title: String,
    pub elevation: u32,
}

#[derive(Component)]
pub struct Dialog {
    pub title: String,
    pub dismissible: bool,
    pub open: bool,
}

#[derive(Component)]
pub struct Menu {
    pub elevation: u32,
    pub open: bool,
}

#[derive(Component)]
pub struct BottomSheet {
    pub height: Option<f32>,
    pub dismissible: bool,
    pub open: bool,
}

#[derive(Component)]
pub struct Snackbar {
    pub message: String,
    pub duration_ms: u32,
    pub elapsed_ms: u32,
}

#[derive(Component)]
pub struct SwitchComponent {
    pub enabled: bool,
    pub on_change: Option<String>,
}

#[derive(Component)]
pub struct Tabs {
    pub selected_index: usize,
    pub tab_count: usize,
    pub on_change: Option<String>,
}

#[derive(Component)]
pub struct TabContent {
    pub tab_index: usize,
    pub visible: bool,
}

#[derive(Component)]
pub struct Badge {
    pub count: Option<u32>,
    pub label: String,
}

#[derive(Component)]
pub struct Tooltip {
    pub message: String,
    pub visible: bool,
    pub position: String,
}

#[derive(Component)]
pub struct Rating {
    pub value: f32,
    pub max: u32,
    pub on_change: Option<String>,
    pub read_only: bool,
}

#[derive(Component)]
pub struct SegmentedButton {
    pub selected_index: usize,
    pub option_count: usize,
    pub multiple_selection: bool,
    pub on_change: Option<String>,
}

#[derive(Component)]
pub struct IconButton {
    pub icon: String,
    pub action: Option<String>,
    pub hovered: bool,
}

#[derive(Component)]
pub struct Divider {
    pub thickness: f32,
    pub color: Color,
}

#[derive(Component)]
pub struct ListComponent {
    pub item_count: usize,
}

#[derive(Component)]
pub struct Drawer {
    pub open: bool,
    pub width: f32,
}

// ===== MATERIAL DESIGN EFFECTS =====

#[derive(Component)]
pub struct RippleEffect {
    pub origin: Vec2,
    pub radius: f32,
    pub max_radius: f32,
    pub duration: f32,
    pub elapsed: f32,
}

#[derive(Component)]
pub struct Elevation {
    pub level: u32,
    pub shadow_blur: f32,
    pub shadow_offset: Vec2,
}

// ===== ANIMATION COMPONENT =====
#[derive(Component, Clone)]
pub struct Animation {
    pub animation_type: AnimationType,
    pub duration: f32,
    pub looping: bool,
    pub easing: EasingType,
    pub elapsed: f32,
}

// ===== AUDIO COMPONENTS =====
#[derive(Component)]
pub struct AudioComponent {
    pub volume: f32,
    pub looping: bool,
    pub autoplay: bool,
}

#[derive(Component)]
pub struct SpatialAudioComponent;

// ===== PARTICLE SYSTEM COMPONENTS =====
#[derive(Component)]
pub struct ParticleEmitter {
    pub emission_rate: f32,
    pub lifetime: f32,
    pub color: Color,
    pub size: f32,
    pub velocity: Vec3,
    pub gravity: Vec3,
    pub timer: f32,
}

#[derive(Component)]
pub struct Particle {
    pub lifetime: f32,
    pub age: f32,
    pub velocity: Vec3,
}

// ===== 3D GAME COMPONENTS =====

#[derive(Component)]
pub struct Terrain {
    pub size: f32,
    pub height: f32,
    pub subdivisions: u32,
}

#[derive(Component)]
pub struct SkyboxComponent {
    pub rotation: Quat,
    pub brightness: f32,
}

#[derive(Component)]
pub struct Foliage {
    pub foliage_type: String,
    pub density: f32,
    pub color_variation: f32,
}

#[derive(Component)]
pub struct Decal {
    pub size: Vec3,
    pub sort_order: i32,
}


#[derive(Component)]
pub struct RoundedBackground {
    pub color: Color,
    // numeric RGBA components cached for runtime image generation (r,g,b,a in 0.0..1.0)
    pub color_rgba: [f32; 4],
    pub corner_radius: f32,
    pub elevation: u32,
    pub glass: bool,
    pub glass_opacity: f32,
}

#[derive(Component)]
pub struct GlassOverlay;


#[derive(Component)]
pub struct Billboard {
    pub billboard_type: String,
    pub size: Vec3,
}

#[derive(Component)]
pub struct Water {
    pub wave_amplitude: f32,
    pub wave_frequency: f32,
    pub wave_speed: f32,
    pub elapsed_time: f32,
}

#[derive(Component)]
pub struct RigidBodyComponent {
    pub mass: f32,
    pub velocity: Vec3,
    pub angular_velocity: Vec3,
}

#[derive(Component)]
pub struct Physics {
    pub mass: f32,
    pub friction: f32,
    pub restitution: f32,
    pub gravity_scale: f32,
    pub use_gravity: bool,
    pub collider_type: String,
}

#[derive(Component)]
pub struct Environment {
    pub ambient_light_intensity: f32,
    pub fog_enabled: bool,
    pub fog_distance: f32,
}

// ===== EVENT MARKER COMPONENTS =====
#[derive(Component)]
pub struct EventId(pub String);

