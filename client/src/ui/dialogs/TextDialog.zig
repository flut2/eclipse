const std = @import("std");

const assets = @import("../../assets.zig");
const main = @import("../../main.zig");
const Button = @import("../elements/Button.zig");
const Container = @import("../elements/Container.zig");
const element = @import("../elements/element.zig");
const Image = @import("../elements/Image.zig");
const Text = @import("../elements/Text.zig");
const dialog = @import("dialog.zig");

const TextDialog = @This();
const width = 300;
const height = 200;
const button_width = 100;
const button_height = 30;

root: *Container = undefined,

title_decor: *Image = undefined,
title_text: *Text = undefined,
base_decor: *Image = undefined,
base_text: *Text = undefined,
close_button: *Button = undefined,
dispose_title: bool = false,
dispose_body: bool = false,

pub fn init(self: *TextDialog) !void {
    const base_data = assets.getUiData("dialog_base_background", 0);
    self.base_decor = try self.root.createChild(Image, .{
        .base = .{ .x = 0, .y = 0 },
        .image_data = .{
            .nine_slice = .fromAtlasData(base_data, width, height, 49, 15, 1, 1, 1.0),
        },
    });

    const title_data = assets.getUiData("dialog_title_background", 0);
    self.title_decor = try self.root.createChild(Image, .{
        .base = .{ .x = 0, .y = 0 },
        .image_data = .{ .nine_slice = .fromAtlasData(title_data, 0, 0, 77, 15, 1, 1, 1.0) },
    });

    self.title_text = try self.root.createChild(Text, .{
        .base = .{ .x = 0, .y = 0 },
        .text_data = .{
            .text = "",
            .size = 22,
            .hori_align = .middle,
            .vert_align = .middle,
            .text_type = .bold_italic,
        },
    });

    self.base_text = try self.root.createChild(Text, .{
        .base = .{ .x = 5, .y = 5 },
        .text_data = .{
            .text = "",
            .size = 16,
            .hori_align = .middle,
            .vert_align = .middle,
            .max_width = width - 10,
            .max_height = height - button_height - self.title_decor.height() / 2.0 - 10,
        },
    });

    const button_data_base = assets.getUiData("button_base", 0);
    const button_data_hover = assets.getUiData("button_hover", 0);
    const button_data_press = assets.getUiData("button_press", 0);

    self.close_button = try self.root.createChild(Button, .{
        .base = .{ .x = (width - button_width) / 2.0, .y = height - button_height - 15 },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 26, 19, 1, 1, 1.0),
        .text_data = .{
            .text = "Ok",
            .size = 16,
            .text_type = .bold,
        },
        .pressCallback = closeDialog,
    });
}

fn closeDialog(_: ?*anyopaque) void {
    dialog.showDialog(.none, {});
}

pub fn deinit(self: *TextDialog) void {
    if (self.dispose_body) main.allocator.free(self.base_text.text_data.text);
    if (self.dispose_title) main.allocator.free(self.title_text.text_data.text);
    element.destroy(self.root);
}

pub fn setValues(self: *TextDialog, params: dialog.ParamsFor(TextDialog)) void {
    if (self.dispose_body) main.allocator.free(self.base_text.text_data.text);
    if (self.dispose_title) main.allocator.free(self.title_text.text_data.text);

    if (params.title) |title| {
        self.title_text.text_data.setText(title);
        switch (self.title_decor.image_data) {
            .nine_slice => |*nine_slice| {
                nine_slice.w = self.title_text.width() + 25 * 2;
                nine_slice.h = self.title_text.height() + 10 * 2;
            },
            .normal => |*image_data| {
                image_data.scale_x = (self.title_text.width() + 25 * 2) / image_data.width();
                image_data.scale_y = (self.title_text.height() + 10 * 2) / image_data.height();
            },
        }

        self.title_decor.base.x = (width - self.title_decor.width()) / 2.0;
        self.title_decor.base.y = -self.title_decor.height() / 2.0 + 6.0;
        self.title_text.base.x = self.title_decor.base.x;
        self.title_text.base.y = self.title_decor.base.y;
        self.title_text.text_data.max_width = self.title_decor.width();
        self.title_text.text_data.max_height = self.title_decor.height();
    }

    self.base_text.base.y = self.title_decor.height() / 2.0;
    self.base_text.text_data.max_height = height - button_height - (self.title_decor.height() / 2.0 + 6.0) - 10;
    self.base_text.text_data.setText(params.body);

    self.dispose_title = params.title != null and params.dispose_title;
    self.dispose_body = params.dispose_body;
}
