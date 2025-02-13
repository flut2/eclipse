const std = @import("std");

const glfw = @import("glfw");

const assets = @import("../../assets.zig");
const input = @import("../../input.zig");
const main = @import("../../main.zig");
const CameraData = @import("../../render/CameraData.zig");
const systems = @import("../systems.zig");
const element = @import("element.zig");
const ElementBase = element.ElementBase;

const Input = @This();
base: ElementBase,
text_inlay_x: f32,
text_inlay_y: f32,
image_data: element.InteractableImageData,
cursor_image_data: element.ImageData,
text_data: element.TextData,
enterCallback: ?*const fn ([]const u8) void = null,
state: element.InteractableState = .none,
is_chat: bool = false,
// -1 means not selected
last_input: i64 = -1,
x_offset: f32 = 0.0,
index: u32 = 0,

pub fn mousePress(self: *Input, x: f32, y: f32, _: f32, _: f32, _: glfw.Mods) bool {
    if (!self.base.visible) return false;

    const in_bounds = element.intersects(self, x, y);
    if (in_bounds) {
        input.selected_input_field = self;
        self.last_input = 0;
        self.state = .pressed;
        return true;
    }

    return !(self.base.event_policy.pass_press or !in_bounds);
}

pub fn mouseRelease(self: *Input, x: f32, y: f32, _: f32, _: f32) bool {
    if (!self.base.visible) return false;
    const in_bounds = element.intersects(self, x, y);
    if (in_bounds) self.state = .hovered;
    return !(self.base.event_policy.pass_release or !in_bounds);
}

pub fn mouseMove(self: *Input, x: f32, y: f32, _: f32, _: f32) bool {
    if (!self.base.visible) return false;

    const in_bounds = element.intersects(self, x, y);
    if (in_bounds) {
        systems.hover_lock.lock();
        defer systems.hover_lock.unlock();
        systems.hover_target = element.UiElement{ .input_field = self }; // TODO: re-add RLS when fixed
        self.state = .hovered;
    } else self.state = .none;

    return !(self.base.event_policy.pass_move or !in_bounds);
}

pub fn init(self: *Input) void {
    if (self.text_data.scissor.isDefault())
        self.text_data.scissor = .{
            .min_x = 0,
            .min_y = 0,
            .max_x = self.width() - self.text_inlay_x * 2,
            .max_y = self.height() - self.text_inlay_y * 2,
        };

    {
        self.text_data.lock.lock();
        defer self.text_data.lock.unlock();
        self.text_data.recalculateAttributes();
    }

    switch (self.cursor_image_data) {
        .nine_slice => |*nine_slice| nine_slice.h = self.text_data.height,
        .normal => |*image_data| image_data.scale_y = self.text_data.height / image_data.height(),
    }
}

pub fn deinit(self: *Input) void {
    if (self == input.selected_input_field) input.selected_input_field = null;
    self.text_data.deinit();
}

pub fn draw(self: *Input, _: CameraData, x_offset: f32, y_offset: f32, time: i64) void {
    if (!self.base.visible) return;

    self.image_data.current(self.state).draw(self.base.x + x_offset, self.base.y + y_offset, self.base.scissor);

    const text_x = self.base.x + self.text_inlay_x + assets.padding + x_offset + self.x_offset;
    const text_y = self.base.y + self.text_inlay_y + assets.padding + y_offset;
    main.renderer.drawText(text_x, text_y, 1.0, &self.text_data, self.base.scissor);

    const flash_delay = 500 * std.time.us_per_ms;
    if (self.last_input != -1 and (time - self.last_input < flash_delay or @mod(@divFloor(time, flash_delay), 2) == 0)) {
        const cursor_x = text_x + self.text_data.width + 1.0;
        self.cursor_image_data.draw(cursor_x, text_y, self.base.scissor);
    }
}

pub fn width(self: Input) f32 {
    return @max(self.text_data.width, switch (self.image_data.current(self.state)) {
        .nine_slice => |nine_slice| nine_slice.w,
        .normal => |image_data| image_data.width(),
    });
}

pub fn height(self: Input) f32 {
    return @max(self.text_data.height, switch (self.image_data.current(self.state)) {
        .nine_slice => |nine_slice| nine_slice.h,
        .normal => |image_data| image_data.height(),
    });
}

pub fn texWRaw(self: Input) f32 {
    return @max(self.text_data.width, switch (self.image_data.current(self.state)) {
        .nine_slice => |nine_slice| nine_slice.w,
        .normal => |image_data| image_data.texWRaw(),
    });
}

pub fn texHRaw(self: Input) f32 {
    return @max(self.text_data.height, switch (self.image_data.current(self.state)) {
        .nine_slice => |nine_slice| nine_slice.h,
        .normal => |image_data| image_data.texHRaw(),
    });
}

pub fn clear(self: *Input) void {
    self.text_data.setText("");
    self.index = 0;
    self.inputUpdate();
}

pub fn inputUpdate(self: *Input) void {
    self.last_input = main.current_time;

    {
        self.text_data.lock.lock();
        defer self.text_data.lock.unlock();
        self.text_data.recalculateAttributes();
    }

    const cursor_width = switch (self.cursor_image_data) {
        .nine_slice => |nine_slice| if (nine_slice.alpha > 0) nine_slice.w else 0.0,
        .normal => |image_data| if (image_data.alpha > 0) image_data.width() else 0.0,
    };

    const img_width = switch (self.image_data.current(self.state)) {
        .nine_slice => |nine_slice| nine_slice.w,
        .normal => |image_data| image_data.width(),
    } - self.text_inlay_x * 2 - cursor_width;
    const offset = @max(0, self.text_data.width - img_width);
    self.x_offset = -offset;
    self.text_data.scissor.min_x = offset;
    self.text_data.scissor.max_x = offset + img_width;
}
