const std = @import("std");

const shared = @import("shared");
const utils = shared.utils;
const game_data = shared.game_data;

const main = @import("../main.zig");

pub fn write(
    comptime StatType: type,
    writer: *utils.PacketWriter,
    cache: *[@typeInfo(StatType).@"union".fields.len]?StatType,
    value: StatType,
) void {
    switch (value) {
        inline else => |inner_value, tag| {
            const T = @TypeOf(inner_value);
            const type_info = @typeInfo(T);
            const is_array = type_info == .array;
            const is_slice = type_info == .pointer and type_info.pointer.size == .slice;
            const is_condition = T == utils.Condition;

            const tag_id = @intFromEnum(tag);
            if (cache[tag_id] != null and
                (is_array and std.mem.eql(type_info.array.child, @field(cache[tag_id].?, @tagName(tag)), inner_value) or
                    is_slice and std.mem.eql(type_info.pointer.child, @field(cache[tag_id].?, @tagName(tag)), inner_value) or
                    is_condition and inner_value.eql(@field(cache[tag_id].?, @tagName(tag))) or
                    !is_condition and !is_array and !is_slice and @field(cache[tag_id].?, @tagName(tag)) == inner_value))
                return;

            writer.write(@intFromEnum(tag), main.allocator);
            writer.write(inner_value, main.allocator);

            if (cache[tag_id]) |*cache_field| {
                if (is_slice) main.allocator.free(@field(cache_field.*, @tagName(tag)));
                @field(cache_field.*, @tagName(tag)) = if (is_slice)
                    main.allocator.dupe(type_info.pointer.child, inner_value) catch main.oomPanic()
                else
                    inner_value;
            } else cache[tag_id] = if (is_slice)
                @unionInit(StatType, @tagName(tag), main.allocator.dupe(type_info.pointer.child, inner_value) catch main.oomPanic())
            else
                @unionInit(StatType, @tagName(tag), inner_value);
        },
    }
}
