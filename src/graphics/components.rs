use bevy::prelude::*;
use crate::graphics::schema::{AnimationType, EasingType};

// UI Components
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

// Animation Component
#[derive(Component, Clone)]
pub struct Animation {
    pub animation_type: AnimationType,
    pub duration: f32,
    pub looping: bool,
    pub easing: EasingType,
    pub elapsed: f32,
}

// Audio Components
#[derive(Component)]
pub struct AudioComponent {
    pub volume: f32,
    pub looping: bool,
    pub autoplay: bool,
}

#[derive(Component)]
pub struct SpatialAudioComponent;

// Particle System Component
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

// Event marker components
#[derive(Component)]
pub struct EventId(pub String);
