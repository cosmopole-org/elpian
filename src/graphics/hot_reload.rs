use bevy::prelude::*;
use notify::{Config, Event, RecommendedWatcher, RecursiveMode, Watcher};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::sync::mpsc::{channel, Receiver};
use std::time::Duration;

#[derive(Resource)]
pub struct HotReloadWatcher {
    pub receiver: Arc<Mutex<Receiver<notify::Result<Event>>>>,
    pub watched_file: PathBuf,
    _watcher: Arc<Mutex<RecommendedWatcher>>, // Keep watcher alive
}

impl HotReloadWatcher {
    pub fn new<P: AsRef<Path>>(path: P) -> Result<Self, notify::Error> {
        let (tx, rx) = channel();
        
        let mut watcher = RecommendedWatcher::new(
            move |res| {
                let _ = tx.send(res);
            },
            Config::default()
                .with_poll_interval(Duration::from_secs(1)),
        )?;

        let path = path.as_ref().to_path_buf();
        watcher.watch(&path, RecursiveMode::NonRecursive)?;

        Ok(Self {
            receiver: Arc::new(Mutex::new(rx)),
            watched_file: path,
            _watcher: Arc::new(Mutex::new(watcher)),
        })
    }
}

#[derive(Event)]
pub struct FileChangedEvent {
    pub path: PathBuf,
}

pub fn hot_reload_system(
    watcher: Option<Res<HotReloadWatcher>>,
    mut events: EventWriter<FileChangedEvent>,
) {
    if let Some(watcher) = watcher {
        // Check for file changes
        if let Ok(receiver) = watcher.receiver.lock() {
            while let Ok(Ok(event)) = receiver.try_recv() {
                match event.kind {
                    notify::EventKind::Modify(_) | notify::EventKind::Create(_) => {
                        info!("Detected file change: {:?}", watcher.watched_file);
                        events.send(FileChangedEvent {
                            path: watcher.watched_file.clone(),
                        });
                    }
                    _ => {}
                }
            }
        }
    }
}

pub fn reload_on_change_system(
    mut commands: Commands,
    mut events: EventReader<FileChangedEvent>,
    asset_server: Res<AssetServer>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    // Query all JSON-spawned entities (you'd need to tag them)
    spawned_entities: Query<Entity, With<JsonSpawned>>,
) {
    for event in events.read() {
        info!("Reloading scene from: {:?}", event.path);
        
        // Despawn all existing JSON entities
        for entity in &spawned_entities {
            commands.entity(entity).despawn_recursive();
        }
        
        // Reload the JSON file
        match crate::graphics::plugin::JsonScene::load_from_file(&event.path) {
            Ok(scene) => {
                // Respawn UI
                if let Err(e) = scene.spawn_ui(&mut commands, &asset_server) {
                    error!("Failed to respawn UI: {}", e);
                }
                
                // Respawn world
                if let Err(e) = scene.spawn_world(&mut commands, &mut meshes, &mut materials, &asset_server) {
                    error!("Failed to respawn world: {}", e);
                }
                
                info!("Scene reloaded successfully!");
            }
            Err(e) => {
                error!("Failed to reload scene: {}", e);
            }
        }
    }
}

// Marker component for entities spawned from JSON
#[derive(Component)]
pub struct JsonSpawned;

// Helper to enable hot reloading
pub fn enable_hot_reload<P: AsRef<Path>>(app: &mut App, path: P) -> Result<(), notify::Error> {
    let watcher = HotReloadWatcher::new(path)?;
    app.insert_resource(watcher);
    app.add_event::<FileChangedEvent>();
    app.add_systems(Update, (hot_reload_system, reload_on_change_system));
    Ok(())
}
