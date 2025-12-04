const std = @import("std");
const builtin = @import("builtin");

const LibuvLibraries = struct {
    const windows = [_][]const u8{
        "psapi",
        "user32",
        "advapi32",
        "iphlpapi",
        "userenv",
        "ws2_32",
        "dbghelp",
        "ole32",
        "shell32",
    };
    const linux = [_][]const u8{ "dl", "rt" };
    const macos = [_][]const u8{};
};

const LibuvSources = struct {
    const base = [_][]const u8{
        "fs-poll.c",
        "idna.c",
        "inet.c",
        "random.c",
        "strscpy.c",
        "thread-common.c",
        "threadpool.c",
        "timer.c",
        "uv-common.c",
        "uv-data-getter-setters.c",
        "version.c",
        "strtok.c",
    };
    const unix = [_][]const u8{
        "unix/async.c",
        "unix/core.c",
        "unix/dl.c",
        "unix/fs.c",
        "unix/getaddrinfo.c",
        "unix/getnameinfo.c",
        "unix/loop-watcher.c",
        "unix/loop.c",
        "unix/pipe.c",
        "unix/poll.c",
        "unix/process.c",
        "unix/random-devurandom.c",
        "unix/signal.c",
        "unix/stream.c",
        "unix/tcp.c",
        "unix/thread.c",
        "unix/tty.c",
        "unix/udp.c",
        "unix/proctitle.c",
    };
    const windows = base ++ [_][]const u8{
        "win/async.c",
        "win/core.c",
        "win/detect-wakeup.c",
        "win/dl.c",
        "win/error.c",
        "win/fs.c",
        "win/fs-event.c",
        "win/getaddrinfo.c",
        "win/getnameinfo.c",
        "win/handle.c",
        "win/loop-watcher.c",
        "win/pipe.c",
        "win/poll.c",
        "win/process.c",
        "win/process-stdio.c",
        "win/signal.c",
        "win/snprintf.c",
        "win/stream.c",
        "win/tcp.c",
        "win/thread.c",
        "win/tty.c",
        "win/udp.c",
        "win/util.c",
        "win/winapi.c",
        "win/winsock.c",
    };
    const linux = base ++ unix ++ [_][]const u8{
        "unix/linux.c",
        "unix/proctitle.c",
        "unix/procfs-exepath.c",
        "unix/random-getrandom.c",
        "unix/random-sysctl-linux.c",
    };
    const macos = base ++ unix ++ [_][]const u8{
        "unix/darwin-proctitle.c",
        "unix/darwin.c",
        "unix/fsevents.c",
        "unix/kqueue.c",
        "unix/proctitle.c",
        "unix/bsd-ifaddrs.c",
        "unix/random-getentropy.c",
    };
};

const LibuvDefinitions = struct {
    const unix = [_][]const u8{"-D_LARGEFILE_SOURCE"};
    const windows = [_][]const u8{
        "-D_WIN32",
        "-DWIN32_LEAN_AND_MEAN",
        "-D_WIN32_WINNT=0x0602",
        "-D_CRT_DECLARE_NONSTDC_NAMES=0",
    };
    const linux = unix ++ [_][]const u8{"-D_GNU_SOURCE"};
    const macos = unix ++ [_][]const u8{ "-D_DARWIN_UNLIMITED_SELECT=1", "-D_DARWIN_USE_64_BIT_INODE=1" };
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libuv_lib = b.addLibrary(.{
        .name = "libuv",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    const libuv_dep = b.dependency("libuv", .{ .optimize = optimize, .target = target });
    inline for (.{
        libuv_dep.path("include"),
        libuv_dep.path("src"),
    }) |include_path| libuv_lib.root_module.addIncludePath(include_path);
    const os_name = @tagName(builtin.os.tag);
    for (@field(LibuvLibraries, os_name)) |lib_name| libuv_lib.root_module.linkSystemLibrary(lib_name, .{});
    libuv_lib.root_module.addCSourceFiles(.{
        .root = libuv_dep.path("src"),
        .files = &@field(LibuvSources, os_name),
        .flags = &@field(LibuvDefinitions, os_name),
    });
    b.installArtifact(libuv_lib);

    const libuv_tc = b.addTranslateC(.{
        .optimize = optimize,
        .target = target,
        .root_source_file = libuv_dep.path("include/uv.h"),
    });
    libuv_tc.addIncludePath(libuv_dep.path("include"));

    const libuv_patcher = b.addExecutable(.{
        .name = "libuv_patcher",
        .root_module = b.createModule(.{
            .root_source_file = b.path("libuv_patcher.zig"),
            .optimize = optimize,
            .target = target,
        }),
    });

    const run_patcher = b.addRunArtifact(libuv_patcher);
    run_patcher.addFileArg(libuv_tc.getOutput());
    run_patcher.step.dependOn(&libuv_tc.step);
    run_patcher.step.dependOn(&libuv_patcher.step);

    libuv_lib.step.dependOn(&run_patcher.step);

    const libuv_mod = b.addModule("uv", .{
        .root_source_file = libuv_tc.getOutput(),
        .link_libc = true,
    });
    libuv_mod.linkLibrary(libuv_lib);

    _ = b.addModule("shared", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        // .use_lld = !check and optimize != .Debug or target.result.os.tag == .windows,
        // .use_llvm = !check and optimize != .Debug or target.result.os.tag == .windows,
        .imports = &.{
            .{ .name = "uv", .module = libuv_mod },
            .{
                .name = "ziggy",
                .module = b.dependency("ziggy", .{
                    .target = target,
                    .optimize = optimize,
                }).module("ziggy"),
            },
        },
    });
}
