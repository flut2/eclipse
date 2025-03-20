const std = @import("std");
const builtin = @import("builtin");

const network_data = @import("shared").network_data;
const use_dragonfly = @import("options").use_dragonfly;

const main = @import("main.zig");

pub const c = @cImport({
    @cDefine("REDIS_OPT_NONBLOCK", {});
    @cDefine("REDIS_OPT_REUSEADDR", {});
    @cInclude("hiredis.h");
});

pub var csprng: std.Random.DefaultCsprng = blk: {
    @setEvalBranchQuota(10000);
    break :blk .init(@splat(0));
};

inline fn anyToBytes(val: anytype) []const u8 {
    const T = @TypeOf(val);
    const type_info = @typeInfo(T);
    return switch (type_info) {
        .array => std.mem.sliceAsBytes(&val),
        .pointer => if (type_info.pointer.size != .slice)
            @compileError("You can not serialize a non-slice pointer")
        else
            std.mem.sliceAsBytes(val),
        else => std.mem.asBytes(&val),
    };
}

inline fn bytesToAny(comptime T: type, bytes: []const u8) T {
    const type_info = @typeInfo(T);
    return switch (type_info) {
        .array => std.mem.bytesAsSlice(type_info.array.child, bytes)[0..type_info.array.len].*,
        .pointer => if (type_info.pointer.size != .slice)
            @compileError("You can not serialize a non-slice pointer")
        else
            @alignCast(std.mem.bytesAsSlice(type_info.pointer.child, bytes)),
        else => std.mem.bytesToValue(T, bytes),
    };
}

pub const BannedHwids = struct {
    reply_list: std.ArrayListUnmanaged(*c.redisReply) = .empty,

    pub fn deinit(self: *BannedHwids) void {
        for (self.reply_list.items) |r| c.freeReplyObject(r);
        self.reply_list.deinit(main.allocator);
    }

    pub fn exists(self: *BannedHwids, hwid: []const u8) bool {
        if (redisCommand(context, "SISMEMBER banned_hwids %b", .{ hwid.ptr, hwid.len })) |reply| {
            self.reply_list.append(main.allocator, reply) catch main.oomPanic();
            if (reply.len <= 0) return false;
            return bytesToAny(bool, reply.str[0..reply.len]);
        } else return false;
    }

    pub fn add(self: *BannedHwids, hwid: []const u8, expiry_sec: u32) !void {
        if (use_dragonfly) {
            if (redisCommand(context, "SADDEX banned_hwids %d %b", .{ expiry_sec, hwid.ptr, hwid.len })) |reply| {
                self.reply_list.append(main.allocator, reply) catch main.oomPanic();
            } else return error.NoData;
        } else {
            if (redisCommand(context, "SADD banned_hwids %b", .{ hwid.ptr, hwid.len })) |reply| {
                self.reply_list.append(main.allocator, reply) catch main.oomPanic();
            } else return error.NoData;
        }
    }

    pub fn remove(self: *BannedHwids, hwid: []const u8) !void {
        if (redisCommand(context, "SREM banned_hwids %b", .{ hwid.ptr, hwid.len })) |reply| {
            self.reply_list.append(main.allocator, reply) catch main.oomPanic();
        } else return error.NoData;
    }
};

pub const MutedHwids = struct {
    reply_list: std.ArrayListUnmanaged(*c.redisReply) = .empty,

    pub fn deinit(self: *MutedHwids) void {
        for (self.reply_list.items) |r| c.freeReplyObject(r);
        self.reply_list.deinit(main.allocator);
    }

    pub fn exists(self: *MutedHwids, hwid: []const u8) bool {
        if (redisCommand(context, "SISMEMBER muted_hwids %b", .{ hwid.ptr, hwid.len })) |reply| {
            self.reply_list.append(main.allocator, reply) catch main.oomPanic();
            if (reply.len <= 0) return false;
            return bytesToAny(bool, reply.str[0..reply.len]);
        } else return false;
    }

    pub fn add(self: *MutedHwids, hwid: []const u8, expiry_sec: u32) !void {
        if (use_dragonfly) {
            if (redisCommand(context, "SADDEX muted_hwids %d %b", .{ expiry_sec, hwid.ptr, hwid.len })) |reply| {
                self.reply_list.append(main.allocator, reply) catch main.oomPanic();
            } else return error.NoData;
        } else {
            if (redisCommand(context, "SADD muted_hwids %b", .{ hwid.ptr, hwid.len })) |reply| {
                self.reply_list.append(main.allocator, reply) catch main.oomPanic();
            } else return error.NoData;
        }
    }

    pub fn remove(self: *MutedHwids, hwid: []const u8) !void {
        if (redisCommand(context, "SREM muted_hwids %b", .{ hwid.ptr, hwid.len })) |reply| {
            self.reply_list.append(main.allocator, reply) catch main.oomPanic();
        } else return error.NoData;
    }

    pub fn ttl(self: *MutedHwids, ip: []const u8) !u32 {
        if (use_dragonfly) {
            if (redisCommand(context, "FIELDTTL muted_hwids %b", .{ ip.ptr, ip.len })) |reply| {
                self.reply_list.append(main.allocator, reply) catch main.oomPanic();
                if (reply.len <= 0) return error.NoData;

                const value = bytesToAny(i32, reply.str[0..reply.len]);
                return switch (value) {
                    -1 => 0,
                    -2 => error.NoKey,
                    -3 => error.NoField,
                    else => @intCast(value),
                };
            } else return error.NoData;
        }

        return error.Unsupported;
    }
};

pub const Names = struct {
    reply_list: std.ArrayListUnmanaged(*c.redisReply) = .empty,

    pub fn deinit(self: *Names) void {
        for (self.reply_list.items) |r| c.freeReplyObject(r);
        self.reply_list.deinit(main.allocator);
    }

    pub fn get(self: *Names, name: []const u8) !u32 {
        if (redisCommand(context, "HGET names %b", .{ name.ptr, name.len })) |reply| {
            self.reply_list.append(main.allocator, reply) catch main.oomPanic();
            if (reply.len <= 0) return error.NoData;
            return bytesToAny(u32, reply.str[0..reply.len]);
        } else return error.NoData;
    }

    pub fn set(self: *Names, name: []const u8, acc_id: u32) !void {
        if (redisCommand(context, "HSET names %b %d", .{ name.ptr, name.len, acc_id })) |reply| {
            self.reply_list.append(main.allocator, reply) catch main.oomPanic();
        } else return error.NoData;
    }
};

pub const LoginData = struct {
    const Data = union(enum) {
        hashed_password: []const u8,
        token: u128,
        account_id: u32,
    };

    email: []const u8,
    reply_list: std.ArrayListUnmanaged(*c.redisReply) = .empty,

    pub fn deinit(self: *LoginData) void {
        for (self.reply_list.items) |r| c.freeReplyObject(r);
        self.reply_list.deinit(main.allocator);
    }

    pub fn get(self: *LoginData, comptime id: @typeInfo(Data).@"union".tag_type.?) !(@typeInfo(Data).@"union".fields[@intFromEnum(id)].type) {
        const T = @typeInfo(Data).@"union".fields[@intFromEnum(id)].type;
        const tag_name = @tagName(id);

        if (redisCommand(context, "HGET l%b %b", .{
            self.email.ptr,
            self.email.len,
            tag_name.ptr,
            tag_name.len,
        })) |reply| {
            self.reply_list.append(main.allocator, reply) catch main.oomPanic();
            if (reply.len <= 0) return error.NoData;
            return bytesToAny(T, reply.str[0..reply.len]);
        } else return error.NoData;
    }

    pub fn getWithDefault(
        self: *LoginData,
        comptime id: @typeInfo(Data).@"union".tag_type.?,
        default: @typeInfo(Data).@"union".fields[@intFromEnum(id)].type,
    ) (@typeInfo(Data).@"union".fields[@intFromEnum(id)].type) {
        return self.get(id) catch {
            try self.set(@unionInit(Data, @tagName(id), default));
            return default;
        };
    }

    pub fn set(self: *LoginData, value: Data) !void {
        const value_bytes = switch (value) {
            inline else => |v| anyToBytes(v),
        };
        const tag_name = @tagName(value);

        if (redisCommand(context, "HSET l%b %b %b", .{
            self.email.ptr,
            self.email.len,
            tag_name.ptr,
            tag_name.len,
            value_bytes.ptr,
            value_bytes.len,
        })) |reply| {
            self.reply_list.append(main.allocator, reply) catch main.oomPanic();
        } else return error.NoData;
    }
};

pub const AccountData = struct {
    const Data = union(enum) {
        email: []const u8,
        name: []const u8,
        hwid: []const u8,
        register_timestamp: i64,
        last_login_timestamp: i64,
        mute_expiry: i64,
        ban_expiry: i64,
        gold: u32,
        gems: u32,
        rank: network_data.Rank,
        next_char_id: u32,
        alive_char_ids: []const u32,
        resources: []const network_data.DataIdWithCount(u32),
        locked_until: u64,
    };

    acc_id: u32,
    reply_list: std.ArrayListUnmanaged(*c.redisReply) = .empty,

    pub fn deinit(self: *AccountData) void {
        for (self.reply_list.items) |r| c.freeReplyObject(r);
        self.reply_list.deinit(main.allocator);
    }

    pub fn get(self: *AccountData, comptime id: @typeInfo(Data).@"union".tag_type.?) !(@typeInfo(Data).@"union".fields[@intFromEnum(id)].type) {
        const T = @typeInfo(Data).@"union".fields[@intFromEnum(id)].type;
        const tag_name = @tagName(id);

        if (redisCommand(context, "HGET a%d %b", .{
            self.acc_id,
            tag_name.ptr,
            tag_name.len,
        })) |reply| {
            self.reply_list.append(main.allocator, reply) catch main.oomPanic();
            if (reply.len <= 0) return error.NoData;
            return bytesToAny(T, reply.str[0..reply.len]);
        } else return error.NoData;
    }

    pub fn getWithDefault(
        self: *AccountData,
        comptime id: @typeInfo(Data).@"union".tag_type.?,
        default: @typeInfo(Data).@"union".fields[@intFromEnum(id)].type,
    ) !(@typeInfo(Data).@"union".fields[@intFromEnum(id)].type) {
        return self.get(id) catch {
            try self.set(@unionInit(Data, @tagName(id), default));
            return default;
        };
    }

    pub fn set(self: *AccountData, value: Data) !void {
        const value_bytes = switch (value) {
            inline else => |v| anyToBytes(v),
        };
        const tag_name = @tagName(value);

        if (redisCommand(context, "HSET a%d %b %b", .{
            self.acc_id,
            tag_name.ptr,
            tag_name.len,
            value_bytes.ptr,
            value_bytes.len,
        })) |reply| {
            self.reply_list.append(main.allocator, reply) catch main.oomPanic();
        } else return error.NoData;
    }
};

pub const CharacterData = struct {
    pub const Data = union(enum) {
        class_id: u16,
        create_timestamp: u64,
        last_login_timestamp: u64,
        aether: u8,
        spirits_communed: u32,
        inventory: [22]u16,
        item_data: [22]network_data.ItemData,
        hp: i32,
        mp: i32,
        cards: []const u16,
        talents: []const network_data.DataIdWithCount(u16),
        celestial: bool,
    };

    acc_id: u32,
    char_id: u32,
    reply_list: std.ArrayListUnmanaged(*c.redisReply) = .empty,

    pub fn deinit(self: *CharacterData) void {
        for (self.reply_list.items) |r| c.freeReplyObject(r);
        self.reply_list.deinit(main.allocator);
    }

    pub fn get(self: *CharacterData, comptime id: @typeInfo(Data).@"union".tag_type.?) !(@typeInfo(Data).@"union".fields[@intFromEnum(id)].type) {
        const T = @typeInfo(Data).@"union".fields[@intFromEnum(id)].type;
        const tag_name = @tagName(id);

        if (redisCommand(context, "HGET c%d:%d %b", .{
            self.acc_id,
            self.char_id,
            tag_name.ptr,
            tag_name.len,
        })) |reply| {
            self.reply_list.append(main.allocator, reply) catch main.oomPanic();
            if (reply.len <= 0) return error.NoData;
            return bytesToAny(T, reply.str[0..reply.len]);
        } else return error.NoData;
    }

    pub fn getWithDefault(
        self: *CharacterData,
        comptime id: @typeInfo(Data).@"union".tag_type.?,
        default: @typeInfo(Data).@"union".fields[@intFromEnum(id)].type,
    ) !(@typeInfo(Data).@"union".fields[@intFromEnum(id)].type) {
        return self.get(id) catch {
            try self.set(@unionInit(Data, @tagName(id), default));
            return default;
        };
    }

    pub fn set(self: *CharacterData, value: Data) !void {
        const value_bytes = switch (value) {
            inline else => |v| anyToBytes(v),
        };
        const tag_name = @tagName(value);

        if (redisCommand(context, "HSET c%d:%d %b %b", .{
            self.acc_id,
            self.char_id,
            tag_name.ptr,
            tag_name.len,
            value_bytes.ptr,
            value_bytes.len,
        })) |reply| {
            self.reply_list.append(main.allocator, reply) catch main.oomPanic();
        } else return error.NoData;
    }
};

var context: *c.redisContext = undefined;

fn redisCommand(ctx: [*c]c.redisContext, format: [*c]const u8, args: anytype) ?*c.redisReply {
    if (@call(.auto, c.redisCommand, .{ ctx, format } ++ args)) |reply| {
        return @ptrCast(@alignCast(reply));
    } else return null;
}

pub fn init() !void {
    var buf: [std.Random.DefaultCsprng.secret_seed_length]u8 = undefined;
    std.posix.getrandom(&buf) catch |e| {
        std.log.err("getrandom() failed: {}. This means that the server is insecure and should not be used in production", .{e});
        buf = @splat(0);
    };
    csprng = .init(buf);

    var ip_buf: [40]u8 = undefined;
    context = c.redisConnect(
        std.fmt.bufPrintZ(&ip_buf, "{s}", .{main.settings.redis_ip}) catch @panic("Invalid IP size"),
        main.settings.redis_port,
    ) orelse return error.OutOfMemory;
    if (context.err != 0) {
        std.log.err("Redis connection error: {s}", .{context.errstr});
        return error.ConnectionError;
    }
}

pub fn deinit() void {
    c.redisFree(context);
}

pub fn nextAccId() !u32 {
    const ret = blk: {
        if (redisCommand(context, "GET next_acc_id", .{})) |reply| {
            defer c.freeReplyObject(reply);
            if (reply.len == 0)
                break :blk error.NoData;

            break :blk bytesToAny(u32, reply.str[0..reply.len]);
        } else break :blk error.NoData;
    } catch 0;

    if (ret == std.math.maxInt(u32))
        @panic("Out of account ids");

    if (redisCommand(context, "SET next_acc_id %d", .{ret + 1})) |reply| {
        c.freeReplyObject(reply);
        return ret;
    }

    return error.NoData;
}

pub fn isBanned(hwid: []const u8) !bool {
    var banned_hwids: BannedHwids = .{};
    defer banned_hwids.deinit();
    if (banned_hwids.exists(hwid)) return true;
    return false;
}

pub fn accountBanned(acc_data: *AccountData) !bool {
    if (try acc_data.get(.ban_expiry) >= main.current_time) return true;
    if (try isBanned(try acc_data.get(.hwid))) return true;
    return false;
}

pub fn login(email: []const u8, token: u128) !u32 {
    var login_data: LoginData = .{ .email = email };
    defer login_data.deinit();
    return if (try login_data.get(.token) == token)
        try login_data.get(.account_id)
    else
        error.InvalidToken;
}
