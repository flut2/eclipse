const std = @import("std");
const element = @import("../element.zig");
const assets = @import("../../assets.zig");
const camera = @import("../../camera.zig");
const game_data = @import("../../game_data.zig");
const map = @import("../../game/map.zig");
const tooltip = @import("tooltip.zig");

pub const AbilityTooltip = struct {
    root: *element.Container = undefined,
    decor: *element.Image = undefined,
    image: *element.Image = undefined,
    title: *element.Text = undefined,
    cost_text: *element.Text = undefined,
    line_break: *element.Image = undefined,
    description: *element.Text = undefined,

    last_abil_name: []const u8 = &[0]u8{},
    allocator: std.mem.Allocator = undefined,

    pub fn init(self: *AbilityTooltip, allocator: std.mem.Allocator) !void {
        self.allocator = allocator;

        self.root = try element.create(allocator, element.Container{
            .visible = false,
            .layer = .tooltip,
            .x = 0,
            .y = 0,
        });

        const tooltip_background_data = assets.getUiData("tooltip_background", 0);
        self.decor = try self.root.createChild(element.Image{
            .x = 0,
            .y = 0,
            .image_data = .{
                .nine_slice = element.NineSliceImageData.fromAtlasData(tooltip_background_data, 360, 360, 34, 34, 1, 1, 1.0),
            },
        });

        self.image = try self.root.createChild(element.Image{
            .x = 10,
            .y = 10,
            .image_data = .{ .normal = .{ .atlas_data = undefined } },
        });

        self.title = try self.root.createChild(element.Text{
            .x = 8 * 4 + 30,
            .y = 10,
            .text_data = .{
                .text = "",
                .size = 16,
                .text_type = .bold_italic,
            },
        });

        self.cost_text = try self.root.createChild(element.Text{
            .x = 8 * 4 + 30,
            .y = self.title.text_data.height + 10,
            .text_data = .{
                .text = "",
                .size = 14,
                .color = 0xB3B3B3,
                .max_chars = 128,
            },
        });

        const tooltip_line_spacer_data = assets.getUiData("tooltip_line_spacer_top", 0);
        self.line_break = try self.root.createChild(element.Image{
            .x = 20,
            .y = self.image.y + self.image.height() + 15,
            .image_data = .{
                .nine_slice = element.NineSliceImageData.fromAtlasData(tooltip_line_spacer_data, self.decor.width() - 40, 6, 16, 0, 1, 6, 1.0),
            },
        });

        self.description = try self.root.createChild(element.Text{
            .x = 10,
            .y = self.line_break.y + self.line_break.height() + 20,
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
        self.root.x = if (left_x < 0) params.x + 15 else left_x;
        self.root.y = if (up_y < 0) params.y + 15 else up_y;

        if (!std.mem.eql(u8, self.last_abil_name, params.props.name)) {
            if (assets.ui_atlas_data.get(params.props.icon.sheet)) |data| {
                self.image.image_data.normal.atlas_data = data[params.props.icon.index];
            }

            self.title.text_data.setText(params.props.name, self.allocator);

            const has_mana_cost = params.props.mana_cost > 0;
            const has_health_cost = params.props.health_cost > 0;
            if (!has_mana_cost and !has_health_cost) {
                self.cost_text.text_data.text = "No Cost";
            } else {
                const mana_icon = comptime game_data.StatType.max_mp.toControlCode();
                const health_icon = comptime game_data.StatType.max_hp.toControlCode();

                if (has_health_cost and has_mana_cost) {
                    self.cost_text.text_data.text = std.fmt.bufPrint(
                        self.cost_text.text_data.backing_buffer,
                        "{d} " ++ mana_icon ++ " {d} " ++ health_icon,
                        .{ params.props.mana_cost, params.props.health_cost },
                    ) catch self.cost_text.text_data.text;
                } else if (has_health_cost) {
                    self.cost_text.text_data.text = std.fmt.bufPrint(
                        self.cost_text.text_data.backing_buffer,
                        "{d} " ++ health_icon,
                        .{params.props.health_cost},
                    ) catch self.cost_text.text_data.text;
                } else {
                    self.cost_text.text_data.text = std.fmt.bufPrint(
                        self.cost_text.text_data.backing_buffer,
                        "{d} " ++ mana_icon,
                        .{params.props.mana_cost},
                    ) catch self.cost_text.text_data.text;
                }
            }

            self.description.text_data.setText(params.props.description, self.allocator);

            self.line_break.y = self.image.y + self.image.height() + 10;
            self.description.y = self.line_break.y + 20;

            const new_h = self.description.y + self.description.text_data.height + 10;
            switch (self.decor.image_data) {
                .nine_slice => |*nine_slice| nine_slice.h = new_h,
                .normal => |*image_data| image_data.scale_y = new_h / image_data.height(),
            }

            self.last_abil_name = params.props.name;
        }
    }
};
