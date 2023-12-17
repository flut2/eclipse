const std = @import("std");
const element = @import("../../element.zig");
const assets = @import("../../../assets.zig");
const camera = @import("../../../camera.zig");
const main = @import("../../../main.zig");

const screen_controller = @import("../../controllers/screen_controller.zig");

pub const CharSelectScreen = struct {
    boxes: std.ArrayList(*element.CharacterBox) = undefined,
    inited: bool = false,

    _allocator: std.mem.Allocator = undefined,
    new_char_button: *element.Button = undefined,
    pub fn init(allocator: std.mem.Allocator) !*CharSelectScreen {
        var screen = try allocator.create(CharSelectScreen);
        screen.* = .{
            ._allocator = allocator,
        };

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

            const box = element.CharacterBox.create(allocator, .{
                .x = (camera.screen_width - button_data_base.texWRaw()) / 2,
                .y = @floatFromInt(50 * i),
                .id = char.id,
                .obj_type = char.obj_type,
                .image_data = .{
                    .base = .{ .nine_slice = element.NineSliceImageData.fromAtlasData(button_data_base, button_width, button_height, 6, 6, 7, 7, 1.0) },
                    .hover = .{ .nine_slice = element.NineSliceImageData.fromAtlasData(button_data_hover, button_width, button_height, 6, 6, 7, 7, 1.0) },
                    .press = .{ .nine_slice = element.NineSliceImageData.fromAtlasData(button_data_press, button_width, button_height, 6, 6, 7, 7, 1.0) },
                },
                .text_data = element.TextData{
                    .text = char.name[0..],
                    .size = 16,
                    .text_type = .bold,
                },
                .press_callback = boxClickCallback,
            }) catch return screen;
            screen.boxes.append(box) catch return screen;
        }

        screen.new_char_button = try element.Button.create(allocator, .{
            .x = (camera.screen_width - button_data_base.texWRaw()) / 2,
            .y = @floatFromInt(50 * (counter + 1)),
            .visible = false,
            .image_data = .{
                .base = .{ .nine_slice = element.NineSliceImageData.fromAtlasData(button_data_base, button_width, button_height, 6, 6, 7, 7, 1.0) },
                .hover = .{ .nine_slice = element.NineSliceImageData.fromAtlasData(button_data_hover, button_width, button_height, 6, 6, 7, 7, 1.0) },
                .press = .{ .nine_slice = element.NineSliceImageData.fromAtlasData(button_data_press, button_width, button_height, 6, 6, 7, 7, 1.0) },
            },
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
            box.destroy();
        }
        self.boxes.clearAndFree();
        self.new_char_button.destroy();

        self._allocator.destroy(self);
    }

    pub fn resize(_: *CharSelectScreen, _: f32, _: f32) void {}

    pub fn update(_: *CharSelectScreen, _: i64, _: f32) !void {}

    fn boxClickCallback(box: *element.CharacterBox) void {
        main.selected_char_id = box.id;
        if (main.server_list) |server_list| {
            if (server_list.len > 0) {
                main.selected_server = server_list[0];
                screen_controller.switchScreen(.game);
                return;
            }
        }

        std.log.err("No servers found", .{});
    }

    fn newCharCallback() void {
        screen_controller.switchScreen(.char_create);
    }
};
