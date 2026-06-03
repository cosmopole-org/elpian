//! Criterion micro-benchmarks for the software rasterizer hot path.
//!
//! Run: `cargo bench --manifest-path rust/Cargo.toml`
//! Record before/after numbers in `upgrade/STATUS.md` and
//! `benchmarks/reports/optimization/`.

use criterion::{criterion_group, criterion_main, BenchmarkId, Criterion};
use elpian_vm::bevy_scene::renderer::SceneRenderer;
use elpian_vm::bevy_scene::schema::SceneDef;

const W: u32 = 512;
const H: u32 = 512;
const DT: f32 = 1.0 / 60.0;

fn scene(json: &str) -> SceneDef {
    serde_json::from_str(json).expect("scene JSON must parse")
}

fn scenes() -> Vec<(&'static str, SceneDef)> {
    vec![
        (
            "empty",
            scene(r#"{"world":[{"type":"camera","transform":{"position":{"x":0,"y":2,"z":6}}}]}"#),
        ),
        (
            "single_cube",
            scene(
                r#"{"world":[
                {"type":"camera","transform":{"position":{"x":0,"y":1.5,"z":5}}},
                {"type":"light","light_type":"Directional","intensity":1.2,
                 "transform":{"position":{"x":3,"y":5,"z":4}}},
                {"type":"mesh3d","mesh":"Cube",
                 "material":{"base_color":{"r":0.8,"g":0.3,"b":0.2}},
                 "transform":{"rotation":{"x":25,"y":40,"z":0}}}]}"#,
            ),
        ),
        (
            "sphere_hipoly",
            scene(
                r#"{"world":[
                {"type":"camera","transform":{"position":{"x":0,"y":0,"z":4}}},
                {"type":"light","light_type":"Point","intensity":1.5,
                 "transform":{"position":{"x":2,"y":3,"z":3}}},
                {"type":"mesh3d","mesh":{"shape":"Sphere","radius":1.5,"subdivisions":48}}]}"#,
            ),
        ),
        (
            "fifty_meshes",
            scene(&fifty_meshes_json()),
        ),
        (
            "particles",
            scene(
                r#"{"world":[
                {"type":"camera","transform":{"position":{"x":0,"y":2,"z":8}}},
                {"type":"light","light_type":"Point","intensity":1.0,
                 "transform":{"position":{"x":0,"y":5,"z":5}}},
                {"type":"particles","emission_rate":80,"lifetime":2.0,"size":0.2,
                 "color":{"r":1.0,"g":0.7,"b":0.1},
                 "velocity":{"x":0,"y":2,"z":0},"gravity":{"x":0,"y":-3,"z":0}}]}"#,
            ),
        ),
        (
            "fillrate_quad",
            scene(
                r#"{"world":[
                {"type":"camera","transform":{"position":{"x":0,"y":0,"z":2}}},
                {"type":"light","light_type":"Directional","intensity":1.0,
                 "transform":{"position":{"x":0,"y":0,"z":5}}},
                {"type":"mesh3d","mesh":{"shape":"Plane","size":20.0},
                 "material":{"base_color":{"r":0.3,"g":0.6,"b":0.9,"a":0.5}},
                 "transform":{"rotation":{"x":90,"y":0,"z":0}}}]}"#,
            ),
        ),
    ]
}

fn fifty_meshes_json() -> String {
    let mut nodes = String::from(
        r#"{"type":"camera","transform":{"position":{"x":0,"y":8,"z":18}}},
           {"type":"light","light_type":"Directional","intensity":1.0,
            "transform":{"position":{"x":1,"y":4,"z":2}}}"#,
    );
    for i in 0..50 {
        let x = (i % 10) as f32 * 1.5 - 7.0;
        let z = (i / 10) as f32 * 1.5 - 3.0;
        nodes.push_str(&format!(
            r#",{{"type":"mesh3d","mesh":"Cube","transform":{{"position":{{"x":{x},"y":0,"z":{z}}}}}}}"#
        ));
    }
    format!(r#"{{"world":[{nodes}]}}"#)
}

fn bench_render(c: &mut Criterion) {
    let mut group = c.benchmark_group("render_scene");
    for (name, scene) in scenes() {
        // Each iteration renders one frame into a reused renderer.
        let mut r = SceneRenderer::new(W, H);
        group.bench_with_input(BenchmarkId::from_parameter(name), &scene, |b, scene| {
            b.iter(|| r.render_scene(scene, DT));
        });
    }
    group.finish();
}

criterion_group!(benches, bench_render);
criterion_main!(benches);
