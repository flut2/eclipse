const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const network_data = shared.network_data;
const utils = shared.utils;
const i32f = utils.i32f;
const f32i = utils.f32i;

const behavior_data = @import("../logic/behavior.zig");
const behavior_logic = @import("../logic/logic.zig");
const main = @import("../main.zig");
const maps = @import("../map/maps.zig");
const World = @import("../World.zig");
const stat_util = @import("stat_util.zig");

const Ally = @This();

map_id: u32 = std.math.maxInt(u32),
data_id: u16 = std.math.maxInt(u16),
x: f32 = 0.0,
y: f32 = 0.0,
spawn_x: f32 = 0.0,
spawn_y: f32 = 0.0,
size_mult: f32 = 1.0,
hit_multiplier: f32 = 1.0,
condition: utils.Condition = .{},
hp: i32 = 0,
max_hp: i32 = 0,
defense: i32 = 0,
resistance: i32 = 0,
owner_map_id: u32 = std.math.maxInt(u32),
disappear_time: i64 = std.math.maxInt(i64),
stats_writer: utils.PacketWriter = .{},
data: *const game_data.AllyData = undefined,
world_id: i32 = std.math.minInt(i32),
spawned: bool = false,
behavior: ?*behavior_data.AllyBehavior = null,
storages: behavior_logic.Storages = .{},

pub fn init(self: *Ally) !void {
    if (behavior_data.ally_behavior_map.get(self.data_id)) |behav| {
        self.behavior = try main.allocator.create(behavior_data.AllyBehavior);
        self.behavior.?.* = behav;
        switch (self.behavior.?.*) {
            inline else => |*b| if (std.meta.hasFn(@TypeOf(b.*), "spawn")) try b.spawn(self),
        }
    }

    self.stats_writer.list = try .initCapacity(main.allocator, 32);
    self.data = game_data.ally.from_id.getPtr(self.data_id) orelse {
        std.log.err("Could not find data for ally with data id {}", .{self.data_id});
        return;
    };
    self.size_mult = self.data.size_mult;
    self.max_hp = self.data.health;
    self.hp = self.max_hp;
    self.defense = self.data.defense;
    self.resistance = self.data.resistance;
    self.spawn_x = self.x;
    self.spawn_y = self.y;
}

pub fn deinit(self: *Ally) !void {
    if (self.behavior) |behav| {
        switch (behav.*) {
            inline else => |*b| if (std.meta.hasFn(@TypeOf(b.*), "death")) try b.death(self),
        }

        main.allocator.destroy(behav);
    }

    self.stats_writer.list.deinit(main.allocator);
}

pub fn delete(self: *Ally) !void {
    const world = maps.worlds.getPtr(self.world_id) orelse return;
    try world.remove(Ally, self);
}

pub fn damage(
    self: *Ally,
    owner_type: network_data.ObjectType,
    _: u32,
    phys_dmg: i32,
    magic_dmg: i32,
    true_dmg: i32,
    _: ?[]const game_data.TimedCondition,
) void {
    if (owner_type != .enemy) return; // something saner later

    const dmg = i32f(f32i(game_data.physDamage(
        phys_dmg,
        self.data.defense,
        self.condition,
    ) + game_data.magicDamage(
        magic_dmg,
        self.data.resistance,
        self.condition,
    ) + true_dmg) * self.hit_multiplier);
    self.hp -= dmg;

    if (self.hp <= 0) self.delete() catch return;
}

pub fn tick(self: *Ally, time: i64, dt: i64) !void {
    if (time >= self.disappear_time) {
        try self.delete();
        return;
    }

    if (self.behavior) |behav| switch (behav.*) {
        inline else => |*b| if (std.meta.hasFn(@TypeOf(b.*), "tick")) try b.tick(self, time, dt),
    };
}

pub fn exportStats(self: *Ally, cache: *[@typeInfo(network_data.AllyStat).@"union".fields.len]?network_data.AllyStat) ![]u8 {
    const writer = &self.stats_writer;
    writer.list.clearRetainingCapacity();

    const T = network_data.AllyStat;
    stat_util.write(T, writer, cache, .{ .x = self.x });
    stat_util.write(T, writer, cache, .{ .y = self.y });
    stat_util.write(T, writer, cache, .{ .size_mult = self.size_mult });
    stat_util.write(T, writer, cache, .{ .condition = self.condition });
    stat_util.write(T, writer, cache, .{ .hp = self.hp });
    stat_util.write(T, writer, cache, .{ .max_hp = self.max_hp });
    stat_util.write(T, writer, cache, .{ .owner_map_id = self.owner_map_id });

    return writer.list.items;
}
