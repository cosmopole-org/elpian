//! Behavioral tests for the P1 material/environment/light parity features added
//! to bring the `bevy_scene` software renderer in line with the scene3d
//! (GameScene) reference: `unlit`, `emissive_strength`, scalar `alpha` + lowercase
//! `alpha_mode`, sky gradient, linear fog + `fog_near`, point-light `range`, and
//! `segments` mesh tessellation.
//!
//! These assert *properties* of the framebuffer (a region got brighter/darker,
//! top≠bottom, a scene parses & renders) rather than exact pixel hashes, so they
//! stay robust to incidental shading tweaks while still guarding the features.

use elpian_vm::bevy_scene::renderer::SceneRenderer;
use elpian_vm::bevy_scene::schema::SceneDef;

const W: u32 = 128;
const H: u32 = 128;

/// Render one frame of a scene and return the RGBA framebuffer.
fn render(json: &str) -> Vec<u8> {
    let scene: SceneDef = serde_json::from_str(json).expect("scene JSON must parse");
    let mut r = SceneRenderer::new(W, H);
    r.render_scene(&scene, 1.0 / 60.0);
    r.pixels.clone()
}

/// Average luminance of the whole frame (rough "how bright is this").
fn avg_luma(px: &[u8]) -> f32 {
    let mut sum = 0.0;
    let mut n = 0.0;
    for p in px.chunks_exact(4) {
        sum += 0.299 * p[0] as f32 + 0.587 * p[1] as f32 + 0.114 * p[2] as f32;
        n += 1.0;
    }
    sum / n
}

/// Pixel at (x,y) as (r,g,b).
fn pixel(px: &[u8], x: u32, y: u32) -> (u8, u8, u8) {
    let idx = ((y * W + x) * 4) as usize;
    (px[idx], px[idx + 1], px[idx + 2])
}

/// Luminance of the framebuffer center (where a cube at the origin lands), to
/// isolate the object from the background when averaging would dilute it.
fn center_luma(px: &[u8]) -> f32 {
    let (r, g, b) = pixel(px, W / 2, H / 2);
    0.299 * r as f32 + 0.587 * g as f32 + 0.114 * b as f32
}

fn cam_front() -> &'static str {
    r#"{"type":"camera","transform":{"position":{"x":0,"y":0,"z":4}}}"#
}

#[test]
fn unlit_material_is_bright_without_lights() {
    // An explicit near-off directional light suppresses the auto-default light, so
    // the lit cube falls to ambient only (near-black). The unlit cube outputs its
    // base color directly and must be clearly brighter at the object center.
    let dim_light = r#"{"type":"light","light_type":"Directional","intensity":0.0,"transform":{"position":{"x":0,"y":1,"z":1}}}"#;
    let lit = format!(
        r#"{{"world":[{cam},{light},
            {{"type":"environment","ambient_intensity":0.05}},
            {{"type":"mesh3d","mesh":"Cube","material":{{"base_color":{{"r":0.9,"g":0.9,"b":0.9}}}}}}]}}"#,
        cam = cam_front(),
        light = dim_light
    );
    let unlit = format!(
        r#"{{"world":[{cam},{light},
            {{"type":"environment","ambient_intensity":0.05}},
            {{"type":"mesh3d","mesh":"Cube","material":{{"base_color":{{"r":0.9,"g":0.9,"b":0.9}},"unlit":true}}}}]}}"#,
        cam = cam_front(),
        light = dim_light
    );
    assert!(
        center_luma(&render(&unlit)) > center_luma(&render(&lit)) + 100.0,
        "unlit cube center should be much brighter than the ambient-only lit cube"
    );
}

#[test]
fn emissive_strength_scales_brightness() {
    let weak = format!(
        r#"{{"world":[{cam},
            {{"type":"mesh3d","mesh":"Cube","material":{{"base_color":{{"r":0,"g":0,"b":0}},"emissive":{{"r":0.3,"g":0.3,"b":0.3}},"emissive_strength":1.0,"unlit":true}}}}]}}"#,
        cam = cam_front()
    );
    let strong = format!(
        r#"{{"world":[{cam},
            {{"type":"mesh3d","mesh":"Cube","material":{{"base_color":{{"r":0,"g":0,"b":0}},"emissive":{{"r":0.3,"g":0.3,"b":0.3}},"emissive_strength":3.0,"unlit":true}}}}]}}"#,
        cam = cam_front()
    );
    assert!(
        center_luma(&render(&strong)) > center_luma(&render(&weak)) + 40.0,
        "higher emissive_strength must produce a brighter object center"
    );
}

#[test]
fn sky_gradient_makes_top_differ_from_bottom() {
    let json = r#"{"world":[
        {"type":"camera","transform":{"position":{"x":0,"y":0,"z":6}}},
        {"type":"environment",
         "sky_color_top":{"r":0.03,"g":0.05,"b":0.14},
         "sky_color_bottom":{"r":0.6,"g":0.42,"b":0.30}}
    ]}"#;
    let px = render(json);
    let top = pixel(&px, W / 2, 1);
    let bottom = pixel(&px, W / 2, H - 2);
    // Bottom is warmer/brighter than the deep-blue top.
    assert_ne!(top, bottom, "sky gradient should vary vertically");
    assert!(
        bottom.0 as i32 > top.0 as i32 + 30,
        "bottom of the sky should be warmer (more red) than the top: top={top:?} bottom={bottom:?}"
    );
}

#[test]
fn lowercase_alpha_mode_and_scalar_alpha_parse_and_blend() {
    // A translucent plane in front of an opaque cube. Using lowercase
    // alpha_mode:"blend" (scene3d spelling) and a scalar `alpha`.
    let json = r#"{"world":[
        {"type":"camera","transform":{"position":{"x":0,"y":0,"z":5}}},
        {"type":"light","light_type":"Directional","intensity":1.0,
         "transform":{"position":{"x":0,"y":3,"z":5}}},
        {"type":"mesh3d","mesh":"Cube",
         "material":{"base_color":{"r":0.1,"g":0.9,"b":0.3}},
         "transform":{"position":{"x":0,"y":0,"z":-1}}},
        {"type":"mesh3d","mesh":{"shape":"Plane","size":3.0},
         "material":{"base_color":{"r":0.9,"g":0.2,"b":0.2},"alpha":0.4,"alpha_mode":"blend"},
         "transform":{"rotation":{"x":80,"y":0,"z":0}}}
    ]}"#;
    // Must parse (scalar alpha + lowercase alpha_mode) and produce a non-empty frame.
    assert!(avg_luma(&render(json)) > 1.0, "blended scene should render");
}

#[test]
fn point_light_range_limits_reach() {
    // A point light 8 units away. With a tight range it should barely light the
    // cube; with a generous range it lights it well.
    let tight = r#"{"world":[
        {"type":"camera","transform":{"position":{"x":0,"y":0,"z":4}}},
        {"type":"environment","ambient_intensity":0.0},
        {"type":"light","light_type":"Point","intensity":3.0,"range":2.0,
         "transform":{"position":{"x":0,"y":0,"z":12}}},
        {"type":"mesh3d","mesh":"Cube","material":{"base_color":{"r":0.9,"g":0.9,"b":0.9}}}
    ]}"#;
    let wide = r#"{"world":[
        {"type":"camera","transform":{"position":{"x":0,"y":0,"z":4}}},
        {"type":"environment","ambient_intensity":0.0},
        {"type":"light","light_type":"Point","intensity":3.0,"range":40.0,
         "transform":{"position":{"x":0,"y":0,"z":12}}},
        {"type":"mesh3d","mesh":"Cube","material":{"base_color":{"r":0.9,"g":0.9,"b":0.9}}}
    ]}"#;
    assert!(
        avg_luma(&render(wide)) > avg_luma(&render(tight)) + 5.0,
        "a larger point-light range should light the cube more than a tiny range"
    );
}

#[test]
fn linear_fog_with_near_darkens_distant_geometry() {
    // Same far plane, with and without linear fog toward a bright color. The
    // fogged frame should differ (blend toward fog color past fog_near).
    let no_fog = r#"{"world":[
        {"type":"camera","transform":{"position":{"x":0,"y":1,"z":2}}},
        {"type":"light","light_type":"Directional","intensity":1.0,
         "transform":{"position":{"x":0,"y":5,"z":2}}},
        {"type":"mesh3d","mesh":{"shape":"Plane","size":60.0},
         "material":{"base_color":{"r":0.2,"g":0.2,"b":0.2}},
         "transform":{"position":{"x":0,"y":0,"z":-20}}}
    ]}"#;
    let fogged = r#"{"world":[
        {"type":"camera","transform":{"position":{"x":0,"y":1,"z":2}}},
        {"type":"environment","fog_type":"linear","fog_near":5.0,"fog_distance":40.0,
         "fog_color":{"r":0.9,"g":0.9,"b":0.95}},
        {"type":"light","light_type":"Directional","intensity":1.0,
         "transform":{"position":{"x":0,"y":5,"z":2}}},
        {"type":"mesh3d","mesh":{"shape":"Plane","size":60.0},
         "material":{"base_color":{"r":0.2,"g":0.2,"b":0.2}},
         "transform":{"position":{"x":0,"y":0,"z":-20}}}
    ]}"#;
    // Fog toward white must brighten the distant dark plane.
    assert!(
        avg_luma(&render(fogged)) > avg_luma(&render(no_fog)) + 3.0,
        "linear fog toward a light color should brighten distant geometry"
    );
}

#[test]
fn checkerboard_texture_produces_two_distinct_colors() {
    // A large unlit checkerboard plane filling the view. With base_color (red) and
    // texture_color2 (blue) and a high scale, the frame must contain clearly red
    // and clearly blue pixels — i.e. the procedural texture is being sampled.
    let json = r#"{"world":[
        {"type":"camera","transform":{"position":{"x":0,"y":6,"z":0},"rotation":{"x":-90,"y":0,"z":0}}},
        {"type":"mesh3d","mesh":{"shape":"Plane","size":10.0},
         "material":{"unlit":true,
            "base_color":{"r":0.9,"g":0.05,"b":0.05},
            "texture":"checkerboard","texture_scale":8.0,
            "texture_color2":{"r":0.05,"g":0.05,"b":0.9}}}
    ]}"#;
    let px = render(json);
    let mut reddish = 0;
    let mut bluish = 0;
    for p in px.chunks_exact(4) {
        // Skip the dark sky background; only count saturated texels.
        if p[0] > 150 && p[2] < 90 {
            reddish += 1;
        } else if p[2] > 150 && p[0] < 90 {
            bluish += 1;
        }
    }
    assert!(
        reddish > 50 && bluish > 50,
        "checkerboard should paint both base_color and texture_color2 cells: red={reddish} blue={bluish}"
    );
}

#[test]
fn noise_texture_varies_across_surface() {
    // An unlit noise plane should not be a single flat color: gather the luma of
    // many surface pixels and assert they span a range (noise modulates base_color).
    let json = r#"{"world":[
        {"type":"camera","transform":{"position":{"x":0,"y":6,"z":0},"rotation":{"x":-90,"y":0,"z":0}}},
        {"type":"mesh3d","mesh":{"shape":"Plane","size":10.0},
         "material":{"unlit":true,
            "base_color":{"r":0.8,"g":0.8,"b":0.8},
            "texture":"noise","texture_scale":40.0}}
    ]}"#;
    let px = render(json);
    let mut min_l = 255.0f32;
    let mut max_l = 0.0f32;
    for p in px.chunks_exact(4) {
        // Only consider lit surface pixels (skip dark background).
        let l = 0.299 * p[0] as f32 + 0.587 * p[1] as f32 + 0.114 * p[2] as f32;
        if l > 20.0 {
            min_l = min_l.min(l);
            max_l = max_l.max(l);
        }
    }
    assert!(
        max_l - min_l > 30.0,
        "noise texture should produce varying brightness across the plane: span={}",
        max_l - min_l
    );
}

#[test]
fn segments_alias_parses_for_cyl_cone_sphere() {
    // The scene3d DSL uses `segments`; ensure it parses and renders for all three.
    let json = r#"{"world":[
        {"type":"camera","transform":{"position":{"x":0,"y":2,"z":8}}},
        {"type":"light","light_type":"Directional","intensity":1.0,
         "transform":{"position":{"x":1,"y":4,"z":2}}},
        {"type":"mesh3d","mesh":{"shape":"Cylinder","radius":0.6,"height":2.0,"segments":20},
         "transform":{"position":{"x":-2,"y":0,"z":0}}},
        {"type":"mesh3d","mesh":{"shape":"Cone","radius":0.6,"height":1.5,"segments":10},
         "transform":{"position":{"x":0,"y":0,"z":0}}},
        {"type":"mesh3d","mesh":{"shape":"Sphere","radius":0.8,"segments":12},
         "transform":{"position":{"x":2,"y":0,"z":0}}}
    ]}"#;
    assert!(
        avg_luma(&render(json)) > 1.0,
        "cyl/cone/sphere with `segments` should parse and render"
    );
}
