const std = @import("std");
const shared = @import("shared");
const utils = shared.utils;
const network_data = shared.network_data;
const element = @import("elements/element.zig");
const input = @import("../input.zig");
const main = @import("../main.zig");
const map = @import("../game/map.zig");
const assets = @import("../assets.zig");
const tooltip = @import("tooltips/tooltip.zig");
const dialog = @import("dialogs/dialog.zig");
const glfw = @import("zglfw");
const network = @import("../network.zig");

const MenuBackground = @import("elements/MenuBackground.zig");
const AccountLoginScreen = @import("screens/AccountLoginScreen.zig");
const AccountRegisterScreen = @import("screens/AccountRegisterScreen.zig");
const CharCreateScreen = @import("screens/CharCreateScreen.zig");
const CharSelectScreen = @import("screens/CharSelectScreen.zig");
const MapEditorScreen = @import("screens/MapEditorScreen.zig");
const GameScreen = @import("screens/GameScreen.zig");

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
    empty: void,
    main_menu: *AccountLoginScreen,
    register: *AccountRegisterScreen,
    char_select: *CharSelectScreen,
    char_create: *CharCreateScreen,
    game: *GameScreen,
    editor: *MapEditorScreen,
};

pub var ui_lock: std.Thread.Mutex = .{};
pub var elements: std.ArrayListUnmanaged(element.UiElement) = .empty;
pub var elements_to_add: std.ArrayListUnmanaged(element.UiElement) = .empty;
pub var screen: Screen = undefined;
pub var menu_background: *MenuBackground = undefined;
pub var hover_lock: std.Thread.Mutex = .{};
pub var hover_target: ?element.UiElement = null;
pub var last_map_data: ?[]u8 = null;
pub var is_testing: bool = false;

pub fn init() !void {
    menu_background = try element.create(MenuBackground, .{
        .base = .{ .x = 0, .y = 0 },
        .w = main.camera.width,
        .h = main.camera.height,
    });

    screen = Screen{ .empty = {} }; // TODO: re-add RLS when fixed

    try tooltip.init();
    try dialog.init();
}

pub fn deinit() void {
    ui_lock.lock();
    defer ui_lock.unlock();

    tooltip.deinit();
    dialog.deinit();

    switch (screen) {
        .empty => {},
        inline else => |inner_screen| inner_screen.deinit(),
    }

    element.destroy(menu_background);

    elements_to_add.deinit(main.allocator);
    elements.deinit(main.allocator);

    if (last_map_data) |data| main.allocator.free(data);
}

pub fn switchScreen(comptime screen_type: ScreenType) void {
    const T = std.meta.TagPayloadByName(Screen, @tagName(screen_type));
    if (T == void) return;

    if (screen == screen_type) return;

    std.debug.assert(!ui_lock.tryLock());

    {
        main.camera.lock.lock();
        defer main.camera.lock.unlock();
        main.camera.scale = 1.0;
    }
    menu_background.base.visible = screen_type != .game and screen_type != .editor;
    input.selected_key_mapper = null;

    switch (screen) {
        .empty => {},
        inline else => |inner_screen| inner_screen.deinit(),
    }

    var screen_inner = main.allocator.create(@typeInfo(T).pointer.child) catch @panic("OOM");
    screen_inner.* = .{};
    screen_inner.init() catch |e| std.debug.panic("Screen init failed: {}", .{e});
    screen = @unionInit(Screen, @tagName(screen_type), screen_inner);
}

pub fn resize(w: f32, h: f32) void {
    ui_lock.lock();
    defer ui_lock.unlock();

    menu_background.w = w;
    menu_background.h = h;

    switch (screen) {
        .empty => {},
        inline else => |inner_screen| if (std.meta.hasFn(@typeInfo(@TypeOf(inner_screen)).pointer.child, "resize")) inner_screen.resize(w, h),
    }

    dialog.resize(w, h);
}

pub fn mouseMove(x: f32, y: f32) bool {
    ui_lock.lock();
    defer ui_lock.unlock();

    tooltip.switchTooltip(.none, {});
    {
        hover_lock.lock();
        defer hover_lock.unlock();
        if (hover_target) |target| {
            switch (target) {
                inline .input_field, .button, .char_box, .toggle, .key_mapper, .dropdown_container => |elem| elem.state = .none,
                .dropdown => |dropdown| dropdown.button_state = .none,
                else => {},
            }

            hover_target = null;
        }
    }

    var elem_iter = std.mem.reverseIterator(elements.items);
    while (elem_iter.next()) |elem| switch (elem) {
        inline else => |inner_elem| 
            if (std.meta.hasFn(@typeInfo(@TypeOf(inner_elem)).pointer.child, "mouseMove") and inner_elem.mouseMove(x, y, 0, 0)) 
                return true,
    };

    return false;
}

pub fn mousePress(x: f32, y: f32, mods: glfw.Mods) bool {
    ui_lock.lock();
    defer ui_lock.unlock();

    var elem_iter = std.mem.reverseIterator(elements.items);
    while (elem_iter.next()) |elem| switch (elem) {
        inline else => |inner_elem|
            if (std.meta.hasFn(@typeInfo(@TypeOf(inner_elem)).pointer.child, "mousePress") and inner_elem.mousePress(x, y, 0, 0, mods))
                return true,
    };

    return false;
}

pub fn mouseRelease(x: f32, y: f32) bool {
    ui_lock.lock();
    defer ui_lock.unlock();

    var elem_iter = std.mem.reverseIterator(elements.items);
    while (elem_iter.next()) |elem| switch (elem) {
        inline else => |inner_elem|
            if (std.meta.hasFn(@typeInfo(@TypeOf(inner_elem)).pointer.child, "mouseRelease") and inner_elem.mouseRelease(x, y, 0, 0))
                return true,
    };

    return false;
}

pub fn mouseScroll(x: f32, y: f32, x_scroll: f32, y_scroll: f32) bool {
    ui_lock.lock();
    defer ui_lock.unlock();

    var elem_iter = std.mem.reverseIterator(elements.items);
    while (elem_iter.next()) |elem| switch (elem) {
        inline else => |inner_elem| 
            if (std.meta.hasFn(@typeInfo(@TypeOf(inner_elem)).pointer.child, "mouseScroll") and inner_elem.mouseScroll(x, y, 0, 0, x_scroll, y_scroll))
                return true,
    };

    return false;
}

fn lessThan(_: void, lhs: element.UiElement, rhs: element.UiElement) bool {
    return switch (lhs) {
        inline else => |elem| @intFromEnum(elem.base.layer),
    } < switch (rhs) {
        inline else => |elem| @intFromEnum(elem.base.layer),
    };
}

pub fn update(time: i64, dt: f32) !void {
    ui_lock.lock();
    defer ui_lock.unlock();

    elements.appendSlice(main.allocator, elements_to_add.items) catch |e| {
        @branchHint(.cold);
        std.log.err("Adding new elements failed: {}, returning", .{e});
        return;
    };
    elements_to_add.clearRetainingCapacity();

    std.sort.block(element.UiElement, elements.items, {}, lessThan);

    switch (screen) {
        .empty => {},
        inline else => |inner_screen| if (std.meta.hasFn(@typeInfo(@TypeOf(inner_screen)).pointer.child, "update")) try inner_screen.update(time, dt),
    }
}
