const std = @import("std");

const ziggy = @import("ziggy");

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

fn parseGeneric(allocator: std.mem.Allocator, path: []const u8, comptime DataType: type, data_maps: *Maps(DataType)) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const file_data = try file.readToEndAllocOptions(allocator, std.math.maxInt(u32), null, @alignOf(u8), 0);
    defer allocator.free(file_data);

    const data_slice = try ziggy.parseLeaky([]DataType, allocator, file_data, .{});
    for (data_slice) |data| {
        const id_res = try data_maps.from_id.getOrPut(allocator, data.id);
        if (id_res.found_existing) {
            std.log.err("Duplicate id for {s}: wanted to override {s}", .{ data.name, id_res.value_ptr.name });
            std.posix.exit(0);
        }
        id_res.value_ptr.* = data;

        const name_res = try data_maps.from_name.getOrPut(allocator, data.name);
        if (name_res.found_existing) {
            std.log.err("Duplicate name for {s}", .{data.name});
            std.posix.exit(0);
        }
        name_res.value_ptr.* = data;
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
            &resource,
        }) |data_maps| {
            if (data_maps.from_id.capacity() > 0) data_maps.from_id.rehash(dummy_id_ctx);
            if (data_maps.from_name.capacity() > 0) data_maps.from_name.rehash(dummy_name_ctx);
        }
    }

    arena = .init(allocator);
    const arena_allocator = arena.allocator();

    try parseGeneric(arena_allocator, "./assets/data/cards.ziggy", CardData, &card);
    try parseGeneric(arena_allocator, "./assets/data/items.ziggy", ItemData, &item);
    try parseGeneric(arena_allocator, "./assets/data/containers.ziggy", ContainerData, &container);
    try parseGeneric(arena_allocator, "./assets/data/enemies.ziggy", EnemyData, &enemy);
    try parseGeneric(arena_allocator, "./assets/data/entities.ziggy", EntityData, &entity);
    try parseGeneric(arena_allocator, "./assets/data/walls.ziggy", EntityData, &entity);
    try parseGeneric(arena_allocator, "./assets/data/ground.ziggy", GroundData, &ground);
    try parseGeneric(arena_allocator, "./assets/data/portals.ziggy", PortalData, &portal);
    try parseGeneric(arena_allocator, "./assets/data/regions.ziggy", RegionData, &region);
    try parseGeneric(arena_allocator, "./assets/data/purchasables.ziggy", PurchasableData, &purchasable);
    try parseGeneric(arena_allocator, "./assets/data/allies.ziggy", AllyData, &ally);
    try parseGeneric(arena_allocator, "./assets/data/resources.ziggy", ResourceData, &resource);
    try parseGeneric(arena_allocator, "./assets/data/classes.ziggy", ClassData, &class);
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

// TODO: this is garbage
fn processMacros(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    const size = @min(8192, text.len * 3);
    var front_buf = try allocator.alloc(u8, size);
    defer allocator.free(front_buf);
    @memset(front_buf, 0);
    @memcpy(front_buf[0..text.len], text);
    var back_buf = try allocator.alloc(u8, size);
    defer allocator.free(back_buf);
    @memset(back_buf, 0);
    @memcpy(back_buf[0..text.len], text);
    var front = true;
    inline for (.{
        .{ "$hptxt", "&type=\"bold_it\"&col=\"20AC20\"" },
        .{ "$mptxt", "&type=\"bold_it\"&col=\"1C40FF\"" },
        .{ "$strtxt", "&type=\"bold_it\"&col=\"FF6C32\"" },
        .{ "$deftxt", "&type=\"bold_it\"&col=\"FF9670\"" },
        .{ "$wittxt", "&type=\"bold_it\"&col=\"A15AFF\"" },
        .{ "$restxt", "&type=\"bold_it\"&col=\"D65BFF\"" },
        .{ "$statxt", "&type=\"bold_it\"&col=\"C45860\"" },
        .{ "$inttxt", "&type=\"bold_it\"&col=\"6080FF\"" },
        .{ "$spdtxt", "&type=\"bold_it\"&col=\"C45860\"" },
        .{ "$hsttxt", "&type=\"bold_it\"&col=\"60FFAC\"" },
        .{ "$multitxt", "&type=\"bold_it\"&col=\"FFE770\"" },
        .{ "$footnotetxt", "&type=\"med_it\"&size=\"10\"&col=\"736562\"" },
        .{ "$hpicon", "&space" ++ comptime StatIncreaseData.toControlCode(.{ .max_hp = undefined }) },
        .{ "$mpicon", "&space" ++ comptime StatIncreaseData.toControlCode(.{ .max_mp = undefined }) },
        .{ "$stricon", "&space" ++ comptime StatIncreaseData.toControlCode(.{ .strength = undefined }) },
        .{ "$deficon", "&space" ++ comptime StatIncreaseData.toControlCode(.{ .defense = undefined }) },
        .{ "$witicon", "&space" ++ comptime StatIncreaseData.toControlCode(.{ .wit = undefined }) },
        .{ "$resicon", "&space" ++ comptime StatIncreaseData.toControlCode(.{ .resistance = undefined }) },
        .{ "$staicon", "&space" ++ comptime StatIncreaseData.toControlCode(.{ .stamina = undefined }) },
        .{ "$inticon", "&space" ++ comptime StatIncreaseData.toControlCode(.{ .intelligence = undefined }) },
        .{ "$spdicon", "&space" ++ comptime StatIncreaseData.toControlCode(.{ .speed = undefined }) },
        .{ "$hsticon", "&space" ++ comptime StatIncreaseData.toControlCode(.{ .haste = undefined }) },
    }) |replace| {
        _ = std.mem.replace(
            u8,
            std.mem.sliceTo(if (front) front_buf else back_buf, 0),
            replace[0],
            replace[1],
            if (front) back_buf else front_buf,
        );
        front = !front;
    }
    return try allocator.dupe(u8, std.mem.sliceTo(if (front) front_buf else back_buf, 0));
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
            .gold => .{ .sheet = "misc", .index = 20 },
            .gems => .{ .sheet = "misc", .index = 21 },
            .crowns => .{ .sheet = "misc_big", .index = 50 },
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

    pub const ziggy_options = struct {
        pub fn parse(parser: *ziggy.Parser, first_tok: ziggy.Tokenizer.Token) ziggy.Parser.Error!TextureData {
            const map = try parser.parseValue(ziggy.dynamic.Map(u16), first_tok);
            switch (map.fields.count()) {
                0 => @panic("You can't provide an empty map"),
                1 => return .{ .sheet = map.fields.keys()[0], .index = map.fields.values()[0] },
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

    pub const ziggy_options = struct {
        pub fn parse(parser: *ziggy.Parser, first_tok: ziggy.Tokenizer.Token) !AbilityData {
            var ability = try parser.parseStruct(AbilityData, first_tok);
            ability.description = try processMacros(parser.gpa, ability.description);
            return ability;
        }
    };
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
        pub fn parse(parser: *ziggy.Parser, first_tok: ziggy.Tokenizer.Token) ziggy.Parser.Error!TalentResourceCost {
            const map = try parser.parseValue(ziggy.dynamic.Map(u16), first_tok);
            switch (map.fields.count()) {
                0 => @panic("You can't provide an empty map"),
                1 => return .{ .name = map.fields.keys()[0], .amount = map.fields.values()[0] },
                else => @panic("You can only map one value in a TalentResourceCost"),
            }
        }
    };
};
pub const TalentRequirement = struct { index: u16, level_per_aether: u8 };
pub const TalentData = struct {
    name: []const u8,
    description: []const u8,
    icon: TextureData,
    max_level: []const u16, // This won't ever be >255, but ziggy breaks otherwise, thinking it's a string...
    level_costs: []const []const TalentResourceCost,
    requires: []const TalentRequirement = &.{},
    stat_increases_per_level: ?[]const StatIncreaseData = null,
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
    rpc_name: []const u8 = "Unknown",
    abilities: [4]AbilityData,
    light: LightData = .{},
    talents: []const TalentData,
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
    animations: ?[]const FrameData = null,
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
    hit_sound: []const u8 = "Unknown.mp3",
    death_sound: []const u8 = "Unknown.mp3",
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
    hit_sound: []const u8 = "Unknown.mp3",
    death_sound: []const u8 = "Unknown.mp3",
    animations: ?[]FrameData = null,
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
};

pub const StatIncreaseData = union(enum) {
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
            .haste => "Haste",
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
            .haste => "&img=\"misc_big,58\"",
        };
    }

    pub fn amount(self: StatIncreaseData) u16 {
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
    sound: []const u8 = "Unknown.mp3",

    pub const ziggy_options = struct {
        pub fn parse(parser: *ziggy.Parser, first_tok: ziggy.Tokenizer.Token) !ItemData {
            var item_data = try parser.parseStruct(ItemData, first_tok);
            item_data.description = try processMacros(parser.gpa, item_data.description);
            return item_data;
        }
    };
};

pub const CardRarity = enum { common, rare, epic, legendary, mythic };
pub const CardData = struct {
    id: u16,
    name: []const u8,
    rarity: CardRarity,
    description: []const u8,
    max_stack: u16 = 0,

    pub const ziggy_options = struct {
        pub fn parse(parser: *ziggy.Parser, first_tok: ziggy.Tokenizer.Token) !CardData {
            var card_data = try parser.parseStruct(CardData, first_tok);
            card_data.description = try processMacros(parser.gpa, card_data.description);
            return card_data;
        }
    };
};

pub const PortalData = struct {
    id: u16,
    name: []const u8,
    textures: []const TextureData,
    draw_on_ground: bool = false,
    light: LightData = .{},
    size_mult: f32 = 1.0,
    show_name: bool = true,
    animations: ?[]FrameData = null,
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
        for (a, b) |a_elem, b_elem| if (a_elem != b_elem and a_elem != std.ascii.toLower(b_elem)) return false;
        return true;
    }
};
