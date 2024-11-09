const std = @import("std");
const shared = @import("shared");
const network_data = shared.network_data;
const game_data = shared.game_data;
const utils = shared.utils;
const stat_util = @import("stat_util.zig");
const behavior_logic = @import("../logic/logic.zig");
const behavior_data = @import("../logic/behavior.zig");
const main = @import("../main.zig");

const World = @import("../World.zig");
const Player = @import("Player.zig");
const Ally = @import("Ally.zig");
const Enemy = @This();

map_id: u32 = std.math.maxInt(u32),
data_id: u16 = std.math.maxInt(u16),
x: f32 = 0.0,
y: f32 = 0.0,
max_hp: i32 = 100,
hp: i32 = 100,
size_mult: f32 = 1.0,
name: ?[]const u8 = null,
next_proj_index: u8 = 0,
projectiles: [256]?u32 = @splat(null),
stats_writer: utils.PacketWriter = .{},
condition: utils.Condition = .{},
damages_dealt: std.AutoArrayHashMapUnmanaged(u32, i32) = .empty,
conditions_active: std.AutoArrayHashMapUnmanaged(utils.ConditionEnum, i64) = .empty,
conditions_to_remove: std.ArrayListUnmanaged(utils.ConditionEnum) = .empty,
data: *const game_data.EnemyData = undefined,
world: *World = undefined,
spawned: bool = false,
behavior: ?*behavior_data.EnemyBehavior = null,
storages: behavior_logic.Storages = .{},

pub fn init(self: *Enemy) !void {
    if (behavior_data.enemy_behavior_map.get(self.data_id)) |behav| {
        self.behavior = try main.allocator.create(behavior_data.EnemyBehavior);
        self.behavior.?.* = behav;
        switch (self.behavior.?.*) {
            inline else => |*b| if (std.meta.hasFn(@TypeOf(b.*), "spawn")) try b.spawn(self),
        }
    }

    self.stats_writer.list = try .initCapacity(main.allocator, 32);

    self.data = game_data.enemy.from_id.getPtr(self.data_id) orelse {
        std.log.err("Could not find data for enemy with data id {}", .{self.data_id});
        return;
    };
    self.hp = @intCast(self.data.health);
    self.max_hp = @intCast(self.data.health);
}

pub fn deinit(self: *Enemy) !void {
    if (self.behavior) |behav| {
        switch (behav.*) {
            inline else => |*b| if (std.meta.hasFn(@TypeOf(b.*), "death")) try b.death(self),
        }

        main.allocator.destroy(behav);
    }

    self.storages.deinit();
    self.damages_dealt.deinit(main.allocator);
    self.stats_writer.list.deinit(main.allocator);
}

pub fn applyCondition(self: *Enemy, condition: utils.ConditionEnum, duration: i64) !void {
    if (self.conditions_active.getPtr(condition)) |current_duration| {
        if (duration > current_duration.*)
            current_duration.* = duration;
    } else try self.conditions_active.put(main.allocator, condition, duration);
    self.condition.set(condition, true);
}

pub fn clearCondition(self: *Enemy, condition: utils.ConditionEnum) void {
    _ = self.conditions_active.swapRemove(condition);
    self.condition.set(condition, false);
}

pub fn delete(self: *Enemy) !void {
    try self.world.remove(Enemy, self);
}

pub fn tick(self: *Enemy, time: i64, dt: i64) !void {
    if (self.data.health > 0 and self.hp <= 0) try self.delete();

    self.conditions_to_remove.clearRetainingCapacity();
    for (self.conditions_active.values(), self.conditions_active.keys()) |*d, k| {
        if (d.* <= dt) {
            try self.conditions_to_remove.append(main.allocator, k);
            continue;
        }

        d.* -= dt;
    }

    for (self.conditions_to_remove.items) |c| {
        self.condition.set(c, false);
        _ = self.conditions_active.swapRemove(c);
    }

    if (self.behavior) |behav| switch (behav.*) {
        inline else => |*b| if (std.meta.hasFn(@TypeOf(b.*), "tick")) try b.tick(self, time, dt),
    };
}

pub fn damage(self: *Enemy, owner_type: network_data.ObjectType, owner_id: u32, phys_dmg: i32, magic_dmg: i32, true_dmg: i32) void {
    if (self.data.health == 0) return;

    const dmg = game_data.physDamage(phys_dmg, self.data.defense, self.condition) +
        game_data.magicDamage(magic_dmg, self.data.resistance, self.condition) +
        true_dmg;
    self.hp -= dmg;
    if (self.hp <= 0) {
        self.delete() catch return;
        return;
    }

    const map_id = switch (owner_type) {
        .player => owner_id,
        .ally => (self.world.find(Ally, owner_id) orelse return).owner_map_id,
        else => return,
    };

    const res = self.damages_dealt.getOrPut(main.allocator, map_id) catch return;
    if (res.found_existing) res.value_ptr.* += dmg else res.value_ptr.* = dmg;
}

pub fn exportStats(self: *Enemy, cache: *[@typeInfo(network_data.EnemyStat).@"union".fields.len]?network_data.EnemyStat) ![]u8 {
    const writer = &self.stats_writer;
    writer.list.clearRetainingCapacity();

    const T = network_data.EnemyStat;
    stat_util.write(T, writer, cache, .{ .x = self.x });
    stat_util.write(T, writer, cache, .{ .y = self.y });
    stat_util.write(T, writer, cache, .{ .size_mult = self.size_mult });
    if (self.name) |name| stat_util.write(T, writer, cache, .{ .name = name });
    stat_util.write(T, writer, cache, .{ .hp = self.hp });
    stat_util.write(T, writer, cache, .{ .max_hp = self.max_hp });
    stat_util.write(T, writer, cache, .{ .condition = self.condition });

    return writer.list.items;
}
