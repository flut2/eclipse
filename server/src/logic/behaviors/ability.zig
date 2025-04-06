const std = @import("std");

const shared = @import("shared");
const network_data = shared.network_data;
const utils = shared.utils;
const f32i = utils.f32i;
const i32f = utils.i32f;
const u32f = utils.u32f;

const main = @import("../../main.zig");
const Ally = @import("../../map/Ally.zig");
const Enemy = @import("../../map/Enemy.zig");
const Entity = @import("../../map/Entity.zig");
const maps = @import("../../map/maps.zig");
const Player = @import("../../map/Player.zig");
const World = @import("../../World.zig");
const Metadata = @import("../behavior.zig").BehaviorMetadata;
const logic = @import("../logic.zig");

pub const BoulderBuddy = struct {
    pub const data: Metadata = .{
        .type = .ally,
        .name = "Boulder Buddy",
    };

    pub fn tick(_: *BoulderBuddy, host: *Ally, _: i64, dt: i64) !void {
        const world = maps.worlds.getPtr(host.world_id) orelse return;
        const owner = world.findRef(Player, host.owner_map_id) orelse {
            logic.wander(@src(), host, dt, 2.5);
            return;
        };

        const dist_sqr = utils.distSqr(owner.x, owner.y, host.x, host.y);
        if (dist_sqr < 1 * 1) {
            logic.wander(@src(), host, dt, 2.5);
            return;
        }

        if (dist_sqr < 3 * 3) {
            if (!logic.orbitPlayer(host, dt, .{
                .speed = 3.85,
                .radius = 2.0,
                .acquire_range = 3.5,
                .target_map_id = host.owner_map_id,
                .rotate_speed = 1.5,
            })) logic.wander(@src(), host, dt, 2.5);
            return;
        }

        if (dist_sqr > 16 * 16) {
            const angle = utils.rng.random().float(f32) * std.math.tau;
            const radius = utils.rng.random().float(f32) * 2.0;
            host.x = owner.x + radius * @cos(angle);
            host.y = owner.y + radius * @sin(angle);
            return;
        }

        World.moveToward(host, owner.x, owner.y, 3.5, dt);
    }
};

pub const DwarvenCoil = struct {
    pub const data: Metadata = .{
        .type = .ally,
        .name = "Dwarven Coil",
    };

    damage: i32 = 300,
    range: f32 = 3.0,
    last_attack: i64 = -1,

    pub fn spawn(self: *DwarvenCoil, host: *Ally) !void {
        const world = maps.worlds.getPtr(host.world_id) orelse return;
        const owner = world.findCon(Player, host.owner_map_id) orelse return;
        self.damage = i32f(300.0 + f32i(owner.totalStat(.wit)) * 2.0);
        self.range = 3.0 + f32i(owner.totalStat(.intelligence)) * 0.05;
    }

    pub fn tick(self: *DwarvenCoil, host: *Ally, time: i64, _: i64) !void {
        if (time - self.last_attack < 1 * std.time.us_per_s) return;
        defer self.last_attack = time;

        const world = maps.worlds.getPtr(host.world_id) orelse return;
        world.aoe(Enemy, host.x, host.y, .ally, host.map_id, self.range, .{
            .magic_dmg = self.damage,
            .aoe_color = 0x01C6C6,
        });
    }
};

pub const EnemySoul = struct {
    pub const data: Metadata = .{
        .type = .entity,
        .name = "Enemy Soul",
    };

    pub fn tick(_: *EnemySoul, host: *Entity, _: i64, dt: i64) !void {
        if (logic.clampToSpawn(@src(), host, dt, 9.0, 7.0, 2.0))
            logic.wander(@src(), host, dt, 1.0);
    }
};

pub const DemonRift = struct {
    pub const data: Metadata = .{
        .type = .entity,
        .name = "Demon Rift",
    };

    last_healed: i64 = -1,
    radius: f32 = 0.0,
    restore_amount: u32 = 0,
    overheal_amount: i32 = 0,

    pub fn spawn(self: *DemonRift, host: *Entity) !void {
        const world = maps.worlds.getPtr(host.world_id) orelse return;
        const owner = world.findCon(Player, host.owner_map_id) orelse return;
        self.restore_amount = u32f(50.0 + f32i(owner.totalStat(.health)) * 0.05) + 5 * owner.abilityTalentLevel(1);
        self.overheal_amount = owner.keystoneTalentLevel(1) * 50;
        self.radius = 7.0 + f32i(owner.totalStat(.intelligence)) * 0.07;
    }

    pub fn tick(self: *DemonRift, host: *Entity, time: i64, _: i64) !void {
        if (time - self.last_healed < 2.5 * std.time.us_per_s) return;
        defer self.last_healed = time;

        const world = maps.worlds.getPtr(host.world_id) orelse return;
        const radius_sqr = self.radius * self.radius;

        for (world.listForType(Player).items) |*player| {
            if (utils.distSqr(player.x, player.y, host.x, host.y) > radius_sqr) continue;
            const max_hp = player.totalStat(.health);
            if (player.hp >= max_hp) continue;
            const pre_hp = player.hp;
            player.restoreHealth(self.restore_amount, self.overheal_amount);
            const hp_delta = player.hp - pre_hp;
            if (hp_delta <= 0) continue;

            var buf: [64]u8 = undefined;
            player.client.sendPacket(.{ .notification = .{
                .obj_type = .player,
                .map_id = player.map_id,
                .message = std.fmt.bufPrint(&buf, "+{}", .{hp_delta}) catch continue,
                .color = 0x00FF00,
            } });

            player.show_effects.append(main.allocator, .{
                .eff_type = .potion,
                .color = 0x00FF00,
                .map_id = player.map_id,
                .obj_type = .player,
                .x1 = 0,
                .x2 = 0,
                .y1 = 0,
                .y2 = 0,
            }) catch main.oomPanic();
        }

        for (world.listForType(Player).items) |*player| {
            if (utils.distSqr(player.x, player.y, host.x, host.y) > 16 * 16) continue;
            player.show_effects.append(main.allocator, .{
                .obj_type = .entity,
                .map_id = host.map_id,
                .eff_type = .area_blast,
                .x1 = host.x,
                .y1 = host.y,
                .x2 = self.radius,
                .y2 = 0.0,
                .color = 0x00FF00,
            }) catch main.oomPanic();
        }
    }
};
