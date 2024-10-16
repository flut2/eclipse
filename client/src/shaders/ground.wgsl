@group(0) @binding(0) var<uniform> uniforms: Uniforms;
@group(0) @binding(1) var<storage, read> instances: array<InstanceData>;
@group(0) @binding(2) var default_sampler: sampler;
@group(0) @binding(3) var tex: texture_2d<f32>;

const pos: array<vec2<f32>, 6> = array<vec2<f32>, 6>(
    vec2<f32>(-0.5, 0.5),
    vec2<f32>(0.5, 0.5),
    vec2<f32>(-0.5, -0.5),
    vec2<f32>(-0.5, -0.5),
    vec2<f32>(0.5, 0.5),
    vec2<f32>(0.5, -0.5),
);

const uv: array<vec2<f32>, 6> = array<vec2<f32>, 6>(
    vec2<f32>(0.0, 1.0),
    vec2<f32>(1.0, 1.0),
    vec2<f32>(0.0, 0.0),
    vec2<f32>(0.0, 0.0),
    vec2<f32>(1.0, 1.0),
    vec2<f32>(1.0, 0.0),
);

const base_size: vec2<f32> = vec2<f32>(9.0, 9.0); // atlas px per tile
const scaled_size: vec2<f32> = vec2<f32>(63.0, 63.0); // screen px per tile
const invert_y: vec2<f32> = vec2<f32>(1.0, -1.0);

struct Uniforms {
    padding: f32,
    scale: f32,
    left_mask_uv: vec2<f32>,
    top_mask_uv: vec2<f32>,
    right_mask_uv: vec2<f32>,
    bottom_mask_uv: vec2<f32>,
    clip_scale: vec2<f32>,
    clip_offset: vec2<f32>,
    atlas_size: vec2<f32>,
}

struct InstanceData {
    pos: vec2<f32>,
    uv: vec2<f32>,
    offset_uv: vec2<f32>,
    left_blend_uv: vec2<f32>,
    top_blend_uv: vec2<f32>,
    right_blend_uv: vec2<f32>,
    bottom_blend_uv: vec2<f32>,
    padding: vec2<f32>,
}

struct VertexData {
    @builtin(vertex_index) vert_id: u32,
}

struct FragmentData {
    @builtin(position) position: vec4<f32>,
    @location(0) @interpolate(flat) instance_id: u32,
    @location(1) uv_offset: vec2<f32>,
}

@vertex
fn vertexMain(vertex: VertexData) -> FragmentData {
    let instance_id = vertex.vert_id / 6;
    let sub_vert_id = vertex.vert_id % 6;
    let instance = instances[instance_id];

    var out: FragmentData;
    out.position = vec4((pos[sub_vert_id] * scaled_size * uniforms.scale + instance.pos + uniforms.clip_offset) 
        * uniforms.clip_scale * invert_y, 0.0, 1.0);
    out.uv_offset = uv[sub_vert_id] / uniforms.atlas_size * base_size;
    out.instance_id = instance_id;
    return out;
}

@fragment
fn fragmentMain(fragment: FragmentData) -> @location(0) vec4<f32> {
    let instance = instances[fragment.instance_id];
    let dx = dpdx(fragment.uv_offset);
    let dy = dpdy(fragment.uv_offset);

    if (instance.left_blend_uv.x > 0.0 || instance.left_blend_uv.y > 0.0) &&
        textureSampleGrad(tex, default_sampler, uniforms.left_mask_uv + fragment.uv_offset, dx, dy).a == 1.0 {
        return textureSampleGrad(tex, default_sampler, instance.left_blend_uv + fragment.uv_offset, dx, dy);
    }

    if (instance.top_blend_uv.x > 0.0 || instance.top_blend_uv.y > 0.0) &&
        textureSampleGrad(tex, default_sampler, uniforms.top_mask_uv + fragment.uv_offset, dx, dy).a == 1.0 {
        return textureSampleGrad(tex, default_sampler, instance.top_blend_uv + fragment.uv_offset, dx, dy);
    }

    if (instance.right_blend_uv.x > 0.0 || instance.right_blend_uv.y > 0.0) &&
        textureSampleGrad(tex, default_sampler, uniforms.right_mask_uv + fragment.uv_offset, dx, dy).a == 1.0 {
        return textureSampleGrad(tex, default_sampler, instance.right_blend_uv + fragment.uv_offset, dx, dy);
    }

    if (instance.bottom_blend_uv.x > 0.0 || instance.bottom_blend_uv.y > 0.0) &&
        textureSampleGrad(tex, default_sampler, uniforms.bottom_mask_uv + fragment.uv_offset, dx, dy).a == 1.0 {
        return textureSampleGrad(tex, default_sampler, instance.bottom_blend_uv + fragment.uv_offset, dx, dy);
    }

    let dims = base_size / uniforms.atlas_size;
    let clamp_uv = (fragment.uv_offset + instance.offset_uv + dims) % dims;
    return textureSampleGrad(tex, default_sampler, clamp_uv + instance.uv, dx, dy);
}