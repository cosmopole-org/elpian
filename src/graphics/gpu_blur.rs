use bevy::prelude::*;
use bevy::render::render_resource::*;
use bevy::render::renderer::{RenderDevice, RenderQueue};
use std::borrow::Cow;
use std::fs;

#[derive(Resource)]
pub struct BlurPipeline {
    pub shader: Handle<Shader>,
    pub pipeline: Option<ComputePipeline>,
    pub bind_group_layout: Option<BindGroupLayout>,
}

pub fn prepare_gpu_blur_system(
    asset_server: Res<AssetServer>,
    _render_device: Res<RenderDevice>,
    mut commands: Commands,
) {
    // Load compute shader handle (asset system) and also try to build a
    // compute pipeline immediately from the WGSL file so we can dispatch.
    let handle = asset_server.load("shaders/blur_compute.wgsl");

    let mut pipeline = BlurPipeline { shader: handle.clone(), pipeline: None, bind_group_layout: None };

    let shader_path = "assets/shaders/blur_compute.wgsl";
    if let Ok(src) = fs::read_to_string(shader_path) {
        let _shader_module = _render_device.create_shader_module(ShaderModuleDescriptor {
            label: Some("blur_compute_module"),
            source: ShaderSource::Wgsl(Cow::Owned(src)),
        });

        // Create a bind group layout: binding 0 = sampled texture, 1 = storage texture (write), 2 = sampler
        let entries: &[BindGroupLayoutEntry] = &[
            BindGroupLayoutEntry {
                binding: 0,
                visibility: ShaderStages::COMPUTE,
                ty: BindingType::Texture {
                    multisampled: false,
                    view_dimension: TextureViewDimension::D2,
                    sample_type: TextureSampleType::Float { filterable: true },
                },
                count: None,
            },
            BindGroupLayoutEntry {
                binding: 1,
                visibility: ShaderStages::COMPUTE,
                ty: BindingType::StorageTexture {
                    access: StorageTextureAccess::WriteOnly,
                    format: TextureFormat::Rgba8UnormSrgb,
                    view_dimension: TextureViewDimension::D2,
                },
                count: None,
            },
            BindGroupLayoutEntry {
                binding: 2,
                visibility: ShaderStages::COMPUTE,
                ty: BindingType::Sampler(SamplerBindingType::Filtering),
                count: None,
            },
        ];

        let bgl = _render_device.create_bind_group_layout(Some("blur_bgl"), entries);
        pipeline.bind_group_layout = Some(bgl);
    }

    commands.insert_resource(pipeline);
}

#[derive(Resource)]
pub struct BlurredScene {
    pub handle: Handle<Image>,
}

pub fn dispatch_gpu_blur_system(
    _render_device: Res<RenderDevice>,
    _render_queue: Res<RenderQueue>,
    _pipelines: Res<Assets<Shader>>,
    blur_pipeline: Res<BlurPipeline>,
    captured: Option<Res<crate::graphics::systems::CapturedScene>>,
    mut images: ResMut<Assets<Image>>,
    mut commands: Commands,
) {
    // This is a placeholder: real compute dispatch with BindGroups and
    // ComputePipeline creation requires access to wgpu types through
    // RenderDevice and low-level APIs. Implementing a full compute pipeline
    // reliably across Bevy versions is invasive. For now, ensure the
    // shader is loaded and that the blurred image resource exists and is
    // sized like the captured scene. Further GPU dispatch will be added
    // after verifying pipeline creation steps.
    if captured.is_none() {
        return;
    }

    // Ensure a blurred target exists; create or resize to match captured
    let cap = captured.unwrap();
    if let Some(src) = images.get(&cap.handle) {
        let w = src.texture_descriptor.size.width;
        let h = src.texture_descriptor.size.height;

        // Create or replace `BlurredScene` image resource in assets
        // so UI overlay code can reference it. We'll create a GPU-backed
        // Image that can be written to by a compute pass.
        let data = vec![0u8; (w * h * 4) as usize];
        let img = Image::new(
            Extent3d { width: w, height: h, depth_or_array_layers: 1 },
            TextureDimension::D2,
            data,
            TextureFormat::Rgba8UnormSrgb,
            Default::default(),
        );
        let blurred_handle = images.add(img);
        commands_insert_blurred_resource(&mut commands, blurred_handle.clone());

        // If a bind-group layout exists, note it (actual bind-group creation
        // and compute dispatch are implemented in the render sub-app node).
        if blur_pipeline.bind_group_layout.is_some() {
            // placeholder: GPU dispatch happens in render-graph node
        }
    }
}

fn commands_insert_blurred_resource(commands: &mut Commands, handle: Handle<Image>) {
    commands.insert_resource(BlurredScene { handle });
}
// end
