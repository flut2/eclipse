const std = @import("std");
const xml = @import("xml.zig");
const utils = @import("utils.zig");

pub const ServerData = struct {
    name: []const u8,
    dns: []const u8,
    port: u16,
    max_players: u16,
    admin_only: bool,

    pub fn parse(node: xml.Node, allocator: std.mem.Allocator) !ServerData {
        return .{
            .name = try node.getValueAlloc("Name", allocator, "Unknown"),
            .dns = try node.getValueAlloc("DNS", allocator, "127.0.0.1"),
            .port = try node.getValueInt("Port", u16, 2050),
            .max_players = try node.getValueInt("MaxPlayers", u16, 0),
            .admin_only = node.elementExists("AdminOnly") and std.mem.eql(u8, node.getValue("AdminOnly").?, "true"),
        };
    }

    pub fn deinit(self: ServerData, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.dns);
    }
};

pub const CharacterData = struct {
    id: u32,
    obj_type: u16,
    name: []const u8,
    health: u16,
    mana: u16,
    strength: u16,
    wit: u16,
    defense: u16,
    resistance: u16,
    speed: u16,
    haste: u16,
    stamina: u16,
    intelligence: u16,
    piercing: u16,
    penetration: u16,
    tenacity: u16,
    tex_1: u32,
    tex_2: u32,
    texture: u16,
    equipment: []u16,

    pub fn parse(allocator: std.mem.Allocator, node: xml.Node, id: u32) !CharacterData {
        const obj_type = try node.getValueInt("ObjectType", u16, 0);

        var equip_list = try std.ArrayList(u16).initCapacity(allocator, 22);
        defer equip_list.deinit();
        if (node.getValue("Equipment")) |equips| {
            var equip_iter = std.mem.split(u8, equips, ", ");
            while (equip_iter.next()) |s|
                try equip_list.append(try std.fmt.parseInt(u16, s, 0));
        }

        return .{
            .id = id,
            .obj_type = obj_type,
            .health = try node.getValueInt("Health", u16, 0),
            .mana = try node.getValueInt("Mana", u16, 0),
            .strength = try node.getValueInt("Strength", u16, 0),
            .wit = try node.getValueInt("Wit", u16, 0),
            .defense = try node.getValueInt("Defense", u16, 0),
            .resistance = try node.getValueInt("Resistance", u16, 0),
            .speed = try node.getValueInt("Speed", u16, 0),
            .haste = try node.getValueInt("Haste", u16, 0),
            .stamina = try node.getValueInt("Stamina", u16, 0),
            .intelligence = try node.getValueInt("Intelligence", u16, 0),
            .piercing = try node.getValueInt("Piercing", u16, 0),
            .penetration = try node.getValueInt("Penetration", u16, 0),
            .tenacity = try node.getValueInt("Tenacity", u16, 0),
            .tex_1 = try node.getValueInt("Tex1", u32, 0),
            .tex_2 = try node.getValueInt("Tex2", u32, 0),
            .texture = try node.getValueInt("Texture", u16, 0),
            .equipment = try allocator.dupe(u16, equip_list.items),
            .name = try allocator.dupe(u8, obj_type_to_name.get(obj_type) orelse "Unknown Class"),
        };
    }

    pub fn deinit(self: CharacterData, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.equipment);
    }
};

pub const ClassType = enum(u8) {
    character,
    container,
    game_object,
    guild_chronicle,
    guild_hall_portal,
    merchant,
    player,
    portal,
    projectile,
    wall,
    skin,

    const map = std.ComptimeStringMap(ClassType, .{
        .{ "Character", .character },
        .{ "Container", .container },
        .{ "GameObject", .game_object },
        .{ "GuildChronicle", .guild_chronicle },
        .{ "GuildHallPortal", .guild_hall_portal },
        .{ "Merchant", .merchant },
        .{ "Player", .player },
        .{ "Portal", .portal },
        .{ "Projectile", .projectile },
        .{ "Wall", .wall },
        .{ "Skin", .skin },
    });

    pub fn fromString(str: []const u8) ClassType {
        return map.get(str) orelse .game_object;
    }

    pub fn isInteractive(class: ClassType) bool {
        return class == .portal or class == .container or class == .merchant or class == .guild_chronicle;
    }
};

pub const TextureData = struct {
    sheet: []const u8,
    index: u16,
    animated: bool,

    pub fn parse(node: xml.Node, allocator: std.mem.Allocator, animated: bool) !TextureData {
        return .{
            .sheet = try node.getValueAlloc("Sheet", allocator, "Unknown"),
            .index = try node.getValueInt("Index", u16, 0),
            .animated = animated,
        };
    }

    pub fn deinit(self: TextureData, allocator: std.mem.Allocator) void {
        allocator.free(self.sheet);
    }
};

pub const CharacterSkin = struct {
    obj_type: u16,
    name: []const u8,
    texture: TextureData,

    pub fn parse(node: xml.Node, allocator: std.mem.Allocator) CharacterSkin {
        return .{
            .obj_type = try node.getAttributeInt("type", u16, 0),
            .name = try node.getAttributeAlloc("id", allocator, "Unknown"),
            .texture = try TextureData.parse(
                node.findChild("AnimatedTexture") orelse
                    std.debug.panic("Could not parse CharacterClass"),
                allocator,
                false,
            ),
        };
    }
};

pub const Ability = struct {
    icon: TextureData,
    name: []const u8,
    mana_cost: i32,
    health_cost: i32,
    gold_cost: i32,
    cooldown: f32,
    description: []const u8,

    pub fn parse(node: xml.Node, allocator: std.mem.Allocator) !Ability {
        return .{
            .icon = try TextureData.parse(node.findChild("Icon") orelse
                std.debug.panic("Could not parse Ability: Icon node is missing", .{}), allocator, false),
            .name = try node.getValueAlloc("Name", allocator, "Unknown"),
            .mana_cost = try node.getValueInt("ManaCost", i32, 0),
            .health_cost = try node.getValueInt("HealthCost", i32, 0),
            .gold_cost = try node.getValueInt("GoldCost", i32, 0),
            .cooldown = try node.getValueFloat("Cooldown", f32, 0.0),
            .description = try node.getValueAlloc("Description", allocator, "Unknown"),
        };
    }

    pub fn deinit(self: Ability, allocator: std.mem.Allocator) void {
        self.icon.deinit(allocator);
        allocator.free(self.name);
        allocator.free(self.description);
    }
};

pub const CharacterClass = struct {
    obj_type: u16,
    name: []const u8,
    rpc_name: []const u8,
    desc: []const u8,
    hit_sound: []const u8,
    death_sound: []const u8,
    blood_prob: f32,
    slot_types: []ItemType,
    equipment: []u16,
    ability_1: Ability,
    ability_2: Ability,
    ability_3: Ability,
    ultimate_ability: Ability,
    health: u16,
    mana: u16,
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
    texture: TextureData,
    projs: []ProjProps,
    skins: ?[]CharacterSkin,

    pub fn parse(node: xml.Node, allocator: std.mem.Allocator) !CharacterClass {
        var slot_list = try std.ArrayList(ItemType).initCapacity(allocator, 22);
        defer slot_list.deinit();
        if (node.getValue("SlotTypes")) |slot_types| {
            var slot_iter = std.mem.split(u8, slot_types, ", ");
            while (slot_iter.next()) |s|
                try slot_list.append(@enumFromInt(try std.fmt.parseInt(i8, s, 0)));
        }

        var equip_list = try std.ArrayList(u16).initCapacity(allocator, 22);
        defer equip_list.deinit();
        if (node.getValue("Equipment")) |equips| {
            var equip_iter = std.mem.split(u8, equips, ", ");
            while (equip_iter.next()) |s|
                try equip_list.append(try std.fmt.parseInt(u16, s, 0));
        }

        const name = try node.getAttributeAlloc("id", allocator, "Unknown");
        const rpc_name = try allocator.dupe(u8, name);
        std.mem.replaceScalar(u8, rpc_name, ' ', '_');
        for (rpc_name) |*char| {
            char.* = std.ascii.toLower(char.*);
        }

        var proj_list = std.ArrayList(ProjProps).init(allocator);
        defer proj_list.deinit();
        var proj_iter = node.iterate(&.{}, "Projectile");
        while (proj_iter.next()) |proj_node|
            try proj_list.append(try ProjProps.parse(proj_node, allocator));

        return .{
            .obj_type = try node.getAttributeInt("type", u16, 0),
            .name = name,
            .rpc_name = rpc_name,
            .desc = try node.getValueAlloc("Description", allocator, "Unknown"),
            .hit_sound = try node.getValueAlloc("HitSound", allocator, "default_hit"),
            .death_sound = try node.getValueAlloc("DeathSound", allocator, "default_death"),
            .blood_prob = try node.getAttributeFloat("BloodProb", f32, 0.0),
            .slot_types = try allocator.dupe(ItemType, slot_list.items),
            .equipment = try allocator.dupe(u16, equip_list.items),
            .ability_1 = try Ability.parse(node.findChild("Ability1") orelse
                std.debug.panic("Could not parse CharacterClass: Ability1 node is missing", .{}), allocator),
            .ability_2 = try Ability.parse(node.findChild("Ability2") orelse
                std.debug.panic("Could not parse CharacterClass: Ability2 node is missing", .{}), allocator),
            .ability_3 = try Ability.parse(node.findChild("Ability3") orelse
                std.debug.panic("Could not parse CharacterClass: Ability3 node is missing", .{}), allocator),
            .ultimate_ability = try Ability.parse(node.findChild("UltimateAbility") orelse
                std.debug.panic("Could not parse CharacterClass: UltimateAbility node is missing", .{}), allocator),
            .health = try node.getValueInt("Health", u16, 0),
            .mana = try node.getValueInt("Mana", u16, 0),
            .strength = try node.getValueInt("Strength", u16, 0),
            .wit = try node.getValueInt("Wit", u16, 0),
            .defense = try node.getValueInt("Defense", u16, 0),
            .resistance = try node.getValueInt("Resistance", u16, 0),
            .speed = try node.getValueInt("Speed", u16, 0),
            .stamina = try node.getValueInt("Stamina", u16, 0),
            .intelligence = try node.getValueInt("Intelligence", u16, 0),
            .penetration = try node.getValueInt("Penetration", u16, 0),
            .piercing = try node.getValueInt("Piercing", u16, 0),
            .haste = try node.getValueInt("Haste", u16, 0),
            .tenacity = try node.getValueInt("Tenacity", u16, 0),
            .texture = try TextureData.parse(node.findChild("AnimatedTexture") orelse
                std.debug.panic("Could not parse CharacterClass: Texture is missing", .{}), allocator, false),
            .skins = null,
            .projs = try allocator.dupe(ProjProps, proj_list.items),
        };
    }

    pub fn deinit(self: CharacterClass, allocator: std.mem.Allocator) void {
        self.texture.deinit(allocator);
        allocator.free(self.hit_sound);
        allocator.free(self.death_sound);
        allocator.free(self.name);
        allocator.free(self.rpc_name);
        for (self.projs) |props| {
            props.deinit(allocator);
        }
        allocator.free(self.projs);
        allocator.free(self.desc);
        allocator.free(self.slot_types);
        allocator.free(self.equipment);
        self.ability_1.deinit(allocator);
        self.ability_2.deinit(allocator);
        self.ability_3.deinit(allocator);
        self.ultimate_ability.deinit(allocator);
    }
};

pub const AnimFrame = struct {
    time: i64,
    tex: TextureData,

    pub fn parse(node: xml.Node, allocator: std.mem.Allocator) !AnimFrame {
        return .{
            .time = @intFromFloat(try node.getAttributeFloat("time", f32, 0.0) * std.time.us_per_s),
            .tex = try TextureData.parse(node.findChild("Texture").?, allocator, false),
        };
    }
};

pub const AnimProps = struct {
    prob: f32,
    period: i64,
    period_jitter: i64,
    frames: []AnimFrame,

    pub fn parse(node: xml.Node, allocator: std.mem.Allocator) !AnimProps {
        var frame_list = try std.ArrayList(AnimFrame).initCapacity(allocator, 5);
        defer frame_list.deinit();
        var frame_iter = node.iterate(&.{}, "Frame");
        while (frame_iter.next()) |anim_node|
            try frame_list.append(try AnimFrame.parse(anim_node, allocator));

        return .{
            .prob = try node.getAttributeFloat("prob", f32, 0.0),
            .period = @intFromFloat(try node.getAttributeFloat("period", f32, 0.0) * std.time.us_per_s),
            .period_jitter = @intFromFloat(try node.getAttributeFloat("periodJitter", f32, 0.0) * std.time.us_per_s),
            .frames = try allocator.dupe(AnimFrame, frame_list.items),
        };
    }

    pub fn deinit(self: AnimProps, allocator: std.mem.Allocator) void {
        for (self.frames) |frame| {
            frame.tex.deinit(allocator);
        }
        allocator.free(self.frames);
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
    physical_damage: u16,
    magic_damage: u16,
    true_damage: u16,
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

        return .{
            .obj_type = try node.getAttributeInt("type", i32, 0),
            .obj_id = try node.getAttributeAlloc("id", allocator, "Unknown"),
            .no_walk = node.elementExists("NoWalk"),
            .physical_damage = try node.getValueInt("PhysicalDamage", u16, 0),
            .magic_damage = try node.getValueInt("MagicDamage", u16, 0),
            .true_damage = try node.getValueInt("TrueDamage", u16, 0),
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
            .light_color = try node.getValueInt("LightColor", u32, std.math.maxInt(u32)),
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

pub const ShowEffect = enum(u8) {
    unknown = 0,
    potion = 1,
    teleport = 2,
    stream = 3,
    throw = 4,
    area_blast = 5,
    dead = 6,
    trail = 7,
    diffuse = 8,
    flow = 9,
    trap = 10,
    lightning = 11,
    concentrate = 12,
    blast_wave = 13,
    earthquake = 14,
    flashing = 15,
    beach_ball = 16,
    ring = 17,

    const map = std.ComptimeStringMap(ShowEffect, .{
        .{ "Potion", .potion },
        .{ "Teleport", .teleport },
        .{ "Stream", .stream },
        .{ "Throw", .throw },
        .{ "AreaBlast", .area_blast },
        .{ "Dead", .dead },
        .{ "Trail", .trail },
        .{ "Diffuse", .diffuse },
        .{ "Flow", .flow },
        .{ "Trap", .trap },
        .{ "Lightning", .lightning },
        .{ "Concentrate", .concentrate },
        .{ "BlastWave", .blast_wave },
        .{ "Earthquake", .earthquake },
        .{ "Flashing", .flashing },
        .{ "BeachBall", .beach_ball },
        .{ "Ring", .ring },
    });

    pub fn fromString(str: []const u8) ShowEffect {
        return map.get(str) orelse .unknown;
    }
};

pub const ShowEffProps = struct {
    effect: ShowEffect,
    radius: f32,
    cooldown: i64,
    color: u32,

    pub fn parse(node: xml.Node) !ShowEffProps {
        return .{
            .effect = ShowEffect.fromString(node.currentValue() orelse ""),
            .radius = try node.getAttributeFloat("radius", f32, 5.0),
            .cooldown = try node.getAttributeInt("cooldown", i64, 1000) * std.time.us_per_ms,
            .color = try node.getAttributeInt("color", u32, 0xFFFFFF),
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
    float_time: f32,
    float_height: f32,
    light_color: u32,
    light_intensity: f32,
    light_radius: f32,
    light_pulse: f32,
    light_pulse_speed: f32,
    alpha_mult: f32,
    show_effects: []ShowEffProps,
    projectiles: []ProjProps,
    hit_sound: []const u8,
    death_sound: []const u8,
    slot_types: []ItemType,
    anim_props: ?AnimProps,
    health: i32,
    resistance: i32,
    defense: i32,

    pub fn parse(node: xml.Node, allocator: std.mem.Allocator) !ObjProps {
        var slot_list = try std.ArrayList(ItemType).initCapacity(allocator, 9);
        defer slot_list.deinit();
        if (node.getValue("SlotTypes")) |slot_types| {
            var slot_iter = std.mem.split(u8, slot_types, ", ");
            while (slot_iter.next()) |s|
                try slot_list.append(@enumFromInt(try std.fmt.parseInt(i8, s, 0)));
        }

        const obj_id = try node.getAttributeAlloc("id", allocator, "");
        var min_size = try node.getValueFloat("MinSize", f32, 100.0) / 100.0;
        var max_size = try node.getValueFloat("MaxSize", f32, 100.0) / 100.0;
        const size = try node.getValueFloat("Size", f32, 0.0) / 100.0;
        if (size > 0) {
            min_size = size;
            max_size = size;
        }

        var proj_it = node.iterate(&.{}, "Projectile");
        var proj_list = std.ArrayList(ProjProps).init(allocator);
        defer proj_list.deinit();
        while (proj_it.next()) |proj_node|
            try proj_list.append(try ProjProps.parse(proj_node, allocator));

        var eff_it = node.iterate(&.{}, "ShowEffect");
        var eff_list = std.ArrayList(ShowEffProps).init(allocator);
        defer eff_list.deinit();
        while (eff_it.next()) |eff_node|
            try eff_list.append(try ShowEffProps.parse(eff_node));

        const float_node = node.findChild("Float");
        return .{
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
            .light_color = try node.getValueInt("LightColor", u32, std.math.maxInt(u32)),
            .light_intensity = try node.getValueFloat("LightIntensity", f32, 0.1),
            .light_radius = try node.getValueFloat("LightRadius", f32, 1.0),
            .light_pulse = try node.getValueFloat("LightPulse", f32, 0.0),
            .light_pulse_speed = try node.getValueFloat("LightPulseSpeed", f32, 1.0),
            .alpha_mult = try node.getValueFloat("AlphaMult", f32, 1.0),
            .float = float_node != null,
            .float_time = try std.fmt.parseFloat(f32, if (float_node != null) float_node.?.getAttribute("time") orelse "0.0" else "0.0") * std.time.us_per_ms,
            .float_height = try std.fmt.parseFloat(f32, if (float_node != null) float_node.?.getAttribute("height") orelse "0.0" else "0.0"),
            .show_effects = try allocator.dupe(ShowEffProps, eff_list.items),
            .projectiles = try allocator.dupe(ProjProps, proj_list.items),
            .slot_types = try allocator.dupe(ItemType, slot_list.items),
            .hit_sound = try node.getValueAlloc("HitSound", allocator, "Unknown"),
            .death_sound = try node.getValueAlloc("DeathSound", allocator, "Unknown"),
            .protect_from_ground_damage = node.elementExists("ProtectFromGroundDamage"),
            .protect_from_sink = node.elementExists("ProtectFromSink"),
            .anim_props = if (node.elementExists("Animation")) try AnimProps.parse(node.findChild("Animation").?, allocator) else null,
            .health = try node.getValueInt("Health", i32, 0),
            .defense = try node.getValueInt("Defense", i32, 0),
            .resistance = try node.getValueInt("Resistance", i32, 0),
        };
    }

    pub fn deinit(self: ObjProps, allocator: std.mem.Allocator) void {
        allocator.free(self.obj_id);
        allocator.free(self.display_id);
        allocator.free(self.death_sound);
        allocator.free(self.hit_sound);

        if (self.portrait) |tex_data| {
            tex_data.deinit(allocator);
        }

        allocator.free(self.show_effects);

        for (self.projectiles) |proj_props| {
            proj_props.deinit(allocator);
        }

        allocator.free(self.projectiles);

        if (self.anim_props) |anim_props| {
            anim_props.deinit(allocator);
        }

        allocator.free(self.slot_types);
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
        return .{
            .duration = try node.getAttributeFloat("duration", f32, 0.0),
            .condition = utils.ConditionEnum.fromString(node.currentValue().?),
        };
    }
};

pub const CardProps = struct {
    card_type: u16,
    title: []const u8,
    description: []const u8,

    pub fn parse(node: xml.Node, allocator: std.mem.Allocator) !CardProps {
        return .{
            .card_type = try node.getAttributeInt("type", u16, 0),
            .title = try node.getValueAlloc("Title", allocator, "Unknown"),
            .description = try node.getValueAlloc("Description", allocator, ""),
        };
    }

    pub fn deinit(self: CardProps, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.description);
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
    lifetime: i64,
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
    accel_delay: i64,
    speed_clamp: u16,
    angle_change: f32,
    angle_change_delay: i64,
    angle_change_end: u16,
    angle_change_accel: f32,
    angle_change_accel_delay: i64,
    angle_change_clamp: f32,
    zero_velocity_delay: i64,
    heat_seek_speed: f32,
    heat_seek_radius: f32,
    heat_seek_delay: i64,
    bouncing: bool,

    pub fn parse(node: xml.Node, allocator: std.mem.Allocator) !ProjProps {
        var effect_it = node.iterate(&.{}, "ConditionEffect");
        var effect_list = try std.ArrayList(ConditionEffect).initCapacity(allocator, 2);
        defer effect_list.deinit();
        while (effect_it.next()) |effect_node|
            try effect_list.append(try ConditionEffect.parse(effect_node));

        return .{
            .texture_data = try parseTexture(node, allocator),
            .angle_correction = try node.getValueFloat("AngleCorrection", f32, 0.0) * (std.math.pi / 4.0),
            .rotation = try node.getValueFloat("Rotation", f32, 0.0),
            .light_color = try node.getValueInt("LightColor", u32, std.math.maxInt(u32)),
            .light_intensity = try node.getValueFloat("LightIntensity", f32, 0.1),
            .light_radius = try node.getValueFloat("LightRadius", f32, 1.0),
            .light_pulse = try node.getValueFloat("LightPulse", f32, 0.0),
            .light_pulse_speed = try node.getValueFloat("LightPulseSpeed", f32, 1.0),
            .bullet_type = try node.getAttributeInt("type", i32, 0),
            .object_id = try node.getValueAlloc("ObjectId", allocator, ""),
            .lifetime = try node.getValueInt("Lifetime", i64, 0) * std.time.us_per_ms,
            .speed = try node.getValueFloat("Speed", f32, 0) / 10000.0 / std.time.us_per_ms,
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
            .accel_delay = try node.getValueInt("AccelerationDelay", i64, 0) * std.time.us_per_ms,
            .speed_clamp = try node.getValueInt("SpeedClamp", u16, 0),
            .angle_change = std.math.degreesToRadians(f32, try node.getValueFloat("AngleChange", f32, 0.0)),
            .angle_change_delay = try node.getValueInt("AngleChangeDelay", i64, 0) * std.time.us_per_ms,
            .angle_change_end = try node.getValueInt("AngleChangeEnd", u16, 0),
            .angle_change_accel = std.math.degreesToRadians(f32, try node.getValueFloat("AngleChangeAccel", f32, 0.0)),
            .angle_change_accel_delay = try node.getValueInt("AngleChangeAccelDelay", i64, 0) * std.time.us_per_ms,
            .angle_change_clamp = try node.getValueFloat("AngleChangeClamp", f32, 0.0),
            .zero_velocity_delay = try node.getValueInt("ZeroVelocityDelay", i64, -1) * std.time.us_per_ms,
            .heat_seek_speed = try node.getValueFloat("HeatSeekSpeed", f32, 0.0) / 10000.0,
            .heat_seek_radius = try node.getValueFloat("HeatSeekRadius", f32, 0.0),
            .heat_seek_delay = try node.getValueInt("HeatSeekDelay", i64, 0) * std.time.us_per_ms,
            .bouncing = node.elementExists("Bouncing"),
        };
    }

    pub fn deinit(self: ProjProps, allocator: std.mem.Allocator) void {
        for (self.texture_data) |tex_data| {
            tex_data.deinit(allocator);
        }
        allocator.free(self.texture_data);
        allocator.free(self.object_id);
        allocator.free(self.effects);
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
    aether = 65,
    damage_multiplier = 66,
    hit_multiplier = 67,
    glow = 68,
    alt_texture_index = 69,
    guild = 70,
    guild_rank = 71,
    texture = 72,
    x = 73,
    y = 74,

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

    pub fn toControlCode(self: StatType) []const u8 {
        return switch (self) {
            .max_hp => "&img=\"misc_big,0x28\"",
            .max_mp => "&img=\"misc_big,0x27\"",
            .strength => "&img=\"misc_big,0x20\"",
            .defense => "&img=\"misc_big,0x21\"",
            .speed => "&img=\"misc_big,0x22\"",
            .stamina => "&img=\"misc_big,0x24\"",
            .wit => "&img=\"misc_big,0x23\"",
            .resistance => "&img=\"misc_big,0x39\"",
            .intelligence => "&img=\"misc_big,0x3b\"",
            .penetration => "&img=\"misc_big,0x26\"",
            .piercing => "&img=\"misc_big,0x3c\"",
            .haste => "&img=\"misc_big,0x3a\"",
            .tenacity => "&img=\"misc_big,0x25\"",
            else => "",
        };
    }
};

pub const ActivationType = enum(u8) {
    open_portal,
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
    obj_type: u16,
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
        return .{
            .activation_type = ActivationType.fromString(node.currentValue() orelse "IncrementStat"),
            .object_id = try node.getAttributeAlloc("objectId", allocator, ""),
            .obj_type = try node.getAttributeInt("objType", u16, std.math.maxInt(u16)),
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

    pub fn deinit(self: *ActivationData, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.object_id);
        allocator.free(self.dungeon_name);
    }
};

pub const StatIncrementData = struct {
    stat: StatType,
    amount: i16,

    pub fn parse(node: xml.Node) !StatIncrementData {
        return .{
            .stat = StatType.fromString(node.getAttribute("stat") orelse "MaxHP"),
            .amount = try node.getAttributeInt("amount", i16, 0),
        };
    }
};

pub const EffectInfo = struct {
    name: []const u8,
    description: []const u8,

    pub fn parse(node: xml.Node, allocator: std.mem.Allocator) !EffectInfo {
        return .{
            .name = try node.getAttributeAlloc("name", allocator, ""),
            .description = try node.getAttributeAlloc("description", allocator, ""),
        };
    }

    pub fn deinit(self: *EffectInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.description);
    }
};

pub const ItemProps = struct {
    consumable: bool,
    untradeable: bool,
    usable: bool,
    slot_type: ItemType,
    rarity: []const u8,
    aether_req: u8,
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
    extra_tooltip_data: ?[]EffectInfo,
    description: []const u8,

    pub fn parse(node: xml.Node, allocator: std.mem.Allocator) !ItemProps {
        var incr_it = node.iterate(&.{}, "IncrementStat");
        var incr_list = std.ArrayList(StatIncrementData).init(allocator);
        defer incr_list.deinit();
        while (incr_it.next()) |incr_node|
            try incr_list.append(try StatIncrementData.parse(incr_node));

        var activate_it = node.iterate(&.{}, "Activate");
        var activate_list = std.ArrayList(ActivationData).init(allocator);
        defer activate_list.deinit();
        while (activate_it.next()) |activate_node|
            try activate_list.append(try ActivationData.parse(activate_node, allocator));

        var extra_tooltip_it = node.iterate(&.{}, "ExtraTooltipData");
        var extra_tooltip_list = std.ArrayList(EffectInfo).init(allocator);
        defer extra_tooltip_list.deinit();
        while (extra_tooltip_it.next()) |extra_tooltip_node|
            try extra_tooltip_list.append(try EffectInfo.parse(extra_tooltip_node, allocator));

        const id = try node.getAttributeAlloc("id", allocator, "Unknown");

        return .{
            .consumable = node.elementExists("Consumable"),
            .untradeable = node.elementExists("Soulbound"),
            .usable = node.elementExists("Usable"),
            .slot_type = @enumFromInt(try node.getValueInt("SlotType", i8, 0)),
            .rarity = try node.getValueAlloc("Rarity", allocator, "Unknown"),
            .aether_req = try node.getValueInt("AetherReq", u8, 0),
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
            .activations = try allocator.dupe(ActivationData, activate_list.items),
            .sound = try node.getValueAlloc("Sound", allocator, "Unknown"),
            .cooldown = try node.getValueFloat("Cooldown", f32, 0.5),
            .extra_tooltip_data = try allocator.dupe(EffectInfo, extra_tooltip_list.items),
            .description = try node.getValueAlloc("Description", allocator, ""),
        };
    }

    pub fn deinit(self: *ItemProps, allocator: std.mem.Allocator) void {
        if (self.stat_increments) |incr| {
            allocator.free(incr);
        }

        if (self.activations) |activate| {
            for (activate) |*data| {
                data.deinit(allocator);
            }
            allocator.free(activate);
        }

        if (self.extra_tooltip_data) |data| {
            for (data) |*effect| {
                effect.deinit(allocator);
            }
            allocator.free(data);
        }

        allocator.free(self.texture_data.sheet);
        allocator.free(self.rarity);
        allocator.free(self.sound);
        allocator.free(self.id);
        allocator.free(self.display_id);
        allocator.free(self.description);

        if (self.projectile) |*props| {
            props.deinit(allocator);
        }
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

    pub fn toString(self: ItemType) []const u8 {
        return switch (self) {
            .boots => "Boots",
            .artifact => "Artifact",
            .consumable => "Consumable",
            .sword => "Sword",
            .bow => "Bow",
            .staff => "Staff",
            .leather => "Leather",
            .heavy => "Heavy",
            .robe => "Robe",
            .no_item, .any, .any_weapon, .any_armor => "Unknown",
        };
    }

    pub inline fn slotsMatch(self: ItemType, target: ItemType) bool {
        return self == target or self == .any or target == .any or
            std.mem.indexOfScalar(ItemType, &weapon_types, self) != null and target == .any_weapon or
            std.mem.indexOfScalar(ItemType, &weapon_types, target) != null and self == .any_weapon or
            std.mem.indexOfScalar(ItemType, &armor_types, self) != null and target == .any_armor or
            std.mem.indexOfScalar(ItemType, &armor_types, target) != null and self == .any_armor;
    }
};

pub const Currency = enum(u8) { gold = 0, gems = 1, crowns = 2 };

pub const RegionType = enum(u8) {
    spawn,
    store_1,
    store_2,
    store_3,
    desert_encounter,
    volcano_encounter,
    forest_encounter,
    desert_setpiece,
    volcano_setpiece,
    forest_setpiece,

    const map = std.ComptimeStringMap(RegionType, .{
        .{ "Spawn", .spawn },
        .{ "Store 1", .store_1 },
        .{ "Store 2", .store_2 },
        .{ "Store 3", .store_3 },
        .{ "Biome Desert Encounter Spawn", .desert_encounter },
        .{ "Biome Volcano Encounter Spawn", .volcano_encounter },
        .{ "Biome Forest Encounter Spawn", .forest_encounter },
        .{ "Biome Desert Setpiece Spawn", .desert_encounter },
        .{ "Biome Volcano Setpiece Spawn", .volcano_encounter },
        .{ "Biome Forest Setpiece Spawn", .forest_encounter },
    });

    pub fn fromString(str: []const u8) RegionType {
        return map.get(str) orelse .store_1;
    }
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

pub var classes: std.AutoHashMap(u16, CharacterClass) = undefined;
pub var card_type_to_props: std.AutoHashMap(u16, CardProps) = undefined;
pub var item_name_to_type: std.HashMap([]const u8, u16, StringContext, 80) = undefined;
pub var item_type_to_props: std.AutoHashMap(u16, ItemProps) = undefined;
pub var item_type_to_name: std.AutoHashMap(u16, []const u8) = undefined;
pub var obj_name_to_type: std.HashMap([]const u8, u16, StringContext, 80) = undefined;
pub var obj_type_to_props: std.AutoHashMap(u16, ObjProps) = undefined;
pub var obj_type_to_name: std.AutoHashMap(u16, []const u8) = undefined;
pub var obj_type_to_tex_data: std.AutoHashMap(u16, []const TextureData) = undefined;
pub var obj_type_to_top_tex_data: std.AutoHashMap(u16, []const TextureData) = undefined;
pub var obj_type_to_anim_data: std.AutoHashMap(u16, AnimProps) = undefined;
pub var obj_type_to_class: std.AutoHashMap(u16, ClassType) = undefined;
pub var ground_name_to_type: std.HashMap([]const u8, u16, StringContext, 80) = undefined;
pub var ground_type_to_props: std.AutoHashMap(u16, GroundProps) = undefined;
pub var ground_type_to_name: std.AutoHashMap(u16, []const u8) = undefined;
pub var ground_type_to_tex_data: std.AutoHashMap(u16, []const TextureData) = undefined;
pub var region_type_to_name: std.AutoHashMap(u8, []const u8) = undefined;
pub var region_type_to_color: std.AutoHashMap(u8, u32) = undefined;
pub var region_type_to_enum: std.AutoHashMap(u8, RegionType) = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    classes = std.AutoHashMap(u16, CharacterClass).init(allocator);
    card_type_to_props = std.AutoHashMap(u16, CardProps).init(allocator);
    item_name_to_type = std.HashMap([]const u8, u16, StringContext, 80).init(allocator);
    item_type_to_props = std.AutoHashMap(u16, ItemProps).init(allocator);
    item_type_to_name = std.AutoHashMap(u16, []const u8).init(allocator);
    obj_name_to_type = std.HashMap([]const u8, u16, StringContext, 80).init(allocator);
    obj_type_to_props = std.AutoHashMap(u16, ObjProps).init(allocator);
    obj_type_to_name = std.AutoHashMap(u16, []const u8).init(allocator);
    obj_type_to_tex_data = std.AutoHashMap(u16, []const TextureData).init(allocator);
    obj_type_to_top_tex_data = std.AutoHashMap(u16, []const TextureData).init(allocator);
    obj_type_to_anim_data = std.AutoHashMap(u16, AnimProps).init(allocator);
    obj_type_to_class = std.AutoHashMap(u16, ClassType).init(allocator);
    ground_name_to_type = std.HashMap([]const u8, u16, StringContext, 80).init(allocator);
    ground_type_to_props = std.AutoHashMap(u16, GroundProps).init(allocator);
    ground_type_to_name = std.AutoHashMap(u16, []const u8).init(allocator);
    ground_type_to_tex_data = std.AutoHashMap(u16, []const TextureData).init(allocator);
    region_type_to_name = std.AutoHashMap(u8, []const u8).init(allocator);
    region_type_to_color = std.AutoHashMap(u8, u32).init(allocator);
    region_type_to_enum = std.AutoHashMap(u8, RegionType).init(allocator);

    const xmls_dir = try std.fs.cwd().openDir("./assets/xmls", .{ .iterate = true });
    var walker = try xmls_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (std.mem.endsWith(u8, entry.path, ".xml")) {
            const path = std.fmt.allocPrintZ(allocator, "./assets/xmls/{s}", .{entry.path}) catch continue;
            defer allocator.free(path);

            const doc = try xml.Doc.fromFile(path);
            defer doc.deinit();

            const root_node = doc.getRootElement() catch {
                std.log.err("Invalid XML in path {s}", .{path});
                continue;
            };

            const root_name = std.mem.span(root_node.impl.name);
            if (std.mem.eql(u8, root_name, "Items")) {
                parseItems(doc, allocator) catch |e| {
                    std.log.err("Item parsing error for path {s}: {}", .{ path, e });
                };
            } else if (std.mem.eql(u8, root_name, "Objects")) {
                parseObjects(doc, allocator) catch |e| {
                    std.log.err("Object parsing error for path {s}: {}", .{ path, e });
                };
            } else if (std.mem.eql(u8, root_name, "GroundTypes")) {
                parseGrounds(doc, allocator) catch |e| {
                    std.log.err("Ground parsing error for path {s}: {}", .{ path, e });
                };
            } else if (std.mem.eql(u8, root_name, "Regions")) {
                parseRegions(doc, allocator) catch |e| {
                    std.log.err("Region parsing error for path {s}: {}", .{ path, e });
                };
            } else if (std.mem.eql(u8, root_name, "Cards")) {
                parseCards(doc, allocator) catch |e| {
                    std.log.err("Card parsing error for path {s}: {}", .{ path, e });
                };
            } else {
                std.log.err("Invalid root node for path {s}: {s}", .{ path, root_name });
            }

            if (@errorReturnTrace()) |trace| {
                std.debug.dumpStackTrace(trace.*);
            }
        }
    }

    const player_doc = try xml.Doc.fromFile("./assets/xmls/players.xml");
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
    while (obj_props_iter.next()) |props| {
        props.deinit(allocator);
    }

    var card_props_iter = card_type_to_props.valueIterator();
    while (card_props_iter.next()) |props| {
        props.deinit(allocator);
    }

    var item_props_iter = item_type_to_props.valueIterator();
    while (item_props_iter.next()) |props| {
        props.deinit(allocator);
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
            tex.deinit(allocator);
        }
        allocator.free(tex_list.*);
    }

    var obj_tex_iter = obj_type_to_tex_data.valueIterator();
    while (obj_tex_iter.next()) |tex_list| {
        for (tex_list.*) |tex| {
            tex.deinit(allocator);
        }
        allocator.free(tex_list.*);
    }

    var obj_top_tex_iter = obj_type_to_top_tex_data.valueIterator();
    while (obj_top_tex_iter.next()) |tex_list| {
        for (tex_list.*) |tex| {
            tex.deinit(allocator);
        }
        allocator.free(tex_list.*);
    }

    var class_iter = classes.valueIterator();
    while (class_iter.next()) |class| {
        class.deinit(allocator);
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
        const obj_type = try node.getAttributeInt("type", u8, 0);
        const id = try node.getAttributeAlloc("id", allocator, "Unknown");
        try region_type_to_name.put(obj_type, id);
        try region_type_to_color.put(obj_type, try node.getValueInt("Color", u32, 0));
        try region_type_to_enum.put(obj_type, RegionType.fromString(id));
    }
}

pub fn parseCards(doc: xml.Doc, allocator: std.mem.Allocator) !void {
    const root = try doc.getRootElement();
    var iter = root.iterate(&.{}, "Card");
    while (iter.next()) |node| {
        const card_type = try node.getAttributeInt("type", u16, 0);
        try card_type_to_props.put(card_type, try CardProps.parse(node, allocator));
    }
}
