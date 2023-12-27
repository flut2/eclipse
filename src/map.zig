const std = @import("std");
const network = @import("network.zig");
const game_data = @import("game_data.zig");
const camera = @import("camera.zig");
const input = @import("input.zig");
const main = @import("main.zig");
const utils = @import("utils.zig");
const assets = @import("assets.zig");
const element = @import("ui/element.zig");
const zstbi = @import("zstbi");
const particles = @import("particles.zig");
const systems = @import("ui/systems.zig");
const rpc = @import("rpc");

pub const move_threshold = 0.4;
pub const min_move_speed = 4.0 / @as(f32, std.time.us_per_s);
pub const max_move_speed = 9.6 / @as(f32, std.time.us_per_s);
pub const attack_frequency = 5.0 / @as(f32, std.time.us_per_s);
pub const min_attack_mult = 0.5;
pub const max_attack_mult = 2.0;
pub const max_sink_level = 18.0;

pub const Square = struct {
    tile_type: u16 = 0xFFFF,
    x: f32 = 0.0,
    y: f32 = 0.0,
    atlas_data: assets.AtlasData = assets.AtlasData.fromRaw(0, 0, 0, 0),
    left_blend_u: f32 = -1.0,
    left_blend_v: f32 = -1.0,
    top_blend_u: f32 = -1.0,
    top_blend_v: f32 = -1.0,
    right_blend_u: f32 = -1.0,
    right_blend_v: f32 = -1.0,
    bottom_blend_u: f32 = -1.0,
    bottom_blend_v: f32 = -1.0,
    props: ?*const game_data.GroundProps = null,
    sinking: bool = false,
    full_occupy: bool = false,
    occupy_square: bool = false,
    enemy_occupy_square: bool = false,
    is_enemy: bool = false,
    protect_from_ground_damage: bool = false,
    protect_from_sink: bool = false,
    obj_id: i32 = -1,
    has_wall: bool = false,
    u_offset: f32 = 0,
    v_offset: f32 = 0,

    pub fn updateBlends(square: *Square) void {
        if (square.tile_type == 0xFFFF or square.tile_type == 0xFF)
            return;

        const x: u32 = @intFromFloat(square.x);
        const y: u32 = @intFromFloat(square.y);
        const props = game_data.ground_type_to_props.get(square.tile_type);
        if (props == null)
            return;

        const current_prio = props.?.blend_prio;

        if (x > 0 and validPos(x - 1, y)) {
            if (squares.getPtr(x - 1 + y * width)) |left_sq| {
                if (left_sq.tile_type != 0xFF and left_sq.props != null and !left_sq.has_wall) {
                    const left_blend_prio = left_sq.props.?.blend_prio;
                    if (left_blend_prio > current_prio) {
                        square.left_blend_u = left_sq.atlas_data.tex_u;
                        square.left_blend_v = left_sq.atlas_data.tex_v;
                        left_sq.right_blend_u = -1.0;
                        left_sq.right_blend_v = -1.0;
                    } else if (left_blend_prio < current_prio) {
                        left_sq.right_blend_u = square.atlas_data.tex_u;
                        left_sq.right_blend_v = square.atlas_data.tex_v;
                        square.left_blend_u = -1.0;
                        square.left_blend_v = -1.0;
                    } else {
                        square.left_blend_u = -1.0;
                        square.left_blend_v = -1.0;
                        left_sq.right_blend_u = -1.0;
                        left_sq.right_blend_v = -1.0;
                    }
                }
            }
        }

        if (y > 0 and validPos(x, y - 1)) {
            if (squares.getPtr(x + (y - 1) * width)) |top_sq| {
                if (top_sq.tile_type != 0xFF and top_sq.props != null and !top_sq.has_wall) {
                    const top_blend_prio = top_sq.props.?.blend_prio;
                    if (top_blend_prio > current_prio) {
                        square.top_blend_u = top_sq.atlas_data.tex_u;
                        square.top_blend_v = top_sq.atlas_data.tex_v;
                        top_sq.bottom_blend_u = -1.0;
                        top_sq.bottom_blend_v = -1.0;
                    } else if (top_blend_prio < current_prio) {
                        top_sq.bottom_blend_u = square.atlas_data.tex_u;
                        top_sq.bottom_blend_v = square.atlas_data.tex_v;
                        square.top_blend_u = -1.0;
                        square.top_blend_v = -1.0;
                    } else {
                        square.top_blend_u = -1.0;
                        square.top_blend_v = -1.0;
                        top_sq.bottom_blend_u = -1.0;
                        top_sq.bottom_blend_v = -1.0;
                    }
                }
            }
        }

        if (x < std.math.maxInt(u32) and validPos(x + 1, y)) {
            if (squares.getPtr(x + 1 + y * width)) |right_sq| {
                if (right_sq.tile_type != 0xFF and right_sq.props != null and !right_sq.has_wall) {
                    const right_blend_prio = right_sq.props.?.blend_prio;
                    if (right_blend_prio > current_prio) {
                        square.right_blend_u = right_sq.atlas_data.tex_u;
                        square.right_blend_v = right_sq.atlas_data.tex_v;
                        right_sq.left_blend_u = -1.0;
                        right_sq.left_blend_v = -1.0;
                    } else if (right_blend_prio < current_prio) {
                        right_sq.left_blend_u = square.atlas_data.tex_u;
                        right_sq.left_blend_v = square.atlas_data.tex_v;
                        square.right_blend_u = -1.0;
                        square.right_blend_v = -1.0;
                    } else {
                        square.right_blend_u = -1.0;
                        square.right_blend_v = -1.0;
                        right_sq.left_blend_u = -1.0;
                        right_sq.left_blend_v = -1.0;
                    }
                }
            }
        }

        if (y < std.math.maxInt(u32) and validPos(x, y + 1)) {
            if (squares.getPtr(x + (y + 1) * width)) |bottom_sq| {
                if (bottom_sq.tile_type != 0xFF and bottom_sq.props != null and !bottom_sq.has_wall) {
                    const bottom_blend_prio = bottom_sq.props.?.blend_prio;
                    if (bottom_blend_prio > current_prio) {
                        square.bottom_blend_u = bottom_sq.atlas_data.tex_u;
                        square.bottom_blend_v = bottom_sq.atlas_data.tex_v;
                        bottom_sq.top_blend_u = -1.0;
                        bottom_sq.top_blend_v = -1.0;
                    } else if (bottom_blend_prio < current_prio) {
                        bottom_sq.top_blend_u = square.atlas_data.tex_u;
                        bottom_sq.top_blend_v = square.atlas_data.tex_v;
                        square.bottom_blend_u = -1.0;
                        square.bottom_blend_v = -1.0;
                    } else {
                        square.bottom_blend_u = -1.0;
                        square.bottom_blend_v = -1.0;
                        bottom_sq.top_blend_u = -1.0;
                        bottom_sq.top_blend_v = -1.0;
                    }
                }
            }
        }
    }
};

pub const GameObject = struct {
    obj_id: i32 = -1,
    obj_type: u16 = 0,
    dead: bool = false,
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,
    screen_x: f32 = 0.0,
    screen_y: f32 = 0.0,
    alpha: f32 = 1.0,
    name: ?[]u8 = null,
    name_text_data: ?element.TextData = null,
    size: f32 = 0,
    max_hp: i32 = 0,
    hp: i32 = 0,
    defense: i16 = 0,
    resistance: i16 = 0,
    condition: utils.Condition = .{},
    tex_1: i32 = 0,
    tex_2: i32 = 0,
    alt_texture_index: u16 = 0,
    inventory: [9]u16 = [_]u16{std.math.maxInt(u16)} ** 9,
    owner_acc_id: i32 = -1,
    last_merch_type: u16 = 0,
    merchant_obj_type: u16 = 0,
    merchant_rem_count: i8 = 0,
    sellable_price: u16 = 0,
    sellable_currency: game_data.Currency = .gold,
    portal_active: bool = false,
    owner_account_id: i32 = 0,
    anim_data: ?assets.AnimEnemyData = null,
    atlas_data: assets.AtlasData = assets.AtlasData.fromRaw(0, 0, 0, 0),
    top_atlas_data: assets.AtlasData = assets.AtlasData.fromRaw(0, 0, 0, 0),
    move_angle: f32 = std.math.nan(f32),
    move_step: f32 = 0.0,
    target_x: f32 = 0.0,
    target_y: f32 = 0.0,
    target_x_dir: f32 = 0.0,
    target_y_dir: f32 = 0.0,
    inv_dist: f32 = 0.0,
    facing: f32 = std.math.nan(f32),
    attack_start: i64 = 0,
    attack_angle: f32 = 0.0,
    dir: u8 = assets.left_dir,
    draw_on_ground: bool = false,
    is_wall: bool = false,
    is_enemy: bool = false,
    light_color: u32 = std.math.maxInt(u32),
    light_intensity: f32 = 0.1,
    light_radius: f32 = 1.0,
    light_pulse: f32 = 0.0,
    light_pulse_speed: f32 = 1.0,
    class: game_data.ClassType = .game_object,
    show_name: bool = false,
    hit_sound: []const u8 = &[0]u8{},
    death_sound: []const u8 = &[0]u8{},
    action: u8 = 0,
    float_period: f32 = 0.0,
    full_occupy: bool = false,
    occupy_square: bool = false,
    enemy_occupy_square: bool = false,
    colors: []u32 = &[0]u32{},
    anim_sector: u8 = 0,
    anim_index: u8 = 0,
    _disposed: bool = false,

    pub inline fn addToMap(self: *GameObject, allocator: std.mem.Allocator) void {
        const floor_y: u32 = @intFromFloat(@floor(self.y));
        const floor_x: u32 = @intFromFloat(@floor(self.x));

        var _props: ?game_data.ObjProps = null;
        var default_name: []const u8 = "";
        if (game_data.obj_type_to_props.get(self.obj_type)) |props| {
            _props = props;
            self.size = props.getSize();
            self.draw_on_ground = props.draw_on_ground;
            self.light_color = props.light_color;
            self.light_intensity = props.light_intensity;
            self.light_radius = props.light_radius;
            self.light_pulse = props.light_pulse;
            self.light_pulse_speed = props.light_pulse_speed;
            self.is_enemy = props.is_enemy;
            self.show_name = props.show_name;
            default_name = props.display_id;
            self.hit_sound = props.hit_sound;
            self.death_sound = props.death_sound;
            self.full_occupy = props.full_occupy;
            self.occupy_square = props.occupy_square;
            self.enemy_occupy_square = props.enemy_occupy_square;

            for (props.show_effects) |eff| {
                if (eff.effect == .ring) {
                    var effect = particles.RingEffect{
                        .start_x = self.x,
                        .start_y = self.y,
                        .color = eff.color,
                        .cooldown = eff.cooldown,
                        .radius = eff.radius,
                    };
                    effect.addToMap();
                }
            }

            if (validPos(floor_x, floor_y)) {
                if (squares.getPtr(floor_y * width + floor_x)) |square| {
                    square.obj_id = self.obj_id;
                    square.enemy_occupy_square = props.enemy_occupy_square;
                    square.occupy_square = props.occupy_square;
                    square.full_occupy = props.full_occupy;
                    square.is_enemy = props.is_enemy;
                    square.protect_from_sink = props.protect_from_sink;
                    square.protect_from_ground_damage = props.protect_from_ground_damage;
                }
            }
        }

        texParse: {
            if (game_data.obj_type_to_tex_data.get(self.obj_type)) |tex_list| {
                if (tex_list.len == 0) {
                    std.log.err("Object with type {d} has an empty texture list, parsing failed", .{self.obj_type});
                    break :texParse;
                }

                const tex = tex_list[@as(usize, @intCast(self.obj_id)) % tex_list.len];

                if (tex.animated) {
                    if (assets.anim_enemies.get(tex.sheet)) |anim_data| {
                        self.anim_data = anim_data[tex.index];
                    } else {
                        std.log.err("Could not find anim sheet {s} for object with type {d}. Using error texture", .{ tex.sheet, self.obj_type });
                        self.anim_data = assets.error_data_enemy;
                    }

                    self.colors = assets.atlas_to_color_data.get(@bitCast(self.anim_data.?.walk_anims[0][0])) orelse blk: {
                        std.log.err("Could not parse color data for object with id {d}. Setting it to empty", .{self.obj_id});
                        break :blk &[0]u32{};
                    };
                } else {
                    if (assets.atlas_data.get(tex.sheet)) |data| {
                        self.atlas_data = data[tex.index];
                    } else {
                        std.log.err("Could not find sheet {s} for object with type 0x{x}. Using error texture", .{ tex.sheet, self.obj_type });
                        self.atlas_data = assets.error_data;
                    }

                    self.colors = assets.atlas_to_color_data.get(@bitCast(self.atlas_data)) orelse blk: {
                        std.log.err("Could not parse color data for object with id {d}. Setting it to empty", .{self.obj_id});
                        break :blk &[0]u32{};
                    };

                    if (_props != null and _props.?.static and _props.?.occupy_square) {
                        if (assets.dominant_color_data.get(tex.sheet)) |color_data| {
                            const color = color_data[tex.index];
                            const base_data_idx: usize = @intCast(floor_y * minimap.num_components * minimap.width + floor_x * minimap.num_components);
                            minimap.data[base_data_idx] = color.r;
                            minimap.data[base_data_idx + 1] = color.g;
                            minimap.data[base_data_idx + 2] = color.b;
                            minimap.data[base_data_idx + 3] = color.a;

                            main.minimap_update_min_x = @min(main.minimap_update_min_x, floor_x);
                            main.minimap_update_max_x = @max(main.minimap_update_max_x, floor_x);
                            main.minimap_update_min_y = @min(main.minimap_update_min_y, floor_y);
                            main.minimap_update_max_y = @max(main.minimap_update_max_y, floor_y);
                        }
                    }

                    if (self.draw_on_ground or game_data.obj_type_to_class.get(self.obj_type) == .wall) {
                        self.atlas_data.removePadding();
                    }
                }
            } else {
                std.log.err("Could not find texture data for obj {d}", .{self.obj_type});
            }
        }

        topTexParse: {
            if (game_data.obj_type_to_top_tex_data.get(self.obj_type)) |top_tex_list| {
                if (top_tex_list.len == 0) {
                    std.log.err("Object with type {d} has an empty top texture list, parsing failed", .{self.obj_type});
                    break :topTexParse;
                }

                const tex = top_tex_list[@as(usize, @intCast(self.obj_id)) % top_tex_list.len];
                if (assets.atlas_data.get(tex.sheet)) |data| {
                    var top_data = data[tex.index];
                    top_data.removePadding();
                    self.top_atlas_data = top_data;
                } else {
                    std.log.err("Could not find top sheet {s} for object with type {d}. Using error texture", .{ tex.sheet, self.obj_type });
                    self.top_atlas_data = assets.error_data;
                }
            }
        }

        if (game_data.obj_type_to_class.get(self.obj_type)) |class_props| {
            self.is_wall = class_props == .wall;
            if (self.is_wall and validPos(floor_x, floor_y)) {
                self.x = @floor(self.x) + 0.5;
                self.y = @floor(self.y) + 0.5;
                self.move_angle = std.math.nan(f32);

                const w: u32 = @intCast(width);
                if (squares.getPtr(floor_y * w + floor_x)) |square| {
                    square.has_wall = true;
                    square.updateBlends();
                }
            }

            if (class_props == .container) {
                assets.playSfx("loot_appears");
            }
        }

        self.class = game_data.obj_type_to_class.get(self.obj_type) orelse .game_object;

        if (systems.screen == .editor) {
            if (systems.screen.editor.active_layer == .ground) {
                if (game_data.ground_type_to_tex_data.get(self.obj_type)) |tex_list| {
                    if (tex_list.len == 0) {
                        self.atlas_data = assets.error_data;
                    } else {
                        const tex = if (tex_list.len == 1) tex_list[0] else tex_list[utils.rng.next() % tex_list.len];
                        if (assets.atlas_data.get(tex.sheet)) |data| {
                            var ground_data = data[tex.index];
                            ground_data.removePadding();
                            self.atlas_data = ground_data;
                        } else {
                            self.atlas_data = assets.error_data;
                        }
                    }
                }
                self.draw_on_ground = true;
            }
        }

        if (self.show_name and self.name_text_data == null) {
            self.name_text_data = element.TextData{
                .text = if (self.name) |obj_name| obj_name else default_name,
                .text_type = .bold,
                .size = 16,
            };
            self.name_text_data.?.recalculateAttributes(allocator);
        }

        add_lock.lock();
        defer add_lock.unlock();
        entities_to_add.append(.{ .object = self.* }) catch |e| {
            std.log.err("Could not add object to map (obj_id={d}, obj_type={d}, x={d}, y={d}): {any}", .{ self.obj_id, self.obj_type, self.x, self.y, e });
        };
    }

    pub fn takeDamage(
        self: *GameObject,
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

            assets.playSfx(self.death_sound);
            var effect = particles.ExplosionEffect{
                .x = self.x,
                .y = self.y,
                .colors = self.colors,
                .size = self.size,
                .amount = 30,
            };
            effect.addToMap();
        } else {
            assets.playSfx(self.hit_sound);

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
                        std.log.err("Allocation for condition text \"{s}\" failed: {any}", .{ cond_str, e });
                    };
                }
            }
        }

        if (phys_dmg > 0 or magic_dmg > 0 or true_dmg > 0) {
            showDamageText(phys_dmg, magic_dmg, true_dmg, self.obj_id, allocator);
        }
    }

    pub fn update(self: *GameObject, time: i64, dt: f32) void {
        // todo: clean this up, reuse
        const attack_period: i64 = 0.3 * std.time.us_per_s;
        if (time < self.attack_start + attack_period) {
            const time_dt: f32 = @floatFromInt(time - self.attack_start);
            self.float_period = @mod(time_dt, attack_period) / attack_period;
            self.facing = self.attack_angle;
            self.action = assets.attack_action;
        } else if (!std.math.isNan(self.move_angle)) {
            const move_period: i64 = 0.4 * std.time.us_per_s;
            const float_time: f32 = @floatFromInt(time);
            self.float_period = @mod(float_time, move_period) / move_period;
            self.facing = self.move_angle;
            self.action = assets.walk_action;
        } else {
            self.float_period = 0;
            self.action = assets.stand_action;
        }

        const screen_pos = camera.rotateAroundCamera(self.x, self.y);
        const size = camera.size_mult * camera.scale * self.size;

        const angle = if (std.math.isNan(self.facing))
            0.0
        else
            utils.halfBound(self.facing) / (std.math.pi / 4.0);

        const sec = switch (@as(u8, @intFromFloat(@round(angle + 4))) % 8) {
            0, 1, 6, 7 => assets.left_dir,
            2, 3, 4, 5 => assets.right_dir,
            else => unreachable,
        };
        const anim_idx: u8 = @intFromFloat(@max(0, @min(0.99999, self.float_period)) * 2.0);

        self.anim_sector = sec;
        self.anim_index = anim_idx;

        var atlas_data = self.atlas_data;
        if (self.anim_data) |anim_data| {
            atlas_data = switch (self.action) {
                assets.walk_action => anim_data.walk_anims[sec][1 + anim_idx],
                assets.attack_action => anim_data.attack_anims[sec][anim_idx],
                assets.stand_action => anim_data.walk_anims[sec][0],
                else => unreachable,
            };
        }

        const h = atlas_data.texHRaw() * size;
        self.screen_y = screen_pos.y + self.z * -camera.px_per_tile - (h - size * assets.padding) - 10;
        self.screen_x = screen_pos.x;

        if (!self.is_wall and !std.math.isNan(self.move_angle) and self.move_step > 0.0) {
            var next_x = self.x + dt * self.move_step * @cos(self.move_angle);
            var next_y = self.y + dt * self.move_step * @sin(self.move_angle);

            if (self.target_x_dir == -1) {
                if (self.target_x > next_x)
                    next_x = self.x;
            } else {
                if (self.target_x < next_x)
                    next_x = self.x;
            }

            if (self.target_y_dir == -1) {
                if (self.target_y > next_y)
                    next_y = self.y;
            } else {
                if (self.target_y < next_y)
                    next_y = self.y;
            }

            self.x = next_x;
            self.y = next_y;
        }

        merchantBlock: {
            if (self.last_merch_type == self.merchant_obj_type)
                break :merchantBlock;

            // this may not be good idea for merchants every frame lols
            // todo move it into a fn call that will only be set on merchant_obj_type set
            // this is temporary

            if (game_data.obj_type_to_tex_data.get(self.merchant_obj_type)) |tex_list| {
                if (tex_list.len == 0) {
                    std.log.err("Merchant with type {d} has an empty texture list, parsing failed", .{self.merchant_obj_type});
                    break :merchantBlock;
                }

                const tex = tex_list[@as(usize, @intCast(self.obj_id)) % tex_list.len];
                if (assets.atlas_data.get(tex.sheet)) |data| {
                    self.atlas_data = data[tex.index];
                } else {
                    std.log.err("Could not find sheet {s} for merchant with type 0x{x}. Using error texture", .{ tex.sheet, self.merchant_obj_type });
                    self.atlas_data = assets.error_data;
                }
            }

            self.last_merch_type = self.merchant_obj_type;
        }
    }
};

pub const Player = struct {
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
    slot_types: [22]game_data.ItemType = [_]game_data.ItemType{.any} ** 22,
    tier: u8 = 0,
    tier_xp: i32 = 0,
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
    target_x_dir: f32 = 0.0,
    target_y_dir: f32 = 0.0,
    facing: f32 = std.math.nan(f32),
    walk_speed_multiplier: f32 = 1.0,
    light_color: u32 = std.math.maxInt(u32),
    light_intensity: f32 = 0.1,
    light_radius: f32 = 1.0,
    light_pulse: f32 = 0.0,
    light_pulse_speed: f32 = 1.0,
    last_ground_damage_time: i64 = -1,
    anim_data: assets.AnimPlayerData = undefined,
    move_multiplier: f32 = 1.0,
    sink_level: f32 = 0,
    hit_sound: []const u8 = &[0]u8{},
    death_sound: []const u8 = &[0]u8{},
    action: u8 = 0,
    float_period: f32 = 0.0,
    colors: []u32 = &[0]u32{},
    next_ability_attack_time: i64 = -1,
    mp_zeroed: bool = false,
    x_dir: f32 = 0.0,
    y_dir: f32 = 0.0,
    anim_sector: u8 = 0,
    anim_index: u8 = 0,
    class_name: []const u8 = "",
    ability_use_times: [4]i64 = [_]i64{-1} ** 4,
    ability_data: std.ArrayList(u8) = undefined,
    _disposed: bool = false,

    pub fn onMove(self: *Player) void {
        if (getSquare(self.x, self.y)) |square| {
            if (square.props == null)
                return;

            if (square.props.?.sinking) {
                self.sink_level = @min(self.sink_level + 1, max_sink_level);
                self.move_multiplier = 0.1 + (1 - self.sink_level / max_sink_level) * (square.props.?.speed - 0.1);
            } else {
                self.sink_level = 0;
                self.move_multiplier = square.props.?.speed;
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
                std.log.err("Could not find anim sheet {s} for player with type {d}. Using error texture", .{ tex.sheet, self.obj_type });
                self.anim_data = assets.error_data_player;
            }

            self.colors = assets.atlas_to_color_data.get(@bitCast(self.anim_data.walk_anims[0][0])) orelse blk: {
                std.log.err("Could not parse color data for player with id {d}. Setting it to empty", .{self.obj_id});
                break :blk &[0]u32{};
            };
        }

        const props = game_data.obj_type_to_props.get(self.obj_type);
        if (props) |obj_props| {
            self.size = obj_props.getSize();
            self.light_color = obj_props.light_color;
            self.light_intensity = obj_props.light_intensity;
            self.light_radius = obj_props.light_radius;
            self.light_pulse = obj_props.light_pulse;
            self.light_pulse_speed = obj_props.light_pulse_speed;
            self.hit_sound = obj_props.hit_sound;
            self.death_sound = obj_props.death_sound;
        }

        var default_name: []const u8 = "";
        if (game_data.classes.get(self.obj_type)) |class| {
            self.slot_types = class.slot_types[0..22].*;
            default_name = class.name;
            self.class_name = class.name;
        }

        if (self.name_text_data == null) {
            self.name_text_data = element.TextData{
                // name could have been set (usually is) before adding to map
                .text = if (self.name) |player_name| player_name else default_name,
                .text_type = .bold,
                .size = 16,
                .color = 0xFCDF00,
                .max_width = 200,
            };
            self.name_text_data.?.recalculateAttributes(allocator);
        }

        setRpc: {
            if (!rpc_set) {
                if (game_data.classes.get(self.obj_type)) |char_class| {
                    const presence = rpc.Packet.Presence{
                        .assets = .{
                            .large_image = rpc.Packet.ArrayString(256).create("logo"),
                            .large_text = rpc.Packet.ArrayString(128).create(main.version_text),
                            .small_image = rpc.Packet.ArrayString(256).create(char_class.rpc_name),
                            .small_text = rpc.Packet.ArrayString(128).createFromFormat("Tier {s} {s}", .{ utils.toRoman(self.tier), char_class.name }) catch {
                                std.log.err("Setting Discord RPC failed, small_text buffer was out of space", .{});
                                break :setRpc;
                            },
                        },
                        .state = rpc.Packet.ArrayString(128).createFromFormat("In {s}", .{name}) catch {
                            std.log.err("Setting Discord RPC failed, state buffer was out of space", .{});
                            break :setRpc;
                        },
                        .timestamps = .{
                            .start = main.rpc_start,
                        },
                    };
                    main.rpc_client.setPresence(presence) catch |e| {
                        std.log.err("Setting Discord RPC failed: {any}", .{e});
                    };
                    rpc_set = true;
                } else {
                    std.log.err("Setting Discord RPC failed, CharacterClass was missing", .{});
                }
            }
        }

        add_lock.lock();
        defer add_lock.unlock();
        entities_to_add.append(.{ .player = self.* }) catch |e| {
            std.log.err("Could not add player to map (obj_id={d}, obj_type={d}, x={d}, y={d}): {any}", .{ self.obj_id, self.obj_type, self.x, self.y, e });
        };
    }

    pub fn useAbility(self: *Player, idx: u8) void {
        if (game_data.classes.get(self.obj_type)) |class| {
            const abil_props = switch (idx) {
                0 => class.ability_1,
                1 => class.ability_2,
                2 => class.ability_3,
                3 => class.ultimate_ability,
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
                if (class.projs.len <= 0) {
                    std.log.err("Attempted to cast Anomalous Burst without any projectiles attached to the player (type: 0x{x})", .{self.obj_type});
                    return;
                }

                const attack_angle = std.math.atan2(f32, input.mouse_y, input.mouse_x);
                const num_projs: u16 = @intCast(6 + @divFloor(self.speed, 30));
                const arc_gap = std.math.degreesToRadians(f32, 24);
                const float_str: f32 = @floatFromInt(self.strength);

                const attack_angle_left = attack_angle - std.math.phi;
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
                        .props = class.projs[0],
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

                const attack_angle_right = attack_angle + std.math.phi;
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
                        .props = class.projs[0],
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
                    std.log.err("Writing to ability data buffer failed: {any}", .{e});
                    return;
                };
            } else if (std.mem.eql(u8, abil_props.name, "Possession")) {
                self.ability_data.writer().writeAll(&std.mem.toBytes(@as(f32, -1))) catch |e| {
                    std.log.err("Writing to ability data buffer failed: {any}", .{e});
                    return;
                };
            }

            network.queuePacket(.{ .use_ability = .{ .time = main.current_time, .ability_type = idx, .data = self.ability_data.items } });
        }
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

            network.queuePacket(.{
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

            assets.playSfx(self.death_sound);
            var effect = particles.ExplosionEffect{
                .x = self.x,
                .y = self.y,
                .colors = self.colors,
                .size = self.size,
                .amount = 30,
            };
            effect.addToMap();
        } else {
            assets.playSfx(self.hit_sound);

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
                        std.log.err("Allocation for condition text \"{s}\" failed: {any}", .{ cond_str, e });
                    };
                }
            }
        }

        if (phys_dmg > 0 or magic_dmg > 0 or true_dmg > 0) {
            showDamageText(phys_dmg, magic_dmg, true_dmg, self.obj_id, allocator);
        }
    }

    pub fn update(self: *Player, time: i64, dt: f32, allocator: std.mem.Allocator) void {
        if (time < self.attack_start + self.attack_period) {
            const time_dt: f32 = @floatFromInt(time - self.attack_start);
            const float_period: f32 = @floatFromInt(self.attack_period);
            self.float_period = @mod(time_dt, float_period) / float_period;
            self.facing = self.attack_angle + camera.angle;
            self.action = assets.attack_action;
        } else if (self.x_dir != 0.0 or self.y_dir != 0.0) {
            const walk_period = 3.5 / self.moveSpeedMultiplier();
            const float_time: f32 = @floatFromInt(time);
            self.float_period = @mod(float_time, walk_period) / walk_period;
            self.facing = std.math.atan2(f32, self.y_dir, self.x_dir);
            self.action = assets.walk_action;
        } else {
            self.float_period = 0.0;
            self.action = assets.stand_action;
        }

        const size = camera.size_mult * camera.scale * self.size;

        const pi_div_4 = std.math.pi / 4.0;
        const angle = if (std.math.isNan(self.facing))
            utils.halfBound(camera.angle) / pi_div_4
        else
            utils.halfBound(self.facing - camera.angle) / pi_div_4;

        const sec = switch (@as(u8, @intFromFloat(@round(angle + 4))) % 8) {
            0, 7 => assets.left_dir,
            1, 2 => assets.up_dir,
            3, 4 => assets.right_dir,
            5, 6 => assets.down_dir,
            else => unreachable,
        };

        const anim_idx: u8 = @intFromFloat(@max(0, @min(0.99999, self.float_period)) * 2.0);
        var atlas_data = switch (self.action) {
            assets.walk_action => self.anim_data.walk_anims[sec][1 + anim_idx],
            assets.attack_action => self.anim_data.attack_anims[sec][anim_idx],
            assets.stand_action => self.anim_data.walk_anims[sec][0],
            else => unreachable,
        };

        self.anim_sector = sec;
        self.anim_index = anim_idx;

        const screen_pos = camera.rotateAroundCamera(self.x, self.y);
        const h = atlas_data.texHRaw() * size;

        self.screen_x = screen_pos.x;
        self.screen_y = screen_pos.y + self.z * -camera.px_per_tile - (h - size * assets.padding) - 30; // account for name

        if (self.obj_id == local_player_id) {
            const floor_x: u32 = @intFromFloat(@floor(self.x));
            const floor_y: u32 = @intFromFloat(@floor(self.y));

            // janky editor movement

            if (systems.screen == .editor) {
                if (!std.math.isNan(self.move_angle)) {
                    const move_angle = camera.angle + self.move_angle;
                    const move_speed = self.moveSpeedMultiplier();
                    const new_x = self.x + move_speed * @cos(move_angle) * dt;
                    const new_y = self.y + move_speed * @sin(move_angle) * dt;

                    self.x = @max(0, @min(new_x, @as(f32, @floatFromInt(width - 1))));
                    self.y = @max(0, @min(new_y, @as(f32, @floatFromInt(height - 1))));
                }
            } else {
                if (validPos(floor_x, floor_y)) {
                    const current_square = squares.get(floor_y * width + floor_x);
                    if (current_square != null) {
                        if (current_square.?.props) |props| {
                            const slide_amount = props.slide_amount;
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

                            if (props.push) {
                                self.x_dir -= props.anim_dx / 1000.0;
                                self.y_dir -= props.anim_dy / 1000.0;
                            }
                        }
                    }

                    const next_x = self.x + self.x_dir * dt;
                    const next_y = self.y + self.y_dir * dt;

                    modifyMove(self, next_x, next_y, &self.x, &self.y);
                }
            }

            if (systems.screen != .editor and !self.condition.invulnerable and time - self.last_ground_damage_time >= 0.5 * std.time.us_per_s) {
                if (validPos(floor_x, floor_y)) {
                    const square = squares.get(floor_y * width + floor_x);
                    if (square != null) {
                        if (square.?.props) |props| {
                            const total_damage = props.physical_damage + props.magic_damage + props.true_damage;
                            if (total_damage > 0 and !square.?.protect_from_ground_damage) {
                                network.queuePacket(.{ .ground_damage = .{ .time = time, .x = self.x, .y = self.y } });
                                self.takeDamage(
                                    @intCast(props.physical_damage),
                                    @intCast(props.magic_damage),
                                    @intCast(props.true_damage),
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
            }

            return;
        }

        if (!std.math.isNan(self.move_angle) and self.move_step > 0.0) {
            var next_x = self.x + dt * self.move_step * @cos(self.move_angle);
            var next_y = self.y + dt * self.move_step * @sin(self.move_angle);

            if (self.target_x_dir == -1) {
                if (self.target_x > next_x)
                    next_x = self.x;
            } else {
                if (self.target_x < next_x)
                    next_x = self.x;
            }

            if (self.target_y_dir == -1) {
                if (self.target_y > next_y)
                    next_y = self.y;
            } else {
                if (self.target_y < next_y)
                    next_y = self.y;
            }

            self.x = next_x;
            self.y = next_y;
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
        if (getSquare(x, y)) |square| {
            const walkable = square.props == null or !square.props.?.no_walk;
            const not_occupied = !square.occupy_square;
            return square.tile_type != 0xFFFF and square.tile_type != 0xFF and walkable and not_occupied;
        } else return false;
    }

    fn isFullOccupy(x: f32, y: f32) bool {
        if (getSquare(x, y)) |square| {
            return square.full_occupy;
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

pub const Projectile = struct {
    var next_obj_id: i32 = 0x7F000000;

    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,
    screen_x: f32 = 0.0,
    screen_y: f32 = 0.0,
    size: f32 = 1.0,
    obj_id: i32 = 0,
    atlas_data: assets.AtlasData = assets.AtlasData.fromRaw(0, 0, 0, 0),
    start_time: i64 = 0,
    angle: f32 = 0.0,
    visual_angle: f32 = 0.0,
    total_angle_change: f32 = 0.0,
    zero_vel_dist: f32 = -1.0,
    start_x: f32 = 0.0,
    start_y: f32 = 0.0,
    last_deflect: f32 = 0.0,
    bullet_id: u8 = 0,
    owner_id: i32 = 0,
    damage_players: bool = false,
    physical_damage: i32 = 0,
    magic_damage: i32 = 0,
    true_damage: i32 = 0,
    penetration: i32 = 0,
    piercing: i32 = 0,
    props: game_data.ProjProps,
    last_hit_check: i64 = 0,
    colors: []u32 = &[0]u32{},
    hit_list: std.AutoHashMap(i32, void) = undefined,
    _disposed: bool = false,

    pub inline fn addToMap(self: *Projectile) void {
        self.hit_list = std.AutoHashMap(i32, void).init(main._allocator);
        self.start_time = main.current_time;

        const tex_list = self.props.texture_data;
        const tex = tex_list[@as(usize, @intCast(self.obj_id)) % tex_list.len];
        if (assets.atlas_data.get(tex.sheet)) |data| {
            self.atlas_data = data[tex.index];
        } else {
            std.log.err("Could not find sheet {s} for proj with id {d}. Using error texture", .{ tex.sheet, self.obj_id });
            self.atlas_data = assets.error_data;
        }

        self.colors = assets.atlas_to_color_data.get(@bitCast(self.atlas_data)) orelse blk: {
            std.log.err("Could not parse color data for projectile with id {d}. Setting it to empty", .{self.obj_id});
            break :blk &[0]u32{};
        };

        self.obj_id = Projectile.next_obj_id + 1;
        Projectile.next_obj_id += 1;
        if (Projectile.next_obj_id == std.math.maxInt(i32))
            Projectile.next_obj_id = 0x7F000000;

        add_lock.lock();
        defer add_lock.unlock();
        entities_to_add.append(.{ .projectile = self.* }) catch |e| {
            std.log.err("Could not add projectile to map (obj_id={d}, x={d}, y={d}): {any}", .{ self.obj_id, self.x, self.y, e });
        };
    }

    // We abuse the fact that the entities array is y-sorted in the below target finding functions.
    // These functions have to be reimagined if the array ever ceases to be y-sorted

    fn findTargetPlayer(x: f32, y: f32, radius: f32, start_idx: usize) ?*Player {
        var min_dist = radius * radius;
        var target: ?*Player = null;

        const items = entities.items;
        loopBelow: for (0..start_idx) |i| {
            const idx = start_idx - i;
            if (items[idx] == .player) {
                const player = items[idx].player;
                if (@abs(y - player.y) > radius)
                    break :loopBelow;

                if (!player.condition.dead) {
                    const dist_sqr = utils.distSqr(player.x, player.y, x, y);
                    if (dist_sqr < min_dist) {
                        min_dist = dist_sqr;
                        target = &items[idx].player;
                    }
                }
            }
        }

        loopAbove: for (start_idx..items.len) |i| {
            if (items[i] == .player) {
                const player = items[i].player;
                if (@abs(y - player.y) > radius)
                    break :loopAbove;

                if (!player.condition.dead) {
                    const dist_sqr = utils.distSqr(player.x, player.y, x, y);
                    if (dist_sqr < min_dist) {
                        min_dist = dist_sqr;
                        target = &items[i].player;
                    }
                }
            }
        }

        return target;
    }

    fn findTargetObject(x: f32, y: f32, radius: f32, start_idx: usize) ?*GameObject {
        var min_dist = radius * radius;
        var target: ?*GameObject = null;

        const items = entities.items;
        loopBelow: for (0..start_idx) |i| {
            const idx = start_idx - i;
            if (items[idx] == .object) {
                const object = items[idx].object;
                if (@abs(y - object.y) > radius)
                    break :loopBelow;

                if ((object.is_enemy or object.occupy_square or object.enemy_occupy_square) and
                    !object.condition.dead)
                {
                    const dist_sqr = utils.distSqr(object.x, object.y, x, y);
                    if (dist_sqr < min_dist) {
                        min_dist = dist_sqr;
                        target = &items[idx].object;
                    }
                }
            }
        }

        loopAbove: for (start_idx..items.len) |i| {
            if (items[i] == .object) {
                const object = items[i].object;
                if (@abs(y - object.y) > radius)
                    break :loopAbove;

                if ((object.is_enemy or object.occupy_square or object.enemy_occupy_square) and
                    !object.condition.dead)
                {
                    const dist_sqr = utils.distSqr(object.x, object.y, x, y);
                    if (dist_sqr < min_dist) {
                        min_dist = dist_sqr;
                        target = &items[i].object;
                    }
                }
            }
        }

        return target;
    }

    fn updatePosition(self: *Projectile, elapsed: i64, dt: f32) void {
        var angle_change: f32 = 0.0;
        if (self.props.angle_change != 0 and elapsed < self.props.angle_change_end and elapsed >= self.props.angle_change_delay) {
            angle_change += dt / std.time.us_per_s * self.props.angle_change;
        }

        if (self.props.angle_change_accel != 0 and elapsed >= self.props.angle_change_accel_delay) {
            const time_in_accel: f32 = @floatFromInt(elapsed - self.props.angle_change_accel_delay);
            angle_change += dt / std.time.us_per_s * self.props.angle_change_accel * time_in_accel / std.time.us_per_s;
        }

        if (angle_change != 0.0) {
            if (self.props.angle_change_clamp != 0) {
                const clamp_dt = self.props.angle_change_clamp - self.total_angle_change;
                const clamped_change = @min(angle_change, clamp_dt);
                self.total_angle_change += clamped_change;
                self.angle += clamped_change;
            } else {
                self.angle += angle_change;
            }
        }

        var dist: f32 = 0.0;
        const uses_zero_vel = self.props.zero_velocity_delay > 0;
        if (!uses_zero_vel or self.props.zero_velocity_delay > elapsed) {
            if (self.props.accel == 0.0 or elapsed < self.props.accel_delay) {
                dist = dt * self.props.speed;
            } else {
                const time_in_accel: f32 = @floatFromInt(elapsed - self.props.accel_delay);
                const accel_dist = dt * ((self.props.speed * 10 * std.time.us_per_s + self.props.accel * time_in_accel / std.time.us_per_s) / (10 * std.time.us_per_s));
                if (self.props.speed_clamp != -1) {
                    dist = accel_dist;
                } else {
                    const clamp_dist = dt * self.props.speed_clamp / (10 * std.time.us_per_s);
                    dist = if (self.props.accel > 0) @min(accel_dist, clamp_dist) else @max(accel_dist, clamp_dist);
                }
            }
        } else {
            if (self.zero_vel_dist == -1.0) {
                self.zero_vel_dist = utils.dist(self.start_x, self.start_y, self.x, self.y);
            }

            self.x = self.start_x + self.zero_vel_dist * @cos(self.angle);
            self.y = self.start_y + self.zero_vel_dist * @sin(self.angle);
            return;
        }

        if (self.props.parametric) {
            const t = @as(f32, @floatFromInt(@divTrunc(elapsed, self.props.lifetime))) * std.math.tau;
            const x = @sin(t) * if (self.bullet_id % 2 == 0) @as(f32, 1.0) else @as(f32, -1.0);
            const y = @sin(2 * t) * if (self.bullet_id % 4 < 2) @as(f32, 1.0) else @as(f32, -1.0);
            self.x += (x * @cos(self.angle) - y * @sin(self.angle)) * self.props.magnitude;
            self.y += (x * @sin(self.angle) + y * @cos(self.angle)) * self.props.magnitude;
        } else {
            if (self.props.boomerang and elapsed > @divFloor(self.props.lifetime, 2))
                dist = -dist;

            self.x += dist * @cos(self.angle);
            self.y += dist * @sin(self.angle);
            if (self.props.amplitude != 0) {
                const phase: f32 = if (self.bullet_id % 2 == 0) 0.0 else std.math.pi;
                const time_ratio: f32 = @as(f32, @floatFromInt(elapsed)) / @as(f32, @floatFromInt(self.props.lifetime));
                const deflection_target = self.props.amplitude * @sin(phase + time_ratio * self.props.frequency * std.math.tau);
                self.x += (deflection_target - self.last_deflect) * @cos(self.angle + std.math.phi);
                self.y += (deflection_target - self.last_deflect) * @sin(self.angle + std.math.phi);
                self.last_deflect = deflection_target;
            }
        }
    }

    pub fn update(self: *Projectile, time: i64, dt: f32, idx: usize, allocator: std.mem.Allocator) bool {
        const elapsed = time - self.start_time;
        if (elapsed >= self.props.lifetime)
            return false;

        const last_x = self.x;
        const last_y = self.y;

        self.updatePosition(elapsed, dt);
        if (self.x < 0 or self.y < 0) {
            if (self.damage_players)
                network.queuePacket(.{ .square_hit = .{
                    .time = time,
                    .bullet_id = self.bullet_id,
                    .obj_id = self.owner_id,
                } });

            return false;
        }

        if (last_x == 0 and last_y == 0) {
            self.visual_angle = self.angle;
        } else {
            const y_dt: f32 = self.y - last_y;
            const x_dt: f32 = self.x - last_x;
            self.visual_angle = std.math.atan2(f32, y_dt, x_dt);
        }

        const floor_y: u32 = @intFromFloat(@floor(self.y));
        const floor_x: u32 = @intFromFloat(@floor(self.x));
        if (validPos(floor_x, floor_y)) {
            if (squares.get(floor_y * width + floor_x)) |square| {
                if (square.tile_type == 0xFF) {
                    if (self.damage_players) {
                        network.queuePacket(.{ .square_hit = .{
                            .time = time,
                            .bullet_id = self.bullet_id,
                            .obj_id = self.owner_id,
                        } });
                    } else {
                        // equivilant to square.obj != null)
                        if (square.obj_id != -1) {
                            var effect = particles.HitEffect{
                                .x = self.x,
                                .y = self.y,
                                .colors = self.colors,
                                .angle = self.angle,
                                .speed = self.props.speed,
                                .size = 1.0,
                                .amount = 3,
                            };
                            effect.addToMap();
                        }
                    }
                    return false;
                }

                if (square.obj_id != -1 and
                    (!square.is_enemy or self.damage_players) and
                    (square.enemy_occupy_square or (!self.props.passes_cover and square.occupy_square)))
                {
                    if (self.damage_players) {
                        network.queuePacket(.{ .other_hit = .{
                            .time = time,
                            .bullet_id = self.bullet_id,
                            .object_id = self.owner_id,
                            .target_id = square.obj_id,
                        } });
                    } else {
                        var effect = particles.HitEffect{
                            .x = self.x,
                            .y = self.y,
                            .colors = self.colors,
                            .angle = self.angle,
                            .speed = self.props.speed,
                            .size = 1.0,
                            .amount = 3,
                        };
                        effect.addToMap();
                    }
                    return false;
                }
            }
        } else {
            if (self.damage_players) {
                network.queuePacket(.{ .square_hit = .{
                    .time = time,
                    .bullet_id = self.bullet_id,
                    .obj_id = self.owner_id,
                } });
            }
        }

        if (time - self.last_hit_check > 16 * std.time.us_per_ms) {
            if (self.damage_players) {
                if (findTargetPlayer(self.x, self.y, 0.57, idx)) |player| {
                    if (self.hit_list.contains(player.obj_id))
                        return true;

                    if (player.condition.invulnerable) {
                        assets.playSfx(player.hit_sound);
                        return false;
                    }

                    if (local_player_id == player.obj_id) {
                        const phys_dmg = physicalDamage(@floatFromInt(self.physical_damage), @floatFromInt(player.defense - self.penetration), player.condition);
                        const magic_dmg = magicDamage(@floatFromInt(self.magic_damage), @floatFromInt(player.resistance - self.piercing), player.condition);
                        const true_dmg: f32 = @floatFromInt(self.true_damage);
                        const dead = @as(f32, @floatFromInt(player.hp)) <= (phys_dmg + magic_dmg + true_dmg);

                        player.takeDamage(
                            @intFromFloat(phys_dmg * player.hit_multiplier),
                            @intFromFloat(magic_dmg * player.hit_multiplier),
                            @intFromFloat(true_dmg * player.hit_multiplier),
                            dead,
                            utils.Condition.fromCondSlice(self.props.effects),
                            self.colors,
                            self.angle,
                            self.props.speed,
                            allocator,
                        );
                        network.queuePacket(.{ .player_hit = .{ .bullet_id = self.bullet_id, .object_id = self.owner_id } });
                    } else if (!self.props.multi_hit) {
                        var effect = particles.HitEffect{
                            .x = self.x,
                            .y = self.y,
                            .colors = self.colors,
                            .angle = self.angle,
                            .speed = self.props.speed,
                            .size = 1.0,
                            .amount = 3,
                        };
                        effect.addToMap();

                        network.queuePacket(.{ .other_hit = .{
                            .time = time,
                            .bullet_id = self.bullet_id,
                            .object_id = self.owner_id,
                            .target_id = player.obj_id,
                        } });
                    } else {
                        std.log.err("Unknown logic for player side of hit logic unexpected branch, todo figure out how to fix this mabye implement send_message check: {s}", .{player.name orelse "Unknown"});
                    }

                    if (self.props.multi_hit) {
                        self.hit_list.put(player.obj_id, {}) catch |e| {
                            std.log.err("failed to add player to hit_list: {any}", .{e});
                        };
                    } else {
                        return false;
                    }
                }
            } else {
                if (findTargetObject(self.x, self.y, 0.57, idx)) |object| {
                    if (self.hit_list.contains(object.obj_id))
                        return true;

                    if (object.condition.invulnerable) {
                        assets.playSfx(object.hit_sound);
                        return false;
                    }

                    if (object.is_enemy) {
                        const phys_dmg = physicalDamage(@floatFromInt(self.physical_damage), @floatFromInt(object.defense - self.penetration), object.condition);
                        const magic_dmg = magicDamage(@floatFromInt(self.magic_damage), @floatFromInt(object.resistance - self.piercing), object.condition);
                        const true_dmg: f32 = @floatFromInt(self.true_damage);
                        const dead = @as(f32, @floatFromInt(object.hp)) <= (phys_dmg + magic_dmg + true_dmg);

                        object.takeDamage(
                            @intFromFloat(phys_dmg),
                            @intFromFloat(magic_dmg),
                            @intFromFloat(true_dmg),
                            dead,
                            utils.Condition.fromCondSlice(self.props.effects),
                            self.colors,
                            self.angle,
                            self.props.speed,
                            allocator,
                        );

                        network.queuePacket(.{ .enemy_hit = .{
                            .time = time,
                            .bullet_id = self.bullet_id,
                            .target_id = object.obj_id,
                            .killed = dead,
                        } });
                    } else if (!self.props.multi_hit) {
                        var effect = particles.HitEffect{
                            .x = self.x,
                            .y = self.y,
                            .colors = self.colors,
                            .angle = self.angle,
                            .speed = self.props.speed,
                            .size = 1.0,
                            .amount = 3,
                        };
                        effect.addToMap();

                        network.queuePacket(.{ .other_hit = .{
                            .time = time,
                            .bullet_id = self.bullet_id,
                            .object_id = self.owner_id,
                            .target_id = object.obj_id,
                        } });
                    }

                    if (self.props.multi_hit) {
                        self.hit_list.put(object.obj_id, {}) catch |e| {
                            std.log.err("failed to add object to hit_list: {any}", .{e});
                        };
                    } else {
                        return false;
                    }
                }
            }
            self.last_hit_check = time;
        }

        return true;
    }
};

pub fn physicalDamage(dmg: f32, defense: f32, condition: utils.Condition) f32 {
    if (dmg == 0)
        return 0;

    var def = defense;
    if (condition.armor_broken) {
        def = 0.0;
    } else if (condition.armored) {
        def *= 2.0;
    }

    if (condition.invulnerable)
        return 0;

    const min = dmg * 0.25;
    return @max(min, dmg - def);
}

pub fn magicDamage(dmg: f32, resistance: f32, condition: utils.Condition) f32 {
    if (dmg == 0)
        return 0;

    var def = resistance;
    if (condition.armor_broken) {
        def = 0.0;
    } else if (condition.armored) {
        def *= 2.0;
    }

    if (condition.invulnerable)
        return 0;

    const min = dmg * 0.25;
    return @max(min, dmg - def);
}

pub fn showDamageText(phys_dmg: i32, magic_dmg: i32, true_dmg: i32, object_id: i32, allocator: std.mem.Allocator) void {
    var delay: i64 = 0;
    if (phys_dmg > 0) {
        element.StatusText.add(.{
            .obj_id = object_id,
            .delay = delay,
            .text_data = .{
                .text = std.fmt.allocPrint(allocator, "-{d}", .{phys_dmg}) catch unreachable,
                .text_type = .bold,
                .size = 22,
                .color = 0xB02020,
            },
            .initial_size = 22,
        }) catch |e| {
            std.log.err("Allocation for physical damage text \"-{d}\" failed: {any}", .{ phys_dmg, e });
        };
        delay += 100;
    }

    if (magic_dmg > 0) {
        element.StatusText.add(.{
            .obj_id = object_id,
            .delay = delay,
            .text_data = .{
                .text = std.fmt.allocPrint(allocator, "-{d}", .{magic_dmg}) catch unreachable,
                .text_type = .bold,
                .size = 22,
                .color = 0x6E15AD,
            },
            .initial_size = 22,
        }) catch |e| {
            std.log.err("Allocation for magic damage text \"-{d}\" failed: {any}", .{ magic_dmg, e });
        };
        delay += 100;
    }

    if (true_dmg > 0) {
        element.StatusText.add(.{
            .obj_id = object_id,
            .delay = delay,
            .text_data = .{
                .text = std.fmt.allocPrint(allocator, "-{d}", .{true_dmg}) catch unreachable,
                .text_type = .bold,
                .size = 22,
                .color = 0xC2C2C2,
            },
            .initial_size = 22,
        }) catch |e| {
            std.log.err("Allocation for true damage text \"-{d}\" failed: {any}", .{ true_dmg, e });
        };
        delay += 100;
    }
}

fn lessThan(_: void, lhs: Entity, rhs: Entity) bool {
    var lhs_sort_val: f32 = 0;
    var rhs_sort_val: f32 = 0;

    switch (lhs) {
        .object => |object| {
            if (object.draw_on_ground) {
                lhs_sort_val = -1;
            } else {
                lhs_sort_val = camera.rotateAroundCamera(object.x, object.y).y + object.z * -camera.px_per_tile;
            }
        },
        .particle_effect => lhs_sort_val = 0,
        .particle => |pt| {
            switch (pt) {
                inline else => |particle| lhs_sort_val = camera.rotateAroundCamera(particle.x, particle.y).y + particle.z * -camera.px_per_tile,
            }
        },
        inline else => |en| {
            lhs_sort_val = camera.rotateAroundCamera(en.x, en.y).y + en.z * -camera.px_per_tile;
        },
    }

    switch (rhs) {
        .object => |object| {
            if (object.draw_on_ground) {
                rhs_sort_val = -1;
            } else {
                rhs_sort_val = camera.rotateAroundCamera(object.x, object.y).y + object.z * -camera.px_per_tile;
            }
        },
        .particle_effect => rhs_sort_val = 0,
        .particle => |pt| {
            switch (pt) {
                inline else => |particle| rhs_sort_val = camera.rotateAroundCamera(particle.x, particle.y).y + particle.z * -camera.px_per_tile,
            }
        },
        inline else => |en| {
            rhs_sort_val = camera.rotateAroundCamera(en.x, en.y).y + en.z * -camera.px_per_tile;
        },
    }

    return lhs_sort_val < rhs_sort_val;
}

pub const Entity = union(enum) {
    player: Player,
    object: GameObject,
    projectile: Projectile,
    particle: particles.Particle,
    particle_effect: particles.ParticleEffect,
};

const day_cycle: i32 = 10 * std.time.us_per_min;
const day_cycle_half: f32 = @as(f32, day_cycle) / 2;

pub var add_lock: std.Thread.Mutex = .{};
pub var object_lock: std.Thread.RwLock = .{};
pub var entities: std.ArrayList(Entity) = undefined;
pub var entities_to_add: std.ArrayList(Entity) = undefined;
pub var move_records: std.ArrayList(network.TimedPosition) = undefined;
pub var local_player_id: i32 = -1;
pub var interactive_id = std.atomic.Value(i32).init(-1);
pub var interactive_type = std.atomic.Value(game_data.ClassType).init(.game_object);
pub var name: []const u8 = "";
pub var seed: u32 = 0;
pub var width: u32 = 0;
pub var height: u32 = 0;
pub var squares: std.AutoHashMap(u32, Square) = undefined;
pub var bg_light_color: u32 = 0;
pub var bg_light_intensity: f32 = 0.0;
pub var day_light_intensity: f32 = 0.0;
pub var night_light_intensity: f32 = 0.0;
pub var server_time_offset: i64 = 0;
pub var last_records_clear_time: i64 = 0;
pub var minimap: zstbi.Image = undefined;
pub var rpc_set = false;
var last_sort: i64 = -1;

pub fn init(allocator: std.mem.Allocator) !void {
    entities = try std.ArrayList(Entity).initCapacity(allocator, 256);
    entities_to_add = try std.ArrayList(Entity).initCapacity(allocator, 128);
    move_records = try std.ArrayList(network.TimedPosition).initCapacity(allocator, 10);
    squares = std.AutoHashMap(u32, Square).init(allocator);

    minimap = try zstbi.Image.createEmpty(4096, 4096, 4, .{});
}

pub fn disposeEntity(allocator: std.mem.Allocator, en: *Entity) void {
    switch (en.*) {
        .object => |*obj| {
            if (obj._disposed)
                return;

            obj._disposed = true;
            if (getSquarePtr(obj.x, obj.y)) |square| {
                if (square.obj_id == obj.obj_id) {
                    square.obj_id = -1;
                    square.enemy_occupy_square = false;
                    square.occupy_square = false;
                    square.full_occupy = false;
                    square.has_wall = false;
                }
            }

            systems.removeAttachedUi(obj.obj_id, allocator);
            if (obj.name) |obj_name|
                allocator.free(obj_name);

            if (obj.name_text_data) |*data| {
                data.deinit(allocator);
            }
        },
        .projectile => |*projectile| {
            if (projectile._disposed)
                return;

            projectile._disposed = true;
            projectile.hit_list.deinit();
        },
        .player => |*player| {
            if (player._disposed)
                return;

            player._disposed = true;
            systems.removeAttachedUi(player.obj_id, allocator);
            player.ability_data.deinit();

            if (player.name_text_data) |*data| {
                data.deinit(allocator);
            }

            if (player.name) |player_name| {
                allocator.free(player_name);
            }
            if (player.guild) |player_guild| {
                allocator.free(player_guild);
            }
        },
        else => {},
    }
}

pub fn dispose(allocator: std.mem.Allocator) void {
    object_lock.lock();
    defer object_lock.unlock();

    local_player_id = -1;
    interactive_id.store(-1, .Release);
    interactive_type.store(.game_object, .Release);
    width = 0;
    height = 0;

    for (entities.items) |*en| {
        disposeEntity(allocator, en);
    }

    for (entities_to_add.items) |*en| {
        disposeEntity(allocator, en);
    }

    squares.clearRetainingCapacity();
    entities.clearRetainingCapacity();
    entities_to_add.clearRetainingCapacity();
    @memset(minimap.data, 0);
}

pub fn deinit(allocator: std.mem.Allocator) void {
    object_lock.lock();
    defer object_lock.unlock();

    for (entities.items) |*en| {
        disposeEntity(allocator, en);
    }

    for (entities_to_add.items) |*en| {
        disposeEntity(allocator, en);
    }

    squares.deinit();
    entities.deinit();
    entities_to_add.deinit();
    move_records.deinit();
    minimap.deinit();

    if (name.len > 0)
        allocator.free(name);
}

pub fn getLightIntensity(time: i64) f32 {
    if (server_time_offset == 0)
        return bg_light_intensity;

    const server_time_clamped: f32 = @floatFromInt(@mod(time + server_time_offset, day_cycle));
    const intensity_delta = day_light_intensity - night_light_intensity;
    if (server_time_clamped <= day_cycle_half) {
        const scale = server_time_clamped / day_cycle_half;
        return night_light_intensity + intensity_delta * scale;
    } else {
        const scale = (server_time_clamped - day_cycle_half) / day_cycle_half;
        return day_light_intensity - intensity_delta * scale;
    }
}

pub fn setWH(w: u32, h: u32) void {
    width = w;
    height = h;

    minimap.deinit();
    minimap = zstbi.Image.createEmpty(w, h, 4, .{}) catch |e| {
        std.debug.panic("Minimap allocation failed: {any}", .{e});
        return;
    };
    main.need_force_update = true;

    const size = @max(w, h);
    const max_zoom: f32 = @floatFromInt(@divFloor(size, 32));
    camera.minimap_zoom = @max(1, @min(max_zoom, camera.minimap_zoom));
}

pub fn localPlayerConst() ?Player {
    if (local_player_id == -1)
        return null;

    if (findEntityConst(local_player_id)) |en| {
        return en.player;
    }

    return null;
}

pub fn localPlayerRef() ?*Player {
    if (local_player_id == -1)
        return null;

    if (findEntityRef(local_player_id)) |en| {
        return &en.player;
    }

    return null;
}

pub fn findEntityConst(obj_id: i32) ?Entity {
    for (entities.items) |en| {
        switch (en) {
            .particle => |pt| {
                switch (pt) {
                    inline else => |particle| {
                        if (particle.obj_id == obj_id)
                            return en;
                    },
                }
            },
            .particle_effect => |pt_eff| {
                switch (pt_eff) {
                    inline else => |effect| {
                        if (effect.obj_id == obj_id)
                            return en;
                    },
                }
            },
            inline else => |obj| {
                if (obj.obj_id == obj_id)
                    return en;
            },
        }
    }

    return null;
}

pub fn findEntityRef(obj_id: i32) ?*Entity {
    for (entities.items) |*en| {
        switch (en.*) {
            .particle => |*pt| {
                switch (pt.*) {
                    inline else => |*particle| {
                        if (particle.obj_id == obj_id)
                            return en;
                    },
                }
            },
            .particle_effect => |*pt_eff| {
                switch (pt_eff.*) {
                    inline else => |*effect| {
                        if (effect.obj_id == obj_id)
                            return en;
                    },
                }
            },
            inline else => |*obj| {
                if (obj.obj_id == obj_id)
                    return en;
            },
        }
    }

    return null;
}

pub fn removeEntity(allocator: std.mem.Allocator, obj_id: i32) void {
    for (entities.items, 0..) |*en, i| {
        switch (en.*) {
            .particle => |*pt| {
                switch (pt.*) {
                    inline else => |*particle| {
                        if (particle.obj_id == obj_id) {
                            disposeEntity(allocator, &entities.items[i]);
                            _ = entities.swapRemove(i);
                            return;
                        }
                    },
                }
            },
            .particle_effect => |*pt_eff| {
                switch (pt_eff.*) {
                    inline else => |*effect| {
                        if (effect.obj_id == obj_id) {
                            disposeEntity(allocator, &entities.items[i]);
                            _ = entities.swapRemove(i);
                            return;
                        }
                    },
                }
            },
            inline else => |obj| {
                if (obj.obj_id == obj_id) {
                    disposeEntity(allocator, &entities.items[i]);
                    _ = entities.swapRemove(i);
                    return;
                }
            },
        }
    }

    std.log.err("Could not remove object with id {d}", .{obj_id});
}

pub fn update(time: i64, dt: i64, allocator: std.mem.Allocator) void {
    object_lock.lock();
    defer object_lock.unlock();

    add_lock.lock();
    entities.appendSlice(entities_to_add.items) catch |e| {
        std.log.err("Adding new entities failed: {any}, returning", .{e});
        return;
    };
    entities_to_add.clearRetainingCapacity();
    add_lock.unlock();

    if (entities.items.len <= 0)
        return;

    interactive_id.store(-1, .Release);
    interactive_type.store(.game_object, .Release);

    const float_dt: f32 = @floatFromInt(dt);

    const cam_x = camera.x.load(.Acquire);
    const cam_y = camera.y.load(.Acquire);

    var interactive_set = false;
    var force_sort = false;
    @prefetch(entities.items, .{ .rw = .write });
    var iter = std.mem.reverseIterator(entities.items);
    var i: usize = entities.items.len - 1;
    while (iter.nextPtr()) |en| {
        defer i -%= 1;

        switch (en.*) {
            .player => |*player| {
                player.update(time, float_dt, allocator);
                if (player.obj_id == local_player_id) {
                    camera.update(player.x, player.y, float_dt, input.rotate);
                    addMoveRecord(time, player.x, player.y);
                    if (input.attacking) {
                        const shoot_angle = std.math.atan2(f32, input.mouse_y - camera.screen_height / 2.0, input.mouse_x - camera.screen_width / 2.0) + camera.angle;
                        player.weaponShoot(shoot_angle, time);
                    }
                }
            },
            .object => |*object| {
                if (systems.screen == .game and !interactive_set and object.class.isInteractive()) {
                    const dt_x = cam_x - object.x;
                    const dt_y = cam_y - object.y;
                    if (dt_x * dt_x + dt_y * dt_y < 1) {
                        interactive_id.store(object.obj_id, .Release);
                        interactive_type.store(object.class, .Release);

                        if (object.class == .container) {
                            if (systems.screen.game.container_id != object.obj_id) {
                                inline for (0..8) |idx| {
                                    systems.screen.game.setContainerItem(object.inventory[idx], idx);
                                }
                            }

                            systems.screen.game.container_id = object.obj_id;
                            systems.screen.game.setContainerVisible(true);
                        }

                        interactive_set = true;
                    }
                }

                object.update(time, float_dt);
            },
            .projectile => |*projectile| {
                if (!projectile.update(time, float_dt, i, allocator)) {
                    disposeEntity(allocator, &entities.items[i]);
                    _ = entities.swapRemove(i);
                    force_sort = true;
                }
            },
            .particle => |*pt| {
                switch (pt.*) {
                    inline else => |*particle| {
                        if (!particle.update(time, float_dt)) {
                            disposeEntity(allocator, &entities.items[i]);
                            _ = entities.swapRemove(i);
                            force_sort = true;
                        }
                    },
                }
            },
            .particle_effect => |*pt_eff| {
                switch (pt_eff.*) {
                    inline else => |*effect| {
                        if (!effect.update(time, float_dt)) {
                            disposeEntity(allocator, &entities.items[i]);
                            _ = entities.swapRemove(i);
                            force_sort = true;
                        }
                    },
                }
            },
        }
    }

    if (!interactive_set and systems.screen == .game) {
        if (systems.screen.game.container_id != -1) {
            inline for (0..8) |idx| {
                systems.screen.game.setContainerItem(std.math.maxInt(u16), idx);
            }
        }

        systems.screen.game.container_id = -1;
        systems.screen.game.setContainerVisible(false);
    }

    if (force_sort or time - last_sort > 100 * std.time.us_per_ms) {
        std.sort.pdq(Entity, entities.items, {}, lessThan);
        last_sort = time;
    }
}

// x/y < 0 has to be handled before this, since it's a u32
pub inline fn validPos(x: u32, y: u32) bool {
    return !(x >= width or y >= height);
}

pub inline fn getSquare(x: f32, y: f32) ?Square {
    if (x < 0 or x >= @as(f32, @floatFromInt(width)) or y < 0 or y >= @as(f32, @floatFromInt(height)))
        return null;

    const floor_x: u32 = @intFromFloat(@floor(x));
    const floor_y: u32 = @intFromFloat(@floor(y));
    return squares.get(floor_y * width + floor_x);
}

pub inline fn getSquarePtr(x: f32, y: f32) ?*Square {
    if (x < 0 or x >= @as(f32, @floatFromInt(width)) or y < 0 or y >= @as(f32, @floatFromInt(height)))
        return null;

    const floor_x: u32 = @intFromFloat(@floor(x));
    const floor_y: u32 = @intFromFloat(@floor(y));
    return squares.getPtr(floor_y * width + floor_x);
}

pub fn setSquare(x: u32, y: u32, tile_type: u16) void {
    var square = Square{
        .tile_type = tile_type,
        .x = @as(f32, @floatFromInt(x)) + 0.5,
        .y = @as(f32, @floatFromInt(y)) + 0.5,
    };

    texParse: {
        if (tile_type == 0xFFFC) {
            square.atlas_data = assets.editor_tile;
            square.updateBlends();
            break :texParse;
        }

        if (game_data.ground_type_to_tex_data.get(tile_type)) |tex_list| {
            if (tex_list.len == 0) {
                std.log.err("Square with type {d} has an empty texture list, parsing failed", .{tile_type});
                break :texParse;
            }

            const tex = if (tex_list.len == 1) tex_list[0] else tex_list[utils.rng.next() % tex_list.len];
            if (assets.atlas_data.get(tex.sheet)) |data| {
                var ground_data = data[tex.index];
                ground_data.removePadding();
                square.atlas_data = ground_data;
            } else {
                std.log.err("Could not find sheet {s} for square with type 0x{x}. Using error texture", .{ tex.sheet, tile_type });
                square.atlas_data = assets.error_data;
            }

            if (assets.dominant_color_data.get(tex.sheet)) |color_data| {
                const color = color_data[tex.index];
                const base_data_idx: usize = @intCast(y * minimap.num_components * minimap.width + x * minimap.num_components);
                minimap.data[base_data_idx] = color.r;
                minimap.data[base_data_idx + 1] = color.g;
                minimap.data[base_data_idx + 2] = color.b;
                minimap.data[base_data_idx + 3] = color.a;

                const ux: u32 = @intCast(x);
                const uy: u32 = @intCast(y);

                main.minimap_update_min_x = @min(main.minimap_update_min_x, ux);
                main.minimap_update_max_x = @max(main.minimap_update_max_x, ux);
                main.minimap_update_min_y = @min(main.minimap_update_min_y, uy);
                main.minimap_update_max_y = @max(main.minimap_update_max_y, uy);
            }

            square.updateBlends();
        }
    }

    if (game_data.ground_type_to_props.getPtr(tile_type)) |props| {
        square.props = props;
        if (props.random_offset) {
            const u_offset: f32 = @floatFromInt(utils.rng.next() % 8);
            const v_offset: f32 = @floatFromInt(utils.rng.next() % 8);
            square.u_offset = u_offset * assets.base_texel_w;
            square.v_offset = v_offset * assets.base_texel_h;
        }
        square.u_offset += props.x_offset * 10.0 * assets.base_texel_w;
        square.v_offset += props.y_offset * 10.0 * assets.base_texel_h;
    }

    squares.put(x + y * width, square) catch |e| {
        std.log.err("Setting square at x={d}, y={d} failed: {any}", .{ x, y, e });
        return;
    };
}

pub fn addMoveRecord(time: i64, x: f32, y: f32) void {
    if (last_records_clear_time < 0)
        return;

    const id = getId(time);
    if (id < 1 or id > 10)
        return;

    if (move_records.items.len == 0) {
        move_records.append(.{ .time = time, .x = x, .y = y }) catch |e| {
            std.log.err("Adding move record failed: {any}", .{e});
        };
        return;
    }

    const record_idx = move_records.items.len - 1;
    const curr_record = move_records.items[record_idx];
    const curr_id = getId(curr_record.time);
    if (id != curr_id) {
        move_records.append(.{ .time = time, .x = x, .y = y }) catch |e| {
            std.log.err("Adding move record failed: {any}", .{e});
        };
        return;
    }

    const score = getScore(id, time);
    const curr_score = getScore(id, curr_record.time);
    if (score < curr_score) {
        move_records.items[record_idx].time = time;
        move_records.items[record_idx].x = x;
        move_records.items[record_idx].y = y;
    }
}

pub fn clearMoveRecords(time: i64) void {
    move_records.clearRetainingCapacity();
    last_records_clear_time = time;
}

inline fn getId(time: i64) i64 {
    return @divFloor(time - last_records_clear_time + 50, 100);
}

inline fn getScore(id: i64, time: i64) i64 {
    return @intCast(@abs(time - last_records_clear_time - id * 100));
}
