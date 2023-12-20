const std = @import("std");
const xml = @import("xml.zig");
const utils = @import("utils.zig");
const asset_dir = @import("build_options").asset_dir;

pub const ClassType = enum(u8) {
    cave_wall,
    character,
    character_changer,
    closed_vault_chest,
    connected_wall,
    container,
    game_object,
    guild_board,
    guild_chronicle,
    guild_hall_portal,
    guild_merchant,
    guild_register,
    merchant,
    money_changer,
    name_changer,
    reskin_vendor,
    one_way_container,
    player,
    portal,
    projectile,
    sign,
    spider_web,
    stalagmite,
    wall,

    const map = std.ComptimeStringMap(ClassType, .{
        .{ "CaveWall", .cave_wall },
        .{ "Character", .character },
        .{ "CharacterChanger", .character_changer },
        .{ "ClosedVaultChest", .closed_vault_chest },
        .{ "ConnectedWall", .connected_wall },
        .{ "Container", .container },
        .{ "GameObject", .game_object },
        .{ "GuildBoard", .guild_board },
        .{ "GuildChronicle", .guild_chronicle },
        .{ "GuildHallPortal", .guild_hall_portal },
        .{ "GuildMerchant", .guild_merchant },
        .{ "GuildRegister", .guild_register },
        .{ "Merchant", .merchant },
        .{ "MoneyChanger", .money_changer },
        .{ "NameChanger", .name_changer },
        .{ "ReskinVendor", .reskin_vendor },
        .{ "OneWayContainer", .one_way_container },
        .{ "Player", .player },
        .{ "Portal", .portal },
        .{ "Projectile", .projectile },
        .{ "Sign", .sign },
        .{ "SpiderWeb", .spider_web },
        .{ "Stalagmite", .stalagmite },
        .{ "Wall", .wall },
    });

    pub fn fromString(str: []const u8) ClassType {
        return map.get(str) orelse .game_object;
    }

    pub fn isInteractive(class: ClassType) bool {
        return class == .portal or
            class == .container or
            class == .merchant or
            class == .guild_board or
            class == .guild_chronicle or
            class == .guild_register or
            class == .guild_merchant;
    }

    pub fn hasPanel(class: ClassType) bool {
        return class == .guild_board or
            class == .guild_chronicle or
            class == .guild_merchant or
            class == .guild_register;
    }
};

pub const TextureData = struct {
    sheet: []const u8,
    index: u16,
    animated: bool,

    pub fn parse(node: xml.Node, allocator: std.mem.Allocator, animated: bool) !TextureData {
        return TextureData{
            .sheet = try node.getValueAlloc("Sheet", allocator, "Unknown"),
            .index = try node.getValueInt("Index", u16, 0),
            .animated = animated,
        };
    }
};

pub const CharacterSkin = struct {
    obj_type: u16,
    name: []const u8,
    texture: TextureData,

    pub fn parse(node: xml.Node, allocator: std.mem.Allocator) CharacterSkin {
        return CharacterSkin{
            .objType = try node.getAttributeInt("type", u16, 0),
            .name = try node.getAttributeAlloc("id", allocator, "Unknown"),
            .texture = try TextureData.parse(
                node.findChild("AnimatedTexture") orelse @panic("Could not parse CharacterClass"),
                allocator,
                false,
            ),
        };
    }
};

pub const Ability = struct {
    icon: TextureData,
    name: []const u8,
    mana_cost: i16,
    health_cost: i32,
    cooldown: f32,
    description: []const u8,

    pub fn parse(node: xml.Node, allocator: std.mem.Allocator) !Ability {
        return Ability{
            .icon = try TextureData.parse(node.findChild("Icon") orelse @panic("Could not parse Ability: Icon node is missing"), allocator, false),
            .name = try node.getValueAlloc("Name", allocator, "Unknown"),
            .mana_cost = try node.getValueInt("ManaCost", i16, 0),
            .health_cost = try node.getValueInt("HealthCost", i32, 0),
            .cooldown = try node.getValueFloat("Cooldown", f32, 0.0),
            .description = try node.getValueAlloc("Description", allocator, "Unknown"),
        };
    }
};

pub const CharacterClassStat = struct {
    const tier_count = 2;

    default_value: u16,
    max_values: [tier_count]u16 = undefined,

    pub fn parse(node: xml.Node) !CharacterClassStat {
        var ret = CharacterClassStat{
            .default_value = try node.currentValueInt(u16, 0),
        };
        var buffer: [4]u8 = undefined;
        inline for (0..tier_count) |i| {
            ret.max_values[i] = try node.getAttributeInt(try std.fmt.bufPrintZ(&buffer, "t{d}", .{i + 1}), u16, 0);
        }
        return ret;
    }
};

pub const CharacterClass = struct {
    obj_type: u16,
    name: []const u8,
    desc: []const u8,
    hit_sound: []const u8,
    death_sound: []const u8,
    blood_prob: f32,
    slot_types: []ItemType,
    equipment: []i16,
    ability_1: Ability,
    ability_2: Ability,
    ability_3: Ability,
    ultimate_ability: Ability,
    health: CharacterClassStat,
    mana: CharacterClassStat,
    strength: CharacterClassStat,
    wit: CharacterClassStat,
    defense: CharacterClassStat,
    resistance: CharacterClassStat,
    speed: CharacterClassStat,
    stamina: CharacterClassStat,
    intelligence: CharacterClassStat,
    penetration: CharacterClassStat,
    piercing: CharacterClassStat,
    haste: CharacterClassStat,
    tenacity: CharacterClassStat,
    texture: TextureData,
    skins: ?[]CharacterSkin,

    pub fn parse(node: xml.Node, allocator: std.mem.Allocator) !CharacterClass {
        var slot_list = try std.ArrayList(ItemType).initCapacity(allocator, 20);
        defer slot_list.deinit();
        var slot_iter = std.mem.split(u8, node.getValue("SlotTypes") orelse "", ", ");
        while (slot_iter.next()) |s|
            try slot_list.append(@enumFromInt(try std.fmt.parseInt(i8, s, 0)));

        var equip_list = try std.ArrayList(i16).initCapacity(allocator, 20);
        defer equip_list.deinit();
        var equip_iter = std.mem.split(u8, node.getValue("Equipment") orelse "", ", ");
        while (equip_iter.next()) |s|
            try equip_list.append(try std.fmt.parseInt(i16, s, 0));

        return CharacterClass{
            .obj_type = try node.getAttributeInt("type", u16, 0),
            .name = try node.getAttributeAlloc("id", allocator, "Unknown"),
            .desc = try node.getValueAlloc("Description", allocator, "Unknown"),
            .hit_sound = try node.getValueAlloc("HitSound", allocator, "default_hit"),
            .death_sound = try node.getValueAlloc("DeathSound", allocator, "default_death"),
            .blood_prob = try node.getAttributeFloat("BloodProb", f32, 0.0),
            .slot_types = try allocator.dupe(ItemType, slot_list.items),
            .equipment = try allocator.dupe(i16, equip_list.items),
            .ability_1 = try Ability.parse(node.findChild("Ability1") orelse @panic("Could not parse CharacterClass: Ability1 node is missing"), allocator),
            .ability_2 = try Ability.parse(node.findChild("Ability2") orelse @panic("Could not parse CharacterClass: Ability2 node is missing"), allocator),
            .ability_3 = try Ability.parse(node.findChild("Ability3") orelse @panic("Could not parse CharacterClass: Ability3 node is missing"), allocator),
            .ultimate_ability = try Ability.parse(node.findChild("UltimateAbility") orelse @panic("Could not parse CharacterClass: UltimateAbility node is missing"), allocator),
            .health = try CharacterClassStat.parse(node.findChild("Health") orelse @panic("Could not parse CharacterClass: Health node is missing")),
            .mana = try CharacterClassStat.parse(node.findChild("Mana") orelse @panic("Could not parse CharacterClass: Mana node is missing")),
            .strength = try CharacterClassStat.parse(node.findChild("Strength") orelse @panic("Could not parse CharacterClass: Strength node is missing")),
            .wit = try CharacterClassStat.parse(node.findChild("Wit") orelse @panic("Could not parse CharacterClass: Wit node is missing")),
            .defense = try CharacterClassStat.parse(node.findChild("Defense") orelse @panic("Could not parse CharacterClass: Defense node is missing")),
            .resistance = try CharacterClassStat.parse(node.findChild("Resistance") orelse @panic("Could not parse CharacterClass: Resistance node is missing")),
            .speed = try CharacterClassStat.parse(node.findChild("Speed") orelse @panic("Could not parse CharacterClass: Speed node is missing")),
            .stamina = try CharacterClassStat.parse(node.findChild("Stamina") orelse @panic("Could not parse CharacterClass: Stamina node is missing")),
            .intelligence = try CharacterClassStat.parse(node.findChild("Intelligence") orelse @panic("Could not parse CharacterClass: Intelligence node is missing")),
            .penetration = try CharacterClassStat.parse(node.findChild("Penetration") orelse @panic("Could not parse CharacterClass: Penetration node is missing")),
            .piercing = try CharacterClassStat.parse(node.findChild("Piercing") orelse @panic("Could not parse CharacterClass: Piercing node is missing")),
            .haste = try CharacterClassStat.parse(node.findChild("Haste") orelse @panic("Could not parse CharacterClass: Haste node is missing")),
            .tenacity = try CharacterClassStat.parse(node.findChild("Tenacity") orelse @panic("Could not parse CharacterClass: Tenacity node is missing")),
            .texture = try TextureData.parse(node.findChild("AnimatedTexture") orelse @panic("Could not parse CharacterClass: Texture is missing"), allocator, false),
            .skins = null,
        };
    }
};

pub const AnimFrame = struct {
    time: f32,
    tex: TextureData,

    pub fn parse(node: xml.Node, allocator: std.mem.Allocator) !AnimFrame {
        return AnimFrame{
            .time = try node.getAttributeFloat("time", f32, 0.0) * 1000,
            .tex = try TextureData.parse(node.findChild("Texture").?, allocator, false),
        };
    }
};

pub const AnimProps = struct {
    prob: f32,
    period: u16,
    period_jitter: u16,
    sync: bool,
    frames: []AnimFrame,

    pub fn parse(node: xml.Node, allocator: std.mem.Allocator) !AnimProps {
        var frame_list = try std.ArrayList(AnimFrame).initCapacity(allocator, 5);
        defer frame_list.deinit();
        var frame_iter = node.iterate(&.{}, "Frame");
        while (frame_iter.next()) |animNode|
            try frame_list.append(try AnimFrame.parse(animNode, allocator));

        return AnimProps{
            .prob = try node.getAttributeFloat("prob", f32, 0.0),
            .period = try node.getAttributeInt("period", u16, 0),
            .period_jitter = try node.getAttributeInt("periodJitter", u16, 0),
            .sync = node.attributeExists("sync"),
            .frames = frame_list.items,
        };
    }
};

pub const GroundAnimType = enum(u8) {
    none = 0,
    wave = 1,
    flow = 2,

    const map = std.ComptimeStringMap(GroundAnimType, .{
        .{ "Wave", .wave },
        .{ "Flow", .flow },
    });

    pub fn fromString(str: []const u8) GroundAnimType {
        return map.get(str) orelse .none;
    }
};

pub const GroundProps = struct {
    obj_type: i32,
    obj_id: []const u8,
    no_walk: bool,
    damage: u16,
    blend_prio: i32,
    composite_prio: i32,
    speed: f32,
    x_offset: f32,
    y_offset: f32,
    push: bool,
    sink: bool,
    sinking: bool,
    random_offset: bool,
    light_color: u32,
    light_intensity: f32,
    light_radius: f32,
    light_pulse: f32,
    light_pulse_speed: f32,
    anim_type: GroundAnimType,
    anim_dx: f32,
    anim_dy: f32,
    slide_amount: f32,

    pub fn parse(node: xml.Node, allocator: std.mem.Allocator) !GroundProps {
        var anim_type: GroundAnimType = .none;
        var dx: f32 = 0.0;
        var dy: f32 = 0.0;
        if (node.findChild("Animate")) |anim_node| {
            anim_type = GroundAnimType.fromString(anim_node.currentValue().?);
            dx = try anim_node.getAttributeFloat("dx", f32, 0.0);
            dy = try anim_node.getAttributeFloat("dy", f32, 0.0);
        }

        return GroundProps{
            .obj_type = try node.getAttributeInt("type", i32, 0),
            .obj_id = try node.getAttributeAlloc("id", allocator, "Unknown"),
            .no_walk = node.elementExists("NoWalk"),
            .damage = try node.getValueInt("Damage", u16, 0),
            .blend_prio = try node.getValueInt("BlendPriority", i32, 0),
            .composite_prio = try node.getValueInt("CompositePriority", i32, 0),
            .speed = try node.getValueFloat("Speed", f32, 1.0),
            .x_offset = try node.getValueFloat("XOffset", f32, 0.0),
            .y_offset = try node.getValueFloat("YOffset", f32, 0.0),
            .slide_amount = try node.getValueFloat("SlideAmount", f32, 0.0),
            .push = node.elementExists("Push"),
            .sink = node.elementExists("Sink"),
            .sinking = node.elementExists("Sinking"),
            .random_offset = node.elementExists("RandomOffset"),
            .light_color = try node.getValueInt("LightColor", u32, 0),
            .light_intensity = try node.getValueFloat("LightIntensity", f32, 0.1),
            .light_radius = try node.getValueFloat("LightRadius", f32, 1.0),
            .light_pulse = try node.getValueFloat("LightPulse", f32, 0.0),
            .light_pulse_speed = try node.getValueFloat("LightPulseSpeed", f32, 1.0),
            .anim_type = anim_type,
            .anim_dx = dx,
            .anim_dy = dy,
        };
    }
};

pub const ObjProps = struct {
    obj_type: u16,
    obj_id: []const u8,
    display_id: []const u8,
    shadow_size: i32,
    is_player: bool,
    is_enemy: bool,
    draw_on_ground: bool,
    draw_under: bool,
    occupy_square: bool,
    full_occupy: bool,
    enemy_occupy_square: bool,
    static: bool,
    no_mini_map: bool,
    protect_from_ground_damage: bool,
    protect_from_sink: bool,
    base_z: f32,
    flying: bool,
    color: u32,
    show_name: bool,
    face_attacks: bool,
    blood_probability: f32,
    blood_color: u32,
    shadow_color: u32,
    portrait: ?TextureData,
    min_size: f32,
    max_size: f32,
    size_step: f32,
    angle_correction: f32,
    rotation: f32,
    float: bool,
    float_time: u16,
    float_height: f32,
    float_sine: bool,
    light_color: u32,
    light_intensity: f32,
    light_radius: f32,
    light_pulse: f32,
    light_pulse_speed: f32,
    alpha_mult: f32,
    projectiles: []ProjProps,
    hit_sound: []const u8,
    death_sound: []const u8,

    pub fn parse(node: xml.Node, allocator: std.mem.Allocator) !ObjProps {
        const obj_id = try node.getAttributeAlloc("id", allocator, "");
        var min_size = try node.getValueFloat("MinSize", f32, 100.0) / 100.0;
        var max_size = try node.getValueFloat("MaxSize", f32, 100.0) / 100.0;
        const size = try node.getValueFloat("Size", f32, 0.0) / 100.0;
        if (size > 0) {
            min_size = size;
            max_size = size;
        }

        var proj_it = node.iterate(&.{}, "Projectile");
        var proj_list = try std.ArrayList(ProjProps).initCapacity(allocator, 5);
        defer proj_list.deinit();
        while (proj_it.next()) |proj_node|
            try proj_list.append(try ProjProps.parse(proj_node, allocator));

        const float_node = node.findChild("Float");
        return ObjProps{
            .obj_type = try node.getAttributeInt("type", u16, 0),
            .obj_id = obj_id,
            .display_id = try node.getValueAlloc("DisplayId", allocator, obj_id),
            .shadow_size = try node.getValueInt("ShadowSize", i32, -1),
            .is_player = node.elementExists("Player"),
            .is_enemy = node.elementExists("Enemy"),
            .draw_on_ground = node.elementExists("DrawOnGround"),
            .draw_under = node.elementExists("DrawUnder"),
            .occupy_square = node.elementExists("OccupySquare"),
            .full_occupy = node.elementExists("FullOccupy"),
            .enemy_occupy_square = node.elementExists("EnemyOccupySquare"),
            .static = node.elementExists("Static"),
            .no_mini_map = node.elementExists("NoMiniMap"),
            .base_z = try node.getValueFloat("Z", f32, 0.0),
            .flying = node.elementExists("Flying"),
            .color = try node.getValueInt("Color", u32, 0xFFFFFF),
            .show_name = node.elementExists("ShowName"),
            .face_attacks = !node.elementExists("DontFaceAttacks"),
            .blood_probability = try node.getValueFloat("BloodProb", f32, 0.0),
            .blood_color = try node.getValueInt("BloodColor", u32, 0xFF0000),
            .shadow_color = try node.getValueInt("ShadowColor", u32, 0),
            .portrait = if (node.elementExists("Portrait")) try TextureData.parse(node.findChild("Portrait").?, allocator, false) else null,
            .min_size = min_size,
            .max_size = max_size,
            .size_step = try node.getValueFloat("SizeStep", f32, 0.0) / 100.0,
            .angle_correction = try node.getValueFloat("AngleCorrection", f32, 0.0) * (std.math.pi / 4.0),
            .rotation = try node.getValueFloat("Rotation", f32, 0.0),
            .light_color = try node.getValueInt("LightColor", u32, 0),
            .light_intensity = try node.getValueFloat("LightIntensity", f32, 0.1),
            .light_radius = try node.getValueFloat("LightRadius", f32, 1.0),
            .light_pulse = try node.getValueFloat("LightPulse", f32, 0.0),
            .light_pulse_speed = try node.getValueFloat("LightPulseSpeed", f32, 1.0),
            .alpha_mult = try node.getValueFloat("AlphaMult", f32, 1.0),
            .float = float_node != null,
            .float_time = try std.fmt.parseInt(u16, if (float_node != null) float_node.?.getAttribute("time") orelse "0" else "0", 0),
            .float_height = try std.fmt.parseFloat(f32, if (float_node != null) float_node.?.getAttribute("height") orelse "0.0" else "0.0"),
            .float_sine = float_node != null and float_node.?.getAttribute("sine") != null,
            .projectiles = try allocator.dupe(ProjProps, proj_list.items),
            .hit_sound = try node.getValueAlloc("HitSound", allocator, "Unknown"),
            .death_sound = try node.getValueAlloc("DeathSound", allocator, "Unknown"),
            .protect_from_ground_damage = node.elementExists("ProtectFromGroundDamage"),
            .protect_from_sink = node.elementExists("ProtectFromSink"),
        };
    }

    pub fn getSize(self: *const ObjProps) f32 {
        if (self.min_size == self.max_size)
            return self.min_size;

        const max_steps = std.math.round((self.max_size - self.min_size) / self.size_step);
        return self.min_size + std.math.round(utils.rng.random().float(f32) * max_steps) * self.size_step;
    }
};

pub const ConditionEffect = struct {
    duration: f32,
    condition: utils.ConditionEnum,

    pub fn parse(node: xml.Node) !ConditionEffect {
        return ConditionEffect{
            .duration = try node.getAttributeFloat("duration", f32, 0.0),
            .condition = utils.ConditionEnum.fromString(node.currentValue().?),
        };
    }
};

pub const ProjProps = struct {
    texture_data: []TextureData,
    angle_correction: f32,
    rotation: f32,
    light_color: u32,
    light_intensity: f32,
    light_radius: f32,
    light_pulse: f32,
    light_pulse_speed: f32,
    bullet_type: i32,
    object_id: []const u8,
    lifetime_ms: u16,
    speed: f32,
    size: f32,
    physical_damage: i32,
    magic_damage: i32,
    true_damage: i32,
    effects: []ConditionEffect,
    multi_hit: bool,
    passes_cover: bool,
    particle_trail: bool,
    wavy: bool,
    parametric: bool,
    boomerang: bool,
    amplitude: f32,
    frequency: f32,
    magnitude: f32,
    accel: f32,
    accel_delay: u16,
    speed_clamp: u16,
    angle_change: f32,
    angle_change_delay: u16,
    angle_change_end: u16,
    angle_change_accel: f32,
    angle_change_accel_delay: u16,
    angle_change_clamp: f32,
    zero_velocity_delay: i16,

    pub fn parse(node: xml.Node, allocator: std.mem.Allocator) !ProjProps {
        var effect_it = node.iterate(&.{}, "ConditionEffect");
        var effect_list = try std.ArrayList(ConditionEffect).initCapacity(allocator, 2);
        defer effect_list.deinit();
        while (effect_it.next()) |effect_node|
            try effect_list.append(try ConditionEffect.parse(effect_node));

        return ProjProps{
            .texture_data = try parseTexture(node, allocator),
            .angle_correction = try node.getValueFloat("AngleCorrection", f32, 0.0) * (std.math.pi / 4.0),
            .rotation = try node.getValueFloat("Rotation", f32, 0.0),
            .light_color = try node.getValueInt("LightColor", u32, 0),
            .light_intensity = try node.getValueFloat("LightIntensity", f32, 0.1),
            .light_radius = try node.getValueFloat("LightRadius", f32, 1.0),
            .light_pulse = try node.getValueFloat("LightPulse", f32, 0.0),
            .light_pulse_speed = try node.getValueFloat("LightPulseSpeed", f32, 1.0),
            .bullet_type = try node.getAttributeInt("type", i32, 0),
            .object_id = try node.getValueAlloc("ObjectId", allocator, ""),
            .lifetime_ms = try node.getValueInt("LifetimeMS", u16, 0),
            .speed = try node.getValueFloat("Speed", f32, 0) / 10000.0,
            .size = try node.getValueFloat("Size", f32, 100) / 100.0,
            .physical_damage = try node.getValueInt("Damage", i32, 0),
            .magic_damage = try node.getValueInt("MagicDamage", i32, 0),
            .true_damage = try node.getValueInt("TrueDamage", i32, 0),
            .effects = try allocator.dupe(ConditionEffect, effect_list.items),
            .multi_hit = node.elementExists("MultiHit"),
            .passes_cover = node.elementExists("PassesCover"),
            .particle_trail = node.elementExists("ParticleTrail"),
            .wavy = node.elementExists("Wavy"),
            .parametric = node.elementExists("Parametric"),
            .boomerang = node.elementExists("Boomerang"),
            .amplitude = try node.getValueFloat("Amplitude", f32, 0.0),
            .frequency = try node.getValueFloat("Frequency", f32, 1.0),
            .magnitude = try node.getValueFloat("Magnitude", f32, 3.0),
            .accel = try node.getValueFloat("Acceleration", f32, 0.0),
            .accel_delay = try node.getValueInt("AccelerationDelay", u16, 0),
            .speed_clamp = try node.getValueInt("SpeedClamp", u16, 0),
            .angle_change = std.math.degreesToRadians(f32, try node.getValueFloat("AngleChange", f32, 0.0)),
            .angle_change_delay = try node.getValueInt("AngleChangeDelay", u16, 0),
            .angle_change_end = try node.getValueInt("AngleChangeEnd", u16, 0),
            .angle_change_accel = std.math.degreesToRadians(f32, try node.getValueFloat("AngleChangeAccel", f32, 0.0)),
            .angle_change_accel_delay = try node.getValueInt("AngleChangeAccelDelay", u16, 0),
            .angle_change_clamp = try node.getValueFloat("AngleChangeClamp", f32, 0.0),
            .zero_velocity_delay = try node.getValueInt("ZeroVelocityDelay", i16, -1),
        };
    }
};

pub const StatType = enum(u8) {
    hp = 0,
    size = 1,
    mp = 2,
    inv_0 = 3,
    inv_1 = 4,
    inv_2 = 5,
    inv_3 = 6,
    inv_4 = 7,
    inv_5 = 8,
    inv_6 = 9,
    inv_7 = 10,
    inv_8 = 11,
    inv_9 = 12,
    inv_10 = 13,
    inv_11 = 14,
    inv_12 = 15,
    inv_13 = 16,
    inv_14 = 17,
    inv_15 = 18,
    inv_16 = 19,
    inv_17 = 20,
    inv_18 = 21,
    inv_19 = 22,
    inv_20 = 23,
    inv_21 = 24,
    name = 25,
    merch_type = 26,
    merch_price = 27,
    merch_count = 28,
    gems = 29,
    gold = 30,
    crowns = 31,
    owner_account_id = 32,

    max_hp = 33,
    max_mp = 34,
    strength = 35,
    defense = 36,
    speed = 37,
    stamina = 38,
    wit = 39,
    resistance = 40,
    intelligence = 41,
    penetration = 42,
    piercing = 43,
    haste = 44,
    tenacity = 45,

    hp_bonus = 46,
    mp_bonus = 47,
    strength_bonus = 48,
    defense_bonus = 49,
    speed_bonus = 50,
    stamina_bonus = 51,
    wit_bonus = 52,
    resistance_bonus = 53,
    intelligence_bonus = 54,
    penetration_bonus = 55,
    piercing_bonus = 56,
    haste_bonus = 57,
    tenacity_bonus = 58,

    condition = 59,
    tex_1 = 60,
    tex_2 = 61,
    sellable_price = 62,
    portal_usable = 63,
    account_id = 64,
    tier = 65,
    damage_multiplier = 66,
    hit_multiplier = 67,
    glow = 68,
    alt_texture_index = 69,
    guild = 70,
    guild_rank = 71,
    texture = 72,

    none = 255,

    const map = std.ComptimeStringMap(StatType, .{
        .{ "MaxHP", .max_hp },
        .{ "Max HP", .max_hp },
        .{ "MaxMP", .max_mp },
        .{ "Max MP", .max_mp },
        .{ "Strength", .strength },
        .{ "Defense", .defense },
        .{ "Speed", .speed },
        .{ "Stamina", .stamina },
        .{ "Wit", .wit },
        .{ "Resistance", .resistance },
        .{ "Intelligence", .intelligence },
        .{ "Penetration", .penetration },
        .{ "Piercing", .piercing },
        .{ "Haste", .haste },
        .{ "Tenacity", .tenacity },
    });

    pub fn fromString(str: []const u8) StatType {
        return map.get(str) orelse .max_hp;
    }

    pub fn toString(self: StatType) []const u8 {
        return switch (self) {
            .max_hp => "Max HP",
            .max_mp => "Max MP",
            .strength => "Strength",
            .defense => "Defense",
            .speed => "Speed",
            .stamina => "Stamina",
            .wit => "Wit",
            .resistance => "Resistance",
            .intelligence => "Intelligence",
            .penetration => "Penetration",
            .piercing => "Piercing",
            .haste => "Haste",
            .tenacity => "Tenacity",
            else => "Unknown Stat",
        };
    }
};

pub const ActivationType = enum(u8) {
    open_portal,
    tier_increase,
    cage,
    clock,
    hit_multiplier,
    damage_multiplier,
    stat_boost_self,
    stat_boost_aura,
    condition_effect_aura,
    condition_effect_self,
    heal,
    heal_nova,
    magic,
    magic_nova,
    teleport,
    increment_stat,
    create,
    totem,
    unlock_portal,
    unlock_skin,
    change_skin,
    fixed_stat,
    unlock_emote,
    bloodstone,
    unknown = std.math.maxInt(u8),

    const map = std.ComptimeStringMap(ActivationType, .{
        .{ "OpenPortal", .open_portal },
        .{ "TierIncrease", .tier_increase },
        .{ "Cage", .cage },
        .{ "Clock", .clock },
        .{ "HitMultiplier", .hit_multiplier },
        .{ "DamageMultiplier", .damage_multiplier },
        .{ "StatBoostSelf", .stat_boost_self },
        .{ "StatBoostAura", .stat_boost_aura },
        .{ "ConditionEffectAura", .condition_effect_aura },
        .{ "ConditionEffectSelf", .condition_effect_self },
        .{ "Heal", .heal },
        .{ "HealNova", .heal_nova },
        .{ "Magic", .magic },
        .{ "MagicNova", .magic_nova },
        .{ "Teleport", .teleport },
        .{ "IncrementStat", .increment_stat },
        .{ "Create", .create },
        .{ "Totem", .totem },
        .{ "UnlockPortal", .unlock_portal },
        .{ "UnlockSkin", .unlock_skin },
        .{ "ChangeSkin", .change_skin },
        .{ "FixedStat", .fixed_stat },
        .{ "UnlockEmote", .unlock_emote },
        .{ "Bloodstone", .bloodstone },
    });

    pub fn fromString(str: []const u8) ActivationType {
        const ret = map.get(str) orelse {
            std.log.warn("Could not find activation type for {s}. Using unknown", .{str});
            return .unknown;
        };
        return ret;
    }
};

pub const ActivationData = struct {
    activation_type: ActivationType,
    object_id: []const u8,
    dungeon_name: []const u8,
    duration: f32,
    max_distance: u8,
    max_targets: u8,
    radius: f32,
    total_damage: u32,
    cond_duration: f32,
    id: []const u8,
    effect: utils.ConditionEnum,
    range: f32,
    stat: ?StatType,
    amount: i16,

    pub fn parse(node: xml.Node, allocator: std.mem.Allocator) !ActivationData {
        return ActivationData{
            .activation_type = ActivationType.fromString(node.currentValue() orelse "IncrementStat"),
            .object_id = try node.getAttributeAlloc("objectId", allocator, ""),
            .id = try node.getAttributeAlloc("id", allocator, ""),
            .dungeon_name = try node.getAttributeAlloc("dungeonName", allocator, "Unknown"),
            .effect = utils.ConditionEnum.fromString(node.getAttribute("effect") orelse ""),
            .duration = try node.getAttributeFloat("duration", f32, 0.0),
            .cond_duration = try node.getAttributeFloat("condDuration", f32, 0.0),
            .max_distance = try node.getAttributeInt("maxDistance", u8, 0),
            .max_targets = try node.getAttributeInt("maxTargets", u8, 0),
            .radius = try node.getAttributeFloat("maxDistance", f32, 0.0),
            .total_damage = try node.getAttributeInt("totalDamage", u32, 0),
            .range = try node.getAttributeFloat("condDuration", f32, 0.0),
            .stat = if (node.attributeExists("stat")) StatType.fromString(node.getAttribute("stat") orelse "MaxHP") else null,
            .amount = try node.getAttributeInt("amount", i16, 0),
        };
    }
};

pub const StatIncrementData = struct {
    stat: StatType,
    amount: i16,

    pub fn parse(node: xml.Node) !StatIncrementData {
        return StatIncrementData{
            .stat = StatType.fromString(node.getAttribute("stat") orelse "MaxHP"),
            .amount = try node.getAttributeInt("amount", i16, 0),
        };
    }
};

pub const EffectInfo = struct {
    name: []const u8,
    description: []const u8,

    pub fn parse(node: xml.Node, allocator: std.mem.Allocator) !EffectInfo {
        return EffectInfo{
            .name = try node.getAttributeAlloc("name", allocator, ""),
            .description = try node.getAttributeAlloc("description", allocator, ""),
        };
    }
};

pub const ItemProps = struct {
    consumable: bool,
    untradeable: bool,
    usable: bool,
    is_potion: bool,
    xp_boost: bool,
    lt_boosted: bool,
    ld_boosted: bool,
    backpack: bool,
    slot_type: ItemType,
    tier: []const u8,
    mp_cost: f32,
    bag_type: u8,
    num_projectiles: u8,
    arc_gap: f32,
    id: []const u8,
    display_id: []const u8,
    rate_of_fire: f32,
    texture_data: TextureData,
    projectile: ?ProjProps,
    stat_increments: ?[]StatIncrementData,
    activations: ?[]ActivationData,
    cooldown: f32,
    sound: []const u8,
    old_sound: []const u8,
    timer: f32,
    extra_tooltip_data: ?[]EffectInfo,
    description: []const u8,

    pub fn parse(node: xml.Node, allocator: std.mem.Allocator) !ItemProps {
        var incr_it = node.iterate(&.{}, "IncrementStat");
        var incr_list = try std.ArrayList(StatIncrementData).initCapacity(allocator, 4);
        defer incr_list.deinit();
        while (incr_it.next()) |incr_node|
            try incr_list.append(try StatIncrementData.parse(incr_node));

        var activate_it = node.iterate(&.{}, "Activate");
        var activate_list = try std.ArrayList(ActivationData).initCapacity(allocator, 4);
        defer activate_list.deinit();
        while (activate_it.next()) |activate_node|
            try activate_list.append(try ActivationData.parse(activate_node, allocator));

        var extra_tooltip_it = node.iterate(&.{}, "ExtraTooltipData");
        var extra_tooltip_list = try std.ArrayList(EffectInfo).initCapacity(allocator, 4);
        defer extra_tooltip_list.deinit();
        while (extra_tooltip_it.next()) |extra_tooltip_node|
            try extra_tooltip_list.append(try EffectInfo.parse(extra_tooltip_node, allocator));

        const id = try node.getAttributeAlloc("id", allocator, "Unknown");

        return ItemProps{
            .consumable = node.elementExists("Consumable"),
            .untradeable = node.elementExists("Soulbound"),
            .usable = node.elementExists("Usable"),
            .slot_type = @enumFromInt(try node.getValueInt("SlotType", i8, 0)),
            .tier = try node.getValueAlloc("Tier", allocator, "Unknown"),
            .bag_type = try node.getValueInt("BagType", u8, 0),
            .num_projectiles = try node.getValueInt("NumProjectiles", u8, 1),
            .arc_gap = std.math.degreesToRadians(f32, try node.getValueFloat("ArcGap", f32, 0)),
            .id = id,
            .display_id = try node.getValueAlloc("DisplayId", allocator, id),
            .mp_cost = try node.getValueFloat("MpCost", f32, 0.0),
            .rate_of_fire = try node.getValueFloat("RateOfFire", f32, 0),
            .texture_data = try TextureData.parse(node.findChild("Texture").?, allocator, false),
            .projectile = if (node.elementExists("Projectile")) try ProjProps.parse(node.findChild("Projectile").?, allocator) else null,
            .stat_increments = try allocator.dupe(StatIncrementData, incr_list.items),
            .activations = if (node.elementExists("Activate")) try allocator.dupe(ActivationData, activate_list.items) else null,
            .sound = try node.getValueAlloc("Sound", allocator, "Unknown"),
            .old_sound = try node.getValueAlloc("OldSound", allocator, "Unknown"),
            .is_potion = node.elementExists("Potion"),
            .cooldown = try node.getValueFloat("Cooldown", f32, 0.5),
            .timer = try node.getValueFloat("Timer", f32, 0.0),
            .xp_boost = node.elementExists("XpBoost"),
            .lt_boosted = node.elementExists("LTBoosted"),
            .ld_boosted = node.elementExists("LDBoosted"),
            .backpack = node.elementExists("Backpack"),
            .extra_tooltip_data = if (node.elementExists("ExtraTooltipData")) try allocator.dupe(EffectInfo, extra_tooltip_list.items) else null,
            .description = try node.getValueAlloc("Description", allocator, ""),
        };
    }
};

pub const UseType = enum(u8) {
    default = 0,
    start = 1,
    end = 2,
};

pub const ItemType = enum(i8) {
    const weapon_types = [_]ItemType{ .sword, .bow, .staff };
    const armor_types = [_]ItemType{ .leather, .heavy, .robe };

    no_item = -1,
    any = 0,
    boots = 9,
    artifact = 23,
    consumable = 10,

    sword = 1,
    bow = 3,
    staff = 17,
    any_weapon = 22,

    leather = 6,
    heavy = 7,
    robe = 14,
    any_armor = 20,

    pub inline fn slotsMatch(self: ItemType, target: ItemType) bool {
        return self == .any or target == .any or
            std.mem.indexOfScalar(ItemType, &weapon_types, self) != null and target == .any_weapon or
            std.mem.indexOfScalar(ItemType, &weapon_types, target) != null and self == .any_weapon or
            std.mem.indexOfScalar(ItemType, &armor_types, self) != null and target == .any_armor or
            std.mem.indexOfScalar(ItemType, &armor_types, target) != null and self == .any_armor or
            self == target;
    }
};

pub const Currency = enum(u8) { gold = 0, gems = 1, crowns = 2 };

pub var classes: std.AutoHashMap(u16, CharacterClass) = undefined;
pub var item_name_to_type: std.StringHashMap(u16) = undefined;
pub var item_type_to_props: std.AutoHashMap(u16, ItemProps) = undefined;
pub var item_type_to_name: std.AutoHashMap(u16, []const u8) = undefined;
pub var obj_name_to_type: std.StringHashMap(u16) = undefined;
pub var obj_type_to_props: std.AutoHashMap(u16, ObjProps) = undefined;
pub var obj_type_to_name: std.AutoHashMap(u16, []const u8) = undefined;
pub var obj_type_to_tex_data: std.AutoHashMap(u16, []const TextureData) = undefined;
pub var obj_type_to_top_tex_data: std.AutoHashMap(u16, []const TextureData) = undefined;
pub var obj_type_to_anim_data: std.AutoHashMap(u16, AnimProps) = undefined;
pub var obj_type_to_class: std.AutoHashMap(u16, ClassType) = undefined;
pub var ground_name_to_type: std.StringHashMap(u16) = undefined;
pub var ground_type_to_props: std.AutoHashMap(u16, GroundProps) = undefined;
pub var ground_type_to_name: std.AutoHashMap(u16, []const u8) = undefined;
pub var ground_type_to_tex_data: std.AutoHashMap(u16, []const TextureData) = undefined;
pub var region_type_to_name: std.AutoHashMap(u16, []const u8) = undefined;
pub var region_type_to_color: std.AutoHashMap(u16, u32) = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    classes = std.AutoHashMap(u16, CharacterClass).init(allocator);
    item_name_to_type = std.StringHashMap(u16).init(allocator);
    item_type_to_props = std.AutoHashMap(u16, ItemProps).init(allocator);
    item_type_to_name = std.AutoHashMap(u16, []const u8).init(allocator);
    obj_name_to_type = std.StringHashMap(u16).init(allocator);
    obj_type_to_props = std.AutoHashMap(u16, ObjProps).init(allocator);
    obj_type_to_name = std.AutoHashMap(u16, []const u8).init(allocator);
    obj_type_to_tex_data = std.AutoHashMap(u16, []const TextureData).init(allocator);
    obj_type_to_top_tex_data = std.AutoHashMap(u16, []const TextureData).init(allocator);
    obj_type_to_anim_data = std.AutoHashMap(u16, AnimProps).init(allocator);
    obj_type_to_class = std.AutoHashMap(u16, ClassType).init(allocator);
    ground_name_to_type = std.StringHashMap(u16).init(allocator);
    ground_type_to_props = std.AutoHashMap(u16, GroundProps).init(allocator);
    ground_type_to_name = std.AutoHashMap(u16, []const u8).init(allocator);
    ground_type_to_tex_data = std.AutoHashMap(u16, []const TextureData).init(allocator);
    region_type_to_name = std.AutoHashMap(u16, []const u8).init(allocator);
    region_type_to_color = std.AutoHashMap(u16, u32).init(allocator);

    const xmls_dir = try std.fs.cwd().openDir(asset_dir ++ "xmls", .{ .iterate = true });
    var walker = try xmls_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (std.mem.endsWith(u8, entry.path, ".xml")) {
            const path = std.fmt.allocPrintZ(allocator, asset_dir ++ "xmls/{s}", .{entry.path}) catch continue;
            defer allocator.free(path);

            const doc = try xml.Doc.fromFile(path);
            defer doc.deinit();

            const root_node = doc.getRootElement() catch {
                std.log.err("Invalid XML for path {s}", .{path});
                continue;
            };

            const root_name = std.mem.span(root_node.impl.name);
            if (std.mem.eql(u8, root_name, "Items")) {
                parseItems(doc, allocator) catch |e| {
                    std.log.err("Item parsing error for path {s}: {any}", .{ path, e });
                };
            } else if (std.mem.eql(u8, root_name, "Objects")) {
                parseObjects(doc, allocator) catch |e| {
                    std.log.err("Object parsing error for path {s}: {any}", .{ path, e });
                };
            } else if (std.mem.eql(u8, root_name, "GroundTypes")) {
                parseGrounds(doc, allocator) catch |e| {
                    std.log.err("Ground parsing error for path {s}: {any}", .{ path, e });
                };
            } else if (std.mem.eql(u8, root_name, "Regions")) {
                parseRegions(doc, allocator) catch |e| {
                    std.log.err("Region parsing error for path {s}: {any}", .{ path, e });
                };
            } else {
                std.log.err("Invalid root node for path {s}: {s}", .{ path, root_name });
            }
        }
    }

    const player_doc = try xml.Doc.fromFile(asset_dir ++ "xmls/players.xml");
    defer player_doc.deinit();
    const player_root = try player_doc.getRootElement();
    var player_root_it = player_root.iterate(&.{}, "Object");

    while (player_root_it.next()) |node| {
        const class = try CharacterClass.parse(node, allocator);
        try classes.put(class.obj_type, class);
    }
}

pub fn deinit(allocator: std.mem.Allocator) void {
    var obj_id_iter = obj_type_to_name.valueIterator();
    while (obj_id_iter.next()) |id| {
        allocator.free(id.*);
    }

    var obj_props_iter = obj_type_to_props.valueIterator();
    while (obj_props_iter.next()) |prop| {
        allocator.free(prop.obj_id);
        allocator.free(prop.display_id);
        allocator.free(prop.death_sound);
        allocator.free(prop.hit_sound);

        if (prop.portrait) |tex_data| {
            allocator.free(tex_data.sheet);
        }

        for (prop.projectiles) |proj_prop| {
            for (proj_prop.texture_data) |tex| {
                allocator.free(tex.sheet);
            }
            allocator.free(proj_prop.texture_data);
            allocator.free(proj_prop.object_id);
            allocator.free(proj_prop.effects);
        }

        allocator.free(prop.projectiles);
    }

    var item_props_iter = item_type_to_props.valueIterator();
    while (item_props_iter.next()) |props| {
        if (props.stat_increments) |stat_increment| {
            allocator.free(stat_increment);
        }

        if (props.activations) |activate| {
            for (activate) |data| {
                allocator.free(data.id);
                allocator.free(data.object_id);
                allocator.free(data.dungeon_name);
            }

            allocator.free(activate);
        }

        if (props.extra_tooltip_data) |data| {
            for (data) |effect| {
                allocator.free(effect.name);
                allocator.free(effect.description);
            }

            allocator.free(data);
        }

        allocator.free(props.texture_data.sheet);
        allocator.free(props.tier);
        allocator.free(props.old_sound);
        allocator.free(props.sound);
        allocator.free(props.id);
        allocator.free(props.display_id);
        allocator.free(props.description);

        if (props.projectile) |proj_props| {
            for (proj_props.texture_data) |tex| {
                allocator.free(tex.sheet);
            }
            allocator.free(proj_props.texture_data);
            allocator.free(proj_props.object_id);
            allocator.free(proj_props.effects);
        }
    }

    var item_name_iter = item_type_to_name.valueIterator();
    while (item_name_iter.next()) |id| {
        allocator.free(id.*);
    }

    var ground_name_iter = ground_type_to_name.valueIterator();
    while (ground_name_iter.next()) |id| {
        allocator.free(id.*);
    }

    var ground_iter = ground_type_to_props.valueIterator();
    while (ground_iter.next()) |props| {
        allocator.free(props.obj_id);
    }

    var region_iter = region_type_to_name.valueIterator();
    while (region_iter.next()) |id| {
        allocator.free(id.*);
    }

    var ground_tex_iter = ground_type_to_tex_data.valueIterator();
    while (ground_tex_iter.next()) |tex_list| {
        for (tex_list.*) |tex| {
            allocator.free(tex.sheet);
        }
        allocator.free(tex_list.*);
    }

    var obj_tex_iter = obj_type_to_tex_data.valueIterator();
    while (obj_tex_iter.next()) |tex_list| {
        for (tex_list.*) |tex| {
            allocator.free(tex.sheet);
        }
        allocator.free(tex_list.*);
    }

    var obj_top_tex_iter = obj_type_to_top_tex_data.valueIterator();
    while (obj_top_tex_iter.next()) |tex_list| {
        for (tex_list.*) |tex| {
            allocator.free(tex.sheet);
        }
        allocator.free(tex_list.*);
    }

    var class_iter = classes.valueIterator();
    while (class_iter.next()) |class| {
        allocator.free(class.texture.sheet);
        allocator.free(class.hit_sound);
        allocator.free(class.death_sound);
        allocator.free(class.name);
        allocator.free(class.desc);
        allocator.free(class.slot_types);
        allocator.free(class.equipment);
        allocator.free(class.ability_1.icon.sheet);
        allocator.free(class.ability_1.name);
        allocator.free(class.ability_1.description);
        allocator.free(class.ability_2.icon.sheet);
        allocator.free(class.ability_2.name);
        allocator.free(class.ability_2.description);
        allocator.free(class.ability_3.icon.sheet);
        allocator.free(class.ability_3.name);
        allocator.free(class.ability_3.description);
        allocator.free(class.ultimate_ability.icon.sheet);
        allocator.free(class.ultimate_ability.name);
        allocator.free(class.ultimate_ability.description);
    }

    classes.deinit();
    item_name_to_type.deinit();
    item_type_to_props.deinit();
    item_type_to_name.deinit();
    obj_name_to_type.deinit();
    obj_type_to_props.deinit();
    obj_type_to_name.deinit();
    obj_type_to_tex_data.deinit();
    obj_type_to_top_tex_data.deinit();
    obj_type_to_anim_data.deinit();
    obj_type_to_class.deinit();
    ground_name_to_type.deinit();
    ground_type_to_props.deinit();
    ground_type_to_name.deinit();
    ground_type_to_tex_data.deinit();
    region_type_to_name.deinit();
    region_type_to_color.deinit();
}

fn parseTexture(node: xml.Node, allocator: std.mem.Allocator) ![]TextureData {
    if (node.findChild("RandomTexture")) |random_tex_child| {
        var tex_iter = random_tex_child.iterate(&.{}, "Texture");
        var tex_list = try std.ArrayList(TextureData).initCapacity(allocator, 4);
        defer tex_list.deinit();
        while (tex_iter.next()) |tex_node| {
            try tex_list.append(try TextureData.parse(tex_node, allocator, false));
        }

        if (tex_list.capacity > 0) {
            return try allocator.dupe(TextureData, tex_list.items);
        } else {
            var anim_tex_iter = random_tex_child.iterate(&.{}, "AnimatedTexture");
            var anim_tex_list = try std.ArrayList(TextureData).initCapacity(allocator, 4);
            defer anim_tex_list.deinit();
            while (anim_tex_iter.next()) |tex_node| {
                try anim_tex_list.append(try TextureData.parse(tex_node, allocator, true));
            }

            return try allocator.dupe(TextureData, anim_tex_list.items);
        }
    } else {
        if (node.findChild("Texture")) |tex_child| {
            const ret = try allocator.alloc(TextureData, 1);
            ret[0] = try TextureData.parse(tex_child, allocator, false);
            return ret;
        } else {
            if (node.findChild("AnimatedTexture")) |anim_tex_child| {
                const ret = try allocator.alloc(TextureData, 1);
                ret[0] = try TextureData.parse(anim_tex_child, allocator, true);
                return ret;
            }
        }
    }

    return &[0]TextureData{};
}

pub fn parseItems(doc: xml.Doc, allocator: std.mem.Allocator) !void {
    const root = try doc.getRootElement();
    var iter = root.iterate(&.{}, "Item");
    while (iter.next()) |node| {
        const obj_type = try node.getAttributeInt("type", u16, 0);
        const id = try node.getAttributeAlloc("id", allocator, "Unknown");
        try item_name_to_type.put(id, obj_type);
        try item_type_to_props.put(obj_type, try ItemProps.parse(node, allocator));
        try item_type_to_name.put(obj_type, id);
    }
}

pub fn parseObjects(doc: xml.Doc, allocator: std.mem.Allocator) !void {
    const root = try doc.getRootElement();
    var iter = root.iterate(&.{}, "Object");
    while (iter.next()) |node| {
        const obj_type = try node.getAttributeInt("type", u16, 0);
        const id = try node.getAttributeAlloc("id", allocator, "Unknown");
        try obj_type_to_class.put(obj_type, ClassType.fromString(node.getValue("Class") orelse "GameObject"));
        try obj_name_to_type.put(id, obj_type);
        try obj_type_to_props.put(obj_type, try ObjProps.parse(node, allocator));
        try obj_type_to_name.put(obj_type, id);

        try obj_type_to_tex_data.put(obj_type, try parseTexture(node, allocator));

        if (node.findChild("Top")) |top_tex_child| {
            try obj_type_to_top_tex_data.put(obj_type, try parseTexture(top_tex_child, allocator));
        }
    }
}

pub fn parseGrounds(doc: xml.Doc, allocator: std.mem.Allocator) !void {
    const root = try doc.getRootElement();
    var iter = root.iterate(&.{}, "Ground");
    while (iter.next()) |node| {
        const obj_type = try node.getAttributeInt("type", u16, 0);
        const id = try node.getAttributeAlloc("id", allocator, "Unknown");
        try ground_name_to_type.put(id, obj_type);
        try ground_type_to_props.put(obj_type, try GroundProps.parse(node, allocator));
        try ground_type_to_name.put(obj_type, id);

        if (node.findChild("RandomTexture")) |random_tex_child| {
            var tex_iter = random_tex_child.iterate(&.{}, "Texture");
            var tex_list = try std.ArrayList(TextureData).initCapacity(allocator, 4);
            defer tex_list.deinit();
            while (tex_iter.next()) |tex_node| {
                try tex_list.append(try TextureData.parse(tex_node, allocator, false));
            }
            try ground_type_to_tex_data.put(obj_type, try allocator.dupe(TextureData, tex_list.items));
        } else {
            if (node.findChild("Texture")) |tex_child| {
                const ret = try allocator.alloc(TextureData, 1);
                ret[0] = try TextureData.parse(tex_child, allocator, false);
                try ground_type_to_tex_data.put(obj_type, ret);
            }
        }
    }
}

pub fn parseRegions(doc: xml.Doc, allocator: std.mem.Allocator) !void {
    const root = try doc.getRootElement();
    var iter = root.iterate(&.{}, "Region");
    while (iter.next()) |node| {
        const obj_type = try node.getAttributeInt("type", u16, 0);
        const id = try node.getAttributeAlloc("id", allocator, "Unknown");
        try region_type_to_name.put(obj_type, id);
        try region_type_to_color.put(obj_type, try node.getValueInt("Color", u32, 0));
    }
}
