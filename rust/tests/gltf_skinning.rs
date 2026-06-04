//! Unit tests for the P2 glTF/GLB loader + CPU skeletal skinning, exercised with
//! a hand-built in-memory GLB (a 3-vertex mesh bound to an animated joint) so the
//! parser, accessor decoding, animation sampling and linear-blend skinning are all
//! covered without shipping a binary asset. Also checks renderer integration:
//! a `model3d` node draws a placeholder before bytes arrive, and posed geometry
//! after.

use elpian_vm::bevy_scene::gltf::parse_model;
use elpian_vm::bevy_scene::renderer::SceneRenderer;
use elpian_vm::bevy_scene::schema::SceneDef;

// ── GLB builder ──────────────────────────────────────────────────────

fn push_f32(buf: &mut Vec<u8>, v: f32) {
    buf.extend_from_slice(&v.to_le_bytes());
}
fn push_u16(buf: &mut Vec<u8>, v: u16) {
    buf.extend_from_slice(&v.to_le_bytes());
}

/// Build the binary buffer for a 3-vertex skinned mesh + a 2-keyframe rotation
/// clip on joint 1, returning the bytes. Layout offsets are mirrored in the JSON.
fn build_bin() -> Vec<u8> {
    let mut b = Vec::new();
    // POSITION (off 0): v0=(-1,0,0) v1=(1,0,0) v2=(0,2,0)
    for v in [(-1.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 2.0, 0.0)] {
        push_f32(&mut b, v.0);
        push_f32(&mut b, v.1);
        push_f32(&mut b, v.2);
    }
    // NORMAL (off 36): all +Z
    for _ in 0..3 {
        push_f32(&mut b, 0.0);
        push_f32(&mut b, 0.0);
        push_f32(&mut b, 1.0);
    }
    // JOINTS_0 (off 72): u16 VEC4, every vertex bound to skin joint index 1
    for _ in 0..3 {
        push_u16(&mut b, 1);
        push_u16(&mut b, 0);
        push_u16(&mut b, 0);
        push_u16(&mut b, 0);
    }
    // WEIGHTS_0 (off 96): f32 VEC4 = [1,0,0,0]
    for _ in 0..3 {
        push_f32(&mut b, 1.0);
        push_f32(&mut b, 0.0);
        push_f32(&mut b, 0.0);
        push_f32(&mut b, 0.0);
    }
    // indices (off 144): u16 [0,1,2]
    for i in [0u16, 1, 2] {
        push_u16(&mut b, i);
    }
    // pad to 4-byte alignment (150 -> 152) for the following f32 accessors
    while b.len() % 4 != 0 {
        b.push(0);
    }
    // inverseBindMatrices (off 152): 2 × identity MAT4
    for _ in 0..2 {
        for col in 0..4 {
            for row in 0..4 {
                push_f32(&mut b, if col == row { 1.0 } else { 0.0 });
            }
        }
    }
    // anim input (off 280): times [0.0, 1.0]
    push_f32(&mut b, 0.0);
    push_f32(&mut b, 1.0);
    // anim output (off 288): rotation quats [identity, rotZ 90°]
    // identity
    push_f32(&mut b, 0.0);
    push_f32(&mut b, 0.0);
    push_f32(&mut b, 0.0);
    push_f32(&mut b, 1.0);
    // 90° about Z: (0,0,sin45,cos45)
    let s = (std::f32::consts::FRAC_PI_4).sin();
    let c = (std::f32::consts::FRAC_PI_4).cos();
    push_f32(&mut b, 0.0);
    push_f32(&mut b, 0.0);
    push_f32(&mut b, s);
    push_f32(&mut b, c);
    b
}

fn skinned_gltf_json(bin_len: usize) -> String {
    // Each accessor gets its own bufferView at the offset chosen in build_bin().
    format!(
        r#"{{
        "asset": {{"version":"2.0"}},
        "scene": 0,
        "scenes": [{{"nodes":[0,1,2]}}],
        "nodes": [
            {{"mesh":0,"skin":0}},
            {{"name":"joint0"}},
            {{"name":"joint1"}}
        ],
        "meshes": [{{"primitives":[{{
            "attributes":{{"POSITION":0,"NORMAL":1,"JOINTS_0":2,"WEIGHTS_0":3}},
            "indices":4,"material":0
        }}]}}],
        "materials": [{{"pbrMetallicRoughness":{{"baseColorFactor":[0.2,0.4,0.8,1.0]}},
                        "emissiveFactor":[0.1,0.0,0.0]}}],
        "skins": [{{"inverseBindMatrices":5,"joints":[1,2]}}],
        "animations": [{{"name":"Run",
            "channels":[{{"sampler":0,"target":{{"node":2,"path":"rotation"}}}}],
            "samplers":[{{"input":6,"output":7,"interpolation":"LINEAR"}}]
        }}],
        "buffers": [{{"byteLength":{bin_len}}}],
        "bufferViews": [
            {{"buffer":0,"byteOffset":0,"byteLength":36}},
            {{"buffer":0,"byteOffset":36,"byteLength":36}},
            {{"buffer":0,"byteOffset":72,"byteLength":24}},
            {{"buffer":0,"byteOffset":96,"byteLength":48}},
            {{"buffer":0,"byteOffset":144,"byteLength":6}},
            {{"buffer":0,"byteOffset":152,"byteLength":128}},
            {{"buffer":0,"byteOffset":280,"byteLength":8}},
            {{"buffer":0,"byteOffset":288,"byteLength":32}}
        ],
        "accessors": [
            {{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"}},
            {{"bufferView":1,"componentType":5126,"count":3,"type":"VEC3"}},
            {{"bufferView":2,"componentType":5123,"count":3,"type":"VEC4"}},
            {{"bufferView":3,"componentType":5126,"count":3,"type":"VEC4"}},
            {{"bufferView":4,"componentType":5123,"count":3,"type":"SCALAR"}},
            {{"bufferView":5,"componentType":5126,"count":2,"type":"MAT4"}},
            {{"bufferView":6,"componentType":5126,"count":2,"type":"SCALAR"}},
            {{"bufferView":7,"componentType":5126,"count":2,"type":"VEC4"}}
        ]
    }}"#,
        bin_len = bin_len
    )
}

/// Pack a glTF JSON + binary buffer into a GLB container.
fn pack_glb(json: &str, bin: &[u8]) -> Vec<u8> {
    let mut json_bytes = json.as_bytes().to_vec();
    while json_bytes.len() % 4 != 0 {
        json_bytes.push(b' ');
    }
    let mut bin_bytes = bin.to_vec();
    while bin_bytes.len() % 4 != 0 {
        bin_bytes.push(0);
    }
    let total = 12 + 8 + json_bytes.len() + 8 + bin_bytes.len();

    let mut out = Vec::with_capacity(total);
    out.extend_from_slice(&0x4654_6C67u32.to_le_bytes()); // magic "glTF"
    out.extend_from_slice(&2u32.to_le_bytes()); // version
    out.extend_from_slice(&(total as u32).to_le_bytes());
    // JSON chunk
    out.extend_from_slice(&(json_bytes.len() as u32).to_le_bytes());
    out.extend_from_slice(&0x4E4F_534Au32.to_le_bytes()); // "JSON"
    out.extend_from_slice(&json_bytes);
    // BIN chunk
    out.extend_from_slice(&(bin_bytes.len() as u32).to_le_bytes());
    out.extend_from_slice(&0x004E_4942u32.to_le_bytes()); // "BIN\0"
    out.extend_from_slice(&bin_bytes);
    out
}

fn build_skinned_glb() -> Vec<u8> {
    let bin = build_bin();
    let json = skinned_gltf_json(bin.len());
    pack_glb(&json, &bin)
}

// ── Tests ────────────────────────────────────────────────────────────

#[test]
fn parses_glb_container_and_material() {
    let glb = build_skinned_glb();
    let model = parse_model(&glb).expect("GLB should parse");
    assert_eq!(model.animation_count(), 1);
    assert_eq!(model.animation_index_by_name("run"), Some(0)); // case-insensitive

    // Bind pose (no anim): one primitive, one triangle with the source positions.
    let posed = model.pose(None, 0.0);
    assert_eq!(posed.len(), 1);
    let prim = &posed[0];
    assert_eq!(prim.triangles.len(), 1);
    // base_color factor from the material.
    assert!((prim.base_color.x - 0.2).abs() < 1e-4);
    assert!((prim.base_color.z - 0.8).abs() < 1e-4);
}

#[test]
fn skinning_rotates_vertices_with_the_joint() {
    let glb = build_skinned_glb();
    let model = parse_model(&glb).expect("GLB should parse");

    // At t=0 the animated joint is identity → vertex 1 stays at (1,0,0).
    let at0 = model.pose(Some(0), 0.0);
    let t0 = &at0[0].triangles[0];
    assert!((t0.v1.x - 1.0).abs() < 1e-3, "t0 v1.x = {}", t0.v1.x);
    assert!(t0.v1.y.abs() < 1e-3, "t0 v1.y = {}", t0.v1.y);

    // Near the end of the 1s clip the joint has rotated ~81° about Z, swinging
    // (1,0,0) up toward (0,1,0). (t=1.0 exactly would loop back to the start.)
    let at1 = model.pose(Some(0), 0.9);
    let t1 = &at1[0].triangles[0];
    assert!(t1.v1.x < 0.3, "t1 v1.x = {}", t1.v1.x);
    assert!(t1.v1.y > 0.85, "t1 v1.y = {}", t1.v1.y);

    // Halfway the vertex should be partway through the arc (slerp), distinct from
    // both endpoints, with the radius roughly preserved.
    let mid = model.pose(Some(0), 0.5);
    let tm = &mid[0].triangles[0];
    let r = (tm.v1.x * tm.v1.x + tm.v1.y * tm.v1.y).sqrt();
    assert!((r - 1.0).abs() < 1e-2, "rotation should preserve radius: r={r}");
    assert!(tm.v1.x > 0.05 && tm.v1.y > 0.05, "midpoint should be on the arc");
}

#[test]
fn renderer_draws_placeholder_then_posed_model() {
    // A model3d node referencing bytes that haven't been fed yet → placeholder
    // capsule still renders something; after feeding the GLB it renders the model.
    let scene_json = r#"{"world":[
        {"type":"camera","transform":{"position":{"x":0,"y":1,"z":6}}},
        {"type":"light","light_type":"Directional","intensity":1.0,
         "transform":{"position":{"x":1,"y":4,"z":3}}},
        {"type":"model3d","model":"hero.glb","anim_time":1.0,
         "tint":{"r":0.9,"g":0.5,"b":0.2},
         "transform":{"position":{"x":0,"y":0,"z":0},"scale":{"x":2,"y":2,"z":2}}}
    ]}"#;
    let scene: SceneDef = serde_json::from_str(scene_json).expect("scene parses");

    let mut r = SceneRenderer::new(96, 96);
    // Before feeding: placeholder capsule must paint some non-background pixels.
    r.render_scene(&scene, 1.0 / 60.0);
    let placeholder_lit = lit_pixels(&r.pixels);
    assert!(placeholder_lit > 50, "placeholder capsule should render");

    // Feed the model bytes, then render: posed geometry should paint pixels too.
    let glb = build_skinned_glb();
    assert!(r.load_model_bytes("hero.glb".to_string(), &glb), "bytes should decode");
    assert!(r.has_model("hero.glb"));
    r.render_scene(&scene, 1.0 / 60.0);
    let model_lit = lit_pixels(&r.pixels);
    assert!(model_lit > 20, "posed model should render some geometry");
}

/// Count pixels that differ from the dark clear background.
fn lit_pixels(px: &[u8]) -> usize {
    px.chunks_exact(4)
        .filter(|p| p[0] > 40 || p[1] > 40 || p[2] > 50)
        .count()
}

#[test]
fn animation_selectable_by_index_and_name() {
    let glb = build_skinned_glb();
    let model = parse_model(&glb).expect("GLB should parse");
    // Selecting by name and by index 0 must pose identically.
    let by_name = model.animation_index_by_name("Run").unwrap();
    assert_eq!(by_name, 0);
    let a = model.pose(Some(0), 1.0);
    let b = model.pose(Some(by_name), 1.0);
    assert!((a[0].triangles[0].v1.y - b[0].triangles[0].v1.y).abs() < 1e-6);
}
