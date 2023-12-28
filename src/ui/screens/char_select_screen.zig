const std = @import("std");
const element = @import("../element.zig");
const assets = @import("../../assets.zig");
const camera = @import("../../camera.zig");
const main = @import("../../main.zig");
const rpc = @import("rpc");
const systems = @import("../systems.zig");

const Interactable = element.InteractableImageData;

pub const CharSelectScreen = struct {
    boxes: std.ArrayList(*element.CharacterBox) = undefined,
    inited: bool = false,

    _allocator: std.mem.Allocator = undefined,
    new_char_button: *element.Button = undefined,
    pub fn init(allocator: std.mem.Allocator) !*CharSelectScreen {
        var screen = try allocator.create(CharSelectScreen);
        screen.* = .{ ._allocator = allocator };

        const presence = rpc.Packet.Presence{
            .assets = .{
                .large_image = rpc.Packet.ArrayString(256).create("logo"),
                .large_text = rpc.Packet.ArrayString(128).create(main.version_text),
            },
            .state = rpc.Packet.ArrayString(128).create("Character Select"),
            .timestamps = .{
                .start = main.rpc_start,
            },
        };
        try main.rpc_client.setPresence(presence);

        screen.boxes = std.ArrayList(*element.CharacterBox).init(allocator);
        try screen.boxes.ensureTotalCapacity(8);

        const button_data_base = assets.getUiData("button_base", 0);
        const button_data_hover = assets.getUiData("button_hover", 0);
        const button_data_press = assets.getUiData("button_press", 0);
        const button_width = 100;
        const button_height = 40;

        var counter: u32 = 0;
        for (main.character_list, 0..) |char, i| {
            counter += 1;

            const box = element.create(allocator, element.CharacterBox{
                .x = (camera.screen_width - button_data_base.texWRaw()) / 2,
                .y = @floatFromInt(50 * i),
                .id = char.id,
                .obj_type = char.obj_type,
                .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 6, 6, 7, 7, 1.0),
                .text_data = element.TextData{
                    .text = char.name[0..],
                    .size = 16,
                    .text_type = .bold,
                },
                .press_callback = boxClickCallback,
            }) catch return screen;
            screen.boxes.append(box) catch return screen;
        }

        screen.new_char_button = try element.create(allocator, element.Button{
            .x = (camera.screen_width - button_data_base.texWRaw()) / 2,
            .y = @floatFromInt(50 * (counter + 1)),
            .visible = false,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 6, 6, 7, 7, 1.0),
            .text_data = .{
                .text = "New Character",
                .size = 16,
                .text_type = .bold,
            },
            .press_callback = newCharCallback,
        });

        if (counter < main.max_chars)
            screen.new_char_button.visible = true;

        screen.inited = true;
        return screen;
    }

    pub fn deinit(self: *CharSelectScreen) void {
        for (self.boxes.items) |box| {
            element.destroy(box);
        }
        self.boxes.clearAndFree();

        element.destroy(self.new_char_button);

        self._allocator.destroy(self);
    }

    pub fn resize(_: *CharSelectScreen, _: f32, _: f32) void {}

    pub fn update(_: *CharSelectScreen, _: i64, _: f32) !void {}

    fn boxClickCallback(box: *element.CharacterBox) void {
        main.selected_char_id = box.id;
        if (main.server_list) |server_list| {
            if (server_list.len > 0) {
                main.selected_server = server_list[0];
                systems.switchScreen(.game);
                return;
            }
        }

        std.log.err("No servers found", .{});
    }

    fn newCharCallback() void {
        systems.switchScreen(.char_create);
    }
};
