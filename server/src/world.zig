const std = @import("std");
const utils = @import("shared").utils;
const game_data = @import("shared").game_data;

const Tile = @import("map/tile.zig").Tile;
const Entity = @import("map/entity.zig").Entity;
const Enemy = @import("map/enemy.zig").Enemy;
const Player = @import("map/player.zig").Player;
const Projectile = @import("map/projectile.zig").Projectile;
const LightData = @import("map/maps.zig").LightData;

pub const WorldPoint = struct { x: u16, y: u16 };

pub const World = struct {
    owner_portal_id: i32 = -1,
    next_obj_id: i32 = 0,
    w: u16 = 0,
    h: u16 = 0,
    name: []const u8 = undefined,
    light_data: LightData = .{},
    tiles: []Tile = &[0]Tile{},
    regions: std.EnumArray(game_data.RegionType, []WorldPoint) = undefined,
    entities: std.ArrayList(Entity) = undefined,
    enemies: std.ArrayList(Enemy) = undefined,
    players: std.ArrayList(Player) = undefined,
    projectiles: std.ArrayList(Projectile) = undefined,
    drops: std.ArrayList(i32) = undefined,
    allocator: std.mem.Allocator = undefined,
    entity_lock: std.Thread.Mutex = .{},
    enemy_lock: std.Thread.Mutex = .{},
    player_lock: std.Thread.Mutex = .{},
    proj_lock: std.Thread.Mutex = .{},

    pub fn create(allocator: std.mem.Allocator, w: u16, h: u16, name: []const u8, light_data: LightData) !World {
        return .{
            .w = w,
            .h = h,
            .name = try allocator.dupe(u8, name),
            .light_data = light_data,
            .tiles = try allocator.alloc(Tile, @as(u32, w) * @as(u32, h)),
            .regions = std.EnumArray(game_data.RegionType, []WorldPoint).initUndefined(),
            .entities = std.ArrayList(Entity).init(allocator),
            .enemies = std.ArrayList(Enemy).init(allocator),
            .players = std.ArrayList(Player).init(allocator),
            .projectiles = std.ArrayList(Projectile).init(allocator),
            .drops = std.ArrayList(i32).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *World) void {
        {
            self.entity_lock.lock();
            defer self.entity_lock.unlock();
            self.entities.deinit();
        }
        {
            self.enemy_lock.lock();
            defer self.enemy_lock.unlock();
            self.enemies.deinit();
        }
        {
            self.player_lock.lock();
            defer self.player_lock.unlock();
            self.players.deinit();
        }
        {
            self.proj_lock.lock();
            defer self.proj_lock.unlock();
            self.projectiles.deinit();
        }
        self.drops.deinit();
        self.allocator.free(self.name);
        self.allocator.free(self.tiles);
    }

    pub fn add(self: *World, comptime T: type, value: *T) !i32 {
        value.obj_id = self.next_obj_id;
        self.next_obj_id +%= 1;

        value.world = self;

        if (std.meta.hasFn(T, "init"))
            try value.init(self.allocator);

        var lock = switch (T) {
            Entity => self.entity_lock,
            Enemy => self.enemy_lock,
            Player => self.player_lock,
            Projectile => self.proj_lock,
            else => @compileError("Invalid type for World.add()"),
        };

        std.debug.assert(!lock.tryLock());
        switch (T) {
            Entity => try self.entities.append(value.*),
            Enemy => try self.enemies.append(value.*),
            Player => try self.players.append(value.*),
            Projectile => try self.projectiles.append(value.*),
            else => unreachable,
        }

        return value.obj_id;
    }

    pub fn remove(self: *World, comptime T: type, value: *T) !void {
        if (std.meta.hasFn(T, "deinit"))
            try value.deinit();

        try self.drops.append(value.obj_id);

        var list = switch (T) {
            Entity => &self.entities,
            Enemy => &self.enemies,
            Player => &self.players,
            Projectile => &self.projectiles,
            else => @compileError("Invalid type for World.remove()"),
        };

        var lock = switch (T) {
            Entity => self.entity_lock,
            Enemy => self.enemy_lock,
            Player => self.player_lock,
            Projectile => self.proj_lock,
            else => unreachable,
        };

        std.debug.assert(!lock.tryLock());
        for (list.items, 0..) |item, i| {
            if (item.obj_id == value.obj_id) {
                _ = list.swapRemove(i);
                return;
            }
        }
    }

    pub fn find(self: World, comptime T: type, obj_id: i32) ?T {
        const list = switch (T) {
            Entity => self.entities,
            Enemy => self.enemies,
            Player => self.players,
            Projectile => self.projectiles,
            else => @compileError("Invalid type for World.find()"),
        };

        var lock = switch (T) {
            Entity => self.entity_lock,
            Enemy => self.enemy_lock,
            Player => self.player_lock,
            Projectile => self.proj_lock,
            else => unreachable,
        };

        std.debug.assert(!lock.tryLock());
        for (list.items) |item| {
            if (item.obj_id == obj_id)
                return item;
        }

        return null;
    }

    pub fn findRef(self: *World, comptime T: type, obj_id: i32) ?*T {
        const list = switch (T) {
            Entity => self.entities,
            Enemy => self.enemies,
            Player => self.players,
            Projectile => self.projectiles,
            else => @compileError("Invalid type for World.findRef()"),
        };

        var lock = switch (T) {
            Entity => self.entity_lock,
            Enemy => self.enemy_lock,
            Player => self.player_lock,
            Projectile => self.proj_lock,
            else => unreachable,
        };

        std.debug.assert(!lock.tryLock());
        for (list.items) |*item| {
            if (item.obj_id == obj_id)
                return item;
        }

        return null;
    }

    pub fn tick(self: *World, time: i64, dt: i64) !void {
        {
            self.entity_lock.lock();
            defer self.entity_lock.unlock();
            for (self.entities.items) |*entity| {
                try entity.tick(time, dt);
            }
        }

        {
            self.enemy_lock.lock();
            defer self.enemy_lock.unlock();
            for (self.enemies.items) |*enemy| {
                try enemy.tick(time, dt);
            }
        }

        {
            self.player_lock.lock();
            defer self.player_lock.unlock();
            for (self.players.items) |*player| {
                try player.tick(time, dt);
            }
        }

        {
            self.proj_lock.lock();
            defer self.proj_lock.unlock();
            for (self.projectiles.items) |*proj| {
                try proj.tick(time, dt);
            }
        }
    }

    pub fn getNearestPlayerWithin(self: *World, x: f32, y: f32, radius_sqr: f32) ?*Player {
        std.debug.assert(!self.player_lock.tryLock());

        var min_dist_sqr = radius_sqr;
        var target: ?*Player = null;
        for (self.players.items) |*p| {
            const dx = p.x - x;
            const dy = p.y - y;
            const dist_sqr = dx * dx + dy * dy;
            if (dist_sqr <= min_dist_sqr and !p.condition.invisible) {
                min_dist_sqr = dist_sqr;
                target = p;
            }
        }

        return target;
    }

    // If there is a target within radius_min_sqr, returns nothing
    // so that the caller can do nothing. Only one line differs.
    pub fn getNearestPlayerWithinRing(self: *World, x: f32, y: f32, radius_sqr: f32, radius_min_sqr: f32) ?*Player {
        std.debug.assert(!self.player_lock.tryLock());

        var min_dist_sqr = radius_sqr;
        var target: ?*Player = null;
        for (self.players.items) |*p| {
            const dx = p.x - x;
            const dy = p.y - y;
            const dist_sqr = dx * dx + dy * dy;
            if (dist_sqr <= radius_min_sqr)
                return null;

            if (dist_sqr <= min_dist_sqr and !p.condition.invisible) {
                min_dist_sqr = dist_sqr;
                target = p;
            }
        }

        return target;
    }

    pub fn getNearestEnemyWithin(self: *World, x: f32, y: f32, radius_sqr: f32, en_type: u16) ?*Enemy {
        std.debug.assert(!self.enemy_lock.tryLock());

        var min_dist_sqr = radius_sqr;
        var target: ?*Enemy = null;
        for (self.enemies.items) |*e| {
            const dx = e.x - x;
            const dy = e.y - y;
            const dist_sqr = dx * dx + dy * dy;
            if (e.en_type == en_type and dist_sqr <= min_dist_sqr) {
                min_dist_sqr = dist_sqr;
                target = e;
            }
        }

        return target;
    }

    pub fn aoePlayer(self: *World, time: i64, x: f32, y: f32, owner_name: []const u8, radius: f32, opts: struct {
        phys_dmg: i32 = 0,
        magic_dmg: i32 = 0,
        true_dmg: i32 = 0,
        effect: utils.ConditionEnum = .unknown,
        effect_duration: i64 = 1 * std.time.us_per_s,
        aoe_color: u32 = 0xFFFFFF,
    }) void {
        std.debug.assert(!self.player_lock.tryLock());

        const radius_sqr = radius * radius;
        for (self.players.items) |*p| {
            const dx = p.x - x;
            const dy = p.y - y;
            const dist_sqr = dx * dx + dy * dy;
            if (dist_sqr > 16 * 16)
                continue;

            p.client.queuePacket(.{ .show_effect = .{
                .eff_type = .area_blast,
                .obj_id = -1,
                .x1 = x,
                .y1 = y,
                .x2 = radius,
                .y2 = 0,
                .color = opts.aoe_color,
            } });

            if (dist_sqr > radius_sqr)
                continue;

            p.damage(owner_name, time, opts.phys_dmg, opts.magic_dmg, opts.true_dmg);
            p.applyCondition(opts.effect, opts.effect_duration) catch continue;
        }
    }
};
