const std = @import("std");
const element = @import("element.zig");
const input = @import("../input.zig");
const camera = @import("../camera.zig");
const utils = @import("../utils.zig");
const main = @import("../main.zig");
const map = @import("../game/map.zig");
const assets = @import("../assets.zig");
const tooltip = @import("tooltips/tooltip.zig");
const dialog = @import("dialogs/dialog.zig");
const zglfw = @import("zglfw");

const AccountLoginScreen = @import("screens/account_login_screen.zig").AccountLoginScreen;
const AccountRegisterScreen = @import("screens/account_register_screen.zig").AccountRegisterScreen;
const CharCreateScreen = @import("screens/char_create_screen.zig").CharCreateScreen;
const CharSelectScreen = @import("screens/char_select_screen.zig").CharSelectScreen;
const MapEditorScreen = @import("screens/map_editor_screen.zig").MapEditorScreen;
const GameScreen = @import("screens/game_screen.zig").GameScreen;
const EmptyScreen = @import("screens/empty_screen.zig").EmptyScreen;

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
pub var elements_to_add: std.ArrayList(element.UiElement) = undefined;
pub var temp_elements: std.ArrayList(element.Temporary) = undefined;
pub var temp_elements_to_add: std.ArrayList(element.Temporary) = undefined;
pub var screen: Screen = undefined;
pub var menu_background: *element.MenuBackground = undefined;

var last_element_update: i64 = 0;
var _allocator: std.mem.Allocator = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    _allocator = allocator;

    elements = try std.ArrayList(element.UiElement).initCapacity(allocator, 32);
    elements_to_add = try std.ArrayList(element.UiElement).initCapacity(allocator, 16);
    temp_elements = try std.ArrayList(element.Temporary).initCapacity(allocator, 32);
    temp_elements_to_add = try std.ArrayList(element.Temporary).initCapacity(allocator, 16);

    menu_background = try element.create(allocator, element.MenuBackground{
        .x = 0,
        .y = 0,
        .w = camera.screen_width,
        .h = camera.screen_height,
    });

    screen = .{ .empty = EmptyScreen.init(allocator) catch std.debug.panic("Initializing EmptyScreen failed", .{}) };

    try tooltip.init(allocator);
    try dialog.init(allocator);
}

pub fn deinit(allocator: std.mem.Allocator) void {
    ui_lock.lock();
    defer ui_lock.unlock();

    tooltip.deinit(allocator);
    dialog.deinit(allocator);

    element.destroy(menu_background);

    switch (screen) {
        inline else => |inner_screen| inner_screen.deinit(),
    }

    temp_elem_lock.lock();
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

    elements_to_add.deinit();
    temp_elements_to_add.deinit();
    elements.deinit();
    temp_elements.deinit();
}

pub fn switchScreen(comptime screen_type: ScreenType) void {
    ui_lock.lock();
    defer ui_lock.unlock();

    menu_background.visible = screen_type != .game and screen_type != .editor;
    input.selected_key_mapper = null;

    switch (screen) {
        inline else => |inner_screen| if (inner_screen.inited) inner_screen.deinit(),
    }

    screen = @unionInit(
        Screen,
        @tagName(screen_type),
        @typeInfo(std.meta.TagPayloadByName(Screen, @tagName(screen_type))).Pointer.child.init(_allocator) catch |e| {
            std.log.err("Initializing screen for {} failed: {}", .{ screen_type, e });
            return;
        },
    );
}

pub fn resize(w: f32, h: f32) void {
    ui_lock.lock();
    defer ui_lock.unlock();

    menu_background.w = camera.screen_width;
    menu_background.h = camera.screen_height;

    switch (screen) {
        inline else => |inner_screen| inner_screen.resize(w, h),
    }

    dialog.resize(w, h);
}

pub fn removeAttachedUi(obj_id: i32, allocator: std.mem.Allocator) void {
    temp_elem_lock.lock();
    defer temp_elem_lock.unlock();

    if (temp_elements.items.len <= 0)
        return;

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

pub fn mouseMove(x: f32, y: f32) bool {
    tooltip.switchTooltip(.none, {});

    var elem_iter_1 = std.mem.reverseIterator(elements.items);
    while (elem_iter_1.next()) |elem| {
        switch (elem) {
            else => {},
            inline .slider => |inner_elem| {
                if (std.meta.hasFn(@typeInfo(@TypeOf(inner_elem)).Pointer.child, "mouseMove") and inner_elem.mouseMove(x, y, 0, 0))
                    return true;
            },
        }
    }

    var elem_iter_2 = std.mem.reverseIterator(elements.items);
    while (elem_iter_2.next()) |elem| {
        switch (elem) {
            .slider => {},
            inline else => |inner_elem| {
                if (std.meta.hasFn(@typeInfo(@TypeOf(inner_elem)).Pointer.child, "mouseMove") and inner_elem.mouseMove(x, y, 0, 0))
                    return true;
            },
        }
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
        switch (elem) {
            inline else => |inner_elem| {
                if (std.meta.hasFn(@typeInfo(@TypeOf(inner_elem)).Pointer.child, "mousePress") and inner_elem.mousePress(x, y, 0, 0, mods))
                    return true;
            },
        }
    }

    return false;
}

pub fn mouseRelease(x: f32, y: f32) bool {
    var elem_iter = std.mem.reverseIterator(elements.items);
    while (elem_iter.next()) |elem| {
        switch (elem) {
            inline else => |inner_elem| {
                if (std.meta.hasFn(@typeInfo(@TypeOf(inner_elem)).Pointer.child, "mouseRelease") and inner_elem.mouseRelease(x, y, 0, 0))
                    return true;
            },
        }
    }

    return false;
}

pub fn mouseScroll(x: f32, y: f32, x_scroll: f32, y_scroll: f32) bool {
    var elem_iter = std.mem.reverseIterator(elements.items);
    while (elem_iter.next()) |elem| {
        switch (elem) {
            inline else => |inner_elem| {
                if (std.meta.hasFn(@typeInfo(@TypeOf(inner_elem)).Pointer.child, "mouseScroll") and inner_elem.mouseScroll(x, y, 0, 0, x_scroll, y_scroll))
                    return true;
            },
        }
    }

    return false;
}

fn lessThan(_: void, lhs: element.UiElement, rhs: element.UiElement) bool {
    return switch (lhs) {
        inline else => |elem| @intFromEnum(elem.layer),
    } < switch (rhs) {
        inline else => |elem| @intFromEnum(elem.layer),
    };
}

inline fn updateElements() !void {
    ui_lock.lock();
    defer ui_lock.unlock();

    elements.appendSlice(elements_to_add.items) catch |e| {
        std.log.err("Adding new elements failed: {}, returning", .{e});
        return;
    };
    elements_to_add.clearRetainingCapacity();

    const time = std.time.microTimestamp() - main.start_time;
    const dt: f32 = @floatFromInt(if (last_element_update > 0) time - last_element_update else 0);
    last_element_update = time;

    std.sort.block(element.UiElement, elements.items, {}, lessThan);

    switch (screen) {
        inline else => |inner_screen| if (inner_screen.inited) try inner_screen.update(time, dt),
    }
}

inline fn updateTempElements(allocator: std.mem.Allocator) !void {
    if (!temp_elem_lock.tryLock())
        return;
    defer temp_elem_lock.unlock();

    temp_elements.appendSlice(temp_elements_to_add.items) catch |e| {
        std.log.err("Adding new temporary elements failed: {}, returning", .{e});
        return;
    };
    temp_elements_to_add.clearRetainingCapacity();

    if (temp_elements.items.len <= 0)
        return;

    if (!map.object_lock.tryLockShared())
        return;
    defer map.object_lock.unlockShared();

    const time = std.time.microTimestamp() - main.start_time;

    // We iterate in reverse in order to preserve integrity, because we remove elements in place
    var iter = std.mem.reverseIterator(temp_elements.items);
    var i: usize = temp_elements.items.len - 1;
    while (iter.nextPtr()) |elem| {
        defer i -%= 1;

        switch (elem.*) {
            .status => |*status_text| {
                const elapsed = time - status_text.start_time;
                if (elapsed > status_text.lifetime * std.time.us_per_ms) {
                    status_text.destroy(allocator);
                    _ = temp_elements.swapRemove(i);
                    continue;
                }

                status_text.visible = false;
                if (map.findEntityConst(status_text.obj_id)) |en| {
                    status_text.visible = true;

                    const frac = @as(f32, @floatFromInt(elapsed)) / @as(f32, @floatFromInt(status_text.lifetime * std.time.us_per_ms));
                    status_text.text_data.size = status_text.initial_size * @min(1.0, @max(0.7, 1.0 - frac * 0.3 + 0.075));
                    status_text.text_data.alpha = 1.0 - frac + 0.33;

                    {
                        status_text.text_data._lock.lock();
                        defer status_text.text_data._lock.unlock();

                        status_text.text_data.recalculateAttributes(allocator);
                    }

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
                const elapsed = time - speech_balloon.start_time;
                const lifetime = 5 * std.time.us_per_s;
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

pub fn update(allocator: std.mem.Allocator) !void {
    try updateElements();
    try updateTempElements(allocator);
}
