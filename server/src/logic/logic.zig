const std = @import("std");
const main = @import("../main.zig");
const shared = @import("shared");
const game_data = shared.game_data;
const network_data = shared.network_data;
const utils = shared.utils;

const Player = @import("../map/Player.zig");
const Projectile = @import("../map/Projectile.zig");
const Enemy = @import("../map/Enemy.zig");
const Entity = @import("../map/Entity.zig");
const Ally = @import("../map/Ally.zig");
const World = @import("../World.zig");

pub const Storages = struct {
    heal: std.AutoHashMapUnmanaged(u64, HealStorage) = .empty,
    charge: std.AutoHashMapUnmanaged(u64, ChargeStorage) = .empty,
    aoe: std.AutoHashMapUnmanaged(u64, AoeStorage) = .empty,
    follow: std.AutoHashMapUnmanaged(u64, FollowStorage) = .empty,
    wander: std.AutoHashMapUnmanaged(u64, WanderStorage) = .empty,
    shoot: std.AutoHashMapUnmanaged(u64, ShootStorage) = .empty,

    pub fn clear(self: *Storages) void {
        inline for (@typeInfo(@TypeOf(self.*)).@"struct".fields) |field| {
            @field(self.*, field.name).clearRetainingCapacity();
        }
    }

    pub fn deinit(self: *Storages) void {
        inline for (@typeInfo(@TypeOf(self.*)).@"struct".fields) |field| {
            @field(self.*, field.name).deinit(main.allocator);
        }
    }
};

fn getStorageId(comptime src_loc: std.builtin.SourceLocation) u64 {
    return @as(u64, std.hash.XxHash32.hash(0, src_loc.file)) << 32 | @as(u64, @intCast(src_loc.line));
}

fn verifyType(comptime T: type) void {
    const type_info = @typeInfo(T);
    if (type_info != .pointer or
        type_info.pointer.child != Enemy and
        type_info.pointer.child != Entity and
        type_info.pointer.child != Ally)
        @compileError("Invalid type given. Please use \"Enemy\", \"Entity\" or \"Ally\"");
}

const HealStorage = struct { time: i64 = 0 };
pub fn heal(comptime src_loc: std.builtin.SourceLocation, host: anytype, dt: i64, opts: struct {
    range: f32,
    amount: i32,
    target_name: []const u8,
    cooldown: i64,
}) bool {
    verifyType(@TypeOf(host));

    const storage_id = getStorageId(src_loc);
    var storage = host.storages.heal.getPtr(storage_id) orelse blk: {
        host.storages.heal.put(main.allocator, storage_id, .{}) catch return false;
        break :blk host.storages.heal.getPtr(storage_id).?;
    };
    storage.time -= dt;
    if (storage.time > 0) return false;
    defer storage.time = opts.cooldown;

    for (host.world.listForType(Enemy).items) |*e| {
        const dx = e.x - host.x;
        const dy = e.y - host.y;
        if (std.mem.eql(u8, e.data.name, opts.target_name) and dx * dx + dy * dy <= opts.range * opts.range) {
            const pre_hp = e.hp;
            e.hp = @min(e.max_hp, e.hp + opts.amount);
            const hp_delta = e.hp - pre_hp;
            if (hp_delta <= 0) return false;

            var buf: [64]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "+{}", .{hp_delta}) catch return false;

            const obj_type: network_data.ObjectType = if (@TypeOf(host.*) == Enemy) .enemy else .entity;
            for (host.world.listForType(Player).items) |p| {
                p.client.queuePacket(.{ .notification = .{
                    .obj_type = obj_type,
                    .map_id = e.map_id,
                    .message = msg,
                    .color = 0x00FF00,
                } });

                p.client.queuePacket(.{ .show_effect = .{
                    .eff_type = .trail,
                    .obj_type = obj_type,
                    .map_id = host.map_id,
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
pub fn charge(comptime src_loc: std.builtin.SourceLocation, host: anytype, dt: i64, opts: struct {
    speed: f32,
    range: f32,
    cooldown: i64,
}) bool {
    verifyType(@TypeOf(host));

    const storage_id = getStorageId(src_loc);
    var storage = host.storages.charge.getPtr(storage_id) orelse blk: {
        host.storages.charge.put(main.allocator, storage_id, .{}) catch return false;
        break :blk host.storages.charge.getPtr(storage_id).?;
    };

    if (!std.math.isNan(storage.target_x) and !std.math.isNan(storage.target_y)) {
        World.moveToward(host, storage.target_x, storage.target_y, opts.speed, dt);
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
        if (storage.time > 0) return false;

        if (host.world.getNearestWithin(Player, host.x, host.y, opts.range * opts.range)) |p| {
            const dx = host.x - p.x;
            const dy = host.y - p.y;
            storage.target_x = p.x;
            storage.target_y = p.y;
            storage.time = @intFromFloat(@sqrt(dx * dx + dy * dy) / opts.speed * std.time.us_per_s);
        }

        return false;
    }
}

pub fn orbit(host: anytype, dt: i64, opts: struct {
    speed: f32,
    radius: f32,
    acquire_range: f32,
    target_name: []const u8,
    rotate_speed: f32 = 1.0,
}) bool {
    verifyType(@TypeOf(host));

    const acq_sqr = opts.acquire_range * opts.acquire_range;
    for (host.world.listForType(Enemy).items) |*e| {
        const dx = host.x - e.x;
        const dy = host.y - e.y;
        if (std.mem.eql(u8, opts.target_name, e.data.name) and
            dx * dx + dy * dy <= acq_sqr)
        {
            const angle = std.math.atan2(dy, dx) + @mod(@as(f32, @floatFromInt(dt)) / std.time.us_per_s * opts.rotate_speed, std.math.tau);
            World.moveToward(host, e.x + opts.radius * @cos(angle), e.y + opts.radius * @sin(angle), opts.speed, dt);
            return true;
        }
    }

    return false;
}

pub fn orbitPlayer(host: anytype, dt: i64, opts: struct {
    speed: f32,
    radius: f32,
    acquire_range: f32,
    target_map_id: u32,
    rotate_speed: f32 = 1.0,
}) bool {
    verifyType(@TypeOf(host));

    const acq_sqr = opts.acquire_range * opts.acquire_range;
    if (host.world.find(Player, opts.target_map_id)) |p| {
        const dx = host.x - p.x;
        const dy = host.y - p.y;
        if (dx * dx + dy * dy <= acq_sqr) {
            const angle = std.math.atan2(dy, dx) + @mod(@as(f32, @floatFromInt(dt)) / std.time.us_per_s * opts.rotate_speed, std.math.tau);
            World.moveToward(host, p.x + opts.radius * @cos(angle), p.y + opts.radius * @sin(angle), opts.speed, dt);
            return true;
        }
    }

    return false;
}

const AoeStorage = struct { time: i64 = 0 };
pub fn aoe(comptime src_loc: std.builtin.SourceLocation, host: anytype, dt: i64, opts: struct {
    radius: f32,
    phys_dmg: i32 = 0,
    magic_dmg: i32 = 0,
    true_dmg: i32 = 0,
    effect: ?utils.ConditionEnum = null,
    effect_duration: i64 = 1 * std.time.us_per_s,
    cooldown: i64 = 1 * std.time.us_per_s,
    color: u32 = 0xFFFFFF,
}) void {
    verifyType(@TypeOf(host));

    const storage_id = getStorageId(src_loc);
    var storage = host.storages.aoe.getPtr(storage_id) orelse blk: {
        host.storages.aoe.put(main.allocator, storage_id, .{}) catch return;
        break :blk host.storages.aoe.getPtr(storage_id).?;
    };

    storage.time -= dt;
    if (storage.time > 0) return;
    defer storage.time = opts.cooldown;

    const obj_type: network_data.ObjectType = switch (@TypeOf(host.*)) {
        Enemy => .enemy,
        Entity => .entity,
        Ally => .ally,
        else => @compileError("Unsupported type"),
    };

    host.world.aoe(Player, host.x, host.y, obj_type, host.map_id, opts.radius, .{
        .phys_dmg = opts.phys_dmg,
        .magic_dmg = opts.magic_dmg,
        .true_dmg = opts.true_dmg,
        .effect = opts.effect,
        .effect_duration = opts.effect_duration,
        .aoe_color = opts.color,
    });
}

const FollowStorage = struct { time: i64 = 0 };
pub fn follow(comptime src_loc: std.builtin.SourceLocation, host: anytype, dt: i64, opts: struct {
    speed: f32,
    acquire_range: f32,
    cooldown: i64,
}) bool {
    verifyType(@TypeOf(host));

    const storage_id = getStorageId(src_loc);
    var storage = host.storages.follow.getPtr(storage_id) orelse blk: {
        host.storages.follow.put(main.allocator, storage_id, .{}) catch return false;
        break :blk host.storages.follow.getPtr(storage_id).?;
    };

    storage.time -= dt;
    if (storage.time > 0) return false;
    defer storage.time = opts.cooldown;

    const acq_sqr = opts.acquire_range * opts.acquire_range;

    const target = host.world.getNearestWithin(Player, host.x, host.y, acq_sqr) orelse return false;
    World.moveToward(host, target.x, target.y, opts.speed, dt);
    return true;
}

const WanderStorage = struct { move_cos: f32 = 0.0, move_sin: f32 = 0.0, rem_dist: f32 = 0.0 };
pub fn wander(comptime src_loc: std.builtin.SourceLocation, host: anytype, dt: i64, speed: f32) void {
    verifyType(@TypeOf(host));

    const storage_id = getStorageId(src_loc);
    var storage = host.storages.wander.getPtr(storage_id) orelse blk: {
        host.storages.wander.put(main.allocator, storage_id, .{}) catch return;
        break :blk host.storages.wander.getPtr(storage_id).?;
    };

    if (storage.rem_dist <= 0.0) {
        const angle = utils.rng.random().float(f32) * std.math.tau;
        storage.move_cos = @cos(angle);
        storage.move_sin = @sin(angle);
        storage.rem_dist = utils.rng.random().float(f32);
    }

    const fdt: f32 = @floatFromInt(dt);
    const dist = speed * (fdt / std.time.us_per_s);
    World.validatedMove(host, host.x + dist * storage.move_cos, host.y + dist * storage.move_sin);
    storage.rem_dist -= dist;
}

const ShootStorage = struct { cooldown: i64 = -1, rotate_count: f32 = 0.0 };
pub fn shoot(comptime src_loc: std.builtin.SourceLocation, host: *Enemy, time: i64, dt: i64, opts: struct {
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
    const storage_id = getStorageId(src_loc);
    var storage = host.storages.shoot.getPtr(storage_id) orelse blk: {
        host.storages.shoot.put(main.allocator, storage_id, .{}) catch return;
        break :blk host.storages.shoot.getPtr(storage_id).?;
    };

    storage.cooldown -= dt;
    if (storage.cooldown > 0) return;
    defer storage.cooldown = opts.cooldown;

    const radius_sqr = opts.radius * opts.radius;

    var angle: f32 = 0.0;
    if (std.math.isNan(opts.fixed_angle)) {
        if (host.world.getNearestWithin(Player, host.x, host.y, radius_sqr)) |p| {
            angle = if (opts.predictivity > 0 and opts.predictivity > utils.rng.random().float(f32))
                0.0 // predict(host, p)
            else
                std.math.atan2(p.y - host.y, p.x - host.x);
        }

        if (!std.math.isNan(opts.default_angle))
            angle = std.math.degreesToRadians(opts.default_angle);
    } else angle = std.math.degreesToRadians(opts.fixed_angle);

    angle += std.math.degreesToRadians(opts.angle_offset) + if (!std.math.isNan(opts.rotate_angle))
        std.math.degreesToRadians(opts.rotate_angle) * storage.rotate_count
    else
        0.0;
    storage.rotate_count += 1.0;

    const shoot_angle_deg = std.math.degreesToRadians(opts.shoot_angle);
    const fcount: f32 = @floatFromInt(opts.count);
    const start_angle = angle - shoot_angle_deg * (fcount - 1.0) / 2.0;
    const proj_index_start = host.next_proj_index;
    const proj_data = host.data.projectiles.?[opts.proj_index];

    for (0..opts.count) |i| {
        const fi: f32 = @floatFromInt(i);

        const map_id = host.world.add(Projectile, .{
            .owner_obj_type = .enemy,
            .owner_map_id = host.map_id,
            .x = host.x,
            .y = host.y,
            .angle = start_angle + fi * shoot_angle_deg,
            .start_time = time,
            .phys_dmg = proj_data.phys_dmg,
            .magic_dmg = proj_data.magic_dmg,
            .true_dmg = proj_data.true_dmg,
            .index = host.next_proj_index,
            .data = &host.data.projectiles.?[opts.proj_index],
        }) catch return;

        host.projectiles[host.next_proj_index] = map_id;
        host.next_proj_index +%= 1;
    }

    for (host.world.listForType(Player).items) |p| {
        const dx = p.x - host.x;
        const dy = p.y - host.y;
        if (dx * dx + dy * dy <= 20 * 20) {
            p.client.queuePacket(.{ .enemy_projectile = .{
                .proj_index = proj_index_start,
                .enemy_map_id = host.map_id,
                .proj_data_id = opts.proj_index,
                .x = host.x,
                .y = host.y,
                .angle = start_angle,
                .phys_dmg = proj_data.phys_dmg,
                .magic_dmg = proj_data.magic_dmg,
                .true_dmg = proj_data.true_dmg,
                .num_projs = opts.count,
                .angle_incr = shoot_angle_deg,
            } });
        }
    }
}
