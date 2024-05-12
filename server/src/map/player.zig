const std = @import("std");
const db = @import("../db.zig");
const game_data = @import("shared").game_data;
const utils = @import("shared").utils;
const main = @import("../main.zig");
const settings = @import("../settings.zig");
const client = @import("../client.zig");
const stat_util = @import("stat_util.zig");

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

    obj_id: i32 = -1,
    acc_data: db.AccountData = undefined,
    char_data: db.CharacterData = undefined,

    x: f32 = -1.0,
    y: f32 = -1.0,
    player_type: u16 = 0xFFFF,
    name: []const u8 = &[0]u8{},
    rank: u8 = 0,
    aether: u8 = 1,
    hp: i32 = 100,
    mp: i32 = 0,
    stats: [13]i32 = [_]i32{0} ** 13,
    stat_boosts: [13]i32 = [_]i32{0} ** 13,
    equips: [22]u16 = [_]u16{0xFFFF} ** 22,
    condition: utils.Condition = .{},
    stat_caches: std.AutoHashMap(i32, std.EnumArray(game_data.StatType, ?stat_util.StatValue)) = undefined,
    tiles: std.ArrayList(client.TileData) = undefined,
    tiles_seen: std.AutoHashMap(u32, u16) = undefined,
    new_objs: std.ArrayList(client.ObjectData) = undefined,
    tick_objs: std.ArrayList(client.ObjectData) = undefined,
    drops: std.ArrayList(i32) = undefined,
    bullets: [256]?i32 = [_]?i32{null} ** 256,
    stats_writer: utils.PacketWriter = .{},
    props: *const game_data.ObjProps = undefined,
    client: *Client = undefined,
    world: *World = undefined,
    allocator: std.mem.Allocator = undefined,

    pub fn init(self: *Player, allocator: std.mem.Allocator) !void {
        self.allocator = allocator;
        self.tiles = std.ArrayList(client.TileData).init(allocator);
        self.tiles_seen = std.AutoHashMap(u32, u16).init(allocator);
        self.new_objs = std.ArrayList(client.ObjectData).init(allocator);
        self.tick_objs = std.ArrayList(client.ObjectData).init(allocator);
        self.stat_caches = std.AutoHashMap(i32, std.EnumArray(game_data.StatType, ?stat_util.StatValue)).init(allocator);
        self.drops = std.ArrayList(i32).init(allocator);
        self.stats_writer.buffer = try allocator.alloc(u8, 256);

        self.name = try allocator.dupe(u8, try self.acc_data.get(.name, []const u8));
        self.player_type = try self.char_data.get(.char_type, u16);
        self.props = game_data.obj_type_to_props.getPtr(self.player_type) orelse {
            std.log.err("Could not find props for player with type 0x{x}", .{self.player_type});
            return;
        };

        const spawn_points = self.world.regions.get(.spawn);
        if (spawn_points.len == 0) {
            std.log.err("Could not find spawn point for player with type 0x{x}", .{self.player_type});
            return;
        }

        const rand_point = spawn_points[utils.rng.random().intRangeAtMost(usize, 0, spawn_points.len - 1)];
        self.x = @as(f32, @floatFromInt(rand_point.x)) + 0.5;
        self.y = @as(f32, @floatFromInt(rand_point.y)) + 0.5;

        self.rank = try self.acc_data.get(.rank, u8);
        self.aether = try self.char_data.get(.aether, u8);
        self.hp = try self.char_data.get(.hp, i32);
        self.mp = try self.char_data.get(.mp, i32);

        self.stats = try self.char_data.get(.stats, [13]i32);
        self.equips = try self.char_data.get(.items, [22]u16);

        self.recalculateItems();
    }

    pub fn deinit(self: *Player) !void {
        self.char_data.deinit();
        self.acc_data.deinit();
        self.tiles.deinit();
        self.tiles_seen.deinit();
        self.new_objs.deinit();
        self.stat_caches.deinit();
        self.tick_objs.deinit();
        self.allocator.free(self.name);
        self.allocator.free(self.stats_writer.buffer);
    }

    pub fn save(self: *Player) !void {
        try self.char_data.set(.hp, i32, self.hp);
        try self.char_data.set(.mp, i32, self.mp);
        try self.char_data.set(.aether, u8, self.aether);
        try self.char_data.set(.items, [22]u16, self.equips);
        try self.char_data.set(.stats, [13]i32, self.stats);
    }

    pub fn death(self: *Player, killer: []const u8) !void {
        // todo reconnect to Retrieve
        if (self.rank >= 80)
            return;

        self.client.queuePacket(.{ .death = .{
            .acc_id = @intCast(self.acc_data.acc_id),
            .char_id = @intCast(self.char_data.char_id),
            .killer = killer,
        } });
        try self.world.remove(Player, self);
    }

    pub fn damage(self: *Player, damage_owner_name: []const u8, phys_dmg: i32, magic_dmg: i32, true_dmg: i32) void {
        self.hp -= phys_dmg - self.props.defense;
        self.hp -= magic_dmg - self.props.resistance;
        self.hp -= true_dmg;
        if (self.hp <= 0) self.death(damage_owner_name) catch return;
    }

    pub fn tick(self: *Player, _: i64, _: i64) !void {
        if (self.hp <= 0) try self.death("Unknown");

        const ux: u16 = @intFromFloat(self.x);
        const uy: u16 = @intFromFloat(self.y);
        const iux: i64 = ux;
        const iuy: i64 = uy;

        self.tiles.clearRetainingCapacity();
        for (self.world.tiles) |tile| {
            const x_dt = @as(i64, tile.x) - iux;
            const y_dt = @as(i64, tile.y) - iuy;
            if (x_dt * x_dt + y_dt * y_dt <= 16 * 16) {
                const hash = @as(u32, tile.x) << 16 | @as(u32, tile.y);
                if (self.tiles_seen.get(hash)) |update_count| {
                    if (update_count == tile.update_count)
                        continue;
                }

                try self.tiles_seen.put(hash, tile.update_count);
                try self.tiles.append(.{
                    .tile_type = tile.tile_type,
                    .x = tile.x,
                    .y = tile.y,
                });
            }
        }

        self.drops.clearRetainingCapacity();
        for (self.world.drops.items) |id| {
            if (self.stat_caches.contains(id)) {
                _ = self.stat_caches.remove(id);
                try self.drops.append(id);
            }
        }

        self.new_objs.clearRetainingCapacity();
        self.tick_objs.clearRetainingCapacity();

        {
            self.world.entity_lock.lock();
            defer self.world.entity_lock.unlock();
            for (self.world.entities.items) |*entity| {
                const x_dt = entity.x - self.x;
                const y_dt = entity.y - self.y;
                if (x_dt * x_dt + y_dt * y_dt <= 16 * 16) {
                    if (self.stat_caches.getPtr(entity.obj_id)) |cache| {
                        const stats = try entity.exportStats(cache);
                        if (stats.len > 0)
                            try self.tick_objs.append(.{
                                .obj_type = entity.en_type,
                                .obj_id = entity.obj_id,
                                .stats = stats,
                            });
                    } else {
                        var cache = std.EnumArray(game_data.StatType, ?stat_util.StatValue).initFill(null);
                        try self.new_objs.append(.{
                            .obj_type = entity.en_type,
                            .obj_id = entity.obj_id,
                            .stats = try entity.exportStats(&cache),
                        });
                        try self.stat_caches.put(entity.obj_id, cache);
                    }
                }
            }
        }

        {
            self.world.enemy_lock.lock();
            defer self.world.enemy_lock.unlock();
            for (self.world.enemies.items) |*enemy| {
                const x_dt = enemy.x - self.x;
                const y_dt = enemy.y - self.y;
                if (x_dt * x_dt + y_dt * y_dt <= 16 * 16) {
                    if (self.stat_caches.getPtr(enemy.obj_id)) |cache| {
                        const stats = try enemy.exportStats(cache);
                        if (stats.len > 0)
                            try self.tick_objs.append(.{
                                .obj_type = enemy.en_type,
                                .obj_id = enemy.obj_id,
                                .stats = stats,
                            });
                    } else {
                        var cache = std.EnumArray(game_data.StatType, ?stat_util.StatValue).initFill(null);
                        try self.new_objs.append(.{
                            .obj_type = enemy.en_type,
                            .obj_id = enemy.obj_id,
                            .stats = try enemy.exportStats(&cache),
                        });
                        try self.stat_caches.put(enemy.obj_id, cache);
                    }
                }
            }
        }

        for (self.world.players.items) |*player| {
            const x_dt = player.x - self.x;
            const y_dt = player.y - self.y;
            if (x_dt * x_dt + y_dt * y_dt <= 16 * 16) {
                if (self.stat_caches.getPtr(player.obj_id)) |cache| {
                    const stats = try player.exportStats(cache, player.obj_id == self.obj_id, false);
                    if (stats.len > 0)
                        try self.tick_objs.append(.{
                            .obj_type = player.player_type,
                            .obj_id = player.obj_id,
                            .stats = stats,
                        });
                } else {
                    var cache = std.EnumArray(game_data.StatType, ?stat_util.StatValue).initFill(null);
                    try self.new_objs.append(.{
                        .obj_type = player.player_type,
                        .obj_id = player.obj_id,
                        .stats = try player.exportStats(&cache, player.obj_id == self.obj_id, true),
                    });
                    try self.stat_caches.put(player.obj_id, cache);
                }
            }
        }

        self.client.queuePacket(.{ .update = .{
            .tiles = self.tiles.items,
            .drops = self.drops.items,
            .new_objs = self.new_objs.items,
        } });

        self.client.queuePacket(.{ .new_tick = .{
            .tick_id = main.tick_id,
            .ticks_per_sec = settings.tps,
            .objs = self.tick_objs.items,
        } });
    }

    inline fn statTypeToId(stat_type: game_data.StatType) u16 {
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
            else => @panic("Invalid stat type given to Player.statTypeToId()"),
        };
    }

    pub fn recalculateItems(self: *Player) void {
        @memset(&self.stat_boosts, 0);
        for (self.equips[0..4]) |equip_type| {
            const props = game_data.item_type_to_props.get(equip_type) orelse continue;
            if (props.stat_increments) |increments| {
                for (increments) |increment| {
                    self.stat_boosts[statTypeToId(increment.stat)] += increment.amount;
                }
            }
        }
    }

    pub fn exportStats(self: *Player, stat_cache: *std.EnumArray(game_data.StatType, ?stat_util.StatValue), is_self: bool, comptime force_export_pos: bool) ![]u8 {
        var writer = &self.stats_writer;
        writer.index = 0;

        if (force_export_pos or !is_self) {
            stat_util.write(writer, stat_cache, self.allocator, .x, self.x);
            stat_util.write(writer, stat_cache, self.allocator, .y, self.y);
        }

        stat_util.write(writer, stat_cache, self.allocator, .name, self.name);
        stat_util.write(writer, stat_cache, self.allocator, .account_id, @as(i32, @intCast(self.acc_data.acc_id)));
        stat_util.write(writer, stat_cache, self.allocator, .max_hp, self.stats[health_stat]);
        stat_util.write(writer, stat_cache, self.allocator, .hp, @as(i32, @intCast(self.hp)));
        stat_util.write(writer, stat_cache, self.allocator, .max_mp, @as(i16, @intCast(self.stats[mana_stat])));
        stat_util.write(writer, stat_cache, self.allocator, .mp, self.mp);
        stat_util.write(writer, stat_cache, self.allocator, .condition, self.condition);

        if (is_self) {
            stat_util.write(writer, stat_cache, self.allocator, .strength, @as(i16, @intCast(self.stats[strength_stat])));
            stat_util.write(writer, stat_cache, self.allocator, .wit, @as(i16, @intCast(self.stats[wit_stat])));
            stat_util.write(writer, stat_cache, self.allocator, .defense, @as(i16, @intCast(self.stats[defense_stat])));
            stat_util.write(writer, stat_cache, self.allocator, .resistance, @as(i16, @intCast(self.stats[resistance_stat])));
            stat_util.write(writer, stat_cache, self.allocator, .speed, @as(i16, @intCast(self.stats[speed_stat])));
            stat_util.write(writer, stat_cache, self.allocator, .stamina, @as(i16, @intCast(self.stats[stamina_stat])));
            stat_util.write(writer, stat_cache, self.allocator, .intelligence, @as(i16, @intCast(self.stats[intelligence_stat])));
            stat_util.write(writer, stat_cache, self.allocator, .penetration, @as(i16, @intCast(self.stats[penetration_stat])));
            stat_util.write(writer, stat_cache, self.allocator, .piercing, @as(i16, @intCast(self.stats[piercing_stat])));
            stat_util.write(writer, stat_cache, self.allocator, .haste, @as(i16, @intCast(self.stats[haste_stat])));
            stat_util.write(writer, stat_cache, self.allocator, .tenacity, @as(i16, @intCast(self.stats[tenacity_stat])));

            stat_util.write(writer, stat_cache, self.allocator, .strength_bonus, @as(i16, @intCast(self.stat_boosts[strength_stat])));
            stat_util.write(writer, stat_cache, self.allocator, .wit_bonus, @as(i16, @intCast(self.stat_boosts[wit_stat])));
            stat_util.write(writer, stat_cache, self.allocator, .defense_bonus, @as(i16, @intCast(self.stat_boosts[defense_stat])));
            stat_util.write(writer, stat_cache, self.allocator, .resistance_bonus, @as(i16, @intCast(self.stat_boosts[resistance_stat])));
            stat_util.write(writer, stat_cache, self.allocator, .speed_bonus, @as(i16, @intCast(self.stat_boosts[speed_stat])));
            stat_util.write(writer, stat_cache, self.allocator, .stamina_bonus, @as(i16, @intCast(self.stat_boosts[stamina_stat])));
            stat_util.write(writer, stat_cache, self.allocator, .intelligence_bonus, @as(i16, @intCast(self.stat_boosts[intelligence_stat])));
            stat_util.write(writer, stat_cache, self.allocator, .penetration_bonus, @as(i16, @intCast(self.stat_boosts[penetration_stat])));
            stat_util.write(writer, stat_cache, self.allocator, .piercing_bonus, @as(i16, @intCast(self.stat_boosts[piercing_stat])));
            stat_util.write(writer, stat_cache, self.allocator, .haste_bonus, @as(i16, @intCast(self.stat_boosts[haste_stat])));
            stat_util.write(writer, stat_cache, self.allocator, .tenacity_bonus, @as(i16, @intCast(self.stat_boosts[tenacity_stat])));
        }

        inline for (0..self.equips.len) |i| {
            const inv_stat: game_data.StatType = @enumFromInt(@intFromEnum(game_data.StatType.inv_0) + @as(u8, i));
            stat_util.write(writer, stat_cache, self.allocator, inv_stat, self.equips[i]);
        }

        return writer.buffer[0..writer.index];
    }
};
