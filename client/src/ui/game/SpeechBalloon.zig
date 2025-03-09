const std = @import("std");

const shared = @import("shared");
const utils = shared.utils;
const f32i = utils.f32i;
const i64f = utils.i64f;

const assets = @import("../../assets.zig");
const main = @import("../../main.zig");
const Renderer = @import("../../render/Renderer.zig");
const element = @import("../elements/element.zig");

const SpeechBalloon = @This();

const text_scale = 2.0;
const text_offset_x = 2.0 * text_scale;
const text_offset_y = 2.0 * text_scale;

text_data: element.TextData = undefined,
image_data: element.ImageData = undefined,
duration: i64 = i64f(0.5 * std.time.us_per_s),
show_at: i64 = 0,

pub fn create(
    show_at: i64,
    duration: i64,
    text: []const u8,
    is_enemy: bool,
) SpeechBalloon {
    var image_data: element.ImageData = .{ .normal = .{
        .atlas_data = if (is_enemy)
            assets.getUiData("speech_balloons_small", 1)
        else
            assets.getUiData("speech_balloons_small", 0),
        .scale_x = text_scale,
        .scale_y = text_scale,
    } };
    var text_data: element.TextData = .{
        .text = text,
        .size = 10,
        .color = 0x000000,
        .vert_align = .middle,
        .hori_align = .middle,
        .max_width = 43 * text_scale,
        .max_height = 12 * text_scale,
        .outline_width = 0.0,
        .sort_extra = 500, // TODO: hack
    };
    text_data.recalculateAttributes();

    if (text_data.height >= 12 * text_scale) {
        image_data.normal.atlas_data = if (is_enemy)
            assets.getUiData("speech_balloons_medium", 1)
        else
            assets.getUiData("speech_balloons_medium", 0);
        text_data.max_height = 19 * text_scale;
        text_data.recalculateAttributes();
    }

    if (text_data.height >= 19 * text_scale) {
        image_data.normal.atlas_data = if (is_enemy)
            assets.getUiData("speech_balloons_large", 1)
        else
            assets.getUiData("speech_balloons_large", 0);
        text_data.max_width = 59 * text_scale;
        text_data.max_height = 26 * text_scale;
        text_data.recalculateAttributes();
    }

    return .{
        .text_data = text_data,
        .image_data = image_data,
        .duration = duration,
        .show_at = show_at,
    };
}

pub fn draw(
    self: *SpeechBalloon,
    generics: *std.ArrayListUnmanaged(Renderer.GenericData),
    sort_extras: *std.ArrayListUnmanaged(f32),
    time: i64,
    obj_x: f32,
    obj_y: f32,
    scale: f32,
) bool {
    const elapsed = time - self.show_at;
    if (elapsed <= 0) return true;
    if (elapsed > self.duration) return false;

    const x = obj_x - self.image_data.width() / 2;
    const y = obj_y - self.image_data.height();

    Renderer.drawQuad(
        generics,
        sort_extras,
        x,
        y,
        self.image_data.width() * scale,
        self.image_data.height() * scale,
        self.image_data.normal.atlas_data,
        .{ .sort_extra = 400 }, // TODO: hack
    );
    Renderer.drawText(generics, sort_extras, x + text_offset_x * scale, y + text_offset_y * scale, scale, &self.text_data, .{});
    return true;
}

pub fn deinit(self: *SpeechBalloon) void {
    main.allocator.free(self.text_data.text);
    self.text_data.deinit();
}
