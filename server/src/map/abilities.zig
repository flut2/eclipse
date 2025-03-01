const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const utils = shared.utils;
const f32i = utils.f32i;
const i32f = utils.i32f;
const i64f = utils.i64f;
const u32f = utils.u32f;

const main = @import("../main.zig");
const maps = @import("../map/maps.zig");
const World = @import("../World.zig");
const Ally = @import("Ally.zig");
const Enemy = @import("Enemy.zig");
const Player = @import("Player.zig");
const Projectile = @import("Projectile.zig");

pub fn handleTerrainExpulsion(player: *Player, proj_data: *const game_data.ProjectileData, proj_index: u8, angle: f32) !void {
    const world = maps.worlds.getPtr(player.world_id) orelse return;

    const x = player.x + @cos(angle) * 0.25;
    const y = player.y + @sin(angle) * 0.25;
    const map_id = world.add(Projectile, .{
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
    if (world.find(Player, player_map_id.*, .ref)) |player| {
        player.hit_multiplier = 1.0;
        player.ability_state.heart_of_stone = false;
    }
}

pub fn handleHeartOfStone(player: *Player) !void {
    const world = maps.worlds.getPtr(player.world_id) orelse return;

    const fint = f32i(player.stats[Player.intelligence_stat] + player.stat_boosts[Player.intelligence_stat]);
    const duration = i64f((10.0 + fint * 0.1) * std.time.us_per_s);

    player.hit_multiplier = 0.5;
    player.ability_state.heart_of_stone = true;
    player.applyCondition(.slowed, duration);
    player.applyCondition(.stunned, duration);

    const map_id_copy = try main.allocator.create(u32);
    map_id_copy.* = player.map_id;
    world.callbacks.append(main.allocator, .{
        .trigger_on = main.current_time + duration,
        .callback = heartOfStoneCallback,
        .data = map_id_copy,
    }) catch main.oomPanic();
}

pub fn handleBoulderBuddies(player: *Player) !void {
    const world = maps.worlds.getPtr(player.world_id) orelse return;

    for (0..3) |_| {
        const fint = f32i(player.stats[Player.intelligence_stat] + player.stat_boosts[Player.intelligence_stat]);
        const duration = i64f((15.0 + fint * 0.1) * std.time.us_per_s);
        const angle = utils.rng.random().float(f32) * std.math.tau;
        const radius = utils.rng.random().float(f32) * 2.0;
        const x = player.x + radius * @cos(angle);
        const y = player.y + radius * @sin(angle);

        const map_id = try world.add(Ally, .{
            .x = x,
            .y = y,
            .data_id = 0,
            .owner_map_id = player.map_id,
            .disappear_time = main.current_time + duration,
        });

        const fhp = f32i(player.stats[Player.health_stat] + player.stat_boosts[Player.health_stat]);
        const fdef = f32i(player.stats[Player.defense_stat] + player.stat_boosts[Player.defense_stat]);
        const fres = f32i(player.stats[Player.resistance_stat] + player.stat_boosts[Player.resistance_stat]);
        if (world.find(Ally, map_id, .ref)) |ally| {
            ally.max_hp = i32f(3600.0 + fhp * 3.6);
            ally.hp = ally.max_hp;
            ally.defense = i32f(25.0 + fdef * 0.15);
            ally.resistance = i32f(5.0 + fres * 0.1);
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

pub fn handleEarthenPrison(player: *Player) !void {
    _ = player;
    std.log.err("Earthen Prison not implemented yet", .{});
}

fn timeDilationCallback(world: *World, plr_id_opaque: ?*anyopaque) void {
    const player_map_id: *u32 = @ptrCast(@alignCast(plr_id_opaque.?));
    defer main.allocator.destroy(player_map_id);
    if (world.find(Player, player_map_id.*, .ref)) |player| player.ability_state.time_dilation = false;
}

pub fn handleTimeDilation(player: *Player) !void {
    const world = maps.worlds.getPtr(player.world_id) orelse return;

    const fint = f32i(player.stats[Player.intelligence_stat] + player.stat_boosts[Player.intelligence_stat]);
    const duration = i64f((10.0 + fint * 0.12) * std.time.us_per_s);

    player.ability_state.time_dilation = true;

    const map_id_copy = try main.allocator.create(u32);
    map_id_copy.* = player.map_id;
    world.callbacks.append(main.allocator, .{
        .trigger_on = main.current_time + duration,
        .callback = timeDilationCallback,
        .data = map_id_copy,
    }) catch main.oomPanic();
}

pub fn handleRewind(player: *Player) !void {
    const fint = f32i(player.stats[Player.intelligence_stat] + player.stat_boosts[Player.intelligence_stat]);
    const fmana = f32i(player.stats[Player.mana_stat] + player.stat_boosts[Player.mana_stat]);
    const fwit = f32i(player.stats[Player.wit_stat] + player.stat_boosts[Player.wit_stat]);
    const duration = i64f((3.0 + fint * 0.01 + fmana * 0.006 + fwit * 0.01) * std.time.us_per_s);
    if (duration <= 0 or duration > 25 * std.time.us_per_s) {
        player.client.sendError(.message_with_disconnect, "Too many/little seconds elapsed for Rewind");
        return;
    }

    const tick = player.chunked_tick_id -%
        @as(u8, @intCast(@divFloor(@as(u64, @intCast(duration)), @as(u64, std.time.us_per_s) / main.settings.tps * 3)));
    if (player.hp_records[tick] == -1) return;

    const hp_delta = player.hp_records[tick] - player.hp;
    if (hp_delta > 0) {
        player.hp = player.hp_records[tick];
        var buf: [64]u8 = undefined;
        player.client.queuePacket(.{ .notification = .{
            .obj_type = .player,
            .map_id = player.map_id,
            .message = std.fmt.bufPrint(&buf, "+{}", .{hp_delta}) catch return,
            .color = 0x00FF00,
        } });

        player.client.queuePacket(.{ .show_effect = .{
            .eff_type = .potion,
            .obj_type = .player,
            .map_id = player.map_id,
            .x1 = 0,
            .y1 = 0,
            .x2 = 0,
            .y2 = 0,
            .color = 0x00FF00,
        } });
    }
    player.x = player.position_records[tick].x;
    player.y = player.position_records[tick].y;
    player.export_pos = true;    
}

pub fn handleNullPulse(player: *Player) !void {
    const world = maps.worlds.getPtr(player.world_id) orelse return;

    const fint = f32i(player.stats[Player.intelligence_stat] + player.stat_boosts[Player.intelligence_stat]);
    const fwit = f32i(player.stats[Player.wit_stat] + player.stat_boosts[Player.wit_stat]);
    const radius = 3.0 + fint * 0.12;
    const radius_sqr = radius * radius;
    const damage_mult = 5.0 + fwit * 0.06;

    var projs_to_remove: std.ArrayListUnmanaged(usize) = .empty;
    for (world.listForType(Projectile).items, 0..) |*p, i| {
        if (utils.distSqr(p.x, p.y, player.x, player.y) <= radius_sqr) {
            if (world.find(Enemy, p.owner_map_id, .ref)) |e| {
                const phys_dmg = i32f(f32i(p.phys_dmg) * damage_mult);
                const magic_dmg = i32f(f32i(p.magic_dmg) * damage_mult);
                const true_dmg = i32f(f32i(p.true_dmg) * damage_mult);
                e.damage(.player, player.map_id, phys_dmg, magic_dmg, true_dmg);
            }
            try p.deinit();
            projs_to_remove.append(main.allocator, i) catch main.oomPanic();
        }
    }
    var iter = std.mem.reverseIterator(projs_to_remove.items);
    while (iter.next()) |i| _ = world.lists.projectile.orderedRemove(i);
}

fn timeLockCallback(world: *World, plr_id_opaque: ?*anyopaque) void {
    const player_map_id: *u32 = @ptrCast(@alignCast(plr_id_opaque.?));
    defer main.allocator.destroy(player_map_id);
    if (world.find(Player, player_map_id.*, .ref)) |player| {
        const fint = f32i(player.stats[Player.intelligence_stat] + player.stat_boosts[Player.intelligence_stat]);
        const radius = 9.0 + fint * 0.06;
        world.aoe(Enemy, player.x, player.x, .player, player.map_id, radius, .{
            .magic_dmg = @intCast(@min(u32f(30000.0 + fint * 100.0), player.stored_damage)),
            .aoe_color = 0x0FE9EB,
        });
        player.ability_state.time_lock = false;
        player.hit_multiplier = 1.0;
        player.stored_damage = 0;
    }
}

pub fn handleTimeLock(player: *Player) !void {
    const world = maps.worlds.getPtr(player.world_id) orelse return;

    const fint = f32i(player.stats[Player.intelligence_stat] + player.stat_boosts[Player.intelligence_stat]);
    const duration = i64f((15.0 + fint * 0.12) * std.time.us_per_s);

    player.ability_state.time_lock = true;
    player.hit_multiplier = 0.5;
    player.applyCondition(.slowed, duration);

    const map_id_copy = try main.allocator.create(u32);
    map_id_copy.* = player.map_id;
    world.callbacks.append(main.allocator, .{
        .trigger_on = main.current_time + duration,
        .callback = timeLockCallback,
        .data = map_id_copy,
    }) catch main.oomPanic();
}

pub fn handleEtherealHarvest(player: *Player) !void {
    _ = player; // autofix
    std.log.err("Ethereal Harvest not implemented yet", .{});
}

pub fn handleSpaceShift(player: *Player) !void {
    _ = player; // autofix
    std.log.err("Space Shift not implemented yet", .{});
}

pub fn handleBloodfont(player: *Player) !void {
    _ = player; // autofix
    std.log.err("Bloodfont not implemented yet", .{});
}

pub fn handleRavenousHunger(player: *Player) !void {
    _ = player; // autofix
    std.log.err("Ravenous Hunger not implemented yet", .{});
}
