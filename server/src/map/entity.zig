const std = @import("std");
const game_data = @import("shared").game_data;
const stat_util = @import("stat_util.zig");
const utils = @import("shared").utils;

const World = @import("../world.zig").World;

pub const Entity = struct {
    obj_id: i32 = -1,
    x: f32 = 0.0,
    y: f32 = 0.0,
    en_type: u16 = 0xFFFF,
    stats_writer: utils.PacketWriter = .{},
    props: *const game_data.ObjProps = undefined,
    world: *World = undefined,
    allocator: std.mem.Allocator = undefined,
    spawned: bool = false,

    pub fn init(self: *Entity, allocator: std.mem.Allocator) !void {
        self.allocator = allocator;
        self.stats_writer.buffer = try allocator.alloc(u8, 32);

        self.props = game_data.obj_type_to_props.getPtr(self.en_type) orelse {
            std.log.err("Could not find props for entity with type 0x{x}", .{self.en_type});
            return;
        };
    }

    pub fn deinit(self: *Entity) !void {
        self.allocator.free(self.stats_writer.buffer);
    }

    pub fn tick(self: *Entity, time: i64, dt: i64) !void {
        _ = self;
        _ = time;
        _ = dt;
    }

    pub fn exportStats(self: *Entity, stat_cache: *std.EnumArray(game_data.StatType, ?stat_util.StatValue)) ![]u8 {
        var writer = &self.stats_writer;
        writer.index = 0;

        stat_util.write(writer, stat_cache, self.allocator, .x, self.x);
        stat_util.write(writer, stat_cache, self.allocator, .y, self.y);
        
        return writer.buffer[0..writer.index];
    }
};
