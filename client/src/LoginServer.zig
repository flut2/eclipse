const std = @import("std");

const build_options = @import("options");
const shared = @import("shared");
const utils = shared.utils;
const game_data = shared.game_data;
const network_data = shared.network_data;
const uv = shared.uv;

const assets = @import("assets.zig");
const map = @import("game/map.zig");
const particles = @import("game/particles.zig");
const main = @import("main.zig");
const dialog = @import("ui/dialogs/dialog.zig");
const ui_systems = @import("ui/systems.zig");

const Server = @This();

const WriteRequest = extern struct {
    request: uv.uv_write_t = .{},
    buffer: uv.uv_buf_t = .{},
};

socket: *uv.uv_tcp_t = undefined,
read_arena: std.heap.ArenaAllocator = undefined,
unsent_packets: std.fifo.LinearFifo(network_data.C2SPacketLogin, .Dynamic) = undefined,
initialized: bool = false,
needs_verify: bool = false,

fn PacketData(comptime tag: @typeInfo(network_data.S2CPacketLogin).@"union".tag_type.?) type {
    return @typeInfo(network_data.S2CPacketLogin).@"union".fields[@intFromEnum(tag)].type;
}

fn handlerFn(comptime tag: @typeInfo(network_data.S2CPacketLogin).@"union".tag_type.?) fn (*Server, PacketData(tag)) void {
    return switch (tag) {
        .login_response => handleLoginResponse,
        .register_response => handleRegisterResponse,
        .verify_response => handleVerifyResponse,
        .delete_response => handleDeleteResponse,
        .@"error" => handleError,
    };
}

pub fn allocBuffer(_: [*c]uv.uv_handle_t, suggested_size: usize, buf: [*c]uv.uv_buf_t) callconv(.C) void {
    buf.* = .{
        .base = @ptrCast(main.allocator.alloc(u8, suggested_size) catch main.oomPanic()),
        .len = @intCast(suggested_size),
    };
}

fn writeCallback(ud: [*c]uv.uv_write_t, status: c_int) callconv(.C) void {
    const wr: *WriteRequest = @ptrCast(@alignCast(ud));
    const server: *Server = @ptrCast(@alignCast(wr.request.data));
    main.allocator.free(wr.buffer.base[0..wr.buffer.len]);
    main.allocator.destroy(wr);

    if (status != 0) {
        std.log.err("Login write error: {s}", .{uv.uv_strerror(status)});
        server.shutdown();
        dialog.showDialog(.text, .{
            .title = "Connection Error",
            .body = "Login socket writing was interrupted",
        });
        return;
    }
}

pub fn readCallback(ud: *anyopaque, bytes_read: isize, buf: [*c]const uv.uv_buf_t) callconv(.C) void {
    const socket: *uv.uv_stream_t = @ptrCast(@alignCast(ud));
    const server: *Server = @ptrCast(@alignCast(socket.data));
    defer _ = server.read_arena.reset(.{ .retain_with_limit = 1024 });
    const allocator = server.read_arena.allocator();

    if (bytes_read > 0) {
        var reader: utils.PacketReader = .{ .buffer = buf.*.base[0..@intCast(bytes_read)] };

        while (reader.index <= bytes_read - 3) {
            const len = reader.read(u16, allocator);
            if (len > bytes_read - reader.index) return;

            const next_packet_idx = reader.index + len;
            const EnumType = @typeInfo(network_data.S2CPacketLogin).@"union".tag_type.?;
            const byte_id = reader.read(std.meta.Int(.unsigned, @bitSizeOf(EnumType)), allocator);
            const packet_id = std.meta.intToEnum(EnumType, byte_id) catch |e| {
                std.log.err("Error parsing S2CPacketLogin ({}): id={}, size={}, len={}", .{ e, byte_id, bytes_read, len });
                return;
            };

            switch (packet_id) {
                inline else => |id| handlerFn(id)(server, reader.read(PacketData(id), allocator)),
            }

            if (reader.index < next_packet_idx) {
                std.log.err("S2C login packet {} has {} bytes left over", .{ packet_id, next_packet_idx - reader.index });
                reader.index = next_packet_idx;
            }
        }
    } else if (bytes_read < 0) {
        std.log.err("Login read error: {s}", .{uv.uv_err_name(@intCast(bytes_read))});
        server.shutdown();
        dialog.showDialog(.text, .{
            .title = "Connection Error",
            .body = "Login server closed the connection",
        });
    }

    if (buf.*.base != null) main.allocator.free(buf.*.base[0..@intCast(buf.*.len)]);
}

fn connectCallback(conn: [*c]uv.uv_connect_t, status: c_int) callconv(.C) void {
    const server: *Server = @ptrCast(@alignCast(conn.*.data));
    defer main.allocator.destroy(@as(*uv.uv_connect_t, @ptrCast(conn)));

    if (status != 0) {
        std.log.err("Login connection callback error: {s}", .{uv.uv_strerror(status)});
        main.disconnect(false);
        server.shutdown();
        dialog.showDialog(.text, .{
            .title = "Connection Error",
            .body = "Connection failed to login server",
        });
        return;
    }

    const read_status = uv.uv_read_start(@ptrCast(server.socket), allocBuffer, readCallback);
    if (read_status != 0) {
        std.log.err("Login read init error: {s}", .{uv.uv_strerror(read_status)});
        server.shutdown();
        dialog.showDialog(.text, .{
            .title = "Connection Error",
            .body = "Login server inaccessible",
        });
        return;
    }

    server.initialized = true;
    if (server.needs_verify) {
        if (main.current_account) |acc| {
            server.sendPacket(.{ .verify = .{ .email = acc.email, .token = acc.token } });
        } else {
            ui_systems.ui_lock.lock();
            defer ui_systems.ui_lock.unlock();
            ui_systems.switchScreen(.main_menu);
        }
        server.needs_verify = false;
    }

    while (server.unsent_packets.readItem()) |packet| server.sendPacket(packet);
}

fn shutdownCallback(handle: [*c]uv.uv_async_t) callconv(.C) void {
    const server: *Server = @ptrCast(@alignCast(handle.*.data));
    server.shutdown();
    dialog.showDialog(.none, {});
}

pub fn init(self: *Server) !void {
    self.socket = try main.allocator.create(uv.uv_tcp_t);
    self.read_arena = .init(main.allocator);
    self.unsent_packets = .init(main.allocator);
    self.connect(build_options.login_server_ip, build_options.login_server_port) catch |e| {
        std.log.err("Login connection failed: {}", .{e});
        return;
    };
}

pub fn deinit(self: *Server) void {
    main.disconnect(false);
    main.allocator.destroy(self.socket);
    self.read_arena.deinit();
    self.unsent_packets.deinit();
    self.initialized = false;
}

pub fn sendPacket(self: *Server, packet: network_data.C2SPacketLogin) void {
    if (!self.initialized) {
        self.unsent_packets.writeItem(packet) catch main.oomPanic();
        self.connect(build_options.login_server_ip, build_options.login_server_port) catch return;
        return;
    }

    if (build_options.log_packets == .all or
        build_options.log_packets == .c2s or
        build_options.log_packets == .c2s_tick or
        build_options.log_packets == .all_tick or
        build_options.log_packets == .c2s_non_tick or
        build_options.log_packets == .all_non_tick)
        std.log.info("Send: {}", .{packet}); // TODO: custom formatting

    switch (packet) {
        inline else => |data| {
            var writer: utils.PacketWriter = .{};
            defer writer.list.deinit(main.allocator);
            writer.writeLength(main.allocator);
            writer.write(@intFromEnum(std.meta.activeTag(packet)), main.allocator);
            writer.write(data, main.allocator);
            writer.updateLength();

            const uv_buffer: uv.uv_buf_t = .{ .base = @ptrCast(writer.list.items.ptr), .len = @intCast(writer.list.items.len) };

            var write_status = uv.UV_EAGAIN;
            while (write_status == uv.UV_EAGAIN) write_status = uv.uv_try_write(@ptrCast(self.socket), @ptrCast(&uv_buffer), 1);
            if (write_status < 0) {
                std.log.err("Login write send error: {s}", .{uv.uv_strerror(write_status)});
                self.shutdown();
                dialog.showDialog(.text, .{
                    .title = "Connection Error",
                    .body = "Login socket writing failed",
                });
                return;
            }
        },
    }
}

pub fn connect(self: *Server, ip: []const u8, port: u16) !void {
    const addr = try std.net.Address.parseIp4(ip, port);

    self.socket.data = self;
    const tcp_status = uv.uv_tcp_init(@ptrCast(main.main_loop), @ptrCast(self.socket));
    if (tcp_status != 0) {
        self.needs_verify = false;
        self.unsent_packets.discard(self.unsent_packets.count);
        std.log.err("Login socket creation error: {s}", .{uv.uv_strerror(tcp_status)});
        return error.NoSocket;
    }

    var connect_data = try main.allocator.create(uv.uv_connect_t);
    connect_data.data = self;
    const conn_status = uv.uv_tcp_connect(@ptrCast(connect_data), @ptrCast(self.socket), @ptrCast(&addr.in.sa), connectCallback);
    if (conn_status != 0) {
        self.needs_verify = false;
        self.unsent_packets.discard(self.unsent_packets.count);
        std.log.err("Login connection error: {s}", .{uv.uv_strerror(conn_status)});
        return error.ConnectionFailed;
    }
}

pub fn shutdown(self: *Server) void {
    self.initialized = false;
    self.needs_verify = false;
    self.unsent_packets.discard(self.unsent_packets.count);

    {
        ui_systems.ui_lock.lock();
        defer ui_systems.ui_lock.unlock();
        ui_systems.switchScreen(.main_menu);
    }

    if (self.initialized and uv.uv_is_closing(@ptrCast(self.socket)) == 0) uv.uv_close(@ptrCast(self.socket), closeCallback);
}

fn closeCallback(_: [*c]uv.uv_handle_t) callconv(.C) void {}

fn logRead(comptime tick: enum { non_tick, tick }) bool {
    return if (tick == .non_tick)
        build_options.log_packets == .all or
            build_options.log_packets == .s2c or
            build_options.log_packets == .s2c_non_tick or
            build_options.log_packets == .all_non_tick
    else
        build_options.log_packets == .all or
            build_options.log_packets == .s2c or
            build_options.log_packets == .s2c_tick or
            build_options.log_packets == .all_tick;
}

fn deepCopyList(temp_list: network_data.CharacterListData) !network_data.CharacterListData {
    var ret = temp_list;
    ret.name = try main.account_arena_allocator.dupe(u8, temp_list.name);
    ret.characters = try main.account_arena_allocator.dupe(network_data.CharacterData, temp_list.characters);

    const servers = try main.account_arena_allocator.dupe(network_data.ServerData, temp_list.servers);
    for (servers, temp_list.servers) |*server, temp_server| {
        server.name = try main.account_arena_allocator.dupe(u8, temp_server.name);
        server.ip = try main.account_arena_allocator.dupe(u8, temp_server.ip);
    }
    ret.servers = servers;

    return ret;
}

fn handleLoginResponse(_: *Server, data: PacketData(.login_response)) void {
    if (logRead(.non_tick)) std.log.debug("Login Recv - LoginResponse: {}", .{data});

    main.character_list = deepCopyList(data) catch main.oomPanic();
    if (main.current_account) |*acc| acc.token = main.character_list.?.token;

    ui_systems.ui_lock.lock();
    defer ui_systems.ui_lock.unlock();
    if (main.character_list.?.characters.len > 0)
        ui_systems.switchScreen(.char_select)
    else
        ui_systems.switchScreen(.char_create);
}

fn handleRegisterResponse(_: *Server, data: PacketData(.register_response)) void {
    if (logRead(.non_tick)) std.log.debug("Login Recv - RegisterResponse: {}", .{data});

    main.character_list = deepCopyList(data) catch main.oomPanic();
    if (main.current_account) |*acc| acc.token = main.character_list.?.token;

    ui_systems.ui_lock.lock();
    defer ui_systems.ui_lock.unlock();
    if (main.character_list.?.characters.len > 0)
        ui_systems.switchScreen(.char_select)
    else
        ui_systems.switchScreen(.char_create);
}

fn handleVerifyResponse(_: *Server, data: PacketData(.verify_response)) void {
    if (logRead(.non_tick)) std.log.debug("Login Recv - VerifyResponse: {}", .{data});

    main.character_list = deepCopyList(data) catch main.oomPanic();
    if (main.character_list.?.characters.len == 0) return;
    if (main.skip_verify_loop) {
        main.skip_verify_loop = false;
        return;
    }

    {
        ui_systems.ui_lock.lock();
        defer ui_systems.ui_lock.unlock();
        ui_systems.switchScreen(.game);
    }

    if (main.settings.char_ids_login_sort.len > 0)
        for (main.character_list.?.characters) |char| if (char.char_id == main.settings.char_ids_login_sort[0]) {
            main.enterGame(main.character_list.?.servers[0], char.char_id, std.math.maxInt(u16));
            return;
        };

    main.enterGame(main.character_list.?.servers[0], main.character_list.?.characters[0].char_id, std.math.maxInt(u16));
}

fn handleDeleteResponse(_: *Server, data: PacketData(.delete_response)) void {
    if (logRead(.non_tick)) std.log.debug("Login Recv - DeleteResponse: {}", .{data});

    main.character_list = deepCopyList(data) catch main.oomPanic();
    if (ui_systems.screen == .char_select) {
        ui_systems.ui_lock.lock();
        defer ui_systems.ui_lock.unlock();
        ui_systems.screen.char_select.refresh() catch |e| {
            std.log.err("Character select refresh failed post-deletion: {}", .{e});
            return;
        };
    }
}

fn handleError(_: *Server, data: PacketData(.@"error")) void {
    if (logRead(.non_tick)) std.log.debug("Login Recv - Error: {}", .{data});

    main.skip_verify_loop = false;
    {
        ui_systems.ui_lock.lock();
        defer ui_systems.ui_lock.unlock();
        ui_systems.switchScreen(.main_menu);
    }
    dialog.showDialog(.text, .{
        .title = "Connection Error",
        .body = main.allocator.dupe(u8, data.description) catch "",
        .dispose_body = true,
    });
}
