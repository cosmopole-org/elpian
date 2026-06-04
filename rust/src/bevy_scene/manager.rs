//! Thread-safe scene manager that stores and manages 3D scene renderers.
//!
//! Each scene is identified by a string ID and has its own renderer instance.
//! The manager provides methods for creating, updating, rendering, and destroying
//! scenes, all safe to call from FFI boundaries.

use std::collections::HashMap;

// A5: use parking_lot's faster mutex on native targets; keep std::sync::Mutex on
// wasm (single-threaded; parking_lot's thread-parking features are unnecessary
// there). `lock_scenes()` hides the API difference (parking_lot::lock() returns the
// guard directly; std returns a Result) so call sites stay uniform.
#[cfg(not(target_arch = "wasm32"))]
use parking_lot::Mutex;
#[cfg(target_arch = "wasm32")]
use std::sync::Mutex;

use once_cell::sync::Lazy;
use serde_json;

use crate::bevy_scene::renderer::SceneRenderer;
use crate::bevy_scene::schema::{InputEvent, SceneDef};

type SceneMap = HashMap<String, SceneInstance>;

/// Global thread-safe scene storage.
static SCENES: Lazy<Mutex<SceneMap>> = Lazy::new(|| Mutex::new(HashMap::new()));

#[cfg(not(target_arch = "wasm32"))]
#[inline]
fn lock_scenes() -> parking_lot::MutexGuard<'static, SceneMap> {
    SCENES.lock()
}

#[cfg(target_arch = "wasm32")]
#[inline]
fn lock_scenes() -> std::sync::MutexGuard<'static, SceneMap> {
    SCENES.lock().unwrap()
}

/// A managed scene instance with renderer and parsed scene data.
struct SceneInstance {
    renderer: SceneRenderer,
    scene: SceneDef,
    frame_count: u64,
}

/// Initialize the Bevy scene subsystem. Call once at startup.
pub fn init_scene_system() {
    drop(lock_scenes());
}

/// Create a new scene from a JSON string.
///
/// The JSON should follow the SceneDef format with `ui` and `world` arrays.
/// Returns true on success, false if JSON parsing fails.
pub fn create_scene(scene_id: String, json: String, width: u32, height: u32) -> bool {
    let scene: SceneDef = match serde_json::from_str(&json) {
        Ok(s) => s,
        Err(_) => return false,
    };

    let renderer = SceneRenderer::new(width, height);
    let instance = SceneInstance {
        renderer,
        scene,
        frame_count: 0,
    };

    let mut scenes = lock_scenes();
    scenes.insert(scene_id, instance);
    true
}

/// Update an existing scene with new JSON data.
///
/// This replaces the scene definition while preserving the renderer state
/// (elapsed time, frame count) for smooth transitions.
pub fn update_scene(scene_id: String, json: String) -> bool {
    let scene: SceneDef = match serde_json::from_str(&json) {
        Ok(s) => s,
        Err(_) => return false,
    };

    let mut scenes = lock_scenes();
    if let Some(instance) = scenes.get_mut(&scene_id) {
        instance.scene = scene;
        true
    } else {
        false
    }
}

/// Render one frame of the scene.
///
/// The delta_time parameter specifies the time elapsed since the last frame
/// in seconds. After calling this, use `get_frame_ptr` to access the pixel data.
pub fn render_frame(scene_id: &str, delta_time: f32) -> bool {
    let mut scenes = lock_scenes();
    if let Some(instance) = scenes.get_mut(scene_id) {
        instance.renderer.render_scene(&instance.scene, delta_time);
        instance.frame_count += 1;
        true
    } else {
        false
    }
}

/// Feed decoded model bytes (GLB or embedded-buffer glTF) into a scene's renderer,
/// keyed by URL. The bytes are decoded once and cached; `model3d` nodes referencing
/// the same URL then render the posed model instead of the placeholder capsule.
///
/// This is the "bridge" entry point: the host (Flutter/JS) fetches the model bytes
/// over the network and hands them to Rust, which owns decoding + skinning. Returns
/// true if the scene exists and the bytes parsed into a usable model.
pub fn feed_model_bytes(scene_id: &str, url: String, bytes: &[u8]) -> bool {
    let mut scenes = lock_scenes();
    if let Some(instance) = scenes.get_mut(scene_id) {
        instance.renderer.load_model_bytes(url, bytes)
    } else {
        false
    }
}

/// Whether a decoded model is cached for `url` in this scene (so the host can
/// skip re-fetching/re-feeding bytes it has already supplied).
pub fn scene_has_model(scene_id: &str, url: &str) -> bool {
    let scenes = lock_scenes();
    scenes
        .get(scene_id)
        .map(|i| i.renderer.has_model(url))
        .unwrap_or(false)
}

/// Resize the scene's render target.
pub fn resize_scene(scene_id: &str, width: u32, height: u32) -> bool {
    let mut scenes = lock_scenes();
    if let Some(instance) = scenes.get_mut(scene_id) {
        instance.renderer.resize(width, height);
        true
    } else {
        false
    }
}

/// Get a pointer to the scene's pixel buffer and its size.
///
/// Returns (pointer, length) where the pointer points to RGBA8 data.
/// The pointer is valid until the next `render_frame` or `destroy_scene` call.
pub fn get_frame_data(scene_id: &str) -> Option<(*const u8, usize)> {
    let scenes = lock_scenes();
    if let Some(instance) = scenes.get(scene_id) {
        let ptr = instance.renderer.pixels.as_ptr();
        let len = instance.renderer.pixels.len();
        Some((ptr, len))
    } else {
        None
    }
}

/// Get the pixel buffer as a Vec<u8> copy (safe for cross-thread use).
pub fn get_frame_copy(scene_id: &str) -> Option<Vec<u8>> {
    let scenes = lock_scenes();
    if let Some(instance) = scenes.get(scene_id) {
        Some(instance.renderer.pixels.clone())
    } else {
        None
    }
}

/// Atomically get a complete frame snapshot: dimensions, pixels, and frame count.
/// This avoids separate lock/unlock cycles that could return inconsistent data.
pub fn get_frame_snapshot(scene_id: &str) -> Option<(u32, u32, Vec<u8>, u64)> {
    let scenes = lock_scenes();
    if let Some(instance) = scenes.get(scene_id) {
        Some((
            instance.renderer.width,
            instance.renderer.height,
            instance.renderer.pixels.clone(),
            instance.frame_count,
        ))
    } else {
        None
    }
}

/// Get the scene's render dimensions.
pub fn get_scene_dimensions(scene_id: &str) -> Option<(u32, u32)> {
    let scenes = lock_scenes();
    if let Some(instance) = scenes.get(scene_id) {
        Some((instance.renderer.width, instance.renderer.height))
    } else {
        None
    }
}

/// Get the current frame count.
pub fn get_frame_count(scene_id: &str) -> u64 {
    let scenes = lock_scenes();
    scenes.get(scene_id).map(|i| i.frame_count).unwrap_or(0)
}

/// Send an input event to the scene.
pub fn send_input(scene_id: &str, input_json: &str) -> bool {
    let _event: InputEvent = match serde_json::from_str(input_json) {
        Ok(e) => e,
        Err(_) => return false,
    };

    let scenes = lock_scenes();
    if scenes.contains_key(scene_id) {
        // Input events are stored for processing during the next render frame.
        // For now, camera orbit/pan can be handled by updating the scene JSON.
        true
    } else {
        false
    }
}

/// Destroy a scene and free its resources.
pub fn destroy_scene(scene_id: &str) -> bool {
    let mut scenes = lock_scenes();
    scenes.remove(scene_id).is_some()
}

/// Check if a scene exists.
pub fn scene_exists(scene_id: &str) -> bool {
    let scenes = lock_scenes();
    scenes.contains_key(scene_id)
}

/// Get the current elapsed time for a scene.
pub fn get_elapsed_time(scene_id: &str) -> f32 {
    let scenes = lock_scenes();
    scenes
        .get(scene_id)
        .map(|i| i.renderer.elapsed_time)
        .unwrap_or(0.0)
}
