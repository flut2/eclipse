const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const utils = shared.utils;
const u32f = utils.u32f;
const f32i = utils.f32i;
const i64f = utils.i64f;

const assets = @import("../assets.zig");
const px_per_tile = @import("../Camera.zig").px_per_tile;
const main = @import("../main.zig");
const Renderer = @import("../render/Renderer.zig");
const ui_systems = @import("../ui/systems.zig");
const Entity = @import("Entity.zig");
const map = @import("map.zig");

const Square = @This();

pub const left_blend_dir = 0;
pub const top_blend_dir = 1;
pub const right_blend_dir = 2;
pub const bottom_blend_dir = 3;

pub const empty_tile = std.math.maxInt(u16);
pub const editor_tile = std.math.maxInt(u16) - 1;

pub const Blend = extern struct { u: f32, v: f32 };
pub const Offset = extern struct { u: f32, v: f32 };

const AnimData = struct {
    anim_idx: u8 = 0,
    next_anim: i64 = -1,
};
var anim_data: std.AutoHashMapUnmanaged(u16, AnimData) = .empty;

data_id: u16 = empty_tile,
x: f32 = 0.0,
y: f32 = 0.0,
color: utils.RGBA = .{},
atlas_data: assets.AtlasData = .fromRaw(0, 0, 0, 0, .base),
blends: [4]Blend = @splat(.{ .u = -1.0, .v = -1.0 }),
blend_offsets: [4]Offset = @splat(.{ .u = 0.0, .v = 0.0 }),
current_offset: Offset = .{ .u = 0.0, .v = 0.0 },
rotation: f32 = 0.0,
entity_map_id: u32 = std.math.maxInt(u32),

fn selectTexture(self: *Square, tex_list: []const game_data.TextureData) void {
    if (tex_list.len == 0) {
        std.log.err("Square with data id {} has an empty texture list, parsing failed", .{self.data_id});
        return;
    }

    const tex = if (tex_list.len == 1) tex_list[0] else tex_list[utils.rng.next() % tex_list.len];
    if (assets.atlas_data.get(tex.sheet)) |data| {
        self.atlas_data = data[tex.index];
    } else {
        std.log.err("Could not find sheet {s} for square with data id {}. Using error texture", .{ tex.sheet, self.data_id });
        self.atlas_data = assets.error_data;
    }
    self.atlas_data.removePadding();
}

pub fn addToMap(square_data: Square) void {
    var self = square_data;
    const floor_y = u32f(self.y);
    const floor_x = u32f(self.x);

    if (game_data.ground.from_id.get(self.data_id)) |ground_data| {
        const tex_list = ground_data.textures;
        self.selectTexture(tex_list);

        if (ui_systems.screen != .editor and tex_list.len > 0) {
            const tex = if (tex_list.len == 1) tex_list[0] else tex_list[utils.rng.next() % tex_list.len];
            if (assets.dominant_color_data.get(tex.sheet)) |color_data| {
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

    const cur = &map.squares[floor_y * map.info.width + floor_x];
    self.entity_map_id = cur.entity_map_id;
    cur.* = self;
    cur.update();
}

fn updateBlendAtDir(square: *Square, other_square: ?*Square, current_prio: i32, disable_blend: bool, comptime blend_dir: comptime_int) void {
    if (other_square) |other_sq| {
        const opposite_dir = (blend_dir + 2) % 4;
        if (disable_blend) {
            square.blends[blend_dir] = .{ .u = -1.0, .v = -1.0 };
            square.blend_offsets[blend_dir] = .{ .u = 0.0, .v = 0.0 };
            other_sq.blends[opposite_dir] = .{ .u = -1.0, .v = -1.0 };
            other_sq.blend_offsets[opposite_dir] = .{ .u = 0.0, .v = 0.0 };
            return;
        }

        if (other_sq.data_id != editor_tile and other_sq.data_id != empty_tile) {
            const other_sq_data = game_data.ground.from_id.get(other_sq.data_id) orelse {
                other_sq.blends[opposite_dir] = .{ .u = square.atlas_data.tex_u, .v = square.atlas_data.tex_v };
                other_sq.blend_offsets[opposite_dir] = square.current_offset;
                square.blends[blend_dir] = .{ .u = -1.0, .v = -1.0 };
                square.blend_offsets[blend_dir] = .{ .u = 0.0, .v = 0.0 };
                return;
            };
            if (other_sq_data.disable_blend or other_sq_data.rug_textures != null) {
                square.blends[blend_dir] = .{ .u = -1.0, .v = -1.0 };
                square.blend_offsets[blend_dir] = .{ .u = 0.0, .v = 0.0 };
                other_sq.blends[opposite_dir] = .{ .u = -1.0, .v = -1.0 };
                other_sq.blend_offsets[opposite_dir] = .{ .u = 0.0, .v = 0.0 };
                return;
            }
            const other_blend_prio = other_sq_data.blend_prio;
            if (other_blend_prio > current_prio) {
                square.blends[blend_dir] = .{ .u = other_sq.atlas_data.tex_u, .v = other_sq.atlas_data.tex_v };
                square.blend_offsets[blend_dir] = other_sq.current_offset;
                other_sq.blends[opposite_dir] = .{ .u = -1.0, .v = -1.0 };
                other_sq.blend_offsets[opposite_dir] = .{ .u = 0.0, .v = 0.0 };
            } else if (other_blend_prio < current_prio) {
                other_sq.blends[opposite_dir] = .{ .u = square.atlas_data.tex_u, .v = square.atlas_data.tex_v };
                other_sq.blend_offsets[opposite_dir] = square.current_offset;
                square.blends[blend_dir] = .{ .u = -1.0, .v = -1.0 };
                square.blend_offsets[blend_dir] = .{ .u = 0.0, .v = 0.0 };
            } else {
                square.blends[blend_dir] = .{ .u = -1.0, .v = -1.0 };
                square.blend_offsets[blend_dir] = .{ .u = 0.0, .v = 0.0 };
                other_sq.blends[opposite_dir] = .{ .u = -1.0, .v = -1.0 };
                other_sq.blend_offsets[opposite_dir] = .{ .u = 0.0, .v = 0.0 };
            }

            return;
        }

        other_sq.blends[opposite_dir] = .{ .u = -1.0, .v = -1.0 };
        other_sq.blend_offsets[opposite_dir] = .{ .u = 0.0, .v = 0.0 };
    }

    square.blends[blend_dir] = .{ .u = -1.0, .v = -1.0 };
    square.blend_offsets[blend_dir] = .{ .u = 0.0, .v = 0.0 };
}

pub fn draw(
    self: *Square,
    grounds: *std.ArrayListUnmanaged(Renderer.GroundData),
    lights: *std.ArrayListUnmanaged(Renderer.LightData),
    float_time_ms: f32,
) void {
    if (ui_systems.screen == .editor and !ui_systems.screen.editor.show_ground_layer or
        self.data_id == Square.empty_tile) return;

    const data = game_data.ground.from_id.get(self.data_id) orelse return;

    const screen_pos = main.camera.worldToScreen(self.x, self.y);

    if (main.settings.enable_lights)
        Renderer.drawLight(lights, data.light, screen_pos.x, screen_pos.y, px_per_tile, px_per_tile, main.camera.scale, float_time_ms);

    const time = main.current_time;
    var update_blends = false;
    updateTexAnim: {
        if (data.animations) |animations| {
            std.debug.assert(data.anim_sync_id != std.math.maxInt(u16));
            var sqr_anim_data: AnimData = anim_data.get(data.anim_sync_id) orelse .{};
            if (time >= sqr_anim_data.next_anim) {
                const frame_len = animations.len;
                if (frame_len < 2) {
                    std.log.err("The amount of frames ({}) was not enough for Square with data id {}", .{ frame_len, self.data_id });
                    break :updateTexAnim;
                }

                const frame_data = animations[sqr_anim_data.anim_idx];
                const tex_data = frame_data.texture;
                if (assets.atlas_data.get(tex_data.sheet)) |tex| {
                    if (tex_data.index >= tex.len) {
                        std.log.err("Incorrect index ({}) given to anim with sheet {s}, Square with data id: {}", .{ tex_data.index, tex_data.sheet, self.data_id });
                        break :updateTexAnim;
                    }
                    update_blends = true;
                    self.atlas_data = tex[tex_data.index];
                    self.atlas_data.removePadding();
                    sqr_anim_data.anim_idx = @intCast((sqr_anim_data.anim_idx + 1) % frame_len);
                    sqr_anim_data.next_anim = time + i64f(frame_data.time * std.time.us_per_s);
                    anim_data.put(main.allocator, data.anim_sync_id, sqr_anim_data) catch break :updateTexAnim;
                } else {
                    std.log.err("Could not find sheet {s} for anim on Square with data id {}", .{ tex_data.sheet, self.data_id });
                    break :updateTexAnim;
                }
            } else {
                const frame_len = animations.len;
                if (frame_len < 2) {
                    std.log.err("The amount of frames ({}) was not enough for Square with data id {}", .{ frame_len, self.data_id });
                    break :updateTexAnim;
                }

                const frame_data = animations[sqr_anim_data.anim_idx];
                const tex_data = frame_data.texture;
                if (assets.atlas_data.get(tex_data.sheet)) |tex| {
                    if (tex_data.index >= tex.len) {
                        std.log.err("Incorrect index ({}) given to anim with sheet {s}, Square with data id: {}", .{ tex_data.index, tex_data.sheet, self.data_id });
                        break :updateTexAnim;
                    }
                    update_blends = true;
                    self.atlas_data = tex[tex_data.index];
                } else {
                    std.log.err("Could not find sheet {s} for anim on Square with data id {}", .{ tex_data.sheet, self.data_id });
                    break :updateTexAnim;
                }
            }
        }
    }

    updateTexelAnim: {
        if (data.animation.type == .unset) break :updateTexelAnim;
        update_blends = true;
        const time_sec = f32i(time) / std.time.us_per_s;
        switch (data.animation.type) {
            .wave => self.current_offset = .{
                .u = @sin(data.animation.delta_x * time_sec) * assets.base_texel_w,
                .v = @sin(data.animation.delta_y * time_sec) * assets.base_texel_h,
            },
            .flow => self.current_offset = .{
                .u = data.animation.delta_x * time_sec * assets.base_texel_w,
                .v = data.animation.delta_y * time_sec * assets.base_texel_h,
            },
            .unset => unreachable,
        }
    }

    if (update_blends) {
        const current_prio = data.blend_prio;
        const disable_blend = data.disable_blend or data.rug_textures != null;
        const left_sq = map.getSquare(self.x - 1, self.y, true, .ref);
        const top_sq = map.getSquare(self.x, self.y - 1, true, .ref);
        const right_sq = if (self.x < std.math.maxInt(u32)) map.getSquare(self.x + 1, self.y, true, .ref) else null;
        const bottom_sq = if (self.y < std.math.maxInt(u32)) map.getSquare(self.x, self.y + 1, true, .ref) else null;
        updateBlendAtDir(self, left_sq, current_prio, disable_blend, left_blend_dir);
        updateBlendAtDir(self, top_sq, current_prio, disable_blend, top_blend_dir);
        updateBlendAtDir(self, right_sq, current_prio, disable_blend, right_blend_dir);
        updateBlendAtDir(self, bottom_sq, current_prio, disable_blend, bottom_blend_dir);
    }

    grounds.append(main.allocator, .{
        .pos = .{ screen_pos.x, screen_pos.y },
        .uv = .{ self.atlas_data.tex_u, self.atlas_data.tex_v },
        .offset_uv = @bitCast(self.current_offset),
        .left_blend_uv = @bitCast(self.blends[0]),
        .left_blend_offset_uv = @bitCast(self.blend_offsets[0]),
        .top_blend_uv = @bitCast(self.blends[1]),
        .top_blend_offset_uv = @bitCast(self.blend_offsets[1]),
        .right_blend_uv = @bitCast(self.blends[2]),
        .right_blend_offset_uv = @bitCast(self.blend_offsets[2]),
        .bottom_blend_uv = @bitCast(self.blends[3]),
        .bottom_blend_offset_uv = @bitCast(self.blend_offsets[3]),
        .rotation = self.rotation,
        .color = self.color,
    }) catch main.oomPanic();
}

fn equals(square: ?*Square, data_id: u16) bool {
    return if (square) |sq| sq.data_id == data_id else false;
}

pub fn update(square: *Square) void {
    if (square.data_id == editor_tile or square.data_id == empty_tile) return;
    const data = game_data.ground.from_id.get(square.data_id) orelse return;

    const current_prio = data.blend_prio;
    const has_rugs = data.rug_textures != null;
    const disable_blend = data.disable_blend or has_rugs;
    const left_sq = map.getSquare(square.x - 1, square.y, true, .ref);
    const top_sq = map.getSquare(square.x, square.y - 1, true, .ref);
    const right_sq = if (square.x < std.math.maxInt(u32)) map.getSquare(square.x + 1, square.y, true, .ref) else null;
    const bottom_sq = if (square.y < std.math.maxInt(u32)) map.getSquare(square.x, square.y + 1, true, .ref) else null;
    updateBlendAtDir(square, left_sq, current_prio, disable_blend, left_blend_dir);
    updateBlendAtDir(square, top_sq, current_prio, disable_blend, top_blend_dir);
    updateBlendAtDir(square, right_sq, current_prio, disable_blend, right_blend_dir);
    updateBlendAtDir(square, bottom_sq, current_prio, disable_blend, bottom_blend_dir);
    if (has_rugs) {
        const current_data_id = square.data_id;
        square.updateRugs(current_data_id);
        if (left_sq) |sq| sq.updateRugs(current_data_id);
        if (top_sq) |sq| sq.updateRugs(current_data_id);
        if (right_sq) |sq| sq.updateRugs(current_data_id);
        if (bottom_sq) |sq| sq.updateRugs(current_data_id);
        const top_left_sq = map.getSquare(square.x - 1, square.y - 1, true, .ref);
        const top_right_sq = if (square.x < std.math.maxInt(u32)) map.getSquare(square.x + 1, square.y - 1, true, .ref) else null;
        const bottom_left_sq = if (square.y < std.math.maxInt(u32)) map.getSquare(square.x - 1, square.y + 1, true, .ref) else null;
        const bottom_right_sq = if (square.x < std.math.maxInt(u32) and square.y < std.math.maxInt(u32))
            map.getSquare(square.x + 1, square.y + 1, true, .ref)
        else
            null;
        if (top_left_sq) |sq| sq.updateRugs(current_data_id);
        if (top_right_sq) |sq| sq.updateRugs(current_data_id);
        if (bottom_left_sq) |sq| sq.updateRugs(current_data_id);
        if (bottom_right_sq) |sq| sq.updateRugs(current_data_id);
    }
}

fn updateRugs(square: *Square, current_data_id: u16) void {
    const data = game_data.ground.from_id.get(square.data_id) orelse return;
    const rug_tex = data.rug_textures orelse return;

    const left_sq = map.getSquare(square.x - 1, square.y, true, .ref);
    const top_sq = map.getSquare(square.x, square.y - 1, true, .ref);
    const right_sq = if (square.x < std.math.maxInt(u32)) map.getSquare(square.x + 1, square.y, true, .ref) else null;
    const bottom_sq = if (square.y < std.math.maxInt(u32)) map.getSquare(square.x, square.y + 1, true, .ref) else null;
    defer {
        const current_prio = data.blend_prio;
        updateBlendAtDir(square, left_sq, current_prio, true, left_blend_dir);
        updateBlendAtDir(square, top_sq, current_prio, true, top_blend_dir);
        updateBlendAtDir(square, right_sq, current_prio, true, right_blend_dir);
        updateBlendAtDir(square, bottom_sq, current_prio, true, bottom_blend_dir);
    }

    const top_left_sq = map.getSquare(square.x - 1, square.y - 1, true, .ref);
    const top_right_sq = if (square.x < std.math.maxInt(u32)) map.getSquare(square.x + 1, square.y - 1, true, .ref) else null;
    const bottom_left_sq = if (square.y < std.math.maxInt(u32)) map.getSquare(square.x - 1, square.y + 1, true, .ref) else null;
    const bottom_right_sq = if (square.x < std.math.maxInt(u32) and square.y < std.math.maxInt(u32))
        map.getSquare(square.x + 1, square.y + 1, true, .ref)
    else
        null;
    const left_eq = equals(left_sq, current_data_id);
    const right_eq = equals(right_sq, current_data_id);
    const bottom_eq = equals(bottom_sq, current_data_id);
    const top_eq = equals(top_sq, current_data_id);
    const top_left_eq = equals(top_left_sq, current_data_id);
    const top_right_eq = equals(top_right_sq, current_data_id);
    const bottom_left_eq = equals(bottom_left_sq, current_data_id);
    const bottom_right_eq = equals(bottom_right_sq, current_data_id);

    square.selectTexture(data.textures);
    square.rotation = std.math.degreesToRadians(0);

    if (!top_eq) {
        square.selectTexture(rug_tex.edges);
        square.rotation = std.math.degreesToRadians(0);
    }

    if (!left_eq) {
        square.selectTexture(rug_tex.edges);
        square.rotation = std.math.degreesToRadians(90);
    }

    if (!right_eq) {
        square.selectTexture(rug_tex.edges);
        square.rotation = std.math.degreesToRadians(270);
    }

    if (!bottom_eq) {
        square.selectTexture(rug_tex.edges);
        square.rotation = std.math.degreesToRadians(180);
    }

    if (left_eq and top_eq and !top_left_eq) {
        square.selectTexture(rug_tex.inner_corners);
        square.rotation = std.math.degreesToRadians(0);
    }

    if (top_eq and right_eq and !top_right_eq) {
        square.selectTexture(rug_tex.inner_corners);
        square.rotation = std.math.degreesToRadians(270);
    }

    if (right_eq and bottom_eq and !bottom_right_eq) {
        square.selectTexture(rug_tex.inner_corners);
        square.rotation = std.math.degreesToRadians(180);
    }

    if (left_eq and bottom_eq and !bottom_left_eq) {
        square.selectTexture(rug_tex.inner_corners);
        square.rotation = std.math.degreesToRadians(90);
    }

    if (!left_eq and !top_eq) {
        square.selectTexture(rug_tex.corners);
        square.rotation = std.math.degreesToRadians(0);
    }

    if (!top_eq and !right_eq) {
        square.selectTexture(rug_tex.corners);
        square.rotation = std.math.degreesToRadians(270);
    }

    if (!right_eq and !bottom_eq) {
        square.selectTexture(rug_tex.corners);
        square.rotation = std.math.degreesToRadians(180);
    }

    if (!left_eq and !bottom_eq) {
        square.selectTexture(rug_tex.corners);
        square.rotation = std.math.degreesToRadians(90);
    }
}
