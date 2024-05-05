const std = @import("std");
const game_data = @import("shared").game_data;

const Entity = @import("map/entity.zig").Entity;
const Enemy = @import("map/enemy.zig").Enemy;
const Player = @import("map/player.zig").Player;
const Client = @import("client.zig").Client;

inline fn h(str: []const u8) u64 {
    return std.hash.Wyhash.hash(0, str);
}

inline fn checkRank(player: *Player, comptime rank: u16) bool {
    if (player.rank >= rank)
        return true;

    player.client.queuePacket(.{ .text = .{
        .name = "Server",
        .obj_id = -1,
        .bubble_time = 0,
        .recipient = "",
        .text = "You don't meet the rank requirements",
        .name_color = 0xCC00CC,
        .text_color = 0xFF99FF,
    } });
    return false;
}

pub fn handle(iter: *std.mem.SplitIterator(u8, .scalar), player: *Player) void {
    const command_name = iter.next() orelse return;
    switch (h(command_name)) {
        h("/spawn") => if (checkRank(player, 100)) handleSpawn(iter, player),
        h("/clearspawn") => if (checkRank(player, 100)) handleClearSpawn(player),
        h("/give") => if (checkRank(player, 100)) handleGive(iter, player),
        else => {
            player.client.queuePacket(.{ .text = .{
                .name = "Server",
                .obj_id = -1,
                .bubble_time = 0,
                .recipient = "",
                .text = "Unknown command",
                .name_color = 0xCC00CC,
                .text_color = 0xFF99FF,
            } });
        },
    }
}

fn handleSpawn(iter: *std.mem.SplitIterator(u8, .scalar), player: *Player) void {
    var buf: [256]u8 = undefined;
    var name_stream = std.io.fixedBufferStream(&buf);
    const first_str = iter.next() orelse return;
    const count = blk: {
        const int = std.fmt.parseInt(u16, first_str, 0) catch {
            _ = name_stream.write(first_str) catch unreachable;
            break :blk 1;
        };

        break :blk int;
    };
    if (iter.index) |i| {
        if (name_stream.pos != 0)
            _ = name_stream.write(" ") catch unreachable;
        _ = name_stream.write(iter.buffer[i..]) catch unreachable;
    }

    const obj_type = game_data.obj_name_to_type.get(name_stream.getWritten()) orelse return;
    const props = game_data.obj_type_to_props.getPtr(obj_type) orelse return;

    for (0..count) |_| {
        if (props.is_enemy) {
            var enemy: Enemy = .{
                .x = player.x,
                .y = player.y,
                .en_type = obj_type,
                .props = props,
                .spawned = true,
            };
            player.world.enemy_lock.lock();
            defer player.world.enemy_lock.unlock();
            _ = player.world.add(Enemy, &enemy) catch return;
        } else {
            var entity: Entity = .{
                .x = player.x,
                .y = player.y,
                .en_type = obj_type,
                .props = props,
                .spawned = true,
            };
            player.world.entity_lock.lock();
            defer player.world.entity_lock.unlock();
            _ = player.world.add(Entity, &entity) catch return;
        }
    }

    player.client.queuePacket(.{ .text = .{
        .name = "Server",
        .obj_id = -1,
        .bubble_time = 0,
        .recipient = "",
        .text = std.fmt.bufPrint(&buf, "Spawned {d}x {s}", .{ count, game_data.obj_type_to_name.get(obj_type) orelse "Unknown" }) catch return,
        .name_color = 0xCC00CC,
        .text_color = 0xFF99FF,
    } });
}

fn handleGive(iter: *std.mem.SplitIterator(u8, .scalar), player: *Player) void {
    _ = iter;
    _ = player;
}

fn handleClearSpawn(player: *Player) void {
    var count: usize = 0;
    {
        player.world.enemy_lock.lock();
        defer player.world.enemy_lock.unlock();
        for (player.world.enemies.items) |*en| {
            if (en.spawned) {
                player.world.remove(Enemy, en) catch continue;
                count += 1;
            }
        }
    }

    {
        player.world.entity_lock.lock();
        defer player.world.entity_lock.unlock();
        for (player.world.entities.items) |*en| {
            if (en.spawned) {
                player.world.remove(Entity, en) catch continue;
                count += 1;
            }
        }
    }

    if (count == 0) {
        player.client.queuePacket(.{ .text = .{
            .name = "Server",
            .obj_id = -1,
            .bubble_time = 0,
            .recipient = "",
            .text = "No entities found",
            .name_color = 0xCC00CC,
            .text_color = 0xFF99FF,
        } });
    } else {
        var buf: [256]u8 = undefined;
        player.client.queuePacket(.{ .text = .{
            .name = "Server",
            .obj_id = -1,
            .bubble_time = 0,
            .recipient = "",
            .text = std.fmt.bufPrint(&buf, "Cleared {d} entities", .{count}) catch return,
            .name_color = 0xCC00CC,
            .text_color = 0xFF99FF,
        } });
    }
}
