const std = @import("std");
const db = @import("db.zig");
const login = @import("login.zig");
const settings = @import("settings.zig");
const builtin = @import("builtin");
const utils = @import("shared").utils;
const ztracy = @import("ztracy");
const rpmalloc = @import("rpmalloc").RPMalloc(.{});

pub const c = @cImport({
    @cDefine("REDIS_OPT_NONBLOCK", {});
    @cDefine("REDIS_OPT_REUSEADDR", {});
    @cInclude("hiredis.h");
});

pub var allocator: std.mem.Allocator = undefined;
pub var login_thread: std.Thread = undefined;
pub var start_time: i64 = 0;

// This is effectively just raw_c_allocator wrapped in the Tracy stuff
fn tracyAlloc(_: *anyopaque, len: usize, _: u8, _: usize) ?[*]u8 {
    const malloc = std.c.malloc(len);
    ztracy.Alloc(malloc, len);
    return @ptrCast(malloc);
}

fn tracyResize(_: *anyopaque, buf: []u8, _: u8, new_len: usize, _: usize) bool {
    return new_len <= buf.len;
}

fn tracyFree(_: *anyopaque, buf: []u8, _: u8, _: usize) void {
    ztracy.Free(buf.ptr);
    std.c.free(buf.ptr);
}

pub fn main() !void {
    start_time = std.time.microTimestamp();
    utils.rng.seed(@intCast(start_time));

    const is_debug = builtin.mode == .Debug;
    var gpa = if (is_debug) std.heap.GeneralPurposeAllocator(.{}){} else {};
    defer _ = if (is_debug) gpa.deinit();

    const tracy_allocator_vtable = std.mem.Allocator.VTable{
        .alloc = tracyAlloc,
        .resize = tracyResize,
        .free = tracyFree,
    };
    const tracy_allocator = std.mem.Allocator{
        .ptr = undefined,
        .vtable = &tracy_allocator_vtable,
    };

    try rpmalloc.init(null, .{});
    defer rpmalloc.deinit();

    allocator = if (settings.enable_tracy) tracy_allocator else switch (builtin.mode) {
        .Debug => gpa.allocator(),
        else => rpmalloc.allocator(),
    };

    try db.init(allocator);
    defer db.deinit();

    try login.init(allocator);
    defer login.deinit();

    login_thread = try std.Thread.spawn(.{}, login.tick, .{});
    defer login_thread.join();

    const stdin = std.io.getStdIn().reader();
    if (try stdin.readUntilDelimiterOrEofAlloc(allocator, '\n', 1024)) |dummy| {
        allocator.free(dummy);
    }
}
