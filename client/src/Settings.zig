const std = @import("std");
const builtin = @import("builtin");

const ziggy = @import("ziggy");

const assets = @import("assets.zig");
const glfw = @import("glfw");
const main = @import("main.zig");

const Self = @This();

pub const CursorType = enum { basic, royal, ranger, aztec, fiery, target_enemy, target_ally };
pub const Button = union(enum) { key: glfw.Key, mouse: glfw.MouseButton };

var arena: std.heap.ArenaAllocator = undefined;

move_left: Button = .{ .key = .a },
move_right: Button = .{ .key = .d },
move_up: Button = .{ .key = .w },
move_down: Button = .{ .key = .s },
ability_1: Button = .{ .key = .q },
ability_2: Button = .{ .key = .e },
ability_3: Button = .{ .key = .r },
ability_4: Button = .{ .key = .f },
interact: Button = .{ .key = .x },
options: Button = .{ .key = .escape },
escape: Button = .{ .key = .tab },
chat_up: Button = .{ .key = .page_up },
chat_down: Button = .{ .key = .page_down },
walk: Button = .{ .key = .left_shift },
toggle_perf_stats: Button = .{ .key = .F3 },
chat: Button = .{ .key = .enter },
chat_cmd: Button = .{ .key = .slash },
respond: Button = .{ .key = .F2 },
shoot: Button = .{ .mouse = .left },
sfx_volume: f32 = 0.33,
music_volume: f32 = 0.1,
enable_vsync: bool = true,
enable_lights: bool = true,
stats_enabled: bool = true,
remember_login: bool = true,
cursor_type: CursorType = .aztec,
last_char_id: u32 = std.math.maxInt(u32),

pub fn init(allocator: std.mem.Allocator) !Self {
    arena = .init(allocator);
    const arena_allocator = arena.allocator();

    const file = std.fs.cwd().openFile("settings.ziggy", .{}) catch return .{};
    defer file.close();

    const file_data = try file.readToEndAllocOptions(arena_allocator, std.math.maxInt(u32), null, @alignOf(u8), 0);
    defer arena_allocator.free(file_data);

    return try ziggy.parseLeaky(Self, arena_allocator, file_data, .{});
}

pub fn deinit(self: Self) void {
    self.save() catch |e| {
        std.log.err("Settings save failed: {}", .{e});
        return;
    };

    arena.deinit();
}

pub fn save(self: Self) !void {
    const file = try std.fs.cwd().createFile("settings.ziggy", .{});
    defer file.close();

    try ziggy.stringify(self, .{ .whitespace = .space_4 }, file.writer());
}

pub fn resetToDefaults(self: *Self) void {
    inline for (@typeInfo(Self).@"struct".fields) |field|
        @field(self, field.name) = @as(*const field.type, @ptrCast(@alignCast(field.default_value_ptr orelse
            @panic("All settings need a default value, but it wasn't found")))).*;
}
