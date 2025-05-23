const std = @import("std");

const main = @import("../../main.zig");
const Renderer = @import("../../render/Renderer.zig");
const element = @import("element.zig");
const ElementBase = element.ElementBase;

const Bar = @This();
base: ElementBase,
image_data: element.ImageData,
text_data: element.TextData,

pub fn init(self: *Bar) void {
    self.text_data.max_width = self.width();
    self.text_data.max_height = self.height();
    self.text_data.vert_align = .middle;
    self.text_data.hori_align = .middle;
    self.text_data.recalculateAttributes();
}

pub fn deinit(self: *Bar) void {
    self.text_data.deinit();
}

pub fn draw(
    self: *Bar,
    generics: *std.ArrayListUnmanaged(Renderer.GenericData),
    sort_extras: *std.ArrayListUnmanaged(f32),
    x_offset: f32,
    y_offset: f32,
    _: i64,
) void {
    if (!self.base.visible) return;
    self.image_data.draw(generics, sort_extras, self.base.x + x_offset, self.base.y + y_offset, self.base.scissor);
    Renderer.drawText(generics, sort_extras, self.base.x + x_offset, self.base.y + y_offset, 1.0, &self.text_data, .{});
}

pub fn width(self: Bar) f32 {
    return switch (self.image_data) {
        .nine_slice => |nine_slice| nine_slice.w,
        .normal => |image_data| image_data.width(),
    };
}

pub fn height(self: Bar) f32 {
    return switch (self.image_data) {
        .nine_slice => |nine_slice| nine_slice.h,
        .normal => |image_data| image_data.height(),
    };
}

pub fn texWRaw(self: Bar) f32 {
    return switch (self.image_data) {
        .nine_slice => |nine_slice| nine_slice.w,
        .normal => |image_data| image_data.texWRaw(),
    };
}

pub fn texHRaw(self: Bar) f32 {
    return switch (self.image_data) {
        .nine_slice => |nine_slice| nine_slice.h,
        .normal => |image_data| image_data.texHRaw(),
    };
}
