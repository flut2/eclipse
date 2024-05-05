const std = @import("std");
const xev = @import("xev");
const utils = @import("shared").utils;
const settings = @import("settings.zig");
const main = @import("main.zig");
const game_data = @import("shared").game_data;
const builtin = @import("builtin");
const db = @import("db.zig");
const maps = @import("map/maps.zig");
const command = @import("command.zig");

const World = @import("world.zig").World;
const Entity = @import("map/entity.zig").Entity;
const Enemy = @import("map/enemy.zig").Enemy;
const Projectile = @import("map/projectile.zig").Projectile;
const Player = @import("map/player.zig").Player;

pub const FailureType = enum(i8) {
    message_no_disconnect = -1,
    message_with_disconnect = 0,
    client_update_needed = 1,
    force_close_game = 2,
    invalid_teleport_target = 3,
};

pub const TimedPosition = extern struct {
    time: i64,
    x: f32,
    y: f32,
};

pub const ObjectData = struct {
    obj_type: u16,
    obj_id: i32,
    stats: []u8,
};

pub const TileData = extern struct {
    x: u16,
    y: u16,
    tile_type: u16,
};

const C2SPacketId = enum(u8) {
    unknown = 0,
    player_shoot = 1,
    move = 2,
    player_text = 3,
    update_ack = 4,
    inv_swap = 5,
    use_item = 6,
    hello = 7,
    inv_drop = 8,
    pong = 9,
    teleport = 10,
    use_portal = 11,
    buy = 12,
    ground_damage = 13,
    player_hit = 14,
    enemy_hit = 15,
    aoe_ack = 16,
    shoot_ack = 17,
    other_hit = 18,
    square_hit = 19,
    escape = 28,
    map_hello = 32,
    use_ability = 33,
};

const S2CPacketId = enum(u8) {
    unknown = 0,
    create_success = 1,
    text = 2,
    server_player_shoot = 3,
    damage = 4,
    update = 5,
    notification = 6,
    new_tick = 7,
    show_effect = 8,
    goto = 9,
    inv_result = 10,
    ping = 11,
    map_info = 12,
    death = 13,
    aoe = 15,
    ally_shoot = 19,
    enemy_shoot = 20,
    failure = 28,
};

// All packets without variable length fields (like slices) should be packed.
// This allows us to directly copy the struct into the buffer
pub const S2CPacket = union(S2CPacketId) {
    unknown: packed struct {},
    create_success: packed struct { player_id: i32, char_id: i32 },
    text: struct {
        name: []const u8,
        obj_id: i32,
        bubble_time: u8,
        recipient: []const u8,
        text: []const u8,
        name_color: u32,
        text_color: u32,
    },
    server_player_shoot: packed struct {},
    damage: packed struct {
        target_id: i32,
        effects: utils.Condition,
        amount: u16,
        kill: bool,
        bullet_id: u8,
        object_id: i32,
    },
    update: struct { tiles: []const TileData, drops: []const i32, new_objs: []const ObjectData },
    notification: struct { obj_id: i32, message: []const u8, color: u32 },
    new_tick: struct { tick_id: u8, ticks_per_sec: u8, objs: []const ObjectData },
    show_effect: packed struct {
        eff_type: game_data.ShowEffect,
        obj_id: i32,
        x1: f32,
        y1: f32,
        x2: f32,
        y2: f32,
        color: u32,
    },
    goto: packed struct { obj_id: i32, x: f32, y: f32 },
    inv_result: packed struct { result: u8 },
    ping: packed struct { serial: i64 },
    map_info: struct {
        width: i32,
        height: i32,
        name: []const u8,
        bg_light_color: u32,
        bg_light_intensity: f32,
        day_light_intensity: f32,
        night_light_intensity: f32,
        server_time: i64,
    },
    death: struct { acc_id: i32, char_id: i32, killer: []const u8 },
    aoe: struct {
        x: f32,
        y: f32,
        radius: f32,
        damage: u16,
        eff: utils.Condition,
        duration: f32,
        orig_type: u8,
        color: u32,
    },
    ally_shoot: packed struct { bullet_id: u8, owner_id: i32, container_type: u16, angle: f32 },
    enemy_shoot: packed struct {
        bullet_id: u8,
        owner_id: i32,
        bullet_index: u8,
        x: f32,
        y: f32,
        angle: f32,
        phys_dmg: i16,
        magic_dmg: i16,
        true_dmg: i16,
        num_shots: u8,
        angle_inc: f32,
    },
    failure: struct {
        fail_type: FailureType,
        desc: []const u8,
    },
};

pub const Client = struct {
    loop: ?*xev.Loop = null,
    socket: ?*xev.TCP = null,
    write_queue: utils.MPSCQueue = undefined,
    reader: utils.PacketReader = .{},
    write_lock: std.Thread.Mutex = .{},
    write_comp: ?*xev.Completion = null,
    allocator: std.mem.Allocator = undefined,
    needs_shutdown: bool = false,
    world: *World = undefined,
    acc_id: u32 = std.math.maxInt(u32),
    char_id: i16 = -1,
    plr_id: i32 = -1,

    pub fn init(
        allocator: std.mem.Allocator,
        loop: *xev.Loop,
        socket: *xev.TCP,
        read_buffer: *[main.read_buffer_size]u8,
        secondary_read_buffer: *[main.read_buffer_size]u8,
    ) !Client {
        var ret = Client{ .allocator = allocator, .loop = loop, .socket = socket };
        ret.reader.buffer = read_buffer;
        ret.reader.fba = std.heap.FixedBufferAllocator.init(secondary_read_buffer);
        ret.write_queue.init(try allocator.create(utils.MPSCQueue.Node));
        return ret;
    }

    pub fn deinit(self: *Client) void {
        self.allocator.destroy(self.write_queue.stub);
        main.read_buffer_pool.destroy(@alignCast(
            @as(*[main.read_buffer_size]u8, @ptrFromInt(@intFromPtr(self.reader.buffer.ptr))),
        ));
        main.read_buffer_pool.destroy(@alignCast(
            @as(*[main.read_buffer_size]u8, @ptrFromInt(@intFromPtr(self.reader.fba.buffer.ptr))),
        ));
    }

    pub fn shutdown(self: *Client) void {
        if (self.socket == null or self.loop == null)
            return;

        const c = main.completion_pool.create() catch unreachable;
        self.socket.?.shutdown(self.loop.?, c, Client, self, shutdownCallback);
    }

    pub fn queuePacket(self: *Client, packet: S2CPacket) void {
        if (self.socket == null or self.loop == null)
            return;

        // What's the point of the MPSC queue if we're going to have to lock either way for MemoryPool? todo thread safe MemoryPool
        self.write_lock.lock();
        defer self.write_lock.unlock();

        var writer = utils.PacketWriter{ .buffer = main.write_buffer_pool.create() catch unreachable };
        writer.writeLength();
        writer.write(@intFromEnum(std.meta.activeTag(packet)));
        switch (packet) {
            inline else => |data| {
                var data_bytes = std.mem.asBytes(&data);
                const data_type = @TypeOf(data);
                const data_info = @typeInfo(data_type);
                if (data_info.Struct.layout == .Packed) {
                    const field_len = (@bitSizeOf(data_info.Struct.backing_integer.?) + 7) / 8;
                    if (field_len > 0)
                        writer.writeDirect(data_bytes[0..field_len]);
                } else {
                    inline for (data_info.Struct.fields) |field| {
                        const base_offset = @offsetOf(data_type, field.name);
                        const type_info = @typeInfo(field.type);
                        if (type_info == .Pointer and (type_info.Pointer.size == .Slice or type_info.Pointer.size == .Many)) {
                            writer.write(std.mem.bytesAsValue([]type_info.Pointer.child, data_bytes[base_offset .. base_offset + 16]).*);
                        } else {
                            const field_len = (@bitSizeOf(field.type) + 7) / 8;
                            if (field_len > 0)
                                writer.writeDirect(data_bytes[base_offset .. base_offset + field_len]);
                        }
                    }
                }
            },
        }
        writer.updateLength();

        if (packet == .failure) {
            self.needs_shutdown = true;
            std.log.err("fail received: {s}", .{packet.failure.desc});
        }

        const empty = self.write_queue.isEmpty();
        const node = main.node_pool.create() catch unreachable;
        node.buf = writer.buffer[0..writer.index];
        self.write_queue.push(node);
        if (empty) {
            self.write_comp = main.completion_pool.create() catch unreachable;
            self.socket.?.write(self.loop.?, self.write_comp.?, .{ .slice = node.buf }, Client, self, writeCallback);
        }
    }

    fn writeCallback(self: ?*Client, _: *xev.Loop, c: *xev.Completion, _: xev.TCP, buf: xev.WriteBuffer, result: xev.TCP.WriteError!usize) xev.CallbackAction {
        if (self) |cli| {
            if (cli.socket == null or cli.loop == null)
                return .disarm;

            if (cli.write_queue.pop()) |node| {
                if (cli.write_queue.getNext(node)) |next| {
                    cli.socket.?.write(cli.loop.?, c, .{ .slice = next.buf }, Client, cli, writeCallback);
                } else {
                    main.completion_pool.destroy(c);
                    cli.write_comp = null;
                }

                main.write_buffer_pool.destroy(
                    @alignCast(
                        @as(*[main.write_buffer_size]u8, @ptrFromInt(@intFromPtr(node.buf.ptr))),
                    ),
                );
                main.node_pool.destroy(node);
            }

            _ = result catch |e| {
                std.log.err("Socket write error: {}", .{e});
                cli.shutdown();
                return .disarm;
            };

            if (buf.slice[2] == @intFromEnum(S2CPacket.failure) and cli.needs_shutdown)
                cli.shutdown();
        }

        return .disarm;
    }

    pub fn readCallback(self: ?*Client, _: *xev.Loop, _: *xev.Completion, _: xev.TCP, _: xev.ReadBuffer, result: xev.TCP.ReadError!usize) xev.CallbackAction {
        if (self) |cli| {
            if (cli.socket == null or cli.loop == null)
                return .disarm;

            const size = result catch |e| {
                std.log.err("Socket read error: {}", .{e});
                cli.shutdown();
                return .disarm;
            };
            cli.reader.reset();
            cli.reader.size = size;

            while (cli.reader.index < size - 3) {
                const len = cli.reader.read(u16);
                if (len > size - cli.reader.index)
                    return .rearm;

                const next_packet_idx = cli.reader.index + len;
                const byte_id = cli.reader.read(u8);
                const packet_id = std.meta.intToEnum(C2SPacketId, byte_id) catch |e| {
                    std.log.err("Error parsing C2SPacketId ({}): id={d}, size={d}, len={d}", .{ e, byte_id, size, len });
                    cli.reader.reset();
                    return .rearm;
                };

                switch (packet_id) {
                    .player_shoot => cli.handlePlayerShoot(),
                    .move => cli.handleMove(),
                    .player_text => cli.handlePlayerText(),
                    .update_ack => cli.handleUpdateAck(),
                    .inv_swap => cli.handleInvSwap(),
                    .use_item => cli.handleUseItem(),
                    .hello => cli.handleHello(),
                    .inv_drop => cli.handleInvDrop(),
                    .pong => cli.handlePong(),
                    .teleport => cli.handleTeleport(),
                    .use_portal => cli.handleUsePortal(),
                    .buy => cli.handleBuy(),
                    .ground_damage => cli.handleGroundDamage(),
                    .player_hit => cli.handlePlayerHit(),
                    .enemy_hit => cli.handleEnemyHit(),
                    .aoe_ack => cli.handleAoeAck(),
                    .shoot_ack => cli.handleShootAck(),
                    .other_hit => cli.handleOtherHit(),
                    .square_hit => cli.handleSquareHit(),
                    .escape => cli.handleEscape(),
                    .map_hello => cli.handleMapHello(),
                    .use_ability => cli.handleUseAbility(),
                    else => {
                        std.log.err("Unknown C2SPacketId: id={}, size={d}, len={d}", .{ packet_id, size, len });
                        cli.reader.reset();
                        return .rearm;
                    },
                }

                if (cli.reader.index < next_packet_idx) {
                    std.log.err("C2S packet {} has {d} bytes left over", .{ packet_id, next_packet_idx - cli.reader.index });
                    cli.reader.index = next_packet_idx;
                }
            }
        }

        return .rearm;
    }

    fn shutdownCallback(self: ?*Client, _: *xev.Loop, c: *xev.Completion, socket: xev.TCP, _: xev.TCP.ShutdownError!void) xev.CallbackAction {
        if (self) |cli| {
            if (cli.loop == null)
                return .disarm;

            socket.close(cli.loop.?, c, Client, cli, closeCallback);
        }

        return .disarm;
    }

    fn closeCallback(self: ?*Client, _: *xev.Loop, _: *xev.Completion, _: xev.TCP, _: xev.TCP.CloseError!void) xev.CallbackAction {
        if (self) |cli| {
            cli.loop = null;
            cli.socket = null;
            cli.write_comp = null;
            cli.deinit();
        }

        return .disarm;
    }

    fn handlePlayerShoot(self: *Client) void {
        var reader = &self.reader;
        const time = reader.read(i64);
        _ = time;
        const bullet_id = reader.read(u8);
        const cont_type = reader.read(u16);
        {
            self.world.player_lock.lock();
            defer self.world.player_lock.unlock();
            if (self.world.findRef(Player, self.plr_id)) |player| {
                if (player.equips[0] != cont_type)
                    return;
            }
        }

        const x = reader.read(f32);
        const y = reader.read(f32);
        const angle = reader.read(f32);
        const item_props = game_data.item_type_to_props.get(cont_type) orelse return;
        const proj_props = item_props.projectile orelse return;
        var proj: Projectile = .{
            .owner_id = self.plr_id,
            .x = x,
            .y = y,
            .angle = angle,
            .start_time = std.time.microTimestamp(),
            .phys_dmg = proj_props.physical_damage,
            .magic_dmg = proj_props.magic_damage,
            .true_dmg = proj_props.true_damage,
            .bullet_id = bullet_id,
            .props = &proj_props,
        };
        {
            self.world.proj_lock.lock();
            defer self.world.proj_lock.unlock();
            _ = self.world.add(Projectile, &proj) catch return;
        }

        {
            self.world.player_lock.lock();
            defer self.world.player_lock.unlock();
            if (self.world.findRef(Player, self.plr_id)) |player| {
                player.bullets[bullet_id] = proj.obj_id;
            }
        }
    }

    fn handleMove(self: *Client) void {
        var reader = &self.reader;
        const tick_id = reader.read(u8);
        const time = reader.read(i64);
        const x = reader.read(f32);
        const y = reader.read(f32);
        const records = reader.read([]TimedPosition);
        _ = records;
        _ = time;
        _ = tick_id;

        if (x < 0.0 or y < 0.0)
            return;

        self.world.player_lock.lock();
        defer self.world.player_lock.unlock();
        if (self.world.findRef(Player, self.plr_id)) |player| {
            player.x = x;
            player.y = y;
        }
    }

    fn handlePlayerText(self: *Client) void {
        var reader = &self.reader;
        const text = reader.read([]u8);
        if (text.len == 0 or text.len > 256)
            return;

        self.world.player_lock.lock();
        defer self.world.player_lock.unlock();
        if (self.world.findRef(Player, self.plr_id)) |player| {
            if (text[0] == '/') {
                var split = std.mem.splitScalar(u8, text, ' ');
                command.handle(&split, player);
                return;
            }

            for (self.world.players.items) |*other_player| {
                other_player.client.queuePacket(.{ .text = .{
                    .name = player.name,
                    .obj_id = self.plr_id,
                    .bubble_time = 0,
                    .recipient = "",
                    .text = text,
                    .name_color = if (player.admin) 0xF2CA46 else 0xEBEBEB,
                    .text_color = if (player.admin) 0xD4AF37 else 0xB0B0B0,
                } });
            }
        }
    }

    fn handleUpdateAck(self: *Client) void {
        _ = self;
    }

    fn handleInvSwap(self: *Client) void {
        var reader = &self.reader;
        const time = reader.read(i64);
        _ = time;
        const x = reader.read(f32);
        _ = x;
        const y = reader.read(f32);
        _ = y;
        const from_obj_id = reader.read(i32);
        const from_slot_id = reader.read(u8);
        const to_obj_id = reader.read(i32);
        _ = to_obj_id;
        const to_slot_id = reader.read(u8);

        // todo container stuff
        self.world.player_lock.lock();
        defer self.world.player_lock.unlock();
        if (self.world.findRef(Player, from_obj_id)) |player| {
            const start = player.equips[from_slot_id];
            player.equips[from_slot_id] = player.equips[to_slot_id];
            player.equips[to_slot_id] = start;
            player.recalculateItems();
        }
    }

    fn handleUseItem(self: *Client) void {
        _ = self;
        // var reader = &self.reader;
        // const time = reader.read(i64);
        // const obj_id = reader.read(i32);
        // const slot_id = reader.read(u8);
        // const x = reader.read(f32);
        // const y = reader.read(f32);
        // const use_type = reader.read(game_data.UseType);
    }

    fn handleHello(self: *Client) void {
        var reader = &self.reader;
        const build_ver = reader.read([]u8);
        if (!std.mem.eql(u8, build_ver, settings.build_version)) {
            self.queuePacket(.{ .failure = .{ .fail_type = .message_with_disconnect, .desc = "Incorrect version" } });
            return;
        }

        const email = reader.read([]u8);
        const password = reader.read([]u8);
        const acc_id = db.login(email, password) catch |e| {
            switch (e) {
                error.NoData => self.queuePacket(.{ .failure = .{ .fail_type = .message_with_disconnect, .desc = "Invalid email" } }),
                error.InvalidCredentials => self.queuePacket(.{ .failure = .{ .fail_type = .message_with_disconnect, .desc = "Invalid credentials" } }),
                else => self.queuePacket(.{ .failure = .{ .fail_type = .message_with_disconnect, .desc = "Unknown error" } }),
            }
            return;
        };
        self.acc_id = acc_id;

        const char_id = reader.read(i16);
        self.char_id = char_id;
        const class_type = reader.read(u16);
        const skin_type = reader.read(u16);
        _ = class_type;
        _ = skin_type;

        self.world = maps.worlds.getPtr(maps.retrieve_id) orelse {
            self.queuePacket(.{ .failure = .{ .fail_type = .message_with_disconnect, .desc = "Retrieve does not exist" } });
            return;
        };
        var player: Player = .{
            .acc_data = db.AccountData.init(self.allocator, acc_id),
            .char_data = db.CharacterData.init(self.allocator, acc_id, @intCast(char_id)),
            .client = self,
        };

        {
            self.world.player_lock.lock();
            defer self.world.player_lock.unlock();
            self.plr_id = self.world.add(Player, &player) catch {
                self.queuePacket(.{ .failure = .{ .fail_type = .message_with_disconnect, .desc = "Adding player to map failed" } });
                return;
            };
        }

        self.queuePacket(.{ .map_info = .{
            .width = @intCast(self.world.w),
            .height = @intCast(self.world.h),
            .name = self.world.name,
            .bg_light_color = self.world.light_data.light_color,
            .bg_light_intensity = self.world.light_data.light_intensity,
            .day_light_intensity = self.world.light_data.day_light_intensity,
            .night_light_intensity = self.world.light_data.night_light_intensity,
            .server_time = std.time.microTimestamp(),
        } });

        self.queuePacket(.{ .create_success = .{
            .player_id = self.plr_id,
            .char_id = char_id,
        } });
    }

    fn handleInvDrop(self: *Client) void {
        var reader = &self.reader;
        const obj_id = reader.read(i32);
        const slot_id = reader.read(u8);

        {
            self.world.player_lock.lock();
            defer self.world.player_lock.unlock();
            if (self.world.findRef(Player, obj_id)) |player| {
                // todo spawn bag
                player.equips[slot_id] = 0xFFFF;
                player.recalculateItems();
            }
        }

        // todo container (should it even be a thing?)
    }

    fn handlePong(self: *Client) void {
        _ = self;
        // var reader = &self.reader;
        // const serial = reader.read(i64);
        // const time = reader.read(i64);
    }

    fn handleTeleport(self: *Client) void {
        _ = self;
        // var reader = &self.reader;
        // const obj_id = reader.read(i32);
    }

    fn handleUsePortal(self: *Client) void {
        var reader = &self.reader;
        const obj_id = reader.read(i32);

        self.world.entity_lock.lock();
        const en_type = if (self.world.find(Entity, obj_id)) |e| e.en_type else return;
        self.world.entity_lock.unlock();

        {
            self.world.player_lock.lock();
            defer self.world.player_lock.unlock();
            const player = self.world.findRef(Player, self.plr_id) orelse {
                self.queuePacket(.{ .failure = .{ .fail_type = .message_with_disconnect, .desc = "Player does not exist" } });
                return;
            };

            self.world.remove(Player, player) catch {
                self.queuePacket(.{ .failure = .{ .fail_type = .message_with_disconnect, .desc = "Removing player from map failed" } });
                return;
            };
        }

        self.world = maps.portalWorld(en_type, obj_id) catch {
            self.queuePacket(.{ .failure = .{ .fail_type = .message_with_disconnect, .desc = "Map load failed" } });
            return;
        } orelse {
            self.queuePacket(.{ .failure = .{ .fail_type = .message_with_disconnect, .desc = "Map does not exist" } });
            return;
        };

        var new_player: Player = .{
            .acc_data = db.AccountData.init(self.allocator, self.acc_id),
            .char_data = db.CharacterData.init(self.allocator, self.acc_id, @intCast(self.char_id)),
            .client = self,
        };

        {
            self.world.player_lock.lock();
            defer self.world.player_lock.unlock();
            self.plr_id = self.world.add(Player, &new_player) catch {
                self.queuePacket(.{ .failure = .{ .fail_type = .message_with_disconnect, .desc = "Adding player to map failed" } });
                return;
            };
        }

        self.queuePacket(.{ .map_info = .{
            .width = @intCast(self.world.w),
            .height = @intCast(self.world.h),
            .name = self.world.name,
            .bg_light_color = self.world.light_data.light_color,
            .bg_light_intensity = self.world.light_data.light_intensity,
            .day_light_intensity = self.world.light_data.day_light_intensity,
            .night_light_intensity = self.world.light_data.night_light_intensity,
            .server_time = std.time.microTimestamp(),
        } });

        self.queuePacket(.{ .create_success = .{
            .player_id = self.plr_id,
            .char_id = self.char_id,
        } });
    }

    fn handleBuy(self: *Client) void {
        _ = self;
        // var reader = &self.reader;
        // const obj_id = reader.read(i32);
    }

    fn handleGroundDamage(self: *Client) void {
        var reader = &self.reader;
        const time = reader.read(i64);
        _ = time;
        const x = reader.read(f32);
        const y = reader.read(f32);

        const ux: u16 = @intFromFloat(x);
        const uy: u16 = @intFromFloat(y);
        const props = self.world.tiles[uy * self.world.w + ux].props;

        self.world.player_lock.lock();
        defer self.world.player_lock.unlock();
        if (self.world.findRef(Player, self.plr_id)) |player| {
            player.damage(props.obj_id, props.physical_damage, props.magic_damage, props.true_damage);
        }
    }

    fn handlePlayerHit(self: *Client) void {
        var reader = &self.reader;
        const bullet_id = reader.read(u8);
        const obj_id = reader.read(i32);
        self.world.enemy_lock.lock();
        defer self.world.enemy_lock.unlock();
        if (self.world.find(Enemy, obj_id)) |enemy| {
            self.world.proj_lock.lock();
            defer self.world.proj_lock.unlock();
            if (self.world.findRef(Projectile, enemy.bullets[bullet_id] orelse return)) |proj| {
                if (proj.obj_ids_hit.contains(self.plr_id))
                    return;

                self.world.player_lock.lock();
                defer self.world.player_lock.unlock();
                if (self.world.findRef(Player, self.plr_id)) |player| {
                    player.damage(enemy.props.display_id, proj.phys_dmg, proj.magic_dmg, proj.true_dmg);
                    proj.obj_ids_hit.put(self.plr_id, {}) catch return;
                }
            }
        }
    }

    fn handleEnemyHit(self: *Client) void {
        var reader = &self.reader;
        const time = reader.read(i64);
        _ = time;
        const bullet_id = reader.read(u8);
        const target_id = reader.read(i32);
        const killed = reader.read(bool);
        _ = killed;

        self.world.player_lock.lock();
        defer self.world.player_lock.unlock();
        if (self.world.find(Player, self.plr_id)) |player| {
            self.world.enemy_lock.lock();
            defer self.world.enemy_lock.unlock();
            if (self.world.findRef(Enemy, target_id)) |enemy| {
                self.world.proj_lock.lock();
                defer self.world.proj_lock.unlock();
                if (self.world.findRef(Projectile, player.bullets[bullet_id] orelse return)) |proj| {
                    enemy.damage(proj.phys_dmg, proj.magic_dmg, proj.true_dmg);
                    if (!proj.props.multi_hit) proj.delete() catch return;
                }
            }
        }
    }

    fn handleAoeAck(self: *Client) void {
        _ = self;
        // var reader = &self.reader;
        // const time = reader.read(i64);
        // const x = reader.read(f32);
        // const y = reader.read(f32);
    }

    fn handleShootAck(self: *Client) void {
        var reader = &self.reader;
        const time = reader.read(i64);
        _ = time;
    }

    fn handleOtherHit(self: *Client) void {
        _ = self;
        // var reader = &self.reader;
        // const time = reader.read(i64);
        // const bullet_id = reader.read(u8);
        // const obj_id = reader.read(i32);
        // const target_id = reader.read(i32);
    }

    fn handleSquareHit(self: *Client) void {
        _ = self;
        // var reader = &self.reader;
        // const time = reader.read(i64);
        // const bullet_id = reader.read(u8);
        // const obj_id = reader.read(i32);
    }

    fn handleEscape(self: *Client) void {
        {
            self.world.player_lock.lock();
            defer self.world.player_lock.unlock();
            const player = self.world.findRef(Player, self.plr_id) orelse {
                self.queuePacket(.{ .failure = .{ .fail_type = .message_with_disconnect, .desc = "Player does not exist" } });
                return;
            };

            self.world.remove(Player, player) catch {
                self.queuePacket(.{ .failure = .{ .fail_type = .message_with_disconnect, .desc = "Removing player from map failed" } });
                return;
            };
        }

        self.world = maps.worlds.getPtr(maps.retrieve_id) orelse {
            self.queuePacket(.{ .failure = .{ .fail_type = .message_with_disconnect, .desc = "Retrieve does not exist" } });
            return;
        };

        var new_player: Player = .{
            .acc_data = db.AccountData.init(self.allocator, self.acc_id),
            .char_data = db.CharacterData.init(self.allocator, self.acc_id, @intCast(self.char_id)),
            .client = self,
        };

        {
            self.world.player_lock.lock();
            defer self.world.player_lock.unlock();
            self.plr_id = self.world.add(Player, &new_player) catch {
                self.queuePacket(.{ .failure = .{ .fail_type = .message_with_disconnect, .desc = "Adding player to map failed" } });
                return;
            };
        }

        self.queuePacket(.{ .map_info = .{
            .width = @intCast(self.world.w),
            .height = @intCast(self.world.h),
            .name = self.world.name,
            .bg_light_color = self.world.light_data.light_color,
            .bg_light_intensity = self.world.light_data.light_intensity,
            .day_light_intensity = self.world.light_data.day_light_intensity,
            .night_light_intensity = self.world.light_data.night_light_intensity,
            .server_time = std.time.microTimestamp(),
        } });

        self.queuePacket(.{ .create_success = .{
            .player_id = self.plr_id,
            .char_id = self.char_id,
        } });
    }

    fn handleMapHello(self: *Client) void {
        _ = self;
        // var reader = &self.reader;
        // const build_ver = reader.readArray(u8);
        // const email = reader.readArray(u8);
        // const password = reader.readArray(u8);
        // const char_id = reader.read(i16);
        // const eclipse_map = reader.readArray(u8);
    }

    fn handleUseAbility(self: *Client) void {
        _ = self;
        // var reader = &self.reader;
        // const time = reader.read(i64);
        // const ability_type = reader.read(u8);
        // const data = reader.read([]u8);
    }
};
