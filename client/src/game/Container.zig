const std = @import("std");

const shared = @import("shared");
const utils = shared.utils;
const game_data = shared.game_data;
const network_data = shared.network_data;

const assets = @import("../assets.zig");
const Camera = @import("../Camera.zig");
const px_per_tile = Camera.px_per_tile;
const main = @import("../main.zig");
const CameraData = @import("../render/CameraData.zig");
const element = @import("../ui/elements/element.zig");
const ui_systems = @import("../ui/systems.zig");
const base = @import("object_base.zig");
const map = @import("map.zig");
const particles = @import("particles.zig");

const Container = @This();

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
inventory: [9]u16 = @splat(std.math.maxInt(u16)),
inv_data: [9]network_data.ItemData = @splat(@bitCast(@as(u32, 0))),
anim_idx: u8 = 0,
next_anim: i64 = -1,

pub fn addToMap(container_data: Container) void {
    base.addToMap(container_data, Container);
}

pub fn deinit(self: *Container) void {
    base.deinit(self);
}

pub fn draw(self: *Container, cam_data: CameraData, float_time_ms: f32) void {
    if (ui_systems.screen == .editor and !ui_systems.screen.editor.show_container_layer or
        !cam_data.visibleInCamera(self.x, self.y)) return;

    var screen_pos = cam_data.worldToScreen(self.x, self.y);
    const size = Camera.size_mult * cam_data.scale * self.size_mult;

    var atlas_data = self.atlas_data;

    var sink: f32 = 1.0;
    if (map.getSquare(self.x, self.y, true, .con)) |square| {
        if (game_data.ground.from_id.get(square.data_id)) |data| sink += if (data.sink) 0.75 else 0;
    }
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
        main.renderer.drawLight(self.data.light, tile_pos.x, tile_pos.y, cam_data.scale, float_time_ms);
    }

    if (self.data.show_name) if (self.name_text_data) |*data| {
        const name_h = (data.height + 5) * cam_data.scale;
        const name_y = screen_pos.y - name_h;
        data.sort_extra = (screen_pos.y - name_y) + (h - name_h);
        main.renderer.drawText(
            screen_pos.x - data.width * cam_data.scale / 2,
            name_y,
            cam_data.scale,
            data,
            .{},
        );
    };

    main.renderer.drawQuad(
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
