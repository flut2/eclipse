const std = @import("std");
const xml = @import("shared").xml;
const utils = @import("shared").utils;

const Enemy = @import("../map/enemy.zig").Enemy;
const State = @import("state.zig").State;

pub const TempTransition = struct {
    target_state: []const u8,
    logic: TransitionLogic,

    pub fn parse(node: xml.Node, allocator: std.mem.Allocator, comptime T: type) !TempTransition {
        comptime var tag_name: []const u8 = "";
        inline for (@typeInfo(TransitionLogic).Union.fields) |field| {
            if (field.type == T) {
                tag_name = field.name;
                break;
            }
        }

        if (tag_name.len == 0)
            @compileError("Could not find transition tag name");

        var temp: TempTransition = undefined;
        temp.target_state = node.getAttribute("targetState") orelse return error.InvalidTargetState;
        const parsed = try T.parse(node, allocator);
        temp.logic = @unionInit(TransitionLogic, tag_name, parsed);
        return temp;
    }
};

pub const Transition = struct {
    target_state: *const State,
    logic: TransitionLogic,

    pub fn tick(self: *Transition, host: *Enemy, time: i64, dt: i64) !bool {
        switch (self.logic) {
            inline else => |*logic, tag| {
                if (host.transition_storage.getPtr(self)) |storage| {
                    switch (storage.*) {
                        inline else => |*t, t_tag| {
                            if (tag == t_tag)
                                return try logic.tick(host, time, dt, t);
                        },
                    }
                } else {
                    const tag_name = @tagName(tag);
                    var storage = @unionInit(TransitionStorage, tag_name, .{});
                    defer host.transition_storage.put(self, storage) catch unreachable;
                    return try logic.tick(host, time, dt, &@field(storage, tag_name));
                }
            },
        }

        unreachable;
    }

    pub fn deinit(self: Transition, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

pub const TransitionTag = enum {
    timed,
    hp_less,
    player_within,
};

pub const TransitionStorage = union(TransitionTag) {
    timed: TimedStorage,
    hp_less: HpLessStorage,
    player_within: PlayerWithinStorage,
};

pub const TransitionLogic = union(TransitionTag) {
    timed: TimedTransition,
    hp_less: HpLessTransition,
    player_within: PlayerWithinTransition,
};

const TimedStorage = struct { time: i64 = -1 };
pub const TimedTransition = struct {
    time: i64,
    random: bool,

    pub fn tick(self: TimedTransition, _: *Enemy, _: i64, dt: i64, storage: *TimedStorage) !bool {
        if (storage.time == -1) storage.time = if (self.random) utils.rng.random().intRangeAtMost(i64, 0, self.time) else self.time;

        storage.time -= dt;
        if (storage.time <= 0) {
            storage.time = -1;
            return true;
        }

        return false;
    }

    pub fn parse(node: xml.Node, _: std.mem.Allocator) !TimedTransition {
        return .{
            .time = try node.getAttributeInt("time", i64, 1000) * std.time.us_per_ms,
            .random = node.attributeExists("randomizedTime"),
        };
    }
};

const HpLessStorage = struct {};
pub const HpLessTransition = struct {
    threshold: f32,

    pub fn tick(self: HpLessTransition, host: *Enemy, _: i64, _: i64, _: *HpLessStorage) !bool {
        const fhp: f32 = @floatFromInt(host.hp);
        const fmhp: f32 = @floatFromInt(host.max_hp);
        return fhp / fmhp < self.threshold;
    }

    pub fn parse(node: xml.Node, _: std.mem.Allocator) !HpLessTransition {
        return .{
            .threshold = try node.getAttributeFloat("threshold", f32, 0.0),
        };
    }
};

const PlayerWithinStorage = struct {};
pub const PlayerWithinTransition = struct {
    dist_sqr: f32,
    see_invis: bool,

    pub fn tick(self: PlayerWithinTransition, host: *Enemy, _: i64, _: i64, _: *PlayerWithinStorage) !bool {
        host.world.player_lock.lock();
        defer host.world.player_lock.unlock();
        for (host.world.players.items) |p| {
            const dx = p.x - host.x;
            const dy = p.y - host.y;
            if (dx * dx + dy * dy <= self.dist_sqr and (self.see_invis or !p.condition.invisible))
                return true;
        }

        return false;
    }

    pub fn parse(node: xml.Node, _: std.mem.Allocator) !PlayerWithinTransition {
        const dist = try node.getAttributeFloat("dist", f32, 20.0);
        return .{
            .dist_sqr = dist * dist,
            .see_invis = node.attributeExists("seeInvis"),
        };
    }
};
