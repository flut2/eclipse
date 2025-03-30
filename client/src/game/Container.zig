const std = @import("std");

const shared = @import("shared");
const utils = shared.utils;
const game_data = shared.game_data;
const network_data = shared.network_data;
const f32i = utils.f32i;

const assets = @import("../assets.zig");
const Camera = @import("../Camera.zig");
const px_per_tile = Camera.px_per_tile;
const main = @import("../main.zig");
const Renderer = @import("../render/Renderer.zig");
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
playing_anim: union(enum) {
    none: void,
    repeat: u8,
    single: u8,
} = .{ .none = {} },
anim_idx: u8 = 0,
next_anim: i64 = -1,
sort_random: u16 = 0xAAAA,

pub fn addToMap(container_data: Container) void {
    base.addToMap(container_data, Container);
}

pub fn deinit(self: *Container) void {
    base.deinit(self);
}

pub fn draw(
    self: *Container,
    generics: *std.ArrayListUnmanaged(Renderer.GenericData),
    sort_extras: *std.ArrayListUnmanaged(f32),
    lights: *std.ArrayListUnmanaged(Renderer.LightData),
    sort_randoms: *std.ArrayListUnmanaged(u16),
    float_time_ms: f32,
) void {
    if (ui_systems.screen == .editor and !ui_systems.screen.editor.show_container_layer or
        !main.camera.visibleInCamera(self.x, self.y)) return;

    var screen_pos = main.camera.worldToScreen(self.x, self.y);
    const size = Camera.size_mult * main.camera.scale * self.size_mult;

    var atlas_data = self.atlas_data;

    var sink: f32 = 1.0;
    if (map.getSquareCon(self.x, self.y, true)) |square| {
        if (game_data.ground.from_id.get(square.data_id)) |data| sink += if (data.sink) 0.75 else 0;
    }
    atlas_data.tex_h /= sink;

    const w = atlas_data.texWRaw() * size;
    const h = atlas_data.texHRaw() * size;

    screen_pos.y += self.z * -px_per_tile - h + assets.padding * size;
    if (self.data.float.time > 0) {
        const time_us = self.data.float.time * std.time.us_per_s;
        screen_pos.y -= self.data.float.height / 2.0 * (@sin(f32i(main.current_time) / time_us) + 1) * px_per_tile * main.camera.scale;
    }

    const alpha_mult: f32 = self.alpha;
    var color: u32 = 0;
    var color_intensity: f32 = 0.0;
    _ = &color;
    _ = &color_intensity;
    // flash

    if (main.settings.enable_lights)
        Renderer.drawLight(
            lights,
            self.data.light,
            screen_pos.x - w / 2.0,
            screen_pos.y,
            w,
            h,
            main.camera.scale,
            float_time_ms,
        );

    if (self.data.show_name) if (self.name_text_data) |*data| {
        const name_h = (data.height + 5) * main.camera.scale;
        const name_y = screen_pos.y - name_h;
        data.sort_extra = (screen_pos.y - name_y) + (h - name_h);
        Renderer.drawText(
            generics,
            sort_extras,
            screen_pos.x - data.width * main.camera.scale / 2,
            name_y,
            main.camera.scale,
            data,
            .{},
        );
        for (0..data.text.len) |_| sort_randoms.append(main.allocator, self.sort_random) catch main.oomPanic();
    };

    Renderer.drawQuad(
        generics,
        sort_extras,
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
    sort_randoms.append(main.allocator, self.sort_random) catch main.oomPanic();
}

pub fn update(self: *Container, time: i64) void {
    base.update(self, Container, time);
}
