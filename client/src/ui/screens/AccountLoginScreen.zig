const std = @import("std");

const build_options = @import("options");
const shared = @import("shared");
const network_data = shared.network_data;

const assets = @import("../../assets.zig");
const input = @import("../../input.zig");
const main = @import("../../main.zig");
const dialog = @import("../dialogs/dialog.zig");
const Button = @import("../elements/Button.zig");
const element = @import("../elements/element.zig");
const Input = @import("../elements/Input.zig");
const Text = @import("../elements/Text.zig");
const Toggle = @import("../elements/Toggle.zig");
const ui_systems = @import("../systems.zig");

const AccountLoginScreen = @This();
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
    const input_data_base = assets.getUiData("text_input", 0);
    const input_data_hover = assets.getUiData("text_input", 1);
    const input_data_press = assets.getUiData("text_input", 2);

    const cursor_data = assets.getUiData("chatbox_cursor", 0);
    self.email_input = try element.create(Input, .{
        .base = .{
            .x = (main.camera.width - input_w) / 2,
            .y = main.camera.height / 3.6,
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

    input.selected_input_field = self.email_input;

    self.email_text = try element.create(Text, .{
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

    self.password_input = try element.create(Input, .{
        .base = .{
            .x = self.email_input.base.x,
            .y = self.email_input.base.y + 150,
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

    self.password_text = try element.create(Text, .{
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

    self.remember_login_toggle = try element.create(Toggle, .{
        .base = .{
            .x = self.password_input.base.x + (input_w - text_w - check_box_base_on.width()) / 2,
            .y = self.password_input.base.y + 75 - (100 - check_box_base_on.height()) / 2,
        },
        .off_image_data = .fromImageData(check_box_base_off, check_box_hover_off, check_box_press_off),
        .on_image_data = .fromImageData(check_box_base_on, check_box_hover_on, check_box_press_on),
        .toggled = &main.settings.remember_login,
        .state_change = rememberLoginCallback,
    });

    self.remember_login_text = try element.create(Text, .{
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

    self.login_button = try element.create(Button, .{
        .base = .{
            .x = self.password_input.base.x + (input_w - 200) / 2 - 12,
            .y = self.password_input.base.y + 150,
        },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, 100, 35, 26, 19, 1, 1, 1.0),
        .text_data = .{
            .text = "Login",
            .size = 16,
            .text_type = .bold,
        },
        .userdata = self,
        .pressCallback = loginCallback,
    });

    self.register_button = try element.create(Button, .{
        .base = .{
            .x = self.login_button.base.x + (input_w - 100) / 2 + 24,
            .y = self.login_button.base.y,
        },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, 100, 35, 26, 19, 1, 1, 1.0),
        .text_data = .{
            .text = "Register",
            .size = 16,
            .text_type = .bold,
        },
        .pressCallback = registerCallback,
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

    main.allocator.destroy(self);
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

fn rememberLoginCallback(_: *Toggle) void {
    main.settings.save() catch |e| {
        std.log.err("Error while saving settings in login screen: {}", .{e});
        return;
    };
}

fn loginCallback(ud: ?*anyopaque) void {
    const current_screen: *AccountLoginScreen = @alignCast(@ptrCast(ud.?));
    const email = main.account_arena_allocator.dupe(u8, current_screen.email_input.text_data.text) catch main.oomPanic();
    main.current_account = .{ .email = email, .token = 0 };
    main.login_server.sendPacket(.{ .login = .{
        .email = email,
        .password = current_screen.password_input.text_data.text,
    } });
}

fn registerCallback(_: ?*anyopaque) void {
    ui_systems.switchScreen(.register);
}
