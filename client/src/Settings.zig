const std = @import("std");
const glfw = @import("zglfw");
const builtin = @import("builtin");
const assets = @import("assets.zig");
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

pub fn init(allocator: std.mem.Allocator) !Self {
    arena = .init(allocator);
    const arena_allocator = arena.allocator();

    const file = std.fs.cwd().openFile("settings.json", .{}) catch return .{};
    defer file.close();

    const file_data = try file.readToEndAlloc(arena_allocator, std.math.maxInt(u32));
    defer arena_allocator.free(file_data);

    return try std.json.parseFromSliceLeaky(Self, arena_allocator, file_data, .{ .ignore_unknown_fields = true });
}

pub fn deinit(self: Self) void {
    self.save() catch |e| {
        std.log.err("Settings save failed: {}", .{e});
        return;
    };

    arena.deinit();
}

pub fn save(self: Self) !void {
    const file = try std.fs.cwd().createFile("settings.json", .{});
    defer file.close();

    const settings_json = try std.json.stringifyAlloc(arena.allocator(), self, .{ .whitespace = .indent_4 });
    try file.writeAll(settings_json);
}

pub fn resetToDefaults(self: *Self) void {
    inline for (@typeInfo(Self).@"struct".fields) |field| {
        @field(self, field.name) = @as(*const field.type, @ptrCast(@alignCast(field.default_value orelse
            @panic("All settings need a default value, but it wasn't found")))).*;
    }
}
