const std = @import("std");

const shared = @import("shared");
const utils = shared.utils;
const game_data = shared.game_data;
const f32i = utils.f32i;
const u32f = utils.u32f;
const i64f = utils.i64f;

const assets = @import("../assets.zig");
const Camera = @import("../Camera.zig");
const px_per_tile = Camera.px_per_tile;
const main = @import("../main.zig");
const render = @import("../render.zig");
const element = @import("../ui/elements/element.zig");
const StatusText = @import("../ui/game/StatusText.zig");
const ui_systems = @import("../ui/systems.zig");
const base = @import("object_base.zig");
const map = @import("map.zig");
const particles = @import("particles.zig");

const Entity = @This();

map_id: u32 = std.math.maxInt(u32),
data_id: u16 = std.math.maxInt(u16),
x: f32 = 0.0,
y: f32 = 0.0,
z: f32 = 0.0,
alpha: f32 = 1.0,
name: ?[]const u8 = null,
name_text_data: ?element.TextData = null,
size_mult: f32 = 0,
max_hp: i32 = 0,
hp: i32 = 0,
defense: i16 = 0,
resistance: i16 = 0,
render_color_override: u32 = std.math.maxInt(u32),
condition: utils.Condition = .{},
atlas_data: assets.AtlasData = .default,
wall_data: assets.WallData = .default,
data: *const game_data.EntityData = undefined,
colors: []u32 = &.{},
anim_idx: u8 = 0,
next_anim: i64 = -1,
wall_outline_cull: packed struct {
    top: bool = false,
    bottom: bool = false,
    left: bool = false,
    right: bool = false,
} = .{},
status_texts: std.ArrayListUnmanaged(StatusText) = .empty,

pub fn addToMap(entity_data: Entity) void {
    var self = entity_data;
    self.data = game_data.entity.from_id.getPtr(self.data_id) orelse {
        std.log.err("Could not find data for entity with data id {}, returning", .{self.data_id});
        return;
    };

    texParse: {
        if (self.data.textures.len == 0) {
            std.log.err("Entity with data id {} has an empty texture list, parsing failed", .{self.data_id});
            break :texParse;
        }

        const tex = self.data.textures[utils.rng.next() % self.data.textures.len];
        if (ui_systems.screen != .editor and self.data.static and self.data.occupy_square) {
            if (assets.dominant_color_data.get(tex.sheet)) |color_data| {
                const floor_y = u32f(self.y);
                const floor_x = u32f(self.x);

                const color = color_data[tex.index];
                const base_data_idx: usize = @intCast(floor_y * map.minimap.num_components * map.minimap.width + floor_x * map.minimap.num_components);
                @memcpy(map.minimap.data[base_data_idx .. base_data_idx + 4], &@as([4]u8, @bitCast(color)));

                main.minimap_update = .{
                    .min_x = @min(main.minimap_update.min_x, floor_x),
                    .max_x = @max(main.minimap_update.max_x, floor_x),
                    .min_y = @min(main.minimap_update.min_y, floor_y),
                    .max_y = @max(main.minimap_update.max_y, floor_y),
                };
            }
        }
    }

    collision: {
        if (self.x >= 0 and self.y >= 0 and (self.data.occupy_square or self.data.full_occupy or self.data.is_wall)) {
            const square = map.getSquare(self.x, self.y, true, .ref) orelse break :collision;
            square.entity_map_id = self.map_id;
        }
    }

    if (self.data.is_wall) {
        self.x = @floor(self.x);
        self.y = @floor(self.y);

        if (map.getSquare(self.x, self.y - 1, true, .con)) |square| {
            if (map.findObjectWithAddList(Entity, square.entity_map_id, .ref)) |wall| {
                if (wall.data.is_wall) {
                    wall.wall_outline_cull.bottom = true;
                    self.wall_outline_cull.top = true;
                }
            }
        }

        if (map.getSquare(self.x, self.y + 1, true, .con)) |square| {
            if (map.findObjectWithAddList(Entity, square.entity_map_id, .ref)) |wall| {
                if (wall.data.is_wall) {
                    wall.wall_outline_cull.top = true;
                    self.wall_outline_cull.bottom = true;
                }
            }
        }

        if (map.getSquare(self.x - 1, self.y, true, .con)) |square| {
            if (map.findObjectWithAddList(Entity, square.entity_map_id, .ref)) |wall| {
                if (wall.data.is_wall) {
                    wall.wall_outline_cull.right = true;
                    self.wall_outline_cull.left = true;
                }
            }
        }

        if (map.getSquare(self.x + 1, self.y, true, .con)) |square| {
            if (map.findObjectWithAddList(Entity, square.entity_map_id, .ref)) |wall| {
                if (wall.data.is_wall) {
                    wall.wall_outline_cull.left = true;
                    self.wall_outline_cull.right = true;
                }
            }
        }
    }

    base.addToMap(self, Entity);
}

pub fn deinit(self: *Entity) void {
    base.deinit(self);

    if (self.data.occupy_square or self.data.full_occupy) {
        if (map.getSquare(self.x, self.y, true, .ref)) |square| {
            if (square.entity_map_id == self.map_id) square.entity_map_id = std.math.maxInt(u32);
        }
    }

    for (self.status_texts.items) |*text| text.deinit();
    self.status_texts.deinit(main.allocator);
}

pub fn draw(self: *Entity, cam_data: render.CameraData, float_time_ms: f32) void {
    if (!cam_data.visibleInCamera(self.x, self.y)) return;

    var screen_pos = cam_data.worldToScreen(self.x, self.y);
    const size = Camera.size_mult * cam_data.scale * self.size_mult;

    if (self.data.is_wall) {
        const wall_size_mult = Camera.px_per_tile / 9.0 * cam_data.scale * self.size_mult;
        const base_w = self.wall_data.base.texWRaw() * wall_size_mult;
        const base_h = self.wall_data.base.texHRaw() * wall_size_mult;
        const base_x = screen_pos.x;
        const base_y = screen_pos.y - @max(base_h / 2.0, (self.wall_data.base.texHRaw() - 9.0) * wall_size_mult / 2.0);
        render.drawQuad(base_x, base_y, base_w, base_h, self.wall_data.base, .{});

        if (!self.wall_outline_cull.left) {
            const left_outline_w = self.wall_data.left_outline.texWRaw() * wall_size_mult;
            render.drawQuad(
                base_x - left_outline_w,
                base_y,
                left_outline_w,
                self.wall_data.left_outline.texHRaw() * wall_size_mult,
                self.wall_data.left_outline,
                .{},
            );
        }

        if (!self.wall_outline_cull.right) {
            render.drawQuad(
                base_x + base_w,
                base_y,
                self.wall_data.right_outline.texWRaw() * wall_size_mult,
                self.wall_data.right_outline.texHRaw() * wall_size_mult,
                self.wall_data.right_outline,
                .{},
            );
        }

        if (!self.wall_outline_cull.top) {
            const top_outline_h = self.wall_data.top_outline.texHRaw() * wall_size_mult;
            render.drawQuad(
                base_x,
                base_y - top_outline_h,
                self.wall_data.top_outline.texWRaw() * wall_size_mult,
                top_outline_h,
                self.wall_data.top_outline,
                .{},
            );
        }

        if (!self.wall_outline_cull.bottom) {
            render.drawQuad(
                base_x,
                base_y + base_h,
                self.wall_data.bottom_outline.texWRaw() * wall_size_mult,
                self.wall_data.bottom_outline.texHRaw() * wall_size_mult,
                self.wall_data.bottom_outline,
                .{},
            );
        }

        return;
    }

    if (self.data.draw_on_ground) {
        const tile_size = @as(f32, px_per_tile) * cam_data.scale;
        const h_half = tile_size / 2.0;

        render.drawQuad(
            screen_pos.x - tile_size / 2.0,
            screen_pos.y - h_half,
            tile_size,
            tile_size,
            self.atlas_data,
            .{ .alpha_mult = self.alpha, .sort_extra = -4096 },
        );

        if (self.name_text_data) |*data| render.drawText(
            screen_pos.x - data.width * cam_data.scale / 2,
            screen_pos.y - h_half - data.height * cam_data.scale - 5,
            cam_data.scale,
            data,
            .{},
        );

        return;
    }

    var atlas_data = self.atlas_data;
    var sink: f32 = 1.0;
    if (map.getSquare(self.x, self.y, true, .con)) |square| sink += if (square.data.sink) 0.75 else 0;
    atlas_data.tex_h /= sink;

    const w = atlas_data.texWRaw() * size;
    const h = atlas_data.texHRaw() * size;

    screen_pos.y += self.z * -px_per_tile - h + assets.padding * size;

    var alpha_mult: f32 = self.alpha;
    if (self.condition.invisible)
        alpha_mult = 0.6;

    var color: u32 = if (self.render_color_override == std.math.maxInt(u32)) 0 else self.render_color_override;
    var color_intensity: f32 = if (self.render_color_override == std.math.maxInt(u32)) 0.0 else 0.5;
    _ = &color;
    _ = &color_intensity;
    // flash

    if (main.settings.enable_lights) {
        const tile_pos = cam_data.worldToScreen(@floor(self.x), @floor(self.y));
        render.drawLight(self.data.light, tile_pos.x, tile_pos.y, cam_data.scale, float_time_ms);
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

    var y_pos: f32 = if (sink != 1.0) 15.0 else 5.0;

    if (self.hp >= 0 and self.hp < self.max_hp) {
        const hp_bar_w = assets.hp_bar_data.texWRaw() * 2 * cam_data.scale;
        const hp_bar_h = assets.hp_bar_data.texHRaw() * 2 * cam_data.scale;
        const hp_bar_y = screen_pos.y + h + y_pos;

        render.drawQuad(
            screen_pos.x - hp_bar_w / 2.0,
            hp_bar_y,
            hp_bar_w,
            hp_bar_h,
            assets.empty_bar_data,
            .{ .shadow_texel_mult = 0.5, .sort_extra = -0.0001 },
        );

        const float_hp = f32i(self.hp);
        const float_max_hp = f32i(self.max_hp);
        const hp_perc = 1.0 / (float_hp / float_max_hp);
        var hp_bar_data = assets.hp_bar_data;
        hp_bar_data.tex_w /= hp_perc;

        render.drawQuad(
            screen_pos.x - hp_bar_w / 2.0,
            hp_bar_y,
            hp_bar_w / hp_perc,
            hp_bar_h,
            hp_bar_data,
            .{},
        );

        y_pos += hp_bar_h + 5.0;
    }

    base.drawStatusTexts(
        self,
        i64f(float_time_ms) * std.time.us_per_ms,
        screen_pos.x,
        screen_pos.y,
        cam_data.scale,
    );
}

pub fn update(self: *Entity, time: i64) void {
    base.update(self, Entity, time);
}
