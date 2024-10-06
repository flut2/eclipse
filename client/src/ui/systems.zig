const std = @import("std");
const shared = @import("shared");
const utils = shared.utils;
const network_data = shared.network_data;
const element = @import("element.zig");
const input = @import("../input.zig");
const main = @import("../main.zig");
const map = @import("../game/map.zig");
const assets = @import("../assets.zig");
const tooltip = @import("tooltips/tooltip.zig");
const dialog = @import("dialogs/dialog.zig");
const glfw = @import("zglfw");
const network = @import("../network.zig");

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
pub var elements: std.ArrayListUnmanaged(element.UiElement) = .empty;
pub var elements_to_add: std.ArrayListUnmanaged(element.UiElement) = .empty;
pub var screen: Screen = undefined;
pub var menu_background: *element.MenuBackground = undefined;
pub var hover_lock: std.Thread.Mutex = .{};
pub var hover_target: ?element.UiElement = null;
pub var last_map_data: ?[]u8 = null;
pub var is_testing: bool = false;

var last_element_update: i64 = 0;
pub var allocator: std.mem.Allocator = undefined;

pub fn init(ally: std.mem.Allocator) !void {
    allocator = ally;

    menu_background = try element.create(ally, element.MenuBackground{
        .x = 0,
        .y = 0,
        .w = main.camera.width,
        .h = main.camera.height,
    });

    screen = Screen{ .empty = EmptyScreen.init(ally) catch @panic("Initializing EmptyScreen failed") }; // TODO: re-add RLS when fixed

    try tooltip.init(ally);
    try dialog.init(ally);
}

pub fn deinit() void {
    ui_lock.lock();
    defer ui_lock.unlock();

    tooltip.deinit(allocator);
    dialog.deinit(allocator);

    switch (screen) {
        inline else => |inner_screen| inner_screen.deinit(),
    }

    element.destroy(menu_background);

    elements_to_add.deinit(allocator);
    elements.deinit(allocator);

    if (last_map_data) |data| allocator.free(data);
}

pub fn switchScreen(comptime screen_type: ScreenType) void {
    if (screen == screen_type)
        return;

    std.debug.assert(!ui_lock.tryLock());

    {
        main.camera.lock.lock();
        defer main.camera.lock.unlock();
        main.camera.scale = 1.0;
    }
    menu_background.visible = screen_type != .game and screen_type != .editor;
    input.selected_key_mapper = null;

    switch (screen) {
        inline else => |inner_screen| inner_screen.deinit(),
    }

    screen = @unionInit(
        Screen,
        @tagName(screen_type),
        @typeInfo(std.meta.TagPayloadByName(Screen, @tagName(screen_type))).pointer.child.init(allocator) catch |e| {
            std.log.err("Initializing screen for {} failed: {}", .{ screen_type, e });
            return;
        },
    );
}

pub fn resize(w: f32, h: f32) void {
    ui_lock.lock();
    defer ui_lock.unlock();

    menu_background.w = w;
    menu_background.h = h;

    switch (screen) {
        inline else => |inner_screen| inner_screen.resize(w, h),
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
            // this is intentionally not else-d. don't add
            switch (target) {
                .image => {},
                .item => {},
                .bar => {},
                .input_field => |input_field| input_field.state = .none,
                .button => |button| button.state = .none,
                .text => {},
                .char_box => |box| box.state = .none,
                .container => {},
                .scrollable_container => {},
                .menu_bg => {},
                .toggle => |toggle| toggle.state = .none,
                .key_mapper => |key_mapper| key_mapper.state = .none,
                .slider => {},
                .dropdown => |dropdown| dropdown.button_state = .none,
                .dropdown_container => |dc| dc.state = .none,
            }

            hover_target = null;
        }
    }

    var elem_iter_1 = std.mem.reverseIterator(elements.items);
    while (elem_iter_1.next()) |elem| {
        switch (elem) {
            else => {},
            .slider => |inner_elem| {
                if (std.meta.hasFn(@typeInfo(@TypeOf(inner_elem)).pointer.child, "mouseMove") and inner_elem.mouseMove(x, y, 0, 0))
                    return true;
            },
        }
    }

    var elem_iter_2 = std.mem.reverseIterator(elements.items);
    while (elem_iter_2.next()) |elem| {
        switch (elem) {
            .slider => {},
            inline else => |inner_elem| {
                if (std.meta.hasFn(@typeInfo(@TypeOf(inner_elem)).pointer.child, "mouseMove") and inner_elem.mouseMove(x, y, 0, 0))
                    return true;
            },
        }
    }

    return false;
}

pub fn mousePress(x: f32, y: f32, mods: glfw.Mods, button: glfw.MouseButton) bool {
    if (input.selected_input_field) |input_field| {
        input_field.last_input = -1;
        input.selected_input_field = null;
    }

    if (input.selected_key_mapper) |key_mapper| {
        key_mapper.key = .unknown;
        key_mapper.mouse = button;
        key_mapper.listening = false;
        key_mapper.set_key_callback(key_mapper);
        input.selected_key_mapper = null;
    }

    ui_lock.lock();
    defer ui_lock.unlock();

    var elem_iter = std.mem.reverseIterator(elements.items);
    while (elem_iter.next()) |elem| {
        switch (elem) {
            inline else => |inner_elem| {
                if (std.meta.hasFn(@typeInfo(@TypeOf(inner_elem)).pointer.child, "mousePress") and inner_elem.mousePress(x, y, 0, 0, mods))
                    return true;
            },
        }
    }

    return false;
}

pub fn mouseRelease(x: f32, y: f32) bool {
    ui_lock.lock();
    defer ui_lock.unlock();

    var elem_iter = std.mem.reverseIterator(elements.items);
    while (elem_iter.next()) |elem| {
        switch (elem) {
            inline else => |inner_elem| {
                if (std.meta.hasFn(@typeInfo(@TypeOf(inner_elem)).pointer.child, "mouseRelease") and inner_elem.mouseRelease(x, y, 0, 0))
                    return true;
            },
        }
    }

    return false;
}

pub fn mouseScroll(x: f32, y: f32, x_scroll: f32, y_scroll: f32) bool {
    ui_lock.lock();
    defer ui_lock.unlock();

    var elem_iter = std.mem.reverseIterator(elements.items);
    while (elem_iter.next()) |elem| {
        switch (elem) {
            inline else => |inner_elem| {
                if (std.meta.hasFn(@typeInfo(@TypeOf(inner_elem)).pointer.child, "mouseScroll") and inner_elem.mouseScroll(x, y, 0, 0, x_scroll, y_scroll))
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

pub fn update(time: i64, dt: f32) !void {
    ui_lock.lock();
    defer ui_lock.unlock();

    elements.appendSlice(allocator, elements_to_add.items) catch |e| {
        @branchHint(.cold);
        std.log.err("Adding new elements failed: {}, returning", .{e});
        return;
    };
    elements_to_add.clearRetainingCapacity();

    std.sort.block(element.UiElement, elements.items, {}, lessThan);

    switch (screen) {
        inline else => |inner_screen| try inner_screen.update(time, dt),
    }
}
