const std = @import("std");
const game_data = @import("shared").game_data;
const utils = @import("shared").utils;
const stat_util = @import("stat_util.zig");
const state = @import("../logic/state.zig");
const behavior = @import("../logic/behavior.zig");
const transition = @import("../logic/transition.zig");
const main = @import("../main.zig");

const State = state.State;
const Behavior = behavior.Behavior;
const BehaviorStorage = behavior.BehaviorStorage;
const Transition = transition.Transition;
const TransitionStorage = transition.TransitionStorage;
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
    active_state: ?*const State = null,
    behavior_storage: std.AutoHashMap(*Behavior, BehaviorStorage) = undefined,
    transition_storage: std.AutoHashMap(*Transition, TransitionStorage) = undefined,
    world: *World = undefined,
    spawned: bool = false,
    allocator: std.mem.Allocator = undefined,

    pub fn init(self: *Enemy, allocator: std.mem.Allocator) !void {
        self.allocator = allocator;
        self.behavior_storage = std.AutoHashMap(*Behavior, BehaviorStorage).init(allocator);
        self.transition_storage = std.AutoHashMap(*Transition, TransitionStorage).init(allocator);
        self.active_state = state.en_type_to_root_state.getPtr(self.en_type);
        if (self.active_state) |s|
            try s.entry(self, main.current_time);
        self.stats_writer.buffer = try allocator.alloc(u8, 32);

        self.props = game_data.obj_type_to_props.getPtr(self.en_type) orelse {
            std.log.err("Could not find props for enemy with type 0x{x}", .{self.en_type});
            return;
        };
        self.hp = self.props.health;
        self.max_hp = self.props.health;
    }

    pub fn deinit(self: *Enemy) !void {
        self.behavior_storage.deinit();
        self.transition_storage.deinit();
        self.allocator.free(self.stats_writer.buffer);
    }

    pub fn move(self: *Enemy, x: f32, y: f32) void {
        const ux: u32 = @intFromFloat(x - 0.5);
        const uy: u32 = @intFromFloat(y - 0.5);
        if (!self.world.tiles[uy * self.world.w + ux].occupied) {
            self.x = x;
            self.y = y;
        }
    }

    pub fn delete(self: *Enemy, time: i64) !void {
        if (self.active_state) |s| try s.exit(self, time);
        try self.world.remove(Enemy, self);
    }

    pub fn tick(self: *Enemy, time: i64, dt: i64) !void {
        if (self.hp <= 0) try self.delete(time);
        if (self.active_state) |s| try s.tick(self, time, dt);
    }

    pub fn damage(self: *Enemy, phys_dmg: i32, magic_dmg: i32, true_dmg: i32) void {
        self.hp -= phys_dmg - self.props.defense;
        self.hp -= magic_dmg - self.props.resistance;
        self.hp -= true_dmg;
        if (self.hp <= 0) self.delete(main.current_time) catch return;
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
};
