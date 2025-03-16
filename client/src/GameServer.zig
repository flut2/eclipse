const std = @import("std");

const build_options = @import("options");
const shared = @import("shared");
const utils = shared.utils;
const game_data = shared.game_data;
const network_data = shared.network_data;
const uv = shared.uv;
const f32i = utils.f32i;
const i64f = utils.i64f;

const assets = @import("assets.zig");
const Ally = @import("game/Ally.zig");
const Container = @import("game/Container.zig");
const Enemy = @import("game/Enemy.zig");
const Entity = @import("game/Entity.zig");
const map = @import("game/map.zig");
const particles = @import("game/particles.zig");
const Player = @import("game/Player.zig");
const Portal = @import("game/Portal.zig");
const Projectile = @import("game/Projectile.zig");
const Square = @import("game/Square.zig");
const main = @import("main.zig");
const dialog = @import("ui/dialogs/dialog.zig");
const ui_systems = @import("ui/systems.zig");

const Server = @This();

pub fn typeToObjEnum(comptime T: type) network_data.ObjectType {
    return switch (T) {
        Player => .player,
        Enemy => .enemy,
        Entity => .entity,
        Container => .container,
        Portal => .portal,
        Ally => .ally,
        else => @compileError("Invalid type"),
    };
}

pub fn ObjEnumToType(comptime obj_type: network_data.ObjectType) type {
    return switch (obj_type) {
        .player => Player,
        .entity => Entity,
        .enemy => Enemy,
        .portal => Portal,
        .container => Container,
        .ally => Ally,
    };
}

const WriteRequest = extern struct {
    request: uv.uv_write_t = .{},
    buffer: uv.uv_buf_t = .{},
};

socket: *uv.uv_tcp_t = undefined,
read_arena: std.heap.ArenaAllocator = undefined,
hello_data: network_data.C2SPacket = undefined,
map_hello_fragments: ?[]network_data.C2SPacket = null,
initialized: bool = false,

fn PacketData(comptime tag: @typeInfo(network_data.S2CPacket).@"union".tag_type.?) type {
    return @typeInfo(network_data.S2CPacket).@"union".fields[@intFromEnum(tag)].type;
}

fn handlerFn(comptime tag: @typeInfo(network_data.S2CPacket).@"union".tag_type.?) fn (*Server, PacketData(tag)) void {
    return switch (tag) {
        .ally_projectile => handleAllyProjectile,
        .aoe => handleAoe,
        .damage => handleDamage,
        .death => handleDeath,
        .enemy_projectile => handleEnemyProjectile,
        .@"error" => handleError,
        .inv_result => handleInvResult,
        .map_info => handleMapInfo,
        .notification => handleNotification,
        .ping => handlePing,
        .show_effect => handleShowEffect,
        .text => handleText,
        .card_options => handleCardOptions,
        .talent_upgrade_response => handleTalentUpgradeResponse,
        .play_animation => handlePlayAnimation,
        .new_tick => handleNewTick,
        .dropped_players => handleDroppedPlayers,
        .dropped_entities => handleDroppedEntities,
        .dropped_enemies => handleDroppedEnemies,
        .dropped_portals => handleDroppedPortals,
        .dropped_containers => handleDroppedContainers,
        .dropped_allies => handleDroppedAllies,
        .new_players => handleNewPlayers,
        .new_entities => handleNewEntities,
        .new_enemies => handleNewEnemies,
        .new_portals => handleNewPortals,
        .new_containers => handleNewContainers,
        .new_allies => handleNewAllies,
    };
}

fn ObjEnumToStatType(comptime obj_type: network_data.ObjectType) type {
    return switch (obj_type) {
        .player => network_data.PlayerStat,
        .entity => network_data.EntityStat,
        .enemy => network_data.EnemyStat,
        .portal => network_data.PortalStat,
        .container => network_data.ContainerStat,
        .ally => network_data.AllyStat,
    };
}

fn ObjEnumToStatHandler(comptime obj_type: network_data.ObjectType) fn (*ObjEnumToType(obj_type), ObjEnumToStatType(obj_type)) void {
    return switch (obj_type) {
        .player => parsePlayerStat,
        .entity => parseEntityStat,
        .enemy => parseEnemyStat,
        .portal => parsePortalStat,
        .container => parseContainerStat,
        .ally => parseAllyStat,
    };
}

pub fn allocBuffer(_: [*c]uv.uv_handle_t, suggested_size: usize, buf: [*c]uv.uv_buf_t) callconv(.C) void {
    buf.* = .{
        .base = @ptrCast(main.allocator.alloc(u8, suggested_size) catch main.oomPanic()),
        .len = @intCast(suggested_size),
    };
}

fn writeCallback(ud: [*c]uv.uv_write_t, status: c_int) callconv(.C) void {
    const wr: *WriteRequest = @ptrCast(@alignCast(ud));
    const server: *Server = @ptrCast(@alignCast(wr.request.data));
    main.allocator.free(wr.buffer.base[0..wr.buffer.len]);
    main.allocator.destroy(wr);

    if (status != 0) {
        std.log.err("Game write error: {s}", .{uv.uv_strerror(status)});
        main.disconnect(false);
        server.shutdown();
        dialog.showDialog(.text, .{
            .title = "Connection Error",
            .body = "Game socket writing was interrupted",
        });
        return;
    }
}

pub fn readCallback(ud: *anyopaque, bytes_read: isize, buf: [*c]const uv.uv_buf_t) callconv(.C) void {
    const socket: *uv.uv_stream_t = @ptrCast(@alignCast(ud));
    const server: *Server = @ptrCast(@alignCast(socket.data));
    defer _ = server.read_arena.reset(.{ .retain_with_limit = std.math.maxInt(u16) });
    const allocator = server.read_arena.allocator();

    if (bytes_read > 0) {
        var reader: utils.PacketReader = .{ .buffer = buf.*.base[0..@intCast(bytes_read)] };

        while (reader.index <= bytes_read - 3) {
            const len = reader.read(u16, allocator);
            if (len > bytes_read - reader.index) return;

            const next_packet_idx = reader.index + len;
            const EnumType = @typeInfo(network_data.S2CPacket).@"union".tag_type.?;
            const byte_id = reader.read(std.meta.Int(.unsigned, @bitSizeOf(EnumType)), allocator);
            const packet_id = std.meta.intToEnum(EnumType, byte_id) catch |e| {
                std.log.err("Error parsing S2CPacket ({}): id={}, size={}, len={}", .{ e, byte_id, bytes_read, len });
                return;
            };

            switch (packet_id) {
                inline else => |id| handlerFn(id)(server, reader.read(PacketData(id), allocator)),
            }

            if (reader.index < next_packet_idx) {
                std.log.err("S2C packet {} has {} bytes left over", .{ packet_id, next_packet_idx - reader.index });
                reader.index = next_packet_idx;
            }
        }
    } else if (bytes_read < 0) {
        std.log.err("Game read error: {s}", .{uv.uv_err_name(@intCast(bytes_read))});
        main.disconnect();
        server.shutdown();
        dialog.showDialog(.text, .{
            .title = "Connection Error",
            .body = "Game server closed the connection",
        });
    }

    main.allocator.free(buf.*.base[0..@intCast(buf.*.len)]);
}

fn connectCallback(conn: [*c]uv.uv_connect_t, status: c_int) callconv(.C) void {
    const server: *Server = @ptrCast(@alignCast(conn.*.data));
    defer main.allocator.destroy(@as(*uv.uv_connect_t, @ptrCast(conn)));

    if (status != 0) {
        std.log.err("Game connection callback error: {s}", .{uv.uv_strerror(status)});
        main.disconnect();
        server.shutdown();
        dialog.showDialog(.text, .{
            .title = "Connection Error",
            .body = "Connection failed to game server",
        });
        return;
    }

    const read_status = uv.uv_read_start(@ptrCast(server.socket), allocBuffer, readCallback);
    if (read_status != 0) {
        std.log.err("Game read init error: {s}", .{uv.uv_strerror(read_status)});
        main.disconnect();
        server.shutdown();
        dialog.showDialog(.text, .{
            .title = "Connection Error",
            .body = "Game server inaccessible",
        });
        return;
    }

    server.initialized = true;

    ui_systems.switchScreen(.game);

    if (server.map_hello_fragments) |fragments| {
        defer main.allocator.free(fragments);
        for (fragments) |fragment| server.sendPacket(fragment);
        server.map_hello_fragments = null;
    }
    server.sendPacket(server.hello_data);
}

fn shutdownCallback(handle: [*c]uv.uv_async_t) callconv(.C) void {
    const server: *Server = @ptrCast(@alignCast(handle.*.data));
    server.shutdown();
    dialog.showDialog(.none, {});
}

pub fn init(self: *Server) !void {
    self.socket = try main.allocator.create(uv.uv_tcp_t);
    self.read_arena = .init(main.allocator);
}

pub fn deinit(self: *Server) void {
    main.disconnect();
    main.allocator.destroy(self.socket);
    self.read_arena.deinit();
    self.initialized = false;
}

pub fn sendPacket(self: *Server, packet: network_data.C2SPacket) void {
    if (!self.initialized) return;

    defer if (packet == .hello) {
        if (main.current_account) |acc| {
            main.login_server.sendPacket(.{ .verify = .{ .email = acc.email, .token = acc.token } });
            main.skip_verify_loop = true;
        }
    };

    const is_tick = packet == .move or packet == .pong;
    if (build_options.log_packets == .all or
        build_options.log_packets == .c2s or
        (build_options.log_packets == .c2s_tick or build_options.log_packets == .all_tick) and is_tick or
        (build_options.log_packets == .c2s_non_tick or build_options.log_packets == .all_non_tick) and !is_tick)
        std.log.info("Send: {}", .{packet}); // TODO: custom formatting

    if (packet == .use_portal or packet == .escape)
        if (map.localPlayer(.ref)) |player| {
            player.x = -1.0;
            player.y = -1.0;
            map.clearMoveRecords(main.current_time);
        };

    switch (packet) {
        inline else => |data| {
            var writer: utils.PacketWriter = .{};
            defer writer.list.deinit(main.allocator);
            writer.writeLength(main.allocator);
            writer.write(@intFromEnum(std.meta.activeTag(packet)), main.allocator);
            writer.write(data, main.allocator);
            writer.updateLength();

            const uv_buffer: uv.uv_buf_t = .{ .base = @ptrCast(writer.list.items.ptr), .len = @intCast(writer.list.items.len) };

            var write_status = uv.UV_EAGAIN;
            while (write_status == uv.UV_EAGAIN or (write_status >= 0 and write_status != writer.list.items.len))
                write_status = uv.uv_try_write(@ptrCast(self.socket), @ptrCast(&uv_buffer), 1);
            if (write_status < 0) {
                std.log.err("Game write send error: {s}", .{uv.uv_strerror(write_status)});
                main.disconnect();
                self.shutdown();
                dialog.showDialog(.text, .{
                    .title = "Connection Error",
                    .body = "Game socket writing failed",
                });
                return;
            }
        },
    }
}

pub fn connect(self: *Server, ip: []const u8, port: u16) !void {
    const addr = try std.net.Address.parseIp4(ip, port);

    self.socket.data = self;
    const tcp_status = uv.uv_tcp_init(@ptrCast(main.main_loop), @ptrCast(self.socket));
    if (tcp_status != 0) {
        std.log.err("Game socket creation error: {s}", .{uv.uv_strerror(tcp_status)});
        return error.NoSocket;
    }

    const disable_nagle_status = uv.uv_tcp_nodelay(@ptrCast(self.socket), 1);
    if (disable_nagle_status != 0)
        std.log.err("Disabling Nagle on socket failed: {s}", .{uv.uv_strerror(disable_nagle_status)});

    var connect_data = try main.allocator.create(uv.uv_connect_t);
    connect_data.data = self;
    const conn_status = uv.uv_tcp_connect(@ptrCast(connect_data), @ptrCast(self.socket), @ptrCast(&addr.in.sa), connectCallback);
    if (conn_status != 0) {
        std.log.err("Game connection error: {s}", .{uv.uv_strerror(conn_status)});
        return error.ConnectionFailed;
    }
}

pub fn shutdown(self: *Server) void {
    if (!self.initialized) return;
    self.initialized = false;
    if (uv.uv_is_closing(@ptrCast(self.socket)) == 0) uv.uv_close(@ptrCast(self.socket), closeCallback);
}

fn closeCallback(_: [*c]uv.uv_handle_t) callconv(.C) void {}

fn logRead(comptime tick: enum { non_tick, tick }) bool {
    return if (tick == .non_tick)
        build_options.log_packets == .all or
            build_options.log_packets == .s2c or
            build_options.log_packets == .s2c_non_tick or
            build_options.log_packets == .all_non_tick
    else
        build_options.log_packets == .all or
            build_options.log_packets == .s2c or
            build_options.log_packets == .s2c_tick or
            build_options.log_packets == .all_tick;
}

fn handleAllyProjectile(_: *Server, data: PacketData(.ally_projectile)) void {
    if (logRead(.non_tick)) std.log.debug("Recv - AllyProjectile: {}", .{data});

    if (map.findObject(Player, data.player_map_id, .ref)) |player| {
        const item_data = game_data.item.from_id.getPtr(data.item_data_id) orelse return;
        Projectile.addToMap(.{
            .x = player.x,
            .y = player.y,
            .data = &item_data.projectile.?,
            .angle = data.angle,
            .index = @intCast(data.proj_index),
            .owner_map_id = player.map_id,
        });

        const attack_period = i64f(1.0 / (Player.attack_frequency * item_data.fire_rate));
        player.attack_period = attack_period;
        player.attack_angle = data.angle;
        player.attack_start = main.current_time;
    }
}

fn handleAoe(_: *Server, data: PacketData(.aoe)) void {
    particles.AoeEffect.addToMap(.{
        .x = data.x,
        .y = data.y,
        .color = data.color,
        .radius = data.radius,
    });

    if (logRead(.non_tick)) std.log.debug("Recv - Aoe: {}", .{data});
}

fn handleDamage(_: *Server, data: PacketData(.damage)) void {
    if (map.findObject(Player, data.player_map_id, .ref)) |player|
        map.takeDamage(
            player,
            data.amount,
            data.damage_type,
            data.effects,
            player.colors,
        );

    if (logRead(.non_tick)) std.log.debug("Recv - Damage: {}", .{data});
}

fn handleDeath(self: *Server, data: PacketData(.death)) void {
    self.shutdown();
    dialog.showDialog(.none, {});

    if (logRead(.non_tick)) std.log.debug("Recv - Death: {}", .{data});
}

fn handleEnemyProjectile(_: *Server, data: PacketData(.enemy_projectile)) void {
    if (logRead(.non_tick)) std.log.debug("Recv - EnemyProjectile: {}", .{data});

    var owner = if (map.findObject(Enemy, data.enemy_map_id, .ref)) |enemy| enemy else return;

    const owner_data = game_data.enemy.from_id.getPtr(owner.data_id);
    if (owner_data == null or owner_data.?.projectiles == null or data.proj_data_id >= owner_data.?.projectiles.?.len)
        return;

    const total_angle = data.angle_incr * f32i(data.num_projs - 1);
    var current_angle = data.angle - total_angle / 2.0;

    for (0..data.num_projs) |i| {
        Projectile.addToMap(.{
            .x = data.x,
            .y = data.y,
            .phys_dmg = data.phys_dmg,
            .magic_dmg = data.magic_dmg,
            .true_dmg = data.true_dmg,
            .data = &owner_data.?.projectiles.?[data.proj_data_id],
            .angle = current_angle,
            .index = data.proj_index +% @as(u8, @intCast(i)),
            .owner_map_id = data.enemy_map_id,
            .damage_players = true,
        });

        current_angle += data.angle_incr;
    }

    owner.attack_angle = data.angle;
    owner.attack_start = main.current_time;
}

fn handleError(self: *Server, data: PacketData(.@"error")) void {
    if (logRead(.non_tick)) std.log.debug("Recv - Error: {}", .{data});

    if (data.type == .message_with_disconnect or data.type == .force_close_game) {
        main.disconnect();
        self.shutdown();
        dialog.showDialog(.text, .{
            .title = "Connection Error",
            .body = main.allocator.dupe(u8, data.description) catch return,
            .dispose_body = true,
        });
    }
}

fn handleInvResult(_: *Server, data: PacketData(.inv_result)) void {
    if (logRead(.non_tick)) std.log.debug("Recv - InvResult: {}", .{data});
}

fn handleMapInfo(_: *Server, data: PacketData(.map_info)) void {
    if (logRead(.non_tick)) std.log.debug("Recv - MapInfo: {}", .{data});

    map.dispose();

    main.camera.quake = false;

    map.setMapInfo(data);
    map.info.name = main.allocator.dupe(u8, data.name) catch main.oomPanic();

    main.tick_frame = true;
}

fn handleDroppedPlayers(_: *Server, data: PacketData(.dropped_players)) void {
    droppedObject(Player, data.map_ids);
    if (logRead(.tick)) std.log.debug("Recv - DroppedPlayers: {}", .{data});
}

fn handleDroppedEnemies(_: *Server, data: PacketData(.dropped_enemies)) void {
    droppedObject(Enemy, data.map_ids);
    if (logRead(.tick)) std.log.debug("Recv - DroppedEnemies: {}", .{data});
}

fn handleDroppedEntities(_: *Server, data: PacketData(.dropped_entities)) void {
    droppedObject(Entity, data.map_ids);
    if (logRead(.tick)) std.log.debug("Recv - DroppedEntities: {}", .{data});
}

fn handleDroppedPortals(_: *Server, data: PacketData(.dropped_portals)) void {
    droppedObject(Portal, data.map_ids);
    if (logRead(.tick)) std.log.debug("Recv - DroppedPortals: {}", .{data});
}

fn handleDroppedContainers(_: *Server, data: PacketData(.dropped_containers)) void {
    droppedObject(Container, data.map_ids);
    if (logRead(.tick)) std.log.debug("Recv - DroppedContainers: {}", .{data});
}

fn handleDroppedAllies(_: *Server, data: PacketData(.dropped_allies)) void {
    droppedObject(Ally, data.map_ids);
    if (logRead(.tick)) std.log.debug("Recv - DroppedAllies: {}", .{data});
}

fn handleNotification(_: *Server, data: PacketData(.notification)) void {
    switch (data.obj_type) {
        inline .player, .ally, .enemy, .entity => |inner| {
            const T = ObjEnumToType(inner);
            if (map.findObject(T, data.map_id, .ref)) |obj| obj.status_texts.append(main.allocator, .{
                .initial_size = 16.0,
                .dispose_text = true,
                .show_at = main.current_time,
                .duration = 2.0 * std.time.us_per_s,
                .text_data = .{
                    .text = main.allocator.dupe(u8, data.message) catch main.oomPanic(),
                    .text_type = .bold,
                    .size = 16,
                    .color = data.color,
                },
            }) catch main.oomPanic();
        },
        else => {
            std.log.err("Invalid type: {}", .{data.obj_type});
            return;
        },
    }
}

fn handlePing(self: *Server, data: PacketData(.ping)) void {
    self.sendPacket(.{ .pong = .{ .ping_time = data.time, .time = main.current_time } });

    if (logRead(.tick)) std.log.debug("Recv - Ping: {}", .{data});
}

fn handleShowEffect(_: *Server, data: PacketData(.show_effect)) void {
    switch (data.eff_type) {
        .area_blast => {
            particles.AoeEffect.addToMap(.{
                .x = data.x1,
                .y = data.y1,
                .radius = data.x2,
                .color = data.color,
            });
        },
        .throw => {
            var start_x = data.x2;
            var start_y = data.y2;

            switch (data.obj_type) {
                inline else => |inner| {
                    const T = ObjEnumToType(inner);
                    if (map.findObject(T, data.map_id, .con)) |obj| {
                        start_x = obj.x;
                        start_y = obj.y;
                    }
                },
            }
            particles.ThrowEffect.addToMap(.{
                .start_x = start_x,
                .start_y = start_y,
                .end_x = data.x1,
                .end_y = data.y1,
                .color = data.color,
                .duration = 1500,
            });
        },
        .teleport => {
            particles.TeleportEffect.addToMap(.{
                .x = data.x1,
                .y = data.y1,
            });
        },
        .trail => {
            var start_x = data.x2;
            var start_y = data.y2;

            switch (data.obj_type) {
                inline else => |inner| {
                    const T = ObjEnumToType(inner);
                    if (map.findObject(T, data.map_id, .con)) |obj| {
                        start_x = obj.x;
                        start_y = obj.y;
                    }
                },
            }

            particles.LineEffect.addToMap(.{
                .start_x = start_x,
                .start_y = start_y,
                .end_x = data.x1,
                .end_y = data.y1,
                .color = data.color,
            });
        },
        .potion => {
            // the effect itself handles checks for invalid entity
            particles.HealEffect.addToMap(.{
                .target_obj_type = data.obj_type,
                .target_map_id = data.map_id,
                .color = data.color,
            });
        },
        .earthquake => {
            main.camera.quake = true;
            main.camera.quake_amount = 0.0;
        },
        else => {},
    }

    if (logRead(.non_tick)) std.log.debug("Recv - ShowEffect: {}", .{data});
}

fn handleText(_: *Server, data: PacketData(.text)) void {
    if (ui_systems.screen == .game)
        ui_systems.screen.game.addChatLine(data.name, data.text, data.name_color, data.text_color) catch |e| {
            std.log.err("Adding message with name {s} and text {s} failed: {}", .{ data.name, data.text, e });
        };

    if (data.map_id != std.math.maxInt(u32)) {
        switch (data.obj_type) {
            inline .player, .enemy => |inner| {
                if (map.findObject(ObjEnumToType(inner), data.map_id, .ref)) |obj| {
                    if (obj.speech_balloon) |*balloon| balloon.deinit();
                    obj.speech_balloon = .create(
                        main.current_time,
                        5.0 * std.time.us_per_s,
                        main.allocator.dupe(u8, data.text) catch main.oomPanic(),
                        data.obj_type == .enemy,
                    );
                }
            },
            else => std.log.err("Unsupported object type for Text: {}", .{data.obj_type}),
        }
    }

    if (logRead(.non_tick)) std.log.debug("Recv - Text: {}", .{data});
}

fn handleCardOptions(_: *Server, data: PacketData(.card_options)) void {
    if (ui_systems.screen == .game) ui_systems.screen.game.card_selection.updateSelectables(data.cards);
    if (logRead(.non_tick)) std.log.debug("Recv - CardOptions: {}", .{data});
}

fn handleTalentUpgradeResponse(_: *Server, _: PacketData(.talent_upgrade_response)) void {}

fn handlePlayAnimation(_: *Server, data: PacketData(.play_animation)) void {
    switch (data.obj_type) {
        .enemy, .player, .ally => |value| std.log.err("Unsupported PlayAnimation for type {}", .{value}),
        inline else => |inner| {
            const T = ObjEnumToType(inner);
            if (map.findObject(T, data.map_id, .ref)) |obj| {
                obj.anim_idx = 0;
                obj.next_anim = -1;
                if (data.repeating)
                    obj.playing_anim = .{ .repeat = data.animation_idx }
                else
                    obj.playing_anim = .{ .single = data.animation_idx };
            }
        },
    }

    if (logRead(.non_tick)) std.log.debug("Recv - PlayAnimation: {}", .{data});
}

fn handleNewTick(self: *Server, data: PacketData(.new_tick)) void {
    defer {
        if (main.tick_frame) {
            const time = main.current_time;
            if (map.localPlayer(.ref)) |local_player| {
                self.sendPacket(.{ .move = .{
                    .tick_id = data.tick_id,
                    .time = time,
                    .x = local_player.x,
                    .y = local_player.y,
                    .records = map.move_records.items,
                } });

                local_player.onMove();
            } else {
                self.sendPacket(.{ .move = .{
                    .tick_id = data.tick_id,
                    .time = time,
                    .x = -1.0,
                    .y = -1.0,
                    .records = &.{},
                } });
            }

            map.clearMoveRecords(time);
        }
    }

    for (data.tiles) |tile| Square.addToMap(.{
        .x = f32i(tile.x) + 0.5,
        .y = f32i(tile.y) + 0.5,
        .data_id = tile.data_id,
    });

    main.need_minimap_update = data.tiles.len > 0;

    if (logRead(.tick)) std.log.debug("Recv - NewTick: {}", .{data});
}

fn handleNewPlayers(_: *Server, data: PacketData(.new_players)) void {
    newObject(Player, data.list);
    if (logRead(.tick)) std.log.debug("Recv - NewPlayers: {}", .{data});
}

fn handleNewEntities(_: *Server, data: PacketData(.new_entities)) void {
    newObject(Entity, data.list);
    if (logRead(.tick)) std.log.debug("Recv - NewEntities: {}", .{data});
}

fn handleNewEnemies(_: *Server, data: PacketData(.new_enemies)) void {
    newObject(Enemy, data.list);
    if (logRead(.tick)) std.log.debug("Recv - NewEnemies: {}", .{data});
}

fn handleNewPortals(_: *Server, data: PacketData(.new_portals)) void {
    newObject(Portal, data.list);
    if (logRead(.tick)) std.log.debug("Recv - NewPortals: {}", .{data});
}

fn handleNewContainers(_: *Server, data: PacketData(.new_containers)) void {
    newObject(Container, data.list);
    if (logRead(.tick)) std.log.debug("Recv - NewContainers: {}", .{data});
}

fn handleNewAllies(_: *Server, data: PacketData(.new_allies)) void {
    newObject(Ally, data.list);
    if (logRead(.tick)) std.log.debug("Recv - NewAllies: {}", .{data});
}

fn droppedObject(comptime T: type, list: []const u32) void {
    if (list.len == 0) return;
    for (list) |map_id| _ = map.removeEntity(T, map_id);
}

fn newObject(comptime T: type, list: []const network_data.ObjectData) void {
    const tick_time = @as(f32, std.time.us_per_s) / 20.0;

    for (list) |obj| {
        var stat_reader: utils.PacketReader = .{ .buffer = obj.stats };
        const current_obj = map.findObject(T, obj.map_id, .ref) orelse findAddObj: {
            for (map.addListForType(T).items) |*add_obj| {
                if (add_obj.map_id == obj.map_id) break :findAddObj add_obj;
            }

            break :findAddObj null;
        };
        if (current_obj) |object| {
            const pre_x = switch (T) {
                Player, Enemy, Ally => object.x,
                else => 0.0,
            };
            const pre_y = switch (T) {
                Player, Enemy, Ally => object.y,
                else => 0.0,
            };

            parseObjectStat(typeToObjEnum(T), &stat_reader, object);

            switch (T) {
                Player => {
                    if (object.map_id != map.info.player_map_id) {
                        updateMove(object, pre_x, pre_y, tick_time);
                    } else if (ui_systems.screen == .game) ui_systems.screen.game.updateStats();
                },
                Enemy, Ally => updateMove(object, pre_x, pre_y, tick_time),
                else => {},
            }
        } else {
            var new_obj: T = .{ .map_id = obj.map_id, .data_id = obj.data_id };
            parseObjectStat(typeToObjEnum(T), &stat_reader, &new_obj);
            T.addToMap(new_obj);
        }
    }
}

fn updateMove(obj: anytype, pre_x: f32, pre_y: f32, tick_time: f32) void {
    const y_dt = obj.y - pre_y;
    const x_dt = obj.x - pre_x;

    obj.move_angle = if (y_dt == 0 and x_dt == 0) std.math.nan(f32) else std.math.atan2(y_dt, x_dt);
    if (!std.math.isNan(obj.move_angle)) {
        const dist_sqr = y_dt * y_dt + x_dt * x_dt;
        obj.move_step = @sqrt(dist_sqr) / tick_time;
        obj.target_x = obj.x;
        obj.target_y = obj.y;
        obj.x = pre_x;
        obj.y = pre_y;
    }
}

fn parseObjectStat(
    comptime obj_type: network_data.ObjectType,
    stat_reader: *utils.PacketReader,
    object: *ObjEnumToType(obj_type),
) void {
    while (stat_reader.index < stat_reader.buffer.len) {
        const StatType = ObjEnumToStatType(obj_type);
        const type_info = @typeInfo(StatType).@"union";
        const TagType = type_info.tag_type.?;
        const stat_id: usize = @intFromEnum(stat_reader.read(TagType, main.allocator));
        inline for (type_info.fields, 0..) |field, i| @"continue": {
            if (i != stat_id) break :@"continue";

            const stat = @unionInit(StatType, field.name, stat_reader.read(field.type, main.allocator));
            ObjEnumToStatHandler(obj_type)(object, stat);
        }
    }
}

fn parseNameStat(object: anytype, name: []const u8) void {
    if (name.len <= 0) return;

    if (object.name) |obj_name| main.allocator.free(obj_name);

    object.name = name;

    if (object.name_text_data) |*data| {
        data.setText(object.name.?);
    } else {
        object.name_text_data = .{
            .text = undefined,
            .text_type = .bold,
            .size = 12,
        };
        if (@TypeOf(object) == Player) {
            object.name_text_data.color = 0xFCDF00;
            object.name_text_data.max_width = 200;
        }

        object.name_text_data.?.setText(object.name.?);
    }
}

fn parsePlayerStat(player: *Player, stat: network_data.PlayerStat) void {
    const is_self = player.map_id == map.info.player_map_id;
    switch (stat) {
        .x => |val| player.x = val,
        .y => |val| player.y = val,
        .size_mult => |val| player.size_mult = val,
        .cards => |val| player.cards = val,
        .resources => |val| player.resources = val,
        .talents => |val| player.talents = val,
        .rank => |val| player.rank = val,
        .aether => |val| player.aether = val,
        .spirits_communed => |val| player.spirits_communed = val,
        .damage_mult => |val| player.damage_mult = val,
        .hit_mult => |val| player.hit_mult = val,
        .ability_state => |val| player.ability_state = val,
        .condition => |val| player.condition = val,
        .gold => |val| player.gold = val,
        .gems => |val| player.gems = val,
        .muted_until => |val| player.muted_until = val,
        .max_hp => |val| player.max_hp = val,
        .hp => |val| player.hp = val,
        .max_mp => |val| player.max_mp = val,
        .mp => |val| player.mp = val,
        .strength => |val| player.strength = val,
        .wit => |val| player.wit = val,
        .defense => |val| player.defense = val,
        .resistance => |val| player.resistance = val,
        .speed => |val| player.speed = val,
        .stamina => |val| player.stamina = val,
        .intelligence => |val| player.intelligence = val,
        .haste => |val| player.haste = val,
        .max_hp_bonus => |val| player.max_hp_bonus = val,
        .max_mp_bonus => |val| player.max_mp_bonus = val,
        .strength_bonus => |val| player.strength_bonus = val,
        .wit_bonus => |val| player.wit_bonus = val,
        .defense_bonus => |val| player.defense_bonus = val,
        .resistance_bonus => |val| player.resistance_bonus = val,
        .speed_bonus => |val| player.speed_bonus = val,
        .stamina_bonus => |val| player.stamina_bonus = val,
        .intelligence_bonus => |val| player.intelligence_bonus = val,
        .haste_bonus => |val| player.haste_bonus = val,
        .inv_0,
        .inv_1,
        .inv_2,
        .inv_3,
        .inv_4,
        .inv_5,
        .inv_6,
        .inv_7,
        .inv_8,
        .inv_9,
        .inv_10,
        .inv_11,
        .inv_12,
        .inv_13,
        .inv_14,
        .inv_15,
        .inv_16,
        .inv_17,
        .inv_18,
        .inv_19,
        .inv_20,
        .inv_21,
        => |val| {
            const inv_idx = @intFromEnum(stat) - @intFromEnum(network_data.PlayerStat.inv_0);
            player.inventory[inv_idx] = val;
            if (is_self and ui_systems.screen == .game)
                ui_systems.screen.game.setInvItem(val, inv_idx);
        },
        .inv_data_0,
        .inv_data_1,
        .inv_data_2,
        .inv_data_3,
        .inv_data_4,
        .inv_data_5,
        .inv_data_6,
        .inv_data_7,
        .inv_data_8,
        .inv_data_9,
        .inv_data_10,
        .inv_data_11,
        .inv_data_12,
        .inv_data_13,
        .inv_data_14,
        .inv_data_15,
        .inv_data_16,
        .inv_data_17,
        .inv_data_18,
        .inv_data_19,
        .inv_data_20,
        .inv_data_21,
        => |val| {
            const inv_idx = @intFromEnum(stat) - @intFromEnum(network_data.PlayerStat.inv_data_0);
            player.inv_data[inv_idx] = val;
            if (is_self and ui_systems.screen == .game)
                ui_systems.screen.game.setInvItemData(val, inv_idx);
        },
        .name => |val| parseNameStat(player, val),
    }
}

fn parseEnemyStat(enemy: *Enemy, stat: network_data.EnemyStat) void {
    switch (stat) {
        .x => |val| enemy.x = val,
        .y => |val| enemy.y = val,
        .max_hp => |val| enemy.max_hp = val,
        .hp => |val| enemy.hp = val,
        .size_mult => |val| enemy.size_mult = val,
        .condition => |val| enemy.condition = val,
        .name => |val| parseNameStat(enemy, val),
    }
}

fn parseEntityStat(entity: *Entity, stat: network_data.EntityStat) void {
    switch (stat) {
        .x => |val| entity.x = val,
        .y => |val| entity.y = val,
        .hp => |val| entity.hp = val,
        .size_mult => |val| entity.size_mult = val,
        .name => |val| parseNameStat(entity, val),
    }
}

fn parseContainerStat(container: *Container, stat: network_data.ContainerStat) void {
    switch (stat) {
        .x => |val| container.x = val,
        .y => |val| container.y = val,
        .size_mult => |val| container.size_mult = val,
        .inv_0, .inv_1, .inv_2, .inv_3, .inv_4, .inv_5, .inv_6, .inv_7, .inv_8 => |val| {
            const inv_idx = @intFromEnum(stat) - @intFromEnum(network_data.ContainerStat.inv_0);
            container.inventory[inv_idx] = val;

            const int_id = map.interactive.map_id.load(.acquire);
            if (container.map_id == int_id and ui_systems.screen == .game)
                ui_systems.screen.game.setContainerItem(val, inv_idx);
        },
        .inv_data_0,
        .inv_data_1,
        .inv_data_2,
        .inv_data_3,
        .inv_data_4,
        .inv_data_5,
        .inv_data_6,
        .inv_data_7,
        .inv_data_8,
        => |val| {
            const inv_idx = @intFromEnum(stat) - @intFromEnum(network_data.ContainerStat.inv_data_0);
            container.inv_data[inv_idx] = val;

            const int_id = map.interactive.map_id.load(.acquire);
            if (container.map_id == int_id and ui_systems.screen == .game)
                ui_systems.screen.game.setContainerItemData(val, inv_idx);
        },
        .name => |val| {
            const int_id = map.interactive.map_id.load(.acquire);
            if (container.map_id == int_id and ui_systems.screen == .game)
                ui_systems.screen.game.container_name.text_data.setText(val);
            parseNameStat(container, val);
        },
    }
}

fn parsePortalStat(portal: *Portal, stat: network_data.PortalStat) void {
    switch (stat) {
        .x => |val| portal.x = val,
        .y => |val| portal.y = val,
        .size_mult => |val| portal.size_mult = val,
        .name => |val| parseNameStat(portal, val),
    }
}

fn parseAllyStat(ally: *Ally, stat: network_data.AllyStat) void {
    switch (stat) {
        .x => |val| ally.x = val,
        .y => |val| ally.y = val,
        .size_mult => |val| ally.size_mult = val,
        .max_hp => |val| ally.max_hp = val,
        .hp => |val| ally.hp = val,
        .condition => |val| ally.condition = val,
        .owner_map_id => |val| ally.owner_map_id = val,
    }
}
