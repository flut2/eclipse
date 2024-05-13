const std = @import("std");
const settings = @import("settings.zig");
const builtin = @import("builtin");
const xml = @import("shared").xml;

pub const c = @cImport({
    @cDefine("REDIS_OPT_NONBLOCK", {});
    @cDefine("REDIS_OPT_REUSEADDR", {});
    @cInclude("hiredis.h");
});

inline fn printNum(val: anytype) ![:0]const u8 {
    var buf: [256]u8 = undefined;
    return try std.fmt.bufPrintZ(&buf, "{d}", .{val});
}

inline fn appendZ(str: []const u8) ![:0]const u8 {
    var buf: [512]u8 = undefined;
    return try std.fmt.bufPrintZ(&buf, "{s}", .{str});
}

inline fn anyToBytes(val: anytype) []const u8 {
    const T = @TypeOf(val);
    const type_info = @typeInfo(T);
    return switch (type_info) {
        .Array => std.mem.sliceAsBytes(&val),
        .Pointer => if (type_info.Pointer.size != .Slice)
            @compileError("You can not serialize a non-slice pointer")
        else
            std.mem.sliceAsBytes(val),
        else => std.mem.asBytes(&val),
    };
}

inline fn bytesToAny(comptime T: type, bytes: []const u8) T {
    const type_info = @typeInfo(T);
    return switch (type_info) {
        .Array => std.mem.bytesAsSlice(type_info.Array.child, bytes)[0..type_info.Array.len].*,
        .Pointer => if (type_info.Pointer.size != .Slice)
            @compileError("You can not serialize a non-slice pointer")
        else
            @alignCast(std.mem.bytesAsSlice(type_info.Pointer.child, bytes)),
        else => std.mem.bytesToValue(T, bytes),
    };
}

pub const Names = struct {
    reply_list: std.ArrayList(*c.redisReply),

    pub fn init(ally: std.mem.Allocator) Names {
        return .{ .reply_list = std.ArrayList(*c.redisReply).init(ally) };
    }

    pub fn deinit(self: Names) void {
        for (self.reply_list.items) |r| {
            c.freeReplyObject(r);
        }
        self.reply_list.deinit();
    }

    pub fn get(self: *Names, name: []const u8) !u32 {
        if (redisCommand(context, "HGET names %b", .{ name.ptr, name.len })) |reply| {
            self.reply_list.append(reply) catch @panic("OOM"); // todo don't do this
            if (reply.len <= 0)
                return error.NoData;

            return bytesToAny(u32, reply.str[0..reply.len]);
        } else return error.NoData;
    }

    pub fn set(self: *Names, name: []const u8, acc_id: u32) !void {
        const acc_id_bytes = anyToBytes(acc_id);

        if (redisCommand(context, "HSET names %b %b", .{ name.ptr, name.len, acc_id_bytes.ptr, acc_id_bytes.len })) |reply| {
            try self.reply_list.append(reply);
        } else return error.NoData;
    }
};

pub const LoginData = struct {
    const DataIds = enum(u8) {
        hashed_password = 0,
        account_id = 1,
    };
    const DataTypes = union(DataIds) {
        hashed_password: []const u8,
        account_id: u32,
    };

    email: []const u8,
    reply_list: std.ArrayList(*c.redisReply),

    pub fn init(ally: std.mem.Allocator, email: []const u8) LoginData {
        return .{
            .email = email,
            .reply_list = std.ArrayList(*c.redisReply).init(ally),
        };
    }

    pub fn deinit(self: LoginData) void {
        for (self.reply_list.items) |r| {
            c.freeReplyObject(r);
        }
        self.reply_list.deinit();
    }

    pub fn get(self: *LoginData, comptime id: DataIds) !(std.meta.fields(DataTypes)[@intFromEnum(id)].type) {
        const T = std.meta.fields(DataTypes)[@intFromEnum(id)].type;
        const id_bytes = anyToBytes(@intFromEnum(id));

        if (redisCommand(context, "HGET l%b %b", .{
            self.email.ptr,
            self.email.len,
            id_bytes.ptr,
            id_bytes.len,
        })) |reply| {
            try self.reply_list.append(reply);
            if (reply.len <= 0)
                return error.NoData;

            return bytesToAny(T, reply.str[0..reply.len]);
        } else return error.NoData;
    }

    pub fn set(self: *LoginData, value: DataTypes) !void {
        const id_bytes = anyToBytes(@intFromEnum(value));
        const value_bytes = switch (value) {
            inline else => |v| anyToBytes(v),
        };

        if (redisCommand(context, "HSET l%b %b %b", .{
            self.email.ptr,
            self.email.len,
            id_bytes.ptr,
            id_bytes.len,
            value_bytes.ptr,
            value_bytes.len,
        })) |reply| {
            try self.reply_list.append(reply);
        } else return error.NoData;
    }
};

pub const AccountData = struct {
    const DataIds = enum(u8) {
        email = 0,
        name = 1,
        hwid = 2,
        ip = 3,
        register_timestamp = 4,
        last_login_timestamp = 5,
        gold = 6,
        gems = 7,
        crowns = 8,
        rank = 9,
        next_char_id = 10,
        alive_char_ids = 11,
        max_char_slots = 12,
    };
    const DataTypes = union(DataIds) {
        email: []const u8,
        name: []const u8,
        hwid: []const u8,
        ip: []const u8,
        register_timestamp: u64,
        last_login_timestamp: u64,
        gold: u32,
        gems: u32,
        crowns: u32,
        rank: u8,
        next_char_id: u32,
        alive_char_ids: []const u32,
        max_char_slots: u32,
    };

    acc_id: u32,
    reply_list: std.ArrayList(*c.redisReply),

    pub fn init(ally: std.mem.Allocator, acc_id: u32) AccountData {
        return .{
            .acc_id = acc_id,
            .reply_list = std.ArrayList(*c.redisReply).init(ally),
        };
    }

    pub fn deinit(self: AccountData) void {
        for (self.reply_list.items) |r| {
            c.freeReplyObject(r);
        }
        self.reply_list.deinit();
    }

    pub fn get(self: *AccountData, comptime id: DataIds) !(std.meta.fields(DataTypes)[@intFromEnum(id)].type) {
        const T = std.meta.fields(DataTypes)[@intFromEnum(id)].type;
        const acc_id_bytes = anyToBytes(self.acc_id);
        const id_bytes = anyToBytes(@intFromEnum(id));

        if (redisCommand(context, "HGET a%b %b", .{
            acc_id_bytes.ptr,
            acc_id_bytes.len,
            id_bytes.ptr,
            id_bytes.len,
        })) |reply| {
            try self.reply_list.append(reply);
            if (reply.len <= 0)
                return error.NoData;

            return bytesToAny(T, reply.str[0..reply.len]);
        } else return error.NoData;
    }

    pub fn set(self: *AccountData, value: DataTypes) !void {
        const acc_id_bytes = anyToBytes(self.acc_id);
        const id_bytes = anyToBytes(@intFromEnum(value));
        const value_bytes = switch (value) {
            inline else => |v| anyToBytes(v),
        };

        if (redisCommand(context, "HSET a%b %b %b", .{
            acc_id_bytes.ptr,
            acc_id_bytes.len,
            id_bytes.ptr,
            id_bytes.len,
            value_bytes.ptr,
            value_bytes.len,
        })) |reply| {
            try self.reply_list.append(reply);
        } else return error.NoData;
    }

    pub fn writeXml(self: *AccountData, writer: xml.DocWriter) !void {
        try writer.startElement("Account");
        try writer.writeElement("AccountId", try printNum(self.acc_id));
        try writer.writeElement("Name", try appendZ(try self.get(.name)));
        if (try self.get(.rank) > 80)
            try writer.writeElement("Admin", "true");
        try writer.writeElement("Rank", try printNum(try self.get(.rank)));
        try writer.writeElement("Gold", try printNum(try self.get(.gold)));
        try writer.writeElement("Gems", try printNum(try self.get(.gems)));
        try writer.writeElement("Crowns", try printNum(try self.get(.crowns)));
        try writer.endElement();
    }
};

pub const CharacterData = struct {
    const DataIds = enum(u8) {
        char_type = 0,
        create_timestamp = 1,
        last_login_timestamp = 2,
        aether = 3,
        stats = 4,
        items = 5,
        hp = 6,
        mp = 7,
        skin_type = 8,
    };
    const DataTypes = union(DataIds) {
        char_type: u16,
        create_timestamp: u64,
        last_login_timestamp: u64,
        aether: u8,
        stats: [13]i32,
        items: [22]u16,
        hp: i32,
        mp: i32,
        skin_type: u16,
    };

    acc_id: u32,
    char_id: u32,
    reply_list: std.ArrayList(*c.redisReply),

    pub fn init(ally: std.mem.Allocator, acc_id: u32, char_id: u32) CharacterData {
        return .{
            .acc_id = acc_id,
            .char_id = char_id,
            .reply_list = std.ArrayList(*c.redisReply).init(ally),
        };
    }

    pub fn deinit(self: CharacterData) void {
        for (self.reply_list.items) |r| {
            c.freeReplyObject(r);
        }
        self.reply_list.deinit();
    }

    pub fn get(self: *CharacterData, comptime id: DataIds) !(std.meta.fields(DataTypes)[@intFromEnum(id)].type) {
        const T = std.meta.fields(DataTypes)[@intFromEnum(id)].type;
        const char_id_bytes = anyToBytes(self.char_id);
        const acc_id_bytes = anyToBytes(self.acc_id);
        const id_bytes = anyToBytes(@intFromEnum(id));

        if (redisCommand(context, "HGET c%b:%b %b", .{
            acc_id_bytes.ptr,
            acc_id_bytes.len,
            char_id_bytes.ptr,
            char_id_bytes.len,
            id_bytes.ptr,
            id_bytes.len,
        })) |reply| {
            try self.reply_list.append(reply);
            if (reply.len <= 0)
                return error.NoData;

            return bytesToAny(T, reply.str[0..reply.len]);
        } else return error.NoData;
    }

    pub fn set(self: *CharacterData, value: DataTypes) !void {
        const acc_id_bytes = anyToBytes(self.acc_id);
        const char_id_bytes = anyToBytes(self.char_id);
        const id_bytes = anyToBytes(@intFromEnum(value));
        const value_bytes = switch (value) {
            inline else => |v| anyToBytes(v),
        };

        if (redisCommand(context, "HSET c%b:%b %b %b", .{ acc_id_bytes.ptr, acc_id_bytes.len, char_id_bytes.ptr, char_id_bytes.len, id_bytes.ptr, id_bytes.len, value_bytes.ptr, value_bytes.len })) |reply| {
            try self.reply_list.append(reply);
        } else return error.NoData;
    }

    pub fn writeXml(self: *CharacterData, writer: xml.DocWriter) !void {
        const stats = try self.get(.stats);
        const items = try self.get(.items);
        _ = items;

        try writer.startElement("Char");
        try writer.writeAttribute("id", try printNum(self.char_id));
        try writer.writeElement("ObjectType", try printNum(try self.get(.char_type)));
        try writer.writeElement("Health", try printNum(stats[0]));
        try writer.writeElement("Mana", try printNum(stats[1]));
        try writer.writeElement("Strength", try printNum(stats[2]));
        try writer.writeElement("Wit", try printNum(stats[3]));
        try writer.writeElement("Defense", try printNum(stats[4]));
        try writer.writeElement("Resistance", try printNum(stats[5]));
        try writer.writeElement("Speed", try printNum(stats[6]));
        try writer.writeElement("Stamina", try printNum(stats[7]));
        try writer.writeElement("Intelligence", try printNum(stats[8]));
        try writer.writeElement("Penetration", try printNum(stats[9]));
        try writer.writeElement("Piercing", try printNum(stats[10]));
        try writer.writeElement("Haste", try printNum(stats[11]));
        try writer.writeElement("Tenacity", try printNum(stats[12]));
        try writer.endElement();
    }
};

var allocator: std.mem.Allocator = undefined;
var context: *c.redisContext = undefined;

fn redisCommand(ctx: [*c]c.redisContext, format: [*c]const u8, args: anytype) ?*c.redisReply {
    if (@call(.auto, c.redisCommand, .{ ctx, format } ++ args)) |reply| {
        return @ptrCast(@alignCast(reply));
    } else return null;
}

pub fn init(ally: std.mem.Allocator) !void {
    allocator = ally;
    const context_base = c.redisConnectWithTimeout(settings.redis_ip, settings.redis_port, .{ .tv_sec = 1, .tv_usec = 0 });

    if (context_base) |ctx| {
        context = ctx;

        if (context.err != 0) {
            std.log.err("Redis connection error: {s}", .{context.errstr});
            return error.ConnectionError;
        }
    } else return error.OutOfMemory;
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

pub fn login(email: []const u8, password: []const u8) !u32 {
    var login_data = LoginData.init(allocator, email);
    defer login_data.deinit();
    try std.crypto.pwhash.scrypt.strVerify(try login_data.get(.hashed_password), password, .{ .allocator = allocator });
    return try login_data.get(.account_id);
}
