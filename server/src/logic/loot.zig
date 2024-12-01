const std = @import("std");
const main = @import("../main.zig");
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

fn nameContains(name_list: []const []const u8, name: []const u8) bool {
    for (name_list) |name_item| if (std.mem.eql(u8, name_item, name)) return true;
    return false;
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
        var has_null = false;
        var name_list: []const []const u8 = &.{};
        for (items) |item| {
            if (item.name) |name| {
                if (nameContains(name_list, name))
                    @compileError("Do not have multiples of the same portal in the pool. Merge their weights instead");
                name_list = name_list ++ .{name};
            }

            min_rolls = min_rolls ++ .{total_weights};
            max_rolls = max_rolls ++ .{total_weights + item.weight};
            total_weights += item.weight;
        } else {
            if (has_null) @compileError("Do not have multiples of empty loot. Merge their weights instead");
            has_null = true;
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
        var has_null = false;
        var name_list: []const []const u8 = &.{};
        for (items) |item| {
            if (item.threshold < 0.0 or item.threshold > 1.0) @compileError("Invalid threshold, keep it [0.0; 1.0]");

            if (item.name) |name| {
                if (nameContains(name_list, name))
                    @compileError("Do not have multiples of the same item in the pool. Merge their weights instead");
                name_list = name_list ++ .{name};
            }

            min_rolls = min_rolls ++ .{total_weights};
            max_rolls = max_rolls ++ .{total_weights + item.weight};
            total_weights += item.weight;
        } else {
            if (has_null) @compileError("Do not have multiples of empty loot. Merge their weights instead");
            has_null = true;
        }
    }

    var iter = host.damages_dealt.iterator();
    const fmax_hp: f32 = @floatFromInt(host.max_hp);
    while (iter.next()) |entry| {
        const player = host.world.find(Player, entry.key_ptr.*, .con) orelse continue;

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

        var inventory = Container.inv_default;
        var inv_index: usize = 0;
        for (loot) |data_id| {
            if (data_id == std.math.maxInt(u16)) continue;
            inventory[inv_index] = data_id;
            inv_index += 1;
            if (inv_index == 9) {
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

const CardRollState = struct {
    total_weights: u32,
    min_rolls: []const u32,
    max_rolls: []const u32,
};

fn cardRollState(comptime len_upper_bound: usize, items: []const CardPoolItem) CardRollState {
    std.debug.assert(len_upper_bound >= items.len);

    var total_weights: u32 = 0;
    var min_rolls: [len_upper_bound]u32 = undefined;
    var max_rolls: [len_upper_bound]u32 = undefined;

    for (items, 0..) |item, i| {
        min_rolls[i] = total_weights;
        max_rolls[i] = total_weights + item.weight;
        total_weights += item.weight;
    }
    return .{
        .total_weights = total_weights,
        .min_rolls = min_rolls[0..items.len],
        .max_rolls = max_rolls[0..items.len],
    };
}

pub fn giveCards(host: anytype, comptime items: []const CardPoolItem) void {
    verifyType(@TypeOf(host));
    comptime {
        if (items.len < 3) @compileError("It's impossible to receive less than 3 cards, design the loot pool accordingly");

        var has_null = false;
        var name_list: []const []const u8 = &.{};
        for (items) |item| {
            if (item.threshold < 0.0 or item.threshold > 1.0) @compileError("Invalid threshold, keep it [0.0; 1.0]");

            if (item.name) |name| {
                if (nameContains(name_list, name))
                    @compileError("Do not have multiples of the same card in the pool. Merge their weights instead");
                name_list = name_list ++ .{name};
            } else {
                if (has_null) @compileError("Do not have multiples of empty loot. Merge their weights instead");
                has_null = true;
            }
        }
    }

    var roll_state: CardRollState = undefined;
    var buf: [@sizeOf(CardPoolItem) * items.len]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&buf);
    const allocator = fba.allocator();
    var iter = host.damages_dealt.iterator();
    const fmax_hp: f32 = @floatFromInt(host.max_hp);
    playerLoop: while (iter.next()) |entry| {
        const player = host.world.find(Player, entry.key_ptr.*, .ref) orelse continue :playerLoop;
        if (player.selecting_cards != null or player.cards.len >= player.aether * 5) continue;

        fba.reset();
        const fdamage: f32 = @floatFromInt(entry.value_ptr.*);
        var cleaned_items: std.ArrayListUnmanaged(CardPoolItem) = .empty;
        cleaned_items.ensureTotalCapacityPrecise(allocator, items.len) catch main.oomPanic();
        for (items) |item| {
            if (item.name == null) {
                if (fdamage / fmax_hp >= item.threshold) cleaned_items.appendAssumeCapacity(item);
                continue;
            }
            const data = game_data.card.from_name.get(item.name.?) orelse {
                std.log.err("Card not found for name \"{s}\"", .{item.name.?});
                return;
            };
            if (!data.stackable and std.mem.indexOfScalar(u16, player.cards, data.id) != null) continue;
            if (fdamage / fmax_hp < item.threshold) continue;
            cleaned_items.appendAssumeCapacity(item);
        }
        if (cleaned_items.items.len < 3) continue;
        roll_state = cardRollState(items.len, cleaned_items.items);

        var cards: [3]u16 = @splat(std.math.maxInt(u16));
        mainLoop: for (0..3) |i| {
            const roll = utils.rng.random().intRangeAtMost(u32, 0, roll_state.total_weights);
            for (cleaned_items.items, 0..) |item, j| {
                if (item.name == null) continue :playerLoop;

                if (roll_state.min_rolls[j] <= roll and roll <= roll_state.max_rolls[j]) {
                    const data = game_data.card.from_name.get(item.name.?) orelse unreachable;
                    cards[i] = data.id;
                    _ = cleaned_items.orderedRemove(j);
                    roll_state = cardRollState(items.len, cleaned_items.items);
                    continue :mainLoop;
                }
            }

            continue :playerLoop;
        }

        player.selecting_cards = cards;
        player.client.queuePacket(.{ .card_options = .{ .cards = cards } });
    }
}
