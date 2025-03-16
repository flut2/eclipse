const std = @import("std");

const shared = @import("shared");
const utils = shared.utils;
const game_data = shared.game_data;
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

const Portal = @This();

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
playing_anim: union(enum) {
    none: void,
    repeat: u8,
    single: u8,
} = .{ .none = {} },
anim_idx: u8 = 0,
next_anim: i64 = -1,
sort_random: u16 = 0xAAAA,

pub fn addToMap(portal_data: Portal) void {
    base.addToMap(portal_data, Portal);
}

pub fn deinit(self: *Portal) void {
    base.deinit(self);
}

pub fn draw(
    self: *Portal,
    renderer: *Renderer,
    generics: *std.ArrayListUnmanaged(Renderer.GenericData),
    sort_extras: *std.ArrayListUnmanaged(f32),
    lights: *std.ArrayListUnmanaged(Renderer.LightData),
    sort_randoms: *std.ArrayListUnmanaged(u16),
    float_time_ms: f32,
    int_id: u32,
) void {
    if (ui_systems.screen == .editor and !ui_systems.screen.editor.show_portal_layer or
        !main.camera.visibleInCamera(self.x, self.y)) return;

    var screen_pos = main.camera.worldToScreen(self.x, self.y);
    const size = Camera.size_mult * main.camera.scale * self.size_mult;

    if (self.data.draw_on_ground) {
        const tile_size = @as(f32, px_per_tile) * main.camera.scale;
        const h_half = tile_size / 2.0;

        Renderer.drawQuad(
            generics,
            sort_extras,
            screen_pos.x - tile_size / 2.0,
            screen_pos.y - h_half,
            tile_size,
            tile_size,
            self.atlas_data,
            .{ .alpha_mult = self.alpha, .sort_extra = -4096 },
        );
        sort_randoms.append(main.allocator, self.sort_random) catch main.oomPanic();

        if (self.name_text_data) |*data| {
            const name_h = h_half + (data.height + 5) * main.camera.scale;
            const name_y = screen_pos.y - name_h;
            data.sort_extra = (screen_pos.y - name_y) + (h_half - name_h);
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
        }

        if (main.settings.enable_lights)
            Renderer.drawLight(
                lights,
                self.data.light,
                screen_pos.x - tile_size / 2.0,
                screen_pos.y - h_half,
                tile_size,
                tile_size,
                main.camera.scale,
                float_time_ms,
            );

        if (int_id == self.map_id) {
            const button_w = 100.0 / 5.0 * main.camera.scale;
            const button_h = 100.0 / 5.0 * main.camera.scale;
            const total_w = renderer.enter_text_data.width * main.camera.scale + button_w;

            const enter_y = screen_pos.y + h_half + 5;
            Renderer.drawQuad(
                generics,
                sort_extras,
                screen_pos.x - total_w / 2,
                enter_y,
                button_w,
                button_h,
                assets.interact_key_tex,
                .{ .sort_extra = (screen_pos.y - enter_y) + (h_half - button_h) },
            );
            sort_randoms.append(main.allocator, self.sort_random) catch main.oomPanic();

            renderer.enter_text_data.sort_extra = (screen_pos.y - enter_y) + (h_half - renderer.enter_text_data.height);
            Renderer.drawText(
                generics,
                sort_extras,
                screen_pos.x - total_w / 2 + button_w + 5,
                enter_y,
                main.camera.scale,
                &renderer.enter_text_data,
                .{},
            );
            for (0..renderer.enter_text_data.text.len) |_| sort_randoms.append(main.allocator, self.sort_random) catch main.oomPanic();
        }

        return;
    }

    var atlas_data = self.atlas_data;

    var sink: f32 = 1.0;
    if (map.getSquare(self.x, self.y, true, .con)) |square| {
        if (game_data.ground.from_id.get(square.data_id)) |data| sink += if (data.sink) 0.75 else 0;
    }
    atlas_data.tex_h /= sink;

    const w = atlas_data.texWRaw() * size;
    const h = atlas_data.texHRaw() * size;

    screen_pos.y += self.z * -px_per_tile - h + assets.padding * size;
    if (self.data.float.time > 0) {
        const time_us = self.data.float.time * std.time.us_per_s;
        screen_pos.y -= self.data.float.height / 2.0 * (@sin(f32i(main.current_time) / time_us) + 1) * px_per_tile;
    }
        
    const alpha_mult: f32 = self.alpha;
    var color: u32 = 0;
    var color_intensity: f32 = 0.0;
    _ = &color;
    _ = &color_intensity;
    // flash

    if (self.name_text_data) |*data| {
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
    }

    if (int_id == self.map_id) {
        const button_w = 100.0 / 5.0 * main.camera.scale;
        const button_h = 100.0 / 5.0 * main.camera.scale;
        const total_w = renderer.enter_text_data.width * main.camera.scale + button_w;

        const enter_y = screen_pos.y + h + 5;
        Renderer.drawQuad(
            generics,
            sort_extras,
            screen_pos.x - total_w / 2,
            enter_y,
            button_w,
            button_h,
            assets.interact_key_tex,
            .{ .sort_extra = (screen_pos.y - enter_y) + (h - button_h) },
        );
        sort_randoms.append(main.allocator, self.sort_random) catch main.oomPanic();

        renderer.enter_text_data.sort_extra = (screen_pos.y - enter_y) + (h - renderer.enter_text_data.height);
        Renderer.drawText(
            generics,
            sort_extras,
            screen_pos.x - total_w / 2 + button_w + 5,
            enter_y,
            main.camera.scale,
            &renderer.enter_text_data,
            .{},
        );
        for (0..renderer.enter_text_data.text.len) |_| sort_randoms.append(main.allocator, self.sort_random) catch main.oomPanic();
    }

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

    if (main.settings.enable_lights)
        Renderer.drawLight(lights, self.data.light, screen_pos.x - w / 2.0, screen_pos.y, w, h, main.camera.scale, float_time_ms);
}

pub fn update(self: *Portal, time: i64) void {
    base.update(self, Portal, time);
}
