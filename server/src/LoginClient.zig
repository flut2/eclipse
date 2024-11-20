const std = @import("std");
const shared = @import("shared");
const utils = shared.utils;
const game_data = shared.game_data;
const network_data = shared.network_data;
const uv = shared.uv;
const main = @import("main.zig");
const builtin = @import("builtin");
const db = @import("db.zig");

const Client = @This();

const WriteRequest = extern struct {
    request: uv.uv_write_t = .{},
    buffer: uv.uv_buf_t = .{},
};

socket: *uv.uv_tcp_t = undefined,
arena: std.heap.ArenaAllocator = undefined,
needs_shutdown: bool = false,

fn PacketData(comptime tag: @typeInfo(network_data.C2SPacketLogin).@"union".tag_type.?) type {
    return @typeInfo(network_data.C2SPacketLogin).@"union".fields[@intFromEnum(tag)].type;
}

fn handlerFn(comptime tag: @typeInfo(network_data.C2SPacketLogin).@"union".tag_type.?) fn (*Client, PacketData(tag)) void {
    return switch (tag) {
        .login => handleLogin,
        .register => handleRegister,
        .verify => handleVerify,
    };
}

pub fn allocBuffer(socket: [*c]uv.uv_handle_t, suggested_size: usize, buf: [*c]uv.uv_buf_t) callconv(.C) void {
    const client: *Client = @ptrCast(@alignCast(socket.*.data));
    buf.*.base = @ptrCast(client.arena.allocator().alloc(u8, suggested_size) catch {
        client.sameThreadShutdown(); // no failure, if we can't alloc it wouldn't go through anyway
        return;
    });
    buf.*.len = @intCast(suggested_size);
}

fn closeCallback(socket: [*c]uv.uv_handle_t) callconv(.C) void {
    const client: *Client = @ptrCast(@alignCast(socket.*.data));
    main.socket_pool.destroy(client.socket);
    client.arena.deinit();
    main.login_client_pool.destroy(client);
}

fn writeCallback(ud: [*c]uv.uv_write_t, status: c_int) callconv(.C) void {
    const wr: *WriteRequest = @ptrCast(ud);
    const client: *Client = @ptrCast(@alignCast(wr.request.data));

    if (status != 0) {
        client.queuePacket(.{ .@"error" = .{ .description = "Socket write error" } });
        return;
    }

    const arena_allocator = client.arena.allocator();
    arena_allocator.free(wr.buffer.base[0..wr.buffer.len]);
    arena_allocator.destroy(wr);
}

pub fn readCallback(ud: *anyopaque, bytes_read: isize, buf: [*c]const uv.uv_buf_t) callconv(.C) void {
    const socket: *uv.uv_stream_t = @ptrCast(@alignCast(ud));
    const client: *Client = @ptrCast(@alignCast(socket.data));
    const arena_allocator = client.arena.allocator();
    var child_arena = std.heap.ArenaAllocator.init(arena_allocator);
    defer child_arena.deinit();
    const child_arena_allocator = child_arena.allocator();

    if (bytes_read > 0) {
        var reader: utils.PacketReader = .{ .buffer = buf.*.base[0..@intCast(bytes_read)] };

        while (reader.index <= bytes_read - 3) {
            defer _ = child_arena.reset(.retain_capacity);

            const len = reader.read(u16, child_arena_allocator);
            if (len > bytes_read - reader.index)
                return;

            const next_packet_idx = reader.index + len;
            const EnumType = @typeInfo(network_data.C2SPacketLogin).@"union".tag_type.?;
            const byte_id = reader.read(std.meta.Int(.unsigned, @bitSizeOf(EnumType)), child_arena_allocator);
            const packet_id = std.meta.intToEnum(EnumType, byte_id) catch |e| {
                std.log.err("Error parsing C2SPacketLogin ({}): id={}, size={}, len={}", .{ e, byte_id, bytes_read, len });
                client.queuePacket(.{ .@"error" = .{ .description = "Socket read error" } });
                return;
            };

            switch (packet_id) {
                inline else => |id| handlerFn(id)(client, reader.read(PacketData(id), child_arena_allocator)),
            }

            if (reader.index < next_packet_idx) {
                std.log.err("C2S login packet {} has {} bytes left over", .{ packet_id, next_packet_idx - reader.index });
                reader.index = next_packet_idx;
            }
        }
    } else if (bytes_read < 0) {
        if (bytes_read != uv.UV_EOF) {
            client.queuePacket(.{ .@"error" = .{ .description = "Socket read error" } });
        } else client.sameThreadShutdown();
        return;
    }

    arena_allocator.free(buf.*.base[0..@intCast(buf.*.len)]);
}

fn asyncCloseCallback(_: [*c]uv.uv_handle_t) callconv(.C) void {}

pub fn shutdownCallback(handle: [*c]uv.uv_async_t) callconv(.C) void {
    const client: *Client = @ptrCast(@alignCast(handle.*.data));
    client.sameThreadShutdown();
}

pub fn sameThreadShutdown(self: *Client) void {
    if (uv.uv_is_closing(@ptrCast(self.socket)) == 0) uv.uv_close(@ptrCast(self.socket), closeCallback);
}

pub fn queuePacket(self: *Client, packet: network_data.S2CPacketLogin) void {
    switch (packet) {
        inline else => |data| {
            const arena_allocator = self.arena.allocator();

            var writer: utils.PacketWriter = .{};
            writer.writeLength(arena_allocator);
            writer.write(@intFromEnum(std.meta.activeTag(packet)), arena_allocator);
            writer.write(data, arena_allocator);
            writer.updateLength();

            const wr: *WriteRequest = arena_allocator.create(WriteRequest) catch main.oomPanic();
            wr.buffer.base = @ptrCast(writer.list.items);
            wr.buffer.len = @intCast(writer.list.items.len);
            wr.request.data = @ptrCast(self);
            const write_status = uv.uv_write(@ptrCast(wr), @ptrCast(self.socket), @ptrCast(&wr.buffer), 1, writeCallback);
            if (write_status != 0) {
                self.sameThreadShutdown();
                return;
            }
        },
    }
}

pub fn sendError(self: *Client, message: []const u8) void {
    self.queuePacket(.{ .@"error" = .{ .description = message } });
}

fn databaseError(self: *Client) void {
    self.sendError("Database error");
}

fn getListData(self: *Client, acc_id: u32, token: u128) !network_data.CharacterListData {
    var acc_data: db.AccountData = .{ .acc_id = acc_id };
    defer acc_data.deinit();

    if (try db.accountBanned(&acc_data)) {
        self.sendError("Account banned");
        return error.AccountBanned;
    }

    var char_list: std.ArrayListUnmanaged(network_data.CharacterData) = .empty;
    defer char_list.deinit(main.allocator);
    buildList: {
        for (acc_data.get(.alive_char_ids) catch break :buildList) |char_id| {
            var char_data: db.CharacterData = .{ .acc_id = acc_id, .char_id = char_id };
            defer char_data.deinit();

            const stats = try char_data.get(.stats);
            try char_list.append(main.allocator, .{
                .char_id = char_id,
                .class_id = try char_data.get(.class_id),
                .health = stats[0],
                .mana = stats[1],
                .attack = stats[2],
                .defense = stats[3],
                .speed = stats[4],
                .dexterity = stats[5],
                .vitality = stats[6],
                .wisdom = stats[7],
                .items = &try char_data.get(.items),
            });
        }
    }

    return .{
        .name = try main.allocator.dupe(u8, try acc_data.get(.name)),
        .token = token,
        .rank = try acc_data.get(.rank),
        .next_char_id = try acc_data.get(.next_char_id),
        .max_chars = try acc_data.get(.max_char_slots),
        .characters = try main.allocator.dupe(network_data.CharacterData, char_list.items),
        .servers = try main.allocator.dupe(network_data.ServerData, &.{.{
            .name = main.settings.server_name,
            .ip = main.settings.public_ip,
            .port = main.settings.game_port,
            .max_players = 500,
            .admin_only = false,
        }}), // TODO: multi-server support
    };
}

fn disposeList(list: network_data.CharacterListData) void {
    main.allocator.free(list.name);
    main.allocator.free(list.characters);
    main.allocator.free(list.servers);
}

fn handleLogin(self: *Client, data: PacketData(.login)) void {
    var login_data: db.LoginData = .{ .email = data.email };
    defer login_data.deinit();
    const hashed_pw = login_data.get(.hashed_password) catch |e| {
        self.sendError(if (e == error.NoData)
            "Invalid email"
        else
            "Unknown error");
        return;
    };
    std.crypto.pwhash.scrypt.strVerify(hashed_pw, data.password, .{ .allocator = main.allocator }) catch |e| {
        self.sendError(if (e == std.crypto.pwhash.HasherError.PasswordVerificationFailed)
            "Invalid credentials"
        else
            "Unknown error");
        return;
    };
    const acc_id = login_data.get(.account_id) catch {
        self.databaseError();
        return;
    };
    const token = db.csprng.random().int(u128);
    login_data.set(.{ .token = token }) catch {
        self.databaseError();
        return;
    };
    const list = self.getListData(acc_id, token) catch {
        self.sendError("Could not retrieve list");
        return;
    };
    defer disposeList(list);
    self.queuePacket(.{ .login_response = list });
}

fn handleRegister(self: *Client, data: PacketData(.register)) void {
    var login_data: db.LoginData = .{ .email = data.email };
    defer login_data.deinit();

    email_exists: {
        _ = login_data.get(.account_id) catch |e| if (e == error.NoData) break :email_exists;
        self.sendError("Email already exists");
        return;
    }

    var names: db.Names = .{};
    defer names.deinit();

    name_exists: {
        _ = names.get(data.name) catch |e| if (e == error.NoData) break :name_exists;
        self.sendError("Name already exists");
        return;
    }

    const acc_id = db.nextAccId() catch {
        self.sendError("Database failure");
        return;
    };
    login_data.set(.{ .account_id = acc_id }) catch {
        self.databaseError();
        return;
    };
    names.set(data.name, acc_id) catch {
        self.databaseError();
        return;
    };

    var out: [256]u8 = undefined;
    const scrypt = std.crypto.pwhash.scrypt;
    const hashed_pass = scrypt.strHash(data.password, .{
        .allocator = main.allocator,
        .params = scrypt.Params.interactive,
        .encoding = .crypt,
    }, &out) catch {
        self.sendError("Password hashing failed");
        return;
    };
    login_data.set(.{ .hashed_password = hashed_pass }) catch {
        self.databaseError();
        return;
    };
    const token = db.csprng.random().int(u128);
    login_data.set(.{ .token = token }) catch {
        self.databaseError();
        return;
    };

    var acc_data: db.AccountData = .{ .acc_id = acc_id };
    defer acc_data.deinit();

    const timestamp = std.time.milliTimestamp();

    acc_data.set(.{ .email = data.email }) catch {
        self.databaseError();
        return;
    };
    acc_data.set(.{ .name = data.name }) catch {
        self.databaseError();
        return;
    };
    acc_data.set(.{ .hwid = data.hwid }) catch {
        self.databaseError();
        return;
    };
    acc_data.set(.{ .register_timestamp = timestamp }) catch {
        self.databaseError();
        return;
    };
    acc_data.set(.{ .last_login_timestamp = timestamp }) catch {
        self.databaseError();
        return;
    };
    acc_data.set(.{ .mute_expiry = 0 }) catch {
        self.databaseError();
        return;
    };
    acc_data.set(.{ .ban_expiry = 0 }) catch {
        self.databaseError();
        return;
    };
    acc_data.set(.{ .gold = 0 }) catch {
        self.databaseError();
        return;
    };
    acc_data.set(.{ .gems = 0 }) catch {
        self.databaseError();
        return;
    };
    acc_data.set(.{ .crowns = 0 }) catch {
        self.databaseError();
        return;
    };
    acc_data.set(.{ .rank = if (acc_id == 0) .admin else .default }) catch {
        self.databaseError();
        return;
    };
    acc_data.set(.{ .next_char_id = 0 }) catch {
        self.databaseError();
        return;
    };
    acc_data.set(.{ .alive_char_ids = &[0]u32{} }) catch {
        self.databaseError();
        return;
    };
    acc_data.set(.{ .max_char_slots = 2 }) catch {
        self.databaseError();
        return;
    };

    const list: network_data.CharacterListData = .{
        .name = acc_data.get(.name) catch {
            self.databaseError();
            return;
        },
        .token = token,
        .rank = acc_data.get(.rank) catch {
            self.databaseError();
            return;
        },
        .next_char_id = acc_data.get(.next_char_id) catch {
            self.databaseError();
            return;
        },
        .max_chars = acc_data.get(.max_char_slots) catch {
            self.databaseError();
            return;
        },
        .characters = &.{},
        .servers = &.{.{
            .name = main.settings.server_name,
            .ip = main.settings.public_ip,
            .port = main.settings.game_port,
            .max_players = 500,
            .admin_only = false,
        }}, // TODO: multi-server support
    };
    defer disposeList(list);
    self.queuePacket(.{ .register_response = list });
}

fn handleVerify(self: *Client, data: PacketData(.verify)) void {
    const acc_id = db.login(data.email, data.token) catch |e| {
        self.sendError(switch (e) {
            error.NoData => "Invalid email",
            error.InvalidToken => "Invalid token",
            else => "Unknown error",
        });
        return;
    };
    const list = self.getListData(acc_id, data.token) catch {
        self.sendError("Could not retrieve list");
        return;
    };
    defer disposeList(list);
    self.queuePacket(.{ .verify_response = list });
}
