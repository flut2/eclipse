const std = @import("std");

const Entity = @import("../../map/Entity.zig");
const Player = @import("../../map/Player.zig");
const Metadata = @import("../behavior.zig").BehaviorMetadata;

pub const HealthShrine = struct {
    pub const data: Metadata = .{
        .type = .entity,
        .name = "Health Shrine",
    };

    last_healed: i64 = -1,

    pub fn tick(self: *HealthShrine, host: *Entity, time: i64, _: i64) !void {
        if (time - self.last_healed < 1.5 * std.time.us_per_s) return;
        defer self.last_healed = time;

        const player = host.world.getNearestWithin(Player, host.x, host.y, 4.0 * 4.0) orelse return;
        const pre_hp = player.hp;
        player.hp = @min(player.stats[Player.health_stat] + player.stat_boosts[Player.health_stat], player.hp + 75);
        const hp_delta = player.hp - pre_hp;
        if (hp_delta <= 0) return;

        var buf: [64]u8 = undefined;
        player.client.queuePacket(.{ .notification = .{
            .obj_type = .player,
            .map_id = player.map_id,
            .message = std.fmt.bufPrint(&buf, "+{}", .{hp_delta}) catch return,
            .color = 0x00FF00,
        } });

        player.client.queuePacket(.{ .show_effect = .{
            .eff_type = .trail,
            .obj_type = .entity,
            .map_id = host.map_id,
            .x1 = player.x,
            .y1 = player.y,
            .x2 = 0,
            .y2 = 0,
            .color = 0x00FF00,
        } });
    }
};

pub const MagicShrine = struct {
    pub const data: Metadata = .{
        .type = .entity,
        .name = "Magic Shrine",
    };

    last_healed: i64 = -1,

    pub fn tick(self: *MagicShrine, host: *Entity, time: i64, _: i64) !void {
        if (time - self.last_healed < 1.5 * std.time.us_per_s) return;
        defer self.last_healed = time;

        const player = host.world.getNearestWithin(Player, host.x, host.y, 4.0 * 4.0) orelse return;
        const pre_mp = player.mp;
        player.mp = @min(player.stats[Player.mana_stat] + player.stat_boosts[Player.mana_stat], player.mp + 40);
        const mp_delta = player.mp - pre_mp;
        if (mp_delta <= 0) return;

        var buf: [64]u8 = undefined;
        player.client.queuePacket(.{ .notification = .{
            .obj_type = .player,
            .map_id = player.map_id,
            .message = std.fmt.bufPrint(&buf, "+{}", .{mp_delta}) catch return,
            .color = 0x0000FF,
        } });

        player.client.queuePacket(.{ .show_effect = .{
            .eff_type = .trail,
            .obj_type = .entity,
            .map_id = host.map_id,
            .x1 = player.x,
            .y1 = player.y,
            .x2 = 0,
            .y2 = 0,
            .color = 0x0000FF,
        } });
    }
};
