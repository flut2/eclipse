const std = @import("std");

const shared = @import("shared");
const network_data = shared.network_data;
const game_data = shared.game_data;
const utils = shared.utils;
const f32i = utils.f32i;
const i32f = utils.i32f;

const behavior_data = @import("../logic/behavior.zig");
const behavior_logic = @import("../logic/logic.zig");
const main = @import("../main.zig");
const maps = @import("../map/maps.zig");
const World = @import("../World.zig");
const Ally = @import("Ally.zig");
const Entity = @import("Entity.zig");
const Player = @import("Player.zig");
const stat_util = @import("stat_util.zig");

const Enemy = @This();

map_id: u32 = std.math.maxInt(u32),
data_id: u16 = std.math.maxInt(u16),
x: f32 = 0.0,
y: f32 = 0.0,
spawn_x: f32 = 0.0,
spawn_y: f32 = 0.0,
max_hp: i32 = 100,
hp: i32 = 100,
size_mult: f32 = 1.0,
obelisk_map_id: u32 = std.math.maxInt(u32),
name: ?[]const u8 = null,
next_proj_index: u8 = 0,
projectiles: [256]?u32 = @splat(null),
stats_writer: utils.PacketWriter = .{},
condition: utils.Condition = .{},
damages_dealt: std.AutoArrayHashMapUnmanaged(u32, i32) = .empty,
conditions_active: std.AutoArrayHashMapUnmanaged(utils.ConditionEnum, i64) = .empty,
conditions_to_remove: std.ArrayListUnmanaged(utils.ConditionEnum) = .empty,
data: *const game_data.EnemyData = undefined,
world_id: i32 = std.math.minInt(i32),
spawn: packed struct {
    command: bool = false,
    biome_1: bool = false,
    biome_2: bool = false,
    biome_3: bool = false,
    biome_1_encounter: bool = false,
    biome_2_encounter: bool = false,
    biome_3_encounter: bool = false,
} = .{},
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
    self.spawn_x = self.x;
    self.spawn_y = self.y;
}

pub fn deinit(self: *Enemy) !void {
    if (self.behavior) |behav| {
        switch (behav.*) {
            inline else => |*b| if (std.meta.hasFn(@TypeOf(b.*), "death")) try b.death(self),
        }

        main.allocator.destroy(behav);
    }

    const world = maps.worlds.getPtr(self.world_id) orelse return;
    if (self.spawn.biome_1_encounter) world.biome_1_encounter_alive = false;
    if (self.spawn.biome_2_encounter) world.biome_2_encounter_alive = false;
    if (self.spawn.biome_3_encounter) world.biome_3_encounter_alive = false;
    if (self.spawn.biome_1 and world.biome_1_spawn > 0) {
        world.biome_1_spawn -= 1;
        if (!world.biome_1_encounter_alive and
            utils.rng.random().float(f32) <= world.details.biome_1_encounter_chance)
        {
            var iter = world.regions.iterator();
            while (iter.next()) |entry| {
                const data = game_data.region.from_id.get(entry.key_ptr.*) orelse continue;
                if (std.mem.eql(u8, data.name, "Biome 1 Encounter Spawn")) {
                    const mobs = world.details.biome_1_encounters orelse continue;
                    const rand_point = entry.value_ptr.*[utils.rng.next() % entry.value_ptr.len];
                    const rand_mob = mobs[utils.rng.next() % mobs.len];
                    const mob_data = game_data.enemy.from_name.get(rand_mob) orelse {
                        std.log.err("Spawning biome 1 encounter \"{s}\" failed, no data found", .{rand_mob});
                        continue;
                    };
                    _ = try world.add(Enemy, .{
                        .x = f32i(rand_point.x) + 0.5,
                        .y = f32i(rand_point.y) + 0.5,
                        .data_id = mob_data.id,
                        .spawn = .{ .biome_1_encounter = true },
                    });
                    world.biome_1_encounter_alive = true;
                    var buf: [256]u8 = undefined;
                    const msg = try std.fmt.bufPrint(
                        &buf,
                        "A mighty \"{s}\" has spawned in {s}",
                        .{ mob_data.name, world.details.biome_1_name },
                    );
                    for (world.listForType(Player).items) |*player| {
                        player.client.sendPacket(.{ .text = .{
                            .name = "",
                            .obj_type = .entity,
                            .map_id = std.math.maxInt(u32),
                            .bubble_time = 0,
                            .recipient = "",
                            .text = msg,
                            .name_color = 0xCC00CC,
                            .text_color = 0xFF99FF,
                        } });
                    }
                    break;
                }
            }
        }
    }
    if (self.spawn.biome_2 and world.biome_2_spawn > 0) {
        world.biome_2_spawn -= 1;
        if (!world.biome_2_encounter_alive and
            utils.rng.random().float(f32) <= world.details.biome_2_encounter_chance)
        {
            var iter = world.regions.iterator();
            while (iter.next()) |entry| {
                const data = game_data.region.from_id.get(entry.key_ptr.*) orelse continue;
                if (std.mem.eql(u8, data.name, "Biome 2 Encounter Spawn")) {
                    const mobs = world.details.biome_2_encounters orelse continue;
                    const rand_point = entry.value_ptr.*[utils.rng.next() % entry.value_ptr.len];
                    const rand_mob = mobs[utils.rng.next() % mobs.len];
                    const mob_data = game_data.enemy.from_name.get(rand_mob) orelse {
                        std.log.err("Spawning biome 2 encounter \"{s}\" failed, no data found", .{rand_mob});
                        continue;
                    };
                    _ = try world.add(Enemy, .{
                        .x = f32i(rand_point.x) + 0.5,
                        .y = f32i(rand_point.y) + 0.5,
                        .data_id = mob_data.id,
                        .spawn = .{ .biome_2_encounter = true },
                    });
                    world.biome_2_encounter_alive = true;
                    var buf: [256]u8 = undefined;
                    const msg = try std.fmt.bufPrint(
                        &buf,
                        "A mighty \"{s}\" has spawned in {s}",
                        .{ mob_data.name, world.details.biome_2_name },
                    );
                    for (world.listForType(Player).items) |*player| {
                        player.client.sendPacket(.{ .text = .{
                            .name = "",
                            .obj_type = .entity,
                            .map_id = std.math.maxInt(u32),
                            .bubble_time = 0,
                            .recipient = "",
                            .text = msg,
                            .name_color = 0xCC00CC,
                            .text_color = 0xFF99FF,
                        } });
                    }
                    break;
                }
            }
        }
    }
    if (self.spawn.biome_3 and world.biome_3_spawn > 0) {
        world.biome_3_spawn -= 1;
        if (!world.biome_3_encounter_alive and
            utils.rng.random().float(f32) <= world.details.biome_3_encounter_chance)
        {
            var iter = world.regions.iterator();
            while (iter.next()) |entry| {
                const data = game_data.region.from_id.get(entry.key_ptr.*) orelse continue;
                if (std.mem.eql(u8, data.name, "Biome 3 Encounter Spawn")) {
                    const mobs = world.details.biome_3_encounters orelse continue;
                    const rand_point = entry.value_ptr.*[utils.rng.next() % entry.value_ptr.len];
                    const rand_mob = mobs[utils.rng.next() % mobs.len];
                    const mob_data = game_data.enemy.from_name.get(rand_mob) orelse {
                        std.log.err("Spawning biome 3 encounter \"{s}\" failed, no data found", .{rand_mob});
                        continue;
                    };
                    _ = try world.add(Enemy, .{
                        .x = f32i(rand_point.x) + 0.5,
                        .y = f32i(rand_point.y) + 0.5,
                        .data_id = mob_data.id,
                        .spawn = .{ .biome_3_encounter = true },
                    });
                    world.biome_3_encounter_alive = true;
                    var buf: [256]u8 = undefined;
                    const msg = try std.fmt.bufPrint(
                        &buf,
                        "A mighty \"{s}\" has spawned in {s}",
                        .{ mob_data.name, world.details.biome_3_name },
                    );
                    for (world.listForType(Player).items) |*player| {
                        player.client.sendPacket(.{ .text = .{
                            .name = "",
                            .obj_type = .entity,
                            .map_id = std.math.maxInt(u32),
                            .bubble_time = 0,
                            .recipient = "",
                            .text = msg,
                            .name_color = 0xCC00CC,
                            .text_color = 0xFF99FF,
                        } });
                    }
                    break;
                }
            }
        }
    }

    var iter = self.damages_dealt.iterator();
    while (iter.next()) |entry| {
        const player = world.findRef(Player, entry.key_ptr.*) orelse continue;
        const dmg = entry.value_ptr.*;
        if (player.hasCard("Vampiric Enchantment")) {
            const old_hp = player.hp;
            player.hp = @min(player.data.stats.health, player.hp + @min(200, @divFloor(dmg, 1000)));
            const hp_delta = player.hp - old_hp;
            var buf: [64]u8 = undefined;
            player.client.sendPacket(.{ .notification = .{
                .obj_type = .player,
                .map_id = player.map_id,
                .message = std.fmt.bufPrint(&buf, "+{}", .{hp_delta}) catch return,
                .color = 0x00FF00,
            } });

            player.client.sendPacket(.{ .show_effect = .{
                .eff_type = .potion,
                .obj_type = .player,
                .map_id = player.map_id,
                .x1 = 0,
                .y1 = 0,
                .x2 = 0,
                .y2 = 0,
                .color = 0x00FF00,
            } });
        }

        if (player.hasCard("Ritual Sacrifice")) {
            const old_mp = player.mp;
            player.mp = @min(player.data.stats.mana, player.mp + @min(100, @divFloor(dmg, 4000)));
            const mp_delta = player.hp - old_mp;
            var buf: [64]u8 = undefined;
            player.client.sendPacket(.{ .notification = .{
                .obj_type = .player,
                .map_id = player.map_id,
                .message = std.fmt.bufPrint(&buf, "+{}", .{mp_delta}) catch return,
                .color = 0x0000FF,
            } });

            player.client.sendPacket(.{ .show_effect = .{
                .eff_type = .potion,
                .obj_type = .player,
                .map_id = player.map_id,
                .x1 = 0,
                .y1 = 0,
                .x2 = 0,
                .y2 = 0,
                .color = 0x0000FF,
            } });
        }
    }

    addSoul: {
        _ = try world.add(Entity, .{
            .x = self.x,
            .y = self.y,
            .data_id = (game_data.entity.from_name.get("Enemy Soul") orelse break :addSoul).id,
            .disappear_time = main.current_time + 30 * std.time.us_per_s,
        });
    }

    self.storages.deinit();
    self.damages_dealt.deinit(main.allocator);
    self.stats_writer.list.deinit(main.allocator);
}

pub fn applyCondition(self: *Enemy, condition: utils.ConditionEnum, duration: i64) void {
    if (self.conditions_active.getPtr(condition)) |current_duration| {
        if (duration > current_duration.*) current_duration.* = duration;
    } else self.conditions_active.put(main.allocator, condition, duration) catch main.oomPanic();
    self.condition.set(condition, true);
}

pub fn clearCondition(self: *Enemy, condition: utils.ConditionEnum) void {
    _ = self.conditions_active.swapRemove(condition);
    self.condition.set(condition, false);
}

pub fn delete(self: *Enemy) !void {
    const world = maps.worlds.getPtr(self.world_id) orelse return;
    try world.remove(Enemy, self);
}

pub fn tick(self: *Enemy, time: i64, dt: i64) !void {
    if (self.data.health > 0 and self.hp <= 0) try self.delete();

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

pub fn damage(
    self: *Enemy,
    owner_type: network_data.ObjectType,
    owner_id: u32,
    phys_dmg: i32,
    magic_dmg: i32,
    true_dmg: i32,
    conditions: ?[]const game_data.TimedCondition,
) void {
    if (self.data.health == 0) return;
    const world = maps.worlds.getPtr(self.world_id) orelse return;

    var fdmg = f32i(game_data.physDamage(
        phys_dmg,
        self.data.defense,
        self.condition,
    ) + game_data.magicDamage(
        magic_dmg,
        self.data.resistance,
        self.condition,
    ) + true_dmg);
    if (owner_type == .player) {
        if (world.findCon(Player, owner_id)) |player| fdmg *= player.damage_multiplier;
    }
    const dmg = i32f(fdmg);
    if (self.condition.encased_in_stone) {
        if (world.findRef(Ally, self.obelisk_map_id)) |obelisk| {
            obelisk.damage(.enemy, self.map_id, 0, 0, dmg, null);
        } else self.clearCondition(.encased_in_stone);
    }
    self.hp -= dmg;

    const map_id = switch (owner_type) {
        .player => owner_id,
        .ally => (world.findCon(Ally, owner_id) orelse return).owner_map_id,
        else => return,
    };

    if (conditions) |conds| for (conds) |cond| self.applyCondition(cond.type, i32f(cond.duration * std.time.us_per_s));

    const res = self.damages_dealt.getOrPut(main.allocator, map_id) catch return;
    if (res.found_existing) res.value_ptr.* += dmg else res.value_ptr.* = dmg;

    if (self.hp <= 0) {
        self.delete() catch return;
        return;
    }
}

pub fn exportStats(self: *Enemy, cache: *[@typeInfo(network_data.EnemyStat).@"union".fields.len]?network_data.EnemyStat) ![]u8 {
    const writer = &self.stats_writer;
    writer.list.clearRetainingCapacity();

    const T = network_data.EnemyStat;
    inline for (.{
        T{ .x = self.x },
        T{ .y = self.y },
        T{ .size_mult = self.size_mult },
        T{ .hp = self.hp },
        T{ .max_hp = self.max_hp },
        T{ .condition = self.condition },
    }) |stat| stat_util.write(T, writer, cache, stat);
    if (self.name) |name| stat_util.write(T, writer, cache, .{ .name = name });

    return writer.list.items;
}
