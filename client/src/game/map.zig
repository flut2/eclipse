const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const utils = shared.utils;
const network_data = shared.network_data;
const f32i = utils.f32i;
const u32f = utils.u32f;
const i64f = utils.i64f;
const zstbi = @import("zstbi");

const assets = @import("../assets.zig");
const input = @import("../input.zig");
const main = @import("../main.zig");
const Renderer = @import("../render/Renderer.zig");
const ui_systems = @import("../ui/systems.zig");
const Ally = @import("Ally.zig");
const Container = @import("Container.zig");
const Enemy = @import("Enemy.zig");
const Entity = @import("Entity.zig");
const particles = @import("particles.zig");
const Player = @import("Player.zig");
const Portal = @import("Portal.zig");
const Projectile = @import("Projectile.zig");
const Square = @import("Square.zig");

const day_cycle: i32 = 10 * std.time.us_per_min;
const day_cycle_half: f32 = @as(f32, day_cycle) / 2;

const MapData = struct {
    grounds: std.ArrayListUnmanaged(Renderer.GroundData) = .empty,
    sort_randoms: std.ArrayListUnmanaged(u16) = .empty,
    sort_extras: std.ArrayListUnmanaged(f32) = .empty,
    generics: std.ArrayListUnmanaged(Renderer.GenericData) = .empty,
    ui_sort_extras: std.ArrayListUnmanaged(f32) = .empty,
    ui_generics: std.ArrayListUnmanaged(Renderer.GenericData) = .empty,
    lights: std.ArrayListUnmanaged(Renderer.LightData) = .empty,

    pub fn clear(self: *MapData) void {
        self.grounds.clearRetainingCapacity();
        self.sort_randoms.clearRetainingCapacity();
        self.sort_extras.clearRetainingCapacity();
        self.generics.clearRetainingCapacity();
        self.ui_sort_extras.clearRetainingCapacity();
        self.ui_generics.clearRetainingCapacity();
        self.lights.clearRetainingCapacity();
    }
};

pub var list: struct {
    player: std.ArrayListUnmanaged(Player) = .empty,
    entity: std.ArrayListUnmanaged(Entity) = .empty,
    enemy: std.ArrayListUnmanaged(Enemy) = .empty,
    container: std.ArrayListUnmanaged(Container) = .empty,
    portal: std.ArrayListUnmanaged(Portal) = .empty,
    projectile: std.ArrayListUnmanaged(Projectile) = .empty,
    particle: std.ArrayListUnmanaged(particles.Particle) = .empty,
    particle_effect: std.ArrayListUnmanaged(particles.ParticleEffect) = .empty,
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
    ally: std.ArrayListUnmanaged(Ally) = .empty,
} = .{};
pub var remove_list: std.ArrayListUnmanaged(usize) = .empty;

pub var lights: std.ArrayListUnmanaged(Renderer.LightData) = .empty;
pub var draw_data: [main.frames_in_flight * 2]MapData = @splat(.{});
pub var draw_data_index: u8 = 0;

pub var interactive: struct {
    const InteractiveType = enum(u8) { unset, portal, container };
    map_id: std.atomic.Value(u32) = .init(std.math.maxInt(u32)),
    type: std.atomic.Value(InteractiveType) = .init(.unset),
} = .{};
pub var squares: []Square = &.{};
pub var move_records: std.ArrayListUnmanaged(network_data.TimedPosition) = .empty;
pub var info: network_data.MapInfo = .{};
pub var last_records_clear_time: i64 = 0;
pub var minimap: zstbi.Image = undefined;
pub var minimap_copy: []u8 = undefined;
pub var frames: std.atomic.Value(u32) = .init(0);
pub var fps_time_start: i64 = 0;

var last_tile_update: i64 = 0;

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
    main.allocator.free(squares);
    squares = &.{};

    minimap.deinit();
    main.allocator.free(minimap_copy);
    info = .{};
    main.camera.resetToDefaults();
}

pub fn dispose() void {
    interactive.map_id.store(std.math.maxInt(u32), .release);
    interactive.type.store(.unset, .release);

    inline for (@typeInfo(@TypeOf(list)).@"struct".fields) |field| {
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
    info = .{};
    @memset(squares, Square{});

    @memset(minimap.data, 0);
    main.need_force_update = true;
    main.camera.resetToDefaults();

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

    squares = if (squares.len == 0)
        main.allocator.alloc(Square, @as(u32, data.width) * @as(u32, data.height)) catch return
    else
        main.allocator.realloc(squares, @as(u32, data.width) * @as(u32, data.height)) catch return;

    @memset(squares, Square{});

    const size = @max(data.width, data.height);
    const max_zoom = f32i(@divFloor(size, 32));
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
    switch (constness) {
        .con => for (listForType(T).items) |obj| if (obj.map_id == map_id) return obj,
        .ref => for (listForType(T).items) |*obj| if (obj.map_id == map_id) return obj,
    }
    return null;
}

// Using this is a bad idea if you don't know what you're doing
pub fn findObjectWithAddList(comptime T: type, map_id: u32, comptime constness: Constness) if (constness == .con) ?T else ?*T {
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
    if (info.player_map_id == std.math.maxInt(u32)) return null;
    if (findObject(Player, info.player_map_id, constness)) |player| return player;
    return null;
}

pub fn removeEntity(comptime T: type, map_id: u32) bool {
    var obj_list = listForType(T);
    for (obj_list.items, 0..) |*obj, i| if (obj.map_id == map_id) {
        obj.deinit();
        _ = obj_list.orderedRemove(i);
        return true;
    };

    return false;
}

pub fn update(renderer: *Renderer, time: i64, dt: f32) void {
    if (info.player_map_id == std.math.maxInt(u32)) return;

    var should_unset_interactive = true;
    defer if (should_unset_interactive) {
        interactive.map_id.store(std.math.maxInt(u32), .release);
        interactive.type.store(.unset, .release);
    };

    var should_unset_container = if (ui_systems.screen == .game) ui_systems.screen.game.container_visible else false;
    defer if (should_unset_container) {
        if (ui_systems.screen == .game) {
            const screen = ui_systems.screen.game;
            if (screen.container_id != -1) {
                inline for (0..9) |idx| {
                    screen.setContainerItem(std.math.maxInt(u16), idx);
                    screen.setContainerItemData(.{}, idx);
                }
                screen.container_name.text_data.setText("");
            }

            screen.container_id = std.math.maxInt(u32);
            screen.setContainerVisible(false);
        }
    };

    if (time - last_tile_update > 16 * std.time.us_per_ms) {
        last_tile_update = time;
        for (squares) |*square| square.updateAnims(time);
    }

    const cam_x = main.camera.x;
    const cam_y = main.camera.y;
    const cam_min_x = f32i(main.camera.min_x);
    const cam_max_x = f32i(main.camera.max_x);
    const cam_min_y = f32i(main.camera.min_y);
    const cam_max_y = f32i(main.camera.max_y);

    defer if (ui_systems.screen == .game) ui_systems.screen.game.minimap.update(time);

    inline for (.{
        Entity,
        Enemy,
        Player,
        Portal,
        Projectile,
        Container,
        particles.Particle,
        particles.ParticleEffect,
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
                    containerUpdate: {
                        if (ui_systems.screen != .game) break :containerUpdate;
                        const screen = ui_systems.screen.game;

                        const dt_x = cam_x - obj.x;
                        const dt_y = cam_y - obj.y;
                        if (dt_x * dt_x + dt_y * dt_y > 1) break :containerUpdate;

                        should_unset_interactive = false;
                        should_unset_container = false;
                        if (screen.container_id == obj.map_id) break :containerUpdate;

                        interactive.map_id.store(obj.map_id, .release);
                        interactive.type.store(.container, .release);

                        if (screen.container_id != obj.map_id) {
                            inline for (0..9) |idx| {
                                screen.setContainerItem(obj.inventory[idx], idx);
                                screen.setContainerItemData(obj.inv_data[idx], idx);
                            }
                            if (obj.name) |name| screen.container_name.text_data.setText(name);
                        }

                        screen.container_id = obj.map_id;
                        screen.setContainerVisible(true);
                    }

                    obj.update(time);
                },
                Player => {
                    const is_self = obj.map_id == info.player_map_id;
                    if (is_self) {
                        obj.walk_speed_multiplier = input.walking_speed_multiplier;
                        obj.move_angle = input.move_angle;
                    }

                    obj.update(time, dt);

                    if (is_self) {
                        main.camera.update(obj.x, obj.y, dt);
                        addMoveRecord(time, obj.x, obj.y);
                        if (input.attacking) {
                            const shoot_angle = std.math.atan2(
                                input.mouse_y - main.camera.height / 2.0,
                                input.mouse_x - main.camera.width / 2.0,
                            );
                            obj.weaponShoot(shoot_angle, time);
                        }
                    }
                },
                Portal => {
                    const is_game = ui_systems.screen == .game;
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

    defer draw_data_index = (draw_data_index + 1) % (main.frames_in_flight * 2);
    var cur_draw_data = &draw_data[draw_data_index];
    cur_draw_data.clear();

    if ((main.tick_frame or main.needs_map_bg) and
        main.camera.x >= 0 and main.camera.y >= 0 and
        validPos(u32f(main.camera.x), u32f(main.camera.y)))
    {
        const float_time_ms = f32i(time) / std.time.us_per_ms;

        for (main.camera.min_y..main.camera.max_y) |y| for (main.camera.min_x..main.camera.max_x) |x|
            getSquare(f32i(x), f32i(y), false, .con).?.draw(&cur_draw_data.grounds, &cur_draw_data.lights, float_time_ms);

        inline for (.{ Enemy, Player, Ally }) |T|
            for (listForType(T).items) |*obj| obj.draw(
                renderer,
                &cur_draw_data.generics,
                &cur_draw_data.sort_extras,
                &cur_draw_data.lights,
                &cur_draw_data.sort_randoms,
                float_time_ms,
            );

        inline for (.{ Entity, Container, Projectile }) |T|
            for (listForType(T).items) |*obj| obj.draw(
                &cur_draw_data.generics,
                &cur_draw_data.sort_extras,
                &cur_draw_data.lights,
                &cur_draw_data.sort_randoms,
                float_time_ms,
            );

        const int_id = interactive.map_id.load(.acquire);
        for (listForType(Portal).items) |*portal| portal.draw(
            renderer,
            &cur_draw_data.generics,
            &cur_draw_data.sort_extras,
            &cur_draw_data.lights,
            &cur_draw_data.sort_randoms,
            float_time_ms,
            int_id,
        );
        for (listForType(particles.Particle).items) |particle| particle.draw(
            &cur_draw_data.generics,
            &cur_draw_data.sort_extras,
            &cur_draw_data.sort_randoms,
        );
    }

    if (main.settings.enable_lights) {
        sortGenerics(cur_draw_data.generics.items, cur_draw_data.sort_extras.items, cur_draw_data.sort_randoms.items);

        const opts: Renderer.QuadOptions = .{
            .color = info.bg_color,
            .color_intensity = 1.0,
            .alpha_mult = getLightIntensity(time),
        };
        Renderer.drawQuad(
            &cur_draw_data.generics,
            &cur_draw_data.sort_extras,
            0,
            0,
            main.camera.width,
            main.camera.height,
            assets.generic_8x8,
            opts,
        );

        for (cur_draw_data.lights.items) |data| Renderer.drawQuad(
            &cur_draw_data.generics,
            &cur_draw_data.sort_extras,
            data.x,
            data.y,
            data.w,
            data.h,
            assets.light_data,
            .{ .color = data.color, .color_intensity = 1.0, .alpha_mult = data.intensity },
        );
    } else sortGenerics(cur_draw_data.generics.items, cur_draw_data.sort_extras.items, cur_draw_data.sort_randoms.items);

    for (ui_systems.elements.items) |elem| elem.draw(
        &cur_draw_data.ui_generics,
        &cur_draw_data.ui_sort_extras,
        0,
        0,
        time,
    );

    if (cur_draw_data.grounds.items.len > 0 or
        cur_draw_data.generics.items.len > 0 or
        cur_draw_data.ui_generics.items.len > 0)
        // This is blocking, meaning updating is locked behind frame rates.
        // This saves power, but has the side effect of lower frame rates being much worse to play,
        // like on Flash where projs skip over entities in low frame rates.
        // TODO: Revisit whether this would be an issue for anyone (really bad PCs)
        renderer.draw_queue.push(.{
            .grounds = cur_draw_data.grounds.items,
            .generics = cur_draw_data.generics.items,
            .ui_generics = cur_draw_data.ui_generics.items,
            .camera = main.camera, // to copy and save
        });

    if (main.settings.stats_enabled and time - fps_time_start >= 1 * std.time.us_per_s) {
        switch (ui_systems.screen) {
            .game => |screen| screen.updateFpsText(frames.load(.acquire), utils.currentMemoryUse(time) catch -1.0),
            .editor => |screen| screen.updateFps(frames.load(.acquire), utils.currentMemoryUse(time) catch -1.0),
            else => {},
        }
        fps_time_start = time;
    }
}

fn sortGenerics(generics: []Renderer.GenericData, sort_extras: []f32, sort_randoms: []u16) void {
    const SortContext = struct {
        items: []Renderer.GenericData,
        sort_extras: []f32,
        sort_randoms: []u16,

        pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
            const item_a = ctx.items[a];
            const item_b = ctx.items[b];
            const norm_sort_random_a = f32i(ctx.sort_randoms[a]) / @as(f32, std.math.maxInt(u16));
            const norm_sort_random_b = f32i(ctx.sort_randoms[b]) / @as(f32, std.math.maxInt(u16));
            const a_value = item_a.pos[1] + item_a.size[1] + ctx.sort_extras[a] + norm_sort_random_a;
            const b_value = item_b.pos[1] + item_b.size[1] + ctx.sort_extras[b] + norm_sort_random_b;
            return a_value < b_value;
        }

        pub fn swap(ctx: @This(), a: usize, b: usize) void {
            std.mem.swap(u16, &ctx.sort_randoms[a], &ctx.sort_randoms[b]);
            std.mem.swap(f32, &ctx.sort_extras[a], &ctx.sort_extras[b]);
            std.mem.swap(Renderer.GenericData, &ctx.items[a], &ctx.items[b]);
        }
    };

    std.sort.pdqContext(0, generics.len, SortContext{ .items = generics, .sort_extras = sort_extras, .sort_randoms = sort_randoms });
}

// x/y < 0 has to be handled before this, since it's a u32
pub fn validPos(x: u32, y: u32) bool {
    return !(info.width == 0 or info.height == 0 or x > info.width - 1 or y > info.height - 1);
}

// check_validity should always be on, unless you profiled that it causes clear slowdowns in your code.
// even then, you should be very sure that the input can't ever go wrong or that it going wrong is inconsequential
pub fn getSquare(x: f32, y: f32, comptime check_validity: bool, comptime constness: Constness) if (constness == .con) ?Square else ?*Square {
    if (check_validity and (x < 0 or y < 0)) {
        @branchHint(.unlikely);
        return null;
    }

    const floor_x = u32f(x);
    const floor_y = u32f(y);
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
    if (damage >= self.hp) {
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
                const eff: utils.ConditionEnum = @enumFromInt(i);
                const cond_str = eff.toString();
                if (cond_str.len == 0) continue;

                self.condition.set(eff, true);

                self.status_texts.append(main.allocator, .{
                    .initial_size = 16.0,
                    .dispose_text = true,
                    .show_at = main.current_time + i64f(0.2 * std.time.us_per_s),
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
