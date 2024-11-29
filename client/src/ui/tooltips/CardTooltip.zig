const std = @import("std");
const element = @import("../elements/element.zig");
const assets = @import("../../assets.zig");
const game_data = @import("shared").game_data;
const map = @import("../../game/map.zig");
const tooltip = @import("tooltip.zig");

const CardTooltip = @This();
const Container = @import("../elements/Container.zig");
const Image = @import("../elements/Image.zig");
const Text = @import("../elements/Text.zig");

root: *Container = undefined,

decor: *Image = undefined,
title: *Text = undefined,
rarity: *Text = undefined,
line_break: *Image = undefined,
description: *Text = undefined,

pub fn init(self: *CardTooltip) !void {
    const tooltip_background_data = assets.getUiData("tooltip_background", 0);
    self.decor = try self.root.createChild(Image, .{
        .base = .{ .x = 0, .y = 0 },
        .image_data = .{ .nine_slice = .fromAtlasData(tooltip_background_data, 280, 0, 34, 34, 1, 1, 1.0) },
    });

    self.title = try self.root.createChild(Text, .{
        .base = .{ .x = 15, .y = 15 },
        .text_data = .{
            .text = undefined,
            .size = 14.0,
            .text_type = .bold_italic,
            .hori_align = .middle,
            .max_width = 280 - 15 * 2,
        },
    });
    self.title.text_data.setText("");

    self.rarity = try self.root.createChild(Text, .{
        .base = .{ .x = 15, .y = self.title.base.y + self.title.height() + 2 },
        .text_data = .{
            .text = undefined,
            .size = 12.0,
            .text_type = .medium_italic,
            .hori_align = .middle,
            .max_width = 280 - 15 * 2,
        },
    });
    self.rarity.text_data.setText("");

    const tooltip_line_spacer_data = assets.getUiData("tooltip_line_spacer_top", 0);
    self.line_break = try self.root.createChild(Image, .{
        .base = .{ .x = 15, .y = self.rarity.base.y + self.rarity.height() + 15 },
        .image_data = .{
            .nine_slice = .fromAtlasData(tooltip_line_spacer_data, self.decor.width() - 30, 6, 16, 0, 1, 6, 1.0),
        },
    });

    self.description = try self.root.createChild(Text, .{
        .base = .{ .x = 15, .y = self.line_break.base.y + self.line_break.height() + 15 },
        .text_data = .{
            .text = undefined,
            .size = 12.0,
            .hori_align = .middle,
            .max_width = 280 - 15 * 2,
        },
    });
    self.description.text_data.setText("");
}

pub fn deinit(self: *CardTooltip) void {
    element.destroy(self.root);
}

pub fn update(self: *CardTooltip, params: tooltip.ParamsFor(CardTooltip)) void {
    self.title.text_data.setText(params.data.name);
    self.rarity.text_data.setText(switch (params.data.rarity) {
        .mythic => "Mythic Card",
        .legendary => "Legendary Card",
        .epic => "Epic Card",
        .rare => "Rare Card",
        .common => "Common Card",
    });
    self.description.text_data.setText(params.data.description);

    self.title.text_data.color, self.description.text_data.color = switch (params.data.rarity) {
        .mythic => .{ 0xE54E4E, 0xFFBFBF },
        .legendary => .{ 0xE5B84E, 0xFFEBBF },
        .epic => .{ 0x9F50E5, 0xE1BFFF },
        .rare => .{ 0x5066E5, 0xBFC7FF },
        .common => .{ 0xE5CCAC, 0xFFF3E5 },
    };
    self.rarity.text_data.color = self.description.text_data.color;

    const tooltip_background_data, const tooltip_line_spacer_data = switch (params.data.rarity) {
        .mythic => .{ assets.getUiData("tooltip_background_mythic", 0), assets.getUiData("tooltip_line_spacer_top_mythic", 0) },
        .legendary => .{ assets.getUiData("tooltip_background_legendary", 0), assets.getUiData("tooltip_line_spacer_top_legendary", 0) },
        .epic => .{ assets.getUiData("tooltip_background_epic", 0), assets.getUiData("tooltip_line_spacer_top_epic", 0) },
        .rare => .{ assets.getUiData("tooltip_background_rare", 0), assets.getUiData("tooltip_line_spacer_top_rare", 0) },
        .common => .{ assets.getUiData("tooltip_background", 0), assets.getUiData("tooltip_line_spacer_top", 0) },
    };
    self.decor.image_data.nine_slice = .fromAtlasData(tooltip_background_data, 280, 0, 34, 34, 1, 1, 1.0);
    self.line_break.image_data.nine_slice = .fromAtlasData(tooltip_line_spacer_data, self.decor.width() - 30, 6, 16, 0, 1, 6, 1.0);

    switch (self.decor.image_data) {
        .nine_slice => |*nine_slice| nine_slice.h = self.root.height() + 15 * 2,
        .normal => |*image_data| image_data.scale_y = (self.root.height() + 15 * 2) / image_data.height(),
    }

    const left_x = params.x - self.decor.width() - 15;
    const up_y = params.y - self.decor.height() - 15;
    self.root.base.x = if (left_x < 0) params.x + 15 else left_x;
    self.root.base.y = if (up_y < 0) params.y + 15 else up_y;
}
