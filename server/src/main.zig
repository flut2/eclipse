const std = @import("std");
const builtin = @import("builtin");

const build_options = @import("options");
const shared = @import("shared");
const game_data = shared.game_data;
const utils = shared.utils;
const uv = @import("uv");

const db = @import("db.zig");
const GameClient = @import("GameClient.zig");
const behavior = @import("logic/behavior.zig");
const behavior_logic = @import("logic/logic.zig");
const LoginClient = @import("LoginClient.zig");
const maps = @import("map/maps.zig");
const Settings = @import("Settings.zig");
const World = @import("World.zig");

const tracy = if (build_options.enable_tracy) @import("tracy") else {};

pub const game_buffer_size = std.math.maxInt(u16);
pub const login_buffer_size = std.math.maxInt(u12);

pub var game_reader: utils.PacketReader = .{};
pub var game_writer: utils.PacketWriter = .{};
pub var login_reader: utils.PacketReader = .{};
pub var login_writer: utils.PacketWriter = .{};
pub var stats_writer: utils.PacketWriter = .{};

pub var game_clients: std.ArrayList(GameClient) = .empty;
pub var login_clients: std.ArrayList(LoginClient) = .empty;
pub var game_client_free_list: std.ArrayList(usize) = .empty;
pub var login_client_free_list: std.ArrayList(usize) = .empty;
pub var game_buffers: std.ArrayList(u8) = .empty;
pub var login_buffers: std.ArrayList(u8) = .empty;
pub var game_buffer_free_list: std.ArrayList([]u8) = .empty;
pub var login_buffer_free_list: std.ArrayList([]u8) = .empty;
pub var game_timer: uv.uv_timer_t = .{};
pub var main_loop: uv.uv_loop_t = .{};
pub var allocator: std.mem.Allocator = undefined;
pub var tick_id: u8 = 0;
pub var current_time: i64 = -1;
pub var settings: Settings = .{};

var uv_pointer_size_map: std.AutoHashMapUnmanaged(usize, usize) = .empty;
var uv_alloc_mutex: std.Thread.Mutex = .{};
const uv_alignment: std.mem.Alignment = .of(std.c.max_align_t);

pub fn oomPanic() noreturn {
    @panic("Out of memory");
}

fn uvMalloc(size: usize) callconv(.c) ?*anyopaque {
    uv_alloc_mutex.lock();
    defer uv_alloc_mutex.unlock();

    const mem = allocator.alignedAlloc(u8, uv_alignment, size) catch oomPanic();
    uv_pointer_size_map.put(allocator, @intFromPtr(mem.ptr), size) catch oomPanic();
    return mem.ptr;
}

fn uvCalloc(size: usize, elem_size: usize) callconv(.c) ?*anyopaque {
    return uvMalloc(size * elem_size);
}

fn uvResize(maybe_ptr: ?*anyopaque, new_size: usize) callconv(.c) ?*anyopaque {
    uv_alloc_mutex.lock();
    defer uv_alloc_mutex.unlock();

    const old_size = if (maybe_ptr) |p| uv_pointer_size_map.fetchRemove(@intFromPtr(p)).?.value else 0;
    const old_mem: [*]align(uv_alignment.toByteUnits()) u8 = if (maybe_ptr) |p| @ptrCast(@alignCast(p)) else &.{};
    const new_mem = allocator.realloc(old_mem[0..old_size], new_size) catch oomPanic();
    uv_pointer_size_map.put(allocator, @intFromPtr(new_mem.ptr), new_size) catch oomPanic();
    return new_mem.ptr;
}

fn uvFree(maybe_ptr: ?*anyopaque) callconv(.c) void {
    const ptr = maybe_ptr orelse return;

    uv_alloc_mutex.lock();
    defer uv_alloc_mutex.unlock();

    const kv = uv_pointer_size_map.fetchRemove(@intFromPtr(ptr)) orelse {
        std.log.err("libuv: Invalid free attempted on {*}", .{ptr});
        return;
    };
    const mem: [*]align(uv_alignment.toByteUnits()) u8 = @ptrCast(@alignCast(ptr));
    allocator.free(mem[0..kv.value]);
}

fn walkCallback(handle: [*c]uv.uv_handle_t, _: ?*anyopaque) callconv(.c) void {
    if (uv.uv_is_closing(handle) == 1) return;
    std.log.err("Unclosed handle found during deinit walk: {*}", .{handle});
    uv.uv_close(handle, null);
}

pub fn main() !void {
    utils.rng.seed(@intCast(std.time.microTimestamp()));

    var dbg_alloc: std.heap.DebugAllocator(.{ .stack_trace_frames = 10 }) = .init;
    defer _ = dbg_alloc.deinit();
    var tracy_alloc: if (build_options.enable_tracy) tracy.TracyAllocator(null) else void =
        if (build_options.enable_tracy) .init(dbg_alloc.allocator()) else {};
    allocator = if (build_options.enable_tracy) tracy_alloc.allocator() else dbg_alloc.allocator();

    const replace_alloc_status = uv.uv_replace_allocator(uvMalloc, uvResize, uvCalloc, uvFree);
    if (replace_alloc_status != 0) {
        std.log.err("Libuv alloc replace error: {s}", .{uv.uv_strerror(replace_alloc_status)});
        return error.ReplaceAllocFailed;
    }
    defer uv_pointer_size_map.deinit(allocator);

    const create_status = uv.uv_loop_init(&main_loop);
    if (create_status != 0) {
        std.log.err("Loop creation error: {s}", .{uv.uv_strerror(create_status)});
        return error.NoLoop;
    }
    defer {
        uv.uv_walk(&main_loop, walkCallback, null);

        const run_status = uv.uv_run(&main_loop, uv.UV_RUN_DEFAULT);
        if (run_status != 0 and run_status != 1) std.log.err("Loop run error: {s}", .{uv.uv_strerror(run_status)});

        const close_status = uv.uv_loop_close(&main_loop);
        if (close_status != 0) std.log.err("Loop closing error: {s}", .{uv.uv_strerror(close_status)});
    }

    settings = try .init(allocator);
    defer Settings.deinit();

    try game_data.init(allocator);
    defer game_data.deinit();

    try behavior.init();
    defer behavior.deinit();

    try maps.init();
    defer maps.deinit();

    try db.init();
    defer db.deinit();

    game_reader.fba = .init(allocator.alloc(u8, game_buffer_size) catch oomPanic());
    defer allocator.free(game_reader.fba.buffer);

    game_writer.list = std.ArrayList(u8).initCapacity(allocator, game_buffer_size) catch oomPanic();
    defer game_writer.list.deinit(allocator);

    login_reader.fba = .init(allocator.alloc(u8, login_buffer_size) catch oomPanic());
    defer allocator.free(login_reader.fba.buffer);

    login_writer.list = std.ArrayList(u8).initCapacity(allocator, login_buffer_size) catch oomPanic();
    defer login_writer.list.deinit(allocator);

    // TODO: could be multiple packets so it should dynamically expand
    stats_writer.list = std.ArrayList(u8).initCapacity(allocator, std.math.maxInt(u20)) catch oomPanic();
    defer stats_writer.list.deinit(allocator);

    defer {
        game_clients.deinit(allocator);
        login_clients.deinit(allocator);
        game_client_free_list.deinit(allocator);
        login_client_free_list.deinit(allocator);
        game_buffers.deinit(allocator);
        login_buffers.deinit(allocator);
        game_buffer_free_list.deinit(allocator);
        login_buffer_free_list.deinit(allocator);
    }

    const timer_init_status = uv.uv_timer_init(&main_loop, &game_timer);
    if (timer_init_status != 0) std.debug.panic("Timer init failed: {s}", .{uv.uv_strerror(timer_init_status)});
    const timer_start_status = uv.uv_timer_start(&game_timer, timerCallback, 0, std.time.ms_per_s / settings.tps);
    if (timer_start_status != 0) std.debug.panic("Timer start failed: {s}", .{uv.uv_strerror(timer_start_status)});
    defer uv.uv_close(@ptrCast(&game_timer), null);

    var game_server: uv.uv_tcp_t = .{};
    var login_server: uv.uv_tcp_t = .{};
    listenToServer(onGameAccept, @ptrCast(&game_server), settings.game_port);
    listenToServer(onLoginAccept, @ptrCast(&login_server), settings.login_port);
    defer {
        uv.uv_close(@ptrCast(&game_server), null);
        uv.uv_close(@ptrCast(&login_server), null);
    }

    const run_status = uv.uv_run(&main_loop, uv.UV_RUN_DEFAULT);
    if (run_status != 0 and run_status != 1) std.log.err("Run failed: {s}", .{uv.uv_strerror(run_status)});
}

fn listenToServer(acceptFunc: fn ([*c]uv.uv_stream_t, i32) callconv(.c) void, server_handle: [*c]uv.uv_tcp_t, port: u16) void {
    const accept_socket_status = uv.uv_tcp_init(&main_loop, server_handle);
    if (accept_socket_status != 0) std.debug.panic("Setting up accept socket failed: {s}", .{uv.uv_strerror(accept_socket_status)});

    const disable_nagle_status = uv.uv_tcp_nodelay(server_handle, 1);
    if (disable_nagle_status != 0) std.debug.panic("Disabling Nagle on socket failed: {s}", .{uv.uv_strerror(disable_nagle_status)});

    const addr = std.net.Address.parseIp4("0.0.0.0", port) catch @panic("Parsing 0.0.0.0 failed");
    const socket_bind_status = uv.uv_tcp_bind(server_handle, @ptrCast(&addr.in.sa), 0);
    if (socket_bind_status != 0) std.debug.panic("Setting up socket bind failed: {s}", .{uv.uv_strerror(socket_bind_status)});

    const listen_result = uv.uv_listen(@ptrCast(server_handle), switch (builtin.os.tag) {
        .windows => std.os.windows.ws2_32.SOMAXCONN,
        .macos, .ios, .tvos, .watchos, .linux => std.os.linux.SOMAXCONN,
        else => @compileError("Host OS not supported"),
    }, acceptFunc);
    if (listen_result != 0) std.debug.panic("Listen error: {s}", .{uv.uv_strerror(listen_result)});
}

fn timerCallback(_: [*c]uv.uv_timer_t) callconv(.c) void {
    tick_id +%= 1;
    const time = std.time.microTimestamp();
    defer current_time = time;
    const dt = if (current_time == -1) 0 else time - current_time;

    const worlds_len = maps.worlds.count();
    if (worlds_len > 0) {
        var iter = utils.mapReverseIterator(i32, World, maps.worlds);
        var i = worlds_len - 1;
        while (iter.next()) |entry| : (i -%= 1) _ = if (!(entry.value_ptr.tick(time, dt) catch |e| blk: {
            std.log.err("Error while ticking world: {}", .{e});
            if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace.*);
            break :blk false;
        })) maps.worlds.swapRemoveAt(i);
    }
}

fn onGameAccept(server: [*c]uv.uv_stream_t, status: i32) callconv(.c) void {
    if (status < 0) {
        std.log.err("New game connection error: {s}", .{uv.uv_strerror(status)});
        return;
    }

    const cli = blk: {
        if (game_client_free_list.items.len > 0) {
            const free_idx = game_client_free_list.pop() orelse unreachable;
            const ret = &game_clients.items[free_idx];
            ret.* = .{ .list_index = free_idx };
            break :blk ret;
        }

        const ret = game_clients.addOne(allocator) catch oomPanic();
        ret.* = .{ .list_index = game_clients.items.len - 1 };
        break :blk ret;
    };

    const init_recv_status = uv.uv_tcp_init(&main_loop, &cli.socket);
    if (init_recv_status != 0) {
        std.log.err("Failed to initialize received game socket: {s}", .{uv.uv_strerror(init_recv_status)});
        return;
    }
    cli.socket.data = cli;

    const accept_status = uv.uv_accept(server, @ptrCast(&cli.socket));
    if (accept_status != 0) {
        std.log.err("Failed to accept game socket: {s}", .{uv.uv_strerror(accept_status)});
        uv.uv_close(@ptrCast(&cli.socket), null);
        return;
    }

    const disable_nagle_status = uv.uv_tcp_nodelay(&cli.socket, 1);
    if (disable_nagle_status != 0)
        std.log.err("Disabling Nagle on game socket failed: {s}", .{uv.uv_strerror(disable_nagle_status)});

    const read_init_status = uv.uv_read_start(@ptrCast(&cli.socket), GameClient.allocBuffer, GameClient.readCallback);
    if (read_init_status != 0) {
        std.log.err("Failed to initialize reading on game socket: {s}", .{uv.uv_strerror(read_init_status)});
        cli.shutdown();
        return;
    }

    cli.initialized = true;
}

fn onLoginAccept(server: [*c]uv.uv_stream_t, status: i32) callconv(.c) void {
    if (status < 0) {
        std.log.err("New login connection error: {s}", .{uv.uv_strerror(status)});
        return;
    }

    const cli = blk: {
        if (login_client_free_list.items.len > 0) {
            const free_idx = login_client_free_list.pop() orelse unreachable;
            const ret = &login_clients.items[free_idx];
            ret.* = .{ .list_index = free_idx };
            break :blk ret;
        }

        const ret = login_clients.addOne(allocator) catch oomPanic();
        ret.* = .{ .list_index = login_clients.items.len - 1 };
        break :blk ret;
    };

    const init_recv_status = uv.uv_tcp_init(&main_loop, &cli.socket);
    if (init_recv_status != 0) {
        std.log.err("Failed to initialize received login socket: {s}", .{uv.uv_strerror(init_recv_status)});
        return;
    }
    cli.socket.data = cli;

    const disable_nagle_status = uv.uv_tcp_nodelay(&cli.socket, 1);
    if (disable_nagle_status != 0)
        std.log.err("Disabling Nagle on login socket failed: {s}", .{uv.uv_strerror(disable_nagle_status)});

    const accept_status = uv.uv_accept(server, @ptrCast(&cli.socket));
    if (accept_status != 0) {
        std.log.err("Failed to accept login socket: {s}", .{uv.uv_strerror(accept_status)});
        uv.uv_close(@ptrCast(&cli.socket), null);
        return;
    }

    const read_init_status = uv.uv_read_start(@ptrCast(&cli.socket), LoginClient.allocBuffer, LoginClient.readCallback);
    if (read_init_status != 0) {
        std.log.err("Failed to initialize reading on login socket: {s}", .{uv.uv_strerror(read_init_status)});
        cli.shutdown();
        return;
    }

    cli.initialized = true;
}
