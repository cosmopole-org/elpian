//! Software 3D rasterizer that renders JSON scenes to RGBA pixel buffers.
//!
//! This renderer uses Bevy-compatible math (glam) and the same JSON schema
//! as the main Bevy renderer. It provides cross-platform 3D rendering that
//! works on all Flutter targets (mobile, desktop, web) without requiring
//! GPU context sharing between Bevy and Flutter.
//!
//! The renderer implements:
//! - Perspective and orthographic camera projection
//! - Triangle rasterization with depth buffering
//! - PBR-inspired material shading (Blinn-Phong approximation)
//! - Point, directional, and spot lights
//! - Transform hierarchies
//! - Basic mesh generation (cube, sphere, plane, cylinder, etc.)
//! - Animation support (rotate, translate, scale, bounce, pulse)
//! - Particle system rendering
//! - Environment settings (ambient light, fog)

use std::collections::HashMap;
use std::sync::Arc;

use glam::{Mat4, Vec2, Vec3, Vec4};

use crate::bevy_scene::gltf::{self, GltfModel};
use crate::bevy_scene::schema::*;

// ── Renderer Core ────────────────────────────────────────────────────

pub struct SceneRenderer {
    pub width: u32,
    pub height: u32,
    /// Front buffer: the last fully-rendered frame (RGBA8, len = width*height*4).
    /// This is what readers (FFI/manager) see; the next frame renders into
    /// `pixels_back` and the two are swapped at the end of `render_scene`, so a
    /// pointer handed out via `get_frame_data` stays valid for the whole next
    /// frame (double-buffering — prerequisite for the F1 no-copy path). See A5.
    pub pixels: Vec<u8>,
    /// Back buffer: the work-in-progress render target.
    pixels_back: Vec<u8>,
    pub depth: Vec<f32>, // depth buffer, length = width * height
    pub elapsed_time: f32,
    /// Cache of generated primitive meshes keyed by (type, params). Mesh geometry
    /// is invariant for a given descriptor — only the per-frame transform changes —
    /// so generating it once and reusing the `Arc` removes a large amount of trig +
    /// allocation from the hot path (esp. the particle loop). See A2.
    mesh_cache: HashMap<MeshCacheKey, Arc<Vec<Triangle>>>,
    /// Scratch list of screen-space triangles collected during scene traversal,
    /// then rasterized in one pass (serial on wasm, tiled-parallel on native). See A4.
    /// Reused across frames to avoid per-frame allocation.
    projected: Vec<ProjectedTri>,
    /// Decoded glTF/GLB models keyed by URL. Populated out-of-band via
    /// `load_model_bytes` (FFI feed / host bridge); `model3d` nodes look up their
    /// posed geometry here, falling back to a capsule placeholder when absent.
    models: HashMap<String, Arc<GltfModel>>,
}

/// A triangle projected to screen space, ready for the fill stage. Plain data so
/// the parallel rasterizer can share `&[ProjectedTri]` across threads. See A4.
///
/// Untextured triangles use the precomputed flat `color` (fast path). Textured
/// triangles carry the albedo decomposition (`light_mul`/`additive`/fog) plus the
/// procedural-texture params and per-vertex UVs, so albedo is sampled **per pixel**
/// from the barycentric-interpolated UV — giving crisp window grids and surface
/// grain instead of a single flat cell per face.
#[derive(Clone, Copy)]
struct ProjectedTri {
    v0: Vec2,
    v1: Vec2,
    v2: Vec2,
    z0: f32,
    z1: f32,
    z2: f32,
    /// Fully shaded flat color (used when `texture == None`).
    color: [f32; 3],
    alpha: f32,
    /// Procedural texture kind; `None` selects the flat fast path.
    texture: TextureKind,
    uv0: Vec2,
    uv1: Vec2,
    uv2: Vec2,
    base_color: Vec3,
    texture_color2: Vec3,
    texture_scale: f32,
    /// Albedo multiplier (ambient + incoming diffuse light); for unlit it is 1.
    light_mul: Vec3,
    /// Albedo-independent additive term (specular + emissive).
    additive: Vec3,
    fog_factor: f32,
    fog_color: Vec3,
}

impl SceneRenderer {
    pub fn new(width: u32, height: u32) -> Self {
        let pixel_count = (width * height) as usize;
        Self {
            width,
            height,
            pixels: vec![0u8; pixel_count * 4],
            pixels_back: vec![0u8; pixel_count * 4],
            depth: vec![f32::INFINITY; pixel_count],
            elapsed_time: 0.0,
            mesh_cache: HashMap::new(),
            projected: Vec::new(),
            models: HashMap::new(),
        }
    }

    /// Decode and cache a streamed model's bytes (GLB or embedded-buffer glTF),
    /// keyed by its URL. Returns true if the bytes parsed into a usable model.
    /// Idempotent: re-feeding the same URL replaces the cached model.
    pub fn load_model_bytes(&mut self, url: String, bytes: &[u8]) -> bool {
        match gltf::parse_model(bytes) {
            Some(model) => {
                self.models.insert(url, Arc::new(model));
                true
            }
            None => false,
        }
    }

    /// Whether a decoded model is cached for `url`.
    pub fn has_model(&self, url: &str) -> bool {
        self.models.contains_key(url)
    }

    /// Return the cached triangle list for a mesh descriptor, generating it on
    /// first use. Geometry depends only on the descriptor, not the transform, so
    /// the result is reused across frames and across particles. The returned
    /// `Arc` clone is a cheap pointer bump (no triangle copy).
    fn mesh_for(&mut self, mesh: &MeshType) -> Arc<Vec<Triangle>> {
        let key = MeshCacheKey::from(mesh);
        if let Some(m) = self.mesh_cache.get(&key) {
            return m.clone();
        }
        let tris = Arc::new(generate_mesh_triangles(mesh));
        self.mesh_cache.insert(key, tris.clone());
        tris
    }

    pub fn resize(&mut self, width: u32, height: u32) {
        self.width = width;
        self.height = height;
        let pixel_count = (width * height) as usize;
        self.pixels.resize(pixel_count * 4, 0);
        self.pixels_back.resize(pixel_count * 4, 0);
        self.depth.resize(pixel_count, f32::INFINITY);
    }

    /// Clear the back (work-in-progress) framebuffer with a background color.
    pub fn clear(&mut self, color: [u8; 4]) {
        #[cfg(not(target_arch = "wasm32"))]
        {
            use rayon::prelude::*;
            self.pixels_back
                .par_chunks_exact_mut(4)
                .for_each(|px| px.copy_from_slice(&color));
            self.depth.par_iter_mut().for_each(|d| *d = f32::INFINITY);
        }
        #[cfg(target_arch = "wasm32")]
        {
            for px in self.pixels_back.chunks_exact_mut(4) {
                px.copy_from_slice(&color);
            }
            for d in self.depth.iter_mut() {
                *d = f32::INFINITY;
            }
        }
    }

    /// Clear the back buffer with a vertical sky gradient (`top` at row 0 →
    /// `bottom` at the last row) and reset the depth buffer. Each row is a solid
    /// color, so the whole band shares one RGBA value (cheap to splat).
    pub fn clear_gradient(&mut self, top: Vec3, bottom: Vec3) {
        let width = self.width as usize;
        let height = self.height.max(1) as usize;
        let row_color = |y: usize| -> [u8; 4] {
            let t = if height > 1 {
                y as f32 / (height - 1) as f32
            } else {
                0.0
            };
            let c = top.lerp(bottom, t);
            [
                (c.x.clamp(0.0, 1.0) * 255.0) as u8,
                (c.y.clamp(0.0, 1.0) * 255.0) as u8,
                (c.z.clamp(0.0, 1.0) * 255.0) as u8,
                255,
            ]
        };

        #[cfg(not(target_arch = "wasm32"))]
        {
            use rayon::prelude::*;
            self.pixels_back
                .par_chunks_exact_mut(width * 4)
                .enumerate()
                .for_each(|(y, row)| {
                    let color = row_color(y);
                    for px in row.chunks_exact_mut(4) {
                        px.copy_from_slice(&color);
                    }
                });
            self.depth.par_iter_mut().for_each(|d| *d = f32::INFINITY);
        }
        #[cfg(target_arch = "wasm32")]
        {
            for (y, row) in self.pixels_back.chunks_exact_mut(width * 4).enumerate() {
                let color = row_color(y);
                for px in row.chunks_exact_mut(4) {
                    px.copy_from_slice(&color);
                }
            }
            for d in self.depth.iter_mut() {
                *d = f32::INFINITY;
            }
        }
    }

    /// Render a complete scene from JSON definition (no static-world split).
    pub fn render_scene(&mut self, scene: &SceneDef, delta_time: f32) {
        self.render_split(&[], &scene.world, delta_time);
    }

    /// Render a frame from a **baked static** node set plus a per-frame **dynamic**
    /// node set (P3 frame splicing). The static nodes (the baked city) are parsed
    /// once by the manager and reused every frame; only the small dynamic `world`
    /// (camera, player, enemies, fx) is re-parsed per tick. Both sets are scanned
    /// for camera/lights/environment and rendered static-first then dynamic.
    pub fn render_split(
        &mut self,
        static_nodes: &[JsonNode],
        dynamic_nodes: &[JsonNode],
        delta_time: f32,
    ) {
        self.elapsed_time += delta_time;

        // Collect environment settings (from either node set).
        let mut env = EnvironmentSettings::default();
        for node in static_nodes.iter().chain(dynamic_nodes.iter()) {
            if let JsonNode::Environment(e) = node {
                env.ambient_intensity = e.ambient_intensity;
                if let Some(ref al) = e.ambient_light {
                    env.ambient_color = al.to_vec3();
                }
                // A `fog_type` implies fog is on even when `fog_enabled` is omitted
                // (the scene3d DSL only emits `fog_type`).
                let linear = e
                    .fog_type
                    .as_deref()
                    .map(|t| t.eq_ignore_ascii_case("linear"))
                    .unwrap_or(false);
                env.fog_enabled = e.fog_enabled || e.fog_type.is_some();
                env.fog_linear = linear;
                env.fog_near = e.fog_near.unwrap_or(0.0);
                env.fog_distance = e.fog_distance;
                if let Some(ref fc) = e.fog_color {
                    env.fog_color = fc.to_vec3();
                }
                if let (Some(top), Some(bottom)) =
                    (e.sky_color_top.as_ref(), e.sky_color_bottom.as_ref())
                {
                    env.sky_gradient = Some((top.to_vec3(), bottom.to_vec3()));
                }
            }
        }

        // Determine sky/clear color from environment or skybox. A skybox color
        // takes precedence over the gradient as an explicit override.
        let mut clear_color = [20u8, 20u8, 30u8, 255u8];
        let mut skybox_override = false;
        for node in static_nodes.iter().chain(dynamic_nodes.iter()) {
            if let JsonNode::Skybox(sky) = node {
                if let Some(ref c) = sky.color {
                    clear_color = c.to_rgba_u8();
                    skybox_override = true;
                }
            }
        }
        if let (Some((top, bottom)), false) = (env.sky_gradient, skybox_override) {
            self.clear_gradient(top, bottom);
        } else {
            self.clear(clear_color);
        }

        // Collect camera + lights (scanning both node sets).
        let camera = self.find_camera(static_nodes.iter().chain(dynamic_nodes.iter()));
        let lights = self.collect_lights(static_nodes.iter().chain(dynamic_nodes.iter()));

        // Build view-projection matrix
        let aspect = self.width as f32 / self.height.max(1) as f32;
        let view_proj = camera.build_view_projection(aspect);

        // Render static geometry first, then the dynamic overlay. Traversal projects
        // + lights triangles into `self.projected` (in scene order); the fill stage
        // runs afterwards and the depth buffer resolves overlaps deterministically.
        for node in static_nodes.iter().chain(dynamic_nodes.iter()) {
            self.render_world_node(node, &Mat4::IDENTITY, &view_proj, &camera, &lights, &env);
        }

        // Fill all collected triangles in one pass. Processing them in the order
        // they were collected (scene order) makes the parallel result byte-identical
        // to the serial path: each pixel has a single writer per tile and the depth
        // test resolves overlaps deterministically.
        self.rasterize_all();

        // Publish the finished frame: swap back→front. Readers of `pixels` (the
        // front buffer) now see this frame; the previous front becomes the next
        // frame's render target. The swap is a cheap pointer exchange. See A5.
        std::mem::swap(&mut self.pixels, &mut self.pixels_back);
    }

    fn find_camera<'a>(&self, nodes: impl Iterator<Item = &'a JsonNode>) -> CameraState {
        for node in nodes {
            if let JsonNode::Camera(cam) = node {
                let transform = cam.transform.to_mat4();
                let pos = transform.col(3).truncate();
                // Extract forward direction (negative Z in camera space)
                let forward = -(transform.col(2).truncate()).normalize();
                let up = transform.col(1).truncate().normalize();
                let fov = cam.fov.unwrap_or(60.0);
                let near = cam.near.unwrap_or(0.1);
                let far = cam.far.unwrap_or(1000.0);
                let is_ortho = matches!(cam.camera_type, CameraType::Orthographic);

                return CameraState {
                    position: pos,
                    forward,
                    up,
                    fov,
                    near,
                    far,
                    is_ortho,
                };
            }
        }

        // Default camera: positioned at (0, 5, 10) looking toward origin
        let pos = Vec3::new(0.0, 5.0, 10.0);
        let target = Vec3::ZERO;
        let forward = (target - pos).normalize();
        CameraState {
            position: pos,
            forward,
            up: Vec3::Y,
            fov: 60.0,
            near: 0.1,
            far: 1000.0,
            is_ortho: false,
        }
    }

    fn collect_lights<'a>(&self, nodes: impl Iterator<Item = &'a JsonNode>) -> Vec<LightState> {
        let mut lights = Vec::new();
        for node in nodes {
            if let JsonNode::Light(l) = node {
                let transform = l.transform.to_mat4();
                let pos = transform.col(3).truncate();
                let direction = -(transform.col(2).truncate()).normalize();
                let color = l.color.as_ref().map(|c| c.to_vec3()).unwrap_or(Vec3::ONE);
                let intensity = l.intensity.unwrap_or(1.0);

                lights.push(LightState {
                    light_type: match l.light_type {
                        LightType::Point => LightStateType::Point,
                        LightType::Directional => LightStateType::Directional,
                        LightType::Spot => LightStateType::Spot,
                    },
                    position: pos,
                    direction,
                    color,
                    intensity,
                    range: l.range,
                });
            }
        }

        // Add default light if none defined
        if lights.is_empty() {
            lights.push(LightState {
                light_type: LightStateType::Directional,
                position: Vec3::new(5.0, 10.0, 5.0),
                direction: Vec3::new(-0.5, -1.0, -0.5).normalize(),
                color: Vec3::ONE,
                intensity: 1.0,
                range: None,
            });
        }

        lights
    }

    fn render_world_node(
        &mut self,
        node: &JsonNode,
        parent_transform: &Mat4,
        view_proj: &Mat4,
        camera: &CameraState,
        lights: &[LightState],
        env: &EnvironmentSettings,
    ) {
        match node {
            JsonNode::Mesh3D(mesh) => {
                let local = self.compute_animated_transform(&mesh.transform, &mesh.animation);
                let world = *parent_transform * local;
                let material = MaterialState::from_def(&mesh.material);
                let triangles = self.mesh_for(&mesh.mesh);
                self.rasterize_triangles(
                    &triangles, &world, view_proj, camera, lights, &material, env,
                );

                // Render children
                for child in &mesh.children {
                    self.render_world_node(child, &world, view_proj, camera, lights, env);
                }
            }
            JsonNode::Model3D(model) => {
                let local = model.transform.to_mat4();
                let world = *parent_transform * local;
                self.render_model(model, &world, view_proj, camera, lights, env);

                for child in &model.children {
                    self.render_world_node(child, &world, view_proj, camera, lights, env);
                }
            }
            JsonNode::RigidBody(rb) => {
                let local = rb.transform.to_mat4();
                let world = *parent_transform * local;
                let material = MaterialState::from_def(&rb.material);
                let triangles = self.mesh_for(&rb.mesh);
                self.rasterize_triangles(
                    &triangles, &world, view_proj, camera, lights, &material, env,
                );
            }
            JsonNode::Terrain(terrain) => {
                let local = terrain.transform.to_mat4();
                let world = *parent_transform * local;
                let material = MaterialState::from_def(&terrain.material);
                let half = terrain.size / 2.0;
                let triangles = vec![
                    Triangle::new(
                        Vec3::new(-half, 0.0, -half),
                        Vec3::new(half, 0.0, -half),
                        Vec3::new(half, 0.0, half),
                        Vec3::Y,
                    ),
                    Triangle::new(
                        Vec3::new(-half, 0.0, -half),
                        Vec3::new(half, 0.0, half),
                        Vec3::new(-half, 0.0, half),
                        Vec3::Y,
                    ),
                ];
                self.rasterize_triangles(
                    &triangles, &world, view_proj, camera, lights, &material, env,
                );
            }
            JsonNode::Water(water) => {
                let local = water.transform.to_mat4();
                let world = *parent_transform * local;
                let wc = water
                    .water_color
                    .as_ref()
                    .map(|c| c.to_vec3())
                    .unwrap_or(Vec3::new(0.0, 0.5, 1.0));
                let material = MaterialState {
                    base_color: wc,
                    metallic: 0.6,
                    roughness: 0.2,
                    emissive: Vec3::ZERO,
                    alpha: water.transparency,
                    unlit: false,
                    texture: TextureKind::None,
                    texture_color2: Vec3::ZERO,
                    texture_scale: 1.0,
                };
                let hx = water.size.x / 2.0;
                let hz = water.size.z / 2.0;
                // Animate water surface with wave
                let t = self.elapsed_time;
                let amp = water.wave_amplitude;
                let freq = water.wave_frequency;
                let y0 = (t * freq).sin() * amp;
                let y1 = ((t * freq) + 1.0).sin() * amp;
                let triangles = vec![
                    Triangle::new(
                        Vec3::new(-hx, y0, -hz),
                        Vec3::new(hx, y1, -hz),
                        Vec3::new(hx, y0, hz),
                        Vec3::Y,
                    ),
                    Triangle::new(
                        Vec3::new(-hx, y0, -hz),
                        Vec3::new(hx, y0, hz),
                        Vec3::new(-hx, y1, hz),
                        Vec3::Y,
                    ),
                ];
                self.rasterize_triangles(
                    &triangles, &world, view_proj, camera, lights, &material, env,
                );
            }
            JsonNode::Particles(particle) => {
                let local = particle.transform.to_mat4();
                let world = *parent_transform * local;
                self.render_particles(particle, &world, view_proj, camera, lights, env);
            }
            JsonNode::Group(group) => {
                let local = group.transform.to_mat4();
                let world = *parent_transform * local;
                for child in &group.children {
                    self.render_world_node(child, &world, view_proj, camera, lights, env);
                }
            }
            // Camera, Light, Environment, Skybox are handled during collection, not rendered as geometry
            _ => {}
        }
    }

    fn compute_animated_transform(
        &self,
        base: &TransformDef,
        animation: &Option<AnimationDef>,
    ) -> Mat4 {
        let base_mat = base.to_mat4();

        let anim = match animation {
            Some(a) => a,
            None => return base_mat,
        };

        let duration = anim.duration.max(0.001);
        let raw_progress = if anim.looping {
            (self.elapsed_time % duration) / duration
        } else {
            (self.elapsed_time / duration).min(1.0)
        };
        let t = apply_easing(raw_progress, &anim.easing);

        match &anim.animation_type {
            AnimationType::Rotate { axis, degrees } => {
                let axis_vec = axis.to_glam().normalize_or_zero();
                if axis_vec == Vec3::ZERO {
                    return base_mat;
                }
                let angle = degrees.to_radians() * t;
                let rot = Mat4::from_axis_angle(axis_vec, angle);
                base_mat * rot
            }
            AnimationType::Translate { from, to } => {
                let from_v = from.to_glam();
                let to_v = to.to_glam();
                let pos = from_v.lerp(to_v, t);
                Mat4::from_translation(pos)
            }
            AnimationType::Scale { from, to } => {
                let from_v = from.to_glam();
                let to_v = to.to_glam();
                let scale = from_v.lerp(to_v, t);
                base_mat * Mat4::from_scale(scale)
            }
            AnimationType::Bounce { height } => {
                let y = (t * std::f32::consts::PI).sin() * height;
                base_mat * Mat4::from_translation(Vec3::new(0.0, y, 0.0))
            }
            AnimationType::Pulse {
                min_scale,
                max_scale,
            } => {
                let s = min_scale
                    + (max_scale - min_scale) * (0.5 + 0.5 * (t * std::f32::consts::TAU).sin());
                base_mat * Mat4::from_scale(Vec3::splat(s))
            }
        }
    }

    fn render_particles(
        &mut self,
        particle: &ParticleNode,
        world: &Mat4,
        view_proj: &Mat4,
        camera: &CameraState,
        lights: &[LightState],
        env: &EnvironmentSettings,
    ) {
        let color = particle.color.to_vec3();
        let material = MaterialState {
            base_color: color,
            metallic: 0.0,
            roughness: 1.0,
            emissive: color * 0.5,
            alpha: 1.0,
            unlit: false,
            texture: TextureKind::None,
            texture_color2: Vec3::ZERO,
            texture_scale: 1.0,
        };

        // Simple particle rendering: scatter small spheres based on time
        let count = (particle.emission_rate * particle.lifetime).ceil() as i32;
        let count = count.min(100); // cap for performance

        // All particles share one cached unit cube; only the transform differs.
        let triangles = self.mesh_for(&MeshType::Named(MeshTypeName::Cube));

        for i in 0..count {
            let spawn_time = (i as f32) / particle.emission_rate;
            let age = (self.elapsed_time - spawn_time) % particle.lifetime;
            if age < 0.0 {
                continue;
            }

            // Particle position: base + velocity*age + 0.5*gravity*age^2
            let vel = particle.velocity.to_glam();
            let grav = particle.gravity.to_glam();
            let offset = vel * age + grav * 0.5 * age * age;

            let particle_world = *world
                * Mat4::from_translation(offset)
                * Mat4::from_scale(Vec3::splat(particle.size));

            self.rasterize_triangles(
                &triangles,
                &particle_world,
                view_proj,
                camera,
                lights,
                &material,
                env,
            );
        }
    }

    /// Render a streamed glTF `model3d` node. When the model bytes have been fed
    /// into the cache, the model is posed for its animation clip + `anim_time` and
    /// drawn skinned/tinted/lit. Until then a tinted capsule placeholder stands in
    /// so gameplay never blocks on a download (parity with the scene3d behavior).
    fn render_model(
        &mut self,
        model: &Model3DNode,
        world: &Mat4,
        view_proj: &Mat4,
        camera: &CameraState,
        lights: &[LightState],
        env: &EnvironmentSettings,
    ) {
        let tint = model.tint.as_ref().map(|c| c.to_vec3()).unwrap_or(Vec3::ONE);
        let node_emissive = model
            .emissive
            .as_ref()
            .map(|c| c.to_vec3())
            .unwrap_or(Vec3::ZERO);
        let strength = model.emissive_strength.unwrap_or(1.0);

        let Some(gltf_model) = self.models.get(&model.model).cloned() else {
            // Placeholder: a tinted capsule at the node transform.
            let material = MaterialState {
                base_color: tint * Vec3::new(0.6, 0.6, 0.65),
                metallic: 0.0,
                roughness: 0.8,
                emissive: node_emissive * strength,
                alpha: 1.0,
                unlit: false,
                texture: TextureKind::None,
                texture_color2: Vec3::ZERO,
                texture_scale: 1.0,
            };
            let triangles = self.mesh_for(&MeshType::Parameterized(MeshTypeParam::Capsule {
                radius: 0.4,
                depth: 1.0,
            }));
            self.rasterize_triangles(&triangles, world, view_proj, camera, lights, &material, env);
            return;
        };

        // Resolve the animation clip: explicit name/index, else the first clip.
        let anim = match &model.animation {
            Some(StringOrIndex::Index(i)) => Some(*i as usize),
            Some(StringOrIndex::Name(n)) => gltf_model.animation_index_by_name(n),
            None => {
                if gltf_model.animation_count() > 0 {
                    Some(0)
                } else {
                    None
                }
            }
        };

        let posed = gltf_model.pose(anim, model.anim_time);
        for prim in &posed {
            let material = MaterialState {
                base_color: prim.base_color * tint,
                metallic: 0.0,
                roughness: 0.6,
                emissive: (prim.emissive + node_emissive) * strength,
                alpha: 1.0,
                unlit: false,
                texture: TextureKind::None,
                texture_color2: Vec3::ZERO,
                texture_scale: 1.0,
            };
            self.rasterize_triangles(
                &prim.triangles,
                world,
                view_proj,
                camera,
                lights,
                &material,
                env,
            );
        }
    }

    // ── Rasterization ────────────────────────────────────────────────

    fn rasterize_triangles(
        &mut self,
        triangles: &[Triangle],
        world: &Mat4,
        view_proj: &Mat4,
        camera: &CameraState,
        lights: &[LightState],
        material: &MaterialState,
        env: &EnvironmentSettings,
    ) {
        let mvp = *view_proj * *world;
        let normal_matrix = world.inverse().transpose();
        let w_clip_plane = 0.001_f32;

        for tri in triangles {
            // Transform vertices to world space
            let w0 = world.transform_point3(tri.v0);
            let w1 = world.transform_point3(tri.v1);
            let w2 = world.transform_point3(tri.v2);

            // Transform normals
            let n = normal_matrix.transform_vector3(tri.normal).normalize();

            // Project to clip space
            let c0 = mvp * Vec4::new(tri.v0.x, tri.v0.y, tri.v0.z, 1.0);
            let c1 = mvp * Vec4::new(tri.v1.x, tri.v1.y, tri.v1.z, 1.0);
            let c2 = mvp * Vec4::new(tri.v2.x, tri.v2.y, tri.v2.z, 1.0);

            // Simple frustum culling: skip if all vertices behind camera
            if c0.w <= 0.0 && c1.w <= 0.0 && c2.w <= 0.0 {
                continue;
            }

            // Near-plane clipping: clip triangles that cross the w=0 plane.
            // Count vertices that are in front of the camera (w > threshold).
            let in0 = c0.w > w_clip_plane;
            let in1 = c1.w > w_clip_plane;
            let in2 = c2.w > w_clip_plane;
            let inside_count = in0 as u8 + in1 as u8 + in2 as u8;

            if inside_count == 0 {
                continue;
            }

            // Flat-shade lighting at the triangle center, decomposed so the albedo
            // (procedural texture) can be applied per pixel in the fill stage. The
            // centroid albedo gives the flat-path color for the untextured fast path
            // and the near-plane-clipped fan (which doesn't carry UVs).
            let center = (w0 + w1 + w2) / 3.0;
            let shading = shade(center, n, camera, lights, material, env);
            let centroid_uv = (tri.uv0 + tri.uv1 + tri.uv2) / 3.0;
            let flat_color = shading.resolve(material.sample_texture(centroid_uv));
            let alpha = material.alpha;

            if inside_count == 3 {
                // All vertices in front: render directly
                let ndc0 = Vec3::new(c0.x / c0.w, c0.y / c0.w, c0.z / c0.w);
                let ndc1 = Vec3::new(c1.x / c1.w, c1.y / c1.w, c1.z / c1.w);
                let ndc2 = Vec3::new(c2.x / c2.w, c2.y / c2.w, c2.z / c2.w);

                let s0 = self.ndc_to_screen(ndc0);
                let s1 = self.ndc_to_screen(ndc1);
                let s2 = self.ndc_to_screen(ndc2);

                self.projected.push(ProjectedTri {
                    v0: s0,
                    v1: s1,
                    v2: s2,
                    z0: ndc0.z,
                    z1: ndc1.z,
                    z2: ndc2.z,
                    color: flat_color,
                    alpha,
                    texture: material.texture,
                    uv0: tri.uv0,
                    uv1: tri.uv1,
                    uv2: tri.uv2,
                    base_color: material.base_color,
                    texture_color2: material.texture_color2,
                    texture_scale: material.texture_scale,
                    light_mul: shading.light_mul,
                    additive: shading.additive,
                    fog_factor: shading.fog_factor,
                    fog_color: shading.fog_color,
                });
            } else {
                // Triangle crosses near plane: clip against w = w_clip_plane.
                // Collect clip-space vertices, splitting edges that cross.
                let clips = [c0, c1, c2];
                let inside = [in0, in1, in2];
                let mut clipped: Vec<Vec4> = Vec::with_capacity(4);

                for i in 0..3 {
                    let j = (i + 1) % 3;
                    let ci = clips[i];
                    let cj = clips[j];

                    if inside[i] {
                        clipped.push(ci);
                    }

                    // If this edge crosses the plane, compute intersection
                    if inside[i] != inside[j] {
                        let t = (ci.w - w_clip_plane) / (ci.w - cj.w);
                        let intersect = ci + (cj - ci) * t;
                        clipped.push(intersect);
                    }
                }

                // Fan-triangulate the clipped polygon (3 or 4 vertices)
                if clipped.len() >= 3 {
                    for k in 1..(clipped.len() - 1) {
                        let a = clipped[0];
                        let b = clipped[k];
                        let c = clipped[k + 1];

                        let ndc_a = Vec3::new(a.x / a.w, a.y / a.w, a.z / a.w);
                        let ndc_b = Vec3::new(b.x / b.w, b.y / b.w, b.z / b.w);
                        let ndc_c = Vec3::new(c.x / c.w, c.y / c.w, c.z / c.w);

                        let sa = self.ndc_to_screen(ndc_a);
                        let sb = self.ndc_to_screen(ndc_b);
                        let sc = self.ndc_to_screen(ndc_c);

                        // The clip path doesn't carry interpolated UVs, so the
                        // textured fan falls back to the flat centroid color.
                        self.projected.push(ProjectedTri {
                            v0: sa,
                            v1: sb,
                            v2: sc,
                            z0: ndc_a.z,
                            z1: ndc_b.z,
                            z2: ndc_c.z,
                            color: flat_color,
                            alpha,
                            texture: TextureKind::None,
                            uv0: Vec2::ZERO,
                            uv1: Vec2::ZERO,
                            uv2: Vec2::ZERO,
                            base_color: material.base_color,
                            texture_color2: material.texture_color2,
                            texture_scale: material.texture_scale,
                            light_mul: shading.light_mul,
                            additive: shading.additive,
                            fog_factor: shading.fog_factor,
                            fog_color: shading.fog_color,
                        });
                    }
                }
            }
        }
    }

    fn ndc_to_screen(&self, ndc: Vec3) -> Vec2 {
        Vec2::new(
            (ndc.x * 0.5 + 0.5) * self.width as f32,
            (1.0 - (ndc.y * 0.5 + 0.5)) * self.height as f32,
        )
    }

    /// Fill every triangle collected in `self.projected` into the framebuffer.
    ///
    /// On native targets the framebuffer is split into disjoint horizontal bands
    /// and rasterized in parallel with rayon: each band owns a contiguous slice of
    /// `pixels`/`depth`, so threads never alias the same bytes (no locks). Each band
    /// processes the triangles in collection (scene) order, so per-pixel depth
    /// resolution is identical to the serial path → byte-identical output.
    ///
    /// On wasm (no threads) it falls back to a single serial pass.
    fn rasterize_all(&mut self) {
        let tris = std::mem::take(&mut self.projected);
        let width = self.width as usize;
        let height = self.height as usize;

        if width != 0 && height != 0 {
            // Render into the back buffer; render_scene swaps it to front afterwards.
            let pixels = &mut self.pixels_back;
            let depth = &mut self.depth;

            #[cfg(not(target_arch = "wasm32"))]
            {
                use rayon::prelude::*;
                // Band height in rows. Larger bands amortize per-band triangle
                // iteration; smaller bands improve load balancing. 32 is a good
                // middle ground for typical render sizes.
                const BAND_ROWS: usize = 32;
                let pix_chunk = BAND_ROWS * width * 4;
                let dep_chunk = BAND_ROWS * width;
                pixels
                    .par_chunks_mut(pix_chunk)
                    .zip(depth.par_chunks_mut(dep_chunk))
                    .enumerate()
                    .for_each(|(band_idx, (pix_band, dep_band))| {
                        let y_start = (band_idx * BAND_ROWS) as i32;
                        let rows = (dep_band.len() / width) as i32;
                        let y_end = y_start + rows;
                        for t in &tris {
                            fill_projected(pix_band, dep_band, width, height, y_start, y_end, t);
                        }
                    });
            }

            #[cfg(target_arch = "wasm32")]
            {
                for t in &tris {
                    fill_projected(pixels, depth, width, height, 0, height as i32, t);
                }
            }
        }

        // Restore the (now-drained) buffer to reuse its capacity next frame.
        let mut tris = tris;
        tris.clear();
        self.projected = tris;
    }

    /// Set a pixel directly (for UI overlay rendering).
    #[inline]
    fn _set_pixel(&mut self, x: u32, y: u32, r: u8, g: u8, b: u8, a: u8) {
        if x < self.width && y < self.height {
            let idx = ((y * self.width + x) * 4) as usize;
            self.pixels[idx] = r;
            self.pixels[idx + 1] = g;
            self.pixels[idx + 2] = b;
            self.pixels[idx + 3] = a;
        }
    }
}

// ── Geometry Helpers ─────────────────────────────────────────────────

#[derive(Debug, Clone)]
pub struct Triangle {
    pub v0: Vec3,
    pub v1: Vec3,
    pub v2: Vec3,
    pub normal: Vec3,
    /// Per-vertex texture coordinates (parity with scene3d). Used to sample the
    /// procedural texture at the triangle centroid in the flat-shaded path.
    pub uv0: Vec2,
    pub uv1: Vec2,
    pub uv2: Vec2,
}

impl Triangle {
    pub fn new(v0: Vec3, v1: Vec3, v2: Vec3, normal: Vec3) -> Self {
        Self {
            v0,
            v1,
            v2,
            normal,
            uv0: Vec2::ZERO,
            uv1: Vec2::ZERO,
            uv2: Vec2::ZERO,
        }
    }

    /// Like `new` but with explicit per-vertex UVs.
    pub fn new_uv(
        v0: Vec3,
        v1: Vec3,
        v2: Vec3,
        normal: Vec3,
        uv0: Vec2,
        uv1: Vec2,
        uv2: Vec2,
    ) -> Self {
        Self {
            v0,
            v1,
            v2,
            normal,
            uv0,
            uv1,
            uv2,
        }
    }

    pub fn from_vertices(v0: Vec3, v1: Vec3, v2: Vec3) -> Self {
        let edge1 = v1 - v0;
        let edge2 = v2 - v0;
        let normal = edge1.cross(edge2).normalize();
        Self {
            v0,
            v1,
            v2,
            normal,
            uv0: Vec2::ZERO,
            uv1: Vec2::ZERO,
            uv2: Vec2::ZERO,
        }
    }
}

fn edge_function(a: Vec2, b: Vec2, c: Vec2) -> f32 {
    (c.x - a.x) * (b.y - a.y) - (c.y - a.y) * (b.x - a.x)
}

/// Rasterize one projected triangle into a (possibly band-local) framebuffer slice.
///
/// `pixels`/`depth` cover the global rows `[band_y_start, band_y_end)` only; pixel
/// indices are computed relative to `band_y_start`. With a single full-height band
/// (`band_y_start = 0`, `band_y_end = height`) this reduces exactly to the serial
/// rasterizer. The per-pixel arithmetic matches the A3 hoisted form bit-for-bit, so
/// output is byte-identical regardless of how the frame is banded. See A4.
#[inline]
fn fill_projected(
    pixels: &mut [u8],
    depth: &mut [f32],
    width: usize,
    height: usize,
    band_y_start: i32,
    band_y_end: i32,
    t: &ProjectedTri,
) {
    let v0 = t.v0;
    let v1 = t.v1;
    let v2 = t.v2;

    // Bounding box (global), then intersect the y-range with this band.
    let min_x = v0.x.min(v1.x).min(v2.x).max(0.0) as i32;
    let max_x = v0.x.max(v1.x).max(v2.x).min(width as f32 - 1.0) as i32;
    let min_y_g = v0.y.min(v1.y).min(v2.y).max(0.0) as i32;
    let max_y_g = v0.y.max(v1.y).max(v2.y).min(height as f32 - 1.0) as i32;
    let min_y = min_y_g.max(band_y_start);
    let max_y = max_y_g.min(band_y_end - 1);

    let area = edge_function(v0, v1, v2);
    if area.abs() < 0.001 {
        return;
    } // Degenerate triangle
    let inv_area = 1.0 / area;

    // Per-triangle edge deltas (see A3). Edge 0: a=v1,b=v2; edge 1: a=v2,b=v0; edge 2: a=v0,b=v1.
    let e0_dy = v2.y - v1.y;
    let e0_dx = v2.x - v1.x;
    let e1_dy = v0.y - v2.y;
    let e1_dx = v0.x - v2.x;
    let e2_dy = v1.y - v0.y;
    let e2_dx = v1.x - v0.x;

    // Flat shading: color/alpha constant per triangle.
    let color = t.color;
    let alpha = t.alpha;
    let r = (color[0].clamp(0.0, 1.0) * 255.0) as u8;
    let g = (color[1].clamp(0.0, 1.0) * 255.0) as u8;
    let b = (color[2].clamp(0.0, 1.0) * 255.0) as u8;
    let a = (alpha.clamp(0.0, 1.0) * 255.0) as u8;
    let opaque = alpha >= 1.0;
    let src_a = alpha;
    let one_minus_sa = 1.0 - src_a;
    let csa_r = color[0] * src_a;
    let csa_g = color[1] * src_a;
    let csa_b = color[2] * src_a;

    let z0 = t.z0;
    let z1 = t.z1;
    let z2 = t.z2;

    // Untextured triangles take the flat fast path (one constant color, no
    // per-pixel sampling). This branch is byte-identical to the original A4 fill.
    if t.texture == TextureKind::None {
        for y in min_y..=max_y {
            let py = y as f32 + 0.5;
            let py0 = (py - v1.y) * e0_dx;
            let py1 = (py - v2.y) * e1_dx;
            let py2 = (py - v0.y) * e2_dx;
            // Row offset relative to this band's first row.
            let row = (y - band_y_start) as usize * width;

            for x in min_x..=max_x {
                let px = x as f32 + 0.5;

                let w0 = ((px - v1.x) * e0_dy - py0) * inv_area;
                let w1 = ((px - v2.x) * e1_dy - py1) * inv_area;
                let w2 = ((px - v0.x) * e2_dy - py2) * inv_area;

                if w0 >= 0.0 && w1 >= 0.0 && w2 >= 0.0 {
                    let z = w0 * z0 + w1 * z1 + w2 * z2;
                    let idx = row + x as usize;

                    if z < depth[idx] {
                        depth[idx] = z;

                        let pidx = idx * 4;
                        if opaque {
                            pixels[pidx] = r;
                            pixels[pidx + 1] = g;
                            pixels[pidx + 2] = b;
                            pixels[pidx + 3] = a;
                        } else {
                            let dst_r = pixels[pidx] as f32 / 255.0;
                            let dst_g = pixels[pidx + 1] as f32 / 255.0;
                            let dst_b = pixels[pidx + 2] as f32 / 255.0;
                            pixels[pidx] =
                                ((csa_r + dst_r * one_minus_sa).clamp(0.0, 1.0) * 255.0) as u8;
                            pixels[pidx + 1] =
                                ((csa_g + dst_g * one_minus_sa).clamp(0.0, 1.0) * 255.0) as u8;
                            pixels[pidx + 2] =
                                ((csa_b + dst_b * one_minus_sa).clamp(0.0, 1.0) * 255.0) as u8;
                            pixels[pidx + 3] = 255;
                        }
                    }
                }
            }
        }
        return;
    }

    // Textured triangles sample the procedural albedo per pixel from the
    // barycentric-interpolated UV, then apply `albedo*light_mul + additive` and fog.
    for y in min_y..=max_y {
        let py = y as f32 + 0.5;
        let py0 = (py - v1.y) * e0_dx;
        let py1 = (py - v2.y) * e1_dx;
        let py2 = (py - v0.y) * e2_dx;
        let row = (y - band_y_start) as usize * width;

        for x in min_x..=max_x {
            let px = x as f32 + 0.5;

            let w0 = ((px - v1.x) * e0_dy - py0) * inv_area;
            let w1 = ((px - v2.x) * e1_dy - py1) * inv_area;
            let w2 = ((px - v0.x) * e2_dy - py2) * inv_area;

            if w0 >= 0.0 && w1 >= 0.0 && w2 >= 0.0 {
                let z = w0 * z0 + w1 * z1 + w2 * z2;
                let idx = row + x as usize;

                if z < depth[idx] {
                    depth[idx] = z;

                    // Affine-interpolated UV (matches the affine z/colour interp used
                    // elsewhere in this renderer), then sample + shade.
                    let uv = t.uv0 * w0 + t.uv1 * w1 + t.uv2 * w2;
                    let albedo = sample_texture_kind(
                        t.texture,
                        t.base_color,
                        t.texture_color2,
                        t.texture_scale,
                        uv,
                    );
                    let pre = albedo * t.light_mul + t.additive;
                    let c = pre.lerp(t.fog_color, t.fog_factor);

                    let pidx = idx * 4;
                    if opaque {
                        pixels[pidx] = (c.x.clamp(0.0, 1.0) * 255.0) as u8;
                        pixels[pidx + 1] = (c.y.clamp(0.0, 1.0) * 255.0) as u8;
                        pixels[pidx + 2] = (c.z.clamp(0.0, 1.0) * 255.0) as u8;
                        pixels[pidx + 3] = a;
                    } else {
                        let dst_r = pixels[pidx] as f32 / 255.0;
                        let dst_g = pixels[pidx + 1] as f32 / 255.0;
                        let dst_b = pixels[pidx + 2] as f32 / 255.0;
                        pixels[pidx] =
                            ((c.x * src_a + dst_r * one_minus_sa).clamp(0.0, 1.0) * 255.0) as u8;
                        pixels[pidx + 1] =
                            ((c.y * src_a + dst_g * one_minus_sa).clamp(0.0, 1.0) * 255.0) as u8;
                        pixels[pidx + 2] =
                            ((c.z * src_a + dst_b * one_minus_sa).clamp(0.0, 1.0) * 255.0) as u8;
                        pixels[pidx + 3] = 255;
                    }
                }
            }
        }
    }
}

/// Hashable cache key for a mesh descriptor (A2). Float params are stored as
/// their exact IEEE-754 bit pattern (`f32::to_bits`) so identical descriptors map
/// to the same entry and *distinct* values never collide — guaranteeing the cached
/// geometry is byte-identical to regenerating it.
#[derive(Clone, PartialEq, Eq, Hash)]
enum MeshCacheKey {
    Cube,
    Sphere { radius: u32, subdivisions: u32 },
    Plane { size: u32 },
    Cylinder { radius: u32, height: u32, segments: u32 },
    Cone { radius: u32, height: u32, segments: u32 },
    Capsule { radius: u32, depth: u32 },
    Torus { radius: u32, tube_radius: u32 },
    File { path: String },
}

impl From<&MeshType> for MeshCacheKey {
    fn from(mesh: &MeshType) -> Self {
        match mesh {
            MeshType::Named(MeshTypeName::Cube) => MeshCacheKey::Cube,
            MeshType::Parameterized(param) => match param {
                MeshTypeParam::Sphere {
                    radius,
                    subdivisions,
                } => MeshCacheKey::Sphere {
                    radius: radius.to_bits(),
                    subdivisions: *subdivisions,
                },
                MeshTypeParam::Plane { size } => MeshCacheKey::Plane {
                    size: size.to_bits(),
                },
                MeshTypeParam::Cylinder {
                    radius,
                    height,
                    segments,
                } => MeshCacheKey::Cylinder {
                    radius: radius.to_bits(),
                    height: height.to_bits(),
                    segments: *segments,
                },
                MeshTypeParam::Cone {
                    radius,
                    height,
                    segments,
                } => MeshCacheKey::Cone {
                    radius: radius.to_bits(),
                    height: height.to_bits(),
                    segments: *segments,
                },
                MeshTypeParam::Capsule { radius, depth } => MeshCacheKey::Capsule {
                    radius: radius.to_bits(),
                    depth: depth.to_bits(),
                },
                MeshTypeParam::Torus {
                    radius,
                    tube_radius,
                } => MeshCacheKey::Torus {
                    radius: radius.to_bits(),
                    tube_radius: tube_radius.to_bits(),
                },
                MeshTypeParam::File { path } => MeshCacheKey::File { path: path.clone() },
            },
        }
    }
}

/// Generate triangles for a mesh type.
pub fn generate_mesh_triangles(mesh_type: &MeshType) -> Vec<Triangle> {
    match mesh_type {
        MeshType::Named(MeshTypeName::Cube) => generate_cube(1.0),
        MeshType::Parameterized(param) => match param {
            MeshTypeParam::Sphere {
                radius,
                subdivisions,
            } => generate_uv_sphere(*radius, (*subdivisions).max(4)),
            MeshTypeParam::Plane { size } => generate_plane(*size),
            MeshTypeParam::Cylinder {
                radius,
                height,
                segments,
            } => generate_cylinder(*radius, *height, (*segments).max(3)),
            MeshTypeParam::Cone {
                radius,
                height,
                segments,
            } => generate_cone(*radius, *height, (*segments).max(3)),
            MeshTypeParam::Capsule { radius, depth } => {
                // Approximate as cylinder + two hemispheres
                let mut tris = generate_cylinder(*radius, *depth, 16);
                tris.extend(generate_uv_sphere(*radius, 8).into_iter().map(|mut t| {
                    t.v0.y += depth / 2.0;
                    t.v1.y += depth / 2.0;
                    t.v2.y += depth / 2.0;
                    t
                }));
                tris.extend(generate_uv_sphere(*radius, 8).into_iter().map(|mut t| {
                    t.v0.y -= depth / 2.0;
                    t.v1.y -= depth / 2.0;
                    t.v2.y -= depth / 2.0;
                    t
                }));
                tris
            }
            MeshTypeParam::Torus {
                radius,
                tube_radius,
            } => generate_torus(*radius, *tube_radius, 24, 12),
            MeshTypeParam::File { .. } => {
                // File meshes not supported in software renderer; show placeholder cube
                generate_cube(1.0)
            }
        },
    }
}

fn generate_cube(size: f32) -> Vec<Triangle> {
    let h = size / 2.0;
    let vertices = [
        // Front face
        Vec3::new(-h, -h, h),
        Vec3::new(h, -h, h),
        Vec3::new(h, h, h),
        Vec3::new(-h, h, h),
        // Back face
        Vec3::new(-h, -h, -h),
        Vec3::new(-h, h, -h),
        Vec3::new(h, h, -h),
        Vec3::new(h, -h, -h),
        // Top face
        Vec3::new(-h, h, -h),
        Vec3::new(-h, h, h),
        Vec3::new(h, h, h),
        Vec3::new(h, h, -h),
        // Bottom face
        Vec3::new(-h, -h, -h),
        Vec3::new(h, -h, -h),
        Vec3::new(h, -h, h),
        Vec3::new(-h, -h, h),
        // Right face
        Vec3::new(h, -h, -h),
        Vec3::new(h, h, -h),
        Vec3::new(h, h, h),
        Vec3::new(h, -h, h),
        // Left face
        Vec3::new(-h, -h, -h),
        Vec3::new(-h, -h, h),
        Vec3::new(-h, h, h),
        Vec3::new(-h, h, -h),
    ];

    let normals = [
        Vec3::new(0.0, 0.0, 1.0),  // Front
        Vec3::new(0.0, 0.0, -1.0), // Back
        Vec3::new(0.0, 1.0, 0.0),  // Top
        Vec3::new(0.0, -1.0, 0.0), // Bottom
        Vec3::new(1.0, 0.0, 0.0),  // Right
        Vec3::new(-1.0, 0.0, 0.0), // Left
    ];

    // Per-corner UVs, matching scene3d's cube layout so procedural textures
    // (checkerboard windows, noise) tile identically across both renderers.
    let uvs = [
        Vec2::new(0.0, 1.0),
        Vec2::new(1.0, 1.0),
        Vec2::new(1.0, 0.0),
        Vec2::new(0.0, 0.0),
    ];

    let mut triangles = Vec::with_capacity(12);
    for face in 0..6 {
        let base = face * 4;
        triangles.push(Triangle::new_uv(
            vertices[base],
            vertices[base + 1],
            vertices[base + 2],
            normals[face],
            uvs[0],
            uvs[1],
            uvs[2],
        ));
        triangles.push(Triangle::new_uv(
            vertices[base],
            vertices[base + 2],
            vertices[base + 3],
            normals[face],
            uvs[0],
            uvs[2],
            uvs[3],
        ));
    }
    triangles
}

fn generate_uv_sphere(radius: f32, segments: u32) -> Vec<Triangle> {
    let mut triangles = Vec::new();
    let stacks = segments;
    let sectors = segments;

    for i in 0..stacks {
        let theta1 = std::f32::consts::PI * (i as f32) / (stacks as f32);
        let theta2 = std::f32::consts::PI * ((i + 1) as f32) / (stacks as f32);

        for j in 0..sectors {
            let phi1 = std::f32::consts::TAU * (j as f32) / (sectors as f32);
            let phi2 = std::f32::consts::TAU * ((j + 1) as f32) / (sectors as f32);

            let v0 = sphere_point(radius, theta1, phi1);
            let v1 = sphere_point(radius, theta2, phi1);
            let v2 = sphere_point(radius, theta2, phi2);
            let v3 = sphere_point(radius, theta1, phi2);

            // UVs match scene3d: u from sector, v from stack.
            let u0 = Vec2::new(j as f32 / sectors as f32, i as f32 / stacks as f32);
            let u1 = Vec2::new(j as f32 / sectors as f32, (i + 1) as f32 / stacks as f32);
            let u2 = Vec2::new((j + 1) as f32 / sectors as f32, (i + 1) as f32 / stacks as f32);
            let u3 = Vec2::new((j + 1) as f32 / sectors as f32, i as f32 / stacks as f32);

            if i != 0 {
                triangles.push(Triangle::new_uv(v0, v1, v2, v0.normalize(), u0, u1, u2));
            }
            if i != stacks - 1 {
                triangles.push(Triangle::new_uv(v0, v2, v3, v0.normalize(), u0, u2, u3));
            }
        }
    }
    triangles
}

fn sphere_point(radius: f32, theta: f32, phi: f32) -> Vec3 {
    Vec3::new(
        radius * theta.sin() * phi.cos(),
        radius * theta.cos(),
        radius * theta.sin() * phi.sin(),
    )
}

fn generate_plane(size: f32) -> Vec<Triangle> {
    let h = size / 2.0;
    let u0 = Vec2::new(0.0, 0.0);
    let u1 = Vec2::new(1.0, 0.0);
    let u2 = Vec2::new(1.0, 1.0);
    let u3 = Vec2::new(0.0, 1.0);
    vec![
        Triangle::new_uv(
            Vec3::new(-h, 0.0, -h),
            Vec3::new(h, 0.0, -h),
            Vec3::new(h, 0.0, h),
            Vec3::Y,
            u0,
            u1,
            u2,
        ),
        Triangle::new_uv(
            Vec3::new(-h, 0.0, -h),
            Vec3::new(h, 0.0, h),
            Vec3::new(-h, 0.0, h),
            Vec3::Y,
            u0,
            u2,
            u3,
        ),
    ]
}

fn generate_cylinder(radius: f32, height: f32, segments: u32) -> Vec<Triangle> {
    let mut triangles = Vec::new();
    let half_h = height / 2.0;

    for i in 0..segments {
        let angle1 = std::f32::consts::TAU * (i as f32) / (segments as f32);
        let angle2 = std::f32::consts::TAU * ((i + 1) as f32) / (segments as f32);

        let x1 = radius * angle1.cos();
        let z1 = radius * angle1.sin();
        let x2 = radius * angle2.cos();
        let z2 = radius * angle2.sin();

        // Side faces (UVs wrap around: u from segment, v from height)
        let normal = Vec3::new((x1 + x2) / 2.0, 0.0, (z1 + z2) / 2.0).normalize();
        let u_lo = i as f32 / segments as f32;
        let u_hi = (i + 1) as f32 / segments as f32;
        triangles.push(Triangle::new_uv(
            Vec3::new(x1, -half_h, z1),
            Vec3::new(x2, -half_h, z2),
            Vec3::new(x2, half_h, z2),
            normal,
            Vec2::new(u_lo, 0.0),
            Vec2::new(u_hi, 0.0),
            Vec2::new(u_hi, 1.0),
        ));
        triangles.push(Triangle::new_uv(
            Vec3::new(x1, -half_h, z1),
            Vec3::new(x2, half_h, z2),
            Vec3::new(x1, half_h, z1),
            normal,
            Vec2::new(u_lo, 0.0),
            Vec2::new(u_hi, 1.0),
            Vec2::new(u_lo, 1.0),
        ));

        // Top cap
        triangles.push(Triangle::new(
            Vec3::new(0.0, half_h, 0.0),
            Vec3::new(x1, half_h, z1),
            Vec3::new(x2, half_h, z2),
            Vec3::Y,
        ));

        // Bottom cap
        triangles.push(Triangle::new(
            Vec3::new(0.0, -half_h, 0.0),
            Vec3::new(x2, -half_h, z2),
            Vec3::new(x1, -half_h, z1),
            -Vec3::Y,
        ));
    }
    triangles
}

fn generate_cone(radius: f32, height: f32, segments: u32) -> Vec<Triangle> {
    let mut triangles = Vec::new();
    let apex = Vec3::new(0.0, height, 0.0);

    for i in 0..segments {
        let angle1 = std::f32::consts::TAU * (i as f32) / (segments as f32);
        let angle2 = std::f32::consts::TAU * ((i + 1) as f32) / (segments as f32);

        let x1 = radius * angle1.cos();
        let z1 = radius * angle1.sin();
        let x2 = radius * angle2.cos();
        let z2 = radius * angle2.sin();

        // Side
        let side_normal = Vec3::new((x1 + x2) / 2.0, radius / height, (z1 + z2) / 2.0).normalize();
        triangles.push(Triangle::new(
            Vec3::new(x1, 0.0, z1),
            Vec3::new(x2, 0.0, z2),
            apex,
            side_normal,
        ));

        // Base
        triangles.push(Triangle::new(
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(x2, 0.0, z2),
            Vec3::new(x1, 0.0, z1),
            -Vec3::Y,
        ));
    }
    triangles
}

fn generate_torus(
    radius: f32,
    tube_radius: f32,
    radial_segments: u32,
    tubular_segments: u32,
) -> Vec<Triangle> {
    let mut triangles = Vec::new();

    for i in 0..radial_segments {
        let theta1 = std::f32::consts::TAU * (i as f32) / (radial_segments as f32);
        let theta2 = std::f32::consts::TAU * ((i + 1) as f32) / (radial_segments as f32);

        for j in 0..tubular_segments {
            let phi1 = std::f32::consts::TAU * (j as f32) / (tubular_segments as f32);
            let phi2 = std::f32::consts::TAU * ((j + 1) as f32) / (tubular_segments as f32);

            let v00 = torus_point(radius, tube_radius, theta1, phi1);
            let v10 = torus_point(radius, tube_radius, theta2, phi1);
            let v11 = torus_point(radius, tube_radius, theta2, phi2);
            let v01 = torus_point(radius, tube_radius, theta1, phi2);

            triangles.push(Triangle::from_vertices(v00, v10, v11));
            triangles.push(Triangle::from_vertices(v00, v11, v01));
        }
    }
    triangles
}

fn torus_point(radius: f32, tube_radius: f32, theta: f32, phi: f32) -> Vec3 {
    let r = radius + tube_radius * phi.cos();
    Vec3::new(r * theta.cos(), tube_radius * phi.sin(), r * theta.sin())
}

// ── Camera ───────────────────────────────────────────────────────────

struct CameraState {
    position: Vec3,
    forward: Vec3,
    up: Vec3,
    fov: f32,
    near: f32,
    far: f32,
    is_ortho: bool,
}

impl CameraState {
    fn build_view_projection(&self, aspect: f32) -> Mat4 {
        let view = Mat4::look_to_rh(self.position, self.forward, self.up);
        let projection = if self.is_ortho {
            let half_h = 10.0;
            let half_w = half_h * aspect;
            Mat4::orthographic_rh(-half_w, half_w, -half_h, half_h, self.near, self.far)
        } else {
            Mat4::perspective_rh(self.fov.to_radians(), aspect, self.near, self.far)
        };
        projection * view
    }
}

// ── Lighting ─────────────────────────────────────────────────────────

#[derive(Debug, Clone)]
struct LightState {
    light_type: LightStateType,
    position: Vec3,
    direction: Vec3,
    color: Vec3,
    intensity: f32,
    /// Point/spot reach. `None` = unbounded (inverse-square only).
    range: Option<f32>,
}

#[derive(Debug, Clone)]
enum LightStateType {
    Point,
    Directional,
    Spot,
}

/// Procedural texture kinds (parity with scene3d's `TextureType`). Sampled
/// per-triangle at the centroid UV between `base_color` and `texture_color2`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum TextureKind {
    None,
    Checkerboard,
    Stripes,
    Gradient,
    Noise,
}

impl TextureKind {
    fn from_str(s: Option<&str>) -> Self {
        match s.map(|t| t.to_ascii_lowercase()).as_deref() {
            Some("checkerboard") => TextureKind::Checkerboard,
            Some("stripes") => TextureKind::Stripes,
            Some("gradient") => TextureKind::Gradient,
            Some("noise") => TextureKind::Noise,
            _ => TextureKind::None,
        }
    }
}

struct MaterialState {
    base_color: Vec3,
    metallic: f32,
    roughness: f32,
    /// `emissive * emissive_strength`, premultiplied at construction.
    emissive: Vec3,
    alpha: f32,
    /// When true, skip Blinn-Phong and output `base_color + emissive` directly.
    unlit: bool,
    /// Procedural texture; `None` means the flat `base_color` is used.
    texture: TextureKind,
    /// Secondary color the procedural texture blends toward.
    texture_color2: Vec3,
    /// UV tiling factor for the procedural texture.
    texture_scale: f32,
}

impl MaterialState {
    fn from_def(def: &MaterialDef) -> Self {
        // Explicit scalar `alpha` wins; otherwise fall back to `base_color.a`.
        let alpha = def
            .alpha
            .unwrap_or_else(|| def.base_color.as_ref().map(|c| c.a).unwrap_or(1.0));
        let strength = def.emissive_strength.unwrap_or(1.0);
        Self {
            base_color: def
                .base_color
                .as_ref()
                .map(|c| c.to_vec3())
                .unwrap_or(Vec3::new(0.8, 0.8, 0.8)),
            metallic: def.metallic.unwrap_or(0.0),
            roughness: def.roughness.unwrap_or(0.5),
            emissive: def
                .emissive
                .as_ref()
                .map(|c| c.to_vec3())
                .unwrap_or(Vec3::ZERO)
                * strength,
            alpha,
            unlit: def.unlit,
            texture: TextureKind::from_str(def.texture.as_deref()),
            // scene3d defaults texture_color2 to (0.3,0.3,0.3) and scale to 1.0.
            texture_color2: def
                .texture_color2
                .as_ref()
                .map(|c| c.to_vec3())
                .unwrap_or(Vec3::new(0.3, 0.3, 0.3)),
            texture_scale: def.texture_scale.unwrap_or(1.0),
        }
    }

    /// Sample the procedural texture at `uv`, returning the effective base color.
    fn sample_texture(&self, uv: Vec2) -> Vec3 {
        sample_texture_kind(
            self.texture,
            self.base_color,
            self.texture_color2,
            self.texture_scale,
            uv,
        )
    }
}

/// Sample a procedural texture, returning the effective albedo. Mirrors
/// `Material3D.sampleTexture` in scene3d/core.dart so both renderers produce
/// matching window grids, asphalt noise, stripes and gradients.
#[inline]
fn sample_texture_kind(
    kind: TextureKind,
    base_color: Vec3,
    texture_color2: Vec3,
    texture_scale: f32,
    uv: Vec2,
) -> Vec3 {
    match kind {
        TextureKind::None => base_color,
        TextureKind::Checkerboard => {
            let u = (uv.x * texture_scale).floor() as i64;
            let v = (uv.y * texture_scale).floor() as i64;
            if (u + v).rem_euclid(2) == 0 {
                base_color
            } else {
                texture_color2
            }
        }
        TextureKind::Stripes => {
            let s = ((uv.x * texture_scale * 10.0).floor() as i64).rem_euclid(2) == 0;
            if s {
                base_color
            } else {
                texture_color2
            }
        }
        TextureKind::Gradient => base_color.lerp(texture_color2, uv.y),
        TextureKind::Noise => {
            let n = simple_noise(uv.x * texture_scale, uv.y * texture_scale);
            base_color * (0.5 + 0.5 * n)
        }
    }
}

/// Cheap hash-based value noise matching scene3d's `_simpleNoise`.
#[inline]
fn simple_noise(x: f32, y: f32) -> f32 {
    let n = (x * 12.9898 + y * 78.233).sin() * 43758.5453;
    n - n.floor()
}

struct EnvironmentSettings {
    ambient_color: Vec3,
    ambient_intensity: f32,
    fog_enabled: bool,
    /// True for `fog_type:"linear"` (near→distance ramp); false uses the legacy
    /// squared falloff over `fog_distance`.
    fog_linear: bool,
    fog_color: Vec3,
    fog_near: f32,
    fog_distance: f32,
    /// Vertical sky gradient (top, bottom) used to clear the frame. `None` keeps
    /// the flat clear color.
    sky_gradient: Option<(Vec3, Vec3)>,
}

impl Default for EnvironmentSettings {
    fn default() -> Self {
        Self {
            ambient_color: Vec3::ONE,
            ambient_intensity: 0.3,
            fog_enabled: false,
            fog_linear: false,
            fog_color: Vec3::new(0.7, 0.7, 0.8),
            fog_near: 0.0,
            fog_distance: 100.0,
            sky_gradient: None,
        }
    }
}

/// Decomposed shading for a surface point, independent of the surface *albedo*
/// so the albedo (procedural texture) can be sampled per pixel:
/// `final = albedo * light_mul + additive`, then blended toward fog.
struct LightingResult {
    /// Albedo multiplier: ambient + incoming diffuse light. `Vec3::ONE` for unlit.
    light_mul: Vec3,
    /// Albedo-independent term: specular + emissive.
    additive: Vec3,
    fog_factor: f32,
    fog_color: Vec3,
}

impl LightingResult {
    /// Resolve to a final RGB color for a given albedo (texture sample).
    #[inline]
    fn resolve(&self, albedo: Vec3) -> [f32; 3] {
        let pre = albedo * self.light_mul + self.additive;
        let c = pre.lerp(self.fog_color, self.fog_factor);
        [c.x, c.y, c.z]
    }
}

/// Compute Blinn-Phong lighting for a surface point, returning the albedo-independent
/// decomposition. Folding the surface albedo back in via `LightingResult::resolve`
/// reproduces the previous single-color result exactly (golden-stable), while also
/// enabling per-pixel texture sampling in the rasterizer.
fn shade(
    position: Vec3,
    normal: Vec3,
    camera: &CameraState,
    lights: &[LightState],
    material: &MaterialState,
    env: &EnvironmentSettings,
) -> LightingResult {
    let fog_factor = fog_factor(position, camera, env);
    let fog_color = env.fog_color;

    // Unlit surfaces (paint markings, neon, tracers, fx) bypass shading: the
    // albedo passes straight through (`light_mul = 1`) plus emissive.
    if material.unlit {
        return LightingResult {
            light_mul: Vec3::ONE,
            additive: material.emissive,
            fog_factor,
            fog_color,
        };
    }

    let n = normal.normalize();
    let view_dir = (camera.position - position).normalize();

    // Ambient + diffuse accumulate into the albedo multiplier; specular is additive.
    let mut light_mul = env.ambient_color * env.ambient_intensity;
    let mut specular_total = Vec3::ZERO;

    for light in lights {
        let (light_dir, attenuation) = match light.light_type {
            LightStateType::Directional => (-light.direction.normalize(), 1.0),
            LightStateType::Point => {
                let to_light = light.position - position;
                let dist = to_light.length();
                let dir = to_light / dist.max(0.001);
                let att = 1.0 / (1.0 + 0.09 * dist + 0.032 * dist * dist)
                    * range_falloff(dist, light.range);
                (dir, att)
            }
            LightStateType::Spot => {
                let to_light = light.position - position;
                let dist = to_light.length();
                let dir = to_light / dist.max(0.001);
                let spot_dot = dir.dot(-light.direction.normalize());
                let spot_att = if spot_dot > 0.9 {
                    1.0
                } else if spot_dot > 0.8 {
                    (spot_dot - 0.8) * 10.0
                } else {
                    0.0
                };
                let att = spot_att / (1.0 + 0.09 * dist + 0.032 * dist * dist)
                    * range_falloff(dist, light.range);
                (dir, att)
            }
        };

        // Diffuse (Lambert) — accumulates into the albedo multiplier.
        let n_dot_l = n.dot(light_dir).max(0.0);
        light_mul += light.color * light.intensity * n_dot_l * attenuation;

        // Specular (Blinn-Phong) — albedo-independent.
        let half_vec = (light_dir + view_dir).normalize();
        let n_dot_h = n.dot(half_vec).max(0.0);
        let shininess = ((1.0 - material.roughness) * 128.0).max(1.0);
        let spec_strength = if material.metallic > 0.0 {
            material.metallic * 0.8
        } else {
            0.04
        };
        specular_total +=
            light.color * light.intensity * n_dot_h.powf(shininess) * spec_strength * attenuation;
    }

    LightingResult {
        light_mul,
        additive: specular_total + material.emissive,
        fog_factor,
        fog_color,
    }
}

/// Smooth point/spot-light cutoff: full strength near the source, fading to zero
/// at `range` (windowed so geometry just past the radius doesn't pop). `None`
/// keeps the unbounded inverse-square falloff.
#[inline]
fn range_falloff(dist: f32, range: Option<f32>) -> f32 {
    match range {
        None => 1.0,
        Some(r) if r <= 0.0 => 1.0,
        Some(r) => {
            let x = (dist / r).clamp(0.0, 1.0);
            let w = 1.0 - x * x;
            (w * w).clamp(0.0, 1.0)
        }
    }
}

/// Fog blend factor (0 = no fog, 1 = fully fogged) by distance from the camera.
/// `linear` fog ramps from `fog_near`→`fog_distance`; otherwise a squared falloff
/// over `fog_distance` (legacy behavior) is used. Zero when fog is disabled.
#[inline]
fn fog_factor(position: Vec3, camera: &CameraState, env: &EnvironmentSettings) -> f32 {
    if !env.fog_enabled {
        return 0.0;
    }
    let dist = (camera.position - position).length();
    if env.fog_linear {
        let near = env.fog_near;
        let far = env.fog_distance.max(near + 0.001);
        ((dist - near) / (far - near)).clamp(0.0, 1.0)
    } else {
        let f = (dist / env.fog_distance).clamp(0.0, 1.0);
        f * f
    }
}

fn apply_easing(progress: f32, easing: &EasingType) -> f32 {
    match easing {
        EasingType::Linear => progress,
        EasingType::EaseIn => progress * progress,
        EasingType::EaseOut => progress * (2.0 - progress),
        EasingType::EaseInOut => {
            if progress < 0.5 {
                2.0 * progress * progress
            } else {
                -1.0 + (4.0 - 2.0 * progress) * progress
            }
        }
        EasingType::Bounce => {
            let n1 = 7.5625;
            let d1 = 2.75;
            if progress < 1.0 / d1 {
                n1 * progress * progress
            } else if progress < 2.0 / d1 {
                let p = progress - 1.5 / d1;
                n1 * p * p + 0.75
            } else if progress < 2.5 / d1 {
                let p = progress - 2.25 / d1;
                n1 * p * p + 0.9375
            } else {
                let p = progress - 2.625 / d1;
                n1 * p * p + 0.984375
            }
        }
    }
}
