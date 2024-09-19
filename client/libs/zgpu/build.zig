const std = @import("std");
const log = std.log.scoped(.zgpu);

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const debug_mode = b.option(
        bool,
        "debug_mode",
        "Whether to have Dawn validation errors and to use the debug binary, for symbols",
    ) orelse false;

    const options = b.addOptions();
    options.addOption(bool, "dawn_skip_validation", !debug_mode);

    const options_module = options.createModule();

    _ = b.addModule("root", .{
        .root_source_file = b.path("src/zgpu.zig"),
        .imports = &.{.{ .name = "zgpu_options", .module = options_module }},
    });

    const zdawn = b.addStaticLibrary(.{
        .name = "zdawn",
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(zdawn);

    @import("system_sdk").addLibraryPathsTo(zdawn);

    switch (target.result.os.tag) {
        .windows => {
            zdawn.linkSystemLibrary("ole32");
            zdawn.linkSystemLibrary("dxguid");
        },
        .macos => {
            zdawn.linkSystemLibrary("objc");
            zdawn.linkFramework("Metal");
            zdawn.linkFramework("CoreGraphics");
            zdawn.linkFramework("Foundation");
            zdawn.linkFramework("IOKit");
            zdawn.linkFramework("IOSurface");
            zdawn.linkFramework("QuartzCore");
        },
        else => {},
    }

    link("", zdawn, debug_mode);
}

pub fn link(comptime dir_prepend: []const u8, exe: *std.Build.Step.Compile, debug_mode: bool) void {
    const b = exe.step.owner;
    const target = exe.rootModuleTarget();
    exe.addObjectFile(b.path(std.fmt.allocPrint(b.allocator, dir_prepend ++ "libs/{s}-{s}/{s}/{s}", .{
        @tagName(target.cpu.arch),
        @tagName(target.os.tag),
        if (debug_mode) "debug" else "release",
        if (target.os.tag == .windows) "dawn.lib" else "libdawn.a",
    }) catch unreachable));
    exe.addIncludePath(b.path(dir_prepend ++ "src/include"));
    exe.linkLibC();
    exe.linkLibCpp();
    exe.addCSourceFile(.{
        .file = b.path(dir_prepend ++ "src/dawn.cpp"),
        .flags = &.{ "-std=c++17", "-fno-sanitize=undefined" },
    });
    exe.addCSourceFile(.{
        .file = b.path(dir_prepend ++ "src/dawn_proc.c"),
        .flags = &.{"-fno-sanitize=undefined"},
    });
}
