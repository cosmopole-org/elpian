//! Regression tests for animation parity between the `bevy_scene` software
//! renderer and the scene3d (GameScene) reference implementation:
//!
//! - every documented animation type (`Rotate`..`Spin`) and easing name
//!   (`Linear`..`Sine`) must *parse* — a single unknown variant used to fail
//!   the whole scene deserialization and render nothing;
//! - `Translate` animations apply on top of the node's base transform instead
//!   of replacing it;
//! - camera nodes honor their `animation` field.

use elpian_vm::bevy_scene::renderer::SceneRenderer;
use elpian_vm::bevy_scene::schema::SceneDef;

const W: u32 = 128;
const H: u32 = 128;

fn render(json: &str) -> Vec<u8> {
    let scene: SceneDef = serde_json::from_str(json).expect("scene JSON must parse");
    let mut r = SceneRenderer::new(W, H);
    r.render_scene(&scene, 1.0 / 60.0);
    r.pixels.clone()
}

fn center_luma(px: &[u8]) -> f32 {
    let idx = (((H / 2) * W + W / 2) * 4) as usize;
    0.299 * px[idx] as f32 + 0.587 * px[idx + 1] as f32 + 0.114 * px[idx + 2] as f32
}

fn cube_scene(animation: &str) -> String {
    format!(
        r#"{{"world":[
            {{"type":"camera","transform":{{"position":{{"x":0,"y":0,"z":4}}}}}},
            {{"type":"mesh3d","mesh":"Cube",
              "material":{{"base_color":{{"r":1,"g":1,"b":1,"a":1}}}},
              "animation":{animation}}}
        ]}}"#
    )
}

#[test]
fn all_documented_animation_types_parse_and_render() {
    let animations = [
        r#"{"animation_type":{"type":"Rotate","axis":{"x":0,"y":1,"z":0},"degrees":360},"duration":2.0,"looping":true}"#,
        r#"{"animation_type":{"type":"Translate","from":{"x":0,"y":0,"z":0},"to":{"x":0,"y":1,"z":0}},"duration":2.0}"#,
        r#"{"animation_type":{"type":"Scale","from":{"x":1,"y":1,"z":1},"to":{"x":2,"y":2,"z":2}},"duration":2.0}"#,
        r#"{"animation_type":{"type":"Bounce","height":1.0},"duration":2.0,"looping":true}"#,
        r#"{"animation_type":{"type":"Pulse","min_scale":0.8,"max_scale":1.2},"duration":2.0,"looping":true}"#,
        r#"{"animation_type":{"type":"Orbit","radius":2.0,"height":0.5},"duration":4.0,"looping":true}"#,
        r#"{"animation_type":{"type":"Swing","angle":30.0,"axis":{"x":0,"y":0,"z":1}},"duration":2.0,"looping":true}"#,
        r#"{"animation_type":{"type":"Shake","intensity":0.1},"duration":1.0,"looping":true}"#,
        r#"{"animation_type":{"type":"Float","amplitude":0.5},"duration":3.0,"looping":true}"#,
        r#"{"animation_type":{"type":"Spin","speed":{"x":0,"y":90,"z":0}},"duration":1.0,"looping":true}"#,
        // Defaults-only variants must parse too (all params are optional).
        r#"{"animation_type":{"type":"Orbit"},"duration":4.0,"looping":true}"#,
        r#"{"animation_type":{"type":"Rotate"},"duration":4.0,"looping":true,"delay":0.5}"#,
    ];
    for anim in animations {
        // `render` panics with a parse error message if the variant is unknown.
        render(&cube_scene(anim));
    }
}

#[test]
fn all_documented_easing_names_parse() {
    for easing in [
        "Linear", "EaseIn", "EaseOut", "EaseInOut", "Bounce", "Elastic", "Back", "Sine",
    ] {
        let anim = format!(
            r#"{{"animation_type":{{"type":"Rotate","axis":{{"x":0,"y":1,"z":0}},"degrees":360}},"duration":2.0,"easing":"{easing}"}}"#
        );
        render(&cube_scene(&anim));
    }
}

#[test]
fn translate_animation_preserves_base_transform() {
    // A cube whose *base* position is far off-screen, with a no-op Translate
    // animation (from == to == origin). The animated translation must compose
    // with the base transform, leaving the cube off-screen: the frame center
    // shows only the background, same as a scene with no cube at all.
    let off_screen = r#"{"world":[
        {"type":"camera","transform":{"position":{"x":0,"y":0,"z":4}}},
        {"type":"mesh3d","mesh":"Cube",
         "material":{"base_color":{"r":1,"g":1,"b":1,"a":1}},
         "transform":{"position":{"x":100,"y":0,"z":0}},
         "animation":{"animation_type":{"type":"Translate",
            "from":{"x":0,"y":0,"z":0},"to":{"x":0,"y":0,"z":0}},"duration":1.0}}
    ]}"#;
    let empty = r#"{"world":[
        {"type":"camera","transform":{"position":{"x":0,"y":0,"z":4}}}
    ]}"#;
    let on_screen = cube_scene(
        r#"{"animation_type":{"type":"Translate","from":{"x":0,"y":0,"z":0},"to":{"x":0,"y":0,"z":0}},"duration":1.0}"#,
    );

    let off_luma = center_luma(&render(off_screen));
    let empty_luma = center_luma(&render(empty));
    let on_luma = center_luma(&render(&on_screen));

    assert!(
        (off_luma - empty_luma).abs() < 1.0,
        "base transform was lost: cube with off-screen base position reappeared at \
         the origin (center luma {off_luma} vs background {empty_luma})"
    );
    assert!(
        on_luma > empty_luma + 20.0,
        "control failed: cube at the origin should light up the frame center \
         (center luma {on_luma} vs background {empty_luma})"
    );
}

#[test]
fn camera_animation_is_applied() {
    // Camera spins 180° around Y (non-looping, duration shorter than the first
    // frame's elapsed time, so it has fully turned by the time we sample).
    // Facing away from the cube, the frame center must show only background.
    let turned_away = r#"{"world":[
        {"type":"camera","transform":{"position":{"x":0,"y":0,"z":4}},
         "animation":{"animation_type":{"type":"Rotate",
            "axis":{"x":0,"y":1,"z":0},"degrees":180},"duration":0.001,"looping":false}},
        {"type":"mesh3d","mesh":"Cube",
         "material":{"base_color":{"r":1,"g":1,"b":1,"a":1}}}
    ]}"#;
    let facing = r#"{"world":[
        {"type":"camera","transform":{"position":{"x":0,"y":0,"z":4}}},
        {"type":"mesh3d","mesh":"Cube",
         "material":{"base_color":{"r":1,"g":1,"b":1,"a":1}}}
    ]}"#;

    let away_luma = center_luma(&render(turned_away));
    let facing_luma = center_luma(&render(facing));

    assert!(
        facing_luma > away_luma + 20.0,
        "camera animation ignored: turned-away camera still sees the cube \
         (away {away_luma} vs facing {facing_luma})"
    );
}
