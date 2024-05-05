const std = @import("std");
const builtin = @import("builtin");
const game_data = @import("game_data.zig");

pub const MPSCQueue = struct {
    pub const PollResult = enum { Empty, Retry, Item };
    pub const Node = struct { buf: []u8, next_opt: ?*Node };

    head: *Node,
    tail: *Node,
    stub: *Node,

    pub fn init(self: *MPSCQueue, stub: *Node) void {
        @atomicStore(*Node, &self.stub, stub, .Monotonic);
        @atomicStore(?*Node, &self.stub.next_opt, null, .Monotonic);
        @atomicStore(*Node, &self.head, self.stub, .Monotonic);
        @atomicStore(*Node, &self.tail, self.stub, .Monotonic);
    }

    pub fn push(self: *MPSCQueue, node: *Node) void {
        @atomicStore(?*Node, &node.next_opt, null, .Monotonic);
        const prev = @atomicRmw(*Node, &self.head, .Xchg, node, .AcqRel);
        @atomicStore(?*Node, &prev.next_opt, node, .Release);
    }

    pub fn isEmpty(self: *MPSCQueue) bool {
        var tail = @atomicLoad(*Node, &self.tail, .Monotonic);
        const next_opt = @atomicLoad(?*Node, &tail.next_opt, .Acquire);
        const head = @atomicLoad(*Node, &self.head, .Acquire);
        return tail == self.stub and next_opt == null and tail == head;
    }

    pub fn poll(self: *MPSCQueue, node: **Node) PollResult {
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

    pub fn pop(self: *MPSCQueue) ?*Node {
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

    pub fn getNext(self: *MPSCQueue, prev: *Node) ?*Node {
        var next_opt = @atomicLoad(?*Node, &prev.next_opt, .Acquire);

        if (next_opt) |next| {
            if (next == self.stub) {
                next_opt = @atomicLoad(?*Node, &next.next_opt, .Acquire);
            }
        }

        return next_opt;
    }
};

// Big endian isn't supported on this
pub const PacketWriter = struct {
    index: u16 = 0,
    length_index: u16 = 0,
    buffer: []u8 = undefined,

    pub fn writeLength(self: *PacketWriter) void {
        self.length_index = self.index;
        self.index += 2;
    }

    pub fn updateLength(self: *PacketWriter) void {
        const buf = self.buffer[self.length_index .. self.length_index + 2];
        const len = self.index - self.length_index - 2;
        @memcpy(buf, std.mem.asBytes(&len));
    }

    pub fn writeDirect(self: *PacketWriter, value: []const u8) void {
        const buf = self.buffer[self.index .. self.index + value.len];
        self.index += @intCast(value.len);
        @memcpy(buf, value);
    }

    pub fn write(self: *PacketWriter, value: anytype) void {
        const T = @TypeOf(value);
        const type_info = @typeInfo(T);

        if (type_info == .Pointer and (type_info.Pointer.size == .Slice or type_info.Pointer.size == .Many)) {
            self.write(@as(u16, @intCast(value.len)));
            for (value) |val|
                self.write(val);
            return;
        }

        if (type_info == .Array) {
            self.write(@as(u16, @intCast(value.len)));
            for (value) |val|
                self.write(val);
            return;
        }

        if (type_info == .Struct) {
            switch (type_info.Struct.layout) {
                .Auto, .Extern => {
                    inline for (type_info.Struct.fields) |field| {
                        self.write(@field(value, field.name));
                    }
                    return;
                },
                .Packed => {}, // will be handled below, packed structs are just ints
            }
        }

        const byte_size = @sizeOf(T);
        const buf = self.buffer[self.index .. self.index + byte_size];
        self.index += byte_size;
        @memcpy(buf, std.mem.asBytes(&value));
    }
};

// Big endian isn't supported on this
pub const PacketReader = struct {
    index: u16 = 0,
    buffer: []u8 = undefined,
    fba: std.heap.FixedBufferAllocator = undefined,
    size: usize = 0,

    pub fn reset(self: *PacketReader) void {
        self.index = 0;
        self.fba.reset();
    }

    pub fn read(self: *PacketReader, comptime T: type) T {
        const type_info = @typeInfo(T);
        if (type_info == .Pointer or type_info == .Array) {
            const ChildType = if (type_info == .Array) type_info.Array.child else type_info.Pointer.child;
            const len = self.read(u16);
            var ret = self.fba.allocator().alloc(ChildType, len) catch unreachable;
            for (0..len) |i| {
                ret[i] = self.read(ChildType);
            }

            return ret;
        }

        if (type_info == .Struct) {
            switch (type_info.Struct.layout) {
                .Auto, .Extern => {
                    var value: T = undefined;
                    inline for (type_info.Struct.fields) |field| {
                        @field(value, field.name) = self.read(field.type);
                    }
                    return value;
                },
                .Packed => {},
            }
        }

        const byte_size = @sizeOf(T);
        const next_idx = self.index + byte_size;
        if (next_idx > self.size)
            std.debug.panic("Buffer attempted to read out of bounds", .{});
        var buf = self.buffer[self.index..next_idx];
        self.index += byte_size;
        return std.mem.bytesToValue(T, buf[0..byte_size]);
    }
};

pub const ConditionEnum = enum(u8) {
    unknown = 0,
    dead = 1,
    weak = 2,
    slowed = 3,
    sick = 4,
    speedy = 5,
    bleeding = 6,
    healing = 7,
    damaging = 8,
    invulnerable = 9,
    armored = 10,
    armor_broken = 11,
    hidden = 12,
    targeted = 13,
    invisible = 14,

    const map = std.ComptimeStringMap(ConditionEnum, .{
        .{ "Unknown", .unknown },
        .{ "Dead", .dead },
        .{ "Weak", .weak },
        .{ "Slowed", .slowed },
        .{ "Sick", .sick },
        .{ "Speedy", .speedy },
        .{ "Bleeding", .bleeding },
        .{ "Healing", .healing },
        .{ "Damaging", .damaging },
        .{ "Invulnerable", .invulnerable },
        .{ "Armored", .armored },
        .{ "ArmorBroken", .armor_broken },
        .{ "Armor Broken", .armor_broken },
        .{ "Hidden", .hidden },
        .{ "Targeted", .targeted },
        .{ "Invisible", .invisible },
    });

    pub fn fromString(str: []const u8) ConditionEnum {
        return map.get(str) orelse .unknown;
    }

    pub fn toString(self: ConditionEnum) []const u8 {
        return switch (self) {
            .dead => "Dead",
            .weak => "Weak",
            .slowed => "Slowed",
            .sick => "Sick",
            .speedy => "Speedy",
            .bleeding => "Bleeding",
            .healing => "Healing",
            .damaging => "Damaging",
            .invulnerable => "Invulnerable",
            .armored => "Armored",
            .armor_broken => "Armor Broken",
            .hidden => "Hidden",
            .targeted => "Targeted",
            .invisible => "Invisible",
            else => "",
        };
    }
};

pub const Condition = packed struct(u32) {
    dead: bool = false,
    weak: bool = false,
    slowed: bool = false,
    sick: bool = false,
    speedy: bool = false,
    bleeding: bool = false,
    healing: bool = false,
    damaging: bool = false,
    invulnerable: bool = false,
    armored: bool = false,
    armor_broken: bool = false,
    hidden: bool = false,
    targeted: bool = false,
    invisible: bool = false,
    padding: u18 = 0,

    pub inline fn fromCondSlice(slice: []game_data.ConditionEffect) Condition {
        var ret = Condition{};
        for (slice) |cond| {
            ret.set(cond.condition, true);
        }
        return ret;
    }

    pub fn set(self: *Condition, cond: ConditionEnum, value: bool) void {
        switch (cond) {
            .weak => self.weak = value,
            .slowed => self.slowed = value,
            .sick => self.sick = value,
            .speedy => self.speedy = value,
            .bleeding => self.bleeding = value,
            .healing => self.healing = value,
            .damaging => self.damaging = value,
            .invulnerable => self.invulnerable = value,
            .armored => self.armored = value,
            .armor_broken => self.armor_broken = value,
            .hidden => self.hidden = value,
            .targeted => self.targeted = value,
            .invisible => self.invisible = value,
            else => std.log.err("Invalid enum specified for condition set: {}", .{@errorReturnTrace() orelse return}),
        }
    }

    pub fn toggle(self: *Condition, cond: ConditionEnum) void {
        switch (cond) {
            .weak => self.weak = !self.weak,
            .slowed => self.slowed = !self.slowed,
            .sick => self.sick = !self.sick,
            .speedy => self.speedy = !self.speedy,
            .bleeding => self.bleeding = !self.bleeding,
            .healing => self.healing = !self.healing,
            .damaging => self.damaging = !self.damaging,
            .invulnerable => self.invulnerable = !self.invulnerable,
            .armored => self.armored = !self.armored,
            .armor_broken => self.armor_broken = !self.armor_broken,
            .hidden => self.hidden = !self.hidden,
            .targeted => self.targeted = !self.targeted,
            .invisible => self.invisible = !self.invisible,
            else => std.log.err("Invalid enum specified for condition toggle: {}", .{@errorReturnTrace() orelse return}),
        }
    }
};

pub const Rect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    w_pad: f32,
    h_pad: f32,
};

pub var rng = std.rand.DefaultPrng.init(0);

var last_memory_access: i64 = -1;
var last_memory_value: f32 = -1.0;

pub fn currentMemoryUse(time: i64) !f32 {
    if (time - last_memory_access < 5 * std.time.us_per_s)
        return last_memory_value;

    var memory_value: f32 = -1.0;
    switch (builtin.os.tag) {
        .windows => {
            const mem_info = try std.os.windows.GetProcessMemoryInfo(std.os.windows.self_process_handle);
            memory_value = @as(f32, @floatFromInt(mem_info.WorkingSetSize)) / 1024.0 / 1024.0;
        },
        .linux => {
            const file = try std.fs.cwd().openFile("/proc/self/statm", .{});
            defer file.close();

            var buf: [1024]u8 = undefined;
            const size = try file.readAll(&buf);

            var split_iter = std.mem.split(u8, buf[0..size], " ");
            _ = split_iter.next(); // total size
            const rss: f32 = @floatFromInt(try std.fmt.parseInt(u32, split_iter.next().?, 0));
            memory_value = rss / 1024.0;
        },
        else => memory_value = 0,
    }

    last_memory_access = time;
    last_memory_value = memory_value;
    return memory_value;
}

pub inline fn toRoman(int: u12) []const u8 {
    if (int > 3999)
        return "Invalid";

    const value = [_]u12{ 1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1 };
    const roman = [_][]const u8{ "M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I" };

    var buf: [32]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    var num = int;
    for (0..value.len) |i| {
        while (num >= value[i]) {
            num -= value[i];
            stream.writer().writeAll(roman[i]) catch continue;
        }
    }

    return buf[0..stream.pos];
}

pub inline fn nextPowerOfTwo(value: u32) u32 {
    var mod_value = value - 1;
    mod_value |= mod_value >> 1;
    mod_value |= mod_value >> 2;
    mod_value |= mod_value >> 4;
    mod_value |= mod_value >> 8;
    mod_value |= mod_value >> 16;
    return mod_value + 1;
}

pub fn plusMinus(range: f32) f32 {
    return rng.random().float(f32) * range * 2 - range;
}

pub inline fn isInBounds(x: f32, y: f32, bound_x: f32, bound_y: f32, bound_w: f32, bound_h: f32) bool {
    return x >= bound_x and x <= bound_x + bound_w and y >= bound_y and y <= bound_y + bound_h;
}

pub fn halfBound(angle: f32) f32 {
    const mod_angle = @mod(angle, std.math.tau);
    const new_angle = @mod(mod_angle + std.math.tau, std.math.tau);
    return if (new_angle > std.math.pi) new_angle - std.math.tau else new_angle;
}

pub inline fn distSqr(x1: f32, y1: f32, x2: f32, y2: f32) f32 {
    const x_dt = x2 - x1;
    const y_dt = y2 - y1;
    return x_dt * x_dt + y_dt * y_dt;
}

pub inline fn dist(x1: f32, y1: f32, x2: f32, y2: f32) f32 {
    return @sqrt(distSqr(x1, y1, x2, y2));
}
