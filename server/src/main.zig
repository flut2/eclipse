const std = @import("std");
const builtin = @import("builtin");

const build_options = @import("options");
const shared = @import("shared");
const game_data = shared.game_data;
const utils = shared.utils;
const uv = shared.uv;

const db = @import("db.zig");
const GameClient = @import("GameClient.zig");
const behavior = @import("logic/behavior.zig");
const behavior_logic = @import("logic/logic.zig");
const LoginClient = @import("LoginClient.zig");
const maps = @import("map/maps.zig");
const Settings = @import("Settings.zig");
const World = @import("World.zig");

const tracy = if (build_options.enable_tracy) @import("tracy") else {};
pub const c = @cImport({
    @cDefine("REDIS_OPT_NONBLOCK", {});
    @cDefine("REDIS_OPT_REUSEADDR", {});
    @cInclude("hiredis.h");
});

pub var game_client_pool: std.heap.MemoryPool(GameClient) = undefined;
pub var login_client_pool: std.heap.MemoryPool(LoginClient) = undefined;
pub var socket_pool: std.heap.MemoryPool(uv.uv_tcp_t) = undefined;
pub var game_timer: uv.uv_timer_t = undefined;
pub var allocator: std.mem.Allocator = undefined;
pub var tick_id: u8 = 0;
pub var current_time: i64 = -1;
pub var settings: Settings = .{};

pub fn oomPanic() noreturn {
    @panic("Out of memory");
}

pub fn main() !void {
    if (build_options.enable_tracy) tracy.SetThreadName("Main");

    utils.rng.seed(@intCast(std.time.microTimestamp()));

    const enable_gpa = build_options.enable_gpa;
    var gpa = if (enable_gpa) std.heap.DebugAllocator(.{}).init else std.heap.smp_allocator;
    defer _ = if (enable_gpa) gpa.deinit();

    allocator = if (enable_gpa) gpa.allocator() else std.heap.smp_allocator;
    // allocator = if (build_options.enable_tracy) blk: {
    //     var tracy_alloc: tracy.TracyAllocator = .init(child_allocator);
    //     break :blk tracy_alloc.allocator();
    // } else child_allocator;

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

    game_client_pool = .init(allocator);
    defer game_client_pool.deinit();

    login_client_pool = .init(allocator);
    defer login_client_pool.deinit();

    socket_pool = .init(allocator);
    defer socket_pool.deinit();

    const timer_init_status = uv.uv_timer_init(uv.uv_default_loop(), @ptrCast(&game_timer));
    if (timer_init_status != 0) std.debug.panic("Timer init failed: {s}", .{uv.uv_strerror(timer_init_status)});
    const timer_start_status = uv.uv_timer_start(@ptrCast(&game_timer), timerCallback, 0, std.time.ms_per_s / settings.tps);
    if (timer_start_status != 0) std.debug.panic("Timer start failed: {s}", .{uv.uv_strerror(timer_start_status)});

    var game_server: uv.uv_tcp_t = .{};
    var login_server: uv.uv_tcp_t = .{};
    listenToServer(onGameAccept, @ptrCast(&game_server), settings.game_port);
    listenToServer(onLoginAccept, @ptrCast(&login_server), settings.login_port);

    const run_status = uv.uv_run(uv.uv_default_loop(), uv.UV_RUN_DEFAULT);
    if (run_status != 0 and run_status != 1) std.log.err("Run failed: {s}", .{uv.uv_strerror(run_status)});
}

fn listenToServer(acceptFunc: fn ([*c]uv.uv_stream_t, i32) callconv(.C) void, server_handle: [*c]uv.uv_tcp_t, port: u16) void {
    const accept_socket_status = uv.uv_tcp_init(uv.uv_default_loop(), server_handle);
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

fn timerCallback(_: [*c]uv.uv_timer_t) callconv(.C) void {
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

fn onGameAccept(server: [*c]uv.uv_stream_t, status: i32) callconv(.C) void {
    if (status < 0) {
        std.log.err("New game connection error: {s}", .{uv.uv_strerror(status)});
        return;
    }

    const socket = socket_pool.create() catch oomPanic();
    const init_recv_status = uv.uv_tcp_init(uv.uv_default_loop(), @ptrCast(socket));
    if (init_recv_status != 0) {
        std.log.err("Failed to initialize received game socket: {s}", .{uv.uv_strerror(init_recv_status)});
        uv.uv_close(@ptrCast(socket), onSocketClose);
        return;
    }

    const disable_nagle_status = uv.uv_tcp_nodelay(@ptrCast(socket), 1);
    if (disable_nagle_status != 0) {
        std.debug.panic("Disabling Nagle on socket failed: {s}", .{uv.uv_strerror(disable_nagle_status)});
        uv.uv_close(@ptrCast(socket), onSocketClose);
        return;
    }

    const accept_status = uv.uv_accept(server, @ptrCast(socket));
    if (accept_status != 0) {
        std.log.err("Failed to accept game socket: {s}", .{uv.uv_strerror(accept_status)});
        uv.uv_close(@ptrCast(socket), onSocketClose);
        return;
    }

    const cli = game_client_pool.create() catch oomPanic();
    socket.*.data = cli;
    cli.* = .{ .read_arena = .init(allocator), .socket = socket };

    const read_init_status = uv.uv_read_start(@ptrCast(socket), GameClient.allocBuffer, GameClient.readCallback);
    if (read_init_status != 0) {
        std.log.err("Failed to initialize reading on game socket: {s}", .{uv.uv_strerror(read_init_status)});
        cli.shutdown();
        return;
    }
}

fn onLoginAccept(server: [*c]uv.uv_stream_t, status: i32) callconv(.C) void {
    if (status < 0) {
        std.log.err("New login connection error: {s}", .{uv.uv_strerror(status)});
        return;
    }

    const socket = socket_pool.create() catch oomPanic();
    const init_recv_status = uv.uv_tcp_init(uv.uv_default_loop(), @ptrCast(socket));
    if (init_recv_status != 0) {
        std.log.err("Failed to initialize received login socket: {s}", .{uv.uv_strerror(init_recv_status)});
        uv.uv_close(@ptrCast(socket), onSocketClose);
        return;
    }

    const accept_status = uv.uv_accept(server, @ptrCast(socket));
    if (accept_status != 0) {
        std.log.err("Failed to accept login socket: {s}", .{uv.uv_strerror(accept_status)});
        uv.uv_close(@ptrCast(socket), onSocketClose);
        return;
    }

    const cli = login_client_pool.create() catch oomPanic();
    socket.*.data = cli;
    cli.* = .{ .read_arena = .init(allocator), .socket = socket };

    const read_init_status = uv.uv_read_start(@ptrCast(socket), LoginClient.allocBuffer, LoginClient.readCallback);
    if (read_init_status != 0) {
        std.log.err("Failed to initialize reading on login socket: {s}", .{uv.uv_strerror(read_init_status)});
        cli.shutdown();
        return;
    }
}

fn onSocketClose(handle: [*c]uv.uv_handle_t) callconv(.C) void {
    socket_pool.destroy(@ptrCast(@alignCast(handle)));
}

pub fn getIp(addr: std.net.Address) ![]const u8 {
    var ip_buf: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&ip_buf);
    switch (addr.any.family) {
        std.posix.AF.INET => {
            const bytes = @as(*const [4]u8, @ptrCast(&addr.in.sa.addr));
            try std.fmt.format(stream.writer(), "{}.{}.{}.{}", .{ bytes[0], bytes[1], bytes[2], bytes[3] });
        },
        std.posix.AF.INET6 => {
            if (std.mem.eql(u8, addr.in6.sa.addr[0..12], &.{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff })) {
                try std.fmt.format(stream.writer(), "[::ffff:{}.{}.{}.{}]", .{
                    addr.in6.sa.addr[12],
                    addr.in6.sa.addr[13],
                    addr.in6.sa.addr[14],
                    addr.in6.sa.addr[15],
                });
                return stream.getWritten();
            }
            const big_endian_parts = @as(*align(1) const [8]u16, @ptrCast(&addr.in6.sa.addr));
            const native_endian_parts = switch (builtin.target.cpu.arch.endian()) {
                .big => big_endian_parts.*,
                .little => blk: {
                    var buf: [8]u16 = undefined;
                    for (big_endian_parts, 0..) |part, i| buf[i] = std.mem.bigToNative(u16, part);
                    break :blk buf;
                },
            };
            try stream.writer().writeAll("[");
            var i: usize = 0;
            var abbrv = false;
            while (i < native_endian_parts.len) : (i += 1) {
                if (native_endian_parts[i] == 0) {
                    if (!abbrv) {
                        try stream.writer().writeAll(if (i == 0) "::" else ":");
                        abbrv = true;
                    }
                    continue;
                }
                try std.fmt.format(stream.writer(), "{x}", .{native_endian_parts[i]});
                if (i != native_endian_parts.len - 1) try stream.writer().writeAll(":");
            }
            try std.fmt.format(stream.writer(), "]", .{});
        },
        else => @panic("Invalid IP family"),
    }
    return stream.getWritten();
}
