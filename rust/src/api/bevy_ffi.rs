/// FFI layer for the Bevy 3D scene renderer.
///
/// Exposes C-compatible functions for creating, rendering, and managing
/// 3D scenes from Flutter via dart:ffi. Frame pixel data is returned
/// as a pointer to RGBA8 bytes that Flutter reads into a dart:ui Image.
///
/// Memory: Strings returned by Rust must be freed with `elpian_free_string`.
/// Pixel buffers are owned by the scene and valid until the next render call.
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;

use serde_json::json;

use crate::bevy_scene::manager;

/// Helper: convert C string pointer to Rust String.
unsafe fn c_str_to_string(ptr: *const c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    CStr::from_ptr(ptr).to_string_lossy().into_owned()
}

/// Helper: convert Rust String to C string pointer.
fn string_to_c_str(s: String) -> *mut c_char {
    CString::new(s).unwrap_or_default().into_raw()
}

// ── Scene Lifecycle ──────────────────────────────────────────────────

/// Initialize the Bevy scene subsystem. Call once at app startup.
#[unsafe(no_mangle)]
pub extern "C" fn elpian_bevy_init() {
    manager::init_scene_system();
}

/// Create a new 3D scene from JSON. Returns 1 on success, 0 on failure.
///
/// The JSON should match the SceneDef format:
/// ```json
/// {
///   "world": [
///     { "type": "mesh3d", "mesh": "Cube", "material": {...}, "transform": {...} },
///     { "type": "light", "light_type": "Directional", ... },
///     { "type": "camera", "camera_type": "Perspective", ... }
///   ]
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn elpian_bevy_create_scene(
    scene_id: *const c_char,
    json: *const c_char,
    width: u32,
    height: u32,
) -> i32 {
    let sid = unsafe { c_str_to_string(scene_id) };
    let j = unsafe { c_str_to_string(json) };
    if manager::create_scene(sid, j, width, height) {
        1
    } else {
        0
    }
}

/// Update an existing scene with new JSON data. Returns 1 on success.
#[unsafe(no_mangle)]
pub extern "C" fn elpian_bevy_update_scene(scene_id: *const c_char, json: *const c_char) -> i32 {
    let sid = unsafe { c_str_to_string(scene_id) };
    let j = unsafe { c_str_to_string(json) };
    if manager::update_scene(sid, j) {
        1
    } else {
        0
    }
}

/// Render one frame. delta_time is seconds since last frame.
/// Returns 1 on success, 0 if scene not found.
#[unsafe(no_mangle)]
pub extern "C" fn elpian_bevy_render_frame(scene_id: *const c_char, delta_time: f32) -> i32 {
    let sid = unsafe { c_str_to_string(scene_id) };
    if manager::render_frame(&sid, delta_time) {
        1
    } else {
        0
    }
}

/// Resize the scene's render target. Returns 1 on success.
#[unsafe(no_mangle)]
pub extern "C" fn elpian_bevy_resize_scene(
    scene_id: *const c_char,
    width: u32,
    height: u32,
) -> i32 {
    let sid = unsafe { c_str_to_string(scene_id) };
    if manager::resize_scene(&sid, width, height) {
        1
    } else {
        0
    }
}

/// Get a pointer to the scene's rendered pixel buffer (RGBA8).
///
/// Returns null if the scene doesn't exist or hasn't been rendered yet.
/// The pointer is valid until the next render_frame or destroy call.
/// The buffer size is width * height * 4 bytes.
#[unsafe(no_mangle)]
pub extern "C" fn elpian_bevy_get_frame_ptr(scene_id: *const c_char) -> *const u8 {
    let sid = unsafe { c_str_to_string(scene_id) };
    match manager::get_frame_data(&sid) {
        Some((ptr, _)) => ptr,
        None => ptr::null(),
    }
}

/// Get the rendered frame as a JSON string containing base64-encoded RGBA data.
///
/// This is used for web/WASM where direct pointer access isn't available.
/// Returns a JSON string: {"width": N, "height": N, "data": "<base64>", "frameCount": N}
/// Caller must free the returned string with elpian_free_string.
///
/// Uses an atomic snapshot to avoid inconsistent data from separate lock/unlock cycles.
#[unsafe(no_mangle)]
pub extern "C" fn elpian_bevy_get_frame_json(scene_id: *const c_char) -> *mut c_char {
    let sid = unsafe { c_str_to_string(scene_id) };

    let (width, height, pixels, frame_count) = match manager::get_frame_snapshot(&sid) {
        Some(snapshot) => snapshot,
        None => return string_to_c_str("{}".to_string()),
    };

    // Base64 encode for safe transport across FFI
    let encoded = base64_encode(&pixels);

    let result = json!({
        "width": width,
        "height": height,
        "data": encoded,
        "frameCount": frame_count,
    });

    string_to_c_str(result.to_string())
}

/// Get the size of the rendered frame buffer in bytes.
#[unsafe(no_mangle)]
pub extern "C" fn elpian_bevy_get_frame_size(scene_id: *const c_char) -> u32 {
    let sid = unsafe { c_str_to_string(scene_id) };
    match manager::get_frame_data(&sid) {
        Some((_, len)) => len as u32,
        None => 0,
    }
}

/// Get the scene dimensions as a packed u64: (width << 32) | height.
#[unsafe(no_mangle)]
pub extern "C" fn elpian_bevy_get_scene_dimensions(scene_id: *const c_char) -> u64 {
    let sid = unsafe { c_str_to_string(scene_id) };
    match manager::get_scene_dimensions(&sid) {
        Some((w, h)) => ((w as u64) << 32) | (h as u64),
        None => 0,
    }
}

/// Send an input event to the scene. Returns 1 on success.
///
/// The input JSON should match:
/// ```json
/// {"event_type": "TouchDown", "x": 100.0, "y": 200.0}
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn elpian_bevy_send_input(
    scene_id: *const c_char,
    input_json: *const c_char,
) -> i32 {
    let sid = unsafe { c_str_to_string(scene_id) };
    let input = unsafe { c_str_to_string(input_json) };
    if manager::send_input(&sid, &input) {
        1
    } else {
        0
    }
}

/// Destroy a scene and free its resources. Returns 1 if found.
#[unsafe(no_mangle)]
pub extern "C" fn elpian_bevy_destroy_scene(scene_id: *const c_char) -> i32 {
    let sid = unsafe { c_str_to_string(scene_id) };
    if manager::destroy_scene(&sid) {
        1
    } else {
        0
    }
}

/// Check if a scene exists. Returns 1 if it does.
#[unsafe(no_mangle)]
pub extern "C" fn elpian_bevy_scene_exists(scene_id: *const c_char) -> i32 {
    let sid = unsafe { c_str_to_string(scene_id) };
    if manager::scene_exists(&sid) {
        1
    } else {
        0
    }
}

/// Get the elapsed time for a scene in seconds.
#[unsafe(no_mangle)]
pub extern "C" fn elpian_bevy_get_elapsed_time(scene_id: *const c_char) -> f32 {
    let sid = unsafe { c_str_to_string(scene_id) };
    manager::get_elapsed_time(&sid)
}

/// Get the frame count for a scene.
#[unsafe(no_mangle)]
pub extern "C" fn elpian_bevy_get_frame_count(scene_id: *const c_char) -> u64 {
    let sid = unsafe { c_str_to_string(scene_id) };
    manager::get_frame_count(&sid)
}

// ── Base64 Encoder ───────────────────────────────────────────────────

const BASE64_CHARS: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

fn base64_encode(data: &[u8]) -> String {
    let mut result = String::with_capacity((data.len() + 2) / 3 * 4);
    let chunks = data.chunks(3);

    for chunk in chunks {
        let b0 = chunk[0] as u32;
        let b1 = if chunk.len() > 1 { chunk[1] as u32 } else { 0 };
        let b2 = if chunk.len() > 2 { chunk[2] as u32 } else { 0 };

        let triple = (b0 << 16) | (b1 << 8) | b2;

        result.push(BASE64_CHARS[((triple >> 18) & 0x3F) as usize] as char);
        result.push(BASE64_CHARS[((triple >> 12) & 0x3F) as usize] as char);

        if chunk.len() > 1 {
            result.push(BASE64_CHARS[((triple >> 6) & 0x3F) as usize] as char);
        } else {
            result.push('=');
        }

        if chunk.len() > 2 {
            result.push(BASE64_CHARS[(triple & 0x3F) as usize] as char);
        } else {
            result.push('=');
        }
    }

    result
}
