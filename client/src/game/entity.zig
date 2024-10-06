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
    render_color_override: u32 = std.math.maxInt(u32),
    condition: utils.Condition = .{},
    atlas_data: assets.AtlasData = .default,
    top_atlas_data: assets.AtlasData = .default,
    bottom_atlas_data: assets.AtlasData = .default,
    left_atlas_data: assets.AtlasData = .default,
    right_atlas_data: assets.AtlasData = .default,
    data: *const game_data.EntityData = undefined,
    colors: []u32 = &.{},
    anim_idx: u8 = 0,
    top_anim_idx: u8 = 0,
    bottom_anim_idx: u8 = 0,
    left_anim_idx: u8 = 0,
    right_anim_idx: u8 = 0,
    next_anim: i64 = -1,
    top_next_anim: i64 = -1,
    bottom_next_anim: i64 = -1,
    left_next_anim: i64 = -1,
    right_next_anim: i64 = -1,
    wall_side_behaviors: packed struct {
        const SideBehavior = enum(u2) { normal, cull, blackout };
        top: SideBehavior = .normal,
        bottom: SideBehavior = .normal,
        left: SideBehavior = .normal,
        right: SideBehavior = .normal,
    } = .{},

    fn parseSide(self: *Entity, comptime side_name: []const u8) void {
        if (@field(self.data, side_name ++ "_textures")) |tex_list| {
            if (tex_list.len == 0) {
                std.log.err("Wall with data id {} has an empty " ++ side_name ++ " side texture list, parsing failed", .{self.data_id});
                return;
            }

            const tex = tex_list[utils.rng.next() % tex_list.len];
            if (assets.atlas_data.get(tex.sheet)) |data| {
                var side_data = data[tex.index];
                side_data.removePadding();
                @field(self, side_name ++ "_atlas_data") = side_data;
            } else {
                std.log.err("Could not find " ++ side_name ++ " side sheet {s} for wall with data id {}. Using error texture", .{ tex.sheet, self.data_id });
                @field(self, side_name ++ "_atlas_data") = assets.error_data;
            }
        }
    }

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

        inline for (.{ "top", "bottom", "left", "right" }) |side| self.parseSide(side);

        collision: {
            if (self.x >= 0 and self.y >= 0 and (self.data.occupy_square or self.data.full_occupy or self.data.is_wall)) {
                const square = map.getSquarePtr(self.x, self.y, true) orelse break :collision;
                square.entity_map_id = self.map_id;
            }
        }

        if (self.data.is_wall) {
            self.x = @floor(self.x);
            self.y = @floor(self.y);

            if (map.getSquare(self.x, self.y - 1, true)) |square| {
                if (map.findObjectWithAddList(Entity, square.entity_map_id, .ref)) |wall| {
                    if (wall.data.is_wall) {
                        wall.wall_side_behaviors.bottom = .cull;
                        self.wall_side_behaviors.top = .cull;
                    }
                }
            } else self.wall_side_behaviors.top = .blackout;

            if (map.getSquare(self.x, self.y + 1, true)) |square| {
                if (map.findObjectWithAddList(Entity, square.entity_map_id, .ref)) |wall| {
                    if (wall.data.is_wall) {
                        wall.wall_side_behaviors.top = .cull;
                        self.wall_side_behaviors.bottom = .cull;
                    }
                }
            } else self.wall_side_behaviors.bottom = .blackout;

            if (map.getSquare(self.x - 1, self.y, true)) |square| {
                if (map.findObjectWithAddList(Entity, square.entity_map_id, .ref)) |wall| {
                    if (wall.data.is_wall) {
                        wall.wall_side_behaviors.right = .cull;
                        self.wall_side_behaviors.left = .cull;
                    }
                }
            } else self.wall_side_behaviors.left = .blackout;

            if (map.getSquare(self.x + 1, self.y, true)) |square| {
                if (map.findObjectWithAddList(Entity, square.entity_map_id, .ref)) |wall| {
                    if (wall.data.is_wall) {
                        wall.wall_side_behaviors.left = .cull;
                        self.wall_side_behaviors.right = .cull;
                    }
                }
            } else self.wall_side_behaviors.right = .blackout;
        }

        base.addToMap(self, Entity, allocator);
    }

    pub fn deinit(self: *Entity, allocator: std.mem.Allocator) void {
        base.deinit(self, allocator);

        if (self.data.occupy_square or self.data.full_occupy) {
            if (map.getSquarePtr(self.x, self.y, true)) |square| {
                if (square.entity_map_id == self.map_id) square.entity_map_id = std.math.maxInt(u32);
            }
        }
    }

    fn drawWallSide(
        render_type: render.RenderType,
        x: f32,
        y: f32,
        scale: f32,
        atlas_data: assets.AtlasData,
        rotation: f32,
        sort_extra: f32,
        color: u32,
        color_intensity: f32,
    ) void {
        const size = px_per_tile * scale;
        render.drawQuad(x, y, size, size, atlas_data, .{
            .rotation = rotation,
            .render_type_override = render_type,
            .sort_extra = sort_extra,
            .color = color,
            .color_intensity = color_intensity,
        });
    }

    pub fn draw(self: *Entity, cam_data: render.CameraData, float_time_ms: f32, allocator: std.mem.Allocator) void {
        if (self.dead or !cam_data.visibleInCamera(self.x, self.y)) return;

        if (self.data.is_wall) {
            const tile_pos = cam_data.worldToScreen(@floor(self.x) + 0.5, @floor(self.y) + 0.5);
            const offset = px_per_tile * cam_data.scale / 2.0;
            drawWallSide(.wall_upper, tile_pos.x, tile_pos.y, cam_data.scale, self.atlas_data, cam_data.angle, -offset * 3.0 - 2.0, 0, 0.1);

            const pi_div_2 = std.math.pi / 2.0;
            const bound_angle = utils.halfBound(cam_data.angle);

            if (self.wall_side_behaviors.top != .cull and
                (bound_angle >= pi_div_2 and bound_angle <= std.math.pi or bound_angle >= -std.math.pi and bound_angle <= -pi_div_2))
            {
                const atlas_data = if (self.wall_side_behaviors.top == .blackout) assets.generic_8x8 else self.top_atlas_data;
                drawWallSide(.wall_top_side, tile_pos.x, tile_pos.y, cam_data.scale, atlas_data, cam_data.angle, -offset - 1.0, 0, 0.25);
            }

            if (self.wall_side_behaviors.bottom != .cull and
                bound_angle <= pi_div_2 and bound_angle >= -pi_div_2)
            {
                const atlas_data = if (self.wall_side_behaviors.bottom == .blackout) assets.generic_8x8 else self.bottom_atlas_data;
                drawWallSide(.wall_bottom_side, tile_pos.x, tile_pos.y, cam_data.scale, atlas_data, cam_data.angle, -offset - 1.0, 0, 0.25);
            }

            if (self.wall_side_behaviors.left != .cull and
                bound_angle >= 0 and bound_angle <= std.math.pi)
            {
                const atlas_data = if (self.wall_side_behaviors.left == .blackout) assets.generic_8x8 else self.left_atlas_data;
                drawWallSide(.wall_left_side, tile_pos.x, tile_pos.y, cam_data.scale, atlas_data, cam_data.angle, -offset - 1.0, 0, 0.25);
            }

            if (self.wall_side_behaviors.right != .cull and
                bound_angle <= 0 and bound_angle >= -std.math.pi)
            {
                const atlas_data = if (self.wall_side_behaviors.right == .blackout) assets.generic_8x8 else self.right_atlas_data;
                drawWallSide(.wall_right_side, tile_pos.x, tile_pos.y, cam_data.scale, atlas_data, cam_data.angle, -offset - 1.0, 0, 0.25);
            }
            return;
        }

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

        var color: u32 = if (self.render_color_override == std.math.maxInt(u32)) 0 else self.render_color_override;
        var color_intensity: f32 = if (self.render_color_override == std.math.maxInt(u32)) 0.0 else 0.5;
        _ = &color;
        _ = &color_intensity;
        // flash

        if (main.settings.enable_lights) {
            const tile_pos = cam_data.worldToScreen(@floor(self.x), @floor(self.y));
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

            y_pos += hp_bar_h + 5.0;
        }
    }

    pub fn update(self: *Entity, time: i64) void {
        base.update(self, Entity, time);
        base.updateAnimation(
            "entity",
            time,
            self.data.top_animation,
            self.data_id,
            self.data.draw_on_ground,
            &self.top_atlas_data,
            &self.top_next_anim,
            &self.top_anim_idx,
        );
        base.updateAnimation(
            "entity",
            time,
            self.data.bottom_animation,
            self.data_id,
            self.data.draw_on_ground,
            &self.bottom_atlas_data,
            &self.bottom_next_anim,
            &self.bottom_anim_idx,
        );
        base.updateAnimation(
            "entity",
            time,
            self.data.left_animation,
            self.data_id,
            self.data.draw_on_ground,
            &self.left_atlas_data,
            &self.left_next_anim,
            &self.left_anim_idx,
        );
        base.updateAnimation(
            "entity",
            time,
            self.data.right_animation,
            self.data_id,
            self.data.draw_on_ground,
            &self.right_atlas_data,
            &self.right_next_anim,
            &self.right_anim_idx,
        );
    }
};
