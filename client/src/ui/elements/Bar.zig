const element = @import("element.zig");
const render = @import("../../render.zig");

const Bar = @This();
const ElementBase = element.ElementBase;

base: ElementBase,
image_data: element.ImageData,
text_data: element.TextData,

pub fn init(self: *Bar) void {
    self.text_data.lock.lock();
    defer self.text_data.lock.unlock();
    self.text_data.recalculateAttributes(self.base.allocator);
}

pub fn deinit(self: *Bar) void {
    self.text_data.deinit(self.base.allocator);
}

pub fn draw(self: *Bar, _: render.CameraData, x_offset: f32, y_offset: f32, _: i64) void {
    if (!self.base.visible) return;
    const w, const h = switch (self.image_data) {
        .nine_slice => |nine_slice| .{ nine_slice.w, nine_slice.h },
        .normal => |normal| .{ normal.texWRaw(), normal.texHRaw() },
    };

    self.image_data.draw(self.base.x + x_offset, self.base.y + y_offset);
    render.drawText(
        self.base.x + (w - self.text_data.width) / 2 + x_offset,
        self.base.y + (h - self.text_data.height) / 2 + y_offset,
        1.0,
        &self.text_data,
        .{},
    );
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
