const std = @import("std");

const game_data = @import("game_data.zig");
const utils = @import("utils.zig");

pub const Rank = enum(u8) {
    default = 0,
    celestial = 10,
    mod = 90,
    admin = 100,

    pub fn printName(self: Rank) []const u8 {
        return switch (self) {
            .default => "Default",
            .celestial => "Celestial",
            .mod => "Mod",
            .admin => "Admin",
        };
    }
};

pub const CharacterListData = struct {
    name: []const u8,
    token: u128,
    rank: Rank,
    next_char_id: u32,
    gold: u32,
    gems: u32,
    characters: []const CharacterData,
    servers: []const ServerData,
};

pub const CharacterData = struct {
    char_id: u32,
    class_id: u16,
    celestial: bool,
    aether: u8,
    spirits_communed: u32,
    equips: [4]u16,
    keystone_talent_perc: f32,
    ability_talent_perc: f32,
    minor_talent_perc: f32,
    common_card_count: u8,
    rare_card_count: u8,
    epic_card_count: u8,
    legendary_card_count: u8,
    mythic_card_count: u8,
};

pub const ServerData = struct {
    name: []const u8,
    ip: []const u8,
    port: u16,
    max_players: u16,
    admin_only: bool,
};

pub const AbilityState = packed struct(u8) {
    heart_of_stone: bool = false,
    time_dilation: bool = false,
    time_lock: bool = false,
    equivalent_exchange: bool = false,
    asset_bubble: bool = false,
    post_asset_bubble: bool = false,
    premium_protection: bool = false,
    compound_interest: bool = false,
};

pub const ItemData = packed struct(u32) {
    amount: u16 = 0, // reuse for level progress
    unused: u16 = 0,
};

pub const PlayerStat = union(enum) {
    x: f32,
    y: f32,
    size_mult: f32,
    name: []const u8,
    cards: []const u16,
    resources: []const DataIdWithCount(u32),
    talents: []const DataIdWithCount(u16),
    rank: Rank,
    aether: u8,
    spirits_communed: u32,
    gold: u32,
    gems: u32,
    condition: utils.Condition,
    muted_until: i64,
    damage_mult: f32,
    hit_mult: f32,
    ability_state: AbilityState,
    hp: i32,
    mp: i32,
    max_hp: i32,
    max_mp: i32,
    strength: i16,
    wit: i16,
    defense: i16,
    resistance: i16,
    speed: i16,
    stamina: i16,
    intelligence: i16,
    haste: i16,
    max_hp_bonus: i32,
    max_mp_bonus: i32,
    strength_bonus: i16,
    wit_bonus: i16,
    defense_bonus: i16,
    resistance_bonus: i16,
    speed_bonus: i16,
    stamina_bonus: i16,
    intelligence_bonus: i16,
    haste_bonus: i16,
    inv_0: u16,
    inv_1: u16,
    inv_2: u16,
    inv_3: u16,
    inv_4: u16,
    inv_5: u16,
    inv_6: u16,
    inv_7: u16,
    inv_8: u16,
    inv_9: u16,
    inv_10: u16,
    inv_11: u16,
    inv_12: u16,
    inv_13: u16,
    inv_14: u16,
    inv_15: u16,
    inv_16: u16,
    inv_17: u16,
    inv_18: u16,
    inv_19: u16,
    inv_20: u16,
    inv_21: u16,
    inv_data_0: ItemData,
    inv_data_1: ItemData,
    inv_data_2: ItemData,
    inv_data_3: ItemData,
    inv_data_4: ItemData,
    inv_data_5: ItemData,
    inv_data_6: ItemData,
    inv_data_7: ItemData,
    inv_data_8: ItemData,
    inv_data_9: ItemData,
    inv_data_10: ItemData,
    inv_data_11: ItemData,
    inv_data_12: ItemData,
    inv_data_13: ItemData,
    inv_data_14: ItemData,
    inv_data_15: ItemData,
    inv_data_16: ItemData,
    inv_data_17: ItemData,
    inv_data_18: ItemData,
    inv_data_19: ItemData,
    inv_data_20: ItemData,
    inv_data_21: ItemData,
};

pub const EntityStat = union(enum) {
    x: f32,
    y: f32,
    size_mult: f32,
    name: []const u8,
    hp: i32,
};

pub const EnemyStat = union(enum) {
    x: f32,
    y: f32,
    size_mult: f32,
    name: []const u8,
    hp: i32,
    max_hp: i32,
    condition: utils.Condition,
};

pub const PortalStat = union(enum) {
    x: f32,
    y: f32,
    size_mult: f32,
    name: []const u8,
};

pub const ContainerStat = union(enum) {
    x: f32,
    y: f32,
    size_mult: f32,
    name: []const u8,
    inv_0: u16,
    inv_1: u16,
    inv_2: u16,
    inv_3: u16,
    inv_4: u16,
    inv_5: u16,
    inv_6: u16,
    inv_7: u16,
    inv_8: u16,
    inv_data_0: ItemData,
    inv_data_1: ItemData,
    inv_data_2: ItemData,
    inv_data_3: ItemData,
    inv_data_4: ItemData,
    inv_data_5: ItemData,
    inv_data_6: ItemData,
    inv_data_7: ItemData,
    inv_data_8: ItemData,
};

pub const AllyStat = union(enum) {
    x: f32,
    y: f32,
    size_mult: f32,
    condition: utils.Condition,
    hp: i32,
    max_hp: i32,
    owner_map_id: u32,
};

pub fn DataIdWithCount(CountType: type) type {
    return packed struct { count: CountType, data_id: u16 };
}

pub const TileData = packed struct {
    x: u16,
    y: u16,
    data_id: u16,
};

pub const TimedPosition = packed struct {
    time: i64,
    x: f32,
    y: f32,
};

pub const ObjectType = enum(u8) {
    player,
    entity,
    enemy,
    container,
    portal,
    ally,
};

pub const ObjectData = struct {
    data_id: u16,
    map_id: u32,
    stats: []const u8,
};

pub const MapInfo = struct {
    width: u16 = 0,
    height: u16 = 0,
    name: []const u8 = "",
    bg_color: u32 = 0,
    bg_intensity: f32 = 0.0,
    day_intensity: f32 = 0.0,
    night_intensity: f32 = 0.0,
    server_time: i64 = 0,
    player_map_id: u32 = std.math.maxInt(u32),
};

pub const DamageType = enum(u8) { physical, magic, true };
pub const ErrorType = enum(u8) {
    message_no_disconnect,
    message_with_disconnect,
    client_update_needed,
    force_close_game,
    invalid_teleport_target,
};

// All packets without variable length fields (like slices) should be extern, with proper alignment ordering.
// This allows us to directly copy the struct into/from the buffer
pub const C2SPacket = union(enum) {
    player_projectile: extern struct { time: i64, x: f32, y: f32, angle: f32, proj_index: u8 },
    move: struct { tick_id: u8, time: i64, x: f32, y: f32, records: []const TimedPosition },
    player_text: struct { text: []const u8 },
    inv_swap: extern struct {
        time: i64,
        x: f32,
        y: f32,
        from_map_id: u32,
        to_map_id: u32,
        from_obj_type: ObjectType,
        from_slot_id: u8,
        to_obj_type: ObjectType,
        to_slot_id: u8,
    },
    use_item: extern struct { time: i64, map_id: u32, x: f32, y: f32, obj_type: ObjectType, slot_id: u8 },
    hello: struct { build_ver: []const u8, email: []const u8, token: u128, char_id: u32, class_id: u16 },
    inv_drop: extern struct { player_map_id: u32, slot_id: u8 },
    pong: extern struct { ping_time: i64, time: i64 },
    teleport: extern struct { player_map_id: u32 },
    use_portal: extern struct { portal_map_id: u32 },
    ground_damage: extern struct { time: i64, x: f32, y: f32 },
    player_hit: extern struct { enemy_map_id: u32, proj_index: u8 },
    enemy_hit: extern struct { time: i64, enemy_map_id: u32, proj_index: u8, killed: bool },
    ally_hit: extern struct { ally_map_id: u32, enemy_map_id: u32, proj_index: u8 },
    escape: extern struct {},
    map_hello: struct { build_ver: []const u8, email: []const u8, token: u128, char_id: u32, map: []const u8 },
    use_ability: struct { time: i64, index: u8, data: []const u8 },
    select_card: extern struct { selection: enum(u8) { none, first, second, third } },
    talent_upgrade: extern struct { index: u8 },
};

pub const S2CPacket = union(enum) {
    text: struct {
        name: []const u8,
        obj_type: ObjectType,
        map_id: u32,
        bubble_time: u8,
        recipient: []const u8,
        text: []const u8,
        name_color: u32,
        text_color: u32,
    },
    damage: extern struct { player_map_id: u32, amount: i32, effects: utils.Condition, damage_type: DamageType },
    new_tick: struct { tick_id: u8, tiles: []const TileData },
    new_players: struct { list: []const ObjectData },
    new_enemies: struct { list: []const ObjectData },
    new_entities: struct { list: []const ObjectData },
    new_portals: struct { list: []const ObjectData },
    new_containers: struct { list: []const ObjectData },
    new_allies: struct { list: []const ObjectData },
    dropped_players: struct { map_ids: []const u32 },
    dropped_enemies: struct { map_ids: []const u32 },
    dropped_entities: struct { map_ids: []const u32 },
    dropped_portals: struct { map_ids: []const u32 },
    dropped_containers: struct { map_ids: []const u32 },
    dropped_allies: struct { map_ids: []const u32 },
    notification: struct { obj_type: ObjectType, map_id: u32, message: []const u8, color: u32 },
    show_effect: extern struct {
        map_id: u32,
        x1: f32,
        y1: f32,
        x2: f32,
        y2: f32,
        color: u32,
        eff_type: enum(u8) {
            potion,
            teleport,
            stream,
            throw,
            area_blast,
            dead,
            trail,
            diffuse,
            flow,
            trap,
            lightning,
            concentrate,
            blast_wave,
            earthquake,
            flashing,
        },
        obj_type: ObjectType,
    },
    inv_result: extern struct { result: u8 },
    ping: extern struct { time: i64 },
    map_info: MapInfo,
    death: struct { killer_name: []const u8 },
    aoe: struct { x: f32, y: f32, radius: f32, damage: u16, eff: utils.Condition, duration: f32, orig_type: u8, color: u32 },
    ally_projectile: extern struct { player_map_id: u32, angle: f32, item_data_id: u16, proj_index: u8 },
    enemy_projectile: extern struct {
        enemy_map_id: u32,
        x: f32,
        y: f32,
        phys_dmg: i32,
        magic_dmg: i32,
        true_dmg: i32,
        angle: f32,
        angle_incr: f32,
        proj_index: u8,
        proj_data_id: u8,
        num_projs: u8,
    },
    card_options: struct { cards: [3]u16 },
    talent_upgrade_response: struct { success: bool, message: []const u8 },
    @"error": struct { type: ErrorType, description: []const u8 },
};

pub const C2SPacketLogin = union(enum) {
    login: struct { email: []const u8, password: []const u8 },
    register: struct { name: []const u8, email: []const u8, password: []const u8, hwid: []const u8 },
    verify: struct { email: []const u8, token: u128 },
    delete: struct { email: []const u8, token: u128, char_id: u32 },
};

pub const S2CPacketLogin = union(enum) {
    login_response: CharacterListData,
    register_response: CharacterListData,
    verify_response: CharacterListData,
    delete_response: CharacterListData,
    @"error": struct { description: []const u8 },
};
