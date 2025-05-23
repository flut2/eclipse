const std = @import("std");
const builtin = @import("builtin");

const build_options = @import("options");
const shared = @import("shared");
const network_data = shared.network_data;

const assets = @import("../../assets.zig");
const main = @import("../../main.zig");
const dialog = @import("../dialogs/dialog.zig");
const Button = @import("../elements/Button.zig");
const element = @import("../elements/element.zig");
const Input = @import("../elements/Input.zig");
const Text = @import("../elements/Text.zig");
const ui_systems = @import("../systems.zig");

const AccountRegisterScreen = @This();
username_text: *Text = undefined,
username_input: *Input = undefined,
email_text: *Text = undefined,
email_input: *Input = undefined,
password_text: *Text = undefined,
password_input: *Input = undefined,
password_repeat_text: *Text = undefined,
password_repeat_input: *Input = undefined,
confirm_button: *Button = undefined,
back_button: *Button = undefined,

pub fn init(self: *AccountRegisterScreen) !void {
    try main.rpc_client.setPresence(.{
        .assets = .{
            .large_image = .create("logo"),
            .large_text = .create("Alpha v" ++ build_options.version),
        },
        .state = .create("Register Screen"),
        .timestamps = .{ .start = main.rpc_start },
    });

    const input_w = 300;
    const input_h = 50;

    const input_data_base = assets.getUiData("text_input", 0);
    const input_data_hover = assets.getUiData("text_input", 1);
    const input_data_press = assets.getUiData("text_input", 2);

    const x_offset = (main.camera.width - input_w) / 2;
    var y_offset: f32 = main.camera.height / 7.2;

    self.username_text = try element.create(Text, .{
        .base = .{
            .x = x_offset,
            .y = y_offset,
        },
        .text_data = .{
            .text = "Username",
            .size = 20,
            .text_type = .bold,
            .hori_align = .middle,
            .vert_align = .middle,
            .max_width = input_w,
            .max_height = input_h,
        },
    });

    y_offset += 50;

    const cursor_data = assets.getUiData("chatbox_cursor", 0);
    self.username_input = try element.create(Input, .{
        .base = .{
            .x = x_offset,
            .y = y_offset,
        },
        .text_inlay_x = 9,
        .text_inlay_y = 8,
        .image_data = .fromNineSlices(input_data_base, input_data_hover, input_data_press, input_w, input_h, 53, 20, 1, 1, 1.0),
        .cursor_image_data = .{ .normal = .{ .atlas_data = cursor_data } },
        .text_data = .{
            .text = "",
            .size = 20,
            .text_type = .bold,
            .max_chars = 256,
            .handle_special_chars = false,
        },
    });

    y_offset += 50;

    self.email_text = try element.create(Text, .{
        .base = .{
            .x = x_offset,
            .y = y_offset,
        },
        .text_data = .{
            .text = "E-mail",
            .size = 20,
            .text_type = .bold,
            .hori_align = .middle,
            .vert_align = .middle,
            .max_width = input_w,
            .max_height = input_h,
        },
    });

    y_offset += 50;

    self.email_input = try element.create(Input, .{
        .base = .{
            .x = x_offset,
            .y = y_offset,
        },
        .text_inlay_x = 9,
        .text_inlay_y = 8,
        .image_data = .fromNineSlices(input_data_base, input_data_hover, input_data_press, input_w, input_h, 53, 20, 1, 1, 1.0),
        .cursor_image_data = .{ .normal = .{ .atlas_data = cursor_data } },
        .text_data = .{
            .text = "",
            .size = 20,
            .text_type = .bold,
            .max_chars = 256,
            .handle_special_chars = false,
        },
    });

    y_offset += 50;

    self.password_text = try element.create(Text, .{
        .base = .{
            .x = x_offset,
            .y = y_offset,
        },
        .text_data = .{
            .text = "Password",
            .size = 20,
            .text_type = .bold,
            .hori_align = .middle,
            .vert_align = .middle,
            .max_width = input_w,
            .max_height = input_h,
        },
    });

    y_offset += 50;

    self.password_input = try element.create(Input, .{
        .base = .{
            .x = x_offset,
            .y = y_offset,
        },
        .text_inlay_x = 9,
        .text_inlay_y = 8,
        .image_data = .fromNineSlices(input_data_base, input_data_hover, input_data_press, input_w, input_h, 53, 20, 1, 1, 1.0),
        .cursor_image_data = .{ .normal = .{ .atlas_data = cursor_data } },
        .text_data = .{
            .text = "",
            .size = 20,
            .text_type = .bold,
            .password = true,
            .max_chars = 256,
            .handle_special_chars = false,
        },
    });

    y_offset += 50;

    self.password_repeat_text = try element.create(Text, .{
        .base = .{
            .x = x_offset,
            .y = y_offset,
        },
        .text_data = .{
            .text = "Confirm Password",
            .size = 20,
            .text_type = .bold,
            .hori_align = .middle,
            .vert_align = .middle,
            .max_width = input_w,
            .max_height = input_h,
        },
    });

    y_offset += 50;

    self.password_repeat_input = try element.create(Input, .{
        .base = .{
            .x = x_offset,
            .y = y_offset,
        },
        .text_inlay_x = 9,
        .text_inlay_y = 8,
        .image_data = .fromNineSlices(input_data_base, input_data_hover, input_data_press, input_w, input_h, 53, 20, 1, 1, 1.0),
        .cursor_image_data = .{ .normal = .{ .atlas_data = cursor_data } },
        .text_data = .{
            .text = "",
            .size = 20,
            .text_type = .bold,
            .password = true,
            .max_chars = 256,
            .handle_special_chars = false,
        },
    });

    y_offset += 75;

    const button_data_base = assets.getUiData("button_base", 0);
    const button_data_hover = assets.getUiData("button_hover", 0);
    const button_data_press = assets.getUiData("button_press", 0);
    const button_width = 100;
    const button_height = 35;

    self.confirm_button = try element.create(Button, .{
        .base = .{
            .x = x_offset + (input_w - (button_width * 2)) / 2 - 12.5,
            .y = y_offset,
        },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 26, 19, 1, 1, 1.0),
        .text_data = .{
            .text = "Confirm",
            .size = 16,
            .text_type = .bold,
        },
        .userdata = self,
        .pressCallback = registerCallback,
    });

    self.back_button = try element.create(Button, .{
        .base = .{
            .x = self.confirm_button.base.x + button_width + 25,
            .y = y_offset,
        },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 26, 19, 1, 1, 1.0),
        .text_data = .{
            .text = "Back",
            .size = 16,
            .text_type = .bold,
        },
        .pressCallback = backCallback,
    });
}

pub fn deinit(self: *AccountRegisterScreen) void {
    element.destroy(self.username_text);
    element.destroy(self.username_input);
    element.destroy(self.email_text);
    element.destroy(self.email_input);
    element.destroy(self.password_text);
    element.destroy(self.password_input);
    element.destroy(self.password_repeat_input);
    element.destroy(self.password_repeat_text);
    element.destroy(self.confirm_button);
    element.destroy(self.back_button);

    main.allocator.destroy(self);
}

pub fn resize(self: *AccountRegisterScreen, w: f32, h: f32) void {
    self.username_text.base.x = (w - 300) / 2;
    self.username_text.base.y = h / 7.2;
    self.username_input.base.x = self.username_text.base.x;
    self.username_input.base.y = self.username_text.base.y + 50;
    self.email_text.base.x = self.username_input.base.x;
    self.email_text.base.y = self.username_input.base.y + 50;
    self.email_input.base.x = self.email_text.base.x;
    self.email_input.base.y = self.email_text.base.y + 50;
    self.password_text.base.x = self.email_input.base.x;
    self.password_text.base.y = self.email_input.base.y + 50;
    self.password_input.base.x = self.password_text.base.x;
    self.password_input.base.y = self.password_text.base.y + 50;
    self.password_repeat_text.base.x = self.password_input.base.x;
    self.password_repeat_text.base.y = self.password_input.base.y + 50;
    self.password_repeat_input.base.x = self.password_repeat_text.base.x;
    self.password_repeat_input.base.y = self.password_repeat_text.base.y + 50;
    self.confirm_button.base.x = self.password_repeat_input.base.x + 100 / 2 - 12.5;
    self.confirm_button.base.y = self.password_repeat_input.base.y + 75;
    self.back_button.base.x = self.confirm_button.base.x + 125;
    self.back_button.base.y = self.confirm_button.base.y;
}

pub fn update(_: *AccountRegisterScreen, _: i64, _: f32) !void {}

fn getHwid(allocator: std.mem.Allocator) ![]const u8 {
    return switch (builtin.os.tag) {
        .windows => {
            const windows = std.os.windows;
            const sub_key = try std.unicode.utf8ToUtf16LeAllocZ(allocator, "SOFTWARE\\Microsoft\\Cryptography");
            defer allocator.free(sub_key);
            const value = try std.unicode.utf8ToUtf16LeAllocZ(allocator, "MachineGuid");
            defer allocator.free(value);
            var buf: [128:0]u16 = undefined;
            var len: u32 = 128;
            _ = windows.advapi32.RegGetValueW(
                windows.HKEY_LOCAL_MACHINE,
                sub_key,
                value,
                windows.advapi32.RRF.SUBKEY_WOW6464KEY | windows.advapi32.RRF.RT_REG_SZ,
                null,
                &buf,
                &len,
            );
            return try std.unicode.utf16LeToUtf8Alloc(allocator, std.mem.span(@as([*:0]const u16, &buf)));
        },
        .macos => {
            const proc = std.process.Child.run(.{
                .allocator = allocator,
                .argv = &.{ "ioreg", "-rd1", "-c", "IOPlatformExpertDevice" },
            }) catch @panic("Failed to spawn child process");
            defer {
                allocator.free(proc.stdout);
                allocator.free(proc.stderr);
            }
            var line_split = std.mem.splitScalar(u8, proc.stdout, '\n');
            while (line_split.next()) |line| {
                if (std.mem.indexOf(u8, line, "IOPlatformUUID") != null) {
                    const left_bound = (std.mem.indexOf(u8, line, " = \"") orelse @panic("No HWID found")) + " = \"".len;
                    const right_bound = std.mem.lastIndexOfScalar(u8, line, '"') orelse @panic("No HWID found");
                    return allocator.dupe(u8, line[left_bound..right_bound]) catch main.oomPanic();
                }
            }
            @panic("No HWID found");
        },
        .linux => {
            tryVar: {
                const file = std.fs.cwd().openFile("/var/lib/dbus/machine-id", .{}) catch break :tryVar;
                defer file.close();

                var buf: [256]u8 = undefined;
                const size = try file.readAll(&buf);
                return std.mem.trim(u8, std.mem.trim(u8, buf[0..size], " "), "\n");
            }

            tryEtc: {
                const file = std.fs.cwd().openFile("/etc/machine-id", .{}) catch break :tryEtc;
                defer file.close();

                var buf: [256]u8 = undefined;
                const size = try file.readAll(&buf);
                return std.mem.trim(u8, std.mem.trim(u8, buf[0..size], " "), "\n");
            }

            @panic("No hwid found");
        },
        else => @compileError("Unsupported OS"),
    };
}

fn registerCallback(ud: ?*anyopaque) void {
    const current_screen: *AccountRegisterScreen = @alignCast(@ptrCast(ud.?));
    const email = main.account_arena_allocator.dupe(u8, current_screen.email_input.text_data.text) catch main.oomPanic();
    const hwid = getHwid(main.account_arena_allocator) catch {
        ui_systems.switchScreen(.main_menu);
        dialog.showDialog(.text, .{
            .title = "Register Failed",
            .body = "Unable to retrieve HWID",
        });
        return;
    };
    defer if (builtin.os.tag == .windows or builtin.os.tag == .macos) main.account_arena_allocator.free(hwid);
    main.current_account = .{ .email = email, .token = 0 };
    main.login_server.sendPacket(.{ .register = .{
        .name = current_screen.username_input.text_data.text,
        .email = email,
        .password = current_screen.password_input.text_data.text,
        .hwid = hwid,
    } });
}

fn backCallback(_: ?*anyopaque) void {
    ui_systems.switchScreen(.main_menu);
}
