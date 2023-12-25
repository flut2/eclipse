const std = @import("std");
const element = @import("../element.zig");
const assets = @import("../../assets.zig");
const camera = @import("../../camera.zig");
const game_data = @import("../../game_data.zig");
const map = @import("../../map.zig");

pub const TextTooltip = struct {
    root: *element.Container = undefined,
    decor: *element.Image = undefined,
    text: *element.Text = undefined,

    _allocator: std.mem.Allocator = undefined,

    pub fn init(self: *TextTooltip, allocator: std.mem.Allocator) !void {
        self._allocator = allocator;

        self.root = try element.Container.create(allocator, .{
            .visible = false,
            .layer = .tooltip,
            .x = 0,
            .y = 0,
        });

        const tooltip_background_data = assets.getUiData("tooltip_background", 0);
        self.decor = try self.root.createElement(element.Image, .{
            .x = 0,
            .y = 0,
            .image_data = .{
                .nine_slice = element.NineSliceImageData.fromAtlasData(tooltip_background_data, 0, 0, 14, 14, 2, 2, 1.0),
            },
        });

        self.text = try self.root.createElement(element.Text, .{
            .x = 16,
            .y = 16,
            .text_data = undefined, // must be set in update
        });
    }

    pub fn deinit(self: *TextTooltip) void {
        self.root.destroy();
    }

    pub fn update(self: *TextTooltip, x: f32, y: f32, text_data: element.TextData) void {
        self.text.text_data = text_data;
        switch (self.decor.image_data) {
            .nine_slice => |*nine_slice| {
                nine_slice.w = self.text.width() + 16 * 2;
                nine_slice.h = self.text.height() + 16 * 2;
            },
            .normal => |*image_data| {
                image_data.scale_x = (self.text.width() + 16 * 2) / image_data.width();
                image_data.scale_y = (self.text.height() + 16 * 2) / image_data.height();
            },
        }

        const left_x = x - self.decor.width() - 15;
        const up_y = y - self.decor.height() - 15;
        self.root.x = if (left_x < 0) x + 15 else left_x;
        self.root.y = if (up_y < 0) y + 15 else up_y;
    }
};
