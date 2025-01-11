const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const utils = shared.utils;

const assets = @import("../assets.zig");
const main = @import("../main.zig");
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

data_id: u16 = empty_tile,
x: f32 = 0.0,
y: f32 = 0.0,
atlas_data: assets.AtlasData = assets.AtlasData.fromRaw(0, 0, 0, 0, .base),
blends: [4]Blend = @splat(.{ .u = -1.0, .v = -1.0 }),
rotation: f32 = 0.0,
data: *const game_data.GroundData = undefined,
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
    std.debug.assert(!map.square_lock.tryLock());

    var self = square_data;
    const floor_y: u32 = @intFromFloat(@floor(self.y));
    const floor_x: u32 = @intFromFloat(@floor(self.x));

    self.data = game_data.ground.from_id.getPtr(self.data_id) orelse {
        std.log.err("Could not find data for square with data id {}, returning", .{self.data_id});
        return;
    };

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

    map.squares[floor_y * map.info.width + floor_x] = self;
    map.squares[floor_y * map.info.width + floor_x].update();
}

fn updateBlendAtDir(square: *Square, other_square: ?*Square, current_prio: i32, comptime blend_dir: comptime_int) void {
    if (other_square) |other_sq| {
        const opposite_dir = (blend_dir + 2) % 4;

        if (other_sq.data_id != editor_tile and other_sq.data_id != empty_tile) {
            const other_blend_prio = other_sq.data.blend_prio;
            if (other_blend_prio > current_prio) {
                square.blends[blend_dir] = .{
                    .u = other_sq.atlas_data.tex_u,
                    .v = other_sq.atlas_data.tex_v,
                };
                other_sq.blends[opposite_dir] = .{ .u = -1.0, .v = -1.0 };
            } else if (other_blend_prio < current_prio) {
                other_sq.blends[opposite_dir] = .{
                    .u = square.atlas_data.tex_u,
                    .v = square.atlas_data.tex_v,
                };
                square.blends[blend_dir] = .{ .u = -1.0, .v = -1.0 };
            } else {
                square.blends[blend_dir] = .{ .u = -1.0, .v = -1.0 };
                other_sq.blends[opposite_dir] = .{ .u = -1.0, .v = -1.0 };
            }

            return;
        }

        other_sq.blends[opposite_dir] = .{ .u = -1.0, .v = -1.0 };
    }

    square.blends[blend_dir] = .{ .u = -1.0, .v = -1.0 };
}

fn equals(square: ?*Square, data_id: u16) bool {
    if (square) |sq| {
        return sq.data_id == data_id;
    } else return false;
}

pub fn update(square: *Square) void {
    if (square.data_id == editor_tile or square.data_id == empty_tile) return;

    const current_prio = square.data.blend_prio;
    const left_sq = map.getSquare(square.x - 1, square.y, true, .ref);
    const top_sq = map.getSquare(square.x, square.y - 1, true, .ref);
    const right_sq = if (square.x < std.math.maxInt(u32)) map.getSquare(square.x + 1, square.y, true, .ref) else null;
    const bottom_sq = if (square.y < std.math.maxInt(u32)) map.getSquare(square.x, square.y + 1, true, .ref) else null;
    updateBlendAtDir(square, left_sq, current_prio, left_blend_dir);
    updateBlendAtDir(square, top_sq, current_prio, top_blend_dir);
    updateBlendAtDir(square, right_sq, current_prio, right_blend_dir);
    updateBlendAtDir(square, bottom_sq, current_prio, bottom_blend_dir);
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

fn updateRugs(square: *Square, current_data_id: u16) void {
    const rug_tex = square.data.rug_textures orelse return;

    const left_sq = map.getSquare(square.x - 1, square.y, true, .ref);
    const top_sq = map.getSquare(square.x, square.y - 1, true, .ref);
    const right_sq = if (square.x < std.math.maxInt(u32)) map.getSquare(square.x + 1, square.y, true, .ref) else null;
    const bottom_sq = if (square.y < std.math.maxInt(u32)) map.getSquare(square.x, square.y + 1, true, .ref) else null;

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

    square.selectTexture(square.data.textures);
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
