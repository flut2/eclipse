const assets = @import("../../assets.zig");
const main = @import("../../main.zig");
const render = @import("../../render.zig");
const ElementBase = @import("element.zig").ElementBase;
const f32i = @import("shared").utils.f32i;

const MenuBackground = @This();
base: ElementBase,
w: f32,
h: f32,

pub fn draw(self: MenuBackground, _: render.CameraData, x_offset: f32, y_offset: f32, _: i64) void {
    if (!self.base.visible) return;
    render.generics.append(main.allocator, .{
        .render_type = .menu_bg,
        .pos = .{ self.base.x + x_offset, self.base.y + y_offset },
        .size = .{ self.w, self.h },
        .uv = .{ 0.0, 0.0 },
        .uv_size = .{ 1.0, 1.0 },
    }) catch main.oomPanic();
}

pub fn width(_: MenuBackground) f32 {
    return f32i(assets.menu_background.width);
}

pub fn height(_: MenuBackground) f32 {
    return f32i(assets.menu_background.height);
}

pub fn texWRaw(_: MenuBackground) f32 {
    return f32i(assets.menu_background.width);
}

pub fn texHRaw(_: MenuBackground) f32 {
    return f32i(assets.menu_background.height);
}
