const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const utils = shared.utils;

const map = @import("../game/map.zig");
const input = @import("../input.zig");
const main = @import("../main.zig");
const Enemy = @import("Enemy.zig");
const Player = @import("Player.zig");
const Projectile = @import("Projectile.zig");

pub fn handleTerrainExpulsion(player: *Player, proj_data: *const game_data.ProjectileData) ![]u8 {
    // TODO: needs VFX
    const proj_index = player.next_proj_index;
    player.next_proj_index +%= 1;

    const attack_angle = std.math.atan2(input.mouse_y - main.camera.height / 2.0, input.mouse_x - main.camera.width / 2.0);
    const x = player.x + @cos(attack_angle) * 0.25;
    const y = player.y + @sin(attack_angle) * 0.25;

    const fstr: f32 = @floatFromInt(player.strength + player.strength_bonus);
    Projectile.addToMap(.{
        .x = x,
        .y = y,
        .data = proj_data,
        .angle = attack_angle,
        .index = proj_index,
        .owner_map_id = player.map_id,
        .phys_dmg = @intFromFloat(1300.0 + fstr * 2.0),
    });

    var buf: [5]u8 = undefined;
    var fba = std.io.fixedBufferStream(&buf);
    _ = fba.write(&std.mem.toBytes(proj_index)) catch main.oomPanic();
    _ = fba.write(&std.mem.toBytes(attack_angle)) catch main.oomPanic();
    return fba.getWritten();
}

pub fn handleHeartOfStone(player: *Player) ![]u8 {
    // TODO: needs VFX
    player.ability_state.heart_of_stone = true;
    return &.{};
}

pub fn handleTimeDilation(player: *Player) ![]u8 {
    // TODO: needs VFX
    player.ability_state.time_dilation = true;
    return &.{};
}

pub fn handleRewind() ![]u8 {
    // TODO: needs VFX
    return &.{};
}

pub fn handleNullPulse(player: *Player) ![]u8 {
    // TODO: needs VFX
    const fint: f32 = @floatFromInt(player.intelligence + player.intelligence_bonus);
    const fwit: f32 = @floatFromInt(player.wit + player.wit_bonus);
    const radius = 3.0 + fint * 0.12;
    const radius_sqr = radius * radius;
    const damage_mult = 5.0 + fwit * 0.06;

    map.object_lock.lock();
    defer map.object_lock.unlock();
    var proj_list = map.listForType(Projectile);
    var projs_to_remove: std.ArrayListUnmanaged(usize) = .empty;
    defer projs_to_remove.deinit(main.allocator);
    for (proj_list.items, 0..) |*p, i| {
        if (utils.distSqr(p.x, p.y, player.x, player.y) <= radius_sqr) {
            if (map.findObject(Enemy, p.owner_map_id, .ref)) |e| {
                const phys_dmg: i32 = @intFromFloat(@as(f32, @floatFromInt(game_data.physDamage(p.phys_dmg, e.defense, e.condition))) * damage_mult);
                const magic_dmg: i32 = @intFromFloat(@as(f32, @floatFromInt(game_data.magicDamage(p.magic_dmg, e.resistance, e.condition))) * damage_mult);
                const true_dmg: i32 = @intFromFloat(@as(f32, @floatFromInt(p.phys_dmg)) * damage_mult);
                if (phys_dmg > 0) map.takeDamage(e, phys_dmg, .physical, .{}, p.colors);
                if (magic_dmg > 0) map.takeDamage(e, magic_dmg, .magic, .{}, p.colors);
                if (true_dmg > 0) map.takeDamage(e, true_dmg, .true, .{}, p.colors);
            }
            p.deinit();
            projs_to_remove.append(main.allocator, i) catch main.oomPanic();
        }
    }
    var iter = std.mem.reverseIterator(projs_to_remove.items);
    while (iter.next()) |i| _ = proj_list.orderedRemove(i);
    return &.{};
}

pub fn handleTimeLock(player: *Player) ![]u8 {
    // TODO: needs VFX
    player.ability_state.time_lock = true;
    return &.{};
}

pub fn handleEquivalentExchange(player: *Player) ![]u8 {
    // TODO: needs VFX, impl
    player.ability_state.equivalent_exchange = true;
    return &.{};
}

pub fn handleAssetBubble(player: *Player) ![]u8 {
    // TODO: needs VFX, impl
    player.ability_state.asset_bubble = true;
    return &.{};
}

pub fn handlePremiumProtection(player: *Player) ![]u8 {
    // TODO: needs VFX, impl
    player.ability_state.premium_protection = true;
    return &.{};
}

pub fn handleCompoundInterest(player: *Player) ![]u8 {
    // TODO: needs VFX, impl
    player.ability_state.compound_interest = true;
    return &.{};
}
