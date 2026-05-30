pub const std = @import("std");

pub const Tile = struct {
    ground_name: []const u8,
    entity_name: []const u8,
    enemy_name: []const u8,
    portal_name: []const u8,
    container_name: []const u8,
    region_name: []const u8,
};

pub const Map = struct {
    x: u16,
    y: u16,
    w: u16,
    h: u16,
    tiles: []Tile,
};

pub fn parseMap(buffer: []const u8, arena: *std.heap.ArenaAllocator) !Map {
    const allocator = arena.allocator();
    var reader: std.Io.Reader = .fixed(buffer);

    const version = try reader.takeInt(u8, .little);
    if (version != 0) {
        std.log.err("Reading map failed, unsupported version: {}", .{version});
        return error.UnsupportedVersion;
    }

    var ret: Map = .{
        .x = try reader.takeInt(u16, .little),
        .y = try reader.takeInt(u16, .little),
        .w = try reader.takeInt(u16, .little),
        .h = try reader.takeInt(u16, .little),
        .tiles = undefined,
    };
    ret.tiles = try allocator.alloc(Tile, @as(u32, ret.w) * @as(u32, ret.h));

    const tiles = try allocator.alloc(Tile, try reader.takeInt(u16, .little));
    for (tiles) |*tile| {
        inline for (@typeInfo(Tile).@"struct".fields) |field| {
            const len = try reader.takeInt(u16, .little);
            const buf = try allocator.alloc(u8, len);
            try reader.readSliceAll(buf);
            @field(tile, field.name) = buf;
        }
    }

    var i: usize = 0;
    const byte_len = tiles.len <= 256;
    for (0..ret.h) |_| {
        for (0..ret.w) |_| {
            defer i += 1;
            const idx = if (byte_len) try reader.takeInt(u8, .little) else try reader.takeInt(u16, .little);
            ret.tiles[i] = tiles[idx];
        }
    }

    return ret;
}
