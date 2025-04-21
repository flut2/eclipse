const std = @import("std");
const ziggy = @import("ziggy");

const Settings = @This();

var arena: std.heap.ArenaAllocator = undefined;

game_port: u16 = 3328,
login_port: u16 = 2833,
redis_ip: []const u8 = "127.0.0.1",
redis_port: u16 = 6379,
public_ip: []const u8 = "127.0.0.1",
server_name: []const u8 = "Eclipse",
build_version: []const u8 = "0.1",
tps: u16 = 30,

pub fn init(allocator: std.mem.Allocator) !Settings {
    arena = std.heap.ArenaAllocator.init(allocator);
    const arena_allocator = arena.allocator();

    const file = std.fs.cwd().openFile("assets/settings.ziggy", .{}) catch @panic("Settings file not found");
    defer file.close();

    const file_data = try file.readToEndAllocOptions(arena_allocator, std.math.maxInt(u32), null, .fromByteUnits(@alignOf(u8)), 0);
    defer arena_allocator.free(file_data);

    return try ziggy.parseLeaky(Settings, arena_allocator, file_data, .{});
}

pub fn deinit() void {
    arena.deinit();
}
