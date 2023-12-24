const std = @import("std");
const element = @import("../element.zig");
const assets = @import("../../assets.zig");
const camera = @import("../../camera.zig");
const game_data = @import("../../game_data.zig");
const map = @import("../../map.zig");

pub const AbilityTooltip = struct {
    root: *element.Container = undefined,
    decor: *element.Image = undefined,
    image: *element.Image = undefined,
    title: *element.Text = undefined,
    cost_text: *element.Text = undefined,
    line_break: *element.Image = undefined,
    description: *element.Text = undefined,

    last_abil_name: []const u8 = &[0]u8{},
    _allocator: std.mem.Allocator = undefined,

    pub fn init(self: *AbilityTooltip, allocator: std.mem.Allocator) !void {
        self._allocator = allocator;

        self.root = try element.Container.create(allocator, .{
            .visible = false,
            .tooltip_container = true,
            .x = 0,
            .y = 0,
        });

        const tooltip_background_data = assets.getUiData("tooltip_background", 0);
        self.decor = try self.root.createElement(element.Image, .{
            .x = 0,
            .y = 0,
            .image_data = .{
                .nine_slice = element.NineSliceImageData.fromAtlasData(tooltip_background_data, 360, 360, 16, 16, 1, 1, 1.0),
            },
        });

        self.image = try self.root.createElement(element.Image, .{
            .x = 10,
            .y = 10,
            .image_data = .{
                .normal = .{
                    .atlas_data = undefined,
                    .glow = true,
                },
            },
        });

        self.title = try self.root.createElement(element.Text, .{
            .x = 8 * 4 + 30,
            .y = 10,
            .text_data = .{
                .text = "",
                .size = 16,
                .text_type = .bold,
            },
        });

        self.cost_text = try self.root.createElement(element.Text, .{
            .x = 8 * 4 + 30,
            .y = self.title.text_data._height + 10,
            .text_data = .{
                .text = "",
                .size = 14,
                .color = 0xB3B3B3,
                .max_chars = 128,
            },
        });

        const tooltip_line_spacer_data = assets.getUiData("tooltip_line_spacer", 0);
        self.line_break = try self.root.createElement(element.Image, .{
            .x = 20,
            .y = self.image.y + self.image.height() + 10,
            .image_data = .{
                .nine_slice = element.NineSliceImageData.fromAtlasData(tooltip_line_spacer_data, self.decor.width() - 40, 4, 13, 0, 1, 4, 1.0),
            },
        });

        self.description = try self.root.createElement(element.Text, .{
            .x = 10,
            .y = self.line_break.y + self.line_break.height() + 10,
            .text_data = .{
                .text = "",
                .size = 14,
                .max_width = self.decor.width() - 20,
                .color = 0x9B9B9B,
            },
        });
    }

    pub fn deinit(self: *AbilityTooltip) void {
        self.root.destroy();
    }

    pub fn update(self: *AbilityTooltip, x: f32, y: f32, props: game_data.Ability) void {
        const left_x = x - self.decor.width() - 15;
        const up_y = y - self.decor.height() - 15;
        self.root.x = if (left_x < 0) x + 15 else left_x;
        self.root.y = if (up_y < 0) y + 15 else up_y;

        if (!std.mem.eql(u8, self.last_abil_name, props.name)) {
            if (assets.ui_atlas_data.get(props.icon.sheet)) |data| {
                self.image.image_data.normal.atlas_data = data[props.icon.index];
            }

            self.title.text_data.text = props.name;
            self.title.text_data.recalculateAttributes(self._allocator);

            const has_mana_cost = props.mana_cost > 0;
            const has_health_cost = props.health_cost > 0;
            if (!has_mana_cost and !has_health_cost) {
                self.cost_text.text_data.text = "No Cost";
            } else {
                const mana_icon = comptime game_data.StatType.max_mp.toControlCode();
                const health_icon = comptime game_data.StatType.max_hp.toControlCode();

                if (has_health_cost and has_mana_cost) {
                    self.cost_text.text_data.text = std.fmt.bufPrint(
                        self.cost_text.text_data._backing_buffer,
                        "{d} " ++ mana_icon ++ " {d} " ++ health_icon,
                        .{ props.mana_cost, props.health_cost },
                    ) catch self.cost_text.text_data.text;
                } else if (has_health_cost) {
                    self.cost_text.text_data.text = std.fmt.bufPrint(
                        self.cost_text.text_data._backing_buffer,
                        "{d} " ++ health_icon,
                        .{props.health_cost},
                    ) catch self.cost_text.text_data.text;
                } else {
                    self.cost_text.text_data.text = std.fmt.bufPrint(
                        self.cost_text.text_data._backing_buffer,
                        "{d} " ++ mana_icon,
                        .{props.mana_cost},
                    ) catch self.cost_text.text_data.text;
                }
            }

            self.description.text_data.text = props.description;
            self.description.text_data.recalculateAttributes(self._allocator);

            self.line_break.y = self.image.y + self.image.height() + 10;
            self.description.y = self.line_break.y + 10;

            const new_h = self.description.y + self.description.text_data._height + 10;
            switch (self.decor.image_data) {
                .nine_slice => |*nine_slice| nine_slice.h = new_h,
                .normal => |*image_data| image_data.scale_y = new_h / image_data.height(),
            }

            self.last_abil_name = props.name;
        }
    }
};
