const std = @import("std");
const db = @import("db.zig");
const login = @import("login.zig");
const settings = @import("settings.zig");
const builtin = @import("builtin");
const utils = @import("shared").utils;
const ztracy = @import("ztracy");
const rpmalloc = @import("rpmalloc").RPMalloc(.{});
const xev = @import("xev");
const game_data = @import("shared").game_data;
const maps = @import("map/maps.zig");
const behavior = @import("logic/behavior.zig");
const behavior_logic = @import("logic/logic.zig");

const Client = @import("client.zig").Client;

pub const c = @cImport({
    @cDefine("REDIS_OPT_NONBLOCK", {});
    @cDefine("REDIS_OPT_REUSEADDR", {});
    @cInclude("hiredis.h");
});

pub const tps_ms = 1000 / settings.tps;

pub const read_buffer_size = 65535;
pub const write_buffer_size = 65535;

pub var client_pool: std.heap.MemoryPool(Client) = undefined;
pub var socket_pool: std.heap.MemoryPool(xev.TCP) = undefined;
pub var completion_pool: std.heap.MemoryPool(xev.Completion) = undefined;
pub var node_pool: std.heap.MemoryPool(utils.MPSCQueue.Node) = undefined;
pub var read_buffer_pool: std.heap.MemoryPool([read_buffer_size]u8) = undefined;
pub var write_buffer_pool: std.heap.MemoryPool([write_buffer_size]u8) = undefined;
pub var game_timer: xev.Timer = undefined;
pub var game_loop: xev.Loop = undefined;
pub var allocator: std.mem.Allocator = undefined;
pub var login_thread: std.Thread = undefined;
pub var game_thread: std.Thread = undefined;
pub var tick_game: bool = true;
pub var tick_id: u8 = 0;
pub var current_time: i64 = -1;

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

fn timerCallback(tick_timer: ?*xev.Timer, timer_loop: *xev.Loop, timer_comp: *xev.Completion, _: xev.Timer.RunError!void) xev.CallbackAction {
    tick_timer.?.run(timer_loop, timer_comp, tps_ms, xev.Timer, tick_timer.?, timerCallback);
    tick_id +%= 1;
    const time = std.time.microTimestamp();
    defer current_time = time;
    const dt = if (current_time == -1) 0 else time - current_time;
    var iter = maps.worlds.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.tick(time, dt) catch unreachable;
    }
    return .disarm;
}

pub fn gameTick() !void {
    rpmalloc.initThread() catch |e| {
        std.log.err("Game thread initialization failed: {}", .{e});
        return;
    };
    defer rpmalloc.deinitThread(true);

    const addr = try std.net.Address.parseIp4("0.0.0.0", settings.game_port);
    var socket = try xev.TCP.init(addr);

    try socket.bind(addr);
    try socket.listen(switch (builtin.os.tag) {
        .windows => std.os.windows.ws2_32.SOMAXCONN,
        .macos, .ios, .tvos, .watchos => std.os.darwin.SOMAXCONN,
        .linux => std.os.linux.SOMAXCONN,
        else => @panic("Host OS not supported"),
    });

    const timer_comp = try completion_pool.create();
    defer completion_pool.destroy(timer_comp);
    game_timer.run(&game_loop, timer_comp, tps_ms, xev.Timer, &game_timer, timerCallback);

    while (tick_game) {
        const comp = try completion_pool.create();
        socket.accept(&game_loop, comp, anyopaque, null, acceptCallback);
        try game_loop.run(.until_done);
    }
}

fn acceptCallback(_: ?*anyopaque, loop: *xev.Loop, comp: *xev.Completion, result: xev.TCP.AcceptError!xev.TCP) xev.CallbackAction {
    const socket = socket_pool.create() catch unreachable;
    socket.* = result catch unreachable;

    const buf = read_buffer_pool.create() catch unreachable;
    const secondary_buf = read_buffer_pool.create() catch unreachable;
    const cli = client_pool.create() catch unreachable;
    cli.* = Client.init(allocator, loop, socket, buf, secondary_buf) catch unreachable;
    socket.read(loop, comp, .{ .slice = cli.reader.buffer }, Client, cli, Client.readCallback);
    return .disarm;
}

pub fn main() !void {
    utils.rng.seed(@intCast(std.time.microTimestamp()));

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

    client_pool = std.heap.MemoryPool(Client).init(allocator);
    defer client_pool.deinit();

    socket_pool = std.heap.MemoryPool(xev.TCP).init(allocator);
    defer socket_pool.deinit();

    completion_pool = std.heap.MemoryPool(xev.Completion).init(allocator);
    defer completion_pool.deinit();

    node_pool = std.heap.MemoryPool(utils.MPSCQueue.Node).init(allocator);
    defer node_pool.deinit();

    read_buffer_pool = std.heap.MemoryPool([read_buffer_size]u8).init(allocator);
    defer read_buffer_pool.deinit();

    write_buffer_pool = std.heap.MemoryPool([write_buffer_size]u8).init(allocator);
    defer write_buffer_pool.deinit();

    try game_data.init(allocator);
    defer game_data.deinit(allocator);

    behavior_logic.init(allocator);
    defer behavior_logic.deinit();

    try behavior.init(allocator);
    defer behavior.deinit();

    try maps.init(allocator);
    defer maps.deinit();

    try db.init(allocator);
    defer db.deinit();

    try login.init(allocator);
    defer login.deinit();

    var thread_pool = xev.ThreadPool.init(.{});
    defer thread_pool.deinit();
    defer thread_pool.shutdown();

    game_loop = try xev.Loop.init(.{
        .entries = std.math.maxInt(u12) + 1,
        .thread_pool = &thread_pool,
    });

    game_timer = try xev.Timer.init();
    defer game_timer.deinit();

    login_thread = try std.Thread.spawn(.{}, login.tick, .{});
    defer login_thread.join();

    game_thread = try std.Thread.spawn(.{}, gameTick, .{});
    defer {
        tick_game = false;
        game_thread.join();
    }

    const stdin = std.io.getStdIn().reader();
    if (try stdin.readUntilDelimiterOrEofAlloc(allocator, '\n', 1024)) |dummy| {
        allocator.free(dummy);
    }
}
