const std = @import("std");
const element = @import("../ui/element.zig");
const shared = @import("shared");
const utils = shared.utils;
const game_data = shared.game_data;
const assets = @import("../assets.zig");
const map = @import("map.zig");
const main = @import("../main.zig");
const input = @import("../input.zig");
const network = @import("../network.zig");
const particles = @import("particles.zig");
const ui_systems = @import("../ui/systems.zig");
const base = @import("object_base.zig");
const render = @import("../render.zig");
const Camera = @import("../Camera.zig");
const px_per_tile = Camera.px_per_tile;
const size_mult = Camera.size_mult;

const Entity = @import("entity.zig").Entity;
const Projectile = @import("projectile.zig").Projectile;
const Square = @import("square.zig").Square;

pub const Player = struct {
    const float_us: comptime_float = std.time.us_per_s;
    pub const move_threshold = 0.4;
    pub const min_move_speed = 4.0 / float_us;
    pub const max_move_speed = 9.6 / float_us;
    pub const attack_frequency = 5.0 / float_us;
    pub const max_sink_level = 18.0;

    map_id: u32 = std.math.maxInt(u32),
    data_id: u16 = std.math.maxInt(u16),
    dead: bool = false,
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,
    alpha: f32 = 1.0,
    name: ?[]const u8 = null,
    name_text_data: ?element.TextData = null,
    name_text_data_inited: bool = false,
    in_combat: bool = false,
    aether: u8 = 1,
    spirits_communed: u32 = 0,
    muted_until: i64 = 0,
    gold: i32 = 0,
    gems: i32 = 0,
    crowns: i32 = 0,
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
    penetration: i16 = 0,
    piercing: i16 = 0,
    haste: i16 = 0,
    tenacity: i16 = 0,
    max_hp_bonus: i32 = 0,
    max_mp_bonus: i32 = 0,
    strength_bonus: i16 = 0,
    defense_bonus: i16 = 0,
    speed_bonus: i16 = 0,
    stamina_bonus: i16 = 0,
    wit_bonus: i16 = 0,
    resistance_bonus: i16 = 0,
    intelligence_bonus: i16 = 0,
    penetration_bonus: i16 = 0,
    piercing_bonus: i16 = 0,
    haste_bonus: i16 = 0,
    tenacity_bonus: i16 = 0,
    hit_multiplier: f32 = 1.0,
    damage_multiplier: f32 = 1.0,
    condition: utils.Condition = .{},
    inventory: [22]u16 = [_]u16{std.math.maxInt(u16)} ** 22,
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
    direction: assets.Direction = .right,

    pub fn addToMap(self: *Player, allocator: std.mem.Allocator) void {
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
            self.name_text_data.?.setText(if (self.name) |player_name| player_name else self.data.name, allocator);
        }

        map.addListForType(Player).append(allocator, self.*) catch @panic("Adding player failed");
    }

    pub fn deinit(self: *Player, allocator: std.mem.Allocator) void {
        base.deinit(self, allocator);
    }

    pub fn onMove(self: *Player) void {
        if (map.getSquare(self.x, self.y, true)) |square| self.move_multiplier = square.data.speed_mult;
    }

    pub fn strengthMult(self: Player) f32 {
        if (self.condition.weak) return 0.5;

        const fstr: f32 = @floatFromInt(self.strength + self.strength_bonus);
        var mult = 0.5 + fstr / 75.0;
        if (self.condition.damaging) mult *= 1.5;
        return mult;
    }

    pub fn witMult(self: Player) f32 {
        const fwit: f32 = @floatFromInt(self.wit + self.wit_bonus);
        return 0.5 + fwit / 75.0;
    }

    pub fn moveSpeedMultiplier(self: Player) f32 {
        if (self.condition.slowed)
            return min_move_speed * self.move_multiplier * self.walk_speed_multiplier;

        const float_speed: f32 = @floatFromInt(self.speed);
        var move_speed = min_move_speed + float_speed / 75.0 * (max_move_speed - min_move_speed);
        if (self.condition.speedy)
            move_speed *= 1.5;

        return move_speed * self.move_multiplier * self.walk_speed_multiplier;
    }

    pub fn useAbility(self: *Player) void {
        const item_data = game_data.item.from_id.get(self.inventory[1]) orelse {
            assets.playSfx("error.mp3");
            return;
        };
        assets.playSfx(item_data.sound);

        main.server.sendPacket(.{ .use_item = .{
            .time = main.current_time,
            .x = self.x,
            .y = self.y,
            .slot_id = 1,
            .obj_type = .player,
            .map_id = self.map_id,
        } });
    }

    pub fn doShoot(
        self: *Player,
        allocator: std.mem.Allocator,
        time: i64,
        item_props: *game_data.ItemData,
        attack_angle: f32,
    ) void {
        const projs_len = item_props.projectile_count;
        const arc_gap = std.math.degreesToRadians(item_props.arc_gap);
        const total_angle = arc_gap * @as(f32, @floatFromInt(projs_len - 1));
        var angle = attack_angle - total_angle / 2.0;
        const proj_data = item_props.projectile.?;

        for (0..projs_len) |_| {
            const proj_index = @mod(self.next_proj_index + 1, 128);
            self.next_proj_index = proj_index;
            const x = self.x + @cos(attack_angle) * 0.25;
            const y = self.y + @sin(attack_angle) * 0.25;

            var proj: Projectile = .{
                .x = x,
                .y = y,
                .data = &item_props.projectile.?,
                .angle = angle,
                .index = proj_index,
                .owner_map_id = self.map_id,
                .phys_dmg = @intFromFloat(@as(f32, @floatFromInt(proj_data.phys_dmg)) * self.strengthMult()),
            };
            proj.addToMap(allocator);

            main.server.sendPacket(.{ .player_projectile = .{
                .time = time,
                .proj_index = proj_index,
                .x = x,
                .y = y,
                .angle = angle,
            } });

            angle += arc_gap;
        }
    }

    pub fn weaponShoot(self: *Player, allocator: std.mem.Allocator, angle: f32, time: i64) void {
        const item_data = game_data.item.from_id.getPtr(self.inventory[0]) orelse return;
        if (item_data.projectile == null)
            return;

        const attack_delay: i64 = @intFromFloat(1.0 / (item_data.fire_rate * attack_frequency));
        if (time < self.attack_start + attack_delay)
            return;

        assets.playSfx(item_data.sound);

        self.attack_period = attack_delay;
        self.attack_angle = angle - main.camera.angle;
        self.attack_start = time;

        self.doShoot(allocator, self.attack_start, item_data, angle);
    }

    pub fn draw(self: *Player, cam_data: render.CameraData, float_time_ms: f32, allocator: std.mem.Allocator) void {
        if (ui_systems.screen == .editor or self.dead or !cam_data.visibleInCamera(self.x, self.y)) return;

        const size = size_mult * cam_data.scale * self.size_mult;

        var atlas_data = self.atlas_data;
        var sink: f32 = 1.0;
        if (map.getSquare(self.x, self.y, true)) |square| sink += if (square.data.sink) 0.75 else 0;
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
            render.drawLight(allocator, self.data.light, tile_pos.x, tile_pos.y, cam_data.scale, float_time_ms);
        }

        if (self.name_text_data) |*data| {
            data.sort_extra = -data.height;
            render.drawText(
                screen_pos.x - x_offset - data.width / 2 - assets.padding * 2,
                screen_pos.y - data.height,
                cam_data.scale,
                data,
                .{},
            );
        }

        render.drawQuad(
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

        if (self.hp >= 0 and self.hp < self.max_hp) {
            const hp_bar_w = assets.hp_bar_data.texWRaw() * 2 * cam_data.scale;
            const hp_bar_h = assets.hp_bar_data.texHRaw() * 2 * cam_data.scale;
            const hp_bar_y = screen_pos.y + h + y_pos;

            render.drawQuad(
                screen_pos.x - x_offset - hp_bar_w / 2.0,
                hp_bar_y,
                hp_bar_w,
                hp_bar_h,
                assets.empty_bar_data,
                .{ .shadow_texel_mult = 0.5, .sort_extra = -h - y_pos - 0.0001 },
            );

            const float_hp: f32 = @floatFromInt(self.hp);
            const float_max_hp: f32 = @floatFromInt(self.max_hp);
            const left_pad = 2.0;
            const w_no_pad = 20.0;
            const total_w = 24.0;
            const hp_perc = (left_pad / total_w) + (w_no_pad / total_w) * (float_hp / float_max_hp);

            var hp_bar_data = assets.hp_bar_data;
            hp_bar_data.tex_w *= hp_perc;

            render.drawQuad(
                screen_pos.x - x_offset - hp_bar_w / 2.0,
                hp_bar_y,
                hp_bar_w * hp_perc,
                hp_bar_h,
                hp_bar_data,
                .{ .shadow_texel_mult = 0.5, .sort_extra = -h - y_pos },
            );

            y_pos += hp_bar_h + 5.0;
        }

        if (self.mp >= 0 and self.mp < self.max_mp) {
            const mp_bar_w = assets.mp_bar_data.width() * 2 * cam_data.scale;
            const mp_bar_h = assets.mp_bar_data.height() * 2 * cam_data.scale;
            const mp_bar_y = screen_pos.y + h + y_pos;

            render.drawQuad(
                screen_pos.x - x_offset - mp_bar_w / 2.0,
                mp_bar_y,
                mp_bar_w,
                mp_bar_h,
                assets.empty_bar_data,
                .{ .shadow_texel_mult = 0.5, .sort_extra = -h - y_pos - 0.0001 },
            );

            const float_mp: f32 = @floatFromInt(self.mp);
            const float_max_mp: f32 = @floatFromInt(self.max_mp);
            const left_pad = 2.0;
            const w_no_pad = 20.0;
            const total_w = 24.0;
            const mp_perc = (left_pad / total_w) + (w_no_pad / total_w) * (float_mp / float_max_mp);

            var mp_bar_data = assets.mp_bar_data;
            mp_bar_data.tex_w *= mp_perc;

            render.drawQuad(
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
    }

    pub fn update(self: *Player, time: i64, dt: f32, allocator: std.mem.Allocator) void {
        var float_period: f32 = 0.0;
        var action: assets.Action = .stand;

        if (time < self.attack_start + self.attack_period) {
            const time_dt: f32 = @floatFromInt(time - self.attack_start);
            float_period = @floatFromInt(self.attack_period);
            float_period = @mod(time_dt, float_period) / float_period;
            self.facing = self.attack_angle + main.camera.angle;
            action = .attack;
        } else if (map.info.player_map_id == self.map_id) {
            if (self.x_dir != 0.0 or self.y_dir != 0.0) {
                const float_time: f32 = @floatFromInt(time);
                float_period = 3.5 / self.moveSpeedMultiplier();
                float_period = @mod(float_time, float_period) / float_period;
                self.facing = std.math.atan2(self.y_dir, self.x_dir);
                action = .walk;
            }
        } else if (!std.math.isNan(self.move_angle)) {
            const float_time: f32 = @floatFromInt(time);
            float_period = 3.5 / self.moveSpeedMultiplier();
            float_period = @mod(float_time, float_period) / float_period;
            self.facing = self.move_angle;
            action = .walk;
        } else {
            float_period = 0.0;
            action = .stand;
        }

        const pi_div_4 = std.math.pi / 4.0;
        const angle = if (std.math.isNan(self.facing))
            utils.halfBound(main.camera.angle) / pi_div_4
        else
            utils.halfBound(self.facing - main.camera.angle) / pi_div_4;

        const dir: assets.Direction = switch (@as(u8, @intFromFloat(@round(angle + 4))) % 8) {
            0, 7 => .left,
            1, 2 => .up,
            3, 4 => .right,
            5, 6 => .down,
            else => unreachable,
        };

        const anim_idx: u8 = @intFromFloat(@max(0, @min(0.99999, float_period)) * 2.0);
        const dir_idx: u8 = @intFromEnum(dir);

        const stand_data = self.anim_data.walk_anims[dir_idx * assets.AnimPlayerData.walk_actions];

        self.atlas_data = switch (action) {
            .walk => self.anim_data.walk_anims[dir_idx * assets.AnimPlayerData.walk_actions + 1 + anim_idx],
            .attack => self.anim_data.attack_anims[dir_idx * assets.AnimPlayerData.attack_actions + anim_idx],
            .stand => stand_data,
        };

        self.direction = dir;

        if (self.map_id == map.info.player_map_id) {
            if (ui_systems.screen == .editor) {
                if (!std.math.isNan(self.move_angle)) {
                    const move_angle = main.camera.angle + self.move_angle;
                    const move_speed = self.moveSpeedMultiplier();
                    const new_x = self.x + move_speed * @cos(move_angle) * dt;
                    const new_y = self.y + move_speed * @sin(move_angle) * dt;

                    self.x = @max(0, @min(new_x, @as(f32, @floatFromInt(map.info.width - 1))));
                    self.y = @max(0, @min(new_y, @as(f32, @floatFromInt(map.info.height - 1))));
                }
            } else {
                if (map.getSquare(self.x, self.y, true)) |square| {
                    const slide_amount = square.data.slide_amount;
                    if (!std.math.isNan(self.move_angle)) {
                        const move_angle = main.camera.angle + self.move_angle;
                        const move_speed = self.moveSpeedMultiplier();
                        const vec_x = move_speed * @cos(move_angle);
                        const vec_y = move_speed * @sin(move_angle);

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

                const next_x = self.x + self.x_dir * dt;
                const next_y = self.y + self.y_dir * dt;

                modifyMove(self, next_x, next_y, &self.x, &self.y);

                if (!self.condition.invulnerable and time - self.last_ground_damage_time >= 0.5 * std.time.us_per_s) {
                    if (map.getSquare(self.x, self.y, true)) |square| {
                        const protect = blk: {
                            const e = map.findObject(Entity, square.entity_map_id, .con) orelse break :blk false;
                            break :blk e.data.block_ground_damage;
                        };
                        if (square.data.damage > 0 and !protect) {
                            main.server.sendPacket(.{ .ground_damage = .{ .time = time, .x = self.x, .y = self.y } });
                            map.takeDamage(self, square.data.damage, .true, .{}, self.colors, allocator);
                            self.last_ground_damage_time = time;
                        }
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
        }
    }

    fn modifyMove(self: *Player, x: f32, y: f32, target_x: *f32, target_y: *f32) void {
        const dx = x - self.x;
        const dy = y - self.y;

        if (dx < move_threshold and dx > -move_threshold and dy < move_threshold and dy > -move_threshold) {
            modifyStep(self, x, y, target_x, target_y);
            return;
        }

        target_x.* = self.x;
        target_y.* = self.y;

        const step_size = move_threshold / @max(@abs(dx), @abs(dy));
        for (0..@intFromFloat(1.0 / step_size)) |_| modifyStep(self, target_x.* + dx * step_size, target_y.* + dy * step_size, target_x, target_y);
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

    fn isWalkable(x: f32, y: f32) bool {
        if (map.getSquare(x, y, true)) |square| {
            const walkable = !square.data.no_walk;
            const not_occupied = blk: {
                const e = map.findObject(Entity, square.entity_map_id, .con) orelse break :blk true;
                break :blk !(e.data.occupy_square or e.data.is_wall);
            };
            return square.data_id != Square.editor_tile and square.data_id != Square.empty_tile and walkable and not_occupied;
        } else return false;
    }

    fn isFullOccupy(x: f32, y: f32) bool {
        if (map.getSquare(x, y, true)) |square| {
            const e = map.findObject(Entity, square.entity_map_id, .con) orelse return false;
            return e.data.full_occupy;
        } else return true;
    }

    fn modifyStep(self: *Player, x: f32, y: f32, target_x: *f32, target_y: *f32) void {
        const x_cross = (@mod(self.x, 0.5) == 0 and x != self.x) or (@floor(self.x / 0.5) != @floor(x / 0.5));
        const y_cross = (@mod(self.y, 0.5) == 0 and y != self.y) or (@floor(self.y / 0.5) != @floor(y / 0.5));

        if (!x_cross and !y_cross or isValidPosition(x, y)) {
            target_x.* = x;
            target_y.* = y;
            return;
        }

        var next_x_border: f32 = 0.0;
        var next_y_border: f32 = 0.0;
        if (x_cross) {
            next_x_border = if (x > self.x) @floor(x * 2) / 2.0 else @floor(self.x * 2) / 2.0;
            if (@floor(next_x_border) > @floor(self.x))
                next_x_border -= 0.01;
        }

        if (y_cross) {
            next_y_border = if (y > self.y) @floor(y * 2) / 2.0 else @floor(self.y * 2) / 2.0;
            if (@floor(next_y_border) > @floor(self.y))
                next_y_border -= 0.01;
        }

        const x_border_dist = if (x > self.x) x - next_x_border else next_x_border - x;
        const y_border_dist = if (y > self.y) y - next_y_border else next_y_border - y;

        if (x_border_dist > y_border_dist) {
            if (isValidPosition(x, next_y_border)) {
                target_x.* = x;
                target_y.* = next_y_border;
                return;
            }

            if (isValidPosition(next_x_border, y)) {
                target_x.* = next_x_border;
                target_y.* = y;
                return;
            }
        } else {
            if (isValidPosition(next_x_border, y)) {
                target_x.* = next_x_border;
                target_y.* = y;
                return;
            }

            if (isValidPosition(x, next_y_border)) {
                target_x.* = x;
                target_y.* = next_y_border;
                return;
            }
        }

        target_x.* = next_x_border;
        target_y.* = next_y_border;
    }
};
