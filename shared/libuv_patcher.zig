const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    var args = try std.process.argsWithAllocator(allocator);
    _ = args.skip();
    const rel_path = args.next() orelse {
        std.log.err("Path not found for uv.zig, patching unsuccessful", .{});
        return;
    };

    const temp_name = "uv_temp.zig";
    var unpatched_file = try std.fs.cwd().openFile(rel_path, .{ .mode = .read_only });
    var patched_file = try std.fs.cwd().createFile(temp_name, .{});

    var rdr_buf: [4096]u8 = undefined;
    var wtr_buf: [4096]u8 = undefined;
    var reader = unpatched_file.reader(&rdr_buf);
    var writer = patched_file.writer(&wtr_buf);

    while (true) {
        const line = reader.interface.takeDelimiterInclusive('\n') catch |e| switch (e) {
            error.EndOfStream => {
                try std.fs.cwd().rename(temp_name, rel_path);
                patched_file.close();
                unpatched_file.close();
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
}