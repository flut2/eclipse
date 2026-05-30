const std = @import("std");

const ziggy = @import("ziggy");

const main = @import("main.zig");

const Settings = @This();

var arena: std.heap.ArenaAllocator = .{ .state = .init, .child_allocator = .failing };

game_port: u16 = 3328,
login_port: u16 = 2833,
redis_ip: []const u8 = "127.0.0.1",
redis_port: u16 = 6379,
redis_db_id: u8 = 0,
public_ip: []const u8 = "127.0.0.1",
server_name: []const u8 = "Eclipse",
build_version: []const u8 = "0.1",
tps: u16 = 10,

pub fn init(allocator: std.mem.Allocator) !Settings {
    arena = .init(allocator);
    errdefer arena.deinit();
    const arena_allocator = arena.allocator();

    const file_path = "assets/server/settings.ziggy";
    const file = std.Io.Dir.cwd().openFile(main.io, file_path, .{}) catch @panic("Settings file not found");
    defer file.close(main.io);

    var read_buf: [1024]u8 = undefined;
    var reader = file.reader(main.io, &read_buf);

    const bytes = try reader.interface.allocRemainingAlignedSentinel(arena_allocator, .unlimited, .of(u8), 0);
    defer arena_allocator.free(bytes);

    var stdout: std.Io.File = .stdout();
    var stdout_buf: [4096]u8 = undefined;
    var stdout_wtr = stdout.writer(main.io, &stdout_buf);

    var meta: ziggy.Deserializer.Meta = .init;
    return ziggy.deserializeLeaky(Settings, arena_allocator, bytes, &meta, .{ .copy_strings = .always }) catch |e| {
        if (e != error.OutOfMemory) {
            try meta.reportErrors(arena_allocator, .{}, file_path, bytes, e, &stdout_wtr.interface);
            try stdout_wtr.interface.flush();
        }
        return e;
    };
}

pub fn deinit() void {
    arena.deinit();
}
