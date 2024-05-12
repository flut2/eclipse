const std = @import("std");

const u16_max = std.math.maxInt(u16);

var allocator: std.mem.Allocator = undefined;
var client: std.http.Client = undefined;
var header_pool: std.heap.MemoryPool([u16_max]u8) = undefined;
var body_pool: std.heap.MemoryPool([u16_max]u8) = undefined;

pub fn init(ally: std.mem.Allocator) void {
    allocator = ally;
    client = .{ .allocator = allocator };
    header_pool = std.heap.MemoryPool([u16_max]u8).init(allocator);
    body_pool = std.heap.MemoryPool([u16_max]u8).init(allocator);
}

pub fn deinit() void {
    client.deinit();
    header_pool.deinit();
    body_pool.deinit();
}

pub fn sendRequest(uri: []const u8, values: std.StringHashMap([]const u8)) ![]u8 {
    const header_buffer = try header_pool.create();
    defer header_pool.destroy(header_buffer);

    var mod_uri = std.ArrayList(u8).init(allocator);
    defer mod_uri.deinit();

    var mod_uri_writer = mod_uri.writer();
    var iter = values.iterator();
    var idx: usize = 0;
    _ = try mod_uri_writer.writeAll(uri);
    _ = try mod_uri_writer.write("?");
    while (iter.next()) |entry| : (idx += 1) {
        try mod_uri_writer.writeAll(entry.key_ptr.*);
        try mod_uri_writer.writeAll("=");
        try mod_uri_writer.writeAll(entry.value_ptr.*);
        if (idx < values.count() - 1) {
            try mod_uri_writer.writeAll("&");
        }
    }

    std.log.err("sending {s}", .{mod_uri.items});
    var req = client.open(.POST, try std.Uri.parse(mod_uri.items), .{ .server_header_buffer = header_buffer }) catch |e| {
        std.log.err("Could not send {s}: {}", .{ uri, e });
        return @constCast("<RequestError/>"); // inelegant is an understatement
    };
    defer req.deinit();

    req.transfer_encoding = .chunked;
    try req.send(.{});
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
