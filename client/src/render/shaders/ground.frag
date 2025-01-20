#version 450 core

const vec2 base_size = vec2(9.0, 9.0); // atlas px per tile
const vec2 scaled_size = vec2(63.0, 63.0); // screen px per tile

layout(location = 0) flat in int instance_id;
layout(location = 1) in vec2 in_uv;

layout(location = 0) out vec4 color;

struct InstanceData {
    vec2 pos;
    vec2 uv;
    vec2 offset_uv;
    vec2 left_blend_uv;
    vec2 top_blend_uv;
    vec2 right_blend_uv;
    vec2 bottom_blend_uv;
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

layout(set = 0, binding = 0) uniform sampler2D ground_tex;

vec4 unpackColor(uint color) {
    return vec4(
        float(color & 255) / 255.0,
        float((color >> 8) & 255) / 255.0,
        float((color >> 16) & 255) / 255.0,
        float((color >> 24) & 255) / 255.0
    );
}

void main() {
    InstanceData instance = instance_buffer.data[instance_id];
    vec2 dx = dFdx(in_uv);
    vec2 dy = dFdy(in_uv);
    vec4 rgba = unpackColor(instance.color);

    if ((instance.left_blend_uv.x > 0.0 || instance.left_blend_uv.y > 0.0) &&
            textureGrad(ground_tex, constants.left_mask_uv + in_uv, dx, dy).a == 1.0) {
        vec4 tex = textureGrad(ground_tex, instance.left_blend_uv + in_uv, dx, dy);
        if (rgba.a <= 0.0) {
            color = tex;
            return;
        }
        color = vec4(mix(tex.rgb, rgba.rgb, rgba.a), tex.a);
        return;
    }

    if ((instance.top_blend_uv.x > 0.0 || instance.top_blend_uv.y > 0.0) &&
            textureGrad(ground_tex, constants.top_mask_uv + in_uv, dx, dy).a == 1.0) {
        vec4 tex = textureGrad(ground_tex, instance.top_blend_uv + in_uv, dx, dy);
        if (rgba.a <= 0.0) {
            color = tex;
            return;
        }
        color = vec4(mix(tex.rgb, rgba.rgb, rgba.a), tex.a);
        return;
    }

    if ((instance.right_blend_uv.x > 0.0 || instance.right_blend_uv.y > 0.0) &&
            textureGrad(ground_tex, constants.right_mask_uv + in_uv, dx, dy).a == 1.0) {
        vec4 tex = textureGrad(ground_tex, instance.right_blend_uv + in_uv, dx, dy);
        if (rgba.a <= 0.0) {
            color = tex;
            return;
        }
        color = vec4(mix(tex.rgb, rgba.rgb, rgba.a), tex.a);
        return;
    }

    if ((instance.bottom_blend_uv.x > 0.0 || instance.bottom_blend_uv.y > 0.0) &&
            textureGrad(ground_tex, constants.bottom_mask_uv + in_uv, dx, dy).a == 1.0) {
        vec4 tex = textureGrad(ground_tex, instance.bottom_blend_uv + in_uv, dx, dy);
        if (rgba.a <= 0.0) {
            color = tex;
            return;
        }
        color = vec4(mix(tex.rgb, rgba.rgb, rgba.a), tex.a);
        return;
    }

    vec2 dims = base_size / constants.atlas_size;
    vec2 clamp_uv = mod(in_uv + instance.offset_uv + dims, dims);
    vec4 tex = textureGrad(ground_tex, clamp_uv + instance.uv, dx, dy);
    if (rgba.a <= 0.0) {
        color = tex;
        return;
    }

    color = vec4(mix(tex.rgb, rgba.rgb, rgba.a), tex.a);
}
