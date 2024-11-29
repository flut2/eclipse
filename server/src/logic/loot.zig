const std = @import("std");
const shared = @import("shared");
const utils = shared.utils;
const game_data = shared.game_data;

const Portal = @import("../map/Portal.zig");
const Enemy = @import("../map/Enemy.zig");
const Entity = @import("../map/Entity.zig");
const Player = @import("../map/Player.zig");
const Container = @import("../map/Container.zig");

fn verifyType(comptime T: type) void {
    const type_info = @typeInfo(T);
    if (type_info != .pointer or
        type_info.pointer.child != Enemy and
        type_info.pointer.child != Entity)
        @compileError("Invalid type given. Please use \"Enemy\" or \"Entity\"");
}

pub const PortalPoolItem = struct {
    name: ?[]const u8 = null, // null meaning empty slot, i.e. getting nothing
    weight: u32,
};

pub fn dropPortals(host: anytype, comptime items: []const PortalPoolItem) void {
    verifyType(@TypeOf(host));

    comptime var total_weights = 0;
    comptime var min_rolls: []const u32 = &.{};
    comptime var max_rolls: []const u32 = &.{};

    comptime {
        for (items) |item| {
            min_rolls = min_rolls ++ .{total_weights + 1};
            max_rolls = max_rolls ++ .{total_weights + item.weight};
            total_weights += item.weight;
        }
    }

    const roll = utils.rng.random().intRangeAtMost(u32, 0, total_weights);
    for (items, 0..) |item, i| {
        if (item.name == null) continue;

        if (min_rolls[i] <= roll and roll <= max_rolls[i]) {
            const data = game_data.portal.from_name.get(item.name.?) orelse {
                std.log.err("Portal not found for name \"{s}\"", .{item.name.?});
                return;
            };
            _ = host.world.add(Portal, .{ .x = host.x, .y = host.y, .data_id = data.id }) catch return;
            return;
        }
    }
}

pub const ItemPoolItem = struct {
    name: ?[]const u8 = null, // null meaning empty slot, i.e. getting nothing
    weight: u32,
    threshold: f32 = 0.0,
};

pub fn dropItems(host: anytype, rolls: comptime_int, comptime items: []const ItemPoolItem) void {
    verifyType(@TypeOf(host));
    comptime var total_weights = 0;
    comptime var min_rolls: []const u32 = &.{};
    comptime var max_rolls: []const u32 = &.{};

    comptime {
        for (items) |item| {
            if (item.threshold < 0.0 or item.threshold > 1.0) @compileError("Invalid threshold, keep it [0.0; 1.0]");

            min_rolls = min_rolls ++ .{total_weights + 1};
            max_rolls = max_rolls ++ .{total_weights + item.weight};
            total_weights += item.weight;
        }
    }

    var iter = host.damages_dealt.iterator();
    const fmax_hp: f32 = @floatFromInt(host.max_hp);
    while (iter.next()) |entry| {
        const player = host.world.find(Player, entry.key_ptr.*) orelse return;

        const fdamage: f32 = @floatFromInt(entry.value_ptr.*);
        var max_rarity: game_data.ContainerRarity = .common;
        var loot: [rolls]u16 = @splat(std.math.maxInt(u16));
        mainLoop: for (0..rolls) |i| {
            const roll = utils.rng.random().intRangeAtMost(u32, 0, total_weights);
            for (items, 0..) |item, j| {
                if (item.name == null or fdamage / fmax_hp < item.threshold) continue;

                if (min_rolls[j] <= roll and roll <= max_rolls[j]) {
                    const data = game_data.item.from_name.get(item.name.?) orelse {
                        std.log.err("Item not found for name \"{s}\"", .{item.name.?});
                        return;
                    };
                    loot[i] = data.id;
                    max_rarity = @enumFromInt(@max(@intFromEnum(max_rarity), @intFromEnum(data.rarity)));
                    continue :mainLoop;
                }
            }
        }

        const container_data_id: u16 = switch (max_rarity) {
            .common => 0,
            .rare => 3,
            .epic => 3,
            .legendary => 3,
            .mythic => 3,
        };

        var inventory: [8]u16 = Container.inv_default;
        var inv_index: usize = 0;
        for (loot) |data_id| {
            if (data_id == std.math.maxInt(u16)) continue;
            inventory[inv_index] = data_id;
            inv_index += 1;
            if (inv_index == 7) {
                const angle = utils.rng.random().float(f32) * std.math.tau;
                const radius = utils.rng.random().float(f32) * 1.0;
                _ = host.world.add(Container, .{
                    .data_id = container_data_id,
                    .name = host.data.name,
                    .x = host.x + radius * @cos(angle),
                    .y = host.y + radius * @sin(angle),
                    .owner_map_id = player.map_id,
                    .inventory = inventory,
                }) catch |e| {
                    std.log.err("Adding loot for player \"{s}\" failed: {}", .{ player.name, e });
                    continue;
                };
                inventory = Container.inv_default;
                inv_index = 0;
            }
        }

        if (inv_index > 0) {
            const angle = utils.rng.random().float(f32) * std.math.tau;
            const radius = utils.rng.random().float(f32) * 1.0;
            _ = host.world.add(Container, .{
                .data_id = container_data_id,
                .name = host.data.name,
                .x = host.x + radius * @cos(angle),
                .y = host.y + radius * @sin(angle),
                .owner_map_id = player.map_id,
                .inventory = inventory,
            }) catch |e| {
                std.log.err("Adding loot for player \"{s}\" failed: {}", .{ player.name, e });
                continue;
            };
        }
    }
}

pub const CardPoolItem = struct {
    name: ?[]const u8 = null, // null meaning empty slot, i.e. getting nothing
    weight: u32,
    threshold: f32,
};

pub fn giveCards(host: anytype, comptime items: []const CardPoolItem) void {
    verifyType(@TypeOf(host));
    comptime var total_weights = 0;
    comptime var min_rolls: []const u32 = &.{};
    comptime var max_rolls: []const u32 = &.{};

    comptime {
        for (items) |item| {
            if (item.threshold < 0.0 or item.threshold > 1.0) @compileError("Invalid threshold, keep it [0.0; 1.0]");

            min_rolls = min_rolls ++ .{total_weights + 1};
            max_rolls = max_rolls ++ .{total_weights + item.weight};
            total_weights += item.weight;
        }
    }

    var iter = host.damages_dealt.iterator();
    const fmax_hp: f32 = @floatFromInt(host.max_hp);
    while (iter.next()) |entry| {
        const player = host.world.findRef(Player, entry.key_ptr.*) orelse return;
        if (player.selecting_cards != null or player.cards.len >= player.aether * 5) continue;

        const fdamage: f32 = @floatFromInt(entry.value_ptr.*);
        var cards: [3]u16 = @splat(std.math.maxInt(u16));
        mainLoop: for (0..3) |i| {
            const roll = utils.rng.random().intRangeAtMost(u32, 0, total_weights);
            for (items, 0..) |item, j| {
                if (item.name == null or fdamage / fmax_hp < item.threshold) continue;

                if (min_rolls[j] <= roll and roll <= max_rolls[j]) {
                    const data = game_data.card.from_name.get(item.name.?) orelse {
                        std.log.err("Card not found for name \"{s}\"", .{item.name.?});
                        return;
                    };
                    if (std.mem.indexOfScalar(u16, &cards, data.id) != null) continue;
                    cards[i] = data.id;
                    continue :mainLoop;
                }
            }

            return;
        }

        player.selecting_cards = cards;
        player.client.queuePacket(.{ .card_options = .{ .cards = cards } });
    }
}
