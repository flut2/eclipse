const std = @import("std");

const shared = @import("shared");
const utils = shared.utils;
const u32f = utils.u32f;

const map = @import("game/map.zig");
const main = @import("main.zig");
const pad = @import("assets.zig").padding;

const Camera = @This();

pub const px_per_tile = 63.0;
pub const size_mult = 6.0;

minimap_zoom: f32 = 4.0,
quake: bool = false,
quake_amount: f32 = 0.0,
x: f32 = 0.0,
y: f32 = 0.0,
scale: f32 = 1.0,
min_x: u32 = 0,
min_y: u32 = 0,
max_x: u32 = 0,
max_y: u32 = 0,
width: f32 = 1280.0,
height: f32 = 720.0,
clip_scale: [2]f32 = [2]f32{ 2.0 / 1280.0, 2.0 / 720.0 },
clip_offset: [2]f32 = [2]f32{ -1280.0 / 2.0, -720.0 / 2.0 },
cam_offset_px: [2]f32 = [2]f32{ 0.0, 0.0 },

pub fn update(self: *@This(), target_x: f32, target_y: f32, dt: f32) void {
    const map_w = map.info.width;
    const map_h = map.info.height;
    if (map_w == 0 or map_h == 0) return;

    var tx: f32 = target_x;
    var ty: f32 = target_y;
    if (self.quake) {
        const max_quake = 0.5;
        const quake_buildup = 10.0 * @as(f32, std.time.us_per_s);
        self.quake_amount += dt * max_quake / quake_buildup;
        if (self.quake_amount > max_quake) self.quake_amount = max_quake;
        tx += utils.plusMinus(self.quake_amount);
        ty += utils.plusMinus(self.quake_amount);
    }

    self.x = tx;
    self.y = ty;
    self.cam_offset_px[0] = tx * px_per_tile * self.scale;
    self.cam_offset_px[1] = ty * px_per_tile * self.scale;

    const w_half = self.width / (2.0 * px_per_tile * self.scale);
    const h_half = self.height / (2.0 * px_per_tile * self.scale);
    const max_dist = @ceil(@sqrt(w_half * w_half + h_half * h_half) + 1);

    const min_x_dt = tx - max_dist;
    self.min_x = @max(0, if (min_x_dt < 0) 0 else u32f(min_x_dt));
    self.max_x = @min(map_w - 1, u32f(tx + max_dist));

    const min_y_dt = ty - max_dist;
    self.min_y = @max(0, if (min_y_dt < 0) 0 else u32f(min_y_dt));
    self.max_y = @min(map_h - 1, u32f(ty + max_dist));
}

pub fn screenToWorld(self: Camera, x_in: f32, y_in: f32) struct { x: f32, y: f32 } {
    const x_div = (x_in - self.width / 2.0) / (px_per_tile * self.scale);
    const y_div = (y_in - self.height / 2.0) / (px_per_tile * self.scale);
    return .{ .x = self.x + x_div, .y = self.y + y_div };
}

pub fn worldToScreen(self: Camera, x_in: f32, y_in: f32) struct { x: f32, y: f32 } {
    return .{
        .x = x_in * px_per_tile * self.scale - self.cam_offset_px[0] - self.clip_offset[0],
        .y = y_in * px_per_tile * self.scale - self.cam_offset_px[1] - self.clip_offset[1],
    };
}

pub fn visibleInCamera(self: Camera, x_in: f32, y_in: f32) bool {
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

pub fn resetToDefaults(self: *Camera) void {
    inline for (@typeInfo(Camera).@"struct".fields) |field| {
        if (!std.mem.eql(u8, field.name, "width") and
            !std.mem.eql(u8, field.name, "height") and
            !std.mem.eql(u8, field.name, "clip_scale") and
            !std.mem.eql(u8, field.name, "clip_offset") and
            !std.mem.eql(u8, field.name, "cam_offset_px"))
            @field(self, field.name) = @as(*const field.type, @ptrCast(@alignCast(field.default_value_ptr orelse
                @panic("All settings need a default value, but it wasn't found")))).*;
    }
}
