const std = @import("std");

const glfw = @import("glfw");

const Renderer = @import("../../render/Renderer.zig");
const systems = @import("../systems.zig");
const Container = @import("Container.zig");
const Dropdown = @import("Dropdown.zig");
const element = @import("element.zig");
const ElementBase = element.ElementBase;

const DropdownContainer = @This();
base: ElementBase,
parent: *Dropdown,
container: Container,
pressCallback: *const fn (*DropdownContainer) void,
background_data: element.InteractableImageData,
state: element.InteractableState = .none,
index: u32 = std.math.maxInt(u32),

pub fn mousePress(self: *DropdownContainer, x: f32, y: f32, _: f32, _: f32, _: glfw.Mods) bool {
    if (!self.base.visible or self.index == self.parent.selected_index) return false;

    const in_bounds = element.intersects(self, x, y);
    if (in_bounds) {
        self.state = .pressed;
        if (self.parent.selected_index != std.math.maxInt(u32))
            self.parent.children.items[self.parent.selected_index].state = .none;
        self.parent.selected_index = self.index;
        if (self.parent.auto_close) self.parent.toggled = false;
        if (systems.hover_target != null and
            systems.hover_target.? == .dropdown_container and
            systems.hover_target.?.dropdown_container == self)
            systems.hover_target = null;
        self.pressCallback(self);
        return true;
    }

    return !(self.base.event_policy.pass_press or !in_bounds);
}

pub fn mouseRelease(self: *DropdownContainer, x: f32, y: f32, _: f32, _: f32) bool {
    if (!self.base.visible or self.index == self.parent.selected_index) return false;
    const in_bounds = element.intersects(self, x, y);
    if (in_bounds) self.state = .hovered;
    return !(self.base.event_policy.pass_release or !in_bounds);
}

pub fn mouseMove(self: *DropdownContainer, x: f32, y: f32, _: f32, _: f32) bool {
    if (!self.base.visible or self.index == self.parent.selected_index) return false;

    const in_bounds = element.intersects(self, x, y);
    if (in_bounds) {
        systems.hover_target = .{ .dropdown_container = self };
        self.state = .hovered;
    } else self.state = .none;

    return !(self.base.event_policy.pass_move or !in_bounds);
}

pub fn deinit(self: *DropdownContainer) void {
    self.container.deinit();
}

pub fn draw(
    self: DropdownContainer,
    generics: *std.ArrayListUnmanaged(Renderer.GenericData),
    sort_extras: *std.ArrayListUnmanaged(f32),
    x_offset: f32,
    y_offset: f32,
    time: i64,
) void {
    if (!self.base.visible) return;
    self.background_data.current(self.state).draw(generics, sort_extras, self.base.x + x_offset, self.base.y + y_offset, self.base.scissor);
    self.container.draw(generics, sort_extras, self.base.x + x_offset, self.base.y + y_offset, time);
}

pub fn width(self: *DropdownContainer) f32 {
    return @max(self.background_data.width(self.state), self.container.width());
}

pub fn height(self: *DropdownContainer) f32 {
    return @max(self.background_data.height(self.state), self.container.height());
}

pub fn texWRaw(self: *DropdownContainer) f32 {
    return @max(self.background_data.texWRaw(self.state), self.container.texWRaw());
}

pub fn texHRaw(self: *DropdownContainer) f32 {
    return @max(self.background_data.texHRaw(self.state), self.container.texHRaw());
}
