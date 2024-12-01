const std = @import("std");
const logic = @import("../logic.zig");
const utils = @import("shared").utils;

const Metadata = @import("../behavior.zig").BehaviorMetadata;
const Player = @import("../../map/Player.zig");
const Ally = @import("../../map/Ally.zig");
const World = @import("../../World.zig");

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
