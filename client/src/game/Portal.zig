const std = @import("std");

const shared = @import("shared");
const utils = shared.utils;
const game_data = shared.game_data;

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
anim_idx: u8 = 0,
next_anim: i64 = -1,

pub fn addToMap(portal_data: Portal) void {
    base.addToMap(portal_data, Portal);
}

pub fn deinit(self: *Portal) void {
    base.deinit(self);
}

pub fn draw(self: *Portal, cam_data: CameraData, float_time_ms: f32, int_id: u32) void {
    if (ui_systems.screen == .editor and !ui_systems.screen.editor.show_portal_layer or
        !cam_data.visibleInCamera(self.x, self.y)) return;

    var screen_pos = cam_data.worldToScreen(self.x, self.y);
    const size = Camera.size_mult * cam_data.scale * self.size_mult;

    if (main.settings.enable_lights) {
        const tile_pos = cam_data.worldToScreen(self.x, self.y);
        main.renderer.drawLight(self.data.light, tile_pos.x, tile_pos.y, cam_data.scale, float_time_ms);
    }

    if (self.data.draw_on_ground) {
        const tile_size = @as(f32, px_per_tile) * cam_data.scale;
        const h_half = tile_size / 2.0;

        main.renderer.drawQuad(
            screen_pos.x - tile_size / 2.0,
            screen_pos.y - h_half,
            tile_size * cam_data.scale,
            tile_size * cam_data.scale,
            self.atlas_data,
            .{ .alpha_mult = self.alpha, .sort_extra = -4096 },
        );

        if (self.name_text_data) |*data| {
            const name_h = h_half + (data.height + 5) * cam_data.scale;
            const name_y = screen_pos.y - name_h;
            data.sort_extra = (screen_pos.y - name_y) + (h_half - name_h);
            main.renderer.drawText(
                screen_pos.x - data.width * cam_data.scale / 2,
                name_y,
                cam_data.scale,
                data,
                .{},
            );
        }

        if (int_id == self.map_id) {
            const button_w = 100.0 / 5.0 * cam_data.scale;
            const button_h = 100.0 / 5.0 * cam_data.scale;
            const total_w = main.renderer.enter_text_data.width * cam_data.scale + button_w;

            const enter_y = screen_pos.y + h_half + 5;
            main.renderer.drawQuad(
                screen_pos.x - total_w / 2,
                enter_y,
                button_w,
                button_h,
                assets.interact_key_tex,
                .{ .sort_extra = (screen_pos.y - enter_y) + (h_half - button_h) },
            );

            main.renderer.enter_text_data.sort_extra = (screen_pos.y - enter_y) + (h_half - main.renderer.enter_text_data.height);
            main.renderer.drawText(
                screen_pos.x - total_w / 2 + button_w + 5,
                enter_y,
                cam_data.scale,
                &main.renderer.enter_text_data,
                .{},
            );
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

    const alpha_mult: f32 = self.alpha;
    var color: u32 = 0;
    var color_intensity: f32 = 0.0;
    _ = &color;
    _ = &color_intensity;
    // flash

    if (self.name_text_data) |*data| {
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
    }

    if (int_id == self.map_id) {
        const button_w = 100.0 / 5.0 * cam_data.scale;
        const button_h = 100.0 / 5.0 * cam_data.scale;
        const total_w = main.renderer.enter_text_data.width * cam_data.scale + button_w;

        const enter_y = screen_pos.y + h + 5;
        main.renderer.drawQuad(
            screen_pos.x - total_w / 2,
            enter_y,
            button_w,
            button_h,
            assets.interact_key_tex,
            .{ .sort_extra = (screen_pos.y - enter_y) + (h - button_h) },
        );

        main.renderer.enter_text_data.sort_extra = (screen_pos.y - enter_y) + (h - main.renderer.enter_text_data.height);
        main.renderer.drawText(
            screen_pos.x - total_w / 2 + button_w + 5,
            enter_y,
            cam_data.scale,
            &main.renderer.enter_text_data,
            .{},
        );
    }

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

pub fn update(self: *Portal, time: i64) void {
    base.update(self, Portal, time);
}
