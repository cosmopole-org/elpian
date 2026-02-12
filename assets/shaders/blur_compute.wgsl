// WGSL compute shader: basic copy kernel (placeholder for blur)
// Bindings:
// @group(0) @binding(0) var src_tex: texture_2d<f32>;
// @group(0) @binding(1) var dst_tex: texture_storage_2d<rgba8unorm, write>;

@group(0) @binding(0)
var src_tex: texture_2d<f32>;

@group(0) @binding(1)
var dst_tex: texture_storage_2d<rgba8unorm, write>;

@group(0) @binding(2)
var samp: sampler;

@compute @workgroup_size(8,8)
fn cs_main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = textureDimensions(dst_tex);
    if (gid.x >= dims.x || gid.y >= dims.y) {
        return;
    }
    let uv: vec2<f32> = (vec2<f32>(f32(gid.x) + 0.5, f32(gid.y) + 0.5)) / vec2<f32>(f32(dims.x), f32(dims.y));
    let color: vec4<f32> = textureSampleLevel(src_tex, samp, uv, 0.0);
    textureStore(dst_tex, vec2<i32>(i32(gid.x), i32(gid.y)), color);
}

// Note: `default_sampler` must be provided by the runtime bindgroup; in Bevy
// we will use the standard sampler resource when constructing the bind group.
