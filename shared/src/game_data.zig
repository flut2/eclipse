const std = @import("std");
const utils = @import("utils.zig");

pub var resource: Maps(ResourceData) = .{};
pub var card: Maps(CardData) = .{};
pub var item: Maps(ItemData) = .{};
pub var class: Maps(ClassData) = .{};
pub var container: Maps(ContainerData) = .{};
pub var enemy: Maps(EnemyData) = .{};
pub var entity: Maps(EntityData) = .{};
pub var ground: Maps(GroundData) = .{};
pub var portal: Maps(PortalData) = .{};
pub var region: Maps(RegionData) = .{};
pub var purchasable: Maps(PurchasableData) = .{};
pub var ally: Maps(AllyData) = .{};

var arena: std.heap.ArenaAllocator = undefined;

pub fn Maps(comptime T: type) type {
    return struct {
        from_id: std.AutoHashMapUnmanaged(u16, T) = .empty,
        from_name: std.HashMapUnmanaged([]const u8, T, StringContext, 80) = .empty,
    };
}

fn parseClasses(allocator: std.mem.Allocator, path: []const u8) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const file_data = try file.readToEndAlloc(allocator, std.math.maxInt(u32));
    defer allocator.free(file_data);

    const json = try std.json.parseFromSlice([]InternalClassData, allocator, file_data, .{});
    defer json.deinit();

    for (json.value) |int_class| {
        const default_items: []u16 = try allocator.alloc(u16, int_class.default_items.len);
        for (default_items, 0..) |*default_item, i| {
            const item_name = int_class.default_items[i];
            if (item_name.len == 0) {
                default_item.* = std.math.maxInt(u16);
                continue;
            }
            default_item.* = (item.from_name.get(item_name) orelse @panic("Invalid item given to ClassData")).id;
        }

        var abilities_copy: [4]AbilityData = undefined;
        for (&abilities_copy, int_class.abilities) |*abil_data, old_abil| {
            abil_data.* = .{
                .name = try allocator.dupe(u8, old_abil.name),
                .description = try allocator.dupe(u8, old_abil.description),
                .mana_cost = old_abil.mana_cost,
                .health_cost = old_abil.health_cost,
                .gold_cost = old_abil.gold_cost,
                .cooldown = old_abil.cooldown,
                .icon = .{
                    .sheet = try allocator.dupe(u8, old_abil.icon.sheet),
                    .index = old_abil.icon.index,
                },
                .projectiles = if (old_abil.projectiles) |projs| try allocator.dupe(ProjectileData, projs) else null,
            };
            if (old_abil.projectiles) |projs| {
                const new_projs = try allocator.dupe(ProjectileData, projs);
                for (new_projs) |*proj| {
                    const new_textures = try allocator.dupe(TextureData, proj.textures);
                    for (new_textures) |*tex| tex.sheet = try allocator.dupe(u8, tex.sheet);
                    proj.textures = new_textures;
                }
                abil_data.projectiles = new_projs;
            }
        }

        const talents_copy = try allocator.dupe(TalentData, int_class.talents);
        for (talents_copy, 0..) |*talent, i| {
            talent.name = try allocator.dupe(u8, int_class.talents[i].name);
            talent.description = try allocator.dupe(u8, int_class.talents[i].description);
            talent.level_costs = try allocator.dupe(TalentLevelCost, int_class.talents[i].level_costs);
            for (talent.level_costs, 0..) |*level_cost, j| {
                level_cost.resource_costs = try allocator.dupe(ResourceCost, int_class.talents[i].level_costs[j].resource_costs);
                level_cost.item_costs = try allocator.dupe(ItemCost, int_class.talents[i].level_costs[j].item_costs);
            }
            talent.requires = try allocator.dupe(TalentRequirement, int_class.talents[i].requires);
        }

        const class_data: ClassData = .{
            .id = int_class.id,
            .name = try allocator.dupe(u8, int_class.name),
            .description = try allocator.dupe(u8, int_class.description),
            .texture = .{
                .sheet = try allocator.dupe(u8, int_class.texture.sheet),
                .index = int_class.texture.index,
            },
            .item_types = int_class.item_types,
            .default_items = default_items,
            .stats = int_class.stats,
            .hit_sound = try allocator.dupe(u8, int_class.hit_sound),
            .death_sound = try allocator.dupe(u8, int_class.death_sound),
            .rpc_name = try allocator.dupe(u8, int_class.rpc_name),
            .abilities = abilities_copy,
            .light = int_class.light,
            .talents = talents_copy,
        };
        try class.from_id.put(allocator, class_data.id, class_data);
        try class.from_name.put(allocator, class_data.name, class_data);
    }
}

fn parseGeneric(allocator: std.mem.Allocator, path: []const u8, comptime DataType: type, data_maps: *Maps(DataType)) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const file_data = try file.readToEndAlloc(allocator, std.math.maxInt(u32));
    defer allocator.free(file_data);

    const data_slice = try std.json.parseFromSliceLeaky([]DataType, allocator, file_data, .{ .allocate = .alloc_always });
    for (data_slice) |data| {
        try data_maps.from_id.put(allocator, data.id, data);
        try data_maps.from_name.put(allocator, data.name, data);
    }
}

pub fn init(allocator: std.mem.Allocator) !void {
    defer {
        const dummy_id_ctx: std.hash_map.AutoContext(u16) = undefined;
        const dummy_name_ctx: StringContext = undefined;
        inline for (.{
            &card,
            &item,
            &class,
            &container,
            &enemy,
            &entity,
            &ground,
            &portal,
            &region,
            &purchasable,
            &ally,
        }) |data_maps| {
            if (data_maps.from_id.capacity() > 0) data_maps.from_id.rehash(dummy_id_ctx);
            if (data_maps.from_name.capacity() > 0) data_maps.from_name.rehash(dummy_name_ctx);
        }
    }

    arena = .init(allocator);
    const arena_allocator = arena.allocator();

    try parseGeneric(arena_allocator, "./assets/data/cards.json", CardData, &card);
    try parseGeneric(arena_allocator, "./assets/data/items.json", ItemData, &item);
    try parseGeneric(arena_allocator, "./assets/data/containers.json", ContainerData, &container);
    try parseGeneric(arena_allocator, "./assets/data/enemies.json", EnemyData, &enemy);
    try parseGeneric(arena_allocator, "./assets/data/entities.json", EntityData, &entity);
    try parseGeneric(arena_allocator, "./assets/data/walls.json", EntityData, &entity);
    try parseGeneric(arena_allocator, "./assets/data/ground.json", GroundData, &ground);
    try parseGeneric(arena_allocator, "./assets/data/portals.json", PortalData, &portal);
    try parseGeneric(arena_allocator, "./assets/data/regions.json", RegionData, &region);
    try parseGeneric(arena_allocator, "./assets/data/purchasables.json", PurchasableData, &purchasable);
    try parseGeneric(arena_allocator, "./assets/data/allies.json", AllyData, &ally);

    // Must be last to resolve item name->id
    try parseClasses(arena_allocator, "./assets/data/classes.json");
}

pub fn deinit() void {
    arena.deinit();
}

fn isNumberFormattedLikeAnInteger(value: []const u8) bool {
    if (std.mem.eql(u8, value, "-0")) return false;
    return std.mem.indexOfAny(u8, value, ".eE") == null;
}

fn sliceToInt(comptime T: type, slice: []const u8) !T {
    if (isNumberFormattedLikeAnInteger(slice))
        return std.fmt.parseInt(T, slice, 0);
    // Try to coerce a float to an integer.
    const float = try std.fmt.parseFloat(f128, slice);
    if (@round(float) != float) return error.InvalidNumber;
    if (float > std.math.maxInt(T) or float < std.math.minInt(T)) return error.Overflow;
    return @as(T, @intCast(@as(i128, @intFromFloat(float))));
}

fn freeAllocated(allocator: std.mem.Allocator, token: std.json.Token) void {
    switch (token) {
        .allocated_number, .allocated_string => |slice| {
            allocator.free(slice);
        },
        else => {},
    }
}

pub fn jsonParseWithHex(comptime T: type, allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(source.*))!T {
    const struct_info = @typeInfo(T).@"struct";

    if (.object_begin != try source.next()) return error.UnexpectedToken;

    var r: T = undefined;
    var fields_seen = [_]bool{false} ** struct_info.fields.len;

    while (true) {
        var name_token: ?std.json.Token = try source.nextAllocMax(allocator, .alloc_if_needed, options.max_value_len.?);
        const field_name = switch (name_token.?) {
            inline .string, .allocated_string => |slice| slice,
            .object_end => { // No more fields.
                break;
            },
            else => {
                return error.UnexpectedToken;
            },
        };

        inline for (struct_info.fields, 0..) |field, i| {
            if (field.is_comptime) @compileError("comptime fields are not supported: " ++ @typeName(LightData) ++ "." ++ field.name);
            if (std.mem.eql(u8, field.name, field_name)) {
                // Free the name token now in case we're using an allocator that optimizes freeing the last allocated object.
                // (Recursing into innerParse() might trigger more allocations.)
                freeAllocated(allocator, name_token.?);
                name_token = null;
                if (fields_seen[i]) {
                    switch (options.duplicate_field_behavior) {
                        .use_first => {
                            // Parse and ignore the redundant value.
                            // We don't want to skip the value, because we want type checking.
                            _ = try std.json.innerParse(field.type, allocator, source, options);
                            break;
                        },
                        .@"error" => return error.DuplicateField,
                        .use_last => {},
                    }
                }
                @field(r, field.name) = switch (@typeInfo(field.type)) {
                    .int, .comptime_int => blk: {
                        const token = try source.nextAllocMax(allocator, .alloc_if_needed, options.max_value_len.?);
                        defer freeAllocated(allocator, token);
                        const slice = switch (token) {
                            inline .number, .allocated_number, .string, .allocated_string => |slice| slice,
                            else => return error.UnexpectedToken,
                        };
                        break :blk try sliceToInt(field.type, slice);
                    },
                    else => try std.json.innerParse(field.type, allocator, source, options),
                };
                fields_seen[i] = true;
                break;
            }
        } else {
            // Didn't match anything.
            freeAllocated(allocator, name_token.?);
            if (options.ignore_unknown_fields) {
                try source.skipValue();
            } else {
                return error.UnknownField;
            }
        }
    }
    inline for (@typeInfo(T).@"struct".fields, 0..) |field, i| {
        if (!fields_seen[i]) {
            if (field.default_value) |default_ptr| {
                const default = @as(*align(1) const field.type, @ptrCast(default_ptr)).*;
                @field(r, field.name) = default;
            } else {
                return error.MissingField;
            }
        }
    }
    return r;
}

pub fn spiritGoal(aether: u8) u32 {
    return switch (aether) {
        1 => 2800,
        2 => 9000,
        3 => 22000,
        else => 0,
    };
}

pub fn physDamage(dmg: i32, defense: i32, condition: utils.Condition) i32 {
    if (dmg == 0 or condition.invulnerable)
        return 0;

    const def = if (condition.armor_broken)
        0
    else if (condition.armored)
        defense * 2
    else
        defense;

    return @max(@divFloor(dmg, 5), dmg - def);
}

pub fn magicDamage(dmg: i32, resistance: i32, condition: utils.Condition) i32 {
    if (dmg == 0 or condition.invulnerable)
        return 0;

    return @max(@divFloor(dmg, 5), dmg - resistance);
}

pub const ItemType = enum {
    const weapon_types = [_]ItemType{ .sword, .bow, .staff };
    const armor_types = [_]ItemType{ .leather, .plate, .robe };

    consumable,
    any,
    any_weapon,
    any_armor,
    boots,
    artifact,
    sword,
    bow,
    staff,
    leather,
    plate,
    robe,

    pub fn toString(self: ItemType) []const u8 {
        return switch (self) {
            .boots => "Boots",
            .artifact => "Artifact",
            .consumable => "Consumable",
            .sword => "Sword",
            .bow => "Bow",
            .staff => "Staff",
            .leather => "Leather",
            .plate => "Plate",
            .robe => "Robe",
            .any => "Any",
            .any_weapon => "Any Weapon",
            .any_armor => "Any Armor",
        };
    }

    pub fn typesMatch(self: ItemType, target: ItemType) bool {
        return self == target or self == .any or target == .any or
            std.mem.indexOfScalar(ItemType, &weapon_types, self) != null and target == .any_weapon or
            std.mem.indexOfScalar(ItemType, &weapon_types, target) != null and self == .any_weapon or
            std.mem.indexOfScalar(ItemType, &armor_types, self) != null and target == .any_armor or
            std.mem.indexOfScalar(ItemType, &armor_types, target) != null and self == .any_armor;
    }
};

pub const Currency = enum {
    gold,
    gems,
    crowns,

    pub fn icon(self: Currency) TextureData {
        return switch (self) {
            .gold => .{
                .sheet = "misc",
                .index = 20,
            },
            .gems => .{
                .sheet = "misc",
                .index = 21,
            },
            .crowns => .{
                .sheet = "misc_big",
                .index = 50,
            },
        };
    }
};

pub const AnimationData = struct {
    probability: f32 = 1.0,
    period: f32,
    period_jitter: f32 = 0.0,
    frames: []struct {
        time: f32,
        texture: TextureData,
    },
};

const TextureData = struct {
    sheet: []const u8,
    index: u16,
};

pub const LightData = struct {
    color: u32 = std.math.maxInt(u32),
    intensity: f32 = 0.0,
    radius: f32 = 1.0,
    pulse: f32 = 0.0,
    pulse_speed: f32 = 0.0,

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(source.*))!LightData {
        return jsonParseWithHex(LightData, allocator, source, options);
    }

    pub const jsonStringify = @compileError("Not supported");
};

const ClassStats = struct {
    health: i32,
    mana: i32,
    strength: i16,
    wit: i16,
    defense: i16,
    resistance: i16,
    speed: i16,
    stamina: i16,
    intelligence: i16,
    penetration: i16,
    piercing: i16,
    haste: i16,
    tenacity: i16,
};

pub const AbilityData = struct {
    name: []const u8,
    description: []const u8,
    mana_cost: i16 = 0,
    health_cost: i16 = 0,
    gold_cost: i16 = 0,
    cooldown: f32,
    icon: TextureData,
    projectiles: ?[]ProjectileData = null,
    sound: []const u8 = "",
};

pub const ResourceRarity = enum { common, rare, epic };
pub const ResourceData = struct {
    id: u16,
    name: []const u8,
    description: []const u8,
    rarity: ResourceRarity,
    icon: TextureData,
};

pub const ResourceCost = struct { index: u16, cost: u32 };
pub const ItemCost = struct { data_id: u16, amount: u8 };

pub const TalentType = enum { minor, major, keystone };
pub const TalentLevelCost = struct {
    resource_costs: []ResourceCost,
    item_costs: []ItemCost,
};
pub const TalentRequirement = struct {
    index: u16,
    level: u8,
};
pub const TalentData = struct {
    name: []const u8,
    description: []const u8,
    type: TalentType,
    icon: TextureData,
    max_level: u8,
    level_costs: []TalentLevelCost,
    requires: []TalentRequirement = &.{},
};

const InternalClassData = struct {
    id: u16,
    name: []const u8,
    description: []const u8,
    texture: TextureData,
    item_types: []const ItemType,
    default_items: []const []const u8,
    stats: ClassStats,
    hit_sound: []const u8 = "Unknown",
    death_sound: []const u8 = "Unknown",
    rpc_name: []const u8 = "Unknown",
    abilities: [4]AbilityData,
    light: LightData = .{},
    talents: []TalentData,
};

pub const ClassData = struct {
    id: u16,
    name: []const u8,
    description: []const u8,
    texture: TextureData,
    item_types: []const ItemType,
    default_items: []const u16,
    stats: ClassStats,
    hit_sound: []const u8,
    death_sound: []const u8,
    rpc_name: []const u8,
    abilities: [4]AbilityData,
    light: LightData,
    talents: []TalentData,
};

pub const ContainerData = struct {
    id: u16,
    name: []const u8,
    textures: []const TextureData,
    size_mult: f32 = 1.0,
    item_types: [8]ItemType = @splat(.any),
    light: LightData = .{},
    show_name: bool = false,
    draw_on_ground: bool = false,
    animation: ?AnimationData = null,
};

pub const ProjectileData = struct {
    textures: []const TextureData,
    speed: f32,
    duration: f32,
    phys_dmg: i32 = 0,
    magic_dmg: i32 = 0,
    true_dmg: i32 = 0,
    angle_correction: i8 = 0,
    size_mult: f32 = 1.0,
    rotation: f32 = 0.0,
    piercing: bool = false,
    boomerang: bool = false,
    amplitude: f32 = 0.0,
    frequency: f32 = 0.0,
    magnitude: f32 = 0.0,
    accel: f32 = 0.0,
    accel_delay: f32 = 0.0,
    speed_clamp: f32 = 0.0,
    angle_change: f32 = 0.0,
    angle_change_delay: f32 = 0,
    angle_change_end: f32 = 0,
    angle_change_accel: f32 = 0.0,
    angle_change_accel_delay: f32 = 0,
    angle_change_clamp: f32 = 0.0,
    zero_velocity_delay: f32 = 0,
    heat_seek_speed: f32 = 0.0,
    heat_seek_radius: f32 = 0.0,
    heat_seek_delay: f32 = 0,
    light: LightData = .{},
    conditions: ?[]const TimedCondition = null,
    knockback: bool = false,
    knockback_strength: f32 = 1.0,

    pub fn range(self: ProjectileData) f32 {
        return self.speed * self.duration * 10.0;
    }
};

pub const EnemyData = struct {
    id: u16,
    name: []const u8,
    textures: []const TextureData,
    health: u32 = 0, // Having no health means it can't be hit/die
    defense: i32 = 0,
    resistance: i32 = 0,
    projectiles: ?[]const ProjectileData = null,
    size_mult: f32 = 1.0,
    light: LightData = .{},
    hit_sound: []const u8 = "Unknown",
    death_sound: []const u8 = "Unknown",
    show_name: bool = false,
    draw_on_ground: bool = false,
};

pub const EntityData = struct {
    id: u16,
    name: []const u8,
    textures: []const TextureData,
    health: i32 = 0, // Having no health means it can't be hit/die
    defense: i32 = 0,
    resistance: i32 = 0,
    size_mult: f32 = 1.0,
    light: LightData = .{},
    draw_on_ground: bool = false,
    occupy_square: bool = false,
    full_occupy: bool = false,
    static: bool = true,
    show_name: bool = false,
    block_ground_damage: bool = false,
    block_sink: bool = false,
    is_wall: bool = false,
    hit_sound: []const u8 = "Unknown",
    death_sound: []const u8 = "Unknown",
    animation: ?AnimationData = null,
};

pub const PurchasableData = struct {
    id: u16,
    name: []const u8,
    size_mult: f32 = 1.0,
    textures: []const TextureData,
    light: LightData = .{},
    show_name: bool = true,
    draw_on_ground: bool = false,
};

pub const AllyData = struct {
    id: u16,
    name: []const u8,
    health: i32 = 0, // Having no health means it can't be hit/die
    defense: i32 = 0,
    resistance: i32 = 0,
    size_mult: f32 = 1.0,
    textures: []const TextureData,
    light: LightData = .{},
    show_name: bool = false,
    draw_on_ground: bool = false,
    hit_sound: []const u8 = "Unknown",
    death_sound: []const u8 = "Unknown",
};

pub const GroundData = struct {
    id: u16,
    name: []const u8,
    textures: []const TextureData,
    light: LightData = .{},
    animation: struct {
        type: enum { unset, flow, wave } = .unset,
        delta_x: f32 = 0.0,
        delta_y: f32 = 0.0,
    } = .{},
    sink: bool = false,
    push: bool = false,
    no_walk: bool = false,
    slide_amount: f32 = 0.0,
    speed_mult: f32 = 1.0,
    damage: i16 = 0,
    blend_prio: i16 = 0,
};

pub const StatIncreaseData = union(enum) {
    max_hp: u16,
    max_mp: u16,
    strength: u16,
    wit: u16,
    defense: u16,
    resistance: u16,
    speed: u16,
    stamina: u16,
    intelligence: u16,
    penetration: u16,
    piercing: u16,
    haste: u16,
    tenacity: u16,

    pub fn toString(self: StatIncreaseData) []const u8 {
        return switch (self) {
            .max_hp => "Max HP",
            .max_mp => "Max MP",
            .strength => "Strength",
            .wit => "Wit",
            .defense => "Defense",
            .resistance => "Resistance",
            .speed => "Speed",
            .stamina => "Stamina",
            .intelligence => "Intelligence",
            .penetration => "Penetration",
            .piercing => "Piercing",
            .haste => "Haste",
            .tenacity => "Tenacity",
        };
    }

    pub fn toControlCode(self: StatIncreaseData) []const u8 {
        return switch (self) {
            .max_hp => "&img=\"misc_big,40\"",
            .max_mp => "&img=\"misc_big,39\"",
            .strength => "&img=\"misc_big,32\"",
            .defense => "&img=\"misc_big,33\"",
            .speed => "&img=\"misc_big,34\"",
            .stamina => "&img=\"misc_big,36\"",
            .wit => "&img=\"misc_big,35\"",
            .resistance => "&img=\"misc_big,57\"",
            .intelligence => "&img=\"misc_big,59\"",
            .penetration => "&img=\"misc_big,38\"",
            .piercing => "&img=\"misc_big,60\"",
            .haste => "&img=\"misc_big,58\"",
            .tenacity => "&img=\"misc_big,37\"",
        };
    }

    pub fn amount(self: StatIncreaseData) u16 {
        return switch (self) {
            inline else => |inner| inner,
        };
    }
};

pub const TimedCondition = struct {
    type: utils.ConditionEnum,
    duration: f32,
};

pub const ActivationData = union(enum) {
    heal: i32,
    magic: i32,
    create_entity: []const u8,
    create_enemy: []const u8,
    create_portal: []const u8,
    heal_nova: struct { amount: i32, radius: f32 },
    magic_nova: struct { amount: i32, radius: f32 },
    stat_boost_self: struct { stat_incr: StatIncreaseData, amount: i16, duration: f32 },
    stat_boost_aura: struct { stat_incr: StatIncreaseData, amount: i16, duration: f32, radius: f32 },
    condition_effect_self: TimedCondition,
    condition_effect_aura: struct { cond: TimedCondition, radius: f32 },
};

pub const ItemRarity = enum { common, rare, epic, legendary, mythic };
pub const ItemData = struct {
    id: u16,
    name: []const u8,
    description: []const u8 = "",
    item_type: ItemType,
    rarity: ItemRarity = .common,
    texture: TextureData,
    fire_rate: f32 = 1.0,
    projectile_count: u8 = 1,
    projectile: ?ProjectileData = null,
    stat_increases: ?[]const StatIncreaseData = null,
    activations: ?[]const ActivationData = null,
    arc_gap: f32 = 5.0,
    mana_cost: i16 = 0,
    health_cost: i16 = 0,
    gold_cost: i16 = 0,
    cooldown: f32 = 0.0,
    consumable: bool = false,
    untradeable: bool = false,
    bag_type: enum { brown, purple, blue, white } = .brown,
    sound: []const u8 = "Unknown",
};

pub const CardRarity = enum { common, rare, epic, legendary, mythic };
pub const CardData = struct {
    id: u16,
    name: []const u8,
    rarity: CardRarity,
    description: []const u8,
};

pub const PortalData = struct {
    id: u16,
    name: []const u8,
    textures: []const TextureData,
    draw_on_ground: bool = false,
    light: LightData = .{},
    size_mult: f32 = 1.0,
    show_name: bool = true,
    animation: ?AnimationData = null,
};

pub const RegionData = struct {
    id: u16,
    name: []const u8,
    color: u32,

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(source.*))!RegionData {
        return jsonParseWithHex(RegionData, allocator, source, options);
    }

    pub const jsonStringify = @compileError("Not supported");
};

pub const StringContext = struct {
    pub fn hash(_: @This(), s: []const u8) u64 {
        var buf: [1024]u8 = undefined; // bad
        return std.hash.Wyhash.hash(0, std.ascii.lowerString(&buf, s));
    }

    pub fn eql(_: @This(), a: []const u8, b: []const u8) bool {
        if (a.len != b.len) return false;
        if (a.len == 0 or a.ptr == b.ptr) return true;

        for (a, b) |a_elem, b_elem| {
            if (a_elem != b_elem and a_elem != std.ascii.toLower(b_elem)) return false;
        }
        return true;
    }
};
