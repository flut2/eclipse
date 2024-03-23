const std = @import("std");
const settings = @import("settings.zig");

const u16_max = std.math.maxInt(u16);

var client: std.http.Client = undefined;
var header_pool: std.heap.MemoryPool([u16_max]u8) = undefined;
var body_pool: std.heap.MemoryPool([u16_max]u8) = undefined;

pub fn init(allocator: std.mem.Allocator) void {
    client = .{ .allocator = allocator };
    header_pool = std.heap.MemoryPool([u16_max]u8).init(allocator);
    body_pool = std.heap.MemoryPool([u16_max]u8).init(allocator);
}

pub fn deinit() void {
    client.deinit();
    header_pool.deinit();
    body_pool.deinit();
}

pub fn sendRequest(comptime endpoint: []const u8, values: std.StringHashMap([]const u8)) ![]u8 {
    const header_buffer = try header_pool.create();
    defer header_pool.destroy(header_buffer);

    var req = client.open(.POST, try std.Uri.parse(settings.app_engine_uri ++ endpoint), .{ .server_header_buffer = header_buffer }) catch |e| {
        var err_buf: [u16_max]u8 = undefined;
        var stream = std.io.fixedBufferStream(&err_buf);

        var first = true;
        var iter = values.iterator();
        while (iter.next()) |entry| {
            if (first) {
                first = false;
            } else {
                _ = try stream.write(", ");
            }

            _ = try stream.write(entry.key_ptr.*);
            _ = try stream.write("=");
            _ = try stream.write(entry.value_ptr.*);
        }

        std.log.err("Could not send " ++ endpoint ++ " ({s}): {}", .{ stream.getWritten(), e });
        return @constCast("<RequestError/>"); // inelegant is an understatement
    };
    defer req.deinit();

    req.transfer_encoding = .chunked;
    try req.send(.{});

    const writer = req.writer();
    var iter = values.iterator();
    _ = try writer.write("?");
    while (iter.next()) |entry| {
        try writer.writeAll(entry.key_ptr.*);
        try writer.writeAll("=");
        try writer.writeAll(entry.value_ptr.*);
        if (iter.index < iter.hm.capacity()) {
            try writer.writeAll("&");
        }
    }

    try req.finish();
    try req.wait();

    const body_buffer = try body_pool.create();
    const len = try req.readAll(body_buffer);
    return body_buffer[0..len];
}

pub fn freeResponse(buf: []u8) void {
    if (std.mem.eql(u8, buf, "<RequestError/>"))
        return;

    body_pool.destroy(@ptrCast(@alignCast(buf)));
}
