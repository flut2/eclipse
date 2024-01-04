const std = @import("std");

pub fn getModule(b: *std.Build) *std.Build.Module {
    return b.addModule("ini", .{
        .root_source_file = .{
            .path = "libs/ini/src/ini.zig",
        },
    });
}

pub fn link(module: *std.Build.Module, exe: *std.Build.Step.Compile) void {
    exe.root_module.addImport("ini", module);
    exe.root_module.addLibraryPath(.{ .path = "libs/ini/src/lib.zig" });
}

pub fn build(b: *std.Build, target: std.zig.CrossTarget, optimize: std.builtin.OptimizeMode) void {
    _ = b.addModule("ini", .{
        .source_file = .{
            .path = "libs/ini/src/ini.zig",
        },
    });

    const lib = b.addStaticLibrary(.{
        .name = "ini",
        .root_source_file = .{ .path = "libs/ini/src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib.bundle_compiler_rt = true;
    lib.root_module.addIncludePath(.{ .path = "libs/ini/src" });
    lib.linkLibC();

    b.installArtifact(lib);

    var main_tests = b.addTest(.{
        .root_source_file = .{ .path = "libs/ini/src/test.zig" },
        .optimize = optimize,
    });

    var binding_tests = b.addTest(.{
        .root_source_file = .{ .path = "libs/ini/src/lib-test.zig" },
        .optimize = optimize,
    });
    binding_tests.root_module.addIncludePath(.{ .path = "libs/ini/src" });
    binding_tests.root_module.linkLibrary(lib);
    binding_tests.linkLibC();

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
    test_step.dependOn(&binding_tests.step);
}
