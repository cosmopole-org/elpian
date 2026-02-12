use crate::graphics::{converter::JsonToBevy, schema::*, validation::JsonValidator, systems::*};
use crate::graphics::gpu_blur::*;
use bevy::prelude::*;
use std::path::Path;

pub struct JsonScenePlugin;

impl Plugin for JsonScenePlugin {
    fn build(&self, app: &mut App) {
        app.add_event::<ComponentEvent>()
            .add_systems(
                Startup,
                (
                    generate_circle_mask_system,
                    load_glass_shader_system,
                    spawn_captured_scene_camera_system,
                    prepare_gpu_blur_system,
                ),
            )
            .add_systems(
                Update,
                (
                    button_interaction_system,
                    checkbox_interaction_system,
                    radio_button_interaction_system,
                    icon_button_interaction_system,
                    button_ripple_spawn_system,
                    ripple_update_system,
                    drawer_system,
                    // apply rounded-image backgrounds and shadows at runtime
                    // apply rounded-image backgrounds and shadows at runtime
                    apply_ui_images_system,
                    blur_captured_overlays_system,
                    dispatch_gpu_blur_system,
                    progress_bar_update_system,
                    animation_system,
                    particle_emission_system,
                    particle_update_system,
                    event_logging_system,
                ),
            );
    }
}

#[derive(Resource)]
pub struct JsonScene {
    pub scene: SceneDef,
}

impl JsonScene {
    pub fn load_from_file<P: AsRef<Path>>(path: P) -> anyhow::Result<Self> {
        let contents = std::fs::read_to_string(path)?;
        let scene: SceneDef = serde_json::from_str(&contents)?;
        
        // Validate the scene
        JsonValidator::validate_scene(&scene)?;
        
        Ok(Self { scene })
    }

    pub fn load_from_str(json: &str) -> anyhow::Result<Self> {
        let scene: SceneDef = serde_json::from_str(json)?;
        
        // Validate the scene
        JsonValidator::validate_scene(&scene)?;
        
        Ok(Self { scene })
    }

    pub fn spawn_ui(&self, commands: &mut Commands, asset_server: &AssetServer) -> anyhow::Result<Vec<Entity>> {
        let mut entities = Vec::new();
        for node in &self.scene.ui {
            let entity = JsonToBevy::spawn_ui(commands, asset_server, node, None)?;
            entities.push(entity);
        }
        Ok(entities)
    }

    pub fn spawn_world(
        &self,
        commands: &mut Commands,
        meshes: &mut ResMut<Assets<Mesh>>,
        materials: &mut ResMut<Assets<StandardMaterial>>,
        asset_server: &AssetServer,
    ) -> anyhow::Result<Vec<Entity>> {
        let mut entities = Vec::new();
        for node in &self.scene.world {
            let entity = JsonToBevy::spawn_world(commands, meshes, materials, asset_server, node)?;
            entities.push(entity);
        }
        Ok(entities)
    }
}

// Button interaction system
fn button_interaction_system(
    mut interaction_query: Query<
        (&Interaction, &mut BackgroundColor),
        (Changed<Interaction>, With<Button>, Without<crate::graphics::components::Checkbox>, Without<crate::graphics::components::RadioButton>),
    >,
) {
    for (interaction, mut color) in &mut interaction_query {
        match *interaction {
            Interaction::Pressed => {
                *color = BackgroundColor(Color::srgb(0.35, 0.35, 0.35));
            }
            Interaction::Hovered => {
                *color = BackgroundColor(Color::srgb(0.25, 0.25, 0.25));
            }
            Interaction::None => {
                *color = BackgroundColor(Color::srgb(0.15, 0.15, 0.15));
            }
        }
    }
}
