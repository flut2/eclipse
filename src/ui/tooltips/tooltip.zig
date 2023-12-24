const std = @import("std");
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
    none: void,
    item: ItemTooltip,
    text: TextTooltip,
    ability: AbilityTooltip,
};

pub var tooltip_map: std.AutoHashMap(TooltipType, *Tooltip) = undefined;
pub var current_tooltip: *Tooltip = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    tooltip_map = std.AutoHashMap(TooltipType, *Tooltip).init(allocator);

    const none_tooltip = try allocator.create(Tooltip);
    none_tooltip.* = .{ .none = {} };
    try tooltip_map.put(.none, none_tooltip);

    var item_tooltip = try allocator.create(Tooltip);
    item_tooltip.* = .{ .item = .{} };
    try item_tooltip.item.init(allocator);
    try tooltip_map.put(.item, item_tooltip);

    var text_tooltip = try allocator.create(Tooltip);
    text_tooltip.* = .{ .text = .{} };
    try text_tooltip.text.init(allocator);
    try tooltip_map.put(.text, text_tooltip);

    var ability_tooltip = try allocator.create(Tooltip);
    ability_tooltip.* = .{ .ability = .{} };
    try ability_tooltip.ability.init(allocator);
    try tooltip_map.put(.ability, ability_tooltip);

    current_tooltip = none_tooltip;
}

pub fn deinit(allocator: std.mem.Allocator) void {
    var iter = tooltip_map.iterator();
    while (iter.next()) |entry| {
        if (entry.key_ptr.* != .none) {
            switch (entry.value_ptr.*.*) {
                .none => {},
                inline else => |*tooltip| {
                    tooltip.deinit();
                },
            }
        }

        allocator.destroy(entry.value_ptr.*);
    }

    tooltip_map.deinit();
}

pub fn switchTooltip(tooltip_type: TooltipType) void {
    if (std.meta.activeTag(current_tooltip.*) == tooltip_type)
        return;

    switch (current_tooltip.*) {
        .none => {},
        inline else => |tooltip| {
            tooltip.root.visible = false;
        },
    }

    current_tooltip = tooltip_map.get(tooltip_type) orelse blk: {
        std.log.err("Tooltip for {any} was not found, using .none", .{tooltip_type});
        break :blk tooltip_map.get(.none) orelse @panic(".none was not a valid tooltip");
    };

    switch (current_tooltip.*) {
        .none => {},
        inline else => |tooltip| {
            tooltip.root.visible = true;
        },
    }
}
