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
    const enable_validation_layers = b.option(bool, "enable_validation_layers", "Toggles Vulkan validation layers") orelse (optimize != .Debug);
    const log_packets = b.option(PacketLogType, "log_packets", "Toggles various packet logging modes") orelse .off;
    const version = b.option([]const u8, "version", "Build version, for the version text and client-server version checks") orelse "1.0";
    const login_server_ip = b.option([]const u8, "login_server_ip", "The IP of the login server") orelse "127.0.0.1";
    const login_server_port = b.option(u16, "login_server_port", "The port of the login server") orelse 2833;

    inline for (.{ true, false }) |check| {
        if (!check and skip_non_check) continue;
        const exe = b.addExecutable(.{
            .name = "Eclipse",
            .root_source_file = b.path(root_add ++ "src/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = optimize == .ReleaseFast or optimize == .ReleaseSmall,
            .use_lld = !check, // and optimize != .Debug,
            .use_llvm = !check, // and optimize != .Debug,
        });

        if (check) check_step.dependOn(&exe.step);

        var options = b.addOptions();
        options.addOption(bool, "enable_tracy", enable_tracy);
        options.addOption(PacketLogType, "log_packets", log_packets);
        options.addOption([]const u8, "version", version);
        options.addOption([]const u8, "login_server_ip", login_server_ip);
        options.addOption(u16, "login_server_port", login_server_port);
        options.addOption(bool, "enable_validation_layers", enable_validation_layers);
        exe.root_module.addOptions("options", options);

        const shared_dep = b.dependency("shared", .{
            .target = target,
            .optimize = optimize,
            .enable_tracy = enable_tracy,
        });
        exe.root_module.linkLibrary(shared_dep.artifact("libuv"));

        exe.root_module.addImport("shared", shared_dep.module("shared"));
        exe.root_module.addImport("rpmalloc", shared_dep.module("rpmalloc"));
        if (enable_tracy) exe.root_module.addImport("tracy", shared_dep.module("tracy"));
        exe.root_module.addImport("ziggy", shared_dep.module("ziggy"));

        exe.root_module.addImport("turbopack", b.dependency("turbopack", .{
            .target = target,
            .optimize = optimize,
        }).module("turbopack"));

        const vulkan = b.dependency("vulkan_zig", .{ .registry = b.path("libs/vk.xml") }).module("vulkan-zig");
        exe.root_module.addImport("vulkan", vulkan);
        exe.linkLibCpp();
        exe.linkSystemLibrary(if (target.result.os.tag == .windows) "vulkan-1" else "vulkan");
        exe.addIncludePath(b.path("libs/vma"));
        const env_map = try std.process.getEnvMap(b.allocator);
        if (env_map.get("VULKAN_SDK")) |path| {
            exe.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ path, "lib" }) });
            exe.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ path, "include" }) });
        } else @panic("Could not find Vulkan SDK");
        exe.addCSourceFile(.{ .file = b.path("libs/vma/vk_mem_alloc.cpp") });

        inline for (.{
            .{ "generic.vert", "generic_vert.spv", "generic_vert" },
            .{ "generic.frag", "generic_frag.spv", "generic_frag" },
            .{ "ground.vert", "ground_vert.spv", "ground_vert" },
            .{ "ground.frag", "ground_frag.spv", "ground_frag" },
        }) |names| {
            const comp_cmd = b.addSystemCommand(&.{ "glslc", "--target-env=vulkan1.2", "-o" });
            const spv = comp_cmd.addOutputFileArg(names[1]);
            comp_cmd.addFileArg(b.path("src/render/shaders/" ++ names[0]));
            exe.root_module.addAnonymousImport(names[2], .{ .root_source_file = spv });
        }

        const zglfw_dep = b.dependency("zglfw", .{
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.addImport("glfw", zglfw_dep.module("root"));
        exe.linkLibrary(zglfw_dep.artifact("glfw"));

        const zstbi_dep = b.dependency("zstbi", .{
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.addImport("zstbi", zstbi_dep.module("root"));
        exe.linkLibrary(zstbi_dep.artifact("zstbi"));

        @import("system_sdk").addLibraryPathsTo(exe);
        const zaudio_dep = b.dependency("zaudio", .{
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.addImport("zaudio", zaudio_dep.module("root"));
        exe.linkLibrary(zaudio_dep.artifact("miniaudio"));

        const nfd_dep = b.dependency("native_file_dialog", .{
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.addImport("nfd", nfd_dep.module("root"));
        exe.linkLibrary(nfd_dep.artifact("nfd"));

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
