const std = @import("std");

const shared = @import("shared");
const utils = shared.utils;
const game_data = shared.game_data;
const f32i = utils.f32i;
const ItemData = shared.network_data.ItemData;

const main = @import("../main.zig");
const Container = @import("../map/Container.zig");
const Enemy = @import("../map/Enemy.zig");
const Entity = @import("../map/Entity.zig");
const maps = @import("../map/maps.zig");
const Player = @import("../map/Player.zig");
const Portal = @import("../map/Portal.zig");

fn verifyType(comptime T: type) void {
    const type_info = @typeInfo(T);
    if (type_info != .pointer or type_info.pointer.child != Enemy and type_info.pointer.child != Entity)
        @compileError("Invalid type given. Please use \"Enemy\" or \"Entity\"");
}

fn nameContains(name_list: []const []const u8, name: []const u8) bool {
    for (name_list) |name_item| if (std.mem.eql(u8, name_item, name)) return true;
    return false;
}

pub const PortalLoot = struct { name: []const u8, chance: f32 };
pub fn dropPortals(host: anytype, comptime loots: []const PortalLoot) void {
    comptime {
        verifyType(@TypeOf(host));
        var name_list: []const []const u8 = &.{};
        for (loots) |loot| {
            if (loot.chance <= 0.0 or loot.chance > 1.0) @compileError("Invalid chance, keep it ]0.0; 1.0]");

            if (nameContains(name_list, loot.name))
                @compileError("Do not have multiples of the same portal in the loot table. Increase the chance of the existing one instead");
            name_list = name_list ++ .{loot.name};
        }
    }

    const world = maps.worlds.getPtr(host.world_id) orelse return;

    inline for (loots) |loot| if (loot.chance >= utils.rng.random().float(f32)) {
        const data = game_data.portal.from_name.get(loot.name) orelse {
            std.log.err("Portal not found for name \"{s}\"", .{loot.name});
            return;
        };
        _ = world.add(Portal, .{ .x = host.x, .y = host.y, .data_id = data.id }) catch return;
        return;
    };
}

pub const ItemLoot = struct { name: []const u8, min: u16 = 1, max: u16 = 1, chance: f32, threshold: f32 = 0.0 };
pub fn dropItems(host: anytype, comptime loots: []const ItemLoot) void {
    comptime {
        verifyType(@TypeOf(host));
        var name_list: []const []const u8 = &.{};
        for (loots) |loot| {
            if (loot.threshold < 0.0 or loot.threshold > 1.0) @compileError("Invalid threshold, keep it [0.0; 1.0]");
            if (loot.chance <= 0.0 or loot.chance > 1.0) @compileError("Invalid chance, keep it ]0.0; 1.0]");
            if (loot.min > loot.max) @compileError("The minimum amount can't be larger than the maximum amount");

            if (nameContains(name_list, loot.name))
                @compileError("Do not have multiples of the same item in the loot table. Increase the chance of the existing one instead");
            name_list = name_list ++ .{loot.name};
        }
    }

    const world = maps.worlds.getPtr(host.world_id) orelse return;

    var iter = host.damages_dealt.iterator();
    const fmax_hp = f32i(host.max_hp);
    while (iter.next()) |entry| {
        const player = world.find(Player, entry.key_ptr.*, .con) orelse continue;

        const fdamage = f32i(entry.value_ptr.*);
        var max_rarity: game_data.ItemRarity = .common;
        var received_loot: std.ArrayListUnmanaged(u16) = .empty;
        defer received_loot.deinit(main.allocator);
        var received_item_data: std.ArrayListUnmanaged(ItemData) = .empty;
        defer received_item_data.deinit(main.allocator);
        var loot_idx: usize = 0;
        inline for (loots) |loot| @"continue": {
            if (fdamage / fmax_hp <= loot.threshold) break :@"continue";

            const rand = utils.rng.random();
            if (loot.chance >= rand.float(f32)) {
                const data = game_data.item.from_name.get(loot.name) orelse {
                    std.log.err("Item not found for name \"{s}\"", .{loot.name});
                    break :@"continue";
                };
                const amount = rand.intRangeAtMost(u16, loot.min, loot.max);
                if (data.max_stack > 0) {
                    received_loot.append(main.allocator, data.id) catch main.oomPanic();
                    received_item_data.append(main.allocator, .{ .amount = amount }) catch main.oomPanic();
                    loot_idx += 1;
                    max_rarity = @enumFromInt(@max(@intFromEnum(max_rarity), @intFromEnum(data.rarity)));
                } else for (0..amount) |_| {
                    received_loot.append(main.allocator, data.id) catch main.oomPanic();
                    received_item_data.append(main.allocator, .{}) catch main.oomPanic();
                    loot_idx += 1;
                    max_rarity = @enumFromInt(@max(@intFromEnum(max_rarity), @intFromEnum(data.rarity)));
                }
            }
        }

        const container_data_id = max_rarity.containerDataId();

        var inventory = Container.inv_default;
        var inv_data = Container.inv_data_default;
        var inv_index: usize = 0;
        for (received_loot.items, received_item_data.items) |data_id, item_data| {
            if (data_id == std.math.maxInt(u16)) continue;
            inventory[inv_index] = data_id;
            inv_data[inv_index] = item_data;
            if (inv_index == 8) {
                const angle = utils.rng.random().float(f32) * std.math.tau;
                const radius = utils.rng.random().float(f32) * 1.0;
                _ = world.add(Container, .{
                    .data_id = container_data_id,
                    .name = host.data.name,
                    .x = host.x + radius * @cos(angle),
                    .y = host.y + radius * @sin(angle),
                    .owner_map_id = player.map_id,
                    .inventory = inventory,
                    .inv_data = inv_data,
                }) catch |e| {
                    std.log.err("Adding loot for player \"{s}\" failed: {}", .{ player.name, e });
                    continue;
                };
                inventory = Container.inv_default;
                inv_data = Container.inv_data_default;
                inv_index = 0;
            } else inv_index += 1;
        }

        if (inv_index > 0) {
            const angle = utils.rng.random().float(f32) * std.math.tau;
            const radius = utils.rng.random().float(f32) * 1.0;
            _ = world.add(Container, .{
                .data_id = container_data_id,
                .name = host.data.name,
                .x = host.x + radius * @cos(angle),
                .y = host.y + radius * @sin(angle),
                .owner_map_id = player.map_id,
                .inventory = inventory,
                .inv_data = inv_data,
            }) catch |e| {
                std.log.err("Adding loot for player \"{s}\" failed: {}", .{ player.name, e });
                continue;
            };
        }
    }
}

pub const CardLoot = struct { name: []const u8, chance: f32, threshold: f32 };
pub fn dropCards(host: anytype, comptime loots: []const CardLoot) void {
    comptime {
        verifyType(@TypeOf(host));
        if (loots.len < 3) @compileError("It's impossible to receive less than 3 cards, design the drop table accordingly");

        var name_list: []const []const u8 = &.{};
        for (loots) |loot| {
            if (loot.threshold < 0.0 or loot.threshold > 1.0) @compileError("Invalid threshold, keep it [0.0; 1.0]");
            if (loot.chance <= 0.0 or loot.chance > 1.0) @compileError("Invalid chance, keep it ]0.0; 1.0]");

            if (nameContains(name_list, loot.name))
                @compileError("Do not have multiples of the same card in the loot table. Increase the chance of the existing one instead");
            name_list = name_list ++ .{loot.name};
        }
    }

    const world = maps.worlds.getPtr(host.world_id) orelse return;

    var iter = host.damages_dealt.iterator();
    const fmax_hp = f32i(host.max_hp);
    playerLoop: while (iter.next()) |entry| {
        const player = world.find(Player, entry.key_ptr.*, .ref) orelse continue :playerLoop;
        if (player.selecting_cards != null or player.cards.len >= player.aether * 5) continue;

        const fdamage = f32i(entry.value_ptr.*);
        var cards: [3]u16 = @splat(std.math.maxInt(u16));
        var card_idx: usize = 0;
        cardLoop: inline for (loots) |loot| @"continue": {
            if (fdamage / fmax_hp <= loot.threshold) break :@"continue";

            if (loot.chance >= utils.rng.random().float(f32)) {
                const data = game_data.card.from_name.get(loot.name) orelse {
                    std.log.err("Card not found for name \"{s}\"", .{loot.name});
                    return;
                };
                cards[card_idx] = data.id;
                card_idx += 1;
                if (card_idx == 3) break :cardLoop;
            }
        }

        if (card_idx == 3) {
            player.selecting_cards = cards;
            player.client.queuePacket(.{ .card_options = .{ .cards = cards } });
        }
    }
}

pub const ResourceLoot = struct { name: []const u8, min: u32, max: u32, chance: f32, threshold: f32 };
pub fn dropResources(host: anytype, comptime loots: []const ResourceLoot) void {
    comptime {
        verifyType(@TypeOf(host));
        var name_list: []const []const u8 = &.{};
        for (loots) |loot| {
            if (loot.threshold < 0.0 or loot.threshold > 1.0) @compileError("Invalid threshold, keep it [0.0; 1.0]");
            if (loot.chance <= 0.0 or loot.chance > 1.0) @compileError("Invalid chance, keep it ]0.0; 1.0]");
            if (loot.min > loot.max) @compileError("The minimum amount can't be larger than the maximum amount");

            if (nameContains(name_list, loot.name))
                @compileError("Do not have multiples of the same resource in the loot table. Increase the chance of the existing one instead");
            name_list = name_list ++ .{loot.name};
        }
    }

    // TODO: some vfx

    const world = maps.worlds.getPtr(host.world_id) orelse return;

    var buf: [256]u8 = undefined;
    var rand = utils.rng.random();
    var iter = host.damages_dealt.iterator();
    const fmax_hp = f32i(host.max_hp);
    while (iter.next()) |entry| {
        const player = world.find(Player, entry.key_ptr.*, .ref) orelse continue;

        const fdamage = f32i(entry.value_ptr.*);
        inline for (loots) |loot| @"continue": {
            if (fdamage / fmax_hp <= loot.threshold) break :@"continue";

            if (loot.chance >= rand.float(f32)) {
                const data = game_data.resource.from_name.get(loot.name) orelse {
                    std.log.err("Resource not found for name \"{s}\"", .{loot.name});
                    return;
                };
                const amount = rand.intRangeAtMost(u32, loot.min, loot.max);
                incrementResource: {
                    for (player.resources.items) |*res| if (res.data_id == data.id) {
                        res.count += amount;
                        break :incrementResource;
                    };
                    player.resources.append(main.allocator, .{
                        .data_id = data.id,
                        .count = amount,
                    }) catch main.oomPanic();
                }

                player.client.queuePacket(.{ .text = .{
                    .name = "Server",
                    .obj_type = .entity,
                    .map_id = std.math.maxInt(u32),
                    .bubble_time = 0,
                    .recipient = "",
                    .text = std.fmt.bufPrint(&buf, "You've received {} " ++ loot.name, .{amount}) catch break :@"continue",
                    .name_color = 0xCC00CC,
                    .text_color = 0xFF99FF,
                } });
            }
        }
    }
}

pub const CurrencyLoot = struct { type: game_data.Currency, min: u32, max: u32, chance: f32, threshold: f32 };
pub fn dropCurrency(host: anytype, comptime loots: []const CurrencyLoot) void {
    comptime {
        verifyType(@TypeOf(host));
        for (loots) |loot| {
            if (loot.threshold < 0.0 or loot.threshold > 1.0) @compileError("Invalid threshold, keep it [0.0; 1.0]");
            if (loot.chance <= 0.0 or loot.chance > 1.0) @compileError("Invalid chance, keep it ]0.0; 1.0]");
            if (loot.min > loot.max) @compileError("The minimum amount can't be larger than the maximum amount");
        }
    }

    // TODO: some vfx

    const world = maps.worlds.getPtr(host.world_id) orelse return;

    var buf: [256]u8 = undefined;
    var rand = utils.rng.random();
    var iter = host.damages_dealt.iterator();
    const fmax_hp = f32i(host.max_hp);
    while (iter.next()) |entry| {
        const player = world.find(Player, entry.key_ptr.*, .ref) orelse continue;

        const fdamage = f32i(entry.value_ptr.*);
        inline for (loots) |loot| @"continue": {
            if (fdamage / fmax_hp <= loot.threshold) break :@"continue";

            if (loot.chance >= rand.float(f32)) {
                const amount = rand.intRangeAtMost(u32, loot.min, loot.max);
                switch (loot.type) {
                    .gems => player.gems += amount,
                    .gold => player.gold += amount,
                }
                player.client.queuePacket(.{ .text = .{
                    .name = "Server",
                    .obj_type = .entity,
                    .map_id = std.math.maxInt(u32),
                    .bubble_time = 0,
                    .recipient = "",
                    .text = std.fmt.bufPrint(&buf, "You've received {} " ++ switch (loot.type) {
                        .gems => "Gems",
                        .gold => "Gold",
                    }, .{amount}) catch break :@"continue",
                    .name_color = 0xCC00CC,
                    .text_color = 0xFF99FF,
                } });
            }
        }
    }
}

pub const SpiritLoot = struct { min: u32, max: u32, chance: f32, threshold: f32 };
pub fn dropSpirits(host: anytype, comptime loot: SpiritLoot) void {
    comptime {
        verifyType(@TypeOf(host));
        if (loot.threshold < 0.0 or loot.threshold > 1.0) @compileError("Invalid threshold, keep it [0.0; 1.0]");
        if (loot.chance <= 0.0 or loot.chance > 1.0) @compileError("Invalid chance, keep it ]0.0; 1.0]");
        if (loot.min > loot.max) @compileError("The minimum amount can't be larger than the maximum amount");
    }

    // TODO: some vfx

    const world = maps.worlds.getPtr(host.world_id) orelse return;

    var buf: [256]u8 = undefined;
    var rand = utils.rng.random();
    var iter = host.damages_dealt.iterator();
    const fmax_hp = f32i(host.max_hp);
    while (iter.next()) |entry| {
        const player = world.find(Player, entry.key_ptr.*, .ref) orelse continue;

        const fdamage = f32i(entry.value_ptr.*);
        if (fdamage / fmax_hp <= loot.threshold) continue;

        if (loot.chance >= rand.float(f32)) {
            const amount = rand.intRangeAtMost(u32, loot.min, loot.max);
            var total_item_spirits = amount / 2;
            const aether_spirits = amount - total_item_spirits;
            var total_recv: [4]u32 = @splat(0);
            while (total_item_spirits > 0) {
                var ways_to_slice: u8 = 0;
                for (player.inventory[0..4]) |item| {
                    if (item == std.math.maxInt(u16)) continue;
                    const data = game_data.item.from_id.get(item) orelse continue;
                    if (data.level_spirits == 0) continue;
                    ways_to_slice += 1;
                }
                if (ways_to_slice == 0) break;

                const slice_amount = @max(1, total_item_spirits / ways_to_slice);
                for (player.inventory[0..4], 0..) |item, i| {
                    if (item == std.math.maxInt(u16) or total_item_spirits <= 0) continue;
                    const data = game_data.item.from_id.get(item) orelse continue;
                    if (data.level_spirits == 0) continue;
                    const old_spirits = player.inv_data[i].amount;
                    const new_spirits = @min(data.level_spirits, player.inv_data[i].amount + slice_amount);
                    const spirit_delta = new_spirits - old_spirits;
                    total_item_spirits -= spirit_delta;
                    if (new_spirits == data.level_spirits) {
                        const next_data = game_data.item.from_name.get(data.level_transform_item.?).?;
                        player.inventory[i] = next_data.id;
                        player.inv_data[i].amount = 0;
                        player.client.sendMessage(
                            std.fmt.bufPrint(&buf, "Your \"{s}\" has leveled up, transforming into \"{s}\"", .{
                                data.name,
                                next_data.name,
                            }) catch continue,
                        );
                        player.recalculateBoosts();
                        total_recv[i] = 0;
                    } else {
                        player.inv_data[i].amount = new_spirits;
                        total_recv[i] += spirit_delta;
                    }
                }
            }

            for (total_recv, 0..) |recv, i| if (recv > 0) {
                const data = game_data.item.from_id.get(player.inventory[i]) orelse continue;
                player.client.sendMessage(
                    std.fmt.bufPrint(&buf, "Your \"{s}\" has received {} Spirits", .{ data.name, recv }) catch continue,
                );
            };

            const clamped_spirits = @min(game_data.spiritGoal(player.aether), player.spirits_communed + aether_spirits + total_item_spirits);
            const spirit_delta = clamped_spirits - player.spirits_communed;
            if (spirit_delta > 0) {
                player.client.sendMessage(
                    std.fmt.bufPrint(&buf, "You've received {} Spirits", .{spirit_delta}) catch continue,
                );
                player.spirits_communed = clamped_spirits;
            }
        }
    }
}
