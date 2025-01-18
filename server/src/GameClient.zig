const std = @import("std");
const builtin = @import("builtin");

const shared = @import("shared");
const utils = shared.utils;
const game_data = shared.game_data;
const network_data = shared.network_data;
const uv = shared.uv;
const f32i = utils.f32i;
const u32f = utils.u32f;
const u16f = utils.u16f;
const i64f = utils.i64f;
const i32f = utils.i32f;

const command = @import("command.zig");
const db = @import("db.zig");
const main = @import("main.zig");
const abilities = @import("map/abilities.zig");
const Ally = @import("map/Ally.zig");
const Container = @import("map/Container.zig");
const Enemy = @import("map/Enemy.zig");
const Entity = @import("map/Entity.zig");
const maps = @import("map/maps.zig");
const Player = @import("map/Player.zig");
const Portal = @import("map/Portal.zig");
const Projectile = @import("map/Projectile.zig");
const World = @import("World.zig");

const Client = @This();

const WriteRequest = extern struct {
    request: uv.uv_write_t = .{},
    buffer: uv.uv_buf_t = .{},
};

socket: *uv.uv_tcp_t = undefined,
arena: std.heap.ArenaAllocator = undefined,
needs_shutdown: bool = false,
world: *World = undefined,
ip: []const u8 = "",
acc_id: u32 = std.math.maxInt(u32),
char_id: u32 = std.math.maxInt(u32),
player_map_id: u32 = std.math.maxInt(u32),

fn PacketData(comptime tag: @typeInfo(network_data.C2SPacket).@"union".tag_type.?) type {
    return @typeInfo(network_data.C2SPacket).@"union".fields[@intFromEnum(tag)].type;
}

fn handlerFn(comptime tag: @typeInfo(network_data.C2SPacket).@"union".tag_type.?) fn (*Client, PacketData(tag)) void {
    return switch (tag) {
        .player_projectile => handlePlayerProjectile,
        .move => handleMove,
        .player_text => handlePlayerText,
        .inv_swap => handleInvSwap,
        .use_item => handleUseItem,
        .hello => handleHello,
        .inv_drop => handleInvDrop,
        .pong => handlePong,
        .teleport => handleTeleport,
        .use_portal => handleUsePortal,
        .buy => handleBuy,
        .ground_damage => handleGroundDamage,
        .player_hit => handlePlayerHit,
        .enemy_hit => handleEnemyHit,
        .ally_hit => handleAllyHit,
        .escape => handleEscape,
        .map_hello => handleMapHello,
        .use_ability => handleUseAbility,
        .select_card => handleSelectCard,
        .talent_upgrade => handleTalentUpgrade,
    };
}

pub fn allocBuffer(socket: [*c]uv.uv_handle_t, suggested_size: usize, buf: [*c]uv.uv_buf_t) callconv(.C) void {
    const client: *Client = @ptrCast(@alignCast(socket.*.data));
    buf.* = .{
        .base = @ptrCast(client.arena.allocator().alloc(u8, suggested_size) catch {
            client.sameThreadShutdown(); // no failure, if we can't alloc it wouldn't go through anyway
            return;
        }),
        .len = @intCast(suggested_size),
    };
}

fn closeCallback(socket: [*c]uv.uv_handle_t) callconv(.C) void {
    const client: *Client = @ptrCast(@alignCast(socket.*.data));

    removePlayer: {
        if (client.player_map_id == std.math.maxInt(u32)) break :removePlayer;
        client.world.remove(Player, client.world.find(Player, client.player_map_id, .ref) orelse break :removePlayer) catch break :removePlayer;
    }

    main.socket_pool.destroy(client.socket);
    client.arena.deinit();
    main.game_client_pool.destroy(client);
}

fn writeCallback(ud: [*c]uv.uv_write_t, status: c_int) callconv(.C) void {
    const wr: *WriteRequest = @ptrCast(ud);
    const client: *Client = @ptrCast(@alignCast(wr.request.data));

    if (status != 0) {
        client.sendError(.message_with_disconnect, "Socket write error");
        return;
    }

    const arena_allocator = client.arena.allocator();
    arena_allocator.free(wr.buffer.base[0..wr.buffer.len]);
    arena_allocator.destroy(wr);
}

pub fn readCallback(ud: *anyopaque, bytes_read: isize, buf: [*c]const uv.uv_buf_t) callconv(.C) void {
    const socket: *uv.uv_stream_t = @ptrCast(@alignCast(ud));
    const client: *Client = @ptrCast(@alignCast(socket.data));

    const arena_allocator = client.arena.allocator();
    var child_arena: std.heap.ArenaAllocator = .init(arena_allocator);
    defer child_arena.deinit();
    const child_arena_allocator = child_arena.allocator();

    if (bytes_read > 0) {
        var reader: utils.PacketReader = .{ .buffer = buf.*.base[0..@intCast(bytes_read)] };

        while (reader.index <= bytes_read - 3) {
            defer _ = child_arena.reset(.retain_capacity);

            const len = reader.read(u16, child_arena_allocator);
            if (len > bytes_read - reader.index) return;

            const next_packet_idx = reader.index + len;
            const EnumType = @typeInfo(network_data.C2SPacket).@"union".tag_type.?;
            const byte_id = reader.read(std.meta.Int(.unsigned, @bitSizeOf(EnumType)), child_arena_allocator);
            const packet_id = std.meta.intToEnum(EnumType, byte_id) catch |e| {
                std.log.err("Error parsing C2SPacket ({}): id={}, size={}, len={}", .{ e, byte_id, bytes_read, len });
                client.sendError(.message_with_disconnect, "Socket read error");
                return;
            };

            switch (packet_id) {
                inline else => |id| handlerFn(id)(client, reader.read(PacketData(id), child_arena_allocator)),
            }

            if (reader.index < next_packet_idx) {
                std.log.err("C2S packet {} has {} bytes left over", .{ packet_id, next_packet_idx - reader.index });
                reader.index = next_packet_idx;
            }
        }
    } else if (bytes_read < 0) {
        if (bytes_read != uv.UV_EOF) {
            client.sendError(.message_with_disconnect, "Socket read error");
        } else client.sameThreadShutdown();
        return;
    }

    arena_allocator.free(buf.*.base[0..@intCast(buf.*.len)]);
}

fn asyncCloseCallback(_: [*c]uv.uv_handle_t) callconv(.C) void {}

pub fn shutdownCallback(handle: [*c]uv.uv_async_t) callconv(.C) void {
    const client: *Client = @ptrCast(@alignCast(handle.*.data));
    client.sameThreadShutdown();
}

pub fn sameThreadShutdown(self: *Client) void {
    if (uv.uv_is_closing(@ptrCast(self.socket)) == 0) uv.uv_close(@ptrCast(self.socket), closeCallback);
}

pub fn queuePacket(self: *Client, packet: network_data.S2CPacket) void {
    switch (packet) {
        inline else => |data| {
            const arena_allocator = self.arena.allocator();

            var writer: utils.PacketWriter = .{};
            writer.writeLength(arena_allocator);
            writer.write(@intFromEnum(std.meta.activeTag(packet)), arena_allocator);
            writer.write(data, arena_allocator);
            writer.updateLength();

            const wr: *WriteRequest = arena_allocator.create(WriteRequest) catch main.oomPanic();
            wr.buffer.base = @ptrCast(writer.list.items);
            wr.buffer.len = @intCast(writer.list.items.len);
            wr.request.data = @ptrCast(self);
            const write_status = uv.uv_write(@ptrCast(wr), @ptrCast(self.socket), @ptrCast(&wr.buffer), 1, writeCallback);
            if (write_status != 0) {
                self.sameThreadShutdown();
                return;
            }
        },
    }

    if (packet == .@"error") self.sameThreadShutdown();
}

pub fn sendMessage(self: *Client, msg: []const u8) void {
    self.queuePacket(.{ .text = .{
        .name = "Server",
        .obj_type = .entity,
        .map_id = std.math.maxInt(u32),
        .bubble_time = 0,
        .recipient = "",
        .text = msg,
        .name_color = 0xCC00CC,
        .text_color = 0xFF99FF,
    } });
}

pub fn sendError(self: *Client, error_type: network_data.ErrorType, message: []const u8) void {
    self.queuePacket(.{ .@"error" = .{ .type = error_type, .description = message } });
}

fn processItemCosts(player: *Player, data: game_data.ItemData) void {
    if (data.mana_cost) |cost| if (player.mp >= cost.amount) {
        if (utils.rng.random().float(f32) <= cost.chance) player.mp = @intCast(@max(0, player.mp - cost.amount));
    } else return;
    if (data.health_cost) |cost| if (player.hp > cost.amount) {
        if (utils.rng.random().float(f32) <= cost.chance) player.hp = @intCast(@max(0, player.hp - cost.amount));
    } else return;
    if (data.gold_cost) |cost| if (player.gold >= cost.amount) {
        if (utils.rng.random().float(f32) <= cost.chance) player.gold = @intCast(@max(0, player.gold - cost.amount));
    } else return;
}

fn handlePlayerProjectile(self: *Client, data: PacketData(.player_projectile)) void {
    const player = self.world.find(Player, self.player_map_id, .ref) orelse return;
    if (player.condition.stunned) return;
    const item_data = game_data.item.from_id.getPtr(player.inventory[0]) orelse return;
    processItemCosts(player, item_data.*);

    const proj_data = item_data.projectile orelse return;

    const map_id = self.world.add(Projectile, .{
        .x = data.x,
        .y = data.y,
        .owner_obj_type = .player,
        .owner_map_id = self.player_map_id,
        .angle = data.angle,
        .start_time = main.current_time,
        .phys_dmg = proj_data.phys_dmg,
        .magic_dmg = proj_data.magic_dmg,
        .true_dmg = proj_data.true_dmg,
        .index = data.proj_index,
        .data = &item_data.projectile.?,
    }) catch return;

    player.projectiles[data.proj_index] = map_id;
}

fn handleMove(self: *Client, data: PacketData(.move)) void {
    if (data.x < 0.0 or data.y < 0.0) return;

    const player = self.world.find(Player, self.player_map_id, .ref) orelse {
        self.sendError(.message_with_disconnect, "Player not found");
        return;
    };
    if (player.condition.paralyzed) return;

    const idx = u32f(data.y) * @as(u32, self.world.w) + u32f(data.x);
    if (idx > self.world.tiles.len) {
        self.sendError(.message_with_disconnect, "Invalid position");
        return;
    }

    const tile = self.world.tiles[idx];
    if (tile.data.no_walk or tile.occupied) {
        self.sendError(.message_with_disconnect, "Tile occupied");
        return;
    }

    player.x = data.x;
    player.y = data.y;
}

fn handlePlayerText(self: *Client, data: PacketData(.player_text)) void {
    if (data.text.len == 0 or data.text.len > 256) return;

    const player = self.world.find(Player, self.player_map_id, .ref) orelse return;
    if (data.text[0] == '/') {
        var split = std.mem.splitScalar(u8, data.text, ' ');
        command.handle(&split, player);
        return;
    }

    if (player.muted_until >= main.current_time) return;

    for (self.world.listForType(Player).items) |*other_player| {
        other_player.client.queuePacket(.{ .text = .{
            .name = player.name,
            .obj_type = .player,
            .map_id = self.player_map_id,
            .bubble_time = 0,
            .recipient = "",
            .text = data.text,
            .name_color = if (@intFromEnum(player.rank) >= @intFromEnum(network_data.Rank.mod)) 0xF2CA46 else 0xEBEBEB,
            .text_color = if (@intFromEnum(player.rank) >= @intFromEnum(network_data.Rank.mod)) 0xD4AF37 else 0xB0B0B0,
        } });
    }
}

fn verifySwap(item_id: u16, target_type: game_data.ItemType) bool {
    const item_type = blk: {
        if (item_id == std.math.maxInt(u16)) break :blk .any;
        break :blk (game_data.item.from_id.get(item_id) orelse return false).item_type;
    };
    return item_type.typesMatch(target_type);
}

fn handleInvSwap(self: *Client, data: PacketData(.inv_swap)) void {
    switch (data.from_obj_type) {
        .player => if (self.world.find(Player, data.from_map_id, .ref)) |player| {
            const start = player.inventory[data.from_slot_id];
            switch (data.to_obj_type) {
                .player => {
                    if (!verifySwap(start, if (data.to_slot_id < 4) player.data.item_types[data.to_slot_id] else .any) or
                        !verifySwap(player.inventory[data.to_slot_id], if (data.from_slot_id < 4) player.data.item_types[data.from_slot_id] else .any))
                        return;
                    player.inventory[data.from_slot_id] = player.inventory[data.to_slot_id];
                    player.inventory[data.to_slot_id] = start;
                },
                .container => if (self.world.find(Container, data.to_map_id, .ref)) |cont| {
                    if (!verifySwap(cont.inventory[data.to_slot_id], if (data.from_slot_id < 4) player.data.item_types[data.from_slot_id] else .any))
                        return;
                    player.inventory[data.from_slot_id] = cont.inventory[data.to_slot_id];
                    cont.inventory[data.to_slot_id] = start;
                } else return,
                else => return,
            }

            player.recalculateItems();
        } else return,
        .container => if (self.world.find(Container, data.from_map_id, .ref)) |cont| {
            const start = cont.inventory[data.from_slot_id];
            switch (data.to_obj_type) {
                .player => if (self.world.find(Player, data.to_map_id, .ref)) |player| {
                    if (!verifySwap(start, if (data.to_slot_id < 4) player.data.item_types[data.to_slot_id] else .any))
                        return;
                    cont.inventory[data.from_slot_id] = player.inventory[data.to_slot_id];
                    player.inventory[data.to_slot_id] = start;
                    player.recalculateItems();
                } else return,
                .container => if (self.world.find(Container, data.to_map_id, .ref)) |other_cont| {
                    cont.inventory[data.from_slot_id] = other_cont.inventory[data.to_slot_id];
                    other_cont.inventory[data.to_slot_id] = start;
                } else return,
                else => return,
            }
        } else return,
        else => return,
    }
}

fn processActivations(player: *Player, activations: []const game_data.ActivationData) void {
    for (activations) |activation| switch (activation) {
        .create_ally => |val| {
            const data = game_data.ally.from_name.get(val.name) orelse continue;

            const fhst = f32i(player.stats[Player.haste_stat] + player.stat_boosts[Player.haste_stat]);
            const duration = i64f((10.0 + fhst * 0.2) * std.time.us_per_s);
            const angle = utils.rng.random().float(f32) * std.math.tau;
            const radius = utils.rng.random().float(f32) * 2.0;
            const x = player.x + radius * @cos(angle);
            const y = player.y + radius * @sin(angle);

            _ = player.world.add(Ally, .{
                .x = x,
                .y = y,
                .data_id = data.id,
                .owner_map_id = player.map_id,
                .disappear_time = main.current_time + duration,
            }) catch continue; // TODO
        },
        else => {},
    };
}

fn handleUseItem(self: *Client, data: PacketData(.use_item)) void {
    const player = self.world.find(Player, self.player_map_id, .ref) orelse return;
    switch (data.obj_type) {
        .player => {
            defer player.inventory[data.slot_id] = std.math.maxInt(u16);
            const item_data = game_data.item.from_id.get(player.inventory[data.slot_id]) orelse return;
            if (item_data.activations) |activations| processActivations(player, activations);
            processItemCosts(player, item_data);
        },
        .container => if (self.world.find(Container, data.map_id, .ref)) |cont| {
            defer cont.inventory[data.slot_id] = std.math.maxInt(u16);
            const item_data = game_data.item.from_id.get(cont.inventory[data.slot_id]) orelse return;
            if (item_data.activations) |activations| processActivations(player, activations);
            processItemCosts(player, item_data);
        } else return,
        else => return,
    }
}

fn createChar(player: *Player, class_id: u16, timestamp: u64) !void {
    if (game_data.class.from_id.get(class_id)) |class_data| {
        const max_slots = try player.acc_data.get(.max_char_slots);
        const alive_ids: []const u32 = player.acc_data.get(.alive_char_ids) catch &.{};
        if (alive_ids.len >= max_slots)
            return error.SlotsFull;

        const next_char_id = try player.acc_data.get(.next_char_id);
        player.char_data.char_id = next_char_id;
        try player.acc_data.set(.{ .next_char_id = next_char_id + 1 });

        const new_alive_ids = try std.mem.concat(player.client.arena.allocator(), u32, &.{ alive_ids, &.{next_char_id} });
        try player.acc_data.set(.{ .alive_char_ids = new_alive_ids });

        try player.char_data.set(.{ .class_id = class_id });
        try player.char_data.set(.{ .create_timestamp = timestamp });

        var stats: [13]i32 = undefined;
        stats[Player.health_stat] = class_data.stats.health;
        stats[Player.mana_stat] = class_data.stats.mana;
        stats[Player.strength_stat] = class_data.stats.strength;
        stats[Player.wit_stat] = class_data.stats.wit;
        stats[Player.defense_stat] = class_data.stats.defense;
        stats[Player.resistance_stat] = class_data.stats.resistance;
        stats[Player.speed_stat] = class_data.stats.speed;
        stats[Player.stamina_stat] = class_data.stats.stamina;
        stats[Player.intelligence_stat] = class_data.stats.intelligence;
        stats[Player.penetration_stat] = class_data.stats.penetration;
        stats[Player.piercing_stat] = class_data.stats.piercing;
        stats[Player.haste_stat] = class_data.stats.haste;
        stats[Player.tenacity_stat] = class_data.stats.tenacity;
        try player.char_data.set(.{ .hp = class_data.stats.health });
        try player.char_data.set(.{ .mp = class_data.stats.mana });
        try player.char_data.set(.{ .stats = stats });
        var starting_inventory: [22]u16 = @splat(std.math.maxInt(u16));
        for (class_data.default_items, 0..) |item, i|
            starting_inventory[i] = (game_data.item.from_name.get(item) orelse return error.UnknownStartItem).id;
        try player.char_data.set(.{ .inventory = starting_inventory });
        try player.char_data.set(.{ .item_data = @splat(@bitCast(@as(u32, 0))) });
    } else return error.InvalidCharId;
}

fn handleHello(self: *Client, data: PacketData(.hello)) void {
    if (self.player_map_id != std.math.maxInt(u32)) {
        self.sendError(.message_with_disconnect, "Already connected");
        return;
    }

    if (!std.mem.eql(u8, data.build_ver, main.settings.build_version)) {
        self.sendError(.message_with_disconnect, "Incorrect version");
        return;
    }

    const acc_id = db.login(data.email, data.token) catch |e| {
        switch (e) {
            error.NoData => self.sendError(.message_with_disconnect, "Invalid email"),
            error.InvalidToken => self.sendError(.message_with_disconnect, "Invalid token"),
        }
        return;
    };
    self.acc_id = acc_id;

    var player: Player = .{
        .acc_data = .{ .acc_id = acc_id },
        .char_data = .{ .acc_id = acc_id, .char_id = data.char_id },
        .client = self,
    };

    const is_banned = db.accountBanned(&player.acc_data) catch {
        self.sendError(.message_with_disconnect, "Database error (check)");
        return;
    };
    if (is_banned) {
        self.sendError(.message_with_disconnect, "Account banned");
        return;
    }

    const locked_until = player.acc_data.get(.locked_until) catch {
        self.sendError(.message_with_disconnect, "Failed to acquire lock");
        return;
    };

    const timestamp: u64 = @intCast(std.time.milliTimestamp());
    if (locked_until > timestamp) {
        self.sendError(.message_with_disconnect, "Account is locked");
        return;
    }

    if (data.class_id != std.math.maxInt(u16)) {
        createChar(&player, data.class_id, timestamp) catch {
            self.sendError(.message_with_disconnect, "Character creation failed");
            return;
        };
    }

    self.char_id = player.char_data.char_id;
    player.char_data.set(.{ .last_login_timestamp = timestamp }) catch {
        self.sendError(.message_with_disconnect, "Database error (login)");
        return;
    };
    player.acc_data.set(.{ .locked_until = timestamp + 300 * std.time.ms_per_s }) catch {
        self.sendError(.message_with_disconnect, "Could not interact with database");
        return;
    };

    self.world = maps.worlds.getPtr(maps.retrieve_id) orelse {
        self.sendError(.message_with_disconnect, "Retrieve does not exist");
        return;
    };

    self.player_map_id = self.world.add(Player, player) catch {
        self.sendError(.message_with_disconnect, "Adding player to map failed");
        return;
    };

    self.queuePacket(.{ .map_info = .{
        .width = self.world.w,
        .height = self.world.h,
        .name = self.world.name,
        .bg_color = self.world.light_data.color,
        .bg_intensity = self.world.light_data.intensity,
        .day_intensity = self.world.light_data.day_intensity,
        .night_intensity = self.world.light_data.night_intensity,
        .server_time = main.current_time,
        .player_map_id = self.player_map_id,
    } });
}

fn handleInvDrop(self: *Client, data: PacketData(.inv_drop)) void {
    const player = self.world.find(Player, data.player_map_id, .ref) orelse return;
    var inventory = Container.inv_default;
    inventory[0] = player.inventory[data.slot_id];
    _ = self.world.add(Container, .{
        .x = player.x,
        .y = player.y,
        .data_id = game_data.item.from_id.get(inventory[0]).?.rarity.containerDataId(),
        .name = main.allocator.dupe(u8, player.name) catch main.oomPanic(),
        .free_name = true,
        .inventory = inventory,
    }) catch {
        self.sendError(.message_with_disconnect, "Bag spawning failed");
        return;
    };

    player.inventory[data.slot_id] = std.math.maxInt(u16);
    player.recalculateItems();
}

fn handlePong(_: *Client, _: PacketData(.pong)) void {}

fn handleTeleport(_: *Client, _: PacketData(.teleport)) void {}

fn handleUsePortal(self: *Client, data: PacketData(.use_portal)) void {
    const portal_map_id = if (self.world.find(Portal, data.portal_map_id, .con)) |e| e.data_id else {
        self.sendMessage("Portal not found");
        return;
    };

    const new_world = maps.portalWorld(portal_map_id, data.portal_map_id) catch {
        self.sendMessage("Map load failed");
        return;
    } orelse {
        self.sendMessage("Map does not exist");
        return;
    };

    const player = self.world.find(Player, self.player_map_id, .ref) orelse {
        self.sendError(.message_with_disconnect, "Player does not exist");
        return;
    };
    player.clearEphemerals();
    player.save() catch {
        self.sendError(.message_with_disconnect, "Player save failed");
        return;
    };

    self.world.remove(Player, player) catch {
        self.sendError(.message_with_disconnect, "Removing player from map failed");
        return;
    };

    self.world = new_world;

    self.player_map_id = self.world.add(Player, .{
        .acc_data = .{ .acc_id = self.acc_id },
        .char_data = .{ .acc_id = self.acc_id, .char_id = self.char_id },
        .client = self,
    }) catch {
        self.sendError(.message_with_disconnect, "Adding player to map failed");
        return;
    };

    self.queuePacket(.{ .map_info = .{
        .width = @intCast(self.world.w),
        .height = @intCast(self.world.h),
        .name = self.world.name,
        .bg_color = self.world.light_data.color,
        .bg_intensity = self.world.light_data.intensity,
        .day_intensity = self.world.light_data.day_intensity,
        .night_intensity = self.world.light_data.night_intensity,
        .server_time = main.current_time,
        .player_map_id = self.player_map_id,
    } });
}

fn handleBuy(_: *Client, _: PacketData(.buy)) void {}

fn handleGroundDamage(self: *Client, data: PacketData(.ground_damage)) void {
    const ux = u16f(data.x);
    const uy = u16f(data.y);
    const tile = self.world.tiles[uy * self.world.w + ux];
    if (tile.data_id == std.math.maxInt(u16)) return;

    const player = self.world.find(Player, self.player_map_id, .ref) orelse return;
    for (self.world.listForType(Player).items) |world_player| {
        if (world_player.map_id == self.player_map_id) continue;

        if (utils.distSqr(world_player.x, world_player.y, player.x, player.y) <= 16 * 16) {
            self.queuePacket(.{ .damage = .{
                .player_map_id = self.player_map_id,
                .effects = .{},
                .damage_type = .true,
                .amount = @intCast(tile.data.damage),
            } });
        }
    }

    player.hp -= tile.data.damage;
    if (player.hp <= 0) player.death(tile.data.name) catch return;
}

fn handlePlayerHit(self: *Client, data: PacketData(.player_hit)) void {
    const enemy = self.world.find(Enemy, data.enemy_map_id, .con) orelse return;
    const proj = self.world.find(Projectile, enemy.projectiles[data.proj_index] orelse return, .ref) orelse return;
    if (proj.player_hit_list.contains(self.player_map_id)) return;
    const player = self.world.find(Player, self.player_map_id, .ref) orelse return;
    player.damage(.enemy, enemy.map_id, proj.phys_dmg, proj.magic_dmg, proj.true_dmg);
    proj.player_hit_list.put(main.allocator, self.player_map_id, {}) catch return;
}

fn handleEnemyHit(self: *Client, data: PacketData(.enemy_hit)) void {
    const player = self.world.find(Player, self.player_map_id, .con) orelse return;
    const enemy = self.world.find(Enemy, data.enemy_map_id, .ref) orelse return;
    const proj = self.world.find(Projectile, player.projectiles[data.proj_index] orelse return, .ref) orelse return;

    enemy.damage(.player, self.player_map_id, proj.phys_dmg, proj.magic_dmg, proj.true_dmg);
    if (!proj.data.piercing) proj.delete() catch return;
}

fn handleAllyHit(self: *Client, data: PacketData(.ally_hit)) void {
    const enemy = self.world.find(Enemy, data.enemy_map_id, .con) orelse return;
    const proj = self.world.find(Projectile, enemy.projectiles[data.proj_index] orelse return, .ref) orelse return;
    if (proj.ally_hit_list.contains(data.ally_map_id)) return;
    const ally = self.world.find(Ally, data.ally_map_id, .ref) orelse return;
    ally.damage(.enemy, enemy.map_id, proj.phys_dmg, proj.magic_dmg, proj.true_dmg);
    proj.ally_hit_list.put(main.allocator, data.ally_map_id, {}) catch return;
}

fn handleEscape(self: *Client, _: PacketData(.escape)) void {
    const player = self.world.find(Player, self.player_map_id, .ref) orelse {
        self.sendError(.message_with_disconnect, "Player does not exist");
        return;
    };
    player.clearEphemerals();
    player.save() catch {
        self.sendError(.message_with_disconnect, "Player save failed");
        return;
    };

    self.world.remove(Player, player) catch {
        self.sendError(.message_with_disconnect, "Removing player from map failed");
        return;
    };

    self.world = maps.worlds.getPtr(maps.retrieve_id) orelse {
        self.sendError(.message_with_disconnect, "Retrieve does not exist");
        return;
    };

    self.player_map_id = self.world.add(Player, .{
        .acc_data = .{ .acc_id = self.acc_id },
        .char_data = .{ .acc_id = self.acc_id, .char_id = self.char_id },
        .client = self,
    }) catch {
        self.sendError(.message_with_disconnect, "Adding player to map failed");
        return;
    };

    self.queuePacket(.{ .map_info = .{
        .width = self.world.w,
        .height = self.world.h,
        .name = self.world.name,
        .bg_color = self.world.light_data.color,
        .bg_intensity = self.world.light_data.intensity,
        .day_intensity = self.world.light_data.day_intensity,
        .night_intensity = self.world.light_data.night_intensity,
        .server_time = main.current_time,
        .player_map_id = self.player_map_id,
    } });
}

fn handleMapHello(self: *Client, data: PacketData(.map_hello)) void {
    if (self.player_map_id != std.math.maxInt(u32)) {
        self.sendError(.message_with_disconnect, "Already connected");
        return;
    }

    if (!std.mem.eql(u8, data.build_ver, main.settings.build_version)) {
        self.sendError(.message_with_disconnect, "Incorrect version");
        return;
    }

    const acc_id = db.login(data.email, data.token) catch |e| {
        switch (e) {
            error.NoData => self.sendError(.message_with_disconnect, "Invalid email"),
            error.InvalidToken => self.sendError(.message_with_disconnect, "Invalid token"),
        }
        return;
    };
    self.acc_id = acc_id;

    var player: Player = .{
        .acc_data = .{ .acc_id = acc_id },
        .char_data = .{ .acc_id = acc_id, .char_id = data.char_id },
        .client = self,
    };

    const is_banned = db.accountBanned(&player.acc_data) catch {
        self.sendError(.message_with_disconnect, "Database is missing data");
        return;
    };
    if (is_banned) {
        self.sendError(.message_with_disconnect, "Account banned");
        return;
    }

    const locked_until = player.acc_data.get(.locked_until) catch {
        self.sendError(.message_with_disconnect, "Failed to acquire lock");
        return;
    };

    const timestamp: u64 = @intCast(std.time.milliTimestamp());
    if (locked_until > timestamp) {
        self.sendError(.message_with_disconnect, "Account is locked");
        return;
    }

    self.char_id = player.char_data.char_id;
    player.char_data.set(.{ .last_login_timestamp = timestamp }) catch {
        self.sendError(.message_with_disconnect, "Could not interact with database");
        return;
    };
    player.acc_data.set(.{ .locked_until = timestamp + 300 * std.time.ms_per_s }) catch {
        self.sendError(.message_with_disconnect, "Could not interact with database");
        return;
    };

    self.world = maps.testWorld(data.map) catch {
        self.sendError(.message_with_disconnect, "Creating test map failed");
        return;
    };

    self.player_map_id = self.world.add(Player, player) catch {
        self.sendError(.message_with_disconnect, "Adding player to map failed");
        return;
    };

    self.queuePacket(.{ .map_info = .{
        .width = self.world.w,
        .height = self.world.h,
        .name = self.world.name,
        .bg_color = self.world.light_data.color,
        .bg_intensity = self.world.light_data.intensity,
        .day_intensity = self.world.light_data.day_intensity,
        .night_intensity = self.world.light_data.night_intensity,
        .server_time = main.current_time,
        .player_map_id = self.player_map_id,
    } });
}

fn hash(str: []const u8) u64 {
    return std.hash.Wyhash.hash(0, str);
}

fn handleUseAbility(self: *Client, data: PacketData(.use_ability)) void {
    if (data.index < 0 or data.index >= 4) {
        self.sendError(.message_with_disconnect, "Invalid index");
        return;
    }

    const player = self.world.find(Player, self.player_map_id, .ref) orelse {
        self.sendError(.message_with_disconnect, "Player does not exist");
        return;
    };

    const abil_data = player.data.abilities[data.index];
    const time = main.current_time;
    if (time - player.last_ability_use[data.index] < i64f(abil_data.cooldown) * std.time.us_per_s) {
        self.sendError(.message_with_disconnect, "Ability on cooldown");
        return;
    }

    if (player.mp < abil_data.mana_cost) return;
    player.mp = @intCast(@as(i33, player.mp) - abil_data.mana_cost);

    // le because 0 HP means dead
    if (player.hp <= abil_data.health_cost) return;
    player.hp = @intCast(@as(i33, player.hp) - abil_data.health_cost);

    if (player.gold < abil_data.gold_cost) return;
    player.gold = @intCast(@as(i33, player.gold) - abil_data.gold_cost);

    var fbs = std.io.fixedBufferStream(data.data);

    _ = switch (hash(abil_data.name)) {
        hash("Terrain Expulsion") => abilities.handleTerrainExpulsion(
            player,
            &player.data.abilities[data.index].projectiles.?[0],
            fbs.reader().readInt(u8, .little) catch {
                self.sendError(.message_with_disconnect, "Invalid data");
                return;
            },
            @bitCast(fbs.reader().any().readBytesNoEof(4) catch {
                self.sendError(.message_with_disconnect, "Invalid data");
                return;
            }),
        ),
        hash("Heart of Stone") => abilities.handleHeartOfStone(player),
        hash("Boulder Buddies") => abilities.handleBoulderBuddies(player),
        hash("Placeholder") => abilities.handlePlaceholder(),
        hash("Time Dilation") => abilities.handleTimeDilation(player),
        hash("Rewind") => abilities.handleRewind(player),
        hash("Null Pulse") => abilities.handleNullPulse(player),
        hash("Time Lock") => abilities.handleTimeLock(player),
        hash("Equivalent Exchange") => abilities.handleEquivalentExchange(player),
        hash("Asset Bubble") => abilities.handleAssetBubble(player),
        hash("Premium Protection") => abilities.handlePremiumProtection(player),
        hash("Compound Interest") => abilities.handleCompoundInterest(player),
        else => {
            std.log.err("Unhandled ability: {s}", .{abil_data.name});
            return;
        },
    } catch |e| {
        std.log.err("Error while processing ability {s}: {}", .{ abil_data.name, e });
        return;
    };

    player.last_ability_use[data.index] = time;
}

fn handleSelectCard(self: *Client, data: PacketData(.select_card)) void {
    const player = self.world.find(Player, self.player_map_id, .ref) orelse {
        self.sendError(.message_with_disconnect, "Player does not exist");
        return;
    };

    if (player.selecting_cards == null) {
        self.sendError(.message_with_disconnect, "You have no cards to select");
        return;
    }

    defer player.selecting_cards = null;

    switch (data.selection) {
        .none => {},
        inline else => |idx| {
            player.cards = main.allocator.realloc(player.cards, player.cards.len + 1) catch main.oomPanic();
            player.cards[player.cards.len - 1] = player.selecting_cards.?[@intFromEnum(idx) - 1];
        },
    }
}

fn handleTalentUpgrade(_: *Client, _: PacketData(.talent_upgrade)) void {}
