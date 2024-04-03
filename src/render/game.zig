const std = @import("std");
const assets = @import("../assets.zig");
const camera = @import("../camera.zig");
const utils = @import("../utils.zig");
const map = @import("../game/map.zig");
const ui_systems = @import("../ui/systems.zig");
const settings = @import("../settings.zig");
const base = @import("base.zig");

const Particle = @import("../game/particles.zig").Particle;
const Player = @import("../game/player.zig").Player;
const GameObject = @import("../game/game_object.zig").GameObject;
const Projectile = @import("../game/projectile.zig").Projectile;

inline fn drawSide(
    idx: u16,
    x: f32,
    y: f32,
    atlas_data: assets.AtlasData,
    draw_data: base.DrawData,
    color: u32,
    color_intensity: f32,
    alpha: f32,
    x1: f32,
    y1: f32,
    x2: f32,
    y2: f32,
    x3: f32,
    y3: f32,
    x4: f32,
    y4: f32,
) u16 {
    var new_idx = idx;

    var atlas_data_new = atlas_data;
    if (x > 0 and y > 0) {
        if (map.getSquare(x, y)) |square| {
            const en = map.findEntityConst(square.static_obj_id);
            if (en != null and en.? == .object and en.?.object.class == .wall) return new_idx;

            if (square.tile_type == 0xFF) {
                atlas_data_new.tex_u = assets.wall_backface_data.tex_u;
                atlas_data_new.tex_v = assets.wall_backface_data.tex_v;
            }
        } else {
            atlas_data_new.tex_u = assets.wall_backface_data.tex_u;
            atlas_data_new.tex_v = assets.wall_backface_data.tex_v;
        }
    }

    new_idx = base.drawQuadVerts(
        new_idx,
        x1,
        y1,
        x2,
        y2,
        x3,
        y3,
        x4,
        y4,
        atlas_data_new,
        draw_data,
        .{ .base_color = color, .base_color_intensity = color_intensity, .alpha_mult = alpha },
    );

    return new_idx;
}

inline fn drawWall(
    idx: u16,
    x: f32,
    y: f32,
    alpha: f32,
    atlas_data: assets.AtlasData,
    top_atlas_data: assets.AtlasData,
    draw_data: base.DrawData,
) u16 {
    var idx_new: u16 = idx;

    const screen_pos = camera.rotateAroundCameraClip(x, y);
    const screen_x = screen_pos.x;
    const screen_y = -screen_pos.y;
    const screen_y_top = screen_y + camera.px_per_tile;

    const radius = @sqrt(@as(f32, camera.px_per_tile * camera.px_per_tile / 2)) + 1;
    const pi_div_4 = std.math.pi / 4.0;
    const top_right_angle = pi_div_4;
    const bottom_right_angle = 3.0 * pi_div_4;
    const bottom_left_angle = 5.0 * pi_div_4;
    const top_left_angle = 7.0 * pi_div_4;

    const x1 = (screen_x + radius * @cos(top_left_angle + camera.angle)) * camera.clip_scale_x;
    const y1 = (screen_y + radius * @sin(top_left_angle + camera.angle)) * camera.clip_scale_y;
    const x2 = (screen_x + radius * @cos(bottom_left_angle + camera.angle)) * camera.clip_scale_x;
    const y2 = (screen_y + radius * @sin(bottom_left_angle + camera.angle)) * camera.clip_scale_y;
    const x3 = (screen_x + radius * @cos(bottom_right_angle + camera.angle)) * camera.clip_scale_x;
    const y3 = (screen_y + radius * @sin(bottom_right_angle + camera.angle)) * camera.clip_scale_y;
    const x4 = (screen_x + radius * @cos(top_right_angle + camera.angle)) * camera.clip_scale_x;
    const y4 = (screen_y + radius * @sin(top_right_angle + camera.angle)) * camera.clip_scale_y;

    const top_y1 = (screen_y_top + radius * @sin(top_left_angle + camera.angle)) * camera.clip_scale_y;
    const top_y2 = (screen_y_top + radius * @sin(bottom_left_angle + camera.angle)) * camera.clip_scale_y;
    const top_y3 = (screen_y_top + radius * @sin(bottom_right_angle + camera.angle)) * camera.clip_scale_y;
    const top_y4 = (screen_y_top + radius * @sin(top_right_angle + camera.angle)) * camera.clip_scale_y;

    const pi_div_2 = std.math.pi / 2.0;
    const bound_angle = utils.halfBound(camera.angle);
    const color = 0x000000;

    if (bound_angle >= pi_div_2 and bound_angle <= std.math.pi or bound_angle >= -std.math.pi and bound_angle <= -pi_div_2 and y > 0) {
        idx_new = drawSide(idx_new, x, y - 1, atlas_data, draw_data, color, 0.25, alpha, x3, top_y3, x4, top_y4, x4, y4, x3, y3);
    }

    if (bound_angle <= pi_div_2 and bound_angle >= -pi_div_2 and y < std.math.maxInt(u32)) {
        idx_new = drawSide(idx_new, x, y + 1, atlas_data, draw_data, color, 0.25, alpha, x1, top_y1, x2, top_y2, x2, y2, x1, y1);
    }

    if (bound_angle >= 0 and bound_angle <= std.math.pi and x > 0) {
        idx_new = drawSide(idx_new, x - 1, y, atlas_data, draw_data, color, 0.25, alpha, x3, top_y3, x2, top_y2, x2, y2, x3, y3);
    }

    if (bound_angle <= 0 and bound_angle >= -std.math.pi and x < std.math.maxInt(u32)) {
        idx_new = drawSide(idx_new, x + 1, y, atlas_data, draw_data, color, 0.25, alpha, x4, top_y4, x1, top_y1, x1, y1, x4, y4);
    }

    return drawSide(idx_new, -1.0, -1.0, top_atlas_data, draw_data, color, 0.1, alpha, x1, top_y1, x2, top_y2, x3, top_y3, x4, top_y4);
}

inline fn drawParticle(idx: u16, pt: Particle, draw_data: base.DrawData) u16 {
    var new_idx = idx;

    switch (pt) {
        inline else => |particle| {
            if (!camera.visibleInCamera(particle.x, particle.y))
                return new_idx;

            const w = particle.atlas_data.texWRaw() * particle.size;
            const h = particle.atlas_data.texHRaw() * particle.size;
            const screen_pos = camera.rotateAroundCamera(particle.x, particle.y);
            const z_off = particle.z * -camera.px_per_tile - (h - particle.size * assets.padding);

            new_idx = base.drawQuad(
                new_idx,
                screen_pos.x - w / 2.0,
                screen_pos.y + z_off,
                w,
                h,
                particle.atlas_data,
                draw_data,
                .{
                    .alpha_mult = particle.alpha_mult,
                    .base_color = particle.color,
                    .base_color_intensity = 1.0,
                },
            );
        },
    }

    return new_idx;
}

inline fn drawConditions(idx: u16, draw_data: base.DrawData, cond_int: @typeInfo(utils.Condition).Struct.backing_integer.?, float_time_ms: f32, x: f32, y: f32) u16 {
    var new_idx = idx;

    var cond_len: f32 = 0.0;
    for (0..@bitSizeOf(utils.Condition)) |i| {
        if (cond_int & (@as(usize, 1) << @intCast(i)) != 0)
            cond_len += if (base.condition_rects[i].len > 0) 1.0 else 0.0;
    }

    var cond_new_idx: f32 = 0.0;
    for (0..@bitSizeOf(utils.Condition)) |i| {
        if (cond_int & (@as(usize, 1) << @intCast(i)) != 0) {
            const data = base.condition_rects[i];
            if (data.len > 0) {
                const frame_new_idx: usize = @intFromFloat(float_time_ms / (0.5 * std.time.us_per_s));
                const current_frame = data[@mod(frame_new_idx, data.len)];
                const cond_w = current_frame.texWRaw() * 2;
                const cond_h = current_frame.texHRaw() * 2;

                new_idx = base.drawQuad(
                    new_idx,
                    x - cond_len * (cond_w + 2) / 2 + cond_new_idx * (cond_w + 2),
                    y,
                    cond_w,
                    cond_h,
                    current_frame,
                    draw_data,
                    .{},
                );
                cond_new_idx += 1.0;
            }
        }
    }

    return idx;
}

inline fn drawPlayer(idx: u16, player: *Player, draw_data: base.DrawData, float_time_ms: f32) u16 {
    var new_idx = idx;

    if (ui_systems.screen == .editor or player.dead or !camera.visibleInCamera(player.x, player.y))
        return new_idx;

    const size = camera.size_mult * camera.scale * player.size;

    var atlas_data = player.atlas_data;
    const x_offset = player.renderx_offset;

    var sink: f32 = 1.0;
    if (map.getSquare(player.x, player.y)) |square| {
        const protect = blk: {
            const entity = map.findEntityConst(square.static_obj_id) orelse break :blk false;
            break :blk entity == .object and entity.object.props.protect_from_sink;
        };
        sink += if (square.props.sink and !protect) 0.75 else 0;
    }

    atlas_data.tex_h /= sink;

    const w = atlas_data.texWRaw() * size;
    const h = atlas_data.texHRaw() * size;

    var screen_pos = camera.rotateAroundCamera(player.x, player.y);
    screen_pos.x += x_offset;
    screen_pos.y += player.z * -camera.px_per_tile - (h - size * assets.padding);

    var alpha_mult: f32 = player.alpha;
    if (player.condition.invisible)
        alpha_mult = 0.6;

    var color: u32 = 0;
    var color_intensity: f32 = 0.0;
    _ = &color;
    _ = &color_intensity;
    // flash

    if (settings.enable_lights and
        base.light_idx < base.max_lights and
        player.props.light_color != std.math.maxInt(u32))
    {
        const light_size = player.props.light_radius + player.props.light_pulse *
            @sin(float_time_ms / 1000.0 * player.props.light_pulse_speed);

        const light_w = w * light_size * 4;
        const light_h = h * light_size * 4;
        base.lights[base.light_idx] = .{
            .x = screen_pos.x - light_w / 2.0,
            .y = screen_pos.y - h * light_size * 1.5,
            .w = light_w,
            .h = light_h,
            .color = player.props.light_color,
            .intensity = player.props.light_intensity,
        };
        base.light_idx += 1;
    }

    if (player.name_text_data) |*data| {
        new_idx = base.drawText(
            new_idx,
            screen_pos.x - x_offset - data.width / 2,
            screen_pos.y - data.height - 5,
            data,
            draw_data,
            .{},
        );
    }

    new_idx = base.drawQuad(
        new_idx,
        screen_pos.x - w / 2.0,
        screen_pos.y,
        w,
        h,
        atlas_data,
        draw_data,
        .{ .alpha_mult = alpha_mult, .base_color = color, .base_color_intensity = color_intensity },
    );

    // todo make sink calculate actual values based on h, pad, etc
    var y_pos: f32 = 5.0 + if (sink != 1.0) @as(f32, 15.0) else @as(f32, 0.0);

    const pad_scale_obj = assets.padding * size * camera.scale;
    const pad_scale_bar = assets.padding * 2 * camera.scale;
    if (player.hp >= 0 and player.hp < player.max_hp) {
        const hp_bar_w = assets.hp_bar_data.texWRaw() * 2 * camera.scale;
        const hp_bar_h = assets.hp_bar_data.texHRaw() * 2 * camera.scale;
        const hp_bar_y = screen_pos.y + h - pad_scale_obj + y_pos;

        new_idx = base.drawQuad(
            new_idx,
            screen_pos.x - x_offset - hp_bar_w / 2.0,
            hp_bar_y,
            hp_bar_w,
            hp_bar_h,
            assets.empty_bar_data,
            draw_data,
            .{},
        );

        const float_hp: f32 = @floatFromInt(player.hp);
        const float_max_hp: f32 = @floatFromInt(player.max_hp);
        const left_pad = 2.0;
        const w_no_pad = 20.0;
        const total_w = 24.0;
        const hp_perc = (left_pad / total_w) + (w_no_pad / total_w) * (float_hp / float_max_hp);

        var hp_bar_data = assets.hp_bar_data;
        hp_bar_data.tex_w *= hp_perc;

        new_idx = base.drawQuad(
            new_idx,
            screen_pos.x - x_offset - hp_bar_w / 2.0,
            hp_bar_y,
            hp_bar_w * hp_perc,
            hp_bar_h,
            hp_bar_data,
            draw_data,
            .{},
        );

        y_pos += hp_bar_h - pad_scale_bar;
    }

    if (player.mp >= 0 and player.mp < player.max_mp) {
        const mp_bar_w = assets.mp_bar_data.texWRaw() * 2 * camera.scale;
        const mp_bar_h = assets.mp_bar_data.texHRaw() * 2 * camera.scale;
        const mp_bar_y = screen_pos.y + h - pad_scale_obj + y_pos;

        new_idx = base.drawQuad(
            new_idx,
            screen_pos.x - x_offset - mp_bar_w / 2.0,
            mp_bar_y,
            mp_bar_w,
            mp_bar_h,
            assets.empty_bar_data,
            draw_data,
            .{},
        );

        const float_mp: f32 = @floatFromInt(player.mp);
        const float_max_mp: f32 = @floatFromInt(player.max_mp);
        const left_pad = 2.0;
        const w_no_pad = 20.0;
        const total_w = 24.0;
        const mp_perc = (left_pad / total_w) + (w_no_pad / total_w) * (float_mp / float_max_mp);

        var mp_bar_data = assets.mp_bar_data;
        mp_bar_data.tex_w *= mp_perc;

        new_idx = base.drawQuad(
            new_idx,
            screen_pos.x - x_offset - mp_bar_w / 2.0,
            mp_bar_y,
            mp_bar_w * mp_perc,
            mp_bar_h,
            mp_bar_data,
            draw_data,
            .{},
        );

        y_pos += mp_bar_h - pad_scale_bar;
    }

    const cond_int: @typeInfo(utils.Condition).Struct.backing_integer.? = @bitCast(player.condition);
    if (cond_int > 0) {
        new_idx = drawConditions(new_idx, draw_data, cond_int, float_time_ms, screen_pos.x - x_offset, screen_pos.y + h - pad_scale_obj + y_pos);
        y_pos += 20;
    }

    return new_idx;
}

inline fn drawGameObject(idx: u16, obj: *GameObject, draw_data: base.DrawData, float_time_ms: f32) u16 {
    var new_idx = idx;

    if (obj.dead or !camera.visibleInCamera(obj.x, obj.y))
        return new_idx;

    var screen_pos = camera.rotateAroundCamera(obj.x, obj.y);
    const size = camera.size_mult * camera.scale * obj.size;

    if (obj.props.draw_on_ground) {
        const tile_size = @as(f32, camera.px_per_tile) * camera.scale;
        const w = tile_size * (obj.atlas_data.texWRaw() / 8);
        const h = tile_size * (obj.atlas_data.texHRaw() / 8);
        const h_half = h / 2.0;

        new_idx = base.drawQuad(
            new_idx,
            screen_pos.x - w / 2.0,
            screen_pos.y - h_half,
            w,
            h,
            obj.atlas_data,
            draw_data,
            .{ .rotation = camera.angle, .alpha_mult = obj.alpha },
        );

        const is_portal = obj.class == .portal;
        if (obj.props.show_name or is_portal) {
            if (obj.name_text_data) |*data| {
                new_idx = base.drawText(
                    new_idx,
                    screen_pos.x - data.width / 2,
                    screen_pos.y - h_half - data.height - 5,
                    data,
                    draw_data,
                    .{},
                );
            }

            if (is_portal and map.interactive_id.load(.Acquire) == obj.obj_id) {
                const button_w = 100 / 5;
                const button_h = 100 / 5;
                const total_w = base.enter_text_data.width + button_w;

                new_idx = base.drawQuad(
                    new_idx,
                    screen_pos.x - total_w / 2,
                    screen_pos.y + h_half + 5,
                    button_w,
                    button_h,
                    settings.interact_key_tex,
                    draw_data,
                    .{},
                );

                new_idx = base.drawText(
                    new_idx,
                    screen_pos.x - total_w / 2 + button_w,
                    screen_pos.y + h_half + 5,
                    &base.enter_text_data,
                    draw_data,
                    .{},
                );
            }
        }

        return new_idx;
    }

    if (obj.class == .wall) {
        new_idx = drawWall(new_idx, obj.x, obj.y, obj.alpha, obj.atlas_data, obj.top_atlas_data, draw_data);
        return new_idx;
    }

    var atlas_data = obj.atlas_data;
    const x_offset = obj.renderx_offset;

    var sink: f32 = 1.0;
    if (map.getSquare(obj.x, obj.y)) |square| {
        const protect = blk: {
            const entity = map.findEntityConst(square.static_obj_id) orelse break :blk false;
            break :blk entity == .object and entity.object.props.protect_from_sink;
        };
        sink += if (square.props.sink and !protect) 0.75 else 0;
    }

    atlas_data.tex_h /= sink;

    const w = atlas_data.texWRaw() * size;
    const h = atlas_data.texHRaw() * size;

    screen_pos.x += x_offset;
    screen_pos.y += obj.z * -camera.px_per_tile - (h - size * assets.padding);

    var alpha_mult: f32 = obj.alpha;
    if (obj.condition.invisible)
        alpha_mult = 0.6;

    var color: u32 = 0;
    var color_intensity: f32 = 0.0;
    _ = &color;
    _ = &color_intensity;
    // flash

    if (settings.enable_lights and
        base.light_idx < base.max_lights and
        obj.props.light_color != std.math.maxInt(u32))
    {
        const light_size = obj.props.light_radius + obj.props.light_pulse * @sin(float_time_ms / 1000.0 * obj.props.light_pulse_speed);
        const light_w = w * light_size * 4;
        const light_h = h * light_size * 4;
        base.lights[base.light_idx] = .{
            .x = screen_pos.x - light_w / 2.0,
            .y = screen_pos.y - h * light_size * 1.5,
            .w = light_w,
            .h = light_h,
            .color = obj.props.light_color,
            .intensity = obj.props.light_intensity,
        };
        base.light_idx += 1;
    }

    const is_portal = obj.class == .portal;
    if (obj.props.show_name or is_portal) {
        if (obj.name_text_data) |*data| {
            new_idx = base.drawText(
                new_idx,
                screen_pos.x - x_offset - data.width / 2,
                screen_pos.y - data.height - 5,
                data,
                draw_data,
                .{},
            );
        }

        if (is_portal and map.interactive_id.load(.Acquire) == obj.obj_id) {
            const button_w = 100 / 5;
            const button_h = 100 / 5;
            const total_w = base.enter_text_data.width + button_w;

            new_idx = base.drawQuad(
                new_idx,
                screen_pos.x - x_offset - total_w / 2,
                screen_pos.y + h + 5,
                button_w,
                button_h,
                settings.interact_key_tex,
                draw_data,
                .{},
            );

            new_idx = base.drawText(
                new_idx,
                screen_pos.x - x_offset - total_w / 2 + button_w,
                screen_pos.y + h + 5,
                &base.enter_text_data,
                draw_data,
                .{},
            );
        }
    }

    new_idx = base.drawQuad(
        new_idx,
        screen_pos.x - w / 2.0,
        screen_pos.y,
        w,
        h,
        atlas_data,
        draw_data,
        .{ .alpha_mult = alpha_mult, .base_color = color, .base_color_intensity = color_intensity },
    );

    if (!obj.props.is_enemy)
        return new_idx;

    var y_pos: f32 = 5.0 + if (sink != 1.0) @as(f32, 15.0) else @as(f32, 0.0);

    const pad_scale_obj = assets.padding * size * camera.scale;
    const pad_scale_bar = assets.padding * 2 * camera.scale;
    if (obj.hp >= 0 and obj.hp < obj.max_hp) {
        const hp_bar_w = assets.hp_bar_data.texWRaw() * 2 * camera.scale;
        const hp_bar_h = assets.hp_bar_data.texHRaw() * 2 * camera.scale;
        const hp_bar_y = screen_pos.y + h - pad_scale_obj + y_pos;

        new_idx = base.drawQuad(
            new_idx,
            screen_pos.x - x_offset - hp_bar_w / 2.0,
            hp_bar_y,
            hp_bar_w,
            hp_bar_h,
            assets.empty_bar_data,
            draw_data,
            .{},
        );

        const float_hp: f32 = @floatFromInt(obj.hp);
        const float_max_hp: f32 = @floatFromInt(obj.max_hp);
        const hp_perc = 1.0 / (float_hp / float_max_hp);
        var hp_bar_data = assets.hp_bar_data;
        hp_bar_data.tex_w /= hp_perc;

        new_idx = base.drawQuad(
            new_idx,
            screen_pos.x - x_offset - hp_bar_w / 2.0,
            hp_bar_y,
            hp_bar_w / hp_perc,
            hp_bar_h,
            hp_bar_data,
            draw_data,
            .{},
        );

        y_pos += hp_bar_h - pad_scale_bar;
    }

    const cond_int: @typeInfo(utils.Condition).Struct.backing_integer.? = @bitCast(obj.condition);
    if (cond_int > 0) {
        new_idx = drawConditions(new_idx, draw_data, cond_int, float_time_ms, screen_pos.x - x_offset, screen_pos.y + h - pad_scale_obj + y_pos);
        y_pos += 20;
    }

    return new_idx;
}

inline fn drawProjectile(idx: u16, proj: Projectile, draw_data: base.DrawData, float_time_ms: f32) u16 {
    var new_idx = idx;

    if (!camera.visibleInCamera(proj.x, proj.y))
        return new_idx;

    const size = camera.size_mult * camera.scale * proj.props.size;
    const w = proj.atlas_data.texWRaw() * size;
    const h = proj.atlas_data.texHRaw() * size;
    const screen_pos = camera.rotateAroundCamera(proj.x, proj.y);
    const z_offset = proj.z * -camera.px_per_tile - h - size * assets.padding;
    const rotation = proj.props.rotation;
    const angle = -(proj.visual_angle + proj.props.angle_correction +
        (if (rotation == 0) 0 else float_time_ms / rotation) - camera.angle);

    if (settings.enable_lights and
        base.light_idx < base.max_lights and
        proj.props.light_color != std.math.maxInt(u32))
    {
        const light_size = proj.props.light_radius + proj.props.light_pulse * @sin(float_time_ms / 1000.0 * proj.props.light_pulse_speed);
        const light_w = w * light_size * 4;
        const light_h = h * light_size * 4;
        base.lights[base.light_idx] = .{
            .x = screen_pos.x - light_w / 2.0,
            .y = screen_pos.y + z_offset - h * light_size * 1.5,
            .w = light_w,
            .h = light_h,
            .color = proj.props.light_color,
            .intensity = proj.props.light_intensity,
        };
        base.light_idx += 1;
    }

    new_idx = base.drawQuad(
        new_idx,
        screen_pos.x - w / 2.0,
        screen_pos.y + z_offset,
        w,
        h,
        proj.atlas_data,
        draw_data,
        .{ .rotation = angle },
    );

    return new_idx;
}

pub inline fn drawEntities(
    idx: u16,
    draw_data: base.DrawData,
    float_time_ms: f32,
) u16 {
    var new_idx = idx;

    for (map.entities.items) |*en| {
        switch (en.*) {
            .particle_effect => {},
            .particle => |pt| new_idx = drawParticle(new_idx, pt, draw_data),
            .player => |*player| new_idx = drawPlayer(new_idx, player, draw_data, float_time_ms),
            .object => |*obj| new_idx = drawGameObject(new_idx, obj, draw_data, float_time_ms),
            .projectile => |proj| new_idx = drawProjectile(new_idx, proj, draw_data, float_time_ms),
        }
    }

    return new_idx;
}
