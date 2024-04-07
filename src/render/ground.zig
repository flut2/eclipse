const std = @import("std");
const base = @import("base.zig");
const camera = @import("../camera.zig");
const map = @import("../game/map.zig");
const settings = @import("../settings.zig");
const assets = @import("../assets.zig");

const Square = @import("../game/square.zig").Square;

inline fn drawSquare(
    idx: u16,
    x1: f32,
    y1: f32,
    x2: f32,
    y2: f32,
    x3: f32,
    y3: f32,
    x4: f32,
    y4: f32,
    atlas_data: assets.AtlasData,
    u_offset: f32,
    v_offset: f32,
    blends: [4]Square.Blend,
    draw_data: base.DrawData,
) u16 {
    var new_idx = idx;
    if (new_idx == base.ground_batch_vert_size) {
        draw_data.encoder.writeBuffer(
            base.ground_vb,
            0,
            base.ground_vert_data[0..base.ground_batch_vert_size],
        );
        base.endDraw(
            draw_data,
            base.ground_batch_vert_size * @sizeOf(base.GroundVertexData),
            @divExact(base.ground_batch_vert_size, 4) * 6,
            null,
        );
        new_idx = 0;
    }

    base.ground_vert_data[new_idx] = base.GroundVertexData{
        .pos_uv = .{
            .x = x1,
            .y = y1,
            .z = atlas_data.tex_w,
            .w = atlas_data.tex_h,
        },
        .left_top_blend_uv = .{
            .x = blends[Square.left_blend_idx].u,
            .y = blends[Square.left_blend_idx].v,
            .z = blends[Square.top_blend_idx].u,
            .w = blends[Square.top_blend_idx].v,
        },
        .right_bottom_blend_uv = .{
            .x = blends[Square.right_blend_idx].u,
            .y = blends[Square.right_blend_idx].v,
            .z = blends[Square.bottom_blend_idx].u,
            .w = blends[Square.bottom_blend_idx].v,
        },
        .base_and_offset_uv = .{
            .x = atlas_data.tex_u,
            .y = atlas_data.tex_v,
            .z = u_offset,
            .w = v_offset,
        },
    };

    base.ground_vert_data[new_idx + 1] = base.GroundVertexData{
        .pos_uv = .{
            .x = x2,
            .y = y2,
            .z = 0,
            .w = atlas_data.tex_h,
        },
        .left_top_blend_uv = .{
            .x = blends[Square.left_blend_idx].u,
            .y = blends[Square.left_blend_idx].v,
            .z = blends[Square.top_blend_idx].u,
            .w = blends[Square.top_blend_idx].v,
        },
        .right_bottom_blend_uv = .{
            .x = blends[Square.right_blend_idx].u,
            .y = blends[Square.right_blend_idx].v,
            .z = blends[Square.bottom_blend_idx].u,
            .w = blends[Square.bottom_blend_idx].v,
        },
        .base_and_offset_uv = .{
            .x = atlas_data.tex_u,
            .y = atlas_data.tex_v,
            .z = u_offset,
            .w = v_offset,
        },
    };

    base.ground_vert_data[new_idx + 2] = base.GroundVertexData{
        .pos_uv = .{
            .x = x3,
            .y = y3,
            .z = 0,
            .w = 0,
        },
        .left_top_blend_uv = .{
            .x = blends[Square.left_blend_idx].u,
            .y = blends[Square.left_blend_idx].v,
            .z = blends[Square.top_blend_idx].u,
            .w = blends[Square.top_blend_idx].v,
        },
        .right_bottom_blend_uv = .{
            .x = blends[Square.right_blend_idx].u,
            .y = blends[Square.right_blend_idx].v,
            .z = blends[Square.bottom_blend_idx].u,
            .w = blends[Square.bottom_blend_idx].v,
        },
        .base_and_offset_uv = .{
            .x = atlas_data.tex_u,
            .y = atlas_data.tex_v,
            .z = u_offset,
            .w = v_offset,
        },
    };

    base.ground_vert_data[new_idx + 3] = base.GroundVertexData{
        .pos_uv = .{
            .x = x4,
            .y = y4,
            .z = atlas_data.tex_w,
            .w = 0,
        },
        .left_top_blend_uv = .{
            .x = blends[Square.left_blend_idx].u,
            .y = blends[Square.left_blend_idx].v,
            .z = blends[Square.top_blend_idx].u,
            .w = blends[Square.top_blend_idx].v,
        },
        .right_bottom_blend_uv = .{
            .x = blends[Square.right_blend_idx].u,
            .y = blends[Square.right_blend_idx].v,
            .z = blends[Square.bottom_blend_idx].u,
            .w = blends[Square.bottom_blend_idx].v,
        },
        .base_and_offset_uv = .{
            .x = atlas_data.tex_u,
            .y = atlas_data.tex_v,
            .z = u_offset,
            .w = v_offset,
        },
    };

    return new_idx + 4;
}

pub inline fn drawSquares(idx: u16, draw_data: base.DrawData, float_time_ms: f32, cam_x: f32, cam_y: f32) u16 {
    var new_idx = idx;

    const px_per_tile = camera.px_per_tile * camera.scale;
    const radius = @sqrt(@as(f32, px_per_tile * px_per_tile / 2)) + 1;
    const pi_div_4 = std.math.pi / 4.0;
    const top_right_angle = pi_div_4;
    const bottom_right_angle = 3.0 * pi_div_4;
    const bottom_left_angle = 5.0 * pi_div_4;
    const top_left_angle = 7.0 * pi_div_4;
    const x1_offset = radius * @cos(top_left_angle + camera.angle) * camera.clip_scale_x;
    const y1_offset = radius * @sin(top_left_angle + camera.angle) * camera.clip_scale_y;
    const x2_offset = radius * @cos(bottom_left_angle + camera.angle) * camera.clip_scale_x;
    const y2_offset = radius * @sin(bottom_left_angle + camera.angle) * camera.clip_scale_y;
    const x3_offset = radius * @cos(bottom_right_angle + camera.angle) * camera.clip_scale_x;
    const y3_offset = radius * @sin(bottom_right_angle + camera.angle) * camera.clip_scale_y;
    const x4_offset = radius * @cos(top_right_angle + camera.angle) * camera.clip_scale_x;
    const y4_offset = radius * @sin(top_right_angle + camera.angle) * camera.clip_scale_y;

    for (camera.min_y..camera.max_y) |y| {
        for (camera.min_x..camera.max_x) |x| {
            const float_x: f32 = @floatFromInt(x);
            const float_y: f32 = @floatFromInt(y);

            const dx = cam_x - float_x - 0.5;
            const dy = cam_y - float_y - 0.5;
            if (dx * dx + dy * dy > camera.max_dist_sq)
                continue;

            if (map.getSquare(float_x, float_y)) |square| {
                if (square.tile_type == 0xFF)
                    continue;

                const screen_pos = camera.rotateAroundCameraClip(square.x, square.y);
                const screen_x = screen_pos.x;
                const screen_y = -screen_pos.y;

                var u_offset = square.u_offset;
                var v_offset = square.v_offset;
                if (settings.enable_lights) {
                    const light_color = square.props.light_color;
                    if (light_color != std.math.maxInt(u32)) {
                        const size = px_per_tile * (square.props.light_radius + square.props.light_pulse *
                            @sin(float_time_ms / 1000.0 * square.props.light_pulse_speed));

                        const light_w = size * 4;
                        const light_h = size * 4;
                        base.lights.append(.{
                            .x = (screen_pos.x + camera.screen_width / 2.0) - light_w / 2.0,
                            .y = (screen_pos.y + camera.screen_height / 2.0) - size * 1.5,
                            .w = light_w,
                            .h = light_h,
                            .color = light_color,
                            .intensity = square.props.light_intensity,
                        }) catch unreachable;
                    }
                }

                switch (square.props.anim_type) {
                    .wave => {
                        u_offset += @sin(square.props.anim_dx * float_time_ms / 1000.0) * assets.base_texel_w;
                        v_offset += @sin(square.props.anim_dy * float_time_ms / 1000.0) * assets.base_texel_h;
                    },
                    .flow => {
                        u_offset += (square.props.anim_dx * float_time_ms / 1000.0) * assets.base_texel_w;
                        v_offset += (square.props.anim_dy * float_time_ms / 1000.0) * assets.base_texel_h;
                    },
                    else => {},
                }

                const scaled_x = screen_x * camera.clip_scale_x;
                const scaled_y = screen_y * camera.clip_scale_y;

                new_idx = drawSquare(
                    new_idx,
                    scaled_x + x1_offset,
                    scaled_y + y1_offset,
                    scaled_x + x2_offset,
                    scaled_y + y2_offset,
                    scaled_x + x3_offset,
                    scaled_y + y3_offset,
                    scaled_x + x4_offset,
                    scaled_y + y4_offset,
                    square.atlas_data,
                    u_offset,
                    v_offset,
                    square.blends,
                    draw_data,
                );
            } else continue;
        }
    }

    return new_idx;
}
