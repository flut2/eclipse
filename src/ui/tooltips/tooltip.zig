const std = @import("std");
const element = @import("../element.zig");
const game_data = @import("../../game_data.zig");

const NoneTooltip = @import("none_tooltip.zig").NoneTooltip;
const ItemTooltip = @import("item_tooltip.zig").ItemTooltip;
const TextTooltip = @import("text_tooltip.zig").TextTooltip;
const AbilityTooltip = @import("ability_tooltip.zig").AbilityTooltip;

pub const TooltipType = enum {
    none,
    item,
    text,
    ability,
};
pub const Tooltip = union(TooltipType) {
    none: NoneTooltip,
    item: ItemTooltip,
    text: TextTooltip,
    ability: AbilityTooltip,
};
pub const TooltipParams = union(TooltipType) {
    none: void,
    item: struct { x: f32, y: f32, item: u16 },
    text: struct { x: f32, y: f32, text_data: element.TextData },
    ability: struct { x: f32, y: f32, props: game_data.Ability },
};

pub var map: std.AutoHashMap(TooltipType, *Tooltip) = undefined;
pub var current: *Tooltip = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    map = std.AutoHashMap(TooltipType, *Tooltip).init(allocator);

    inline for (std.meta.fields(Tooltip)) |field| {
        var tooltip = try allocator.create(Tooltip);
        tooltip.* = @unionInit(Tooltip, field.name, .{});
        try @field(tooltip, field.name).init(allocator);
        try map.put(std.meta.stringToEnum(TooltipType, field.name) orelse
            std.debug.panic("No enum type with name {s} found on TooltipType", .{field.name}), tooltip);
    }

    current = map.get(.none).?;
}

pub fn deinit(allocator: std.mem.Allocator) void {
    var iter = map.valueIterator();
    while (iter.next()) |value| {
        switch (value.*.*) {
            inline else => |*tooltip| {
                tooltip.deinit();
            },
        }

        allocator.destroy(value.*);
    }

    map.deinit();
}

inline fn fieldName(comptime T: type) []const u8 {
    comptime {
        var field_name: []const u8 = "";
        for (std.meta.fields(Tooltip)) |field| {
            if (field.type == T)
                field_name = field.name;
        }

        if (field_name.len <= 0)
            @compileError("No params found");

        return field_name;
    }
}

pub inline fn ParamsFor(comptime T: type) type {
    return std.meta.TagPayloadByName(TooltipParams, fieldName(T));
}

pub fn switchTooltip(comptime tooltip_type: TooltipType, params: std.meta.TagPayload(TooltipParams, tooltip_type)) void {
    if (std.meta.activeTag(current.*) == tooltip_type)
        return;

    switch (current.*) {
        inline else => |tooltip| {
            tooltip.root.visible = false;
        },
    }

    current = map.get(tooltip_type) orelse blk: {
        std.log.err("Tooltip for {any} was not found, using .none", .{tooltip_type});
        break :blk map.get(.none) orelse std.debug.panic(".none was not a valid tooltip", .{});
    };

    const T = std.meta.TagPayload(Tooltip, tooltip_type);
    @field(current, fieldName(T)).root.visible = true;
    @field(current, fieldName(T)).update(params);
}
