const std = @import("std");
const game_data = @import("shared").game_data;
const utils = @import("shared").utils;
const stat_util = @import("stat_util.zig");
const behavior_logic = @import("../logic/logic.zig");
const behavior = @import("../logic/behavior.zig");
const main = @import("../main.zig");

const Behavior = behavior.Behavior;
const World = @import("../world.zig").World;

pub const Enemy = struct {
    obj_id: i32 = -1,
    x: f32 = 0.0,
    y: f32 = 0.0,
    en_type: u16 = 0xFFFF,
    max_hp: i32 = 100,
    hp: i32 = 100,
    next_bullet_id: u8 = 0,
    bullets: [256]?i32 = [_]?i32{null} ** 256,
    stats_writer: utils.PacketWriter = .{},
    condition: utils.Condition = .{},
    props: *const game_data.ObjProps = undefined,
    behavior: ?*Behavior = null,
    world: *World = undefined,
    spawned: bool = false,
    storages: behavior_logic.Storages = .{},
    allocator: std.mem.Allocator = undefined,

    pub fn init(self: *Enemy, allocator: std.mem.Allocator) !void {
        self.allocator = allocator;
        if (behavior.behavior_map.get(self.en_type)) |behav| {
            self.behavior = try allocator.create(Behavior);
            self.behavior.?.* = behav;
            switch (self.behavior.?.*) {
                inline else => |*b| {
                    const T = @TypeOf(b.*);
                    if (std.meta.hasFn(T, "spawn")) try b.spawn(self);
                    if (std.meta.hasFn(T, "entry")) try b.entry(self);
                },
            }
        }

        self.stats_writer.buffer = try allocator.alloc(u8, 32);

        self.props = game_data.obj_type_to_props.getPtr(self.en_type) orelse {
            std.log.err("Could not find props for enemy with type 0x{x}", .{self.en_type});
            return;
        };
        self.hp = self.props.health;
        self.max_hp = self.props.health;
    }

    pub fn deinit(self: *Enemy) !void {
        if (self.behavior) |behav| {
            switch (behav.*) {
                inline else => |*b| {
                    const T = @TypeOf(b.*);
                    if (std.meta.hasFn(T, "death")) try b.death(self);
                    if (std.meta.hasFn(T, "exit")) try b.exit(self);
                },
            }

            self.allocator.destroy(behav);
        }

        self.storages.deinit();
        self.allocator.free(self.stats_writer.buffer);
    }

    pub fn switchBehavior(self: *Enemy, comptime TargetBehavior: type) !void {
        const behav = behavior.fromType(TargetBehavior);
        if (self.behavior) |old_behav| {
            switch (old_behav.*) {
                inline else => |*b| if (std.meta.hasFn(@TypeOf(b.*), "exit")) try b.exit(self),
            }
            self.storages.clear();
        } else self.behavior = try self.allocator.create(Behavior);

        self.behavior.?.* = behav;
        switch (self.behavior.?.*) {
            inline else => |*b| if (std.meta.hasFn(@TypeOf(b.*), "entry")) try b.entry(self),
        }
    }

    pub fn move(self: *Enemy, x: f32, y: f32) void {
        const ux: u32 = @intFromFloat(x);
        const uy: u32 = @intFromFloat(y);
        if (!self.world.tiles[uy * self.world.w + ux].occupied) {
            self.x = x;
            self.y = y;
        }
    }

    pub fn delete(self: *Enemy) !void {
        try self.world.remove(Enemy, self);
    }

    pub fn tick(self: *Enemy, time: i64, dt: i64) !void {
        if (!self.props.damage_immune and self.hp <= 0) try self.delete();
        if (self.behavior) |behav| {
            switch (behav.*) {
                inline else => |*b| {
                    if (std.meta.hasFn(@TypeOf(b.*), "tick"))
                        try b.tick(self, time, dt);
                },
            }
        }
    }

    pub fn damage(self: *Enemy, phys_dmg: i32, magic_dmg: i32, true_dmg: i32) void {
        if (self.props.damage_immune)
            return;

        self.hp -= phys_dmg - self.props.defense;
        self.hp -= magic_dmg - self.props.resistance;
        self.hp -= true_dmg;
        if (self.hp <= 0) self.delete() catch return;
    }

    pub fn exportStats(self: *Enemy, stat_cache: *std.EnumArray(game_data.StatType, ?stat_util.StatValue)) ![]u8 {
        var writer = &self.stats_writer;
        writer.index = 0;

        stat_util.write(writer, stat_cache, self.allocator, .x, self.x);
        stat_util.write(writer, stat_cache, self.allocator, .y, self.y);
        stat_util.write(writer, stat_cache, self.allocator, .max_hp, self.max_hp);
        stat_util.write(writer, stat_cache, self.allocator, .hp, self.hp);
        stat_util.write(writer, stat_cache, self.allocator, .condition, self.condition);

        return writer.buffer[0..writer.index];
    }

    // Move toward or onto, but not through. Don't move if too close
    // Does not prevent moving closer than range if crossing it
    pub fn moveToward(host: *Enemy, x: f32, y: f32, range_sqr: f32, speed: f32, dt: i64) void {
        const dx = x - host.x;
        const dy = y - host.y;
        const mag_sqr = dx * dx + dy * dy;
        if (mag_sqr <= range_sqr) return; // Close enough

        const fdt: f32 = @floatFromInt(dt);
        const dist = speed * (fdt / std.time.us_per_s); // Distance to move this tick

        if (mag_sqr > dist * dist) {
            // Set length of dx,dy to dist
            const c = dist / @sqrt(mag_sqr);
            host.move(host.x + dx * c, host.y + dy * c);
        } else {
            // Don't overshoot
            host.move(x, y);
        }
    }
};
