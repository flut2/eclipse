const std = @import("std");
const settings = @import("settings.zig");
const db = @import("db.zig");
const httpz = @import("httpz");
const xml = @import("shared").xml;
const rpmalloc = @import("rpmalloc").RPMalloc(.{});

var server: httpz.ServerCtx(void, void) = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    server = try httpz.Server().init(allocator, .{ .port = settings.login_port });
    server.notFound(notFound);
    server.errorHandler(errorHandler);

    var router = server.router();
    router.post("/account/verify", handleAccountVerify);
    router.post("/account/register", handleAccountRegister);
    router.post("/app/init", handleAppInit);
    router.post("/char/list", handleCharList);
}

pub fn deinit() void {
    server.deinit();
}

pub fn tick() !void {
    rpmalloc.initThread() catch |e| {
        std.log.err("Login thread initialization failed: {}", .{e});
        return;
    };
    defer rpmalloc.deinitThread(true);

    try server.listen();
}

fn handleAccountRegister(req: *httpz.Request, res: *httpz.Response) !void {
    rpmalloc.initThread() catch {
        res.body = "<Error>Thread initialization failed</Error>";
        return;
    };
    defer rpmalloc.deinitThread(true);

    const query = try req.query();
    const name = query.get("name") orelse {
        res.body = "<Error>Invalid name</Error>";
        return;
    };
    const hwid = query.get("hwid") orelse {
        res.body = "<Error>Invalid HWID</Error>";
        return;
    };
    const email = query.get("email") orelse {
        res.body = "<Error>Invalid email</Error>";
        return;
    };
    const password = query.get("password") orelse {
        res.body = "<Error>Invalid password</Error>";
        return;
    };

    var login_data = db.LoginData.init(res.arena, email);
    defer login_data.deinit();

    email_exists: {
        _ = login_data.get(.account_id, u32) catch |e| {
            if (e == error.NoData) break :email_exists;
        };

        res.body = "<Error>Email already exists</Error>";
        return;
    }

    var names = db.Names.init(res.arena);
    defer names.deinit();

    _ = names.get(name) catch {
        res.body = "<Error>Name already exists</Error>";
        return;
    };

    const acc_id = db.nextAccId() catch {
        res.body = "<Error>Database failure</Error>";
        return;
    };
    try login_data.set(.account_id, u32, acc_id);
    try names.set(name, acc_id);

    var out: [256]u8 = undefined;
    const scrypt = std.crypto.pwhash.scrypt;
    const hashed_pass = try scrypt.strHash(password, .{
        .allocator = res.arena,
        .params = scrypt.Params.interactive,
        .encoding = .crypt,
    }, &out);
    try login_data.set(.hashed_password, []const u8, hashed_pass);

    var acc_data = db.AccountData.init(res.arena, acc_id);
    defer acc_data.deinit();

    const timestamp: u64 = @intCast(std.time.milliTimestamp());
    const empty_char_ids: []u32 = &[0]u32{};
    var ip_buf: [39]u8 = undefined;
    var stream = std.io.fixedBufferStream(&ip_buf);
    try req.address.format("", .{}, stream.writer());

    try acc_data.set(.email, []const u8, email);
    try acc_data.set(.name, []const u8, name);
    try acc_data.set(.hwid, []const u8, hwid);
    try acc_data.set(.ip, []const u8, stream.getWritten());
    try acc_data.set(.register_timestamp, u64, timestamp);
    try acc_data.set(.last_login_timestamp, u64, timestamp);
    try acc_data.set(.gold, u32, 0);
    try acc_data.set(.gems, u32, 0);
    try acc_data.set(.crowns, u32, 0);
    try acc_data.set(.rank, u8, if (acc_id == 0) 100 else 0);
    try acc_data.set(.next_char_id, u32, 0);
    try acc_data.set(.alive_char_ids, []u32, empty_char_ids);
    try acc_data.set(.max_char_slots, u32, 9);

    var writer = xml.DocWriter.create();
    defer writer.deinit();

    try writer.startDocument(.{});
    try acc_data.writeXml(writer);
    try writer.endDocument();

    res.body = try writer.childDoc().toMemory(res.arena);
}

fn handleAccountVerify(req: *httpz.Request, res: *httpz.Response) !void {
    rpmalloc.initThread() catch {
        res.body = "<Error>Thread initialization failed</Error>";
        return;
    };
    defer rpmalloc.deinitThread(true);

    const query = try req.query();
    const email = query.get("email") orelse {
        res.body = "<Error>Invalid email</Error>";
        return;
    };
    const password = query.get("password") orelse {
        res.body = "<Error>Invalid password</Error>";
        return;
    };

    const HasherError = std.crypto.pwhash.HasherError;
    const acc_id = db.login(email, password) catch |e| {
        res.body = switch (e) {
            error.NoData => "<Error>Invalid email</Error>",
            HasherError.PasswordVerificationFailed => "<Error>Invalid credentials</Error>",
            else => "<Error>Unknown error</Error>",
        };
        return;
    };

    var acc_data = db.AccountData.init(res.arena, acc_id);
    defer acc_data.deinit();

    var writer = xml.DocWriter.create();
    defer writer.deinit();

    try writer.startDocument(.{});
    try acc_data.writeXml(writer);
    try writer.endDocument();

    res.body = try writer.childDoc().toMemory(res.arena);
}

fn handleAppInit(_: *httpz.Request, res: *httpz.Response) !void {
    res.body = "<Error>Currently not implemented</Error>";
}

fn handleCharList(req: *httpz.Request, res: *httpz.Response) !void {
    rpmalloc.initThread() catch {
        res.body = "<Error>Thread initialization failed</Error>";
        return;
    };
    defer rpmalloc.deinitThread(true);

    const query = try req.query();
    const email = query.get("email") orelse {
        res.body = "<Error>Invalid email</Error>";
        return;
    };
    const password = query.get("password") orelse {
        res.body = "<Error>Invalid password</Error>";
        return;
    };

    const HasherError = std.crypto.pwhash.HasherError;
    const acc_id = db.login(email, password) catch |e| {
        res.body = switch (e) {
            error.NoData => "<Error>Invalid email</Error>",
            HasherError.PasswordVerificationFailed => "<Error>Invalid credentials</Error>",
            else => "<Error>Unknown error</Error>",
        };
        return;
    };

    var acc_data = db.AccountData.init(res.arena, acc_id);
    defer acc_data.deinit();

    var writer = xml.DocWriter.create();
    defer writer.deinit();

    try writer.startDocument(.{});
    try writer.startElement("Chars");

    try writer.writeAttribute("nextCharId", try std.fmt.allocPrintZ(res.arena, "{d}", .{try acc_data.get(.next_char_id, u32)}));
    try writer.writeAttribute("maxNumChars", try std.fmt.allocPrintZ(res.arena, "{d}", .{try acc_data.get(.max_char_slots, u32)}));

    // temp
    try writer.startElement("Servers");
    try writer.startElement("Server");
    try writer.writeElement("Name", settings.server_name);
    try writer.writeElement("DNS", settings.public_ip);
    try writer.writeElement("Port", try std.fmt.allocPrintZ(res.arena, "{d}", .{settings.game_port}));
    try writer.writeElement("Lat", "0");
    try writer.writeElement("Long", "0");
    try writer.writeElement("Usage", "0");
    try writer.writeElement("MaxPlayers", "500");
    try writer.writeElement("AdminOnly", "false");
    try writer.endElement();
    try writer.endElement();

    const char_ids = acc_data.get(.alive_char_ids, []const u32) catch &[0]u32{};
    for (char_ids) |char_id| {
        var char_data = db.CharacterData.init(res.arena, acc_id, char_id);
        defer char_data.deinit();

        try char_data.writeXml(writer);
    }

    try acc_data.writeXml(writer);

    try writer.endElement();
    try writer.endDocument();

    res.body = try writer.childDoc().toMemory(res.arena);
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
