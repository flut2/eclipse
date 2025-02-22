const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const network_data = shared.network_data;
const utils = shared.utils;
const u32f = utils.u32f;

const behavior_data = @import("../logic/behavior.zig");
const behavior_logic = @import("../logic/logic.zig");
const main = @import("../main.zig");
const maps = @import("../map/maps.zig");
const World = @import("../World.zig");
const Ally = @import("Ally.zig");
const stat_util = @import("stat_util.zig");

const Entity = @This();
map_id: u32 = std.math.maxInt(u32),
data_id: u16 = std.math.maxInt(u16),
x: f32 = 0.0,
y: f32 = 0.0,
hp: i32 = 0,
max_hp: i32 = 0,
name: []const u8 = &.{},
condition: utils.Condition = .{},
conditions_active: std.AutoArrayHashMapUnmanaged(utils.ConditionEnum, i64) = .empty,
conditions_to_remove: std.ArrayListUnmanaged(utils.ConditionEnum) = .empty,
damages_dealt: std.AutoArrayHashMapUnmanaged(u32, i32) = .empty,
stats_writer: utils.PacketWriter = .{},
data: *const game_data.EntityData = undefined,
world_id: i32 = std.math.minInt(i32),
spawned: bool = false,
behavior: ?*behavior_data.EntityBehavior = null,
storages: behavior_logic.Storages = .{},

pub fn init(self: *Entity) !void {
    if (behavior_data.entity_behavior_map.get(self.data_id)) |behav| {
        self.behavior = try main.allocator.create(behavior_data.EntityBehavior);
        self.behavior.?.* = behav;
        switch (self.behavior.?.*) {
            inline else => |*b| if (std.meta.hasFn(@TypeOf(b.*), "spawn")) try b.spawn(self),
        }
    }

    self.stats_writer.list = try .initCapacity(main.allocator, 32);

    self.data = game_data.entity.from_id.getPtr(self.data_id) orelse {
        std.log.err("Could not find data for entity with data id {}", .{self.data_id});
        return;
    };

    if (self.data.occupy_square or self.data.full_occupy or self.data.is_wall) {
        const ux = u32f(self.x);
        const uy = u32f(self.y);
        if (maps.worlds.getPtr(self.world_id)) |world| world.tiles[uy * world.w + ux].occupied = true;
    }

    self.hp = self.data.health;
    self.max_hp = self.data.health;
}

pub fn deinit(self: *Entity) !void {
    if (self.behavior) |behav| {
        switch (behav.*) {
            inline else => |*b| if (std.meta.hasFn(@TypeOf(b.*), "death")) try b.death(self),
        }

        main.allocator.destroy(behav);
    }

    if (self.data.occupy_square or self.data.full_occupy or self.data.is_wall) {
        const ux = u32f(self.x);
        const uy = u32f(self.y);
        if (maps.worlds.getPtr(self.world_id)) |world| world.tiles[uy * world.w + ux].occupied = false;
    }

    self.damages_dealt.deinit(main.allocator);
    self.stats_writer.list.deinit(main.allocator);
    main.allocator.free(self.name);
}

pub fn applyCondition(self: *Entity, condition: utils.ConditionEnum, duration: i64) void {
    if (self.conditions_active.getPtr(condition)) |current_duration| {
        if (duration > current_duration.*) current_duration.* = duration;
    } else self.conditions_active.put(main.allocator, condition, duration) catch main.oomPanic();
    self.condition.set(condition, true);
}

pub fn clearCondition(self: *Entity, condition: utils.ConditionEnum) void {
    _ = self.conditions_active.swapRemove(condition);
    self.condition.set(condition, false);
}

pub fn tick(self: *Entity, time: i64, dt: i64) !void {
    const world = maps.worlds.getPtr(self.world_id) orelse return;
    if (self.data.health > 0 and self.hp <= 0) try world.remove(Entity, self);

    self.conditions_to_remove.clearRetainingCapacity();
    for (self.conditions_active.values(), self.conditions_active.keys()) |*d, k| {
        if (d.* <= dt) {
            self.conditions_to_remove.append(main.allocator, k) catch main.oomPanic();
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

pub fn damage(self: *Entity, owner_type: network_data.ObjectType, owner_id: u32, phys_dmg: i32, magic_dmg: i32, true_dmg: i32) void {
    if (self.data.health == 0) return;
    const world = maps.worlds.getPtr(self.world_id) orelse return;

    const dmg = game_data.physDamage(phys_dmg, self.data.defense, self.condition) +
        game_data.magicDamage(magic_dmg, self.data.resistance, self.condition) +
        true_dmg;
    self.hp -= dmg;

    const map_id = switch (owner_type) {
        .player => owner_id,
        .ally => (world.find(Ally, owner_id) orelse return).owner_map_id,
        else => return,
    };

    const res = self.damages_dealt.getOrPut(main.allocator, map_id) catch return;
    if (res.found_existing) res.value_ptr.* += dmg else res.value_ptr.* = dmg;

    if (self.hp <= 0) {
        self.delete() catch return;
        return;
    }
}

pub fn exportStats(self: *Entity, cache: *[@typeInfo(network_data.EntityStat).@"union".fields.len]?network_data.EntityStat) ![]u8 {
    const writer = &self.stats_writer;
    writer.list.clearRetainingCapacity();

    const T = network_data.EntityStat;
    stat_util.write(T, writer, cache, .{ .x = self.x });
    stat_util.write(T, writer, cache, .{ .y = self.y });
    if (self.data.health > 0) stat_util.write(T, writer, cache, .{ .hp = self.hp });

    return writer.list.items;
}
