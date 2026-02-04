use bevy::prelude::*;
use crate::graphics::plugin::{JsonScene, JsonScenePlugin};

pub fn run_ui_demo() {
    App::new()
        .add_plugins(DefaultPlugins)
        .add_plugins(JsonScenePlugin)
        .add_systems(Startup, setup)
        .add_systems(Update, rotate_objects)
        .run();
}

#[derive(Component)]
struct Rotator {
    speed: Vec3,
}

fn setup(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    asset_server: Res<AssetServer>,
) {
    // Load the JSON scene
    let json_scene = JsonScene::load_from_file("/home/keyhan/elpian/src/examples/3d_example.json")
        .expect("Failed to load 3D scene");

    // Spawn the 3D world from JSON
    let entities = json_scene
        .spawn_world(&mut commands, &mut meshes, &mut materials, &asset_server)
        .expect("Failed to spawn 3D world");

    // Add rotation components to the meshes (entities 3, 4, 5 are the meshes after camera and lights)
    if entities.len() >= 6 {
        // Red cube
        commands.entity(entities[3]).insert(Rotator {
            speed: Vec3::new(0.0, 1.0, 0.3),
        });

        // Blue sphere
        commands.entity(entities[4]).insert(Rotator {
            speed: Vec3::new(0.5, 0.5, 0.0),
        });

        // Green capsule
        commands.entity(entities[5]).insert(Rotator {
            speed: Vec3::new(0.3, 0.0, 0.7),
        });
    }

    println!("3D Demo loaded successfully!");
    println!("The entire scene is defined in examples/3d_example.json");
    println!("Camera, lights, and meshes are all configured via JSON");
}

fn rotate_objects(time: Res<Time>, mut query: Query<(&mut Transform, &Rotator)>) {
    for (mut transform, rotator) in &mut query {
        transform.rotate_local_x(rotator.speed.x * time.delta_secs());
        transform.rotate_local_y(rotator.speed.y * time.delta_secs());
        transform.rotate_local_z(rotator.speed.z * time.delta_secs());
    }
}
