const std = @import("std");
const element = @import("element.zig");
const glfw = @import("zglfw");
const tooltip = @import("../tooltips/tooltip.zig");
const render = @import("../../render.zig");
const main = @import("../../main.zig");

const Item = @This();
const ElementBase = element.ElementBase;

base: ElementBase,
background_x: f32,
background_y: f32,
image_data: element.ImageData,
drag_start_callback: *const fn (*Item) void,
drag_end_callback: *const fn (*Item) void,
double_click_callback: *const fn (*Item) void,
shift_click_callback: *const fn (*Item) void,
draggable: bool = false,
// don't set this to anything, it's used for item rarity backgrounds
background_image_data: ?element.ImageData = null,
is_dragging: bool = false,
drag_start_x: f32 = 0,
drag_start_y: f32 = 0,
drag_offset_x: f32 = 0,
drag_offset_y: f32 = 0,
last_click_time: i64 = 0,
item: u16 = std.math.maxInt(u16),

pub fn mousePress(self: *Item, x: f32, y: f32, _: f32, _: f32, mods: glfw.Mods) bool {
    if (!self.base.visible or !self.draggable) return false;

    const in_bounds = element.intersects(self, x, y);
    if (in_bounds) {
        if (mods.shift) {
            self.shift_click_callback(self);
            return true;
        }

        if (self.last_click_time + 333 * std.time.us_per_ms > main.current_time) {
            self.double_click_callback(self);
            return true;
        }

        self.is_dragging = true;
        self.drag_start_x = self.base.x;
        self.drag_start_y = self.base.y;
        self.drag_offset_x = self.base.x - x;
        self.drag_offset_y = self.base.y - y;
        self.last_click_time = main.current_time;
        self.drag_start_callback(self);
        return true;
    }

    return !(self.base.event_policy.pass_press or !in_bounds);
}

pub fn mouseRelease(self: *Item, x: f32, y: f32, _: f32, _: f32) bool {
    if (!self.is_dragging) return false;
    self.is_dragging = false;
    self.drag_end_callback(self);
    return !(self.base.event_policy.pass_release or !element.intersects(self, x, y));
}

pub fn mouseMove(self: *Item, x: f32, y: f32, x_offset: f32, y_offset: f32) bool {
    if (!self.base.visible) return false;

    const in_bounds = element.intersects(self, x, y);
    if (!self.is_dragging) {
        if (in_bounds) {
            tooltip.switchTooltip(.item, .{
                .x = x + x_offset,
                .y = y + y_offset,
                .item = self.item,
            });
            return true;
        }

        return false;
    }

    self.base.x = x + self.drag_offset_x;
    self.base.y = y + self.drag_offset_y;
    return !(self.base.event_policy.pass_move or !in_bounds);
}

pub fn draw(self: Item, _: render.CameraData, x_offset: f32, y_offset: f32, _: i64) void {
    if (!self.base.visible) return;
    if (self.background_image_data) |background_image_data| background_image_data.draw(self.background_x + x_offset, self.background_y + y_offset);
    self.image_data.draw(self.base.x + x_offset, self.base.y + y_offset);
}

pub fn width(self: Item) f32 {
    switch (self.image_data) {
        .nine_slice => |nine_slice| return nine_slice.w,
        .normal => |image_data| return image_data.width(),
    }
}

pub fn height(self: Item) f32 {
    switch (self.image_data) {
        .nine_slice => |nine_slice| return nine_slice.h,
        .normal => |image_data| return image_data.height(),
    }
}

pub fn texWRaw(self: Item) f32 {
    switch (self.image_data) {
        .nine_slice => |nine_slice| return nine_slice.w,
        .normal => |image_data| return image_data.texWRaw(),
    }
}

pub fn texHRaw(self: Item) f32 {
    switch (self.image_data) {
        .nine_slice => |nine_slice| return nine_slice.h,
        .normal => |image_data| return image_data.texHRaw(),
    }
}
