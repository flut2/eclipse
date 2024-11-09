const std = @import("std");
const element = @import("../elements/element.zig");
const assets = @import("../../assets.zig");
const main = @import("../../main.zig");
const game_data = @import("shared").game_data;
const systems = @import("../systems.zig");

const CharCreateScreen = @This();
const CharacterBox = @import("../elements/CharacterBox.zig");

boxes: std.ArrayListUnmanaged(*CharacterBox) = .empty,

pub fn init(self: *CharCreateScreen) !void {
    const button_data_base = assets.getUiData("button_base", 0);
    const button_data_hover = assets.getUiData("button_hover", 0);
    const button_data_press = assets.getUiData("button_press", 0);

    // TODO: Check which classes are locked as it kicks you to character select if class is locked
    var class_iter = game_data.class.from_id.valueIterator();
    var i: usize = 0;
    while (class_iter.next()) |char| {
        defer i += 1;
        const box = element.create(CharacterBox, .{
            .base = .{
                .x = (main.camera.width - button_data_base.width()) / 2,
                .y = @floatFromInt(50 * i),
            },
            .id = 0,
            .class_data_id = char.id,
            .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, 100, 40, 26, 21, 3, 3, 1.0),
            .text_data = .{
                .text = char.name,
                .size = 16,
                .text_type = .bold,
            },
            .press_callback = boxClickCallback,
        }) catch return;
        self.boxes.append(main.allocator, box) catch return;
    }
}

pub fn deinit(self: *CharCreateScreen) void {
    for (self.boxes.items) |box| element.destroy(box);
    self.boxes.clearAndFree(main.allocator);
    main.allocator.destroy(self);
}

fn boxClickCallback(box: *CharacterBox) void {
    if (main.character_list) |*list| if (list.servers.len > 0) {
        main.enterGame(list.servers[0], list.next_char_id, box.class_data_id);
        list.next_char_id += 1;
        return;
    };

    std.log.err("No servers found", .{});
}
