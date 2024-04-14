const std = @import("std");
const libxml2 = @import("libs/libxml/libxml2.zig");
const zstbi = @import("libs/zstbi/build.zig");
const ztracy = @import("libs/ztracy/build.zig");
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
    });

    exe.root_module.addAnonymousImport("rpmalloc", .{ .root_source_file = .{ .path = "libs/rpmalloc/rpmalloc.zig" } });
    exe.root_module.addAnonymousImport("turbopack", .{ .root_source_file = .{ .path = "libs/turbopack/pack.zig" } });
    exe.root_module.addImport("rpc", @import("libs/zig-discord/build.zig").getModule(b));
    exe.root_module.addImport("nfd", nfd.getModule(b));

    exe.root_module.addImport("mach-glfw", b.dependency("mach_glfw", .{
        .target = target,
        .optimize = optimize,
    }).module("mach-glfw"));

    exe.root_module.addImport("mach", b.dependency("mach", .{
        .target = target,
        .optimize = optimize,
    }).module("mach"));

    exe.root_module.addImport("mach-gpu", b.dependency("mach_gpu", .{
        .target = target,
        .optimize = optimize,
    }).module("mach-gpu"));

    exe.root_module.addImport("xev", b.dependency("libxev", .{
        .target = target,
        .optimize = optimize,
    }).module("xev"));

    const nfd_lib = nfd.makeLib(b, target, optimize);
    if (target.result.os.tag == .macos) {
        nfd_lib.defineCMacro("__kernel_ptr_semantics", "");
    }
    exe.linkLibrary(nfd_lib);

    (try libxml2.create(b, target, optimize, .{
        .iconv = false,
        .lzma = false,
        .zlib = false,
    })).link(exe);

    zstbi.package(b, target, optimize, .{}).link(exe);
    ztracy.package(b, target, optimize, .{ .options = .{ .enable_ztracy = true } }).link(exe);
    zaudio.package(b, target, optimize, .{}).link(exe);

    ini.link(ini.getModule(b), exe);

    @import("mach_gpu").link(b.dependency("mach_gpu", .{
        .target = target,
        .optimize = optimize,
    }).builder, exe, &exe.root_module, .{}) catch unreachable;

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_options = b.addOptions();
    exe.root_module.addOptions("build_options", exe_options);
    exe_options.addOption(bool, "use_dawn", target.result.os.tag == .windows);
    exe_options.addOption([]const u8, "asset_dir", "./assets/");

    exe.step.dependOn(&b.addInstallDirectory(.{
        .source_dir = .{ .path = "src/assets" },
        .install_dir = .{ .bin = {} },
        .install_subdir = "assets",
    }).step);

    b.step("run", "Run the app").dependOn(&run_cmd.step);
}
