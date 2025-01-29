const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const network_data = shared.network_data;
const utils = shared.utils;

const Client = @import("GameClient.zig");
const db = @import("db.zig");
const main = @import("main.zig");
const Ally = @import("map/Ally.zig");
const Container = @import("map/Container.zig");
const Enemy = @import("map/Enemy.zig");
const Entity = @import("map/Entity.zig");
const Player = @import("map/Player.zig");
const Portal = @import("map/Portal.zig");
const Purchasable = @import("map/Purchasable.zig");

fn checkRank(player: *Player, comptime rank: network_data.Rank) bool {
    if (@intFromEnum(player.rank) >= @intFromEnum(rank)) return true;
    player.client.sendMessage("You don't meet the rank requirements");
    return false;
}

pub fn handle(iter: *std.mem.SplitIterator(u8, .scalar), player: *Player) void {
    const command_name = iter.next() orelse return;
    inline for (.{
        .{ "/spawn", network_data.Rank.admin, handleSpawn },
        .{ "/clearspawn", network_data.Rank.admin, handleClearSpawn },
        .{ "/give", network_data.Rank.admin, handleGive },
        .{ "/setgold", network_data.Rank.admin, handleSetGold },
        .{ "/setgems", network_data.Rank.admin, handleSetGems },
        .{ "/setresource", network_data.Rank.admin, handleSetResource },
        .{ "/rank", network_data.Rank.admin, handleRank },
        .{ "/ban", network_data.Rank.mod, handleBan },
        .{ "/unban", network_data.Rank.mod, handleUnban },
        .{ "/mute", network_data.Rank.mod, handleMute },
        .{ "/unmute", network_data.Rank.mod, handleUnmute },
        .{ "/cond", network_data.Rank.mod, handleCond },
    }) |mappings| if (std.mem.eql(u8, mappings[0], command_name) and checkRank(player, mappings[1])) {
        mappings[2](iter, player);
        return;
    };

    player.client.sendMessage("Unknown command");
}

fn handleSpawn(iter: *std.mem.SplitIterator(u8, .scalar), player: *Player) void {
    var buf: [256]u8 = undefined;
    var name_stream = std.io.fixedBufferStream(&buf);
    const first_str = iter.next() orelse return;
    const count = blk: {
        const int = std.fmt.parseInt(u16, first_str, 0) catch {
            _ = name_stream.write(first_str) catch return;
            break :blk 1;
        };

        break :blk int;
    };
    if (iter.index) |i| {
        if (name_stream.pos != 0)
            _ = name_stream.write(" ") catch return;
        _ = name_stream.write(iter.buffer[i..]) catch return;
    }

    var response_buf: [256]u8 = undefined;

    const written_name = name_stream.getWritten();
    var name: ?[]const u8 = null;
    inline for (.{ Entity, Enemy, Portal, Container, Purchasable, Ally }) |ObjType| {
        if (switch (ObjType) {
            Entity => game_data.entity,
            Enemy => game_data.enemy,
            Portal => game_data.portal,
            Container => game_data.container,
            Purchasable => game_data.purchasable,
            Ally => game_data.ally,
            else => @compileError("Invalid type"),
        }.from_name.get(written_name)) |data| {
            name = data.name;
            for (0..count) |_| _ = player.world.add(ObjType, .{
                .x = player.x,
                .y = player.y,
                .data_id = data.id,
                .spawned = true,
            }) catch return;
        }
    }

    if (name) |name_inner| {
        player.client.sendMessage(std.fmt.bufPrint(&response_buf, "Spawned {}x \"{s}\"", .{ count, name_inner }) catch return);
    } else {
        player.client.sendMessage(std.fmt.bufPrint(&response_buf, "\"{s}\" not found in game data", .{written_name}) catch return);
        return;
    }
}

fn handleGive(iter: *std.mem.SplitIterator(u8, .scalar), player: *Player) void {
    var response_buf: [256]u8 = undefined;

    const amount = std.fmt.parseInt(u16, iter.next() orelse {
        player.client.sendMessage("Invalid command usage. Arguments: /give [decimal amount] [name]");
        return;
    }, 0) catch {
        player.client.sendMessage("Improper amount supplied for /give");
        return;
    };

    const item_name = iter.buffer[iter.index orelse 0 ..];
    const item_data = game_data.item.from_name.get(item_name) orelse {
        player.client.sendMessage(std.fmt.bufPrint(&response_buf, "\"{s}\" not found in game data", .{item_name}) catch "Buffer overflow");
        return;
    };
    const class_data = game_data.class.from_id.get(player.data_id) orelse return;
    var amount_given: usize = 0;
    for (0..amount) |_|
        for (&player.inventory, &player.inv_data, 0..) |*equip, *inv_data, j| {
            if (equip.* == std.math.maxInt(u16) and (j >= 4 or class_data.item_types[j].typesMatch(item_data.item_type))) {
                equip.* = item_data.id;
                if (item_data.max_stack > 0) {
                    const clamped_amount = @min(item_data.max_stack, amount);
                    inv_data.*.amount = clamped_amount;
                    player.client.sendMessage(
                        std.fmt.bufPrint(&response_buf, "You've been given {}x \"{s}\"", .{ clamped_amount, item_data.name }) catch "Buffer overflow",
                    );
                    return;
                }
                amount_given += 1;
            }
        };

    if (amount_given == 0)
        player.client.sendMessage("You don't have enough space for any items")
    else
        player.client.sendMessage(
            std.fmt.bufPrint(&response_buf, "You've been given {}x \"{s}\"", .{ amount_given, item_data.name }) catch "Buffer overflow",
        );
}

fn handleClearSpawn(_: *std.mem.SplitIterator(u8, .scalar), player: *Player) void {
    var count: usize = 0;
    inline for (.{ Entity, Enemy, Portal, Container }) |ObjType| {
        for (player.world.listForType(ObjType).items) |*obj| {
            if (obj.spawned) {
                player.world.remove(ObjType, obj) catch continue;
                count += 1;
            }
        }
    }

    if (count == 0) {
        player.client.sendMessage("No entities found");
    } else {
        var buf: [256]u8 = undefined;
        player.client.sendMessage(std.fmt.bufPrint(&buf, "Cleared {} entities", .{count}) catch return);
    }
}

fn handleBan(iter: *std.mem.SplitIterator(u8, .scalar), player: *Player) void {
    var response_buf: [256]u8 = undefined;

    var names: db.Names = .{};
    defer names.deinit();

    const player_name = iter.next() orelse {
        player.client.sendMessage("Invalid command usage. Arguments: /ban [name] [optional expiry, in seconds]");
        return;
    };
    const acc_id = names.get(player_name) catch {
        player.client.sendMessage(std.fmt.bufPrint(&response_buf, "Player \"{s}\" not found in database", .{player_name}) catch return);
        return;
    };

    var acc_data: db.AccountData = .{ .acc_id = acc_id };
    defer acc_data.deinit();

    const expiry_str = iter.next();
    const expiry = if (expiry_str) |str| std.fmt.parseInt(u32, str, 10) catch std.math.maxInt(u32) else std.math.maxInt(u32);

    banHwid: {
        const hwid = acc_data.get(.hwid) catch break :banHwid;
        var banned_hwids: db.BannedHwids = .{};
        defer banned_hwids.deinit();
        banned_hwids.add(hwid, expiry) catch break :banHwid;
    }

    acc_data.set(.{ .ban_expiry = main.current_time + expiry * std.time.us_per_s }) catch {
        player.client.sendMessage(std.fmt.bufPrint(&response_buf, "Accessing database records for player \"{s}\" failed", .{player_name}) catch return);
        return;
    };

    player.client.sendMessage(std.fmt.bufPrint(&response_buf, "Player \"{s}\" successfully banned", .{player_name}) catch return);
}

fn handleUnban(iter: *std.mem.SplitIterator(u8, .scalar), player: *Player) void {
    var response_buf: [256]u8 = undefined;

    var names: db.Names = .{};
    defer names.deinit();

    const player_name = iter.next() orelse {
        player.client.sendMessage("Invalid command usage. Arguments: /unban [name]");
        return;
    };
    const acc_id = names.get(player_name) catch {
        player.client.sendMessage(std.fmt.bufPrint(&response_buf, "Player \"{s}\" not found in database", .{player_name}) catch return);
        return;
    };

    var acc_data: db.AccountData = .{ .acc_id = acc_id };
    defer acc_data.deinit();

    unbanHwid: {
        const hwid = acc_data.get(.hwid) catch break :unbanHwid;
        var banned_hwids: db.BannedHwids = .{};
        defer banned_hwids.deinit();
        banned_hwids.remove(hwid) catch break :unbanHwid;
    }

    acc_data.set(.{ .ban_expiry = 0 }) catch {
        player.client.sendMessage(std.fmt.bufPrint(&response_buf, "Accessing database records for player \"{s}\" failed", .{player_name}) catch return);
        return;
    };

    player.client.sendMessage(std.fmt.bufPrint(&response_buf, "Player \"{s}\" successfully unbanned", .{player_name}) catch return);
}

fn handleMute(iter: *std.mem.SplitIterator(u8, .scalar), player: *Player) void {
    var response_buf: [256]u8 = undefined;

    var names: db.Names = .{};
    defer names.deinit();

    const player_name = iter.next() orelse {
        player.client.sendMessage("Invalid command usage. Arguments: /mute [name] [optional expiry, in seconds]");
        return;
    };
    const acc_id = names.get(player_name) catch {
        player.client.sendMessage(std.fmt.bufPrint(&response_buf, "Player \"{s}\" not found in database", .{player_name}) catch return);
        return;
    };

    var acc_data: db.AccountData = .{ .acc_id = acc_id };
    defer acc_data.deinit();

    const expiry_str = iter.next();
    const expiry = if (expiry_str) |str| std.fmt.parseInt(u32, str, 10) catch std.math.maxInt(u32) else std.math.maxInt(u32);

    muteHwid: {
        const hwid = acc_data.get(.hwid) catch break :muteHwid;
        var muted_hwids: db.MutedHwids = .{};
        defer muted_hwids.deinit();
        muted_hwids.add(hwid, expiry) catch break :muteHwid;
    }

    acc_data.set(.{ .mute_expiry = main.current_time + expiry * std.time.us_per_s }) catch {
        player.client.sendMessage(std.fmt.bufPrint(&response_buf, "Accessing database records for player \"{s}\" failed", .{player_name}) catch return);
        return;
    };

    player.client.sendMessage(std.fmt.bufPrint(&response_buf, "Player \"{s}\" successfully muted", .{player_name}) catch return);
}

fn handleUnmute(iter: *std.mem.SplitIterator(u8, .scalar), player: *Player) void {
    var response_buf: [256]u8 = undefined;

    var names: db.Names = .{};
    defer names.deinit();

    const player_name = iter.next() orelse {
        player.client.sendMessage("Invalid command usage. Arguments: /unmute [name]");
        return;
    };
    const acc_id = names.get(player_name) catch {
        player.client.sendMessage(std.fmt.bufPrint(&response_buf, "Player \"{s}\" not found in database", .{player_name}) catch return);
        return;
    };

    var acc_data: db.AccountData = .{ .acc_id = acc_id };
    defer acc_data.deinit();

    unmuteHwid: {
        const hwid = acc_data.get(.hwid) catch break :unmuteHwid;
        var muted_hwids: db.MutedHwids = .{};
        defer muted_hwids.deinit();
        muted_hwids.remove(hwid) catch break :unmuteHwid;
    }

    acc_data.set(.{ .mute_expiry = 0 }) catch {
        player.client.sendMessage(std.fmt.bufPrint(&response_buf, "Accessing database records for player \"{s}\" failed", .{player_name}) catch return);
        return;
    };

    player.client.sendMessage(std.fmt.bufPrint(&response_buf, "Player \"{s}\" successfully unmuted", .{player_name}) catch return);
}

fn handleCond(iter: *std.mem.SplitIterator(u8, .scalar), player: *Player) void {
    var response_buf: [256]u8 = undefined;

    const cond_name = iter.buffer[iter.index orelse 0 ..];
    const cond = std.meta.stringToEnum(utils.ConditionEnum, cond_name) orelse {
        player.client.sendMessage(std.fmt.bufPrint(&response_buf, "Condition \"{s}\" not found in game data", .{cond_name}) catch return);
        return;
    };
    player.condition.toggle(cond);
    if (player.condition.get(cond)) {
        player.client.sendMessage(std.fmt.bufPrint(&response_buf, "Condition applied: \"{s}\"", .{@tagName(cond)}) catch return);
        return;
    } else {
        player.client.sendMessage(std.fmt.bufPrint(&response_buf, "Condition removed: \"{s}\"", .{@tagName(cond)}) catch return);
        return;
    }
}

fn handleSetGold(iter: *std.mem.SplitIterator(u8, .scalar), player: *Player) void {
    var response_buf: [256]u8 = undefined;

    const player_name = iter.next() orelse {
        player.client.sendMessage("Invalid command usage. Arguments: /setgold [name] [decimal amount]");
        return;
    };
    const amount = std.fmt.parseInt(u32, iter.buffer[iter.index orelse 0 ..], 0) catch {
        player.client.sendMessage("Invalid command usage. Arguments: /setgold [name] [decimal amount]");
        return;
    };

    for (player.world.listForType(Player).items) |*other_player|
        if (std.mem.eql(u8, other_player.name, player_name)) {
            const old_gold = other_player.gold;
            other_player.gold = amount;

            if (std.mem.eql(u8, player.name, player_name))
                player.client.sendMessage(std.fmt.bufPrint(&response_buf, "You've given yourself {} Gold", .{amount - old_gold}) catch return)
            else {
                other_player.client.sendMessage(std.fmt.bufPrint(
                    &response_buf,
                    "You've received {} Gold from \"{s}\"",
                    .{ amount - old_gold, player.name },
                ) catch return);
                player.client.sendMessage(std.fmt.bufPrint(
                    &response_buf,
                    "You've given \"{s}\" {} Gold",
                    .{ other_player.name, amount - old_gold },
                ) catch return);
            }
            return;
        };

    var names: db.Names = .{};
    defer names.deinit();

    const acc_id = names.get(player_name) catch {
        player.client.sendMessage(std.fmt.bufPrint(&response_buf, "Player \"{s}\" not found in database", .{player_name}) catch return);
        return;
    };

    var acc_data: db.AccountData = .{ .acc_id = acc_id };
    defer acc_data.deinit();

    const old_gold = acc_data.get(.gold) catch {
        player.client.sendMessage(std.fmt.bufPrint(&response_buf, "Accessing database records for player \"{s}\" failed", .{player_name}) catch return);
        return;
    };

    acc_data.set(.{ .gold = amount }) catch {
        player.client.sendMessage(std.fmt.bufPrint(&response_buf, "Accessing database records for player \"{s}\" failed", .{player_name}) catch return);
        return;
    };

    player.client.sendMessage(std.fmt.bufPrint(&response_buf, "You've given \"{s}\" {} Gold", .{ player_name, amount - old_gold }) catch return);
}

fn handleSetGems(iter: *std.mem.SplitIterator(u8, .scalar), player: *Player) void {
    var response_buf: [256]u8 = undefined;

    const player_name = iter.next() orelse {
        player.client.sendMessage("Invalid command usage. Arguments: /setgems [name] [decimal amount]");
        return;
    };
    const amount = std.fmt.parseInt(u32, iter.buffer[iter.index orelse 0 ..], 0) catch {
        player.client.sendMessage("Invalid command usage. Arguments: /setgems [name] [decimal amount]");
        return;
    };

    for (player.world.listForType(Player).items) |*other_player|
        if (std.mem.eql(u8, other_player.name, player_name)) {
            const old_gems = other_player.gems;
            other_player.gems = amount;

            if (std.mem.eql(u8, player.name, player_name))
                player.client.sendMessage(std.fmt.bufPrint(&response_buf, "You've given yourself {} Gems", .{amount - old_gems}) catch return)
            else {
                other_player.client.sendMessage(std.fmt.bufPrint(
                    &response_buf,
                    "You've received {} Gems from \"{s}\"",
                    .{ amount - old_gems, player.name },
                ) catch return);
                player.client.sendMessage(std.fmt.bufPrint(
                    &response_buf,
                    "You've given \"{s}\" {} Gems",
                    .{ other_player.name, amount - old_gems },
                ) catch return);
            }
            return;
        };

    var names: db.Names = .{};
    defer names.deinit();

    const acc_id = names.get(player_name) catch {
        player.client.sendMessage(std.fmt.bufPrint(&response_buf, "Player \"{s}\" not found in database", .{player_name}) catch return);
        return;
    };

    var acc_data: db.AccountData = .{ .acc_id = acc_id };
    defer acc_data.deinit();

    const old_gems = acc_data.get(.gems) catch {
        player.client.sendMessage(std.fmt.bufPrint(&response_buf, "Accessing database records for player \"{s}\" failed", .{player_name}) catch return);
        return;
    };

    acc_data.set(.{ .gems = amount }) catch {
        player.client.sendMessage(std.fmt.bufPrint(&response_buf, "Accessing database records for player \"{s}\" failed", .{player_name}) catch return);
        return;
    };

    player.client.sendMessage(std.fmt.bufPrint(&response_buf, "You've given \"{s}\" {} Gems", .{ player_name, amount - old_gems }) catch return);
}

fn handleSetResource(iter: *std.mem.SplitIterator(u8, .scalar), player: *Player) void {
    var response_buf: [256]u8 = undefined;

    const player_name = iter.next() orelse {
        player.client.sendMessage("Invalid command usage. Arguments: /setresource [player name] [decimal amount] [resource name]");
        return;
    };
    const amount = std.fmt.parseInt(u32, iter.next() orelse {
        player.client.sendMessage("Invalid command usage. Arguments: /setresource [player name] [decimal amount] [resource name]");
        return;
    }, 0) catch {
        player.client.sendMessage("Invalid resource amount given");
        return;
    };
    const resource_name = iter.buffer[iter.index orelse 0 ..];

    const resource_data = game_data.resource.from_name.get(resource_name) orelse {
        player.client.sendMessage("Resource not found in game data");
        return;
    };

    for (player.world.listForType(Player).items) |*other_player|
        if (std.mem.eql(u8, other_player.name, player_name)) {
            const old_resources = blk: {
                for (player.resources.items) |*res| if (res.data_id == resource_data.id) break :blk res.count;
                break :blk 0;
            };

            incrementResource: {
                for (player.resources.items) |*res| if (res.data_id == resource_data.id) {
                    res.count += amount;
                    break :incrementResource;
                };
                player.resources.append(main.allocator, .{
                    .data_id = resource_data.id,
                    .count = amount,
                }) catch main.oomPanic();
            }

            if (std.mem.eql(u8, player.name, player_name))
                player.client.sendMessage(std.fmt.bufPrint(
                    &response_buf,
                    "You've given yourself {}x {s}",
                    .{ amount - old_resources, resource_data.name },
                ) catch return)
            else {
                other_player.client.sendMessage(std.fmt.bufPrint(
                    &response_buf,
                    "You've received {}x {s} from \"{s}\"",
                    .{ amount - old_resources, resource_data.name, player.name },
                ) catch return);
                player.client.sendMessage(std.fmt.bufPrint(
                    &response_buf,
                    "You've given \"{s}\" {}x {s}",
                    .{ other_player.name, amount - old_resources, resource_data.name },
                ) catch return);
            }
            return;
        };

    var names: db.Names = .{};
    defer names.deinit();

    const acc_id = names.get(player_name) catch {
        player.client.sendMessage(std.fmt.bufPrint(&response_buf, "Player \"{s}\" not found in database", .{player_name}) catch return);
        return;
    };

    var acc_data: db.AccountData = .{ .acc_id = acc_id };
    defer acc_data.deinit();

    const resources = acc_data.get(.resources) catch {
        player.client.sendMessage(std.fmt.bufPrint(
            &response_buf,
            "Accessing database records for player \"{s}\" failed",
            .{player_name},
        ) catch return);
        return;
    };

    const new_resources = main.allocator.alloc(network_data.DataIdWithCount(u32), resources.len + 1) catch main.oomPanic();
    defer main.allocator.free(new_resources);
    @memcpy(new_resources[0..resources.len], resources);

    const old_resources = blk: {
        for (resources) |res| if (res.data_id == resource_data.id) break :blk res.count;
        break :blk 0;
    };

    incrementResource: {
        for (new_resources) |*res| if (res.data_id == resource_data.id) {
            res.count += amount;
            acc_data.set(.{ .resources = new_resources[0..resources.len] }) catch {
                player.client.sendMessage(std.fmt.bufPrint(
                    &response_buf,
                    "Accessing database records for player \"{s}\" failed",
                    .{player_name},
                ) catch return);
                return;
            };
            break :incrementResource;
        };

        new_resources[resources.len] = .{
            .data_id = resource_data.id,
            .count = amount,
        };
        acc_data.set(.{ .resources = new_resources }) catch {
            player.client.sendMessage(std.fmt.bufPrint(
                &response_buf,
                "Accessing database records for player \"{s}\" failed",
                .{player_name},
            ) catch return);
            return;
        };
    }

    player.client.sendMessage(std.fmt.bufPrint(
        &response_buf,
        "You've given \"{s}\" {}x {s}",
        .{ player_name, amount - old_resources, resource_data.name },
    ) catch return);
}

fn handleRank(iter: *std.mem.SplitIterator(u8, .scalar), player: *Player) void {
    var response_buf: [256]u8 = undefined;

    const player_name = iter.next() orelse {
        player.client.sendMessage("Invalid command usage. Arguments: /rank [name] [rank]");
        return;
    };
    const rank = std.meta.stringToEnum(network_data.Rank, iter.buffer[iter.index orelse 0 ..]) orelse {
        player.client.sendMessage("Invalid rank name. Arguments: /rank [name] [rank]");
        return;
    };

    if (@intFromEnum(rank) >= @intFromEnum(network_data.Rank.admin)) {
        player.client.sendMessage("This rank can not be given out in-game. Contact the owners");
        return;
    }

    for (player.world.listForType(Player).items) |other_player|
        if (std.mem.eql(u8, other_player.name, player_name)) {
            other_player.client.sendMessage(std.fmt.bufPrint(
                &response_buf,
                "You've received the {s} Rank from \"{s}\"",
                .{ rank.printName(), player.name },
            ) catch return);
            player.client.sendMessage(std.fmt.bufPrint(
                &response_buf,
                "You've set \"{s}\"'s Rank to {s}",
                .{ other_player.name, rank.printName() },
            ) catch return);
            return;
        };

    var names: db.Names = .{};
    defer names.deinit();

    const acc_id = names.get(player_name) catch {
        player.client.sendMessage(std.fmt.bufPrint(&response_buf, "Player \"{s}\" not found in database", .{player_name}) catch return);
        return;
    };

    var acc_data: db.AccountData = .{ .acc_id = acc_id };
    defer acc_data.deinit();

    acc_data.set(.{ .rank = rank }) catch {
        player.client.sendMessage(std.fmt.bufPrint(&response_buf, "Accessing database records for player \"{s}\" failed", .{player_name}) catch return);
        return;
    };

    player.client.sendMessage(std.fmt.bufPrint(&response_buf, "You've set \"{s}\"'s Rank to {s}", .{ player_name, rank.printName() }) catch return);
}
