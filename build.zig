const std = @import("std");
const libxml2 = @import("libs/libxml/libxml2.zig");
const nfd = @import("libs/nfd-zig/build.zig");
const zglfw = @import("libs/zglfw/build.zig");
const zgpu = @import("libs/zgpu/build.zig");
const zpool = @import("libs/zpool/build.zig");
const zstbi = @import("libs/zstbi/build.zig");
const zstbrp = @import("libs/zstbrp/build.zig");
const ztracy = @import("libs/ztracy/build.zig");
const zaudio = @import("libs/zaudio/build.zig");
const ini = @import("libs/ini/build.zig");
const zdiscord = @import("libs/zig-discord/build.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const is_debug = optimize == .Debug;

    const exe = b.addExecutable(.{
        .name = "Faer",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.strip = optimize == .ReleaseFast or optimize == .ReleaseSmall;
    exe.root_module.addImport("rpc", zdiscord.getModule(b));
    exe.root_module.addImport("nfd", nfd.getModule(b));

    exe.root_module.addAnonymousImport("rpmalloc", .{ .root_source_file = .{ .path = "libs/rpmalloc/rpmalloc.zig" } });
    exe.root_module.addAnonymousImport("xev", .{ 
        .root_source_file = .{ .path = "libs/libxev/src/main.zig" }
    });

    const nfd_lib = nfd.makeLib(b, target, optimize);
    if (target.result.os.tag == .macos) {
        nfd_lib.defineCMacro("__kernel_ptr_semantics", "");
    }
    exe.linkLibrary(nfd_lib);

    const libxml = try libxml2.create(b, target, optimize, .{
        .iconv = false,
        .lzma = false,
        .zlib = false,
    });
    libxml.link(exe);

    const zstbi_pkg = zstbi.package(b, target, optimize, .{});
    zstbi_pkg.link(exe);

    const zstbrp_pkg = zstbrp.package(b, target, optimize, .{});
    zstbrp_pkg.link(exe);

    const ztracy_pkg = ztracy.package(b, target, optimize, .{
        .options = .{ .enable_ztracy = true },
    });
    ztracy_pkg.link(exe);

    const zaudio_pkg = zaudio.package(b, target, optimize, .{});
    zaudio_pkg.link(exe);

    const zglfw_pkg = zglfw.package(b, target, optimize, .{});
    const zpool_pkg = zpool.package(b, target, optimize, .{});
    const zgpu_pkg = zgpu.package(b, target, optimize, .{
        .deps = .{ .zpool = zpool_pkg.zpool, .zglfw = zglfw_pkg.zglfw },
        .options = .{
            .dawn_skip_validation = !is_debug,
            .disable_robustness = !is_debug,
        },
    });

    ini.link(ini.getModule(b), exe);

    // const xev = b.dependency("libxev", .{ .target = target, .optimize = optimize });
    // exe.root_module.addImport("xev", xev.module("xev"));

    zglfw_pkg.link(exe);
    zgpu_pkg.link(exe);

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_options = b.addOptions();
    exe.root_module.addOptions("build_options", exe_options);
    exe_options.addOption([]const u8, "asset_dir", "./assets/");

    const install_assets_step = b.addInstallDirectory(.{
        .source_dir = .{ .path = "src/assets" },
        .install_dir = .{ .bin = {} },
        .install_subdir = "assets",
    });
    exe.step.dependOn(&install_assets_step.step);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
