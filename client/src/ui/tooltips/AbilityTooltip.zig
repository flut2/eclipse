const std = @import("std");

const game_data = @import("shared").game_data;

const assets = @import("../../assets.zig");
const map = @import("../../game/map.zig");
const Container = @import("../elements/Container.zig");
const element = @import("../elements/element.zig");
const Image = @import("../elements/Image.zig");
const Text = @import("../elements/Text.zig");
const tooltip = @import("tooltip.zig");

const AbilityTooltip = @This();
root: *Container = undefined,

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
        .base = .{ .x = 10, .y = 13 },
        .image_data = .{ .normal = .{ .atlas_data = undefined, .scale_x = 2.0, .scale_y = 2.0 } },
    });

    self.title = try self.root.createChild(Text, .{
        .base = .{ .x = 8 * 4 + 30, .y = 12 },
        .text_data = .{
            .text = "",
            .size = 14,
            .text_type = .bold_italic,
        },
    });

    self.subtext = try self.root.createChild(Text, .{
        .base = .{ .x = 8 * 4 + 30, .y = 12 + 5 + self.title.text_data.height },
        .text_data = .{
            .text = "",
            .size = 12,
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
            .size = 12,
            .max_width = self.decor.width() - 20,
            .color = 0x9B9B9B,
        },
    });
}

pub fn deinit(self: *AbilityTooltip) void {
    element.destroy(self.root);
}

pub fn update(self: *AbilityTooltip, params: tooltip.ParamsFor(AbilityTooltip)) void {
    defer {
        const left_x = params.x - self.decor.width() - 5;
        const up_y = params.y - self.decor.height() - 5;
        self.root.base.x = if (left_x < 0) params.x + 5 else left_x;
        self.root.base.y = if (up_y < 0) params.y + 5 else up_y;
    }

    if (std.mem.eql(u8, self.last_abil_name, params.data.name)) return;

    if (assets.ui_atlas_data.get(params.data.icon.sheet)) |data|
        self.image.image_data.normal.atlas_data = data[params.data.icon.index];

    const cooldown_icon = "&img=\"misc_big,69\"";
    const has_mana_cost = params.data.mana_cost > 0;
    const has_health_cost = params.data.health_cost > 0;
    const has_gold_cost = params.data.gold_cost > 0;
    if (!has_mana_cost and !has_health_cost and !has_gold_cost) {
        self.subtext.text_data.setText(std.fmt.bufPrint(
            self.subtext.text_data.backing_buffer,
            "No Cost &col=\"222222\"|&reset {d:.1}s " ++ cooldown_icon,
            .{params.data.cooldown},
        ) catch "Buffer overflow");
    } else {
        const mana_icon = comptime game_data.StatIncreaseData.toControlCode(.{ .max_mp = undefined });
        const health_icon = comptime game_data.StatIncreaseData.toControlCode(.{ .max_hp = undefined });
        const gold_icon = "&img=\"misc,20\"";

        if (has_health_cost and has_mana_cost) {
            self.subtext.text_data.setText(std.fmt.bufPrint(
                self.subtext.text_data.backing_buffer,
                "{d} " ++ mana_icon ++ " {d} " ++ health_icon ++ " &col=\"222222\"|&reset {d:.1}s " ++ cooldown_icon,
                .{ params.data.mana_cost, params.data.health_cost, params.data.cooldown },
            ) catch "Buffer overflow");
        } else if (has_health_cost) {
            self.subtext.text_data.setText(std.fmt.bufPrint(
                self.subtext.text_data.backing_buffer,
                "{d} " ++ health_icon ++ " &col=\"222222\"|&reset {d:.1}s " ++ cooldown_icon,
                .{ params.data.health_cost, params.data.cooldown },
            ) catch "Buffer overflow");
        } else if (has_mana_cost) {
            self.subtext.text_data.setText(std.fmt.bufPrint(
                self.subtext.text_data.backing_buffer,
                "{d} " ++ mana_icon ++ " &col=\"222222\"|&reset {d:.1}s " ++ cooldown_icon,
                .{ params.data.mana_cost, params.data.cooldown },
            ) catch "Buffer overflow");
        } else {
            self.subtext.text_data.setText(std.fmt.bufPrint(
                self.subtext.text_data.backing_buffer,
                "{d} " ++ gold_icon ++ " &col=\"222222\"|&reset {d:.1}s " ++ cooldown_icon,
                .{ params.data.gold_cost, params.data.cooldown },
            ) catch "Buffer overflow");
        }
    }

    self.title.text_data.setText(params.data.name);
    self.description.text_data.setText(params.data.description);

    self.line_break.base.y = self.image.base.y + self.image.height() + 10;
    self.description.base.y = self.line_break.base.y + 10;

    const new_h = self.description.base.y + self.description.text_data.height + 10;
    switch (self.decor.image_data) {
        .nine_slice => |*nine_slice| nine_slice.h = new_h,
        .normal => |*image_data| image_data.scale_y = new_h / image_data.height(),
    }

    self.last_abil_name = params.data.name;
}
