const std = @import("std");

pub fn buildWithoutDupes(
    b: *std.Build,
    comptime root_add: []const u8,
    comptime skip_non_check: bool,
    check_step: *std.Build.Step,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    enable_tracy: bool,
) !void {
    const use_dragonfly = b.option(bool, "use_dragonfly",
        \\Whether to use Dragonfly for the database.
        \\Redis is assumed otherwise, and TTL banning/muting will be permanent across HWIDs, but not accounts.
    ) orelse false;
    const enable_gpa = b.option(bool, "enable_gpa", "Toggles using the GPA for memory debugging") orelse false;

    behaviorGen: {
        var gen_file = b.build_root.handle.createFile(root_add ++ "src/_gen_behavior_file_dont_use.zig", .{}) catch break :behaviorGen;
        try gen_file.writeAll("pub const behaviors = .{\n");
        defer gen_file.writeAll("};\n") catch @panic("TODO");

        const dir = b.build_root.handle.openDir(root_add ++ "src/logic/behaviors/", .{ .iterate = true }) catch break :behaviorGen;
        var walker = try dir.walk(b.allocator);
        while (try walker.next()) |entry| if (std.mem.endsWith(u8, entry.path, ".zig"))
            try gen_file.writeAll(try std.fmt.allocPrint(b.allocator, "    @import(\"logic/behaviors/{s}\"),\n", .{entry.path}));
    }

    inline for (.{ true, false }) |check| {
        if (!check and skip_non_check) continue;
        const exe = b.addExecutable(.{
            .name = "Eclipse",
            .root_source_file = b.path(root_add ++ "src/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = optimize == .ReleaseFast or optimize == .ReleaseSmall,
            // .use_lld = !check and optimize != .Debug,
            // .use_llvm = !check and optimize != .Debug,
        });

        if (check) check_step.dependOn(&exe.step);

        const shared_dep = b.dependency("shared", .{
            .target = target,
            .optimize = optimize,
            .enable_tracy = enable_tracy,
        });
        exe.root_module.linkLibrary(shared_dep.artifact("libuv"));

        if (!enable_gpa) {
            const rpmalloc_dep = b.dependency("rpmalloc", .{
                .target = target,
                .optimize = optimize,
            });
            exe.root_module.addImport("rpmalloc", rpmalloc_dep.module("rpmalloc"));
            exe.root_module.linkLibrary(rpmalloc_dep.artifact("rpmalloc-lib"));
        }
        
        exe.root_module.addImport("shared", shared_dep.module("shared"));
        if (enable_tracy) exe.root_module.addImport("tracy", shared_dep.module("tracy"));
        exe.root_module.addImport("ziggy", shared_dep.module("ziggy"));

        const hiredis = b.dependency("hiredis", .{});
        const hiredis_path = hiredis.path(".");
        exe.addIncludePath(hiredis_path);
        exe.installHeadersDirectory(hiredis_path, "hiredis", .{ .include_extensions = &.{".h"} });
        exe.linkLibC();
        if (target.result.os.tag == .windows) {
            exe.linkSystemLibrary("ws2_32");
            exe.linkSystemLibrary("crypt32");
            exe.root_module.addCMacro("WIN32_LEAN_AND_MEAN", "");
            exe.root_module.addCMacro("_CRT_SECURE_NO_WARNINGS", "");
            exe.root_module.addCMacro("_WIN32", "");
        }
        exe.addCSourceFiles(.{
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

        var options = b.addOptions();
        options.addOption(bool, "enable_tracy", enable_tracy);
        options.addOption(bool, "enable_gpa", enable_gpa);
        options.addOption(bool, "use_dragonfly", use_dragonfly);
        exe.root_module.addOptions("options", options);

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
    const enable_tracy = b.option(bool, "enable_tracy", "Enable Tracy") orelse false;
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    try buildWithoutDupes(b, "", false, check_step, target, optimize, enable_tracy);
}
