const std = @import("std");
const element = @import("../element.zig");
const assets = @import("../../assets.zig");
const camera = @import("../../camera.zig");
const requests = @import("../../requests.zig");
const xml = @import("../../xml.zig");
const main = @import("../../main.zig");
const rpc = @import("rpc");

const systems = @import("../systems.zig");

const NineSlice = element.NineSliceImageData;

pub const AccountRegisterScreen = struct {
    username_text: *element.Text = undefined,
    username_input: *element.Input = undefined,
    email_text: *element.Text = undefined,
    email_input: *element.Input = undefined,
    password_text: *element.Text = undefined,
    password_input: *element.Input = undefined,
    password_repeat_text: *element.Text = undefined,
    password_repeat_input: *element.Input = undefined,
    confirm_button: *element.Button = undefined,
    back_button: *element.Button = undefined,
    inited: bool = false,

    _allocator: std.mem.Allocator = undefined,

    pub fn init(allocator: std.mem.Allocator) !*AccountRegisterScreen {
        var screen = try allocator.create(AccountRegisterScreen);
        screen.* = .{ ._allocator = allocator };

        const presence = rpc.Packet.Presence{
            .assets = .{
                .large_image = rpc.Packet.ArrayString(256).create("logo"),
                .large_text = rpc.Packet.ArrayString(128).create(main.version_text),
            },
            .state = rpc.Packet.ArrayString(128).create("Register Screen"),
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

        const x_offset: f32 = (camera.screen_width - input_w) / 2;
        var y_offset: f32 = camera.screen_height / 7.2;

        screen.username_text = try element.create(allocator, element.Text{
            .x = x_offset,
            .y = y_offset,
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
        screen.username_input = try element.create(allocator, element.Input{
            .x = x_offset,
            .y = y_offset,
            .text_inlay_x = 9,
            .text_inlay_y = 8,
            .image_data = .{
                .base = .{ .nine_slice = NineSlice.fromAtlasData(input_data_base, input_w, input_h, 8, 8, 32, 32, 1.0) },
                .hover = .{ .nine_slice = NineSlice.fromAtlasData(input_data_hover, input_w, input_h, 8, 8, 32, 32, 1.0) },
                .press = .{ .nine_slice = NineSlice.fromAtlasData(input_data_press, input_w, input_h, 8, 8, 32, 32, 1.0) },
            },
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

        y_offset += 50;

        screen.email_text = try element.create(allocator, element.Text{
            .x = x_offset,
            .y = y_offset,
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

        screen.email_input = try element.create(allocator, element.Input{
            .x = x_offset,
            .y = y_offset,
            .text_inlay_x = 9,
            .text_inlay_y = 8,
            .image_data = .{
                .base = .{ .nine_slice = NineSlice.fromAtlasData(input_data_base, input_w, input_h, 8, 8, 32, 32, 1.0) },
                .hover = .{ .nine_slice = NineSlice.fromAtlasData(input_data_hover, input_w, input_h, 8, 8, 32, 32, 1.0) },
                .press = .{ .nine_slice = NineSlice.fromAtlasData(input_data_press, input_w, input_h, 8, 8, 32, 32, 1.0) },
            },
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

        y_offset += 50;

        screen.password_text = try element.create(allocator, element.Text{
            .x = x_offset,
            .y = y_offset,
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

        screen.password_input = try element.create(allocator, element.Input{
            .x = x_offset,
            .y = y_offset,
            .text_inlay_x = 9,
            .text_inlay_y = 8,
            .image_data = .{
                .base = .{ .nine_slice = NineSlice.fromAtlasData(input_data_base, input_w, input_h, 8, 8, 32, 32, 1.0) },
                .hover = .{ .nine_slice = NineSlice.fromAtlasData(input_data_hover, input_w, input_h, 8, 8, 32, 32, 1.0) },
                .press = .{ .nine_slice = NineSlice.fromAtlasData(input_data_press, input_w, input_h, 8, 8, 32, 32, 1.0) },
            },
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

        y_offset += 50;

        screen.password_repeat_text = try element.create(allocator, element.Text{
            .x = x_offset,
            .y = y_offset,
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

        screen.password_repeat_input = try element.create(allocator, element.Input{
            .x = x_offset,
            .y = y_offset,
            .text_inlay_x = 9,
            .text_inlay_y = 8,
            .image_data = .{
                .base = .{ .nine_slice = NineSlice.fromAtlasData(input_data_base, input_w, input_h, 8, 8, 32, 32, 1.0) },
                .hover = .{ .nine_slice = NineSlice.fromAtlasData(input_data_hover, input_w, input_h, 8, 8, 32, 32, 1.0) },
                .press = .{ .nine_slice = NineSlice.fromAtlasData(input_data_press, input_w, input_h, 8, 8, 32, 32, 1.0) },
            },
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

        y_offset += 75;

        const button_data_base = assets.getUiData("button_base", 0);
        const button_data_hover = assets.getUiData("button_hover", 0);
        const button_data_press = assets.getUiData("button_press", 0);
        const button_width = 100;
        const button_height = 35;

        screen.confirm_button = try element.create(allocator, element.Button{
            .x = x_offset + (input_w - (button_width * 2)) / 2 - 12.5,
            .y = y_offset,
            .image_data = .{
                .base = .{ .nine_slice = NineSlice.fromAtlasData(button_data_base, button_width, button_height, 6, 6, 7, 7, 1.0) },
                .hover = .{ .nine_slice = NineSlice.fromAtlasData(button_data_hover, button_width, button_height, 6, 6, 7, 7, 1.0) },
                .press = .{ .nine_slice = NineSlice.fromAtlasData(button_data_press, button_width, button_height, 6, 6, 7, 7, 1.0) },
            },
            .text_data = .{
                .text = "Confirm",
                .size = 16,
                .text_type = .bold,
            },
            .press_callback = registerCallback,
        });

        screen.back_button = try element.create(allocator, element.Button{
            .x = screen.confirm_button.x + button_width + 25,
            .y = y_offset,
            .image_data = .{
                .base = .{ .nine_slice = NineSlice.fromAtlasData(button_data_base, button_width, button_height, 6, 6, 7, 7, 1.0) },
                .hover = .{ .nine_slice = NineSlice.fromAtlasData(button_data_hover, button_width, button_height, 6, 6, 7, 7, 1.0) },
                .press = .{ .nine_slice = NineSlice.fromAtlasData(button_data_press, button_width, button_height, 6, 6, 7, 7, 1.0) },
            },
            .text_data = .{
                .text = "Back",
                .size = 16,
                .text_type = .bold,
            },
            .press_callback = backCallback,
        });

        screen.inited = true;
        return screen;
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

        self._allocator.destroy(self);
    }

    pub fn resize(self: *AccountRegisterScreen, w: f32, h: f32) void {
        self.username_text.x = (w - 300) / 2;
        self.username_text.y = h / 7.2;
        self.username_input.x = self.username_text.x;
        self.username_input.y = self.username_text.y + 50;
        self.email_text.x = self.username_input.x;
        self.email_text.y = self.username_input.y + 50;
        self.email_input.x = self.email_text.x;
        self.email_input.y = self.email_text.y + 50;
        self.password_text.x = self.email_input.x;
        self.password_text.y = self.email_input.y + 50;
        self.password_input.x = self.password_text.x;
        self.password_input.y = self.password_text.y + 50;
        self.password_repeat_text.x = self.password_input.x;
        self.password_repeat_text.y = self.password_input.y + 50;
        self.password_repeat_input.x = self.password_repeat_text.x;
        self.password_repeat_input.y = self.password_repeat_text.y + 50;
        self.confirm_button.x = self.password_repeat_input.x + 100 / 2 - 12.5;
        self.confirm_button.y = self.password_repeat_input.y + 75;
        self.back_button.x = self.confirm_button.x + 125;
        self.back_button.y = self.confirm_button.y;
    }

    pub fn update(_: *AccountRegisterScreen, _: i64, _: f32) !void {}

    fn register(email: []const u8, password: []const u8, username: []const u8) !bool {
        const response = try requests.sendAccountRegister(email, password, username);
        if (std.mem.eql(u8, response, "<Error />")) {
            std.log.err("Register failed: {s}", .{response});
            return false;
        }

        return true;
    }

    fn login(allocator: std.mem.Allocator, email: []const u8, password: []const u8) !bool {
        const response = try requests.sendAccountVerify(email, password);
        if (std.mem.eql(u8, response, "<Error />")) {
            std.log.err("Login failed: {s}", .{response});
            return false;
        }

        const verify_doc = try xml.Doc.fromMemory(response);
        defer verify_doc.deinit();
        const verify_root = try verify_doc.getRootElement();

        if (std.mem.eql(u8, verify_root.currentName().?, "Error")) {
            std.log.err("Login failed: {s}", .{verify_root.currentValue().?});
            return false;
        }

        main.current_account.name = try allocator.dupe(u8, verify_root.getValue("Name") orelse "Guest");
        main.current_account.email = try allocator.dupe(u8, email);
        main.current_account.password = try allocator.dupe(u8, password);
        main.current_account.admin = verify_root.elementExists("Admin");

        const guild_node = verify_root.findChild("Guild");
        main.current_account.guild_name = try guild_node.?.getValueAlloc("Name", allocator, "");
        main.current_account.guild_rank = try guild_node.?.getValueInt("Rank", u8, 0);

        const list_response = try requests.sendCharList(email, password);
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

        if (main.character_list.len > 0) {
            systems.switchScreen(.char_select);
        } else {
            systems.switchScreen(.char_create);
        }

        return true;
    }

    fn registerCallback() void {
        const current_screen = systems.screen.register;
        _ = register(
            current_screen.email_input.text_data.text,
            current_screen.password_input.text_data.text,
            current_screen.username_input.text_data.text,
        ) catch |e| {
            std.log.err("Register failed: {any}", .{e});
            return;
        };

        _ = login(
            current_screen._allocator,
            current_screen.email_input.text_data.text,
            current_screen.password_input.text_data.text,
        ) catch |e| {
            std.log.err("Login failed: {any}", .{e});
            return;
        };
    }

    fn backCallback() void {
        systems.switchScreen(.main_menu);
    }
};
