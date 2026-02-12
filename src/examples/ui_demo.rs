use bevy::prelude::*;
use crate::graphics::plugin::{JsonScene, JsonScenePlugin};

pub fn run_demo() {
    run_scene_from_file("src/examples/material_and_3d.json");
}

pub fn run_scene_from_file<P: AsRef<std::path::Path>>(path: P) {
    let path = path.as_ref().to_path_buf();
    App::new()
        .add_plugins(DefaultPlugins)
        .add_plugins(JsonScenePlugin)
        .add_systems(Startup, move |mut commands: Commands, mut meshes: ResMut<Assets<Mesh>>, mut materials: ResMut<Assets<StandardMaterial>>, asset_server: Res<AssetServer>| {
            let json_scene = match JsonScene::load_from_file(path.clone()) {
                Ok(s) => s,
                Err(e) => {
                    eprintln!("Failed to load scene: {}", e);
                    return;
                }
            };

            if let Err(e) = json_scene.spawn_ui(&mut commands, &asset_server) {
                eprintln!("Failed to spawn UI: {}", e);
            }

            if let Err(e) = json_scene.spawn_world(&mut commands, &mut meshes, &mut materials, &asset_server) {
                eprintln!("Failed to spawn world: {}", e);
            }

            println!("Scene loaded from {}", path.display());
        })
        .run();
}
