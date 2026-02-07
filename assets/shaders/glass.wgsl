// Simple WGSL scaffold for glass/backdrop blur shader
// NOTE: This is a scaffold. True backdrop blur requires a render-pass that provides
// a sampled input of the scene behind UI elements. This shader assumes a texture
// binding named `u_texture` will be provided by a later render integration.

@group(0) @binding(0)
var u_texture: texture_2d<f32>;
@group(0) @binding(1)
var u_sampler: sampler;

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>;
    @location(0) uv: vec2<f32>;
};

@stage(fragment)
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let uv = in.uv;
    // Simple 3x3 box blur as placeholder
    var color: vec4<f32> = vec4<f32>(0.0);
    let off: array<vec2<f32>, 9> = array<vec2<f32>, 9>(
        vec2<f32>(-1.0, -1.0), vec2<f32>(0.0, -1.0), vec2<f32>(1.0, -1.0),
        vec2<f32>(-1.0,  0.0), vec2<f32>(0.0,  0.0), vec2<f32>(1.0,  0.0),
        vec2<f32>(-1.0,  1.0), vec2<f32>(0.0,  1.0), vec2<f32>(1.0,  1.0)
    );
    let texel = vec2<f32>(1.0/512.0, 1.0/512.0); // placeholder, real value comes from uniforms
    for (var i = 0u; i < 9u; i = i + 1u) {
        let sample_uv = uv + off[i] * texel;
        color = color + textureSample(u_texture, u_sampler, sample_uv);
    }
    color = color / 9.0;
    // apply a tint/alpha to emulate frosted glass
    return vec4<f32>(color.rgb * 0.9, 0.6);
}
