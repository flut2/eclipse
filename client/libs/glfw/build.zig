const std = @import("std");
const builtin = @import("builtin");

const Libraries = struct {
    const windows = [_][]const u8{ "gdi32", "user32", "shell32" };
    const linux = [_][]const u8{};
    const apple = [_][]const u8{"objc"};
    const frameworks = [_][]const u8{
        "IOKit",
        "CoreFoundation",
        "Metal",
        "AppKit",
        "CoreServices",
        "CoreGraphics",
        "Foundation",
    };
};

const Sources = struct {
    const base = [_][]const u8{
        "platform.c",
        "monitor.c",
        "init.c",
        "vulkan.c",
        "input.c",
        "context.c",
        "window.c",
        "osmesa_context.c",
        "egl_context.c",
        "null_init.c",
        "null_monitor.c",
        "null_window.c",
        "null_joystick.c",
    };
    const unix = [_][]const u8{ "posix_thread.c", "posix_module.c", "posix_poll.c" };
    const windows = base ++ [_][]const u8{
        "wgl_context.c",
        "win32_thread.c",
        "win32_init.c",
        "win32_monitor.c",
        "win32_time.c",
        "win32_joystick.c",
        "win32_window.c",
        "win32_module.c",
    };
    const linux = base ++ unix ++ [_][]const u8{ "posix_time.c", "xkb_unicode.c", "linux_joystick.c" };
    const apple = base ++ unix ++ [_][]const u8{
        "nsgl_context.m",
        "cocoa_time.c",
        "cocoa_joystick.m",
        "cocoa_init.m",
        "cocoa_window.m",
        "cocoa_monitor.m",
    };
};

const Definitions = struct {
    const windows = [_][]const u8{"-D_GLFW_WIN32"};
    const linux = [_][]const u8{};
    const apple = [_][]const u8{"-D_GLFW_COCOA"};
};

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const options = .{
        .shared = b.option(bool, "shared", "Build GLFW as shared library") orelse false,
        .enable_x11 = b.option(bool, "x11", "Whether to build with X11 support") orelse true,
        .enable_wayland = b.option(bool, "wayland", "Whether to build with Wayland support") orelse false,
    };

    const opt_step = b.addOptions();
    inline for (@typeInfo(@TypeOf(options)).@"struct".fields) |field|
        opt_step.addOption(field.type, field.name, @field(options, field.name));

    _ = b.addModule("root", .{
        .root_source_file = b.path("glfw.zig"),
        .imports = &.{.{ .name = "options", .module = opt_step.createModule() }},
    });

    const glfw_lib = b.addLibrary(.{
        .name = "glfw",
        .linkage = if (options.shared) .dynamic else .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    if (options.shared and target.result.os.tag == .windows)
        glfw_lib.root_module.addCMacro("_GLFW_BUILD_DLL", "");
    b.installArtifact(glfw_lib);

    const glfw_dep = b.dependency("glfw", .{
        .target = target,
        .optimize = optimize,
    });

    glfw_lib.root_module.addIncludePath(glfw_dep.path("include"));
    const os_name = @tagName(builtin.os.tag);
    for (@field(Libraries, os_name)) |lib_name| glfw_lib.root_module.linkSystemLibrary(lib_name, .{});
    const src_path = glfw_dep.path("src");
    glfw_lib.root_module.addCSourceFiles(.{
        .root = src_path,
        .files = &@field(Sources, os_name),
        .flags = &@field(Definitions, os_name),
    });

    switch (target.result.os.tag) {
        .macos => for (Libraries.frameworks) |fw_name| glfw_lib.root_module.linkFramework(fw_name, .{}),
        .linux => {
            if (options.enable_x11) {
                glfw_lib.root_module.addCSourceFiles(.{
                    .root = src_path,
                    .files = &.{ "x11_init.c", "x11_monitor.c", "x11_window.c", "glx_context.c" },
                    .flags = &.{},
                });
                glfw_lib.root_module.addCMacro("_GLFW_X11", "");
                glfw_lib.root_module.linkSystemLibrary("X11", .{});
            }

            if (options.enable_wayland) {
                glfw_lib.root_module.addCSourceFiles(.{
                    .root = src_path,
                    .files = &.{ "wl_init.c", "wl_monitor.c", "wl_window.c" },
                    .flags = &.{},
                });
                glfw_lib.root_module.addCMacro("_GLFW_WAYLAND", "");
            }
        },
        else => {},
    }
}
