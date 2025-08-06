const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    var args = try std.process.argsWithAllocator(allocator);
    _ = args.next();
    const rel_path = args.next().?;

    var new_file_data: std.ArrayListUnmanaged(u8) = .empty;
    defer new_file_data.deinit(allocator);

    {
        var file = try std.fs.cwd().openFile(rel_path, .{ .mode = .read_only });
        defer file.close();

        var buf_reader = std.io.bufferedReader(file.deprecatedReader());
        var stream = buf_reader.reader();
        while (try stream.readUntilDelimiterOrEofAlloc(allocator, '\n', std.math.maxInt(u32))) |line| {
            try new_file_data.append(allocator, '\n');

            if (std.mem.eql(u8, "pub const uv_read_cb = ?*const fn ([*c]uv_stream_t, isize, [*c]const uv_buf_t) callconv(.c) void;", line))
                try new_file_data.appendSlice(
                    allocator,
                    "pub const uv_read_cb = ?*const fn (*anyopaque, isize, [*c]const uv_buf_t) callconv(.c) void;",
                )
            else
                try new_file_data.appendSlice(allocator, line);
        }
    }

    try std.fs.cwd().deleteFile(rel_path);

    var new_file = try std.fs.cwd().createFile(rel_path, .{});
    defer new_file.close();
    try new_file.writeAll(new_file_data.items);
}
