const std = @import("std");

const game_data = @import("shared").game_data;

const assets = @import("../../assets.zig");
const main = @import("../../main.zig");
const Container = @import("../elements/Container.zig");
const element = @import("../elements/element.zig");
const Image = @import("../elements/Image.zig");
const TextDialog = @import("TextDialog.zig");

pub const DialogType = enum {
    none,
    text,
};
pub const Dialog = union(DialogType) {
    none: void,
    text: TextDialog,
};
pub const DialogParams = union(DialogType) {
    none: void,
    text: struct { title: ?[]const u8 = null, body: []const u8, dispose_title: bool = false, dispose_body: bool = false },
};

pub var map: std.AutoHashMapUnmanaged(DialogType, *Dialog) = .empty;
pub var dialog_bg: *Image = undefined;
pub var current: *Dialog = undefined;

pub fn init() !void {
    defer {
        const dummy_dialog_ctx: std.hash_map.AutoContext(DialogType) = undefined;
        if (map.capacity() > 0) map.rehash(dummy_dialog_ctx);
    }

    const background_data = assets.getUiData("dark_background", 0);
    dialog_bg = try element.create(Image, .{
        .base = .{ .x = 0, .y = 0, .visible = false, .layer = .dialog },
        .image_data = .{ .nine_slice = .fromAtlasData(background_data, main.camera.width, main.camera.height, 0, 0, 8, 8, 1.0) },
    });

    inline for (@typeInfo(Dialog).@"union".fields) |field| @"continue": {
        var dialog = try main.allocator.create(Dialog);
        if (field.type == void) {
            dialog.* = @unionInit(Dialog, field.name, {});
            try map.put(main.allocator, std.meta.stringToEnum(DialogType, field.name) orelse
                std.debug.panic("No enum type with name {s} found in DialogType", .{field.name}), dialog);
            break :@"continue";
        }
        dialog.* = @unionInit(Dialog, field.name, .{});
        var dialog_inner = &@field(dialog, field.name);
        dialog_inner.* = .{ .root = try element.create(Container, .{ .base = .{ .visible = false, .layer = .dialog, .x = 0, .y = 0 } }) };
        try dialog_inner.init();
        try map.put(main.allocator, std.meta.stringToEnum(DialogType, field.name) orelse
            std.debug.panic("No enum type with name {s} found in DialogType", .{field.name}), dialog);
    }

    current = map.get(.none).?;
}

pub fn deinit() void {
    var iter = map.valueIterator();
    while (iter.next()) |value| {
        switch (value.*.*) {
            .none => {},
            inline else => |*dialog| dialog.deinit(),
        }

        main.allocator.destroy(value.*);
    }

    map.deinit(main.allocator);

    element.destroy(dialog_bg);
}

pub fn resize(w: f32, h: f32) void {
    dialog_bg.image_data.nine_slice.w = w;
    dialog_bg.image_data.nine_slice.h = h;

    switch (current.*) {
        .none => {},
        inline else => |dialog| {
            dialog.root.base.x = (w - dialog.root.width()) / 2.0;
            dialog.root.base.y = (h - dialog.root.height()) / 2.0;
        },
    }
}

fn fieldName(comptime T: type) []const u8 {
    if (!@inComptime()) @compileError("This function is comptime only");

    var field_name: []const u8 = "";
    for (@typeInfo(Dialog).@"union".fields) |field| {
        if (field.type == T) field_name = field.name;
    }

    if (field_name.len <= 0) @compileError("No params found");
    return field_name;
}

pub fn ParamsFor(comptime T: type) type {
    return std.meta.TagPayloadByName(DialogParams, fieldName(T));
}

pub fn showDialog(comptime dialog_type: DialogType, params: std.meta.TagPayload(DialogParams, dialog_type)) void {
    switch (current.*) {
        .none => {},
        inline else => |dialog| dialog.root.base.visible = false,
    }

    dialog_bg.base.visible = dialog_type != .none;
    if (current.* != dialog_type) {
        current = map.get(dialog_type) orelse blk: {
            std.log.err("Dialog for {} was not found, using .none", .{dialog_type});
            break :blk map.get(.none) orelse @panic(".none was not a valid dialog");
        };
    }

    const T = std.meta.TagPayload(Dialog, dialog_type);
    if (T == void) return;
    var dialog = &@field(current, fieldName(T));
    dialog.root.base.visible = true;
    dialog.setValues(params);
    dialog.root.base.x = (main.camera.width - dialog.root.width()) / 2.0;
    dialog.root.base.y = (main.camera.height - dialog.root.height()) / 2.0;
}
