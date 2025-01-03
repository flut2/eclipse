const glfw = @import("zglfw");

const assets = @import("../../assets.zig");
const render = @import("../../render.zig");
const systems = @import("../systems.zig");
const tooltip = @import("../tooltips/tooltip.zig");
const element = @import("element.zig");
const ElementBase = element.ElementBase;

const Button = @This();
base: ElementBase,
enabled: bool = true,
userdata: ?*anyopaque = null,
pressCallback: *const fn (?*anyopaque) void,
image_data: element.InteractableImageData,
state: element.InteractableState = .none,
disabled_image_data: ?element.ImageData = null,
text_data: ?element.TextData = null,
tooltip_text: ?element.TextData = null,

pub fn mousePress(self: *Button, x: f32, y: f32, _: f32, _: f32, _: glfw.Mods) bool {
    if (!self.base.visible or !self.enabled) return false;

    const in_bounds = element.intersects(self, x, y);
    if (in_bounds) {
        self.state = .pressed;
        self.pressCallback(self.userdata);
        assets.playSfx("button.mp3");
        return true;
    }

    return !(self.base.event_policy.pass_press or !in_bounds);
}

pub fn mouseRelease(self: *Button, x: f32, y: f32, _: f32, _: f32) bool {
    if (!self.base.visible or !self.enabled) return false;
    const in_bounds = element.intersects(self, x, y);
    if (in_bounds) self.state = .hovered;
    return !(self.base.event_policy.pass_release or !in_bounds);
}

pub fn mouseMove(self: *Button, x: f32, y: f32, x_offset: f32, y_offset: f32) bool {
    if (!self.base.visible or !self.enabled) return false;

    const in_bounds = element.intersects(self, x, y);
    if (in_bounds) {
        if (self.tooltip_text) |text| {
            tooltip.switchTooltip(.text, .{
                .x = x + x_offset,
                .y = y + y_offset,
                .text_data = text,
            });
            return true;
        }

        systems.hover_lock.lock();
        defer systems.hover_lock.unlock();
        systems.hover_target = element.UiElement{ .button = self }; // TODO: re-add RLS when fixed
        self.state = .hovered;
    } else self.state = .none;

    return !(self.base.event_policy.pass_move or !in_bounds);
}

pub fn init(self: *Button) void {
    if (self.text_data) |*text_data| {
        text_data.max_width = self.width();
        text_data.max_height = self.height();
        text_data.vert_align = .middle;
        text_data.hori_align = .middle;
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

pub fn deinit(self: *Button) void {
    if (self.text_data) |*text_data| text_data.deinit();
    if (self.tooltip_text) |*text_data| text_data.deinit();
}

pub fn draw(self: *Button, _: render.CameraData, x_offset: f32, y_offset: f32, _: i64) void {
    if (!self.base.visible) return;
    const image_data = if (self.enabled or self.disabled_image_data == null) self.image_data.current(self.state) else self.disabled_image_data.?;
    image_data.draw(self.base.x + x_offset, self.base.y + y_offset, self.base.scissor);
    if (self.text_data) |*text_data| render.drawText(
        self.base.x + x_offset,
        self.base.y + y_offset,
        1.0,
        text_data,
        self.base.scissor,
    );
}

pub fn width(self: Button) f32 {
    const data = if (self.enabled or self.disabled_image_data == null) self.image_data.current(self.state) else self.disabled_image_data.?;
    if (self.text_data) |text| {
        return @max(text.width, switch (data) {
            .nine_slice => |nine_slice| return nine_slice.w,
            .normal => |image_data| return image_data.width(),
        });
    } else {
        return switch (data) {
            .nine_slice => |nine_slice| return nine_slice.w,
            .normal => |image_data| return image_data.width(),
        };
    }
}

pub fn height(self: Button) f32 {
    const data = if (self.enabled or self.disabled_image_data == null) self.image_data.current(self.state) else self.disabled_image_data.?;
    if (self.text_data) |text| {
        return @max(text.height, switch (data) {
            .nine_slice => |nine_slice| return nine_slice.h,
            .normal => |image_data| return image_data.height(),
        });
    } else {
        return switch (data) {
            .nine_slice => |nine_slice| return nine_slice.h,
            .normal => |image_data| return image_data.height(),
        };
    }
}

pub fn texWRaw(self: Button) f32 {
    const data = if (self.enabled or self.disabled_image_data == null) self.image_data.current(self.state) else self.disabled_image_data.?;
    if (self.text_data) |text| {
        return @max(text.width, switch (data) {
            .nine_slice => |nine_slice| return nine_slice.w,
            .normal => |image_data| return image_data.texWRaw(),
        });
    } else {
        return switch (data) {
            .nine_slice => |nine_slice| return nine_slice.w,
            .normal => |image_data| return image_data.texWRaw(),
        };
    }
}

pub fn texHRaw(self: Button) f32 {
    const data = if (self.enabled or self.disabled_image_data == null) self.image_data.current(self.state) else self.disabled_image_data.?;
    if (self.text_data) |text| {
        return @max(text.height, switch (data) {
            .nine_slice => |nine_slice| return nine_slice.h,
            .normal => |image_data| return image_data.texHRaw(),
        });
    } else {
        return switch (data) {
            .nine_slice => |nine_slice| return nine_slice.h,
            .normal => |image_data| return image_data.texHRaw(),
        };
    }
}
