const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const utils = shared.utils;
const f32i = utils.f32i;
const i64f = utils.i64f;

const main = @import("../../main.zig");
const Ally = @import("../../map/Ally.zig");
const Enemy = @import("../../map/Enemy.zig");
const Entity = @import("../../map/Entity.zig");
const maps = @import("../../map/maps.zig");
const Player = @import("../../map/Player.zig");
const World = @import("../../World.zig");
const Metadata = @import("../behavior.zig").BehaviorMetadata;
const logic = @import("../logic.zig");
const loot = @import("../loot.zig");

pub const TribeChief = struct {
    pub const data: Metadata = .{
        .type = .enemy,
        .name = "Tribe Chief",
    };

    next_switch_time: i64 = 0,
    state: enum { waiting, monologue, possession_next, spawn_next, enraged, in_possession } = .waiting,

    pub fn spawn(_: *TribeChief, host: *Enemy) !void {
        host.condition.invulnerable = true;
    }

    pub fn death(_: *TribeChief, host: *Enemy) !void {
        loot.dropItems(host, &.{
            .{ .name = "Tiki Torch", .chance = 1.0 / 5.0, .threshold = 0.01 },
            .{ .name = "Tribal Topper", .chance = 1.0 / 5.0, .threshold = 0.01 },
            .{ .name = "Spirit Shank", .chance = 1.0 / 10.0, .threshold = 0.05 },
        });
        loot.dropCards(host, &.{
            .{ .name = "Absorption", .chance = 1.0 / 15.0, .threshold = 0.05 },
            .{ .name = "Ritual Sacrifice", .chance = 1.0 / 10.0, .threshold = 0.01 },
            .{ .name = "Titan's Resolve", .chance = 1.0 / 5.0, .threshold = 0.005 },
            .{ .name = "Boundless Aptitude", .chance = 1.0 / 2.0, .threshold = 0.005 },
            .{ .name = "Enhanced Fortitude", .chance = 1.0 / 2.0, .threshold = 0.005 },
            .{ .name = "Time Distortion", .chance = 1.0 / 2.0, .threshold = 0.005 },
            .{ .name = "Nimble Feet", .chance = 1.0 / 2.0, .threshold = 0.005 },
        });
        loot.dropResources(host, &.{
            .{ .name = "Tiny Magisteel Alloy", .chance = 1.0 / 1.0, .min = 30, .max = 60, .threshold = 0.01 },
            .{ .name = "Large Magisteel Alloy", .chance = 1.0 / 3.0, .min = 10, .max = 30, .threshold = 0.01 },
            .{ .name = "Huge Magisteel Alloy", .chance = 1.0 / 5.0, .min = 5, .max = 15, .threshold = 0.01 },
            .{ .name = "Pine Driftwood", .chance = 1.0 / 1.0, .min = 30, .max = 60, .threshold = 0.01 },
            .{ .name = "Maple Batten", .chance = 1.0 / 3.0, .min = 10, .max = 30, .threshold = 0.01 },
            .{ .name = "Flawless Mahogany", .chance = 1.0 / 5.0, .min = 5, .max = 15, .threshold = 0.01 },
            .{ .name = "Solid Magma", .chance = 1.0 / 1.0, .min = 30, .max = 60, .threshold = 0.01 },
            .{ .name = "Phoenix Feather", .chance = 1.0 / 3.0, .min = 10, .max = 30, .threshold = 0.01 },
            .{ .name = "Bottled Flame", .chance = 1.0 / 5.0, .min = 5, .max = 15, .threshold = 0.01 },
        });
        loot.dropSpirits(host, .{ .chance = 1.0 / 1.0, .min = 150, .max = 300, .threshold = 0.03 });
    }

    pub fn tick(self: *TribeChief, host: *Enemy, time: i64, dt: i64) !void {
        const world = maps.worlds.getPtr(host.world_id) orelse return;

        switch (self.state) {
            .waiting => {
                if (world.anyPlayersNear(host.x, host.y, 15 * 15)) {
                    self.next_switch_time = main.current_time + 5 * std.time.us_per_s;
                    self.state = .monologue;
                }
            },
            .monologue => {
                if (time >= self.next_switch_time) {
                    defer self.next_switch_time = time + 30 * std.time.us_per_s;
                    switch (utils.rng.next() % 2) {
                        0 => self.state = .possession_next,
                        1 => self.state = .spawn_next,
                        else => unreachable,
                    }
                    host.condition.invulnerable = false;
                    return;
                }
                // todo text
            },
            .in_possession => {
                logic.wander(@src(), host, dt, 2.2);
                // the possessed axe/daggers/sword will signal a state switch once it dies
            },
            .enraged => {
                if (time >= self.next_switch_time) {
                    defer self.next_switch_time = time + std.time.us_per_min;
                    const possession_data = game_data.entity.from_name.get(switch (utils.rng.next() % 3) {
                        0 => "Possessed Axe of Anger",
                        1 => "Possessed Daggers of Anger",
                        2 => "Possessed Sword of Anger",
                        else => unreachable,
                    }) orelse return;
                    _ = try world.add(Entity, .{ .data_id = possession_data.id, .x = host.x, .y = host.y });
                }

                if (!logic.follow(@src(), host, dt, .{
                    .speed = 5.0,
                    .acquire_range = 16.0,
                    .cooldown = 0.5 * std.time.us_per_s,
                })) logic.wander(@src(), host, dt, 1.5);

                logic.shoot(@src(), host, time, dt, .{
                    .shoot_angle = 12.0,
                    .proj_index = 0,
                    .count = 3,
                    .radius = 20.0,
                    .cooldown = 0.1 * std.time.us_per_s,
                    .predictivity = 0.5,
                });

                logic.shoot(@src(), host, time, dt, .{
                    .shoot_angle = 360.0 / 9.0,
                    .proj_index = 1,
                    .count = 9,
                    .radius = 20.0,
                    .cooldown = 0.2 * std.time.us_per_s,
                });
            },
            .possession_next => {
                if (time >= self.next_switch_time) for (world.listForType(Entity).items) |*obj| {
                    if (utils.distSqr(obj.x, obj.y, host.x, host.y) <= 20 * 20)
                        inline for (.{
                            .{ "Discarded Axe", "Possessed Axe of Sorrow" },
                            .{ "Discarded Daggers", "Possessed Daggers of Sorrow" },
                            .{ "Discarded Sword", "Possessed Sword of Sorrow" },
                        }) |mapping| if (std.mem.eql(u8, obj.data.name, mapping[0])) {
                            const possession_data = game_data.entity.from_name.get(mapping[1]) orelse return;
                            _ = try world.add(Entity, .{ .data_id = possession_data.id, .x = obj.x, .y = obj.y });
                            try obj.delete();
                            self.state = .in_possession;
                            host.condition.invulnerable = true;
                            return;
                        };

                    self.state = .enraged;
                    return;
                };

                if (!logic.follow(@src(), host, dt, .{
                    .speed = 2.5,
                    .acquire_range = 16.0,
                    .cooldown = 0.5 * std.time.us_per_s,
                })) logic.wander(@src(), host, dt, 1.5);

                logic.shoot(@src(), host, time, dt, .{
                    .shoot_angle = 12.0,
                    .proj_index = 0,
                    .count = 3,
                    .radius = 20.0,
                    .cooldown = 0.33 * std.time.us_per_s,
                    .predictivity = 0.5,
                });

                logic.shoot(@src(), host, time, dt, .{
                    .shoot_angle = 360.0 / 9.0,
                    .proj_index = 1,
                    .count = 9,
                    .radius = 20.0,
                    .cooldown = 0.66 * std.time.us_per_s,
                });
            },
            .spawn_next => {
                if (time >= self.next_switch_time) {
                    defer self.next_switch_time = time + 30 * std.time.us_per_s;
                    switch (utils.rng.next() % 2) {
                        0 => self.state = .possession_next,
                        1 => self.state = .spawn_next,
                        else => unreachable,
                    }
                    const possession_data = game_data.entity.from_name.get(switch (utils.rng.next() % 3) {
                        0 => "Possessed Axe of Sorrow",
                        1 => "Possessed Daggers of Sorrow",
                        2 => "Possessed Sword of Sorrow",
                        else => unreachable,
                    }) orelse return;
                    _ = try world.add(Entity, .{ .data_id = possession_data.id, .x = host.x, .y = host.y });
                    return;
                }

                if (!logic.follow(@src(), host, dt, .{
                    .speed = 2.5,
                    .acquire_range = 16.0,
                    .cooldown = 0.5 * std.time.us_per_s,
                })) logic.wander(@src(), host, dt, 1.5);

                logic.shoot(@src(), host, time, dt, .{
                    .shoot_angle = 12.0,
                    .proj_index = 0,
                    .count = 3,
                    .radius = 20.0,
                    .cooldown = 0.33 * std.time.us_per_s,
                    .predictivity = 0.5,
                });

                logic.shoot(@src(), host, time, dt, .{
                    .shoot_angle = 360.0 / 9.0,
                    .proj_index = 1,
                    .count = 9,
                    .radius = 20.0,
                    .cooldown = 0.66 * std.time.us_per_s,
                });
            },
        }
    }
};
