//! Golden pixel-checksum tests for the software rasterizer.
//!
//! These lock the framebuffer output of a set of representative scenes so that
//! performance refactors (mesh cache A2, incremental rasterizer A3, parallel
//! rasterizer A4, double-buffering A5) can be proven **byte-identical** to the
//! baseline captured before those changes.
//!
//! If a change is meant to alter output, update the constants intentionally and
//! say so in the commit. Otherwise a mismatch here is a regression.
//!
//! To (re)capture baselines: `cargo test --release --test renderer_golden -- --nocapture print_hashes`

use elpian_vm::bevy_scene::renderer::SceneRenderer;
use elpian_vm::bevy_scene::schema::SceneDef;

const W: u32 = 256;
const H: u32 = 256;
const FRAMES: usize = 3;
const DT: f32 = 1.0 / 60.0;

/// FNV-1a 64-bit hash of the framebuffer — stable, dependency-free.
fn fnv1a(bytes: &[u8]) -> u64 {
    let mut hash: u64 = 0xcbf29ce484222325;
    for &b in bytes {
        hash ^= b as u64;
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

/// Render `frames` frames of a scene at fixed delta and hash the final framebuffer.
fn render_hash(json: &str) -> u64 {
    let scene: SceneDef = serde_json::from_str(json).expect("scene JSON must parse");
    let mut r = SceneRenderer::new(W, H);
    for _ in 0..FRAMES {
        r.render_scene(&scene, DT);
    }
    fnv1a(&r.pixels)
}

// ── Representative scenes ────────────────────────────────────────────────

fn scene_empty() -> &'static str {
    r#"{"world":[{"type":"camera","transform":{"position":{"x":0,"y":2,"z":6}}}]}"#
}

fn scene_cube() -> &'static str {
    r#"{"world":[
        {"type":"camera","transform":{"position":{"x":0,"y":1.5,"z":5}}},
        {"type":"light","light_type":"Directional","intensity":1.2,
         "transform":{"position":{"x":3,"y":5,"z":4}}},
        {"type":"mesh3d","mesh":"Cube",
         "material":{"base_color":{"r":0.8,"g":0.3,"b":0.2}},
         "transform":{"rotation":{"x":25,"y":40,"z":0}}}
    ]}"#
}

fn scene_sphere() -> &'static str {
    r#"{"world":[
        {"type":"camera","transform":{"position":{"x":0,"y":0,"z":4}}},
        {"type":"light","light_type":"Point","intensity":1.5,
         "transform":{"position":{"x":2,"y":3,"z":3}}},
        {"type":"mesh3d","mesh":{"shape":"Sphere","radius":1.2,"subdivisions":24},
         "material":{"base_color":{"r":0.2,"g":0.6,"b":0.9},"metallic":0.3,"roughness":0.4}}
    ]}"#
}

fn scene_multi_mesh() -> &'static str {
    r#"{"world":[
        {"type":"camera","transform":{"position":{"x":0,"y":4,"z":9}}},
        {"type":"light","light_type":"Directional","intensity":1.0,
         "transform":{"position":{"x":1,"y":4,"z":2}}},
        {"type":"mesh3d","mesh":"Cube","transform":{"position":{"x":-2.5,"y":0,"z":0}}},
        {"type":"mesh3d","mesh":{"shape":"Sphere","radius":1.0,"subdivisions":16},
         "transform":{"position":{"x":0,"y":0,"z":0}}},
        {"type":"mesh3d","mesh":{"shape":"Cylinder","radius":0.7,"height":2.0},
         "transform":{"position":{"x":2.5,"y":0,"z":0}}},
        {"type":"mesh3d","mesh":{"shape":"Torus","radius":1.0,"tube_radius":0.3},
         "transform":{"position":{"x":0,"y":2.5,"z":0},"rotation":{"x":45,"y":0,"z":0}}}
    ]}"#
}

fn scene_particles() -> &'static str {
    r#"{"world":[
        {"type":"camera","transform":{"position":{"x":0,"y":2,"z":8}}},
        {"type":"light","light_type":"Point","intensity":1.0,
         "transform":{"position":{"x":0,"y":5,"z":5}}},
        {"type":"particles","emission_rate":60,"lifetime":2.0,"size":0.15,
         "color":{"r":1.0,"g":0.7,"b":0.1},
         "velocity":{"x":0,"y":2,"z":0},"gravity":{"x":0,"y":-3,"z":0}}
    ]}"#
}

fn scene_translucent() -> &'static str {
    r#"{"world":[
        {"type":"camera","transform":{"position":{"x":0,"y":0,"z":5}}},
        {"type":"light","light_type":"Directional","intensity":1.0,
         "transform":{"position":{"x":0,"y":3,"z":5}}},
        {"type":"mesh3d","mesh":"Cube",
         "material":{"base_color":{"r":0.1,"g":0.9,"b":0.4,"a":1.0}},
         "transform":{"position":{"x":-0.5,"y":0,"z":-1}}},
        {"type":"mesh3d","mesh":{"shape":"Plane","size":3.0},
         "material":{"base_color":{"r":0.9,"g":0.2,"b":0.2,"a":0.5}},
         "transform":{"position":{"x":0.5,"y":0,"z":0},"rotation":{"x":80,"y":0,"z":0}}}
    ]}"#
}

/// All scenes in a stable order: (name, json).
fn all_scenes() -> Vec<(&'static str, &'static str)> {
    vec![
        ("empty", scene_empty()),
        ("cube", scene_cube()),
        ("sphere", scene_sphere()),
        ("multi_mesh", scene_multi_mesh()),
        ("particles", scene_particles()),
        ("translucent", scene_translucent()),
    ]
}

// ── Baseline hashes (captured 2026-06-03 on the pre-A2/A3 serial renderer) ──
// Order matches `all_scenes()`.
const BASELINE: &[(&str, u64)] = &[
    ("empty", 0x952aff0bd3202325),
    ("cube", 0x9cb0269a67f5ba05),
    ("sphere", 0x6ca1c9c47e7ae1e9),
    ("multi_mesh", 0xa3087ff23a07a4cf),
    ("particles", 0xc92a64600f8cf54a),
    ("translucent", 0x1bf5f3f29ac99f0c),
];

/// Helper to (re)capture baselines. Run with:
/// `cargo test --release --test renderer_golden print_hashes -- --nocapture --ignored`
#[test]
#[ignore]
fn print_hashes() {
    println!("// captured golden hashes:");
    for (name, json) in all_scenes() {
        println!("    (\"{}\", 0x{:016x}),", name, render_hash(json));
    }
}

#[test]
fn golden_output_is_stable() {
    let mut mismatches = Vec::new();
    for ((name, json), (bname, expected)) in all_scenes().iter().zip(BASELINE.iter()) {
        assert_eq!(name, bname, "scene order must match BASELINE order");
        let got = render_hash(json);
        if got != *expected {
            mismatches.push(format!(
                "  {name}: expected 0x{expected:016x}, got 0x{got:016x}"
            ));
        }
    }
    assert!(
        mismatches.is_empty(),
        "framebuffer output changed for:\n{}",
        mismatches.join("\n")
    );
}

/// Renderer output must be deterministic across runs (no uninitialized memory,
/// no time/threading nondeterminism).
#[test]
fn rendering_is_deterministic() {
    for (name, json) in all_scenes() {
        let a = render_hash(json);
        let b = render_hash(json);
        assert_eq!(a, b, "scene `{name}` is non-deterministic");
    }
}
