const std = @import("std");
const builtin = @import("builtin");

const build_options = @import("options");
const shared = @import("shared");
const utils = shared.utils;
const game_data = shared.game_data;
const network_data = shared.network_data;
const uv = @import("uv");

const db = @import("db.zig");
const main = @import("main.zig");

const Client = @This();

socket: uv.uv_tcp_t = .{},
list_index: usize = std.math.maxInt(usize),
initialized: bool = false,

fn PacketData(comptime tag: std.meta.Tag(network_data.C2SPacketLogin)) type {
    return @FieldType(network_data.C2SPacketLogin, @tagName(tag));
}

fn handlerFn(comptime tag: std.meta.Tag(network_data.C2SPacketLogin)) fn (*Client, PacketData(tag)) void {
    return switch (tag) {
        .login => handleLogin,
        .register => handleRegister,
        .verify => handleVerify,
        .delete => handleDelete,
    };
}

fn logRead(comptime _: std.meta.Tag(network_data.C2SPacketLogin)) bool {
    return build_options.log_packets == .all or
        build_options.log_packets == .s2c or
        build_options.log_packets == .s2c_non_tick or
        build_options.log_packets == .all_non_tick or
        build_options.log_packets == .s2c_tick or
        build_options.log_packets == .all_tick;
}

fn logWrite(comptime _: std.meta.Tag(network_data.S2CPacketLogin)) bool {
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

pub fn shutdown(self: *Client) void {
    if (!self.initialized) {
        closeCallback(@ptrCast(&self.socket));
        return;
    }
    self.initialized = false;

    const close_status = uv.uv_tcp_close_reset(&self.socket, closeCallback);
    if (close_status != 0) std.log.err("Libuv socket close error: {s}", .{uv.uv_strerror(close_status)});
}

fn closeCallback(socket: [*c]uv.uv_handle_t) callconv(.c) void {
    const client: *Client = @ptrCast(@alignCast(socket.*.data));
    if (client.list_index == std.math.maxInt(usize)) {
        std.log.err("Login client had unset list index, not appending to free list", .{});
        return;
    }
    main.login_client_free_list.append(main.allocator, client.list_index) catch main.oomPanic();
}

pub fn readCallback(ud: *anyopaque, bytes_read: isize, _: [*c]const uv.uv_buf_t) callconv(.c) void {
    if (bytes_read == 0) return;

    const socket: *uv.uv_stream_t = @ptrCast(@alignCast(ud));
    const client: *Client = @ptrCast(@alignCast(socket.data));

    if (bytes_read < 0) {
        if (bytes_read != uv.UV_EOF)
            client.sendError("Socket read error")
        else
            client.shutdown();
        return;
    }

    if (!shared.uv.socketRead(
        network_data.C2SPacketLogin,
        "C2S login packet",
        client,
        bytes_read,
        &main.login_reader,
        handlerFn,
        logRead,
    )) {
        client.sendError("Socket read error");
        return;
    }
}

pub fn sendPacket(self: *Client, packet: network_data.S2CPacketLogin) void {
    const write_status = shared.uv.socketWrite(
        network_data.S2CPacketLogin,
        "S2C login packet",
        packet,
        &main.login_writer,
        &self.socket,
        logWrite,
    );
    if (write_status < 0) {
        self.shutdown();
        return;
    }

    if (packet == .@"error") self.shutdown();
}

pub fn sendError(self: *Client, message: []const u8) void {
    self.sendPacket(.{ .@"error" = .{ .description = message } });
}

fn databaseError(self: *Client) void {
    self.sendError("Database error");
}

fn getListData(self: *Client, acc_data: *db.AccountData, token: u128) !network_data.CharacterListData {
    if (try db.accountBanned(acc_data)) {
        self.sendError("Account banned");
        return error.AccountBanned;
    }

    var char_list: std.ArrayList(network_data.CharacterData) = .empty;
    defer char_list.deinit(main.allocator);
    buildList: {
        for (acc_data.get(.alive_char_ids) catch break :buildList) |char_id| {
            var char_data: db.CharacterData = .{ .acc_id = acc_data.acc_id, .char_id = char_id };
            defer char_data.deinit();

            var common_card_count: u8 = 0;
            var rare_card_count: u8 = 0;
            var epic_card_count: u8 = 0;
            var legendary_card_count: u8 = 0;
            var mythic_card_count: u8 = 0;

            countCards: {
                for (char_data.get(.cards) catch break :countCards) |card| {
                    const card_data = game_data.card.from_id.get(card) orelse continue;
                    switch (card_data.rarity) {
                        .common => common_card_count += 1,
                        .rare => rare_card_count += 1,
                        .epic => epic_card_count += 1,
                        .legendary => legendary_card_count += 1,
                        .mythic => mythic_card_count += 1,
                    }
                }
            }

            try char_list.append(main.allocator, .{
                .char_id = char_id,
                .class_id = try char_data.get(.class_id),
                .celestial = try char_data.get(.celestial),
                .aether = try char_data.get(.aether),
                .spirits_communed = try char_data.get(.spirits_communed),
                .equips = (try char_data.get(.inventory))[0..4].*,
                .keystone_talent_perc = 0.0,
                .ability_talent_perc = 0.0,
                .minor_talent_perc = 0.0,
                .common_card_count = common_card_count,
                .rare_card_count = rare_card_count,
                .epic_card_count = epic_card_count,
                .legendary_card_count = legendary_card_count,
                .mythic_card_count = mythic_card_count,
            });
        }
    }

    return .{
        .name = try main.allocator.dupe(u8, try acc_data.get(.name)),
        .token = token,
        .rank = try acc_data.get(.rank),
        .next_char_id = try acc_data.get(.next_char_id),
        .gold = try acc_data.get(.gold),
        .gems = try acc_data.get(.gems),
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
    var acc_data: db.AccountData = .{ .acc_id = acc_id };
    defer acc_data.deinit();
    const list = self.getListData(&acc_data, token) catch |e| {
        std.log.err("Error while creating list for {s}: {}", .{ data.email, e });
        if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace.*);

        self.sendError("Could not retrieve list");
        return;
    };
    defer disposeList(list);
    self.sendPacket(.{ .login_response = list });
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
    acc_data.set(.{ .rank = if (acc_id == 0) .admin else .default }) catch {
        self.databaseError();
        return;
    };
    acc_data.set(.{ .next_char_id = 0 }) catch {
        self.databaseError();
        return;
    };
    acc_data.set(.{ .alive_char_ids = &.{} }) catch {
        self.databaseError();
        return;
    };
    acc_data.set(.{ .resources = &.{} }) catch {
        self.databaseError();
        return;
    };
    acc_data.set(.{ .locked_until = 0 }) catch {
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
        .gold = acc_data.get(.gold) catch {
            self.databaseError();
            return;
        },
        .gems = acc_data.get(.gems) catch {
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
    self.sendPacket(.{ .register_response = list });
}

fn handleVerify(self: *Client, data: PacketData(.verify)) void {
    const acc_id = db.login(data.email, data.token) catch |e| {
        self.sendError(switch (e) {
            error.NoData => "Invalid email",
            error.InvalidToken => "Invalid token",
        });
        return;
    };
    var acc_data: db.AccountData = .{ .acc_id = acc_id };
    defer acc_data.deinit();
    const list = self.getListData(&acc_data, data.token) catch |e| {
        std.log.err("Error while creating list for {s}: {}", .{ data.email, e });
        if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace.*);

        self.sendError("Could not retrieve list");
        return;
    };
    defer disposeList(list);
    self.sendPacket(.{ .verify_response = list });
}

fn handleDelete(self: *Client, data: PacketData(.delete)) void {
    const acc_id = db.login(data.email, data.token) catch |e| {
        self.sendError(switch (e) {
            error.NoData => "Invalid email",
            error.InvalidToken => "Invalid token",
        });
        return;
    };

    var acc_data: db.AccountData = .{ .acc_id = acc_id };
    defer acc_data.deinit();

    const alive_char_ids = acc_data.get(.alive_char_ids) catch {
        self.sendError("Deletion failed: Database Error");
        return;
    };
    const new_char_ids = main.allocator.alloc(u32, alive_char_ids.len - 1) catch main.oomPanic();
    defer main.allocator.free(new_char_ids);
    delete: {
        for (alive_char_ids, 0..) |char_id, i| {
            if (data.char_id != char_id) continue;
            @memcpy(new_char_ids[0..i], alive_char_ids[0..i]);
            @memcpy(new_char_ids[i..], alive_char_ids[i + 1 ..]);
            break :delete;
        }
        self.sendError("Deletion failed: Character does not exist");
        return;
    }

    acc_data.set(.{ .alive_char_ids = new_char_ids }) catch {
        self.databaseError();
        return;
    };

    const list = self.getListData(&acc_data, data.token) catch |e| {
        std.log.err("Error while creating list for {s}: {}", .{ data.email, e });
        if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace.*);

        self.sendError("Could not retrieve list");
        return;
    };
    defer disposeList(list);
    self.sendPacket(.{ .delete_response = list });
}
