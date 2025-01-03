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

pub fn parseMap(data_reader: anytype, arena: *std.heap.ArenaAllocator) !Map {
    const allocator = arena.allocator();
    var dcp = std.compress.zlib.decompressor(data_reader);
    var reader = dcp.reader();

    const version = try reader.readInt(u8, .little);
    if (version != 0) {
        std.log.err("Reading map failed, unsupported version: {}", .{version});
        return error.UnsupportedVersion;
    }

    var ret: Map = .{
        .x = try reader.readInt(u16, .little),
        .y = try reader.readInt(u16, .little),
        .w = try reader.readInt(u16, .little),
        .h = try reader.readInt(u16, .little),
        .tiles = undefined,
    };
    ret.tiles = try allocator.alloc(Tile, ret.w * ret.h);

    const tiles = try allocator.alloc(Tile, try reader.readInt(u16, .little));
    for (tiles) |*tile| {
        inline for (@typeInfo(Tile).@"struct".fields) |field| {
            const len = try reader.readInt(u16, .little);
            const buf = try allocator.alloc(u8, len);
            try reader.readNoEof(buf);
            @field(tile, field.name) = buf;
        }
    }

    var i: usize = 0;
    const byte_len = tiles.len <= 256;
    for (0..ret.h) |_| {
        for (0..ret.w) |_| {
            defer i += 1;
            const idx = if (byte_len) try reader.readInt(u8, .little) else try reader.readInt(u16, .little);
            ret.tiles[i] = tiles[idx];
        }
    }

    return ret;
}
