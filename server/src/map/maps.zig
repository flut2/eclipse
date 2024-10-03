const std = @import("std");
const shared = @import("shared");
const map_data = shared.map_data;
const game_data = shared.game_data;
const main = @import("../main.zig");
const world = @import("../world.zig");

const Tile = @import("tile.zig").Tile;
const Entity = @import("entity.zig").Entity;
const Enemy = @import("enemy.zig").Enemy;
const Portal = @import("portal.zig").Portal;
const Container = @import("container.zig").Container;
const World = world.World;

pub const retrieve_id = -1;

pub const LightData = struct {
    color: u32 = 0x000000,
    intensity: f32 = 0.0,
    day_intensity: f32 = 0.0,
    night_intensity: f32 = 0.0,

    pub fn jsonParse(ally: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(source.*))!@This() {
        return game_data.jsonParseWithHex(@This(), ally, source, options);
    }

    pub const jsonStringify = @compileError("Not supported");
};

pub const MapType = enum { default, realm, @"test" };

pub const MapDetails = struct {
    name: []const u8,
    file: []const u8,
    setpiece: bool = false,
    id: i32 = 0,
    light: LightData = .{},
    portal_name: ?[]const u8 = null,
    map_type: MapType = .default,

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
    regions: std.AutoHashMapUnmanaged(u16, []world.WorldPoint),

    pub fn deinit(self: *MapData, ally: std.mem.Allocator) void {
        var regions_iter = self.regions.valueIterator();
        while (regions_iter.next()) |points| ally.free(points.*);
        ally.free(self.tiles);
        ally.free(self.entities);
        ally.free(self.enemies);
        ally.free(self.portals);
        ally.free(self.containers);
    }
};

pub var setpieces: std.StringHashMapUnmanaged(MapData) = .{};
pub var maps: std.AutoHashMapUnmanaged(u16, MapData) = .{};
pub var worlds: std.AutoArrayHashMapUnmanaged(i32, World) = .{};
pub var next_world_id: i32 = 0;
pub var allocator: std.mem.Allocator = undefined;
var arena: std.heap.ArenaAllocator = undefined;

pub fn parseMap(reader: anytype, details: MapDetails) !MapData {
    var tiles: std.ArrayListUnmanaged(Tile) = .empty;
    var entities: std.ArrayListUnmanaged(Entity) = .empty;
    var enemies: std.ArrayListUnmanaged(Enemy) = .empty;
    var portals: std.ArrayListUnmanaged(Portal) = .empty;
    var containers: std.ArrayListUnmanaged(Container) = .empty;
    var regions: std.AutoHashMapUnmanaged(u16, std.ArrayListUnmanaged(world.WorldPoint)) = .empty;
    defer {
        tiles.deinit(allocator);
        entities.deinit(allocator);
        enemies.deinit(allocator);
        portals.deinit(allocator);
        containers.deinit(allocator);
        regions.deinit(allocator);
    }

    var map: MapData = undefined;
    map.details = details;
    map.details.name = try allocator.dupe(u8, details.name);

    tiles.clearRetainingCapacity();
    entities.clearRetainingCapacity();
    enemies.clearRetainingCapacity();
    portals.clearRetainingCapacity();
    containers.clearRetainingCapacity();
    regions.clearRetainingCapacity();

    var map_arena: std.heap.ArenaAllocator = .init(allocator);
    defer map_arena.deinit();
    const parsed_map = try map_data.parseMap(reader, &map_arena);
    for (parsed_map.tiles, 0..) |tile, i| {
        const ux: u16 = @intCast(i % parsed_map.w);
        const uy: u16 = @intCast(@divFloor(i, parsed_map.w));
        const fx: f32 = @floatFromInt(ux);
        const fy: f32 = @floatFromInt(uy);

        if (tile.ground_name.len > 0) {
            const data = game_data.ground.from_name.getPtr(tile.ground_name) orelse @panic("Tile had no data attached");
            try tiles.append(allocator, .{ .x = ux, .y = uy, .data_id = data.id, .data = data });
        } else try tiles.append(allocator, .{ .x = ux, .y = uy, .data_id = std.math.maxInt(u16) });

        if (tile.region_name.len > 0) {
            const data = game_data.region.from_name.get(tile.region_name) orelse @panic("Region had no data attached");

            if (regions.getPtr(data.id)) |list| {
                try list.append(allocator, .{ .x = ux, .y = uy });
            } else {
                var list: std.ArrayListUnmanaged(world.WorldPoint) = .empty;
                try list.append(allocator, .{ .x = ux, .y = uy });
                try regions.put(allocator, data.id, list);
            }
        }

        if (tile.entity_name.len > 0) {
            const data = game_data.entity.from_name.getPtr(tile.entity_name) orelse @panic("Entity had no data attached");
            try entities.append(allocator, .{ .x = fx, .y = fy, .data_id = data.id, .data = data });
        }

        if (tile.enemy_name.len > 0) {
            const data = game_data.enemy.from_name.getPtr(tile.enemy_name) orelse @panic("Enemy had no data attached");
            try enemies.append(allocator, .{ .x = fx, .y = fy, .data_id = data.id, .data = data });
        }

        if (tile.portal_name.len > 0) {
            const data = game_data.portal.from_name.getPtr(tile.portal_name) orelse @panic("Portal had no data attached");
            try portals.append(allocator, .{ .x = fx, .y = fy, .data_id = data.id, .data = data });
        }

        if (tile.container_name.len > 0) {
            const data = game_data.container.from_name.getPtr(tile.container_name) orelse @panic("Container had no data attached");
            try containers.append(allocator, .{ .x = fx, .y = fy, .data_id = data.id, .data = data });
        }
    }

    map.w = parsed_map.w;
    map.h = parsed_map.h;
    map.tiles = try allocator.dupe(Tile, tiles.items);
    map.entities = try allocator.dupe(Entity, entities.items);
    map.enemies = try allocator.dupe(Enemy, enemies.items);
    map.portals = try allocator.dupe(Portal, portals.items);
    map.containers = try allocator.dupe(Container, containers.items);

    map.regions = .{};
    var region_iter = regions.iterator();
    while (region_iter.next()) |entry| {
        try map.regions.put(allocator, entry.key_ptr.*, try allocator.dupe(world.WorldPoint, entry.value_ptr.*.items));
    }

    return map;
}

pub fn init(ally: std.mem.Allocator) !void {
    arena = std.heap.ArenaAllocator.init(ally);
    allocator = arena.allocator();

    const file = try std.fs.cwd().openFile("./assets/worlds/maps.json", .{});
    defer file.close();

    const file_data = try file.readToEndAlloc(allocator, std.math.maxInt(u32));
    defer allocator.free(file_data);

    for (try std.json.parseFromSliceLeaky([]MapDetails, allocator, file_data, .{})) |details| {
        const path = try std.fmt.allocPrint(allocator, "./assets/worlds/{s}", .{details.file});
        defer allocator.free(path);

        const map_file = try std.fs.cwd().openFile(path, .{});
        defer map_file.close();

        var map = try parseMap(map_file.reader(), details);

        const portal_id = if (details.portal_name) |name|
            (game_data.portal.from_name.get(name) orelse @panic("Given portal name has no data")).id
        else
            std.math.maxInt(u16);
        if (portal_id == std.math.maxInt(u16) and details.id >= 0) {
            map.deinit(allocator);
            continue;
        }

        if (details.id < 0) {
            try worlds.put(allocator, details.id, try World.create(allocator, map.w, map.h, details.id));
            var new_world = worlds.getPtr(details.id).?;
            try new_world.appendMap(map);
            std.log.info("Added persistent world \"{s}\" (id {})", .{ details.name, details.id });
        }

        if (portal_id != std.math.maxInt(u16))
            try maps.put(allocator, portal_id, map);

        std.log.info("Parsed world \"{s}\"", .{details.name});
    }
}

pub fn deinit() void {
    arena.deinit();
}

pub fn portalWorld(portal_type: u16, portal_map_id: u32) !?*World {
    var world_iter = worlds.iterator();
    while (world_iter.next()) |w| if (w.value_ptr.owner_portal_id == portal_map_id) return w.value_ptr;

    if (maps.get(portal_type)) |map| {
        if (map.details.id < 0) return worlds.getPtr(map.details.id);

        try worlds.put(allocator, next_world_id, try World.create(allocator, map.w, map.h, next_world_id));
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

    try worlds.put(allocator, next_world_id, try World.create(allocator, map.w, map.h, next_world_id));
    defer next_world_id += 1;

    std.log.info("Added test world (id {})", .{ next_world_id });

    var new_world = worlds.getPtr(next_world_id).?;
    try new_world.appendMap(map);
    return new_world;
}
