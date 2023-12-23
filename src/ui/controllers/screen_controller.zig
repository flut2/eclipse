const std = @import("std");
const element = @import("../element.zig");
const input = @import("../../input.zig");
const camera = @import("../../camera.zig");
const utils = @import("../../utils.zig");
const main = @import("../../main.zig");
const map = @import("../../map.zig");
const assets = @import("../../assets.zig");
const tooltip = @import("../tooltips/tooltip.zig");
const zglfw = @import("zglfw");

const AccountLoginScreen = @import("../screens/account/account_login_screen.zig").AccountLoginScreen;
const AccountRegisterScreen = @import("../screens/account/account_register_screen.zig").AccountRegisterScreen;
const CharCreateScreen = @import("../screens/character/char_create_screen.zig").CharCreateScreen;
const CharSelectScreen = @import("../screens/character/char_select_screen.zig").CharSelectScreen;
const MapEditorScreen = @import("../screens/map_editor_screen.zig").MapEditorScreen;
const GameScreen = @import("../screens/game_screen.zig").GameScreen;
const EmptyScreen = @import("../screens/empty_screen.zig").EmptyScreen;

pub const ScreenType = enum {
    empty,
    main_menu,
    register,
    char_select,
    char_create,
    game,
    editor,
};

pub const Screen = union(ScreenType) {
    empty: *EmptyScreen,
    main_menu: *AccountLoginScreen,
    register: *AccountRegisterScreen,
    char_select: *CharSelectScreen,
    char_create: *CharCreateScreen,
    game: *GameScreen,
    editor: *MapEditorScreen,
};

pub var ui_lock: std.Thread.Mutex = .{};
pub var temp_elem_lock: std.Thread.Mutex = .{};
pub var elements: std.ArrayList(element.UiElement) = undefined;
pub var tooltip_elements: std.ArrayList(element.UiElement) = undefined;
pub var temp_elements: std.ArrayList(element.Temporary) = undefined;
pub var current_screen: Screen = undefined;

pub var menu_background: *element.MenuBackground = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    elements = try std.ArrayList(element.UiElement).initCapacity(allocator, 32);
    tooltip_elements = try std.ArrayList(element.UiElement).initCapacity(allocator, 32);
    temp_elements = try std.ArrayList(element.Temporary).initCapacity(allocator, 32);

    menu_background = try element.MenuBackground.create(allocator, .{
        .x = 0,
        .y = 0,
        .w = camera.screen_width,
        .h = camera.screen_height,
    });

    current_screen = .{ .empty = try EmptyScreen.init(allocator) };

    try tooltip.init(allocator);
}

pub fn deinit(allocator: std.mem.Allocator) void {
    while (!ui_lock.tryLock()) {}
    defer ui_lock.unlock();

    tooltip.deinit();

    menu_background.destroy();

    switch (current_screen) {
        inline else => |screen| screen.deinit(),
    }

    while (!temp_elem_lock.tryLock()) {}
    defer temp_elem_lock.unlock();

    // Do not dispose normal UI elements here, it's the screen's job to handle that

    for (temp_elements.items) |*elem| {
        switch (elem.*) {
            inline else => |*inner| {
                if (inner._disposed)
                    return;

                inner._disposed = true;

                allocator.free(inner.text_data.text);
                inner.text_data.deinit(allocator);
            },
        }
    }

    elements.deinit();
    tooltip_elements.deinit();
    temp_elements.deinit();
}

pub fn switchScreen(screen_type: ScreenType) void {
    while (!ui_lock.tryLock()) {}
    defer ui_lock.unlock();

    menu_background.visible = screen_type != .game and screen_type != .editor;
    input.selected_key_mapper = null;

    switch (current_screen) {
        inline else => |screen| if (screen.inited) screen.deinit(),
    }

    // should probably figure out some comptime magic to avoid all this... todo
    switch (screen_type) {
        .empty => current_screen = .{ .empty = EmptyScreen.init(main._allocator) catch unreachable },
        .main_menu => {
            current_screen = .{ .main_menu = AccountLoginScreen.init(main._allocator) catch |e| {
                std.log.err("Initializing login screen failed: {any}", .{e});
                return;
            } };
        },
        .register => {
            current_screen = .{ .register = AccountRegisterScreen.init(main._allocator) catch |e| {
                std.log.err("Initializing register screen failed: {any}", .{e});
                return;
            } };
        },
        .char_select => {
            current_screen = .{ .char_select = CharSelectScreen.init(main._allocator) catch |e| {
                std.log.err("Initializing char select screen failed: {any}", .{e});
                return;
            } };
        },
        .char_create => {
            current_screen = .{ .char_create = CharCreateScreen.init(main._allocator) catch |e| {
                std.log.err("Initializing char create screen failed: {any}", .{e});
                return;
            } };
        },
        .game => {
            current_screen = .{ .game = GameScreen.init(main._allocator) catch |e| {
                std.log.err("Initializing in game screen failed: {any}", .{e});
                return;
            } };
        },
        .editor => {
            current_screen = .{ .editor = MapEditorScreen.init(main._allocator) catch |e| {
                std.log.err("Initializing in editor screen failed: {any}", .{e});
                return;
            } };
        },
    }
}

pub fn resize(w: f32, h: f32) void {
    while (!ui_lock.tryLock()) {}
    defer ui_lock.unlock();

    menu_background.w = camera.screen_width;
    menu_background.h = camera.screen_height;

    switch (current_screen) {
        inline else => |screen| screen.resize(w, h),
    }
}

pub fn removeAttachedUi(obj_id: i32, allocator: std.mem.Allocator) void {
    if (temp_elements.items.len <= 0)
        return;

    while (!temp_elem_lock.tryLock()) {}
    defer temp_elem_lock.unlock();

    // We iterate in reverse in order to preserve integrity, because we remove elements in place
    var iter = std.mem.reverseIterator(temp_elements.items);
    var i: usize = temp_elements.items.len - 1;
    while (iter.nextPtr()) |elem| {
        defer i -%= 1;

        switch (elem.*) {
            .status => |*status| {
                if (status.obj_id == obj_id) {
                    status.destroy(allocator);
                    _ = temp_elements.swapRemove(i);
                }
            },
            .balloon => |*balloon| {
                if (balloon.target_id == obj_id) {
                    balloon.destroy(allocator);
                    _ = temp_elements.swapRemove(i);
                }
            },
        }
    }
}

fn elemMove(elem: element.UiElement, x: f32, y: f32, x_offset: f32, y_offset: f32) void {
    switch (elem) {
        .scrollable_container => |scrollable_container| {
            if (!scrollable_container.visible)
                return;

            const container = scrollable_container._container;
            elemMove(.{ .container = container }, x - container.x, y - container.y, container.x, container.y);
            elemMove(.{ .slider = scrollable_container._scroll_bar }, x, y, 0, 0);
        },
        .container => |container| {
            if (!container.visible)
                return;

            if (container._is_dragging) {
                if (!container._clamp_x) {
                    container.x = x + container._drag_offset_x;
                    if (container._clamp_to_screen) {
                        if (container.x > 0)
                            container.x = 0;

                        const bottom_x = container.x + container.width();
                        if (bottom_x < camera.screen_width)
                            container.x = container.width();
                    }
                }
                if (!container._clamp_y) {
                    container.y = y + container._drag_offset_y;
                    if (container._clamp_to_screen) {
                        if (container.y > 0)
                            container.y = 0;

                        const bottom_y = container.y + container.height();
                        if (bottom_y < camera.screen_height)
                            container.y = bottom_y;
                    }
                }
            }

            for (container._elements.items) |container_elem| {
                elemMove(container_elem, x - container.x, y - container.y, container.x, container.y);
            }
        },
        .item => |item| {
            if (!item.visible)
                return;

            if (utils.isInBounds(x, y, item.x, item.y, item.width(), item.height())) {
                tooltip.switchTooltip(.item);
                tooltip.current_tooltip.item.update(x + x_offset, y + y_offset, item._item);
            }

            if (!item._is_dragging)
                return;

            item.x = x + item._drag_offset_x;
            item.y = y + item._drag_offset_y;
        },
        .button => |button| {
            if (!button.visible)
                return;

            if (utils.isInBounds(x, y, button.x, button.y, button.width(), button.height())) {
                button.state = .hovered;
            } else {
                button.state = .none;
            }
        },
        .toggle => |toggle| {
            if (!toggle.visible)
                return;

            if (utils.isInBounds(x, y, toggle.x, toggle.y, toggle.width(), toggle.height())) {
                if (toggle.tooltip_text) |text_data| {
                    tooltip.switchTooltip(.text);
                    tooltip.current_tooltip.text.update(x + x_offset, y + y_offset, text_data);
                }

                toggle.state = .hovered;
            } else {
                toggle.state = .none;
            }
        },
        .char_box => |box| {
            if (!box.visible)
                return;

            if (utils.isInBounds(x, y, box.x, box.y, box.width(), box.height())) {
                box.state = .hovered;
            } else {
                box.state = .none;
            }
        },
        .input_field => |input_field| {
            if (!input_field.visible)
                return;

            if (utils.isInBounds(x, y, input_field.x, input_field.y, input_field.width(), input_field.height())) {
                input_field.state = .hovered;
            } else {
                input_field.state = .none;
            }
        },
        .key_mapper => |key_mapper| {
            if (!key_mapper.visible)
                return;

            if (utils.isInBounds(x, y, key_mapper.x, key_mapper.y, key_mapper.width(), key_mapper.height())) {
                if (key_mapper.tooltip_text) |text_data| {
                    tooltip.switchTooltip(.text);
                    tooltip.current_tooltip.text.update(x + x_offset, y + y_offset, text_data);
                }

                key_mapper.state = .hovered;
            } else {
                key_mapper.state = .none;
            }
        },
        .slider => |slider| {
            if (!slider.visible)
                return;

            const knob_w = switch (slider.knob_image_data.current(slider.state)) {
                .nine_slice => |nine_slice| nine_slice.w,
                .normal => |normal| normal.width(),
            };

            const knob_h = switch (slider.knob_image_data.current(slider.state)) {
                .nine_slice => |nine_slice| nine_slice.h,
                .normal => |normal| normal.height(),
            };

            if (utils.isInBounds(x, y, slider.x, slider.y, slider.width(), slider.height())) {
                if (slider.tooltip_text) |text_data| {
                    tooltip.switchTooltip(.text);
                    tooltip.current_tooltip.text.update(x + x_offset, y + y_offset, text_data);
                }
            }

            if (slider.state == .pressed) {
                sliderPressed(slider, x, y, knob_h, knob_w);
            } else if (utils.isInBounds(x, y, slider.x + slider._knob_x, slider.y + slider._knob_y, knob_w, knob_h)) {
                slider.state = .hovered;
            } else if (slider.state == .hovered) {
                slider.state = .none;
            }
        },
        else => {},
    }
}

pub fn mouseMove(x: f32, y: f32) void {
    tooltip.switchTooltip(.none);

    for (elements.items) |elem| {
        elemMove(elem, x, y, 0, 0);
    }

    for (tooltip_elements.items) |elem| {
        elemMove(elem, x, y, 0, 0);
    }
}

fn elemPress(elem: element.UiElement, x: f32, y: f32, mods: zglfw.Mods) bool {
    switch (elem) {
        .scrollable_container => |scrollable_container| {
            if (!scrollable_container.visible)
                return false;

            const container = scrollable_container._container;
            if (elemPress(.{ .container = container }, x - container.x, y - container.y, mods) or
                elemPress(.{ .slider = scrollable_container._scroll_bar }, x, y, mods))
                return true;
        },
        .container => |container| {
            if (!container.visible)
                return false;

            var cont_iter = std.mem.reverseIterator(container._elements.items);
            while (cont_iter.next()) |container_elem| {
                if (elemPress(container_elem, x - container.x, y - container.y, mods))
                    return true;
            }

            if (container.draggable and utils.isInBounds(x, y, container.x, container.y, container.width(), container.height())) {
                container._is_dragging = true;
                container._drag_start_x = container.x;
                container._drag_start_y = container.y;
                container._drag_offset_x = container.x - x;
                container._drag_offset_y = container.y - y;
            }
        },
        .item => |item| {
            if (!item.visible or !item.draggable)
                return false;

            if (utils.isInBounds(x, y, item.x, item.y, item.width(), item.height())) {
                if (mods.shift) {
                    item.shift_click_callback(item);
                    return true;
                }

                if (item._last_click_time + 333 * std.time.us_per_ms > main.current_time) {
                    item.double_click_callback(item);
                    return true;
                }

                item._is_dragging = true;
                item._drag_start_x = item.x;
                item._drag_start_y = item.y;
                item._drag_offset_x = item.x - x;
                item._drag_offset_y = item.y - y;
                item._last_click_time = main.current_time;
                item.drag_start_callback(item);
                return true;
            }
        },
        .button => |button| {
            if (!button.visible)
                return false;

            if (utils.isInBounds(x, y, button.x, button.y, button.width(), button.height())) {
                button.state = .pressed;
                button.press_callback();
                assets.playSfx("button_click");
                return true;
            }
        },
        .toggle => |toggle| {
            if (!toggle.visible)
                return false;

            if (utils.isInBounds(x, y, toggle.x, toggle.y, toggle.width(), toggle.height())) {
                toggle.state = .pressed;
                toggle.toggled.* = !toggle.toggled.*;
                if (toggle.state_change) |callback| {
                    callback(toggle);
                }
                assets.playSfx("button_click");
                return true;
            }
        },
        .char_box => |box| {
            if (!box.visible)
                return false;

            if (utils.isInBounds(x, y, box.x, box.y, box.width(), box.height())) {
                box.state = .pressed;
                box.press_callback(box);
                assets.playSfx("button_click");
                return true;
            }
        },
        .input_field => |input_field| {
            if (!input_field.visible)
                return false;

            if (utils.isInBounds(x, y, input_field.x, input_field.y, input_field.width(), input_field.height())) {
                input.selected_input_field = input_field;
                input_field._last_input = 0;
                input_field.state = .pressed;
                return true;
            }
        },
        .key_mapper => |key_mapper| {
            if (!key_mapper.visible)
                return false;

            if (utils.isInBounds(x, y, key_mapper.x, key_mapper.y, key_mapper.width(), key_mapper.height())) {
                key_mapper.state = .pressed;

                if (input.selected_key_mapper == null) {
                    key_mapper.listening = true;
                    input.selected_key_mapper = key_mapper;
                }

                assets.playSfx("button_click");
                return true;
            }
        },
        .slider => |slider| {
            if (!slider.visible)
                return false;

            if (utils.isInBounds(x, y, slider.x, slider.y, slider.w, slider.h)) {
                const knob_w = switch (slider.knob_image_data.current(slider.state)) {
                    .nine_slice => |nine_slice| nine_slice.w,
                    .normal => |normal| normal.width(),
                };

                const knob_h = switch (slider.knob_image_data.current(slider.state)) {
                    .nine_slice => |nine_slice| nine_slice.h,
                    .normal => |normal| normal.height(),
                };

                sliderPressed(slider, x, y, knob_h, knob_w);
            }
        },
        else => {},
    }

    return false;
}

pub fn mousePress(x: f32, y: f32, mods: zglfw.Mods, button: zglfw.MouseButton) bool {
    if (input.selected_input_field) |input_field| {
        input_field._last_input = -1;
        input.selected_input_field = null;
    }

    if (input.selected_key_mapper) |key_mapper| {
        key_mapper.key = .unknown;
        key_mapper.mouse = button;
        key_mapper.listening = false;
        key_mapper.set_key_callback(key_mapper);
        input.selected_key_mapper = null;
    }

    var elem_iter = std.mem.reverseIterator(elements.items);
    while (elem_iter.next()) |elem| {
        if (elemPress(elem, x, y, mods))
            return true;
    }

    var tooltip_elem_iter = std.mem.reverseIterator(tooltip_elements.items);
    while (tooltip_elem_iter.next()) |elem| {
        if (elemPress(elem, x, y, mods))
            return true;
    }

    return false;
}

fn elemRelease(elem: element.UiElement, x: f32, y: f32) void {
    switch (elem) {
        .scrollable_container => |scrollable_container| {
            if (!scrollable_container.visible)
                return;

            const container = scrollable_container._container;
            elemRelease(.{ .container = container }, x - container.x, y - container.y);
            elemRelease(.{ .slider = scrollable_container._scroll_bar }, x, y);
        },
        .container => |container| {
            if (!container.visible)
                return;

            if (container._is_dragging)
                container._is_dragging = false;

            for (container._elements.items) |container_elem| {
                elemRelease(container_elem, x - container.x, y - container.y);
            }
        },
        .item => |item| {
            if (!item._is_dragging)
                return;

            item._is_dragging = false;
            item.drag_end_callback(item);
        },
        .button => |button| {
            if (!button.visible)
                return;

            if (utils.isInBounds(x, y, button.x, button.y, button.width(), button.height())) {
                button.state = .none;
            }
        },
        .toggle => |toggle| {
            if (!toggle.visible)
                return;

            if (utils.isInBounds(x, y, toggle.x, toggle.y, toggle.width(), toggle.height())) {
                toggle.state = .none;
            }
        },
        .char_box => |box| {
            if (!box.visible)
                return;

            if (utils.isInBounds(x, y, box.x, box.y, box.width(), box.height())) {
                box.state = .none;
            }
        },
        .input_field => |input_field| {
            if (!input_field.visible)
                return;

            if (utils.isInBounds(x, y, input_field.x, input_field.y, input_field.width(), input_field.height())) {
                input_field.state = .none;
            }
        },
        .key_mapper => |key_mapper| {
            if (!key_mapper.visible)
                return;

            if (utils.isInBounds(x, y, key_mapper.x, key_mapper.y, key_mapper.width(), key_mapper.height())) {
                key_mapper.state = .none;
            }
        },
        .slider => |slider| {
            if (!slider.visible)
                return;

            if (slider.state == .pressed) {
                const knob_w = switch (slider.knob_image_data.current(slider.state)) {
                    .nine_slice => |nine_slice| nine_slice.w,
                    .normal => |normal| normal.width(),
                };

                const knob_h = switch (slider.knob_image_data.current(slider.state)) {
                    .nine_slice => |nine_slice| nine_slice.h,
                    .normal => |normal| normal.height(),
                };

                if (utils.isInBounds(x, y, slider._knob_x, slider._knob_y, knob_w, knob_h)) {
                    slider.state = .hovered;
                } else {
                    slider.state = .none;
                }
                slider.state_change(slider);
            }
        },
        else => {},
    }
}

pub fn mouseRelease(x: f32, y: f32) void {
    for (elements.items) |elem| {
        elemRelease(elem, x, y);
    }

    for (tooltip_elements.items) |elem| {
        elemRelease(elem, x, y);
    }
}

pub fn elemScroll(elem: element.UiElement, x: f32, y: f32, x_offset: f32, y_offset: f32) bool {
    switch (elem) {
        .scrollable_container => |scrollable_container| {
            if (!scrollable_container.visible)
                return false;

            const container = scrollable_container._container;
            if (utils.isInBounds(x, y, container.x, container.y, scrollable_container.width(), scrollable_container.height())) {
                const scroll_bar = scrollable_container._scroll_bar;
                scrollable_container._scroll_bar.setValue(
                    @min(
                        scroll_bar.max_value,
                        @max(
                            scroll_bar.min_value,
                            scroll_bar._current_value + (scroll_bar.max_value - scroll_bar.min_value) * -y_offset / 64.0,
                        ),
                    ),
                );
                return true;
            }
        },
        .container => |container| {
            if (!container.visible)
                return false;

            var iter = std.mem.reverseIterator(container._elements.items);
            while (iter.next()) |container_elem| {
                if (elemScroll(container_elem, x - container.x, y - container.y, x_offset, y_offset))
                    return true;
            }
        },
        .slider => |slider| {
            if (utils.isInBounds(x, y, slider.x, slider.y, slider.width(), slider.height())) {
                slider.setValue(
                    @min(
                        slider.max_value,
                        @max(
                            slider.min_value,
                            slider._current_value + (slider.max_value - slider.min_value) * -y_offset / 64.0,
                        ),
                    ),
                );
                return true;
            }
        },
        else => {},
    }

    return false;
}

pub fn mouseScroll(x: f32, y: f32, x_offset: f32, y_offset: f32) bool {
    var elem_iter = std.mem.reverseIterator(elements.items);
    while (elem_iter.next()) |elem| {
        if (elemScroll(elem, x, y, x_offset, y_offset))
            return true;
    }

    var tooltip_elem_iter = std.mem.reverseIterator(tooltip_elements.items);
    while (tooltip_elem_iter.next()) |elem| {
        if (elemScroll(elem, x, y, x_offset, y_offset))
            return true;
    }

    return false;
}

pub fn update(time: i64, dt: i64, allocator: std.mem.Allocator) !void {
    while (!ui_lock.tryLock()) {}
    defer ui_lock.unlock();

    const ms_time = @divFloor(time, std.time.us_per_ms);
    const ms_dt = @as(f32, @floatFromInt(dt)) / std.time.us_per_ms;

    switch (current_screen) {
        inline else => |screen| if (screen.inited) try screen.update(ms_time, ms_dt),
    }

    if (temp_elements.items.len <= 0)
        return;

    while (!temp_elem_lock.tryLock()) {}
    defer temp_elem_lock.unlock();

    // We iterate in reverse in order to preserve integrity, because we remove elements in place
    var iter = std.mem.reverseIterator(temp_elements.items);
    var i: usize = temp_elements.items.len - 1;
    while (iter.nextPtr()) |elem| {
        defer i -%= 1;

        switch (elem.*) {
            .status => |*status_text| {
                const elapsed = ms_time - status_text.start_time;
                if (elapsed > status_text.lifetime) {
                    status_text.destroy(allocator);
                    _ = temp_elements.swapRemove(i);
                    continue;
                }

                status_text.visible = false;
                if (map.findEntityConst(status_text.obj_id)) |en| {
                    status_text.visible = true;

                    const frac = @as(f32, @floatFromInt(elapsed)) / @as(f32, @floatFromInt(status_text.lifetime));
                    status_text.text_data.size = status_text.initial_size * @min(1.0, @max(0.7, 1.0 - frac * 0.3 + 0.075));
                    status_text.text_data.alpha = 1.0 - frac + 0.33;
                    status_text.text_data.recalculateAttributes(allocator);

                    switch (en) {
                        .particle, .particle_effect, .projectile => {},
                        inline else => |obj| {
                            if (obj.dead) {
                                status_text.destroy(allocator);
                                _ = temp_elements.swapRemove(i);
                                continue;
                            }
                            status_text._screen_x = obj.screen_x - status_text.text_data._width / 2;
                            status_text._screen_y = obj.screen_y - status_text.text_data._height - frac * 40;
                        },
                    }
                }
            },
            .balloon => |*speech_balloon| {
                const elapsed = ms_time - speech_balloon.start_time;
                const lifetime = 5000;
                if (elapsed > lifetime) {
                    speech_balloon.destroy(allocator);
                    _ = temp_elements.swapRemove(i);
                    continue;
                }

                speech_balloon.visible = false;
                if (map.findEntityConst(speech_balloon.target_id)) |en| {
                    speech_balloon.visible = true;

                    const frac = @as(f32, @floatFromInt(elapsed)) / @as(f32, lifetime);
                    const alpha = 1.0 - frac * 2.0 + 0.9;
                    speech_balloon.image_data.normal.alpha = alpha; // assume no 9 slice
                    speech_balloon.text_data.alpha = alpha;

                    switch (en) {
                        .particle, .particle_effect, .projectile => {},
                        inline else => |obj| {
                            if (obj.dead) {
                                speech_balloon.destroy(allocator);
                                _ = temp_elements.swapRemove(i);
                                continue;
                            }
                            speech_balloon._screen_x = obj.screen_x - speech_balloon.width() / 2;
                            speech_balloon._screen_y = obj.screen_y - speech_balloon.height();
                        },
                    }
                }
            },
        }
    }
}

fn sliderPressed(slider: *element.Slider, x: f32, y: f32, knob_h: f32, knob_w: f32) void {
    const prev_value = slider._current_value;

    if (slider.vertical) {
        slider._knob_y = @min(slider.h - knob_h, @max(0, y - knob_h - slider.y));
        slider._current_value = slider._knob_y / (slider.h - knob_h) * (slider.max_value - slider.min_value) + slider.min_value;
    } else {
        slider._knob_x = @min(slider.w - knob_w, @max(0, x - knob_w - slider.x));
        slider._current_value = slider._knob_x / (slider.w - knob_w) * (slider.max_value - slider.min_value) + slider.min_value;
    }

    if (slider._current_value != prev_value) {
        if (slider.value_text_data) |*text_data| {
            text_data.text = std.fmt.bufPrint(text_data._backing_buffer, "{d:.2}", .{slider._current_value}) catch "-1.00";
            text_data.recalculateAttributes(slider._allocator);
        }

        if (slider.continous_event_fire)
            slider.state_change(slider);
    }

    slider.state = .pressed;
}
