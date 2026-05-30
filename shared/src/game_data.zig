const std = @import("std");

const ziggy = @import("ziggy");

const network_data = @import("network_data.zig");
const utils = @import("utils.zig");

const ReplacePair = struct { base: []const u8, replace: []const u8 };
const macro_mappings = b: {
    var ret: []const ReplacePair = &.{};
    for (@typeInfo(Stat).@"enum".fields) |field| {
        const stat = @field(Stat, field.name);
        const shorthand = stat.shorthand();
        ret = ret ++ &[_]ReplacePair{.{
            .base = "$" ++ shorthand ++ "txt",
            .replace = std.fmt.comptimePrint("&type=\"bold_it\"&col=\"{X:0>6}\"", .{stat.color()}),
        }};
        ret = ret ++ &[_]ReplacePair{.{
            .base = "$" ++ shorthand ++ "icon",
            .replace = "&space" ++ stat.icon().comptimeControlCode(),
        }};
    }
    ret = ret ++ &[_]ReplacePair{
        .{ .base = "$multitxt", .replace = "&type=\"bold_it\"&col=\"FFE770\"" },
        .{ .base = "$footnotetxt", .replace = "&type=\"med_it\"&size=\"10\"&col=\"736562\"" },
    };
    break :b ret;
};

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
pub var ally: Maps(AllyData) = .{};

var arena: std.heap.ArenaAllocator = undefined;

pub fn Maps(comptime T: type) type {
    return struct {
        from_id: std.AutoHashMapUnmanaged(u16, T) = .empty,
        from_name: std.HashMapUnmanaged([]const u8, T, StringContext, 80) = .empty,
    };
}

fn parseGeneric(
    allocator: std.mem.Allocator,
    io: std.Io,
    stdout_wtr: *std.Io.Writer,
    path: []const u8,
    comptime T: type,
    data_maps: *Maps(T),
) !void {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    var read_buf: [4096]u8 = undefined;
    var reader = file.reader(io, &read_buf);

    const bytes = try reader.interface.allocRemainingAlignedSentinel(allocator, .unlimited, .of(u8), 0);
    defer allocator.free(bytes);

    var meta: ziggy.Deserializer.Meta = .init;
    const slice = ziggy.deserializeLeaky([]T, allocator, bytes, &meta, .{ .copy_strings = .always }) catch |e| {
        if (e != error.OutOfMemory) {
            try meta.reportErrors(allocator, .{}, path, bytes, e, stdout_wtr);
            try stdout_wtr.flush();
        }
        return e;
    };
    for (slice) |*val| {
        if (std.meta.hasFn(T, "postProcess"))
            try val.postProcess(allocator);

        const id_res = try data_maps.from_id.getOrPut(allocator, val.id);
        if (id_res.found_existing) {
            std.log.err("Duplicate id for {s}: wanted to override {s}", .{ val.name, id_res.value_ptr.name });
            std.process.exit(0);
        }
        id_res.value_ptr.* = val.*;

        const name_res = try data_maps.from_name.getOrPut(allocator, val.name);
        if (name_res.found_existing) {
            std.log.err("Duplicate name for {s}", .{val.name});
            std.process.exit(0);
        }
        name_res.value_ptr.* = val.*;
    }
}

pub fn init(allocator: std.mem.Allocator, io: std.Io) !void {
    arena = .init(allocator);
    const arena_allocator = arena.allocator();
    errdefer arena.deinit();

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
            &ally,
            &resource,
        }) |data_maps| {
            if (data_maps.from_id.capacity() > 0) data_maps.from_id.rehash(dummy_id_ctx);
            if (data_maps.from_name.capacity() > 0) data_maps.from_name.rehash(dummy_name_ctx);
        }
    }

    var stdout: std.Io.File = .stdout();
    var stdout_buf: [4096]u8 = undefined;
    var stdout_wtr = stdout.writer(io, &stdout_buf);

    try parseGeneric(arena_allocator, io, &stdout_wtr.interface, "./assets/shared/data/cards.ziggy", CardData, &card);
    try parseGeneric(arena_allocator, io, &stdout_wtr.interface, "./assets/shared/data/items.ziggy", ItemData, &item);
    try parseGeneric(arena_allocator, io, &stdout_wtr.interface, "./assets/shared/data/containers.ziggy", ContainerData, &container);
    try parseGeneric(arena_allocator, io, &stdout_wtr.interface, "./assets/shared/data/enemies.ziggy", EnemyData, &enemy);
    try parseGeneric(arena_allocator, io, &stdout_wtr.interface, "./assets/shared/data/entities.ziggy", EntityData, &entity);
    try parseGeneric(arena_allocator, io, &stdout_wtr.interface, "./assets/shared/data/walls.ziggy", EntityData, &entity);
    try parseGeneric(arena_allocator, io, &stdout_wtr.interface, "./assets/shared/data/ground.ziggy", GroundData, &ground);
    try parseGeneric(arena_allocator, io, &stdout_wtr.interface, "./assets/shared/data/portals.ziggy", PortalData, &portal);
    try parseGeneric(arena_allocator, io, &stdout_wtr.interface, "./assets/shared/data/regions.ziggy", RegionData, &region);
    try parseGeneric(arena_allocator, io, &stdout_wtr.interface, "./assets/shared/data/allies.ziggy", AllyData, &ally);
    try parseGeneric(arena_allocator, io, &stdout_wtr.interface, "./assets/shared/data/resources.ziggy", ResourceData, &resource);
    try parseGeneric(arena_allocator, io, &stdout_wtr.interface, "./assets/shared/data/classes.ziggy", ClassData, &class);
}

pub fn deinit() void {
    arena.deinit();
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
    if (dmg == 0 or condition.invulnerable) return 0;

    const def = if (condition.armor_broken)
        0
    else if (condition.armored)
        defense * 2
    else
        defense;

    return @max(@divFloor(dmg, 5), dmg - def);
}

pub fn magicDamage(dmg: i32, resistance: i32, condition: utils.Condition) i32 {
    if (dmg == 0 or condition.invulnerable) return 0;
    return @max(@divFloor(dmg, 5), dmg - resistance);
}

fn processMacros(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);

    var slide: usize = 0;
    slide: while (slide < text.len) {
        for (macro_mappings) |map|
            if (std.mem.startsWith(u8, text[slide..], map.base)) {
                try out.writer.writeAll(map.replace);
                slide += map.base.len;
                continue :slide;
            };

        try out.writer.writeByte(text[slide]);
        slide += 1;
    }

    return out.written();
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

    pub fn icon(self: Currency) TextureData {
        return switch (self) {
            .gold => .{ .sheet = "misc", .index = 0 },
            .gems => .{ .sheet = "misc", .index = 1 },
        };
    }
};

pub const FrameData = struct {
    time: f32,
    texture: TextureData,
};

pub const TextureData = struct {
    sheet: []const u8,
    index: u16,

    pub fn controlCode(self: TextureData, buf: []u8) []const u8 {
        // maybe bubble the error up later... I don't really see an use for it now
        return std.fmt.bufPrint(buf, "&img=\"{s},{d}\"", .{ self.sheet, self.index }) catch "Buffer overflow";
    }

    pub fn comptimeControlCode(self: TextureData) []const u8 {
        return std.fmt.comptimePrint("&img=\"{s},{d}\"", .{ self.sheet, self.index });
    }

    pub const ziggy_options = struct {
        pub fn deserialize(d: *const ziggy.Deserializer, first_tok: ziggy.Tokenizer.Token, top_lvl: bool) ziggy.Deserializer.Error!TextureData {
            const map = try d.deserializeOne(ziggy.Dynamic, first_tok, top_lvl);
            if (map != .kv) @panic("Invalid TextureData format");
            switch (map.kv.fields.count()) {
                0 => @panic("You can't provide an empty map"),
                1 => return .{
                    .sheet = try arena.allocator().dupe(u8, map.kv.fields.keys()[0]),
                    .index = @intCast(map.kv.fields.values()[0].integer),
                },
                else => @panic("You can only map one value in a TextureData"),
            }
        }
    };
};

pub const LightData = struct {
    color: u32 = std.math.maxInt(u32),
    intensity: f32 = 0.0,
    radius: f32 = 1.0,
    pulse: f32 = 0.0,
    pulse_speed: f32 = 0.0,
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
    haste: i16,
};

pub const AbilityData = struct {
    name: []const u8,
    description: []const u8,
    mana_cost: u16 = 0,
    health_cost: u16 = 0,
    gold_cost: u16 = 0,
    cooldown: f32,
    icon: TextureData,
    projectiles: ?[]ProjectileData = null,
    sound: []const u8 = "Unknown.mp3",

    pub fn postProcess(self: *AbilityData, allocator: std.mem.Allocator) !void {
        self.description = try processMacros(allocator, self.description);
    }
};

pub const ResourceRarity = enum { common, rare, epic };
pub const ResourceData = struct {
    id: u16,
    name: []const u8,
    rarity: ResourceRarity,
    icon: TextureData,
};

pub const TalentResourceCost = struct {
    name: []const u8,
    amount: u32,

    pub const ziggy_options = struct {
        pub fn deserialize(d: *const ziggy.Deserializer, first_tok: ziggy.Tokenizer.Token, top_lvl: bool) ziggy.Deserializer.Error!TalentResourceCost {
            const map = try d.deserializeOne(ziggy.Dynamic, first_tok, top_lvl);
            if (map != .kv) @panic("Invalid TalentResourceCost format");
            switch (map.kv.fields.count()) {
                0 => @panic("You can't provide an empty map"),
                1 => return .{
                    .name = try arena.allocator().dupe(u8, map.kv.fields.keys()[0]),
                    .amount = @intCast(map.kv.fields.values()[0].integer),
                },
                else => @panic("You can only map one value in a TalentResourceCost"),
            }
        }
    };
};
pub const TalentRequirement = struct { index: u16, level_per_aether: u8 };
pub const TalentType = enum { keystone, ability, minor };
pub const TalentData = struct {
    name: []const u8,
    description: []const u8,
    icon: TextureData,
    type: TalentType,
    max_level: []const u16, // This won't ever be >255, but ziggy breaks otherwise, thinking it's a string...
    level_costs: []const []const TalentResourceCost,
    requires: []const TalentRequirement = &.{},
    flat_stats: ?[]const StatIncreaseData = null,
    perc_stats: ?[]const StatIncreaseDataPerc = null,

    pub fn postProcess(self: *TalentData, allocator: std.mem.Allocator) !void {
        self.description = try processMacros(allocator, self.description);
    }
};

pub const ClassData = struct {
    id: u16,
    name: []const u8,
    description: []const u8,
    texture: TextureData,
    item_types: []const ItemType,
    default_items: []const []const u8,
    stats: ClassStats,
    hit_sound: []const u8 = "Unknown.mp3",
    death_sound: []const u8 = "Unknown.mp3",
    abilities: [4]AbilityData,
    light: LightData = .{},
    float: FloatData = .{},
    talents: []TalentData,

    pub fn postProcess(self: *ClassData, allocator: std.mem.Allocator) !void {
        self.description = try processMacros(allocator, self.description);
        for (&self.abilities) |*abil| try abil.postProcess(allocator);
        for (self.talents) |*talent| try talent.postProcess(allocator);
    }
};

pub const ContainerData = struct {
    id: u16,
    name: []const u8,
    textures: []const TextureData,
    size_mult: f32 = 1.0,
    item_types: [8]ItemType = @splat(.any),
    light: LightData = .{},
    float: FloatData = .{},
    show_name: bool = false,
    draw_on_ground: bool = false,
    animations: ?[]const FrameData = null,
    playable_animations: ?[]const []const FrameData = null,
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
    float: FloatData = .{},
    conditions: ?[]const TimedCondition = null,

    pub fn range(self: ProjectileData) f32 {
        const base_range = self.speed * self.duration * 10.0;
        return if (self.boomerang) base_range / 2.0 else base_range;
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
    float: FloatData = .{},
    hit_sound: []const u8 = "Unknown.mp3",
    death_sound: []const u8 = "Unknown.mp3",
    show_name: bool = false,
    draw_on_ground: bool = false,
    elite: bool = false,
};

pub const FloatData = struct {
    time: f32 = 0.0,
    height: f32 = 0.0,
};

pub const SubtextureData = struct {
    textures: []const TextureData,
    animations: ?[]const FrameData = null,
    x_offset: i8 = 0,
    y_offset: i8 = 0,
    size_mult: f32 = 1.0,
    rotation: f32 = 0.0,
    light: LightData = .{},
    float: FloatData = .{},
};

pub const ShowEffData = struct {
    effect: network_data.ShowEffect,
    radius: f32,
    cooldown: f32,
    color: u32,
};

pub const EntityData = struct {
    id: u16,
    name: []const u8,
    textures: []const TextureData,
    subtexture: ?SubtextureData = null,
    minimap_color: u32 = std.math.maxInt(u32),
    health: i32 = 0, // Having no health means it can't be hit/die
    defense: i32 = 0,
    resistance: i32 = 0,
    size_mult: f32 = 1.0,
    rotation: f32 = 0.0,
    light: LightData = .{},
    float: FloatData = .{},
    draw_on_ground: bool = false,
    occupy_square: bool = false,
    full_occupy: bool = false,
    static: bool = true,
    show_name: bool = false,
    block_ground_damage: bool = false,
    block_sink: bool = false,
    is_wall: bool = false,
    hit_sound: []const u8 = "Unknown.mp3",
    death_sound: []const u8 = "Unknown.mp3",
    show_effects: ?[]const ShowEffData = null,
    animations: ?[]const FrameData = null,
    playable_animations: ?[]const []const FrameData = null,
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
    float: FloatData = .{},
    show_name: bool = false,
    draw_on_ground: bool = false,
    hit_sound: []const u8 = "Unknown.mp3",
    death_sound: []const u8 = "Unknown.mp3",
};

pub const GroundData = struct {
    id: u16,
    name: []const u8,
    textures: []const TextureData,
    rug_textures: ?struct {
        corners: []const TextureData,
        inner_corners: []const TextureData,
        edges: []const TextureData,
    } = null,
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
    disable_blend: bool = false,
    anim_sync_id: u16 = std.math.maxInt(u16),
    animations: ?[]const FrameData = null,
};

pub const Stat = enum(u8) {
    max_hp = 0,
    max_mp = 1,
    strength = 2,
    wit = 3,
    defense = 4,
    resistance = 5,
    speed = 6,
    stamina = 7,
    intelligence = 8,
    haste = 9,

    pub fn name(self: Stat) []const u8 {
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
            .haste => "Haste",
        };
    }

    pub fn shorthand(self: Stat) []const u8 {
        return switch (self) {
            .max_hp => "hp",
            .max_mp => "mp",
            .strength => "str",
            .wit => "wit",
            .defense => "def",
            .resistance => "res",
            .speed => "spd",
            .stamina => "sta",
            .intelligence => "int",
            .haste => "hst",
        };
    }

    pub fn color(self: Stat) u24 {
        return switch (self) {
            .max_hp => 0x20AC20,
            .max_mp => 0x1C40FF,
            .strength => 0xFF6C32,
            .wit => 0xA15AFF,
            .defense => 0xFF9670,
            .resistance => 0xD65BFF,
            .speed => 0xC45860,
            .stamina => 0xC45860,
            .intelligence => 0x6080FF,
            .haste => 0x60FFAC,
        };
    }

    pub fn icon(self: Stat) TextureData {
        return switch (self) {
            .max_hp => .{ .sheet = "misc_big", .index = 0 },
            .max_mp => .{ .sheet = "misc_big", .index = 1 },
            .strength => .{ .sheet = "misc_big", .index = 2 },
            .wit => .{ .sheet = "misc_big", .index = 3 },
            .defense => .{ .sheet = "misc_big", .index = 4 },
            .resistance => .{ .sheet = "misc_big", .index = 5 },
            .stamina => .{ .sheet = "misc_big", .index = 6 },
            .intelligence => .{ .sheet = "misc_big", .index = 7 },
            .speed => .{ .sheet = "misc_big", .index = 8 },
            .haste => .{ .sheet = "misc_big", .index = 9 },
        };
    }
};

pub const StatIncreaseData = union(Stat) {
    max_hp: struct { amount: u16 },
    max_mp: struct { amount: u16 },
    strength: struct { amount: u16 },
    wit: struct { amount: u16 },
    defense: struct { amount: u16 },
    resistance: struct { amount: u16 },
    speed: struct { amount: u16 },
    stamina: struct { amount: u16 },
    intelligence: struct { amount: u16 },
    haste: struct { amount: u16 },
};

pub const StatIncreaseDataPerc = union(enum) {
    max_hp: struct { amount: f32 },
    max_mp: struct { amount: f32 },
    strength: struct { amount: f32 },
    wit: struct { amount: f32 },
    defense: struct { amount: f32 },
    resistance: struct { amount: f32 },
    speed: struct { amount: f32 },
    stamina: struct { amount: f32 },
    intelligence: struct { amount: f32 },
    haste: struct { amount: f32 },

    pub fn toString(self: StatIncreaseDataPerc) []const u8 {
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
            .haste => "Haste",
        };
    }

    pub fn toControlCode(self: StatIncreaseDataPerc) []const u8 {
        return switch (self) {
            .max_hp => "&img=\"misc_big,0\"",
            .max_mp => "&img=\"misc_big,1\"",
            .strength => "&img=\"misc_big,2\"",
            .wit => "&img=\"misc_big,3\"",
            .defense => "&img=\"misc_big,4\"",
            .resistance => "&img=\"misc_big,5\"",
            .stamina => "&img=\"misc_big,6\"",
            .intelligence => "&img=\"misc_big,7\"",
            .speed => "&img=\"misc_big,8\"",
            .haste => "&img=\"misc_big,9\"",
        };
    }

    pub fn amount(self: StatIncreaseDataPerc) f32 {
        return switch (self) {
            inline else => |inner| inner.amount,
        };
    }
};

pub const TimedCondition = struct {
    type: utils.ConditionEnum,
    duration: f32,
};

pub const ActivationData = union(enum) {
    heal: struct { amount: i32 },
    magic: struct { amount: i32 },
    heal_nova: struct { amount: i32, radius: f32 },
    magic_nova: struct { amount: i32, radius: f32 },
    create_ally: struct { name: []const u8 },
    create_portal: struct { name: []const u8 },
};

pub const ItemRarity = enum {
    common,
    rare,
    epic,
    legendary,
    mythic,

    pub fn containerDataId(self: ItemRarity) u16 {
        return switch (self) {
            .common => 0,
            .rare => 1,
            .epic => 2,
            .legendary => 3,
            .mythic => 4,
        };
    }
};
pub const ItemResourceCost = struct { chance: f32, amount: u16 };
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
    perc_stat_increases: ?[]const StatIncreaseDataPerc = null,
    activations: ?[]const ActivationData = null,
    arc_gap: f32 = 5.0,
    mana_cost: ?ItemResourceCost = null,
    health_cost: ?ItemResourceCost = null,
    gold_cost: ?ItemResourceCost = null,
    cooldown: f32 = 0.0,
    untradeable: bool = false,
    ephemeral: bool = false,
    max_stack: u16 = 0,
    level_spirits: u16 = 0,
    level_transform_item: ?[]const u8 = null,
    health_gain_incr: f32 = 0.0,
    mana_gain_incr: f32 = 0.0,
    env_dmg_reduction: f32 = 0.0,
    sound: []const u8 = "Unknown.mp3",

    pub fn postProcess(self: *ItemData, allocator: std.mem.Allocator) !void {
        self.description = try processMacros(allocator, self.description);
    }
};

pub const CardRarity = enum { common, rare, epic, legendary, mythic };
pub const CardData = struct {
    id: u16,
    name: []const u8,
    rarity: CardRarity,
    description: []const u8,
    max_stack: u16 = 0,
    flat_stats: ?[]const StatIncreaseData = null,
    perc_stats: ?[]const StatIncreaseDataPerc = null,

    pub fn postProcess(self: *CardData, allocator: std.mem.Allocator) !void {
        self.description = try processMacros(allocator, self.description);
    }
};

pub const PortalData = struct {
    id: u16,
    name: []const u8,
    textures: []const TextureData,
    draw_on_ground: bool = false,
    light: LightData = .{},
    float: FloatData = .{},
    size_mult: f32 = 1.0,
    show_name: bool = true,
    animations: ?[]const FrameData = null,
    playable_animations: ?[]const []const FrameData = null,
};

pub const RegionData = struct {
    id: u16,
    name: []const u8,
    color: u32,
};

pub const StringContext = struct {
    pub fn hash(_: @This(), s: []const u8) u64 {
        var buf: [1024]u8 = undefined; // bad
        return std.hash.Wyhash.hash(0, std.ascii.lowerString(&buf, s));
    }

    pub fn eql(_: @This(), a: []const u8, b: []const u8) bool {
        if (a.len != b.len) return false;
        if (a.len == 0 or a.ptr == b.ptr) return true;
        for (a, b) |a_elem, b_elem| if (std.ascii.toLower(a_elem) != std.ascii.toLower(b_elem)) return false;
        return true;
    }
};
