const std = @import("std");
const element = @import("../ui/element.zig");
const utils = @import("../utils.zig");
const game_data = @import("../game_data.zig");
const assets = @import("../assets.zig");
const map = @import("map.zig");
const rpc = @import("rpc");
const main = @import("../main.zig");
const input = @import("../input.zig");
const network = @import("../network.zig");
const camera = @import("../camera.zig");
const particles = @import("particles.zig");
const systems = @import("../ui/systems.zig");

const Projectile = @import("projectile.zig").Projectile;

var rpc_set = false;

pub const Player = struct {
    pub const move_threshold = 0.4;
    pub const min_move_speed = 4.0 / @as(f32, std.time.us_per_s);
    pub const max_move_speed = 9.6 / @as(f32, std.time.us_per_s);
    pub const attack_frequency = 5.0 / @as(f32, std.time.us_per_s);
    pub const min_attack_mult = 0.5;
    pub const max_attack_mult = 2.0;
    pub const max_sink_level = 18.0;

    obj_id: i32 = -1,
    obj_type: u16 = 0,
    dead: bool = false,
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,
    screen_x: f32 = 0.0,
    screen_y: f32 = 0.0,
    alpha: f32 = 1.0,
    name: ?[]const u8 = null,
    guild: ?[]const u8 = null,
    name_text_data: ?element.TextData = null,
    name_text_data_inited: bool = false,
    account_id: i32 = 0,
    size: f32 = 0,
    max_hp: i32 = 0,
    max_mp: i16 = 0,
    hp: i32 = 0,
    mp: i16 = 0,
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
    hp_bonus: i16 = 0,
    mp_bonus: i16 = 0,
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
    condition: utils.Condition = utils.Condition{},
    inventory: [22]u16 = [_]u16{std.math.maxInt(u16)} ** 22,
    tier: u8 = 0,
    tier_xp: i32 = 0,
    next_tier_xp: i32 = 1000,
    tex_1: i32 = 0,
    tex_2: i32 = 0,
    skin: u16 = 0,
    gold: i32 = 0,
    gems: i32 = 0,
    crowns: i32 = 0,
    guild_rank: i8 = 0,
    attack_start: i64 = 0,
    attack_period: i64 = 0,
    attack_angle: f32 = 0,
    next_bullet_id: u8 = 0,
    move_angle: f32 = std.math.nan(f32),
    move_step: f32 = 0.0,
    target_x: f32 = 0.0,
    target_y: f32 = 0.0,
    move_x_dir: bool = false,
    move_y_dir: bool = false,
    walk_speed_multiplier: f32 = 1.0,
    props: *const game_data.ObjProps = undefined,
    class_data: *const game_data.CharacterClass = undefined,
    last_ground_damage_time: i64 = -1,
    anim_data: assets.AnimPlayerData = undefined,
    atlas_data: assets.AtlasData = assets.AtlasData.fromRaw(0, 0, 0, 0, .base),
    render_x_offset: f32 = 0.0,
    move_multiplier: f32 = 1.0,
    sink_level: f32 = 0,
    colors: []u32 = &[0]u32{},
    next_ability_attack_time: i64 = -1,
    mp_zeroed: bool = false,
    x_dir: f32 = 0.0,
    y_dir: f32 = 0.0,
    facing: f32 = std.math.nan(f32),
    ability_use_times: [4]i64 = [_]i64{-1} ** 4,
    ability_data: std.ArrayList(u8) = undefined,
    in_combat: bool = false,
    _disposed: bool = false,

    pub fn onMove(self: *Player) void {
        if (map.getSquare(self.x, self.y)) |square| {
            if (square.props.sinking) {
                self.sink_level = @min(self.sink_level + 1, max_sink_level);
                self.move_multiplier = 0.1 + (1 - self.sink_level / max_sink_level) * (square.props.speed - 0.1);
            } else {
                self.sink_level = 0;
                self.move_multiplier = square.props.speed;
            }
        }
    }

    pub fn strengthMultiplier(self: Player) f32 {
        if (self.condition.weak)
            return min_attack_mult;

        const float_strength: f32 = @floatFromInt(self.strength);
        var mult = min_attack_mult + float_strength / 75.0 * (max_attack_mult - min_attack_mult);
        if (self.condition.damaging)
            mult *= 1.5;

        return mult;
    }

    pub fn witMultiplier(self: Player) f32 {
        if (self.condition.weak)
            return min_attack_mult;

        const float_wit: f32 = @floatFromInt(self.wit);
        var mult = min_attack_mult + float_wit / 75.0 * (max_attack_mult - min_attack_mult);
        if (self.condition.damaging)
            mult *= 1.5;

        return mult;
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

    pub inline fn addToMap(self: *Player, allocator: std.mem.Allocator) void {
        self.ability_data = std.ArrayList(u8).init(allocator);

        if (game_data.obj_type_to_tex_data.get(self.obj_type)) |tex_list| {
            const tex = tex_list[@as(usize, @intCast(self.obj_id)) % tex_list.len];
            if (assets.anim_players.get(tex.sheet)) |anim_data| {
                self.anim_data = anim_data[tex.index];
            } else {
                std.log.err("Could not find anim sheet {s} for player with type 0x{x}. Using error texture", .{ tex.sheet, self.obj_type });
                self.anim_data = assets.error_data_player;
            }

            self.colors = assets.atlas_to_color_data.get(@bitCast(self.anim_data.walk_anims[0])) orelse blk: {
                std.log.err("Could not parse color data for player with id {d}. Setting it to empty", .{self.obj_id});
                break :blk &[0]u32{};
            };
        }

        self.props = game_data.obj_type_to_props.getPtr(self.obj_type) orelse {
            std.log.err("Player with type 0x{x} has no props, can't add", .{self.obj_type});
            return;
        };
        self.size = self.props.getSize();

        self.class_data = game_data.classes.getPtr(self.obj_type) orelse {
            std.log.err("Player with type 0x{x} has no class data, can't add", .{self.obj_type});
            return;
        };

        if (self.name_text_data == null) {
            self.name_text_data = element.TextData{
                // name could have been set (usually is) before adding to map
                .text = if (self.name) |player_name| player_name else self.class_data.name,
                .text_type = .bold,
                .size = 16,
                .color = 0xFCDF00,
                .max_width = 200,
            };
            
            {
                self.name_text_data.?._lock.lock();
                defer self.name_text_data.?._lock.unlock();

                self.name_text_data.?.recalculateAttributes(allocator);
            }
        }

        setRpc: {
            if (self.obj_id == map.local_player_id and !rpc_set) {
                const presence = rpc.Packet.Presence{
                    .assets = .{
                        .large_image = rpc.Packet.ArrayString(256).create("logo"),
                        .large_text = rpc.Packet.ArrayString(128).create(main.version_text),
                        .small_image = rpc.Packet.ArrayString(256).create(self.class_data.rpc_name),
                        .small_text = rpc.Packet.ArrayString(128).createFromFormat("Tier {s} {s}", .{ utils.toRoman(self.tier), self.class_data.name }) catch {
                            std.log.err("Setting Discord RPC failed, small_text buffer was out of space", .{});
                            break :setRpc;
                        },
                    },
                    .state = rpc.Packet.ArrayString(128).createFromFormat("In {s}", .{map.name}) catch {
                        std.log.err("Setting Discord RPC failed, state buffer was out of space", .{});
                        break :setRpc;
                    },
                    .timestamps = .{
                        .start = main.rpc_start,
                    },
                };
                main.rpc_client.setPresence(presence) catch |e| {
                    std.log.err("Setting Discord RPC failed: {}", .{e});
                };
                rpc_set = true;
            }
        }

        map.add_lock.lockShared();
        defer map.add_lock.unlockShared();
        map.entities_to_add.append(.{ .player = self.* }) catch |e| {
            std.log.err("Could not add player to map (obj_id={d}, obj_type={d}, x={d}, y={d}): {}", .{ self.obj_id, self.obj_type, self.x, self.y, e });
        };
    }

    pub fn useAbility(self: *Player, idx: u8) void {
        const abil_props = switch (idx) {
            0 => self.class_data.ability_1,
            1 => self.class_data.ability_2,
            2 => self.class_data.ability_3,
            3 => self.class_data.ultimate_ability,
            else => {
                std.log.err("Invalid idx {d} for useAbility()", .{idx});
                return;
            },
        };

        const int_cd_ms: i64 = @intFromFloat(abil_props.cooldown * 1000);
        if (int_cd_ms > main.current_time - self.ability_use_times[idx] or
            abil_props.mana_cost > self.mp or
            abil_props.health_cost > self.hp - 1)
        {
            assets.playSfx("error");
            return;
        }

        self.ability_use_times[idx] = main.current_time;
        self.ability_data.clearRetainingCapacity();

        if (std.mem.eql(u8, abil_props.name, "Anomalous Burst")) {
            if (self.class_data.projs.len <= 0) {
                std.log.err("Attempted to cast Anomalous Burst without any projectiles attached to the player (type: 0x{x})", .{self.obj_type});
                return;
            }

            const attack_angle = std.math.atan2(f32, input.mouse_y, input.mouse_x);
            const num_projs: u16 = @intCast(6 + @divFloor(self.speed, 30));
            const arc_gap = std.math.degreesToRadians(f32, 24);
            const float_str: f32 = @floatFromInt(self.strength);

            const attack_angle_left = attack_angle - std.math.pi / 2.0;
            const left_proj_count = @divFloor(num_projs, 2);
            var left_angle = attack_angle_left - arc_gap * @as(f32, @floatFromInt(left_proj_count - 1));
            for (0..left_proj_count) |_| {
                const bullet_id = @mod(self.next_bullet_id + 1, 128);
                self.next_bullet_id = bullet_id;
                const x = self.x + @cos(attack_angle) * 0.25;
                const y = self.y + @sin(attack_angle) * 0.25;

                var proj = Projectile{
                    .x = x,
                    .y = y,
                    .props = self.class_data.projs[0],
                    .angle = left_angle,
                    .bullet_id = bullet_id,
                    .owner_id = self.obj_id,
                    .physical_damage = @intFromFloat((750 + float_str * 0.75) * self.damage_multiplier),
                    .piercing = self.piercing,
                    .penetration = self.penetration,
                };
                proj.addToMap();

                left_angle += arc_gap;
            }

            const attack_angle_right = attack_angle + std.math.pi / 2.0;
            const right_proj_count = num_projs - left_proj_count;
            var right_angle = attack_angle_right - arc_gap * @as(f32, @floatFromInt(right_proj_count - 1));
            for (0..left_proj_count) |_| {
                const bullet_id = @mod(self.next_bullet_id + 1, 128);
                self.next_bullet_id = bullet_id;
                const x = self.x + @cos(attack_angle) * 0.25;
                const y = self.y + @sin(attack_angle) * 0.25;

                var proj = Projectile{
                    .x = x,
                    .y = y,
                    .props = self.class_data.projs[0],
                    .angle = right_angle,
                    .bullet_id = bullet_id,
                    .owner_id = self.obj_id,
                    .physical_damage = @intFromFloat((750 + float_str * 0.75) * self.damage_multiplier),
                    .piercing = self.piercing,
                    .penetration = self.penetration,
                };
                proj.addToMap();

                right_angle += arc_gap;
            }

            self.ability_data.writer().writeAll(&std.mem.toBytes(attack_angle)) catch |e| {
                std.log.err("Writing to ability data buffer failed: {}", .{e});
                return;
            };
        } else if (std.mem.eql(u8, abil_props.name, "Possession")) {
            self.ability_data.writer().writeAll(&std.mem.toBytes(@as(f32, -1))) catch |e| {
                std.log.err("Writing to ability data buffer failed: {}", .{e});
                return;
            };
        }

        main.server.queuePacket(.{ .use_ability = .{ .time = main.current_time, .ability_type = idx, .data = self.ability_data.items } });
    }

    pub fn doShoot(self: *Player, time: i64, weapon_type: i32, item_props: ?*game_data.ItemProps, attack_angle: f32) void {
        const projs_len = item_props.?.num_projectiles;
        const arc_gap = item_props.?.arc_gap;
        const total_angle = arc_gap * @as(f32, @floatFromInt(projs_len - 1));
        var angle = attack_angle - total_angle / 2.0;
        const proj_props = item_props.?.projectile.?;

        const container_type = if (weapon_type == -1) std.math.maxInt(u16) else @as(u16, @intCast(weapon_type));

        for (0..projs_len) |_| {
            const bullet_id = @mod(self.next_bullet_id + 1, 128);
            self.next_bullet_id = bullet_id;
            const x = self.x + @cos(attack_angle) * 0.25;
            const y = self.y + @sin(attack_angle) * 0.25;

            const physical_damage = @as(f32, @floatFromInt(proj_props.physical_damage)) * self.strengthMultiplier();
            const magic_damage = @as(f32, @floatFromInt(proj_props.magic_damage)) * self.witMultiplier();
            const true_damage = @as(f32, @floatFromInt(proj_props.true_damage));

            var proj = Projectile{
                .x = x,
                .y = y,
                .props = proj_props,
                .angle = angle,
                .bullet_id = bullet_id,
                .owner_id = self.obj_id,
                .physical_damage = @intFromFloat(physical_damage * self.damage_multiplier),
                .magic_damage = @intFromFloat(magic_damage * self.damage_multiplier),
                .true_damage = @intFromFloat(true_damage * self.damage_multiplier),
                .piercing = self.piercing,
                .penetration = self.penetration,
            };
            proj.addToMap();

            main.server.queuePacket(.{
                .player_shoot = .{
                    .time = time,
                    .bullet_id = bullet_id,
                    .container_type = container_type, // todo mabye convert to a i32 for packet or convert client into u16?
                    .start_x = x,
                    .start_y = y,
                    .angle = angle,
                },
            });

            angle += arc_gap;
        }
    }

    pub fn weaponShoot(self: *Player, angle: f32, time: i64) void {
        const weapon_type: i32 = self.inventory[0];
        if (weapon_type == -1)
            return;

        const item_props = game_data.item_type_to_props.getPtr(@intCast(weapon_type));
        if (item_props == null or item_props.?.projectile == null)
            return;

        const attack_delay: i64 = @intFromFloat(1.0 / (item_props.?.rate_of_fire * attack_frequency));
        if (time < self.attack_start + attack_delay)
            return;

        assets.playSfx(item_props.?.old_sound);

        self.attack_period = attack_delay;
        self.attack_angle = angle - camera.angle;
        self.attack_start = time;

        self.doShoot(self.attack_start, weapon_type, item_props, angle);
    }

    pub fn takeDamage(
        self: *Player,
        phys_dmg: i32,
        magic_dmg: i32,
        true_dmg: i32,
        kill: bool,
        conditions: utils.Condition,
        proj_colors: []const u32,
        proj_angle: f32,
        proj_speed: f32,
        allocator: std.mem.Allocator,
    ) void {
        if (self.dead)
            return;

        if (kill) {
            self.dead = true;

            assets.playSfx(self.props.death_sound);
            var effect = particles.ExplosionEffect{
                .x = self.x,
                .y = self.y,
                .colors = self.colors,
                .size = self.size,
                .amount = 30,
            };
            effect.addToMap();
        } else {
            assets.playSfx(self.props.hit_sound);
            if (proj_angle == 0.0 and proj_speed == 0.0) {
                var effect = particles.ExplosionEffect{
                    .x = self.x,
                    .y = self.y,
                    .colors = self.colors,
                    .size = self.size,
                    .amount = 30,
                };
                effect.addToMap();
            } else {
                var effect = particles.HitEffect{
                    .x = self.x,
                    .y = self.y,
                    .colors = proj_colors,
                    .angle = proj_angle,
                    .speed = proj_speed,
                    .size = 1.0,
                    .amount = 3,
                };
                effect.addToMap();
            }

            const cond_int: @typeInfo(utils.Condition).Struct.backing_integer.? = @bitCast(conditions);
            for (0..@bitSizeOf(utils.Condition)) |i| {
                if (cond_int & (@as(usize, 1) << @intCast(i)) != 0) {
                    const eff: utils.ConditionEnum = @enumFromInt(i + 1);
                    const cond_str = eff.toString();
                    if (cond_str.len == 0)
                        continue;

                    self.condition.set(eff, true);

                    element.StatusText.add(.{
                        .obj_id = self.obj_id,
                        .text_data = .{
                            .text = std.fmt.allocPrint(allocator, "{s}", .{cond_str}) catch unreachable,
                            .text_type = .bold,
                            .size = 22,
                            .color = 0xB02020,
                        },
                        .initial_size = 22,
                    }) catch |e| {
                        std.log.err("Allocation for condition text \"{s}\" failed: {}", .{ cond_str, e });
                    };
                }
            }
        }

        if (phys_dmg > 0 or magic_dmg > 0 or true_dmg > 0) {
            map.showDamageText(phys_dmg, magic_dmg, true_dmg, self.obj_id, allocator);
        }
    }

    pub inline fn update(self: *Player, time: i64, dt: f32, allocator: std.mem.Allocator) void {
        var float_period: f32 = 0.0;
        var action: assets.Action = .stand;

        if (time < self.attack_start + self.attack_period) {
            const time_dt: f32 = @floatFromInt(time - self.attack_start);
            float_period = @floatFromInt(self.attack_period);
            float_period = @mod(time_dt, float_period) / float_period;
            self.facing = self.attack_angle + camera.angle;
            action = .attack;
        } else if (self.x_dir != 0.0 or self.y_dir != 0.0) {
            const float_time: f32 = @floatFromInt(time);
            float_period = 3.5 / self.moveSpeedMultiplier();
            float_period = @mod(float_time, float_period) / float_period;
            self.facing = std.math.atan2(f32, self.y_dir, self.x_dir);
            action = .walk;
        } else {
            float_period = 0.0;
            action = .stand;
        }

        const size = camera.size_mult * camera.scale * self.size;

        const pi_div_4 = std.math.pi / 4.0;
        const angle = if (std.math.isNan(self.facing))
            utils.halfBound(camera.angle) / pi_div_4
        else
            utils.halfBound(self.facing - camera.angle) / pi_div_4;

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

        const screen_pos = camera.rotateAroundCamera(self.x, self.y);
        const w = (self.atlas_data.texWRaw() - assets.padding * 2) * size;
        const h = (self.atlas_data.texHRaw() - assets.padding * 2) * size;
        const stand_w = (stand_data.texWRaw() - assets.padding * 2) * size;
        self.render_x_offset = (if (dir == .left) stand_w - w else w - stand_w) / 2.0;

        self.screen_x = screen_pos.x;
        self.screen_y = screen_pos.y + self.z * -camera.px_per_tile - h - 30; // account for name

        if (self.obj_id == map.local_player_id) {
            if (systems.screen == .editor) {
                if (!std.math.isNan(self.move_angle)) {
                    const move_angle = camera.angle + self.move_angle;
                    const move_speed = self.moveSpeedMultiplier();
                    const new_x = self.x + move_speed * @cos(move_angle) * dt;
                    const new_y = self.y + move_speed * @sin(move_angle) * dt;

                    self.x = @max(0, @min(new_x, @as(f32, @floatFromInt(map.width - 1))));
                    self.y = @max(0, @min(new_y, @as(f32, @floatFromInt(map.height - 1))));
                }
            } else {
                if (map.getSquare(self.x, self.y)) |square| {
                    const slide_amount = square.props.slide_amount;
                    if (!std.math.isNan(self.move_angle)) {
                        const move_angle = camera.angle + self.move_angle;
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

                    if (square.props.push) {
                        self.x_dir -= square.props.anim_dx / 1000.0;
                        self.y_dir -= square.props.anim_dy / 1000.0;
                    }
                }

                const next_x = self.x + self.x_dir * dt;
                const next_y = self.y + self.y_dir * dt;

                modifyMove(self, next_x, next_y, &self.x, &self.y);

                if (!self.condition.invulnerable and time - self.last_ground_damage_time >= 0.5 * std.time.us_per_s) {
                    if (map.getSquare(self.x, self.y)) |square| {
                        const total_damage = square.props.physical_damage + square.props.magic_damage + square.props.true_damage;
                        const protect = blk: {
                            const en = map.findEntityConst(square.static_obj_id) orelse break :blk false;
                            break :blk en == .object and en.object.props.protect_from_ground_damage;
                        };
                        if (total_damage > 0 and !protect) {
                            main.server.queuePacket(.{ .ground_damage = .{ .time = time, .x = self.x, .y = self.y } });
                            self.takeDamage(
                                @intCast(square.props.physical_damage),
                                @intCast(square.props.magic_damage),
                                @intCast(square.props.true_damage),
                                total_damage >= self.hp,
                                .{},
                                self.colors,
                                0.0,
                                100.0 / 10000.0,
                                allocator,
                            );
                            self.last_ground_damage_time = time;
                        }
                    }
                }
            }
        } else if (!std.math.isNan(self.move_angle) and self.move_step > 0.0) {
            const next_x = self.x + dt * self.move_step * @cos(self.move_angle);
            const next_y = self.y + dt * self.move_step * @sin(self.move_angle);
            self.x = if (self.move_x_dir) @min(self.target_x, next_x) else @max(self.target_x, next_x);
            self.y = if (self.move_y_dir) @min(self.target_y, next_y) else @max(self.target_y, next_y);
        }
    }

    fn modifyMove(self: *Player, x: f32, y: f32, target_x: *f32, target_y: *f32) void {
        const dx = x - self.x;
        const dy = y - self.y;

        if (dx < move_threshold and dx > -move_threshold and dy < move_threshold and dy > -move_threshold) {
            modifyStep(self, x, y, target_x, target_y);
            return;
        }

        var step_size = move_threshold / @max(@abs(dx), @abs(dy));

        target_x.* = self.x;
        target_y.* = self.y;

        var d: f32 = 0.0;
        while (true) {
            if (d + step_size >= 1.0) {
                step_size = 1.0 - d;
                break;
            }
            modifyStep(self, target_x.* + dx * step_size, target_y.* + dy * step_size, target_x, target_y);
            d += step_size;
        }
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
        if (map.getSquare(x, y)) |square| {
            const walkable = !square.props.no_walk;
            const not_occupied = blk: {
                const en = map.findEntityConst(square.static_obj_id) orelse break :blk true;
                break :blk en != .object or !en.object.props.occupy_square;
            };
            return square.tile_type != 0xFFFF and square.tile_type != 0xFF and walkable and not_occupied;
        } else return false;
    }

    fn isFullOccupy(x: f32, y: f32) bool {
        if (map.getSquare(x, y)) |square| {
            const en = map.findEntityConst(square.static_obj_id) orelse return false;
            return en == .object and en.object.props.full_occupy;
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
