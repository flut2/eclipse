#version 450 core

const uint medium_text_type = 0;
const uint medium_italic_text_type = 1;
const uint bold_text_type = 2;
const uint bold_italic_text_type = 3;

const uint quad_render_type = 0;
const uint ui_quad_render_type = 1;
const uint minimap_render_type = 2;
const uint menu_bg_render_type = 3;
const uint text_normal_render_type = 4;
const uint text_drop_shadow_render_type = 5;

layout(location = 0) flat in int instance_id;
layout(location = 1) in vec2 in_uv;

layout(location = 0) out vec4 color;

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

layout(std140, set = 1, binding = 1) readonly buffer UiInstanceBuffer {
    InstanceData data[];
} ui_instance_buffer;

layout(std140, push_constant) uniform PushConstants {
    vec2 clip_scale;
    vec2 clip_offset;
    uint is_ui;
} constants;

layout(set = 0, binding = 0) uniform sampler2D game_tex;
layout(set = 0, binding = 1) uniform sampler2D ui_tex;
layout(set = 0, binding = 2) uniform sampler2D medium_text_tex;
layout(set = 0, binding = 3) uniform sampler2D medium_italic_text_tex;
layout(set = 0, binding = 4) uniform sampler2D bold_text_tex;
layout(set = 0, binding = 5) uniform sampler2D bold_italic_text_tex;
layout(set = 0, binding = 6) uniform sampler2D minimap_tex;
layout(set = 0, binding = 7) uniform sampler2D menu_bg_tex;

vec4 premultiply(vec4 tex) {
    return vec4(tex.rgb * tex.a, tex.a);
}

vec3 unpackColor(uint color) {
    return vec3(
        float((color & 0xFF0000) >> 16) / 255.0, 
        float((color & 0x00FF00) >> 8) / 255.0, 
        float(color & 0x0000FF) / 255.0
    );
}

float median(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

float sampleMsdf(vec4 tex, float dist_factor, float width) {
    return clamp((median(tex.r, tex.g, tex.b) - 0.5) * dist_factor + 0.5 + width, 0.0, 1.0);
}

void main() {
    InstanceData instance = constants.is_ui == 1 ? ui_instance_buffer.data[instance_id] : instance_buffer.data[instance_id];
    vec2 dx = dFdx(in_uv);
    vec2 dy = dFdy(in_uv);

    if (clamp(in_uv.x, instance.scissor.x, instance.scissor.y) != in_uv.x || 
        clamp(in_uv.y, instance.scissor.z, instance.scissor.w) != in_uv.y) {
        discard;
    }

    switch (instance.render_type) {
        default: {
            color = vec4(0.0, 0.0, 0.0, 1.0);
            return;
        }

        case quad_render_type: {
            vec4 pixel = textureGrad(game_tex, in_uv, dx, dy);
            color = premultiply(vec4(mix(pixel.rgb, unpackColor(instance.base_color), instance.color_intensity), pixel.a * instance.alpha_mult));
            return;
        }

        case ui_quad_render_type: {
            vec4 pixel = textureGrad(ui_tex, in_uv, dx, dy);
            color = premultiply(vec4(mix(pixel.rgb, unpackColor(instance.base_color), instance.color_intensity), pixel.a * instance.alpha_mult));
            return;
        }

        case minimap_render_type: {
            color = premultiply(textureGrad(minimap_tex, in_uv, dx, dy));
            return;
        }

        case menu_bg_render_type: {
            color = premultiply(textureGrad(menu_bg_tex, in_uv, dx, dy));
            return;
        }

        case text_normal_render_type: {
            vec4 tex = vec4(0.0, 0.0, 0.0, 0.0);
            switch (instance.text_type) {
                default: discard;
                case medium_text_type: tex = textureGrad(medium_text_tex, in_uv, dx, dy); break;
                case medium_italic_text_type: tex = textureGrad(medium_italic_text_tex, in_uv, dx, dy); break;
                case bold_text_type: tex = textureGrad(bold_text_tex, in_uv, dx, dy); break;
                case bold_italic_text_type: tex = textureGrad(bold_italic_text_tex, in_uv, dx, dy); break;
            }

            float alpha = sampleMsdf(tex, instance.text_dist_factor, 0.0);
            vec4 base_pixel = vec4(unpackColor(instance.base_color), alpha * instance.alpha_mult);
            if (instance.outline_width <= 0.0) {
                color = base_pixel;
                return;
            }

            float outline_alpha = sampleMsdf(tex, instance.text_dist_factor, instance.outline_width);
            color = premultiply(mix(vec4(unpackColor(instance.outline_color), outline_alpha * instance.alpha_mult), base_pixel, alpha * instance.alpha_mult));
            return;
        }

        case text_drop_shadow_render_type: {
            vec4 tex = vec4(0.0, 0.0, 0.0, 0.0);
            vec4 tex_offset = vec4(0.0, 0.0, 0.0, 0.0);
            switch (instance.text_type) {
                default: discard;
                case medium_text_type: {
                    tex = textureGrad(medium_text_tex, in_uv, dx, dy);
                    tex_offset = textureGrad(medium_text_tex, in_uv - instance.shadow_texel_size, dx, dy);
                    break;
                }
                case medium_italic_text_type: {
                    tex = textureGrad(medium_italic_text_tex, in_uv, dx, dy);
                    tex_offset = textureGrad(medium_italic_text_tex, in_uv - instance.shadow_texel_size, dx, dy);
                    break;
                }
                case bold_text_type: {
                    tex = textureGrad(bold_text_tex, in_uv, dx, dy);
                    tex_offset = textureGrad(bold_text_tex, in_uv - instance.shadow_texel_size, dx, dy);
                    break;
                }
                case bold_italic_text_type: {
                    tex = textureGrad(bold_italic_text_tex, in_uv, dx, dy);
                    tex_offset = textureGrad(bold_italic_text_tex, in_uv - instance.shadow_texel_size, dx, dy);
                    break;
                }
            }

            float alpha = sampleMsdf(tex, instance.text_dist_factor, 0.0);
            vec4 base_pixel = vec4(unpackColor(instance.base_color), alpha * instance.alpha_mult);

            float offset_opacity = sampleMsdf(tex_offset, instance.text_dist_factor, instance.outline_width);
            vec4 offset_pixel = vec4(unpackColor(instance.shadow_color), offset_opacity * instance.alpha_mult);

            if (instance.outline_width <= 0.0) {
                color = mix(offset_pixel, base_pixel, alpha);
                return;
            }

            float outline_alpha = sampleMsdf(tex, instance.text_dist_factor, instance.outline_width);
            vec4 outlined_pixel = mix(vec4(unpackColor(instance.outline_color), outline_alpha * instance.alpha_mult), base_pixel, alpha * instance.alpha_mult);

            color = premultiply(mix(offset_pixel, outlined_pixel, outline_alpha));
            return;
        }
    }

    color = premultiply(vec4(0.0, 1.0, 0.0, 1.0));
    return;
}