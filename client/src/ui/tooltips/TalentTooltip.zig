const std = @import("std");

const game_data = @import("shared").game_data;

const assets = @import("../../assets.zig");
const map = @import("../../game/map.zig");
const Container = @import("../elements/Container.zig");
const element = @import("../elements/element.zig");
const Image = @import("../elements/Image.zig");
const Text = @import("../elements/Text.zig");
const tooltip = @import("tooltip.zig");

const LabelledIcon = struct {
    icon: *Image,
    label: *Text,
};

const TalentTooltip = @This();
root: *Container = undefined,

decor: *Image = undefined,
icon: *Image = undefined,
title: *Text = undefined,
subtext: *Text = undefined,
line_break_one: *Image = undefined,
description: *Text = undefined,
line_break_two: *Image = undefined,
cost_icons: []LabelledIcon = &.{},

pub fn init(self: *TalentTooltip) !void {
    const tooltip_background_data = assets.getUiData("tooltip_background", 0);
    self.decor = try self.root.createChild(Image, .{
        .base = .{ .x = 0, .y = 0 },
        .image_data = .{ .nine_slice = .fromAtlasData(tooltip_background_data, 280, 0, 34, 34, 1, 1, 1.0) },
    });

    self.title = try self.root.createChild(Text, .{
        .base = .{ .x = 15, .y = 15 },
        .text_data = .{
            .text = "",
            .size = 14.0,
            .text_type = .bold_italic,
            .hori_align = .middle,
            .max_width = 280 - 15 * 2,
        },
    });

    self.subtext = try self.root.createChild(Text, .{
        .base = .{ .x = 15, .y = self.title.base.y + self.title.height() + 2 },
        .text_data = .{
            .text = "",
            .size = 12.0,
            .text_type = .medium_italic,
            .hori_align = .middle,
            .max_width = 280 - 15 * 2,
        },
    });

    const tooltip_line_spacer_data = assets.getUiData("tooltip_line_spacer_top", 0);
    self.line_break_one = try self.root.createChild(Image, .{
        .base = .{ .x = 15, .y = self.subtext.base.y + self.subtext.height() + 15 },
        .image_data = .{ .nine_slice = .fromAtlasData(tooltip_line_spacer_data, self.decor.width() - 30, 6, 16, 0, 1, 6, 1.0) },
    });

    self.description = try self.root.createChild(Text, .{
        .base = .{ .x = 6 + 2, .y = self.line_break_one.base.y + self.line_break_one.height() + 15 },
        .text_data = .{
            .text = "",
            .size = 12.0,
            .hori_align = .middle,
            .max_width = 280 - (6 + 2) * 2,
        },
    });
}

pub fn deinit(self: *TalentTooltip) void {
    element.destroy(self.root);
}

pub fn update(self: *TalentTooltip, params: tooltip.ParamsFor(TalentTooltip)) void {
    self.title.text_data.setText(params.data.name);

    switch (self.decor.image_data) {
        .nine_slice => |*nine_slice| nine_slice.h = self.root.height() + 15 * 2,
        .normal => |*image_data| image_data.scale_y = (self.root.height() + 15 * 2) / image_data.height(),
    }

    const left_x = params.x - self.decor.width() - 15;
    const up_y = params.y - self.decor.height() - 15;
    self.root.base.x = if (left_x < 0) params.x + 15 else left_x;
    self.root.base.y = if (up_y < 0) params.y + 15 else up_y;
}
