const std = @import("std");
const ItemTooltip = @import("item_tooltip.zig").ItemTooltip;
const TextTooltip = @import("text_tooltip.zig").TextTooltip;

pub const TooltipType = enum {
    none,
    item,
    text,
};
pub const Tooltip = union(TooltipType) {
    none: void,
    item: ItemTooltip,
    text: TextTooltip,
};

pub var tooltip_map: std.AutoHashMap(TooltipType, Tooltip) = undefined;
pub var current_tooltip = Tooltip{ .none = {} };

pub fn init(allocator: std.mem.Allocator) !void {
    tooltip_map = std.AutoHashMap(TooltipType, Tooltip).init(allocator);

    try tooltip_map.put(.none, Tooltip{ .none = {} });

    var item_tooltip = Tooltip{ .item = .{} };
    try item_tooltip.item.init(allocator);
    try tooltip_map.put(.item, item_tooltip);

    var text_tooltip = Tooltip{ .text = .{} };
    try text_tooltip.text.init(allocator);
    try tooltip_map.put(.text, text_tooltip);
}

pub fn deinit() void {
    var iter = tooltip_map.iterator();
    while (iter.next()) |entry| {
        if (entry.key_ptr.* != .none) {
            switch (entry.value_ptr.*) {
                .none => {},
                inline else => |*tooltip| {
                    tooltip.deinit();
                },
            }
        }
    }

    tooltip_map.deinit();
}

pub fn switchTooltip(tooltip_type: TooltipType) void {
    if (std.meta.activeTag(current_tooltip) == tooltip_type)
        return;

    switch (current_tooltip) {
        .none => {},
        inline else => |tooltip| {
            tooltip.root.visible = false;
        },
    }

    current_tooltip = tooltip_map.get(tooltip_type) orelse blk: {
        std.log.err("Tooltip for {any} was not found, using .none", .{tooltip_type});
        break :blk Tooltip{ .none = {} };
    };

    switch (current_tooltip) {
        .none => {},
        inline else => |tooltip| {
            tooltip.root.visible = true;
        },
    }
}
