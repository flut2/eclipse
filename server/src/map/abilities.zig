const std = @import("std");

const shared = @import("shared");
const network_data = shared.network_data;
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
const Entity = @import("Entity.zig");
const Player = @import("Player.zig");
const Projectile = @import("Projectile.zig");

pub fn handleTerrainExpulsion(player: *Player, proj_data: *const game_data.ProjectileData, proj_index: u8, angle: f32) !void {
    const world = maps.worlds.getPtr(player.world_id) orelse return;

    const fstr = f32i(player.stats[Player.strength_stat] + player.stat_boosts[Player.strength_stat]);
    const x = player.x + @cos(angle) * 0.25;
    const y = player.y + @sin(angle) * 0.25;
    const map_id = world.add(Projectile, .{
        .x = x,
        .y = y,
        .owner_obj_type = .player,
        .owner_map_id = player.map_id,
        .angle = angle,
        .start_time = main.current_time,
        .phys_dmg = i32f(3000.0 + fstr * 3.0 * player.damage_multiplier),
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
        var rand = utils.rng.random();
        const angle = rand.float(f32) * std.math.tau;
        const radius = rand.float(f32) * 2.0;
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

        player.client.sendPacket(.{ .show_effect = .{
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
    const world = maps.worlds.getPtr(player.world_id) orelse return;

    const fhst = f32i(player.stats[Player.haste_stat] + player.stat_boosts[Player.haste_stat]);
    const fint = f32i(player.stats[Player.intelligence_stat] + player.stat_boosts[Player.intelligence_stat]);
    const fdef = f32i(player.stats[Player.defense_stat] + player.stat_boosts[Player.defense_stat]);
    const fres = f32i(player.stats[Player.resistance_stat] + player.stat_boosts[Player.resistance_stat]);
    const duration = i64f((15.0 + fhst * 0.2) * std.time.us_per_s);
    const radius = 9.0 + fint * 0.1;
    const redirect_perc = @max(0.0, 0.5 - fdef * 0.01 * 0.01 - fres * 0.01 * 0.01);
    const radius_sqr = radius * radius;

    const obelisk_map_id = try world.add(Ally, .{
        .x = player.x,
        .y = player.y,
        .data_id = 2,
        .owner_map_id = player.map_id,
        .disappear_time = main.current_time + duration,
        .hit_multiplier = redirect_perc,
    });

    for (world.listForType(Enemy).items) |*e|
        if (utils.distSqr(e.x, e.y, player.x, player.y) <= radius_sqr) {
            e.obelisk_map_id = obelisk_map_id;
            e.applyCondition(.encased_in_stone, duration);
        };
}

fn timeDilationCallback(world: *World, plr_id_opaque: ?*anyopaque) void {
    const player_map_id: *u32 = @ptrCast(@alignCast(plr_id_opaque.?));
    defer main.allocator.destroy(player_map_id);
    if (world.find(Player, player_map_id.*, .ref)) |player| player.ability_state.time_dilation = false;
}

pub fn handleTimeDilation(player: *Player) !void {
    const world = maps.worlds.getPtr(player.world_id) orelse return;

    const fint = f32i(player.stats[Player.intelligence_stat] + player.stat_boosts[Player.intelligence_stat]);
    const duration = i64f((5.0 + fint * 0.05) * std.time.us_per_s);

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
        player.client.sendPacket(.{ .notification = .{
            .obj_type = .player,
            .map_id = player.map_id,
            .message = std.fmt.bufPrint(&buf, "+{}", .{hp_delta}) catch return,
            .color = 0x00FF00,
        } });

        player.client.sendPacket(.{ .show_effect = .{
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
    const radius = 5.0 + fint * 0.12;
    const radius_sqr = radius * radius;
    const damage_mult = 0.25 + fwit * 0.01 * player.damage_multiplier;

    var projs_to_remove: std.ArrayListUnmanaged(usize) = .empty;
    defer projs_to_remove.deinit(main.allocator);
    for (world.listForType(Projectile).items, 0..) |*p, i| {
        if (utils.distSqr(p.x, p.y, player.x, player.y) <= radius_sqr) {
            if (world.find(Enemy, p.owner_map_id, .ref)) |e| {
                const phys_dmg = i32f(f32i(p.phys_dmg) * damage_mult);
                const magic_dmg = i32f(f32i(p.magic_dmg) * damage_mult);
                const true_dmg = i32f(f32i(p.true_dmg) * damage_mult);
                e.damage(.player, player.map_id, phys_dmg, magic_dmg, true_dmg, null);
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
        const radius = 12.0 + fint * 0.06;
        world.aoe(Enemy, player.x, player.x, .player, player.map_id, radius, .{
            .magic_dmg = @intCast(@min(u32f(30000.0 + fint * 100.0 * player.damage_multiplier), player.stored_damage)),
            .aoe_color = 0x0FE9EB,
        });
        player.ability_state.time_lock = false;
        player.hit_multiplier = 1.0;
        player.damage_multiplier = 1.0;
        player.stored_damage = 0;
    }
}

pub fn handleTimeLock(player: *Player) !void {
    const world = maps.worlds.getPtr(player.world_id) orelse return;

    const fint = f32i(player.stats[Player.intelligence_stat] + player.stat_boosts[Player.intelligence_stat]);
    const duration = i64f((10.0 + fint * 0.12) * std.time.us_per_s);

    player.ability_state.time_lock = true;
    player.hit_multiplier = 0.5;
    player.damage_multiplier = 0.75;
    player.applyCondition(.slowed, duration);

    const map_id_copy = try main.allocator.create(u32);
    map_id_copy.* = player.map_id;
    world.callbacks.append(main.allocator, .{
        .trigger_on = main.current_time + duration,
        .callback = timeLockCallback,
        .data = map_id_copy,
    }) catch main.oomPanic();
}

fn etherealHarvestCallback(world: *World, plr_id_opaque: ?*anyopaque) void {
    const player_map_id: *u32 = @ptrCast(@alignCast(plr_id_opaque.?));
    defer main.allocator.destroy(player_map_id);
    if (world.find(Player, player_map_id.*, .ref)) |player| player.damage_multiplier = 1.0;
}

pub fn handleEtherealHarvest(player: *Player) !void {
    const world = maps.worlds.getPtr(player.world_id) orelse return;
    const soul_id = (game_data.entity.from_name.get("Enemy Soul") orelse return).id;

    const fint = f32i(player.stats[Player.intelligence_stat] + player.stat_boosts[Player.intelligence_stat]);
    const fhst = f32i(player.stats[Player.haste_stat] + player.stat_boosts[Player.haste_stat]);
    const duration = i64f((6.0 + fhst * 0.06) * std.time.us_per_s);
    const radius = 6.0 + fint * 0.09;
    const radius_sqr = radius * radius;

    var total_damage_boost: f32 = 1.0;
    var entities_to_kill: std.ArrayListUnmanaged(usize) = .empty;
    defer entities_to_kill.deinit(main.allocator);
    const ShowEffectData = @typeInfo(network_data.S2CPacket).@"union".fields[@intFromEnum(network_data.S2CPacket.show_effect)].type;
    var show_effects: std.ArrayListUnmanaged(ShowEffectData) = .empty;
    defer show_effects.deinit(main.allocator);
    for (world.listForType(Entity).items, 0..) |*e, i| {
        if (utils.distSqr(e.x, e.y, player.x, player.y) > radius_sqr or e.data_id != soul_id) continue;
        total_damage_boost += 0.25;
        show_effects.append(main.allocator, .{
            .obj_type = .enemy,
            .map_id = e.map_id,
            .eff_type = .area_blast,
            .x1 = e.x,
            .y1 = e.y,
            .x2 = 1.5,
            .y2 = 0.0,
            .color = 0xFF0000,
        }) catch main.oomPanic();
        entities_to_kill.append(main.allocator, i) catch main.oomPanic();
    }

    var iter = std.mem.reverseIterator(entities_to_kill.items);
    while (iter.next()) |i| _ = try world.lists.entity.items[i].delete();

    for (world.listForType(Player).items) |*other_player| {
        for (show_effects.items) |show_eff| other_player.client.sendPacket(.{ .show_effect = show_eff });
    }

    if (total_damage_boost > 1.0) {
        player.damage_multiplier = total_damage_boost;
        const map_id_copy = try main.allocator.create(u32);
        map_id_copy.* = player.map_id;
        world.callbacks.append(main.allocator, .{
            .trigger_on = main.current_time + duration,
            .callback = etherealHarvestCallback,
            .data = map_id_copy,
        }) catch main.oomPanic();
    }
}

pub fn handleSpaceShift(player: *Player) !void {
    const world = maps.worlds.getPtr(player.world_id) orelse return;
    const rift_data = game_data.entity.from_name.get("Demon Rift") orelse return;

    const fsta = f32i(player.stats[Player.stamina_stat] + player.stat_boosts[Player.stamina_stat]);
    const duration = i64f((6.0 + fsta * 0.06) * std.time.us_per_s);

    var rand = utils.rng.random();
    const angle = rand.float(f32) * std.math.tau;
    const radius = rand.float(f32) * 2.0;
    _ = try world.add(Entity, .{
        .x = player.x + radius * @cos(angle),
        .y = player.y + radius * @sin(angle),
        .data_id = rift_data.id,
        .disappear_time = main.current_time + duration,
        .owner_map_id = player.map_id,
    });
}

fn bloodfontCallback(world: *World, plr_id_opaque: ?*anyopaque) void {
    const player_map_id: *u32 = @ptrCast(@alignCast(plr_id_opaque.?));
    defer main.allocator.destroy(player_map_id);
    if (world.find(Player, player_map_id.*, .ref)) |player| {
        const old_hp = player.hp;
        player.hp = @max(1, player.hp - @as(i32, @intCast(player.stored_damage)));
        const hp_delta = player.hp - old_hp;
        if (hp_delta < 0) {
            var buf: [64]u8 = undefined;
            player.client.sendPacket(.{ .notification = .{
                .obj_type = .player,
                .map_id = player.map_id,
                .message = std.fmt.bufPrint(&buf, "{}", .{hp_delta}) catch return,
                .color = 0xFF0000,
            } });

            player.client.sendPacket(.{ .show_effect = .{
                .eff_type = .potion,
                .obj_type = .player,
                .map_id = player.map_id,
                .x1 = 0,
                .y1 = 0,
                .x2 = 0,
                .y2 = 0,
                .color = 0xFF0000,
            } });
        }
        player.ability_state.bloodfont = false;
        player.hit_multiplier = 1.0;
        player.stored_damage = 0;
    }
}

pub fn handleBloodfont(player: *Player) !void {
    const world = maps.worlds.getPtr(player.world_id) orelse return;

    const fhp = f32i(player.stats[Player.health_stat] + player.stat_boosts[Player.health_stat]);
    const duration = i64f((3.0 + fhp * 0.0033) * std.time.us_per_s);

    player.ability_state.bloodfont = true;
    player.hit_multiplier = 0.0;

    const map_id_copy = try main.allocator.create(u32);
    map_id_copy.* = player.map_id;
    world.callbacks.append(main.allocator, .{
        .trigger_on = main.current_time + duration,
        .callback = bloodfontCallback,
        .data = map_id_copy,
    }) catch main.oomPanic();
}

pub fn handleRavenousHunger(player: *Player) !void {
    const world = maps.worlds.getPtr(player.world_id) orelse return;

    const fhst = f32i(player.stats[Player.haste_stat] + player.stat_boosts[Player.haste_stat]);
    const fhp = f32i(player.stats[Player.health_stat] + player.stat_boosts[Player.health_stat]);
    const radius = 2.0 + fhst * 0.05;
    const radius_sqr = radius * radius;
    const max_overheal = 1000 + i32f(0.1 * fhp);
    const kill_perc = 0.1;
    const prev_hp = player.hp;

    var total_hp_gain: i32 = 0;
    var enemies_to_kill: std.ArrayListUnmanaged(usize) = .empty;
    defer enemies_to_kill.deinit(main.allocator);
    const ShowEffectData = @typeInfo(network_data.S2CPacket).@"union".fields[@intFromEnum(network_data.S2CPacket.show_effect)].type;
    var show_effects: std.ArrayListUnmanaged(ShowEffectData) = .empty;
    defer show_effects.deinit(main.allocator);
    for (world.listForType(Enemy).items, 0..) |*e, i| {
        if (utils.distSqr(e.x, e.y, player.x, player.y) > radius_sqr or f32i(e.hp) / f32i(e.max_hp) > kill_perc) continue;
        total_hp_gain += e.hp;
        show_effects.append(main.allocator, .{
            .obj_type = .enemy,
            .map_id = e.map_id,
            .eff_type = .area_blast,
            .x1 = e.x,
            .y1 = e.y,
            .x2 = 1.5,
            .y2 = 0.0,
            .color = 0xFF0000,
        }) catch main.oomPanic();
        enemies_to_kill.append(main.allocator, i) catch main.oomPanic();
    }

    var iter = std.mem.reverseIterator(enemies_to_kill.items);
    while (iter.next()) |i| {
        var enemy = &world.lists.enemy.items[i];
        const res = enemy.damages_dealt.getOrPut(main.allocator, player.map_id) catch continue;
        if (res.found_existing) res.value_ptr.* += enemy.hp else res.value_ptr.* = enemy.hp;
        _ = try enemy.delete();
    }

    player.hp = @min(
        player.stats[Player.health_stat] + player.stat_boosts[Player.health_stat] + max_overheal,
        @divFloor(player.hp + total_hp_gain, 10),
    );
    const hp_delta = player.hp - prev_hp;

    var buf: [64]u8 = undefined;
    const hp_gain_text = if (hp_delta > 0) "" else std.fmt.bufPrint(&buf, "+{}", .{hp_delta}) catch return;
    for (world.listForType(Player).items) |*other_player| {
        for (show_effects.items) |show_eff| other_player.client.sendPacket(.{ .show_effect = show_eff });

        if (hp_delta > 0) {
            other_player.client.sendPacket(.{ .notification = .{
                .obj_type = .player,
                .map_id = player.map_id,
                .message = hp_gain_text,
                .color = 0x00FF00,
            } });

            other_player.client.sendPacket(.{ .show_effect = .{
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
    }
}
