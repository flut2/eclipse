const std = @import("std");

const glfw = @import("zglfw");

const main = @import("../../main.zig");
const render = @import("../../render.zig");
const systems = @import("../systems.zig");
const element = @import("element.zig");
const ElementBase = element.ElementBase;

const Container = @This();
base: ElementBase,
draggable: bool = false,
drag_start_x: f32 = 0,
drag_start_y: f32 = 0,
drag_offset_x: f32 = 0,
drag_offset_y: f32 = 0,
is_dragging: bool = false,
clamp_x: bool = false,
clamp_y: bool = false,
clamp_to_screen: bool = false,
elements: std.ArrayListUnmanaged(element.UiElement) = .empty,

pub fn mousePress(self: *Container, x: f32, y: f32, x_offset: f32, y_offset: f32, mods: glfw.Mods) bool {
    if (!self.base.visible) return false;

    var iter = std.mem.reverseIterator(self.elements.items);
    while (iter.next()) |elem| switch (elem) {
        inline else => |inner_elem| if (std.meta.hasFn(@typeInfo(@TypeOf(inner_elem)).pointer.child, "mousePress") and
            inner_elem.mousePress(x - self.base.x, y - self.base.y, self.base.x + x_offset, self.base.y + y_offset, mods))
            return true,
    };

    const in_bounds = element.intersects(self, x, y);
    if (self.draggable and in_bounds) {
        self.is_dragging = true;
        self.drag_start_x = self.base.x;
        self.drag_start_y = self.base.y;
        self.drag_offset_x = self.base.x - x;
        self.drag_offset_y = self.base.y - y;
    }

    return !(self.base.event_policy.pass_press or !in_bounds);
}

pub fn mouseRelease(self: *Container, x: f32, y: f32, x_offset: f32, y_offset: f32) bool {
    if (!self.base.visible) return false;
    if (self.is_dragging) self.is_dragging = false;

    var iter = std.mem.reverseIterator(self.elements.items);
    while (iter.next()) |elem| switch (elem) {
        inline else => |inner_elem| if (std.meta.hasFn(@typeInfo(@TypeOf(inner_elem)).pointer.child, "mouseRelease") and
            inner_elem.mouseRelease(x - self.base.x, y - self.base.y, self.base.x + x_offset, self.base.y + y_offset))
            return true,
    };

    return !(self.base.event_policy.pass_release or !element.intersects(self, x, y));
}

pub fn mouseMove(self: *Container, x: f32, y: f32, x_offset: f32, y_offset: f32) bool {
    if (!self.base.visible) return false;

    if (self.is_dragging) {
        if (!self.clamp_x) {
            self.base.x = x + self.drag_offset_x;
            if (self.clamp_to_screen) {
                if (self.base.x > 0) self.base.x = 0;
                const bottom_x = self.base.x + self.width();
                if (bottom_x < main.camera.width) self.base.x = self.width();
            }
        }

        if (!self.clamp_y) {
            self.base.y = y + self.drag_offset_y;
            if (self.clamp_to_screen) {
                if (self.base.y > 0) self.base.y = 0;
                const bottom_y = self.base.y + self.height();
                if (bottom_y < main.camera.height) self.base.y = bottom_y;
            }
        }
    }

    var iter = std.mem.reverseIterator(self.elements.items);
    while (iter.next()) |elem| switch (elem) {
        inline else => |inner_elem| if (std.meta.hasFn(@typeInfo(@TypeOf(inner_elem)).pointer.child, "mouseMove") and
            inner_elem.mouseMove(x - self.base.x, y - self.base.y, self.base.x + x_offset, self.base.y + y_offset))
            return true,
    };

    return !(self.base.event_policy.pass_move or !element.intersects(self, x, y));
}

pub fn mouseScroll(self: *Container, x: f32, y: f32, x_offset: f32, y_offset: f32, x_scroll: f32, y_scroll: f32) bool {
    if (!self.base.visible) return false;

    var iter = std.mem.reverseIterator(self.elements.items);
    while (iter.next()) |elem| switch (elem) {
        inline else => |inner_elem| if (std.meta.hasFn(@typeInfo(@TypeOf(inner_elem)).pointer.child, "mouseScroll") and
            inner_elem.mouseScroll(x - self.base.x, y - self.base.y, self.base.x + x_offset, self.base.y + y_offset, x_scroll, y_scroll))
            return true,
    };

    return !(self.base.event_policy.pass_scroll or !element.intersects(self, x, y));
}

pub fn deinit(self: *Container) void {
    for (self.elements.items) |*elem| switch (elem.*) {
        inline else => |inner_elem| {
            comptime var field_name: []const u8 = "";
            inline for (@typeInfo(element.UiElement).@"union".fields) |field| {
                if (field.type == @TypeOf(inner_elem)) {
                    field_name = field.name;
                    break;
                }
            }

            if (field_name.len == 0) @compileError("Could not find field name");

            const tag = std.meta.stringToEnum(std.meta.Tag(element.UiElement), field_name);
            if (systems.hover_target != null and
                std.meta.activeTag(systems.hover_target.?) == tag and
                inner_elem == @field(systems.hover_target.?, field_name))
                systems.hover_target = null;

            if (std.meta.hasFn(@typeInfo(@TypeOf(inner_elem)).pointer.child, "deinit")) inner_elem.deinit();
            main.allocator.destroy(inner_elem);
        },
    };
    self.elements.deinit(main.allocator);
}

pub fn draw(self: Container, cam_data: render.CameraData, x_offset: f32, y_offset: f32, time: i64) void {
    if (!self.base.visible) return;
    for (self.elements.items) |elem| elem.draw(cam_data, x_offset + self.base.x, y_offset + self.base.y, time);
}

pub fn width(self: *Container) f32 {
    if (self.elements.items.len <= 0) return 0.0;

    var min_x = std.math.floatMax(f32);
    var max_x = std.math.floatMin(f32);
    for (self.elements.items) |elem| switch (elem) {
        inline else => |inner_elem| {
            min_x = @min(min_x, inner_elem.base.x);
            max_x = @max(max_x, inner_elem.base.x + inner_elem.width());
        },
    };

    return max_x - min_x;
}

pub fn height(self: *Container) f32 {
    if (self.elements.items.len <= 0) return 0.0;

    var min_y = std.math.floatMax(f32);
    var max_y = std.math.floatMin(f32);
    for (self.elements.items) |elem| switch (elem) {
        inline else => |inner_elem| {
            min_y = @min(min_y, inner_elem.base.y);
            max_y = @max(max_y, inner_elem.base.y + inner_elem.height());
        },
    };

    return max_y - min_y;
}

pub fn texWRaw(self: *Container) f32 {
    if (self.elements.items.len <= 0) return 0.0;

    var min_x = std.math.floatMax(f32);
    var max_x = std.math.floatMin(f32);
    for (self.elements.items) |elem| {
        switch (elem) {
            inline else => |inner_elem| {
                min_x = @min(min_x, inner_elem.base.x);
                max_x = @max(max_x, inner_elem.base.x + inner_elem.texWRaw());
            },
        }
    }

    return max_x - min_x;
}

pub fn texHRaw(self: *Container) f32 {
    if (self.elements.items.len <= 0) return 0.0;

    var min_y = std.math.floatMax(f32);
    var max_y = std.math.floatMin(f32);
    for (self.elements.items) |elem| {
        switch (elem) {
            inline else => |inner_elem| {
                min_y = @min(min_y, inner_elem.base.y);
                max_y = @max(max_y, inner_elem.base.y + inner_elem.texHRaw());
            },
        }
    }

    return max_y - min_y;
}

pub fn createChild(self: *Container, comptime T: type, data: T) !*T {
    var elem = try main.allocator.create(T);
    elem.* = data;
    if (std.meta.hasFn(T, "init")) elem.init();
    const ScissorRect = element.ScissorRect;
    elem.base.scissor = .{
        .min_x = if (self.base.scissor.min_x == ScissorRect.dont_scissor)
            ScissorRect.dont_scissor
        else
            self.base.scissor.min_x - elem.base.x,
        .min_y = if (self.base.scissor.min_y == ScissorRect.dont_scissor)
            ScissorRect.dont_scissor
        else
            self.base.scissor.min_y - elem.base.y,
        .max_x = if (self.base.scissor.max_x == ScissorRect.dont_scissor)
            ScissorRect.dont_scissor
        else
            self.base.scissor.max_x - elem.base.x,
        .max_y = if (self.base.scissor.max_y == ScissorRect.dont_scissor)
            ScissorRect.dont_scissor
        else
            self.base.scissor.max_y - elem.base.y,
    };

    comptime var field_name: []const u8 = "";
    inline for (@typeInfo(element.UiElement).@"union".fields) |field| {
        if (@typeInfo(field.type).pointer.child == T) {
            field_name = field.name;
            break;
        }
    }

    if (field_name.len == 0) @compileError("Could not find field name");
    try self.elements.append(main.allocator, @unionInit(element.UiElement, field_name, elem));
    return elem;
}

pub fn updateScissors(self: *Container) void {
    const ScissorRect = element.ScissorRect;
    for (self.elements.items) |elem| {
        switch (elem) {
            .scrollable_container => {},
            inline else => |inner_elem| {
                inner_elem.base.scissor = .{
                    .min_x = if (self.base.scissor.min_x == ScissorRect.dont_scissor)
                        ScissorRect.dont_scissor
                    else
                        self.base.scissor.min_x - inner_elem.base.x,
                    .min_y = if (self.base.scissor.min_y == ScissorRect.dont_scissor)
                        ScissorRect.dont_scissor
                    else
                        self.base.scissor.min_y - inner_elem.base.y,
                    .max_x = if (self.base.scissor.max_x == ScissorRect.dont_scissor)
                        ScissorRect.dont_scissor
                    else
                        self.base.scissor.max_x - inner_elem.base.x,
                    .max_y = if (self.base.scissor.max_y == ScissorRect.dont_scissor)
                        ScissorRect.dont_scissor
                    else
                        self.base.scissor.max_y - inner_elem.base.y,
                };
            },
        }

        if (elem == .container) {
            elem.container.updateScissors();
        } else if (elem == .dropdown_container) {
            // lol
            elem.dropdown_container.background_data.setScissor(elem.dropdown_container.base.scissor);
            elem.dropdown_container.container.base.scissor = elem.dropdown_container.base.scissor;
            elem.dropdown_container.container.updateScissors();
        }
    }
}
