const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const network_data = shared.network_data;
const utils = shared.utils;
const usizef = utils.usizef;
const i64f = utils.i64f;

const assets = @import("../assets.zig");
const Camera = @import("../Camera.zig");
const px_per_tile = Camera.px_per_tile;
const size_mult = Camera.size_mult;
const main = @import("../main.zig");
const CameraData = @import("../render/CameraData.zig");
const ui_systems = @import("../ui/systems.zig");
const Ally = @import("Ally.zig");
const Container = @import("Container.zig");
const Enemy = @import("Enemy.zig");
const Entity = @import("Entity.zig");
const map = @import("map.zig");
const Player = @import("Player.zig");
const Portal = @import("Portal.zig");

pub fn addToMap(obj_data: anytype, comptime ObjType: type) void {
    const type_name = switch (ObjType) {
        Player => "player",
        Entity => "entity",
        Enemy => "enemy",
        Portal => "portal",
        Container => "container",
        Ally => "ally",
        else => @compileError("Invalid type"),
    };

    var self = obj_data;
    self.data = @field(game_data, type_name).from_id.getPtr(self.data_id) orelse {
        std.log.err("Could not find data for {s} with data id {}, returning", .{ type_name, self.data_id });
        return;
    };
    self.size_mult = self.data.size_mult;

    texParse: {
        const T = @TypeOf(self);
        if (T == Enemy or T == Ally) {
            if (self.data.textures.len == 0) {
                std.log.err("{s} with data id {} has an empty texture list, parsing failed", .{ type_name, self.data_id });
                break :texParse;
            }

            const tex = self.data.textures[utils.rng.next() % self.data.textures.len];

            if (assets.anim_enemies.get(tex.sheet)) |anim_data| {
                self.anim_data = anim_data[tex.index];
            } else {
                std.log.err("Could not find anim sheet {s} for {s} with data id {}. Using error texture", .{ tex.sheet, type_name, self.data_id });
                self.anim_data = assets.error_data_enemy;
            }
            self.atlas_data = self.anim_data.walk_anims[0];
        } else {
            if (self.data.textures.len == 0) {
                std.log.err("{s} with data id {} has an empty texture list, parsing failed", .{ type_name, self.data_id });
                break :texParse;
            }

            const tex = self.data.textures[utils.rng.next() % self.data.textures.len];

            if (@hasField(@TypeOf(self.data.*), "is_wall") and self.data.is_wall) {
                if (assets.walls.get(tex.sheet)) |data| {
                    self.wall_data = data[tex.index];
                } else {
                    std.log.err("Could not find sheet {s} for wall with data id {}. Using error texture", .{ tex.sheet, self.data_id });
                    self.wall_data = assets.error_data_wall;
                }
            } else {
                if (assets.atlas_data.get(tex.sheet)) |data| {
                    self.atlas_data = data[tex.index];
                } else {
                    std.log.err("Could not find sheet {s} for {s} with data id {}. Using error texture", .{ tex.sheet, type_name, self.data_id });
                    self.atlas_data = assets.error_data;
                }
            }
        }

        if (@hasField(T, "colors")) self.colors = assets.atlas_to_color_data.get(if (@hasField(@TypeOf(self.data.*), "is_wall") and self.data.is_wall)
            @bitCast(self.wall_data.base)
        else
            @bitCast(self.atlas_data)) orelse blk: {
            std.log.err("Could not parse color data for {s} with data id {}. Setting it to empty", .{ type_name, self.data_id });
            break :blk &.{};
        };

        if (self.data.draw_on_ground or @hasField(@TypeOf(self.data.*), "is_wall") and self.data.is_wall)
            self.atlas_data.removePadding();
    }

    if (self.name_text_data == null and self.data.show_name) {
        self.name_text_data = .{
            .text = undefined,
            .text_type = .bold,
            .size = 12,
        };
        self.name_text_data.?.setText(if (self.name) |obj_name| obj_name else self.data.name);
    }

    map.addListForType(ObjType).append(main.allocator, self) catch @panic("Adding " ++ type_name ++ " failed");
}

pub fn deinit(self: anytype) void {
    if (self.name_text_data) |*data| data.deinit();
    if (self.name) |en_name| main.allocator.free(en_name);
}

pub fn update(self: anytype, comptime ObjType: type, time: i64) void {
    const type_name = switch (ObjType) {
        Player => "player",
        Entity => "entity",
        Enemy => "enemy",
        Portal => "portal",
        Container => "container",
        else => @compileError("Invalid type"),
    };

    if (self.data.animations) |animations| {
        if (time >= self.next_anim) {
            const frame_len = animations.len;
            if (frame_len < 2) {
                std.log.err("The amount of frames ({}) was not enough for {s} with data id {}", .{ frame_len, type_name, self.data_id });
                return;
            }

            const frame_data = animations[self.anim_idx];
            const tex_data = frame_data.texture;
            if (@hasField(@TypeOf(self.data.*), "is_wall") and self.data.is_wall) {
                if (assets.walls.get(tex_data.sheet)) |tex| {
                    if (tex_data.index >= tex.len) {
                        std.log.err("Incorrect index ({}) given to anim with sheet {s}, {s} with data id: {}", .{ tex_data.index, tex_data.sheet, type_name, self.data_id });
                        return;
                    }
                    self.wall_data = tex[tex_data.index];
                    self.anim_idx = @intCast((self.anim_idx + 1) % frame_len);
                    self.next_anim = time + i64f(frame_data.time * std.time.us_per_s);
                } else {
                    std.log.err("Could not find sheet {s} for anim on {s} with data id {}", .{ tex_data.sheet, type_name, self.data_id });
                    return;
                }
            } else {
                if (assets.atlas_data.get(tex_data.sheet)) |tex| {
                    if (tex_data.index >= tex.len) {
                        std.log.err("Incorrect index ({}) given to anim with sheet {s}, {s} with data id: {}", .{ tex_data.index, tex_data.sheet, type_name, self.data_id });
                        return;
                    }
                    self.atlas_data = tex[tex_data.index];
                    if (self.data.draw_on_ground) self.atlas_data.removePadding();
                    self.anim_idx = @intCast((self.anim_idx + 1) % frame_len);
                    self.next_anim = time + i64f(frame_data.time * std.time.us_per_s);
                } else {
                    std.log.err("Could not find sheet {s} for anim on {s} with data id {}", .{ tex_data.sheet, type_name, self.data_id });
                    return;
                }
            }
        }
    }
}

pub fn drawConditions(cond_int: @typeInfo(utils.Condition).@"struct".backing_integer.?, float_time_ms: f32, x: f32, y: f32, scale: f32) void {
    var cond_len: f32 = 0.0;
    for (0..@bitSizeOf(utils.Condition)) |i| {
        if (cond_int & (@as(usize, 1) << @intCast(i)) != 0)
            cond_len += if (main.renderer.condition_rects[i].len > 0) 1.0 else 0.0;
    }

    var cond_new_idx: f32 = 0.0;
    for (0..@bitSizeOf(utils.Condition)) |i| {
        if (cond_int & (@as(usize, 1) << @intCast(i)) != 0) {
            const data = main.renderer.condition_rects[i];
            if (data.len > 0) {
                const frame_new_idx = usizef(float_time_ms / (0.5 * std.time.us_per_s));
                const current_frame = data[@mod(frame_new_idx, data.len)];
                const cond_w = current_frame.texWRaw() * scale;
                const cond_h = current_frame.texHRaw() * scale;

                main.renderer.drawQuad(
                    x - cond_len * (cond_w + 2) / 2 + cond_new_idx * (cond_w + 2),
                    y,
                    cond_w,
                    cond_h,
                    current_frame,
                    .{ .shadow_texel_mult = 1.0 },
                );
                cond_new_idx += 1.0;
            }
        }
    }
}

pub fn drawStatusTexts(self: anytype, time: i64, x: f32, y: f32, scale: f32) void {
    var status_texts_to_dispose: std.ArrayListUnmanaged(usize) = .empty;
    defer status_texts_to_dispose.deinit(main.allocator);
    for (self.status_texts.items, 0..) |*text, i|
        if (!text.draw(time, x, y, scale))
            status_texts_to_dispose.append(main.allocator, i) catch main.oomPanic();

    var iter = std.mem.reverseIterator(status_texts_to_dispose.items);
    while (iter.next()) |i| {
        self.status_texts.items[i].deinit();
        _ = self.status_texts.orderedRemove(i);
    }
}
