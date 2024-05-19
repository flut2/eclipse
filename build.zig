const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    if (b.option(bool, "client", "Build/run client") orelse false) {
        const client_dep = b.dependency("client", .{
            .target = target,
            .optimize = optimize,
            .enable_tracy = b.option(bool, "enable_tracy", "Enable Tracy") orelse false,
        });
        const client_exe = client_dep.artifact("Eclipse");
        b.getInstallStep().dependOn(&b.addInstallArtifact(client_exe, .{
            .dest_dir = .{ .override = .{ .custom = "bin/client" } },
        }).step);
        const run_cmd_cli = b.addRunArtifact(client_exe);
        run_cmd_cli.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd_cli.addArgs(args);
        }

        client_exe.step.dependOn(&b.addInstallDirectory(.{
            .source_dir = .{ .path = "assets/shared" },
            .install_dir = .{ .bin = {} },
            .install_subdir = "client/assets",
        }).step);

        client_exe.step.dependOn(&b.addInstallDirectory(.{
            .source_dir = .{ .path = "assets/client" },
            .install_dir = .{ .bin = {} },
            .install_subdir = "client/assets",
        }).step);

        b.step("run", "Run the Eclipse client").dependOn(&run_cmd_cli.step);
    } else if (b.option(bool, "server", "Build/run server") orelse false) {
        const server_dep = b.dependency("server", .{
            .target = target,
            .optimize = optimize,
            .enable_tracy = b.option(bool, "enable_tracy", "Enable Tracy") orelse false,
        });
        const server_exe = server_dep.artifact("Eclipse");
        b.getInstallStep().dependOn(&b.addInstallArtifact(server_exe, .{
            .dest_dir = .{ .override = .{ .custom = "bin/server" } },
        }).step);
        const run_cmd_srv = b.addRunArtifact(server_exe);
        run_cmd_srv.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd_srv.addArgs(args);
        }

        server_exe.step.dependOn(&b.addInstallDirectory(.{
            .source_dir = .{ .path = "assets/shared" },
            .install_dir = .{ .bin = {} },
            .install_subdir = "server/assets",
        }).step);

        server_exe.step.dependOn(&b.addInstallDirectory(.{
            .source_dir = .{ .path = "assets/server" },
            .install_dir = .{ .bin = {} },
            .install_subdir = "server/assets",
        }).step);

        b.step("run", "Run the Eclipse server").dependOn(&run_cmd_srv.step);
    } else std.debug.panic("Invalid build, please specify -Dclient or -Dserver", .{});
}
