
use bevy::prelude::*;
use crate::graphics::plugin::{JsonScene, JsonScenePlugin};

pub fn run_demo() {
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
    let json_scene = JsonScene::load_from_file("examples/animations.json")
        .expect("Failed to load animations scene");

    // Spawn the 3D world from JSON
    json_scene
        .spawn_world(&mut commands, &mut meshes, &mut materials, &asset_server)
        .expect("Failed to spawn 3D world");

    println!("Animation & Particles Demo loaded successfully!");
    println!("Watch the:");
    println!("  - Red cube rotating");
    println!("  - Blue sphere bouncing");
    println!("  - Green capsule pulsing");
    println!("  - Blue particle fountain on the left");
    println!("  - Orange fire particles on the right");
    println!("All animations and particles defined in examples/animations.json");
}
