const glfw = @import("zglfw");

const assets = @import("../../assets.zig");
const render = @import("../../render.zig");
const systems = @import("../systems.zig");
const tooltip = @import("../tooltips/tooltip.zig");
const element = @import("element.zig");
const ElementBase = element.ElementBase;

const Toggle = @This();
base: ElementBase,
toggled: *bool,
off_image_data: element.InteractableImageData,
on_image_data: element.InteractableImageData,
state: element.InteractableState = .none,
text_data: ?element.TextData = null,
tooltip_text: ?element.TextData = null,
state_change: ?*const fn (*Toggle) void = null,

pub fn mousePress(self: *Toggle, x: f32, y: f32, _: f32, _: f32, _: glfw.Mods) bool {
    if (!self.base.visible) return false;

    const in_bounds = element.intersects(self, x, y);
    if (in_bounds) {
        self.state = .pressed;
        self.toggled.* = !self.toggled.*;
        if (self.state_change) |callback| callback(self);
        assets.playSfx("button.mp3");
        return true;
    }

    return !(self.base.event_policy.pass_press or !in_bounds);
}

pub fn mouseRelease(self: *Toggle, x: f32, y: f32, _: f32, _: f32) bool {
    if (!self.base.visible) return false;
    const in_bounds = element.intersects(self, x, y);
    if (in_bounds) self.state = .hovered;
    return !(self.base.event_policy.pass_release or !in_bounds);
}

pub fn mouseMove(self: *Toggle, x: f32, y: f32, x_offset: f32, y_offset: f32) bool {
    if (!self.base.visible) return false;

    const in_bounds = element.intersects(self, x, y);
    if (in_bounds) {
        if (self.tooltip_text) |text_data| {
            tooltip.switchTooltip(.text, .{
                .x = x + x_offset,
                .y = y + y_offset,
                .text_data = text_data,
            });
            return true;
        }

        systems.hover_lock.lock();
        defer systems.hover_lock.unlock();
        systems.hover_target = element.UiElement{ .toggle = self }; // TODO: re-add RLS when fixed
        self.state = .hovered;
    } else self.state = .none;

    return !(self.base.event_policy.pass_move or !in_bounds);
}

pub fn init(self: *Toggle) void {
    if (self.text_data) |*text_data| {
        text_data.lock.lock();
        defer text_data.lock.unlock();
        text_data.recalculateAttributes();
    }

    if (self.tooltip_text) |*text_data| {
        text_data.lock.lock();
        defer text_data.lock.unlock();
        text_data.recalculateAttributes();
    }
}

pub fn deinit(self: *Toggle) void {
    if (self.text_data) |*text_data| text_data.deinit();
    if (self.tooltip_text) |*text_data| text_data.deinit();
}

pub fn draw(self: *Toggle, _: render.CameraData, x_offset: f32, y_offset: f32, _: i64) void {
    if (!self.base.visible) return;
    const image_data = if (self.toggled.*)
        self.on_image_data.current(self.state)
    else
        self.off_image_data.current(self.state);
    const w, const h = switch (image_data) {
        .nine_slice => |nine_slice| .{ nine_slice.w, nine_slice.h },
        .normal => |normal| .{ normal.texWRaw(), normal.texHRaw() },
    };

    image_data.draw(self.base.x + x_offset, self.base.y + y_offset, self.base.scissor);
    if (self.text_data) |*text_data| render.drawText(
        self.base.x + w + 5 + x_offset,
        self.base.y + (h - text_data.height) / 2 + y_offset,
        1.0,
        text_data,
        self.base.scissor,
    );
}

pub fn width(self: Toggle) f32 {
    switch (if (self.toggled.*)
        self.on_image_data.current(self.state)
    else
        self.off_image_data.current(self.state)) {
        .nine_slice => |nine_slice| return nine_slice.w,
        .normal => |image_data| return image_data.width(),
    }
}

pub fn height(self: Toggle) f32 {
    switch (if (self.toggled.*)
        self.on_image_data.current(self.state)
    else
        self.off_image_data.current(self.state)) {
        .nine_slice => |nine_slice| return nine_slice.h,
        .normal => |image_data| return image_data.height(),
    }
}

pub fn texWRaw(self: Toggle) f32 {
    switch (if (self.toggled.*)
        self.on_image_data.current(self.state)
    else
        self.off_image_data.current(self.state)) {
        .nine_slice => |nine_slice| return nine_slice.w,
        .normal => |image_data| return image_data.texWRaw(),
    }
}

pub fn texHRaw(self: Toggle) f32 {
    switch (if (self.toggled.*)
        self.on_image_data.current(self.state)
    else
        self.off_image_data.current(self.state)) {
        .nine_slice => |nine_slice| return nine_slice.h,
        .normal => |image_data| return image_data.texHRaw(),
    }
}
