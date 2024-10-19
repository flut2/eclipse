const std = @import("std");
const element = @import("../elements/element.zig");
const assets = @import("../../assets.zig");
const main = @import("../../main.zig");
const ui_systems = @import("../systems.zig");
const build_options = @import("options");
const game_data = @import("shared").game_data;

const CharSelectScreen = @This();
const Button = @import("../elements/Button.zig");
const CharacterBox = @import("../elements/CharacterBox.zig");

boxes: std.ArrayListUnmanaged(*CharacterBox) = .empty,

new_char_button: *Button = undefined,
editor_button: *Button = undefined,
back_button: *Button = undefined,

pub fn init(self: *CharSelectScreen) !void {
    const button_data_base = assets.getUiData("button_base", 0);
    const button_data_hover = assets.getUiData("button_hover", 0);
    const button_data_press = assets.getUiData("button_press", 0);
    const button_width = 100;
    const button_height = 40;

    var counter: u32 = 0;
    if (main.character_list) |list| {
        for (list.characters, 0..) |char, i| {
            counter += 1;

            if (game_data.class.from_id.get(char.class_id)) |class| {
                const box = try element.create(CharacterBox, .{
                    .base = .{
                        .x = (main.camera.width - button_data_base.width()) / 2,
                        .y = @floatFromInt(50 * i),
                    },
                    .id = char.char_id,
                    .class_data_id = char.class_id,
                    .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 26, 21, 3, 3, 1.0),
                    .text_data = .{
                        .text = class.name,
                        .size = 16,
                        .text_type = .bold,
                    },
                    .press_callback = boxClickCallback,
                });
                try self.boxes.append(main.allocator, box);
            }
        }
    }

    self.new_char_button = try element.create(Button, .{
        .base = .{
            .x = (main.camera.width - button_data_base.width()) / 2,
            .y = @floatFromInt(50 * (counter + 1)),
            .visible = false,
        },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 26, 21, 3, 3, 1.0),
        .text_data = .{
            .text = "New Character",
            .size = 16,
            .text_type = .bold,
        },
        .press_callback = newCharCallback,
    });

    if (counter < if (main.character_list) |list| list.max_chars else 0) self.new_char_button.base.visible = true;

    self.editor_button = try element.create(Button, .{
        .base = .{ .x = 100, .y = 100 },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, 200, 35, 26, 21, 3, 3, 1.0),
        .text_data = .{
            .text = "Editor",
            .size = 16,
            .text_type = .bold,
        },
        .press_callback = editorCallback,
    });

    self.back_button = try element.create(Button, .{
        .base = .{ .x = 100, .y = 200 },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, 200, 35, 26, 21, 3, 3, 1.0),
        .text_data = .{
            .text = "Back to Login",
            .size = 16,
            .text_type = .bold,
        },
        .press_callback = backCallback,
    });
}

pub fn deinit(self: *CharSelectScreen) void {
    for (self.boxes.items) |box| element.destroy(box);
    self.boxes.clearAndFree(main.allocator);

    element.destroy(self.new_char_button);
    element.destroy(self.editor_button);
    element.destroy(self.back_button);

    main.allocator.destroy(self);
}

fn boxClickCallback(box: *CharacterBox) void {
    if (main.character_list) |list| if (list.servers.len > 0) {
        main.enterGame(list.servers[0], box.id, std.math.maxInt(u16));
        return;
    };

    std.log.err("No servers found", .{});
}

fn newCharCallback(_: ?*anyopaque) void {
    ui_systems.switchScreen(.char_create);
}

pub fn editorCallback(_: ?*anyopaque) void {
    ui_systems.switchScreen(.editor);
}

pub fn backCallback(_: ?*anyopaque) void {
    ui_systems.switchScreen(.main_menu);
}
