const std = @import("std");
const utils = @import("shared").utils;
const game_data = @import("shared").game_data;

pub const StatValue = union(enum) {
    str: []const u8,
    sbyte: i8,
    byte: u8,
    short: i16,
    ushort: u16,
    int: i32,
    uint: u32,
    float: f32,
    condition: utils.Condition,
};

pub inline fn ensureCapacity(writer: *utils.PacketWriter, allocator: std.mem.Allocator, comptime space_needed: u16) !void {
    const len = writer.buffer.len;
    const rem = len - writer.index;
    if (rem >= space_needed)
        return;

    var new = len;
    while (true) {
        new +|= new / 2 + 8;
        if (new >= len + space_needed - rem)
            break;
    }

    writer.buffer = try allocator.realloc(writer.buffer, new);
}

pub inline fn write(
    writer: *utils.PacketWriter,
    cache: *std.EnumArray(game_data.StatType, ?StatValue),
    allocator: std.mem.Allocator,
    comptime stat_type: game_data.StatType,
    value: anytype,
) void {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);

    comptime var field_name: []const u8 = "";
    inline for (std.meta.fields(StatValue)) |field| {
        if (field.type == T) {
            field_name = field.name;
            break;
        }
    }

    if (field_name.len == 0)
        @compileError("Could not find field name");

    if (cache.get(stat_type)) |sv| {
        switch (T) {
            []const u8, []u8 => if (std.mem.eql(u8, sv.str, value)) return,
            utils.Condition => {
                const backing_int = type_info.Struct.backing_integer.?;
                if (@as(backing_int, @bitCast(value)) == @as(backing_int, @bitCast(sv.condition)))
                    return;
            },
            else => if (@field(sv, field_name) == value) return,
        }
    }

    ensureCapacity(writer, allocator, @sizeOf(u8) +
        if (type_info == .Array)
        @sizeOf(u16) + @sizeOf(type_info.Array.child)
    else if (type_info == .Pointer and type_info.Pointer.size == .Slice)
        @sizeOf(u16) + @sizeOf(type_info.Pointer.child)
    else
        @sizeOf(T)) catch unreachable;
    writer.write(@intFromEnum(stat_type));
    writer.write(value);

    cache.set(stat_type, @unionInit(StatValue, field_name, value));
}
