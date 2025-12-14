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

const tracy = if (build_options.tracy) @import("tracy") else {};

// The size (in bytes) for each corresponding reader/writer.
// Note that only a single one of each is used, as libuv's TCP
// seems to always call the read callback after an allocation,
// so the allocation lifetime is effectively sync.
pub const game_buffer_size = std.math.maxInt(u24);
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
pub var game_timer: uv.uv_timer_t = .{};
pub var main_loop: uv.uv_loop_t = .{};
pub var allocator: std.mem.Allocator = undefined;
pub var tick_id: u8 = 0;
pub var current_time: i64 = -1;
pub var settings: Settings = .{};

pub fn oomPanic() noreturn {
    @panic("Out of memory");
}

pub fn main() !void {
    utils.rng.seed(@intCast(std.time.microTimestamp()));

    var dbg_alloc: std.heap.DebugAllocator(.{ .stack_trace_frames = 10 }) = .init;
    defer _ = dbg_alloc.deinit();
    var tracy_alloc: if (build_options.tracy) tracy.TracyAllocator(null) else void =
        if (build_options.tracy) .init(dbg_alloc.allocator()) else {};
    allocator = if (build_options.tracy) tracy_alloc.allocator() else dbg_alloc.allocator();

    defer {
        game_clients.deinit(allocator);
        login_clients.deinit(allocator);
        game_client_free_list.deinit(allocator);
        login_client_free_list.deinit(allocator);
    }

    try shared.uv.init(allocator);
    defer shared.uv.deinit();

    const create_status = uv.uv_loop_init(&main_loop);
    if (create_status != 0) {
        std.log.err("Loop creation error: {s}", .{uv.uv_strerror(create_status)});
        return error.NoLoop;
    }
    defer {
        uv.uv_walk(&main_loop, shared.uv.walkCallback, null);

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

    game_reader.init(allocator, game_buffer_size) catch oomPanic();
    defer game_reader.deinit(allocator);

    game_writer.init(allocator, game_buffer_size) catch oomPanic();
    defer game_writer.deinit(allocator);

    login_reader.init(allocator, login_buffer_size) catch oomPanic();
    defer login_reader.deinit(allocator);

    login_writer.init(allocator, login_buffer_size) catch oomPanic();
    defer login_writer.deinit(allocator);

    stats_writer.init(allocator, game_buffer_size) catch oomPanic();
    defer stats_writer.deinit(allocator);

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
        for (game_clients.items) |*cli| uv.uv_close(@ptrCast(&cli.socket), null);
        for (login_clients.items) |*cli| uv.uv_close(@ptrCast(&cli.socket), null);
    }

    const run_status = uv.uv_run(&main_loop, uv.UV_RUN_DEFAULT);
    if (run_status != 0 and run_status != 1) {
        std.log.err("Run failed: {s}", .{uv.uv_strerror(run_status)});
        return error.RunFailed;
    }
}

fn listenToServer(acceptFunc: fn ([*c]uv.uv_stream_t, i32) callconv(.c) void, server_handle: [*c]uv.uv_tcp_t, port: u16) void {
    const accept_socket_status = uv.uv_tcp_init(&main_loop, server_handle);
    if (accept_socket_status != 0) std.debug.panic("Setting up accept socket failed: {s}", .{uv.uv_strerror(accept_socket_status)});

    const disable_nagle_status = uv.uv_tcp_nodelay(server_handle, 1);
    if (disable_nagle_status != 0) std.debug.panic("Disabling Nagle on socket failed: {s}", .{uv.uv_strerror(disable_nagle_status)});

    const addr = std.net.Address.parseIp4("0.0.0.0", port) catch @panic("Parsing 0.0.0.0 failed");
    const socket_bind_status = uv.uv_tcp_bind(server_handle, @ptrCast(&addr.in.sa), 0);
    if (socket_bind_status != 0) std.debug.panic("Setting up socket bind failed: {s}", .{uv.uv_strerror(socket_bind_status)});

    const listen_result = uv.uv_listen(@ptrCast(server_handle), std.c.SOMAXCONN, acceptFunc);
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
