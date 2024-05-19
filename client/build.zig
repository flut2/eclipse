const std = @import("std");
const zstbi = @import("libs/zstbi/build.zig");
const zaudio = @import("libs/zaudio/build.zig");
const ini = @import("libs/ini/build.zig");
const nfd = @import("libs/nfd-zig/build.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "Eclipse",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
        .strip = optimize == .ReleaseFast or optimize == .ReleaseSmall,
        // .use_lld = optimize != .Debug,
        // .use_llvm = optimize != .Debug,
    });

    const enable_tracy = b.option(bool, "enable_tracy", "Enable Tracy") orelse false;
    const shared_dep = b.dependency("shared", .{
        .target = target,
        .optimize = optimize,
        .enable_tracy = enable_tracy,
    });
    exe.root_module.addImport("shared", shared_dep.module("shared"));
    exe.root_module.addImport("xev", shared_dep.module("xev"));
    exe.root_module.addImport("rpmalloc", shared_dep.module("rpmalloc"));
    exe.root_module.addImport("tracy", shared_dep.module("tracy"));

    exe.root_module.addImport("rpc", @import("libs/zig-discord/build.zig").getModule(b));
    exe.root_module.addImport("nfd", nfd.getModule(b));

    exe.root_module.addImport("turbopack", b.dependency("turbopack", .{
        .target = target,
        .optimize = optimize,
    }).module("turbopack"));

    exe.root_module.addImport("mach-glfw", b.dependency("mach_glfw", .{
        .target = target,
        .optimize = optimize,
    }).module("mach-glfw"));

    exe.root_module.addImport("mach", b.dependency("mach", .{
        .target = target,
        .optimize = optimize,
    }).module("mach"));

    if (target.result.os.tag == .windows) {
        const mach_gpu_dep = b.dependency("mach_gpu", .{
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.addImport("mach-gpu", mach_gpu_dep.module("mach-gpu"));
        try @import("mach_gpu").link(mach_gpu_dep.builder, exe, &exe.root_module, .{});
    }

    const nfd_lib = nfd.makeLib(b, target, optimize);
    if (target.result.os.tag == .macos) {
        nfd_lib.defineCMacro("__kernel_ptr_semantics", "");
    }
    exe.linkLibrary(nfd_lib);

    var options = b.addOptions();
    options.addOption(bool, "enable_tracy", enable_tracy);
    exe.root_module.addOptions("options", options);

    zstbi.package(b, target, optimize, .{}).link(exe);
    zaudio.package(b, target, optimize, .{}).link(exe);

    ini.link(ini.getModule(b), exe);

    b.installArtifact(exe);
}
