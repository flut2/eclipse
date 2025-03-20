const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const utils = shared.utils;
const network_data = shared.network_data;
const f32i = utils.f32i;
const i32f = utils.i32f;
const u16f = utils.u16f;

const db = @import("../db.zig");
const Client = @import("../GameClient.zig");
const main = @import("../main.zig");
const maps = @import("../map/maps.zig");
const World = @import("../World.zig");
const Ally = @import("Ally.zig");
const Container = @import("Container.zig");
const Enemy = @import("Enemy.zig");
const Entity = @import("Entity.zig");
const Portal = @import("Portal.zig");
const stat_util = @import("stat_util.zig");

const Player = @This();

pub const StatId = enum {
    health,
    mana,
    strength,
    wit,
    defense,
    resistance,
    speed,
    haste,
    stamina,
    intelligence,
};

pub fn Stat(Size: type) type {
    return struct {
        base: Size = 0,
        boost: Size = 0,

        pub fn total(self: @This()) Size {
            return self.base + self.boost;
        }
    };
}

map_id: u32 = std.math.maxInt(u32),
data_id: u16 = std.math.maxInt(u16),

acc_data: db.AccountData,
char_data: db.CharacterData,

x: f32 = -1.0,
y: f32 = -1.0,
name: []const u8 = &.{},
rank: network_data.Rank = .default,
gold: u32 = 0,
gems: u32 = 0,
aether: u8 = 0,
spirits_communed: u32 = 0,
hp: i32 = 100,
mp: i32 = 0,
hp_regen: f32 = 0.0,
mp_regen: f32 = 0.0,
health: Stat(i32) = .{},
mana: Stat(i32) = .{},
strength: Stat(i16) = .{},
wit: Stat(i16) = .{},
defense: Stat(i16) = .{},
resistance: Stat(i16) = .{},
speed: Stat(i16) = .{},
stamina: Stat(i16) = .{},
intelligence: Stat(i16) = .{},
haste: Stat(i16) = .{},
inventory: [22]u16 = @splat(std.math.maxInt(u16)),
inv_data: [22]network_data.ItemData = @splat(@bitCast(@as(u32, 0))),
selecting_cards: ?[3]u16 = null,
cards: []u16 = &.{},
resources: std.ArrayListUnmanaged(network_data.DataIdWithCount(u32)) = .empty,
talents: std.ArrayListUnmanaged(network_data.DataIdWithCount(u16)) = .empty,
muted_until: i64 = 0,
condition: utils.Condition = .{},
caches: struct {
    player: std.AutoHashMapUnmanaged(u32, [@typeInfo(network_data.PlayerStat).@"union".fields.len]?network_data.PlayerStat) = .empty,
    entity: std.AutoHashMapUnmanaged(u32, [@typeInfo(network_data.EntityStat).@"union".fields.len]?network_data.EntityStat) = .empty,
    enemy: std.AutoHashMapUnmanaged(u32, [@typeInfo(network_data.EnemyStat).@"union".fields.len]?network_data.EnemyStat) = .empty,
    portal: std.AutoHashMapUnmanaged(u32, [@typeInfo(network_data.PortalStat).@"union".fields.len]?network_data.PortalStat) = .empty,
    container: std.AutoHashMapUnmanaged(u32, [@typeInfo(network_data.ContainerStat).@"union".fields.len]?network_data.ContainerStat) = .empty,
    ally: std.AutoHashMapUnmanaged(u32, [@typeInfo(network_data.AllyStat).@"union".fields.len]?network_data.AllyStat) = .empty,
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
    ally: std.ArrayListUnmanaged(network_data.ObjectData) = .empty,
} = .{},
drops: struct {
    entity: std.ArrayListUnmanaged(u32) = .empty,
    enemy: std.ArrayListUnmanaged(u32) = .empty,
    player: std.ArrayListUnmanaged(u32) = .empty,
    portal: std.ArrayListUnmanaged(u32) = .empty,
    container: std.ArrayListUnmanaged(u32) = .empty,
    ally: std.ArrayListUnmanaged(u32) = .empty,
} = .{},
projectiles: [256]?u32 = @splat(null),
position_records: [256]struct { x: f32, y: f32 } = @splat(.{ .x = std.math.maxInt(u16), .y = std.math.maxInt(u16) }),
hp_records: [256]i32 = @splat(-1),
chunked_tick_id: u8 = 0,
/// Used by Time Lock and Bloodfont
stored_damage: u32 = 0,
last_ability_use: [4]i64 = @splat(-1),
last_lock_update: i64 = -1,
damage_multiplier: f32 = 1.0,
hit_multiplier: f32 = 1.0,
ability_state: network_data.AbilityState = .{},
stats_writer: utils.PacketWriter = .{},
data: *const game_data.ClassData = undefined,
client: *Client = undefined,
world_id: i32 = std.math.minInt(i32),
export_pos: bool = false,

pub fn init(self: *Player) !void {
    self.stats_writer.list = try .initCapacity(main.allocator, 256);

    self.name = try main.allocator.dupe(u8, try self.acc_data.get(.name));
    self.data_id = try self.char_data.get(.class_id);
    self.data = game_data.class.from_id.getPtr(self.data_id) orelse {
        std.log.err("Could not find class data for player with data id {}", .{self.data_id});
        return;
    };

    const hwid_mute_expiry = blk: {
        const hwid = try self.acc_data.get(.hwid);
        var muted_hwids: db.MutedHwids = .{};
        defer muted_hwids.deinit();
        break :blk main.current_time + (muted_hwids.ttl(hwid) catch break :blk 0);
    };

    const acc_mute_expiry = try self.acc_data.get(.mute_expiry);

    self.muted_until = @max(hwid_mute_expiry, acc_mute_expiry);

    self.rank = try self.acc_data.getWithDefault(.rank, .default);
    self.gold = try self.acc_data.getWithDefault(.gold, 0);
    self.gems = try self.acc_data.getWithDefault(.gems, 0);
    self.resources.clearRetainingCapacity();
    self.resources.appendSlice(main.allocator, try self.acc_data.getWithDefault(.resources, &.{})) catch main.oomPanic();

    self.aether = try self.char_data.getWithDefault(.aether, 1);
    self.spirits_communed = try self.char_data.getWithDefault(.spirits_communed, 0);
    self.hp = try self.char_data.getWithDefault(.hp, 100);
    self.mp = try self.char_data.getWithDefault(.mp, 0);
    self.cards = try main.allocator.dupe(u16, try self.char_data.getWithDefault(.cards, &.{}));
    self.talents.clearRetainingCapacity();
    self.talents.appendSlice(main.allocator, try self.char_data.getWithDefault(.talents, &.{})) catch main.oomPanic();
    inline for (.{
        "health",
        "mana",
        "strength",
        "wit",
        "defense",
        "resistance",
        "speed",
        "haste",
        "stamina",
        "intelligence",
    }) |name| {
        const EnumType = @typeInfo(db.CharacterData.Data).@"union".tag_type.?;
        @field(self, name).base = try self.char_data.get(@field(EnumType, name));
    }
    self.inventory = try self.char_data.get(.inventory);
    self.inv_data = try self.char_data.get(.item_data);

    self.recalculateBoosts();

    self.moveToSpawn();
}

pub fn deinit(self: *Player) !void {
    self.clearEphemerals();
    try self.save();
    try self.acc_data.set(.{ .locked_until = 0 });

    self.char_data.deinit();
    self.acc_data.deinit();

    self.tiles.deinit(main.allocator);
    self.tiles_seen.deinit(main.allocator);

    inline for (@typeInfo(@TypeOf(self.objs)).@"struct".fields) |field| @field(self.objs, field.name).deinit(main.allocator);
    inline for (@typeInfo(@TypeOf(self.caches)).@"struct".fields) |field| @field(self.caches, field.name).deinit(main.allocator);

    main.allocator.free(self.name);
    main.allocator.free(self.cards);
    self.resources.deinit(main.allocator);
    self.talents.deinit(main.allocator);
    self.stats_writer.list.deinit(main.allocator);
}

pub inline fn totalStat(self: Player, comptime stat: StatId) i32 {
    return switch (stat) {
        .health => self.data.stats.health + self.health.total(),
        .mana => self.data.stats.mana + self.mana.total(),
        .strength => self.data.stats.strength + self.strength.total(),
        .wit => self.data.stats.wit + self.wit.total(),
        .defense => self.data.stats.defense + self.defense.total(),
        .resistance => self.data.stats.resistance + self.resistance.total(),
        .speed => self.data.stats.speed + self.speed.total(),
        .haste => self.data.stats.haste + self.haste.total(),
        .stamina => self.data.stats.stamina + self.stamina.total(),
        .intelligence => self.data.stats.intelligence + self.intelligence.total(),
    };
}

pub fn clearEphemerals(self: *Player) void {
    for (&self.inventory) |*item| {
        const data = game_data.item.from_id.get(item.*) orelse continue;
        if (data.ephemeral) {
            sendMessage: {
                var buf: [256]u8 = undefined;
                const message = std.fmt.bufPrint(&buf, "Your \"{s}\" has vanished from your inventory", .{data.name}) catch break :sendMessage;
                self.client.sendMessage(message);
            }

            item.* = std.math.maxInt(u16);
        }
    }
}

pub fn moveToSpawn(self: *Player) void {
    const world = maps.worlds.getPtr(self.world_id) orelse return;

    const spawn_points = world.regions.get(game_data.region.from_name.get("Spawn").?.id);
    if (spawn_points == null or spawn_points.?.len == 0) {
        std.log.err("Could not find spawn point for player with data id {}", .{self.data_id});
        return;
    }

    const rand_point = spawn_points.?[utils.rng.random().intRangeAtMost(usize, 0, spawn_points.?.len - 1)];
    const tile = world.tiles[@as(u32, rand_point.y) * @as(u32, world.w) + @as(u32, rand_point.x)];
    if (tile.data_id == std.math.maxInt(u16) or tile.data.no_walk or tile.occupied) {
        std.log.err("Spawn point {} was not walkable for player with data id {}", .{ rand_point, self.data_id });
        return;
    }
    self.x = f32i(rand_point.x) + 0.5;
    self.y = f32i(rand_point.y) + 0.5;
}

pub fn applyCondition(self: *Player, condition: utils.ConditionEnum, duration: i64) void {
    if (self.conditions_active.getPtr(condition)) |current_duration| {
        if (duration > current_duration.*) current_duration.* = duration;
    } else self.conditions_active.put(main.allocator, condition, duration) catch main.oomPanic();
    self.condition.set(condition, true);
}

pub fn clearCondition(self: *Player, condition: utils.ConditionEnum) void {
    _ = self.conditions_active.swapRemove(condition);
    self.condition.set(condition, false);
}

pub fn save(self: *Player) !void {
    try self.acc_data.set(.{ .rank = self.rank });
    try self.acc_data.set(.{ .gold = self.gold });
    try self.acc_data.set(.{ .gems = self.gems });
    try self.acc_data.set(.{ .resources = self.resources.items });

    try self.char_data.set(.{ .hp = self.hp });
    try self.char_data.set(.{ .mp = self.mp });
    try self.char_data.set(.{ .aether = self.aether });
    try self.char_data.set(.{ .spirits_communed = self.spirits_communed });
    try self.char_data.set(.{ .inventory = self.inventory });
    try self.char_data.set(.{ .item_data = self.inv_data });
    inline for (.{
        "health",
        "mana",
        "strength",
        "wit",
        "defense",
        "resistance",
        "speed",
        "haste",
        "stamina",
        "intelligence",
    }) |name|
        try self.char_data.set(@unionInit(db.CharacterData.Data, name, @field(self, name).base));
    try self.char_data.set(.{ .cards = self.cards });
    try self.char_data.set(.{ .talents = self.talents.items });
}

pub fn death(self: *Player, killer: []const u8) !void {
    if (self.rank == .admin) {
        self.hp = 1;
        return;
    }

    const alive_char_ids = self.acc_data.get(.alive_char_ids) catch {
        self.client.sendError(.message_with_disconnect, "Death failed: Database Error");
        return;
    };
    const new_char_ids = main.allocator.alloc(u32, alive_char_ids.len - 1) catch main.oomPanic();
    defer main.allocator.free(new_char_ids);
    delete: {
        for (alive_char_ids, 0..) |char_id, i| {
            if (self.char_data.char_id != char_id) continue;
            @memcpy(new_char_ids[0..i], alive_char_ids[0..i]);
            @memcpy(new_char_ids[i..], alive_char_ids[i + 1 ..]);
            break :delete;
        }
        self.client.sendError(.message_with_disconnect, "Death failed: Character does not exist");
        return;
    }

    self.acc_data.set(.{ .alive_char_ids = new_char_ids }) catch {
        self.client.sendError(.message_with_disconnect, "Death failed: Database Error");
        return;
    };

    const gravestone_id: u16 = switch (self.aether) {
        1 => 2,
        2 => 3,
        3 => 4,
        4 => 5,
        5 => 6,
        else => 2,
    };

    if (maps.worlds.getPtr(self.world_id)) |world|
        _ = world.add(Entity, .{
            .x = self.x,
            .y = self.y,
            .data_id = gravestone_id,
            .name = main.allocator.dupe(u8, self.name) catch main.oomPanic(),
        }) catch |e| std.log.err("Populating gravestone for {s} failed: {}", .{ self.name, e });

    self.client.sendPacket(.{ .death = .{ .killer_name = killer } });
    self.client.shutdown();
}

pub fn hasCard(self: *Player, card_name: []const u8) bool {
    const data = game_data.card.from_name.get(card_name) orelse return false;
    for (self.cards) |card_id| if (card_id == data.id) return true;
    return false;
}

pub fn addSpirits(self: *Player, amount: u32) void {
    self.spirits_communed += amount;
    const spirit_goal = game_data.spiritGoal(self.aether);
    if (self.spirits_communed >= spirit_goal) {
        self.spirits_communed -= spirit_goal;
        self.aether += 1;
    }
}

pub fn damage(
    self: *Player,
    owner_type: network_data.ObjectType,
    owner_id: u32,
    phys_dmg: i32,
    magic_dmg: i32,
    true_dmg: i32,
    conditions: ?[]const game_data.TimedCondition,
) void {
    if (owner_type != .enemy) return; // something saner later

    const unscaled_dmg = f32i(game_data.physDamage(
        phys_dmg,
        self.totalStat(.defense),
        self.condition,
    ) + game_data.magicDamage(
        magic_dmg,
        self.totalStat(.resistance),
        self.condition,
    ) + true_dmg);
    const dmg = i32f(unscaled_dmg * self.hit_multiplier);
    self.hp -= dmg;

    if (self.hp <= 0) {
        const owner_name = blk: {
            const world = maps.worlds.getPtr(self.world_id) orelse break :blk "Unknown";
            break :blk (world.find(Enemy, owner_id, .con) orelse break :blk "Unknown").data.name;
        };
        self.death(owner_name) catch return;
        return;
    }

    if (conditions) |conds| for (conds) |cond| self.applyCondition(cond.type, i32f(cond.duration));

    if (dmg > 0 and self.ability_state.time_lock) self.stored_damage += @intCast(dmg * 5);
    if (unscaled_dmg > 0 and self.ability_state.bloodfont) self.stored_damage += @intCast(i32f(unscaled_dmg));
    if (dmg > 100 and self.hasCard("Absorption"))
        self.hp = @min(self.totalStat(.health), i32f(f32i(dmg) * 0.15));
}

fn CacheType(comptime T: type) type {
    return switch (T) {
        Player => [@typeInfo(network_data.PlayerStat).@"union".fields.len]?network_data.PlayerStat,
        Entity => [@typeInfo(network_data.EntityStat).@"union".fields.len]?network_data.EntityStat,
        Enemy => [@typeInfo(network_data.EnemyStat).@"union".fields.len]?network_data.EnemyStat,
        Portal => [@typeInfo(network_data.PortalStat).@"union".fields.len]?network_data.PortalStat,
        Container => [@typeInfo(network_data.ContainerStat).@"union".fields.len]?network_data.ContainerStat,
        Ally => [@typeInfo(network_data.AllyStat).@"union".fields.len]?network_data.AllyStat,
        else => @compileError("Unsupported type"),
    };
}

fn defaultCache(comptime T: type) CacheType(T) {
    var cache: CacheType(T) = undefined;
    @memset(&cache, null);
    return cache;
}

fn exportObject(self: *Player, world: *World, comptime T: type) !void {
    for (world.listForType(T).items) |*object| {
        if (T == Container and
            object.owner_map_id != std.math.maxInt(u32) and
            object.owner_map_id != self.map_id) continue;

        // demon soul check, have to hardcode things since this is the hot path
        if (T == Entity and object.data_id == 49 and self.data_id != 0) continue;

        const x_dt = object.x - self.x;
        const y_dt = object.y - self.y;
        if (T == Enemy and object.data.elite or x_dt * x_dt + y_dt * y_dt <= 16 * 16) {
            var caches = &switch (T) {
                Entity => self.caches.entity,
                Enemy => self.caches.enemy,
                Portal => self.caches.portal,
                Container => self.caches.container,
                Ally => self.caches.ally,
                else => @compileError("Unsupported type"),
            };
            const obj_type: network_data.ObjectType = switch (T) {
                Entity => .entity,
                Enemy => .enemy,
                Portal => .portal,
                Container => .container,
                Ally => .ally,
                else => @compileError("Unsupported type"),
            };
            if (caches.getPtr(object.map_id)) |cache| {
                const stats = try object.exportStats(cache);
                if (stats.len > 0)
                    try @field(self.objs, @tagName(obj_type)).append(main.allocator, .{
                        .data_id = object.data_id,
                        .map_id = object.map_id,
                        .stats = stats,
                    });
            } else {
                var cache = defaultCache(T);
                try @field(self.objs, @tagName(obj_type)).append(main.allocator, .{
                    .data_id = object.data_id,
                    .map_id = object.map_id,
                    .stats = try object.exportStats(&cache),
                });
                try caches.put(main.allocator, object.map_id, cache);
            }
        }
    }
}

pub fn tick(self: *Player, time: i64, dt: i64) !void {
    if (self.x < 0.0 or self.y < 0.0) return;
    const world = maps.worlds.getPtr(self.world_id) orelse return;

    if (time - self.last_lock_update >= 60 * std.time.us_per_s) {
        const ms_time = @divFloor(time, 1000);
        try self.acc_data.set(.{ .locked_until = @intCast(ms_time + 90 * std.time.ms_per_s) });
        self.last_lock_update = time;
    }

    const scaled_dt = f32i(dt) / std.time.us_per_s;

    const max_hp = self.totalStat(.health);
    if (self.hp < max_hp) {
        self.hp_regen += (1.0 + f32i(self.totalStat(.stamina)) * 0.12) * scaled_dt;
        const hp_regen_whole = i32f(self.hp_regen);
        self.hp = @min(max_hp, self.hp + hp_regen_whole);
        self.hp_regen -= f32i(hp_regen_whole);
    }

    const max_mp = self.totalStat(.mana);
    if (self.mp < max_mp) {
        self.mp_regen += (0.5 + f32i(self.totalStat(.intelligence)) * 0.06) * scaled_dt;
        const mp_regen_whole = i32f(self.mp_regen);
        self.mp = @min(max_mp, self.mp + mp_regen_whole);
        self.mp_regen -= f32i(mp_regen_whole);
    }

    if (self.hp <= 0) try self.death("Unknown");

    if (main.tick_id % 3 == 0) {
        defer self.chunked_tick_id +%= 1;
        self.hp_records[self.chunked_tick_id] = self.hp;
        self.position_records[self.chunked_tick_id] = .{ .x = self.x, .y = self.y };
    }

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

    const ux = u16f(self.x);
    const uy = u16f(self.y);
    const iux: i64 = ux;
    const iuy: i64 = uy;

    self.tiles.clearRetainingCapacity();

    for (world.tiles) |tile| {
        if (tile.data_id == std.math.maxInt(u16))
            continue;

        const x_dt = @as(i64, tile.x) - iux;
        const y_dt = @as(i64, tile.y) - iuy;
        if (x_dt * x_dt + y_dt * y_dt <= 16 * 16) {
            const hash = @as(u32, tile.x) << 16 | @as(u32, tile.y);
            if (self.tiles_seen.get(hash)) |update_count| if (update_count == tile.update_count) continue;

            try self.tiles_seen.put(main.allocator, hash, tile.update_count);
            try self.tiles.append(main.allocator, .{
                .data_id = tile.data_id,
                .x = tile.x,
                .y = tile.y,
            });
        }
    }

    inline for (@typeInfo(@TypeOf(self.drops)).@"struct".fields) |field| {
        @field(self.drops, field.name).clearRetainingCapacity();
        for (@field(world.drops, field.name).items) |id| {
            if (@field(self.caches, field.name).contains(id)) {
                _ = @field(self.caches, field.name).remove(id);
                try @field(self.drops, field.name).append(main.allocator, id);
            }
        }
    }

    inline for (@typeInfo(@TypeOf(self.objs)).@"struct".fields) |field| @field(self.objs, field.name).clearRetainingCapacity();
    inline for (.{ Entity, Enemy, Portal, Container, Ally }) |ObjType| try self.exportObject(world, ObjType);

    for (world.listForType(Player).items) |*player| {
        const x_dt = player.x - self.x;
        const y_dt = player.y - self.y;
        if (x_dt * x_dt + y_dt * y_dt <= 16 * 16) {
            if (self.caches.player.getPtr(player.map_id)) |cache| {
                const stats = try player.exportStats(cache, player.map_id == self.map_id, self.export_pos);
                if (stats.len > 0)
                    try self.objs.player.append(main.allocator, .{
                        .data_id = player.data_id,
                        .map_id = player.map_id,
                        .stats = stats,
                    });
                self.export_pos = false;
            } else {
                var cache = defaultCache(Player);
                try self.objs.player.append(main.allocator, .{
                    .data_id = player.data_id,
                    .map_id = player.map_id,
                    .stats = try player.exportStats(&cache, player.map_id == self.map_id, true),
                });
                try self.caches.player.put(main.allocator, player.map_id, cache);
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

    self.client.sendPacket(.{ .new_tick = .{ .tick_id = main.tick_id, .tiles = self.tiles.items } });

    const max_bytes = std.math.maxInt(u15);
    inline for (.{
        .{ "dropped_players", self.drops.player.items },
        .{ "dropped_entities", self.drops.entity.items },
        .{ "dropped_enemies", self.drops.enemy.items },
        .{ "dropped_portals", self.drops.portal.items },
        .{ "dropped_containers", self.drops.container.items },
        .{ "dropped_allies", self.drops.ally.items },
    }) |mapping| @"continue": {
        if (mapping[1].len == 0) break :@"continue";
        const child_size = @sizeOf(u32);
        const total_size = mapping[1].len * child_size;
        for (0..total_size / max_bytes + 1) |i|
            self.client.sendPacket(@unionInit(network_data.S2CPacket, mapping[0], .{
                .map_ids = mapping[1][i * max_bytes / child_size .. @min((total_size - i * max_bytes) / child_size, (i + 1) * max_bytes / child_size)],
            }));
    }

    inline for (.{
        .{ "new_players", self.objs.player.items },
        .{ "new_entities", self.objs.entity.items },
        .{ "new_enemies", self.objs.enemy.items },
        .{ "new_portals", self.objs.portal.items },
        .{ "new_containers", self.objs.container.items },
        .{ "new_allies", self.objs.ally.items },
    }) |mapping| @"continue": {
        if (mapping[1].len == 0) break :@"continue";
        var size_tally: usize = 0;
        var last_idx: usize = 0;
        var idx: usize = 0;
        for (mapping[1]) |data| {
            defer idx += 1;
            const byte_size = data.byteSize();
            const next_size = size_tally + byte_size;
            if (next_size > max_bytes and idx > last_idx) {
                self.client.sendPacket(@unionInit(network_data.S2CPacket, mapping[0], .{
                    .list = mapping[1][last_idx .. idx - 1],
                }));
                size_tally = byte_size;
                last_idx = idx;
            } else size_tally = next_size;
        }

        if (last_idx < mapping[1].len)
            self.client.sendPacket(@unionInit(network_data.S2CPacket, mapping[0], .{
                .list = mapping[1][last_idx..],
            }));
    }
}

fn statTypeToName(stat_type: anytype) []const u8 {
    return switch (stat_type) {
        .max_hp => "health",
        .max_mp => "mana",
        .strength => "strength",
        .wit => "wit",
        .defense => "defense",
        .resistance => "resistance",
        .speed => "speed",
        .stamina => "stamina",
        .intelligence => "intelligence",
        .haste => "haste",
    };
}

pub fn recalculateBoosts(self: *Player) void {
    inline for (.{
        "health",
        "mana",
        "strength",
        "wit",
        "defense",
        "resistance",
        "speed",
        "haste",
        "stamina",
        "intelligence",
    }) |name|
        @field(self, name).boost = 0;

    var perc_boosts: struct {
        health: f32 = 0.0,
        mana: f32 = 0.0,
        strength: f32 = 0.0,
        wit: f32 = 0.0,
        defense: f32 = 0.0,
        resistance: f32 = 0.0,
        speed: f32 = 0.0,
        haste: f32 = 0.0,
        stamina: f32 = 0.0,
        intelligence: f32 = 0.0,
    } = .{};

    for (self.inventory[0..4]) |item_id| {
        const data = game_data.item.from_id.get(item_id) orelse continue;
        if (data.stat_increases) |stat_increases| for (stat_increases) |si|
            switch (si) {
                inline else => |inner, tag| @field(self, statTypeToName(tag)).boost += @intCast(inner.amount),
            };
        if (data.perc_stat_increases) |stat_increases| for (stat_increases) |si|
            switch (si) {
                inline else => |inner, tag| @field(perc_boosts, statTypeToName(tag)) += inner.amount,
            };
    }

    for (self.cards) |card_id| {
        const data = game_data.card.from_id.get(card_id) orelse continue;
        if (data.flat_stats) |stat_increases| for (stat_increases) |si|
            switch (si) {
                inline else => |inner, tag| @field(self, statTypeToName(tag)).boost += @intCast(inner.amount),
            };
        if (data.perc_stats) |stat_increases| for (stat_increases) |si|
            switch (si) {
                inline else => |inner, tag| @field(perc_boosts, statTypeToName(tag)) += inner.amount,
            };
    }

    for (self.talents.items) |talent| {
        const class_data = game_data.class.from_id.get(self.data_id) orelse continue;
        if (class_data.talents.len >= talent.data_id) continue;
        const talent_data = class_data.talents[talent.data_id];
        if (talent_data.flat_stats) |stat_increases| for (stat_increases) |si|
            switch (si) {
                inline else => |inner, tag| @field(self, statTypeToName(tag)).boost += @intCast(inner.amount * talent.count),
            };
        if (talent_data.perc_stats) |stat_increases| for (stat_increases) |si|
            switch (si) {
                inline else => |inner, tag| @field(perc_boosts, statTypeToName(tag)) += inner.amount * f32i(talent.count),
            };
    }

    inline for (@typeInfo(@TypeOf(perc_boosts)).@"struct".fields) |field| {
        if (@field(perc_boosts, field.name) != 0.0)
            @field(self, field.name).boost += @intFromFloat(f32i(@field(self, field.name).boost) * @field(perc_boosts, field.name));
    }
}

pub fn exportStats(
    self: *Player,
    cache: *[@typeInfo(network_data.PlayerStat).@"union".fields.len]?network_data.PlayerStat,
    is_self: bool,
    force_export_pos: bool,
) ![]const u8 {
    const writer = &self.stats_writer;
    writer.list.clearRetainingCapacity();

    const T = network_data.PlayerStat;
    if (force_export_pos or !is_self) {
        inline for (.{
            T{ .x = self.x },
            T{ .y = self.y },
        }) |stat| stat_util.write(T, writer, cache, stat);
    }

    inline for (.{
        T{ .name = self.name },
        T{ .aether = self.aether },
        T{ .spirits_communed = self.spirits_communed },
        T{ .max_hp = self.data.stats.health + self.health.base },
        T{ .max_hp_bonus = self.health.boost },
        T{ .hp = self.hp },
        T{ .max_mp = self.data.stats.mana + self.mana.base },
        T{ .max_mp_bonus = self.mana.boost },
        T{ .mp = self.mp },
        T{ .condition = self.condition },
        T{ .ability_state = self.ability_state },
        T{ .muted_until = self.muted_until },
        T{ .rank = self.rank },
        T{ .damage_mult = self.damage_multiplier },
        T{ .hit_mult = self.hit_multiplier },
    }) |stat| stat_util.write(T, writer, cache, stat);

    inline for (0..4) |i| {
        const inv_tag: @typeInfo(T).@"union".tag_type.? = @enumFromInt(@intFromEnum(T.inv_0) + @as(u8, i));
        stat_util.write(T, writer, cache, @unionInit(T, @tagName(inv_tag), self.inventory[i]));
        const inv_data_tag: @typeInfo(T).@"union".tag_type.? = @enumFromInt(@intFromEnum(T.inv_data_0) + @as(u8, i));
        stat_util.write(T, writer, cache, @unionInit(T, @tagName(inv_data_tag), self.inv_data[i]));
    }

    if (is_self) {
        inline for (.{
            T{ .gold = self.gold },
            T{ .gems = self.gems },
            T{ .cards = self.cards },
            T{ .resources = self.resources.items },
            T{ .talents = self.talents.items },
            T{ .strength = self.data.stats.strength + self.strength.base },
            T{ .wit = self.data.stats.wit + self.wit.base },
            T{ .defense = self.data.stats.defense + self.defense.base },
            T{ .resistance = self.data.stats.resistance + self.resistance.base },
            T{ .speed = self.data.stats.speed + self.speed.base },
            T{ .haste = self.data.stats.haste + self.haste.base },
            T{ .stamina = self.data.stats.stamina + self.stamina.base },
            T{ .intelligence = self.data.stats.intelligence + self.intelligence.base },
            T{ .strength_bonus = self.strength.boost },
            T{ .wit_bonus = self.wit.boost },
            T{ .defense_bonus = self.defense.boost },
            T{ .resistance_bonus = self.resistance.boost },
            T{ .speed_bonus = self.speed.boost },
            T{ .haste_bonus = self.haste.boost },
            T{ .stamina_bonus = self.stamina.boost },
            T{ .intelligence_bonus = self.intelligence.boost },
        }) |stat| stat_util.write(T, writer, cache, stat);

        inline for (4..self.inventory.len) |i| {
            const inv_tag: @typeInfo(T).@"union".tag_type.? = @enumFromInt(@intFromEnum(T.inv_0) + @as(u8, i));
            stat_util.write(T, writer, cache, @unionInit(T, @tagName(inv_tag), self.inventory[i]));
            const inv_data_tag: @typeInfo(T).@"union".tag_type.? = @enumFromInt(@intFromEnum(T.inv_data_0) + @as(u8, i));
            stat_util.write(T, writer, cache, @unionInit(T, @tagName(inv_data_tag), self.inv_data[i]));
        }
    }

    return writer.list.items;
}
