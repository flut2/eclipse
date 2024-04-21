const std = @import("std");
const assets = @import("../assets.zig");
const game_data = @import("shared").game_data;
const main = @import("../main.zig");
const map = @import("map.zig");
const utils = @import("shared").utils;
const network = @import("../network.zig");
const particles = @import("particles.zig");

const Player = @import("player.zig").Player;
const GameObject = @import("game_object.zig").GameObject;

pub const Projectile = struct {
    var next_obj_id: i32 = 0x7F000000;

    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,
    screen_x: f32 = 0.0,
    screen_y: f32 = 0.0,
    size: f32 = 1.0,
    obj_id: i32 = 0,
    atlas_data: assets.AtlasData = assets.AtlasData.fromRaw(0, 0, 0, 0, .base),
    start_time: i64 = 0,
    angle: f32 = 0.0,
    visual_angle: f32 = 0.0,
    total_angle_change: f32 = 0.0,
    zero_vel_dist: f32 = -1.0,
    start_x: f32 = 0.0,
    start_y: f32 = 0.0,
    last_deflect: f32 = 0.0,
    bullet_id: u8 = 0,
    owner_id: i32 = 0,
    damage_players: bool = false,
    physical_damage: i32 = 0,
    magic_damage: i32 = 0,
    true_damage: i32 = 0,
    penetration: i32 = 0,
    piercing: i32 = 0,
    props: game_data.ProjProps,
    colors: []u32 = &[0]u32{},
    hit_list: std.AutoHashMap(i32, void) = undefined,
    heat_seek_fired: bool = false,
    last_hit_check: i64 = 0,
    disposed: bool = false,

    pub inline fn addToMap(self: *Projectile) void {
        self.hit_list = std.AutoHashMap(i32, void).init(main.allocator);
        self.start_time = main.current_time;

        const tex_list = self.props.texture_data;
        const tex = tex_list[@as(usize, @intCast(self.obj_id)) % tex_list.len];
        if (assets.atlas_data.get(tex.sheet)) |data| {
            self.atlas_data = data[tex.index];
        } else {
            std.log.err("Could not find sheet {s} for proj with id {d}. Using error texture", .{ tex.sheet, self.obj_id });
            self.atlas_data = assets.error_data;
        }

        self.colors = assets.atlas_to_color_data.get(@bitCast(self.atlas_data)) orelse blk: {
            std.log.err("Could not parse color data for projectile with id {d}. Setting it to empty", .{self.obj_id});
            break :blk &[0]u32{};
        };

        self.obj_id = Projectile.next_obj_id + 1;
        Projectile.next_obj_id += 1;
        if (Projectile.next_obj_id == std.math.maxInt(i32))
            Projectile.next_obj_id = 0x7F000000;

        map.add_lock.lockShared();
        defer map.add_lock.unlockShared();
        map.entities_to_add.append(.{ .projectile = self.* }) catch |e| {
            std.log.err("Could not add projectile to map (obj_id={d}, x={d}, y={d}): {}", .{ self.obj_id, self.x, self.y, e });
        };
    }

    fn findTargetPlayer(x: f32, y: f32, radius: f32) ?*Player {
        var min_dist = radius * radius;
        var target: ?*Player = null;

        for (map.entities.items) |*en| {
            if (en.* == .player) {
                const dist_sqr = utils.distSqr(en.player.x, en.player.y, x, y);
                if (dist_sqr < min_dist) {
                    min_dist = dist_sqr;
                    target = &en.player;
                }
            }
        }

        return target;
    }

    fn findTargetObject(x: f32, y: f32, radius: f32, enemy_only: bool) ?*GameObject {
        var min_dist = radius * radius;
        var target: ?*GameObject = null;

        for (map.entities.items) |*en| {
            if (en.* == .object) {
                if (en.object.props.is_enemy or !enemy_only and (en.object.props.occupy_square or en.object.props.enemy_occupy_square)) {
                    const dist_sqr = utils.distSqr(en.object.x, en.object.y, x, y);
                    if (dist_sqr < min_dist) {
                        min_dist = dist_sqr;
                        target = &en.object;
                    }
                }
            }
        }

        return target;
    }

    fn updatePosition(self: *Projectile, elapsed: i64, dt: f32) void {
        if (self.props.heat_seek_radius > 0 and elapsed >= self.props.heat_seek_delay and !self.heat_seek_fired) {
            var target_x: f32 = -1.0;
            var target_y: f32 = -1.0;

            if (self.damage_players) {
                if (findTargetPlayer(self.x, self.y, self.props.heat_seek_radius * self.props.heat_seek_radius)) |player| {
                    target_x = player.x;
                    target_y = player.y;
                }
            } else {
                if (findTargetObject(self.x, self.y, self.props.heat_seek_radius * self.props.heat_seek_radius, true)) |object| {
                    target_x = object.x;
                    target_y = object.y;
                }
            }

            if (target_x > 0 and target_y > 0) {
                self.angle = @mod(std.math.atan2(target_y - self.y, target_x - self.x), std.math.tau);
                self.heat_seek_fired = true;
            }
        }

        var angle_change: f32 = 0.0;
        if (self.props.angle_change != 0 and elapsed < self.props.angle_change_end and elapsed >= self.props.angle_change_delay) {
            angle_change += dt / std.time.us_per_s * self.props.angle_change;
        }

        if (self.props.angle_change_accel != 0 and elapsed >= self.props.angle_change_accel_delay) {
            const time_in_accel: f32 = @floatFromInt(elapsed - self.props.angle_change_accel_delay);
            angle_change += dt / std.time.us_per_s * self.props.angle_change_accel * time_in_accel / std.time.us_per_s;
        }

        if (angle_change != 0.0) {
            if (self.props.angle_change_clamp != 0) {
                const clamp_dt = self.props.angle_change_clamp - self.total_angle_change;
                const clamped_change = @min(angle_change, clamp_dt);
                self.total_angle_change += clamped_change;
                self.angle += clamped_change;
            } else {
                self.angle += angle_change;
            }
        }

        var dist: f32 = 0.0;
        const uses_zero_vel = self.props.zero_velocity_delay > 0;
        if (!uses_zero_vel or self.props.zero_velocity_delay > elapsed) {
            if (self.props.accel == 0.0 or elapsed < self.props.accel_delay) {
                dist = dt * self.props.speed;
            } else {
                const time_in_accel: f32 = @floatFromInt(elapsed - self.props.accel_delay);
                const accel_dist = dt * ((self.props.speed * 10 * std.time.us_per_s + self.props.accel * time_in_accel / std.time.us_per_s) / (10 * std.time.us_per_s));
                if (self.props.speed_clamp != -1) {
                    dist = accel_dist;
                } else {
                    const clamp_dist = dt * self.props.speed_clamp / (10 * std.time.us_per_s);
                    dist = if (self.props.accel > 0) @min(accel_dist, clamp_dist) else @max(accel_dist, clamp_dist);
                }
            }
        } else {
            if (self.zero_vel_dist == -1.0) {
                self.zero_vel_dist = utils.dist(self.start_x, self.start_y, self.x, self.y);
            }

            self.x = self.start_x + self.zero_vel_dist * @cos(self.angle);
            self.y = self.start_y + self.zero_vel_dist * @sin(self.angle);
            return;
        }

        if (self.props.parametric) {
            const t = @as(f32, @floatFromInt(@divTrunc(elapsed, self.props.lifetime))) * std.math.tau;
            const x = @sin(t) * if (self.bullet_id % 2 == 0) @as(f32, 1.0) else @as(f32, -1.0);
            const y = @sin(2 * t) * if (self.bullet_id % 4 < 2) @as(f32, 1.0) else @as(f32, -1.0);
            self.x += (x * @cos(self.angle) - y * @sin(self.angle)) * self.props.magnitude;
            self.y += (x * @sin(self.angle) + y * @cos(self.angle)) * self.props.magnitude;
        } else {
            if (self.props.boomerang and elapsed > @divFloor(self.props.lifetime, 2))
                dist = -dist;

            self.x += dist * @cos(self.angle);
            self.y += dist * @sin(self.angle);
            if (self.props.amplitude != 0) {
                const phase: f32 = if (self.bullet_id % 2 == 0) 0.0 else std.math.pi;
                const time_ratio: f32 = @as(f32, @floatFromInt(elapsed)) / @as(f32, @floatFromInt(self.props.lifetime));
                const deflection_target = self.props.amplitude * @sin(phase + time_ratio * self.props.frequency * std.math.tau);
                self.x += (deflection_target - self.last_deflect) * @cos(self.angle + std.math.pi / 2.0);
                self.y += (deflection_target - self.last_deflect) * @sin(self.angle + std.math.pi / 2.0);
                self.last_deflect = deflection_target;
            }
        }
    }

    pub inline fn update(self: *Projectile, time: i64, dt: f32, allocator: std.mem.Allocator) bool {
        const elapsed = time - self.start_time;
        if (elapsed >= self.props.lifetime)
            return false;

        const last_x = self.x;
        const last_y = self.y;

        self.updatePosition(elapsed, dt);
        if (self.x < 0 or self.y < 0) {
            if (self.damage_players)
                main.server.queuePacket(.{ .square_hit = .{
                    .time = time,
                    .bullet_id = self.bullet_id,
                    .obj_id = self.owner_id,
                } });

            return false;
        }

        if (last_x == 0 and last_y == 0) {
            self.visual_angle = self.angle;
        } else {
            const y_dt: f32 = self.y - last_y;
            const x_dt: f32 = self.x - last_x;
            self.visual_angle = std.math.atan2(y_dt, x_dt);
        }

        if (time - self.last_hit_check < 16 * std.time.us_per_ms)
            return true;

        self.last_hit_check = time;

        if (map.getSquare(self.x, self.y, true)) |square| {
            const en = map.findEntityConst(square.static_obj_id);
            if (square.tile_type == 0xFFFE or square.tile_type == 0xFFFF) {
                if (self.damage_players) {
                    main.server.queuePacket(.{ .square_hit = .{
                        .time = time,
                        .bullet_id = self.bullet_id,
                        .obj_id = self.owner_id,
                    } });
                } else {
                    if (en) |_| {
                        var effect = particles.HitEffect{
                            .x = self.x,
                            .y = self.y,
                            .colors = self.colors,
                            .angle = self.angle,
                            .speed = self.props.speed,
                            .size = 1.0,
                            .amount = 3,
                        };
                        effect.addToMap();
                    }
                }
                return false;
            }

            if (en) |entity| {
                if (entity == .object and
                    (entity.object.props.is_enemy or self.damage_players) and
                    (entity.object.props.enemy_occupy_square or (!self.props.passes_cover and entity.object.props.occupy_square)))
                {
                    if (self.damage_players) {
                        main.server.queuePacket(.{ .other_hit = .{
                            .time = time,
                            .bullet_id = self.bullet_id,
                            .object_id = self.owner_id,
                            .target_id = square.static_obj_id,
                        } });
                    } else {
                        var effect = particles.HitEffect{
                            .x = self.x,
                            .y = self.y,
                            .colors = self.colors,
                            .angle = self.angle,
                            .speed = self.props.speed,
                            .size = 1.0,
                            .amount = 3,
                        };
                        effect.addToMap();
                    }
                    return false;
                }
            }
        } else {
            if (self.damage_players) {
                main.server.queuePacket(.{ .square_hit = .{
                    .time = time,
                    .bullet_id = self.bullet_id,
                    .obj_id = self.owner_id,
                } });
            }
        }

        if (self.damage_players) {
            if (findTargetPlayer(self.x, self.y, 0.57)) |player| {
                if (self.hit_list.contains(player.obj_id))
                    return true;

                if (player.condition.invulnerable) {
                    assets.playSfx(player.props.hit_sound);
                    return false;
                }

                if (map.local_player_id == player.obj_id) {
                    const phys_dmg = map.physicalDamage(@floatFromInt(self.physical_damage), @floatFromInt(player.defense - self.penetration), player.condition);
                    const magic_dmg = map.magicDamage(@floatFromInt(self.magic_damage), @floatFromInt(player.resistance - self.piercing), player.condition);
                    const true_dmg: f32 = @floatFromInt(self.true_damage);
                    const dead = @as(f32, @floatFromInt(player.hp)) <= (phys_dmg + magic_dmg + true_dmg);

                    player.takeDamage(
                        @intFromFloat(phys_dmg * player.hit_multiplier),
                        @intFromFloat(magic_dmg * player.hit_multiplier),
                        @intFromFloat(true_dmg * player.hit_multiplier),
                        dead,
                        utils.Condition.fromCondSlice(self.props.effects),
                        self.colors,
                        self.angle,
                        self.props.speed,
                        allocator,
                    );
                    main.server.queuePacket(.{ .player_hit = .{ .bullet_id = self.bullet_id, .object_id = self.owner_id } });
                } else if (!self.props.multi_hit) {
                    var effect = particles.HitEffect{
                        .x = self.x,
                        .y = self.y,
                        .colors = self.colors,
                        .angle = self.angle,
                        .speed = self.props.speed,
                        .size = 1.0,
                        .amount = 3,
                    };
                    effect.addToMap();

                    main.server.queuePacket(.{ .other_hit = .{
                        .time = time,
                        .bullet_id = self.bullet_id,
                        .object_id = self.owner_id,
                        .target_id = player.obj_id,
                    } });
                } else {
                    std.log.err("Unknown logic for player side of hit logic unexpected branch, todo figure out how to fix this mabye implement send_message check: {s}", .{player.name orelse "Unknown"});
                }

                if (self.props.multi_hit) {
                    self.hit_list.put(player.obj_id, {}) catch |e| {
                        std.log.err("failed to add player to hit_list: {}", .{e});
                    };
                } else {
                    return false;
                }
            }
        } else {
            if (findTargetObject(self.x, self.y, 0.57, false)) |object| {
                if (self.hit_list.contains(object.obj_id))
                    return true;

                if (object.condition.invulnerable) {
                    assets.playSfx(object.props.hit_sound);
                    return false;
                }

                if (object.props.is_enemy) {
                    const phys_dmg = map.physicalDamage(@floatFromInt(self.physical_damage), @floatFromInt(object.defense - self.penetration), object.condition);
                    const magic_dmg = map.magicDamage(@floatFromInt(self.magic_damage), @floatFromInt(object.resistance - self.piercing), object.condition);
                    const true_dmg: f32 = @floatFromInt(self.true_damage);
                    const dead = @as(f32, @floatFromInt(object.hp)) <= (phys_dmg + magic_dmg + true_dmg);

                    object.takeDamage(
                        @intFromFloat(phys_dmg),
                        @intFromFloat(magic_dmg),
                        @intFromFloat(true_dmg),
                        dead,
                        utils.Condition.fromCondSlice(self.props.effects),
                        self.colors,
                        self.angle,
                        self.props.speed,
                        allocator,
                    );

                    main.server.queuePacket(.{ .enemy_hit = .{
                        .time = time,
                        .bullet_id = self.bullet_id,
                        .target_id = object.obj_id,
                        .killed = dead,
                    } });
                } else if (!self.props.multi_hit) {
                    var effect = particles.HitEffect{
                        .x = self.x,
                        .y = self.y,
                        .colors = self.colors,
                        .angle = self.angle,
                        .speed = self.props.speed,
                        .size = 1.0,
                        .amount = 3,
                    };
                    effect.addToMap();

                    main.server.queuePacket(.{ .other_hit = .{
                        .time = time,
                        .bullet_id = self.bullet_id,
                        .object_id = self.owner_id,
                        .target_id = object.obj_id,
                    } });
                }

                if (self.props.multi_hit) {
                    self.hit_list.put(object.obj_id, {}) catch |e| {
                        std.log.err("failed to add object to hit_list: {}", .{e});
                    };
                } else {
                    return false;
                }
            }
        }

        return true;
    }
};
