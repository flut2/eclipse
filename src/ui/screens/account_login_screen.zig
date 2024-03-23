const std = @import("std");
const element = @import("../element.zig");
const assets = @import("../../assets.zig");
const camera = @import("../../camera.zig");
const requests = @import("../../requests.zig");
const xml = @import("../../xml.zig");
const main = @import("../../main.zig");
const settings = @import("../../settings.zig");
const systems = @import("../systems.zig");
const input = @import("../../input.zig");
const rpc = @import("rpc");
const dialog = @import("../dialogs/dialog.zig");

const Interactable = element.InteractableImageData;

pub const AccountLoginScreen = struct {
    email_text: *element.Text = undefined,
    email_input: *element.Input = undefined,
    password_text: *element.Text = undefined,
    password_input: *element.Input = undefined,
    login_button: *element.Button = undefined,
    confirm_button: *element.Button = undefined,
    save_email_text: *element.Text = undefined,
    save_email_toggle: *element.Toggle = undefined,
    editor_button: *element.Button = undefined,
    inited: bool = false,

    _allocator: std.mem.Allocator = undefined,

    pub fn init(allocator: std.mem.Allocator) !*AccountLoginScreen {
        var screen = try allocator.create(AccountLoginScreen);
        screen.* = .{ ._allocator = allocator };

        const presence = rpc.Packet.Presence{
            .assets = .{
                .large_image = rpc.Packet.ArrayString(256).create("logo"),
                .large_text = rpc.Packet.ArrayString(128).create(main.version_text),
            },
            .state = rpc.Packet.ArrayString(128).create("Login Screen"),
            .timestamps = .{
                .start = main.rpc_start,
            },
        };
        try main.rpc_client.setPresence(presence);

        const input_w = 300;
        const input_h = 50;
        const input_data_base = assets.getUiData("text_input_base", 0);
        const input_data_hover = assets.getUiData("text_input_hover", 0);
        const input_data_press = assets.getUiData("text_input_press", 0);

        const cursor_data = assets.getUiData("chatbox_cursor", 0);
        screen.email_input = try element.create(allocator, element.Input{
            .x = (camera.screen_width - input_w) / 2,
            .y = camera.screen_height / 3.6,
            .text_inlay_x = 9,
            .text_inlay_y = 8,
            .image_data = Interactable.fromNineSlices(input_data_base, input_data_hover, input_data_press, input_w, input_h, 12, 12, 2, 2, 1.0),
            .cursor_image_data = .{ .normal = .{ .atlas_data = cursor_data } },
            .text_data = .{
                .text = "",
                .size = 20,
                .text_type = .bold,
                .max_chars = 256,
                .handle_special_chars = false,
            },
            .allocator = allocator,
        });

        input.selected_input_field = screen.email_input;
        const email_len = settings.email.len;
        @memcpy(screen.email_input.text_data._backing_buffer[0..email_len], settings.email);
        screen.email_input._index += @intCast(email_len);
        screen.email_input.text_data.text = screen.email_input.text_data._backing_buffer[0..email_len];
        screen.email_input.inputUpdate();

        screen.email_text = try element.create(allocator, element.Text{
            .x = screen.email_input.x,
            .y = screen.email_input.y - 50,
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

        screen.password_input = try element.create(allocator, element.Input{
            .x = screen.email_input.x,
            .y = screen.email_input.y + 150,
            .text_inlay_x = 9,
            .text_inlay_y = 8,
            .image_data = Interactable.fromNineSlices(input_data_base, input_data_hover, input_data_press, input_w, input_h, 12, 12, 2, 2, 1.0),
            .cursor_image_data = .{ .normal = .{ .atlas_data = cursor_data } },
            .text_data = .{
                .text = "",
                .size = 20,
                .text_type = .bold,
                .password = true,
                .max_chars = 256,
                .handle_special_chars = false,
            },
            .allocator = allocator,
        });

        screen.password_text = try element.create(allocator, element.Text{
            .x = screen.password_input.x,
            .y = screen.password_input.y - 50,
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

        screen.save_email_toggle = try element.create(allocator, element.Toggle{
            .x = screen.password_input.x + (input_w - text_w - check_box_base_on.texWRaw()) / 2,
            .y = screen.password_input.y + 100 - (100 - check_box_base_on.texHRaw()) / 2,
            .off_image_data = Interactable.fromImageData(check_box_base_off, check_box_hover_off, check_box_press_off),
            .on_image_data = Interactable.fromImageData(check_box_base_on, check_box_hover_on, check_box_press_on),
            .toggled = &settings.save_email,
        });

        screen.save_email_text = try element.create(allocator, element.Text{
            .x = screen.save_email_toggle.x + check_box_base_on.texWRaw(),
            .y = screen.save_email_toggle.y,
            .text_data = .{
                .text = "Save e-mail",
                .size = 20,
                .text_type = .bold,
                .hori_align = .middle,
                .vert_align = .middle,
                .max_width = text_w,
                .max_height = screen.save_email_toggle.height(),
            },
        });

        const button_data_base = assets.getUiData("button_base", 0);
        const button_data_hover = assets.getUiData("button_hover", 0);
        const button_data_press = assets.getUiData("button_press", 0);

        screen.login_button = try element.create(allocator, element.Button{
            .x = screen.password_input.x + (input_w - 200) / 2 - 12.5,
            .y = screen.password_input.y + 150,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, 100, 35, 11, 9, 3, 3, 1.0),
            .text_data = .{
                .text = "Login",
                .size = 16,
                .text_type = .bold,
            },
            .press_callback = loginCallback,
        });

        screen.confirm_button = try element.create(allocator, element.Button{
            .x = screen.login_button.x + (input_w - 100) / 2 + 25,
            .y = screen.login_button.y,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, 100, 35, 11, 9, 3, 3, 1.0),
            .text_data = .{
                .text = "Register",
                .size = 16,
                .text_type = .bold,
            },
            .press_callback = registerCallback,
        });

        screen.editor_button = try element.create(allocator, element.Button{
            .x = screen.password_input.x + (input_w - 200) / 2,
            .y = screen.confirm_button.y + 50,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, 200, 35, 11, 9, 3, 3, 1.0),
            .text_data = .{
                .text = "Editor",
                .size = 16,
                .text_type = .bold,
            },
            .press_callback = enableEditorCallback,
        });
        screen.inited = true;
        return screen;
    }

    pub fn enableEditorCallback() void {
        systems.switchScreen(.editor);
    }

    pub fn deinit(self: *AccountLoginScreen) void {
        element.destroy(self.email_text);
        element.destroy(self.email_input);
        element.destroy(self.password_text);
        element.destroy(self.password_input);
        element.destroy(self.login_button);
        element.destroy(self.confirm_button);
        element.destroy(self.save_email_text);
        element.destroy(self.save_email_toggle);
        element.destroy(self.editor_button);

        self._allocator.destroy(self);
    }

    pub fn resize(self: *AccountLoginScreen, w: f32, h: f32) void {
        self.email_input.x = (w - self.email_input.width()) / 2;
        self.email_input.y = h / 3.6;
        self.email_text.x = self.email_input.x;
        self.email_text.y = self.email_input.y - 50;
        self.password_input.x = self.email_input.x;
        self.password_input.y = self.email_input.y + 150;
        self.password_text.x = self.password_input.x;
        self.password_text.y = self.password_input.y - 50;
        self.save_email_toggle.x = self.password_input.x + 49;
        self.save_email_toggle.y = self.password_input.y + 74;
        self.save_email_text.x = self.save_email_toggle.x + 52;
        self.save_email_text.y = self.save_email_toggle.y - 24;
        self.login_button.x = self.password_input.x + 37.5;
        self.login_button.y = self.password_input.y + 150;
        self.confirm_button.x = self.login_button.x + 125;
        self.confirm_button.y = self.login_button.y;
        self.editor_button.x = self.password_input.x + 50;
        self.editor_button.y = self.login_button.y + 50;
    }

    pub fn update(_: *AccountLoginScreen, _: i64, _: f32) !void {}

    fn loginCallback() void {
        const current_screen = systems.screen.main_menu;
        _ = login(
            current_screen._allocator,
            current_screen.email_input.text_data.text,
            current_screen.password_input.text_data.text,
        ) catch |e| {
            std.log.err("Login failed: {}", .{e});
        };
    }

    fn registerCallback() void {
        systems.switchScreen(.register);
    }
};

fn login(allocator: std.mem.Allocator, email: []const u8, password: []const u8) !bool {
    var verify_data = std.StringHashMap([]const u8).init(allocator);
    try verify_data.put("email", email);
    try verify_data.put("password", password);
    defer verify_data.deinit();

    const response = try requests.sendRequest("account/verify", verify_data);
    defer requests.freeResponse(response);

    if (std.mem.eql(u8, response, "<Error />")) {
        dialog.showDialog(.text, .{
            .title = "Login Failed",
            .body = "Invalid credentials",
        });
        return false;
    }

    std.log.err("login {s}", .{response});
    const verify_doc = try xml.Doc.fromMemory(response);
    defer verify_doc.deinit();
    const verify_root = try verify_doc.getRootElement();

    if (std.mem.eql(u8, verify_root.currentName().?, "Error")) {
        dialog.showDialog(.text, .{
            .title = "Login Failed",
            .body = try allocator.dupe(u8, verify_root.currentValue().?),
            .dispose_body = true,
        });
        return false;
    }

    main.current_account.name = try allocator.dupe(u8, verify_root.getValue("Name") orelse "Guest");
    main.current_account.email = try allocator.dupe(u8, email);
    main.current_account.password = try allocator.dupe(u8, password);
    main.current_account.admin = verify_root.elementExists("Admin");

    const guild_node = verify_root.findChild("Guild");
    main.current_account.guild_name = try guild_node.?.getValueAlloc("Name", allocator, "");
    main.current_account.guild_rank = try guild_node.?.getValueInt("Rank", u8, 0);

    var list_data = std.StringHashMap([]const u8).init(allocator);
    try list_data.put("email", email);
    try list_data.put("password", password);
    defer list_data.deinit();

    const list_response = try requests.sendRequest("char/list", list_data);
    defer requests.freeResponse(list_response);

    const list_doc = try xml.Doc.fromMemory(list_response);
    defer list_doc.deinit();
    const list_root = try list_doc.getRootElement();
    main.next_char_id = try list_root.getAttributeInt("nextCharId", u8, 0);
    main.max_chars = try list_root.getAttributeInt("maxNumChars", u8, 0);

    var char_list = try std.ArrayList(main.CharacterData).initCapacity(allocator, 4);
    defer char_list.deinit();

    var char_iter = list_root.iterate(&.{}, "Char");
    while (char_iter.next()) |node|
        try char_list.append(try main.CharacterData.parse(allocator, node, try node.getAttributeInt("id", u32, 0)));

    main.character_list = try allocator.dupe(main.CharacterData, char_list.items);

    const server_root = list_root.findChild("Servers");
    if (server_root) |srv_root| {
        var server_data_list = try std.ArrayList(main.ServerData).initCapacity(allocator, 4);
        defer server_data_list.deinit();

        var server_iter = srv_root.iterate(&.{}, "Server");
        while (server_iter.next()) |server_node|
            try server_data_list.append(try main.ServerData.parse(server_node, allocator));

        main.server_list = try allocator.dupe(main.ServerData, server_data_list.items);
    }

    if (settings.save_email) {
        if (settings.email.len > 0)
            allocator.free(settings.email);

        settings.email = try allocator.dupe(u8, email);
    }

    if (main.character_list.len > 0) {
        systems.switchScreen(.char_select);
    } else {
        systems.switchScreen(.char_create);
    }

    return true;
}
