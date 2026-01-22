#version 450 core

const uint medium_text_type = 0;
const uint medium_italic_text_type = 1;
const uint bold_text_type = 2;
const uint bold_italic_text_type = 3;

const uint quad_render_type = 0;
const uint ui_quad_render_type = 1;
const uint minimap_render_type = 2;
const uint text_normal_render_type = 3;
const uint text_subpixel_render_type = 4;

layout(location = 0) flat in int instance_id;
layout(location = 1) in vec2 in_uv;

layout(location = 0) out vec4 color;

struct InstanceData {
    uint render_type;
    uint text_type;
    float rotation;
    float text_dist_factor;
    uint padding1;
    float alpha_mult;
    uint outline_color;
    float outline_width;
    uint base_color;
    float color_intensity;
    vec2 pos;
    vec2 size;
    vec2 uv;
    vec2 uv_size;
    vec2 padding2;
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

float resolveDist(float dist, float dist_factor, float width) {
    return clamp((dist - 0.5 + width) * dist_factor + 0.5, 0.0, 1.0);
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
        default: discard;

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

        case text_normal_render_type: {
            float dist = 0.0;
            switch (instance.text_type) {
                default: discard;

                case medium_text_type:
                    dist = textureGrad(medium_text_tex, in_uv, dx, dy).r;
                    break;

                case medium_italic_text_type:
                    dist = textureGrad(medium_italic_text_tex, in_uv, dx, dy).r;
                    break;

                case bold_text_type:
                    dist = textureGrad(bold_text_tex, in_uv, dx, dy).r;
                    break;
                
                case bold_italic_text_type:
                    dist = textureGrad(bold_italic_text_tex, in_uv, dx, dy).r;
                    break;
            }

            if (dist == 0.0) discard;
            
            float alpha = resolveDist(dist, instance.text_dist_factor, 0.0);
            vec4 base_pixel = vec4(unpackColor(instance.base_color), alpha * instance.alpha_mult);
            if (instance.outline_width <= 0.0) {
                color = premultiply(base_pixel);
                return;
            }

            float outline_alpha = resolveDist(dist, instance.text_dist_factor, instance.outline_width);
            color = premultiply(mix(vec4(unpackColor(instance.outline_color), outline_alpha * instance.alpha_mult), base_pixel, alpha * instance.alpha_mult));
            return;
        }

        case text_subpixel_render_type: {
            vec2 subpixel_width = vec2((abs(dx.x) + abs(dy.x)) / 3.0, 0.0);

            float red = 0.0;
            float green = 0.0;
            float blue = 0.0;
            switch (instance.text_type) {
                default: discard;

                case medium_text_type:
                    red = textureGrad(medium_text_tex, in_uv - subpixel_width, dx, dy).r;
                    green = textureGrad(medium_text_tex, in_uv, dx, dy).r;
                    blue = textureGrad(medium_text_tex, in_uv + subpixel_width, dx, dy).r;
                    break;

                case medium_italic_text_type:
                    red = textureGrad(medium_italic_text_tex, in_uv - subpixel_width, dx, dy).r;
                    green = textureGrad(medium_italic_text_tex, in_uv, dx, dy).r;
                    blue = textureGrad(medium_italic_text_tex, in_uv + subpixel_width, dx, dy).r;
                    break;

                case bold_text_type:
                    red = textureGrad(bold_text_tex, in_uv - subpixel_width, dx, dy).r;
                    green = textureGrad(bold_text_tex, in_uv, dx, dy).r;
                    blue = textureGrad(bold_text_tex, in_uv + subpixel_width, dx, dy).r;
                    break;
                
                case bold_italic_text_type:
                    red = textureGrad(bold_italic_text_tex, in_uv - subpixel_width, dx, dy).r;
                    green = textureGrad(bold_italic_text_tex, in_uv, dx, dy).r;
                    blue = textureGrad(bold_italic_text_tex, in_uv + subpixel_width, dx, dy).r;
                    break;
            }

            if (red == 0.0 && green == 0.0 && blue == 0.0) discard;
            
            float red_alpha = resolveDist(red, instance.text_dist_factor, 0.0) * instance.alpha_mult;
            float green_alpha = resolveDist(green, instance.text_dist_factor, 0.0) * instance.alpha_mult;
            float blue_alpha = resolveDist(blue, instance.text_dist_factor, 0.0) * instance.alpha_mult;

            vec3 base_color = unpackColor(instance.base_color);
            vec4 base_pixel = vec4(
                base_color.r * red_alpha,
                base_color.g * green_alpha,
                base_color.b * blue_alpha,
                green_alpha
            );
            if (instance.outline_width <= 0.0) {
                color = premultiply(base_pixel);
                return;
            }

            float outline_alpha = resolveDist(green, instance.text_dist_factor, instance.outline_width);
            color = premultiply(mix(vec4(unpackColor(instance.outline_color), outline_alpha * instance.alpha_mult), base_pixel, green_alpha));
            return;
        }
    }

    discard;
}
