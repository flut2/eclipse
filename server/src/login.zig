const std = @import("std");
const settings = @import("settings.zig");
const db = @import("db.zig");
const httpz = @import("httpz");
const xml = @import("shared").xml;

var allocator: std.mem.Allocator = undefined;
var server: httpz.ServerCtx(void, void) = undefined;

pub fn init(ally: std.mem.Allocator) !void {
    allocator = ally;
    server = try httpz.Server().init(allocator, .{ .port = settings.login_port });
    server.notFound(notFound);
    server.errorHandler(errorHandler);

    var router = server.router();
    router.post("/account/verify", handleAccountVerify);
    router.post("/app/init", handleAppInit);
    router.post("/char/list", handleCharList);
}

pub fn deinit() void {
    server.deinit();
}

pub fn tick() !void {
    try server.listen();
}

fn login(email: []const u8, password: []const u8, res: *httpz.Response) !u32 {
    const login_data = db.loginData(email) catch |e| {
        switch (e) {
            error.NoData => {
                res.body = "<Error>Account does not exist</Error>";
                return std.math.maxInt(u32);
            },
            else => {
                res.body = "<Error>Data parsing failure</Error>";
                return std.math.maxInt(u32);
            },
        }
    };
    defer login_data.deinit();

    const salted_pw = try std.mem.concat(allocator, u8, &.{ password, login_data.value.Salt });
    defer allocator.free(salted_pw);

    var hashed_pass: [std.crypto.hash.Sha1.digest_length]u8 = undefined;
    var h = std.crypto.hash.Sha1.init(.{});
    h.update(salted_pw);
    h.final(hashed_pass[0..]);

    const base64_pass = try allocator.alloc(u8, std.base64.standard.Encoder.calcSize(hashed_pass.len));
    defer allocator.free(base64_pass);

    if (std.mem.eql(u8, login_data.value.HashedPassword, std.base64.standard.Encoder.encode(base64_pass, &hashed_pass))) {
        res.body = "<Error>Invalid credentials</Error>";
        return std.math.maxInt(u32);
    }

    return login_data.value.AccountId;
}

fn handleAccountVerify(req: *httpz.Request, res: *httpz.Response) !void {
    const query = try req.query();
    const email = query.get("email") orelse {
        std.log.err("Could not parse e-mail for /account/verify", .{});
        return;
    };
    const password = query.get("password") orelse {
        std.log.err("Could not parse password for /account/verify", .{});
        return;
    };

    const acc_id = try login(email, password, res);
    if (acc_id == std.math.maxInt(u32))
        return;

    var acc_data = db.AccountData.init(allocator, acc_id);
    defer acc_data.deinit();

    var writer = xml.DocWriter.create();
    defer writer.deinit();

    try writer.startDocument(.{});
    try acc_data.writeXml(writer, res.arena);
    try writer.endDocument();

    res.body = try writer.childDoc().toMemory(res.arena);
    std.log.err("body {s}", .{res.body.?});
}

fn handleAppInit(_: *httpz.Request, res: *httpz.Response) !void {
    res.body = "<Error>Currently not implemented</Error>";
}

fn handleCharList(req: *httpz.Request, res: *httpz.Response) !void {
    const query = try req.query();
    const email = query.get("email") orelse {
        std.log.err("Could not parse e-mail for /account/verify", .{});
        return;
    };
    const password = query.get("password") orelse {
        std.log.err("Could not parse password for /account/verify", .{});
        return;
    };

    const acc_id = try login(email, password, res);
    if (acc_id == std.math.maxInt(u32))
        return;

    var acc_data = db.AccountData.init(allocator, acc_id);
    defer acc_data.deinit();

    var alive_data = db.AliveData.init(allocator, acc_id);
    defer alive_data.deinit();

    var writer = xml.DocWriter.create();
    defer writer.deinit();

    try writer.startDocument(.{});
    try writer.startElement("Chars");

    try writer.writeAttribute("nextCharId", try std.fmt.allocPrintZ(res.arena, "{d}", .{try alive_data.nextCharId()}));
    try writer.writeAttribute("maxNumChars", try acc_data.get("maxCharSlot"));

    // temp
    try writer.startElement("Servers");
    try writer.writeElement("Name", settings.server_name);
    try writer.writeElement("DNS", settings.public_ip);
    try writer.writeElement("Port", try std.fmt.allocPrintZ(res.arena, "{d}", .{settings.game_port}));
    try writer.writeElement("Lat", "0");
    try writer.writeElement("Long", "0");
    try writer.writeElement("Usage", "0");
    try writer.writeElement("MaxPlayers", "500");
    try writer.writeElement("AdminOnly", "false");
    try writer.endElement();

    try alive_data.writeXml(writer, res.arena);
    try acc_data.writeXml(writer, res.arena);

    try writer.endElement();
    try writer.endDocument();

    res.body = try writer.childDoc().toMemory(res.arena);
    std.log.err("body2 {s}", .{res.body.?});
}

fn notFound(_: *httpz.Request, res: *httpz.Response) !void {
    res.status = 404;
    res.body = "Not Found";
}

// note that the error handler return `void` and not `!void`
fn errorHandler(req: *httpz.Request, res: *httpz.Response, err: anyerror) void {
    res.status = 500;
    res.body = "Internal Server Error";
    std.log.warn("Unhandled exception for request '{s}': {}", .{ req.url.raw, err });
}
