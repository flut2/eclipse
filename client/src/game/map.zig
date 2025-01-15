const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const utils = shared.utils;
const network_data = shared.network_data;
const f32i = utils.f32i;
const int = utils.int;
const zstbi = @import("zstbi");

const assets = @import("../assets.zig");
const input = @import("../input.zig");
const main = @import("../main.zig");
const systems = @import("../ui/systems.zig");
const Ally = @import("Ally.zig");
const Container = @import("Container.zig");
const Enemy = @import("Enemy.zig");
const Entity = @import("Entity.zig");
const particles = @import("particles.zig");
const Player = @import("Player.zig");
const Portal = @import("Portal.zig");
const Projectile = @import("Projectile.zig");
const Purchasable = @import("Purchasable.zig");
const Square = @import("Square.zig");

const day_cycle: i32 = 10 * std.time.us_per_min;
const day_cycle_half: f32 = @as(f32, day_cycle) / 2;

pub var square_lock: std.Thread.Mutex = .{};
pub var object_lock: std.Thread.Mutex = .{};
pub var list: struct {
    player: std.ArrayListUnmanaged(Player) = .empty,
    entity: std.ArrayListUnmanaged(Entity) = .empty,
    enemy: std.ArrayListUnmanaged(Enemy) = .empty,
    container: std.ArrayListUnmanaged(Container) = .empty,
    portal: std.ArrayListUnmanaged(Portal) = .empty,
    projectile: std.ArrayListUnmanaged(Projectile) = .empty,
    particle: std.ArrayListUnmanaged(particles.Particle) = .empty,
    particle_effect: std.ArrayListUnmanaged(particles.ParticleEffect) = .empty,
    purchasable: std.ArrayListUnmanaged(Purchasable) = .empty,
    ally: std.ArrayListUnmanaged(Ally) = .empty,
} = .{};
pub var add_list: struct {
    player: std.ArrayListUnmanaged(Player) = .empty,
    entity: std.ArrayListUnmanaged(Entity) = .empty,
    enemy: std.ArrayListUnmanaged(Enemy) = .empty,
    container: std.ArrayListUnmanaged(Container) = .empty,
    portal: std.ArrayListUnmanaged(Portal) = .empty,
    projectile: std.ArrayListUnmanaged(Projectile) = .empty,
    particle: std.ArrayListUnmanaged(particles.Particle) = .empty,
    particle_effect: std.ArrayListUnmanaged(particles.ParticleEffect) = .empty,
    purchasable: std.ArrayListUnmanaged(Purchasable) = .empty,
    ally: std.ArrayListUnmanaged(Ally) = .empty,
} = .{};
pub var remove_list: std.ArrayListUnmanaged(usize) = .empty;

pub var interactive: struct {
    const InteractiveType = enum(u8) { unset, portal, container, purchasable };
    map_id: std.atomic.Value(u32) = .init(std.math.maxInt(u32)),
    type: std.atomic.Value(InteractiveType) = .init(.unset),
} = .{};
pub var squares: []Square = &.{};
pub var move_records: std.ArrayListUnmanaged(network_data.TimedPosition) = .empty;
pub var info: network_data.MapInfo = .{};
pub var last_records_clear_time: i64 = 0;
pub var minimap: zstbi.Image = undefined;
pub var minimap_copy: []u8 = undefined;

var last_update: i64 = 0;

pub fn listForType(comptime T: type) *std.ArrayListUnmanaged(T) {
    return switch (T) {
        Entity => &list.entity,
        Enemy => &list.enemy,
        Player => &list.player,
        Portal => &list.portal,
        Container => &list.container,
        Projectile => &list.projectile,
        particles.Particle => &list.particle,
        particles.ParticleEffect => &list.particle_effect,
        Purchasable => &list.purchasable,
        Ally => &list.ally,
        else => @compileError("Invalid type"),
    };
}

pub fn addListForType(comptime T: type) *std.ArrayListUnmanaged(T) {
    return switch (T) {
        Entity => &add_list.entity,
        Enemy => &add_list.enemy,
        Player => &add_list.player,
        Portal => &add_list.portal,
        Container => &add_list.container,
        Projectile => &add_list.projectile,
        particles.Particle => &add_list.particle,
        particles.ParticleEffect => &add_list.particle_effect,
        Purchasable => &add_list.purchasable,
        Ally => &add_list.ally,
        else => @compileError("Invalid type"),
    };
}

pub fn init() !void {
    minimap = try zstbi.Image.createEmpty(1024, 1024, 4, .{});
    minimap_copy = try main.allocator.alloc(u8, 1024 * 1024 * 4);
}

pub fn deinit() void {
    inline for (@typeInfo(@TypeOf(list)).@"struct".fields) |field| {
        object_lock.lock();
        defer object_lock.unlock();

        var child_list = &@field(list, field.name);
        defer child_list.deinit(main.allocator);
        if (comptime !std.mem.eql(u8, field.name, "particle") and !std.mem.eql(u8, field.name, "particle_effect"))
            for (child_list.items) |*obj| obj.deinit();
    }

    inline for (@typeInfo(@TypeOf(add_list)).@"struct".fields) |field| {
        var child_list = &@field(add_list, field.name);
        defer child_list.deinit(main.allocator);
        if (comptime !std.mem.eql(u8, field.name, "particle") and !std.mem.eql(u8, field.name, "particle_effect"))
            for (child_list.items) |*obj| obj.deinit();
    }

    remove_list.deinit(main.allocator);

    move_records.deinit(main.allocator);
    main.allocator.free(info.name);
    {
        square_lock.lock();
        defer square_lock.unlock();
        main.allocator.free(squares);
    }

    minimap.deinit();
    main.allocator.free(minimap_copy);
}

pub fn dispose() void {
    interactive.map_id.store(std.math.maxInt(u32), .release);
    interactive.type.store(.unset, .release);

    info = .{};

    inline for (@typeInfo(@TypeOf(list)).@"struct".fields) |field| {
        object_lock.lock();
        defer object_lock.unlock();

        var child_list = &@field(list, field.name);
        defer child_list.clearRetainingCapacity();
        if (comptime !std.mem.eql(u8, field.name, "particle") and !std.mem.eql(u8, field.name, "particle_effect"))
            for (child_list.items) |*obj| obj.deinit();
    }

    inline for (@typeInfo(@TypeOf(add_list)).@"struct".fields) |field| {
        var child_list = &@field(add_list, field.name);
        defer child_list.clearRetainingCapacity();
        if (comptime !std.mem.eql(u8, field.name, "particle") and !std.mem.eql(u8, field.name, "particle_effect"))
            for (child_list.items) |*obj| obj.deinit();
    }

    move_records.clearRetainingCapacity();
    main.allocator.free(info.name);
    info.name = "";
    {
        square_lock.lock();
        defer square_lock.unlock();
        @memset(squares, Square{});
    }

    @memset(minimap.data, 0);
    main.need_force_update = true;

    // main.minimap_update = .{};
    // minimap.deinit();
    // minimap = try zstbi.Image.createEmpty(1, 1, 4, .{});
    // main.need_force_update = true;
}

pub fn getLightIntensity(time: i64) f32 {
    if (info.day_intensity == 0 and info.night_intensity == 0) return info.bg_intensity;

    const server_time_clamped = f32i(@mod(time + info.server_time, day_cycle));
    const intensity_delta = info.day_intensity - info.night_intensity;
    if (server_time_clamped <= day_cycle_half)
        return info.night_intensity + intensity_delta * (server_time_clamped / day_cycle_half)
    else
        return info.day_intensity - intensity_delta * ((server_time_clamped - day_cycle_half) / day_cycle_half);
}

pub fn setMapInfo(data: network_data.MapInfo) void {
    info = data;

    {
        square_lock.lock();
        defer square_lock.unlock();
        squares = if (squares.len == 0)
            main.allocator.alloc(Square, @as(u32, data.width) * @as(u32, data.height)) catch return
        else
            main.allocator.realloc(squares, @as(u32, data.width) * @as(u32, data.height)) catch return;

        @memset(squares, Square{});
    }

    const size = @max(data.width, data.height);
    const max_zoom = f32i(@divFloor(size, 32));
    main.camera.lock.lock();
    defer main.camera.lock.unlock();
    main.camera.minimap_zoom = @max(1, @min(max_zoom, main.camera.minimap_zoom));

    @memset(minimap.data, 0);
    main.need_force_update = true;

    // main.minimap_update = .{};
    // minimap.deinit();
    // minimap = zstbi.Image.createEmpty(data.width, data.height, 4, .{}) catch |e| {
    //     std.debug.panic("Minimap allocation failed: {}", .{e});
    //     return;
    // };
    // main.need_force_update = true;
}

const Constness = enum { con, ref };
pub fn findObject(comptime T: type, map_id: u32, comptime constness: Constness) if (constness == .con) ?T else ?*T {
    std.debug.assert(!object_lock.tryLock());
    switch (constness) {
        .con => for (listForType(T).items) |obj| if (obj.map_id == map_id) return obj,
        .ref => for (listForType(T).items) |*obj| if (obj.map_id == map_id) return obj,
    }
    return null;
}

// Using this is a bad idea if you don't know what you're doing
pub fn findObjectWithAddList(comptime T: type, map_id: u32, comptime constness: Constness) if (constness == .con) ?T else ?*T {
    std.debug.assert(!object_lock.tryLock());
    switch (constness) {
        .con => {
            for (listForType(T).items) |obj| if (obj.map_id == map_id) return obj;
            for (addListForType(T).items) |obj| if (obj.map_id == map_id) return obj;
        },
        .ref => {
            for (listForType(T).items) |*obj| if (obj.map_id == map_id) return obj;
            for (addListForType(T).items) |*obj| if (obj.map_id == map_id) return obj;
        },
    }
    return null;
}

pub fn localPlayer(comptime constness: Constness) if (constness == .con) ?Player else ?*Player {
    std.debug.assert(!object_lock.tryLock());
    if (info.player_map_id == std.math.maxInt(u32)) return null;
    if (findObject(Player, info.player_map_id, constness)) |player| return player;
    return null;
}

pub fn removeEntity(comptime T: type, map_id: u32) bool {
    std.debug.assert(!object_lock.tryLock());
    var obj_list = listForType(T);
    for (obj_list.items, 0..) |*obj, i| if (obj.map_id == map_id) {
        obj.deinit();
        _ = obj_list.orderedRemove(i);
        return true;
    };

    return false;
}

pub fn update(time: i64, dt: f32) void {
    if (info.player_map_id == std.math.maxInt(u32)) return;

    var should_unset_interactive = true;
    defer if (should_unset_interactive) {
        interactive.map_id.store(std.math.maxInt(u32), .release);
        interactive.type.store(.unset, .release);
    };

    var should_unset_container = true;
    defer if (should_unset_container) {
        systems.ui_lock.lock();
        defer systems.ui_lock.unlock();
        if (systems.screen == .game) {
            const screen = systems.screen.game;
            if (screen.container_id != -1) {
                inline for (0..8) |idx| screen.setContainerItem(std.math.maxInt(u16), idx);
                screen.container_name.text_data.setText("");
            }

            screen.container_id = std.math.maxInt(u32);
            screen.setContainerVisible(false);
        }
    };

    const cam_x = main.camera.x;
    const cam_y = main.camera.y;
    const cam_min_x = f32i(main.camera.min_x);
    const cam_max_x = f32i(main.camera.max_x);
    const cam_min_y = f32i(main.camera.min_y);
    const cam_max_y = f32i(main.camera.max_y);

    object_lock.lock();
    defer object_lock.unlock();

    defer if (systems.screen == .game) systems.screen.game.minimap.update(time);

    inline for (.{
        Entity,
        Enemy,
        Player,
        Portal,
        Projectile,
        Container,
        particles.Particle,
        particles.ParticleEffect,
        Purchasable,
        Ally,
    }) |ObjType| {
        var obj_list = listForType(ObjType);
        {
            var obj_add_list = addListForType(ObjType);
            defer obj_add_list.clearRetainingCapacity();
            obj_list.appendSlice(main.allocator, obj_add_list.items) catch @panic("Failed to add objects");
        }

        remove_list.clearRetainingCapacity();

        for (obj_list.items, 0..) |*obj, i| {
            if (ObjType != particles.ParticleEffect and (ObjType != Player or obj.map_id != info.player_map_id)) {
                const obj_x = switch (ObjType) {
                    particles.Particle => switch (obj.*) {
                        inline else => |pt| pt.x,
                    },
                    else => obj.x,
                };
                const obj_y = switch (ObjType) {
                    particles.Particle => switch (obj.*) {
                        inline else => |pt| pt.y,
                    },
                    else => obj.y,
                };
                if (obj_x <= cam_min_x - 0.0001 or obj_x >= cam_max_x + 0.0001 or obj_y <= cam_min_y - 0.0001 or obj_y >= cam_max_y + 0.0001) continue;
            }

            switch (ObjType) {
                Container => {
                    {
                        systems.ui_lock.lock();
                        defer systems.ui_lock.unlock();
                        if (systems.screen == .game) {
                            const screen = systems.screen.game;
                            const dt_x = cam_x - obj.x;
                            const dt_y = cam_y - obj.y;
                            if (dt_x * dt_x + dt_y * dt_y < 1) {
                                interactive.map_id.store(obj.map_id, .release);
                                interactive.type.store(.container, .release);

                                if (screen.container_id != obj.map_id) {
                                    inline for (0..8) |idx| screen.setContainerItem(obj.inventory[idx], idx);
                                    if (obj.name) |name| screen.container_name.text_data.setText(name);
                                }

                                screen.container_id = obj.map_id;
                                screen.setContainerVisible(true);
                                should_unset_interactive = false;
                                should_unset_container = false;
                            }
                        }
                    }

                    obj.update(time);
                },
                Player => {
                    obj.walk_speed_multiplier = input.walking_speed_multiplier;
                    obj.move_angle = input.move_angle;
                    obj.update(time, dt);
                    if (obj.map_id == info.player_map_id) {
                        main.camera.update(obj.x, obj.y, dt);
                        addMoveRecord(time, obj.x, obj.y);
                        if (input.attacking) {
                            const shoot_angle = std.math.atan2(input.mouse_y - main.camera.height / 2.0, input.mouse_x - main.camera.width / 2.0);
                            obj.weaponShoot(shoot_angle, time);
                        }
                    }
                },
                Portal => {
                    const is_game = blk: {
                        systems.ui_lock.lock();
                        defer systems.ui_lock.unlock();
                        break :blk systems.screen == .game;
                    };
                    if (is_game) {
                        const dt_x = cam_x - obj.x;
                        const dt_y = cam_y - obj.y;
                        if (dt_x * dt_x + dt_y * dt_y < 1) {
                            interactive.map_id.store(obj.map_id, .release);
                            interactive.type.store(.portal, .release);
                            should_unset_interactive = false;
                        }
                    }
                    obj.update(time);
                },
                Purchasable => {
                    const is_game = blk: {
                        systems.ui_lock.lock();
                        defer systems.ui_lock.unlock();
                        break :blk systems.screen == .game;
                    };
                    if (is_game) {
                        const dt_x = cam_x - obj.x;
                        const dt_y = cam_y - obj.y;
                        if (dt_x * dt_x + dt_y * dt_y < 1) {
                            interactive.map_id.store(obj.map_id, .release);
                            interactive.type.store(.purchasable, .release);
                            should_unset_interactive = false;
                        }
                    }

                    obj.update(time);
                },
                Projectile => if (!obj.update(time, dt))
                    remove_list.append(main.allocator, i) catch @panic("Removing projectile failed"),
                particles.Particle => if (!obj.update(time, dt))
                    remove_list.append(main.allocator, i) catch @panic("Removing particle failed"),
                particles.ParticleEffect => if (!obj.update(time, dt))
                    remove_list.append(main.allocator, i) catch @panic("Removing particle effect failed"),
                Entity => obj.update(time),
                Enemy => obj.update(time, dt),
                Ally => obj.update(time, dt),
                else => @compileError("Invalid type"),
            }
        }

        var iter = std.mem.reverseIterator(remove_list.items);
        while (iter.next()) |i| {
            const T = @TypeOf(obj_list.items[i]);
            if (T != particles.Particle and T != particles.ParticleEffect) obj_list.items[i].deinit();
            _ = obj_list.orderedRemove(i);
        }
    }
}

// x/y < 0 has to be handled before this, since it's a u32
pub fn validPos(x: u32, y: u32) bool {
    return !(info.width == 0 or info.height == 0 or x >= info.width - 1 or y >= info.height - 1);
}

// check_validity should always be on, unless you profiled that it causes clear slowdowns in your code.
// even then, you should be very sure that the input can't ever go wrong or that it going wrong is inconsequential
pub fn getSquare(x: f32, y: f32, comptime check_validity: bool, comptime constness: Constness) if (constness == .con) ?Square else ?*Square {
    if (check_validity and (x < 0 or y < 0)) {
        @branchHint(.unlikely);
        return null;
    }

    const floor_x = int(u32, x);
    const floor_y = int(u32, y);
    if (check_validity and !validPos(floor_x, floor_y)) {
        @branchHint(.unlikely);
        return null;
    }

    const square = switch (constness) {
        .con => squares[floor_y * info.width + floor_x],
        .ref => &squares[floor_y * info.width + floor_x],
    };
    if (check_validity and square.data_id == Square.empty_tile) return null;
    return square;
}

pub fn addMoveRecord(time: i64, x: f32, y: f32) void {
    if (last_records_clear_time < 0) return;

    const id = getId(time);
    if (id < 1 or id > 10) return;

    const new_record: network_data.TimedPosition = .{ .time = time, .x = x, .y = y };
    if (move_records.items.len == 0) {
        move_records.append(main.allocator, new_record) catch main.oomPanic();
        return;
    }

    const record_idx = move_records.items.len - 1;
    const curr_record = move_records.items[record_idx];
    const curr_id = getId(curr_record.time);
    if (id != curr_id) {
        move_records.append(main.allocator, new_record) catch main.oomPanic();
        return;
    }

    const score = getScore(id, time);
    const curr_score = getScore(id, curr_record.time);
    if (score < curr_score) move_records.items[record_idx] = new_record;
}

pub fn clearMoveRecords(time: i64) void {
    move_records.clearRetainingCapacity();
    last_records_clear_time = time;
}

fn getId(time: i64) i64 {
    return @divFloor(time - last_records_clear_time + 50, 100);
}

fn getScore(id: i64, time: i64) i64 {
    return @intCast(@abs(time - last_records_clear_time - id * 100));
}

pub fn takeDamage(
    self: anytype,
    damage: i32,
    damage_type: network_data.DamageType,
    conditions: utils.Condition,
    proj_colors: []const u32,
) void {
    if (self.dead) return;

    if (damage >= self.hp) {
        self.dead = true;

        assets.playSfx(self.data.death_sound);
        particles.ExplosionEffect.addToMap(.{
            .x = self.x,
            .y = self.y,
            .colors = self.colors,
            .size = self.size_mult,
            .amount = 30,
        });
    } else {
        assets.playSfx(self.data.hit_sound);
        particles.HitEffect.addToMap(.{
            .x = self.x,
            .y = self.y,
            .colors = proj_colors,
            .angle = 0.0,
            .speed = 0.01,
            .size = 1.0,
            .amount = 3,
        });

        const cond_int: @typeInfo(utils.Condition).@"struct".backing_integer.? = @bitCast(conditions);
        for (0..@bitSizeOf(utils.Condition)) |i| {
            if (cond_int & (@as(usize, 1) << @intCast(i)) != 0) {
                const eff: utils.ConditionEnum = @enumFromInt(i + 1);
                const cond_str = eff.toString();
                if (cond_str.len == 0) continue;

                self.condition.set(eff, true);

                self.status_texts.append(main.allocator, .{
                    .initial_size = 16.0,
                    .dispose_text = true,
                    .show_at = main.current_time,
                    .text_data = .{
                        .text = std.fmt.allocPrint(main.allocator, "{s}", .{cond_str}) catch main.oomPanic(),
                        .text_type = .bold,
                        .size = 16,
                        .color = 0xC2C2C2,
                    },
                }) catch main.oomPanic();
            }
        }
    }

    self.status_texts.append(main.allocator, .{
        .initial_size = 16.0,
        .dispose_text = true,
        .show_at = main.current_time,
        .text_data = .{
            .text = std.fmt.allocPrint(main.allocator, "-{}", .{damage}) catch main.oomPanic(),
            .text_type = .bold,
            .size = 16,
            .color = switch (damage_type) {
                .physical => 0xB02020,
                .magic => 0x6E15AD,
                .true => 0xC2C2C2,
            },
        },
    }) catch main.oomPanic();
}
