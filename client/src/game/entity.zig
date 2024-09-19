const std = @import("std");
const element = @import("../ui/element.zig");
const ui_systems = @import("../ui/systems.zig");
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

pub const Entity = struct {
    map_id: u32 = std.math.maxInt(u32),
    data_id: u16 = std.math.maxInt(u16),
    dead: bool = false,
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
    condition: utils.Condition = .{},
    atlas_data: assets.AtlasData = .default,
    data: *const game_data.EntityData = undefined,
    colors: []u32 = &.{},
    anim_idx: u8 = 0,
    next_anim: i64 = -1,
    disposed: bool = false,

    pub fn addToMap(self: *Entity, allocator: std.mem.Allocator) void {
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
                    main.minimap_lock.lock();
                    defer main.minimap_lock.unlock();

                    const floor_y: u32 = @intFromFloat(@floor(self.y));
                    const floor_x: u32 = @intFromFloat(@floor(self.x));

                    const color = color_data[tex.index];
                    const base_data_idx: usize = @intCast(floor_y * map.minimap.num_components * map.minimap.width + floor_x * map.minimap.num_components);
                    @memcpy(map.minimap.data[base_data_idx .. base_data_idx + 4], &@as([4]u8, @bitCast(color)));

                    main.minimap_update.min_x = @min(main.minimap_update.min_x, floor_x);
                    main.minimap_update.max_x = @max(main.minimap_update.max_x, floor_x);
                    main.minimap_update.min_y = @min(main.minimap_update.min_y, floor_y);
                    main.minimap_update.max_y = @max(main.minimap_update.max_y, floor_y);
                }
            }
        }

        collision: {
            if (self.x >= 0 and self.y >= 0 and self.data.occupy_square or self.data.full_occupy) {
                const square = map.getSquarePtr(self.x, self.y, true) orelse break :collision;
                square.entity_map_id = self.map_id;
            }
        }

        base.addToMap(self, Entity, allocator);
    }

    pub fn deinit(self: *Entity, allocator: std.mem.Allocator) void {
        base.deinit(self, Entity, allocator);

        if (self.data.occupy_square or self.data.full_occupy) {
            if (map.getSquarePtr(self.x, self.y, true)) |square| {
                if (square.entity_map_id == self.map_id) square.entity_map_id = std.math.maxInt(u32);
            }
        }
    }

    pub fn draw(self: *Entity, cam_data: render.CameraData, float_time_ms: f32, allocator: std.mem.Allocator) void {
        if (self.dead or !cam_data.visibleInCamera(self.x, self.y)) return;

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

            return;
        }

        var atlas_data = self.atlas_data;
        var sink: f32 = 1.0;
        if (map.getSquare(self.x, self.y, true)) |square| sink += if (square.data.sink) 0.75 else 0;
        atlas_data.tex_h /= sink;

        const w = atlas_data.texWRaw() * size;
        const h = atlas_data.texHRaw() * size;

        screen_pos.y += self.z * -px_per_tile - h + assets.padding * size;

        var alpha_mult: f32 = self.alpha;
        if (self.condition.invisible)
            alpha_mult = 0.6;

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

        var y_pos: f32 = if (sink != 1.0) 10.0 else 0.0;

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
                .{ .shadow_texel_mult = 0.5 },
            );

            const float_hp: f32 = @floatFromInt(self.hp);
            const float_max_hp: f32 = @floatFromInt(self.max_hp);
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

            y_pos += hp_bar_h;
        }
    }

    pub fn update(self: *Entity, time: i64) void {
        base.update(self, Entity, time);
    }
};
