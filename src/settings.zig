const std = @import("std");
const glfw = @import("mach-glfw");
const builtin = @import("builtin");
const assets = @import("assets.zig");
const ini = @import("ini");
const main = @import("main.zig");

pub const LogType = enum(u8) {
    all = 0,
    all_non_tick = 1,
    c2s = 2,
    c2s_non_tick = 3,
    c2s_tick = 4,
    s2c = 5,
    s2c_non_tick = 6,
    s2c_tick = 7,
    off = 255,
};

pub const CursorType = enum(u8) {
    basic = 0,
    royal = 1,
    ranger = 2,
    aztec = 3,
    fiery = 4,
    target_enemy = 5,
    target_ally = 6,
};

pub const AaType = enum(u8) {
    none = 0,
    fxaa = 1, // not implemented yet
    msaa2x = 2,
    msaa4x = 3,
};

pub const Button = union(enum) {
    key: glfw.Key,
    mouse: glfw.MouseButton,

    pub fn getKey(self: Button) glfw.Key {
        switch (self) {
            .key => |key| return key,
            .mouse => return .unknown,
        }
    }

    pub fn getMouse(self: Button) glfw.MouseButton {
        switch (self) {
            .key => return .eight,
            .mouse => |mouse| return mouse,
        }
    }

    pub inline fn getPrefix(self: Button) []const u8 {
        return switch (self) {
            .key => "",
            .mouse => "mouse_",
        };
    }

    pub inline fn getTagName(self: Button) []const u8 {
        return switch (self) {
            .key => |key| @tagName(key),
            .mouse => |mouse| @tagName(mouse),
        };
    }
};

const key_name_map = std.ComptimeStringMap(*Button, .{
    .{ "move_left", &move_left },
    .{ "move_right", &move_right },
    .{ "move_up", &move_up },
    .{ "move_down", &move_down },
    .{ "rotate_left", &rotate_left },
    .{ "rotate_right", &rotate_right },
    .{ "interact", &interact },
    .{ "options", &options },
    .{ "escape", &escape },
    .{ "chat_up", &chat_up },
    .{ "chat_down", &chat_down },
    .{ "walk", &walk },
    .{ "reset_camera", &reset_camera },
    .{ "toggle_perf_stats", &toggle_perf_stats },
    .{ "chat", &chat },
    .{ "chat_cmd", &chat_cmd },
    .{ "respond", &respond },
    .{ "toggle_centering", &toggle_centering },
    .{ "toggle_stats", &toggle_stats },
    .{ "shoot", &shoot },
    .{ "ability_1", &ability_1 },
    .{ "ability_2", &ability_2 },
    .{ "ability_3", &ability_3 },
    .{ "ultimate_ability", &ultimate_ability },
});

const bool_name_map = std.ComptimeStringMap(*bool, .{
    .{ "enable_lights", &enable_lights },
    .{ "enable_vsync", &enable_vsync },
    .{ "save_email", &save_email },
});

const float_name_map = std.ComptimeStringMap(*f32, .{
    .{ "sfx_volume", &sfx_volume },
    .{ "music_volume", &music_volume },
    .{ "fps_cap", &fps_cap },
});

const int_name_map = std.ComptimeStringMap(*i32, .{});

const string_name_map = std.ComptimeStringMap(*[]const u8, .{
    .{ "email", &email },
});

pub const build_version = "0.5";
pub const app_engine_uri = "http://127.0.0.1:8080/";
pub const log_packets = LogType.off;
pub const print_atlas = false;
pub const print_ui_atlas = false;
pub const rotate_speed = 2.0 / @as(f32, std.time.us_per_s);
pub const enable_tracy = false;
pub const unset_key_tex_idx = 0x68;

pub var interact_key_tex: assets.AtlasData = undefined;
pub var key_tex_map: std.AutoHashMap(Button, u16) = undefined;

pub var move_left = Button{ .key = .a };
pub var move_right = Button{ .key = .d };
pub var move_up = Button{ .key = .w };
pub var move_down = Button{ .key = .s };
pub var rotate_left = Button{ .key = .q };
pub var rotate_right = Button{ .key = .e };
pub var interact = Button{ .key = .r };
pub var options = Button{ .key = .escape };
pub var escape = Button{ .key = .tab };
pub var chat_up = Button{ .key = .page_up };
pub var chat_down = Button{ .key = .page_down };
pub var walk = Button{ .key = .left_shift };
pub var reset_camera = Button{ .key = .z };
pub var toggle_perf_stats = Button{ .key = .F3 };
pub var chat = Button{ .key = .enter };
pub var chat_cmd = Button{ .key = .slash };
pub var respond = Button{ .key = .F2 };
pub var toggle_centering = Button{ .key = .x };
pub var shoot = Button{ .mouse = .left };
pub var ability_1 = Button{ .key = .one };
pub var ability_2 = Button{ .key = .two };
pub var ability_3 = Button{ .key = .three };
pub var ultimate_ability = Button{ .key = .four };
pub var toggle_stats = Button{ .key = .b };
pub var sfx_volume: f32 = 0.33;
pub var music_volume: f32 = 0.1;
pub var fps_cap: f32 = 360.0;
pub var fps_ns: u64 = @intFromFloat(@as(comptime_float, std.time.ns_per_s) / 360.0 * 1.5);
pub var enable_lights = true;
pub var enable_vsync = true;
pub var stats_enabled = true;
pub var save_email = true;
pub var cursor_type = CursorType.aztec;
pub var aa_type = AaType.none;
pub var email: []const u8 = "";

pub fn init(allocator: std.mem.Allocator) !void {
    key_tex_map = std.AutoHashMap(Button, u16).init(allocator);
    try key_tex_map.put(.{ .mouse = .left }, 0x2e);
    try key_tex_map.put(.{ .mouse = .right }, 0x3b);
    try key_tex_map.put(.{ .mouse = .middle }, 0x3a);
    try key_tex_map.put(.{ .mouse = .four }, 0x6c);
    try key_tex_map.put(.{ .mouse = .five }, 0x6d);
    try key_tex_map.put(.{ .key = .zero }, 0x00);
    try key_tex_map.put(.{ .key = .one }, 0x04);
    try key_tex_map.put(.{ .key = .two }, 0x05);
    try key_tex_map.put(.{ .key = .three }, 0x06);
    try key_tex_map.put(.{ .key = .four }, 0x07);
    try key_tex_map.put(.{ .key = .five }, 0x08);
    try key_tex_map.put(.{ .key = .six }, 0x10);
    try key_tex_map.put(.{ .key = .seven }, 0x11);
    try key_tex_map.put(.{ .key = .eight }, 0x12);
    try key_tex_map.put(.{ .key = .nine }, 0x13);
    try key_tex_map.put(.{ .key = .kp_0 }, 0x5b);
    try key_tex_map.put(.{ .key = .kp_1 }, 0x5c);
    try key_tex_map.put(.{ .key = .kp_2 }, 0x5d);
    try key_tex_map.put(.{ .key = .kp_3 }, 0x5e);
    try key_tex_map.put(.{ .key = .kp_4 }, 0x5f);
    try key_tex_map.put(.{ .key = .kp_5 }, 0x60);
    try key_tex_map.put(.{ .key = .kp_6 }, 0x61);
    try key_tex_map.put(.{ .key = .kp_7 }, 0x62);
    try key_tex_map.put(.{ .key = .kp_8 }, 0x63);
    try key_tex_map.put(.{ .key = .kp_9 }, 0x64);
    try key_tex_map.put(.{ .key = .F1 }, 0x44);
    try key_tex_map.put(.{ .key = .F2 }, 0x45);
    try key_tex_map.put(.{ .key = .F3 }, 0x46);
    try key_tex_map.put(.{ .key = .F4 }, 0x47);
    try key_tex_map.put(.{ .key = .F5 }, 0x48);
    try key_tex_map.put(.{ .key = .F6 }, 0x50);
    try key_tex_map.put(.{ .key = .F7 }, 0x51);
    try key_tex_map.put(.{ .key = .F8 }, 0x52);
    try key_tex_map.put(.{ .key = .F9 }, 0x53);
    try key_tex_map.put(.{ .key = .F10 }, 0x01);
    try key_tex_map.put(.{ .key = .F11 }, 0x02);
    try key_tex_map.put(.{ .key = .F12 }, 0x03);
    try key_tex_map.put(.{ .key = .a }, 0x14);
    try key_tex_map.put(.{ .key = .b }, 0x22);
    try key_tex_map.put(.{ .key = .c }, 0x27);
    try key_tex_map.put(.{ .key = .d }, 0x32);
    try key_tex_map.put(.{ .key = .e }, 0x34);
    try key_tex_map.put(.{ .key = .f }, 0x54);
    try key_tex_map.put(.{ .key = .g }, 0x55);
    try key_tex_map.put(.{ .key = .h }, 0x56);
    try key_tex_map.put(.{ .key = .i }, 0x58);
    try key_tex_map.put(.{ .key = .j }, 0x3f);
    try key_tex_map.put(.{ .key = .k }, 0x4a);
    try key_tex_map.put(.{ .key = .l }, 0x4b);
    try key_tex_map.put(.{ .key = .m }, 0x4c);
    try key_tex_map.put(.{ .key = .n }, 0x3d);
    try key_tex_map.put(.{ .key = .o }, 0x41);
    try key_tex_map.put(.{ .key = .p }, 0x42);
    try key_tex_map.put(.{ .key = .q }, 0x19);
    try key_tex_map.put(.{ .key = .r }, 0x1c);
    try key_tex_map.put(.{ .key = .s }, 0x1d);
    try key_tex_map.put(.{ .key = .t }, 0x49);
    try key_tex_map.put(.{ .key = .u }, 0x43);
    try key_tex_map.put(.{ .key = .v }, 0x1f);
    try key_tex_map.put(.{ .key = .w }, 0x0a);
    try key_tex_map.put(.{ .key = .x }, 0x0c);
    try key_tex_map.put(.{ .key = .y }, 0x0d);
    try key_tex_map.put(.{ .key = .z }, 0x0e);
    try key_tex_map.put(.{ .key = .up }, 0x20);
    try key_tex_map.put(.{ .key = .down }, 0x16);
    try key_tex_map.put(.{ .key = .left }, 0x17);
    try key_tex_map.put(.{ .key = .right }, 0x18);
    try key_tex_map.put(.{ .key = .left_shift }, 0x0f);
    try key_tex_map.put(.{ .key = .right_shift }, 0x09);
    try key_tex_map.put(.{ .key = .left_bracket }, 0x25);
    try key_tex_map.put(.{ .key = .right_bracket }, 0x26);
    try key_tex_map.put(.{ .key = .left_control }, 0x31);
    try key_tex_map.put(.{ .key = .right_control }, 0x31);
    try key_tex_map.put(.{ .key = .left_alt }, 0x15);
    try key_tex_map.put(.{ .key = .right_alt }, 0x15);
    try key_tex_map.put(.{ .key = .comma }, 0x65);
    try key_tex_map.put(.{ .key = .period }, 0x66);
    try key_tex_map.put(.{ .key = .slash }, 0x67);
    try key_tex_map.put(.{ .key = .backslash }, 0x29);
    try key_tex_map.put(.{ .key = .semicolon }, 0x1e);
    try key_tex_map.put(.{ .key = .minus }, 0x2d);
    try key_tex_map.put(.{ .key = .equal }, 0x2a);
    try key_tex_map.put(.{ .key = .tab }, 0x4f);
    try key_tex_map.put(.{ .key = .space }, 0x39);
    try key_tex_map.put(.{ .key = .backspace }, 0x23);
    try key_tex_map.put(.{ .key = .enter }, 0x36);
    try key_tex_map.put(.{ .key = .delete }, 0x33);
    try key_tex_map.put(.{ .key = .end }, 0x35);
    try key_tex_map.put(.{ .key = .print_screen }, 0x2c);
    try key_tex_map.put(.{ .key = .insert }, 0x3e);
    try key_tex_map.put(.{ .key = .escape }, 0x40);
    try key_tex_map.put(.{ .key = .home }, 0x57);
    try key_tex_map.put(.{ .key = .page_up }, 0x59);
    try key_tex_map.put(.{ .key = .page_down }, 0x5a);
    try key_tex_map.put(.{ .key = .caps_lock }, 0x28);
    try key_tex_map.put(.{ .key = .kp_add }, 0x2b);
    try key_tex_map.put(.{ .key = .kp_subtract }, 0x6b);
    try key_tex_map.put(.{ .key = .kp_multiply }, 0x21);
    try key_tex_map.put(.{ .key = .kp_divide }, 0x6a);
    try key_tex_map.put(.{ .key = .kp_decimal }, 0x69);
    try key_tex_map.put(.{ .key = .kp_enter }, 0x38);

    try key_tex_map.put(.{ .key = .left_super }, if (builtin.os.tag == .windows) 0x0b else 0x30);
    try key_tex_map.put(.{ .key = .right_super }, if (builtin.os.tag == .windows) 0x0b else 0x30);

    try parseSettings(allocator);
}

pub fn getKeyTexture(button: Button) assets.AtlasData {
    const tex_list = assets.atlas_data.get("key_indicators") orelse std.debug.panic("Key texture parsing failed, the key_indicators sheet is missing", .{});
    return tex_list[key_tex_map.get(button) orelse unset_key_tex_idx];
}

pub fn deinit(allocator: std.mem.Allocator) void {
    save() catch |e| {
        std.log.err("Settings save failed: {}", .{e});
    };

    allocator.free(email);
    key_tex_map.deinit();
}

fn parseSettings(allocator: std.mem.Allocator) !void {
    if (std.fs.cwd().access("settings.ini", .{})) |_| {} else |_| return;
    
    const file = try std.fs.cwd().openFile("settings.ini", .{});
    defer file.close();

    var parser = ini.parse(allocator, file.reader());
    defer parser.deinit();

    var writer = std.io.getStdOut().writer();
    while (try parser.next()) |record| {
        switch (record) {
            .property => |kv| {
                if (key_name_map.get(kv.key)) |button| {
                    const mouse = std.mem.indexOf(u8, kv.value, "mouse_");
                    if (mouse) |mouse_idx| {
                        const mouse_enum = std.meta.stringToEnum(glfw.MouseButton, kv.value[mouse_idx + "mouse_".len ..]);
                        if (mouse_enum == null) {
                            std.log.err("Mouse parsing for {s} failed. Using the default of mouse eight", .{kv.value});
                            button.* = .{ .mouse = .eight };
                            continue;
                        }

                        button.* = .{ .mouse = mouse_enum.? };
                        continue;
                    }

                    const key_enum = std.meta.stringToEnum(glfw.Key, kv.value);
                    if (key_enum == null) {
                        std.log.err("Key parsing for {s} failed. Using the default of unknown key", .{kv.value});
                        button.* = .{ .key = .unknown };
                        continue;
                    }

                    button.* = .{ .key = key_enum.? };
                    continue;
                } else if (bool_name_map.get(kv.key)) |bool_var| {
                    if (std.mem.eql(u8, kv.value, "true") or std.mem.eql(u8, kv.value, "false")) {
                        bool_var.* = std.mem.eql(u8, kv.value, "true");
                        continue;
                    }

                    try writer.print("Invalid value ({s}) specified for bool type {s}. Using the default of 'false'\n", .{ kv.value, kv.key });
                    bool_var.* = false;
                    continue;
                } else if (float_name_map.get(kv.key)) |float_var| {
                    const value = std.fmt.parseFloat(f32, kv.value) catch blk: {
                        try writer.print("Invalid value ({s}) specified for float type {s}. Using the default of '0.0'\n", .{ kv.value, kv.key });
                        break :blk 0.0;
                    };

                    float_var.* = value;
                    if (std.mem.eql(u8, kv.key, "fps_cap"))
                        fps_ns = @intFromFloat(std.time.ns_per_s / value * 1.5);
                    continue;
                } else if (int_name_map.get(kv.key)) |int_var| {
                    const value = std.fmt.parseInt(i32, kv.value, 0) catch blk: {
                        try writer.print("Invalid value ({s}) specified for int type {s}. Using the default of '0'\n", .{ kv.value, kv.key });
                        break :blk 0;
                    };

                    int_var.* = value;
                    continue;
                } else if (string_name_map.get(kv.key)) |string_var| {
                    if (string_var.len > 0)
                        allocator.free(string_var.*);
                    string_var.* = allocator.dupe(u8, kv.value) catch "";
                    continue;
                } else if (std.mem.eql(u8, kv.key, "aa_type")) {
                    const value = std.meta.stringToEnum(AaType, kv.value) orelse blk: {
                        try writer.print("Invalid value ({s}) specified for anti-alias type {s}. Using the default of 'none'\n", .{ kv.value, kv.key });
                        break :blk .none;
                    };

                    aa_type = value;
                    continue;
                } else if (std.mem.eql(u8, kv.key, "cursor_type")) {
                    const value = std.meta.stringToEnum(CursorType, kv.value) orelse blk: {
                        try writer.print("Invalid value ({s}) specified for cursor type {s}. Using the default of 'basic'\n", .{ kv.value, kv.key });
                        break :blk .basic;
                    };

                    cursor_type = value;
                    continue;
                } else {}
            },
            else => continue,
        }
    }
}

pub fn save() !void {
    const file = try std.fs.cwd().createFile("settings.ini", .{});
    defer file.close();

    var buf: [2048]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    _ = try stream.write("[Keys]");
    for (key_name_map.kvs) |kv| {
        try stream.writer().print("\n{s}={s}{s}", .{ kv.key, kv.value.getPrefix(), kv.value.getTagName() });
    }
    _ = try file.write(stream.getWritten());

    try stream.seekTo(0);
    _ = try stream.write("\n[Misc]");
    for (bool_name_map.kvs) |kv| {
        try stream.writer().print("\n{s}={s}", .{ kv.key, if (kv.value.*) "true" else "false" });
    }
    for (float_name_map.kvs) |kv| {
        try stream.writer().print("\n{s}={d:.2}", .{ kv.key, kv.value.* });
    }
    // Uncomment when int settings are added. Would error otherwise
    // for (int_name_map.kvs) |kv| {
    //     try stream.writer().print("\n{s}={d}", .{kv.key, kv.value.*});
    // }
    for (string_name_map.kvs) |kv| {
        try stream.writer().print("\n{s}={s}", .{ kv.key, kv.value.* });
    }
    _ = try stream.writer().print("\naa_type={s}", .{@tagName(aa_type)});
    _ = try stream.writer().print("\ncursor_type={s}", .{@tagName(cursor_type)});
    _ = try file.write(stream.getWritten());
}

pub fn resetToDefault() void {
    move_left = .{ .key = .a };
    move_right = .{ .key = .d };
    move_up = .{ .key = .w };
    move_down = .{ .key = .s };
    rotate_left = .{ .key = .q };
    rotate_right = .{ .key = .e };
    interact = .{ .key = .r };
    options = .{ .key = .escape };
    escape = .{ .key = .tab };
    chat_up = .{ .key = .page_up };
    chat_down = .{ .key = .page_down };
    walk = .{ .key = .left_shift };
    reset_camera = .{ .key = .z };
    toggle_perf_stats = .{ .key = .F3 };
    chat = .{ .key = .enter };
    chat_cmd = .{ .key = .slash };
    respond = .{ .key = .F2 };
    toggle_centering = .{ .key = .x };
    shoot = .{ .mouse = .left };
    ability_1 = .{ .key = .one };
    ability_2 = .{ .key = .two };
    ability_3 = .{ .key = .three };
    ultimate_ability = .{ .key = .four };
    sfx_volume = 0.33;
    music_volume = 0.1;
    enable_lights = true;
    enable_vsync = true;
    fps_cap = 360.0;
    fps_ns = @intFromFloat(@as(comptime_float, std.time.ns_per_s) / 360.0 * 1.5);
    cursor_type = .aztec;
    aa_type = .msaa4x;
    save_email = true;
}
