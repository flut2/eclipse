const std = @import("std");

const glfw = @import("glfw");
const shared = @import("shared");
const CharacterData = shared.network_data.CharacterData;
const TalentData = shared.game_data.TalentData;

const assets = @import("../../assets.zig");
const main = @import("../../main.zig");
const Renderer = @import("../../render/Renderer.zig");
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
text_offset_x: f32 = 0.0,
text_offset_y: f32 = 0.0,
text_data: ?element.TextData = null,
tooltip_text: ?element.TextData = null,
char: ?*const CharacterData = null, // hack
talent: ?*const TalentData = null, // hack 2
talent_index: u8 = std.math.maxInt(u8),

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
    if (!self.base.visible) return false;

    const in_bounds = element.intersects(self, x, y);
    if (in_bounds) {
        systems.hover_target = .{ .button = self };
        if (self.enabled) self.state = .hovered;

        if (self.char) |char| {
            tooltip.switchTooltip(.character, .{
                .x = x + x_offset,
                .y = y + y_offset,
                .data = char,
            });
            return true;
        }

        if (self.talent) |talent| {
            tooltip.switchTooltip(.talent, .{
                .x = x + x_offset,
                .y = y + y_offset,
                .data = talent,
                .index = self.talent_index,
            });
            return true;
        }

        if (self.tooltip_text) |text| {
            tooltip.switchTooltip(.text, .{
                .x = x + x_offset,
                .y = y + y_offset,
                .text_data = text,
            });
            return true;
        }
    } else if (self.enabled) self.state = .none;

    return !(self.base.event_policy.pass_move or !in_bounds or !self.enabled);
}

pub fn init(self: *Button) void {
    if (self.text_data) |*text_data| {
        if (self.text_offset_x == 0.0 and self.text_offset_y == 0.0) {
            text_data.max_width = self.width();
            text_data.max_height = self.height();
            text_data.vert_align = .middle;
            text_data.hori_align = .middle;
        }

        text_data.recalculateAttributes();
    }

    if (self.tooltip_text) |*text_data| text_data.recalculateAttributes();
}

pub fn deinit(self: *Button) void {
    if (self.text_data) |*text_data| text_data.deinit();
    if (self.tooltip_text) |*text_data| text_data.deinit();
}

pub fn draw(
    self: *Button,
    generics: *std.ArrayListUnmanaged(Renderer.GenericData),
    sort_extras: *std.ArrayListUnmanaged(f32),
    x_offset: f32,
    y_offset: f32,
    _: i64,
) void {
    if (!self.base.visible) return;
    const image_data = if (self.enabled or self.disabled_image_data == null)
        self.image_data.current(self.state)
    else
        self.disabled_image_data.?;
    image_data.draw(generics, sort_extras, self.base.x + x_offset, self.base.y + y_offset, self.base.scissor);
    if (self.text_data) |*text_data| Renderer.drawText(
        generics,
        sort_extras,
        self.base.x + self.text_offset_x + x_offset,
        self.base.y + self.text_offset_y + y_offset,
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
