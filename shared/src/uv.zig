const std = @import("std");

const uv = @import("uv");

const utils = @import("utils.zig");

var uv_allocator: std.mem.Allocator = undefined;
var pointer_size_map: std.AutoHashMapUnmanaged(usize, usize) = .empty;
var alloc_mutex: std.Io.Mutex = .init;
var alloc_io: std.Io = .failing;
const alignment: std.mem.Alignment = .of(std.c.max_align_t);

fn outOfMemory() noreturn {
    @panic("libuv: Out of memory");
}

fn uvMalloc(size: usize) callconv(.c) ?*anyopaque {
    alloc_mutex.lockUncancelable(alloc_io);
    defer alloc_mutex.unlock(alloc_io);

    const mem = uv_allocator.alignedAlloc(u8, alignment, size) catch outOfMemory();
    pointer_size_map.put(uv_allocator, @intFromPtr(mem.ptr), size) catch outOfMemory();
    return mem.ptr;
}

fn uvCalloc(size: usize, elem_size: usize) callconv(.c) ?*anyopaque {
    return uvMalloc(size * elem_size);
}

fn uvResize(maybe_ptr: ?*anyopaque, new_size: usize) callconv(.c) ?*anyopaque {
    alloc_mutex.lockUncancelable(alloc_io);
    defer alloc_mutex.unlock(alloc_io);

    const old_size = if (maybe_ptr) |p| pointer_size_map.fetchRemove(@intFromPtr(p)).?.value else 0;
    const old_mem: [*]align(alignment.toByteUnits()) u8 = if (maybe_ptr) |p| @ptrCast(@alignCast(p)) else &.{};
    const new_mem = uv_allocator.realloc(old_mem[0..old_size], new_size) catch outOfMemory();
    pointer_size_map.put(uv_allocator, @intFromPtr(new_mem.ptr), new_size) catch outOfMemory();
    return new_mem.ptr;
}

fn uvFree(maybe_ptr: ?*anyopaque) callconv(.c) void {
    const ptr = maybe_ptr orelse return;

    alloc_mutex.lockUncancelable(alloc_io);
    defer alloc_mutex.unlock(alloc_io);

    const kv = pointer_size_map.fetchRemove(@intFromPtr(ptr)) orelse {
        std.log.err("libuv: Invalid free attempted on `{*}`", .{ptr});
        return;
    };
    const mem: [*]align(alignment.toByteUnits()) u8 = @ptrCast(@alignCast(ptr));
    uv_allocator.free(mem[0..kv.value]);
}

pub fn init(allocator: std.mem.Allocator, io: std.Io) !void {
    uv_allocator = allocator;
    alloc_io = io;

    const replace_alloc_status = uv.uv_replace_allocator(uvMalloc, uvResize, uvCalloc, uvFree);
    if (replace_alloc_status != 0) {
        std.log.err("Libuv alloc replace error: `{s}`", .{uv.uv_strerror(replace_alloc_status)});
        return error.ReplaceAllocFailed;
    }
}

pub fn deinit() void {
    pointer_size_map.deinit(uv_allocator);
}

pub fn walkCallback(handle: [*c]uv.uv_handle_t, _: ?*anyopaque) callconv(.c) void {
    if (uv.uv_is_closing(handle) == 1) return;
    const type_str = switch (handle.*.type) {
        uv.UV_UNKNOWN_HANDLE => "Unknown",
        uv.UV_ASYNC => "Async",
        uv.UV_CHECK => "Check",
        uv.UV_FS_EVENT => "Filesystem Event",
        uv.UV_FS_POLL => "Filesystem Poll",
        uv.UV_HANDLE => "Handle",
        uv.UV_IDLE => "Idle",
        uv.UV_NAMED_PIPE => "Named Pipe",
        uv.UV_POLL => "Poll",
        uv.UV_PREPARE => "Prepare",
        uv.UV_PROCESS => "Process",
        uv.UV_STREAM => "Stream",
        uv.UV_TCP => "TCP",
        uv.UV_TIMER => "Timer",
        uv.UV_TTY => "TTY",
        uv.UV_UDP => "UDP",
        uv.UV_SIGNAL => "Signal",
        uv.UV_FILE => "File",
        else => "Invalid",
    };
    std.log.err("Unclosed handle with type `{s}` found during deinit walk: `{*}`", .{ type_str, handle });
    uv.uv_close(handle, null);
}

pub fn socketWrite(
    comptime T: type,
    comptime log_name: []const u8,
    packet: T,
    writer: *utils.PacketWriter,
    socket: *uv.uv_tcp_t,
    comptime logWrite: fn (comptime std.meta.Tag(T)) bool,
) i32 {
    switch (packet) {
        inline else => |_, tag| if (comptime logWrite(tag))
            std.log.info("Sending {s}: {f}", .{ log_name, packet }),
    }

    switch (packet) {
        inline else => |body| {
            writer.list.clearRetainingCapacity();
            writer.writeLength();
            writer.write(@intFromEnum(std.meta.activeTag(packet)));
            writer.write(body);
            writer.updateLength();

            const uv_buffer: uv.uv_buf_t = .{ .base = @ptrCast(writer.list.items.ptr), .len = @intCast(writer.list.items.len) };
            var write_status = uv.UV_EAGAIN;
            while (write_status == uv.UV_EAGAIN or write_status > 0 and write_status < writer.list.items.len)
                write_status = uv.uv_try_write(@ptrCast(socket), @ptrCast(&uv_buffer), 1);
            return write_status;
        },
    }
}

pub fn socketRead(
    comptime T: type,
    comptime log_name: []const u8,
    client: anytype,
    bytes_read: isize,
    reader: *utils.PacketReader,
    comptime handlerFn: anytype,
    comptime logRead: fn (comptime std.meta.Tag(T)) bool,
) bool {
    reader.reset();

    while (reader.index <= bytes_read - 5) {
        const len = reader.read(u32);
        if (len > bytes_read - reader.index) return true;

        const next_packet_idx = reader.index + len;
        const byte_id = reader.read(std.meta.Int(.unsigned, @bitSizeOf(std.meta.Tag(T))));
        const packet_id = std.enums.fromInt(std.meta.Tag(T), byte_id) orelse {
            std.log.err("Error parsing {s} with id `{}`, size `{}`, len `{}`", .{ log_name, byte_id, bytes_read, len });
            return false;
        };

        switch (packet_id) {
            inline else => |tag| {
                const packet = reader.read(@FieldType(T, @tagName(tag)));
                if (comptime logRead(tag))
                    std.log.info("Reading {s} with len `{}`: {f}", .{ log_name, len, @unionInit(T, @tagName(tag), packet) });
                handlerFn(tag)(client, packet);
            },
        }

        if (reader.index < next_packet_idx) {
            std.log.err("{s} {} has {} bytes left over", .{ log_name, packet_id, next_packet_idx - reader.index });
            reader.index = next_packet_idx;
        }
    }

    return true;
}
