const std = @import("std");
const xev = @import("xev");
const utils = @import("utils.zig");
const settings = @import("settings.zig");
const main = @import("main.zig");
const map = @import("game/map.zig");
const game_data = @import("game_data.zig");
const element = @import("ui/element.zig");
const camera = @import("camera.zig");
const assets = @import("assets.zig");
const particles = @import("game/particles.zig");
const systems = @import("ui/systems.zig");
const dialog = @import("ui/dialogs/dialog.zig");
const rpc = @import("rpc");

const Square = @import("game/square.zig").Square;
const Player = @import("game/player.zig").Player;
const GameObject = @import("game/game_object.zig").GameObject;
const Projectile = @import("game/projectile.zig").Projectile;

const read_buffer_size = 65535;
const write_buffer_size = 65535;

const C2SQueue = struct {
    pub const PollResult = enum { Empty, Retry, Item };
    pub const Node = struct { buf: []u8, next_opt: ?*Node };

    head: *Node,
    tail: *Node,
    stub: *Node,

    pub fn init(self: *C2SQueue, stub: *Node) void {
        @atomicStore(*Node, &self.stub, stub, .Monotonic);
        @atomicStore(?*Node, &self.stub.next_opt, null, .Monotonic);
        @atomicStore(*Node, &self.head, self.stub, .Monotonic);
        @atomicStore(*Node, &self.tail, self.stub, .Monotonic);
    }

    pub fn push(self: *C2SQueue, node: *Node) void {
        @atomicStore(?*Node, &node.next_opt, null, .Monotonic);
        const prev = @atomicRmw(*Node, &self.head, .Xchg, node, .AcqRel);
        @atomicStore(?*Node, &prev.next_opt, node, .Release);
    }

    pub fn isEmpty(self: *C2SQueue) bool {
        var tail = @atomicLoad(*Node, &self.tail, .Monotonic);
        const next_opt = @atomicLoad(?*Node, &tail.next_opt, .Acquire);
        const head = @atomicLoad(*Node, &self.head, .Acquire);
        return tail == self.stub and next_opt == null and tail == head;
    }

    pub fn poll(self: *C2SQueue, node: **Node) PollResult {
        var head: *Node = undefined;
        var tail = @atomicLoad(*Node, &self.tail, .Monotonic);
        var next_opt = @atomicLoad(?*Node, &tail.next_opt, .Acquire);

        if (tail == self.stub) {
            if (next_opt) |next| {
                @atomicStore(*Node, &self.tail, next, .Monotonic);
                tail = next;
                next_opt = @atomicLoad(?*Node, &tail.next_opt, .Acquire);
            } else {
                head = @atomicLoad(*Node, &self.head, .Acquire);
                return if (tail != head) .Retry else .Empty;
            }
        }

        if (next_opt) |next| {
            @atomicStore(*Node, &self.tail, next, .Monotonic);
            node.* = tail;
            return .Item;
        }

        head = @atomicLoad(*Node, &self.head, .Acquire);
        if (tail != head) {
            return .Retry;
        }

        self.push(self.stub);

        next_opt = @atomicLoad(?*Node, &tail.next_opt, .Acquire);
        if (next_opt) |next| {
            @atomicStore(*Node, &self.tail, next, .Monotonic);
            node.* = tail;
            return .Item;
        }

        return .Retry;
    }

    pub fn pop(self: *C2SQueue) ?*Node {
        var result = PollResult.Retry;
        var node: *Node = undefined;

        while (result == .Retry) {
            result = self.poll(&node);
            if (result == .Empty) {
                return null;
            }
        }

        return node;
    }

    pub fn getNext(self: *C2SQueue, prev: *Node) ?*Node {
        var next_opt = @atomicLoad(?*Node, &prev.next_opt, .Acquire);

        if (next_opt) |next| {
            if (next == self.stub) {
                next_opt = @atomicLoad(?*Node, &next.next_opt, .Acquire);
            }
        }

        return next_opt;
    }
};

pub const FailureType = enum(i8) {
    message_no_disconnect = -1,
    message_with_disconnect = 0,
    client_update_needed = 1,
    force_close_game = 2,
    invalid_teleport_target = 3,
};

pub const TimedPosition = packed struct {
    time: i64,
    x: f32,
    y: f32,
};

pub const TileData = extern struct {
    x: u16,
    y: u16,
    tile_type: u16,
};

pub const TradeItem = extern struct {
    item: i32,
    slot_type: i32,
    tradeable: bool,
    included: bool,
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
    edit_account_list = 20,
    create_guild = 21,
    guild_remove = 22,
    guild_invite = 23,
    request_trade = 24,
    change_trade = 25,
    accept_trade = 26,
    cancel_trade = 27,
    escape = 28,
    join_guild = 29,
    change_guild_rank = 30,
    reskin = 31,
    map_hello = 32,
    use_ability = 33,
};

// All packets without variable length fields (like slices) should be packed.
// This allows us to directly copy the struct into the buffer
pub const C2SPacket = union(C2SPacketId) {
    unknown: packed struct {},
    player_shoot: packed struct { time: i64, bullet_id: u8, container_type: u16, start_x: f32, start_y: f32, angle: f32 },
    move: struct { tick_id: u8, time: i64, pos_x: f32, pos_y: f32, records: []const TimedPosition },
    player_text: struct { text: []const u8 },
    update_ack: packed struct {},
    inv_swap: packed struct {
        time: i64,
        x: f32,
        y: f32,
        from_obj_id: i32,
        from_slot_id: u8,
        to_obj_id: i32,
        to_slot_id: u8,
    },
    use_item: packed struct { time: i64, obj_id: i32, slot_id: u8, x: f32, y: f32, use_type: game_data.UseType },
    hello: struct {
        build_ver: []const u8,
        game_id: i32,
        email: []const u8,
        password: []const u8,
        char_id: i16,
        class_type: u16,
        skin_type: u16,
    },
    inv_drop: packed struct { obj_id: i32, slot_id: u8 },
    pong: packed struct { serial: i64, time: i64 },
    teleport: packed struct { obj_id: i32 },
    use_portal: packed struct { obj_id: i32 },
    buy: packed struct { obj_id: i32 },
    ground_damage: packed struct { time: i64, x: f32, y: f32 },
    player_hit: packed struct { bullet_id: u8, object_id: i32 },
    enemy_hit: packed struct { time: i64, bullet_id: u8, target_id: i32, killed: bool },
    aoe_ack: packed struct { time: i64, x: f32, y: f32 },
    shoot_ack: packed struct { time: i64 },
    other_hit: packed struct { time: i64, bullet_id: u8, object_id: i32, target_id: i32 },
    square_hit: packed struct { time: i64, bullet_id: u8, obj_id: i32 },
    edit_account_list: packed struct { list_id: i32, add: bool, obj_id: i32 },
    create_guild: struct { guild_name: []const u8 },
    guild_remove: struct { name: []const u8 },
    guild_invite: struct { name: []const u8 },
    request_trade: struct { name: []const u8 },
    change_trade: struct { offer: []bool },
    accept_trade: struct { my_offer: []bool, your_offer: []bool },
    cancel_trade: packed struct {},
    escape: packed struct {},
    join_guild: struct { name: []const u8 },
    change_guild_rank: struct { name: []const u8, rank: i32 },
    reskin: packed struct { skin_id: i32 },
    map_hello: struct { name: []const u8 },
    use_ability: struct { time: i64, ability_type: u8, data: []u8 },
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
    buy_result = 14,
    aoe = 15,
    account_list = 16,
    quest_obj_id = 17,
    guild_result = 18,
    ally_shoot = 19,
    enemy_shoot = 20,
    trade_requested = 21,
    trade_start = 22,
    trade_changed = 23,
    trade_done = 24,
    trade_accepted = 25,
    invited_to_guild = 26,
    failure = 28,
};

pub const Server = struct {
    loop: *xev.Loop,
    socket: ?xev.TCP = null,
    write_queue: C2SQueue = undefined,
    completion_pool: std.heap.MemoryPool(xev.Completion),
    node_pool: std.heap.MemoryPool(C2SQueue.Node),
    write_buffer_pool: std.heap.MemoryPool([write_buffer_size]u8),
    reader: utils.PacketReader = .{},
    write_lock: std.Thread.Mutex = .{},
    write_comp: ?*xev.Completion = null,
    allocator: std.mem.Allocator = undefined,
    hello_data: C2SPacket = undefined,

    pub fn init(allocator: std.mem.Allocator, loop: *xev.Loop) !Server {
        var ret = Server{
            .loop = loop,
            .completion_pool = std.heap.MemoryPool(xev.Completion).init(allocator),
            .node_pool = std.heap.MemoryPool(C2SQueue.Node).init(allocator),
            .write_buffer_pool = std.heap.MemoryPool([write_buffer_size]u8).init(allocator),
            .allocator = allocator,
        };

        ret.write_queue.init(try allocator.create(C2SQueue.Node));
        ret.reader.buffer = try allocator.alloc(u8, read_buffer_size);
        return ret;
    }

    fn disposeCallback(ud: ?*anyopaque, _: *xev.Loop, c: *xev.Completion, _: xev.Result) xev.CallbackAction {
        const self: *Server = @ptrCast(@alignCast(ud.?));
        self.completion_pool.destroy(c);
        self.write_comp = null;
        return .disarm;
    }

    fn cancelWriteQueue(self: *Server) void {
        self.write_queue.init(self.write_queue.stub);

        if (self.write_comp) |wc| {
            var c = self.completion_pool.create() catch unreachable;
            c.op = .{ .cancel = .{ .c = wc } };
            c.userdata = self;
            c.callback = disposeCallback;
            self.loop.add(c);
        }
    }

    pub fn deinit(self: *Server) void {
        self.loop.stop();
        while (self.loop.flags.in_run) {}
        self.loop.deinit();
        self.completion_pool.deinit();
        self.write_buffer_pool.deinit();
        self.node_pool.deinit();
        self.allocator.destroy(self.write_queue.stub);
        self.allocator.free(self.reader.buffer);
    }

    pub fn connect(self: *Server, ip: []const u8, port: u16, hello_data: C2SPacket) !void {
        const addr = try std.net.Address.parseIp4(ip, port);
        const socket = try xev.TCP.init(addr);

        self.hello_data = hello_data;

        const c = try self.completion_pool.create();
        socket.connect(self.loop, c, addr, Server, self, connectCallback);
        try self.loop.run(.until_done);
    }

    pub fn shutdown(self: *Server) void {
        if (self.socket == null)
            return;

        const c = self.completion_pool.create() catch unreachable;
        self.socket.?.shutdown(self.loop, c, Server, self, shutdownCallback);
    }

    pub fn queuePacket(self: *Server, packet: C2SPacket) void {
        if (self.socket == null)
            return;

        const needs_cancel = packet == .use_portal or packet == .escape;

        // What's the point of the MPSC queue if we're going to have to lock either way for MemoryPool? todo thread safe MemoryPool
        self.write_lock.lock();

        defer {
            self.write_lock.unlock();
            if (needs_cancel) {
                main.clear();
                main.tick_frame = false;
            }
        }

        if (needs_cancel)
            self.cancelWriteQueue();

        if (settings.log_packets == .all or
            settings.log_packets == .c2s or
            (settings.log_packets == .c2s_non_tick or settings.log_packets == .all_non_tick) and packet != .move and packet != .update_ack)
        {
            std.log.info("Send: {}", .{packet}); // todo custom formatting
        }

        var writer = utils.PacketWriter{ .buffer = self.write_buffer_pool.create() catch unreachable };
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

        const empty = self.write_queue.isEmpty();
        const node = self.node_pool.create() catch unreachable;
        node.buf = writer.buffer[0..writer.index];
        self.write_queue.push(node);
        if (empty) {
            self.write_comp = self.completion_pool.create() catch unreachable;
            self.socket.?.write(self.loop, self.write_comp.?, .{ .slice = node.buf }, Server, self, writeCallback);
        }
    }

    fn connectCallback(self: ?*Server, _: *xev.Loop, c: *xev.Completion, socket: xev.TCP, _: xev.TCP.ConnectError!void) xev.CallbackAction {
        if (self) |srv| {
            srv.socket = socket;
            socket.read(srv.loop, c, .{ .slice = srv.reader.buffer }, Server, srv, readCallback);
            srv.queuePacket(srv.hello_data);
        }

        return .disarm;
    }

    fn writeCallback(self: ?*Server, _: *xev.Loop, c: *xev.Completion, _: xev.TCP, _: xev.WriteBuffer, result: xev.TCP.WriteError!usize) xev.CallbackAction {
        if (self) |srv| {
            _ = result catch |e| {
                std.log.err("Write error: {}", .{e});
                main.disconnect();
                dialog.showDialog(.text, .{
                    .title = "Connection Error",
                    .body = "Writing was interrupted",
                });
                return .disarm;
            };

            if (srv.write_queue.pop()) |node| {
                if (srv.write_queue.getNext(node)) |next| {
                    srv.socket.?.write(srv.loop, c, .{ .slice = next.buf }, Server, srv, writeCallback);
                } else {
                    srv.completion_pool.destroy(c);
                    srv.write_comp = null;
                }

                srv.write_buffer_pool.destroy(
                    @alignCast(
                        @as(*[write_buffer_size]u8, @ptrFromInt(@intFromPtr(node.buf.ptr))),
                    ),
                );
                srv.node_pool.destroy(node);
            }
        }

        return .disarm;
    }

    fn readCallback(self: ?*Server, _: *xev.Loop, _: *xev.Completion, _: xev.TCP, _: xev.ReadBuffer, result: xev.TCP.ReadError!usize) xev.CallbackAction {
        if (self) |srv| {
            const size = result catch |e| {
                std.log.err("Read error: {}", .{e});
                main.disconnect();
                dialog.showDialog(.text, .{
                    .title = "Connection Error",
                    .body = "Reading was interrupted",
                });
                return .disarm;
            };
            srv.reader.index = 0;
            srv.reader.size = size;

            while (srv.reader.index < size - 3) {
                const len = srv.reader.read(u16);
                if (len > size - srv.reader.index)
                    return .rearm;

                const next_packet_idx = srv.reader.index + len;
                const byte_id = srv.reader.read(u8);
                const packet_id = std.meta.intToEnum(S2CPacketId, byte_id) catch |e| {
                    std.log.err("Error parsing S2CPacketId ({}): id={d}, size={d}, len={d}", .{ e, byte_id, size, len });
                    srv.reader.index = 0;
                    return .rearm;
                };

                switch (packet_id) {
                    .account_list => srv.handleAccountList(),
                    .ally_shoot => srv.handleAllyShoot(),
                    .aoe => srv.handleAoe(),
                    .buy_result => srv.handleBuyResult(),
                    .create_success => srv.handleCreateSuccess(),
                    .damage => srv.handleDamage(),
                    .death => srv.handleDeath(),
                    .enemy_shoot => srv.handleEnemyShoot(),
                    .failure => srv.handleFailure(),
                    .goto => srv.handleGoto(),
                    .invited_to_guild => srv.handleInvitedToGuild(),
                    .inv_result => srv.handleInvResult(),
                    .map_info => srv.handleMapInfo(),
                    .new_tick => srv.handleNewTick(),
                    .notification => srv.handleNotification(),
                    .ping => srv.handlePing(),
                    .quest_obj_id => srv.handleQuestObjId(),
                    .server_player_shoot => srv.handleServerPlayerShoot(),
                    .show_effect => srv.handleShowEffect(),
                    .text => srv.handleText(),
                    .trade_accepted => srv.handleTradeAccepted(),
                    .trade_changed => srv.handleTradeChanged(),
                    .trade_done => srv.handleTradeDone(),
                    .trade_requested => srv.handleTradeRequested(),
                    .trade_start => srv.handleTradeStart(),
                    .update => srv.handleUpdate(),
                    else => {
                        std.log.err("Unknown S2CPacketId: id={}, size={d}, len={d}", .{ packet_id, size, len });
                        srv.reader.index = 0;
                        return .rearm;
                    },
                }

                if (srv.reader.index < next_packet_idx) {
                    std.log.err("S2C packet {} has {d} bytes left over", .{ packet_id, next_packet_idx - srv.reader.index });
                    srv.reader.index = next_packet_idx;
                }
            }
        }

        return .rearm;
    }

    fn shutdownCallback(self: ?*Server, _: *xev.Loop, c: *xev.Completion, socket: xev.TCP, _: xev.TCP.ShutdownError!void) xev.CallbackAction {
        if (self) |srv| {
            socket.close(srv.loop, c, Server, srv, closeCallback);
        }

        return .disarm;
    }

    fn closeCallback(self: ?*Server, _: *xev.Loop, _: *xev.Completion, _: xev.TCP, _: xev.TCP.CloseError!void) xev.CallbackAction {
        if (self) |srv| {
            srv.loop.stop();
            while (srv.loop.flags.in_run) {}

            srv.socket = null;
            srv.write_comp = null;
            _ = srv.completion_pool.reset(.free_all);
            _ = srv.node_pool.reset(.free_all);
            _ = srv.write_buffer_pool.reset(.free_all);
        }

        return .disarm;
    }

    fn handleAccountList(self: *Server) void {
        var reader = &self.reader;
        const account_list_id = reader.read(i32);
        const account_ids = reader.readArray(i32);

        if (settings.log_packets == .all or settings.log_packets == .s2c or settings.log_packets == .s2c_non_tick or settings.log_packets == .all_non_tick)
            std.log.debug("Recv - AccountList: account_list_id={d}, account_ids={d}", .{ account_list_id, account_ids });
    }

    fn handleAllyShoot(self: *Server) void {
        var reader = &self.reader;
        const bullet_id = reader.read(u8);
        const owner_id = reader.read(i32);
        const container_type = reader.read(u16);
        const angle = reader.read(f32);

        map.object_lock.lock();
        defer map.object_lock.unlock();

        if (map.findEntityRef(owner_id)) |en| {
            if (en.* == .player) {
                const player = &en.player;
                const item_props = game_data.item_type_to_props.getPtr(@intCast(container_type));
                const proj_props = item_props.?.projectile.?;
                var proj = Projectile{
                    .x = player.x,
                    .y = player.y,
                    .props = proj_props,
                    .angle = angle,
                    .bullet_id = @intCast(bullet_id),
                    .owner_id = player.obj_id,
                };
                proj.addToMap();

                const attack_period: i64 = @intFromFloat(1.0 / (Player.attack_frequency * item_props.?.rate_of_fire));
                player.attack_period = attack_period;
                player.attack_angle = angle - camera.angle;
                player.attack_start = main.current_time;
            }
        }

        if (settings.log_packets == .all or settings.log_packets == .s2c or settings.log_packets == .s2c_non_tick or settings.log_packets == .all_non_tick)
            std.log.debug("Recv - AllyShoot: bullet_id={d}, owner_id={d}, container_type={d}, angle={e}", .{ bullet_id, owner_id, container_type, angle });
    }

    fn handleAoe(self: *Server) void {
        var reader = &self.reader;
        const x = reader.read(f32);
        const y = reader.read(f32);
        const radius = reader.read(f32);
        const damage = reader.read(u16);
        const condition_effect = reader.read(utils.Condition);
        const duration = reader.read(f32);
        const orig_type = reader.read(u8);
        const color = reader.read(u32);

        var effect = particles.AoeEffect{
            .x = x,
            .y = y,
            .color = 0xFF0000,
            .radius = radius,
        };
        effect.addToMap();

        if (settings.log_packets == .all or settings.log_packets == .s2c or settings.log_packets == .s2c_non_tick or settings.log_packets == .all_non_tick)
            std.log.debug("Recv - Aoe: x={e}, y={e}, radius={e}, damage={d}, condition_effect={}, duration={e}, orig_type={d}, color={d}", .{ x, y, radius, damage, condition_effect, duration, orig_type, color });
    }

    fn handleBuyResult(self: *Server) void {
        var reader = &self.reader;
        const result = reader.read(i32);
        const message = reader.readArray(u8);

        if (settings.log_packets == .all or settings.log_packets == .s2c or settings.log_packets == .s2c_non_tick)
            std.log.debug("Recv - BuyResult: result={d}, message={s}", .{ result, message });
    }

    fn handleCreateSuccess(self: *Server) void {
        var reader = &self.reader;
        map.local_player_id = reader.read(i32);
        const char_id = reader.read(i32);

        if (settings.log_packets == .all or settings.log_packets == .s2c or settings.log_packets == .s2c_non_tick or settings.log_packets == .all_non_tick)
            std.log.debug("Recv - CreateSuccess: player_id={d}, char_id={d}", .{ map.local_player_id, char_id });
    }

    fn handleDamage(self: *Server) void {
        var reader = &self.reader;
        const target_id = reader.read(i32);
        const effects = reader.read(utils.Condition);
        const amount = reader.read(u16);
        const kill = reader.read(bool);
        const bullet_id = reader.read(u8);
        const object_id = reader.read(i32);

        map.object_lock.lock();
        defer map.object_lock.unlock();

        if (map.findEntityRef(target_id)) |en| {
            switch (en.*) {
                .player => |*player| {
                    player.takeDamage(
                        amount,
                        0,
                        0,
                        kill,
                        effects,
                        player.colors,
                        0.0,
                        100.0 / 10000.0,
                        self.allocator,
                    );
                },
                .object => |*object| {
                    object.takeDamage(
                        amount,
                        0,
                        0,
                        kill,
                        effects,
                        object.colors,
                        0.0,
                        100.0 / 10000.0,
                        self.allocator,
                    );
                },
                else => {},
            }
        }

        if (settings.log_packets == .all or settings.log_packets == .s2c or settings.log_packets == .s2c_non_tick or settings.log_packets == .all_non_tick)
            std.log.debug("Recv - Damage: target_id={d}, effects={}, damage_amount={d}, kill={}, bullet_id={d}, object_id={d}", .{ target_id, effects, amount, kill, bullet_id, object_id });
    }

    fn handleDeath(self: *Server) void {
        var reader = &self.reader;
        const account_id = reader.read(i32);
        const char_id = reader.read(i32);
        const killed_by = reader.readArray(u8);

        assets.playSfx("death_screen");
        main.disconnect();

        if (settings.log_packets == .all or settings.log_packets == .s2c or settings.log_packets == .s2c_non_tick)
            std.log.debug("Recv - Death: account_id={d}, char_id={d}, killed_by={s}", .{ account_id, char_id, killed_by });
    }

    fn handleEnemyShoot(self: *Server) void {
        var reader = &self.reader;
        const bullet_id = reader.read(u8);
        const owner_id = reader.read(i32);
        const bullet_type = reader.read(u8);
        const start_x = reader.read(f32);
        const start_y = reader.read(f32);
        const angle = reader.read(f32);
        const physical_damage = reader.read(i16);
        const magic_damage = reader.read(i16);
        const true_damage = reader.read(i16);
        const num_shots = reader.read(u8);
        const angle_inc = reader.read(f32);

        // why?
        if (num_shots == 0)
            return;

        map.object_lock.lockShared();
        defer map.object_lock.unlockShared();

        var owner: ?GameObject = null;
        if (map.findEntityConst(owner_id)) |en| {
            if (en == .object) {
                owner = en.object;
            }
        }

        if (owner == null)
            return;

        const owner_props = game_data.obj_type_to_props.getPtr(owner.?.obj_type);
        if (owner_props == null or bullet_type >= owner_props.?.projectiles.len)
            return;

        const total_angle = angle_inc * @as(f32, @floatFromInt(num_shots - 1));
        var current_angle = angle - total_angle / 2.0;
        const proj_props = owner_props.?.projectiles[bullet_type];

        for (0..num_shots) |i| {
            var proj = Projectile{
                .x = start_x,
                .y = start_y,
                .physical_damage = physical_damage,
                .magic_damage = magic_damage,
                .true_damage = true_damage,
                .props = proj_props,
                .angle = current_angle,
                .bullet_id = bullet_id +% @as(u8, @intCast(i)),
                .owner_id = owner_id,
                .damage_players = true,
            };
            proj.addToMap();

            current_angle += angle_inc;
        }

        owner.?.attack_angle = angle;
        owner.?.attack_start = main.current_time;

        if (settings.log_packets == .all or settings.log_packets == .s2c or settings.log_packets == .s2c_non_tick or settings.log_packets == .all_non_tick)
            std.log.debug("Recv - EnemyShoot: bullet_id={d}, owner_id={d}, bullet_type={d}, x={e}, y={e}, angle={e}, physical_damage={d}, magic_damage={d}, true_damage={d}, num_shots={d}, angle_inc={e}", .{ bullet_id, owner_id, bullet_type, start_x, start_y, angle, physical_damage, magic_damage, true_damage, num_shots, angle_inc });

        self.queuePacket(.{ .shoot_ack = .{ .time = main.current_time } });
    }

    fn handleFailure(self: *Server) void {
        var reader = &self.reader;
        const error_id = reader.read(FailureType);
        const error_description = self.allocator.dupe(u8, reader.readArray(u8)) catch &[0]u8{};

        if (error_id == .message_with_disconnect or error_id == .force_close_game) {
            main.disconnect();
            dialog.showDialog(.text, .{
                .title = "Connection Error",
                .body = error_description,
                .dispose_body = true,
            });
        }

        if (settings.log_packets == .all or settings.log_packets == .s2c or settings.log_packets == .s2c_non_tick)
            std.log.debug("Recv - Failure: error_id={}, error_description={s}", .{ error_id, error_description });
    }

    fn handleGoto(self: *Server) void {
        var reader = &self.reader;
        const object_id = reader.read(i32);
        const x = reader.read(f32);
        const y = reader.read(f32);

        map.object_lock.lock();
        defer map.object_lock.unlock();

        if (map.findEntityRef(object_id)) |en| {
            if (en.* == .player) {
                const player = &en.player;
                player.x = x;
                player.y = y;
            }
        } else {
            std.log.err("Object id {d} not found while attempting to goto to pos x={d}, y={d}", .{ object_id, x, y });
        }

        if (settings.log_packets == .all or settings.log_packets == .s2c or settings.log_packets == .s2c_non_tick)
            std.log.debug("Recv - Goto: object_id={d}, x={e}, y={e}", .{ object_id, x, y });
    }

    fn handleGuildResult(self: *Server) void {
        var reader = &self.reader;
        const success = reader.read(bool);
        const error_text = reader.readArray(u8);

        if (settings.log_packets == .all or settings.log_packets == .s2c or settings.log_packets == .s2c_non_tick)
            std.log.debug("Recv - GuildResult: success={}, error_text={s}", .{ success, error_text });
    }

    fn handleInvitedToGuild(self: *Server) void {
        var reader = &self.reader;
        const guild_name = reader.readArray(u8);
        const name = reader.readArray(u8);

        if (settings.log_packets == .all or settings.log_packets == .s2c or settings.log_packets == .s2c_non_tick)
            std.log.debug("Recv - InvitedToGuild: guild_name={s}, name={s}", .{ guild_name, name });
    }

    fn handleInvResult(self: *Server) void {
        var reader = &self.reader;
        const result = reader.read(u8);

        if (settings.log_packets == .all or settings.log_packets == .s2c or settings.log_packets == .s2c_non_tick)
            std.log.debug("Recv - InvResult: result={d}", .{result});
    }

    fn handleMapInfo(self: *Server) void {
        var reader = &self.reader;
        main.clear();
        camera.quake = false;

        const width: u32 = @intCast(@max(0, reader.read(i32)));
        const height: u32 = @intCast(@max(0, reader.read(i32)));
        map.setWH(width, height);
        if (map.name.len > 0)
            self.allocator.free(map.name);
        map.name = self.allocator.dupe(u8, reader.readArray(u8)) catch "";

        map.bg_light_color = reader.read(u32);
        map.bg_light_intensity = reader.read(f32);
        const allow_player_teleport = reader.read(bool);
        const uses_day_night = reader.read(bool);
        if (uses_day_night) {
            map.day_light_intensity = reader.read(f32);
            map.night_light_intensity = reader.read(f32);
            map.server_time_offset = reader.read(i64) - main.current_time;
        } else {
            map.day_light_intensity = 0.0;
            map.night_light_intensity = 0.0;
            map.server_time_offset = 0;
        }

        main.tick_frame = true;

        if (settings.log_packets == .all or settings.log_packets == .s2c or settings.log_packets == .s2c_non_tick)
            std.log.debug("Recv - MapInfo: width={d}, height={d}, name={s}, bg_light_color={d}, bg_light_intensity={e}, allow_player_teleport={}, day_and_night={}", .{ width, height, map.name, map.bg_light_color, map.bg_light_intensity, allow_player_teleport, uses_day_night });
    }

    fn handleNewTick(self: *Server) void {
        var reader = &self.reader;
        const tick_id = reader.read(u8);
        const tick_time = @as(f32, std.time.us_per_s) / @as(f32, @floatFromInt(reader.read(u8)));

        map.object_lock.lock();
        defer map.object_lock.unlock();

        defer {
            if (main.tick_frame) {
                const time = main.current_time;
                if (map.localPlayerRef()) |local_player| {
                    self.queuePacket(.{ .move = .{
                        .tick_id = tick_id,
                        .time = time,
                        .pos_x = local_player.x,
                        .pos_y = local_player.y,
                        .records = map.move_records.items,
                    } });

                    local_player.onMove();
                } else {
                    self.queuePacket(.{ .move = .{
                        .tick_id = tick_id,
                        .time = time,
                        .pos_x = -1,
                        .pos_y = -1,
                        .records = &[0]TimedPosition{},
                    } });
                }

                map.clearMoveRecords(time);
            }
        }

        var stat_reader = utils.PacketReader{};
        const statuses_len = reader.read(u16);
        for (0..statuses_len) |_| {
            const obj_id = reader.read(i32);
            const x = reader.read(f32);
            const y = reader.read(f32);

            stat_reader.index = 0;
            stat_reader.buffer = reader.readArrayMut(u8);
            stat_reader.size = stat_reader.buffer.len;

            if (map.findEntityRef(obj_id)) |en| {
                switch (en.*) {
                    .player => |*player| {
                        if (player.obj_id != map.local_player_id) {
                            const y_dt = y - player.y;
                            const x_dt = x - player.x;

                            if (!std.math.isNan(player.move_angle)) {
                                const dist_sqr = y_dt * y_dt + x_dt * x_dt;
                                player.move_step = @sqrt(dist_sqr) / tick_time;
                                player.target_x = x;
                                player.target_y = y;
                                player.move_x_dir = player.x < x;
                                player.move_y_dir = player.y < y;
                                player.x_dir = x_dt / tick_time;
                                player.y_dir = y_dt / tick_time;
                            } else {
                                player.x = x;
                                player.y = y;
                            }

                            player.move_angle = if (y_dt <= 0 and x_dt <= 0) std.math.nan(f32) else std.math.atan2(y_dt, x_dt);
                        }

                        while (stat_reader.index < stat_reader.buffer.len) {
                            const stat_id = stat_reader.read(u8);
                            const stat = std.meta.intToEnum(game_data.StatType, stat_id) catch |e| {
                                std.log.err("Could not parse stat {d}: {}", .{ stat_id, e });
                                continue;
                            };
                            if (!parsePlayerStat(&player.*, stat, &stat_reader, self.allocator)) {
                                std.log.err("Stat data parsing for stat {} failed, player: {}", .{ stat, player });
                                continue;
                            }
                        }

                        if (player.obj_id == map.local_player_id and systems.screen == .game)
                            systems.screen.game.updateStats();

                        continue;
                    },
                    .object => |*object| {
                        {
                            const y_dt = y - object.y;
                            const x_dt = x - object.x;

                            if (!std.math.isNan(object.move_angle)) {
                                const dist_sqr = y_dt * y_dt + x_dt * x_dt;
                                object.move_step = @sqrt(dist_sqr) / tick_time;
                                object.target_x = x;
                                object.target_y = y;
                                object.move_x_dir = object.x < x;
                                object.move_y_dir = object.y < y;
                            } else {
                                object.x = x;
                                object.y = y;
                            }

                            object.move_angle = if (y_dt == 0 and x_dt == 0) std.math.nan(f32) else std.math.atan2(y_dt, x_dt);
                        }

                        while (stat_reader.index < stat_reader.buffer.len) {
                            const stat_id = stat_reader.read(u8);
                            const stat = std.meta.intToEnum(game_data.StatType, stat_id) catch |e| {
                                std.log.err("Could not parse stat {d}: {}", .{ stat_id, e });
                                continue;
                            };
                            if (!parseObjectStat(&object.*, stat, &stat_reader, self.allocator)) {
                                std.log.err("Stat data parsing for stat {} failed, object: {}", .{ stat, object });
                                continue;
                            }
                        }

                        continue;
                    },
                    else => {},
                }
            }

            std.log.err("Could not find object in NewTick (obj_id={d}, x={d:.2}, y={d:.2})", .{ obj_id, x, y });
        }

        if (settings.log_packets == .all or settings.log_packets == .s2c or settings.log_packets == .s2c_tick)
            std.log.debug("Recv - NewTick: tick_id={d}, tick_time={d}, statuses_len={d}", .{ tick_id, tick_time, statuses_len });
    }

    fn handleNotification(self: *Server) void {
        var reader = &self.reader;
        const object_id = reader.read(i32);
        const message = reader.readArray(u8);
        const color = reader.read(u32);

        map.object_lock.lockShared();
        defer map.object_lock.unlockShared();

        if (map.findEntityConst(object_id)) |en| {
            const text_data = element.TextData{
                .text = self.allocator.dupe(u8, message) catch return,
                .text_type = .bold,
                .size = 16,
                .color = color,
            };

            if (en == .player) {
                element.StatusText.add(.{
                    .obj_id = en.player.obj_id,
                    .lifetime = 2000,
                    .text_data = text_data,
                    .initial_size = 16,
                }) catch unreachable;
            } else if (en == .object) {
                element.StatusText.add(.{
                    .obj_id = en.object.obj_id,
                    .lifetime = 2000,
                    .text_data = text_data,
                    .initial_size = 16,
                }) catch unreachable;
            }
        }

        if (settings.log_packets == .all or settings.log_packets == .s2c or settings.log_packets == .s2c_non_tick)
            std.log.debug("Recv - Notification: object_id={d}, message={s}, color={}", .{ object_id, message, color });
    }

    fn handlePing(self: *Server) void {
        var reader = &self.reader;
        const serial = reader.read(i64);

        self.queuePacket(.{ .pong = .{ .serial = serial, .time = main.current_time } });

        if (settings.log_packets == .all or settings.log_packets == .s2c or settings.log_packets == .s2c_tick)
            std.log.debug("Recv - Ping: serial={d}", .{serial});
    }

    fn handlePlaySound(self: *Server) void {
        var reader = &self.reader;
        const owner_id = reader.read(i32);
        const sound_id = reader.read(u8);

        if (settings.log_packets == .all or settings.log_packets == .s2c or settings.log_packets == .s2c_non_tick)
            std.log.debug("Recv - PlaySound: owner_id={d}, sound_id={d}", .{ owner_id, sound_id });
    }

    fn handleQuestObjId(self: *Server) void {
        var reader = &self.reader;
        const object_id = reader.read(i32);

        if (settings.log_packets == .all or settings.log_packets == .s2c or settings.log_packets == .s2c_non_tick)
            std.log.debug("Recv - QuestObjId: object_id={d}", .{object_id});
    }

    fn handleServerPlayerShoot(self: *Server) void {
        var reader = &self.reader;
        const bullet_id = reader.read(u8);
        const owner_id = reader.read(i32);
        const container_type = reader.read(u16);
        const start_x = reader.read(f32);
        const start_y = reader.read(f32);
        const angle = reader.read(f32);
        const damage = reader.read(i16);
        const num_shots = 1; // todo
        const angle_inc = 0.0;

        if (settings.log_packets == .all or settings.log_packets == .s2c or settings.log_packets == .s2c_non_tick)
            std.log.debug("Recv - ServerPlayerShoot: bullet_id={d}, owner_id={d}, container_type={d}, x={e}, y={e}, angle={e}, damage={d}", .{ bullet_id, owner_id, container_type, start_x, start_y, angle, damage });
        map.object_lock.lockShared();
        defer map.object_lock.unlockShared();

        const needs_ack = owner_id == map.local_player_id;
        if (map.findEntityConst(owner_id)) |en| {
            if (en == .player) {
                const item_props = game_data.item_type_to_props.getPtr(@intCast(container_type));
                if (item_props == null or item_props.?.projectile == null)
                    return;

                const proj_props = item_props.?.projectile.?;
                const total_angle = angle_inc * @as(f32, @floatFromInt(num_shots - 1));
                var current_angle = angle - total_angle / 2.0;
                for (0..num_shots) |i| {
                    var proj = Projectile{
                        .x = start_x,
                        .y = start_y,
                        .physical_damage = damage,
                        .props = proj_props,
                        .angle = current_angle,
                        .bullet_id = bullet_id +% @as(u8, @intCast(i)), // this is wrong but whatever
                        .owner_id = owner_id,
                    };
                    proj.addToMap();

                    current_angle += angle_inc;
                }

                if (needs_ack) {
                    self.queuePacket(.{ .shoot_ack = .{ .time = main.current_time } });
                }
            } else {
                if (needs_ack) {
                    self.queuePacket(.{ .shoot_ack = .{ .time = -1 } });
                }
            }
        }
    }

    fn handleShowEffect(self: *Server) void {
        var reader = &self.reader;
        const effect_type: game_data.ShowEffect = @enumFromInt(reader.read(u8));
        const target_object_id = reader.read(i32);
        const x1 = reader.read(f32);
        const y1 = reader.read(f32);
        const x2 = reader.read(f32);
        const y2 = reader.read(f32);
        const color = reader.read(u32);

        switch (effect_type) {
            .throw => {
                var start_x = x2;
                var start_y = y2;

                map.object_lock.lockShared();
                defer map.object_lock.unlockShared();

                if (map.findEntityConst(target_object_id)) |en| {
                    switch (en) {
                        .object => |object| {
                            start_x = object.x;
                            start_y = object.y;
                        },
                        .player => |player| {
                            start_x = player.x;
                            start_y = player.y;
                        },
                        else => {},
                    }
                }

                var effect = particles.ThrowEffect{
                    .start_x = start_x,
                    .start_y = start_y,
                    .end_x = x1,
                    .end_y = y1,
                    .color = color,
                    .duration = 1500,
                };
                effect.addToMap();
            },
            .teleport => {
                var effect = particles.TeleportEffect{
                    .x = x1,
                    .y = y1,
                };
                effect.addToMap();
            },
            .trail => {
                var start_x = x2;
                var start_y = y2;

                map.object_lock.lockShared();
                defer map.object_lock.unlockShared();

                if (map.findEntityConst(target_object_id)) |en| {
                    switch (en) {
                        .object => |object| {
                            start_x = object.x;
                            start_y = object.y;
                        },
                        .player => |player| {
                            start_x = player.x;
                            start_y = player.y;
                        },
                        else => {},
                    }
                }

                var effect = particles.LineEffect{
                    .start_x = start_x,
                    .start_y = start_y,
                    .end_x = x1,
                    .end_y = y1,
                    .color = color,
                };
                effect.addToMap();
            },
            .potion => {
                // the effect itself handles checks for invalid entity
                var effect = particles.HealEffect{
                    .target_id = target_object_id,
                    .color = color,
                };
                effect.addToMap();
            },
            .earthquake => {
                camera.quake = true;
                camera.quake_amount = 0.0;
            },
            else => {},
        }

        if (settings.log_packets == .all or settings.log_packets == .s2c or settings.log_packets == .s2c_non_tick)
            std.log.debug("Recv - ShowEffect: effect_type={}, target_object_id={d}, x1={e}, y1={e}, x2={e}, y2={e}, color={}", .{ effect_type, target_object_id, x1, y1, x2, y2, color });
    }

    fn handleText(self: *Server) void {
        var reader = &self.reader;
        const name = reader.readArray(u8);
        const object_id = reader.read(i32);
        const bubble_time = reader.read(u8);
        const recipient = reader.readArray(u8);
        const text = reader.readArray(u8);
        var name_color: u32 = 0xFF0000;
        var text_color: u32 = 0xFFFFFF;
        if (name.len > 0)
            name_color = reader.read(u32);
        if (text.len > 0)
            text_color = reader.read(u32);

        if (systems.screen == .game)
            systems.screen.game.addChatLine(name, text, name_color, text_color) catch |e| {
                std.log.err("Adding message with name {s} and text {s} failed: {}", .{ name, text, e });
            };
        map.object_lock.lockShared();
        defer map.object_lock.unlockShared();

        if (map.findEntityConst(object_id)) |en| {
            var atlas_data = assets.error_data;
            if (assets.ui_atlas_data.get("speech_balloons")) |balloon_data| {
                switch (name_color) {
                    0xD4AF37 => atlas_data = balloon_data[5], // admin balloon
                    // todo
                    0x000000 => atlas_data = balloon_data[2], // guild balloon
                    0x000001 => atlas_data = balloon_data[4], // party balloon
                    else => {
                        if (!std.mem.eql(u8, recipient, "")) {
                            atlas_data = balloon_data[1]; // tell balloon
                        } else {
                            if (en == .object) {
                                atlas_data = balloon_data[3]; // enemy balloon
                            } else {
                                atlas_data = balloon_data[0]; // normal balloon
                            }
                        }
                    },
                }
            } else std.debug.panic("Could not find speech_balloons in the UI atlas", .{});

            element.SpeechBalloon.add(.{
                .image_data = .{ .normal = .{
                    .scale_x = 3.0,
                    .scale_y = 3.0,
                    .atlas_data = atlas_data,
                } },
                .text_data = .{
                    .text = self.allocator.dupe(u8, text) catch unreachable,
                    .size = 16,
                    .max_width = 160,
                    .outline_width = 1.5,
                    .disable_subpixel = true,
                    .color = text_color,
                },
                .target_id = object_id,
            }) catch unreachable;
        }

        if (settings.log_packets == .all or settings.log_packets == .s2c or settings.log_packets == .s2c_non_tick)
            std.log.debug("Recv - Text: name={s}, object_id={d}, bubble_time={d}, recipient={s}, text={s}", .{ name, object_id, bubble_time, recipient, text });
    }

    fn handleTradeAccepted(self: *Server) void {
        var reader = &self.reader;
        const my_offer = reader.readArray(bool);
        const your_offer = reader.readArray(bool);

        if (settings.log_packets == .all or settings.log_packets == .s2c or settings.log_packets == .s2c_non_tick)
            std.log.debug("Recv - TradeAccepted: my_offer={any}, your_offer={any}", .{ my_offer, your_offer });
    }

    fn handleTradeChanged(self: *Server) void {
        var reader = &self.reader;
        const offer = reader.readArray(bool);

        if (settings.log_packets == .all or settings.log_packets == .s2c or settings.log_packets == .s2c_non_tick)
            std.log.debug("Recv - TradeChanged: offer={any}", .{offer});
    }

    fn handleTradeDone(self: *Server) void {
        var reader = &self.reader;
        const code = reader.read(i32);
        const description = reader.readArray(u8);

        if (settings.log_packets == .all or settings.log_packets == .s2c or settings.log_packets == .s2c_non_tick)
            std.log.debug("Recv - TradeDone: code={d}, description={s}", .{ code, description });
    }

    fn handleTradeRequested(self: *Server) void {
        var reader = &self.reader;
        const name = reader.readArray(u8);

        if (settings.log_packets == .all or settings.log_packets == .s2c or settings.log_packets == .s2c_non_tick)
            std.log.debug("Recv - TradeRequested: name={s}", .{name});
    }

    fn handleTradeStart(self: *Server) void {
        var reader = &self.reader;
        const my_items = reader.readArray(TradeItem);
        const your_name = reader.readArray(u8);
        const your_items = reader.readArray(TradeItem);

        if (settings.log_packets == .all or settings.log_packets == .s2c or settings.log_packets == .s2c_non_tick)
            std.log.debug("Recv - TradeStart: my_items={any}, your_name={s}, your_items={any}", .{ my_items, your_name, your_items });
    }

    fn handleUpdate(self: *Server) void {
        var reader = &self.reader;
        defer if (main.tick_frame) self.queuePacket(.{ .update_ack = .{} });

        const tiles = reader.readArray(TileData);
        for (tiles) |tile| {
            var square = Square{
                .tile_type = tile.tile_type,
                .x = @as(f32, @floatFromInt(tile.x)) + 0.5,
                .y = @as(f32, @floatFromInt(tile.y)) + 0.5,
            };

            square.addToMap();
        }

        main.need_minimap_update = tiles.len > 0;

        const drops = reader.readArray(i32);
        {
            map.object_lock.lock();
            defer map.object_lock.unlock();
            for (drops) |drop| {
                map.removeEntity(self.allocator, drop);
            }
        }

        var stat_reader = utils.PacketReader{};
        const new_objs_len = reader.read(u16);
        for (0..new_objs_len) |_| {
            const obj_type = reader.read(u16);
            const obj_id = reader.read(i32);
            const x = reader.read(f32);
            const y = reader.read(f32);

            stat_reader.index = 0;
            stat_reader.buffer = reader.readArrayMut(u8);
            stat_reader.size = stat_reader.buffer.len;

            const class = game_data.obj_type_to_class.get(obj_type) orelse game_data.ClassType.game_object;

            switch (class) {
                .player => {
                    var player = Player{ .x = x, .y = y, .obj_id = obj_id, .obj_type = obj_type };

                    while (stat_reader.index < stat_reader.buffer.len) {
                        const stat_id = stat_reader.read(u8);
                        const stat = std.meta.intToEnum(game_data.StatType, stat_id) catch |e| {
                            std.log.err("Could not parse stat {d}: {}", .{ stat_id, e });
                            continue;
                        };
                        if (!parsePlayerStat(&player, stat, &stat_reader, self.allocator)) {
                            std.log.err("Stat data parsing for stat {} failed, player: {}", .{ stat, player });
                            continue;
                        }
                    }

                    player.addToMap(self.allocator);
                },
                inline else => {
                    var obj = GameObject{ .x = x, .y = y, .obj_id = obj_id, .obj_type = obj_type };

                    while (stat_reader.index < stat_reader.buffer.len) {
                        const stat_id = stat_reader.read(u8);
                        const stat = std.meta.intToEnum(game_data.StatType, stat_id) catch |e| {
                            std.log.err("Could not parse stat {d}: {}", .{ stat_id, e });
                            continue;
                        };
                        if (!parseObjectStat(&obj, stat, &stat_reader, self.allocator)) {
                            std.log.err("Stat data parsing for stat {} failed, object: {}", .{ stat, obj });
                            continue;
                        }
                    }

                    obj.addToMap(self.allocator);
                },
            }
        }

        if (settings.log_packets == .all or settings.log_packets == .s2c or settings.log_packets == .s2c_tick)
            std.log.debug("Recv - Update: tiles_len={d}, new_objs_len={d}, drops_len={d}", .{ tiles.len, new_objs_len, drops.len });
    }

    fn parsePlayerStat(plr: *Player, stat_type: game_data.StatType, stat_reader: *utils.PacketReader, allocator: std.mem.Allocator) bool {
        switch (stat_type) {
            .max_hp => plr.max_hp = stat_reader.read(i32),
            .hp => {
                plr.hp = stat_reader.read(i32);
                if (plr.hp > 0)
                    plr.dead = false;
            },
            .size => plr.size = @as(f32, @floatFromInt(stat_reader.read(u16))) / 100.0,
            .max_mp => plr.max_mp = stat_reader.read(i16),
            .mp => plr.mp = stat_reader.read(i16),
            .strength => plr.strength = stat_reader.read(i16),
            .defense => plr.defense = stat_reader.read(i16),
            .speed => plr.speed = stat_reader.read(i16),
            .stamina => plr.stamina = stat_reader.read(i16),
            .wit => plr.wit = stat_reader.read(i16),
            .resistance => plr.resistance = stat_reader.read(i16),
            .intelligence => plr.intelligence = stat_reader.read(i16),
            .penetration => plr.penetration = stat_reader.read(i16),
            .piercing => plr.piercing = stat_reader.read(i16),
            .haste => plr.haste = stat_reader.read(i16),
            .tenacity => plr.tenacity = stat_reader.read(i16),
            .hp_bonus => plr.hp_bonus = stat_reader.read(i16),
            .mp_bonus => plr.mp_bonus = stat_reader.read(i16),
            .strength_bonus => plr.strength_bonus = stat_reader.read(i16),
            .defense_bonus => plr.defense_bonus = stat_reader.read(i16),
            .speed_bonus => plr.speed_bonus = stat_reader.read(i16),
            .stamina_bonus => plr.stamina_bonus = stat_reader.read(i16),
            .wit_bonus => plr.wit_bonus = stat_reader.read(i16),
            .resistance_bonus => plr.resistance_bonus = stat_reader.read(i16),
            .intelligence_bonus => plr.intelligence_bonus = stat_reader.read(i16),
            .penetration_bonus => plr.penetration_bonus = stat_reader.read(i16),
            .piercing_bonus => plr.piercing_bonus = stat_reader.read(i16),
            .haste_bonus => plr.haste_bonus = stat_reader.read(i16),
            .tenacity_bonus => plr.tenacity_bonus = stat_reader.read(i16),
            .hit_multiplier => plr.hit_multiplier = stat_reader.read(f32),
            .damage_multiplier => plr.damage_multiplier = stat_reader.read(f32),
            .condition => plr.condition = stat_reader.read(utils.Condition),
            .inv_0, .inv_1, .inv_2, .inv_3, .inv_4, .inv_5, .inv_6, .inv_7, .inv_8, .inv_9, .inv_10, .inv_11, .inv_12, .inv_13, .inv_14, .inv_15, .inv_16, .inv_17, .inv_18, .inv_19, .inv_20, .inv_21 => {
                const inv_idx = @intFromEnum(stat_type) - @intFromEnum(game_data.StatType.inv_0);
                const item = stat_reader.read(u16);
                plr.inventory[inv_idx] = item;
                if (plr.obj_id == map.local_player_id and systems.screen == .game)
                    systems.screen.game.setInvItem(item, inv_idx);
            },
            .name => {
                if (plr.name) |player_name| {
                    allocator.free(player_name);
                }

                plr.name = allocator.dupe(u8, stat_reader.readArray(u8)) catch &[0]u8{};

                if (plr.name_text_data) |*data| {
                    data.setText(plr.name.?, allocator);
                } else {
                    plr.name_text_data = element.TextData{
                        .text = plr.name.?,
                        .text_type = .bold,
                        .size = 12,
                        .color = 0xFCDF00,
                        .max_width = 200,
                    };

                    {
                        plr.name_text_data.?.lock.lock();
                        defer plr.name_text_data.?.lock.unlock();

                        plr.name_text_data.?.recalculateAttributes(allocator);
                    }
                }
            },
            .tex_1 => plr.tex_1 = stat_reader.read(i32),
            .tex_2 => plr.tex_2 = stat_reader.read(i32),
            .gold => plr.gold = stat_reader.read(i32),
            .gems => plr.gems = stat_reader.read(i32),
            .crowns => plr.crowns = stat_reader.read(i32),
            .account_id => plr.account_id = stat_reader.read(i32),
            .guild => {
                if (plr.guild) |guild_name| {
                    allocator.free(guild_name);
                }

                plr.guild = allocator.dupe(u8, stat_reader.readArray(u8)) catch &[0]u8{};
            },
            .guild_rank => plr.guild_rank = stat_reader.read(i8),
            .texture => plr.skin = stat_reader.read(u16),
            .tier => plr.tier = stat_reader.read(u8),
            .alt_texture_index => _ = stat_reader.read(u16),
            else => {
                std.log.err("Unknown player stat type: {}", .{stat_type});
                return false;
            },
        }

        return true;
    }

    fn parseObjectStat(obj: *GameObject, stat_type: game_data.StatType, stat_reader: *utils.PacketReader, allocator: std.mem.Allocator) bool {
        switch (stat_type) {
            .max_hp => obj.max_hp = stat_reader.read(i32),
            .hp => {
                obj.hp = stat_reader.read(i32);
                if (obj.hp > 0)
                    obj.dead = false;
            },
            .size => obj.size = @as(f32, @floatFromInt(stat_reader.read(u16))) / 100.0,
            .defense => obj.defense = stat_reader.read(i16),
            .resistance => obj.resistance = stat_reader.read(i16),
            .condition => obj.condition = stat_reader.read(utils.Condition),
            .inv_0, .inv_1, .inv_2, .inv_3, .inv_4, .inv_5, .inv_6, .inv_7, .inv_8 => {
                const inv_idx = @intFromEnum(stat_type) - @intFromEnum(game_data.StatType.inv_0);
                const item = stat_reader.read(u16);
                obj.inventory[inv_idx] = item;
                if (obj.obj_id == map.interactive_id.load(.Acquire) and systems.screen == .game) {
                    systems.screen.game.setContainerItem(item, inv_idx);
                }
            },
            .name => {
                const new_name = stat_reader.readArray(u8);
                if (new_name.len <= 0)
                    return true;

                if (obj.name) |obj_name| {
                    allocator.free(obj_name);
                }

                obj.name = allocator.dupe(u8, new_name) catch &[0]u8{};

                if (obj.name_text_data) |*data| {
                    data.setText(obj.name.?, allocator);
                } else {
                    obj.name_text_data = element.TextData{
                        .text = obj.name.?,
                        .text_type = .bold,
                        .size = 12,
                    };

                    {
                        obj.name_text_data.?.lock.lock();
                        defer obj.name_text_data.?.lock.unlock();

                        obj.name_text_data.?.recalculateAttributes(allocator);
                    }
                }
            },
            .tex_1 => _ = stat_reader.read(i32),
            .tex_2 => _ = stat_reader.read(i32),
            .merch_price => _ = stat_reader.read(u8),
            .merch_type => obj.merchant_obj_type = stat_reader.read(u16),
            .merch_count => obj.merchant_rem_count = stat_reader.read(i8),
            .sellable_price => obj.sellable_price = stat_reader.read(u16),
            //.sellable_currency => obj.sellable_currency = @enumFromInt(stat_reader.read(u8)),
            .portal_usable => obj.portal_active = stat_reader.read(bool),
            .owner_account_id => obj.owner_acc_id = stat_reader.read(i32),
            .alt_texture_index => obj.alt_texture_index = stat_reader.read(u16),
            else => {
                std.log.err("Unknown entity stat type: {}", .{stat_type});
                return false;
            },
        }

        return true;
    }
};
