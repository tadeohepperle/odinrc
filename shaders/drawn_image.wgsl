#import globals.wgsl

@group(1) @binding(0)
var t_diffuse: texture_2d<f32>;
@group(1) @binding(1)
var s_diffuse: sampler;

struct VertexOutput{
    @builtin(position) clip_position: vec4<f32>,
    @location(0) uv: vec2<f32>,
}

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VertexOutput {
   var u_uv = unit_uv_from_idx(vertex_index);
   var pos = u_uv * 2.0 - 1.0;
   pos.x = pos.x * globals.screen_size.y/globals.screen_size.x;
   pos.y = -pos.y;
   var out: VertexOutput; 
   out.clip_position = vec4(pos, 0.0,1.0);
   out.uv = u_uv;
   return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32>  {
    let image_color = textureSample(t_diffuse, s_diffuse, in.uv);
    //  return vec4(globals.screen_size.x / globals.screen_size.y, 0.0, 0.0, 1.0);
    return image_color;
}

fn unit_uv_from_idx(idx: u32) -> vec2<f32> {
    return vec2<f32>(
        f32(((idx << 1) & 2) >> 1),
        f32((idx & 2) >> 1)
    );
}