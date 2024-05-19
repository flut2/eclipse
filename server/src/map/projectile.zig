const std = @import("std");
const game_data = @import("shared").game_data;

const Player = @import("player.zig").Player;
const World = @import("../world.zig").World;

pub const Projectile = struct {
    obj_id: i32 = -1,
    x: f32 = 0.0,
    y: f32 = 0.0,
    angle: f32 = 0.0,
    phys_dmg: i32 = 0,
    magic_dmg: i32 = 0,
    true_dmg: i32 = 0,
    owner_id: i32 = -1,
    bullet_id: u8 = 0,
    start_time: i64 = 0,
    obj_ids_hit: std.AutoHashMapUnmanaged(i32, void) = .{},
    props: *const game_data.ProjProps = undefined,
    world: *World = undefined,

    pub fn deinit(self: *Projectile) !void {
        self.obj_ids_hit.deinit(self.world.allocator);
    }

    pub fn delete(self: *Projectile) !void {
        std.debug.assert(!self.world.player_lock.tryLock());
        if (self.world.findRef(Player, self.owner_id)) |player| {
            player.bullets[self.bullet_id] = null;
        }

        try self.world.remove(Projectile, self);
    }

    pub fn tick(self: *Projectile, time: i64, _: i64) !void {
        if (time - self.start_time >= self.props.lifetime + 250) {
            self.world.player_lock.lock();
            defer self.world.player_lock.unlock();
            try self.delete();
            return;
        }
    }
};
