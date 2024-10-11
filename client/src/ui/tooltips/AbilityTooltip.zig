const std = @import("std");
const element = @import("../elements/element.zig");
const assets = @import("../../assets.zig");
const game_data = @import("shared").game_data;
const map = @import("../../game/map.zig");
const tooltip = @import("tooltip.zig");

const AbilityTooltip = @This();
const Container = @import("../elements/Container.zig");
const Image = @import("../elements/Image.zig");
const Text = @import("../elements/Text.zig");

root: *Container = undefined,
allocator: std.mem.Allocator = undefined,

decor: *Image = undefined,
image: *Image = undefined,
title: *Text = undefined,
subtext: *Text = undefined,
line_break: *Image = undefined,
description: *Text = undefined,
last_abil_name: []const u8 = &[0]u8{},

pub fn init(self: *AbilityTooltip) !void {
    const tooltip_background_data = assets.getUiData("tooltip_background", 0);
    self.decor = try self.root.createChild(Image, .{
        .base = .{ .x = 0, .y = 0 },
        .image_data = .{
            .nine_slice = .fromAtlasData(tooltip_background_data, 360, 360, 34, 34, 1, 1, 1.0),
        },
    });

    self.image = try self.root.createChild(Image, .{
        .base = .{ .x = 10, .y = 10 },
        .image_data = .{ .normal = .{ .atlas_data = undefined } },
    });

    self.title = try self.root.createChild(Text, .{
        .base = .{ .x = 8 * 4 + 30, .y = 9 },
        .text_data = .{
            .text = "",
            .size = 16,
            .text_type = .bold_italic,
        },
    });

    self.subtext = try self.root.createChild(Text, .{
        .base = .{ .x = 8 * 4 + 30, .y = self.title.text_data.height + 9 },
        .text_data = .{
            .text = "",
            .size = 14,
            .color = 0xB3B3B3,
            .max_chars = 128,
        },
    });

    const tooltip_line_spacer_data = assets.getUiData("tooltip_line_spacer_top", 0);
    self.line_break = try self.root.createChild(Image, .{
        .base = .{ .x = 20, .y = self.image.base.y + self.image.height() + 15 },
        .image_data = .{
            .nine_slice = .fromAtlasData(tooltip_line_spacer_data, self.decor.width() - 40, 6, 16, 0, 1, 6, 1.0),
        },
    });

    self.description = try self.root.createChild(Text, .{
        .base = .{ .x = 10, .y = self.line_break.base.y + self.line_break.height() + 10 },
        .text_data = .{
            .text = "",
            .size = 14,
            .max_width = self.decor.width() - 20,
            .color = 0x9B9B9B,
        },
    });
}

pub fn deinit(self: *AbilityTooltip) void {
    element.destroy(self.root);
}

pub fn update(self: *AbilityTooltip, params: tooltip.ParamsFor(AbilityTooltip)) void {
    const left_x = params.x - self.decor.width() - 15;
    const up_y = params.y - self.decor.height() - 15;
    self.root.base.x = if (left_x < 0) params.x + 15 else left_x;
    self.root.base.y = if (up_y < 0) params.y + 15 else up_y;

    if (!std.mem.eql(u8, self.last_abil_name, params.props.name)) {
        if (assets.ui_atlas_data.get(params.props.icon.sheet)) |data| {
            self.image.image_data.normal.atlas_data = data[params.props.icon.index];
        }

        self.title.text_data.setText(params.props.name, self.allocator);

        const cooldown_icon = "&img=\"misc_big,69\"";
        const has_mana_cost = params.props.mana_cost > 0;
        const has_health_cost = params.props.health_cost > 0;
        const has_gold_cost = params.props.gold_cost > 0;
        if (!has_mana_cost and !has_health_cost and !has_gold_cost) {
            self.subtext.text_data.text = std.fmt.bufPrint(
                self.subtext.text_data.backing_buffer,
                "No Cost | {d:.1}s " ++ cooldown_icon,
                .{params.props.cooldown},
            ) catch self.subtext.text_data.text;
        } else {
            const mana_icon = comptime game_data.StatIncreaseData.toControlCode(.{ .max_mp = undefined });
            const health_icon = comptime game_data.StatIncreaseData.toControlCode(.{ .max_hp = undefined });
            const gold_icon = "&img=\"misc,20\"";

            if (has_health_cost and has_mana_cost) {
                self.subtext.text_data.text = std.fmt.bufPrint(
                    self.subtext.text_data.backing_buffer,
                    "{d} " ++ mana_icon ++ " {d} " ++ health_icon ++ " | {d:.1}s " ++ cooldown_icon,
                    .{ params.props.mana_cost, params.props.health_cost, params.props.cooldown },
                ) catch self.subtext.text_data.text;
            } else if (has_health_cost) {
                self.subtext.text_data.text = std.fmt.bufPrint(
                    self.subtext.text_data.backing_buffer,
                    "{d} " ++ health_icon ++ " | {d:.1}s " ++ cooldown_icon,
                    .{ params.props.health_cost, params.props.cooldown },
                ) catch self.subtext.text_data.text;
            } else if (has_mana_cost) {
                self.subtext.text_data.text = std.fmt.bufPrint(
                    self.subtext.text_data.backing_buffer,
                    "{d} " ++ mana_icon ++ " | {d:.1}s " ++ cooldown_icon,
                    .{ params.props.mana_cost, params.props.cooldown },
                ) catch self.subtext.text_data.text;
            } else {
                self.subtext.text_data.text = std.fmt.bufPrint(
                    self.subtext.text_data.backing_buffer,
                    "{d} " ++ gold_icon ++ " | {d:.1}s " ++ cooldown_icon,
                    .{ params.props.gold_cost, params.props.cooldown },
                ) catch self.subtext.text_data.text;
            }
        }

        self.description.text_data.setText(params.props.description, self.allocator);

        self.line_break.base.y = self.image.base.y + self.image.height() + 10;
        self.description.base.y = self.line_break.base.y + 10;

        const new_h = self.description.base.y + self.description.text_data.height + 10;
        switch (self.decor.image_data) {
            .nine_slice => |*nine_slice| nine_slice.h = new_h,
            .normal => |*image_data| image_data.scale_y = new_h / image_data.height(),
        }

        self.last_abil_name = params.props.name;
    }
}
