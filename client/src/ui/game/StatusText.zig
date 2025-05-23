const std = @import("std");

const shared = @import("shared");
const utils = shared.utils;
const f32i = utils.f32i;
const i64f = utils.i64f;

const main = @import("../../main.zig");
const Renderer = @import("../../render/Renderer.zig");
const element = @import("../elements/element.zig");

const StatusText = @This();

text_data: element.TextData,
initial_size: f32 = 22.0,
duration: i64 = i64f(0.5 * std.time.us_per_s),
show_at: i64 = 0,
dispose_text: bool = false,

pub fn draw(
    self: *StatusText,
    generics: *std.ArrayListUnmanaged(Renderer.GenericData),
    sort_extras: *std.ArrayListUnmanaged(f32),
    time: i64,
    obj_x: f32,
    obj_y: f32,
    offset: f32,
    scale: f32,
) bool {
    const elapsed = time - self.show_at;
    if (elapsed <= 0) return true;
    if (elapsed > self.duration) return false;

    const frac = f32i(elapsed) / f32i(self.duration);
    self.text_data.size = self.initial_size * @min(1.0, @max(0.7, 1.0 - frac * 0.3 + 0.075));
    self.text_data.alpha = 1.0 - frac + 0.33;
    self.text_data.recalculateAttributes(); // not great doing this per frame for each instance but oh well
    const x = obj_x - self.text_data.width / 2;
    const y = obj_y - offset - self.text_data.height - frac * 40;
    self.text_data.sort_extra = obj_y - y;

    Renderer.drawText(generics, sort_extras, x, y, scale, &self.text_data, .{});
    return true;
}

pub fn deinit(self: *StatusText) void {
    if (self.dispose_text) main.allocator.free(self.text_data.text);
    self.text_data.deinit();
}
