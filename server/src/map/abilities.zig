const std = @import("std");
const shared = @import("shared");
const game_data = shared.game_data;
const utils = shared.utils;
const main = @import("../main.zig");

const Player = @import("Player.zig");
const Projectile = @import("Projectile.zig");
const Enemy = @import("Enemy.zig");
const Ally = @import("Ally.zig");
const World = @import("../World.zig");

pub fn handleTerrainExpulsion(player: *Player, proj_data: *const game_data.ProjectileData, proj_index: u8, angle: f32) !void {
    const x = player.x + @cos(angle) * 0.25;
    const y = player.y + @sin(angle) * 0.25;
    const map_id = player.world.add(Projectile, .{
        .x = x,
        .y = y,
        .owner_obj_type = .player,
        .owner_map_id = player.map_id,
        .angle = angle,
        .start_time = main.current_time,
        .phys_dmg = proj_data.phys_dmg,
        .index = proj_index,
        .data = proj_data,
    }) catch return;
    player.projectiles[proj_index] = map_id;
}

fn heartOfStoneCallback(world: *World, plr_id_opaque: ?*anyopaque) void {
    const player_map_id: *u32 = @ptrCast(@alignCast(plr_id_opaque.?));
    defer main.allocator.destroy(player_map_id);
    if (world.findRef(Player, player_map_id.*)) |player| {
        player.hit_multiplier = 1.0;
        player.ability_state.heart_of_stone = false;
    }
}

pub fn handleHeartOfStone(player: *Player) !void {
    const fint: f32 = @floatFromInt(player.stats[Player.intelligence_stat] + player.stat_boosts[Player.intelligence_stat]);
    const duration: i64 = @intFromFloat((10.0 + fint * 0.1) * std.time.us_per_s);

    player.hit_multiplier = 0.15;
    player.ability_state.heart_of_stone = true;
    try player.applyCondition(.slowed, duration);
    try player.applyCondition(.stunned, duration);

    const map_id_copy = try main.allocator.create(u32);
    map_id_copy.* = player.map_id;
    try player.world.callbacks.append(main.allocator, .{
        .trigger_on = main.current_time + duration,
        .callback = heartOfStoneCallback,
        .data = map_id_copy,
    });
}

pub fn handleBoulderBuddies(player: *Player) !void {
    for (0..3) |_| {
        const fint: f32 = @floatFromInt(player.stats[Player.intelligence_stat] + player.stat_boosts[Player.intelligence_stat]);
        const duration: i64 = @intFromFloat((15.0 + fint * 0.1) * std.time.us_per_s);
        const angle = utils.rng.random().float(f32) * std.math.tau;
        const radius = utils.rng.random().float(f32) * 2.0;
        const x = player.x + radius * @cos(angle);
        const y = player.y + radius * @sin(angle);

        const map_id = try player.world.add(Ally, .{
            .x = x,
            .y = y,
            .data_id = 0,
            .owner_map_id = player.map_id,
            .disappear_time = main.current_time + duration,
        });

        const fhp: f32 = @floatFromInt(player.stats[Player.health_stat] + player.stat_boosts[Player.health_stat]);
        const fdef: f32 = @floatFromInt(player.stats[Player.defense_stat] + player.stat_boosts[Player.defense_stat]);
        const fres: f32 = @floatFromInt(player.stats[Player.resistance_stat] + player.stat_boosts[Player.resistance_stat]);
        if (player.world.findRef(Ally, map_id)) |ally| {
            ally.max_hp = @intFromFloat(3600.0 + fhp * 3.6);
            ally.hp = ally.max_hp;
            ally.defense = @intFromFloat(25.0 + fdef * 0.15);
            ally.resistance = @intFromFloat(5.0 + fres * 0.1);
        } else return;

        player.client.queuePacket(.{ .show_effect = .{
            .obj_type = .ally,
            .map_id = map_id,
            .eff_type = .area_blast,
            .x1 = x,
            .y1 = y,
            .x2 = 1.5,
            .y2 = 0.0,
            .color = 0xA13A2F,
        } });
    }
}

pub fn handlePlaceholder() !void {
    std.log.err("Placeholder not implemented yet", .{});
}

fn timeDilationCallback(world: *World, plr_id_opaque: ?*anyopaque) void {
    const player_map_id: *u32 = @ptrCast(@alignCast(plr_id_opaque.?));
    defer main.allocator.destroy(player_map_id);
    if (world.findRef(Player, player_map_id.*)) |player| player.ability_state.time_dilation = false;
}

pub fn handleTimeDilation(player: *Player) !void {
    const fint: f32 = @floatFromInt(player.stats[Player.intelligence_stat] + player.stat_boosts[Player.intelligence_stat]);
    const duration: i64 = @intFromFloat((10.0 + fint * 0.12) * std.time.us_per_s);

    player.ability_state.time_dilation = true;

    const map_id_copy = try main.allocator.create(u32);
    map_id_copy.* = player.map_id;
    try player.world.callbacks.append(main.allocator, .{
        .trigger_on = main.current_time + duration,
        .callback = timeDilationCallback,
        .data = map_id_copy,
    });
}

pub fn handleRewind(player: *Player) !void {
    const fint: f32 = @floatFromInt(player.stats[Player.intelligence_stat] + player.stat_boosts[Player.intelligence_stat]);
    const fmana: f32 = @floatFromInt(player.stats[Player.mana_stat] + player.stat_boosts[Player.mana_stat]);
    const fwit: f32 = @floatFromInt(player.stats[Player.wit_stat] + player.stat_boosts[Player.wit_stat]);
    const duration: i64 = @intFromFloat((3.0 + fint * 0.06 + fmana * 0.06 + fwit * 0.06) * std.time.us_per_s);
    if (duration <= 0 or duration > 25 * std.time.us_per_s) {
        player.client.sendError(.message_with_disconnect, "Too many/little seconds elapsed");
        return;
    }

    const tick = player.chunked_tick_id -% @divFloor(@as(u64, @intCast(duration)), @as(u64, std.time.us_per_s) / main.settings.tps * 3);
    player.hp = player.hp_records[tick];
    player.x = player.position_records[tick].x;
    player.y = player.position_records[tick].y;
}

pub fn handleNullPulse(player: *Player) !void {
    const fint: f32 = @floatFromInt(player.stats[Player.intelligence_stat] + player.stat_boosts[Player.intelligence_stat]);
    const fwit: f32 = @floatFromInt(player.stats[Player.wit_stat] + player.stat_boosts[Player.wit_stat]);
    const radius = 3.0 + fint * 0.12;
    const radius_sqr = radius * radius;
    const damage_mult = 5.0 + fwit * 0.06;

    var projs_to_remove: std.ArrayListUnmanaged(usize) = .empty;
    for (player.world.listForType(Projectile).items, 0..) |*p, i| {
        if (utils.distSqr(p.x, p.y, player.x, player.y) <= radius_sqr) {
            if (player.world.findRef(Enemy, p.owner_map_id)) |e| {
                const phys_dmg: i32 = @intFromFloat(@as(f32, @floatFromInt(p.phys_dmg)) * damage_mult);
                const magic_dmg: i32 = @intFromFloat(@as(f32, @floatFromInt(p.magic_dmg)) * damage_mult);
                const true_dmg: i32 = @intFromFloat(@as(f32, @floatFromInt(p.true_dmg)) * damage_mult);
                e.damage(.player, player.map_id, phys_dmg, magic_dmg, true_dmg);
            }
            try p.deinit();
            projs_to_remove.append(main.allocator, i) catch @panic("OOM");
        }
    }
    var iter = std.mem.reverseIterator(projs_to_remove.items);
    while (iter.next()) |i| _ = player.world.lists.projectile.orderedRemove(i);
}

fn timeLockCallback(world: *World, plr_id_opaque: ?*anyopaque) void {
    const player_map_id: *u32 = @ptrCast(@alignCast(plr_id_opaque.?));
    defer main.allocator.destroy(player_map_id);
    if (world.findRef(Player, player_map_id.*)) |player| {
        const fint: f32 = @floatFromInt(player.stats[Player.intelligence_stat] + player.stat_boosts[Player.intelligence_stat]);
        const radius = 9.0 + fint * 0.06;
        player.world.aoe(Enemy, player.x, player.x, .player, player.map_id, radius, .{
            .magic_dmg = @intCast(@min(@as(u32, @intFromFloat(30000.0 + fint * 100.0)), player.stored_damage)),
            .aoe_color = 0x0FE9EB,
        });
        player.ability_state.time_lock = false;
        player.stored_damage = 0;
    }
}

pub fn handleTimeLock(player: *Player) !void {
    const fint: f32 = @floatFromInt(player.stats[Player.intelligence_stat] + player.stat_boosts[Player.intelligence_stat]);
    const duration: i64 = @intFromFloat((15.0 + fint * 0.12) * std.time.us_per_s);

    player.ability_state.time_lock = true;
    try player.applyCondition(.stunned, duration);
    try player.applyCondition(.paralyzed, duration);

    const map_id_copy = try main.allocator.create(u32);
    map_id_copy.* = player.map_id;
    try player.world.callbacks.append(main.allocator, .{
        .trigger_on = main.current_time + duration,
        .callback = timeLockCallback,
        .data = map_id_copy,
    });
}

fn equivalentExchangeCallback(world: *World, plr_id_opaque: ?*anyopaque) void {
    const player_map_id: *u32 = @ptrCast(@alignCast(plr_id_opaque.?));
    defer main.allocator.destroy(player_map_id);
    if (world.findRef(Player, player_map_id.*)) |player| player.ability_state.equivalent_exchange = false;
}

pub fn handleEquivalentExchange(player: *Player) !void {
    player.ability_state.equivalent_exchange = true;

    const map_id_copy = try main.allocator.create(u32);
    map_id_copy.* = player.map_id;
    try player.world.callbacks.append(main.allocator, .{
        .trigger_on = main.current_time + 8 * std.time.us_per_s,
        .callback = equivalentExchangeCallback,
        .data = map_id_copy,
    });
}

fn postAssetBubbleCallback(world: *World, plr_id_opaque: ?*anyopaque) void {
    const player_map_id: *u32 = @ptrCast(@alignCast(plr_id_opaque.?));
    defer main.allocator.destroy(player_map_id);
    if (world.findRef(Player, player_map_id.*)) |player| player.ability_state.post_asset_bubble = false;
}

fn assetBubbleCallback(world: *World, plr_id_opaque: ?*anyopaque) void {
    const player_map_id: *u32 = @ptrCast(@alignCast(plr_id_opaque.?));
    if (world.findRef(Player, player_map_id.*)) |player| {
        player.ability_state.asset_bubble = false;
        player.ability_state.post_asset_bubble = true;
        player.world.callbacks.append(main.allocator, .{
            .trigger_on = main.current_time + 17 * std.time.us_per_s,
            .callback = postAssetBubbleCallback,
            .data = player_map_id,
        }) catch {
            player.client.sendError(.message_with_disconnect, "World out of memory");
            return;
        };
    }
}

pub fn handleAssetBubble(player: *Player) !void {
    player.ability_state.asset_bubble = true;

    const map_id_copy = try main.allocator.create(u32);
    map_id_copy.* = player.map_id;
    try player.world.callbacks.append(main.allocator, .{
        .trigger_on = main.current_time + 8 * std.time.us_per_s,
        .callback = assetBubbleCallback,
        .data = map_id_copy,
    });
}

fn premiumProtectionCallback(world: *World, plr_id_opaque: ?*anyopaque) void {
    const player_map_id: *u32 = @ptrCast(@alignCast(plr_id_opaque.?));
    defer main.allocator.destroy(player_map_id);
    if (world.findRef(Player, player_map_id.*)) |player| player.ability_state.premium_protection = false;
}

pub fn handlePremiumProtection(player: *Player) !void {
    const fhst: f32 = @floatFromInt(player.stats[Player.haste_stat] + player.stat_boosts[Player.haste_stat]);
    const duration: i64 = @intFromFloat((8.0 + fhst * 0.08) * std.time.us_per_s);

    player.ability_state.premium_protection = true;

    const map_id_copy = try main.allocator.create(u32);
    map_id_copy.* = player.map_id;
    try player.world.callbacks.append(main.allocator, .{
        .trigger_on = main.current_time + duration,
        .callback = assetBubbleCallback,
        .data = map_id_copy,
    });
}

pub fn handleCompoundInterest(player: *Player) !void {
    _ = player;
    std.log.err("Compound Interest not implemented yet", .{});
}
