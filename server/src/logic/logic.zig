const std = @import("std");
const game_data = @import("shared").game_data;
const utils = @import("shared").utils;

const Projectile = @import("../map/projectile.zig").Projectile;
const Enemy = @import("../map/enemy.zig").Enemy;

var heal_storage: std.AutoHashMap(u64, HealStorage) = undefined;
var charge_storage: std.AutoHashMap(u64, ChargeStorage) = undefined;
var aoe_storage: std.AutoHashMap(u64, AoeStorage) = undefined;
var follow_storage: std.AutoHashMap(u64, FollowStorage) = undefined;
var wander_storage: std.AutoHashMap(u64, WanderStorage) = undefined;
var shoot_storage: std.AutoHashMap(u64, ShootStorage) = undefined;

pub fn init(allocator: std.mem.Allocator) void {
    heal_storage = std.AutoHashMap(u64, HealStorage).init(allocator);
    charge_storage = std.AutoHashMap(u64, ChargeStorage).init(allocator);
    aoe_storage = std.AutoHashMap(u64, AoeStorage).init(allocator);
    follow_storage = std.AutoHashMap(u64, FollowStorage).init(allocator);
    wander_storage = std.AutoHashMap(u64, WanderStorage).init(allocator);
    shoot_storage = std.AutoHashMap(u64, ShootStorage).init(allocator);
}

pub fn deinit() void {
    heal_storage.deinit();
    charge_storage.deinit();
    aoe_storage.deinit();
    follow_storage.deinit();
    wander_storage.deinit();
    shoot_storage.deinit();
}

pub inline fn clearStorage(storage_id: u64) void {
    _ = heal_storage.remove(storage_id);
    _ = charge_storage.remove(storage_id);
    _ = aoe_storage.remove(storage_id);
    _ = follow_storage.remove(storage_id);
    _ = wander_storage.remove(storage_id);
    _ = shoot_storage.remove(storage_id);
}

pub inline fn getStorageId(comptime type_id: u32, obj_id: i32) u64 {
    return @as(u64, type_id) << 32 | @as(u64, @intCast(obj_id));
}

const HealStorage = struct { time: i64 = 0 };
pub inline fn heal(host: *Enemy, dt: i64, opts: struct {
    range: f32,
    amount: i32,
    target_name: []const u8,
    cooldown: i64,
}) bool {
    const storage_id = getStorageId(utils.typeId(@This()), host.obj_id);
    var storage = heal_storage.getPtr(storage_id) orelse blk: {
        heal_storage.put(storage_id, .{}) catch return false;
        break :blk heal_storage.getPtr(storage_id).?;
    };
    storage.time -= dt;
    if (storage.time > 0)
        return false;
    defer storage.time = opts.cooldown;

    for (host.world.enemies.items) |*e| {
        const dx = e.x - host.x;
        const dy = e.y - host.y;
        if (std.mem.eql(u8, e.props.display_id, opts.target_name) and dx * dx + dy * dy <= opts.range * opts.range) {
            const pre_hp = e.hp;
            e.hp = @min(e.max_hp, e.hp + opts.amount);
            const hp_delta = e.hp - pre_hp;
            if (hp_delta <= 0)
                return false;

            var buf: [64]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "+{d}", .{hp_delta}) catch return false;

            host.world.player_lock.lock();
            defer host.world.player_lock.unlock();
            for (host.world.players.items) |p| {
                p.client.queuePacket(.{ .notification = .{
                    .obj_id = e.obj_id,
                    .message = msg,
                    .color = 0x00FF00,
                } });

                p.client.queuePacket(.{ .show_effect = .{
                    .eff_type = .trail,
                    .obj_id = host.obj_id,
                    .x1 = e.x,
                    .y1 = e.y,
                    .x2 = 0,
                    .y2 = 0,
                    .color = 0x00FF00,
                } });
            }

            return true;
        }
    }

    return false;
}

const ChargeStorage = struct { target_x: f32 = std.math.nan(f32), target_y: f32 = std.math.nan(f32), time: i64 = 0 };
pub inline fn charge(host: *Enemy, dt: i64, opts: struct {
    speed: f32,
    range: f32,
    cooldown: i64,
}) bool {
    const storage_id = getStorageId(utils.typeId(@This()), host.obj_id);
    var storage = charge_storage.getPtr(storage_id) orelse blk: {
        charge_storage.put(storage_id, .{}) catch return false;
        break :blk charge_storage.getPtr(storage_id).?;
    };

    if (!std.math.isNan(storage.target_x) and !std.math.isNan(storage.target_y)) {
        host.moveToward(storage.target_x, storage.target_y, 0.0001, opts.speed, dt);
        storage.time -= dt;
        if (storage.time < 0) {
            storage.target_x = std.math.nan(f32);
            storage.target_y = std.math.nan(f32);
            storage.time = opts.cooldown;
            return false;
        }

        return true;
    } else {
        storage.time -= dt;
        if (storage.time > 0)
            return false;

        host.world.player_lock.lock();
        defer host.world.player_lock.unlock();

        if (host.world.getNearestPlayerWithin(host.x, host.y, opts.range * opts.range)) |p| {
            const dx = host.x - p.x;
            const dy = host.y - p.y;
            storage.target_x = p.x;
            storage.target_y = p.y;
            storage.time = @intFromFloat(@sqrt(dx * dx + dy * dy) / opts.speed * std.time.us_per_s);
        }

        return false;
    }
}

pub inline fn orbit(host: *Enemy, dt: i64, opts: struct {
    speed: f32,
    radius: f32,
    acquire_range: f32,
    target_name: []const u8,
    rotate_speed: f32 = 1.0,
}) bool {
    const acq_sqr = opts.acquire_range * opts.acquire_range;
    for (host.world.enemies.items) |*e| {
        const dx = host.x - e.x;
        const dy = host.y - e.y;
        if (std.mem.eql(u8, opts.target_name, e.props.display_id) and
            dx * dx + dy * dy <= acq_sqr)
        {
            const angle = std.math.atan2(dy, dx) + @mod(@as(f32, @floatFromInt(dt)) / std.time.us_per_s * opts.rotate_speed, std.math.tau);
            host.moveToward(e.x + opts.radius * @cos(angle), e.y + opts.radius * @sin(angle), 0.0001, opts.speed, dt);
            return true;
        }
    }

    return false;
}

const AoeStorage = struct { time: i64 = 0 };
pub inline fn aoe(host: *Enemy, time: i64, dt: i64, opts: struct {
    radius: f32,
    phys_dmg: i32 = 0,
    magic_dmg: i32 = 0,
    true_dmg: i32 = 0,
    effect: utils.ConditionEnum = .unknown,
    effect_duration: i64 = 1 * std.time.us_per_s,
    cooldown: i64 = 1 * std.time.us_per_s,
    color: u32 = 0xFFFFFF,
}) void {
    const storage_id = getStorageId(utils.typeId(@This()), host.obj_id);
    var storage = aoe_storage.getPtr(storage_id) orelse blk: {
        aoe_storage.put(storage_id, .{}) catch return;
        break :blk aoe_storage.getPtr(storage_id).?;
    };

    storage.time -= dt;
    if (storage.time > 0)
        return;
    defer storage.time = opts.cooldown;

    host.world.player_lock.lock();
    defer host.world.player_lock.unlock();

    host.world.aoePlayer(time, host.x, host.y, host.props.display_id, opts.radius, .{
        .phys_dmg = opts.phys_dmg,
        .magic_dmg = opts.magic_dmg,
        .true_dmg = opts.true_dmg,
        .effect = opts.effect,
        .effect_duration = opts.effect_duration,
        .aoe_color = opts.color,
    });
}

const FollowStorage = struct { time: i64 = 0 };
pub inline fn follow(host: *Enemy, dt: i64, opts: struct {
    speed: f32,
    acquire_range: f32,
    range: f32,
    cooldown: i64,
}) bool {
    const storage_id = getStorageId(utils.typeId(@This()), host.obj_id);
    var storage = follow_storage.getPtr(storage_id) orelse blk: {
        follow_storage.put(storage_id, .{}) catch return false;
        break :blk follow_storage.getPtr(storage_id).?;
    };

    storage.time -= dt;
    if (storage.time > 0)
        return false;
    defer storage.time = opts.cooldown;

    const acq_sqr = opts.acquire_range * opts.acquire_range;
    const range_sqr = opts.range * opts.range;

    host.world.player_lock.lock();
    defer host.world.player_lock.unlock();

    const target = host.world.getNearestPlayerWithinRing(host.x, host.y, acq_sqr, range_sqr) orelse return false;
    host.moveToward(target.x, target.y, range_sqr, opts.speed, dt);
    return true;
}

const WanderStorage = struct { move_cos: f32 = 0.0, move_sin: f32 = 0.0, rem_dist: f32 = 0.0 };
pub inline fn wander(host: *Enemy, dt: i64, speed: f32) void {
    const storage_id = getStorageId(utils.typeId(@This()), host.obj_id);
    var storage = wander_storage.getPtr(storage_id) orelse blk: {
        wander_storage.put(storage_id, .{}) catch return;
        break :blk wander_storage.getPtr(storage_id).?;
    };

    if (storage.rem_dist <= 0.0) {
        const angle = utils.rng.random().float(f32) * std.math.tau;
        storage.move_cos = @cos(angle);
        storage.move_sin = @sin(angle);
        storage.rem_dist = utils.rng.random().float(f32);
    }

    const fdt: f32 = @floatFromInt(dt);
    const dist = speed * (fdt / std.time.us_per_s);
    host.move(host.x + dist * storage.move_cos, host.y + dist * storage.move_sin);
    storage.rem_dist -= dist;
}

const ShootStorage = struct { cooldown: i64 = -1, rotate_count: f32 = 0.0 };
pub inline fn shoot(host: *Enemy, time: i64, dt: i64, opts: struct {
    proj_index: u8,
    shoot_angle: f32,
    angle_offset: f32 = 0.0,
    count: u8 = 1,
    radius: f32 = 20.0,
    cooldown: i64 = 1000,
    predictivity: f32 = 0.0,
    default_angle: f32 = std.math.nan(f32),
    fixed_angle: f32 = std.math.nan(f32),
    rotate_angle: f32 = std.math.nan(f32),
}) void {
    const storage_id = getStorageId(utils.typeId(@This()), host.obj_id);
    var storage = shoot_storage.getPtr(storage_id) orelse blk: {
        shoot_storage.put(storage_id, .{}) catch return;
        break :blk shoot_storage.getPtr(storage_id).?;
    };

    storage.cooldown -= dt;
    if (storage.cooldown > 0)
        return;

    defer storage.cooldown = opts.cooldown;

    const radius_sqr = opts.radius * opts.radius;

    var angle: f32 = 0.0;
    if (std.math.isNan(opts.fixed_angle)) {
        {
            host.world.player_lock.lock();
            defer host.world.player_lock.unlock();
            if (host.world.getNearestPlayerWithin(host.x, host.y, radius_sqr)) |p| {
                angle = if (opts.predictivity > 0 and opts.predictivity > utils.rng.random().float(f32))
                    0.0 // predict(host, p)
                else
                    std.math.atan2(p.y - host.y, p.x - host.x);
            }
        }

        if (!std.math.isNan(opts.default_angle))
            angle = std.math.degreesToRadians(f32, opts.default_angle);
    } else angle = std.math.degreesToRadians(f32, opts.fixed_angle);

    angle += std.math.degreesToRadians(f32, opts.angle_offset) + if (!std.math.isNan(opts.rotate_angle))
        std.math.degreesToRadians(f32, opts.rotate_angle) * storage.rotate_count
    else
        0.0;
    storage.rotate_count += 1.0;

    const shoot_angle_deg = std.math.degreesToRadians(f32, opts.shoot_angle);
    const fcount: f32 = @floatFromInt(opts.count);
    const start_angle = angle - shoot_angle_deg * (fcount - 1.0) / 2.0;
    const bullet_id_start = host.next_bullet_id;
    const proj_props = host.props.projectiles[opts.proj_index];

    for (0..opts.count) |i| {
        const fi: f32 = @floatFromInt(i);

        var proj: Projectile = .{
            .owner_id = host.obj_id,
            .x = host.x,
            .y = host.y,
            .angle = start_angle + fi * shoot_angle_deg,
            .start_time = time,
            .phys_dmg = proj_props.physical_damage,
            .magic_dmg = proj_props.magic_damage,
            .true_dmg = proj_props.true_damage,
            .bullet_id = host.next_bullet_id,
            .props = &proj_props,
        };

        {
            host.world.proj_lock.lock();
            defer host.world.proj_lock.unlock();
            _ = host.world.add(Projectile, &proj) catch return;
        }

        host.bullets[host.next_bullet_id] = proj.obj_id;
        host.next_bullet_id +%= 1;
    }

    host.world.player_lock.lock();
    defer host.world.player_lock.unlock();
    for (host.world.players.items) |p| {
        const dx = p.x - host.x;
        const dy = p.y - host.y;
        if (dx * dx + dy * dy <= 20 * 20) {
            p.client.queuePacket(.{ .enemy_shoot = .{
                .bullet_id = bullet_id_start,
                .owner_id = host.obj_id,
                .bullet_index = opts.proj_index,
                .x = host.x,
                .y = host.y,
                .angle = start_angle,
                .phys_dmg = @intCast(proj_props.physical_damage),
                .magic_dmg = @intCast(proj_props.magic_damage),
                .true_dmg = @intCast(proj_props.true_damage),
                .num_shots = opts.count,
                .angle_inc = shoot_angle_deg,
            } });
        }
    }
}
