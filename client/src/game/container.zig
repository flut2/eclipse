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

pub const Container = struct {
    map_id: u32 = std.math.maxInt(u32),
    data_id: u16 = std.math.maxInt(u16),
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,
    alpha: f32 = 1.0,
    name: ?[]const u8 = null,
    name_text_data: ?element.TextData = null,
    size_mult: f32 = 0,
    atlas_data: assets.AtlasData = .default,
    data: *const game_data.ContainerData = undefined,
    inventory: [9]u16 = [_]u16{std.math.maxInt(u16)} ** 9,
    anim_idx: u8 = 0,
    next_anim: i64 = -1,

    pub fn addToMap(self: *Container, allocator: std.mem.Allocator) void {
        base.addToMap(self, Container, allocator);
    }

    pub fn deinit(self: *Container, allocator: std.mem.Allocator) void {
        base.deinit(self, allocator);
    }

    pub fn draw(self: *Container, cam_data: render.CameraData, float_time_ms: f32, allocator: std.mem.Allocator) void {
        if (!cam_data.visibleInCamera(self.x, self.y)) return;

        var screen_pos = cam_data.worldToScreen(self.x, self.y);
        const size = size_mult * cam_data.scale * self.size_mult;

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

        if (main.settings.enable_lights) {
            const tile_pos = cam_data.worldToScreen(self.x, self.y);
            render.drawLight(allocator, self.data.light, tile_pos.x, tile_pos.y, cam_data.scale, float_time_ms);
        }

        if (self.data.show_name) {
            if (self.name_text_data) |*data| render.drawText(
                screen_pos.x - data.width * cam_data.scale / 2,
                screen_pos.y - data.height * cam_data.scale - 5,
                cam_data.scale,
                data,
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

    pub fn update(self: *Container, time: i64) void {
        base.update(self, Container, time);
    }
};
