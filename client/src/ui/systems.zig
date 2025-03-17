const std = @import("std");

const build_options = @import("options");
const glfw = @import("glfw");
const shared = @import("shared");
const utils = shared.utils;
const network_data = shared.network_data;
const game_data = shared.game_data;
const map_data = shared.map_data;
const f32i = utils.f32i;

const assets = @import("../assets.zig");
const Camera = @import("../Camera.zig");
const Container = @import("../game/Container.zig");
const Enemy = @import("../game/Enemy.zig");
const Entity = @import("../game/Entity.zig");
const map = @import("../game/map.zig");
const Player = @import("../game/Player.zig");
const Portal = @import("../game/Portal.zig");
const Square = @import("../game/Square.zig");
const input = @import("../input.zig");
const main = @import("../main.zig");
const Renderer = @import("../render/Renderer.zig");
const dialog = @import("dialogs/dialog.zig");
const element = @import("elements/element.zig");
const Image = @import("elements/Image.zig");
const Text = @import("elements/Text.zig");
const menu = @import("menus/menu.zig");
const AccountLoginScreen = @import("screens/AccountLoginScreen.zig");
const AccountRegisterScreen = @import("screens/AccountRegisterScreen.zig");
const CharCreateScreen = @import("screens/CharCreateScreen.zig");
const CharSelectScreen = @import("screens/CharSelectScreen.zig");
const GameScreen = @import("screens/GameScreen.zig");
const MapEditorScreen = @import("screens/MapEditorScreen.zig");
const tooltip = @import("tooltips/tooltip.zig");

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

const TimedPoint = struct { x: f32, y: f32, time: i64 };
const points = [_]TimedPoint{
    .{ .x = 9.0, .y = 18.0, .time = 3 * std.time.us_per_s },
    .{ .x = 22.0, .y = 9.0, .time = 3 * std.time.us_per_s },
    .{ .x = 30.0, .y = 18.0, .time = 3 * std.time.us_per_s },
    .{ .x = 22.0, .y = 28.0, .time = 3 * std.time.us_per_s },
};

pub var elements: std.ArrayListUnmanaged(element.UiElement) = .empty;
pub var elements_to_add: std.ArrayListUnmanaged(element.UiElement) = .empty;
pub var screen: Screen = undefined;
pub var darken_bg: *Image = undefined;
pub var version_text: *Text = undefined;
pub var hover_target: ?element.UiElement = null;
pub var last_map_data: ?[]u8 = null;
pub var is_testing: bool = false;
pub var next_map_ids: struct {
    entity: u32 = 0,
    enemy: u32 = 0,
    portal: u32 = 0,
    container: u32 = 0,
} = .{};
var current_point_idx: u32 = 0;
var last_point_switch: i64 = 0;

pub fn init() !void {
    screen = .{ .empty = {} };

    try tooltip.init();
    try dialog.init();
    try menu.init();

    const cam_w = main.camera.width;
    const cam_h = main.camera.height;
    darken_bg = try element.create(Image, .{
        .base = .{ .x = 0, .y = 0, .visible = false },
        .image_data = .{ .nine_slice = .fromAtlasData(assets.getUiData("dark_background", 0), cam_w, cam_h, 0, 0, 8, 8, 1.0) },
    });

    version_text = try element.create(Text, .{
        .base = .{ .x = 10, .y = main.camera.height - 25, .visible = false },
        .text_data = .{
            .text = "",
            .size = 12,
            .max_chars = 32,
            .text_type = .medium_italic,
            .color = 0xB0B0B0,
        },
    });
    version_text.text_data.setText(
        try std.fmt.bufPrint(version_text.text_data.backing_buffer, "Eclipse Alpha - v{s}", .{build_options.version}),
    );
}

pub fn deinit() void {
    tooltip.deinit();
    dialog.deinit();
    menu.deinit();

    element.destroy(darken_bg);
    element.destroy(version_text);

    switch (screen) {
        .game, .editor => {},
        else => map.dispose(),
    }

    switch (screen) {
        .empty => {},
        inline else => |inner_screen| inner_screen.deinit(),
    }

    elements_to_add.deinit(main.allocator);
    elements.deinit(main.allocator);

    if (last_map_data) |data| main.allocator.free(data);
}

pub fn switchScreen(comptime screen_type: ScreenType) void {
    const T = std.meta.TagPayloadByName(Screen, @tagName(screen_type));
    if (T == void or screen == screen_type) return;

    main.camera.scale = 1.0;
    input.selected_key_mapper = null;

    switch (screen) {
        .empty => {},
        inline else => |inner_screen| inner_screen.deinit(),
    }

    switch (screen) {
        .game, .editor => {},
        else => if (screen_type == .game or screen_type == .editor) {
            main.needs_map_bg = false;
            map.dispose();
        },
    }

    switch (screen_type) {
        .game, .editor => {
            darken_bg.base.visible = false;
            version_text.base.visible = false;
        },
        else => {
            darken_bg.base.visible = true;
            version_text.base.visible = true;
            loadMap() catch |e| {
                std.log.err("Map loading failed: {}", .{e});
            };
        },
    }

    var screen_inner = main.allocator.create(@typeInfo(T).pointer.child) catch main.oomPanic();
    screen_inner.* = .{};
    screen_inner.init() catch |e| std.debug.panic("Screen init failed: {}", .{e});
    screen = @unionInit(Screen, @tagName(screen_type), screen_inner);
}

fn loadMap() !void {
    // Means that the map is already loaded, map editor unsets this
    if (main.needs_map_bg) return;

    const file = try std.fs.cwd().openFile("./assets/background.map", .{});
    defer file.close();

    var arena: std.heap.ArenaAllocator = .init(main.allocator);
    defer arena.deinit();
    const parsed_map = try map_data.parseMap(file.reader(), &arena);

    map.dispose();
    map.setMapInfo(.{ .width = parsed_map.w, .height = parsed_map.h, .bg_color = 0, .bg_intensity = 0.15 });

    map.info.player_map_id = std.math.maxInt(u32) - 1;
    Player.addToMap(.{
        .x = f32i(parsed_map.w / 2),
        .y = f32i(parsed_map.h / 2),
        .map_id = map.info.player_map_id,
        .data_id = 0,
    });

    for (parsed_map.tiles, 0..) |tile, i| {
        const ux: u16 = @intCast(i % parsed_map.w);
        const uy: u16 = @intCast(i / parsed_map.w);
        if (tile.ground_name.len > 0) setTile(ux, uy, game_data.ground.from_name.get(tile.ground_name).?.id);
        if (tile.entity_name.len > 0) setObject(Entity, ux, uy, game_data.entity.from_name.get(tile.entity_name).?.id);
        if (tile.enemy_name.len > 0) setObject(Enemy, ux, uy, game_data.enemy.from_name.get(tile.enemy_name).?.id);
        if (tile.portal_name.len > 0) setObject(Portal, ux, uy, game_data.portal.from_name.get(tile.portal_name).?.id);
        if (tile.container_name.len > 0) setObject(Container, ux, uy, game_data.container.from_name.get(tile.container_name).?.id);
    }

    main.needs_map_bg = true;
    current_point_idx = 0;
    last_point_switch = main.current_time;
}

fn setTile(x: u16, y: u16, data_id: u16) void {
    if (game_data.ground.from_id.get(data_id) == null) {
        std.log.err("Data not found for tile with data id {}, setting at x={}, y={} cancelled", .{ data_id, x, y });
        return;
    }

    Square.addToMap(.{
        .x = f32i(x) + 0.5,
        .y = f32i(y) + 0.5,
        .data_id = data_id,
    });
}

fn setObject(comptime ObjType: type, x: u16, y: u16, data_id: u16) void {
    const data = switch (ObjType) {
        Entity => game_data.entity,
        Enemy => game_data.enemy,
        Portal => game_data.portal,
        Container => game_data.container,
        else => @compileError("Invalid type"),
    }.from_id.get(data_id);
    if (data == null) {
        std.log.err("Data not found for object with data id {}, setting at x={}, y={} cancelled", .{ data_id, x, y });
        return;
    }

    const next_map_id = nextMapIdForType(ObjType);
    defer next_map_id.* += 1;

    ObjType.addToMap(.{
        .x = f32i(x) + 0.5,
        .y = f32i(y) + 0.5,
        .map_id = next_map_id.*,
        .data_id = data_id,
    });
}

fn nextMapIdForType(comptime T: type) *u32 {
    return switch (T) {
        Entity => &next_map_ids.entity,
        Enemy => &next_map_ids.enemy,
        Portal => &next_map_ids.portal,
        Container => &next_map_ids.container,
        else => @compileError("Invalid type"),
    };
}

pub fn resize(w: f32, h: f32) void {
    switch (screen) {
        .empty => {},
        inline else => |inner_screen| if (std.meta.hasFn(@typeInfo(@TypeOf(inner_screen)).pointer.child, "resize")) inner_screen.resize(w, h),
    }

    dialog.resize(w, h);
    version_text.base.y = h - 25;
    darken_bg.image_data.scaleWidth(w);
    darken_bg.image_data.scaleHeight(h);
}

pub fn mouseMove(x: f32, y: f32) bool {
    tooltip.switchTooltip(.none, {});
    if (hover_target) |target| {
        switch (target) {
            inline .input_field, .button, .toggle, .key_mapper, .dropdown_container => |elem| elem.state = .none,
            .dropdown => |dropdown| dropdown.button_state = .none,
            else => {},
        }

        hover_target = null;
    }

    var elem_iter = std.mem.reverseIterator(elements.items);
    while (elem_iter.next()) |elem| switch (elem) {
        inline else => |inner_elem| if (std.meta.hasFn(@typeInfo(@TypeOf(inner_elem)).pointer.child, "mouseMove") and inner_elem.mouseMove(x, y, 0, 0))
            return true,
    };

    return false;
}

pub fn mousePress(x: f32, y: f32, button: glfw.MouseButton, mods: glfw.Mods) bool {
    var elem_iter = std.mem.reverseIterator(elements.items);
    while (elem_iter.next()) |elem| switch (elem) {
        inline else => |inner_elem| if (std.meta.hasFn(@typeInfo(@TypeOf(inner_elem)).pointer.child, "mousePress") and inner_elem.mousePress(x, y, 0, 0, mods))
            return true,
    };

    checkMenu: {
        defer menu.checkMenuValidity(x, y);

        if (button != .right) break :checkMenu;

        const cam_scale = Camera.size_mult * main.camera.scale;
        for (map.listForType(Player).items) |player| {
            if (player.map_id == map.info.player_map_id) continue;
            const size = cam_scale * player.size_mult;
            const pos = main.camera.worldToScreen(player.x, player.y);
            const w = player.atlas_data.texWRaw() * size;
            const h = player.atlas_data.texHRaw() * size;
            const tl_x = pos.x - w / 2.0;
            const tl_y = pos.y - h;
            if (!utils.isInBounds(x, y, tl_x, tl_y, w, h)) continue;
            menu.switchMenu(.player, .{ .x = x, .y = y, .player = player });
            break :checkMenu;
        }
    }

    return false;
}

pub fn mouseRelease(x: f32, y: f32) bool {
    var elem_iter = std.mem.reverseIterator(elements.items);
    while (elem_iter.next()) |elem| switch (elem) {
        inline else => |inner_elem| if (std.meta.hasFn(@typeInfo(@TypeOf(inner_elem)).pointer.child, "mouseRelease") and inner_elem.mouseRelease(x, y, 0, 0))
            return true,
    };

    return false;
}

pub fn mouseScroll(x: f32, y: f32, x_scroll: f32, y_scroll: f32) bool {
    var elem_iter = std.mem.reverseIterator(elements.items);
    while (elem_iter.next()) |elem| switch (elem) {
        inline else => |inner_elem| if (std.meta.hasFn(@typeInfo(@TypeOf(inner_elem)).pointer.child, "mouseScroll") and inner_elem.mouseScroll(x, y, 0, 0, x_scroll, y_scroll))
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

fn lerp(a: f32, b: f32, f: f32) f32 {
    return a * (1.0 - f) + (b * f);
}

pub fn update(time: i64, dt: f32) !void {
    backgroundUpdate: switch (screen) {
        .game, .editor => {},
        else => {
            const point_len: u32 = @intCast(points.len);
            if (time >= last_point_switch + points[current_point_idx].time) {
                current_point_idx = (current_point_idx + 1) % point_len;
                last_point_switch += points[current_point_idx].time;
            }

            const next_point_idx = (current_point_idx + 1) % point_len;
            const current_point = points[current_point_idx];
            const next_point = points[next_point_idx];
            const frac = f32i(time - last_point_switch) / f32i(current_point.time);
            var player = map.localPlayer(.ref) orelse break :backgroundUpdate;
            player.x = lerp(current_point.x, next_point.x, frac);
            player.y = lerp(current_point.y, next_point.y, frac);
        },
    }

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
