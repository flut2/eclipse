const std = @import("std");
const settings = @import("settings.zig");

const u16_max = std.math.maxInt(u16);

var client: std.http.Client = undefined;
var header_pool: std.heap.MemoryPool([u16_max]u8) = undefined;
var body_pool: std.heap.MemoryPool([u16_max]u8) = undefined;

pub fn init(allocator: std.mem.Allocator) void {
    client = .{ .allocator = allocator };
    header_pool = std.heap.MemoryPool([u16_max]u8).init(allocator);
    body_pool = std.heap.MemoryPool([u16_max]u8).init(allocator);
}

pub fn deinit() void {
    client.deinit();
    header_pool.deinit();
    body_pool.deinit();
}

inline fn parseUri(comptime endpoint: []const u8) !std.Uri {
    return try std.Uri.parse(settings.app_engine_uri ++ endpoint);
}

pub fn sendCharList(email: []const u8, password: []const u8) ![]const u8 {
    const header_buffer = try header_pool.create();
    defer header_pool.destroy(header_buffer);

    var req = client.open(.POST, try parseUri("char/list"), .{ .server_header_buffer = header_buffer }) catch |e| {
        std.log.err("Could not send char/list (params: email={s}, password={s}): {}", .{ email, password, e });
        return "<Error />";
    };
    defer req.deinit();

    req.transfer_encoding = .chunked;
    try req.send(.{});

    const writer = req.writer();
    try writer.writeAll("email=");
    try writer.writeAll(email);
    try writer.writeAll("&password=");
    try writer.writeAll(password);

    try req.finish();
    try req.wait();

    const body_buffer = try body_pool.create();
    defer body_pool.destroy(body_buffer);
    const len = try req.readAll(body_buffer);
    return body_buffer[0..len];
}

pub fn sendCharDelete(email: []const u8, password: []const u8, char_id: []const u8) ![]const u8 {
    const header_buffer = try header_pool.create();
    defer header_pool.destroy(header_buffer);

    var req = client.open(.POST, try parseUri("char/delete"), .{ .server_header_buffer = header_buffer }) catch |e| {
        std.log.err("Could not send char/delete (params: email={s}, password={s}, charId={s}): {}", .{ email, password, char_id, e });
        return "<Error />";
    };
    defer req.deinit();

    req.transfer_encoding = .chunked;
    try req.send(.{});

    const writer = req.writer();
    try writer.writeAll("email=");
    try writer.writeAll(email);
    try writer.writeAll("&password=");
    try writer.writeAll(password);
    try writer.writeAll("&charId=");
    try writer.writeAll(char_id);

    try req.finish();
    try req.wait();

    const body_buffer = try body_pool.create();
    defer body_pool.destroy(body_buffer);
    const len = try req.readAll(body_buffer);
    return body_buffer[0..len];
}

pub fn sendAccountVerify(email: []const u8, password: []const u8) ![]const u8 {
    const header_buffer = try header_pool.create();
    defer header_pool.destroy(header_buffer);

    var req = client.open(.POST, try parseUri("account/verify"), .{ .server_header_buffer = header_buffer }) catch |e| {
        std.log.err("Could not send account/verify (params: email={s}, password={s}): {}", .{ email, password, e });
        return "<Error />";
    };
    defer req.deinit();

    req.transfer_encoding = .chunked;
    try req.send(.{});

    const writer = req.writer();
    try writer.writeAll("email=");
    try writer.writeAll(email);
    try writer.writeAll("&password=");
    try writer.writeAll(password);

    try req.finish();
    try req.wait();

    const body_buffer = try body_pool.create();
    defer body_pool.destroy(body_buffer);
    const len = try req.readAll(body_buffer);
    return body_buffer[0..len];
}

pub fn sendAccountRegister(email: []const u8, password: []const u8, username: []const u8) ![]const u8 {
    const header_buffer = try header_pool.create();
    defer header_pool.destroy(header_buffer);

    var req = client.open(.POST, try parseUri("account/register"), .{ .server_header_buffer = header_buffer }) catch |e| {
        std.log.err("Could not send account/register (params: email={s}, password={s}): {}", .{ email, password, e });
        return "<Error />";
    };
    defer req.deinit();

    req.transfer_encoding = .chunked;
    try req.send(.{});

    const writer = req.writer();
    try writer.writeAll("&email=");
    try writer.writeAll(email);
    try writer.writeAll("&password=");
    try writer.writeAll(password);
    try writer.writeAll("&username=");
    try writer.writeAll(username);

    try req.finish();
    try req.wait();

    const body_buffer = try body_pool.create();
    defer body_pool.destroy(body_buffer);
    const len = try req.readAll(body_buffer);
    return body_buffer[0..len];
}

pub fn sendAccountChangePassword(email: []const u8, password: []const u8, newPassword: []const u8) ![]const u8 {
    const header_buffer = try header_pool.create();
    defer header_pool.destroy(header_buffer);

    var req = client.open(.POST, try parseUri("account/changePassword"), .{ .server_header_buffer = header_buffer }) catch |e| {
        std.log.err("Could not send account/changePassword (params: email={s}, password={s}, newPassword={s}): {}", .{ email, password, newPassword, e });
        return "<Error />";
    };
    defer req.deinit();

    req.transfer_encoding = .chunked;
    try req.send(.{});

    const writer = req.writer();
    try writer.writeAll("email=");
    try writer.writeAll(email);
    try writer.writeAll("&password=");
    try writer.writeAll(password);
    try writer.writeAll("&newPassword=");
    try writer.writeAll(newPassword);

    try req.finish();
    try req.wait();

    const body_buffer = try body_pool.create();
    defer body_pool.destroy(body_buffer);
    const len = try req.readAll(body_buffer);
    return body_buffer[0..len];
}

pub fn sendAppInit() ![]const u8 {
    const header_buffer = try header_pool.create();
    defer header_pool.destroy(header_buffer);

    var req = client.open(.POST, try parseUri("app/init"), .{ .server_header_buffer = header_buffer }) catch |e| {
        std.log.err("Could not send app/init: {}", .{e});
        return "<Error />";
    };
    defer req.deinit();

    req.transfer_encoding = .chunked;
    try req.send(.{});

    try req.finish();
    try req.wait();

    const body_buffer = try body_pool.create();
    defer body_pool.destroy(body_buffer);
    const len = try req.readAll(body_buffer);
    return body_buffer[0..len];
}
