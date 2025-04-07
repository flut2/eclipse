const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const utils = shared.utils;
const i32f = utils.i32f;
const f32i = utils.f32i;

const assets = @import("../assets.zig");
const Camera = @import("../Camera.zig");
const px_per_tile = Camera.px_per_tile;
const main = @import("../main.zig");
const Renderer = @import("../render/Renderer.zig");
const Ally = @import("Ally.zig");
const Enemy = @import("Enemy.zig");
const Entity = @import("Entity.zig");
const map = @import("map.zig");
const particles = @import("particles.zig");
const Player = @import("Player.zig");
const Square = @import("Square.zig");

const Projectile = @This();

x: f32 = 0.0,
y: f32 = 0.0,
z: f32 = 0.0,
size: f32 = 1.0,
atlas_data: assets.AtlasData = .default,
start_time: i64 = 0,
angle: f32 = 0.0,
visual_angle: f32 = 0.0,
total_angle_change: f32 = 0.0,
zero_vel_dist: f32 = -1.0,
start_x: f32 = 0.0,
start_y: f32 = 0.0,
last_deflect: f32 = 0.0,
index: u8 = 0,
owner_map_id: u32 = std.math.maxInt(u32),
damage_players: bool = false,
phys_dmg: i32 = 0,
magic_dmg: i32 = 0,
true_dmg: i32 = 0,
data: *const game_data.ProjectileData,
colors: []u32 = &.{},
hit_list: std.AutoHashMapUnmanaged(u32, void) = .empty,
heat_seek_fired: bool = false,
time_dilation_slow: f32 = 0.0,
last_hit_check: i64 = 0,
sort_random: u16 = 0xAAAA,

pub fn addToMap(proj_data: Projectile) void {
    var self = proj_data;
    self.start_time = main.current_time;
    self.start_x = self.x;
    self.start_y = self.y;

    const tex_list = self.data.textures;
    const tex = tex_list[utils.rng.next() % tex_list.len];
    if (assets.atlas_data.get(tex.sheet)) |data| {
        self.atlas_data = data[tex.index];
    } else {
        std.log.err("Could not find sheet {s} for projectile. Using error texture", .{tex.sheet});
        self.atlas_data = assets.error_data;
    }

    self.colors = assets.atlas_to_color_data.get(@bitCast(self.atlas_data)) orelse blk: {
        std.log.err("Could not parse color data for projectile. Setting it to empty", .{});
        break :blk &.{};
    };

    self.sort_random = utils.rng.random().int(u16);

    map.listForType(Projectile).append(main.allocator, self) catch main.oomPanic();
}

pub fn deinit(self: *Projectile) void {
    self.hit_list.deinit(main.allocator);
}

fn findTargetAlly(x: f32, y: f32, radius: f32) ?*Ally {
    var min_dist = radius * radius;
    var target: ?*Ally = null;

    for (map.listForType(Ally).items) |*p| {
        const dist_sqr = utils.distSqr(p.x, p.y, x, y);
        if (dist_sqr < min_dist) {
            min_dist = dist_sqr;
            target = p;
        }
    }

    return target;
}

fn findTargetPlayer(x: f32, y: f32, radius: f32) ?*Player {
    var min_dist = radius * radius;
    var target: ?*Player = null;

    for (map.listForType(Player).items) |*p| {
        const dist_sqr = utils.distSqr(p.x, p.y, x, y);
        if (dist_sqr < min_dist) {
            min_dist = dist_sqr;
            target = p;
        }
    }

    return target;
}

fn findTargetEnemy(x: f32, y: f32, radius: f32) ?*Enemy {
    var min_dist = radius * radius;
    var target: ?*Enemy = null;

    for (map.listForType(Enemy).items) |*e| {
        if (e.data.health <= 0) continue;

        const dist_sqr = utils.distSqr(e.x, e.y, x, y);
        if (dist_sqr < min_dist) {
            min_dist = dist_sqr;
            target = e;
        }
    }

    return target;
}

fn updatePosition(self: *Projectile, elapsed: f32, dt: f32) void {
    if (self.data.heat_seek_radius > 0 and elapsed >= self.data.heat_seek_delay and !self.heat_seek_fired) {
        var target_x: f32 = -1.0;
        var target_y: f32 = -1.0;

        if (self.damage_players) {
            if (findTargetAlly(self.x, self.y, self.data.heat_seek_radius * self.data.heat_seek_radius)) |ally| {
                target_x = ally.x;
                target_y = ally.y;
            } else if (findTargetPlayer(self.x, self.y, self.data.heat_seek_radius * self.data.heat_seek_radius)) |player| {
                target_x = player.x;
                target_y = player.y;
            }
        } else if (findTargetEnemy(self.x, self.y, self.data.heat_seek_radius * self.data.heat_seek_radius)) |enemy| {
            target_x = enemy.x;
            target_y = enemy.y;
        }

        if (target_x > 0 and target_y > 0) {
            self.angle = @mod(std.math.atan2(target_y - self.y, target_x - self.x), std.math.tau);
            self.heat_seek_fired = true;
        }
    }

    var angle_change: f32 = 0.0;
    if (self.data.angle_change != 0 and elapsed < self.data.angle_change_end and elapsed >= self.data.angle_change_delay)
        angle_change += dt * std.math.degreesToRadians(self.data.angle_change);

    if (self.data.angle_change_accel != 0 and elapsed >= self.data.angle_change_accel_delay) {
        const time_in_accel = elapsed - self.data.angle_change_accel_delay;
        angle_change += dt * std.math.degreesToRadians(self.data.angle_change_accel) * time_in_accel;
    }

    if (angle_change != 0.0) {
        if (self.data.angle_change_clamp != 0) {
            const clamp_dt = self.data.angle_change_clamp - self.total_angle_change;
            const clamped_change = @min(angle_change, clamp_dt);
            self.total_angle_change += clamped_change;
            self.angle += clamped_change;
        } else self.angle += angle_change;
    }

    var dist: f32 = 0.0;
    const uses_zero_vel = self.data.zero_velocity_delay > 0;
    if (!uses_zero_vel or self.data.zero_velocity_delay > elapsed) {
        if (self.data.accel != 0.0 and elapsed >= self.data.accel_delay) {
            const time_in_accel = elapsed - self.data.accel_delay;
            const accel_dist = dt * (self.data.speed * 10.0 + self.data.accel * 10.0 * time_in_accel);
            if (self.data.speed_clamp != 0.0) {
                const clamp_dist = dt * self.data.speed_clamp * 10.0;
                dist = if (self.data.accel > 0) @min(accel_dist, clamp_dist) else @max(accel_dist, clamp_dist);
            } else dist = accel_dist;
        } else dist = dt * self.data.speed * 10.0;
    } else {
        if (self.zero_vel_dist == -1.0) self.zero_vel_dist = utils.dist(self.start_x, self.start_y, self.x, self.y);

        self.x = self.start_x + self.zero_vel_dist * @cos(self.angle);
        self.y = self.start_y + self.zero_vel_dist * @sin(self.angle);
        return;
    }

    if (self.data.boomerang and elapsed > self.data.duration / 2.0) dist = -dist;

    self.x += dist * @cos(self.angle);
    self.y += dist * @sin(self.angle);
    if (self.data.amplitude != 0) {
        const phase: f32 = if (self.index % 2 == 0) 0.0 else std.math.pi;
        const time_ratio = elapsed / self.data.duration;
        const deflection_target = self.data.amplitude * @sin(phase + time_ratio * self.data.frequency * std.math.tau);
        self.x += (deflection_target - self.last_deflect) * @cos(self.angle + std.math.pi / 2.0);
        self.y += (deflection_target - self.last_deflect) * @sin(self.angle + std.math.pi / 2.0);
        self.last_deflect = deflection_target;
    }
}

pub fn draw(
    self: *Projectile,
    generics: *std.ArrayListUnmanaged(Renderer.GenericData),
    sort_extras: *std.ArrayListUnmanaged(f32),
    lights: *std.ArrayListUnmanaged(Renderer.LightData),
    sort_randoms: *std.ArrayListUnmanaged(u16),
    float_time_ms: f32,
) void {
    defer self.time_dilation_slow = 0.0;

    if (!main.camera.visibleInCamera(self.x, self.y)) return;

    const size = Camera.size_mult * main.camera.scale * self.data.size_mult;
    const w = self.atlas_data.texWRaw() * size;
    const h = self.atlas_data.texHRaw() * size;
    var screen_pos = main.camera.worldToScreen(self.x, self.y);
    const z_offset = self.z * -px_per_tile - h + assets.padding * size;
    const rotation = self.data.rotation;
    const angle_correction = f32i(self.data.angle_correction) * std.math.degreesToRadians(45);
    const angle = -(self.visual_angle + angle_correction +
        (if (rotation == 0.0) 0.0 else std.math.degreesToRadians(float_time_ms / (1 / rotation))));

    if (self.data.float.time > 0) {
        const time_us = self.data.float.time * std.time.us_per_s;
        screen_pos.y -= self.data.float.height / 2.0 * (@sin(f32i(main.current_time) / time_us) + 1) * px_per_tile * main.camera.scale;
    }

    if (main.settings.enable_lights)
        Renderer.drawLight(
            lights,
            self.data.light,
            screen_pos.x - w / 2.0,
            screen_pos.y + z_offset,
            w,
            h,
            main.camera.scale,
            float_time_ms,
        );

    const color: u32 = if (self.time_dilation_slow > 0.0) 0x0000FF else 0x000000;
    const color_intensity: f32 = if (self.time_dilation_slow > 0.0) 0.33 else 0.0;

    Renderer.drawQuad(
        generics,
        sort_extras,
        screen_pos.x - w / 2.0,
        screen_pos.y + z_offset,
        w,
        h,
        self.atlas_data,
        .{ .shadow_texel_mult = 2.0 / size, .rotation = angle, .color = color, .color_intensity = color_intensity },
    );
    sort_randoms.append(main.allocator, self.sort_random) catch main.oomPanic();
}

pub fn update(self: *Projectile, time: i64, dt: f32) bool {
    const elapsed_sec = f32i(time - self.start_time) / std.time.us_per_s;
    const dt_sec = dt / std.time.us_per_s;
    if (elapsed_sec >= self.data.duration) return false;

    const last_x = self.x;
    const last_y = self.y;

    self.updatePosition(elapsed_sec, dt_sec * (1.0 - self.time_dilation_slow));
    if (self.x < 0 or self.y < 0 or
        self.x >= f32i(map.info.width - 1) or self.y >= f32i(map.info.height - 1))
        return false;

    if (last_x != 0 or last_y != 0) {
        const y_dt: f32 = self.y - last_y;
        const x_dt: f32 = self.x - last_x;
        self.visual_angle = std.math.atan2(y_dt, x_dt);
    } else self.visual_angle = self.angle;

    if (time - self.last_hit_check < 16 * std.time.us_per_ms) return true;

    self.last_hit_check = time;

    const square = map.getSquareCon(self.x, self.y, false).?;
    if (square.data_id == Square.editor_tile or square.data_id == Square.empty_tile) return false;

    if (map.findObjectCon(Entity, square.entity_map_id)) |e|
        if (e.data.occupy_square or e.data.full_occupy or e.data.is_wall) {
            particles.HitEffect.addToMap(.{
                .x = self.x,
                .y = self.y,
                .colors = self.colors,
                .angle = self.angle,
                .speed = self.data.speed,
                .size = 1.0,
                .amount = 3,
            });
            return false;
        };

    if (self.damage_players) {
        if (findTargetAlly(self.x, self.y, 0.6)) |ally| return self.hit(Ally, ally, time);
        if (findTargetPlayer(self.x, self.y, 0.6)) |player| return self.hit(Player, player, time);
    } else if (findTargetEnemy(self.x, self.y, 0.6)) |enemy| return self.hit(Enemy, enemy, time);

    return true;
}

fn hit(self: *Projectile, comptime T: type, obj: *T, time: i64) bool {
    if (self.hit_list.contains(obj.map_id)) return true;

    particles.HitEffect.addToMap(.{
        .x = self.x,
        .y = self.y,
        .colors = self.colors,
        .angle = self.angle,
        .speed = self.data.speed,
        .size = 1.0,
        .amount = 3,
    });

    if (obj.condition.invulnerable) {
        self.hit_list.put(main.allocator, obj.map_id, {}) catch main.oomPanic();
        assets.playSfx(obj.data.hit_sound);
        return false;
    }

    var phys_dmg: i32 = 0;
    var magic_dmg: i32 = 0;
    var true_dmg = self.true_dmg;
    switch (@TypeOf(obj.*)) {
        Player => {
            if (map.info.player_map_id != obj.map_id) return self.data.piercing;
            phys_dmg = i32f(f32i(game_data.physDamage(self.phys_dmg, obj.data.stats.defense + obj.defense_bonus, obj.condition)) * obj.hit_mult);
            magic_dmg = i32f(f32i(game_data.magicDamage(self.magic_dmg, obj.data.stats.resistance + obj.resistance_bonus, obj.condition)) * obj.hit_mult);
            true_dmg = i32f(f32i(true_dmg) * obj.hit_mult);
            main.game_server.sendPacket(.{ .player_hit = .{ .proj_index = self.index, .enemy_map_id = self.owner_map_id } });
        },
        Ally => {
            phys_dmg = game_data.physDamage(self.phys_dmg, obj.data.defense, obj.condition);
            magic_dmg = game_data.magicDamage(self.magic_dmg, obj.data.resistance, obj.condition);
            main.game_server.sendPacket(.{ .ally_hit = .{
                .ally_map_id = obj.map_id,
                .proj_index = self.index,
                .enemy_map_id = self.owner_map_id,
            } });
        },
        Enemy => {
            phys_dmg = game_data.physDamage(self.phys_dmg, obj.data.defense, obj.condition);
            magic_dmg = game_data.magicDamage(self.magic_dmg, obj.data.resistance, obj.condition);
            main.game_server.sendPacket(.{ .enemy_hit = .{
                .time = time,
                .proj_index = self.index,
                .enemy_map_id = obj.map_id,
            } });
        },
        else => @compileError("Invalid type"),
    }

    const cond: utils.Condition = .fromCondSlice(self.data.conditions);
    if (phys_dmg > 0) map.takeDamage(obj, phys_dmg, .physical, cond, self.colors);
    if (magic_dmg > 0) map.takeDamage(obj, magic_dmg, .magic, cond, self.colors);
    if (true_dmg > 0) map.takeDamage(obj, true_dmg, .true, cond, self.colors);

    self.hit_list.put(main.allocator, obj.map_id, {}) catch main.oomPanic();
    return self.data.piercing;
}
