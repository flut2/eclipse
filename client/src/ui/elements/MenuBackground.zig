const assets = @import("../../assets.zig");
const render = @import("../../render.zig");
const main = @import("../../main.zig");

const MenuBackground = @This();
const ElementBase = @import("element.zig").ElementBase;

base: ElementBase,
w: f32,
h: f32,

pub fn draw(self: MenuBackground, _: render.CameraData, x_offset: f32, y_offset: f32, _: i64) void {
    if (!self.base.visible) return;
    render.generics.append(main.allocator, .{
        .render_type = .menu_bg,
        .pos = [_]f32{ self.base.x + x_offset, self.base.y + y_offset },
        .size = [_]f32{ self.w, self.h },
        .uv = [_]f32{ 0.0, 0.0 },
        .uv_size = [_]f32{ 1.0, 1.0 },
    }) catch @panic("OOM");
}

pub fn width(_: MenuBackground) f32 {
    return @floatFromInt(assets.menu_background.width);
}

pub fn height(_: MenuBackground) f32 {
    return @floatFromInt(assets.menu_background.height);
}

pub fn texWRaw(_: MenuBackground) f32 {
    return @floatFromInt(assets.menu_background.width);
}

pub fn texHRaw(_: MenuBackground) f32 {
    return @floatFromInt(assets.menu_background.height);
}
