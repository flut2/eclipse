const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const network_data = shared.network_data;
const utils = shared.utils;
const f32i = utils.f32i;

const assets = @import("../../assets.zig");
const map = @import("../../game/map.zig");
const Player = @import("../../game/Player.zig");
const main = @import("../../main.zig");
const Container = @import("../elements/Container.zig");
const element = @import("../elements/element.zig");
const Image = @import("../elements/Image.zig");
const Text = @import("../elements/Text.zig");
const tooltip = @import("tooltip.zig");

const LabelledIcon = struct {
    base: *Container,
    icon: *Image,
    label: *Text,

    pub fn create(
        root: *Container,
        data: game_data.TextureData,
        x: f32,
        y: f32,
        resource_name: []const u8,
        req_amount: u32,
    ) !LabelledIcon {
        const tex_list = assets.atlas_data.get(data.sheet) orelse
            assets.ui_atlas_data.get(data.sheet) orelse
            return error.IconSheetNotFound;
        if (tex_list.len <= data.index) return error.IconIndexTooLarge;
        const icon = tex_list[data.index];

        const base = try root.createChild(Container, .{ .base = .{ .x = x, .y = y } });

        const ui_icon = try base.createChild(Image, .{
            .base = .{ .x = 0, .y = 0 },
            .image_data = .{ .normal = .{ .atlas_data = icon } },
        });

        const label = try base.createChild(Text, .{
            .base = .{ .x = icon.width() + 5, .y = 0 },
            .text_data = .{
                .text = "",
                .size = 12,
                .text_type = .medium_italic,
                .max_chars = 128,
                .color = 0xB3B3B3,
            },
        });
        label.text_data.setText(
            try std.fmt.bufPrint(label.text_data.backing_buffer, "{}x {s}", .{
                req_amount,
                resource_name,
            }),
        );

        return .{
            .base = base,
            .icon = ui_icon,
            .label = label,
        };
    }

    pub fn destroy(self: *LabelledIcon, root: *Container) void {
        root.destroyElement(self.base);
    }
};

const InfoTalentTooltip = @This();
root: *Container = undefined,

decor: *Image = undefined,
icon: *Image = undefined,
title: *Text = undefined,
subtext: *Text = undefined,
line_break_one: *Image = undefined,
description: *Text = undefined,
line_break_two: *Image = undefined,
cost_text: *Text = undefined,
requires_text: *Text = undefined,
costs: []LabelledIcon = &.{},
reqs: []LabelledIcon = &.{},

last_data_id: u16 = std.math.maxInt(u16),
last_class_id: u16 = std.math.maxInt(u16),

pub fn init(self: *InfoTalentTooltip) !void {
    const tooltip_background_data = assets.getUiData("tooltip_background", 0);
    self.decor = try self.root.createChild(Image, .{
        .base = .{ .x = 0, .y = 0 },
        .image_data = .{ .nine_slice = .fromAtlasData(tooltip_background_data, 360, 0, 34, 34, 1, 1, 1.0) },
    });

    self.icon = try self.root.createChild(Image, .{
        .base = .{ .x = 10, .y = 13 },
        .image_data = .{ .normal = .{ .atlas_data = undefined, .scale_x = 2.0, .scale_y = 2.0 } },
    });

    self.title = try self.root.createChild(Text, .{
        .base = .{ .x = 8 * 4 + 30, .y = 12 },
        .text_data = .{
            .text = "",
            .size = 14.0,
            .text_type = .bold_italic,
        },
    });

    self.subtext = try self.root.createChild(Text, .{
        .base = .{ .x = 8 * 4 + 30, .y = 12 + 5 + self.title.text_data.height },
        .text_data = .{
            .text = "",
            .size = 12.0,
            .max_chars = 128,
            .color = 0xB3B3B3,
        },
    });

    const tooltip_line_spacer_top_data = assets.getUiData("tooltip_line_spacer_top", 0);
    self.line_break_one = try self.root.createChild(Image, .{
        .base = .{ .x = 20, .y = self.subtext.base.y + self.subtext.height() + 10 },
        .image_data = .{
            .nine_slice = .fromAtlasData(tooltip_line_spacer_top_data, self.decor.width() - 40, 6, 16, 0, 1, 6, 1.0),
        },
    });

    self.description = try self.root.createChild(Text, .{
        .base = .{ .x = 10, .y = self.line_break_one.base.y + self.line_break_one.height() + 10 },
        .text_data = .{
            .text = "",
            .size = 12.0,
            .color = 0x9B9B9B,
            .max_width = self.decor.width() - 20,
        },
    });

    const tooltip_line_spacer_bottom_data = assets.getUiData("tooltip_line_spacer_bottom", 0);
    self.line_break_two = try self.root.createChild(Image, .{
        .base = .{ .x = 20, .y = self.description.base.y + self.description.text_data.height + 10 },
        .image_data = .{
            .nine_slice = .fromAtlasData(tooltip_line_spacer_bottom_data, self.decor.width() - 40, 6, 16, 0, 1, 6, 1.0),
        },
    });

    self.cost_text = try self.root.createChild(Text, .{
        .base = .{ .x = 10, .y = self.line_break_two.base.y + self.line_break_two.height() + 10 },
        .text_data = .{
            .text = "Costs:",
            .size = 12.0,
            .color = 0xB3B3B3,
        },
    });

    self.requires_text = try self.root.createChild(Text, .{
        .base = .{ .x = 10, .y = self.cost_text.base.y + self.cost_text.height() + 10, .visible = false },
        .text_data = .{
            .text = "Requires:",
            .size = 12.0,
            .color = 0xB3B3B3,
        },
    });
}

pub fn deinit(self: *InfoTalentTooltip) void {
    for (self.costs) |*cost| cost.destroy(self.root);
    main.allocator.free(self.costs);
    for (self.reqs) |*req| req.destroy(self.root);
    main.allocator.free(self.reqs);
    element.destroy(self.root);
}

pub fn update(self: *InfoTalentTooltip, params: tooltip.ParamsFor(InfoTalentTooltip)) void {
    defer {
        const left_x = params.x - self.decor.width() - 5;
        const up_y = params.y - self.decor.height() - 5;
        self.root.base.x = if (left_x < 0) params.x + 5 else left_x;
        self.root.base.y = if (up_y < 0) params.y + 5 else up_y;
    }

    if (self.last_data_id == params.index and self.last_class_id == params.class_id) return;
    self.last_data_id = params.index;
    self.last_class_id = params.class_id;

    const class_data = game_data.class.from_id.get(params.class_id) orelse return;

    const atlas_data = assets.ui_atlas_data.get(params.data.icon.sheet) orelse assets.atlas_data.get(params.data.icon.sheet);
    if (atlas_data) |data| {
        const icon = data[params.data.icon.index];
        self.icon.image_data.normal.atlas_data = icon;
        self.icon.base.x = 10 + (44 - icon.width() * self.icon.image_data.normal.scale_x) / 2.0;
        self.icon.base.y = 13 + (44 - icon.height() * self.icon.image_data.normal.scale_y) / 2.0;
    }

    self.decor.image_data.nine_slice = .fromAtlasData(assets.getUiData("tooltip_background", 0), 360, 0, 34, 34, 1, 1, 1.0);
    self.line_break_one.image_data.nine_slice =
        .fromAtlasData(assets.getUiData("tooltip_line_spacer_top", 0), self.decor.width() - 40, 6, 16, 0, 1, 6, 1.0);
    self.line_break_two.image_data.nine_slice =
        .fromAtlasData(assets.getUiData("tooltip_line_spacer_bottom", 0), self.decor.width() - 40, 6, 16, 0, 1, 6, 1.0);

    const talent_type_name = switch (params.data.type) {
        .keystone => "Keystone",
        .ability => "Ability",
        .minor => "Minor",
    };

    self.subtext.text_data.setText(std.fmt.bufPrint(
        self.subtext.text_data.backing_buffer,
        "{s} Talent",
        .{talent_type_name},
    ) catch "Buffer overflow");

    self.title.text_data.setText(params.data.name);
    self.description.text_data.setText(params.data.description);
    self.line_break_one.base.y = self.subtext.base.y + self.subtext.height() + 10;
    self.description.base.y = self.line_break_one.base.y + self.line_break_one.height() + 10;
    self.line_break_two.base.y = self.description.base.y + self.description.height() + 10;
    self.cost_text.base.y = self.line_break_two.base.y + self.line_break_two.height() + 10;

    for (self.costs) |*cost| cost.destroy(self.root);
    main.allocator.free(self.costs);
    self.costs = &.{};
    for (self.reqs) |*req| req.destroy(self.root);
    main.allocator.free(self.reqs);
    self.reqs = &.{};

    var costs: std.ArrayListUnmanaged(LabelledIcon) = .empty;
    const x = self.cost_text.base.x;
    var y = self.cost_text.base.y + self.cost_text.height() + 5;
    for (params.data.level_costs[0]) |lvl_cost| {
        const resource_data = game_data.resource.from_name.get(lvl_cost.name) orelse continue;
        const cost = LabelledIcon.create(self.root, resource_data.icon, x, y, resource_data.name, lvl_cost.amount) catch |e| {
            std.log.err("Adding cost labelled icon failed: {}", .{e});
            continue;
        };
        costs.append(main.allocator, cost) catch main.oomPanic();
        y += cost.base.height() + 5;
    }
    self.costs = costs.toOwnedSlice(main.allocator) catch main.oomPanic();

    if (params.data.requires.len > 0) {
        self.requires_text.base.visible = true;
        self.requires_text.base.y = y;
        y += self.requires_text.height() + 5;

        var reqs: std.ArrayListUnmanaged(LabelledIcon) = .empty;
        for (params.data.requires) |talent_req| {
            const talent_data = class_data.talents[talent_req.index];
            const req = LabelledIcon.create(self.root, talent_data.icon, x, y, talent_data.name, talent_req.level_per_aether) catch |e| {
                std.log.err("Adding requirement labelled icon failed: {}", .{e});
                continue;
            };
            reqs.append(main.allocator, req) catch main.oomPanic();
            y += req.base.height() + 5;
        }
        self.reqs = reqs.toOwnedSlice(main.allocator) catch main.oomPanic();

        const new_h = y + 5;
        switch (self.decor.image_data) {
            .nine_slice => |*nine_slice| nine_slice.h = new_h,
            .normal => |*image_data| image_data.scale_y = new_h / image_data.height(),
        }
    } else {
        self.requires_text.base.visible = false;
        const new_h = y + 5;
        switch (self.decor.image_data) {
            .nine_slice => |*nine_slice| nine_slice.h = new_h,
            .normal => |*image_data| image_data.scale_y = new_h / image_data.height(),
        }
    }
}
