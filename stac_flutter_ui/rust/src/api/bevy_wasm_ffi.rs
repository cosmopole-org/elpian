/// WASM FFI layer for the Bevy 3D scene renderer on web platforms.
///
/// Uses wasm-bindgen to expose scene management functions to
/// JavaScript/Dart on the web platform.
#[cfg(target_arch = "wasm32")]
mod wasm {
    use wasm_bindgen::prelude::*;
    use serde_json::json;

    use crate::bevy_scene::manager;

    #[wasm_bindgen]
    pub fn elpian_bevy_wasm_init() {
        manager::init_scene_system();
    }

    #[wasm_bindgen]
    pub fn elpian_bevy_wasm_create_scene(
        scene_id: String,
        json: String,
        width: u32,
        height: u32,
    ) -> bool {
        manager::create_scene(scene_id, json, width, height)
    }

    #[wasm_bindgen]
    pub fn elpian_bevy_wasm_update_scene(scene_id: String, json: String) -> bool {
        manager::update_scene(scene_id, json)
    }

    #[wasm_bindgen]
    pub fn elpian_bevy_wasm_render_frame(scene_id: String, delta_time: f32) -> bool {
        manager::render_frame(&scene_id, delta_time)
    }

    #[wasm_bindgen]
    pub fn elpian_bevy_wasm_resize_scene(scene_id: String, width: u32, height: u32) -> bool {
        manager::resize_scene(&scene_id, width, height)
    }

    /// Returns the rendered frame as a JSON string with base64-encoded RGBA data.
    /// Format: {"width": N, "height": N, "data": "<base64>", "frameCount": N}
    #[wasm_bindgen]
    pub fn elpian_bevy_wasm_get_frame(scene_id: String) -> String {
        let dims = match manager::get_scene_dimensions(&scene_id) {
            Some(d) => d,
            None => return "{}".to_string(),
        };

        let pixels = match manager::get_frame_copy(&scene_id) {
            Some(p) => p,
            None => return "{}".to_string(),
        };

        // For WASM, return raw pixel data as a comma-separated list of bytes
        // (more efficient than base64 for JS typed arrays)
        let frame_count = manager::get_frame_count(&scene_id);

        json!({
            "width": dims.0,
            "height": dims.1,
            "frameCount": frame_count,
            "pixelCount": pixels.len(),
        })
        .to_string()
    }

    /// Get raw pixel bytes as a Vec<u8> for direct typed array access in JS.
    #[wasm_bindgen]
    pub fn elpian_bevy_wasm_get_frame_bytes(scene_id: String) -> Vec<u8> {
        manager::get_frame_copy(&scene_id).unwrap_or_default()
    }

    #[wasm_bindgen]
    pub fn elpian_bevy_wasm_send_input(scene_id: String, input_json: String) -> bool {
        manager::send_input(&scene_id, &input_json)
    }

    #[wasm_bindgen]
    pub fn elpian_bevy_wasm_destroy_scene(scene_id: String) -> bool {
        manager::destroy_scene(&scene_id)
    }

    #[wasm_bindgen]
    pub fn elpian_bevy_wasm_scene_exists(scene_id: String) -> bool {
        manager::scene_exists(&scene_id)
    }

    #[wasm_bindgen]
    pub fn elpian_bevy_wasm_get_elapsed_time(scene_id: String) -> f32 {
        manager::get_elapsed_time(&scene_id)
    }

    #[wasm_bindgen]
    pub fn elpian_bevy_wasm_get_frame_count(scene_id: String) -> u64 {
        manager::get_frame_count(&scene_id)
    }
}
