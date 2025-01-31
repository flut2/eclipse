const std = @import("std");
const float_us: comptime_float = std.time.us_per_s;

const shared = @import("shared");
const utils = shared.utils;
const game_data = shared.game_data;
const network_data = shared.network_data;
const f32i = utils.f32i;
const u8f = utils.u8f;
const i64f = utils.i64f;
const i32f = utils.i32f;
const usizef = utils.usizef;

const assets = @import("../assets.zig");
const Camera = @import("../Camera.zig");
const px_per_tile = Camera.px_per_tile;
const input = @import("../input.zig");
const main = @import("../main.zig");
const CameraData = @import("../render/CameraData.zig");
const element = @import("../ui/elements/element.zig");
const StatusText = @import("../ui/game/StatusText.zig");
const ui_systems = @import("../ui/systems.zig");
const abilities = @import("abilities.zig");
const base = @import("object_base.zig");
const Entity = @import("Entity.zig");
const map = @import("map.zig");
const particles = @import("particles.zig");
const Projectile = @import("Projectile.zig");
const Square = @import("Square.zig");

const Player = @This();

pub const move_threshold = 0.4;
pub const min_move_speed = 4.0 / float_us;
pub const max_move_speed = 9.6 / float_us;
pub const attack_frequency = 5.0 / float_us;
pub const max_sink_level = 18.0;

map_id: u32 = std.math.maxInt(u32),
data_id: u16 = std.math.maxInt(u16),
x: f32 = 0.0,
y: f32 = 0.0,
z: f32 = 0.0,
alpha: f32 = 1.0,
name: ?[]const u8 = null,
name_text_data: ?element.TextData = null,
name_text_data_inited: bool = false,
cards: []const u16 = &.{},
resources: []const network_data.DataIdWithCount(u32) = &.{},
talents: []const network_data.DataIdWithCount(u16) = &.{},
in_combat: bool = false,
aether: u8 = 1,
spirits_communed: u32 = 0,
muted_until: i64 = 0,
gold: u32 = 0,
gems: u32 = 0,
damage_mult: f32 = 1.0,
hit_mult: f32 = 1.0,
size_mult: f32 = 1.0,
max_hp: i32 = 0,
max_mp: i32 = 0,
hp: i32 = 0,
mp: i32 = 0,
strength: i16 = 0,
defense: i16 = 0,
speed: i16 = 0,
stamina: i16 = 0,
wit: i16 = 0,
resistance: i16 = 0,
intelligence: i16 = 0,
haste: i16 = 0,
max_hp_bonus: i32 = 0,
max_mp_bonus: i32 = 0,
strength_bonus: i16 = 0,
defense_bonus: i16 = 0,
speed_bonus: i16 = 0,
stamina_bonus: i16 = 0,
wit_bonus: i16 = 0,
resistance_bonus: i16 = 0,
intelligence_bonus: i16 = 0,
haste_bonus: i16 = 0,
hit_multiplier: f32 = 1.0,
damage_multiplier: f32 = 1.0,
condition: utils.Condition = .{},
inventory: [22]u16 = @splat(std.math.maxInt(u16)),
inv_data: [22]network_data.ItemData = @splat(@bitCast(@as(u32, 0))),
attack_start: i64 = 0,
attack_period: i64 = 0,
attack_angle: f32 = 0,
next_proj_index: u8 = 0,
move_angle: f32 = std.math.nan(f32),
move_step: f32 = 0.0,
target_x: f32 = 0.0,
target_y: f32 = 0.0,
walk_speed_multiplier: f32 = 1.0,
data: *const game_data.ClassData = undefined,
last_ground_damage_time: i64 = -1,
anim_data: assets.AnimPlayerData = undefined,
atlas_data: assets.AtlasData = .default,
move_multiplier: f32 = 1.0,
sink_level: f32 = 0,
colors: []u32 = &.{},
x_dir: f32 = 0.0,
y_dir: f32 = 0.0,
facing: f32 = std.math.nan(f32),
status_texts: std.ArrayListUnmanaged(StatusText) = .empty,
direction: assets.Direction = .right,
last_ability_use: [4]i64 = @splat(std.math.minInt(i31)),
ability_state: network_data.AbilityState = .{},

pub fn addToMap(player_data: Player) void {
    var self = player_data;
    self.data = game_data.class.from_id.getPtr(self.data_id) orelse {
        std.log.err("Player with data id {} has no class data, can't add", .{self.data_id});
        return;
    };

    if (assets.anim_players.get(self.data.texture.sheet)) |anim_data| {
        self.anim_data = anim_data[self.data.texture.index];
    } else {
        std.log.err("Could not find anim sheet {s} for player with data id {}. Using error texture", .{ self.data.texture.sheet, self.data_id });
        self.anim_data = assets.error_data_player;
    }

    self.colors = assets.atlas_to_color_data.get(@bitCast(self.anim_data.walk_anims[0])) orelse blk: {
        std.log.err("Could not parse color data for player with data id {}. Setting it to empty", .{self.data_id});
        break :blk &.{};
    };

    if (self.name_text_data == null) {
        self.name_text_data = .{
            .text = undefined,
            .text_type = .bold,
            .size = 12,
            .color = 0xFCDF00,
            .max_width = 200,
        };
        self.name_text_data.?.setText(if (self.name) |player_name| player_name else self.data.name);
    }

    map.addListForType(Player).append(main.allocator, self) catch @panic("Adding player failed");
}

pub fn deinit(self: *Player) void {
    base.deinit(self);
    for (self.status_texts.items) |*text| text.deinit();
    self.status_texts.deinit(main.allocator);
    main.allocator.free(self.cards);
    main.allocator.free(self.resources);
    main.allocator.free(self.talents);
}

pub fn onMove(self: *Player) void {
    if (map.getSquare(self.x, self.y, true, .con)) |square| self.move_multiplier = square.data.speed_mult;
}

pub fn strengthMult(self: Player) f32 {
    if (self.condition.weak) return 0.5;

    var mult = 0.5 + f32i(self.strength + self.strength_bonus) / 75.0;
    if (self.condition.damaging) mult *= 1.5;
    return mult;
}

pub fn witMult(self: Player) f32 {
    return 0.5 + f32i(self.wit + self.wit_bonus) / 75.0;
}

pub fn moveSpeedMultiplier(self: Player) f32 {
    if (self.condition.slowed) return min_move_speed * self.move_multiplier * self.walk_speed_multiplier;

    var move_speed = min_move_speed + f32i(self.speed + self.speed_bonus) / 75.0 * (max_move_speed - min_move_speed);
    if (self.condition.speedy) move_speed *= 1.5;

    return move_speed * self.move_multiplier * self.walk_speed_multiplier;
}

fn hash(str: []const u8) u64 {
    return std.hash.Wyhash.hash(0, str);
}

pub fn useAbility(self: *Player, index: comptime_int) void {
    if (index < 0 or index >= 4) @compileError("Invalid index");
    const abil_data = self.data.abilities[index];
    const time = main.current_time;
    if (time - self.last_ability_use[index] < i64f(abil_data.cooldown) * std.time.us_per_s) {
        assets.playSfx("error.mp3");
        return;
    }

    if (self.mp < abil_data.mana_cost) {
        assets.playSfx("error.mp3");
        return;
    }
    self.mp -= abil_data.mana_cost;

    // le because 0 HP means dead
    if (self.hp <= abil_data.health_cost) {
        assets.playSfx("error.mp3");
        return;
    }
    self.hp -= abil_data.health_cost;

    if (self.gold < abil_data.gold_cost) {
        assets.playSfx("error.mp3");
        return;
    }
    self.gold -= abil_data.gold_cost;

    const data = switch (hash(abil_data.name)) {
        hash("Terrain Expulsion") => abilities.handleTerrainExpulsion(self, &self.data.abilities[index].projectiles.?[0]),
        hash("Heart of Stone") => abilities.handleHeartOfStone(self),
        hash("Time Dilation") => abilities.handleTimeDilation(self),
        hash("Rewind") => abilities.handleRewind(),
        hash("Null Pulse") => abilities.handleNullPulse(self),
        hash("Time Lock") => abilities.handleTimeLock(self),
        hash("Equivalent Exchange") => abilities.handleEquivalentExchange(self),
        hash("Asset Bubble") => abilities.handleAssetBubble(self),
        hash("Premium Protection") => abilities.handlePremiumProtection(self),
        hash("Compound Interest") => abilities.handleCompoundInterest(self),
        hash("Boulder Buddies"), hash("Placeholder") => &.{},
        else => {
            std.log.err("Unhandled ability: {s}", .{abil_data.name});
            return;
        },
    } catch |e| {
        std.log.err("Error while processing ability {s}: {}", .{ abil_data.name, e });
        return;
    };

    assets.playSfx(abil_data.sound);
    self.last_ability_use[index] = time;
    main.game_server.sendPacket(.{ .use_ability = .{ .time = time, .index = index, .data = data } });
}

pub fn weaponShoot(self: *Player, angle_base: f32, time: i64) void {
    if (self.condition.stunned) return;

    const item_data = game_data.item.from_id.getPtr(self.inventory[0]) orelse return;
    if (item_data.projectile == null) return;

    if (item_data.mana_cost) |cost| if (self.mp < cost.amount) {
        assets.playSfx("error.mp3");
        return;
    };

    if (item_data.health_cost) |cost| if (self.hp <= cost.amount) {
        assets.playSfx("error.mp3");
        return;
    };

    if (item_data.gold_cost) |cost| if (self.gold < cost.amount) {
        assets.playSfx("error.mp3");
        return;
    };

    const attack_delay = i64f(1.0 / (item_data.fire_rate * attack_frequency));
    if (time < self.attack_start + attack_delay) return;

    assets.playSfx(item_data.sound);

    self.attack_period = attack_delay;
    self.attack_angle = angle_base;
    self.attack_start = time;

    const projs_len = item_data.projectile_count;
    const arc_gap = item_data.arc_gap * std.math.rad_per_deg;
    const total_angle = arc_gap * f32i(projs_len - 1);
    var angle = angle_base - total_angle / 2.0;
    const proj_data = item_data.projectile.?;

    for (0..projs_len) |_| {
        const proj_index = self.next_proj_index;
        self.next_proj_index +%= 1;
        const x = self.x + @cos(angle_base) * 0.25;
        const y = self.y + @sin(angle_base) * 0.25;

        Projectile.addToMap(.{
            .x = x,
            .y = y,
            .data = &item_data.projectile.?,
            .angle = angle,
            .index = proj_index,
            .owner_map_id = self.map_id,
            .phys_dmg = i32f(f32i(proj_data.phys_dmg) * self.strengthMult()),
            .magic_dmg = i32f(f32i(proj_data.magic_dmg) * self.witMult()),
            .true_dmg = i32f(f32i(proj_data.true_dmg)),
        });

        main.game_server.sendPacket(.{ .player_projectile = .{
            .time = time,
            .proj_index = proj_index,
            .x = x,
            .y = y,
            .angle = angle,
        } });

        angle += arc_gap;
    }
}

pub fn draw(self: *Player, cam_data: CameraData, float_time_ms: f32) void {
    if (main.needs_map_bg or !cam_data.visibleInCamera(self.x, self.y)) return;

    const size = Camera.size_mult * cam_data.scale * self.size_mult;

    var atlas_data = self.atlas_data;
    var sink: f32 = 1.0;
    if (map.getSquare(self.x, self.y, true, .con)) |square| sink += if (square.data.sink) 0.75 else 0;
    atlas_data.tex_h /= sink;

    const w = atlas_data.texWRaw() * size;
    const h = atlas_data.texHRaw() * size;
    const dir_idx: u8 = @intFromEnum(self.direction);
    const stand_data = self.anim_data.walk_anims[dir_idx * assets.AnimPlayerData.walk_actions];
    const stand_w = stand_data.width() * size;
    const x_offset = (if (self.direction == .left) stand_w - w else w - stand_w) / 2.0;

    var screen_pos = cam_data.worldToScreen(self.x, self.y);
    screen_pos.x += x_offset;
    screen_pos.y += self.z * -px_per_tile - h + assets.padding * size;

    var alpha_mult: f32 = self.alpha;
    if (self.condition.invisible)
        alpha_mult = 0.6;

    var color: u32 = 0;
    var color_intensity: f32 = 0.0;
    _ = &color;
    _ = &color_intensity;
    // flash

    if (main.settings.enable_lights) {
        const tile_pos = cam_data.worldToScreen(self.x, self.y);
        main.renderer.drawLight(self.data.light, tile_pos.x, tile_pos.y, cam_data.scale, float_time_ms);
    }

    if (self.name_text_data) |*data| {
        data.sort_extra = -data.height;
        main.renderer.drawText(
            screen_pos.x - x_offset - data.width / 2 - assets.padding * 2,
            screen_pos.y - data.height - 5,
            cam_data.scale,
            data,
            .{},
        );
    }

    main.renderer.drawQuad(
        screen_pos.x - w / 2.0,
        screen_pos.y,
        w,
        h,
        atlas_data,
        .{
            .shadow_texel_mult = 2.0 / size,
            .alpha_mult = alpha_mult,
            .color = color,
            .color_intensity = color_intensity,
        },
    );

    var y_pos: f32 = if (sink != 1.0) 15.0 else 5.0;

    if (self.hp >= 0 and self.hp < self.max_hp + self.max_hp_bonus) {
        const hp_bar_w = assets.hp_bar_data.texWRaw() * 2 * cam_data.scale;
        const hp_bar_h = assets.hp_bar_data.texHRaw() * 2 * cam_data.scale;
        const hp_bar_y = screen_pos.y + h + y_pos;

        main.renderer.drawQuad(
            screen_pos.x - x_offset - hp_bar_w / 2.0,
            hp_bar_y,
            hp_bar_w,
            hp_bar_h,
            assets.empty_bar_data,
            .{ .shadow_texel_mult = 0.5, .sort_extra = -h - y_pos - 0.0001 },
        );

        const float_hp = f32i(self.hp);
        const float_max_hp = f32i(self.max_hp + self.max_hp_bonus);
        const left_pad = 2.0;
        const w_no_pad = 20.0;
        const total_w = 24.0;
        const hp_perc = (left_pad / total_w) + (w_no_pad / total_w) * (float_hp / float_max_hp);

        var hp_bar_data = assets.hp_bar_data;
        hp_bar_data.tex_w *= hp_perc;

        main.renderer.drawQuad(
            screen_pos.x - x_offset - hp_bar_w / 2.0,
            hp_bar_y,
            hp_bar_w * hp_perc,
            hp_bar_h,
            hp_bar_data,
            .{ .shadow_texel_mult = 0.5, .sort_extra = -h - y_pos },
        );

        y_pos += hp_bar_h + 5.0;
    }

    if (self.mp >= 0 and self.mp < self.max_mp + self.max_mp_bonus) {
        const mp_bar_w = assets.mp_bar_data.width() * 2 * cam_data.scale;
        const mp_bar_h = assets.mp_bar_data.height() * 2 * cam_data.scale;
        const mp_bar_y = screen_pos.y + h + y_pos;

        main.renderer.drawQuad(
            screen_pos.x - x_offset - mp_bar_w / 2.0,
            mp_bar_y,
            mp_bar_w,
            mp_bar_h,
            assets.empty_bar_data,
            .{ .shadow_texel_mult = 0.5, .sort_extra = -h - y_pos - 0.0001 },
        );

        const float_mp = f32i(self.mp);
        const float_max_mp = f32i(self.max_mp + self.max_mp_bonus);
        const left_pad = 2.0;
        const w_no_pad = 20.0;
        const total_w = 24.0;
        const mp_perc = (left_pad / total_w) + (w_no_pad / total_w) * (float_mp / float_max_mp);

        var mp_bar_data = assets.mp_bar_data;
        mp_bar_data.tex_w *= mp_perc;

        main.renderer.drawQuad(
            screen_pos.x - x_offset - mp_bar_w / 2.0,
            mp_bar_y,
            mp_bar_w * mp_perc,
            mp_bar_h,
            mp_bar_data,
            .{ .shadow_texel_mult = 0.5, .sort_extra = -h - y_pos },
        );

        y_pos += mp_bar_h + 5.0;
    }

    const cond_int: @typeInfo(utils.Condition).@"struct".backing_integer.? = @bitCast(self.condition);
    if (cond_int > 0) {
        base.drawConditions(cond_int, float_time_ms, screen_pos.x - x_offset, screen_pos.y + h + y_pos, cam_data.scale);
        y_pos += 20;
    }

    base.drawStatusTexts(
        self,
        i64f(float_time_ms) * std.time.us_per_ms,
        screen_pos.x - x_offset,
        screen_pos.y,
        cam_data.scale,
    );
}

pub fn update(self: *Player, time: i64, dt: f32) void {
    var float_period: f32 = 0.0;
    var action: assets.Action = .stand;

    if (time < self.attack_start + self.attack_period) {
        const time_dt = f32i(time - self.attack_start);
        float_period = f32i(self.attack_period);
        float_period = @mod(time_dt, float_period) / float_period;
        self.facing = self.attack_angle;
        action = .attack;
    } else if (map.info.player_map_id == self.map_id) {
        if (self.x_dir != 0.0 or self.y_dir != 0.0) {
            const float_time = f32i(time);
            float_period = 3.5 / self.moveSpeedMultiplier();
            float_period = @mod(float_time, float_period) / float_period;
            self.facing = std.math.atan2(self.y_dir, self.x_dir);
            action = .walk;
        }
    } else if (!std.math.isNan(self.move_angle)) {
        const float_time = f32i(time);
        float_period = 3.5 / self.moveSpeedMultiplier();
        float_period = @mod(float_time, float_period) / float_period;
        self.facing = self.move_angle;
        action = .walk;
    } else {
        float_period = 0.0;
        action = .stand;
    }

    const pi_div_4 = std.math.pi / 4.0;
    const angle = if (!std.math.isNan(self.facing))
        utils.halfBound(self.facing) / pi_div_4
    else
        0;

    const dir: assets.Direction = switch (u8f(@round(angle + 4)) % 8) {
        0, 7 => .left,
        1, 2 => .up,
        3, 4 => .right,
        5, 6 => .down,
        else => @panic("Invalid direction in player update"),
    };

    const anim_idx = u8f(@max(0, @min(0.99999, float_period)) * 2.0);
    const dir_idx: u8 = @intFromEnum(dir);

    const stand_data = self.anim_data.walk_anims[dir_idx * assets.AnimPlayerData.walk_actions];

    self.atlas_data = switch (action) {
        .walk => self.anim_data.walk_anims[dir_idx * assets.AnimPlayerData.walk_actions + 1 + anim_idx],
        .attack => self.anim_data.attack_anims[dir_idx * assets.AnimPlayerData.attack_actions + anim_idx],
        .stand => stand_data,
    };

    self.direction = dir;

    if (self.map_id == map.info.player_map_id) {
        if (!self.condition.paralyzed) {
            if (ui_systems.screen == .editor) {
                if (!std.math.isNan(self.move_angle)) {
                    const move_speed = self.moveSpeedMultiplier();
                    const new_x = self.x + move_speed * @cos(self.move_angle) * dt;
                    const new_y = self.y + move_speed * @sin(self.move_angle) * dt;

                    self.x = @max(0, @min(new_x, f32i(map.info.width - 1)));
                    self.y = @max(0, @min(new_y, f32i(map.info.height - 1)));
                }
            } else {
                if (map.getSquare(self.x, self.y, true, .con)) |square| {
                    const slide_amount = square.data.slide_amount;
                    if (!std.math.isNan(self.move_angle)) {
                        const move_speed = self.moveSpeedMultiplier();
                        const vec_x = move_speed * @cos(self.move_angle);
                        const vec_y = move_speed * @sin(self.move_angle);

                        if (slide_amount > 0.0) {
                            self.x_dir *= slide_amount;
                            self.y_dir *= slide_amount;

                            const max_move_length = vec_x * vec_x + vec_y * vec_y;
                            const move_length = self.x_dir * self.x_dir + self.y_dir * self.y_dir;
                            if (move_length < max_move_length) {
                                self.x_dir += vec_x * -1.0 * (slide_amount - 1.0);
                                self.y_dir += vec_y * -1.0 * (slide_amount - 1.0);
                            }
                        } else {
                            self.x_dir = vec_x;
                            self.y_dir = vec_y;
                        }
                    } else {
                        const move_length_sqr = self.x_dir * self.x_dir + self.y_dir * self.y_dir;
                        const min_move_len_sqr = 0.00012 * 0.00012;
                        if (move_length_sqr > min_move_len_sqr and slide_amount > 0.0) {
                            self.x_dir *= slide_amount;
                            self.y_dir *= slide_amount;
                        } else {
                            self.x_dir = 0.0;
                            self.y_dir = 0.0;
                        }
                    }

                    if (square.data.push) {
                        self.x_dir -= square.data.animation.delta_x / 1000.0;
                        self.y_dir -= square.data.animation.delta_y / 1000.0;
                    }
                }

                const dx = self.x_dir * dt;
                const dy = self.y_dir * dt;

                if (dx < move_threshold and dx > -move_threshold and dy < move_threshold and dy > -move_threshold) {
                    modifyStep(self, self.x + dx, self.y + dy);
                } else {
                    const step_size = move_threshold / @max(@abs(dx), @abs(dy));
                    for (0..usizef(1.0 / step_size)) |_| modifyStep(self, self.x + dx * step_size, self.y + dy * step_size);
                }
            }
        }

        if (!self.condition.invulnerable and time - self.last_ground_damage_time >= 0.5 * std.time.us_per_s) {
            if (map.getSquare(self.x, self.y, true, .con)) |square| {
                const protect = blk: {
                    const e = map.findObject(Entity, square.entity_map_id, .con) orelse break :blk false;
                    break :blk e.data.block_ground_damage;
                };
                if (square.data.damage > 0 and !protect) {
                    main.game_server.sendPacket(.{ .ground_damage = .{ .time = time, .x = self.x, .y = self.y } });
                    map.takeDamage(self, square.data.damage, .true, .{}, self.colors);
                    self.last_ground_damage_time = time;
                }
            }
        }
    } else if (!std.math.isNan(self.move_angle) and self.move_step > 0.0) {
        const cos_angle = @cos(self.move_angle);
        const sin_angle = @sin(self.move_angle);
        const next_x = self.x + dt * self.move_step * cos_angle;
        const next_y = self.y + dt * self.move_step * sin_angle;
        self.x = if (cos_angle > 0.0) @min(self.target_x, next_x) else @max(self.target_x, next_x);
        self.y = if (sin_angle > 0.0) @min(self.target_y, next_y) else @max(self.target_y, next_y);
        if (@abs(self.x - self.target_x) < 0.01 and @abs(self.y - self.target_y) < 0.01) {
            self.move_angle = std.math.nan(f32);
            self.move_step = 0.0;
            self.target_x = 0.0;
            self.target_y = 0.0;
        }
    }

    if (self.ability_state.time_dilation) {
        const radius = 3.0 + f32i(self.wit + self.wit_bonus) * 0.06;
        const radius_sqr = radius * radius;

        for (map.listForType(Projectile).items) |*p| {
            if (p.damage_players and utils.distSqr(p.x, p.y, self.x, self.y) <= radius_sqr) p.time_dilation_active = true;
        }
    }
}

fn isWalkable(x: f32, y: f32) bool {
    if (map.getSquare(x, y, true, .con)) |square| {
        const walkable = !square.data.no_walk;
        const not_occupied = blk: {
            const e = map.findObject(Entity, square.entity_map_id, .con) orelse break :blk true;
            break :blk !e.data.occupy_square;
        };
        return square.data_id != Square.editor_tile and square.data_id != Square.empty_tile and walkable and not_occupied;
    } else return false;
}

fn isFullOccupy(x: f32, y: f32) bool {
    if (map.getSquare(x, y, true, .con)) |square| {
        const e = map.findObject(Entity, square.entity_map_id, .con) orelse return false;
        return e.data.full_occupy or e.data.is_wall;
    } else return true;
}

fn isValidPosition(x: f32, y: f32) bool {
    if (!isWalkable(x, y))
        return false;

    const x_frac = x - @floor(x);
    const y_frac = y - @floor(y);

    if (x_frac < 0.5) {
        if (isFullOccupy(x - 1, y))
            return false;

        if (y_frac < 0.5 and (isFullOccupy(x, y - 1) or isFullOccupy(x - 1, y - 1)))
            return false;

        if (y_frac > 0.5 and (isFullOccupy(x, y + 1) or isFullOccupy(x - 1, y + 1)))
            return false;
    } else if (x_frac > 0.5) {
        if (isFullOccupy(x + 1, y))
            return false;

        if (y_frac < 0.5 and (isFullOccupy(x, y - 1) or isFullOccupy(x + 1, y - 1)))
            return false;

        if (y_frac > 0.5 and (isFullOccupy(x, y + 1) or isFullOccupy(x + 1, y + 1)))
            return false;
    } else {
        if (y_frac < 0.5 and isFullOccupy(x, y - 1))
            return false;

        if (y_frac > 0.5 and isFullOccupy(x, y + 1))
            return false;
    }
    return true;
}

fn modifyStep(self: *Player, x: f32, y: f32) void {
    const x_cross = (@mod(self.x, 0.5) == 0 and x != self.x) or (@floor(self.x / 0.5) != @floor(x / 0.5));
    const y_cross = (@mod(self.y, 0.5) == 0 and y != self.y) or (@floor(self.y / 0.5) != @floor(y / 0.5));

    if (!x_cross and !y_cross or isValidPosition(x, y)) {
        self.x = x;
        self.y = y;
        return;
    }

    var next_x_border: f32 = 0.0;
    var next_y_border: f32 = 0.0;
    if (x_cross) {
        next_x_border = if (x > self.x) @floor(x * 2) / 2.0 else @floor(self.x * 2) / 2.0;
        if (@floor(next_x_border) > @floor(self.x))
            next_x_border -= 0.001;
    }

    if (y_cross) {
        next_y_border = if (y > self.y) @floor(y * 2) / 2.0 else @floor(self.y * 2) / 2.0;
        if (@floor(next_y_border) > @floor(self.y))
            next_y_border -= 0.001;
    }

    const x_border_dist = if (x > self.x) x - next_x_border else next_x_border - x;
    const y_border_dist = if (y > self.y) y - next_y_border else next_y_border - y;

    if (x_border_dist > y_border_dist) {
        if (isValidPosition(x, next_y_border)) {
            self.x = x;
            self.y = next_y_border;
            return;
        }

        if (isValidPosition(next_x_border, y)) {
            self.x = next_x_border;
            self.y = y;
            return;
        }
    } else {
        if (isValidPosition(next_x_border, y)) {
            self.x = next_x_border;
            self.y = y;
            return;
        }

        if (isValidPosition(x, next_y_border)) {
            self.x = x;
            self.y = next_y_border;
            return;
        }
    }

    self.x = next_x_border;
    self.y = next_y_border;
}
