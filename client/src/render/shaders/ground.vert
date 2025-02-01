#version 450 core

const vec2 base_pos[6] = vec2[6](
    vec2(-0.5, 0.5),
    vec2(0.5, 0.5),
    vec2(-0.5, -0.5),
    vec2(-0.5, -0.5),
    vec2(0.5, 0.5),
    vec2(0.5, -0.5)
);

const vec2 base_uv[6] = vec2[6](
    vec2(0.0, 1.0),
    vec2(1.0, 1.0),
    vec2(0.0, 0.0),
    vec2(0.0, 0.0),
    vec2(1.0, 1.0),
    vec2(1.0, 0.0)
);

const vec2 base_size = vec2(9.0, 9.0); // atlas px per tile
const vec2 scaled_size = vec2(63.0, 63.0); // screen px per tile

layout(location = 0) flat out int instance_id;
layout(location = 1) out vec2 out_uv;

struct InstanceData {
    vec2 pos;
    vec2 uv;
    vec2 offset_uv;
    vec2 left_blend_uv;
    vec2 left_blend_offset_uv;
    vec2 top_blend_uv;
    vec2 top_blend_offset_uv;
    vec2 right_blend_uv;
    vec2 right_blend_offset_uv;
    vec2 bottom_blend_uv;
    vec2 bottom_blend_offset_uv;
    float rotation;
    // r u8, g u8, b u8, a u8
    uint color;
};

layout(std140, set = 1, binding = 0) readonly buffer InstanceBuffer {
    InstanceData data[];
} instance_buffer;

layout(std140, push_constant) uniform PushConstants {
    float padding;
    float scale;
    vec2 left_mask_uv;
    vec2 top_mask_uv;
    vec2 right_mask_uv;
    vec2 bottom_mask_uv;
    vec2 clip_scale;
    vec2 clip_offset;
    vec2 atlas_size;
} constants;

void main() {
    instance_id = gl_VertexIndex / 6;
    uint sub_vert_id = gl_VertexIndex % 6;
    InstanceData instance = instance_buffer.data[instance_id];
    float c = cos(instance.rotation);
    float s = sin(instance.rotation);
    mat2x2 rot_mat = mat2x2(c, s, -s, c);

    gl_Position = vec4((base_pos[sub_vert_id] * rot_mat * scaled_size * constants.scale + instance.pos + constants.clip_offset) 
        * constants.clip_scale, 0.0, 1.0);
    out_uv = base_uv[sub_vert_id] / constants.atlas_size * base_size;
}