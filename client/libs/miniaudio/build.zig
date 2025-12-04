const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    _ = b.addModule("root", .{ .root_source_file = b.path("miniaudio.zig") });

    const ma_lib = b.addLibrary(.{
        .name = "miniaudio",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    ma_lib.root_module.addIncludePath(b.dependency("miniaudio", .{
        .target = target,
        .optimize = optimize,
    }).path("."));

    if (target.result.os.tag == .macos) {
        ma_lib.root_module.linkFramework("CoreAudio", .{});
        ma_lib.root_module.linkFramework("CoreFoundation", .{});
        ma_lib.root_module.linkFramework("AudioUnit", .{});
        ma_lib.root_module.linkFramework("AudioToolbox", .{});
    } else if (target.result.os.tag == .linux) {
        ma_lib.root_module.linkSystemLibrary("pthread", .{});
        ma_lib.root_module.linkSystemLibrary("m", .{});
        ma_lib.root_module.linkSystemLibrary("dl", .{});
    }

    ma_lib.root_module.addCSourceFile(.{
        .file = b.path("miniaudio.c"),
        .flags = &.{"-std=c99"},
    });
    ma_lib.root_module.addCSourceFile(.{
        .file = b.addWriteFiles().add("miniaudio_impl.c",
            \\#define MINIAUDIO_IMPLEMENTATION
            \\#include "miniaudio.h"
        ),
        .flags = &.{
            "-DMA_NO_WEBAUDIO",
            "-DMA_NO_ENCODING",
            "-DMA_NO_NULL",
            "-DMA_NO_JACK",
            "-DMA_NO_DSOUND",
            "-DMA_NO_WINMM",
            "-std=c99",
            "-fno-sanitize=undefined",
            if (target.result.os.tag == .macos) "-DMA_NO_RUNTIME_LINKING" else "",
        },
    });
    b.installArtifact(ma_lib);
}
