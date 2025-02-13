const std = @import("std");

const glfw = @import("glfw");

const main = @import("../../main.zig");
const CameraData = @import("../../render/CameraData.zig");
const Container = @import("Container.zig");
const element = @import("element.zig");
const ElementBase = element.ElementBase;
const Image = @import("Image.zig");
const Slider = @import("Slider.zig");

const ScrollableContainer = @This();

base: ElementBase,
scissor_w: f32,
scissor_h: f32,
scroll_x: f32,
scroll_y: f32,
scroll_w: f32,
scroll_h: f32,
scroll_side_x: f32 = -1.0,
scroll_side_y: f32 = -1.0,
scroll_side_decor_image_data: element.ImageData = undefined,
scroll_decor_image_data: element.ImageData,
scroll_knob_image_data: element.InteractableImageData,
// Range is [0.0, 1.0]
start_value: f32 = 0.0,
base_y: f32 = 0.0,
container: *Container = undefined,
scroll_bar: *Slider = undefined,
scroll_bar_decor: *Image = undefined,

pub fn mousePress(self: *ScrollableContainer, x: f32, y: f32, x_offset: f32, y_offset: f32, mods: glfw.Mods) bool {
    if (!self.base.visible) return false;
    if (self.container.mousePress(x, y, x_offset, y_offset, mods) or self.scroll_bar.mousePress(x, y, x_offset, y_offset, mods)) return true;
    return !(self.base.event_policy.pass_press or !element.intersects(self, x, y));
}

pub fn mouseRelease(self: *ScrollableContainer, x: f32, y: f32, x_offset: f32, y_offset: f32) bool {
    if (!self.base.visible) return false;
    if (self.container.mouseRelease(x, y, x_offset, y_offset) or self.scroll_bar.mouseRelease(x, y, x_offset, y_offset)) return true;
    return !(self.base.event_policy.pass_release or !element.intersects(self, x, y));
}

pub fn mouseMove(self: *ScrollableContainer, x: f32, y: f32, x_offset: f32, y_offset: f32) bool {
    if (!self.base.visible) return false;
    if (self.container.mouseMove(x, y, x_offset, y_offset) or self.scroll_bar.mouseMove(x, y, x_offset, y_offset)) return true;
    return !(self.base.event_policy.pass_move or !element.intersects(self, x, y));
}

pub fn mouseScroll(self: *ScrollableContainer, x: f32, y: f32, _: f32, _: f32, _: f32, y_scroll: f32) bool {
    if (!self.base.visible) return false;

    const in_bounds = element.intersects(self.container, x, y);
    if (in_bounds) {
        self.scroll_bar.setValue(
            @min(
                self.scroll_bar.max_value,
                @max(
                    self.scroll_bar.min_value,
                    self.scroll_bar.current_value +
                        (self.scroll_bar.max_value - self.scroll_bar.min_value) * -y_scroll / (self.container.height() / 10.0),
                ),
            ),
        );
        return true;
    }

    return !(self.base.event_policy.pass_scroll or !in_bounds);
}

pub fn init(self: *ScrollableContainer) void {
    if (self.start_value < 0.0 or self.start_value > 1.0)
        std.debug.panic("Invalid start_value for ScrollableContainer: {d:.2}", .{self.start_value});

    self.base_y = self.base.y;

    self.container = main.allocator.create(Container) catch main.oomPanic();
    self.container.* = .{ .base = .{
        .x = self.base.x,
        .y = self.base.y,
        .scissor = .{
            .min_x = 0,
            .min_y = 0,
            .max_x = self.scissor_w,
            .max_y = self.scissor_h,
        },
        .layer = self.base.layer,
    } };

    self.scroll_bar = self.container.createChild(Slider, .{
        .base = .{
            .x = self.scroll_x,
            .y = self.scroll_y,
            .layer = self.base.layer,
            .visible = false,
        },
        .w = self.scroll_w,
        .h = self.scroll_h,
        .decor_image_data = self.scroll_decor_image_data,
        .knob_image_data = self.scroll_knob_image_data,
        .min_value = 0.0,
        .max_value = 1.0,
        .continous_event_fire = true,
        .state_change = onScrollChanged,
        .vertical = true,
        .userdata = self,
        .current_value = self.start_value,
    }) catch @panic("ScrollableContainer scroll bar alloc failed");

    if (self.hasScrollDecor())
        self.scroll_bar_decor = self.container.createChild(Image, .{
            .base = .{
                .x = self.scroll_side_x,
                .y = self.scroll_side_y,
                .scissor = .{ .min_x = 0, .min_y = 0, .max_x = self.scissor_w, .max_y = self.scissor_h },
                .visible = false,
                .layer = self.base.layer,
                .event_policy = .pass_all,
            },
            .image_data = self.scroll_side_decor_image_data,
        }) catch @panic("ScrollableContainer scroll bar decor alloc failed");
}

pub fn deinit(self: *ScrollableContainer) void {
    self.container.deinit();
    main.allocator.destroy(self.container);
}

pub fn draw(self: ScrollableContainer, cam_data: CameraData, x_offset: f32, y_offset: f32, time: i64) void {
    if (!self.base.visible) return;
    self.container.draw(cam_data, x_offset, y_offset, time);
}

pub fn width(self: ScrollableContainer) f32 {
    return @max(self.container.width(), (self.scroll_bar.base.x - self.container.base.x) + self.scroll_bar.width());
}

pub fn height(self: ScrollableContainer) f32 {
    return @max(self.container.height(), (self.scroll_bar.base.y - self.container.base.y) + self.scroll_bar.height());
}

pub fn texWRaw(self: ScrollableContainer) f32 {
    return @max(self.container.texWRaw(), (self.scroll_bar.base.x - self.container.base.x) + self.scroll_bar.texWRaw());
}

pub fn texHRaw(self: ScrollableContainer) f32 {
    return @max(self.container.texHRaw(), (self.scroll_bar.base.y - self.container.base.y) + self.scroll_bar.texHRaw());
}

pub fn hasScrollDecor(self: ScrollableContainer) bool {
    return self.scroll_side_x > 0 and self.scroll_side_y > 0;
}

pub fn createChild(self: *ScrollableContainer, comptime T: type, data: T) !*T {
    const elem = self.container.createChild(T, data);
    self.update();
    return elem;
}

pub fn update(self: *ScrollableContainer) void {
    if (self.scissor_h >= self.container.height()) {
        self.scroll_bar.base.visible = false;
        if (self.hasScrollDecor()) self.scroll_bar_decor.base.visible = false;
        return;
    }

    const h_dt_base = (self.scissor_h - self.container.height());
    const h_dt = self.scroll_bar.current_value * h_dt_base;
    const new_h = self.scroll_bar.h / (2.0 + -h_dt_base / self.scissor_h);
    self.scroll_bar.knob_image_data.scaleHeight(new_h);
    self.scroll_bar.setValue(self.scroll_bar.current_value);
    self.scroll_bar.base.visible = true;
    if (self.hasScrollDecor()) self.scroll_bar_decor.base.visible = true;

    self.container.base.y = self.base_y + h_dt;
    self.container.base.scissor.min_y = -h_dt;
    self.container.base.scissor.max_y = -h_dt + self.scissor_h;
    self.container.updateScissors();
}

fn onScrollChanged(scroll_bar: *Slider) void {
    var parent: *ScrollableContainer = @alignCast(@ptrCast(scroll_bar.userdata));
    if (parent.scissor_h >= parent.container.height()) {
        parent.scroll_bar.base.visible = false;
        if (parent.hasScrollDecor()) parent.scroll_bar_decor.base.visible = false;
        return;
    }

    const h_dt_base = (parent.scissor_h - parent.container.height());
    const h_dt = scroll_bar.current_value * h_dt_base;
    const new_h = parent.scroll_bar.h / (2.0 + -h_dt_base / parent.scissor_h);
    parent.scroll_bar.knob_image_data.scaleHeight(new_h);
    parent.scroll_bar.base.visible = true;
    if (parent.hasScrollDecor()) parent.scroll_bar_decor.base.visible = true;

    parent.container.base.y = parent.base_y + h_dt;
    parent.container.base.scissor.min_y = -h_dt;
    parent.container.base.scissor.max_y = -h_dt + parent.scissor_h;
    parent.container.updateScissors();
}
