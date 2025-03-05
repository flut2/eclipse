const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const network_data = shared.network_data;
const i64f = shared.utils.i64f;

const main = @import("../main.zig");
const World = @import("../World.zig");
const Player = @import("Player.zig");
const maps = @import("../map/maps.zig");

const Projectile = @This();

map_id: u32 = std.math.maxInt(u32),
index: u8 = 0,
x: f32 = 0.0,
y: f32 = 0.0,
angle: f32 = 0.0,
phys_dmg: i32 = 0,
magic_dmg: i32 = 0,
true_dmg: i32 = 0,
owner_obj_type: network_data.ObjectType,
owner_map_id: u32 = std.math.maxInt(u32),
start_time: i64 = 0,
player_hit_list: std.AutoHashMapUnmanaged(u32, void) = .empty,
ally_hit_list: std.AutoHashMapUnmanaged(u32, void) = .empty,
data: *const game_data.ProjectileData,
world_id: i32 = std.math.minInt(i32),

pub fn deinit(self: *Projectile) !void {
    self.player_hit_list.deinit(main.allocator);
    self.ally_hit_list.deinit(main.allocator);
}

pub fn delete(self: *Projectile) !void {
    const world = maps.worlds.getPtr(self.world_id) orelse return;
    if (world.find(Player, self.owner_map_id, .ref)) |player| player.projectiles[self.index] = null;
    try world.remove(Projectile, self);
}

pub fn tick(self: *Projectile, time: i64, _: i64) !void {
    if (time - self.start_time >= i64f(self.data.duration + 3 * std.time.us_per_s)) {
        try self.delete();
        return;
    }
}
