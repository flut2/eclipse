const std = @import("std");
const network = @import("../network.zig");
const game_data = @import("../game_data.zig");
const camera = @import("../camera.zig");
const input = @import("../input.zig");
const main = @import("../main.zig");
const utils = @import("../utils.zig");
const element = @import("../ui/element.zig");
const zstbi = @import("zstbi");
const particles = @import("particles.zig");
const systems = @import("../ui/systems.zig");

const Square = @import("square.zig").Square;
const Player = @import("player.zig").Player;
const Projectile = @import("projectile.zig").Projectile;
const GameObject = @import("game_object.zig").GameObject;

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
            std.log.err("Allocation for physical damage text \"-{d}\" failed: {}", .{ phys_dmg, e });
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
            std.log.err("Allocation for magic damage text \"-{d}\" failed: {}", .{ magic_dmg, e });
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
            std.log.err("Allocation for true damage text \"-{d}\" failed: {}", .{ true_dmg, e });
        };
        delay += 100;
    }
}

fn lessThan(_: void, lhs: Entity, rhs: Entity) bool {
    var lhs_sort_val: f32 = 0;
    var rhs_sort_val: f32 = 0;

    switch (lhs) {
        .object => |object| {
            if (object.props.draw_on_ground) {
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
            if (object.props.draw_on_ground) {
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

pub var add_lock: std.Thread.RwLock = .{};
pub var object_lock: std.Thread.RwLock = .{};
pub var entities: std.ArrayList(Entity) = undefined;
pub var entities_to_add: std.ArrayList(Entity) = undefined;
pub var entity_indices_to_remove: std.ArrayList(usize) = undefined;
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

var last_update: i64 = 0;
var last_sort: i64 = 0;

pub fn init(allocator: std.mem.Allocator) !void {
    entities = try std.ArrayList(Entity).initCapacity(allocator, 256);
    entities_to_add = try std.ArrayList(Entity).initCapacity(allocator, 128);
    entity_indices_to_remove = try std.ArrayList(usize).initCapacity(allocator, 128);
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

            if (obj.props.static) {
                if (getSquarePtr(obj.x, obj.y)) |square| {
                    if (square.static_obj_id == obj.obj_id) square.static_obj_id = -1;
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
    entity_indices_to_remove.clearRetainingCapacity();
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
    entity_indices_to_remove.deinit();
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
        std.debug.panic("Minimap allocation failed: {}", .{e});
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
    std.debug.assert(!object_lock.tryLock());
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
    std.debug.assert(!object_lock.tryLock());
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

pub inline fn update(allocator: std.mem.Allocator) void {
    if (!object_lock.tryLock())
        return;
    defer object_lock.unlock();

    if (!add_lock.tryLock())
        return;
    entities.appendSlice(entities_to_add.items) catch |e| {
        std.log.err("Adding new entities failed: {}, returning", .{e});
        return;
    };
    entities_to_add.clearRetainingCapacity();
    add_lock.unlock();

    if (entities.items.len <= 0)
        return;

    entity_indices_to_remove.clearRetainingCapacity();

    interactive_id.store(-1, .Release);
    interactive_type.store(.game_object, .Release);

    const time = std.time.microTimestamp() - main.start_time;
    const dt: f32 = @floatFromInt(if (last_update > 0) time - last_update else 0);
    last_update = time;

    const cam_x = camera.x.load(.Acquire);
    const cam_y = camera.y.load(.Acquire);

    var interactive_set = false;
    @prefetch(entities.items, .{ .rw = .write });
    var iter = std.mem.reverseIterator(entities.items);
    var i: usize = entities.items.len - 1;
    while (iter.nextPtr()) |en| {
        defer i -%= 1;

        switch (en.*) {
            .player => |*player| {
                player.update(time, dt, allocator);
                if (player.obj_id == local_player_id) {
                    camera.update(player.x, player.y, dt, input.rotate);
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

                object.update(time, dt);
            },
            .projectile => |*projectile| {
                if (!projectile.update(time, dt, i, allocator)) {
                    entity_indices_to_remove.append(i) catch |e| {
                        std.log.err("Disposing entity at idx {d} failed: {}", .{ i, e });
                        return;
                    };
                }
            },
            .particle => |*pt| {
                switch (pt.*) {
                    inline else => |*particle| {
                        if (!particle.update(time, dt)) {
                            entity_indices_to_remove.append(i) catch |e| {
                                std.log.err("Disposing entity at idx {d} failed: {}", .{ i, e });
                                return;
                            };
                        }
                    },
                }
            },
            .particle_effect => |*pt_eff| {
                switch (pt_eff.*) {
                    inline else => |*effect| {
                        if (!effect.update(time, dt)) {
                            entity_indices_to_remove.append(i) catch |e| {
                                std.log.err("Disposing entity at idx {d} failed: {}", .{ i, e });
                                return;
                            };
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

    for (entity_indices_to_remove.items) |idx| {
        disposeEntity(allocator, &entities.items[idx]);
        _ = entities.swapRemove(idx);
    }

    if (entity_indices_to_remove.items.len > 0 or time - last_sort > 100 * std.time.us_per_ms) {
        std.sort.pdq(Entity, entities.items, {}, lessThan);
        last_sort = time;
    }
}

// x/y < 0 has to be handled before this, since it's a u32
pub inline fn validPos(x: u32, y: u32) bool {
    return !(x >= width or y >= height);
}

pub inline fn getSquare(x: f32, y: f32) ?Square {
    if (x < 0 or y < 0)
        return null;

    const floor_x: u32 = @intFromFloat(x);
    const floor_y: u32 = @intFromFloat(y);
    if (!validPos(floor_x, floor_y))
        return null;

    return squares.get(floor_y * width + floor_x);
}

pub inline fn getSquarePtr(x: f32, y: f32) ?*Square {
    if (x < 0 or y < 0)
        return null;

    const floor_x: u32 = @intFromFloat(x);
    const floor_y: u32 = @intFromFloat(y);
    if (!validPos(floor_x, floor_y))
        return null;

    return squares.getPtr(floor_y * width + floor_x);
}

pub fn addMoveRecord(time: i64, x: f32, y: f32) void {
    if (last_records_clear_time < 0)
        return;

    const id = getId(time);
    if (id < 1 or id > 10)
        return;

    if (move_records.items.len == 0) {
        move_records.append(.{ .time = time, .x = x, .y = y }) catch |e| {
            std.log.err("Adding move record failed: {}", .{e});
        };
        return;
    }

    const record_idx = move_records.items.len - 1;
    const curr_record = move_records.items[record_idx];
    const curr_id = getId(curr_record.time);
    if (id != curr_id) {
        move_records.append(.{ .time = time, .x = x, .y = y }) catch |e| {
            std.log.err("Adding move record failed: {}", .{e});
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
