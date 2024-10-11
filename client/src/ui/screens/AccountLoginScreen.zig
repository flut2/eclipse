const std = @import("std");
const shared = @import("shared");
const requests = shared.requests;
const network_data = shared.network_data;
const element = @import("../elements/element.zig");
const assets = @import("../../assets.zig");
const main = @import("../../main.zig");
const ui_systems = @import("../systems.zig");
const input = @import("../../input.zig");
const dialog = @import("../dialogs/dialog.zig");
const build_options = @import("options");

const AccountLoginScreen = @This();
const Text = @import("../elements/Text.zig");
const Input = @import("../elements/Input.zig");
const Button = @import("../elements/Button.zig");
const Toggle = @import("../elements/Toggle.zig");

allocator: std.mem.Allocator = undefined,

email_text: *Text = undefined,
email_input: *Input = undefined,
password_text: *Text = undefined,
password_input: *Input = undefined,
login_button: *Button = undefined,
register_button: *Button = undefined,
remember_login_text: *Text = undefined,
remember_login_toggle: *Toggle = undefined,

pub fn init(self: *AccountLoginScreen) !void {
    const input_w = 300;
    const input_h = 50;
    const input_data_base = assets.getUiData("text_input_base", 0);
    const input_data_hover = assets.getUiData("text_input_hover", 0);
    const input_data_press = assets.getUiData("text_input_press", 0);

    const cursor_data = assets.getUiData("chatbox_cursor", 0);
    self.email_input = try element.create(self.allocator, Input, .{
        .base = .{
            .x = (main.camera.width - input_w) / 2,
            .y = main.camera.height / 3.6,
            .allocator = self.allocator,
        },
        .text_inlay_x = 9,
        .text_inlay_y = 8,
        .image_data = .fromNineSlices(input_data_base, input_data_hover, input_data_press, input_w, input_h, 12, 12, 2, 2, 1.0),
        .cursor_image_data = .{ .normal = .{ .atlas_data = cursor_data } },
        .text_data = .{
            .text = "",
            .size = 20,
            .text_type = .bold,
            .max_chars = 256,
            .handle_special_chars = false,
        },
    });

    input.selected_input_field = self.email_input;

    self.email_text = try element.create(self.allocator, Text, .{
        .base = .{
            .x = self.email_input.base.x,
            .y = self.email_input.base.y - 50,
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

    self.password_input = try element.create(self.allocator, Input, .{
        .base = .{
            .x = self.email_input.base.x,
            .y = self.email_input.base.y + 150,
            .allocator = self.allocator,
        },
        .text_inlay_x = 9,
        .text_inlay_y = 8,
        .image_data = .fromNineSlices(input_data_base, input_data_hover, input_data_press, input_w, input_h, 12, 12, 2, 2, 1.0),
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

    self.password_text = try element.create(self.allocator, Text, .{
        .base = .{
            .x = self.password_input.base.x,
            .y = self.password_input.base.y - 50,
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

    const check_box_base_on = assets.getUiData("checked_box_base", 0);
    const check_box_hover_on = assets.getUiData("checked_box_hover", 0);
    const check_box_press_on = assets.getUiData("checked_box_press", 0);
    const check_box_base_off = assets.getUiData("unchecked_box_base", 0);
    const check_box_hover_off = assets.getUiData("unchecked_box_hover", 0);
    const check_box_press_off = assets.getUiData("unchecked_box_press", 0);

    const text_w = 150;

    self.remember_login_toggle = try element.create(self.allocator, Toggle, .{
        .base = .{
            .x = self.password_input.base.x + (input_w - text_w - check_box_base_on.width()) / 2,
            .y = self.password_input.base.y + 75 - (100 - check_box_base_on.height()) / 2,
        },
        .off_image_data = .fromImageData(check_box_base_off, check_box_hover_off, check_box_press_off),
        .on_image_data = .fromImageData(check_box_base_on, check_box_hover_on, check_box_press_on),
        .toggled = &main.settings.remember_login,
    });

    self.remember_login_text = try element.create(self.allocator, Text, .{
        .base = .{
            .x = self.remember_login_toggle.base.x + check_box_base_on.width(),
            .y = self.remember_login_toggle.base.y,
        },
        .text_data = .{
            .text = "Remember Login",
            .size = 20,
            .text_type = .bold,
            .hori_align = .middle,
            .vert_align = .middle,
            .max_width = text_w,
            .max_height = self.remember_login_toggle.height(),
        },
    });

    const button_data_base = assets.getUiData("button_base", 0);
    const button_data_hover = assets.getUiData("button_hover", 0);
    const button_data_press = assets.getUiData("button_press", 0);

    self.login_button = try element.create(self.allocator, Button, .{
        .base = .{
            .x = self.password_input.base.x + (input_w - 200) / 2 - 12,
            .y = self.password_input.base.y + 150,
        },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, 100, 35, 26, 21, 3, 3, 1.0),
        .text_data = .{
            .text = "Login",
            .size = 16,
            .text_type = .bold,
        },
        .userdata = self,
        .press_callback = loginCallback,
    });

    self.register_button = try element.create(self.allocator, Button, .{
        .base = .{
            .x = self.login_button.base.x + (input_w - 100) / 2 + 24,
            .y = self.login_button.base.y,
        },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, 100, 35, 26, 21, 3, 3, 1.0),
        .text_data = .{
            .text = "Register",
            .size = 16,
            .text_type = .bold,
        },
        .press_callback = registerCallback,
    });
}

pub fn deinit(self: *AccountLoginScreen) void {
    element.destroy(self.email_text);
    element.destroy(self.email_input);
    element.destroy(self.password_text);
    element.destroy(self.password_input);
    element.destroy(self.login_button);
    element.destroy(self.register_button);
    element.destroy(self.remember_login_text);
    element.destroy(self.remember_login_toggle);

    self.allocator.destroy(self);
}

pub fn resize(self: *AccountLoginScreen, w: f32, h: f32) void {
    self.email_input.base.x = (w - self.email_input.width()) / 2;
    self.email_input.base.y = h / 3.6;
    self.email_text.base.x = self.email_input.base.x;
    self.email_text.base.y = self.email_input.base.y - 50;
    self.password_input.base.x = self.email_input.base.x;
    self.password_input.base.y = self.email_input.base.y + 150;
    self.password_text.base.x = self.password_input.base.x;
    self.password_text.base.y = self.password_input.base.y - 50;
    self.remember_login_toggle.base.x = self.password_input.base.x + 36;
    self.remember_login_toggle.base.y = self.password_input.base.y + 64;
    self.remember_login_text.base.x = self.remember_login_toggle.base.x + 78;
    self.remember_login_text.base.y = self.remember_login_toggle.base.y;
    self.login_button.base.x = self.password_input.base.x + 38;
    self.login_button.base.y = self.password_input.base.y + 150;
    self.register_button.base.x = self.login_button.base.x + 124;
    self.register_button.base.y = self.login_button.base.y;
}

pub fn update(_: *AccountLoginScreen, _: i64, _: f32) !void {}

fn loginCallback(ud: ?*anyopaque) void {
    const current_screen: *AccountLoginScreen = @alignCast(@ptrCast(ud.?));
    _ = login(
        main.account_arena_allocator,
        current_screen.email_input.text_data.text,
        current_screen.password_input.text_data.text,
    ) catch |e| {
        std.log.err("Login failed: {}", .{e});
    };
}

fn registerCallback(_: ?*anyopaque) void {
    ui_systems.switchScreen(.register);
}

fn login(allocator: std.mem.Allocator, email: []const u8, password: []const u8) !bool {
    var data: std.StringHashMapUnmanaged([]const u8) = .empty;
    try data.put(allocator, "email", email);
    try data.put(allocator, "password", password);
    defer data.deinit(allocator);

    var needs_free = true;
    const response = requests.sendRequest(build_options.login_server_uri ++ "account/verify", data) catch |e| blk: {
        switch (e) {
            error.ConnectionRefused => {
                needs_free = false;
                break :blk "Connection Refused";
            },
            else => return e,
        }
    };
    defer if (needs_free) requests.freeResponse(response);

    main.character_list = std.json.parseFromSliceLeaky(network_data.CharacterListData, allocator, response, .{ .allocate = .alloc_always }) catch {
        dialog.showDialog(.text, .{
            .title = "Login Failed",
            .body = try std.fmt.allocPrint(allocator, "Error: {s}", .{response}),
        });
        return false;
    };

    main.current_account = .{
        .email = try allocator.dupe(u8, email),
        .token = main.character_list.?.token,
    };

    if (main.character_list.?.characters.len > 0)
        ui_systems.switchScreen(.char_select)
    else
        ui_systems.switchScreen(.char_create);

    return true;
}
