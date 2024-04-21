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
}
