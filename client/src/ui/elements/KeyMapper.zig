const glfw = @import("glfw");

const assets = @import("../../assets.zig");
const input = @import("../../input.zig");
const main = @import("../../main.zig");
const CameraData = @import("../../render/CameraData.zig");
const Settings = @import("../../Settings.zig");
const systems = @import("../systems.zig");
const tooltip = @import("../tooltips/tooltip.zig");
const element = @import("element.zig");
const ElementBase = element.ElementBase;

const KeyMapper = @This();
base: ElementBase,
setKeyCallback: *const fn (*KeyMapper) void,
image_data: element.InteractableImageData,
settings_button: *Settings.Button,
title_text_data: ?element.TextData = null,
tooltip_text: ?element.TextData = null,
state: element.InteractableState = .none,
listening: bool = false,

pub fn mousePress(self: *KeyMapper, x: f32, y: f32, _: f32, _: f32, _: glfw.Mods) bool {
    if (!self.base.visible) return false;

    const in_bounds = element.intersects(self, x, y);
    if (in_bounds) {
        self.state = .pressed;

        if (input.selected_key_mapper == null) {
            self.listening = true;
            input.selected_key_mapper = self;
        }

        assets.playSfx("button.mp3");
        return true;
    }

    return !(self.base.event_policy.pass_press or !in_bounds);
}

pub fn mouseRelease(self: *KeyMapper, x: f32, y: f32, _: f32, _: f32) bool {
    if (!self.base.visible) return false;
    const in_bounds = element.intersects(self, x, y);
    if (in_bounds) self.state = .hovered;
    return !(self.base.event_policy.pass_release or !in_bounds);
}

pub fn mouseMove(self: *KeyMapper, x: f32, y: f32, x_offset: f32, y_offset: f32) bool {
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
        systems.hover_target = element.UiElement{ .key_mapper = self }; // TODO: re-add RLS when fixed
        self.state = .hovered;
    } else self.state = .none;

    return !(self.base.event_policy.pass_move or !in_bounds);
}

pub fn init(self: *KeyMapper) void {
    if (self.title_text_data) |*text_data| {
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

pub fn deinit(self: *KeyMapper) void {
    if (self.title_text_data) |*text_data| text_data.deinit();
    if (self.tooltip_text) |*text_data| text_data.deinit();
}

pub fn draw(self: *KeyMapper, _: CameraData, x_offset: f32, y_offset: f32, _: i64) void {
    if (!self.base.visible) return;
    const image_data = self.image_data.current(self.state);
    const w, const h = switch (image_data) {
        .nine_slice => |nine_slice| .{ nine_slice.w, nine_slice.h },
        .normal => |normal| .{ normal.texWRaw(), normal.texHRaw() },
    };

    main.renderer.drawQuad(
        self.base.x + x_offset,
        self.base.y + y_offset,
        w,
        h,
        assets.getKeyTexture(self.settings_button.*),
        .{ .scissor = self.base.scissor },
    );
    if (self.title_text_data) |*text_data| main.renderer.drawText(
        self.base.x + w + 5 + x_offset,
        self.base.y + (h - text_data.height) / 2 + y_offset,
        1.0,
        text_data,
        self.base.scissor,
    );
}

pub fn width(self: KeyMapper) f32 {
    const extra = if (self.title_text_data) |t| t.width else 0;
    return switch (self.image_data.current(self.state)) {
        .nine_slice => |nine_slice| return nine_slice.w + extra,
        .normal => |image_data| return image_data.width() + extra,
    };
}

pub fn height(self: KeyMapper) f32 {
    return switch (self.image_data.current(self.state)) {
        .nine_slice => |nine_slice| return nine_slice.h,
        .normal => |image_data| return image_data.height(),
    };
}

pub fn texWRaw(self: KeyMapper) f32 {
    const extra = if (self.title_text_data) |t| t.width else 0;
    return switch (self.image_data.current(self.state)) {
        .nine_slice => |nine_slice| return nine_slice.w + extra,
        .normal => |image_data| return image_data.texWRaw() + extra,
    };
}

pub fn texHRaw(self: KeyMapper) f32 {
    return switch (self.image_data.current(self.state)) {
        .nine_slice => |nine_slice| return nine_slice.h,
        .normal => |image_data| return image_data.texHRaw(),
    };
}
