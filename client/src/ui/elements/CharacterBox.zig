const glfw = @import("zglfw");

const assets = @import("../../assets.zig");
const render = @import("../../render.zig");
const systems = @import("../systems.zig");
const element = @import("element.zig");
const ElementBase = element.ElementBase;

const CharacterBox = @This();
base: ElementBase,
id: u32,
class_data_id: u16,
pressCallback: *const fn (*CharacterBox) void,
image_data: element.InteractableImageData,
state: element.InteractableState = .none,
text_data: ?element.TextData = null,

pub fn mousePress(self: *CharacterBox, x: f32, y: f32, _: f32, _: f32, _: glfw.Mods) bool {
    if (!self.base.visible) return false;

    const in_bounds = element.intersects(self, x, y);
    if (in_bounds) {
        self.state = .pressed;
        self.pressCallback(self);
        assets.playSfx("button.mp3");
        return true;
    }

    return !(self.base.event_policy.pass_press or !in_bounds);
}

pub fn mouseRelease(self: *CharacterBox, x: f32, y: f32, _: f32, _: f32) bool {
    if (!self.base.visible) return false;
    const in_bounds = element.intersects(self, x, y);
    if (in_bounds) self.state = .hovered;
    return !(self.base.event_policy.pass_release or !in_bounds);
}

pub fn mouseMove(self: *CharacterBox, x: f32, y: f32, _: f32, _: f32) bool {
    if (!self.base.visible) return false;

    const in_bounds = element.intersects(self, x, y);
    if (in_bounds) {
        systems.hover_lock.lock();
        defer systems.hover_lock.unlock();
        systems.hover_target = element.UiElement{ .char_box = self }; // TODO: re-add RLS when fixed
        self.state = .hovered;
    } else self.state = .none;

    return !(self.base.event_policy.pass_move or !in_bounds);
}

pub fn init(self: *CharacterBox) void {
    if (self.text_data) |*text_data| {
        text_data.lock.lock();
        defer text_data.lock.unlock();
        text_data.recalculateAttributes();
    }
}

pub fn deinit(self: *CharacterBox) void {
    if (self.text_data) |*text_data| text_data.deinit();
}

pub fn draw(self: *CharacterBox, _: render.CameraData, x_offset: f32, y_offset: f32, _: i64) void {
    if (!self.base.visible) return;
    const image_data = self.image_data.current(self.state);
    const w, const h = switch (image_data) {
        .nine_slice => |nine_slice| .{ nine_slice.w, nine_slice.h },
        .normal => |normal| .{ normal.texWRaw(), normal.texHRaw() },
    };

    image_data.draw(self.base.x + x_offset, self.base.y + y_offset, self.base.scissor);
    if (self.text_data) |*text_data| render.drawText(
        self.base.x + (w - text_data.width) / 2 + x_offset,
        self.base.y + (h - text_data.height) / 2 + y_offset,
        1.0,
        text_data,
        self.base.scissor,
    );
}

pub fn width(self: CharacterBox) f32 {
    return if (self.text_data) |text| blk: {
        break :blk @max(text.width, switch (self.image_data.current(self.state)) {
            .nine_slice => |nine_slice| nine_slice.w,
            .normal => |image_data| image_data.width(),
        });
    } else switch (self.image_data.current(self.state)) {
        .nine_slice => |nine_slice| nine_slice.w,
        .normal => |image_data| image_data.width(),
    };
}

pub fn height(self: CharacterBox) f32 {
    return if (self.text_data) |text| blk: {
        break :blk @max(text.height, switch (self.image_data.current(self.state)) {
            .nine_slice => |nine_slice| nine_slice.h,
            .normal => |image_data| image_data.height(),
        });
    } else switch (self.image_data.current(self.state)) {
        .nine_slice => |nine_slice| nine_slice.h,
        .normal => |image_data| image_data.height(),
    };
}

pub fn texWRaw(self: CharacterBox) f32 {
    return if (self.text_data) |text| blk: {
        break :blk @max(text.width, switch (self.image_data.current(self.state)) {
            .nine_slice => |nine_slice| nine_slice.w,
            .normal => |image_data| image_data.texWRaw(),
        });
    } else switch (self.image_data.current(self.state)) {
        .nine_slice => |nine_slice| nine_slice.w,
        .normal => |image_data| image_data.texWRaw(),
    };
}

pub fn texHRaw(self: CharacterBox) f32 {
    return if (self.text_data) |text| blk: {
        break :blk @max(text.height, switch (self.image_data.current(self.state)) {
            .nine_slice => |nine_slice| nine_slice.h,
            .normal => |image_data| image_data.texHRaw(),
        });
    } else switch (self.image_data.current(self.state)) {
        .nine_slice => |nine_slice| nine_slice.h,
        .normal => |image_data| image_data.texHRaw(),
    };
}
