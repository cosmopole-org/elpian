use bevy::prelude::*;
use crate::graphics::components::*;
use crate::graphics::schema::{AnimationType, EasingType};
use bevy::render::render_resource::{Extent3d, TextureDimension, TextureFormat};
use bevy::prelude::Image;
// RenderTarget alias removed; captured-scene camera is not spawned by default.

#[derive(Resource)]
pub struct CircleMask {
    pub handle: Handle<Image>,
}

#[derive(Resource)]
pub struct RoundedRectImage {
    pub handle: Handle<Image>,
}

#[derive(Resource)]
pub struct ShadowImage {
    pub handle: Handle<Image>,
}

#[derive(Resource)]
pub struct GlassNoise {
    pub handle: Handle<Image>,
}

#[derive(Resource)]
pub struct GlassShader {
    pub handle: Handle<Shader>,
}

#[derive(Resource)]
pub struct CapturedScene {
    pub handle: Handle<Image>,
}

// Generate a procedural circular alpha mask and insert as a resource
pub fn generate_circle_mask_system(mut images: ResMut<Assets<Image>>, mut commands: Commands) {
    let size: u32 = 128;
    let mut data = vec![0u8; (size * size * 4) as usize];

    let center = (size as f32) / 2.0;
    for y in 0..size {
        for x in 0..size {
            let dx = x as f32 + 0.5 - center;
            let dy = y as f32 + 0.5 - center;
            let dist = (dx * dx + dy * dy).sqrt();
            let radius = center;
            let mut t = (radius - dist) / 1.0; // sharp edge; could smooth
            if t < 0.0 { t = 0.0; }
            if t > 1.0 { t = 1.0; }
            // smoothstep for nicer edge
            let alpha = (t * t * (3.0 - 2.0 * t) * 255.0) as u8;

            let idx = ((y * size + x) * 4) as usize;
            data[idx] = 255u8;
            data[idx + 1] = 255u8;
            data[idx + 2] = 255u8;
            data[idx + 3] = alpha;
        }
    }

    let image = Image::new(
        Extent3d {
            width: size,
            height: size,
            depth_or_array_layers: 1,
        },
        TextureDimension::D2,
        data,
        TextureFormat::Rgba8UnormSrgb,
        Default::default(),
    );

    let handle = images.add(image);
    commands.insert_resource(CircleMask { handle });

    // Generate a rounded rectangle mask (white with rounded alpha)
    let size: u32 = 128;
    let mut rdata = vec![0u8; (size * size * 4) as usize];
    let radius = 12.0f32;
    let cr = radius;
    for y in 0..size {
        for x in 0..size {
            let xf = x as f32 + 0.5;
            let yf = y as f32 + 0.5;
            // compute distance to nearest corner center
            let dx = if xf < cr { cr - xf } else if xf > (size as f32 - cr) { xf - (size as f32 - cr) } else { 0.0 };
            let dy = if yf < cr { cr - yf } else if yf > (size as f32 - cr) { yf - (size as f32 - cr) } else { 0.0 };
            let dist = (dx*dx + dy*dy).sqrt();
            let t = (1.0 - (dist / cr)).clamp(0.0, 1.0);
            let alpha = (t * 255.0) as u8;
            let idx = ((y * size + x) * 4) as usize;
            rdata[idx] = 255u8;
            rdata[idx + 1] = 255u8;
            rdata[idx + 2] = 255u8;
            rdata[idx + 3] = alpha;
        }
    }
    let rimg = Image::new(
        Extent3d { width: size, height: size, depth_or_array_layers: 1 },
        TextureDimension::D2,
        rdata,
        TextureFormat::Rgba8UnormSrgb,
        Default::default(),
    );
    let rhandle = images.add(rimg);
    commands.insert_resource(RoundedRectImage { handle: rhandle });

    // Generate a soft circular shadow texture (blurred circle) for simple shadows
    let s_size: u32 = 256;
    let mut sdata = vec![0u8; (s_size * s_size * 4) as usize];
    let center = (s_size as f32) / 2.0;
    for y in 0..s_size {
        for x in 0..s_size {
            let dx = x as f32 + 0.5 - center;
            let dy = y as f32 + 0.5 - center;
            let dist = (dx*dx + dy*dy).sqrt();
            let maxr = center * 0.9;
            let t = (1.0 - (dist / maxr)).clamp(0.0, 1.0);
            // smoother falloff
            let alpha = ((t * t) * 180.0) as u8; // max shadow alpha
            let idx = ((y * s_size + x) * 4) as usize;
            sdata[idx] = 0u8;
            sdata[idx + 1] = 0u8;
            sdata[idx + 2] = 0u8;
            sdata[idx + 3] = alpha;
        }
    }
    let simg = Image::new(
        Extent3d { width: s_size, height: s_size, depth_or_array_layers: 1 },
        TextureDimension::D2,
        sdata,
        TextureFormat::Rgba8UnormSrgb,
        Default::default(),
    );
    let shandle = images.add(simg);
    commands.insert_resource(ShadowImage { handle: shandle });

    // Generate simple glass noise/overlay texture (solid white, will be tinted by opacity)
    let g_size: u32 = 32;
    let mut gdata = vec![0u8; (g_size * g_size * 4) as usize];
    for y in 0..g_size {
        for x in 0..g_size {
            let idx = ((y * g_size + x) * 4) as usize;
            gdata[idx] = 255u8;
            gdata[idx + 1] = 255u8;
            gdata[idx + 2] = 255u8;
            gdata[idx + 3] = 255u8;
        }
    }
    let gimg = Image::new(
        Extent3d { width: g_size, height: g_size, depth_or_array_layers: 1 },
        TextureDimension::D2,
        gdata,
        TextureFormat::Rgba8UnormSrgb,
        Default::default(),
    );
    let ghandle = images.add(gimg);
    commands.insert_resource(GlassNoise { handle: ghandle });

    // Create a placeholder captured scene image resource. This will be replaced
    // later by a true render-graph capture node that writes the main color
    // attachment into this image each frame. For now we provide a small low-res
    // texture so glass overlays can sample something and the pipeline compiles.
    let c_size: u32 = 16;
    let mut cdata = vec![0u8; (c_size * c_size * 4) as usize];
    // Fill with a subtle gray so the glass overlay has visible content
    for y in 0..c_size {
        for x in 0..c_size {
            let idx = ((y * c_size + x) * 4) as usize;
            cdata[idx] = 200u8;
            cdata[idx + 1] = 200u8;
            cdata[idx + 2] = 200u8;
            cdata[idx + 3] = 255u8;
        }
    }
    let cimg = Image::new(
        Extent3d { width: c_size, height: c_size, depth_or_array_layers: 1 },
        TextureDimension::D2,
        cdata,
        TextureFormat::Rgba8UnormSrgb,
        Default::default(),
    );
    // Ensure this image can be used as a render target by the camera: add RENDER_ATTACHMENT usage
    let mut cimg = cimg;
    cimg.texture_descriptor.usage = bevy::render::render_resource::TextureUsages::RENDER_ATTACHMENT
        | bevy::render::render_resource::TextureUsages::TEXTURE_BINDING
        | bevy::render::render_resource::TextureUsages::COPY_SRC;
    let chandle = images.add(cimg);
    commands.insert_resource(CapturedScene { handle: chandle });

    // Note: shader asset is loaded separately in startup using AssetServer
}

pub fn load_glass_shader_system(asset_server: Res<AssetServer>, mut commands: Commands) {
    let handle: Handle<Shader> = asset_server.load("shaders/glass.wgsl");
    commands.insert_resource(GlassShader { handle });
}

// Generate a blurred, cropped Image for each glass overlay by sampling the
// CapturedScene image on the CPU. This is a pragmatic fallback to obtain a
// backdrop-blur look without full render-graph shader plumbing.
pub fn blur_captured_overlays_system(
    mut commands: Commands,
    mut images: ResMut<Assets<Image>>,
    captured: Option<Res<CapturedScene>>,
    mut query: Query<(Entity, &ImageNode, &Node), With<crate::graphics::components::GlassOverlay>>,
) {
    let captured = match captured {
        Some(c) => c,
        None => return,
    };

    // Obtain the source captured image
    let src_image = match images.get(&captured.handle) {
        Some(img) => img.clone(),
        None => return,
    };

    // parse src dimensions
    let src_w = src_image.texture_descriptor.size.width as usize;
    let src_h = src_image.texture_descriptor.size.height as usize;
    let src_data = &src_image.data;

    for (entity, _image_node, node) in &mut query {
        // Process all GlassOverlay entities (they were spawned with the captured
        // handle or with the procedural glass noise). We'll generate a blurred
        // crop regardless and replace the ImageNode handle.

        // Determine pixel size
        let mut px_w: Option<usize> = None;
        let mut px_h: Option<usize> = None;
        match node.width {
            Val::Px(v) => px_w = Some(v.max(1.0) as usize),
            _ => {}
        }
        match node.height {
            Val::Px(v) => px_h = Some(v.max(1.0) as usize),
            _ => {}
        }

        if let (Some(tw), Some(th)) = (px_w, px_h) {
            // create target buffer and sample+scale from source
            let mut tdata = vec![0u8; tw * th * 4];

            for y in 0..th {
                for x in 0..tw {
                    // normalized uv over target
                    let u = (x as f32 + 0.5) / (tw as f32);
                    let v = (y as f32 + 0.5) / (th as f32);
                    // map to source coords
                    let sx = (u * (src_w as f32)).clamp(0.0, (src_w - 1) as f32) as usize;
                    let sy = (v * (src_h as f32)).clamp(0.0, (src_h - 1) as f32) as usize;
                    let sidx = (sy * src_w + sx) * 4;
                    let tidx = (y * tw + x) * 4;
                    tdata[tidx] = src_data[sidx];
                    tdata[tidx + 1] = src_data[sidx + 1];
                    tdata[tidx + 2] = src_data[sidx + 2];
                    tdata[tidx + 3] = src_data[sidx + 3];
                }
            }

            // apply a cheap box blur pass (radius = 3)
            let radius = 3usize;
            let mut bdata = tdata.clone();
            for y in 0..th {
                for x in 0..tw {
                    let mut rr = 0u32;
                    let mut gg = 0u32;
                    let mut bb = 0u32;
                    let mut aa = 0u32;
                    let mut count = 0u32;
                    let x0 = if x > radius { x - radius } else { 0 };
                    let x1 = (x + radius).min(tw - 1);
                    let y0 = if y > radius { y - radius } else { 0 };
                    let y1 = (y + radius).min(th - 1);
                    for yy in y0..=y1 {
                        for xx in x0..=x1 {
                            let idx = (yy * tw + xx) * 4;
                            rr += tdata[idx] as u32;
                            gg += tdata[idx + 1] as u32;
                            bb += tdata[idx + 2] as u32;
                            aa += tdata[idx + 3] as u32;
                            count += 1;
                        }
                    }
                    let tidx = (y * tw + x) * 4;
                    bdata[tidx] = (rr / count) as u8;
                    bdata[tidx + 1] = (gg / count) as u8;
                    bdata[tidx + 2] = (bb / count) as u8;
                    bdata[tidx + 3] = (aa / count) as u8;
                }
            }

            let image = Image::new(
                Extent3d { width: tw as u32, height: th as u32, depth_or_array_layers: 1 },
                TextureDimension::D2,
                bdata,
                TextureFormat::Rgba8UnormSrgb,
                Default::default(),
            );

            let handle = images.add(image);
            // replace the image node with the newly generated blurred image
            commands.entity(entity).insert((ImageNode::new(handle),));
        }
    }
}

// Spawn a camera that renders the 3D scene into an Image asset each frame.
// This image is stored in the `CapturedScene` resource so UI overlays can
// sample it. This is a standard render-to-texture approach; later we can
// replace this with a render-graph node if needed.
pub fn spawn_captured_scene_camera_system(
    mut commands: Commands,
    mut images: ResMut<Assets<Image>>, 
) {
    // create a reasonably sized render target (will be recreated/resized later if needed)
    let size: u32 = 512;
    let data = vec![0u8; (size * size * 4) as usize];
    let img = Image::new(
        Extent3d { width: size, height: size, depth_or_array_layers: 1 },
        TextureDimension::D2,
        data,
        TextureFormat::Rgba8UnormSrgb,
        Default::default(),
    );

    let handle = images.add(img);
    commands.insert_resource(CapturedScene { handle: handle.clone() });

        // Note: spawning an offscreen camera that renders into this Image
        // caused validation errors on some platforms when the texture usages
        // didn't match expectations. For stability across environments (and
        // to keep the CPU fallback working), we do not spawn the camera here.
        // A render-graph based implementation will be added later to perform
        // a correct GPU-side capture and blur.
}

// Animation system
pub fn animation_system(
    time: Res<Time>,
    mut query: Query<(&mut Transform, &mut Animation)>,
) {
    for (mut transform, mut animation) in &mut query {
        animation.elapsed += time.delta_secs();
        
        let progress = if animation.duration > 0.0 {
            (animation.elapsed / animation.duration).min(1.0)
        } else {
            1.0
        };

        // Apply easing
        let eased_progress = apply_easing(progress, &animation.easing);

        // Apply animation
        match &animation.animation_type {
            AnimationType::Rotate { axis, degrees } => {
                let angle = degrees.to_radians() * eased_progress;
                let axis_vec = Vec3::new(axis.x, axis.y, axis.z).normalize();
                transform.rotation = Quat::from_axis_angle(axis_vec, angle);
            }
            AnimationType::Translate { from, to } => {
                let from_vec = Vec3::new(from.x, from.y, from.z);
                let to_vec = Vec3::new(to.x, to.y, to.z);
                transform.translation = from_vec.lerp(to_vec, eased_progress);
            }
            AnimationType::Scale { from, to } => {
                let from_vec = Vec3::new(from.x, from.y, from.z);
                let to_vec = Vec3::new(to.x, to.y, to.z);
                transform.scale = from_vec.lerp(to_vec, eased_progress);
            }
            AnimationType::Bounce { height } => {
                let y = (eased_progress * std::f32::consts::PI).sin() * height;
                transform.translation.y = y;
            }
            AnimationType::Pulse { min_scale, max_scale } => {
                let scale = min_scale + (max_scale - min_scale) * 
                    (0.5 + 0.5 * (eased_progress * std::f32::consts::TAU).sin());
                transform.scale = Vec3::splat(scale);
            }
        }

        // Loop or stop
        if animation.elapsed >= animation.duration {
            if animation.looping {
                animation.elapsed = 0.0;
            }
        }
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

// Particle system
pub fn particle_emission_system(
    mut commands: Commands,
    time: Res<Time>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    mut query: Query<(&Transform, &mut ParticleEmitter)>,
) {
    for (transform, mut emitter) in &mut query {
        emitter.timer += time.delta_secs();
        
        let emission_interval = 1.0 / emitter.emission_rate;
        
        while emitter.timer >= emission_interval {
            emitter.timer -= emission_interval;
            
            // Spawn particle
            let mesh = meshes.add(Sphere::new(emitter.size));
            let material = materials.add(StandardMaterial {
                base_color: emitter.color,
                emissive: emitter.color.into(),
                ..default()
            });
            
            commands.spawn((
                Mesh3d(mesh),
                MeshMaterial3d(material),
                Transform::from_translation(transform.translation),
                Particle {
                    lifetime: emitter.lifetime,
                    age: 0.0,
                    velocity: emitter.velocity,
                },
            ));
        }
    }
}

pub fn particle_update_system(
    mut commands: Commands,
    time: Res<Time>,
    mut query: Query<(Entity, &mut Transform, &mut Particle, &ParticleEmitter)>,
    emitter_query: Query<&ParticleEmitter>,
) {
    for (entity, mut transform, mut particle, _) in &mut query {
        particle.age += time.delta_secs();
        
        // Get gravity from nearest emitter (for simplicity, using first emitter)
        let gravity = emitter_query.iter().next()
            .map(|e| e.gravity)
            .unwrap_or(Vec3::new(0.0, -9.8, 0.0));
        
        // Update velocity with gravity
        particle.velocity += gravity * time.delta_secs();
        
        // Update position
        transform.translation += particle.velocity * time.delta_secs();
        
        // Remove if expired
        if particle.age >= particle.lifetime {
            commands.entity(entity).despawn();
        }
    }
}

// Checkbox interaction system
pub fn checkbox_interaction_system(
    mut interaction_query: Query<
        (&Interaction, &mut BackgroundColor, &mut Checkbox),
        (Changed<Interaction>, With<Button>),
    >,
    mut events: EventWriter<ComponentEvent>,
) {
    for (interaction, mut color, mut checkbox) in &mut interaction_query {
        if *interaction == Interaction::Pressed {
            checkbox.checked = !checkbox.checked;
            
            *color = if checkbox.checked {
                BackgroundColor(Color::srgb(0.2, 0.8, 0.2))
            } else {
                BackgroundColor(Color::srgb(0.3, 0.3, 0.3))
            };
            
            if let Some(event_id) = &checkbox.on_change {
                events.send(ComponentEvent {
                    event_type: "checkbox_change".to_string(),
                    event_id: event_id.clone(),
                    data: checkbox.checked.to_string(),
                });
            }
        }
    }
}

// Radio button interaction system
pub fn radio_button_interaction_system(
    mut interaction_query: Query<
        (&Interaction, &mut BackgroundColor, &mut RadioButton),
        (Changed<Interaction>, With<Button>),
    >,
    mut all_radios: Query<(&mut BackgroundColor, &mut RadioButton), Without<Interaction>>,
    mut events: EventWriter<ComponentEvent>,
) {
    for (interaction, mut color, mut radio) in &mut interaction_query {
        if *interaction == Interaction::Pressed && !radio.checked {
            // Uncheck all radios in the same group
            for (mut other_color, mut other_radio) in &mut all_radios {
                if other_radio.group == radio.group && other_radio.checked {
                    other_radio.checked = false;
                    *other_color = BackgroundColor(Color::srgb(0.3, 0.3, 0.3));
                }
            }
            
            // Check this radio
            radio.checked = true;
            *color = BackgroundColor(Color::srgb(0.2, 0.6, 0.9));
            
            if let Some(event_id) = &radio.on_change {
                events.send(ComponentEvent {
                    event_type: "radio_change".to_string(),
                    event_id: event_id.clone(),
                    data: "selected".to_string(),
                });
            }
        }
    }
}

// Icon button interaction system
pub fn icon_button_interaction_system(
    mut interaction_query: Query<(&Interaction, &IconButton), (Changed<Interaction>, With<Button>)>,
    mut events: EventWriter<ComponentEvent>,
) {
    for (interaction, icon) in &mut interaction_query {
        if *interaction == Interaction::Pressed {
            if let Some(action) = &icon.action {
                events.send(ComponentEvent {
                    event_type: "iconbutton_click".to_string(),
                    event_id: action.clone(),
                    data: "clicked".to_string(),
                });
            }
        }
    }
}

// Spawn a ripple child when any button is pressed
pub fn button_ripple_spawn_system(
    mut commands: Commands,
    interaction_query: Query<(Entity, &Interaction, &Node, &GlobalTransform), (Changed<Interaction>, With<Button>)>,
    circle: Option<Res<CircleMask>>,
    windows: Query<&Window, With<bevy::window::PrimaryWindow>>,
) {
    // obtain primary window if present
    let primary_window = windows.get_single().ok();

    for (entity, interaction, button_node, global_transform) in &interaction_query {
        if *interaction != Interaction::Pressed {
            continue;
        }

        // determine button size in pixels
        let bw = match button_node.width { Val::Px(v) => v.max(1.0), _ => 64.0 };
        let bh = match button_node.height { Val::Px(v) => v.max(1.0), _ => 32.0 };

        // compute click origin relative to button top-left in pixels
        let mut origin = Vec2::new(bw * 0.5, bh * 0.5); // default center
        if let Some(window) = primary_window {
            if let Some(cursor) = window.cursor_position() {
                // convert cursor (bottom-left origin) to world coords (center origin)
                let win_w = window.width();
                let win_h = window.height();
                let world_x = cursor.x - (win_w * 0.5);
                let world_y = cursor.y - (win_h * 0.5);

                let parent_center = global_transform.translation();
                let parent_center = Vec2::new(parent_center.x, parent_center.y);

                // top-left of parent in world coords
                let top_left = parent_center - Vec2::new(bw * 0.5, bh * 0.5);

                // local pixel coordinates from top-left
                origin = Vec2::new(world_x - top_left.x, world_y - top_left.y);

                // If cursor values appear normalized (0..1), convert to pixels
                if origin.x >= 0.0 && origin.x <= 1.0 && origin.y >= 0.0 && origin.y <= 1.0 {
                    origin.x *= bw;
                    origin.y *= bh;
                }

                // clamp to button rect
                origin.x = origin.x.clamp(0.0, bw);
                origin.y = origin.y.clamp(0.0, bh);
            }
        }

        // max radius is distance to farthest corner from origin
        let corners = [Vec2::new(0.0, 0.0), Vec2::new(bw, 0.0), Vec2::new(0.0, bh), Vec2::new(bw, bh)];
        let mut max_r = 0.0f32;
        for c in &corners {
            let d = (*c - origin).length();
            if d > max_r { max_r = d; }
        }

        // spawn ripple (use circle mask if available)
        // use a soft, low alpha so ripple shows as a subtle highlight
        let base_alpha = 0.12f32;
        if let Some(circle) = &circle {
            let node = Node {
                position_type: PositionType::Absolute,
                left: Val::Px(origin.x),
                top: Val::Px(origin.y),
                width: Val::Px(0.0),
                height: Val::Px(0.0),
                ..default()
            };

            let ripple_id = commands.spawn((
                ImageNode::new(circle.handle.clone()),
                node,
                BackgroundColor(Color::srgba(1.0, 1.0, 1.0, base_alpha)),
                RippleEffect {
                    origin,
                    radius: 0.0,
                    max_radius: max_r as f32,
                    duration: 0.5,
                    elapsed: 0.0,
                },
            )).id();

            commands.entity(ripple_id).set_parent(entity);
        } else {
            let node = Node {
                position_type: PositionType::Absolute,
                left: Val::Px(origin.x),
                top: Val::Px(origin.y),
                width: Val::Px(0.0),
                height: Val::Px(0.0),
                ..default()
            };

            let ripple_id = commands.spawn((
                node,
                BackgroundColor(Color::srgba(1.0, 1.0, 1.0, base_alpha)),
                RippleEffect {
                    origin,
                    radius: 0.0,
                    max_radius: max_r as f32,
                    duration: 0.5,
                    elapsed: 0.0,
                },
            )).id();

            commands.entity(ripple_id).set_parent(entity);
        }
    }
}

// Animate and despawn ripples
pub fn ripple_update_system(
    time: Res<Time>,
    mut commands: Commands,
    mut query: Query<(Entity, &mut RippleEffect, &mut Node, Option<&mut BackgroundColor>)>,
) {
    for (entity, mut ripple, mut node, bg) in &mut query {
        ripple.elapsed += time.delta_secs();
        let t = if ripple.duration > 0.0 { (ripple.elapsed / ripple.duration).min(1.0) } else { 1.0 };

        // apply easing (ease out cubic)
        let eased = 1.0 - (1.0 - t).powf(3.0);

        // start slightly visible and expand to max_radius
        let size = ripple.max_radius * 2.0 * eased;

        // position the ripple so its center follows the origin
        let left = ripple.origin.x - size * 0.5;
        let top = ripple.origin.y - size * 0.5;
        node.width = Val::Px(size);
        node.height = Val::Px(size);
        node.left = Val::Px(left);
        node.top = Val::Px(top);

        if let Some(mut color) = bg {
            // fade alpha over time with a subtle multiplier
            let alpha = (1.0 - eased).clamp(0.0, 1.0) * 0.18;
            color.0 = Color::srgba(1.0, 1.0, 1.0, alpha);
        }

        if ripple.elapsed >= ripple.duration {
            commands.entity(entity).despawn_recursive();
        }
    }
}

// Progress bar update system
pub fn progress_bar_update_system(
    mut query: Query<(&ProgressBarComponent, &Children), Changed<ProgressBarComponent>>,
    mut fill_query: Query<&mut Node, With<ProgressBarFill>>,
) {
    for (progress, children) in &mut query {
        for child in children.iter() {
            if let Ok(mut style) = fill_query.get_mut(*child) {
                style.width = Val::Percent((progress.value / progress.max) * 100.0);
            }
        }
    }
}

// Drawer system: simple open/close immediate toggle (could be animated)
pub fn drawer_system(
    mut query: Query<(&mut Node, &Drawer)>,
) {
    for (mut node, drawer) in &mut query {
        // adjust left based on open state
        node.left = if drawer.open { Val::Px(0.0) } else { Val::Px(-drawer.width) };
    }
}

// Custom event type
#[derive(Event)]
pub struct ComponentEvent {
    pub event_type: String,
    pub event_id: String,
    pub data: String,
}

// Event logging system (for debugging)
pub fn event_logging_system(mut events: EventReader<ComponentEvent>) {
    for event in events.read() {
        info!(
            "Component Event - Type: {}, ID: {}, Data: {}",
            event.event_type, event.event_id, event.data
        );
    }
}

// After images are generated, apply UiImage and shadow children to entities marked with RoundedBackground
pub fn apply_ui_images_system(
    mut commands: Commands,
    mut images: ResMut<Assets<Image>>,
    shadow: Option<Res<ShadowImage>>,
    glass: Option<Res<GlassNoise>>,
    captured: Option<Res<CapturedScene>>,
    query: Query<(Entity, &crate::graphics::components::RoundedBackground, &Node)>,
) {
    for (entity, rb, node) in &query {
        // Determine pixel size from Node if available
        let mut px_w: Option<u32> = None;
        let mut px_h: Option<u32> = None;
        match node.width {
            Val::Px(v) => px_w = Some(v.max(1.0) as u32),
            _ => {}
        }
        match node.height {
            Val::Px(v) => px_h = Some(v.max(1.0) as u32),
            _ => {}
        }

        if let (Some(w), Some(h)) = (px_w, px_h) {
            // generate per-element rounded background image matching size
            let mut data = vec![0u8; (w * h * 4) as usize];
            let cr = rb.corner_radius.max(0.0).min((w.min(h) / 2) as f32);
            for y in 0..h {
                for x in 0..w {
                    let xf = x as f32 + 0.5;
                    let yf = y as f32 + 0.5;
                    // distance to rounded rectangle edge
                    let left = cr;
                    let right = w as f32 - cr;
                    let top = cr;
                    let bottom = h as f32 - cr;

                    let mut alpha = 1.0f32;

                    if xf < left {
                        if yf < top {
                            // top-left corner
                            let dx = left - xf;
                            let dy = top - yf;
                            let dist = (dx*dx + dy*dy).sqrt();
                            if dist > cr { alpha = 0.0; } else { alpha = 1.0 - (dist / cr); }
                        } else if yf > bottom {
                            let dx = left - xf;
                            let dy = yf - bottom;
                            let dist = (dx*dx + dy*dy).sqrt();
                            if dist > cr { alpha = 0.0 } else { alpha = 1.0 - (dist / cr); }
                        }
                    } else if xf > right {
                        if yf < top {
                            let dx = xf - right;
                            let dy = top - yf;
                            let dist = (dx*dx + dy*dy).sqrt();
                            if dist > cr { alpha = 0.0 } else { alpha = 1.0 - (dist / cr); }
                        } else if yf > bottom {
                            let dx = xf - right;
                            let dy = yf - bottom;
                            let dist = (dx*dx + dy*dy).sqrt();
                            if dist > cr { alpha = 0.0 } else { alpha = 1.0 - (dist / cr); }
                        }
                    }

                    // simple smoothing at edges
                    let alpha_u8 = (alpha.clamp(0.0, 1.0) * 255.0) as u8;
                    let idx = ((y * w + x) * 4) as usize;
                    // apply background color using cached numeric RGBA in the component
                    let rr = rb.color_rgba[0];
                    let gg = rb.color_rgba[1];
                    let bb = rb.color_rgba[2];
                    let r = (rr.clamp(0.0, 1.0) * 255.0) as u8;
                    let g = (gg.clamp(0.0, 1.0) * 255.0) as u8;
                    let b = (bb.clamp(0.0, 1.0) * 255.0) as u8;
                    data[idx] = r;
                    data[idx + 1] = g;
                    data[idx + 2] = b;
                    data[idx + 3] = alpha_u8;
                }
            }

            let image = Image::new(
                Extent3d { width: w, height: h, depth_or_array_layers: 1 },
                TextureDimension::D2,
                data,
                TextureFormat::Rgba8UnormSrgb,
                Default::default(),
            );

            let handle = images.add(image);
            // insert ImageNode with generated handle (replace existing)
            commands.entity(entity).insert(ImageNode::new(handle.clone()));
        } else {
            // fallback: tint background color
            commands.entity(entity).insert(BackgroundColor(rb.color));
        }

        // Add shadow child if shadow resource exists and elevation > 0
        if let Some(s) = &shadow {
            if rb.elevation > 0 {
                // improved falloff: scale and alpha based on elevation with smoother curve
                let level = rb.elevation as f32;
                let shadow_alpha = (level.powf(0.9) * 0.08).clamp(0.03, 0.8);
                let scale = 1.0 + level * 0.06; // grow shadow with elevation
                let offset_y = 4.0 + level * 1.5; // vertical offset grows

                let s_node = Node {
                    position_type: PositionType::Absolute,
                    left: Val::Px((-16.0 * scale) as f32),
                    top: Val::Px((offset_y) as f32),
                    width: Val::Percent(100.0 * scale),
                    height: Val::Percent(100.0 * scale),
                    ..default()
                };

                let shadow_id = commands.spawn((
                    ImageNode::new(s.handle.clone()),
                    s_node,
                    BackgroundColor(Color::srgba(0.0, 0.0, 0.0, shadow_alpha)),
                )).id();

                commands.entity(shadow_id).set_parent(entity);
            }
        }

        // Add glass overlay if requested. Prefer a captured scene texture if available
        if rb.glass {
            // If a captured scene resource exists, use it as the overlay image so
            // the UI can sample a (placeholder) scene texture. This is a scaffold
            // for the real render-graph-backed capture.
            if let Some(captured) = &captured {
                let g_node = Node {
                    position_type: PositionType::Absolute,
                    left: Val::Px(0.0),
                    top: Val::Px(0.0),
                    width: Val::Percent(100.0),
                    height: Val::Percent(100.0),
                    ..default()
                };

                let overlay_id = commands.spawn((
                    ImageNode::new(captured.handle.clone()),
                    g_node,
                    BackgroundColor(Color::srgba(1.0, 1.0, 1.0, rb.glass_opacity)),
                    crate::graphics::components::GlassOverlay,
                )).id();

                commands.entity(overlay_id).set_parent(entity);
            } else if let Some(g) = &glass {
                // fallback to the procedural glass noise texture if no captured
                // scene is available yet.
                let g_node = Node {
                    position_type: PositionType::Absolute,
                    left: Val::Px(0.0),
                    top: Val::Px(0.0),
                    width: Val::Percent(100.0),
                    height: Val::Percent(100.0),
                    ..default()
                };

                let overlay_id = commands.spawn((
                    ImageNode::new(g.handle.clone()),
                    g_node,
                    BackgroundColor(Color::srgba(1.0, 1.0, 1.0, rb.glass_opacity)),
                    crate::graphics::components::GlassOverlay,
                )).id();

                commands.entity(overlay_id).set_parent(entity);
            }
        }

        // remove marker component to avoid re-processing
        commands.entity(entity).remove::<crate::graphics::components::RoundedBackground>();
    }
}
