const std = @import("std");
const game_data = @import("shared").game_data;
const xml = @import("shared").xml;
const main = @import("../main.zig");
const world = @import("../world.zig");

const Tile = @import("tile.zig").Tile;
const Entity = @import("entity.zig").Entity;
const Enemy = @import("enemy.zig").Enemy;
const World = world.World;

pub const retrieve_id = -1;

pub const LightData = struct {
    light_color: u32 = 0x000000,
    light_intensity: f32 = 0.0,
    day_light_intensity: f32 = 0.0,
    night_light_intensity: f32 = 0.0,

    pub fn parse(node: xml.Node) !LightData {
        return .{
            .light_color = try node.currentValueInt(u32, 0x000000),
            .light_intensity = try node.getAttributeFloat("intensity", f32, 0.0),
            .day_light_intensity = try node.getAttributeFloat("dayIntensity", f32, 0.0),
            .night_light_intensity = try node.getAttributeFloat("nightIntensity", f32, 0.0),
        };
    }
};

const MapData = struct {
    id: i32,
    w: u16,
    h: u16,
    name: []const u8,
    tiles: []const Tile,
    entities: []const Entity,
    enemies: []const Enemy,
    regions: std.EnumArray(game_data.RegionType, []world.WorldPoint),
    light: LightData = .{},

    pub fn deinit(self: *MapData, ally: std.mem.Allocator) void {
        var regions_iter = self.regions.iterator();
        while (regions_iter.next()) |entry| {
            ally.free(entry.value.*);
        }
        ally.free(self.name);
        ally.free(self.tiles);
        ally.free(self.entities);
        ally.free(self.enemies);
    }
};

pub var setpieces: std.StringHashMap(MapData) = undefined;
pub var maps: std.AutoHashMap(u16, MapData) = undefined;
pub var worlds: std.AutoArrayHashMap(i32, World) = undefined;
pub var next_world_id: i32 = 0;
pub var allocator: std.mem.Allocator = undefined;

pub fn init(ally: std.mem.Allocator) !void {
    allocator = ally;
    worlds = std.AutoArrayHashMap(i32, World).init(allocator);
    setpieces = std.StringHashMap(MapData).init(allocator);
    maps = std.AutoHashMap(u16, MapData).init(allocator);

    const doc = try xml.Doc.fromFile("./assets/worlds/maps.xml");
    defer doc.deinit();
    const root = try doc.getRootElement();

    var enemies = std.ArrayList(Enemy).init(allocator);
    defer enemies.deinit();
    var entities = std.ArrayList(Entity).init(allocator);
    defer entities.deinit();
    var regions = std.EnumArray(game_data.RegionType, std.ArrayList(world.WorldPoint)).initFill(std.ArrayList(world.WorldPoint).init(allocator));
    defer {
        var regions_iter = regions.iterator();
        while (regions_iter.next()) |entry| {
            entry.value.deinit();
        }
    }

    var maps_iter = root.iterate(&.{}, "Map");
    while (maps_iter.next()) |node| {
        const file_name = node.getValue("File") orelse continue;
        const path = try std.fmt.allocPrint(allocator, "./assets/worlds/{s}", .{file_name});
        defer allocator.free(path);

        var map_data: MapData = undefined;
        map_data.id = try node.getAttributeInt("id", i32, 0);
        map_data.name = try node.getValueAlloc("Name", allocator, "Unknown Map");
        const light_node = node.findChild("Light");
        map_data.light = if (light_node) |ln| try LightData.parse(ln) else .{};

        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        var dcp = std.compress.zlib.decompressor(file.reader());

        const version = try dcp.reader().readInt(u8, .little);
        if (version != 2)
            std.log.err("Reading map failed, unsupported version: {d}", .{version});

        _ = try dcp.reader().readInt(u16, .little); // x, for editor
        _ = try dcp.reader().readInt(u16, .little); // y, for editor
        map_data.w = try dcp.reader().readInt(u16, .little);
        map_data.h = try dcp.reader().readInt(u16, .little);

        var tiles = try allocator.alloc(Tile, @as(u32, map_data.w) * @as(u32, map_data.h));
        defer allocator.free(tiles);

        const MapTile = struct {
            tile_type: u16,
            obj_type: u16,
            region_type: u8,
        };

        const map_tiles = try allocator.alloc(MapTile, try dcp.reader().readInt(u16, .little));
        defer allocator.free(map_tiles);
        for (map_tiles) |*tile| {
            tile.* = .{
                .tile_type = try dcp.reader().readInt(u16, .little),
                .obj_type = try dcp.reader().readInt(u16, .little),
                .region_type = try dcp.reader().readInt(u8, .little),
            };
        }

        enemies.clearRetainingCapacity();
        entities.clearRetainingCapacity();
        var regions_iter = regions.iterator();
        while (regions_iter.next()) |entry| {
            entry.value.clearRetainingCapacity();
        }

        var next_obj_id: i32 = 0;
        const byte_len = map_tiles.len <= 256;
        for (0..map_data.h) |y| {
            for (0..map_data.w) |x| {
                const ux: u16 = @intCast(x);
                const uy: u16 = @intCast(y);
                const fx: f32 = @floatFromInt(x);
                const fy: f32 = @floatFromInt(y);

                const idx = if (byte_len) try dcp.reader().readInt(u8, .little) else try dcp.reader().readInt(u16, .little);
                const tile = map_tiles[idx];
                if (tile.tile_type != std.math.maxInt(u16)) {
                    tiles[y * map_data.w + x] = .{
                        .x = ux,
                        .y = uy,
                        .tile_type = tile.tile_type,
                        .props = game_data.ground_type_to_props.getPtr(tile.tile_type) orelse {
                            std.log.err("Could not find props for tile with type 0x{x}", .{tile.tile_type});
                            continue;
                        },
                    };
                }

                if (tile.obj_type != std.math.maxInt(u16)) {
                    const props = game_data.obj_type_to_props.getPtr(tile.obj_type) orelse {
                        std.log.err("Could not find props for object with type 0x{x}", .{tile.obj_type});
                        continue;
                    };

                    if (props.is_enemy) {
                        try enemies.append(.{
                            .x = fx + 0.5,
                            .y = fy + 0.5,
                            .en_type = tile.obj_type,
                            .obj_id = next_obj_id,
                            .props = props,
                        });
                    } else {
                        try entities.append(.{
                            .x = fx + 0.5,
                            .y = fy + 0.5,
                            .en_type = tile.obj_type,
                            .obj_id = next_obj_id,
                            .props = props,
                        });
                    }

                    next_obj_id += 1;
                }

                if (tile.region_type != std.math.maxInt(u8)) {
                    const region_type = game_data.region_type_to_enum.get(tile.region_type) orelse {
                        std.log.err("Could not find enum for region with type 0x{x}", .{tile.region_type});
                        continue;
                    };

                    var list = regions.getPtr(region_type);
                    try list.append(.{ .x = ux, .y = uy });
                }
            }
        }

        const portal_name = node.getValue("PortalName");
        const portal_type = if (portal_name) |name| game_data.obj_name_to_type.get(name) else 0xFFFF;
        if (portal_type == 0xFFFF and map_data.id >= 0) {
            map_data.deinit(allocator);
            continue;
        }

        map_data.tiles = try allocator.dupe(Tile, tiles);
        map_data.enemies = try allocator.dupe(Enemy, enemies.items);
        map_data.entities = try allocator.dupe(Entity, entities.items);
        map_data.regions = std.EnumArray(game_data.RegionType, []world.WorldPoint).initUndefined();
        for (regions.values, &map_data.regions.values) |list, *slice| {
            slice.* = try allocator.dupe(world.WorldPoint, list.items);
        }

        if (map_data.id < 0) {
            try worlds.put(map_data.id, try World.create(allocator, map_data.w, map_data.h, map_data.name, map_data.light));
            var new_world = worlds.getPtr(map_data.id).?;
            @memcpy(new_world.tiles, map_data.tiles);
            var new_region_iter = map_data.regions.iterator();
            while (new_region_iter.next()) |entry| {
                new_world.regions.set(entry.key, entry.value.*);
            }

            {
                new_world.enemy_lock.lock();
                defer new_world.enemy_lock.unlock();
                for (map_data.enemies) |e| {
                    var enemy = Enemy{
                        .x = e.x,
                        .y = e.y,
                        .en_type = e.en_type,
                    };
                    _ = try new_world.add(Enemy, &enemy);
                }
            }

            {
                new_world.entity_lock.lock();
                defer new_world.entity_lock.unlock();
                for (map_data.entities) |e| {
                    var entity = Entity{
                        .x = e.x,
                        .y = e.y,
                        .en_type = e.en_type,
                    };
                    _ = try new_world.add(Entity, &entity);
                }
            }

            std.log.info("Added persistent world '{s}' (id {d})", .{ map_data.name, map_data.id });
        }

        if (portal_type != 0xFFFF)
            try maps.put(portal_type.?, map_data);

        std.log.info("Parsed world '{s}'", .{map_data.name});
    }
}

pub fn deinit() void {
    var world_iter = worlds.iterator();
    while (world_iter.next()) |w| {
        w.value_ptr.deinit();
    }
    worlds.deinit();

    var setpiece_iter = setpieces.valueIterator();
    while (setpiece_iter.next()) |setpiece| {
        setpiece.deinit(allocator);
    }
    setpieces.deinit();

    var map_iter = maps.valueIterator();
    while (map_iter.next()) |map| {
        map.deinit(allocator);
    }
    maps.deinit();
}

pub fn portalWorld(portal_type: u16, portal_obj_id: i32) !?*World {
    var world_iter = worlds.iterator();
    while (world_iter.next()) |w| {
        if (w.value_ptr.owner_portal_id == portal_obj_id)
            return w.value_ptr;
    }

    if (maps.get(portal_type)) |map_data| {
        if (map_data.id < 0)
            return worlds.getPtr(map_data.id);

        try worlds.put(next_world_id, try World.create(allocator, map_data.w, map_data.h, map_data.name, map_data.light));
        std.log.info("Added world '{s}' (id {d})", .{ map_data.name, next_world_id });
        next_world_id += 1;
        if (worlds.getPtr(next_world_id - 1)) |new_world| {
            new_world.owner_portal_id = portal_obj_id;
            @memcpy(new_world.tiles, map_data.tiles);
            var regions_copy = map_data.regions;
            var new_region_iter = regions_copy.iterator();
            while (new_region_iter.next()) |entry| {
                new_world.regions.set(entry.key, entry.value.*);
            }

            {
                new_world.enemy_lock.lock();
                defer new_world.enemy_lock.unlock();
                for (map_data.enemies) |e| {
                    var enemy = Enemy{
                        .x = e.x,
                        .y = e.y,
                        .en_type = e.en_type,
                    };
                    _ = try new_world.add(Enemy, &enemy);
                }
            }

            {
                new_world.entity_lock.lock();
                defer new_world.entity_lock.unlock();
                for (map_data.entities) |e| {
                    var entity = Entity{
                        .x = e.x,
                        .y = e.y,
                        .en_type = e.en_type,
                    };
                    _ = try new_world.add(Entity, &entity);
                }
            }

            return new_world;
        } else return null;
    } else return null;
}
