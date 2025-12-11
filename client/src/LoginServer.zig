const std = @import("std");

const build_options = @import("options");
const shared = @import("shared");
const utils = shared.utils;
const game_data = shared.game_data;
const network_data = shared.network_data;
const uv = @import("uv");

const assets = @import("assets.zig");
const map = @import("game/map.zig");
const particles = @import("game/particles.zig");
const main = @import("main.zig");
const dialog = @import("ui/dialogs/dialog.zig");
const ui_systems = @import("ui/systems.zig");

const Server = @This();

socket: uv.uv_tcp_t = .{},
unsent_packets: std.ArrayList(network_data.C2SPacketLogin),
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

pub fn allocBuffer(_: [*c]uv.uv_handle_t, _: usize, buf: [*c]uv.uv_buf_t) callconv(.c) void {
    if (main.login_buffer_free_list.items.len > 0) {
        const free_buf = main.login_buffer_free_list.pop() orelse unreachable;
        buf.* = .{ .base = free_buf.ptr, .len = main.login_buffer_size };
        return;
    }

    const start_idx = main.login_buffers.items.len;
    main.login_buffers.appendNTimes(main.allocator, 0, main.login_buffer_size) catch main.oomPanic();
    buf.* = .{ .base = &main.login_buffers.items[start_idx], .len = main.login_buffer_size };
}

pub fn readCallback(ud: *anyopaque, bytes_read: isize, buf: [*c]const uv.uv_buf_t) callconv(.c) void {
    const socket: *uv.uv_stream_t = @ptrCast(@alignCast(ud));
    const server: *Server = @ptrCast(@alignCast(socket.data));

    defer if (buf.*.base != null) main.login_buffer_free_list.append(main.allocator, buf.*.base[0..main.login_buffer_size]) catch main.oomPanic();

    if (bytes_read > 0) {
        const reader = &main.login_reader;
        reader.reset(buf.*.base[0..@intCast(bytes_read)]);

        while (reader.index <= bytes_read - 3) {
            const len = reader.read(u16);
            if (len > bytes_read - reader.index) return;

            const next_packet_idx = reader.index + len;
            const EnumType = @typeInfo(network_data.S2CPacketLogin).@"union".tag_type.?;
            const byte_id = reader.read(std.meta.Int(.unsigned, @bitSizeOf(EnumType)));
            const packet_id = std.meta.intToEnum(EnumType, byte_id) catch |e| {
                std.log.err("Error parsing S2CPacketLogin ({}): id={}, size={}, len={}", .{ e, byte_id, bytes_read, len });
                return;
            };

            switch (packet_id) {
                inline else => |id| {
                    const packet = reader.read(PacketData(id));
                    if (comptime logRead())
                        std.log.info(
                            "Receiving login packet: {f}",
                            .{@unionInit(network_data.S2CPacketLogin, @tagName(id), packet)},
                        );
                    handlerFn(id)(server, packet);
                },
            }

            if (reader.index < next_packet_idx) {
                std.log.err("S2C login packet {} has {} bytes left over", .{ packet_id, next_packet_idx - reader.index });
                reader.index = next_packet_idx;
            }
        }
    } else if (bytes_read < 0) {
        if (bytes_read == uv.UV_EOF) return;
        std.log.err("Login read error: {s}", .{uv.uv_err_name(@intCast(bytes_read))});
        server.shutdown();
        dialog.showDialog(.text, .{
            .title = "Connection Error",
            .body = "Login server closed the connection",
        });
    }
}

fn connectCallback(conn: [*c]uv.uv_connect_t, status: c_int) callconv(.c) void {
    const server: *Server = @ptrCast(@alignCast(conn.*.data));
    defer main.allocator.destroy(@as(*uv.uv_connect_t, @ptrCast(conn)));

    if (status != 0) {
        std.log.err("Login connection callback error: {s}", .{uv.uv_strerror(status)});
        server.shutdown();
        dialog.showDialog(.text, .{
            .title = "Connection Error",
            .body = "Connection failed to login server",
        });
        return;
    }

    const read_status = uv.uv_read_start(@ptrCast(&server.socket), allocBuffer, readCallback);
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
        if (main.current_account) |acc|
            server.sendPacket(.{ .verify = .{ .email = acc.email, .token = acc.token } })
        else
            ui_systems.switchScreen(.main_menu);

        server.needs_verify = false;
    }

    for (server.unsent_packets.items) |packet| server.sendPacket(packet);
}

fn shutdownCallback(handle: [*c]uv.uv_async_t) callconv(.c) void {
    const server: *Server = @ptrCast(@alignCast(handle.*.data));
    server.shutdown();
    dialog.showDialog(.none, {});
}

pub fn init(self: *Server) !void {
    self.connect(build_options.login_server_ip, build_options.login_server_port) catch |e| {
        std.log.err("Login connection failed: {}", .{e});
        return;
    };
}

pub fn sendPacket(self: *Server, packet: network_data.C2SPacketLogin) void {
    if (!self.initialized) {
        self.unsent_packets.append(main.allocator, packet) catch main.oomPanic();
        self.connect(build_options.login_server_ip, build_options.login_server_port) catch return;
        return;
    }

    if (comptime logWrite())
        std.log.info("Sending login packet: {f}", .{packet});

    switch (packet) {
        inline else => |data| {
            const writer = &main.login_writer;
            writer.list.clearRetainingCapacity();
            writer.writeLength();
            writer.write(@intFromEnum(std.meta.activeTag(packet)));
            writer.write(data);
            writer.updateLength();

            const uv_buffer: uv.uv_buf_t = .{ .base = @ptrCast(writer.list.items.ptr), .len = @intCast(writer.list.items.len) };
            var write_status = uv.UV_EAGAIN;
            while (write_status == uv.UV_EAGAIN or write_status > 0 and write_status < writer.list.items.len)
                write_status = uv.uv_try_write(@ptrCast(&self.socket), @ptrCast(&uv_buffer), 1);

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
    const addr: std.net.Address = try .parseIp4(ip, port);

    const tcp_status = uv.uv_tcp_init(&main.main_loop, &self.socket);
    if (tcp_status != 0) {
        self.needs_verify = false;
        self.unsent_packets.clearAndFree(main.allocator);
        std.log.err("Login socket creation error: {s}", .{uv.uv_strerror(tcp_status)});
        return error.NoSocket;
    }
    self.socket.data = self;

    const disable_nagle_status = uv.uv_tcp_nodelay(&self.socket, 1);
    if (disable_nagle_status != 0)
        std.log.err("Disabling Nagle on socket failed: {s}", .{uv.uv_strerror(disable_nagle_status)});

    var connect_data = try main.allocator.create(uv.uv_connect_t);
    connect_data.data = self;
    const conn_status = uv.uv_tcp_connect(@ptrCast(connect_data), &self.socket, @ptrCast(&addr.in.sa), connectCallback);
    if (conn_status != 0) {
        self.needs_verify = false;
        self.unsent_packets.clearAndFree(main.allocator);
        std.log.err("Login connection error: {s}", .{uv.uv_strerror(conn_status)});
        return error.ConnectionFailed;
    }
}

pub fn shutdown(self: *Server) void {
    if (!self.initialized) {
        closeCallback(@ptrCast(&self.socket));
        return;
    }
    self.initialized = false;

    const close_status = uv.uv_tcp_close_reset(&self.socket, closeCallback);
    if (close_status != 0) std.log.err("Libuv socket close error: {s}", .{uv.uv_strerror(close_status)});
}

fn closeCallback(ud: [*c]uv.uv_handle_t) callconv(.c) void {
    const server: *Server = @ptrCast(@alignCast(ud.*.data));
    main.disconnect();
    server.unsent_packets.clearAndFree(main.allocator);
    server.needs_verify = false;
}

fn logRead() bool {
    return build_options.log_packets == .all or
        build_options.log_packets == .s2c or
        build_options.log_packets == .s2c_non_tick or
        build_options.log_packets == .all_non_tick or
        build_options.log_packets == .s2c_tick or
        build_options.log_packets == .all_tick;
}

fn logWrite() bool {
    return build_options.log_packets == .all or
        build_options.log_packets == .c2s or
        build_options.log_packets == .c2s_non_tick or
        build_options.log_packets == .all_non_tick or
        build_options.log_packets == .c2s_tick or
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
    main.character_list = deepCopyList(data) catch main.oomPanic();
    if (main.current_account) |*acc| acc.token = main.character_list.?.token;

    ui_systems.switchScreen(.char_select);
}

fn handleRegisterResponse(_: *Server, data: PacketData(.register_response)) void {
    main.character_list = deepCopyList(data) catch main.oomPanic();
    if (main.current_account) |*acc| acc.token = main.character_list.?.token;

    ui_systems.switchScreen(.char_select);
}

fn handleVerifyResponse(_: *Server, data: PacketData(.verify_response)) void {
    main.character_list = deepCopyList(data) catch main.oomPanic();
    if (main.character_list.?.characters.len == 0) return;
    if (main.skip_verify_loop) {
        main.skip_verify_loop = false;
        return;
    }

    ui_systems.switchScreen(.game);

    if (main.settings.char_ids_login_sort.len > 0)
        for (main.character_list.?.characters) |char| if (char.char_id == main.settings.char_ids_login_sort[0]) {
            main.enterGame(main.character_list.?.servers[0], char.char_id, std.math.maxInt(u16));
            return;
        };

    main.enterGame(main.character_list.?.servers[0], main.character_list.?.characters[0].char_id, std.math.maxInt(u16));
}

fn handleDeleteResponse(_: *Server, data: PacketData(.delete_response)) void {
    main.character_list = deepCopyList(data) catch main.oomPanic();
    if (ui_systems.screen == .char_select)
        ui_systems.screen.char_select.refresh() catch |e| {
            std.log.err("Character select refresh failed post-deletion: {}", .{e});
            return;
        };
}

fn handleError(_: *Server, data: PacketData(.@"error")) void {
    main.skip_verify_loop = false;
    ui_systems.switchScreen(.main_menu);

    dialog.showDialog(.text, .{
        .title = "Connection Error",
        .body = main.allocator.dupe(u8, data.description) catch "",
        .dispose_body = true,
    });
}
