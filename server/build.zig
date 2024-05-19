const std = @import("std");
const ztracy = @import("libs/ztracy/build.zig");

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

    exe.root_module.addImport("rpmalloc", b.dependency("rpmalloc", .{
        .target = target,
        .optimize = optimize,
    }).module("rpmalloc"));

    exe.root_module.addImport("shared", b.dependency("shared", .{
        .target = target,
        .optimize = optimize,
    }).module("shared"));

    exe.root_module.addImport("httpz", b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    }).module("httpz"));

    exe.root_module.addImport("xev", b.dependency("libxev", .{
        .target = target,
        .optimize = optimize,
    }).module("xev"));

    ztracy.package(b, target, optimize, .{ .options = .{ .enable_ztracy = true } }).link(exe);

    const hiredis = b.dependency("hiredis", .{});
    const hiredis_path = hiredis.path(".");
    exe.addIncludePath(hiredis_path);
    exe.installHeadersDirectoryOptions(.{
        .source_dir = hiredis_path,
        .install_dir = .header,
        .install_subdir = "hiredis",
        .include_extensions = &.{".h"},
    });
    exe.linkSystemLibrary("ssl");
    exe.linkSystemLibrary("crypto");
    exe.addCSourceFiles(.{
        .root = hiredis_path,
        .files = &.{
            "alloc.c",
            "async.c",
            "dict.c",
            "hiredis.c",
            "net.c",
            "read.c",
            "sds.c",
            "sockcompat.c",
            "ssl.c",
        },
        .flags = &.{
            "-pedantic",
            "-Wall",
            "-Wextra",
            "-Wshadow",
            "-Wpointer-arith",
            "-Wcast-align",
            "-Wwrite-strings",
            "-Wstrict-prototypes",
            "-Wmissing-prototypes",
            "-Wno-long-long",
            "-Wno-format-extra-args",
        },
    });

    var gen_file = try std.fs.cwd().createFile("./server/src/_generated_dont_use.zig", .{});

    const dir = try std.fs.cwd().openDir("./server/src/logic/behaviors/", .{ .iterate = true });
    var walker = try dir.walk(b.allocator);
    defer walker.deinit();
    var i: usize = 0;
    while (try walker.next()) |entry| : (i += 1) {
        if (std.mem.endsWith(u8, entry.path, ".zig")) {
            try gen_file.writeAll(try std.fmt.allocPrint(b.allocator, "pub const b{d} = @import(\"logic/behaviors/{s}\");\n", .{ i, entry.path }));
        }
    }

    var options = b.addOptions();
    options.addOption(usize, "len", i);
    exe.root_module.addOptions("behaviors", options);

    b.installArtifact(exe);
}
