const std = @import("std");
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

pub var tooltip_map: std.AutoHashMap(TooltipType, *Tooltip) = undefined;
pub var current_tooltip: *Tooltip = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    tooltip_map = std.AutoHashMap(TooltipType, *Tooltip).init(allocator);

    inline for (std.meta.fields(Tooltip)) |field| {
        var tooltip = try allocator.create(Tooltip);
        tooltip.* = @unionInit(Tooltip, field.name, .{});
        try @field(tooltip, field.name).init(allocator);
        try tooltip_map.put(std.meta.stringToEnum(TooltipType, field.name) orelse 
            std.debug.panic("No enum type with name {s} found on TooltipType", .{field.name}), tooltip);
    }

    current_tooltip = tooltip_map.get(.none).?;
}

pub fn deinit(allocator: std.mem.Allocator) void {
    var iter = tooltip_map.valueIterator();
    while (iter.next()) |value| {
        switch (value.*.*) {
            inline else => |*tooltip| {
                tooltip.deinit();
            },
        }

        allocator.destroy(value.*);
    }

    tooltip_map.deinit();
}

pub fn switchTooltip(tooltip_type: TooltipType) void {
    if (std.meta.activeTag(current_tooltip.*) == tooltip_type)
        return;

    switch (current_tooltip.*) {
        inline else => |tooltip| {
            tooltip.root.visible = false;
        },
    }

    current_tooltip = tooltip_map.get(tooltip_type) orelse blk: {
        std.log.err("Tooltip for {any} was not found, using .none", .{tooltip_type});
        break :blk tooltip_map.get(.none) orelse std.debug.panic(".none was not a valid tooltip", .{});
    };

    switch (current_tooltip.*) {
        inline else => |tooltip| {
            tooltip.root.visible = true;
        },
    }
}
