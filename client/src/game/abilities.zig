const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const utils = shared.utils;
const f32i = utils.f32i;
const i32f = utils.i32f;

const map = @import("../game/map.zig");
const input = @import("../input.zig");
const main = @import("../main.zig");
const Enemy = @import("Enemy.zig");
const Player = @import("Player.zig");
const Projectile = @import("Projectile.zig");

pub fn handleTerrainExpulsion(player: *Player, proj_data: *const game_data.ProjectileData) ![]u8 {
    const attack_angle = std.math.atan2(input.mouse_y - main.camera.height / 2.0, input.mouse_x - main.camera.width / 2.0);
    const x = player.x + @cos(attack_angle) * 0.25;
    const y = player.y + @sin(attack_angle) * 0.25;

    const projs_len = player.keystoneTalentLevel(0) + 1;
    const arc_gap = std.math.rad_per_deg;
    const total_angle = arc_gap * f32i(projs_len - 1);
    var angle = attack_angle - total_angle / 2.0;

    const first_proj_index = player.next_proj_index;
    for (0..projs_len) |_| {
        const proj_index = player.next_proj_index;
        player.next_proj_index +%= 1;

        const fstr = f32i(player.data.stats.strength + player.strength_bonus);
        Projectile.addToMap(.{
            .x = x,
            .y = y,
            .data = proj_data,
            .angle = attack_angle,
            .index = proj_index,
            .owner_map_id = player.map_id,
            .phys_dmg = i32f((3000.0 + fstr * 3.0 + f32i(player.abilityTalentLevel(0)) * 250.0) * player.damage_mult),
        });

        angle += arc_gap;
    }

    var buf: [@sizeOf(@TypeOf(first_proj_index)) + @sizeOf(@TypeOf(attack_angle))]u8 = undefined;
    var fba = std.io.fixedBufferStream(&buf);
    _ = fba.write(&std.mem.toBytes(first_proj_index)) catch main.oomPanic();
    _ = fba.write(&std.mem.toBytes(attack_angle)) catch main.oomPanic();
    return fba.getWritten();
}

pub fn handleHeartOfStone(player: *Player) ![]u8 {
    player.ability_state.heart_of_stone = true;
    return &.{};
}

pub fn handleTimeDilation(player: *Player) ![]u8 {
    player.ability_state.time_dilation = true;
    return &.{};
}

pub fn handleRewind() ![]u8 {
    return &.{};
}

pub fn handleNullPulse() ![]u8 {
    return &.{};
}

pub fn handleTimeLock(player: *Player) ![]u8 {
    player.ability_state.time_lock = true;
    return &.{};
}

pub fn handleBloodfont(player: *Player) ![]u8 {
    player.ability_state.bloodfont = true;
    return &.{};
}
