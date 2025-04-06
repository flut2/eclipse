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

    const x = player.x + @cos(angle) * 0.25;
    const y = player.y + @sin(angle) * 0.25;
    const map_id = world.add(Projectile, .{
        .x = x,
        .y = y,
        .owner_obj_type = .player,
        .owner_map_id = player.map_id,
        .angle = angle,
        .start_time = main.current_time,
        .phys_dmg = i32f(3000.0 + f32i(player.totalStat(.strength)) * 3.0 * player.damage_multiplier),
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
    const world = maps.worlds.getPtr(player.world_id) orelse return;

    const duration = i64f((10.0 + f32i(player.totalStat(.intelligence)) * 0.1) * std.time.us_per_s);

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
        const duration = i64f((15.0 + f32i(player.totalStat(.intelligence)) * 0.1) * std.time.us_per_s);
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

        if (world.findRef(Ally, map_id)) |ally| {
            ally.max_hp = i32f(3600.0 + f32i(player.totalStat(.health)) * 3.6);
            ally.hp = ally.max_hp;
            ally.defense = i32f(25.0 + f32i(player.totalStat(.defense)) * 0.15);
            ally.resistance = i32f(5.0 + f32i(player.totalStat(.resistance)) * 0.1);
        } else return;

        player.show_effects.append(main.allocator, .{
            .obj_type = .ally,
            .map_id = map_id,
            .eff_type = .area_blast,
            .x1 = x,
            .y1 = y,
            .x2 = 1.5,
            .y2 = 0.0,
            .color = 0xA13A2F,
        }) catch main.oomPanic();
    }
}

pub fn handleEarthenPrison(player: *Player) !void {
    const world = maps.worlds.getPtr(player.world_id) orelse return;

    const fduration = 15.0 + f32i(player.totalStat(.haste)) * 0.2;
    const duration = i64f(fduration * std.time.us_per_s);
    const radius = 9.0 + f32i(player.totalStat(.intelligence)) * 0.1;
    const redirect_perc = @max(0.0, 0.5 - f32i(player.totalStat(.defense)) * 0.01 * 0.01 - f32i(player.totalStat(.resistance)) * 0.01 * 0.01);
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

    for (world.listForType(Player).items) |*p| {
        if (utils.distSqr(player.x, player.y, p.x, p.y) > 20 * 20) continue;
        p.show_effects.append(main.allocator, .{
            .eff_type = .ring,
            .obj_type = .ally,
            .map_id = obelisk_map_id,
            .x1 = radius,
            .y1 = 1.0,
            .x2 = fduration,
            .y2 = 0.0,
            .color = 0x00FF00,
        }) catch main.oomPanic();
    }
}

fn timeDilationCallback(world: *World, plr_id_opaque: ?*anyopaque) void {
    const player_map_id: *u32 = @ptrCast(@alignCast(plr_id_opaque.?));
    defer main.allocator.destroy(player_map_id);
    if (world.findRef(Player, player_map_id.*)) |player| player.ability_state.time_dilation = false;
}

pub fn handleTimeDilation(player: *Player) !void {
    const world = maps.worlds.getPtr(player.world_id) orelse return;

    const radius = 3.0 + f32i(player.totalStat(.wit)) * 0.06;
    const fduration = 5.0 + f32i(player.totalStat(.intelligence)) * 0.05;
    const duration = i64f(fduration * std.time.us_per_s);

    player.ability_state.time_dilation = true;
    for (world.listForType(Player).items) |*p| {
        if (utils.distSqr(player.x, player.y, p.x, p.y) > 20 * 20) continue;
        p.show_effects.append(main.allocator, .{
            .eff_type = .ring,
            .obj_type = .player,
            .map_id = player.map_id,
            .x1 = radius,
            .y1 = 0.5,
            .x2 = fduration,
            .y2 = 0.0,
            .color = 0x0000FF,
        }) catch main.oomPanic();
    }

    const map_id_copy = try main.allocator.create(u32);
    map_id_copy.* = player.map_id;
    world.callbacks.append(main.allocator, .{
        .trigger_on = main.current_time + duration,
        .callback = timeDilationCallback,
        .data = map_id_copy,
    }) catch main.oomPanic();
}

pub fn handleRewind(player: *Player) !void {
    const duration = i64f((3.0 + f32i(player.totalStat(.intelligence)) * 0.01 +
        f32i(player.totalStat(.mana)) * 0.006 +
        f32i(player.totalStat(.wit)) * 0.01) * std.time.us_per_s);
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

        player.show_effects.append(main.allocator, .{
            .eff_type = .potion,
            .obj_type = .player,
            .map_id = player.map_id,
            .x1 = 0,
            .y1 = 0,
            .x2 = 0,
            .y2 = 0,
            .color = 0x00FF00,
        }) catch main.oomPanic();
    }
    player.x = player.position_records[tick].x;
    player.y = player.position_records[tick].y;
    player.export_pos = true;
}

pub fn handleNullPulse(player: *Player) !void {
    const world = maps.worlds.getPtr(player.world_id) orelse return;

    const radius = 5.0 + f32i(player.totalStat(.intelligence)) * 0.12;
    const radius_sqr = radius * radius;
    const damage_mult = 0.25 + f32i(player.totalStat(.wit)) * 0.01 * player.damage_multiplier;

    var proj_lists: std.AutoHashMapUnmanaged(u32, std.ArrayListUnmanaged(u8)) = .empty;
    defer proj_lists.deinit(main.allocator);
    const proj_list = world.listForType(Projectile);
    const projs_len = proj_list.items.len;
    if (projs_len > 0) {
        var iter = std.mem.reverseIterator(proj_list.items);
        var i = projs_len - 1;
        while (iter.nextPtr()) |p| : (i -%= 1)
            if (utils.distSqr(p.x, p.y, player.x, player.y) <= radius_sqr) {
                if (world.findRef(Enemy, p.owner_map_id)) |e| {
                    const phys_dmg = i32f(f32i(p.phys_dmg) * damage_mult);
                    const magic_dmg = i32f(f32i(p.magic_dmg) * damage_mult);
                    const true_dmg = i32f(f32i(p.true_dmg) * damage_mult);
                    e.damage(.player, player.map_id, phys_dmg, magic_dmg, true_dmg, null);
                }
                if (proj_lists.getPtr(p.owner_map_id)) |list| {
                    list.append(main.allocator, p.index) catch main.oomPanic();
                } else proj_lists.put(main.allocator, p.owner_map_id, .empty) catch main.oomPanic();
                try p.deinit();
                _ = proj_list.swapRemove(i);
            };
    }

    var enemy_proj_lists: std.ArrayListUnmanaged(network_data.EnemyProjList) = .empty;
    defer enemy_proj_lists.deinit(main.allocator);
    var proj_list_iter = proj_lists.iterator();
    while (proj_list_iter.next()) |entry| enemy_proj_lists.append(main.allocator, .{
        .enemy_map_id = entry.key_ptr.*,
        .proj_ids = entry.value_ptr.items,
    }) catch main.oomPanic();

    for (world.listForType(Player).items) |*p| {
        if (p.map_id == player.map_id or utils.distSqr(p.x, p.y, player.x, player.y) > 16 * 16) continue;
        p.client.sendPacket(.{ .drop_projs = .{ .lists = enemy_proj_lists.items } });
    }
}

fn timeLockCallback(world: *World, plr_id_opaque: ?*anyopaque) void {
    const player_map_id: *u32 = @ptrCast(@alignCast(plr_id_opaque.?));
    defer main.allocator.destroy(player_map_id);
    if (world.findRef(Player, player_map_id.*)) |player| {
        const fint = f32i(player.totalStat(.intelligence));
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

    const duration = i64f((10.0 + f32i(player.totalStat(.intelligence)) * 0.12) * std.time.us_per_s);

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
    if (world.findRef(Player, player_map_id.*)) |player| player.damage_multiplier = 1.0;
}

pub fn handleEtherealHarvest(player: *Player) !void {
    const world = maps.worlds.getPtr(player.world_id) orelse return;
    const soul_id = (game_data.entity.from_name.get("Enemy Soul") orelse return).id;

    const duration = i64f((6.0 + f32i(player.totalStat(.haste)) * 0.06) * std.time.us_per_s);
    const radius = 6.0 + f32i(player.totalStat(.intelligence)) * 0.09 + f32i(player.abilityTalentLevel(0)) * 0.5;
    const radius_sqr = radius * radius;

    var num_souls: u32 = 0;
    var entities_to_kill: std.ArrayListUnmanaged(usize) = .empty;
    defer entities_to_kill.deinit(main.allocator);
    var show_effects: std.ArrayListUnmanaged(network_data.ShowEffectItem) = .empty;
    defer show_effects.deinit(main.allocator);
    for (world.listForType(Entity).items, 0..) |*e, i| {
        if (utils.distSqr(e.x, e.y, player.x, player.y) > radius_sqr or e.data_id != soul_id) continue;
        num_souls += 1;
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

    if (num_souls > 0) {
        const pre_hp = player.hp;
        player.restoreHealth(player.keystoneTalentLevel(0) * 30, 0);
        const hp_delta = player.hp - pre_hp;
        if (hp_delta > 0) {
            var buf: [64]u8 = undefined;
            for (world.listForType(Player).items) |*other_player| {
                if (utils.distSqr(other_player.x, other_player.y, player.x, player.y) > 16 * 16) continue;
                other_player.client.sendPacket(.{ .notification = .{
                    .obj_type = .player,
                    .map_id = player.map_id,
                    .message = std.fmt.bufPrint(&buf, "+{}", .{hp_delta}) catch return,
                    .color = 0x00FF00,
                } });

                other_player.show_effects.append(main.allocator, .{
                    .eff_type = .potion,
                    .color = 0x00FF00,
                    .map_id = player.map_id,
                    .obj_type = .player,
                    .x1 = 0,
                    .x2 = 0,
                    .y1 = 0,
                    .y2 = 0,
                }) catch main.oomPanic();
            }
        }

        player.damage_multiplier = 1.0 + f32i(num_souls) * 0.25;
        const map_id_copy = try main.allocator.create(u32);
        map_id_copy.* = player.map_id;
        world.callbacks.append(main.allocator, .{
            .trigger_on = main.current_time + duration,
            .callback = etherealHarvestCallback,
            .data = map_id_copy,
        }) catch main.oomPanic();
    }

    for (world.listForType(Player).items) |*other_player| {
        if (utils.distSqr(other_player.x, other_player.y, player.x, player.y) > 16 * 16) continue;
        other_player.show_effects.appendSlice(main.allocator, show_effects.items) catch main.oomPanic();
    }
}

pub fn handleSpaceShift(player: *Player) !void {
    const world = maps.worlds.getPtr(player.world_id) orelse return;
    const rift_data = game_data.entity.from_name.get("Demon Rift") orelse return;

    const fduration = 6.0 + f32i(player.totalStat(.stamina)) * 0.06;
    const duration = i64f(fduration * std.time.us_per_s);

    var rand = utils.rng.random();
    const angle = rand.float(f32) * std.math.tau;
    const radius = rand.float(f32) * 2.0;
    const rift_id = try world.add(Entity, .{
        .x = player.x + radius * @cos(angle),
        .y = player.y + radius * @sin(angle),
        .data_id = rift_data.id,
        .disappear_time = main.current_time + duration,
        .owner_map_id = player.map_id,
    });

    const heal_radius = 7.0 + f32i(player.totalStat(.intelligence)) * 0.07;
    for (world.listForType(Player).items) |*p| {
        if (utils.distSqr(player.x, player.y, p.x, p.y) > 20 * 20) continue;
        p.show_effects.append(main.allocator, .{
            .eff_type = .ring,
            .obj_type = .entity,
            .map_id = rift_id,
            .x1 = heal_radius,
            .y1 = 1.0,
            .x2 = fduration,
            .y2 = 0.0,
            .color = 0x00FF00,
        }) catch main.oomPanic();
    }
}

fn bloodfontCallback(world: *World, plr_id_opaque: ?*anyopaque) void {
    const player_map_id: *u32 = @ptrCast(@alignCast(plr_id_opaque.?));
    defer main.allocator.destroy(player_map_id);
    if (world.findRef(Player, player_map_id.*)) |player| {
        const old_hp = player.hp;
        player.hp = @max(1, player.hp - i32f(f32i(player.stored_damage) * (1.0 - 0.1 * f32i(player.keystoneTalentLevel(2)))));
        const hp_delta = player.hp - old_hp;
        if (hp_delta < 0) {
            var buf: [64]u8 = undefined;
            player.client.sendPacket(.{ .notification = .{
                .obj_type = .player,
                .map_id = player.map_id,
                .message = std.fmt.bufPrint(&buf, "{}", .{hp_delta}) catch return,
                .color = 0xFF0000,
            } });

            player.show_effects.append(main.allocator, .{
                .eff_type = .potion,
                .obj_type = .player,
                .map_id = player.map_id,
                .x1 = 0,
                .y1 = 0,
                .x2 = 0,
                .y2 = 0,
                .color = 0xFF0000,
            }) catch main.oomPanic();
        }
        player.ability_state.bloodfont = false;
        player.hit_multiplier = 1.0;
        player.stored_damage = 0;
    }
}

pub fn handleBloodfont(player: *Player) !void {
    const world = maps.worlds.getPtr(player.world_id) orelse return;

    const duration = i64f((3.0 + f32i(player.totalStat(.health)) * 0.0033 + 0.25 * f32i(player.abilityTalentLevel(2))) * std.time.us_per_s);

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

fn ravenousHungerCallback(world: *World, plr_id_opaque: ?*anyopaque) void {
    const player_map_id: *u32 = @ptrCast(@alignCast(plr_id_opaque.?));
    defer main.allocator.destroy(player_map_id);
    if (world.findRef(Player, player_map_id.*)) |player| player.hit_multiplier = 1.0;
}

pub fn handleRavenousHunger(player: *Player) !void {
    const world = maps.worlds.getPtr(player.world_id) orelse return;

    const radius = 2.0 + f32i(player.totalStat(.haste)) * 0.05;
    const radius_sqr = radius * radius;
    const max_overheal = i32f(1000.0 + 0.1 * f32i(player.totalStat(.health)));
    const kill_perc = 0.1 + 0.0025 * f32i(player.abilityTalentLevel(3));
    const prev_hp = player.hp;
    const dmg_boost_per_kill = f32i(player.keystoneTalentLevel(3)) * 1.5;

    var dmg_boost: f32 = 1.0;
    var total_hp_gain: i32 = 0;
    var enemies_to_kill: std.ArrayListUnmanaged(usize) = .empty;
    defer enemies_to_kill.deinit(main.allocator);
    var show_effects: std.ArrayListUnmanaged(network_data.ShowEffectItem) = .empty;
    defer show_effects.deinit(main.allocator);
    for (world.listForType(Enemy).items, 0..) |*e, i| {
        if (utils.distSqr(e.x, e.y, player.x, player.y) > radius_sqr or f32i(e.hp) / f32i(e.max_hp) > kill_perc) continue;
        dmg_boost += dmg_boost_per_kill;
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

    player.restoreHealth(@intCast(@divFloor(total_hp_gain, 10)), max_overheal);
    const hp_delta = player.hp - prev_hp;

    var buf: [64]u8 = undefined;
    const hp_gain_text = if (hp_delta <= 0) "" else std.fmt.bufPrint(&buf, "+{}", .{hp_delta}) catch return;
    for (world.listForType(Player).items) |*other_player| {
        if (utils.distSqr(other_player.x, other_player.y, player.x, player.y) > 16 * 16) continue;
        other_player.show_effects.appendSlice(main.allocator, show_effects.items) catch main.oomPanic();

        if (hp_delta > 0) {
            other_player.client.sendPacket(.{ .notification = .{
                .obj_type = .player,
                .map_id = player.map_id,
                .message = hp_gain_text,
                .color = 0x00FF00,
            } });

            other_player.show_effects.append(main.allocator, .{
                .eff_type = .potion,
                .obj_type = .player,
                .map_id = player.map_id,
                .x1 = 0,
                .y1 = 0,
                .x2 = 0,
                .y2 = 0,
                .color = 0x00FF00,
            }) catch main.oomPanic();
        }
    }

    if (dmg_boost > 1.0) {
        const map_id_copy = try main.allocator.create(u32);
        map_id_copy.* = player.map_id;
        world.callbacks.append(main.allocator, .{
            .trigger_on = main.current_time + 4 * std.time.us_per_s,
            .callback = ravenousHungerCallback,
            .data = map_id_copy,
        }) catch main.oomPanic();
    }
}
