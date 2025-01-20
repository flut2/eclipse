const game_data = @import("shared").game_data;

const assets = @import("../../assets.zig");
const map = @import("../../game/map.zig");
const main = @import("../../main.zig");
const CameraData = @import("../../render/CameraData.zig");
const tooltip = @import("../tooltips/tooltip.zig");
const element = @import("element.zig");
const ElementBase = element.ElementBase;

const Image = @This();
base: ElementBase,
image_data: element.ImageData,
tooltip_text: ?element.TextData = null,
ability_data: ?game_data.AbilityData = null,
card_data: ?game_data.CardData = null,

pub fn mouseMove(self: *Image, x: f32, y: f32, x_offset: f32, y_offset: f32) bool {
    if (!self.base.visible) return false;

    const in_bounds = element.intersects(self, x, y);
    if (in_bounds) {
        if (self.card_data) |data| {
            tooltip.switchTooltip(.card, .{
                .x = x + x_offset,
                .y = y + y_offset,
                .data = data,
            });
            return true;
        }

        if (self.ability_data) |data| {
            tooltip.switchTooltip(.ability, .{
                .x = x + x_offset,
                .y = y + y_offset,
                .data = data,
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
    }

    return !(self.base.event_policy.pass_move or !in_bounds);
}

pub fn init(self: *Image) void {
    if (self.tooltip_text) |*text_data| {
        text_data.lock.lock();
        defer text_data.lock.unlock();
        text_data.recalculateAttributes();
    }
}

pub fn deinit(self: *Image) void {
    if (self.tooltip_text) |*text_data| text_data.deinit();
}

pub fn draw(self: Image, _: CameraData, x_offset: f32, y_offset: f32, _: i64) void {
    if (!self.base.visible) return;
    self.image_data.draw(self.base.x + x_offset, self.base.y + y_offset, self.base.scissor);
}

pub fn width(self: Image) f32 {
    return switch (self.image_data) {
        .nine_slice => |nine_slice| nine_slice.w,
        .normal => |image_data| image_data.width(),
    };
}

pub fn height(self: Image) f32 {
    return switch (self.image_data) {
        .nine_slice => |nine_slice| nine_slice.h,
        .normal => |image_data| image_data.height(),
    };
}

pub fn texWRaw(self: Image) f32 {
    return switch (self.image_data) {
        .nine_slice => |nine_slice| nine_slice.w,
        .normal => |image_data| image_data.texWRaw(),
    };
}

pub fn texHRaw(self: Image) f32 {
    return switch (self.image_data) {
        .nine_slice => |nine_slice| nine_slice.h,
        .normal => |image_data| image_data.texHRaw(),
    };
}
