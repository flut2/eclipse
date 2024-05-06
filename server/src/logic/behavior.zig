const std = @import("std");
const utils = @import("shared").utils;
const xml = @import("shared").xml;
const main = @import("../main.zig");

const Projectile = @import("../map/projectile.zig").Projectile;
const Enemy = @import("../map/enemy.zig").Enemy;

pub const BehaviorTag = enum {
    wander,
    shoot,
};

pub const BehaviorStorage = union(BehaviorTag) {
    wander: WanderStorage,
    shoot: ShootStorage,
};

pub const Behavior = union(BehaviorTag) {
    wander: Wander,
    shoot: Shoot,

    pub fn tick(self: *Behavior, host: *Enemy, time: i64, dt: i64) !void {
        switch (self.*) {
            inline else => |*behav, tag| {
                if (host.behavior_storage.getPtr(self)) |storage| {
                    switch (storage.*) {
                        inline else => |*s, s_tag| {
                            if (tag == s_tag)
                                try behav.tick(host, time, dt, s);
                        },
                    }
                } else {
                    const tag_name = @tagName(tag);
                    var storage = @unionInit(BehaviorStorage, tag_name, .{});
                    try behav.tick(host, time, dt, &@field(storage, tag_name));
                    try host.behavior_storage.put(self, storage);
                }
            },
        }
    }

    pub fn entry(self: *Behavior, host: *Enemy, time: i64) !void {
        switch (self.*) {
            inline else => |*behav, tag| {
                if (host.behavior_storage.getPtr(self)) |storage| {
                    switch (storage.*) {
                        inline else => |*s, s_tag| {
                            if (tag == s_tag)
                                try behav.entry(host, time, s);
                        },
                    }
                } else {
                    const tag_name = @tagName(tag);
                    var storage = @unionInit(BehaviorStorage, tag_name, .{});
                    try behav.entry(host, time, &@field(storage, tag_name));
                    try host.behavior_storage.put(self, storage);
                }
            },
        }
    }

    pub fn exit(self: *Behavior, host: *Enemy, time: i64) !void {
        switch (self.*) {
            inline else => |*behav, tag| {
                if (host.behavior_storage.getPtr(self)) |storage| {
                    switch (storage.*) {
                        inline else => |*s, s_tag| {
                            if (tag == s_tag)
                                try behav.exit(host, time, s);
                        },
                    }
                } else {
                    const tag_name = @tagName(tag);
                    var storage = @unionInit(BehaviorStorage, tag_name, .{});
                    try behav.exit(host, time, &@field(storage, tag_name));
                    try host.behavior_storage.put(self, storage);
                }
            },
        }
    }

    pub fn deinit(self: Behavior, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

const WanderStorage = struct { move_angle: f32 = 0.0, rem_dist: f32 = 0.0 };
pub const Wander = struct {
    speed: f32,

    pub fn entry(_: Wander, _: *Enemy, _: i64, _: *WanderStorage) !void {}
    pub fn exit(_: Wander, _: *Enemy, _: i64, _: *WanderStorage) !void {}

    pub fn tick(self: Wander, host: *Enemy, _: i64, dt: i64, storage: *WanderStorage) !void {
        if (storage.rem_dist <= 0.0) {
            storage.move_angle = utils.rng.random().float(f32) * std.math.tau;
            storage.rem_dist = utils.rng.random().float(f32);
        }

        const fdt: f32 = @floatFromInt(dt);
        const dist = self.speed * (fdt / std.time.us_per_s);
        host.move(host.x + dist * @cos(storage.move_angle), host.y + dist * @sin(storage.move_angle));
        storage.rem_dist -= dist;
    }

    pub fn parse(node: xml.Node, _: std.mem.Allocator) !Behavior {
        return .{ .wander = .{
            .speed = try node.getAttributeFloat("speed", f32, 0.0),
        } };
    }
};

const ShootStorage = struct { cooldown: i64 = -1, rotate_count: f32 = 0.0 };
pub const Shoot = struct {
    proj_index: u8,
    count: u8,
    radius_sqr: f32,
    shoot_angle: f32,
    fixed_angle: f32,
    default_angle: f32,
    angle_offset: f32,
    rotate_angle: f32,
    cooldown: i64,
    cooldown_offset: i64,
    predictive: f32,

    pub fn entry(self: Shoot, _: *Enemy, _: i64, storage: *ShootStorage) !void {
        storage.cooldown = self.cooldown_offset;
    }

    pub fn exit(_: Shoot, _: *Enemy, _: i64, _: *ShootStorage) !void {}

    pub fn tick(self: Shoot, host: *Enemy, time: i64, dt: i64, storage: *ShootStorage) !void {
        storage.cooldown -= dt;
        if (storage.cooldown > 0)
            return;

        defer storage.cooldown = self.cooldown;

        var angle: f32 = 0.0;
        if (self.fixed_angle < 0.0) {
            blk: {
                {
                    host.world.player_lock.lock();
                    defer host.world.player_lock.unlock();
                    for (host.world.players.items) |p| {
                        const dx = p.x - host.x;
                        const dy = p.y - host.y;
                        if (dx * dx + dy * dy <= self.radius_sqr and !p.condition.invisible) {
                            angle = if (self.predictive > 0 and self.predictive > utils.rng.random().float(f32))
                                0.0 // predict(host, p)
                            else
                                std.math.atan2(p.y - host.y, p.x - host.x);
                            break :blk;
                        }
                    }
                }

                if (self.default_angle >= 0.0)
                    angle = self.default_angle;
            }
        } else angle = self.fixed_angle;

        angle += self.angle_offset + if (self.rotate_angle > 0.0) self.rotate_angle * storage.rotate_count else 0.0;
        storage.rotate_count += 1.0;

        const fcount: f32 = @floatFromInt(self.count);
        const start_angle = angle - self.shoot_angle * (fcount - 1.0) / 2.0;
        const bullet_id_start = host.next_bullet_id;
        const proj_props = host.props.projectiles[self.proj_index];

        for (0..self.count) |i| {
            const fi: f32 = @floatFromInt(i);

            var proj: Projectile = .{
                .owner_id = host.obj_id,
                .x = host.x,
                .y = host.y,
                .angle = start_angle + fi * self.shoot_angle,
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
                    .bullet_index = self.proj_index,
                    .x = host.x,
                    .y = host.y,
                    .angle = start_angle,
                    .phys_dmg = @intCast(proj_props.physical_damage),
                    .magic_dmg = @intCast(proj_props.magic_damage),
                    .true_dmg = @intCast(proj_props.true_damage),
                    .num_shots = self.count,
                    .angle_inc = self.shoot_angle,
                } });
            }
        }
    }

    pub fn parse(node: xml.Node, _: std.mem.Allocator) !Behavior {
        const count = try node.getAttributeInt("count", u8, 1);
        const fcount: f32 = @floatFromInt(count);
        const radius = try node.getAttributeFloat("radius", f32, 20.0);
        return .{ .shoot = .{
            .radius_sqr = radius * radius,
            .count = count,
            .proj_index = try node.getAttributeInt("projectileIndex", u8, 0),
            .shoot_angle = std.math.degreesToRadians(f32, try node.getAttributeFloat("shootAngle", f32, 360.0) / fcount),
            .angle_offset = std.math.degreesToRadians(f32, try node.getAttributeFloat("angleOffset", f32, 0.0)),
            .rotate_angle = std.math.degreesToRadians(f32, try node.getAttributeFloat("rotateAngle", f32, -1.0)),
            .default_angle = std.math.degreesToRadians(f32, try node.getAttributeFloat("defaultAngle", f32, -1.0)),
            .fixed_angle = std.math.degreesToRadians(f32, try node.getAttributeFloat("fixedAngle", f32, -1.0)),
            .cooldown = try node.getAttributeInt("cooldown", i64, 1000) * std.time.us_per_ms,
            .cooldown_offset = try node.getAttributeInt("cooldownOffset", i64, 0) * std.time.us_per_ms,
            .predictive = try node.getAttributeFloat("predictive", f32, 0.0),
        } };
    }
};
