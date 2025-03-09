const std = @import("std");

const main = @import("../../main.zig");
const Renderer = @import("../../render/Renderer.zig");
const element = @import("element.zig");
const ElementBase = element.ElementBase;

const Text = @This();
base: ElementBase,
text_data: element.TextData,

pub fn init(self: *Text) void {
    self.text_data.recalculateAttributes();
}

pub fn deinit(self: *Text) void {
    self.text_data.deinit();
}

pub fn draw(
    self: *Text,
    generics: *std.ArrayListUnmanaged(Renderer.GenericData),
    sort_extras: *std.ArrayListUnmanaged(f32),
    x_offset: f32,
    y_offset: f32,
    _: i64,
) void {
    if (!self.base.visible) return;
    Renderer.drawText(generics, sort_extras, self.base.x + x_offset, self.base.y + y_offset, 1.0, &self.text_data, self.base.scissor);
}

pub fn width(self: Text) f32 {
    return self.text_data.width;
}

pub fn height(self: Text) f32 {
    return self.text_data.height;
}

pub fn texWRaw(self: Text) f32 {
    return self.text_data.width;
}

pub fn texHRaw(self: Text) f32 {
    return self.text_data.height;
}
