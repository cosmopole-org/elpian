use bevy::prelude::*;
use crate::graphics::components::*;
use crate::graphics::schema::{AnimationType, EasingType};

// Animation system
pub fn animation_system(
    time: Res<Time>,
    mut query: Query<(&mut Transform, &mut Animation)>,
) {
    for (mut transform, mut animation) in &mut query {
        animation.elapsed += time.delta_secs();
        
        let progress = if animation.duration > 0.0 {
            (animation.elapsed / animation.duration).min(1.0)
        } else {
            1.0
        };

        // Apply easing
        let eased_progress = apply_easing(progress, &animation.easing);

        // Apply animation
        match &animation.animation_type {
            AnimationType::Rotate { axis, degrees } => {
                let angle = degrees.to_radians() * eased_progress;
                let axis_vec = Vec3::new(axis.x, axis.y, axis.z).normalize();
                transform.rotation = Quat::from_axis_angle(axis_vec, angle);
            }
            AnimationType::Translate { from, to } => {
                let from_vec = Vec3::new(from.x, from.y, from.z);
                let to_vec = Vec3::new(to.x, to.y, to.z);
                transform.translation = from_vec.lerp(to_vec, eased_progress);
            }
            AnimationType::Scale { from, to } => {
                let from_vec = Vec3::new(from.x, from.y, from.z);
                let to_vec = Vec3::new(to.x, to.y, to.z);
                transform.scale = from_vec.lerp(to_vec, eased_progress);
            }
            AnimationType::Bounce { height } => {
                let y = (eased_progress * std::f32::consts::PI).sin() * height;
                transform.translation.y = y;
            }
            AnimationType::Pulse { min_scale, max_scale } => {
                let scale = min_scale + (max_scale - min_scale) * 
                    (0.5 + 0.5 * (eased_progress * std::f32::consts::TAU).sin());
                transform.scale = Vec3::splat(scale);
            }
        }

        // Loop or stop
        if animation.elapsed >= animation.duration {
            if animation.looping {
                animation.elapsed = 0.0;
            }
        }
    }
}

fn apply_easing(progress: f32, easing: &EasingType) -> f32 {
    match easing {
        EasingType::Linear => progress,
        EasingType::EaseIn => progress * progress,
        EasingType::EaseOut => progress * (2.0 - progress),
        EasingType::EaseInOut => {
            if progress < 0.5 {
                2.0 * progress * progress
            } else {
                -1.0 + (4.0 - 2.0 * progress) * progress
            }
        }
        EasingType::Bounce => {
            let n1 = 7.5625;
            let d1 = 2.75;
            
            if progress < 1.0 / d1 {
                n1 * progress * progress
            } else if progress < 2.0 / d1 {
                let p = progress - 1.5 / d1;
                n1 * p * p + 0.75
            } else if progress < 2.5 / d1 {
                let p = progress - 2.25 / d1;
                n1 * p * p + 0.9375
            } else {
                let p = progress - 2.625 / d1;
                n1 * p * p + 0.984375
            }
        }
    }
}

// Particle system
pub fn particle_emission_system(
    mut commands: Commands,
    time: Res<Time>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    mut query: Query<(&Transform, &mut ParticleEmitter)>,
) {
    for (transform, mut emitter) in &mut query {
        emitter.timer += time.delta_secs();
        
        let emission_interval = 1.0 / emitter.emission_rate;
        
        while emitter.timer >= emission_interval {
            emitter.timer -= emission_interval;
            
            // Spawn particle
            let mesh = meshes.add(Sphere::new(emitter.size));
            let material = materials.add(StandardMaterial {
                base_color: emitter.color,
                emissive: emitter.color.into(),
                ..default()
            });
            
            commands.spawn((
                Mesh3d(mesh),
                MeshMaterial3d(material),
                Transform::from_translation(transform.translation),
                Particle {
                    lifetime: emitter.lifetime,
                    age: 0.0,
                    velocity: emitter.velocity,
                },
            ));
        }
    }
}

pub fn particle_update_system(
    mut commands: Commands,
    time: Res<Time>,
    mut query: Query<(Entity, &mut Transform, &mut Particle, &ParticleEmitter)>,
    emitter_query: Query<&ParticleEmitter>,
) {
    for (entity, mut transform, mut particle, _) in &mut query {
        particle.age += time.delta_secs();
        
        // Get gravity from nearest emitter (for simplicity, using first emitter)
        let gravity = emitter_query.iter().next()
            .map(|e| e.gravity)
            .unwrap_or(Vec3::new(0.0, -9.8, 0.0));
        
        // Update velocity with gravity
        particle.velocity += gravity * time.delta_secs();
        
        // Update position
        transform.translation += particle.velocity * time.delta_secs();
        
        // Remove if expired
        if particle.age >= particle.lifetime {
            commands.entity(entity).despawn();
        }
    }
}

// Checkbox interaction system
pub fn checkbox_interaction_system(
    mut interaction_query: Query<
        (&Interaction, &mut BackgroundColor, &mut Checkbox),
        (Changed<Interaction>, With<Button>),
    >,
    mut events: EventWriter<ComponentEvent>,
) {
    for (interaction, mut color, mut checkbox) in &mut interaction_query {
        if *interaction == Interaction::Pressed {
            checkbox.checked = !checkbox.checked;
            
            *color = if checkbox.checked {
                BackgroundColor(Color::srgb(0.2, 0.8, 0.2))
            } else {
                BackgroundColor(Color::srgb(0.3, 0.3, 0.3))
            };
            
            if let Some(event_id) = &checkbox.on_change {
                events.send(ComponentEvent {
                    event_type: "checkbox_change".to_string(),
                    event_id: event_id.clone(),
                    data: checkbox.checked.to_string(),
                });
            }
        }
    }
}

// Radio button interaction system
pub fn radio_button_interaction_system(
    mut interaction_query: Query<
        (&Interaction, &mut BackgroundColor, &mut RadioButton),
        (Changed<Interaction>, With<Button>),
    >,
    mut all_radios: Query<(&mut BackgroundColor, &mut RadioButton), Without<Interaction>>,
    mut events: EventWriter<ComponentEvent>,
) {
    for (interaction, mut color, mut radio) in &mut interaction_query {
        if *interaction == Interaction::Pressed && !radio.checked {
            // Uncheck all radios in the same group
            for (mut other_color, mut other_radio) in &mut all_radios {
                if other_radio.group == radio.group && other_radio.checked {
                    other_radio.checked = false;
                    *other_color = BackgroundColor(Color::srgb(0.3, 0.3, 0.3));
                }
            }
            
            // Check this radio
            radio.checked = true;
            *color = BackgroundColor(Color::srgb(0.2, 0.6, 0.9));
            
            if let Some(event_id) = &radio.on_change {
                events.send(ComponentEvent {
                    event_type: "radio_change".to_string(),
                    event_id: event_id.clone(),
                    data: "selected".to_string(),
                });
            }
        }
    }
}

// Progress bar update system
pub fn progress_bar_update_system(
    mut query: Query<(&ProgressBarComponent, &Children), Changed<ProgressBarComponent>>,
    mut fill_query: Query<&mut Node, With<ProgressBarFill>>,
) {
    for (progress, children) in &mut query {
        for child in children.iter() {
            if let Ok(mut style) = fill_query.get_mut(*child) {
                style.width = Val::Percent((progress.value / progress.max) * 100.0);
            }
        }
    }
}

// Custom event type
#[derive(Event)]
pub struct ComponentEvent {
    pub event_type: String,
    pub event_id: String,
    pub data: String,
}

// Event logging system (for debugging)
pub fn event_logging_system(mut events: EventReader<ComponentEvent>) {
    for event in events.read() {
        info!(
            "Component Event - Type: {}, ID: {}, Data: {}",
            event.event_type, event.event_id, event.data
        );
    }
}
