const std = @import("std");
const element = @import("../elements/element.zig");
const assets = @import("../../assets.zig");
const game_data = @import("shared").game_data;
const map = @import("../../game/map.zig");
const tooltip = @import("tooltip.zig");

const TextTooltip = @This();
const Container = @import("../elements/Container.zig");
const Image = @import("../elements/Image.zig");
const Text = @import("../elements/Text.zig");

root: *Container = undefined,

decor: *Image = undefined,
text: *Text = undefined,

pub fn init(self: *TextTooltip) !void {
    const tooltip_background_data = assets.getUiData("tooltip_background", 0);
    self.decor = try self.root.createChild(Image, .{
        .base = .{ .x = 0, .y = 0 },
        .image_data = .{ .nine_slice = .fromAtlasData(tooltip_background_data, 0, 0, 34, 34, 1, 1, 1.0) },
    });

    self.text = try self.root.createChild(Text, .{
        .base = .{ .x = 16, .y = 16 },
        .text_data = .{ .text = "", .size = 0 },
    });

    self.text.text_data.lock.lock();
    defer self.text.text_data.lock.unlock();
    self.text.text_data.recalculateAttributes();
}

pub fn deinit(self: *TextTooltip) void {
    element.destroy(self.root);
}

pub fn update(self: *TextTooltip, params: tooltip.ParamsFor(TextTooltip)) void {
    inline for (@typeInfo(element.TextData).@"struct".fields) |field| {
        comptime if (std.mem.eql(u8, field.name, "backing_buffer") or
            std.mem.eql(u8, field.name, "line_widths") or
            std.mem.eql(u8, field.name, "break_indices") or
            std.mem.eql(u8, field.name, "lock")) continue;

        @field(self.text.text_data, field.name) = @field(params.text_data, field.name);
    }

    {
        self.text.text_data.lock.lock();
        defer self.text.text_data.lock.unlock();
        self.text.text_data.recalculateAttributes();
    }

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

    const left_x = params.x - self.decor.width() - 15;
    const up_y = params.y - self.decor.height() - 15;
    self.root.base.x = if (left_x < 0) params.x + 15 else left_x;
    self.root.base.y = if (up_y < 0) params.y + 15 else up_y;
}
