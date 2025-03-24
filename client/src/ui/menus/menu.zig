const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const network_data = shared.network_data;
const utils = shared.utils;

const Player = @import("../../game/Player.zig");
const main = @import("../../main.zig");
const Container = @import("../elements/Container.zig");
const element = @import("../elements/element.zig");
const PlayerMenu = @import("PlayerMenu.zig");
const TeleportMenu = @import("TeleportMenu.zig");

pub const MenuType = enum {
    none,
    player,
    teleport,
};
pub const Menu = union(MenuType) {
    none: void,
    player: PlayerMenu,
    teleport: TeleportMenu,
};
pub const MenuParams = union(MenuType) {
    none: void,
    player: struct { x: f32, y: f32, player: Player },
    teleport: struct {
        x: f32,
        y: f32,
        map_id: u32,
        data_id: u16,
        name: []const u8,
        rank: network_data.Rank,
    },
};

pub var map: std.AutoHashMapUnmanaged(MenuType, *Menu) = .empty;
pub var current: *Menu = undefined;

pub fn init() !void {
    defer {
        const dummy_menu_ctx: std.hash_map.AutoContext(MenuType) = undefined;
        if (map.capacity() > 0) map.rehash(dummy_menu_ctx);
    }

    inline for (@typeInfo(Menu).@"union".fields) |field| @"continue": {
        var menu = try main.allocator.create(Menu);
        if (field.type == void) {
            menu.* = @unionInit(Menu, field.name, {});
            try map.put(main.allocator, std.meta.stringToEnum(MenuType, field.name) orelse
                std.debug.panic("No enum type with name {s} found in MenuType", .{field.name}), menu);
            break :@"continue";
        }
        menu.* = @unionInit(Menu, field.name, .{});
        var menu_inner = &@field(menu, field.name);
        menu_inner.* = .{ .root = try element.create(Container, .{ .base = .{ .visible = false, .layer = .menu, .x = 0, .y = 0 } }) };
        try menu_inner.init();
        try map.put(main.allocator, std.meta.stringToEnum(MenuType, field.name) orelse
            std.debug.panic("No enum type with name {s} found in MenuType", .{field.name}), menu);
    }

    current = map.get(.none).?;
}

pub fn deinit() void {
    var iter = map.valueIterator();
    while (iter.next()) |value| {
        switch (value.*.*) {
            .none => {},
            inline else => |*menu| menu.deinit(),
        }

        main.allocator.destroy(value.*);
    }

    map.deinit(main.allocator);
}

pub fn ParamsFor(comptime T: type) type {
    for (@typeInfo(Menu).@"union".fields) |field|
        if (field.type == T) return @FieldType(MenuParams, field.name);
    @compileError("No params found");
}

pub fn switchMenu(comptime menu_type: MenuType, params: @FieldType(MenuParams, @tagName(menu_type))) void {
    if (current.* == menu_type) return;

    switch (current.*) {
        .none => {},
        inline else => |menu| menu.root.base.visible = false,
    }

    current = map.get(menu_type) orelse blk: {
        std.log.err("Menu for {} was not found, using .none", .{menu_type});
        break :blk map.get(.none) orelse @panic(".none was not a valid menu");
    };

    if (@FieldType(Menu, @tagName(menu_type)) == void) return;
    var menu = &@field(current, @tagName(menu_type));
    menu.root.base.visible = true;
    menu.update(params);
}

pub fn checkMenuValidity(x: f32, y: f32) void {
    if (current.* == .none) return;

    switch (current.*) {
        .none => unreachable,
        inline else => |menu| {
            if (!utils.isInBounds(x, y, menu.root.base.x, menu.root.base.y, menu.root.width(), menu.root.height())) {
                menu.root.base.visible = false;
                current = map.get(.none) orelse unreachable;
            }
        },
    }
}

pub fn cancelMenu() void {
    if (current.* == .none or current.* == .teleport) return;

    switch (current.*) {
        .none => unreachable,
        inline else => |menu| {
            menu.root.base.visible = false;
            current = map.get(.none) orelse unreachable;
        },
    }
}
