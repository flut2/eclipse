const std = @import("std");
const zon = @import("build.zig.zon");

/// The full Ziggy parsing functionality is available at build time.
pub const ziggy = @import("src/root.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const single_threaded = b.option(
        bool,
        "single-threaded",
        "Create a single-threaded build of the Ziggy CLI tool.",
    ) orelse false;
    const version = b.option(
        []const u8,
        "version",
        "Override the version of Ziggy.",
    ) orelse zon.version;

    const options = b.addOptions();
    options.addOption([]const u8, "version", version);

    const ziggy_module = b.addModule("ziggy", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .strip = false,
    });

    const folders = b.dependency("known_folders", .{
        .target = target,
        .optimize = optimize,
    }).module("known-folders");
    const lsp = b.dependency("lsp_kit", .{
        .target = target,
        .optimize = optimize,
    }).module("lsp");

    const cli_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = single_threaded,
        .imports = &.{
            .{ .name = "ziggy", .module = ziggy_module },
            .{ .name = "known-folders", .module = folders },
            .{ .name = "lsp", .module = lsp },
        },
    });
    cli_module.addOptions("options", options);

    const cli_exe = b.addExecutable(.{
        .name = "ziggy",
        .root_module = cli_module,
    });
    b.installArtifact(cli_exe);

    const run_exe = b.addRunArtifact(cli_exe);
    if (b.args) |args| run_exe.addArgs(args);
    const run_exe_step = b.step("run", "Run the Ziggy tool");
    run_exe_step.dependOn(&run_exe.step);

    const ziggy_check = b.addExecutable(.{
        .name = "ziggy_check",
        .root_module = cli_module,
    });

    const check = b.step("check", "Check if the project compiles");
    check.dependOn(&ziggy_check.step);
}
