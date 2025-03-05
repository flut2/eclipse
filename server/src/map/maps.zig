const std = @import("std");

const shared = @import("shared");
const map_data = shared.map_data;
const game_data = shared.game_data;
const f32i = shared.utils.f32i;
const ziggy = @import("ziggy");

const main = @import("../main.zig");
const World = @import("../World.zig");
const Container = @import("Container.zig");
const Enemy = @import("Enemy.zig");
const Entity = @import("Entity.zig");
const Portal = @import("Portal.zig");
const Tile = @import("Tile.zig");

pub const retrieve_id = -1;

pub const LightData = struct {
    color: u32 = 0x000000,
    intensity: f32 = 0.0,
    day_intensity: f32 = 0.0,
    night_intensity: f32 = 0.0,
};

pub const MapType = enum { default, realm, dungeon, @"test" };

pub const MapDetails = struct {
    name: []const u8 = &.{},
    file: []const u8 = &.{},
    setpiece: bool = false,
    id: i32 = 0,
    light: LightData = .{},
    portal_name: ?[]const u8 = null,
    map_type: MapType = .default,
    normal_mobs: ?[][]const u8 = null,
    treasure_chance: f32 = 0.0,
    treasure_mobs: ?[][]const u8 = null,
    biome_1_mobs: ?[][]const u8 = null,
    biome_1_encounters: ?[][]const u8 = null,
    biome_1_spawn_target: u32 = 0,
    biome_1_encounter_chance: f32 = 0.0,
    biome_1_name: []const u8 = "Unknown Biome",
    biome_2_mobs: ?[][]const u8 = null,
    biome_2_encounters: ?[][]const u8 = null,
    biome_2_spawn_target: u32 = 0,
    biome_2_encounter_chance: f32 = 0.0,
    biome_2_name: []const u8 = "Unknown Biome",
    biome_3_mobs: ?[][]const u8 = null,
    biome_3_encounters: ?[][]const u8 = null,
    biome_3_spawn_target: u32 = 0,
    biome_3_encounter_chance: f32 = 0.0,
    biome_3_name: []const u8 = "Unknown Biome",

    pub const test_details: MapDetails = .{
        .name = "Test Map",
        .file = "",
        .setpiece = false,
        .id = std.math.minInt(u32),
        .light = .{},
        .portal_name = null,
        .map_type = .@"test",
    };
};

pub const MapData = struct {
    details: MapDetails,
    w: u16,
    h: u16,
    tiles: []const Tile,
    entities: []const Entity,
    enemies: []const Enemy,
    portals: []const Portal,
    containers: []const Container,
    regions: std.AutoHashMapUnmanaged(u16, []World.WorldPoint),

    pub fn deinit(self: *MapData) void {
        var regions_iter = self.regions.valueIterator();
        while (regions_iter.next()) |points| main.allocator.free(points.*);
        main.allocator.free(self.tiles);
        main.allocator.free(self.entities);
        main.allocator.free(self.enemies);
        main.allocator.free(self.portals);
        main.allocator.free(self.containers);
    }
};

pub var setpieces: std.StringHashMapUnmanaged(MapData) = .{};
pub var maps: std.AutoHashMapUnmanaged(u16, MapData) = .{};
pub var worlds: std.AutoArrayHashMapUnmanaged(i32, World) = .{};
pub var next_world_id: i32 = 0;

pub fn parseMap(reader: anytype, details: MapDetails) !MapData {
    var tiles: std.ArrayListUnmanaged(Tile) = .empty;
    var entities: std.ArrayListUnmanaged(Entity) = .empty;
    var enemies: std.ArrayListUnmanaged(Enemy) = .empty;
    var portals: std.ArrayListUnmanaged(Portal) = .empty;
    var containers: std.ArrayListUnmanaged(Container) = .empty;
    var regions: std.AutoHashMapUnmanaged(u16, std.ArrayListUnmanaged(World.WorldPoint)) = .empty;
    defer {
        tiles.deinit(main.allocator);
        entities.deinit(main.allocator);
        enemies.deinit(main.allocator);
        portals.deinit(main.allocator);
        containers.deinit(main.allocator);
        regions.deinit(main.allocator);
    }

    var map: MapData = undefined;
    map.details = details;
    map.details.name = try main.allocator.dupe(u8, details.name);

    tiles.clearRetainingCapacity();
    entities.clearRetainingCapacity();
    enemies.clearRetainingCapacity();
    portals.clearRetainingCapacity();
    containers.clearRetainingCapacity();
    regions.clearRetainingCapacity();

    var map_arena: std.heap.ArenaAllocator = .init(main.allocator);
    defer map_arena.deinit();
    const parsed_map = try map_data.parseMap(reader, &map_arena);
    for (parsed_map.tiles, 0..) |tile, i| {
        const ux: u16 = @intCast(i % parsed_map.w);
        const uy: u16 = @intCast(@divFloor(i, parsed_map.w));
        const fx = f32i(ux) + 0.5;
        const fy = f32i(uy) + 0.5;

        if (tile.ground_name.len > 0) {
            const data = game_data.ground.from_name.getPtr(tile.ground_name) orelse @panic("Tile had no data attached");
            try tiles.append(main.allocator, .{ .x = ux, .y = uy, .data_id = data.id, .data = data });
        } else try tiles.append(main.allocator, .{ .x = ux, .y = uy, .data_id = std.math.maxInt(u16) });

        if (tile.region_name.len > 0) {
            const data = game_data.region.from_name.get(tile.region_name) orelse @panic("Region had no data attached");

            if (regions.getPtr(data.id)) |list| {
                try list.append(main.allocator, .{ .x = ux, .y = uy });
            } else {
                var list: std.ArrayListUnmanaged(World.WorldPoint) = .empty;
                try list.append(main.allocator, .{ .x = ux, .y = uy });
                try regions.put(main.allocator, data.id, list);
            }
        }

        if (tile.entity_name.len > 0) {
            const data = game_data.entity.from_name.getPtr(tile.entity_name) orelse @panic("Entity had no data attached");
            try entities.append(main.allocator, .{ .x = fx, .y = fy, .data_id = data.id, .data = data });
        }

        if (tile.enemy_name.len > 0) {
            const data = game_data.enemy.from_name.getPtr(tile.enemy_name) orelse @panic("Enemy had no data attached");
            try enemies.append(main.allocator, .{ .x = fx, .y = fy, .data_id = data.id, .data = data });
        }

        if (tile.portal_name.len > 0) {
            const data = game_data.portal.from_name.getPtr(tile.portal_name) orelse @panic("Portal had no data attached");
            try portals.append(main.allocator, .{ .x = fx, .y = fy, .data_id = data.id, .data = data });
        }

        if (tile.container_name.len > 0) {
            const data = game_data.container.from_name.getPtr(tile.container_name) orelse @panic("Container had no data attached");
            try containers.append(main.allocator, .{ .x = fx, .y = fy, .data_id = data.id, .data = data });
        }
    }

    map.w = parsed_map.w;
    map.h = parsed_map.h;
    map.tiles = try main.allocator.dupe(Tile, tiles.items);
    map.entities = try main.allocator.dupe(Entity, entities.items);
    map.enemies = try main.allocator.dupe(Enemy, enemies.items);
    map.portals = try main.allocator.dupe(Portal, portals.items);
    map.containers = try main.allocator.dupe(Container, containers.items);

    map.regions = .{};
    var region_iter = regions.iterator();
    while (region_iter.next()) |entry| {
        try map.regions.put(main.allocator, entry.key_ptr.*, try main.allocator.dupe(World.WorldPoint, entry.value_ptr.*.items));
    }

    return map;
}

pub fn init() !void {
    const file = try std.fs.cwd().openFile("./assets/worlds/maps.ziggy", .{});
    defer file.close();

    const file_data = try file.readToEndAllocOptions(main.allocator, std.math.maxInt(u32), null, @alignOf(u8), 0);
    defer main.allocator.free(file_data);

    for (try ziggy.parseLeaky([]MapDetails, main.allocator, file_data, .{})) |details| {
        const path = try std.fmt.allocPrint(main.allocator, "./assets/worlds/{s}", .{details.file});
        defer main.allocator.free(path);

        const map_file = try std.fs.cwd().openFile(path, .{});
        defer map_file.close();

        var map = try parseMap(map_file.reader(), details);

        const portal_id = if (details.portal_name) |name|
            (game_data.portal.from_name.get(name) orelse @panic("Given portal name has no data")).id
        else
            std.math.maxInt(u16);
        if (portal_id == std.math.maxInt(u16) and details.id >= 0) {
            map.deinit();
            continue;
        }

        if (details.id < 0) {
            try worlds.put(main.allocator, details.id, try .create(map.w, map.h, details.id));
            var new_world = worlds.getPtr(details.id).?;
            try new_world.appendMap(map);
            std.log.info("Added persistent world \"{s}\" (id {})", .{ details.name, details.id });
        }

        if (portal_id != std.math.maxInt(u16))
            try maps.put(main.allocator, portal_id, map);

        std.log.info("Parsed world \"{s}\"", .{details.name});
    }
}

pub fn deinit() void {
    var setpiece_iter = setpieces.valueIterator();
    while (setpiece_iter.next()) |setpiece| setpiece.deinit();
    setpieces.deinit(main.allocator);

    var map_iter = maps.valueIterator();
    while (map_iter.next()) |map| map.deinit();
    maps.deinit(main.allocator);

    for (worlds.values()) |*w| w.deinit();
    worlds.deinit(main.allocator);
}

pub fn portalWorld(portal_type: u16, portal_map_id: u32) !?*World {
    var world_iter = worlds.iterator();
    while (world_iter.next()) |w| if (w.value_ptr.owner_portal_id == portal_map_id) return w.value_ptr;

    if (maps.get(portal_type)) |map| {
        if (map.details.id < 0) return worlds.getPtr(map.details.id);

        try worlds.put(main.allocator, next_world_id, try .create(map.w, map.h, next_world_id));
        defer next_world_id += 1;

        std.log.info("Added world \"{s}\" (id {})", .{ map.details.name, next_world_id });

        var new_world = worlds.getPtr(next_world_id).?;
        try new_world.appendMap(map);
        new_world.owner_portal_id = portal_map_id;
        return new_world;
    } else return null;
}

pub fn testWorld(data: []const u8) !*World {
    var fbs = std.io.fixedBufferStream(data);
    const map = try parseMap(fbs.reader(), .test_details);

    try worlds.put(main.allocator, next_world_id, try .create(map.w, map.h, next_world_id));
    defer next_world_id += 1;

    std.log.info("Added test world (id {})", .{next_world_id});

    var new_world = worlds.getPtr(next_world_id).?;
    try new_world.appendMap(map);
    return new_world;
}
