const std = @import("std");

const shared = @import("shared");
const utils = shared.utils;
const game_data = shared.game_data;

const main = @import("../main.zig");
const Enemy = @import("../map/Enemy.zig");
const Entity = @import("../map/Entity.zig");

const behaviors = .{
    @import("behaviors/ability.zig"),
    @import("behaviors/basic_enemies.zig"),
    @import("behaviors/crown_cove.zig"),
    @import("behaviors/misc.zig"),
};

const BehaviorType = enum { entity, enemy, ally };
pub const BehaviorMetadata = struct {
    type: BehaviorType,
    name: []const u8,
};

fn getMetadata(comptime T: type) BehaviorMetadata {
    @setEvalBranchQuota(10000);

    var ret: ?BehaviorMetadata = null;
    for (@typeInfo(T).@"struct".decls) |decl| @"continue": {
        if (!std.mem.eql(u8, decl.name, "data")) break :@"continue";
        const metadata = @field(T, decl.name);
        if (@TypeOf(metadata) != BehaviorMetadata) continue;
        if (ret != null) @compileError("Duplicate behavior metadata");
        ret = metadata;
    }

    if (ret == null) @compileError("No behavior metadata found");
    return ret.?;
}

fn Behavior(comptime behav_type: BehaviorType) type {
    const UnionAttrs = std.builtin.Type.UnionField.Attributes;

    var union_field_names: []const []const u8 = &.{};
    var union_field_types: []const type = &.{};
    var union_field_attrs: []const UnionAttrs = &.{};
    var enum_field_names: []const []const u8 = &.{};
    var enum_field_values: []const u32 = &.{};

    var enum_index: u32 = 0;
    for (behaviors) |import| {
        for (@typeInfo(import).@"struct".decls) |d| @"continue": {
            const behav = @field(import, d.name);
            if (getMetadata(behav).type != behav_type) break :@"continue";
            const name = std.fmt.comptimePrint("{d}", .{utils.typeId(behav)});

            enum_field_names = enum_field_names ++ &[_][]const u8{name};
            enum_field_values = enum_field_values ++ &[_]u32{enum_index};
            enum_index += 1;

            union_field_names = union_field_names ++ &[_][]const u8{name};
            union_field_types = union_field_types ++ &[_]type{behav};
            union_field_attrs = union_field_attrs ++ &[_]UnionAttrs{.{ .@"align" = @alignOf(behav) }};
        }
    }

    const TagEnum = @Enum(u32, .nonexhaustive, enum_field_names, enum_field_values[0..]);
    return @Union(.auto, TagEnum, union_field_names, union_field_types[0..], union_field_attrs[0..]);
}

pub const EntityBehavior = Behavior(.entity);
pub const EnemyBehavior = Behavior(.enemy);
pub const AllyBehavior = Behavior(.ally);

pub var entity_behavior_map: std.AutoHashMapUnmanaged(u16, EntityBehavior) = .empty;
pub var enemy_behavior_map: std.AutoHashMapUnmanaged(u16, EnemyBehavior) = .empty;
pub var ally_behavior_map: std.AutoHashMapUnmanaged(u16, AllyBehavior) = .empty;

pub fn init() !void {
    inline for (behaviors) |import| {
        inline for (@typeInfo(import).@"struct".decls) |d| @"continue": {
            const behav = @field(import, d.name);
            const metadata = comptime getMetadata(behav);
            const id = (switch (metadata.type) {
                .entity => game_data.entity.from_name.get(metadata.name),
                .enemy => game_data.enemy.from_name.get(metadata.name),
                .ally => game_data.ally.from_name.get(metadata.name),
            } orelse {
                std.log.err("Adding behavior for \"{s}\" failed: object not found", .{metadata.name});
                break :@"continue";
            }).id;

            const res = try switch (metadata.type) {
                .entity => entity_behavior_map.getOrPut(main.allocator, id),
                .enemy => enemy_behavior_map.getOrPut(main.allocator, id),
                .ally => ally_behavior_map.getOrPut(main.allocator, id),
            };
            if (res.found_existing)
                std.log.err("The struct \"{s}\" overwrote the behavior for the object \"{s}\"", .{ @typeName(behav), metadata.name });

            res.value_ptr.* = @unionInit(switch (metadata.type) {
                .entity => EntityBehavior,
                .enemy => EnemyBehavior,
                .ally => AllyBehavior,
            }, std.fmt.comptimePrint("{d}", .{utils.typeId(behav)}), .{});
        }
    }
}

pub fn deinit() void {
    entity_behavior_map.deinit(main.allocator);
    enemy_behavior_map.deinit(main.allocator);
    ally_behavior_map.deinit(main.allocator);
}
