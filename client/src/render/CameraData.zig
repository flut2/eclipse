const std = @import("std");
const u32f = @import("shared").utils.u32f;

const px_per_tile = @import("../Camera.zig").px_per_tile;

minimap_zoom: f32,
scale: f32,
x: f32,
y: f32,
x_dir: f32,
y_dir: f32,
last_update: i64,
width: f32,
height: f32,
min_x: u32,
max_x: u32,
min_y: u32,
max_y: u32,
clip_scale: [2]f32,
clip_offset: [2]f32,
cam_offset_px: [2]f32,

pub fn worldToScreen(self: @This(), x_in: f32, y_in: f32) struct { x: f32, y: f32 } {
    return .{
        .x = x_in * px_per_tile * self.scale - self.cam_offset_px[0] - self.clip_offset[0],
        .y = y_in * px_per_tile * self.scale - self.cam_offset_px[1] - self.clip_offset[1],
    };
}

pub fn visibleInCamera(self: @This(), x_in: f32, y_in: f32) bool {
    if (std.math.isNan(x_in) or
        std.math.isNan(y_in) or
        x_in < 0 or
        y_in < 0 or
        x_in > std.math.maxInt(u32) or
        y_in > std.math.maxInt(u32))
        return false;

    const floor_x = u32f(x_in);
    const floor_y = u32f(y_in);
    return !(floor_x < self.min_x or floor_x > self.max_x or floor_y < self.min_y or floor_y > self.max_y);
}
