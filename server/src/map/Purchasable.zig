const std = @import("std");
const main = @import("../main.zig");
const shared = @import("shared");
const game_data = shared.game_data;
const network_data = shared.network_data;
const utils = shared.utils;
const stat_util = @import("stat_util.zig");

const World = @import("../World.zig");
const Purchasable = @This();

map_id: u32 = std.math.maxInt(u32),
data_id: u16 = std.math.maxInt(u16),
x: f32 = 0.0,
y: f32 = 0.0,
size_mult: f32 = 1.0,
name: []const u8 = "",
cost: u32 = 0,
currency: game_data.Currency = .gold,
stats_writer: utils.PacketWriter = .{},
data: *const game_data.PurchasableData = undefined,
world: *World = undefined,
spawned: bool = false,

pub fn init(self: *Purchasable) !void {
    self.stats_writer.list = try .initCapacity(main.allocator, 32);
    self.data = game_data.purchasable.from_id.getPtr(self.data_id) orelse {
        std.log.err("Could not find data for purchasable with data id {}", .{self.data_id});
        return;
    };
}

pub fn deinit(self: *Purchasable) !void {
    self.stats_writer.list.deinit(main.allocator);
}

pub fn tick(_: *Purchasable, _: i64, _: i64) !void {}

pub fn exportStats(self: *Purchasable, cache: *[@typeInfo(network_data.PurchasableStat).@"union".fields.len]?network_data.PurchasableStat) ![]u8 {
    const writer = &self.stats_writer;
    writer.list.clearRetainingCapacity();

    const T = network_data.PurchasableStat;
    stat_util.write(T, writer, cache, .{ .x = self.x });
    stat_util.write(T, writer, cache, .{ .y = self.y });
    stat_util.write(T, writer, cache, .{ .size_mult = self.size_mult });
    stat_util.write(T, writer, cache, .{ .name = self.name });
    stat_util.write(T, writer, cache, .{ .cost = self.cost });
    stat_util.write(T, writer, cache, .{ .currency = self.currency });

    return writer.list.items;
}
