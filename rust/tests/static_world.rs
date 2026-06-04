//! P3 tests: the manager bakes the `staticWorld` once (keyed by `staticKey`) and
//! splices it with the per-frame dynamic `world`. Steady-state frames that omit
//! `staticWorld` must still render the cached static geometry; a changed key with
//! fresh geometry must swap it.

use elpian_vm::bevy_scene::manager;

const W: u32 = 64;
const H: u32 = 64;

fn center_rgb(scene_id: &str) -> (u8, u8, u8) {
    let px = manager::get_frame_copy(scene_id).expect("frame");
    let idx = (((H / 2) * W + (W / 2)) * 4) as usize;
    (px[idx], px[idx + 1], px[idx + 2])
}

#[test]
fn static_world_is_baked_once_and_reused_when_omitted() {
    let id = "p3-static-reuse";
    // Boot: a red unlit cube in the static world; camera in the dynamic world.
    let boot = r#"{
        "staticKey":"city-v1",
        "staticWorld":[
            {"type":"mesh3d","mesh":"Cube",
             "material":{"unlit":true,"base_color":{"r":0.9,"g":0.15,"b":0.15}}}
        ],
        "world":[{"type":"camera","transform":{"position":{"x":0,"y":0,"z":4}}}]
    }"#;
    assert!(manager::create_scene(id.to_string(), boot.to_string(), W, H));
    assert!(manager::render_frame(id, 1.0 / 60.0));
    let (r0, g0, b0) = center_rgb(id);
    assert!(r0 > 150 && g0 < 90 && b0 < 90, "static red cube should render: {r0},{g0},{b0}");

    // Steady-state frame: only the dynamic world (no staticWorld). The baked city
    // must survive — the red cube is still centered.
    let frame = r#"{
        "staticKey":"city-v1",
        "world":[{"type":"camera","transform":{"position":{"x":0,"y":0,"z":4}}}]
    }"#;
    assert!(manager::update_scene(id.to_string(), frame.to_string()));
    assert!(manager::render_frame(id, 1.0 / 60.0));
    let (r1, g1, b1) = center_rgb(id);
    assert!(
        r1 > 150 && g1 < 90 && b1 < 90,
        "baked static cube must persist after a dynamic-only update: {r1},{g1},{b1}"
    );

    manager::destroy_scene(id);
}

#[test]
fn changed_static_key_rebakes_the_world() {
    let id = "p3-static-rebake";
    let boot = r#"{
        "staticKey":"v1",
        "staticWorld":[{"type":"mesh3d","mesh":"Cube",
            "material":{"unlit":true,"base_color":{"r":0.9,"g":0.1,"b":0.1}}}],
        "world":[{"type":"camera","transform":{"position":{"x":0,"y":0,"z":4}}}]
    }"#;
    assert!(manager::create_scene(id.to_string(), boot.to_string(), W, H));
    assert!(manager::render_frame(id, 1.0 / 60.0));
    let (r0, _g0, _b0) = center_rgb(id);
    assert!(r0 > 150, "v1 red cube renders");

    // New key + new geometry (green cube) → the static cache swaps.
    let rebake = r#"{
        "staticKey":"v2",
        "staticWorld":[{"type":"mesh3d","mesh":"Cube",
            "material":{"unlit":true,"base_color":{"r":0.1,"g":0.9,"b":0.1}}}],
        "world":[{"type":"camera","transform":{"position":{"x":0,"y":0,"z":4}}}]
    }"#;
    assert!(manager::update_scene(id.to_string(), rebake.to_string()));
    assert!(manager::render_frame(id, 1.0 / 60.0));
    let (r1, g1, _b1) = center_rgb(id);
    assert!(g1 > 150 && r1 < 90, "static world should rebake to the green cube: {r1},{g1}");

    manager::destroy_scene(id);
}
