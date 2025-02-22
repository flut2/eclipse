const std = @import("std");

const glfw = @import("glfw");
const ItemData = @import("shared").network_data.ItemData;

const main = @import("../../main.zig");
const CameraData = @import("../../render/CameraData.zig");
const tooltip = @import("../tooltips/tooltip.zig");
const element = @import("element.zig");
const ElementBase = element.ElementBase;

const Item = @This();
base: ElementBase,
image_data: element.ImageData,
background_x: f32,
background_y: f32,
// don't set this to anything, it's used for item rarity backgrounds
background_image_data: ?element.ImageData = null,
amount_text: ?element.TextData = null,
dragStartCallback: ?*const fn (*Item) void = null,
dragEndCallback: ?*const fn (*Item) void = null,
doubleClickCallback: ?*const fn (*Item) void = null,
shiftClickCallback: ?*const fn (*Item) void = null,
amount_visible: bool = false,
draggable: bool = false,
is_dragging: bool = false,
drag_start_x: f32 = 0,
drag_start_y: f32 = 0,
drag_offset_x: f32 = 0,
drag_offset_y: f32 = 0,
last_click_time: i64 = 0,
data_id: u16 = std.math.maxInt(u16),
item_data: ItemData = .{},

pub fn mousePress(self: *Item, x: f32, y: f32, _: f32, _: f32, mods: glfw.Mods) bool {
    if (!self.base.visible or !self.draggable) return false;

    const in_bounds = element.intersects(self, x, y);
    if (in_bounds) {
        if (mods.shift) {
            self.shiftClickCallback.?(self);
            return true;
        }

        if (self.last_click_time + 333 * std.time.us_per_ms > main.current_time) {
            self.doubleClickCallback.?(self);
            return true;
        }

        self.is_dragging = true;
        self.drag_start_x = self.base.x;
        self.drag_start_y = self.base.y;
        self.drag_offset_x = self.base.x - x;
        self.drag_offset_y = self.base.y - y;
        self.last_click_time = main.current_time;
        self.dragStartCallback.?(self);
        return true;
    }

    return !(self.base.event_policy.pass_press or !in_bounds);
}

pub fn mouseRelease(self: *Item, x: f32, y: f32, _: f32, _: f32) bool {
    if (!self.is_dragging) return false;
    self.is_dragging = false;
    self.dragEndCallback.?(self);
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
                .item = self.data_id,
                .item_data = self.item_data,
            });
            return true;
        }

        return false;
    }

    self.base.x = x + self.drag_offset_x;
    self.base.y = y + self.drag_offset_y;
    return !(self.base.event_policy.pass_move or !in_bounds);
}

pub fn init(self: *Item) void {
    if (self.amount_text) |*text_data| {
        text_data.lock.lock();
        defer text_data.lock.unlock();
        text_data.recalculateAttributes();
    }
}

pub fn deinit(self: *Item) void {
    if (self.amount_text) |*text_data| text_data.deinit();
}

pub fn draw(self: *Item, _: CameraData, x_offset: f32, y_offset: f32, _: i64) void {
    if (!self.base.visible) return;
    if (self.background_image_data) |background_image_data| background_image_data.draw(
        self.background_x + x_offset,
        self.background_y + y_offset,
        self.base.scissor,
    );
    self.image_data.draw(self.base.x + x_offset, self.base.y + y_offset, self.base.scissor);
    if (self.amount_visible) if (self.amount_text) |*text| main.renderer.drawText(
        self.background_x + 8 + x_offset,
        self.background_y + 4 + y_offset,
        1.0,
        text,
        self.base.scissor,
    );
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
