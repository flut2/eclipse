const std = @import("std");
const assets = @import("../assets.zig");
const game_data = @import("../game_data.zig");
const utils = @import("../utils.zig");
const map = @import("map.zig");
const main = @import("../main.zig");

pub const Square = struct {
    pub const left_blend_idx = 0;
    pub const top_blend_idx = 1;
    pub const right_blend_idx = 2;
    pub const bottom_blend_idx = 3;

    pub const Blend = struct {
        u: f32,
        v: f32,
    };

    tile_type: u16 = 0xFFFF,
    x: f32 = 0.0,
    y: f32 = 0.0,
    atlas_data: assets.AtlasData = assets.AtlasData.fromRaw(0, 0, 0, 0, .base),
    blends: [4]Blend = [_]Blend{.{ .u = -1.0, .v = -1.0 }} ** 4,
    props: *const game_data.GroundProps = undefined,
    static_obj_id: i32 = -1,
    sinking: bool = false,
    u_offset: f32 = 0,
    v_offset: f32 = 0,

    pub inline fn addToMap(self: *Square) void {
        const floor_y: u32 = @intFromFloat(@floor(self.y));
        const floor_x: u32 = @intFromFloat(@floor(self.x));

        self.props = game_data.ground_type_to_props.getPtr(self.tile_type) orelse {
            std.log.err("Could not find props for square with type 0x{x}, returning", .{self.tile_type});
            return;
        };

        texParse: {
            if (self.tile_type == 0xFFFC) {
                self.atlas_data = assets.editor_tile;
                self.updateBlends();
                break :texParse;
            }

            if (game_data.ground_type_to_tex_data.get(self.tile_type)) |tex_list| {
                if (tex_list.len == 0) {
                    std.log.err("Square with type 0x{x} has an empty texture list, parsing failed", .{self.tile_type});
                    break :texParse;
                }

                const tex = if (tex_list.len == 1) tex_list[0] else tex_list[utils.rng.next() % tex_list.len];
                if (assets.atlas_data.get(tex.sheet)) |data| {
                    var ground_data = data[tex.index];
                    ground_data.removePadding();
                    self.atlas_data = ground_data;
                } else {
                    std.log.err("Could not find sheet {s} for square with type 0x{x}. Using error texture", .{ tex.sheet, self.tile_type });
                    self.atlas_data = assets.error_data;
                }

                if (assets.dominant_color_data.get(tex.sheet)) |color_data| {
                    const color = color_data[tex.index];
                    const base_data_idx: usize = @intCast(floor_y * map.minimap.num_components * map.minimap.width + floor_x * map.minimap.num_components);
                    map.minimap.data[base_data_idx] = color.r;
                    map.minimap.data[base_data_idx + 1] = color.g;
                    map.minimap.data[base_data_idx + 2] = color.b;
                    map.minimap.data[base_data_idx + 3] = color.a;

                    main.minimap_update_min_x = @min(main.minimap_update_min_x, floor_x);
                    main.minimap_update_max_x = @max(main.minimap_update_max_x, floor_x);
                    main.minimap_update_min_y = @min(main.minimap_update_min_y, floor_y);
                    main.minimap_update_max_y = @max(main.minimap_update_max_y, floor_y);
                }

                self.updateBlends();
            }
        }

        if (self.props.random_offset) {
            const u_offset: f32 = @floatFromInt(utils.rng.next() % 8);
            const v_offset: f32 = @floatFromInt(utils.rng.next() % 8);
            self.u_offset = u_offset * assets.base_texel_w;
            self.v_offset = v_offset * assets.base_texel_h;
        }
        self.u_offset += self.props.x_offset * 10.0 * assets.base_texel_w;
        self.v_offset += self.props.y_offset * 10.0 * assets.base_texel_h;

        map.squares.put(floor_x + floor_y * map.width, self.*) catch |e| {
            std.log.err("Setting square at x={d}, y={d} failed: {}", .{ self.x, self.y, e });
            return;
        };
    }

    inline fn parseDir(x: f32, y: f32, square: *Square, current_prio: i32, comptime blend_idx: comptime_int) void {
        const opposite_idx = (blend_idx + 2) % 4;
        if (map.getSquarePtr(x, y)) |other_sq| {
            const has_wall = blk: {
                const en = map.findEntityConst(other_sq.static_obj_id) orelse break :blk false;
                break :blk en == .object and en.object.class == .wall;
            };

            if (other_sq.tile_type != 0xFF and !has_wall) {
                const other_blend_prio = other_sq.props.blend_prio;
                if (other_blend_prio > current_prio) {
                    square.blends[blend_idx] = .{
                        .u = other_sq.atlas_data.tex_u,
                        .v = other_sq.atlas_data.tex_v,
                    };
                    other_sq.blends[opposite_idx] = .{ .u = -1.0, .v = -1.0 };
                } else if (other_blend_prio < current_prio) {
                    other_sq.blends[opposite_idx] = .{
                        .u = square.atlas_data.tex_u,
                        .v = square.atlas_data.tex_v,
                    };
                    square.blends[blend_idx] = .{ .u = -1.0, .v = -1.0 };
                } else {
                    square.blends[blend_idx] = .{ .u = -1.0, .v = -1.0 };
                    other_sq.blends[opposite_idx] = .{ .u = -1.0, .v = -1.0 };
                }
            }
        }
    }

    pub fn updateBlends(square: *Square) void {
        if (square.tile_type == 0xFF)
            return;

        map.object_lock.lockShared();
        defer map.object_lock.unlockShared();

        const current_prio = square.props.blend_prio;

        if (square.x > 0) parseDir(square.x - 1, square.y, square, current_prio, left_blend_idx);
        if (square.y > 0) parseDir(square.x, square.y - 1, square, current_prio, top_blend_idx);
        if (square.x < std.math.maxInt(u32)) parseDir(square.x + 1, square.y, square, current_prio, right_blend_idx);
        if (square.y < std.math.maxInt(u32)) parseDir(square.x, square.y + 1, square, current_prio, bottom_blend_idx);
    }
};
