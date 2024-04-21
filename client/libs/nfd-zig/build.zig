const std = @import("std");
const builtin = std.builtin;

fn sdkPath(comptime suffix: []const u8) []const u8 {
    if (suffix[0] != '/') @compileError("relToPath requires an absolute path!");
    return comptime blk: {
        const root_dir = std.fs.path.dirname(@src().file) orelse ".";
        break :blk root_dir ++ suffix;
    };
}

pub fn makeLib(b: *std.Build, target: std.Build.ResolvedTarget, optimize: builtin.OptimizeMode) *std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = "nfd",
        .root_source_file = .{ .path = sdkPath("/src/lib.zig") },
        .target = target,
        .optimize = optimize,
    });

    const cflags = [_][]const u8{ "-m64", "-g", "-Wall", "-Wextra", "-fno-exceptions" };
    lib.root_module.addIncludePath(.{ .path = sdkPath("/nativefiledialog/src/include") });
    lib.root_module.addCSourceFile(.{ .file = .{ .path = sdkPath("/nativefiledialog/src/nfd_common.c") }, .flags = &cflags });
    if (target.result.os.tag == .macos) {
        lib.root_module.addCSourceFile(.{ .file = .{ .path = sdkPath("/nativefiledialog/src/nfd_cocoa.m") }, .flags = &cflags });
    } else if (target.result.os.tag == .windows) {
        lib.root_module.addCSourceFile(.{ .file = .{ .path = sdkPath("/nativefiledialog/src/nfd_win.cpp") }, .flags = &cflags });
    } else {
        lib.root_module.addCSourceFile(.{ .file = .{ .path = sdkPath("/nativefiledialog/src/nfd_gtk.c") }, .flags = &cflags });
    }

    lib.linkLibC();
    if (target.result.os.tag == .macos) {
        lib.root_module.linkFramework("AppKit", .{});
        lib.root_module.linkFramework("Foundation", .{});
    } else if (target.result.os.tag == .windows) {
        lib.root_module.linkSystemLibrary("shell32", .{});
        lib.root_module.linkSystemLibrary("ole32", .{});
        lib.root_module.linkSystemLibrary("uuid", .{}); // needed by MinGW
    } else {
        lib.root_module.linkSystemLibrary("atk-1.0", .{});
        lib.root_module.linkSystemLibrary("gdk-3", .{});
        lib.root_module.linkSystemLibrary("gtk-3", .{});
        lib.root_module.linkSystemLibrary("glib-2.0", .{});
        lib.root_module.linkSystemLibrary("gobject-2.0", .{});
    }

    return lib;
}

pub fn getModule(b: *std.Build) *std.Build.Module {
    return b.createModule(.{ .root_source_file = .{ .path = sdkPath("/src/lib.zig") } });
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const lib = makeLib(b, target, optimize);
    b.addInstallArtifact(lib, .{});

    var demo = b.addExecutable(.{
        .name = "demo",
        .root_source_file = .{ .path = "src/demo.zig" },
        .target = target,
        .optimize = optimize,
    });
    demo.root_module.addImport("nfd", getModule(b));
    demo.linkLibrary(lib);
    b.addInstallArtifact(demo, .{});

    const run_demo_cmd = b.addRunArtifact(demo);
    run_demo_cmd.step.dependOn(b.getInstallStep());

    const run_demo_step = b.step("run", "Run the demo");
    run_demo_step.dependOn(&run_demo_cmd.step);
}
