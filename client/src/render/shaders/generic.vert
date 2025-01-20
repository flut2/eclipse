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

layout(location = 0) flat out int instance_id;
layout(location = 1) out vec2 out_uv;

struct InstanceData {
    uint render_type;
    uint text_type;
    float rotation;
    float text_dist_factor;
    uint shadow_color;
    float alpha_mult;
    uint outline_color;
    float outline_width;
    uint base_color;
    float color_intensity;
    vec2 pos;
    vec2 size;
    vec2 uv;
    vec2 uv_size;
    vec2 shadow_texel_size;
    vec4 scissor;
};

layout(std140, set = 1, binding = 0) readonly buffer InstanceBuffer {
    InstanceData data[];
} instance_buffer;

layout(std140, push_constant) uniform PushConstants {
    vec2 clip_scale;
    vec2 clip_offset;
} constants;

void main() {
    instance_id = gl_VertexIndex / 6;
    int sub_vert_id = gl_VertexIndex % 6;
    InstanceData instance = instance_buffer.data[instance_id];
    float c = cos(instance.rotation);
    float s = sin(instance.rotation);
    mat2x2 rot_mat = mat2x2(c, s, -s, c);

    vec2 center_pos = instance.pos + instance.size / vec2(2.0, 2.0);
    gl_Position = vec4((base_pos[sub_vert_id] * rot_mat * instance.size + center_pos + constants.clip_offset) * constants.clip_scale, 0.0, 1.0);
    out_uv = base_uv[sub_vert_id] * instance.uv_size + instance.uv;
}