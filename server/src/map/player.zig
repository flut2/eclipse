const std = @import("std");
const shared = @import("shared");
const game_data = shared.game_data;
const utils = shared.utils;
const network_data = shared.network_data;
const db = @import("../db.zig");
const main = @import("../main.zig");
const settings = @import("../settings.zig");
const client = @import("../client.zig");
const stat_util = @import("stat_util.zig");

const Entity = @import("entity.zig").Entity;
const Enemy = @import("enemy.zig").Enemy;
const Portal = @import("portal.zig").Portal;
const Container = @import("container.zig").Container;
const World = @import("../world.zig").World;
const Client = client.Client;

pub const Player = struct {
    pub const health_stat = 0;
    pub const mana_stat = 1;
    pub const strength_stat = 2;
    pub const wit_stat = 3;
    pub const defense_stat = 4;
    pub const resistance_stat = 5;
    pub const speed_stat = 6;
    pub const stamina_stat = 7;
    pub const intelligence_stat = 8;
    pub const penetration_stat = 9;
    pub const piercing_stat = 10;
    pub const haste_stat = 11;
    pub const tenacity_stat = 12;

    map_id: u32 = std.math.maxInt(u32),
    data_id: u16 = std.math.maxInt(u16),

    acc_data: db.AccountData = undefined,
    char_data: db.CharacterData = undefined,

    x: f32 = -1.0,
    y: f32 = -1.0,
    name: []const u8 = &.{},
    rank: network_data.Rank = .default,
    aether: u8 = 0,
    spirits_communed: u32 = 0,
    hp: i32 = 100,
    mp: i32 = 0,
    hp_regen: f32 = 0.0,
    mp_regen: f32 = 0.0,
    stats: [13]i32 = @splat(0),
    stat_boosts: [13]i32 = @splat(0),
    inventory: [22]u16 = @splat(std.math.maxInt(u16)),
    muted_until: i64 = 0,
    condition: utils.Condition = .{},
    caches: struct {
        player: std.AutoHashMapUnmanaged(u32, [@typeInfo(network_data.PlayerStat).@"union".fields.len]?network_data.PlayerStat) = .empty,
        entity: std.AutoHashMapUnmanaged(u32, [@typeInfo(network_data.EntityStat).@"union".fields.len]?network_data.EntityStat) = .empty,
        enemy: std.AutoHashMapUnmanaged(u32, [@typeInfo(network_data.EnemyStat).@"union".fields.len]?network_data.EnemyStat) = .empty,
        portal: std.AutoHashMapUnmanaged(u32, [@typeInfo(network_data.PortalStat).@"union".fields.len]?network_data.PortalStat) = .empty,
        container: std.AutoHashMapUnmanaged(u32, [@typeInfo(network_data.ContainerStat).@"union".fields.len]?network_data.ContainerStat) = .empty,
    } = .{},
    conditions_active: std.AutoArrayHashMapUnmanaged(utils.ConditionEnum, i64) = .empty,
    conditions_to_remove: std.ArrayListUnmanaged(utils.ConditionEnum) = .empty,
    tiles: std.ArrayListUnmanaged(network_data.TileData) = .empty,
    tiles_seen: std.AutoHashMapUnmanaged(u32, u16) = .empty,
    objs: struct {
        entity: std.ArrayListUnmanaged(network_data.ObjectData) = .empty,
        enemy: std.ArrayListUnmanaged(network_data.ObjectData) = .empty,
        player: std.ArrayListUnmanaged(network_data.ObjectData) = .empty,
        portal: std.ArrayListUnmanaged(network_data.ObjectData) = .empty,
        container: std.ArrayListUnmanaged(network_data.ObjectData) = .empty,
    } = .{},
    drops: struct {
        entity: std.ArrayListUnmanaged(u32) = .empty,
        enemy: std.ArrayListUnmanaged(u32) = .empty,
        player: std.ArrayListUnmanaged(u32) = .empty,
        portal: std.ArrayListUnmanaged(u32) = .empty,
        container: std.ArrayListUnmanaged(u32) = .empty,
    } = .{},
    projectiles: [256]?u32 = @splat(null),
    stats_writer: utils.PacketWriter = .{},
    data: *const game_data.ClassData = undefined,
    client: *Client = undefined,
    world: *World = undefined,

    pub fn init(self: *Player, allocator: std.mem.Allocator) !void {
        self.stats_writer.list = try .initCapacity(allocator, 256);

        self.name = try allocator.dupe(u8, try self.acc_data.get(.name));
        self.data_id = try self.char_data.get(.class_id);
        self.data = game_data.class.from_id.getPtr(self.data_id) orelse {
            std.log.err("Could not find class data for player with data id {}", .{self.data_id});
            return;
        };

        const hwid_mute_expiry = blk: {
            const hwid = self.acc_data.get(.hwid) catch break :blk 0;
            var muted_hwids = db.MutedHwids.init(allocator);
            defer muted_hwids.deinit();
            break :blk main.current_time + (muted_hwids.ttl(hwid) catch break :blk 0);
        };

        const acc_mute_expiry = self.acc_data.get(.mute_expiry) catch 0;

        self.muted_until = @max(hwid_mute_expiry, acc_mute_expiry);

        self.rank = try self.acc_data.get(.rank);
        self.aether = try self.char_data.get(.aether);
        self.spirits_communed = try self.char_data.get(.spirits_communed);
        self.hp = try self.char_data.get(.hp);
        self.mp = try self.char_data.get(.mp);

        self.stats = try self.char_data.get(.stats);
        self.inventory = try self.char_data.get(.items);

        self.recalculateItems();

        self.moveToSpawn();
    }

    pub fn deinit(self: *Player) !void {
        try self.save();

        self.char_data.deinit();
        self.acc_data.deinit();

        const allocator = self.world.allocator;
        self.tiles.deinit(allocator);
        self.tiles_seen.deinit(allocator);

        inline for (@typeInfo(@TypeOf(self.objs)).@"struct".fields) |field| {
            @field(self.objs, field.name).deinit(allocator);
        }

        inline for (@typeInfo(@TypeOf(self.caches)).@"struct".fields) |field| {
            @field(self.caches, field.name).deinit(allocator);
        }

        allocator.free(self.name);
        self.stats_writer.list.deinit(allocator);
    }

    pub fn moveToSpawn(self: *Player) void {
        const spawn_points = self.world.regions.get(game_data.region.from_name.get("Spawn").?.id);
        if (spawn_points == null or spawn_points.?.len == 0) {
            std.log.err("Could not find spawn point for player with data id {}", .{self.data_id});
            return;
        }

        const rand_point = spawn_points.?[utils.rng.random().intRangeAtMost(usize, 0, spawn_points.?.len - 1)];
        const tile = self.world.tiles[rand_point.y * self.world.w + rand_point.x];
        if (tile.data_id == std.math.maxInt(u16) or tile.data.no_walk or tile.occupied) {
            std.log.err("Spawn point {} was not walkable for player with data id {}", .{ rand_point, self.data_id });
            return;
        }
        self.x = @as(f32, @floatFromInt(rand_point.x)) + 0.5;
        self.y = @as(f32, @floatFromInt(rand_point.y)) + 0.5;
    }

    pub fn applyCondition(self: *Player, condition: utils.ConditionEnum, duration: i64) !void {
        if (self.conditions_active.getPtr(condition)) |current_duration| {
            if (duration > current_duration.*)
                current_duration.* = duration;
        } else try self.conditions_active.put(self.world.allocator, condition, duration);
        self.condition.set(condition, true);
    }

    pub fn clearCondition(self: *Player, condition: utils.ConditionEnum) void {
        _ = self.conditions_active.swapRemove(condition);
        self.condition.set(condition, false);
    }

    pub fn save(self: *Player) !void {
        try self.char_data.set(.{ .hp = self.hp });
        try self.char_data.set(.{ .mp = self.mp });
        try self.char_data.set(.{ .aether = self.aether });
        try self.char_data.set(.{ .spirits_communed = self.spirits_communed });
        try self.char_data.set(.{ .items = self.inventory });
        try self.char_data.set(.{ .stats = self.stats });
    }

    pub fn death(self: *Player, killer: []const u8) !void {
        if (self.rank == .admin) return;
        self.client.queuePacket(.{ .death = .{ .killer_name = killer } });
        self.client.sameThreadShutdown();
    }

    pub fn addExp(self: *Player, amount: u32) void {
        self.spirits_communed += amount;
        const spirit_goal = game_data.spiritGoal(self.aether);
        if (self.spirits_communed >= spirit_goal) {
            self.spirits_communed -= spirit_goal;
            self.aether += 1;
        }
    }

    pub fn damage(self: *Player, damage_owner_name: []const u8, phys_dmg: i32, magic_dmg: i32, true_dmg: i32) void {
        self.hp -= game_data.physDamage(phys_dmg, self.stats[defense_stat] + self.stat_boosts[defense_stat], self.condition);
        self.hp -= game_data.magicDamage(magic_dmg, self.stats[resistance_stat] + self.stat_boosts[resistance_stat], self.condition);
        self.hp -= true_dmg;

        if (self.hp <= 0) self.death(damage_owner_name) catch return;
    }

    fn CacheType(comptime T: type) type {
        return switch (T) {
            Player => [@typeInfo(network_data.PlayerStat).@"union".fields.len]?network_data.PlayerStat,
            Entity => [@typeInfo(network_data.EntityStat).@"union".fields.len]?network_data.EntityStat,
            Enemy => [@typeInfo(network_data.EnemyStat).@"union".fields.len]?network_data.EnemyStat,
            Portal => [@typeInfo(network_data.PortalStat).@"union".fields.len]?network_data.PortalStat,
            Container => [@typeInfo(network_data.ContainerStat).@"union".fields.len]?network_data.ContainerStat,
            else => unreachable,
        };
    }

    fn defaultCache(comptime T: type) CacheType(T) {
        var cache: CacheType(T) = undefined;
        @memset(&cache, null);
        return cache;
    }

    fn exportObject(self: *Player, comptime T: type, allocator: std.mem.Allocator) !void {
        for (self.world.listForType(T).items) |*object| {
            const x_dt = object.x - self.x;
            const y_dt = object.y - self.y;
            if (x_dt * x_dt + y_dt * y_dt <= 16 * 16) {
                var caches = &switch (T) {
                    Entity => self.caches.entity,
                    Enemy => self.caches.enemy,
                    Portal => self.caches.portal,
                    Container => self.caches.container,
                    else => unreachable,
                };
                const obj_type: network_data.ObjectType = switch (T) {
                    Entity => .entity,
                    Enemy => .enemy,
                    Portal => .portal,
                    Container => .container,
                    else => unreachable,
                };
                if (caches.getPtr(object.map_id)) |cache| {
                    const stats = try object.exportStats(cache);
                    if (stats.len > 0)
                        try @field(self.objs, @tagName(obj_type)).append(allocator, .{
                            .data_id = object.data_id,
                            .map_id = object.map_id,
                            .stats = stats,
                        });
                } else {
                    var cache = defaultCache(T);
                    try @field(self.objs, @tagName(obj_type)).append(allocator, .{
                        .data_id = object.data_id,
                        .map_id = object.map_id,
                        .stats = try object.exportStats(&cache),
                    });
                    try caches.put(allocator, object.map_id, cache);
                }
            }
        }
    }

    pub fn tick(self: *Player, _: i64, dt: i64) !void {
        if (self.x < 0.0 or self.y < 0.0)
            return;

        const scaled_dt = @as(f32, @floatFromInt(dt)) / std.time.us_per_s;

        const fstam: f32 = @floatFromInt(self.stats[stamina_stat] + self.stat_boosts[stamina_stat]);
        self.hp_regen += (1.0 + fstam * 0.12) * scaled_dt;
        const hp_regen_whole: i32 = @intFromFloat(self.hp_regen);
        self.hp = @min(self.stats[health_stat] + self.stat_boosts[health_stat], self.hp + hp_regen_whole);
        self.hp_regen -= @floatFromInt(hp_regen_whole);

        const fint: f32 = @floatFromInt(self.stats[intelligence_stat] + self.stat_boosts[intelligence_stat]);
        self.mp_regen += (0.5 + fint * 0.06) * scaled_dt;
        const mp_regen_whole: i32 = @intFromFloat(self.mp_regen);
        self.mp = @min(self.stats[mana_stat] + self.stat_boosts[mana_stat], self.mp + mp_regen_whole);
        self.mp_regen -= @floatFromInt(mp_regen_whole);

        if (self.hp <= 0) try self.death("Unknown");

        const allocator = self.world.allocator;

        self.conditions_to_remove.clearRetainingCapacity();
        for (self.conditions_active.values(), self.conditions_active.keys()) |*d, k| {
            if (d.* <= dt) {
                try self.conditions_to_remove.append(allocator, k);
                continue;
            }

            d.* -= dt;
        }

        for (self.conditions_to_remove.items) |c| {
            self.condition.set(c, false);
            _ = self.conditions_active.swapRemove(c);
        }

        const ux: u16 = @intFromFloat(self.x);
        const uy: u16 = @intFromFloat(self.y);
        const iux: i64 = ux;
        const iuy: i64 = uy;

        self.tiles.clearRetainingCapacity();
        for (self.world.tiles) |tile| {
            if (tile.data_id == std.math.maxInt(u16))
                continue;

            const x_dt = @as(i64, tile.x) - iux;
            const y_dt = @as(i64, tile.y) - iuy;
            if (x_dt * x_dt + y_dt * y_dt <= 16 * 16) {
                const hash = @as(u32, tile.x) << 16 | @as(u32, tile.y);
                if (self.tiles_seen.get(hash)) |update_count| {
                    if (update_count == tile.update_count)
                        continue;
                }

                try self.tiles_seen.put(allocator, hash, tile.update_count);
                try self.tiles.append(allocator, .{
                    .data_id = tile.data_id,
                    .x = tile.x,
                    .y = tile.y,
                });
            }
        }

        inline for (@typeInfo(@TypeOf(self.drops)).@"struct".fields) |field| {
            @field(self.drops, field.name).clearRetainingCapacity();
            for (@field(self.world.drops, field.name).items) |id| {
                if (@field(self.caches, field.name).contains(id)) {
                    _ = @field(self.caches, field.name).remove(id);
                    try @field(self.drops, field.name).append(allocator, id);
                }
            }
        }

        inline for (@typeInfo(@TypeOf(self.objs)).@"struct".fields) |field| {
            @field(self.objs, field.name).clearRetainingCapacity();
        }

        inline for (.{ Entity, Enemy, Portal, Container }) |ObjType| {
            try self.exportObject(ObjType, allocator);
        }

        for (self.world.listForType(Player).items) |*player| {
            const x_dt = player.x - self.x;
            const y_dt = player.y - self.y;
            if (x_dt * x_dt + y_dt * y_dt <= 16 * 16) {
                if (self.caches.player.getPtr(player.map_id)) |cache| {
                    const stats = try player.exportStats(cache, player.map_id == self.map_id, false);
                    if (stats.len > 0)
                        try self.objs.player.append(allocator, .{
                            .data_id = player.data_id,
                            .map_id = player.map_id,
                            .stats = stats,
                        });
                } else {
                    var cache = defaultCache(Player);
                    try self.objs.player.append(allocator, .{
                        .data_id = player.data_id,
                        .map_id = player.map_id,
                        .stats = try player.exportStats(&cache, player.map_id == self.map_id, true),
                    });
                    try self.caches.player.put(allocator, player.map_id, cache);
                }
            }
        }

        var needs_drop = false;
        inline for (@typeInfo(@TypeOf(self.drops)).@"struct".fields) |field| {
            if (@field(self.drops, field.name).items.len > 0) {
                needs_drop = true;
                break;
            }
        }

        if (needs_drop) self.client.queuePacket(.{ .dropped_map_ids = .{
            .players = self.drops.player.items,
            .enemies = self.drops.enemy.items,
            .entities = self.drops.entity.items,
            .portals = self.drops.portal.items,
            .containers = self.drops.container.items,
        } });

        self.client.queuePacket(.{ .new_data = .{
            .tick_id = main.tick_id,
            .tiles = self.tiles.items,
            .players = self.objs.player.items,
            .enemies = self.objs.enemy.items,
            .entities = self.objs.entity.items,
            .portals = self.objs.portal.items,
            .containers = self.objs.container.items,
        } });
    }

    fn statTypeToId(stat_type: @typeInfo(game_data.StatIncreaseData).@"union".tag_type.?) u16 {
        return switch (stat_type) {
            .max_hp => health_stat,
            .max_mp => mana_stat,
            .strength => strength_stat,
            .wit => wit_stat,
            .defense => defense_stat,
            .resistance => resistance_stat,
            .speed => speed_stat,
            .stamina => stamina_stat,
            .intelligence => intelligence_stat,
            .penetration => penetration_stat,
            .piercing => piercing_stat,
            .haste => haste_stat,
            .tenacity => tenacity_stat,
        };
    }

    pub fn recalculateItems(self: *Player) void {
        @memset(&self.stat_boosts, 0);
        for (self.inventory[0..4]) |item_id| {
            const props = game_data.item.from_id.get(item_id) orelse continue;
            if (props.stat_increases) |stat_increases| {
                for (stat_increases) |si| {
                    switch (si) {
                        inline else => |amount, tag| self.stat_boosts[statTypeToId(tag)] += @intCast(amount),
                    }
                }
            }
        }
    }

    pub fn exportStats(
        self: *Player,
        cache: *[@typeInfo(network_data.PlayerStat).@"union".fields.len]?network_data.PlayerStat,
        is_self: bool,
        comptime force_export_pos: bool,
    ) ![]const u8 {
        const writer = &self.stats_writer;
        writer.list.clearRetainingCapacity();

        const allocator = self.world.allocator;

        if (force_export_pos or !is_self) {
            stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .x = self.x });
            stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .y = self.y });
        }

        stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .name = self.name });
        stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .aether = self.aether });
        stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .max_hp = self.stats[health_stat] });
        stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .max_hp_bonus = self.stat_boosts[health_stat] });
        stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .hp = self.hp });
        stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .max_mp = self.stats[mana_stat] });
        stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .max_mp_bonus = self.stat_boosts[mana_stat] });
        stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .mp = self.mp });
        stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .condition = self.condition });

        if (is_self) {
            stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .spirits_communed = self.spirits_communed });
            stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .muted_until = self.muted_until });

            stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .strength = @intCast(self.stats[strength_stat]) });
            stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .wit = @intCast(self.stats[wit_stat]) });
            stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .defense = @intCast(self.stats[defense_stat]) });
            stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .resistance = @intCast(self.stats[resistance_stat]) });
            stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .speed = @intCast(self.stats[speed_stat]) });
            stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .stamina = @intCast(self.stats[stamina_stat]) });
            stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .intelligence = @intCast(self.stats[intelligence_stat]) });
            stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .penetration = @intCast(self.stats[penetration_stat]) });
            stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .piercing = @intCast(self.stats[piercing_stat]) });
            stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .haste = @intCast(self.stats[haste_stat]) });
            stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .tenacity = @intCast(self.stats[tenacity_stat]) });

            stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .strength_bonus = @intCast(self.stat_boosts[strength_stat]) });
            stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .wit_bonus = @intCast(self.stat_boosts[wit_stat]) });
            stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .defense_bonus = @intCast(self.stat_boosts[defense_stat]) });
            stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .resistance_bonus = @intCast(self.stat_boosts[resistance_stat]) });
            stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .speed_bonus = @intCast(self.stat_boosts[speed_stat]) });
            stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .stamina_bonus = @intCast(self.stat_boosts[stamina_stat]) });
            stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .intelligence_bonus = @intCast(self.stat_boosts[intelligence_stat]) });
            stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .penetration_bonus = @intCast(self.stat_boosts[penetration_stat]) });
            stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .piercing_bonus = @intCast(self.stat_boosts[piercing_stat]) });
            stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .haste_bonus = @intCast(self.stat_boosts[haste_stat]) });
            stat_util.write(network_data.PlayerStat, allocator, writer, cache, .{ .tenacity_bonus = @intCast(self.stat_boosts[tenacity_stat]) });

            inline for (0..self.inventory.len) |i| {
                const inv_tag: @typeInfo(network_data.PlayerStat).@"union".tag_type.? =
                    @enumFromInt(@intFromEnum(network_data.PlayerStat.inv_0) + @as(u8, i));
                stat_util.write(
                    network_data.PlayerStat,
                    allocator,
                    writer,
                    cache,
                    @unionInit(network_data.PlayerStat, @tagName(inv_tag), self.inventory[i]),
                );
            }
        }

        return writer.list.items;
    }
};
