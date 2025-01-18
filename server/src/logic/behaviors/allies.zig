const std = @import("std");

const utils = @import("shared").utils;
const f32i = utils.f32i;
const i64f = utils.i64f;

const Ally = @import("../../map/Ally.zig");
const Enemy = @import("../../map/Enemy.zig");
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
        const owner = host.world.find(Player, host.owner_map_id, .ref) orelse {
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

    pub fn entry(self: *DwarvenCoil, host: *Ally) !void {
        const owner = host.world.find(Player, host.owner_map_id, .con) orelse return;
        const fint = f32i(owner.stats[Player.intelligence_stat] + owner.stat_boosts[Player.intelligence_stat]);
        const fwit = f32i(owner.stats[Player.wit_stat] + owner.stat_boosts[Player.wit_stat]);
        self.damage = i64f(300.0 + fwit * 2.0);
        self.range = i64f(3.0 + fint * 0.05);
    }

    pub fn tick(self: *DwarvenCoil, host: *Ally, time: i64, _: i64) !void {
        if (time - self.last_attack < 1 * std.time.us_per_s) return;
        defer self.last_attack = time;

        host.world.aoe(Enemy, host.x, host.y, .ally, host.map_id, self.range, .{
            .magic_dmg = self.damage,
            .aoe_color = 0x01C6C6,
        });
    }
};
