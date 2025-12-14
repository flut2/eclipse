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

fn PacketData(comptime tag: std.meta.Tag(network_data.S2CPacketLogin)) type {
    return @FieldType(network_data.S2CPacketLogin, @tagName(tag));
}

fn handlerFn(comptime tag: std.meta.Tag(network_data.S2CPacketLogin)) fn (*Server, PacketData(tag)) void {
    return switch (tag) {
        .login_response => handleLoginResponse,
        .register_response => handleRegisterResponse,
        .verify_response => handleVerifyResponse,
        .delete_response => handleDeleteResponse,
        .@"error" => handleError,
    };
}

fn logRead(comptime _: std.meta.Tag(network_data.S2CPacketLogin)) bool {
    return build_options.log_packets == .all or
        build_options.log_packets == .s2c or
        build_options.log_packets == .s2c_non_tick or
        build_options.log_packets == .all_non_tick or
        build_options.log_packets == .s2c_tick or
        build_options.log_packets == .all_tick;
}

fn logWrite(comptime _: std.meta.Tag(network_data.C2SPacketLogin)) bool {
    return build_options.log_packets == .all or
        build_options.log_packets == .c2s or
        build_options.log_packets == .c2s_non_tick or
        build_options.log_packets == .all_non_tick or
        build_options.log_packets == .c2s_tick or
        build_options.log_packets == .all_tick;
}

pub fn allocBuffer(_: [*c]uv.uv_handle_t, _: usize, buf: [*c]uv.uv_buf_t) callconv(.c) void {
    buf.* = .{ .base = @ptrCast(main.login_reader.buffer.ptr), .len = main.login_buffer_size };
}

pub fn init(self: *Server) !void {
    self.connect(build_options.login_server_ip, build_options.login_server_port) catch |e| {
        std.log.err("Login connection failed: {}", .{e});
        return;
    };
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

fn closeCallback(socket: [*c]uv.uv_handle_t) callconv(.c) void {
    const server: *Server = @ptrCast(@alignCast(socket.*.data));
    main.disconnect();
    server.unsent_packets.clearAndFree(main.allocator);
    server.needs_verify = false;
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

    var con_handle = try main.allocator.create(uv.uv_connect_t);
    con_handle.data = self;
    const conn_status = uv.uv_tcp_connect(@ptrCast(con_handle), &self.socket, @ptrCast(&addr.in.sa), connectCallback);
    if (conn_status != 0) {
        self.needs_verify = false;
        self.unsent_packets.clearAndFree(main.allocator);
        std.log.err("Login connection error: {s}", .{uv.uv_strerror(conn_status)});
        return error.ConnectionFailed;
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

pub fn readCallback(ud: *anyopaque, bytes_read: isize, _: [*c]const uv.uv_buf_t) callconv(.c) void {
    if (bytes_read == 0) return;

    const socket: *uv.uv_stream_t = @ptrCast(@alignCast(ud));
    const server: *Server = @ptrCast(@alignCast(socket.data));

    if (bytes_read < 0) {
        server.shutdown();
        dialog.showDialog(.text, .{
            .title = "Connection Error",
            .body = "Login server closed the connection",
        });
        if (bytes_read != uv.UV_EOF)
            std.log.err("Login read error: {s}", .{uv.uv_err_name(@intCast(bytes_read))});
        return;
    }

    if (!shared.uv.socketRead(
        network_data.S2CPacketLogin,
        "S2C login packet",
        server,
        bytes_read,
        &main.login_reader,
        handlerFn,
        logRead,
    )) {
        server.shutdown();
        dialog.showDialog(.text, .{
            .title = "Connection Error",
            .body = "Login server closed the connection",
        });
        return;
    }
}

pub fn sendPacket(self: *Server, packet: network_data.C2SPacketLogin) void {
    if (!self.initialized) {
        self.unsent_packets.append(main.allocator, packet) catch main.oomPanic();
        self.connect(build_options.login_server_ip, build_options.login_server_port) catch return;
        return;
    }

    const write_status = shared.uv.socketWrite(
        network_data.C2SPacketLogin,
        "C2S login packet",
        packet,
        &main.login_writer,
        &self.socket,
        logWrite,
    );
    if (write_status < 0) {
        std.log.err("Login write send error: {s}", .{uv.uv_strerror(write_status)});
        self.shutdown();
        dialog.showDialog(.text, .{
            .title = "Connection Error",
            .body = "Login socket writing failed",
        });
        return;
    }
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
