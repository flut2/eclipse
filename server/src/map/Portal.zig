const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const network_data = shared.network_data;
const utils = shared.utils;

const main = @import("../main.zig");
const World = @import("../World.zig");
const stat_util = @import("stat_util.zig");

const Portal = @This();

map_id: u32 = std.math.maxInt(u32),
data_id: u16 = std.math.maxInt(u16),
x: f32 = 0.0,
y: f32 = 0.0,
disappear_time: i64 = std.math.maxInt(i64),
stats_writer: utils.PacketWriter = .{},
data: *const game_data.PortalData = undefined,
world: *World = undefined,
spawned: bool = false,

pub fn init(self: *Portal) !void {
    self.stats_writer.list = try .initCapacity(main.allocator, 32);
    self.data = game_data.portal.from_id.getPtr(self.data_id) orelse {
        std.log.err("Could not find data for portal with data id {}", .{self.data_id});
        return;
    };
    if (@import("maps.zig").maps.get(self.data_id)) |map| {
        if (map.details.id == 0) self.disappear_time = main.current_time + 30 * std.time.us_per_s;
    }
}

pub fn deinit(self: *Portal) !void {
    self.stats_writer.list.deinit(main.allocator);
}

pub fn tick(self: *Portal, time: i64, _: i64) !void {
    if (time >= self.disappear_time) {
        try self.world.remove(Portal, self);
        return;
    }
}

pub fn exportStats(self: *Portal, cache: *[@typeInfo(network_data.PortalStat).@"union".fields.len]?network_data.PortalStat) ![]u8 {
    const writer = &self.stats_writer;
    writer.list.clearRetainingCapacity();

    const T = network_data.PortalStat;
    stat_util.write(T, writer, cache, .{ .x = self.x });
    stat_util.write(T, writer, cache, .{ .y = self.y });

    return writer.list.items;
}
