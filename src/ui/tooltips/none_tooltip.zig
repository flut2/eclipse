const std = @import("std");
const element = @import("../element.zig");

pub const NoneTooltip = struct {
    root: *element.Container = undefined,

    pub fn init(self: *NoneTooltip, allocator: std.mem.Allocator) !void {
        self.root = try element.Container.create(allocator, .{
            .visible = false,
            .layer = .tooltip,
            .x = 0,
            .y = 0,
        });
    }

    pub fn deinit(self: *NoneTooltip) void {
        self.root.destroy();
    }
};
