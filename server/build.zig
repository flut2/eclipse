const std = @import("std");

pub const PacketLogType = enum {
    all,
    all_non_tick,
    all_tick,
    c2s,
    c2s_non_tick,
    c2s_tick,
    s2c,
    s2c_non_tick,
    s2c_tick,
    off,
};

pub fn buildWithoutDupes(
    b: *std.Build,
    comptime root_add: []const u8,
    comptime skip_non_check: bool,
    check_step: *std.Build.Step,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    log_packets: PacketLogType,
    enable_tracy: bool,
) !void {
    const options = .{
        .use_dragonfly = b.option(bool, "use_dragonfly",
            \\Whether to use Dragonfly for the database.
            \\Redis is assumed otherwise, and TTL banning/muting will be permanent across HWIDs, but not accounts.
        ) orelse false,
        .log_packets = log_packets,
        .enable_tracy = enable_tracy,
    };

    const opt_step = b.addOptions();
    inline for (@typeInfo(@TypeOf(options)).@"struct".fields) |field|
        opt_step.addOption(field.type, field.name, @field(options, field.name));

    const shared_dep = b.dependency("shared", .{ .target = target, .optimize = optimize });
    const hiredis_dep = b.dependency("hiredis", .{ .target = target, .optimize = optimize });

    inline for (.{ true, false }) |check| {
        if (!check and skip_non_check) continue;
        const exe = b.addExecutable(.{
            .name = "Eclipse",
            .use_lld = !check,
            .use_llvm = !check,
            // .use_lld = !check and optimize != .Debug or target.result.os.tag == .windows,
            // .use_llvm = !check and optimize != .Debug or target.result.os.tag == .windows,
            .root_module = b.createModule(.{
                .root_source_file = b.path(root_add ++ "src/main.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
                .imports = &.{
                    .{ .name = "options", .module = opt_step.createModule() },
                    .{ .name = "shared", .module = shared_dep.module("shared") },
                    .{ .name = "uv", .module = shared_dep.module("uv") },
                    .{
                        .name = "ziggy",
                        .module = b.dependency("ziggy", .{
                            .target = target,
                            .optimize = optimize,
                        }).module("ziggy"),
                    },
                },
            }),
        });

        exe.root_module.linkLibrary(shared_dep.artifact("libuv"));

        if (enable_tracy) {
            const tracy_module = b.createModule(.{
                .root_source_file = shared_dep.path("src/tracy.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
                .link_libcpp = true,
                .sanitize_c = .off,
            });

            const tracy_dep = b.dependency("tracy", .{ .target = target, .optimize = optimize });

            tracy_module.addCMacro("TRACY_ENABLE", "1");
            tracy_module.addIncludePath(tracy_dep.path(""));
            tracy_module.addCSourceFile(.{ .file = tracy_dep.path("public/TracyClient.cpp") });

            if (target.result.os.tag == .windows) {
                tracy_module.linkSystemLibrary("dbghelp", .{});
                tracy_module.linkSystemLibrary("ws2_32", .{});
            }

            exe.root_module.addImport("tracy", tracy_module);
        }

        const hiredis_path = hiredis_dep.path(".");
        exe.installHeadersDirectory(hiredis_path, "hiredis", .{ .include_extensions = &.{".h"} });
        exe.root_module.addIncludePath(hiredis_path);
        if (target.result.os.tag == .windows) {
            exe.root_module.linkSystemLibrary("ws2_32", .{});
            exe.root_module.linkSystemLibrary("crypt32", .{});
            exe.root_module.addCMacro("WIN32_LEAN_AND_MEAN", "");
            exe.root_module.addCMacro("_CRT_SECURE_NO_WARNINGS", "");
            exe.root_module.addCMacro("_WIN32", "");
        }
        exe.root_module.addCSourceFiles(.{
            .root = hiredis_path,
            .files = &.{
                "alloc.c",
                "async.c",
                "hiredis.c",
                "net.c",
                "read.c",
                "sds.c",
                "sockcompat.c",
            },
            .flags = &.{
                "-std=c99",
                "-fno-sanitize=undefined",
            },
        });

        if (check)
            check_step.dependOn(&exe.step)
        else
            exe.addWin32ResourceFile(.{ .file = b.path("../assets/resources.rc") });

        if (!check) {
            b.installArtifact(exe);

            b.getInstallStep().dependOn(&b.addInstallArtifact(exe, .{
                .dest_dir = .{ .override = .{ .custom = "bin" } },
            }).step);

            exe.step.dependOn(&b.addInstallDirectory(.{
                .source_dir = b.path(root_add ++ "../assets/shared"),
                .install_dir = .{ .bin = {} },
                .install_subdir = "assets",
            }).step);

            exe.step.dependOn(&b.addInstallDirectory(.{
                .source_dir = b.path(root_add ++ "../assets/server"),
                .install_dir = .{ .bin = {} },
                .install_subdir = "assets",
            }).step);

            const run_cmd = b.addRunArtifact(exe);
            run_cmd.step.dependOn(b.getInstallStep());
            if (b.args) |args| run_cmd.addArgs(args);
            b.step("run-srv", "Run the Eclipse server").dependOn(&run_cmd.step);
        }
    }
}

pub fn build(b: *std.Build) !void {
    const check_step = b.step("check", "Check if app compiles");
    const log_packets = b.option(PacketLogType, "log_packets", "Toggles various packet logging modes") orelse .off;
    const enable_tracy = b.option(bool, "enable_tracy", "Enable Tracy") orelse false;
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    try buildWithoutDupes(b, "", false, check_step, target, optimize, log_packets, enable_tracy);
}
