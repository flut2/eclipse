const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const network_data = shared.network_data;
const utils = shared.utils;

const main = @import("../main.zig");
const maps = @import("../map/maps.zig");
const World = @import("../World.zig");
const stat_util = @import("stat_util.zig");

const Container = @This();

pub const inv_default: [9]u16 = @splat(std.math.maxInt(u16));
pub const inv_data_default: [9]network_data.ItemData = @splat(.{});

map_id: u32 = std.math.maxInt(u32),
data_id: u16 = std.math.maxInt(u16),
x: f32 = 0.0,
y: f32 = 0.0,
name: ?[]const u8 = null,
size_mult: f32 = 1.0,
stats_writer: utils.PacketWriter = .{},
owner_map_id: u32 = std.math.maxInt(u32),
inventory: [9]u16 = inv_default,
inv_data: [9]network_data.ItemData = inv_data_default,
disappear_time: i64 = 0,
data: *const game_data.ContainerData = undefined,
world_id: i32 = std.math.minInt(i32),
spawn: packed struct {
    command: bool = false,
} = .{},
free_name: bool = false,

pub fn init(self: *Container) !void {
    self.stats_writer.list = try .initCapacity(main.allocator, 32);
    self.data = game_data.container.from_id.getPtr(self.data_id) orelse {
        std.log.err("Could not find data for container with data id {}", .{self.data_id});
        return;
    };
    self.disappear_time = main.current_time + 30 * std.time.us_per_s;
}

pub fn deinit(self: *Container) !void {
    if (self.free_name) if (self.name) |name| main.allocator.free(name);
    self.stats_writer.list.deinit(main.allocator);
}

pub fn tick(self: *Container, time: i64, _: i64) !void {
    if (time >= self.disappear_time or std.mem.eql(u16, &self.inventory, &inv_default)) {
        const world = maps.worlds.getPtr(self.world_id) orelse return;
        try world.remove(Container, self);
        return;
    }
}

pub fn exportStats(self: *Container, cache: *[@typeInfo(network_data.ContainerStat).@"union".fields.len]?network_data.ContainerStat) ![]u8 {
    const writer = &self.stats_writer;
    writer.list.clearRetainingCapacity();

    const T = network_data.ContainerStat;
    inline for (.{
        T{ .x = self.x },
        T{ .y = self.y },
        T{ .size_mult = self.size_mult },
    }) |stat| stat_util.write(T, writer, cache, stat);
    if (self.name) |name| stat_util.write(T, writer, cache, .{ .name = name });

    inline for (0..9) |i| {
        const inv_tag: @typeInfo(T).@"union".tag_type.? = @enumFromInt(@intFromEnum(T.inv_0) + @as(u8, i));
        stat_util.write(T, writer, cache, @unionInit(T, @tagName(inv_tag), self.inventory[i]));
        const inv_data_tag: @typeInfo(T).@"union".tag_type.? = @enumFromInt(@intFromEnum(T.inv_data_0) + @as(u8, i));
        stat_util.write(T, writer, cache, @unionInit(T, @tagName(inv_data_tag), self.inv_data[i]));
    }

    return writer.list.items;
}
