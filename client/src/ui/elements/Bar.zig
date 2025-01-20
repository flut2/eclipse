const main = @import("../../main.zig");
const CameraData = @import("../../render/CameraData.zig");
const element = @import("element.zig");
const ElementBase = element.ElementBase;

const Bar = @This();
base: ElementBase,
image_data: element.ImageData,
text_data: element.TextData,

pub fn init(self: *Bar) void {
    self.text_data.lock.lock();
    defer self.text_data.lock.unlock();
    self.text_data.max_width = self.width();
    self.text_data.max_height = self.height();
    self.text_data.vert_align = .middle;
    self.text_data.hori_align = .middle;
    self.text_data.recalculateAttributes();
}

pub fn deinit(self: *Bar) void {
    self.text_data.deinit();
}

pub fn draw(self: *Bar, _: CameraData, x_offset: f32, y_offset: f32, _: i64) void {
    if (!self.base.visible) return;
    self.image_data.draw(self.base.x + x_offset, self.base.y + y_offset, self.base.scissor);
    main.renderer.drawText(self.base.x + x_offset, self.base.y + y_offset, 1.0, &self.text_data, .{});
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
