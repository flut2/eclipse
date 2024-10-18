const std = @import("std");
const gen_behaviors = @import("../_gen_behavior_file_dont_use.zig");
const shared = @import("shared");
const utils = shared.utils;
const game_data = shared.game_data;

const Entity = @import("../map/entity.zig").Entity;
const Enemy = @import("../map/enemy.zig").Enemy;

const BehaviorType = enum { entity, enemy };
pub const BehaviorMetadata = struct {
    type: BehaviorType,
    name: []const u8,
};

fn getMetadata(comptime T: type) BehaviorMetadata {
    if (!@inComptime()) @compileError("This function is comptime-only");

    var ret: BehaviorMetadata = undefined;
    var found_metadata = false;
    for (@typeInfo(T).@"struct".decls) |decl| @"continue": {
        if (!std.mem.eql(u8, decl.name, "data")) break :@"continue";
        const metadata = @field(T, decl.name);
        if (@TypeOf(metadata) != BehaviorMetadata) continue;
        if (found_metadata) @compileError("Duplicate behavior metadata");
        ret = metadata;
        found_metadata = true;
    }

    if (!found_metadata) @compileError("No behavior metadata found");
    return ret;
}

fn Behavior(comptime behav_type: BehaviorType) type {
    if (!@inComptime()) @compileError("This function is comptime-only");

    const EnumField = std.builtin.Type.EnumField;
    const UnionField = std.builtin.Type.UnionField;

    var union_fields: []const UnionField = &[_]UnionField{};
    var enum_fields: []const EnumField = &[_]EnumField{};

    var enum_index: u32 = 0;
    for (gen_behaviors.behaviors) |import| {
        for (@typeInfo(import).@"struct".decls) |d| @"continue": {
            const behav = @field(import, d.name);
            if (getMetadata(behav).type != behav_type) break :@"continue";
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

    const Enum = @Type(.{ .@"enum" = .{
        .tag_type = u32,
        .fields = enum_fields,
        .decls = &.{},
        .is_exhaustive = true,
    } });

    return @Type(.{ .@"union" = .{
        .layout = .auto,
        .fields = union_fields,
        .decls = &.{},
        .tag_type = Enum,
    } });
}

pub const EntityBehavior = Behavior(.entity);
pub const EnemyBehavior = Behavior(.enemy);

pub var entity_behavior_map: std.AutoHashMapUnmanaged(u16, EntityBehavior) = .empty;
pub var enemy_behavior_map: std.AutoHashMapUnmanaged(u16, EnemyBehavior) = .empty;

pub fn init(allocator: std.mem.Allocator) !void {
    inline for (gen_behaviors.behaviors) |import| {
        inline for (@typeInfo(import).@"struct".decls) |d| @"continue": {
            const behav = @field(import, d.name);
            const metadata = comptime getMetadata(behav);
            const id = (switch (metadata.type) {
                .entity => game_data.entity.from_name.get(metadata.name),
                .enemy => game_data.enemy.from_name.get(metadata.name),
            } orelse {
                std.log.err("Adding behavior for \"{s}\" failed: object not found", .{metadata.name});
                break :@"continue";
            }).id;

            const res = try switch (metadata.type) {
                .entity => entity_behavior_map.getOrPut(allocator, id),
                .enemy => enemy_behavior_map.getOrPut(allocator, id),
            };
            if (res.found_existing)
                std.log.err("The struct \"{s}\" overwrote the behavior for the object \"{s}\"", .{ @typeName(behav), metadata.name });

            res.value_ptr.* = @unionInit(switch (metadata.type) {
                .entity => EntityBehavior,
                .enemy => EnemyBehavior,
            }, std.fmt.comptimePrint("{d}", .{utils.typeId(behav)}), .{});
        }
    }
}

pub fn deinit(allocator: std.mem.Allocator) void {
    entity_behavior_map.deinit(allocator);
    enemy_behavior_map.deinit(allocator);
}