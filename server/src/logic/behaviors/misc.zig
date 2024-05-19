const std = @import("std");

const Player = @import("../../map/player.zig").Player;
const Enemy = @import("../../map/enemy.zig").Enemy;

pub const HealthShrine = struct {
    pub const object_name = "Health Shrine";

    last_healed: i64 = -1,

    pub fn tick(self: *HealthShrine, host: *Enemy, time: i64, _: i64) !void {
        if (time - self.last_healed >= 1.5 * std.time.us_per_s) {
            if (!host.world.player_lock.tryLock()) return;
            defer {
                host.world.player_lock.unlock();
                self.last_healed = time;
            }

            const player = host.world.getNearestPlayerWithin(host.x, host.y, 4.0 * 4.0) orelse return;
            const pre_hp = player.hp;
            player.hp = @min(player.stats[Player.health_stat], player.hp + 75);
            const hp_delta = player.hp - pre_hp;
            if (hp_delta <= 0)
                return;

            var buf: [64]u8 = undefined;
            player.client.queuePacket(.{ .notification = .{
                .obj_id = player.obj_id,
                .message = std.fmt.bufPrint(&buf, "+{d}", .{hp_delta}) catch return,
                .color = 0x00FF00,
            } });

            player.client.queuePacket(.{ .show_effect = .{
                .eff_type = .trail,
                .obj_id = host.obj_id,
                .x1 = player.x,
                .y1 = player.y,
                .x2 = 0,
                .y2 = 0,
                .color = 0x00FF00,
            } });
        }
    }
};

pub const MagicShrine = struct {
    pub const object_name = "Magic Shrine";

    last_healed: i64 = -1,

    pub fn tick(self: *MagicShrine, host: *Enemy, time: i64, _: i64) !void {
        if (time - self.last_healed >= 1.5 * std.time.us_per_s) {
            if (!host.world.player_lock.tryLock()) return;
            defer {
                host.world.player_lock.unlock();
                self.last_healed = time;
            }

            const player = host.world.getNearestPlayerWithin(host.x, host.y, 4.0 * 4.0) orelse return;
            const pre_mp = player.mp;
            player.mp = @min(player.stats[Player.mana_stat], player.mp + 40);
            const mp_delta = player.mp - pre_mp;
            if (mp_delta <= 0)
                return;

            var buf: [64]u8 = undefined;
            player.client.queuePacket(.{ .notification = .{
                .obj_id = player.obj_id,
                .message = std.fmt.bufPrint(&buf, "+{d}", .{mp_delta}) catch return,
                .color = 0x0000FF,
            } });

            player.client.queuePacket(.{ .show_effect = .{
                .eff_type = .trail,
                .obj_id = host.obj_id,
                .x1 = player.x,
                .y1 = player.y,
                .x2 = 0,
                .y2 = 0,
                .color = 0x0000FF,
            } });
        }
    }
};
