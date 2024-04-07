const std = @import("std");
const element = @import("../ui/element.zig");
const utils = @import("../utils.zig");
const game_data = @import("../game_data.zig");
const assets = @import("../assets.zig");
const particles = @import("particles.zig");
const map = @import("map.zig");
const main = @import("../main.zig");
const camera = @import("../camera.zig");

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
    atlas_data: assets.AtlasData = assets.AtlasData.fromRaw(0, 0, 0, 0, .base),
    top_atlas_data: assets.AtlasData = assets.AtlasData.fromRaw(0, 0, 0, 0, .base),
    move_angle: f32 = std.math.nan(f32),
    move_step: f32 = 0.0,
    target_x: f32 = 0.0,
    target_y: f32 = 0.0,
    move_x_dir: bool = false,
    move_y_dir: bool = false,
    attack_start: i64 = 0,
    attack_angle: f32 = 0.0,
    props: *const game_data.ObjProps = undefined,
    class: game_data.ClassType = .game_object,
    colors: []u32 = &[0]u32{},
    renderx_offset: f32 = 0.0,
    anim_idx: u8 = 0,
    facing: f32 = std.math.nan(f32),
    next_anim: i64 = -1,
    float_time_offset: i64 = 0,
    disposed: bool = false,

    pub inline fn addToMap(self: *GameObject, allocator: std.mem.Allocator, comptime no_wall_offset: bool) void {
        self.class = game_data.obj_type_to_class.get(self.obj_type) orelse blk: {
            std.log.err("Parsing class for object with type 0x{x} failed, using .game_object", .{self.obj_type});
            break :blk .game_object;
        };

        self.props = game_data.obj_type_to_props.getPtr(self.obj_type) orelse {
            std.log.err("Could not find props for object with type 0x{x}, returning", .{self.obj_type});
            return;
        };
        self.size = self.props.getSize();

        if (self.props.float) {
            self.float_time_offset = @intFromFloat(utils.rng.random().float(f32) * self.props.float_time);
        }

        for (self.props.show_effects) |eff| {
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

        if (self.props.static) {
            if (map.getSquarePtr(self.x, self.y)) |square| {
                square.static_obj_id = self.obj_id;
            }
        }

        texParse: {
            if (game_data.obj_type_to_tex_data.get(self.obj_type)) |tex_list| {
                if (tex_list.len == 0) {
                    std.log.err("Object with type 0x{x} has an empty texture list, parsing failed", .{self.obj_type});
                    break :texParse;
                }

                const tex = tex_list[@as(usize, @intCast(self.obj_id)) % tex_list.len];

                if (tex.animated) {
                    if (assets.anim_enemies.get(tex.sheet)) |anim_data| {
                        self.anim_data = anim_data[tex.index];
                    } else {
                        std.log.err("Could not find anim sheet {s} for object with type 0x{x}. Using error texture", .{ tex.sheet, self.obj_type });
                        self.anim_data = assets.error_data_enemy;
                    }

                    self.colors = assets.atlas_to_color_data.get(@bitCast(self.anim_data.?.walk_anims[0])) orelse blk: {
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

                    if (self.props.static and self.props.occupy_square) {
                        if (assets.dominant_color_data.get(tex.sheet)) |color_data| {
                            main.minimap_lock.lock();
                            defer main.minimap_lock.unlock();

                            const floor_y: u32 = @intFromFloat(@floor(self.y));
                            const floor_x: u32 = @intFromFloat(@floor(self.x));

                            const color = color_data[tex.index];
                            const base_data_idx: usize = @intCast(floor_y * map.minimap.num_components * map.minimap.width + floor_x * map.minimap.num_components);
                            map.minimap.data[base_data_idx] = color.r;
                            map.minimap.data[base_data_idx + 1] = color.g;
                            map.minimap.data[base_data_idx + 2] = color.b;
                            map.minimap.data[base_data_idx + 3] = color.a;

                            main.minimap_update_min_x = @min(main.minimap_update_min_x, floor_x);
                            main.minimap_update_max_x = @max(main.minimap_update_max_x, floor_x);
                            main.minimap_update_min_y = @min(main.minimap_update_min_y, floor_y);
                            main.minimap_update_max_y = @max(main.minimap_update_max_y, floor_y);
                        }
                    }

                    if (self.props.draw_on_ground or self.class == .wall) {
                        self.atlas_data.removePadding();
                    }
                }
            } else {
                std.log.err("Could not find texture data for obj 0x{x}", .{self.obj_type});
            }
        }

        topTexParse: {
            if (game_data.obj_type_to_top_tex_data.get(self.obj_type)) |top_tex_list| {
                if (top_tex_list.len == 0) {
                    std.log.err("Object with type 0x{x} has an empty top texture list, parsing failed", .{self.obj_type});
                    break :topTexParse;
                }

                const tex = top_tex_list[@as(usize, @intCast(self.obj_id)) % top_tex_list.len];
                if (assets.atlas_data.get(tex.sheet)) |data| {
                    var top_data = data[tex.index];
                    top_data.removePadding();
                    self.top_atlas_data = top_data;
                } else {
                    std.log.err("Could not find top sheet {s} for object with type 0x{x}. Using error texture", .{ tex.sheet, self.obj_type });
                    self.top_atlas_data = assets.error_data;
                }
            }
        }

        if (self.class == .wall and self.x >= 0 and self.y >= 0) {
            if (map.getSquarePtr(self.x, self.y)) |square| {
                if (!no_wall_offset) {
                    self.x = @floor(self.x) + 0.5;
                    self.y = @floor(self.y) + 0.5;
                }

                self.move_angle = std.math.nan(f32);

                square.static_obj_id = self.obj_id;
                square.updateBlends();
            }
        }

        if (self.class == .container) {
            assets.playSfx("loot_appears");
        }

        if (self.props.show_name and self.name_text_data == null) {
            self.name_text_data = element.TextData{
                .text = if (self.name) |obj_name| obj_name else self.props.display_id,
                .text_type = .bold,
                .size = 12,
            };

            {
                self.name_text_data.?.lock.lock();
                defer self.name_text_data.?.lock.unlock();

                self.name_text_data.?.recalculateAttributes(allocator);
            }
        }

        map.add_lock.lockShared();
        defer map.add_lock.unlockShared();
        map.entities_to_add.append(.{ .object = self.* }) catch |e| {
            std.log.err("Could not add object to map (obj_id={d}, obj_type={d}, x={d}, y={d}): {}", .{ self.obj_id, self.obj_type, self.x, self.y, e });
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
                            .size = 16,
                            .color = 0xB02020,
                        },
                        .initial_size = 16,
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

    pub inline fn update(self: *GameObject, time: i64, dt: f32) void {
        const screen_pos = camera.rotateAroundCamera(self.x, self.y);
        const size = camera.size_mult * camera.scale * self.size;

        if (self.anim_data) |anim_data| {
            const attack_period: i64 = 0.3 * std.time.us_per_s;
            const move_period: i64 = 0.4 * std.time.us_per_s;

            var float_period: f32 = 0.0;
            var action: assets.Action = .stand;
            if (time < self.attack_start + attack_period) {
                const time_dt: f32 = @floatFromInt(time - self.attack_start);
                float_period = @mod(time_dt, attack_period) / attack_period;
                self.facing = self.attack_angle;
                action = .attack;
            } else if (!std.math.isNan(self.move_angle)) {
                const float_time: f32 = @floatFromInt(time);
                float_period = @mod(float_time, move_period) / move_period;
                self.facing = self.move_angle;
                action = .walk;
            } else {
                float_period = 0;
                action = .stand;
            }

            const angle = if (std.math.isNan(self.facing))
                0.0
            else
                utils.halfBound(self.facing) / (std.math.pi / 4.0);

            const dir: assets.Direction = switch (@as(u8, @intFromFloat(@round(angle + 4))) % 8) {
                2...5 => .right,
                else => .left,
            };

            const anim_idx: u8 = @intFromFloat(@max(0, @min(0.99999, float_period)) * 2.0);
            const dir_idx: u8 = @intFromEnum(dir);
            const stand_data = anim_data.walk_anims[dir_idx * assets.AnimEnemyData.walk_actions];

            self.atlas_data = switch (action) {
                .walk => anim_data.walk_anims[dir_idx * assets.AnimEnemyData.walk_actions + 1 + anim_idx],
                .attack => anim_data.attack_anims[dir_idx * assets.AnimEnemyData.attack_actions + anim_idx],
                .stand => stand_data,
            };

            const w = (self.atlas_data.texWRaw() - assets.padding * 2) * size;
            const stand_w = (stand_data.texWRaw() - assets.padding * 2) * size;
            self.renderx_offset = (if (dir == .left) stand_w - w else w - stand_w) / 2.0;
        } else if (self.props.anim_props) |props| {
            updateAnim: {
                if (time >= self.next_anim) {
                    const frame_len = props.frames.len;
                    if (frame_len < 2) {
                        std.log.err("The amount of frames ({d}) was not enough for obj type 0x{x}", .{ frame_len, self.obj_type });
                        break :updateAnim;
                    }

                    const frame_data = props.frames[self.anim_idx];
                    const tex_data = frame_data.tex;
                    if (assets.atlas_data.get(tex_data.sheet)) |tex| {
                        if (tex_data.index >= tex.len) {
                            std.log.err("Incorrect index ({d}) given to anim with sheet {s}, obj type: 0x{x}", .{ tex_data.index, tex_data.sheet, self.obj_type });
                            break :updateAnim;
                        }
                        self.atlas_data = tex[tex_data.index];
                        self.anim_idx = @intCast((self.anim_idx + 1) % frame_len);
                        self.next_anim = time + frame_data.time;
                    } else {
                        std.log.err("Could not find sheet {s} for anim on obj type 0x{x}", .{ tex_data.sheet, self.obj_type });
                        break :updateAnim;
                    }
                }
            }
        }

        if (self.props.float) {
            const total_time: f32 = @floatFromInt(time + self.float_time_offset);
            self.z = self.props.float_height / 2.0 * (@sin(total_time / self.props.float_time) + 1.0);
        }

        const h = self.atlas_data.texHRaw() * size;
        self.screen_y = screen_pos.y + self.z * -camera.px_per_tile - (h - size * assets.padding) - 10;
        self.screen_x = screen_pos.x;

        if (self.class != .wall and !std.math.isNan(self.move_angle) and self.move_step > 0.0) {
            const next_x = self.x + dt * self.move_step * @cos(self.move_angle);
            const next_y = self.y + dt * self.move_step * @sin(self.move_angle);
            self.x = if (self.move_x_dir) @min(self.target_x, next_x) else @max(self.target_x, next_x);
            self.y = if (self.move_y_dir) @min(self.target_y, next_y) else @max(self.target_y, next_y);
        }
    }
};
