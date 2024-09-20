const std = @import("std");
const element = @import("../ui/element.zig");
const shared = @import("shared");
const utils = shared.utils;
const game_data = shared.game_data;
const assets = @import("../assets.zig");
const particles = @import("particles.zig");
const map = @import("map.zig");
const main = @import("../main.zig");
const base = @import("object_base.zig");
const render = @import("../render.zig");
const Camera = @import("../Camera.zig");
const px_per_tile = Camera.px_per_tile;
const size_mult = Camera.size_mult;

pub const Portal = struct {
    map_id: u32 = std.math.maxInt(u32),
    data_id: u16 = std.math.maxInt(u16),
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,
    alpha: f32 = 1.0,
    name: ?[]const u8 = null,
    name_text_data: ?element.TextData = null,
    size_mult: f32 = 1.0,
    atlas_data: assets.AtlasData = .default,
    data: *const game_data.PortalData = undefined,
    anim_idx: u8 = 0,
    next_anim: i64 = -1,

    pub fn addToMap(self: *Portal, allocator: std.mem.Allocator) void {
        base.addToMap(self, Portal, allocator);
    }

    pub fn deinit(self: *Portal, allocator: std.mem.Allocator) void {
        base.deinit(self, Portal, allocator);
    }

    pub fn draw(self: *Portal, cam_data: render.CameraData, float_time_ms: f32, allocator: std.mem.Allocator, int_id: u32) void {
        if (!cam_data.visibleInCamera(self.x, self.y)) return;

        var screen_pos = cam_data.worldToScreen(self.x, self.y);
        const size = size_mult * cam_data.scale * self.size_mult;

        if (self.data.draw_on_ground) {
            const tile_size = @as(f32, px_per_tile) * cam_data.scale;
            const h_half = tile_size / 2.0;

            render.drawQuad(
                screen_pos.x - tile_size / 2.0,
                screen_pos.y - h_half,
                tile_size,
                tile_size,
                self.atlas_data,
                .{ .rotation = cam_data.angle, .alpha_mult = self.alpha, .sort_extra = -4096 },
            );

            if (self.name_text_data) |*data| render.drawText(
                screen_pos.x - data.width * cam_data.scale / 2,
                screen_pos.y - h_half - data.height * cam_data.scale - 5,
                cam_data.scale,
                data,
                .{},
            );

            if (int_id == self.map_id) {
                const button_w = 100 / 5;
                const button_h = 100 / 5;
                const total_w = render.enter_text_data.width * cam_data.scale + button_w;

                render.drawQuad(
                    screen_pos.x - total_w / 2,
                    screen_pos.y + h_half + 5,
                    button_w,
                    button_h,
                    assets.interact_key_tex,
                    .{},
                );

                render.drawText(
                    screen_pos.x - total_w / 2 + button_w,
                    screen_pos.y + h_half + 5,
                    cam_data.scale,
                    &render.enter_text_data,
                    .{},
                );
            }

            return;
        }

        var atlas_data = self.atlas_data;

        var sink: f32 = 1.0;
        if (map.getSquare(self.x, self.y, true)) |square| sink += if (square.data.sink) 0.75 else 0;
        atlas_data.tex_h /= sink;

        const w = atlas_data.texWRaw() * size;
        const h = atlas_data.texHRaw() * size;

        screen_pos.y += self.z * -px_per_tile - h + assets.padding * size;

        const alpha_mult: f32 = self.alpha;
        var color: u32 = 0;
        var color_intensity: f32 = 0.0;
        _ = &color;
        _ = &color_intensity;
        // flash

        if (main.settings.enable_lights and self.data.light.color != std.math.maxInt(u32)) {
            const light_size = self.data.light.radius + self.data.light.pulse * @sin(float_time_ms / 1000.0 * self.data.light.pulse_speed);
            const light_w = w * light_size * 4;
            const light_h = h * light_size * 4;
            render.lights.append(allocator, .{
                .x = screen_pos.x - light_w / 2.0,
                .y = screen_pos.y - h * light_size * 1.5,
                .w = light_w,
                .h = light_h,
                .color = self.data.light.color,
                .intensity = self.data.light.intensity,
            }) catch unreachable;
        }

        if (self.name_text_data) |*data| render.drawText(
            screen_pos.x - data.width * cam_data.scale / 2,
            screen_pos.y - data.height * cam_data.scale - 5,
            cam_data.scale,
            data,
            .{},
        );

        if (int_id == self.map_id) {
            const button_w = 100 / 5;
            const button_h = 100 / 5;
            const total_w = render.enter_text_data.width * cam_data.scale + button_w;

            render.drawQuad(
                screen_pos.x - total_w / 2,
                screen_pos.y + h + 5,
                button_w,
                button_h,
                assets.interact_key_tex,
                .{},
            );

            render.drawText(
                screen_pos.x - total_w / 2 + button_w,
                screen_pos.y + h + 5,
                cam_data.scale,
                &render.enter_text_data,
                .{},
            );
        }

        render.drawQuad(
            screen_pos.x - w / 2.0,
            screen_pos.y,
            w,
            h,
            atlas_data,
            .{
                .shadow_texel_mult = 2.0 / size,
                .alpha_mult = alpha_mult,
                .color = color,
                .color_intensity = color_intensity,
            },
        );
    }

    pub fn update(self: *Portal, time: i64) void {
        base.update(self, Portal, time);
    }
};
