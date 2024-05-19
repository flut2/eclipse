const std = @import("std");
const utils = @import("shared").utils;
const game_data = @import("shared").game_data;

pub const Behavior = blk: {
    const EnumField = std.builtin.Type.EnumField;
    const UnionField = std.builtin.Type.UnionField;

    var union_fields: []const UnionField = &[_]UnionField{};
    var enum_fields: []const EnumField = &[_]EnumField{};

    var enum_index: u32 = 0;
    for (0..@import("behaviors").len) |i| {
        const import = @field(@import("../_generated_dont_use.zig"), std.fmt.comptimePrint("b{d}", .{i}));
        for (@typeInfo(import).Struct.decls) |d| {
            const behav = @field(import, d.name);
            const name = std.fmt.comptimePrint("{d}", .{utils.typeId(behav)});

            enum_fields = enum_fields ++ &[_]EnumField{.{
                .name = name,
                .value = enum_index,
            }};
            enum_index += 1;

            union_fields = union_fields ++ &[_]UnionField{.{
                .name = name,
                .type = behav,
                .alignment = @alignOf(behav),
            }};
        }
    }

    const Enum = @Type(.{ .Enum = .{
        .tag_type = u32,
        .fields = enum_fields,
        .decls = &.{},
        .is_exhaustive = false,
    } });

    break :blk @Type(.{ .Union = .{
        .layout = .Auto,
        .fields = union_fields,
        .decls = &.{},
        .tag_type = Enum,
    } });
};

pub var behavior_map: std.AutoHashMap(u16, Behavior) = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    behavior_map = std.AutoHashMap(u16, Behavior).init(allocator);
    inline for (0..@import("behaviors").len) |i| {
        const import = @field(@import("../_generated_dont_use.zig"), std.fmt.comptimePrint("b{d}", .{i}));
        inline for (@typeInfo(import).Struct.decls) |d| {
            const behav = @field(import, d.name);
            const name = @field(behav, "object_name");
            const obj_type = game_data.obj_name_to_type.get(name) orelse {
                std.log.err("Adding behavior for {s} failed: obj type not found", .{name});
                return;
            };

            try behavior_map.put(obj_type, @unionInit(Behavior, std.fmt.comptimePrint("{d}", .{utils.typeId(behav)}), .{}));
        }
    }
}

pub fn deinit() void {
    behavior_map.deinit();
}
