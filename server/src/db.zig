const std = @import("std");
const settings = @import("settings.zig");
const builtin = @import("builtin");
const xml = @import("shared").xml;

pub const c = @cImport({
    @cDefine("REDIS_OPT_NONBLOCK", {});
    @cDefine("REDIS_OPT_REUSEADDR", {});
    @cInclude("hiredis.h");
});

const LoginData = struct {
    Salt: []const u8,
    HashedPassword: []const u8,
    AccountId: u32,
};

pub const AccountData = struct {
    acc_id: u32,
    reply_list: std.ArrayList(*c.redisReply),

    pub fn init(ally: std.mem.Allocator, acc_id: u32) AccountData {
        return .{
            .acc_id = acc_id,
            .reply_list = std.ArrayList(*c.redisReply).init(ally),
        };
    }

    pub fn deinit(self: AccountData) void {
        self.reply_list.deinit();
    }

    pub fn get(self: *AccountData, comptime field: []const u8) ![:0]const u8 {
        if (redisCommand(context, "HGET account.%d " ++ field, .{self.acc_id})) |reply| {
            try self.reply_list.append(reply);
            return reply.str[0..reply.len :0];
        } else return error.NoData;
    }

    pub fn set(self: *AccountData, comptime field: []const u8, value: []const u8) !void {
        const value_dupe = try allocator.dupeZ(u8, value);
        defer allocator.free(value_dupe);

        if (redisCommand(context, "HSET account.%d " ++ field ++ " %s", .{ self.acc_id, value_dupe.ptr })) |reply| {
            try self.reply_list.append(reply);
        } else return error.NoData;
    }

    pub fn writeXml(self: *AccountData, writer: xml.DocWriter, ally: std.mem.Allocator) !void {
        try writer.startElement("Account");

        try writer.writeElement("AccountId", try std.fmt.allocPrintZ(ally, "{d}", .{self.acc_id}));
        try writer.writeElement("Name", try self.get("name"));
        if (!std.mem.eql(u8, try self.get("admin"), "0"))
            try writer.writeElement("Admin", "true");
        try writer.writeElement("Rank", try self.get("rank"));
        try writer.writeElement("Gold", try self.get("credits"));

        // temp
        try writer.startElement("Guild");
        try writer.writeElement("Name", "");
        try writer.writeElement("Rank", "0");
        try writer.endElement();

        try writer.endElement();
    }
};

pub const CharacterData = struct {
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
        self.reply_list.deinit();
    }

    pub fn get(self: *CharacterData, comptime field: []const u8) ![:0]const u8 {
        if (redisCommand(context, "HGET char.%d.%d " ++ field, .{ self.acc_id, self.char_id })) |reply| {
            try self.reply_list.append(reply);
            return reply.str[0..reply.len :0];
        } else return error.NoData;
    }

    pub fn set(self: *CharacterData, comptime field: []const u8, value: []const u8) !void {
        const value_dupe = try allocator.dupeZ(u8, value);
        defer allocator.free(value_dupe);

        if (redisCommand(context, "HSET char.%d.%d " ++ field ++ " %s", .{ self.acc_id, self.char_id, value_dupe.ptr })) |reply| {
            try self.reply_list.append(reply);
        } else return error.NoData;
    }

    pub fn writeXml(self: *CharacterData, writer: xml.DocWriter, ally: std.mem.Allocator) !void {
        var stats: [13]i32 = undefined;

        if (redisCommand(context, "HGET char.%d.%d stats", .{ self.acc_id, self.char_id })) |reply| {
            try self.reply_list.append(reply);
            inline for (0..13) |i| {
                stats[i] = @bitCast(reply.str[i * 4 .. i * 4 + 4].*);
            }
        } else return error.NoData;

        try writer.startElement("Char");
        try writer.writeAttribute("id", try std.fmt.allocPrintZ(ally, "{d}", .{self.char_id}));
        try writer.writeElement("ObjectType", try self.get("charType"));
        try writer.writeIntElement(allocator, "Health", stats[0]);
        try writer.writeIntElement(allocator, "Mana", stats[1]);
        try writer.writeIntElement(allocator, "Strength", stats[2]);
        try writer.writeIntElement(allocator, "Wit", stats[3]);
        try writer.writeIntElement(allocator, "Defense", stats[4]);
        try writer.writeIntElement(allocator, "Resistance", stats[5]);
        try writer.writeIntElement(allocator, "Speed", stats[6]);
        try writer.writeIntElement(allocator, "Stamina", stats[7]);
        try writer.writeIntElement(allocator, "Intelligence", stats[8]);
        try writer.writeIntElement(allocator, "Penetration", stats[9]);
        try writer.writeIntElement(allocator, "Piercing", stats[10]);
        try writer.writeIntElement(allocator, "Haste", stats[11]);
        try writer.writeIntElement(allocator, "Tenacity", stats[12]);
        try writer.endElement();
    }
};

pub const AliveData = struct {
    acc_id: u32,
    char_list: std.ArrayList(CharacterData),
    reply_list: std.ArrayList(*c.redisReply),

    pub fn init(ally: std.mem.Allocator, acc_id: u32) AliveData {
        return .{
            .acc_id = acc_id,
            .reply_list = std.ArrayList(*c.redisReply).init(ally),
            .char_list = std.ArrayList(CharacterData).init(ally),
        };
    }

    pub fn deinit(self: AliveData) void {
        self.reply_list.deinit();
        for (self.char_list.items) |data| {
            data.deinit();
        }
        self.char_list.deinit();
    }

    pub fn chars(self: *AliveData) ![]CharacterData {
        for (self.char_list.items) |data| {
            data.deinit();
        }
        self.char_list.clearAndFree();

        if (redisCommand(context, "SMEMBERS alive.%d", .{self.acc_id})) |reply| {
            try self.reply_list.append(reply);

            for (reply.element[0..reply.elements]) |child| {
                try self.char_list.append(CharacterData.init(
                    allocator,
                    self.acc_id,
                    @bitCast(child.*.str[0..4].*),
                ));
            }

            return self.char_list.items;
        } else return error.NoData;
    }

    pub fn nextCharId(self: *AliveData) !u32 {
        const char_list = try self.chars();
        if (char_list.len == 0)
            return 1;

        return char_list[char_list.len - 1].char_id + 1;
    }

    pub fn writeXml(self: *AliveData, writer: xml.DocWriter, ally: std.mem.Allocator) !void {
        for (try self.chars()) |*data| {
            try data.writeXml(writer, ally);
        }
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

// Must deinit()
pub fn loginData(email: []const u8) !std.json.Parsed(LoginData) {
    var email_upper: [64]u8 = undefined;
    const mod = std.ascii.upperString(&email_upper, email);
    email_upper[mod.len] = 0;
    if (redisCommand(context, "HGET logins %s", .{email_upper[0..mod.len].ptr})) |login_json| {
        defer c.freeReplyObject(login_json);
        return try std.json.parseFromSlice(LoginData, allocator, login_json.str[0..login_json.len], .{});
    } else return error.NoData;
}

pub fn deinit() void {
    c.redisFree(context);
}
