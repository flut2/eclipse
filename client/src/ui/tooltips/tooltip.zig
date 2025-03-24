const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const network_data = shared.network_data;

const main = @import("../../main.zig");
const Container = @import("../elements/Container.zig");
const element = @import("../elements/element.zig");
const AbilityTooltip = @import("AbilityTooltip.zig");
const CardTooltip = @import("CardTooltip.zig");
const CharacterTooltip = @import("CharacterTooltip.zig");
const ItemTooltip = @import("ItemTooltip.zig");
const PlayerListTooltip = @import("PlayerListTooltip.zig");
const TalentTooltip = @import("TalentTooltip.zig");
const TextTooltip = @import("TextTooltip.zig");

pub const PlayerListItem = struct { data_id: u16, name: []const u8, celestial: bool };

pub const TooltipType = enum {
    none,
    item,
    text,
    ability,
    card,
    talent,
    character,
    player_list,
};
pub const Tooltip = union(TooltipType) {
    none: void,
    item: ItemTooltip,
    text: TextTooltip,
    ability: AbilityTooltip,
    card: CardTooltip,
    talent: TalentTooltip,
    character: CharacterTooltip,
    player_list: PlayerListTooltip,
};
pub const TooltipParams = union(TooltipType) {
    none: void,
    item: struct { x: f32, y: f32, item: u16, item_data: network_data.ItemData },
    text: struct { x: f32, y: f32, text_data: element.TextData },
    ability: struct { x: f32, y: f32, data: game_data.AbilityData },
    card: struct { x: f32, y: f32, data: game_data.CardData },
    talent: struct { x: f32, y: f32, index: u8, data: *const game_data.TalentData },
    character: struct { x: f32, y: f32, data: *const network_data.CharacterData },
    player_list: struct { x: f32, y: f32, items: []const PlayerListItem },
};

pub var map: std.AutoHashMapUnmanaged(TooltipType, *Tooltip) = .empty;
pub var current: *Tooltip = undefined;

pub fn init() !void {
    defer {
        const dummy_tooltip_ctx: std.hash_map.AutoContext(TooltipType) = undefined;
        if (map.capacity() > 0) map.rehash(dummy_tooltip_ctx);
    }

    inline for (@typeInfo(Tooltip).@"union".fields) |field| @"continue": {
        var tooltip = try main.allocator.create(Tooltip);
        if (field.type == void) {
            tooltip.* = @unionInit(Tooltip, field.name, {});
            try map.put(main.allocator, std.meta.stringToEnum(TooltipType, field.name) orelse
                std.debug.panic("No enum type with name {s} found in TooltipType", .{field.name}), tooltip);
            break :@"continue";
        }
        tooltip.* = @unionInit(Tooltip, field.name, .{});
        var tooltip_inner = &@field(tooltip, field.name);
        tooltip_inner.* = .{ .root = try element.create(Container, .{ .base = .{ .visible = false, .layer = .tooltip, .x = 0, .y = 0 } }) };
        try tooltip_inner.init();
        try map.put(main.allocator, std.meta.stringToEnum(TooltipType, field.name) orelse
            std.debug.panic("No enum type with name {s} found in TooltipType", .{field.name}), tooltip);
    }

    current = map.get(.none).?;
}

pub fn deinit() void {
    var iter = map.valueIterator();
    while (iter.next()) |value| {
        switch (value.*.*) {
            .none => {},
            inline else => |*tooltip| tooltip.deinit(),
        }

        main.allocator.destroy(value.*);
    }

    map.deinit(main.allocator);
}

pub fn ParamsFor(comptime T: type) type {
    for (@typeInfo(Tooltip).@"union".fields) |field|
        if (field.type == T) return @FieldType(TooltipParams, field.name);
    @compileError("No params found");
}

pub fn switchTooltip(comptime tooltip_type: TooltipType, params: @FieldType(TooltipParams, @tagName(tooltip_type))) void {
    if (current.* == tooltip_type) return;

    switch (current.*) {
        .none => {},
        inline else => |tooltip| tooltip.root.base.visible = false,
    }

    current = map.get(tooltip_type) orelse blk: {
        std.log.err("Tooltip for {} was not found, using .none", .{tooltip_type});
        break :blk map.get(.none) orelse @panic(".none was not a valid tooltip");
    };

    if (@FieldType(Tooltip, @tagName(tooltip_type)) == void) return;
    var tooltip = &@field(current, @tagName(tooltip_type));
    tooltip.root.base.visible = true;
    tooltip.update(params);
}
