#![allow(dead_code)]

use bevy::prelude::*;
use crate::graphics::plugin::{JsonScene, JsonScenePlugin};

fn main() {
    App::new()
        .add_plugins(DefaultPlugins)
        .add_plugins(JsonScenePlugin)
        .add_systems(Startup, setup)
        .run();
}

fn setup(mut commands: Commands, asset_server: Res<AssetServer>) {
    // Load the JSON scene
    let json_scene = JsonScene::load_from_file("examples/advanced_ui.json")
        .expect("Failed to load UI scene");

    // Spawn the UI elements from JSON
    json_scene
        .spawn_ui(&mut commands, &asset_server)
        .expect("Failed to spawn UI");

    println!("Advanced UI Demo loaded successfully!");
    println!("Showcasing: Sliders, Checkboxes, Radio Buttons, Progress Bars, Text Inputs");
    println!("All components defined in examples/advanced_ui.json");
}
