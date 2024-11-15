@group(0) @binding(0) var<uniform> uniforms: Uniforms;
@group(0) @binding(1) var<storage, read> instances: array<InstanceData>;
@group(0) @binding(2) var default_sampler: sampler;
@group(0) @binding(3) var linear_sampler: sampler;
@group(0) @binding(4) var game_tex: texture_2d<f32>;
@group(0) @binding(5) var ui_tex: texture_2d<f32>;
@group(0) @binding(6) var medium_tex: texture_2d<f32>;
@group(0) @binding(7) var medium_italic_tex: texture_2d<f32>;
@group(0) @binding(8) var bold_tex: texture_2d<f32>;
@group(0) @binding(9) var bold_italic_tex: texture_2d<f32>;
@group(1) @binding(0) var minimap_tex: texture_2d<f32>;
@group(1) @binding(1) var menu_bg_tex: texture_2d<f32>;

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

const invert_y: vec2<f32> = vec2<f32>(1.0, -1.0);

const medium_text_type = 0;
const medium_italic_text_type = 1;
const bold_text_type = 2;
const bold_italic_text_type = 3;

const quad_render_type = 0;
const ui_quad_render_type = 1;
const minimap_render_type = 2;
const menu_bg_render_type = 3;
const text_normal_render_type = 4;
const text_drop_shadow_render_type = 5;

struct Uniforms {
    clip_scale: vec2<f32>,
    clip_offset: vec2<f32>,
}

struct InstanceData {
    render_type: u32,
    text_type: u32,
    rotation: f32,
    text_dist_factor: f32,
    shadow_color: u32,
    alpha_mult: f32,
    outline_color: u32,
    outline_width: f32,
    base_color: u32,
    color_intensity: f32,
    pos: vec2<f32>,
    size: vec2<f32>,
    uv: vec2<f32>,
    uv_size: vec2<f32>,
    shadow_texel_size: vec2<f32>,
    scissor: vec4<f32>,
}

struct VertexData {
    @builtin(vertex_index) vert_id: u32,
}

struct FragmentData {
    @builtin(position) position: vec4<f32>,
    @location(0) @interpolate(flat) instance_id: u32,
    @location(1) uv: vec2<f32>,
}

@vertex
fn vertexMain(vertex: VertexData) -> FragmentData {
    let instance_id = vertex.vert_id / 6;
    let sub_vert_id = vertex.vert_id % 6;
    let instance = instances[instance_id];
    let cos = cos(instance.rotation);
    let sin = sin(instance.rotation);
    let rot_mat = mat2x2<f32>(cos, sin, -sin, cos);

    let center_pos = instance.pos + instance.size / vec2<f32>(2.0, 2.0);
    var out: FragmentData;
    out.position = vec4((pos[sub_vert_id] * rot_mat * instance.size + center_pos + uniforms.clip_offset) * uniforms.clip_scale * invert_y, 0.0, 1.0);
    out.uv = uv[sub_vert_id] * instance.uv_size + instance.uv;
    out.instance_id = instance_id;
    return out;
}

@fragment
fn fragmentMain(fragment: FragmentData) -> @location(0) vec4<f32> {
    let instance = instances[fragment.instance_id];
    let dx = dpdx(fragment.uv);
    let dy = dpdy(fragment.uv);

    if clamp(fragment.uv.x, instance.scissor.x, instance.scissor.y) != fragment.uv.x || 
        clamp(fragment.uv.y, instance.scissor.z, instance.scissor.w) != fragment.uv.y {
        discard;
    }

    switch instance.render_type {
        default {
            return vec4(0.0, 0.0, 0.0, 1.0);
        }

        case quad_render_type {
            let pixel = textureSampleGrad(game_tex, default_sampler, fragment.uv, dx, dy);
            return premultiply(vec4(mix(pixel.rgb, unpackColor(instance.base_color), instance.color_intensity), pixel.a * instance.alpha_mult));
        }

        case ui_quad_render_type {
            let pixel = textureSampleGrad(ui_tex, default_sampler, fragment.uv, dx, dy);
            return premultiply(vec4(mix(pixel.rgb, unpackColor(instance.base_color), instance.color_intensity), pixel.a * instance.alpha_mult));
        }

        case minimap_render_type {
            return premultiply(textureSampleGrad(minimap_tex, default_sampler, fragment.uv, dx, dy));
        }

        case menu_bg_render_type {
            return premultiply(textureSampleGrad(menu_bg_tex, linear_sampler, fragment.uv, dx, dy));
        }

        case text_normal_render_type {
            var tex = vec4(0.0, 0.0, 0.0, 0.0);
            switch instance.text_type {
                default {
                    discard;
                }

                case medium_text_type {
                    tex = textureSampleGrad(medium_tex, linear_sampler, fragment.uv, dx, dy);
                }

                case medium_italic_text_type {
                    tex = textureSampleGrad(medium_italic_tex, linear_sampler, fragment.uv, dx, dy);
                }

                case bold_text_type {
                    tex = textureSampleGrad(bold_tex, linear_sampler, fragment.uv, dx, dy);
                }

                case bold_italic_text_type {
                    tex = textureSampleGrad(bold_italic_tex, linear_sampler, fragment.uv, dx, dy);
                }
            }

            let alpha = sampleMsdf(tex, instance.text_dist_factor, 0.0);
            let base_pixel = vec4(unpackColor(instance.base_color), alpha * instance.alpha_mult);
            if instance.outline_width <= 0.0 {
                return base_pixel;
            }

            let outline_alpha = sampleMsdf(tex, instance.text_dist_factor, instance.outline_width);
            return premultiply(mix(vec4(unpackColor(instance.outline_color), outline_alpha * instance.alpha_mult), base_pixel, alpha * instance.alpha_mult));
        }

        case text_drop_shadow_render_type {
            var tex = vec4(0.0, 0.0, 0.0, 0.0);
            var tex_offset = vec4(0.0, 0.0, 0.0, 0.0);
            switch instance.text_type {
                default {
                    discard;
                }

                case medium_text_type {
                    tex = textureSampleGrad(medium_tex, linear_sampler, fragment.uv, dx, dy);
                    tex_offset = textureSampleGrad(medium_tex, linear_sampler, fragment.uv - instance.shadow_texel_size, dx, dy);
                }

                case medium_italic_text_type {
                    tex = textureSampleGrad(medium_italic_tex, linear_sampler, fragment.uv, dx, dy);
                    tex_offset = textureSampleGrad(medium_italic_tex, linear_sampler, fragment.uv - instance.shadow_texel_size, dx, dy);
                }

                case bold_text_type {
                    tex = textureSampleGrad(bold_tex, linear_sampler, fragment.uv, dx, dy);
                    tex_offset = textureSampleGrad(bold_tex, linear_sampler, fragment.uv - instance.shadow_texel_size, dx, dy);
                }

                case bold_italic_text_type {
                    tex = textureSampleGrad(bold_italic_tex, linear_sampler, fragment.uv, dx, dy);
                    tex_offset = textureSampleGrad(bold_italic_tex, linear_sampler, fragment.uv - instance.shadow_texel_size, dx, dy);
                }
            }

            let alpha = sampleMsdf(tex, instance.text_dist_factor, 0.0);
            let base_pixel = vec4(unpackColor(instance.base_color), alpha * instance.alpha_mult);

            let offset_opacity = sampleMsdf(tex_offset, instance.text_dist_factor, instance.outline_width);
            let offset_pixel = vec4(unpackColor(instance.shadow_color), offset_opacity * instance.alpha_mult);

            if instance.outline_width <= 0.0 {
                return mix(offset_pixel, base_pixel, alpha);
            }

            let outline_alpha = sampleMsdf(tex, instance.text_dist_factor, instance.outline_width);
            let outlined_pixel = mix(vec4(unpackColor(instance.outline_color), outline_alpha * instance.alpha_mult), base_pixel, alpha * instance.alpha_mult);

            return premultiply(mix(offset_pixel, outlined_pixel, outline_alpha));
        }
    }

    return premultiply(vec4(0.0, 1.0, 0.0, 1.0));
}

fn premultiply(tex: vec4<f32>) -> vec4<f32> {
    return vec4(tex.rgb * tex.a, tex.a);
}

fn unpackColor(color: u32) -> vec3<f32> {
    return vec3<f32>(f32((color & 0xFF0000) >> 16) / 255.0, f32((color & 0x00FF00) >> 8) / 255.0, f32(color & 0x0000FF) / 255.0);
}

fn median(r: f32, g: f32, b: f32) -> f32 {
    return max(min(r, g), min(max(r, g), b));
}

fn sampleMsdf(tex: vec4<f32>, dist_factor: f32, width: f32) -> f32 {
    return clamp((median(tex.r, tex.g, tex.b) - 0.5) * dist_factor + 0.5 + width, 0.0, 1.0);
}
