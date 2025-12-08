const std = @import("std");

pub fn build(b: *std.Build) !void {
    const check_step = b.step("check", "Check if app compiles");
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    try @import("client/build.zig").buildWithoutDupes(b, "client/", true, check_step, target, optimize, .all, true);
    try @import("server/build.zig").buildWithoutDupes(b, "server/", true, check_step, target, optimize, .all, true);
}
