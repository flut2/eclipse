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
const text_normal_subpixel_off_render_type = 6;
const text_drop_shadow_subpixel_off_render_type = 7;
const wall_upper_render_type = 8;
const wall_top_side_render_type = 9;
const wall_bottom_side_render_type = 10;
const wall_left_side_render_type = 11;
const wall_right_side_render_type = 12;

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

    var out: FragmentData;
    switch instance.render_type {
        default {
            let center_pos = instance.pos + instance.size / vec2<f32>(2.0, 2.0);
            out.position = vec4((pos[sub_vert_id] * rot_mat * instance.size + center_pos + uniforms.clip_offset) * uniforms.clip_scale * invert_y, 0.0, 1.0);
        }

        case wall_upper_render_type {
            let upper_quad = (pos[sub_vert_id] * rot_mat * instance.size - vec2(0.0, instance.size.y) + instance.pos + uniforms.clip_offset) * uniforms.clip_scale * invert_y;
            out.position = vec4(upper_quad, 0.0, 1.0);
        }

        case wall_bottom_side_render_type {
            switch sub_vert_id {
                default {}

                case 0 {
                    let upper_quad = (pos[0] * rot_mat * instance.size - vec2(0.0, instance.size.y) + instance.pos + uniforms.clip_offset) * uniforms.clip_scale * invert_y;
                    out.position = vec4(upper_quad, 0.0, 1.0);
                }

                case 1, 4 {
                    let upper_quad = (pos[1] * rot_mat * instance.size - vec2(0.0, instance.size.y) + instance.pos + uniforms.clip_offset) * uniforms.clip_scale * invert_y;
                    out.position = vec4(upper_quad, 0.0, 1.0);
                }

                case 2, 3 {
                    let lower_quad = (pos[0] * rot_mat * instance.size + instance.pos + uniforms.clip_offset) * uniforms.clip_scale * invert_y;
                    out.position = vec4(lower_quad, 0.0, 1.0);
                }

                case 5 {
                    let lower_quad = (pos[1] * rot_mat * instance.size + instance.pos + uniforms.clip_offset) * uniforms.clip_scale * invert_y;
                    out.position = vec4(lower_quad, 0.0, 1.0);
                }
            }
        }

        case wall_top_side_render_type {
            switch sub_vert_id {
                default {}

                case 0 {
                    let upper_quad = (pos[3] * rot_mat * instance.size - vec2(0.0, instance.size.y) + instance.pos + uniforms.clip_offset) * uniforms.clip_scale * invert_y;
                    out.position = vec4(upper_quad, 0.0, 1.0);
                }

                case 1, 4 {
                    let upper_quad = (pos[5] * rot_mat * instance.size - vec2(0.0, instance.size.y) + instance.pos + uniforms.clip_offset) * uniforms.clip_scale * invert_y;
                    out.position = vec4(upper_quad, 0.0, 1.0);
                }

                case 2, 3 {
                    let lower_quad = (pos[3] * rot_mat * instance.size + instance.pos + uniforms.clip_offset) * uniforms.clip_scale * invert_y;
                    out.position = vec4(lower_quad, 0.0, 1.0);
                }

                case 5 {
                    let lower_quad = (pos[5] * rot_mat * instance.size + instance.pos + uniforms.clip_offset) * uniforms.clip_scale * invert_y;
                    out.position = vec4(lower_quad, 0.0, 1.0);
                }
            }
        }

        case wall_left_side_render_type {
            switch sub_vert_id {
                default {}

                case 0 {
                    let upper_quad = (pos[0] * rot_mat * instance.size - vec2(0.0, instance.size.y) + instance.pos + uniforms.clip_offset) * uniforms.clip_scale * invert_y;
                    out.position = vec4(upper_quad, 0.0, 1.0);
                }

                case 1, 4 {
                    let upper_quad = (pos[3] * rot_mat * instance.size - vec2(0.0, instance.size.y) + instance.pos + uniforms.clip_offset) * uniforms.clip_scale * invert_y;
                    out.position = vec4(upper_quad, 0.0, 1.0);
                }

                case 2, 3 {
                    let lower_quad = (pos[0] * rot_mat * instance.size + instance.pos + uniforms.clip_offset) * uniforms.clip_scale * invert_y;
                    out.position = vec4(lower_quad, 0.0, 1.0);
                }

                case 5 {
                    let lower_quad = (pos[3] * rot_mat * instance.size + instance.pos + uniforms.clip_offset) * uniforms.clip_scale * invert_y;
                    out.position = vec4(lower_quad, 0.0, 1.0);
                }
            }
        }

        case wall_right_side_render_type {
            switch sub_vert_id {
                default {}
                
                case 0 {
                    let upper_quad = (pos[1] * rot_mat * instance.size - vec2(0.0, instance.size.y) + instance.pos + uniforms.clip_offset) * uniforms.clip_scale * invert_y;
                    out.position = vec4(upper_quad, 0.0, 1.0);
                }

                case 1, 4 {
                    let upper_quad = (pos[5] * rot_mat * instance.size - vec2(0.0, instance.size.y) + instance.pos + uniforms.clip_offset) * uniforms.clip_scale * invert_y;
                    out.position = vec4(upper_quad, 0.0, 1.0);
                }

                case 2, 3 {
                    let lower_quad = (pos[1] * rot_mat * instance.size + instance.pos + uniforms.clip_offset) * uniforms.clip_scale * invert_y;
                    out.position = vec4(lower_quad, 0.0, 1.0);
                }

                case 5 {
                    let lower_quad = (pos[5] * rot_mat * instance.size + instance.pos + uniforms.clip_offset) * uniforms.clip_scale * invert_y;
                    out.position = vec4(lower_quad, 0.0, 1.0);
                }
            }
        }
    }
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

        case quad_render_type, 
            wall_upper_render_type, 
            wall_top_side_render_type, 
            wall_bottom_side_render_type, 
            wall_left_side_render_type, 
            wall_right_side_render_type {
            let pixel = textureSampleGrad(game_tex, default_sampler, fragment.uv, dx, dy);
            return vec4(mix(pixel.rgb, unpackColor(instance.base_color), instance.color_intensity), pixel.a * instance.alpha_mult);
        }

        case ui_quad_render_type {
            let pixel = textureSampleGrad(ui_tex, default_sampler, fragment.uv, dx, dy);
            return vec4(mix(pixel.rgb, unpackColor(instance.base_color), instance.color_intensity), pixel.a * instance.alpha_mult);
        }

        case minimap_render_type {
            return textureSampleGrad(minimap_tex, default_sampler, fragment.uv, dx, dy);
        }

        case menu_bg_render_type {
            return textureSampleGrad(menu_bg_tex, linear_sampler, fragment.uv, dx, dy);
        }

        case text_normal_render_type {
            const subpixel = 1.0 / 3.0;
            let subpixel_width = (abs(dx.x) + abs(dy.x)) * subpixel; // this is just fwidth(in.uv).x * subpixel

            var red_tex = vec4(0.0, 0.0, 0.0, 0.0);
            var green_tex = vec4(0.0, 0.0, 0.0, 0.0);
            var blue_tex = vec4(0.0, 0.0, 0.0, 0.0);
            var tex_offset = vec4(0.0, 0.0, 0.0, 0.0);
            switch instance.text_type {
                default {
                    discard;
                }

                case medium_text_type {
                    red_tex = textureSampleGrad(medium_tex, linear_sampler, vec2(fragment.uv.x - subpixel_width, fragment.uv.y), dx, dy);
                    green_tex = textureSampleGrad(medium_tex, linear_sampler, fragment.uv, dx, dy);
                    blue_tex = textureSampleGrad(medium_tex, linear_sampler, vec2(fragment.uv.x + subpixel_width, fragment.uv.y), dx, dy);
                }

                case medium_italic_text_type {
                    red_tex = textureSampleGrad(medium_italic_tex, linear_sampler, vec2(fragment.uv.x - subpixel_width, fragment.uv.y), dx, dy);
                    green_tex = textureSampleGrad(medium_italic_tex, linear_sampler, fragment.uv, dx, dy);
                    blue_tex = textureSampleGrad(medium_italic_tex, linear_sampler, vec2(fragment.uv.x + subpixel_width, fragment.uv.y), dx, dy);
                }

                case bold_text_type {
                    red_tex = textureSampleGrad(bold_tex, linear_sampler, vec2(fragment.uv.x - subpixel_width, fragment.uv.y), dx, dy);
                    green_tex = textureSampleGrad(bold_tex, linear_sampler, fragment.uv, dx, dy);
                    blue_tex = textureSampleGrad(bold_tex, linear_sampler, vec2(fragment.uv.x + subpixel_width, fragment.uv.y), dx, dy);
                }

                case bold_italic_text_type {
                    red_tex = textureSampleGrad(bold_italic_tex, linear_sampler, vec2(fragment.uv.x - subpixel_width, fragment.uv.y), dx, dy);
                    green_tex = textureSampleGrad(bold_italic_tex, linear_sampler, fragment.uv, dx, dy);
                    blue_tex = textureSampleGrad(bold_italic_tex, linear_sampler, vec2(fragment.uv.x + subpixel_width, fragment.uv.y), dx, dy);
                }
            }

            let red = sampleMsdf(red_tex, instance.text_dist_factor, instance.alpha_mult, 0.5);
            let green = sampleMsdf(green_tex, instance.text_dist_factor, instance.alpha_mult, 0.5);
            let blue = sampleMsdf(blue_tex, instance.text_dist_factor, instance.alpha_mult, 0.5);

            let alpha = clamp((red + green + blue) / 3.0, 0.0, 1.0);
            let base_color = unpackColor(instance.base_color);
            let base_pixel = vec4(red * base_color.r, green * base_color.g, blue * base_color.b, alpha);

            let outline_alpha = sampleMsdf(green_tex, instance.text_dist_factor, instance.alpha_mult, instance.outline_width);
            return mix(vec4(unpackColor(instance.outline_color), outline_alpha), base_pixel, alpha);
        }

        case text_normal_subpixel_off_render_type {
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

            let alpha = sampleMsdf(tex, instance.text_dist_factor, instance.alpha_mult, 0.5);
            let base_pixel = vec4(unpackColor(instance.base_color), alpha);

            let outline_alpha = sampleMsdf(tex, instance.text_dist_factor, instance.alpha_mult, instance.outline_width);
            return mix(vec4(unpackColor(instance.outline_color), outline_alpha), base_pixel, alpha);
        }

        case text_drop_shadow_render_type {
            const subpixel = 1.0 / 3.0;
            let subpixel_width = (abs(dx.x) + abs(dy.x)) * subpixel; // this is just fwidth(in.uv).x * subpixel

            var red_tex = vec4(0.0, 0.0, 0.0, 0.0);
            var green_tex = vec4(0.0, 0.0, 0.0, 0.0);
            var blue_tex = vec4(0.0, 0.0, 0.0, 0.0);
            var tex_offset = vec4(0.0, 0.0, 0.0, 0.0);
            switch instance.text_type {
                default {
                    discard;
                }

                case medium_text_type {
                    red_tex = textureSampleGrad(medium_tex, linear_sampler, vec2(fragment.uv.x - subpixel_width, fragment.uv.y), dx, dy);
                    green_tex = textureSampleGrad(medium_tex, linear_sampler, fragment.uv, dx, dy);
                    blue_tex = textureSampleGrad(medium_tex, linear_sampler, vec2(fragment.uv.x + subpixel_width, fragment.uv.y), dx, dy);
                    tex_offset = textureSampleGrad(medium_tex, linear_sampler, fragment.uv - instance.shadow_texel_size, dx, dy);
                }

                case medium_italic_text_type {
                    red_tex = textureSampleGrad(medium_italic_tex, linear_sampler, vec2(fragment.uv.x - subpixel_width, fragment.uv.y), dx, dy);
                    green_tex = textureSampleGrad(medium_italic_tex, linear_sampler, fragment.uv, dx, dy);
                    blue_tex = textureSampleGrad(medium_italic_tex, linear_sampler, vec2(fragment.uv.x + subpixel_width, fragment.uv.y), dx, dy);
                    tex_offset = textureSampleGrad(medium_italic_tex, linear_sampler, fragment.uv - instance.shadow_texel_size, dx, dy);
                }

                case bold_text_type {
                    red_tex = textureSampleGrad(bold_tex, linear_sampler, vec2(fragment.uv.x - subpixel_width, fragment.uv.y), dx, dy);
                    green_tex = textureSampleGrad(bold_tex, linear_sampler, fragment.uv, dx, dy);
                    blue_tex = textureSampleGrad(bold_tex, linear_sampler, vec2(fragment.uv.x + subpixel_width, fragment.uv.y), dx, dy);
                    tex_offset = textureSampleGrad(bold_tex, linear_sampler, fragment.uv - instance.shadow_texel_size, dx, dy);
                }

                case bold_italic_text_type {
                    red_tex = textureSampleGrad(bold_italic_tex, linear_sampler, vec2(fragment.uv.x - subpixel_width, fragment.uv.y), dx, dy);
                    green_tex = textureSampleGrad(bold_italic_tex, linear_sampler, fragment.uv, dx, dy);
                    blue_tex = textureSampleGrad(bold_italic_tex, linear_sampler, vec2(fragment.uv.x + subpixel_width, fragment.uv.y), dx, dy);
                    tex_offset = textureSampleGrad(bold_italic_tex, linear_sampler, fragment.uv - instance.shadow_texel_size, dx, dy);
                }
            }

            let red = sampleMsdf(red_tex, instance.text_dist_factor, instance.alpha_mult, 0.5);
            let green = sampleMsdf(green_tex, instance.text_dist_factor, instance.alpha_mult, 0.5);
            let blue = sampleMsdf(blue_tex, instance.text_dist_factor, instance.alpha_mult, 0.5);

            let alpha = clamp((red + green + blue) / 3.0, 0.0, 1.0);
            let base_color = unpackColor(instance.base_color);
            let base_pixel = vec4(red * base_color.r, green * base_color.g, blue * base_color.b, alpha);

            let outline_alpha = sampleMsdf(green_tex, instance.text_dist_factor, instance.alpha_mult, instance.outline_width);
            let outlined_pixel = mix(vec4(unpackColor(instance.outline_color), outline_alpha), base_pixel, alpha);

            // don't subpixel aa the offset, it's supposed to be a shadow
            let offset_opacity = sampleMsdf(tex_offset, instance.text_dist_factor, instance.alpha_mult, instance.outline_width);
            let offset_pixel = vec4(unpackColor(instance.shadow_color), offset_opacity);

            return mix(offset_pixel, base_pixel, outline_alpha);
        }

        case text_drop_shadow_subpixel_off_render_type {
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

            let alpha = sampleMsdf(tex, instance.text_dist_factor, instance.alpha_mult, 0.5);
            let base_pixel = vec4(unpackColor(instance.base_color), alpha);

            let outline_alpha = sampleMsdf(tex, instance.text_dist_factor, instance.alpha_mult, instance.outline_width);
            let outlined_pixel = mix(vec4(unpackColor(instance.outline_color), outline_alpha), base_pixel, alpha);

            let offset_opacity = sampleMsdf(tex_offset, instance.text_dist_factor, instance.alpha_mult, instance.outline_width);
            let offset_pixel = vec4(unpackColor(instance.shadow_color), offset_opacity);

            return mix(offset_pixel, base_pixel, outline_alpha);
        }
    }

    return vec4(0.0, 1.0, 0.0, 1.0);
}

fn unpackColor(color: u32) -> vec3<f32> {
    return vec3<f32>(f32((color & 0xFF0000) >> 16) / 255.0, f32((color & 0x00FF00) >> 8) / 255.0, f32(color & 0x0000FF) / 255.0);
}

fn median(r: f32, g: f32, b: f32) -> f32 {
    return max(min(r, g), min(max(r, g), b));
}

fn sampleMsdf(tex: vec4<f32>, dist_factor: f32, alpha_mult: f32, width: f32) -> f32 {
    return clamp((median(tex.r, tex.g, tex.b) - 0.5) * dist_factor + width, 0.0, 1.0) * alpha_mult;
}
