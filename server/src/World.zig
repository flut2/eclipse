const std = @import("std");

const shared = @import("shared");
const utils = shared.utils;
const game_data = shared.game_data;
const network_data = shared.network_data;
const f32i = utils.f32i;
const u32f = utils.u32f;

const main = @import("main.zig");
const Ally = @import("map/Ally.zig");
const Container = @import("map/Container.zig");
const Enemy = @import("map/Enemy.zig");
const Entity = @import("map/Entity.zig");
const maps = @import("map/maps.zig");
const LightData = maps.LightData;
const Player = @import("map/Player.zig");
const Portal = @import("map/Portal.zig");
const Projectile = @import("map/Projectile.zig");
const Tile = @import("map/Tile.zig");

const World = @This();

pub const WorldPoint = struct { x: u16, y: u16 };

/// Data must have pointer stability and must be deallocated manually, usually in the callback (for type information)
pub const TimedCallback = struct { trigger_on: i64, callback: *const fn (*World, *anyopaque) void, data: *anyopaque };

id: i32 = std.math.minInt(i32),
owner_portal_id: u32 = std.math.maxInt(u32),
next_map_ids: struct {
    entity: u32 = 0,
    enemy: u32 = 0,
    player: u32 = 0,
    portal: u32 = 0,
    container: u32 = 0,
    projectile: u32 = 0,
    ally: u32 = 0,
} = .{},
w: u16 = 0,
h: u16 = 0,
time_added: i64 = 0,
name: []const u8 = undefined,
light_data: LightData = .{},
map_type: maps.MapType = .default,
tiles: []Tile = &.{},
regions: std.AutoHashMapUnmanaged(u16, []WorldPoint) = .empty,
drops: struct {
    entity: std.ArrayListUnmanaged(u32) = .empty,
    enemy: std.ArrayListUnmanaged(u32) = .empty,
    player: std.ArrayListUnmanaged(u32) = .empty,
    portal: std.ArrayListUnmanaged(u32) = .empty,
    container: std.ArrayListUnmanaged(u32) = .empty,
    ally: std.ArrayListUnmanaged(u32) = .empty,
} = .{},
lists: struct {
    entity: std.ArrayListUnmanaged(Entity) = .empty,
    enemy: std.ArrayListUnmanaged(Enemy) = .empty,
    player: std.ArrayListUnmanaged(Player) = .empty,
    portal: std.ArrayListUnmanaged(Portal) = .empty,
    container: std.ArrayListUnmanaged(Container) = .empty,
    projectile: std.ArrayListUnmanaged(Projectile) = .empty,
    ally: std.ArrayListUnmanaged(Ally) = .empty,
} = .{},
callbacks: std.ArrayListUnmanaged(TimedCallback) = .empty,

pub fn listForType(self: *World, comptime T: type) *std.ArrayListUnmanaged(T) {
    return switch (T) {
        Entity => &self.lists.entity,
        Enemy => &self.lists.enemy,
        Player => &self.lists.player,
        Portal => &self.lists.portal,
        Container => &self.lists.container,
        Projectile => &self.lists.projectile,
        Ally => &self.lists.ally,
        else => @compileError("Given type has no list"),
    };
}

pub fn dropsForType(self: *World, comptime T: type) *std.ArrayListUnmanaged(u32) {
    return switch (T) {
        Entity => &self.drops.entity,
        Enemy => &self.drops.enemy,
        Player => &self.drops.player,
        Portal => &self.drops.portal,
        Container => &self.drops.container,
        Ally => &self.drops.ally,
        else => @compileError("Given type has no drops list"),
    };
}

pub fn nextMapIdForType(self: *World, comptime T: type) *u32 {
    return switch (T) {
        Entity => &self.next_map_ids.entity,
        Enemy => &self.next_map_ids.enemy,
        Player => &self.next_map_ids.player,
        Portal => &self.next_map_ids.portal,
        Container => &self.next_map_ids.container,
        Projectile => &self.next_map_ids.projectile,
        Ally => &self.next_map_ids.ally,
        else => @compileError("Given type has no next map id"),
    };
}

pub fn appendMap(self: *World, map: maps.MapData) !void {
    @memcpy(self.tiles, map.tiles);
    self.regions = map.regions;

    self.name = map.details.name;
    self.light_data = map.details.light;
    self.map_type = map.details.map_type;

    for (map.entities) |e| _ = try self.add(Entity, .{ .x = e.x, .y = e.y, .data_id = e.data_id });
    for (map.enemies) |e| _ = try self.add(Enemy, .{ .x = e.x, .y = e.y, .data_id = e.data_id });
    for (map.portals) |p| _ = try self.add(Portal, .{ .x = p.x, .y = p.y, .data_id = p.data_id });
    for (map.containers) |c| _ = try self.add(Container, .{ .x = c.x, .y = c.y, .data_id = c.data_id });

    switch (self.map_type) {
        .dungeon => {
            var iter = map.regions.iterator();
            while (iter.next()) |entry| {
                const data = game_data.region.from_id.get(entry.key_ptr.*) orelse continue;
                if (std.mem.eql(u8, data.name, "Dungeon Monster Spawn")) {
                    const mobs = map.details.normal_mobs orelse continue;
                    for (entry.value_ptr.*) |point| {
                        const rand_mob = mobs[utils.rng.next() % mobs.len];
                        const mob_data = game_data.enemy.from_name.get(rand_mob) orelse {
                            std.log.err("Spawning dungeon mob \"{s}\" failed, no data found", .{rand_mob});
                            continue;
                        };
                        _ = try self.add(Enemy, .{ .x = f32i(point.x) + 0.5, .y = f32i(point.y) + 0.5, .data_id = mob_data.id });
                    }
                } else if (std.mem.eql(u8, data.name, "Dungeon Treasure Spawn")) {
                    const mobs = map.details.treasure_mobs orelse continue;
                    if (utils.rng.random().float(f32) <= map.details.treasure_chance) {
                        const rand_point = entry.value_ptr.*[utils.rng.next() % entry.value_ptr.len];
                        const rand_mob = mobs[utils.rng.next() % mobs.len];
                        const mob_data = game_data.enemy.from_name.get(rand_mob) orelse {
                            std.log.err("Spawning dungeon treasure \"{s}\" failed, no data found", .{rand_mob});
                            continue;
                        };
                        _ = try self.add(Enemy, .{ .x = f32i(rand_point.x) + 0.5, .y = f32i(rand_point.y) + 0.5, .data_id = mob_data.id });
                    }
                }
            }
        },
        else => {},
    }
}

pub fn create(w: u16, h: u16, id: i32) !World {
    return .{
        .id = id,
        .w = w,
        .h = h,
        .tiles = try main.allocator.alloc(Tile, @as(u32, w) * @as(u32, h)),
        .time_added = main.current_time,
    };
}

pub fn deinit(self: *World) void {
    std.log.info("World \"{s}\" (id {}) removed", .{ self.name, self.id });

    inline for (.{ &self.lists, &self.drops }) |list| {
        inline for (@typeInfo(@TypeOf(list.*)).@"struct".fields) |field| @field(list, field.name).deinit(main.allocator);
    }
    main.allocator.free(self.tiles);
    _ = maps.worlds.swapRemove(self.id);
}

pub fn add(self: *World, comptime T: type, data: T) !u32 {
    var obj = data;
    if (@hasField(T, "data_id")) obj.data_id = data.data_id;

    const next_map_id = self.nextMapIdForType(T);
    obj.map_id = next_map_id.*;
    next_map_id.* += 1;

    obj.world_id = self.id;

    if (std.meta.hasFn(T, "init")) try obj.init();
    try self.listForType(T).append(main.allocator, obj);

    return obj.map_id;
}

pub fn remove(self: *World, comptime T: type, value: *T) !void {
    if (std.meta.hasFn(T, "deinit")) try value.deinit();

    if (T != Projectile) try self.dropsForType(T).append(main.allocator, value.map_id);

    var list = self.listForType(T);
    for (list.items, 0..) |item, i| if (item.map_id == value.map_id) {
        _ = list.swapRemove(i);
        return;
    };
}

pub fn find(self: *World, comptime T: type, map_id: u32, comptime constness: enum { con, ref }) if (constness == .con) ?T else ?*T {
    switch (constness) {
        .con => for (self.listForType(T).items) |item| if (item.map_id == map_id) return item,
        .ref => for (self.listForType(T).items) |*item| if (item.map_id == map_id) return item,
    }
    return null;
}

pub fn tick(self: *World, time: i64, dt: i64) !void {
    if (self.id >= 0 and self.map_type != .realm and
        time > self.time_added + 30 * std.time.us_per_s and self.listForType(Player).items.len == 0)
    {
        self.deinit();
        return;
    }

    var callback_indices_to_remove: std.ArrayListUnmanaged(usize) = .empty;
    defer callback_indices_to_remove.deinit(main.allocator);
    for (self.callbacks.items, 0..) |timed_cb, i| {
        if (timed_cb.trigger_on <= time) {
            timed_cb.callback(self, timed_cb.data);
            callback_indices_to_remove.append(main.allocator, i) catch main.oomPanic();
        }
    }
    var iter = std.mem.reverseIterator(callback_indices_to_remove.items);
    while (iter.next()) |i| _ = self.callbacks.swapRemove(i);

    inline for (.{ Entity, Enemy, Portal, Container, Projectile, Player, Ally }) |ObjType| {
        for (self.listForType(ObjType).items) |*obj| try obj.tick(time, dt);
    }
}

pub fn moveToward(host: anytype, x: f32, y: f32, speed: f32, dt: i64) void {
    const dx = x - host.x;
    const dy = y - host.y;
    const dist = @sqrt(dx * dx + dy * dy);
    if (dist <= 0.01) return;

    const fdt = f32i(dt);
    const travel_dist = speed * (fdt / std.time.us_per_s);

    if (dist > travel_dist) {
        const c = travel_dist / dist;
        validatedMove(host, host.x + dx * c, host.y + dy * c);
    } else validatedMove(host, x, y);
}

pub fn validatedMove(self: anytype, x: f32, y: f32) void {
    if (x < 0.0 or y < 0.0) return;
    const world = maps.worlds.getPtr(self.world_id) orelse return;

    const ux = u32f(x);
    const uy = u32f(y);
    if (ux >= world.w or uy >= world.h) return;

    const tile = world.tiles[uy * world.w + ux];
    if (tile.data_id != std.math.maxInt(u16) and !tile.data.no_walk and !tile.occupied) {
        self.x = x;
        self.y = y;
    }
}

pub fn getNearestWithin(self: *World, comptime T: type, x: f32, y: f32, radius_sqr: f32) ?*T {
    var min_dist_sqr = radius_sqr;
    var target: ?*T = null;
    for (self.listForType(T).items) |*obj| {
        const dist_sqr = utils.distSqr(obj.x, obj.y, x, y);
        if (dist_sqr <= min_dist_sqr and !obj.condition.invisible) {
            min_dist_sqr = dist_sqr;
            target = obj;
        }
    }

    return target;
}

pub fn aoe(self: *World, comptime T: type, x: f32, y: f32, owner_type: network_data.ObjectType, owner_id: u32, radius: f32, opts: struct {
    phys_dmg: i32 = 0,
    magic_dmg: i32 = 0,
    true_dmg: i32 = 0,
    effect: ?utils.ConditionEnum = null,
    effect_duration: i64 = 1 * std.time.us_per_s,
    aoe_color: u32 = 0xFFFFFFFF,
}) void {
    const radius_sqr = radius * radius;
    for (self.listForType(T).items) |*obj| {
        if (utils.distSqr(obj.x, obj.y, x, y) > radius_sqr) continue;
        obj.damage(owner_type, owner_id, opts.phys_dmg, opts.magic_dmg, opts.true_dmg);
        if (opts.effect) |eff| obj.applyCondition(eff, opts.effect_duration);
    }

    if (T == Enemy and opts.aoe_color != 0xFFFFFFFF) for (self.listForType(Player).items) |*player| {
        player.client.queuePacket(.{ .show_effect = .{
            .obj_type = owner_type,
            .map_id = owner_id,
            .eff_type = .area_blast,
            .x1 = x,
            .y1 = y,
            .x2 = radius,
            .y2 = 0.0,
            .color = opts.aoe_color,
        } });
    };
}

pub fn getAmountWithin(self: *World, comptime T: type, name: []const u8, x: f32, y: f32, radius_sqr: f32) u32 {
    var amount: u32 = 0;
    for (self.listForType(T).items) |*obj| {
        if (!std.mem.eql(u8, obj.data.name, name)) continue;
        const dist_sqr = utils.distSqr(obj.x, obj.y, x, y);
        if (dist_sqr <= radius_sqr and !obj.condition.invisible) amount += 1;
    }
    return amount;
}