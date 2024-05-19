const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addModule("shared", .{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
        .strip = optimize == .ReleaseFast or optimize == .ReleaseSmall,
        // .use_lld = optimize != .Debug,
        // .use_llvm = optimize != .Debug,
    });

    lib.linkLibrary(b.dependency("libxml2", .{
        .target = target,
        .optimize = optimize,
    }).artifact("xml2"));

    b.modules.put(b.dupe("xev"), b.dependency("libxev", .{
        .target = target,
        .optimize = optimize,
    }).module("xev")) catch @panic("OOM");

    b.modules.put(b.dupe("rpmalloc"), b.dependency("rpmalloc", .{
        .target = target,
        .optimize = optimize,
    }).module("rpmalloc")) catch @panic("OOM");

    const tracy_dep = b.dependency("tracy", .{
        .target = target,
        .optimize = optimize,
        .tracy_enable = b.option(bool, "enable_tracy", "Enable Tracy") orelse false,
        .tracy_on_demand = true,
        .tracy_callstack = @as(u8, 8),
        .tracy_only_localhost = true,
    });
    b.modules.put(b.dupe("tracy"), tracy_dep.module("tracy")) catch @panic("OOM");
    lib.linkLibrary(tracy_dep.artifact("tracy"));
    lib.link_libcpp = true;
}
