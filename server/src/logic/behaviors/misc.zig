const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const utils = shared.utils;
const i64f = utils.i64f;

const Enemy = @import("../../map/Enemy.zig");
const Entity = @import("../../map/Entity.zig");
const maps = @import("../../map/maps.zig");
const Player = @import("../../map/Player.zig");
const World = @import("../../World.zig");
const Metadata = @import("../behavior.zig").BehaviorMetadata;
const logic = @import("../logic.zig");

pub const HealthShrine = struct {
    pub const data: Metadata = .{
        .type = .entity,
        .name = "Health Shrine",
    };

    last_healed: i64 = -1,

    pub fn tick(self: *HealthShrine, host: *Entity, time: i64, _: i64) !void {
        if (time - self.last_healed < 1.5 * std.time.us_per_s) return;
        defer self.last_healed = time;

        const world = maps.worlds.getPtr(host.world_id) orelse return;
        const player = world.getNearestWithin(Player, host.x, host.y, 4.0 * 4.0) orelse return;
        const max_hp = player.totalStat(.health);
        if (player.hp >= max_hp) return; // TODO: select random player instead
        const pre_hp = player.hp;
        player.hp = @min(max_hp, player.hp + 75);
        const hp_delta = player.hp - pre_hp;
        if (hp_delta <= 0) return;

        var buf: [64]u8 = undefined;
        player.client.sendPacket(.{ .notification = .{
            .obj_type = .player,
            .map_id = player.map_id,
            .message = std.fmt.bufPrint(&buf, "+{}", .{hp_delta}) catch return,
            .color = 0x00FF00,
        } });

        player.client.sendPacket(.{ .show_effect = .{
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

        const world = maps.worlds.getPtr(host.world_id) orelse return;
        const player = world.getNearestWithin(Player, host.x, host.y, 4.0 * 4.0) orelse return;
        const max_mp = player.totalStat(.mana);
        if (player.mp >= max_mp) return; // TODO: select random player instead
        const pre_mp = player.mp;
        player.mp = @min(max_mp, player.mp + 40);
        const mp_delta = player.mp - pre_mp;
        if (mp_delta <= 0) return;

        var buf: [64]u8 = undefined;
        player.client.sendPacket(.{ .notification = .{
            .obj_type = .player,
            .map_id = player.map_id,
            .message = std.fmt.bufPrint(&buf, "+{}", .{mp_delta}) catch return,
            .color = 0x0000FF,
        } });

        player.client.sendPacket(.{ .show_effect = .{
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

pub const RetrieveHealthBeacon = struct {
    pub const data: Metadata = .{
        .type = .entity,
        .name = "Retrieve Health Beacon",
    };

    last_healed: i64 = -1,

    pub fn tick(self: *RetrieveHealthBeacon, host: *Entity, time: i64, _: i64) !void {
        if (time - self.last_healed < 1.5 * std.time.us_per_s) return;
        defer self.last_healed = time;

        const world = maps.worlds.getPtr(host.world_id) orelse return;
        const player = world.getNearestWithin(Player, host.x, host.y, 4.0 * 4.0) orelse return;
        const max_hp = player.totalStat(.health);
        if (player.hp >= max_hp) return; // TODO: select random player instead
        const pre_hp = player.hp;
        player.hp = @min(max_hp, player.hp + 75);
        const hp_delta = player.hp - pre_hp;
        if (hp_delta <= 0) return;

        var buf: [64]u8 = undefined;
        player.client.sendPacket(.{ .notification = .{
            .obj_type = .player,
            .map_id = player.map_id,
            .message = std.fmt.bufPrint(&buf, "+{}", .{hp_delta}) catch return,
            .color = 0x00FF00,
        } });

        player.client.sendPacket(.{ .show_effect = .{
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

pub const RetrieveManaBeacon = struct {
    pub const data: Metadata = .{
        .type = .entity,
        .name = "Retrieve Mana Beacon",
    };

    last_healed: i64 = -1,

    pub fn tick(self: *RetrieveManaBeacon, host: *Entity, time: i64, _: i64) !void {
        if (time - self.last_healed < 1.5 * std.time.us_per_s) return;
        defer self.last_healed = time;

        const world = maps.worlds.getPtr(host.world_id) orelse return;
        const player = world.getNearestWithin(Player, host.x, host.y, 4.0 * 4.0) orelse return;
        const max_mp = player.totalStat(.mana);
        if (player.mp >= max_mp) return; // TODO: select random player instead
        const pre_mp = player.mp;
        player.mp = @min(max_mp, player.mp + 40);
        const mp_delta = player.mp - pre_mp;
        if (mp_delta <= 0) return;

        var buf: [64]u8 = undefined;
        player.client.sendPacket(.{ .notification = .{
            .obj_type = .player,
            .map_id = player.map_id,
            .message = std.fmt.bufPrint(&buf, "+{}", .{mp_delta}) catch return,
            .color = 0x0000FF,
        } });

        player.client.sendPacket(.{ .show_effect = .{
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

pub const HealthWisp = struct {
    pub const data: Metadata = .{
        .type = .enemy,
        .name = "Health Wisp",
    };

    pub fn tick(_: *HealthWisp, host: *Enemy, _: i64, dt: i64) !void {
        if (logic.clampToSpawn(@src(), host, dt, 6.0, 4.0, 2.5))
            logic.wander(@src(), host, dt, 2.5);
    }
};

pub const MagicWisp = struct {
    pub const data: Metadata = .{
        .type = .enemy,
        .name = "Magic Wisp",
    };

    pub fn tick(_: *MagicWisp, host: *Enemy, _: i64, dt: i64) !void {
        if (logic.clampToSpawn(@src(), host, dt, 6.0, 4.0, 2.5))
            logic.wander(@src(), host, dt, 2.5);
    }
};

pub const DormantHealthShrine = struct {
    pub const data: Metadata = .{
        .type = .entity,
        .name = "Dormant Health Shrine",
    };

    transform_at: i64 = std.math.maxInt(i64),

    pub fn tick(self: *DormantHealthShrine, host: *Entity, time: i64, _: i64) !void {
        const world = maps.worlds.getPtr(host.world_id) orelse return;

        if (self.transform_at != std.math.maxInt(i64)) {
            if (time >= self.transform_at) {
                const shrine_data = game_data.entity.from_name.get("Health Shrine") orelse return;
                _ = try world.add(Entity, .{ .data_id = shrine_data.id, .x = host.x, .y = host.y });
                try host.delete();
                return;
            }
        } else {
            if (world.getAmountWithin(Enemy, "Health Wisp", host.x, host.y, 20 * 20) == 0) {
                self.transform_at = time + i64f(1.15 * std.time.us_per_s);
                for (world.listForType(Player).items) |*player| {
                    if (utils.distSqr(host.x, host.y, player.x, player.y) > 16 * 16) continue;
                    player.client.sendPacket(.{ .play_animation = .{
                        .obj_type = .entity,
                        .map_id = host.map_id,
                        .animation_idx = 0,
                        .repeating = false,
                    } });
                }
            }
        }
    }
};

pub const DormantMagicShrine = struct {
    pub const data: Metadata = .{
        .type = .entity,
        .name = "Dormant Magic Shrine",
    };

    transform_at: i64 = std.math.maxInt(i64),

    pub fn tick(self: *DormantMagicShrine, host: *Entity, time: i64, _: i64) !void {
        const world = maps.worlds.getPtr(host.world_id) orelse return;

        if (self.transform_at != std.math.maxInt(i64)) {
            if (time >= self.transform_at) {
                const shrine_data = game_data.entity.from_name.get("Magic Shrine") orelse return;
                _ = try world.add(Entity, .{ .data_id = shrine_data.id, .x = host.x, .y = host.y });
                try host.delete();
                return;
            }
        } else {
            if (world.getAmountWithin(Enemy, "Magic Wisp", host.x, host.y, 20 * 20) == 0) {
                self.transform_at = time + i64f(1.15 * std.time.us_per_s);
                for (world.listForType(Player).items) |*player| {
                    if (utils.distSqr(host.x, host.y, player.x, player.y) > 16 * 16) continue;
                    player.client.sendPacket(.{ .play_animation = .{
                        .obj_type = .entity,
                        .map_id = host.map_id,
                        .animation_idx = 0,
                        .repeating = false,
                    } });
                }
            }
        }
    }
};
