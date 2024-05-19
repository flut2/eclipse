const std = @import("std");
const utils = @import("shared").utils;
const game_data = @import("shared").game_data;

const Entity = @import("../map/entity.zig").Entity;
const Enemy = @import("../map/enemy.zig").Enemy;

pub inline fn dropPortal(host: *Enemy, portal_name: []const u8, chance: f32) void {
    if (utils.rng.random().float(f32) <= chance) {
        const portal_type = game_data.obj_name_to_type.get(portal_name) orelse {
            std.log.err("Portal not found for name {s}", .{portal_name});
            return;
        };
        var portal = Entity{
            .x = host.x,
            .y = host.y,
            .en_type = portal_type,
        };

        host.world.entity_lock.lock();
        defer host.world.entity_lock.unlock();
        _ = host.world.add(Entity, &portal) catch return;
    }
}
