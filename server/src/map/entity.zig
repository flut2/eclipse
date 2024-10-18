const std = @import("std");
const shared = @import("shared");
const game_data = shared.game_data;
const network_data = shared.network_data;
const utils = shared.utils;
const stat_util = @import("stat_util.zig");
const behavior_logic = @import("../logic/logic.zig");
const behavior = @import("../logic/behavior.zig");

const World = @import("../world.zig").World;

pub const Entity = struct {
    map_id: u32 = std.math.maxInt(u32),
    data_id: u16 = std.math.maxInt(u16),
    x: f32 = 0.0,
    y: f32 = 0.0,
    hp: i32 = 0,
    stats_writer: utils.PacketWriter = .{},
    data: *const game_data.EntityData = undefined,
    world: *World = undefined,
    spawned: bool = false,
    behavior: ?*behavior.EntityBehavior = null,
    behavior_data: ?*anyopaque = undefined,
    storages: behavior_logic.EntityStorages = .{},

    pub fn init(self: *Entity, allocator: std.mem.Allocator) !void {
        if (behavior.entity_behavior_map.get(self.data_id)) |behav| {
            self.behavior = try allocator.create(behavior.EntityBehavior);
            self.behavior.?.* = behav;
            switch (self.behavior.?.*) {
                inline else => |*b| if (std.meta.hasFn(@TypeOf(b.*), "spawn")) try b.spawn(self),
            }
        }

        self.stats_writer.list = try .initCapacity(allocator, 32);

        self.data = game_data.entity.from_id.getPtr(self.data_id) orelse {
            std.log.err("Could not find data for entity with data id {}", .{self.data_id});
            return;
        };

        if (self.data.occupy_square or self.data.full_occupy) {
            const ux: u32 = @intFromFloat(self.x);
            const uy: u32 = @intFromFloat(self.y);
            self.world.tiles[uy * self.world.w + ux].occupied = true;
        }

        self.hp = self.data.health;
    }

    pub fn deinit(self: *Entity) !void {
        if (self.behavior) |behav| {
            switch (behav.*) {
                inline else => |*b| if (std.meta.hasFn(@TypeOf(b.*), "death")) try b.death(self),
            }

            self.world.allocator.destroy(behav);
        }

        if (self.data.occupy_square or self.data.full_occupy) {
            const ux: u32 = @intFromFloat(self.x);
            const uy: u32 = @intFromFloat(self.y);
            self.world.tiles[uy * self.world.w + ux].occupied = false;
        }

        self.stats_writer.list.deinit(self.world.allocator);
    }

    pub fn tick(self: *Entity, time: i64, dt: i64) !void {
        if (self.data.health > 0 and self.hp <= 0) try self.world.remove(Entity, self);
        if (self.behavior) |behav| switch (behav.*) {
            inline else => |*b| if (std.meta.hasFn(@TypeOf(b.*), "tick")) try b.tick(self, time, dt),
        };
    }

    pub fn exportStats(self: *Entity, cache: *[@typeInfo(network_data.EntityStat).@"union".fields.len]?network_data.EntityStat) ![]u8 {
        const writer = &self.stats_writer;
        writer.list.clearRetainingCapacity();

        const allocator = self.world.allocator;
        stat_util.write(network_data.EntityStat, allocator, writer, cache, .{ .x = self.x });
        stat_util.write(network_data.EntityStat, allocator, writer, cache, .{ .y = self.y });
        if (self.data.health > 0) stat_util.write(network_data.EntityStat, allocator, writer, cache, .{ .hp = self.hp });

        return writer.list.items;
    }
};
