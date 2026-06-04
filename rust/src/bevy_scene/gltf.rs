//! Minimal glTF 2.0 / GLB loader with CPU linear-blend skeletal skinning.
//!
//! This is a dependency-light decoder (only `serde_json` + `glam` + std) used by
//! the software renderer to draw streamed `model3d` characters/vehicles in the
//! Bevy scene path, at parity with the scene3d glTF pipeline. It supports:
//!
//! - The binary **GLB** container (JSON chunk + BIN chunk) and self-contained
//!   glTF with an embedded base64 `data:` buffer URI.
//! - Accessor / bufferView decoding for POSITION, NORMAL, TEXCOORD_0, JOINTS_0,
//!   WEIGHTS_0 and indices (i8/u8/i16/u16/u32/f32 component types).
//! - The node hierarchy, skins (inverse-bind matrices) and animation channels
//!   (translation/rotation/scale) sampled with STEP or LINEAR interpolation.
//! - CPU linear-blend skinning to produce posed, world-relative triangles per
//!   frame for a given animation clip + time.
//!
//! Embedded image textures are **not** decoded here (that needs a PNG/JPEG
//! decoder); models are drawn with their glTF `baseColorFactor` (× the node
//! `tint`) and `emissiveFactor`, which is enough for the TPS characters to read
//! correctly. Texture image support can layer on later without changing callers.

use std::collections::HashMap;

use glam::{Mat4, Quat, Vec3};
use serde::Deserialize;

use crate::bevy_scene::renderer::Triangle;

// ── Public decoded model ─────────────────────────────────────────────

/// A fully decoded glTF model, ready to be posed each frame.
pub struct GltfModel {
    nodes: Vec<DecNode>,
    roots: Vec<usize>,
    meshes: Vec<DecMesh>,
    skins: Vec<DecSkin>,
    animations: Vec<DecAnim>,
}

/// One posed primitive: world-relative triangles plus its flat material color.
pub struct PosedPrimitive {
    pub triangles: Vec<Triangle>,
    pub base_color: Vec3,
    pub emissive: Vec3,
}

struct DecNode {
    translation: Vec3,
    rotation: Quat,
    scale: Vec3,
    children: Vec<usize>,
    mesh: Option<usize>,
    skin: Option<usize>,
}

struct DecMesh {
    primitives: Vec<DecPrimitive>,
}

struct DecPrimitive {
    positions: Vec<Vec3>,
    normals: Vec<Vec3>,
    uvs: Vec<[f32; 2]>,
    joints: Vec<[u32; 4]>,
    weights: Vec<[f32; 4]>,
    indices: Vec<u32>,
    base_color: Vec3,
    emissive: Vec3,
}

struct DecSkin {
    joints: Vec<usize>,
    inverse_bind: Vec<Mat4>,
}

#[derive(Clone, Copy, PartialEq)]
enum Path {
    Translation,
    Rotation,
    Scale,
}

#[derive(Clone, Copy, PartialEq)]
enum Interp {
    Step,
    Linear,
}

struct AnimSampler {
    input: Vec<f32>,
    /// Flattened output values (3 per T/S keyframe, 4 per rotation keyframe).
    output: Vec<f32>,
    interp: Interp,
}

struct AnimChannel {
    node: usize,
    path: Path,
    sampler: usize,
}

struct DecAnim {
    name: Option<String>,
    channels: Vec<AnimChannel>,
    samplers: Vec<AnimSampler>,
    duration: f32,
}

impl GltfModel {
    /// Number of animation clips.
    pub fn animation_count(&self) -> usize {
        self.animations.len()
    }

    /// Resolve an animation clip name to its index (case-insensitive).
    pub fn animation_index_by_name(&self, name: &str) -> Option<usize> {
        self.animations
            .iter()
            .position(|a| a.name.as_deref().map(|n| n.eq_ignore_ascii_case(name)).unwrap_or(false))
    }

    /// Pose the model for the given animation clip + time, returning posed
    /// primitives in model space (the caller applies the node world transform).
    /// `anim` out of range or `None` yields the bind pose.
    pub fn pose(&self, anim: Option<usize>, time: f32) -> Vec<PosedPrimitive> {
        // Per-node local TRS, seeded from the bind pose then overridden by the
        // sampled animation channels.
        let mut translations: Vec<Vec3> = self.nodes.iter().map(|n| n.translation).collect();
        let mut rotations: Vec<Quat> = self.nodes.iter().map(|n| n.rotation).collect();
        let mut scales: Vec<Vec3> = self.nodes.iter().map(|n| n.scale).collect();

        if let Some(ai) = anim {
            if let Some(clip) = self.animations.get(ai) {
                let t = if clip.duration > 0.0 {
                    time.rem_euclid(clip.duration)
                } else {
                    0.0
                };
                for ch in &clip.channels {
                    let s = &clip.samplers[ch.sampler];
                    match ch.path {
                        Path::Translation => {
                            translations[ch.node] = sample_vec3(s, t);
                        }
                        Path::Scale => {
                            scales[ch.node] = sample_vec3(s, t);
                        }
                        Path::Rotation => {
                            rotations[ch.node] = sample_quat(s, t);
                        }
                    }
                }
            }
        }

        // Local matrices, then global matrices via a hierarchy walk from the roots.
        let local: Vec<Mat4> = (0..self.nodes.len())
            .map(|i| Mat4::from_scale_rotation_translation(scales[i], rotations[i], translations[i]))
            .collect();
        let mut global = vec![Mat4::IDENTITY; self.nodes.len()];
        let mut visited = vec![false; self.nodes.len()];
        for &r in &self.roots {
            self.accumulate_global(r, &Mat4::IDENTITY, &local, &mut global, &mut visited);
        }

        // Emit posed primitives for every mesh-bearing node.
        let mut out = Vec::new();
        for (ni, node) in self.nodes.iter().enumerate() {
            let Some(mesh_idx) = node.mesh else { continue };
            let Some(mesh) = self.meshes.get(mesh_idx) else { continue };

            // Joint matrices for the skin bound to this node (if any).
            let joint_mats: Option<Vec<Mat4>> = node.skin.and_then(|si| self.skins.get(si)).map(|skin| {
                skin.joints
                    .iter()
                    .enumerate()
                    .map(|(j, &jn)| global[jn] * skin.inverse_bind[j])
                    .collect()
            });

            for prim in &mesh.primitives {
                let posed = pose_primitive(prim, &global[ni], joint_mats.as_deref());
                out.push(posed);
            }
        }
        out
    }

    fn accumulate_global(
        &self,
        node: usize,
        parent: &Mat4,
        local: &[Mat4],
        global: &mut [Mat4],
        visited: &mut [bool],
    ) {
        if visited[node] {
            return; // guard against malformed cyclic hierarchies
        }
        visited[node] = true;
        let g = *parent * local[node];
        global[node] = g;
        for &c in &self.nodes[node].children {
            self.accumulate_global(c, &g, local, global, visited);
        }
    }
}

/// Skin/transform one primitive into posed triangles.
fn pose_primitive(prim: &DecPrimitive, node_global: &Mat4, joints: Option<&[Mat4]>) -> PosedPrimitive {
    let vcount = prim.positions.len();
    let mut posed_pos = Vec::with_capacity(vcount);
    let mut posed_nrm = Vec::with_capacity(vcount);

    let skinned = joints.is_some() && !prim.joints.is_empty() && !prim.weights.is_empty();

    for v in 0..vcount {
        let p = prim.positions[v];
        let n = prim.normals.get(v).copied().unwrap_or(Vec3::Y);
        if skinned {
            let js = prim.joints[v];
            let ws = prim.weights[v];
            let jm = joints.unwrap();
            let mut skin_mat = Mat4::ZERO;
            let mut total = 0.0;
            for i in 0..4 {
                let w = ws[i];
                if w <= 0.0 {
                    continue;
                }
                if let Some(m) = jm.get(js[i] as usize) {
                    skin_mat += mat4_scale(m, w);
                    total += w;
                }
            }
            // Fall back to the node transform if weights were empty/degenerate.
            let m = if total > 0.0 { skin_mat } else { *node_global };
            posed_pos.push(m.transform_point3(p));
            posed_nrm.push(mat3_transform(&m, n).normalize_or_zero());
        } else {
            posed_pos.push(node_global.transform_point3(p));
            posed_nrm.push(mat3_transform(node_global, n).normalize_or_zero());
        }
    }

    // Build triangles from indices (or sequential triples).
    let mut triangles = Vec::new();
    let push_tri = |tris: &mut Vec<Triangle>, a: usize, b: usize, c: usize| {
        if a >= vcount || b >= vcount || c >= vcount {
            return;
        }
        let na = posed_nrm[a];
        let nb = posed_nrm[b];
        let nc = posed_nrm[c];
        let mut n = (na + nb + nc) / 3.0;
        if n.length_squared() < 1e-8 {
            // Derive a geometric normal if vertex normals were absent/zero.
            n = (posed_pos[b] - posed_pos[a])
                .cross(posed_pos[c] - posed_pos[a])
                .normalize_or_zero();
        } else {
            n = n.normalize_or_zero();
        }
        let uv = |i: usize| {
            prim.uvs
                .get(i)
                .map(|u| glam::Vec2::new(u[0], u[1]))
                .unwrap_or(glam::Vec2::ZERO)
        };
        tris.push(Triangle::new_uv(
            posed_pos[a],
            posed_pos[b],
            posed_pos[c],
            n,
            uv(a),
            uv(b),
            uv(c),
        ));
    };

    if prim.indices.is_empty() {
        let mut i = 0;
        while i + 2 < vcount {
            push_tri(&mut triangles, i, i + 1, i + 2);
            i += 3;
        }
    } else {
        let mut i = 0;
        while i + 2 < prim.indices.len() {
            push_tri(
                &mut triangles,
                prim.indices[i] as usize,
                prim.indices[i + 1] as usize,
                prim.indices[i + 2] as usize,
            );
            i += 3;
        }
    }

    PosedPrimitive {
        triangles,
        base_color: prim.base_color,
        emissive: prim.emissive,
    }
}

#[inline]
fn mat4_scale(m: &Mat4, s: f32) -> Mat4 {
    Mat4::from_cols(
        m.x_axis * s,
        m.y_axis * s,
        m.z_axis * s,
        m.w_axis * s,
    )
}

/// Transform a direction by the upper-left 3×3 of a matrix (ignores translation).
#[inline]
fn mat3_transform(m: &Mat4, v: Vec3) -> Vec3 {
    Vec3::new(
        m.x_axis.x * v.x + m.y_axis.x * v.y + m.z_axis.x * v.z,
        m.x_axis.y * v.x + m.y_axis.y * v.y + m.z_axis.y * v.z,
        m.x_axis.z * v.x + m.y_axis.z * v.y + m.z_axis.z * v.z,
    )
}

// ── Animation sampling ───────────────────────────────────────────────

/// Find the keyframe interval for `t` and return (i0, i1, frac).
fn key_interval(times: &[f32], t: f32) -> (usize, usize, f32) {
    if times.is_empty() {
        return (0, 0, 0.0);
    }
    if t <= times[0] {
        return (0, 0, 0.0);
    }
    let last = times.len() - 1;
    if t >= times[last] {
        return (last, last, 0.0);
    }
    // Linear scan (clips are short); find first time > t.
    let mut i1 = 1;
    while i1 < times.len() && times[i1] < t {
        i1 += 1;
    }
    let i0 = i1 - 1;
    let span = (times[i1] - times[i0]).max(1e-8);
    let frac = ((t - times[i0]) / span).clamp(0.0, 1.0);
    (i0, i1, frac)
}

fn sample_vec3(s: &AnimSampler, t: f32) -> Vec3 {
    let (i0, i1, frac) = key_interval(&s.input, t);
    let a = vec3_at(&s.output, i0);
    if s.interp == Interp::Step || i0 == i1 {
        return a;
    }
    let b = vec3_at(&s.output, i1);
    a.lerp(b, frac)
}

fn sample_quat(s: &AnimSampler, t: f32) -> Quat {
    let (i0, i1, frac) = key_interval(&s.input, t);
    let a = quat_at(&s.output, i0);
    if s.interp == Interp::Step || i0 == i1 {
        return a.normalize();
    }
    let b = quat_at(&s.output, i1);
    a.slerp(b, frac).normalize()
}

#[inline]
fn vec3_at(out: &[f32], i: usize) -> Vec3 {
    let b = i * 3;
    if b + 2 < out.len() {
        Vec3::new(out[b], out[b + 1], out[b + 2])
    } else {
        Vec3::ZERO
    }
}

#[inline]
fn quat_at(out: &[f32], i: usize) -> Quat {
    let b = i * 4;
    if b + 3 < out.len() {
        Quat::from_xyzw(out[b], out[b + 1], out[b + 2], out[b + 3])
    } else {
        Quat::IDENTITY
    }
}

// ── glTF JSON schema (subset) ────────────────────────────────────────

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct GltfJson {
    #[serde(default)]
    buffers: Vec<GBuffer>,
    #[serde(default)]
    buffer_views: Vec<GBufferView>,
    #[serde(default)]
    accessors: Vec<GAccessor>,
    #[serde(default)]
    meshes: Vec<GMesh>,
    #[serde(default)]
    materials: Vec<GMaterial>,
    #[serde(default)]
    nodes: Vec<GNode>,
    #[serde(default)]
    skins: Vec<GSkin>,
    #[serde(default)]
    animations: Vec<GAnimation>,
    #[serde(default)]
    scenes: Vec<GScene>,
    #[serde(default)]
    scene: Option<usize>,
}

#[derive(Deserialize)]
struct GBuffer {
    #[serde(default)]
    uri: Option<String>,
    #[serde(rename = "byteLength", default)]
    _byte_length: usize,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct GBufferView {
    buffer: usize,
    #[serde(default)]
    byte_offset: usize,
    // Present in every real bufferView; we bounds-check against the buffer slice
    // directly, so it's parsed but not otherwise consulted.
    #[allow(dead_code)]
    byte_length: usize,
    #[serde(default)]
    byte_stride: Option<usize>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct GAccessor {
    #[serde(default)]
    buffer_view: Option<usize>,
    #[serde(default)]
    byte_offset: usize,
    component_type: u32,
    count: usize,
    #[serde(rename = "type")]
    kind: String,
    #[serde(default)]
    normalized: bool,
}

#[derive(Deserialize)]
struct GMesh {
    #[serde(default)]
    primitives: Vec<GPrimitive>,
}

#[derive(Deserialize)]
struct GPrimitive {
    #[serde(default)]
    attributes: HashMap<String, usize>,
    #[serde(default)]
    indices: Option<usize>,
    #[serde(default)]
    material: Option<usize>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct GMaterial {
    #[serde(default)]
    pbr_metallic_roughness: Option<GPbr>,
    #[serde(default)]
    emissive_factor: Option<[f32; 3]>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct GPbr {
    #[serde(default)]
    base_color_factor: Option<[f32; 4]>,
}

#[derive(Deserialize)]
struct GNode {
    #[serde(default)]
    mesh: Option<usize>,
    #[serde(default)]
    skin: Option<usize>,
    #[serde(default)]
    children: Vec<usize>,
    #[serde(default)]
    translation: Option<[f32; 3]>,
    #[serde(default)]
    rotation: Option<[f32; 4]>,
    #[serde(default)]
    scale: Option<[f32; 3]>,
    #[serde(default)]
    matrix: Option<[f32; 16]>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct GSkin {
    #[serde(default)]
    inverse_bind_matrices: Option<usize>,
    #[serde(default)]
    joints: Vec<usize>,
}

#[derive(Deserialize)]
struct GAnimation {
    #[serde(default)]
    name: Option<String>,
    #[serde(default)]
    channels: Vec<GChannel>,
    #[serde(default)]
    samplers: Vec<GSampler>,
}

#[derive(Deserialize)]
struct GChannel {
    sampler: usize,
    target: GTarget,
}

#[derive(Deserialize)]
struct GTarget {
    #[serde(default)]
    node: Option<usize>,
    path: String,
}

#[derive(Deserialize)]
struct GSampler {
    input: usize,
    output: usize,
    #[serde(default)]
    interpolation: Option<String>,
}

#[derive(Deserialize)]
struct GScene {
    #[serde(default)]
    nodes: Vec<usize>,
}

// ── Parsing ──────────────────────────────────────────────────────────

const GLB_MAGIC: u32 = 0x4654_6C67; // "glTF"
const CHUNK_JSON: u32 = 0x4E4F_534A; // "JSON"
const CHUNK_BIN: u32 = 0x004E_4942; // "BIN\0"

/// Parse a model from either a GLB container or a JSON glTF with an embedded
/// base64 buffer. Returns `None` on any structural error (caller draws a capsule).
pub fn parse_model(bytes: &[u8]) -> Option<GltfModel> {
    let (json_bytes, bin) = if bytes.len() >= 12 && le_u32(bytes, 0) == GLB_MAGIC {
        split_glb(bytes)?
    } else {
        // Plain .gltf JSON; buffers must be embedded as data URIs.
        (bytes.to_vec(), Vec::new())
    };

    let json: GltfJson = serde_json::from_slice(&json_bytes).ok()?;
    decode(json, bin)
}

/// Split a GLB into (JSON chunk bytes, BIN chunk bytes).
fn split_glb(bytes: &[u8]) -> Option<(Vec<u8>, Vec<u8>)> {
    // Header: magic(4) version(4) length(4)
    let total = le_u32(bytes, 8) as usize;
    let end = total.min(bytes.len());
    let mut off = 12;
    let mut json = Vec::new();
    let mut bin = Vec::new();
    while off + 8 <= end {
        let clen = le_u32(bytes, off) as usize;
        let ctype = le_u32(bytes, off + 4);
        let dstart = off + 8;
        let dend = dstart.checked_add(clen)?;
        if dend > bytes.len() {
            break;
        }
        match ctype {
            CHUNK_JSON => json = bytes[dstart..dend].to_vec(),
            CHUNK_BIN => bin = bytes[dstart..dend].to_vec(),
            _ => {}
        }
        // Chunks are 4-byte aligned.
        off = dend + ((4 - (clen % 4)) % 4);
    }
    if json.is_empty() {
        return None;
    }
    Some((json, bin))
}

/// Resolve the byte storage for every buffer (BIN chunk for buffer 0, or a
/// base64 `data:` URI). Buffers we can't resolve become empty.
fn resolve_buffers(buffers: &[GBuffer], bin: Vec<u8>) -> Vec<Vec<u8>> {
    let mut out = Vec::with_capacity(buffers.len());
    for (i, b) in buffers.iter().enumerate() {
        match &b.uri {
            None if i == 0 => out.push(bin.clone()),
            Some(uri) if uri.starts_with("data:") => {
                out.push(decode_data_uri(uri).unwrap_or_default());
            }
            _ => out.push(Vec::new()),
        }
    }
    if buffers.is_empty() && !bin.is_empty() {
        out.push(bin);
    }
    out
}

fn decode_data_uri(uri: &str) -> Option<Vec<u8>> {
    use base64::Engine;
    let comma = uri.find(',')?;
    let payload = &uri[comma + 1..];
    base64::engine::general_purpose::STANDARD.decode(payload).ok()
}

fn decode(json: GltfJson, bin: Vec<u8>) -> Option<GltfModel> {
    let buffers = resolve_buffers(&json.buffers, bin);

    // Decode nodes (TRS or matrix).
    let nodes: Vec<DecNode> = json
        .nodes
        .iter()
        .map(|n| {
            let (t, r, s) = if let Some(m) = n.matrix {
                let mat = Mat4::from_cols_array(&m);
                let (s, r, t) = mat.to_scale_rotation_translation();
                (t, r, s)
            } else {
                (
                    n.translation.map(Vec3::from).unwrap_or(Vec3::ZERO),
                    n.rotation
                        .map(|q| Quat::from_xyzw(q[0], q[1], q[2], q[3]).normalize())
                        .unwrap_or(Quat::IDENTITY),
                    n.scale.map(Vec3::from).unwrap_or(Vec3::ONE),
                )
            };
            DecNode {
                translation: t,
                rotation: r,
                scale: s,
                children: n.children.clone(),
                mesh: n.mesh,
                skin: n.skin,
            }
        })
        .collect();

    // Roots: explicit scene, else any node that isn't someone's child.
    let roots = scene_roots(&json, &nodes);

    // Decode meshes/primitives into flat vertex arrays.
    let meshes: Vec<DecMesh> = json
        .meshes
        .iter()
        .map(|m| DecMesh {
            primitives: m
                .primitives
                .iter()
                .map(|p| decode_primitive(&json, &buffers, p))
                .collect(),
        })
        .collect();

    // Decode skins.
    let skins: Vec<DecSkin> = json
        .skins
        .iter()
        .map(|sk| {
            let inverse_bind = sk
                .inverse_bind_matrices
                .map(|acc| read_mat4(&json, &buffers, acc))
                .unwrap_or_else(|| vec![Mat4::IDENTITY; sk.joints.len()]);
            DecSkin {
                joints: sk.joints.clone(),
                inverse_bind,
            }
        })
        .collect();

    // Decode animations.
    let animations: Vec<DecAnim> = json
        .animations
        .iter()
        .map(|a| decode_animation(&json, &buffers, a))
        .collect();

    Some(GltfModel {
        nodes,
        roots,
        meshes,
        skins,
        animations,
    })
}

fn scene_roots(json: &GltfJson, nodes: &[DecNode]) -> Vec<usize> {
    if let Some(si) = json.scene {
        if let Some(s) = json.scenes.get(si) {
            return s.nodes.clone();
        }
    }
    if let Some(s) = json.scenes.first() {
        if !s.nodes.is_empty() {
            return s.nodes.clone();
        }
    }
    // Fallback: nodes that are not referenced as a child.
    let mut is_child = vec![false; nodes.len()];
    for n in nodes {
        for &c in &n.children {
            if c < is_child.len() {
                is_child[c] = true;
            }
        }
    }
    (0..nodes.len()).filter(|&i| !is_child[i]).collect()
}

fn decode_primitive(json: &GltfJson, buffers: &[Vec<u8>], p: &GPrimitive) -> DecPrimitive {
    let positions = p
        .attributes
        .get("POSITION")
        .map(|&a| read_vec3(json, buffers, a))
        .unwrap_or_default();
    let normals = p
        .attributes
        .get("NORMAL")
        .map(|&a| read_vec3(json, buffers, a))
        .unwrap_or_default();
    let uvs = p
        .attributes
        .get("TEXCOORD_0")
        .map(|&a| read_vec2(json, buffers, a))
        .unwrap_or_default();
    let joints = p
        .attributes
        .get("JOINTS_0")
        .map(|&a| read_u32x4(json, buffers, a))
        .unwrap_or_default();
    let weights = p
        .attributes
        .get("WEIGHTS_0")
        .map(|&a| read_vec4(json, buffers, a))
        .unwrap_or_default();
    let indices = p
        .indices
        .map(|a| read_indices(json, buffers, a))
        .unwrap_or_default();

    // Material factors (base color × node tint applied later; emissive here).
    let (base_color, emissive) = p
        .material
        .and_then(|mi| json.materials.get(mi))
        .map(|m| {
            let base = m
                .pbr_metallic_roughness
                .as_ref()
                .and_then(|p| p.base_color_factor)
                .map(|c| Vec3::new(c[0], c[1], c[2]))
                .unwrap_or(Vec3::new(0.8, 0.8, 0.8));
            let emi = m
                .emissive_factor
                .map(Vec3::from)
                .unwrap_or(Vec3::ZERO);
            (base, emi)
        })
        .unwrap_or((Vec3::new(0.8, 0.8, 0.8), Vec3::ZERO));

    DecPrimitive {
        positions,
        normals,
        uvs,
        joints,
        weights,
        indices,
        base_color,
        emissive,
    }
}

fn decode_animation(json: &GltfJson, buffers: &[Vec<u8>], a: &GAnimation) -> DecAnim {
    let samplers: Vec<AnimSampler> = a
        .samplers
        .iter()
        .map(|s| {
            let input = read_scalar_f32(json, buffers, s.input);
            let output = read_raw_f32(json, buffers, s.output);
            let interp = match s.interpolation.as_deref() {
                Some("STEP") => Interp::Step,
                _ => Interp::Linear, // LINEAR (and CUBICSPLINE → treated as linear)
            };
            AnimSampler {
                input,
                output,
                interp,
            }
        })
        .collect();

    let channels: Vec<AnimChannel> = a
        .channels
        .iter()
        .filter_map(|c| {
            let node = c.target.node?;
            let path = match c.target.path.as_str() {
                "translation" => Path::Translation,
                "rotation" => Path::Rotation,
                "scale" => Path::Scale,
                _ => return None, // weights morph targets unsupported
            };
            Some(AnimChannel {
                node,
                path,
                sampler: c.sampler,
            })
        })
        .collect();

    let duration = samplers
        .iter()
        .filter_map(|s| s.input.last().copied())
        .fold(0.0_f32, f32::max);

    DecAnim {
        name: a.name.clone(),
        channels,
        samplers,
        duration,
    }
}

// ── Accessor decoding ────────────────────────────────────────────────

fn component_size(component_type: u32) -> usize {
    match component_type {
        5120 | 5121 => 1, // i8 / u8
        5122 | 5123 => 2, // i16 / u16
        5125 | 5126 => 4, // u32 / f32
        _ => 0,
    }
}

fn type_component_count(kind: &str) -> usize {
    match kind {
        "SCALAR" => 1,
        "VEC2" => 2,
        "VEC3" => 3,
        "VEC4" => 4,
        "MAT4" => 16,
        _ => 0,
    }
}

/// Iterate an accessor's elements, yielding each element's raw component slice
/// position. Calls `f(element_index, component_index, value_f32)`.
fn read_accessor_components(
    json: &GltfJson,
    buffers: &[Vec<u8>],
    accessor_idx: usize,
    mut f: impl FnMut(usize, usize, f32),
) -> Option<(usize, usize)> {
    let acc = json.accessors.get(accessor_idx)?;
    let comps = type_component_count(&acc.kind);
    let csize = component_size(acc.component_type);
    if comps == 0 || csize == 0 {
        return None;
    }
    let view_idx = acc.buffer_view?;
    let view = json.buffer_views.get(view_idx)?;
    let buf = buffers.get(view.buffer)?;
    let elem_size = comps * csize;
    let stride = view.byte_stride.unwrap_or(elem_size);
    let base = view.byte_offset + acc.byte_offset;

    for e in 0..acc.count {
        let elem_off = base + e * stride;
        for c in 0..comps {
            let off = elem_off + c * csize;
            if off + csize > buf.len() {
                return Some((acc.count, comps));
            }
            let val = decode_component(&buf[off..off + csize], acc.component_type, acc.normalized);
            f(e, c, val);
        }
    }
    Some((acc.count, comps))
}

fn decode_component(bytes: &[u8], component_type: u32, normalized: bool) -> f32 {
    match component_type {
        5126 => f32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]),
        5125 => u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]) as f32,
        5123 => {
            let v = u16::from_le_bytes([bytes[0], bytes[1]]);
            if normalized {
                v as f32 / 65535.0
            } else {
                v as f32
            }
        }
        5122 => {
            let v = i16::from_le_bytes([bytes[0], bytes[1]]);
            if normalized {
                (v as f32 / 32767.0).max(-1.0)
            } else {
                v as f32
            }
        }
        5121 => {
            let v = bytes[0];
            if normalized {
                v as f32 / 255.0
            } else {
                v as f32
            }
        }
        5120 => {
            let v = bytes[0] as i8;
            if normalized {
                (v as f32 / 127.0).max(-1.0)
            } else {
                v as f32
            }
        }
        _ => 0.0,
    }
}

fn read_vec3(json: &GltfJson, buffers: &[Vec<u8>], acc: usize) -> Vec<Vec3> {
    let mut out: Vec<Vec3> = Vec::new();
    read_accessor_components(json, buffers, acc, |e, c, v| {
        if out.len() <= e {
            out.resize(e + 1, Vec3::ZERO);
        }
        match c {
            0 => out[e].x = v,
            1 => out[e].y = v,
            2 => out[e].z = v,
            _ => {}
        }
    });
    out
}

fn read_vec2(json: &GltfJson, buffers: &[Vec<u8>], acc: usize) -> Vec<[f32; 2]> {
    let mut out: Vec<[f32; 2]> = Vec::new();
    read_accessor_components(json, buffers, acc, |e, c, v| {
        if out.len() <= e {
            out.resize(e + 1, [0.0; 2]);
        }
        if c < 2 {
            out[e][c] = v;
        }
    });
    out
}

fn read_vec4(json: &GltfJson, buffers: &[Vec<u8>], acc: usize) -> Vec<[f32; 4]> {
    let mut out: Vec<[f32; 4]> = Vec::new();
    read_accessor_components(json, buffers, acc, |e, c, v| {
        if out.len() <= e {
            out.resize(e + 1, [0.0; 4]);
        }
        if c < 4 {
            out[e][c] = v;
        }
    });
    out
}

fn read_u32x4(json: &GltfJson, buffers: &[Vec<u8>], acc: usize) -> Vec<[u32; 4]> {
    let mut out: Vec<[u32; 4]> = Vec::new();
    read_accessor_components(json, buffers, acc, |e, c, v| {
        if out.len() <= e {
            out.resize(e + 1, [0; 4]);
        }
        if c < 4 {
            out[e][c] = v as u32;
        }
    });
    out
}

fn read_scalar_f32(json: &GltfJson, buffers: &[Vec<u8>], acc: usize) -> Vec<f32> {
    let mut out: Vec<f32> = Vec::new();
    read_accessor_components(json, buffers, acc, |e, _c, v| {
        if out.len() <= e {
            out.resize(e + 1, 0.0);
        }
        out[e] = v;
    });
    out
}

/// Read all components of an accessor flattened (used for animation outputs).
fn read_raw_f32(json: &GltfJson, buffers: &[Vec<u8>], acc: usize) -> Vec<f32> {
    let comps = json
        .accessors
        .get(acc)
        .map(|a| type_component_count(&a.kind))
        .unwrap_or(0);
    let mut out: Vec<f32> = Vec::new();
    read_accessor_components(json, buffers, acc, |e, c, v| {
        let idx = e * comps + c;
        if out.len() <= idx {
            out.resize(idx + 1, 0.0);
        }
        out[idx] = v;
    });
    out
}

fn read_indices(json: &GltfJson, buffers: &[Vec<u8>], acc: usize) -> Vec<u32> {
    let mut out: Vec<u32> = Vec::new();
    read_accessor_components(json, buffers, acc, |e, _c, v| {
        if out.len() <= e {
            out.resize(e + 1, 0);
        }
        out[e] = v as u32;
    });
    out
}

fn read_mat4(json: &GltfJson, buffers: &[Vec<u8>], acc: usize) -> Vec<Mat4> {
    let mut flat: Vec<f32> = Vec::new();
    read_accessor_components(json, buffers, acc, |e, c, v| {
        let idx = e * 16 + c;
        if flat.len() <= idx {
            flat.resize(idx + 1, 0.0);
        }
        flat[idx] = v;
    });
    flat.chunks_exact(16)
        .map(|c| {
            let mut arr = [0.0_f32; 16];
            arr.copy_from_slice(c);
            Mat4::from_cols_array(&arr)
        })
        .collect()
}

#[inline]
fn le_u32(b: &[u8], off: usize) -> u32 {
    u32::from_le_bytes([b[off], b[off + 1], b[off + 2], b[off + 3]])
}
