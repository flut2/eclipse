const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var args = try init.minimal.args.iterateAllocator(init.gpa);
    defer args.deinit();
    _ = args.skip();
    const rel_path = args.next() orelse {
        std.log.err("Path not found for uv.zig, patching unsuccessful", .{});
        return;
    };

    const cwd = std.Io.Dir.cwd();
    const temp_name = "uv_temp.zig";
    var unpatched_file = try cwd.openFile(init.io, rel_path, .{ .mode = .read_only });
    errdefer unpatched_file.close(init.io);
    var patched_file = try cwd.createFile(init.io, temp_name, .{});
    errdefer patched_file.close(init.io);

    var rdr_buf: [4096]u8 = undefined;
    var wtr_buf: [4096]u8 = undefined;
    var reader = unpatched_file.reader(init.io, &rdr_buf);
    var writer = patched_file.writer(init.io, &wtr_buf);

    while (true) {
        const line = reader.interface.takeDelimiterInclusive('\n') catch |e| switch (e) {
            error.EndOfStream => {
                try std.Io.Dir.rename(cwd, temp_name, cwd, rel_path, init.io);
                patched_file.close(init.io);
                unpatched_file.close(init.io);
                return;
            },
            else => return e,
        };

        if (std.mem.eql(u8, "pub const uv_read_cb = ?*const fn ([*c]uv_stream_t, isize, [*c]const uv_buf_t) callconv(.c) void;\n", line))
            try writer.interface.writeAll(
                "pub const uv_read_cb = ?*const fn (*anyopaque, isize, [*c]const uv_buf_t) callconv(.c) void;\n",
            )
        else
            try writer.interface.writeAll(line);
        try writer.interface.flush();
    }

    std.log.warn("Did not reach the expected `EndOfStream` during patching", .{});
    patched_file.close(init.io);
    unpatched_file.close(init.io);
}
