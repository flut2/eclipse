const std = @import("std");

const glfw = @import("zglfw");
const shared = @import("shared");
const utils = shared.utils;
const f32i = utils.f32i;

const assets = @import("../../assets.zig");
const main = @import("../../main.zig");
const render = @import("../../render.zig");
const systems = @import("../systems.zig");
const DropdownContainer = @import("DropdownContainer.zig");
const element = @import("element.zig");
const ElementBase = element.ElementBase;
const ScrollableContainer = @import("ScrollableContainer.zig");

const Dropdown = @This();
base: ElementBase,
w: f32,
container: *ScrollableContainer = undefined,
container_inlay_x: f32,
container_inlay_y: f32,
// w/h will be overwritten
title_data: element.ImageData,
title_text: element.TextData,
// make sure h is appriopriate. w will be overwritten
background_data: element.ImageData,
button_data_collapsed: element.InteractableImageData,
button_data_extended: element.InteractableImageData,
// the w on these will be overwritten. h must match
main_background_data: element.InteractableImageData,
alt_background_data: element.InteractableImageData,
scroll_w: f32,
scroll_h: f32,
scroll_side_x_rel: f32 = std.math.floatMax(f32),
scroll_side_y_rel: f32 = std.math.floatMax(f32),
scroll_side_decor_image_data: element.ImageData = undefined,
scroll_decor_image_data: element.ImageData,
scroll_knob_image_data: element.InteractableImageData,
button_state: element.InteractableState = .none,
auto_close: bool = true,
toggled: bool = false,
next_index: u32 = 0,
selected_index: u32 = std.math.maxInt(u32),
lock: std.Thread.Mutex = .{},
children: std.ArrayListUnmanaged(*DropdownContainer) = .empty,

pub fn mousePress(self: *Dropdown, x: f32, y: f32, x_offset: f32, y_offset: f32, mods: glfw.Mods) bool {
    if (!self.base.visible) return false;

    const button_data = if (self.toggled) self.button_data_collapsed else self.button_data_extended;
    const current_button = button_data.current(self.button_state);
    const in_bounds = utils.isInBounds(x, y, self.base.x + self.title_data.width(), self.base.y, current_button.width(), current_button.height());
    if (in_bounds) {
        self.button_state = .pressed;
        self.toggled = !self.toggled;
        assets.playSfx("button.mp3");
        return true;
    }

    const block = !(self.base.event_policy.pass_press or !in_bounds);
    if (!block) return self.container.mousePress(x, y, x_offset, y_offset, mods);
    return block;
}

pub fn mouseRelease(self: *Dropdown, x: f32, y: f32, x_offset: f32, y_offset: f32) bool {
    if (!self.base.visible) return false;

    const button_data = if (self.toggled) self.button_data_collapsed else self.button_data_extended;
    const current_button = button_data.current(self.button_state);
    const in_bounds = utils.isInBounds(x, y, self.base.x + self.title_data.width(), self.base.y, current_button.width(), current_button.height());
    if (in_bounds) self.button_state = .none;

    const block = !(self.base.event_policy.pass_release or !in_bounds);
    if (!block) return self.container.mouseRelease(x, y, x_offset, y_offset);
    return block;
}

pub fn mouseMove(self: *Dropdown, x: f32, y: f32, x_offset: f32, y_offset: f32) bool {
    if (!self.base.visible) return false;

    const button_data = if (self.toggled) self.button_data_collapsed else self.button_data_extended;
    const current_button = button_data.current(self.button_state);
    const in_bounds = utils.isInBounds(x, y, self.base.x + self.title_data.width(), self.base.y, current_button.width(), current_button.height());
    if (in_bounds) {
        systems.hover_lock.lock();
        defer systems.hover_lock.unlock();
        systems.hover_target = element.UiElement{ .dropdown = self }; // TODO: re-add RLS when fixed
        self.button_state = .hovered;
    } else self.button_state = .none;

    const block = !(self.base.event_policy.pass_move or !in_bounds);
    if (!block) return self.container.mouseMove(x, y, x_offset, y_offset);
    return block;
}

pub fn mouseScroll(self: *Dropdown, x: f32, y: f32, x_offset: f32, y_offset: f32, x_scroll: f32, y_scroll: f32) bool {
    if (!self.base.visible) return false;
    if (self.container.mouseScroll(x, y, x_offset, y_offset, x_scroll, y_scroll)) return true;
    return !(self.base.event_policy.pass_scroll or !element.intersects(self, x, y));
}

pub fn init(self: *Dropdown) void {
    std.debug.assert(self.button_data_collapsed.width(.none) == self.button_data_extended.width(.none) and
        self.button_data_collapsed.height(.none) == self.button_data_extended.height(.none) and
        self.button_data_collapsed.width(.hovered) == self.button_data_extended.width(.hovered) and
        self.button_data_collapsed.height(.hovered) == self.button_data_extended.height(.hovered) and
        self.button_data_collapsed.width(.pressed) == self.button_data_extended.width(.pressed) and
        self.button_data_collapsed.height(.pressed) == self.button_data_extended.height(.pressed));

    std.debug.assert(self.main_background_data.height(.none) == self.alt_background_data.height(.none) and
        self.main_background_data.height(.hovered) == self.alt_background_data.height(.hovered) and
        self.main_background_data.height(.pressed) == self.alt_background_data.height(.pressed));

    self.background_data.scaleWidth(self.w);
    self.title_data.scaleWidth(self.w - self.button_data_collapsed.width(.none));
    self.title_data.scaleHeight(self.button_data_collapsed.height(.none));

    self.title_text.max_width = self.title_data.width();
    self.title_text.max_height = self.title_data.height();
    self.title_text.vert_align = .middle;
    self.title_text.hori_align = .middle;
    {
        self.title_text.lock.lock();
        defer self.title_text.lock.unlock();
        self.title_text.recalculateAttributes();
    }

    const w_base = self.w - self.container_inlay_x * 2;
    const scroll_max_w = @max(self.scroll_w, self.scroll_knob_image_data.width(.none));
    const scissor_w = w_base - scroll_max_w - 2 +
        (if (self.scroll_side_x_rel > 0.0) 0.0 else self.scroll_side_x_rel);

    self.main_background_data.scaleWidth(w_base);
    self.alt_background_data.scaleWidth(w_base);

    const scroll_x_base = self.base.x + self.container_inlay_x + scissor_w + 2;
    const scroll_y_base = self.base.y + self.container_inlay_y + self.title_data.height();
    self.container = main.allocator.create(ScrollableContainer) catch @panic("Dropdown child container alloc failed");
    self.container.* = .{
        .base = .{
            .x = self.base.x + self.container_inlay_x,
            .y = self.base.y + self.container_inlay_y + self.title_data.height(),
            .layer = self.base.layer,
        },
        .scissor_w = scissor_w,
        .scissor_h = self.background_data.height() - self.container_inlay_y * 2 - 6,
        .scroll_x = scroll_x_base + if (self.scroll_side_x_rel == std.math.floatMax(f32)) 0.0 else -self.scroll_side_x_rel,
        .scroll_y = scroll_y_base + if (self.scroll_side_y_rel == std.math.floatMax(f32)) 0.0 else -self.scroll_side_y_rel,
        .scroll_w = self.scroll_w,
        .scroll_h = self.scroll_h,
        .scroll_side_x = scroll_x_base,
        .scroll_side_y = scroll_y_base,
        .scroll_decor_image_data = self.scroll_decor_image_data,
        .scroll_knob_image_data = self.scroll_knob_image_data,
        .scroll_side_decor_image_data = self.scroll_side_decor_image_data,
    };
    self.container.init();
}

pub fn deinit(self: *Dropdown) void {
    self.title_text.deinit();
    self.container.deinit();
    self.children.deinit(main.allocator);
    main.allocator.destroy(self.container);
}

pub fn draw(self: *Dropdown, cam_data: render.CameraData, x_offset: f32, y_offset: f32, time: i64) void {
    if (!self.base.visible) return;

    const base_x = self.base.x + x_offset;
    const base_y = self.base.y + y_offset;
    const title_w, const title_h = switch (self.title_data) {
        .nine_slice => |nine_slice| .{ nine_slice.w, nine_slice.h },
        .normal => |normal| .{ normal.texWRaw(), normal.texHRaw() },
    };
    self.title_data.draw(base_x, base_y, self.base.scissor);

    render.drawText(base_x, base_y, 1.0, &self.title_text, self.base.scissor);

    const toggled = self.toggled;
    const button_image_data = (if (toggled) self.button_data_extended else self.button_data_collapsed).current(self.button_state);
    button_image_data.draw(base_x + title_w, base_y, self.base.scissor);

    if (self.toggled and self.container.base.visible) {
        self.background_data.draw(base_x, base_y + title_h, self.base.scissor);

        self.lock.lock();
        defer self.lock.unlock();
        self.container.draw(cam_data, x_offset, y_offset, time);
    }
}

pub fn width(self: Dropdown) f32 {
    return self.background_data.width();
}

pub fn height(self: Dropdown) f32 {
    return self.title_data.height() + (if (self.toggled) self.background_data.height() else 0.0);
}

pub fn texWRaw(self: Dropdown) f32 {
    return self.background_data.texWRaw();
}

pub fn texHRaw(self: Dropdown) f32 {
    return self.title_data.texHRaw() + (if (self.toggled) self.background_data.texHRaw() else 0.0);
}

// the container field's x/y are relative to parents
pub fn createChild(self: *Dropdown, pressCallback: *const fn (*DropdownContainer) void) !*DropdownContainer {
    self.lock.lock();
    defer self.lock.unlock();

    const scroll_vis_pre = self.container.scroll_bar.base.visible;

    const next_idx = f32i(self.next_index);
    const ret = try self.container.createChild(DropdownContainer, .{
        .base = .{
            .x = 0,
            .y = self.main_background_data.height(.none) * next_idx,
            .layer = self.base.layer,
            .visible = self.base.visible,
        },
        .parent = self,
        .container = .{ .base = .{
            .x = 0,
            .y = 0,
            .visible = self.base.visible,
        } },
        .pressCallback = pressCallback,
        .index = self.next_index,
        .background_data = if (@mod(self.next_index, 2) == 0) self.main_background_data else self.alt_background_data,
    });
    self.next_index += 1;
    try self.children.append(main.allocator, ret);

    if (self.container.scroll_bar.base.visible and !scroll_vis_pre) {
        self.main_background_data.scaleWidth(self.container.scissor_w);
        self.alt_background_data.scaleWidth(self.container.scissor_w);
    }

    return ret;
}
