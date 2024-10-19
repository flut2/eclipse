const std = @import("std");
const element = @import("element.zig");
const systems = @import("../systems.zig");
const tooltip = @import("../tooltips/tooltip.zig");
const render = @import("../../render.zig");
const utils = @import("shared").utils;
const glfw = @import("zglfw");

const Slider = @This();
const ElementBase = element.ElementBase;

// Event policy will be overwritten
base: ElementBase,
w: f32,
h: f32,
min_value: f32,
max_value: f32,
decor_image_data: element.ImageData,
knob_image_data: element.InteractableImageData,
state_change: ?*const fn (*Slider) void = null,
step: f32 = 0.0,
vertical: bool = false,
continous_event_fire: bool = true,
state: element.InteractableState = .none,
// the alignments and max w/h on these will be overwritten, don't bother setting it
value_text_data: ?element.TextData = null,
title_text_data: ?element.TextData = null,
tooltip_text: ?element.TextData = null,
title_offset: f32 = 30.0,
target: ?*f32 = null,
userdata: ?*anyopaque = null,
knob_x: f32 = 0.0,
knob_y: f32 = 0.0,
knob_offset_x: f32 = 0.0,
knob_offset_y: f32 = 0.0,
current_value: f32 = 0.0,

pub fn mousePress(self: *Slider, x: f32, y: f32, _: f32, _: f32, _: glfw.Mods) bool {
    if (!self.base.visible) return false;

    if (utils.isInBounds(x, y, self.base.x, self.base.y, self.w, self.h)) {
        const knob_w = switch (self.knob_image_data.current(self.state)) {
            .nine_slice => |nine_slice| nine_slice.w,
            .normal => |normal| normal.width(),
        };

        const knob_h = switch (self.knob_image_data.current(self.state)) {
            .nine_slice => |nine_slice| nine_slice.h,
            .normal => |normal| normal.height(),
        };

        self.knob_offset_x = -((x - self.base.x) - self.knob_x);
        self.knob_offset_y = -((y - self.base.y) - self.knob_y);
        self.pressed(x, y, knob_h, knob_w);
    }

    return !(self.base.event_policy.pass_press or !element.intersects(self, x, y));
}

pub fn mouseRelease(self: *Slider, x: f32, y: f32, _: f32, _: f32) bool {
    if (!self.base.visible) return false;

    if (self.state == .pressed) {
        const knob_w = switch (self.knob_image_data.current(self.state)) {
            .nine_slice => |nine_slice| nine_slice.w,
            .normal => |normal| normal.width(),
        };

        const knob_h = switch (self.knob_image_data.current(self.state)) {
            .nine_slice => |nine_slice| nine_slice.h,
            .normal => |normal| normal.height(),
        };

        if (utils.isInBounds(x, y, self.knob_x, self.knob_y, knob_w, knob_h)) {
            systems.hover_lock.lock();
            defer systems.hover_lock.unlock();
            systems.hover_target = element.UiElement{ .slider = self }; // TODO: re-add RLS when fixed
            self.state = .hovered;
        } else self.state = .none;

        if (self.target) |target| target.* = self.current_value;
        if (self.state_change) |sc| sc(self);
    }

    return !(self.base.event_policy.pass_release or !element.intersects(self, x, y));
}

pub fn mouseMove(self: *Slider, x: f32, y: f32, x_offset: f32, y_offset: f32) bool {
    if (!self.base.visible) return false;

    const knob_w = switch (self.knob_image_data.current(self.state)) {
        .nine_slice => |nine_slice| nine_slice.w,
        .normal => |normal| normal.width(),
    };

    const knob_h = switch (self.knob_image_data.current(self.state)) {
        .nine_slice => |nine_slice| nine_slice.h,
        .normal => |normal| normal.height(),
    };

    const in_bounds = element.intersects(self, x, y);
    if (in_bounds) if (self.tooltip_text) |text_data| tooltip.switchTooltip(.text, .{
        .x = x + x_offset,
        .y = y + y_offset,
        .text_data = text_data,
    });

    if (self.state == .pressed) {
        self.pressed(x, y, knob_h, knob_w);
    } else if (utils.isInBounds(x, y, self.base.x + self.knob_x, self.base.y + self.knob_y, knob_w, knob_h)) {
        systems.hover_lock.lock();
        defer systems.hover_lock.unlock();
        systems.hover_target = element.UiElement{ .slider = self }; // todo re-add RLS when fixed
        self.state = .hovered;
    } else if (self.state == .hovered) self.state = .none;

    return !(self.base.event_policy.pass_move or !in_bounds);
}

pub fn mouseScroll(self: *Slider, x: f32, y: f32, _: f32, _: f32, _: f32, y_scroll: f32) bool {
    const in_bounds = element.intersects(self, x, y);
    if (in_bounds) {
        self.setValue(
            @min(
                self.max_value,
                @max(
                    self.min_value,
                    self.current_value + (self.max_value - self.min_value) * -y_scroll / 64.0,
                ),
            ),
        );
        return true;
    }

    return !(self.base.event_policy.pass_scroll or !in_bounds);
}

pub fn init(self: *Slider) void {
    self.base.event_policy = .{
        .pass_move = true,
        .pass_press = true,
        .pass_scroll = true,
        .pass_release = true,
    };

    if (self.target) |value_ptr| {
        value_ptr.* = @min(self.max_value, @max(self.min_value, value_ptr.*));
        self.current_value = value_ptr.*;
    }

    switch (self.decor_image_data) {
        .nine_slice => |*nine_slice| {
            nine_slice.w = self.w;
            nine_slice.h = self.h;
        },
        .normal => |*image_data| {
            image_data.scale_x = self.w / image_data.width();
            image_data.scale_y = self.h / image_data.height();
        },
    }

    const knob_w = switch (self.knob_image_data.current(self.state)) {
        .nine_slice => |nine_slice| nine_slice.w,
        .normal => |normal| normal.width(),
    };
    const knob_h = switch (self.knob_image_data.current(self.state)) {
        .nine_slice => |nine_slice| nine_slice.h,
        .normal => |normal| normal.height(),
    };

    if (self.vertical) {
        const offset = (self.w - knob_w) / 2.0;
        if (offset < 0) self.base.x = self.base.x - offset;
        self.knob_x = self.knob_x + offset;

        if (self.value_text_data) |*text_data| {
            text_data.hori_align = .left;
            text_data.vert_align = .middle;
            text_data.max_height = knob_h;
        }
    } else {
        const offset = (self.h - knob_h) / 2.0;
        if (offset < 0) self.base.y = self.base.y - offset;
        self.knob_y = self.knob_y + offset;

        if (self.value_text_data) |*text_data| {
            text_data.hori_align = .middle;
            text_data.vert_align = .top;
            text_data.max_width = knob_w;
        }
    }

    if (self.value_text_data) |*text_data| {
        // have to do it for the backing buffer init
        {
            text_data.lock.lock();
            defer text_data.lock.unlock();
            text_data.recalculateAttributes();
        }

        text_data.setText(std.fmt.bufPrint(text_data.backing_buffer, "{d:.2}", .{self.current_value}) catch "-1.00");
    }

    if (self.title_text_data) |*text_data| {
        text_data.vert_align = .middle;
        text_data.hori_align = .middle;
        text_data.max_width = self.w;
        text_data.max_height = self.title_offset;
        text_data.lock.lock();
        defer text_data.lock.unlock();
        text_data.recalculateAttributes();
    }

    if (self.tooltip_text) |*text_data| {
        text_data.lock.lock();
        defer text_data.lock.unlock();
        text_data.recalculateAttributes();
    }

    self.setValue(self.current_value);
}

pub fn deinit(self: *Slider) void {
    if (self.value_text_data) |*text_data| text_data.deinit();
    if (self.title_text_data) |*text_data| text_data.deinit();
    if (self.tooltip_text) |*text_data| text_data.deinit();
}

pub fn draw(self: *Slider, _: render.CameraData, x_offset: f32, y_offset: f32, _: i64) void {
    if (!self.base.visible) return;
    self.decor_image_data.draw(self.base.x + x_offset, self.base.y + y_offset);

    const knob_image_data = self.knob_image_data.current(self.state);
    const knob_x = self.base.x + self.knob_x + x_offset;
    const knob_y = self.base.y + self.knob_y + y_offset;
    const knob_w, const knob_h = switch (knob_image_data) {
        .nine_slice => |nine_slice| .{ nine_slice.w, nine_slice.h },
        .normal => |normal| .{ normal.texWRaw(), normal.texHRaw() },
    };
    knob_image_data.draw(knob_x, knob_y);

    if (self.title_text_data) |*text_data| render.drawText(
        self.base.x + x_offset,
        self.base.y + y_offset - self.title_offset,
        1.0,
        text_data,
        self.base.scissor,
    );

    if (self.value_text_data) |*text_data| render.drawText(
        knob_x + if (self.vertical) knob_w else 0,
        knob_y + if (self.vertical) 0 else knob_h,
        1.0,
        text_data,
        self.base.scissor,
    );
}

pub fn width(self: Slider) f32 {
    const decor_w = switch (self.decor_image_data) {
        .nine_slice => |nine_slice| nine_slice.w,
        .normal => |image_data| image_data.width(),
    };

    const knob_w = switch (self.knob_image_data.current(self.state)) {
        .nine_slice => |nine_slice| nine_slice.w,
        .normal => |normal| normal.width(),
    };

    return @max(decor_w, knob_w);
}

pub fn height(self: Slider) f32 {
    const decor_h = switch (self.decor_image_data) {
        .nine_slice => |nine_slice| nine_slice.h,
        .normal => |image_data| image_data.height(),
    };

    const knob_h = switch (self.knob_image_data.current(self.state)) {
        .nine_slice => |nine_slice| nine_slice.h,
        .normal => |normal| normal.height(),
    };

    return @max(decor_h, knob_h);
}

pub fn texWRaw(self: Slider) f32 {
    const decor_w = switch (self.decor_image_data) {
        .nine_slice => |nine_slice| nine_slice.w,
        .normal => |image_data| image_data.texWRaw(),
    };

    const knob_w = switch (self.knob_image_data.current(self.state)) {
        .nine_slice => |nine_slice| nine_slice.w,
        .normal => |normal| normal.texWRaw(),
    };

    return @max(decor_w, knob_w);
}

pub fn texHRaw(self: Slider) f32 {
    const decor_h = switch (self.decor_image_data) {
        .nine_slice => |nine_slice| nine_slice.h,
        .normal => |image_data| image_data.texHRaw(),
    };

    const knob_h = switch (self.knob_image_data.current(self.state)) {
        .nine_slice => |nine_slice| nine_slice.h,
        .normal => |normal| normal.texHRaw(),
    };

    return @max(decor_h, knob_h);
}

fn pressed(self: *Slider, x: f32, y: f32, knob_h: f32, knob_w: f32) void {
    const prev_value = self.current_value;

    if (self.vertical) {
        self.knob_y = @min(self.h - knob_h, @max(0, y - self.base.y + self.knob_offset_y));
        self.current_value = self.knob_y / (self.h - knob_h) * (self.max_value - self.min_value) + self.min_value;
    } else {
        self.knob_x = @min(self.w - knob_w, @max(0, x - self.base.x + self.knob_offset_x));
        self.current_value = self.knob_x / (self.w - knob_w) * (self.max_value - self.min_value) + self.min_value;
    }

    if (self.current_value != prev_value) {
        if (self.value_text_data) |*text_data| {
            text_data.setText(std.fmt.bufPrint(text_data.backing_buffer, "{d:.2}", .{self.current_value}) catch "-1.00");
        }

        if (self.continous_event_fire) {
            if (self.target) |target| target.* = self.current_value;
            if (self.state_change) |sc| sc(self);
        }
    }

    self.state = .pressed;
}

pub fn setValue(self: *Slider, value: f32) void {
    const prev_value = self.current_value;

    const knob_w = switch (self.knob_image_data.current(self.state)) {
        .nine_slice => |nine_slice| nine_slice.w,
        .normal => |normal| normal.width(),
    };

    const knob_h = switch (self.knob_image_data.current(self.state)) {
        .nine_slice => |nine_slice| nine_slice.h,
        .normal => |normal| normal.height(),
    };

    self.current_value = value;
    if (self.vertical)
        self.knob_y = (value - self.min_value) / (self.max_value - self.min_value) * (self.h - knob_h)
    else
        self.knob_x = (value - self.min_value) / (self.max_value - self.min_value) * (self.w - knob_w);

    if (self.current_value != prev_value) {
        if (self.value_text_data) |*text_data| {
            text_data.setText(std.fmt.bufPrint(text_data.backing_buffer, "{d:.2}", .{self.current_value}) catch "-1.00");
        }

        if (self.continous_event_fire) {
            if (self.target) |target| target.* = self.current_value;
            if (self.state_change) |sc| sc(self);
        }
    }
}
