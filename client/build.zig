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
    enable_tracy: bool,
) !void {
    const options = .{
        .enable_validation_layers = b.option(bool, "enable_validation_layers", "Toggles Vulkan validation layers") orelse false,
        .log_packets = b.option(PacketLogType, "log_packets", "Toggles various packet logging modes") orelse .off,
        .version = b.option([]const u8, "version", "Build version, for the version text and client-server version checks") orelse "0.1",
        .login_server_ip = b.option([]const u8, "login_server_ip", "The IP of the login server") orelse "127.0.0.1",
        .login_server_port = b.option(u16, "login_server_port", "The port of the login server") orelse 2833,
        .enable_tracy = enable_tracy,
    };

    const opt_step = b.addOptions();
    inline for (@typeInfo(@TypeOf(options)).@"struct".fields) |field|
        opt_step.addOption(field.type, field.name, @field(options, field.name));

    const vulkan_dep = b.dependency("vulkan_zig", .{ .registry = b.path(root_add ++ "libs/vk.xml") });
    const shared_dep = b.dependency("shared", .{ .target = target, .optimize = optimize });
    const zstbi_dep = b.dependency("zstbi", .{ .target = target, .optimize = optimize });
    const zaudio_dep = b.dependency("zaudio", .{ .target = target, .optimize = optimize });
    const nfd_dep = b.dependency("nfd", .{ .target = target, .optimize = optimize });
    const zglfw_dep = b.dependency("zglfw", .{ .target = target, .optimize = optimize });

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
                .link_libcpp = true,
                .imports = &.{
                    .{ .name = "options", .module = opt_step.createModule() },
                    .{ .name = "uv", .module = shared_dep.module("uv") },
                    .{ .name = "shared", .module = shared_dep.module("shared") },
                    .{ .name = "vulkan", .module = vulkan_dep.module("vulkan-zig") },
                    .{ .name = "glfw", .module = zglfw_dep.module("root") },
                    .{ .name = "zstbi", .module = zstbi_dep.module("root") },
                    .{ .name = "zaudio", .module = zaudio_dep.module("root") },
                    .{ .name = "nfd", .module = nfd_dep.module("root") },
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
        exe.root_module.linkLibrary(zstbi_dep.artifact("zstbi"));
        exe.root_module.linkLibrary(zaudio_dep.artifact("miniaudio"));
        exe.root_module.linkLibrary(nfd_dep.artifact("nfd"));
        exe.root_module.linkLibrary(zglfw_dep.artifact("glfw"));

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
            comp_cmd.addFileArg(b.path(root_add ++ "src/render/shaders/" ++ names.shader_in));
            exe.root_module.addAnonymousImport(names.import, .{ .root_source_file = spv });
        }

        if (check)
            check_step.dependOn(&exe.step)
        else
            exe.root_module.addWin32ResourceFile(.{ .file = b.path("../assets/resources.rc") });

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
                .source_dir = b.path(root_add ++ "../assets/client"),
                .install_dir = .{ .bin = {} },
                .install_subdir = "assets",
            }).step);

            const run_cmd = b.addRunArtifact(exe);
            run_cmd.step.dependOn(b.getInstallStep());
            if (b.args) |args| run_cmd.addArgs(args);
            b.step("run-cli", "Run the Eclipse client").dependOn(&run_cmd.step);
        }
    }
}

pub fn build(b: *std.Build) !void {
    const check_step = b.step("check", "Check if app compiles");
    const enable_tracy = b.option(bool, "enable_tracy", "Enable Tracy") orelse false;
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    try buildWithoutDupes(b, "", false, check_step, target, optimize, enable_tracy);
}
