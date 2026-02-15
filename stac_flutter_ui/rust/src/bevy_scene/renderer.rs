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

use glam::{Vec2, Vec3, Vec4, Mat4};

use crate::bevy_scene::schema::*;

// ── Renderer Core ────────────────────────────────────────────────────

pub struct SceneRenderer {
    pub width: u32,
    pub height: u32,
    pub pixels: Vec<u8>,    // RGBA8, length = width * height * 4
    pub depth: Vec<f32>,    // depth buffer, length = width * height
    pub elapsed_time: f32,
}

impl SceneRenderer {
    pub fn new(width: u32, height: u32) -> Self {
        let pixel_count = (width * height) as usize;
        Self {
            width,
            height,
            pixels: vec![0u8; pixel_count * 4],
            depth: vec![f32::INFINITY; pixel_count],
            elapsed_time: 0.0,
        }
    }

    pub fn resize(&mut self, width: u32, height: u32) {
        self.width = width;
        self.height = height;
        let pixel_count = (width * height) as usize;
        self.pixels.resize(pixel_count * 4, 0);
        self.depth.resize(pixel_count, f32::INFINITY);
    }

    /// Clear framebuffer with a background color.
    pub fn clear(&mut self, color: [u8; 4]) {
        for i in 0..(self.width * self.height) as usize {
            let idx = i * 4;
            self.pixels[idx] = color[0];
            self.pixels[idx + 1] = color[1];
            self.pixels[idx + 2] = color[2];
            self.pixels[idx + 3] = color[3];
        }
        for d in self.depth.iter_mut() {
            *d = f32::INFINITY;
        }
    }

    /// Render a complete scene from JSON definition.
    pub fn render_scene(&mut self, scene: &SceneDef, delta_time: f32) {
        self.elapsed_time += delta_time;

        // Collect environment settings
        let mut env = EnvironmentSettings::default();
        for node in &scene.world {
            if let JsonNode::Environment(e) = node {
                env.ambient_intensity = e.ambient_intensity;
                if let Some(ref al) = e.ambient_light {
                    env.ambient_color = al.to_vec3();
                }
                env.fog_enabled = e.fog_enabled;
                env.fog_distance = e.fog_distance;
                if let Some(ref fc) = e.fog_color {
                    env.fog_color = fc.to_vec3();
                }
            }
        }

        // Determine sky/clear color from environment or skybox
        let mut clear_color = [20u8, 20u8, 30u8, 255u8];
        for node in &scene.world {
            if let JsonNode::Skybox(sky) = node {
                if let Some(ref c) = sky.color {
                    clear_color = c.to_rgba_u8();
                }
            }
        }
        self.clear(clear_color);

        // Collect camera
        let camera = self.find_camera(&scene.world);

        // Collect lights
        let lights = self.collect_lights(&scene.world);

        // Build view-projection matrix
        let aspect = self.width as f32 / self.height.max(1) as f32;
        let view_proj = camera.build_view_projection(aspect);

        // Render all world nodes
        for node in &scene.world {
            self.render_world_node(node, &Mat4::IDENTITY, &view_proj, &camera, &lights, &env);
        }
    }

    fn find_camera(&self, nodes: &[JsonNode]) -> CameraState {
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

    fn collect_lights(&self, nodes: &[JsonNode]) -> Vec<LightState> {
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
                let local = self.compute_animated_transform(
                    &mesh.transform,
                    &mesh.animation,
                );
                let world = *parent_transform * local;
                let material = MaterialState::from_def(&mesh.material);
                let triangles = generate_mesh_triangles(&mesh.mesh);
                self.rasterize_triangles(&triangles, &world, view_proj, camera, lights, &material, env);

                // Render children
                for child in &mesh.children {
                    self.render_world_node(child, &world, view_proj, camera, lights, env);
                }
            }
            JsonNode::RigidBody(rb) => {
                let local = rb.transform.to_mat4();
                let world = *parent_transform * local;
                let material = MaterialState::from_def(&rb.material);
                let triangles = generate_mesh_triangles(&rb.mesh);
                self.rasterize_triangles(&triangles, &world, view_proj, camera, lights, &material, env);
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
                self.rasterize_triangles(&triangles, &world, view_proj, camera, lights, &material, env);
            }
            JsonNode::Water(water) => {
                let local = water.transform.to_mat4();
                let world = *parent_transform * local;
                let wc = water.water_color.as_ref().map(|c| c.to_vec3())
                    .unwrap_or(Vec3::new(0.0, 0.5, 1.0));
                let material = MaterialState {
                    base_color: wc,
                    metallic: 0.6,
                    roughness: 0.2,
                    emissive: Vec3::ZERO,
                    alpha: water.transparency,
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
                self.rasterize_triangles(&triangles, &world, view_proj, camera, lights, &material, env);
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
                if axis_vec == Vec3::ZERO { return base_mat; }
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
            AnimationType::Pulse { min_scale, max_scale } => {
                let s = min_scale + (max_scale - min_scale) *
                    (0.5 + 0.5 * (t * std::f32::consts::TAU).sin());
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
        };

        // Simple particle rendering: scatter small spheres based on time
        let count = (particle.emission_rate * particle.lifetime).ceil() as i32;
        let count = count.min(100); // cap for performance

        for i in 0..count {
            let spawn_time = (i as f32) / particle.emission_rate;
            let age = (self.elapsed_time - spawn_time) % particle.lifetime;
            if age < 0.0 { continue; }

            // Particle position: base + velocity*age + 0.5*gravity*age^2
            let vel = particle.velocity.to_glam();
            let grav = particle.gravity.to_glam();
            let offset = vel * age + grav * 0.5 * age * age;

            let particle_world = *world * Mat4::from_translation(offset) *
                Mat4::from_scale(Vec3::splat(particle.size));

            let triangles = generate_mesh_triangles(&MeshType::Named(MeshTypeName::Cube));
            self.rasterize_triangles(&triangles, &particle_world, view_proj, camera, lights, &material, env);
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

            // Compute lighting for triangle center (flat shading)
            let center = (w0 + w1 + w2) / 3.0;
            let lit_color = compute_lighting(center, n, camera, lights, material, env);

            if inside_count == 3 {
                // All vertices in front: render directly
                let ndc0 = Vec3::new(c0.x / c0.w, c0.y / c0.w, c0.z / c0.w);
                let ndc1 = Vec3::new(c1.x / c1.w, c1.y / c1.w, c1.z / c1.w);
                let ndc2 = Vec3::new(c2.x / c2.w, c2.y / c2.w, c2.z / c2.w);

                let s0 = self.ndc_to_screen(ndc0);
                let s1 = self.ndc_to_screen(ndc1);
                let s2 = self.ndc_to_screen(ndc2);

                self.fill_triangle(s0, s1, s2, ndc0.z, ndc1.z, ndc2.z, &lit_color, material.alpha);
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

                        self.fill_triangle(sa, sb, sc, ndc_a.z, ndc_b.z, ndc_c.z, &lit_color, material.alpha);
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

    fn fill_triangle(
        &mut self,
        v0: Vec2, v1: Vec2, v2: Vec2,
        z0: f32, z1: f32, z2: f32,
        color: &[f32; 3],
        alpha: f32,
    ) {
        // Bounding box
        let min_x = v0.x.min(v1.x).min(v2.x).max(0.0) as i32;
        let max_x = v0.x.max(v1.x).max(v2.x).min(self.width as f32 - 1.0) as i32;
        let min_y = v0.y.min(v1.y).min(v2.y).max(0.0) as i32;
        let max_y = v0.y.max(v1.y).max(v2.y).min(self.height as f32 - 1.0) as i32;

        let area = edge_function(v0, v1, v2);
        if area.abs() < 0.001 { return; } // Degenerate triangle
        let inv_area = 1.0 / area;

        for y in min_y..=max_y {
            for x in min_x..=max_x {
                let p = Vec2::new(x as f32 + 0.5, y as f32 + 0.5);

                let w0 = edge_function(v1, v2, p) * inv_area;
                let w1 = edge_function(v2, v0, p) * inv_area;
                let w2 = edge_function(v0, v1, p) * inv_area;

                // Inside triangle?
                if w0 >= 0.0 && w1 >= 0.0 && w2 >= 0.0 {
                    // Interpolate depth
                    let z = w0 * z0 + w1 * z1 + w2 * z2;

                    let idx = (y as u32 * self.width + x as u32) as usize;

                    // Depth test
                    if z < self.depth[idx] {
                        self.depth[idx] = z;

                        let r = (color[0].clamp(0.0, 1.0) * 255.0) as u8;
                        let g = (color[1].clamp(0.0, 1.0) * 255.0) as u8;
                        let b = (color[2].clamp(0.0, 1.0) * 255.0) as u8;
                        let a = (alpha.clamp(0.0, 1.0) * 255.0) as u8;

                        let pidx = idx * 4;
                        if alpha >= 1.0 {
                            self.pixels[pidx] = r;
                            self.pixels[pidx + 1] = g;
                            self.pixels[pidx + 2] = b;
                            self.pixels[pidx + 3] = a;
                        } else {
                            // Alpha blending
                            let dst_r = self.pixels[pidx] as f32 / 255.0;
                            let dst_g = self.pixels[pidx + 1] as f32 / 255.0;
                            let dst_b = self.pixels[pidx + 2] as f32 / 255.0;
                            let src_a = alpha;
                            self.pixels[pidx] = ((color[0] * src_a + dst_r * (1.0 - src_a)).clamp(0.0, 1.0) * 255.0) as u8;
                            self.pixels[pidx + 1] = ((color[1] * src_a + dst_g * (1.0 - src_a)).clamp(0.0, 1.0) * 255.0) as u8;
                            self.pixels[pidx + 2] = ((color[2] * src_a + dst_b * (1.0 - src_a)).clamp(0.0, 1.0) * 255.0) as u8;
                            self.pixels[pidx + 3] = 255;
                        }
                    }
                }
            }
        }
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
}

impl Triangle {
    pub fn new(v0: Vec3, v1: Vec3, v2: Vec3, normal: Vec3) -> Self {
        Self { v0, v1, v2, normal }
    }

    pub fn from_vertices(v0: Vec3, v1: Vec3, v2: Vec3) -> Self {
        let edge1 = v1 - v0;
        let edge2 = v2 - v0;
        let normal = edge1.cross(edge2).normalize();
        Self { v0, v1, v2, normal }
    }
}

fn edge_function(a: Vec2, b: Vec2, c: Vec2) -> f32 {
    (c.x - a.x) * (b.y - a.y) - (c.y - a.y) * (b.x - a.x)
}

/// Generate triangles for a mesh type.
pub fn generate_mesh_triangles(mesh_type: &MeshType) -> Vec<Triangle> {
    match mesh_type {
        MeshType::Named(MeshTypeName::Cube) => generate_cube(1.0),
        MeshType::Parameterized(param) => match param {
            MeshTypeParam::Sphere { radius, subdivisions } => {
                generate_uv_sphere(*radius, (*subdivisions).max(4))
            }
            MeshTypeParam::Plane { size } => generate_plane(*size),
            MeshTypeParam::Cylinder { radius, height } => {
                generate_cylinder(*radius, *height, 16)
            }
            MeshTypeParam::Cone { radius, height } => {
                generate_cone(*radius, *height, 16)
            }
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
            MeshTypeParam::Torus { radius, tube_radius } => {
                generate_torus(*radius, *tube_radius, 24, 12)
            }
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
        Vec3::new(-h, -h, h), Vec3::new(h, -h, h), Vec3::new(h, h, h), Vec3::new(-h, h, h),
        // Back face
        Vec3::new(-h, -h, -h), Vec3::new(-h, h, -h), Vec3::new(h, h, -h), Vec3::new(h, -h, -h),
        // Top face
        Vec3::new(-h, h, -h), Vec3::new(-h, h, h), Vec3::new(h, h, h), Vec3::new(h, h, -h),
        // Bottom face
        Vec3::new(-h, -h, -h), Vec3::new(h, -h, -h), Vec3::new(h, -h, h), Vec3::new(-h, -h, h),
        // Right face
        Vec3::new(h, -h, -h), Vec3::new(h, h, -h), Vec3::new(h, h, h), Vec3::new(h, -h, h),
        // Left face
        Vec3::new(-h, -h, -h), Vec3::new(-h, -h, h), Vec3::new(-h, h, h), Vec3::new(-h, h, -h),
    ];

    let normals = [
        Vec3::new(0.0, 0.0, 1.0),  // Front
        Vec3::new(0.0, 0.0, -1.0), // Back
        Vec3::new(0.0, 1.0, 0.0),  // Top
        Vec3::new(0.0, -1.0, 0.0), // Bottom
        Vec3::new(1.0, 0.0, 0.0),  // Right
        Vec3::new(-1.0, 0.0, 0.0), // Left
    ];

    let mut triangles = Vec::with_capacity(12);
    for face in 0..6 {
        let base = face * 4;
        triangles.push(Triangle::new(vertices[base], vertices[base + 1], vertices[base + 2], normals[face]));
        triangles.push(Triangle::new(vertices[base], vertices[base + 2], vertices[base + 3], normals[face]));
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

            if i != 0 {
                triangles.push(Triangle::new(v0, v1, v2, v0.normalize()));
            }
            if i != stacks - 1 {
                triangles.push(Triangle::new(v0, v2, v3, v0.normalize()));
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
    vec![
        Triangle::new(
            Vec3::new(-h, 0.0, -h),
            Vec3::new(h, 0.0, -h),
            Vec3::new(h, 0.0, h),
            Vec3::Y,
        ),
        Triangle::new(
            Vec3::new(-h, 0.0, -h),
            Vec3::new(h, 0.0, h),
            Vec3::new(-h, 0.0, h),
            Vec3::Y,
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

        // Side faces
        let normal = Vec3::new((x1 + x2) / 2.0, 0.0, (z1 + z2) / 2.0).normalize();
        triangles.push(Triangle::new(
            Vec3::new(x1, -half_h, z1),
            Vec3::new(x2, -half_h, z2),
            Vec3::new(x2, half_h, z2),
            normal,
        ));
        triangles.push(Triangle::new(
            Vec3::new(x1, -half_h, z1),
            Vec3::new(x2, half_h, z2),
            Vec3::new(x1, half_h, z1),
            normal,
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

fn generate_torus(radius: f32, tube_radius: f32, radial_segments: u32, tubular_segments: u32) -> Vec<Triangle> {
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
    Vec3::new(
        r * theta.cos(),
        tube_radius * phi.sin(),
        r * theta.sin(),
    )
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
            Mat4::perspective_rh(
                self.fov.to_radians(),
                aspect,
                self.near,
                self.far,
            )
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
}

#[derive(Debug, Clone)]
enum LightStateType {
    Point,
    Directional,
    Spot,
}

struct MaterialState {
    base_color: Vec3,
    metallic: f32,
    roughness: f32,
    emissive: Vec3,
    alpha: f32,
}

impl MaterialState {
    fn from_def(def: &MaterialDef) -> Self {
        let alpha = def.base_color.as_ref().map(|c| c.a).unwrap_or(1.0);
        Self {
            base_color: def.base_color.as_ref().map(|c| c.to_vec3()).unwrap_or(Vec3::new(0.8, 0.8, 0.8)),
            metallic: def.metallic.unwrap_or(0.0),
            roughness: def.roughness.unwrap_or(0.5),
            emissive: def.emissive.as_ref().map(|c| c.to_vec3()).unwrap_or(Vec3::ZERO),
            alpha,
        }
    }
}

struct EnvironmentSettings {
    ambient_color: Vec3,
    ambient_intensity: f32,
    fog_enabled: bool,
    fog_color: Vec3,
    fog_distance: f32,
}

impl Default for EnvironmentSettings {
    fn default() -> Self {
        Self {
            ambient_color: Vec3::ONE,
            ambient_intensity: 0.3,
            fog_enabled: false,
            fog_color: Vec3::new(0.7, 0.7, 0.8),
            fog_distance: 100.0,
        }
    }
}

/// Compute Blinn-Phong lighting for a surface point.
fn compute_lighting(
    position: Vec3,
    normal: Vec3,
    camera: &CameraState,
    lights: &[LightState],
    material: &MaterialState,
    env: &EnvironmentSettings,
) -> [f32; 3] {
    let n = normal.normalize();
    let view_dir = (camera.position - position).normalize();

    // Ambient contribution
    let ambient = env.ambient_color * env.ambient_intensity * material.base_color;

    let mut diffuse_total = Vec3::ZERO;
    let mut specular_total = Vec3::ZERO;

    for light in lights {
        let (light_dir, attenuation) = match light.light_type {
            LightStateType::Directional => {
                (-light.direction.normalize(), 1.0)
            }
            LightStateType::Point => {
                let to_light = light.position - position;
                let dist = to_light.length();
                let dir = to_light / dist.max(0.001);
                let att = 1.0 / (1.0 + 0.09 * dist + 0.032 * dist * dist);
                (dir, att)
            }
            LightStateType::Spot => {
                let to_light = light.position - position;
                let dist = to_light.length();
                let dir = to_light / dist.max(0.001);
                let spot_dot = dir.dot(-light.direction.normalize());
                let spot_att = if spot_dot > 0.9 { 1.0 } else if spot_dot > 0.8 { (spot_dot - 0.8) * 10.0 } else { 0.0 };
                let att = spot_att / (1.0 + 0.09 * dist + 0.032 * dist * dist);
                (dir, att)
            }
        };

        // Diffuse (Lambert)
        let n_dot_l = n.dot(light_dir).max(0.0);
        let diffuse = material.base_color * light.color * light.intensity * n_dot_l * attenuation;

        // Specular (Blinn-Phong)
        let half_vec = (light_dir + view_dir).normalize();
        let n_dot_h = n.dot(half_vec).max(0.0);
        let shininess = ((1.0 - material.roughness) * 128.0).max(1.0);
        let spec_strength = if material.metallic > 0.0 {
            material.metallic * 0.8
        } else {
            0.04
        };
        let specular = light.color * light.intensity * n_dot_h.powf(shininess) * spec_strength * attenuation;

        diffuse_total += diffuse;
        specular_total += specular;
    }

    let mut final_color = ambient + diffuse_total + specular_total + material.emissive;

    // Fog
    if env.fog_enabled {
        let dist = (camera.position - position).length();
        let fog_factor = (dist / env.fog_distance).clamp(0.0, 1.0);
        final_color = final_color.lerp(env.fog_color, fog_factor * fog_factor);
    }

    [final_color.x, final_color.y, final_color.z]
}

fn apply_easing(progress: f32, easing: &EasingType) -> f32 {
    match easing {
        EasingType::Linear => progress,
        EasingType::EaseIn => progress * progress,
        EasingType::EaseOut => progress * (2.0 - progress),
        EasingType::EaseInOut => {
            if progress < 0.5 { 2.0 * progress * progress }
            else { -1.0 + (4.0 - 2.0 * progress) * progress }
        }
        EasingType::Bounce => {
            let n1 = 7.5625;
            let d1 = 2.75;
            if progress < 1.0 / d1 { n1 * progress * progress }
            else if progress < 2.0 / d1 { let p = progress - 1.5 / d1; n1 * p * p + 0.75 }
            else if progress < 2.5 / d1 { let p = progress - 2.25 / d1; n1 * p * p + 0.9375 }
            else { let p = progress - 2.625 / d1; n1 * p * p + 0.984375 }
        }
    }
}
