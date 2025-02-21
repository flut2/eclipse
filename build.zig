const std = @import("std");

pub fn build(b: *std.Build) !void {
    const check_step = b.step("check", "Check if app compiles");
    const enable_tracy = b.option(bool, "enable_tracy", "Enable Tracy") orelse false;
    const enable_gpa = b.option(bool, "enable_gpa", "Toggles using the GPA for memory debugging") orelse false;
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    try @import("client/build.zig").buildWithoutDupes(b, "client/", true, check_step, target, optimize, enable_tracy, enable_gpa);
    try @import("server/build.zig").buildWithoutDupes(b, "server/", true, check_step, target, optimize, enable_tracy, enable_gpa);
}
