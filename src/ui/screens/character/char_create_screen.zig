const std = @import("std");
const element = @import("../../element.zig");
const assets = @import("../../../assets.zig");
const camera = @import("../../../camera.zig");
const main = @import("../../../main.zig");
const game_data = @import("../../../game_data.zig");
const screen_controller = @import("../../controllers/screen_controller.zig");

pub const CharCreateScreen = struct {
    inited: bool = false,
    boxes: std.ArrayList(*element.CharacterBox) = undefined, //TODO change 'CharacterBox' to 'NewCharacterBox' when implemented
    _allocator: std.mem.Allocator = undefined,

    pub fn init(allocator: std.mem.Allocator) !*CharCreateScreen {
        var screen = try allocator.create(CharCreateScreen);
        screen.* = CharCreateScreen{
            ._allocator = allocator,
        };

        screen.boxes = std.ArrayList(*element.CharacterBox).init(allocator);
        try screen.boxes.ensureTotalCapacity(game_data.classes.len);

        const button_data_base = assets.getUiData("button_base", 0);
        const button_data_hover = assets.getUiData("button_hover", 0);
        const button_data_press = assets.getUiData("button_press", 0);

        //TODO Check which classes are locked as it kicks you to character select if class is locked
        for (game_data.classes, 0..) |char, i| {
            const box = element.CharacterBox.create(allocator, .{
                .x = (camera.screen_width - button_data_base.texWRaw()) / 2,
                .y = @floatFromInt(50 * i),
                .id = 0,
                .obj_type = char.obj_type,
                .image_data = .{
                    .base = .{ .nine_slice = element.NineSliceImageData.fromAtlasData(button_data_base, 100, 40, 6, 6, 7, 7, 1.0) },
                    .hover = .{ .nine_slice = element.NineSliceImageData.fromAtlasData(button_data_hover, 100, 40, 6, 6, 7, 7, 1.0) },
                    .press = .{ .nine_slice = element.NineSliceImageData.fromAtlasData(button_data_press, 100, 40, 6, 6, 7, 7, 1.0) },
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
        screen.inited = true;
        return screen;
    }

    pub fn deinit(self: *CharCreateScreen) void {
        for (self.boxes.items) |box| {
            box.destroy();
        }
        self.boxes.clearAndFree();

        self._allocator.destroy(self);
    }

    pub fn resize(_: *CharCreateScreen, _: f32, _: f32) void {}

    pub fn update(_: *CharCreateScreen, _: i64, _: f32) !void {}

    fn boxClickCallback(box: *element.CharacterBox) void {
        main.char_create_type = box.obj_type;
        main.char_create_skin_type = 0;
        main.selected_char_id = main.next_char_id;
        main.next_char_id += 1;

        if (main.server_list) |server_list| {
            main.selected_server = server_list[0];
        } else {
            std.log.err("No servers found", .{});
        }
        screen_controller.switchScreen(.game);
    }
};
