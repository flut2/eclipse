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

fn addTracy(
    b: *std.Build,
    mod: *std.Build.Module,
    tracy_path: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const tracy_module = b.createModule(.{
        .root_source_file = tracy_path,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
        .sanitize_c = .off,
    });

    const tracy_dep = b.dependency("tracy", .{ .target = target, .optimize = optimize });

    tracy_module.addCMacro("TRACY_ENABLE", "");
    tracy_module.addIncludePath(tracy_dep.path(""));
    tracy_module.addCSourceFile(.{ .file = tracy_dep.path("public/TracyClient.cpp") });

    if (target.result.os.tag == .windows) {
        tracy_module.linkSystemLibrary("dbghelp", .{});
        tracy_module.linkSystemLibrary("ws2_32", .{});
    }

    mod.addImport("tracy", tracy_module);
}

fn buildClient(
    b: *std.Build,
    check_step: *std.Build.Step,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    log_packets: PacketLogType,
    tracy: bool,
) !void {
    const options = .{
        .vk_validation = b.option(bool, "vk_validation", "Toggles Vulkan validation layers") orelse false,
        .version = b.option([]const u8, "version", "Build version, for the version text and client-server version checks") orelse "0.1",
        .login_server_ip = b.option([]const u8, "login_server_ip", "The IP of the login server") orelse "127.0.0.1",
        .login_server_port = b.option(u16, "login_server_port", "The port of the login server") orelse 2833,
        .log_packets = log_packets,
        .tracy = tracy,
    };

    const opt_step = b.addOptions();
    inline for (@typeInfo(@TypeOf(options)).@"struct".fields) |field|
        opt_step.addOption(field.type, field.name, @field(options, field.name));

    const vulkan_dep = b.dependency("vulkan_zig", .{ .registry = b.path("client/libs/vk.xml") });
    const shared_dep = b.dependency("shared", .{ .target = target, .optimize = optimize });
    const stbi_dep = b.dependency("stbi", .{ .target = target, .optimize = optimize });
    const miniaudio_dep = b.dependency("miniaudio", .{ .target = target, .optimize = optimize });
    const windy_dep = b.dependency("windy", .{
        .target = target,
        .optimize = optimize,
        .vulkan_support = true,
    });

    inline for (.{ true, false }) |check| {
        const exe = b.addExecutable(.{
            .name = "Eclipse",
            .use_lld = !check,
            .use_llvm = !check,
            // .use_lld = !check and optimize != .Debug or target.result.os.tag == .windows,
            // .use_llvm = !check and optimize != .Debug or target.result.os.tag == .windows,
            .root_module = b.createModule(.{
                .root_source_file = b.path("client/src/main.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
                .link_libcpp = true,
                .imports = &.{
                    .{ .name = "options", .module = opt_step.createModule() },
                    .{ .name = "uv", .module = shared_dep.module("uv") },
                    .{ .name = "shared", .module = shared_dep.module("shared") },
                    .{ .name = "vulkan", .module = vulkan_dep.module("vulkan-zig") },
                    .{ .name = "windy", .module = windy_dep.module("windy") },
                    .{ .name = "stbi", .module = stbi_dep.module("root") },
                    .{ .name = "miniaudio", .module = miniaudio_dep.module("root") },
                    .{
                        .name = "msdf-zig",
                        .module = b.dependency("msdf_zig", .{
                            .target = target,
                            .optimize = optimize,
                        }).module("msdf-zig"),
                    },
                    .{
                        .name = "ziggy",
                        .module = b.dependency("ziggy", .{
                            .target = target,
                            .optimize = optimize,
                        }).module("ziggy"),
                    },
                    .{
                        .name = "turbopack",
                        .module = b.dependency("turbopack", .{
                            .target = target,
                            .optimize = optimize,
                        }).module("turbopack"),
                    },
                },
            }),
        });

        exe.root_module.linkLibrary(shared_dep.artifact("libuv"));
        exe.root_module.linkLibrary(stbi_dep.artifact("stbi"));
        exe.root_module.linkLibrary(miniaudio_dep.artifact("miniaudio"));

        if (tracy)
            addTracy(b, exe.root_module, shared_dep.path("src/tracy.zig"), target, optimize);

        exe.root_module.linkSystemLibrary(if (target.result.os.tag == .windows) "vulkan-1" else "vulkan", .{});

        exe.root_module.addIncludePath(b.dependency("vma", .{
            .target = target,
            .optimize = optimize,
        }).path("include"));
        const env_map = try std.process.getEnvMap(b.allocator);
        if (env_map.get("VULKAN_SDK")) |path| {
            exe.root_module.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ path, "lib" }) });
            exe.root_module.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ path, "include" }) });
        } else @panic("Could not find Vulkan SDK");
        exe.root_module.addCSourceFile(.{
            .file = b.addWriteFiles().add("vma.cpp",
                \\#define VMA_IMPLEMENTATION
                \\#include <vk_mem_alloc.h>
            ),
            .flags = &.{"-std=c++17"},
        });

        inline for (.{
            .{ .shader_in = "generic.vert", .shader_out = "generic_vert.spv", .import = "generic_vert" },
            .{ .shader_in = "generic.frag", .shader_out = "generic_frag.spv", .import = "generic_frag" },
            .{ .shader_in = "ground.vert", .shader_out = "ground_vert.spv", .import = "ground_vert" },
            .{ .shader_in = "ground.frag", .shader_out = "ground_frag.spv", .import = "ground_frag" },
        }) |names| {
            const comp_cmd = b.addSystemCommand(&.{ "glslc", "--target-env=vulkan1.0", "-o" });
            const spv = comp_cmd.addOutputFileArg(names.shader_out);
            comp_cmd.addFileArg(b.path("client/src/render/shaders/" ++ names.shader_in));
            exe.root_module.addAnonymousImport(names.import, .{ .root_source_file = spv });
        }

        if (check)
            check_step.dependOn(&exe.step)
        else
            exe.root_module.addWin32ResourceFile(.{ .file = b.path("assets/resources.rc") });

        if (!check) {
            b.getInstallStep().dependOn(&b.addInstallArtifact(exe, .{
                .dest_dir = .{ .override = .{ .custom = "client" } },
            }).step);

            exe.step.dependOn(&b.addInstallDirectory(.{
                .source_dir = b.path("assets/shared"),
                .install_dir = .{ .custom = "client" },
                .install_subdir = "assets/shared",
            }).step);

            exe.step.dependOn(&b.addInstallDirectory(.{
                .source_dir = b.path("assets/client"),
                .install_dir = .{ .custom = "client" },
                .install_subdir = "assets/client",
            }).step);

            const run_cmd = b.addRunArtifact(exe);
            run_cmd.step.dependOn(b.getInstallStep());
            if (b.args) |args| run_cmd.addArgs(args);
            b.step("run-cli", "Run the Eclipse client").dependOn(&run_cmd.step);
        }
    }
}

fn buildServer(
    b: *std.Build,
    check_step: *std.Build.Step,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    log_packets: PacketLogType,
    tracy: bool,
) !void {
    const options = .{
        .use_dragonfly = b.option(bool, "use_dragonfly",
            \\Whether to use Dragonfly for the database.
            \\Redis is assumed otherwise, and TTL banning/muting will be permanent across HWIDs, but not accounts.
        ) orelse false,
        .log_packets = log_packets,
        .tracy = tracy,
    };

    const opt_step = b.addOptions();
    inline for (@typeInfo(@TypeOf(options)).@"struct".fields) |field|
        opt_step.addOption(field.type, field.name, @field(options, field.name));

    const shared_dep = b.dependency("shared", .{ .target = target, .optimize = optimize });
    const hiredis_dep = b.dependency("hiredis", .{ .target = target, .optimize = optimize });

    inline for (.{ true, false }) |check| {
        const exe = b.addExecutable(.{
            .name = "Eclipse",
            .use_lld = !check,
            .use_llvm = !check,
            // .use_lld = !check and optimize != .Debug or target.result.os.tag == .windows,
            // .use_llvm = !check and optimize != .Debug or target.result.os.tag == .windows,
            .root_module = b.createModule(.{
                .root_source_file = b.path("server/src/main.zig"),
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

        if (tracy)
            addTracy(b, exe.root_module, shared_dep.path("src/tracy.zig"), target, optimize);

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
            exe.addWin32ResourceFile(.{ .file = b.path("assets/resources.rc") });

        if (!check) {
            b.getInstallStep().dependOn(&b.addInstallArtifact(exe, .{
                .dest_dir = .{ .override = .{ .custom = "server" } },
            }).step);

            exe.step.dependOn(&b.addInstallDirectory(.{
                .source_dir = b.path("assets/shared"),
                .install_dir = .{ .custom = "server" },
                .install_subdir = "assets/shared",
            }).step);

            exe.step.dependOn(&b.addInstallDirectory(.{
                .source_dir = b.path("assets/server"),
                .install_dir = .{ .custom = "server" },
                .install_subdir = "assets/server",
            }).step);

            const run_cmd = b.addRunArtifact(exe);
            run_cmd.step.dependOn(b.getInstallStep());
            if (b.args) |args| run_cmd.addArgs(args);
            b.step("run-srv", "Run the Eclipse server").dependOn(&run_cmd.step);
        }
    }
}

pub fn build(b: *std.Build) !void {
    const check_step = b.step("check", "Check if the app compiles");
    const tracy = b.option(bool, "tracy", "Toggles Tracy integration") orelse false;
    const log_packets = b.option(PacketLogType, "log_packets", "Toggles various packet logging modes") orelse .off;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    if (b.option(bool, "client", "Build the client") orelse true)
        try buildClient(b, check_step, target, optimize, log_packets, tracy);

    if (b.option(bool, "server", "Build the server") orelse true)
        try buildServer(b, check_step, target, optimize, log_packets, tracy);
}
