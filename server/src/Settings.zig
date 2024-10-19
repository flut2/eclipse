const std = @import("std");

const Settings = @This();

var arena: std.heap.ArenaAllocator = undefined;

game_port: u16 = 3328,
login_port: u16 = 2833,
redis_ip: []const u8 = "127.0.0.1",
redis_port: u16 = 6379,
public_ip: []const u8 = "127.0.0.1",
server_name: []const u8 = "Eclipse",
build_version: []const u8 = "1.0",
tps: u16 = 30,

pub fn init(allocator: std.mem.Allocator) !Settings {
    arena = std.heap.ArenaAllocator.init(allocator);
    const arena_allocator = arena.allocator();

    const file = std.fs.cwd().openFile("assets/settings.json", .{}) catch @panic("Settings file not found");
    defer file.close();

    const file_data = try file.readToEndAlloc(arena_allocator, std.math.maxInt(u32));
    defer arena_allocator.free(file_data);

    return try std.json.parseFromSliceLeaky(Settings, arena_allocator, file_data, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
}

pub fn deinit() void {
    arena.deinit();
}