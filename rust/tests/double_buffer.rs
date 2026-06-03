//! A5 double-buffer correctness: the front buffer a reader grabbed must stay
//! intact while the *next* frame renders (that is the property F1 relies on to
//! hand out a pointer without copying).

use elpian_vm::bevy_scene::renderer::SceneRenderer;
use elpian_vm::bevy_scene::schema::SceneDef;

// A rotating cube so consecutive frames are genuinely different — otherwise the
// test could pass trivially even if the buffer were overwritten.
const ANIMATED: &str = r#"{"world":[
    {"type":"camera","transform":{"position":{"x":0,"y":1.5,"z":5}}},
    {"type":"light","light_type":"Directional","intensity":1.2,
     "transform":{"position":{"x":3,"y":5,"z":4}}},
    {"type":"mesh3d","mesh":"Cube",
     "material":{"base_color":{"r":0.8,"g":0.3,"b":0.2}},
     "animation":{"animation_type":{"type":"Rotate","axis":{"x":0,"y":1,"z":0},"degrees":120},
                  "duration":2.0,"looping":true}}
]}"#;

#[test]
fn front_buffer_survives_next_render() {
    let scene: SceneDef = serde_json::from_str(ANIMATED).unwrap();
    let mut r = SceneRenderer::new(128, 128);
    let dt = 1.0 / 60.0;

    // Frame 0 lands in the front buffer (`pixels`).
    r.render_scene(&scene, dt);
    let frame0 = r.pixels.clone();
    let ptr = r.pixels.as_ptr();
    let len = r.pixels.len();

    // Render frame 1. With double-buffering this renders into the back buffer and
    // swaps; the allocation `ptr` points to becomes the back buffer but is NOT
    // written during this frame, so it still holds frame 0.
    r.render_scene(&scene, dt);
    let frame1 = &r.pixels;

    // Sanity: the animation actually changed the image (else the test is vacuous).
    assert_ne!(
        &frame0[..],
        &frame1[..],
        "frames identical — pick a scene that animates"
    );

    // The buffer a reader grabbed after frame 0 is still frame 0 (not corrupted by
    // frame 1's render).
    let after = unsafe { std::slice::from_raw_parts(ptr, len) };
    assert_eq!(
        after,
        &frame0[..],
        "front buffer was overwritten while the next frame rendered"
    );
}
