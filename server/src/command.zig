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
        .{ "/setcrowns", network_data.Rank.admin, handleSetCrowns },
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

    const item_name = iter.buffer[iter.index orelse 0 ..];
    const item_data = game_data.item.from_name.get(item_name) orelse {
        player.client.sendMessage(std.fmt.bufPrint(&response_buf, "\"{s}\" not found in game data", .{item_name}) catch return);
        return;
    };
    const class_data = game_data.class.from_id.get(player.data_id) orelse return;
    for (&player.inventory, 0..) |*equip, i| {
        if (equip.* == std.math.maxInt(u16) and (i >= 4 or class_data.item_types[i].typesMatch(item_data.item_type))) {
            equip.* = item_data.id;
            player.client.sendMessage(std.fmt.bufPrint(&response_buf, "You've been given a \"{s}\"", .{item_data.name}) catch return);
            return;
        }
    }

    player.client.sendMessage("You don't have enough space");
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

fn handleSetCrowns(iter: *std.mem.SplitIterator(u8, .scalar), player: *Player) void {
    var response_buf: [256]u8 = undefined;

    const player_name = iter.next() orelse {
        player.client.sendMessage("Invalid command usage. Arguments: /setcrowns [name] [decimal amount]");
        return;
    };
    const amount = std.fmt.parseInt(u32, iter.buffer[iter.index orelse 0 ..], 0) catch {
        player.client.sendMessage("Invalid command usage. Arguments: /setcrowns [name] [decimal amount]");
        return;
    };

    for (player.world.listForType(Player).items) |*other_player|
        if (std.mem.eql(u8, other_player.name, player_name)) {
            const old_crowns = other_player.crowns;
            other_player.crowns = amount;

            if (std.mem.eql(u8, player.name, player_name))
                player.client.sendMessage(std.fmt.bufPrint(&response_buf, "You've given yourself {} Crowns", .{amount - old_crowns}) catch return)
            else {
                other_player.client.sendMessage(std.fmt.bufPrint(
                    &response_buf,
                    "You've received {} Crowns from \"{s}\"",
                    .{ amount - old_crowns, player.name },
                ) catch return);
                player.client.sendMessage(std.fmt.bufPrint(
                    &response_buf,
                    "You've given \"{s}\" {} Crowns",
                    .{ other_player.name, amount - old_crowns },
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

    const old_crowns = acc_data.get(.crowns) catch {
        player.client.sendMessage(std.fmt.bufPrint(&response_buf, "Accessing database records for player \"{s}\" failed", .{player_name}) catch return);
        return;
    };

    acc_data.set(.{ .crowns = amount }) catch {
        player.client.sendMessage(std.fmt.bufPrint(&response_buf, "Accessing database records for player \"{s}\" failed", .{player_name}) catch return);
        return;
    };

    player.client.sendMessage(std.fmt.bufPrint(&response_buf, "You've given \"{s}\" {} Crowns", .{ player_name, amount - old_crowns }) catch return);
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