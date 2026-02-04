use crate::graphics::plugin::{JsonScene, JsonScenePlugin};
use bevy::prelude::*;

pub fn run_ui_demo() {
    App::new()
        .add_plugins(DefaultPlugins)
        .add_plugins(JsonScenePlugin)
        .add_systems(Startup, setup)
        .run();
}

fn setup(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    asset_server: Res<AssetServer>,
) {
    // Load the JSON scene
    let json_scene = JsonScene::load_from_file("/home/keyhan/elpian/src/examples/ui_example.json")
        .expect("Failed to load UI scene");

    // Spawn the UI elements from JSON
    json_scene
        .spawn_ui(&mut commands, &asset_server)
        .expect("Failed to spawn UI");

    json_scene
        .spawn_world(&mut commands, &mut meshes, &mut materials, &asset_server)
        .expect("Failed to spawn 3D world");

    println!("UI Demo loaded successfully!");
    println!("The UI is defined entirely in examples/ui_example.json");
}
