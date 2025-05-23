const std = @import("std");
const builtin = @import("builtin");

const game_data = @import("game_data.zig");

// Big endian isn't supported on this
pub const PacketWriter = struct {
    list: std.ArrayListUnmanaged(u8) = .empty,

    pub fn writeLength(self: *PacketWriter, allocator: std.mem.Allocator) void {
        self.list.appendSlice(allocator, &.{ 0, 0 }) catch @panic("OOM");
    }

    pub fn updateLength(self: *PacketWriter) void {
        const buf = self.list.items[0..2];
        const len: u16 = @intCast(self.list.items.len - 2);
        @memcpy(buf, std.mem.asBytes(&len));
    }

    pub fn write(self: *PacketWriter, value: anytype, allocator: std.mem.Allocator) void {
        const T = @TypeOf(value);
        const type_info = @typeInfo(T);

        if (type_info == .pointer and (type_info.pointer.size == .slice or type_info.pointer.size == .many)) {
            self.write(@as(u16, @intCast(value.len)), allocator);
            for (value) |val| self.write(val, allocator);
            return;
        }

        const value_bytes = std.mem.asBytes(&value);

        if (type_info == .@"struct") {
            switch (type_info.@"struct".layout) {
                .auto, .@"extern" => {
                    inline for (type_info.@"struct".fields) |field| {
                        self.write(@field(value, field.name), allocator);
                    }
                    return;
                },
                .@"packed" => {}, // will be handled below, packed structs are just ints
            }
        }

        self.list.appendSlice(allocator, value_bytes) catch @panic("OOM");
    }
};

// Big endian isn't supported on this
pub const PacketReader = struct {
    index: u16 = 0,
    buffer: []const u8 = undefined,

    pub const empty: PacketReader = .{
        .index = 0,
        .buffer = undefined,
    };

    // Arrays and slices are allocated. Using an arena allocator is recommended
    pub fn read(self: *PacketReader, comptime T: type, allocator: std.mem.Allocator) T {
        const type_info = @typeInfo(T);
        switch (type_info) {
            .pointer => {
                const ChildType = type_info.pointer.child;
                const len = self.read(u16, allocator);
                var ret = allocator.alloc(ChildType, len) catch @panic("OOM");
                for (0..len) |i| ret[i] = self.read(ChildType, allocator);
                return ret;
            },
            .@"struct" => {
                switch (type_info.@"struct".layout) {
                    .auto, .@"extern" => {
                        var value: T = undefined;
                        inline for (type_info.@"struct".fields) |field| @field(value, field.name) = self.read(field.type, allocator);
                        return value;
                    },
                    .@"packed" => {}, // will be handled below, packed structs are just ints
                }
            },
            else => {},
        }

        const byte_size = @sizeOf(T);
        const next_idx = self.index + byte_size;
        if (next_idx > self.buffer.len) @panic("Buffer attempted to read out of bounds");
        var buf = self.buffer[self.index..next_idx];
        self.index += byte_size;
        return std.mem.bytesToValue(T, buf[0..byte_size]);
    }
};

pub fn SpscQueue(comptime T: type, capacity: comptime_int) type {
    return struct {
        comptime {
            if (capacity < 2) @compileError("SpscQueue capacity has to be at least two");
        }

        data: [capacity]T = @splat(.{}),
        write_index: std.atomic.Value(usize) align(std.atomic.cache_line) = .init(0),
        cached_write_index: usize align(std.atomic.cache_line) = 0,
        read_index: std.atomic.Value(usize) align(std.atomic.cache_line) = .init(0),
        cached_read_index: usize align(std.atomic.cache_line) = 0,

        pub fn push(self: *@This(), item: T) void {
            const write = self.write_index.load(.unordered);
            const next_write = (write + 1) % capacity;
            while (next_write == self.cached_read_index)
                self.cached_read_index = self.read_index.load(.acquire);
            self.data[write] = item;
            self.write_index.store(next_write, .release);
        }

        pub fn pop(self: *@This()) ?T {
            const current_read = self.read_index.load(.unordered);
            if (current_read == self.cached_write_index) {
                self.cached_write_index = self.write_index.load(.acquire);
                if (current_read == self.cached_write_index) return null;
            }
            const value = self.data[current_read];
            self.read_index.store((current_read + 1) % capacity, .release);
            return value;
        }
    };
}

pub fn mapReverseIterator(comptime K: type, comptime V: type, map: std.AutoArrayHashMapUnmanaged(K, V)) MapReverseIterator(K, V) {
    const slice = map.entries.slice();
    return .{
        .keys = slice.items(.key).ptr,
        .values = slice.items(.value).ptr,
        .index = slice.len,
    };
}
fn MapReverseIterator(comptime K: type, comptime V: type) type {
    return struct {
        keys: [*]K,
        values: [*]V,
        index: usize = 0,

        pub fn next(iter: *@This()) ?struct {
            key_ptr: *K,
            value_ptr: *V,
        } {
            if (iter.index == 0) return null;
            iter.index -%= 1;
            return .{
                .key_ptr = &iter.keys[iter.index],
                .value_ptr = if (@sizeOf(*V) == 0) undefined else &iter.values[iter.index],
            };
        }
    };
}

pub const ConditionEnum = enum {
    weak,
    slowed,
    sick,
    speedy,
    bleeding,
    healing,
    damaging,
    invulnerable,
    armored,
    armor_broken,
    hidden,
    targeted,
    invisible,
    paralyzed,
    stunned,
    silenced,
    encased_in_stone,

    pub fn toString(self: ConditionEnum) []const u8 {
        return switch (self) {
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
            .paralyzed => "Paralyzed",
            .stunned => "Stunned",
            .silenced => "Silenced",
            .encased_in_stone => "Encased in Stone",
        };
    }
};

pub const Condition = packed struct(u32) {
    comptime {
        const struct_fields = @typeInfo(Condition).@"struct".fields;
        const enum_fields = @typeInfo(ConditionEnum).@"enum".fields;
        if (struct_fields.len - 1 != enum_fields.len)
            @compileError("utils.Condition and utils.ConditionEnum's field lengths don't match");

        for (struct_fields[0..enum_fields.len], enum_fields) |struct_field, enum_field| {
            if (!std.mem.eql(u8, struct_field.name, enum_field.name))
                @compileError("utils.Condition and utils.ConditionEnum have differing field names: utils.Condition=" ++
                    struct_field.name ++ ", utils.ConditionEnum=" ++ enum_field.name);
        }
    }

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
    paralyzed: bool = false,
    stunned: bool = false,
    silenced: bool = false,
    encased_in_stone: bool = false,
    padding: u15 = 0,

    pub fn isDefault(self: Condition) bool {
        return self == .{};
    }

    pub fn eql(self: Condition, other: Condition) bool {
        const cond_int = @typeInfo(Condition).@"struct".backing_integer.?;
        return @as(cond_int, @bitCast(self)) == @as(cond_int, @bitCast(other));
    }

    pub fn fromCondSlice(slice: ?[]const game_data.TimedCondition) Condition {
        if (slice) |s| {
            var ret: Condition = .{};
            for (s) |cond| ret.set(cond.type, true);
            return ret;
        } else return .{};
    }

    pub fn set(self: *Condition, cond: ConditionEnum, value: bool) void {
        switch (cond) {
            inline else => |tag| @field(self, @tagName(tag)) = value,
        }
    }

    pub fn get(self: *Condition, cond: ConditionEnum) bool {
        return switch (cond) {
            inline else => |tag| @field(self, @tagName(tag)),
        };
    }

    pub fn toggle(self: *Condition, cond: ConditionEnum) void {
        switch (cond) {
            inline else => |tag| @field(self, @tagName(tag)) = !@field(self, @tagName(tag)),
        }
    }
};

pub const RGBA = extern struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 0,

    pub fn fromColor(rgb: u24, alpha: f32) RGBA {
        return .{
            .r = @intCast((rgb >> 16) & 255),
            .g = @intCast((rgb >> 8) & 255),
            .b = @intCast(rgb & 255),
            .a = u8f(std.math.maxInt(u8) * alpha),
        };
    }

    pub fn toColor(self: RGBA) u24 {
        return @as(u24, @intCast(self.r)) << 16 |
            @as(u24, @intCast(self.g)) << 8 |
            @as(u24, @intCast(self.b));
    }
};

pub var rng: std.Random.DefaultPrng = .init(0);

var last_memory_access: i64 = -1;
var last_memory_value: f32 = -1.0;

pub fn typeId(comptime T: type) u32 {
    return @intFromError(@field(anyerror, @typeName(T)));
}

pub fn currentMemoryUse(time: i64) !f32 {
    if (time - last_memory_access < 5 * std.time.us_per_s) return last_memory_value;

    var memory_value: f32 = -1.0;
    switch (builtin.os.tag) {
        .windows => {
            const mem_info = try std.os.windows.GetProcessMemoryInfo(std.os.windows.self_process_handle);
            memory_value = f32i(mem_info.WorkingSetSize) / 1024.0 / 1024.0;
        },
        .linux => {
            const file = try std.fs.cwd().openFile("/proc/self/statm", .{});
            defer file.close();

            var buf: [1024]u8 = undefined;
            const size = try file.readAll(&buf);

            var split_iter = std.mem.splitScalar(u8, buf[0..size], ' ');
            _ = split_iter.next(); // total size
            const rss = f32i(try std.fmt.parseInt(u32, split_iter.next().?, 0));
            memory_value = rss / 1024.0;
        },
        else => memory_value = 0,
    }

    last_memory_access = time;
    last_memory_value = memory_value;
    return memory_value;
}

pub fn nextPowerOfTwo(value: u16) u16 {
    var mod_value = value - 1;
    mod_value |= mod_value >> 1;
    mod_value |= mod_value >> 2;
    mod_value |= mod_value >> 4;
    mod_value |= mod_value >> 8;
    return mod_value + 1;
}

pub fn plusMinus(range: f32) f32 {
    return rng.random().float(f32) * range * 2 - range;
}

pub fn isInBounds(x: f32, y: f32, bound_x: f32, bound_y: f32, bound_w: f32, bound_h: f32) bool {
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

pub fn hueToRgb(p: f32, q: f32, t: f32) f32 {
    var mod_t = t;
    if (mod_t < 0.0) mod_t += 1.0;
    if (mod_t > 1.0) mod_t -= 1.0;
    if (mod_t < 1.0 / 6.0) return p + (q - p) * 6.0 * mod_t;
    if (mod_t < 1.0 / 2.0) return q;
    if (mod_t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - mod_t) * 6.0;
    return p;
}

fn rgbRound(val: f32) u8 {
    return u8f(@min(@floor(val * 256), 255));
}

pub fn hslToRgb(h: f32, s: f32, l: f32) RGBA {
    if (s == 0) return .{
        .r = rgbRound(l),
        .g = rgbRound(l),
        .b = rgbRound(l),
        .a = 255,
    };

    const q = if (l < 0.5) l * (1.0 + s) else l + s - l * s;
    const p = 2.0 * l - q;
    return .{
        .r = rgbRound(hueToRgb(p, q, h + 1.0 / 3.0)),
        .g = rgbRound(hueToRgb(p, q, h)),
        .b = rgbRound(hueToRgb(p, q, h - 1.0 / 3.0)),
        .a = 255,
    };
}

pub fn strengthMult(str: i16, str_bonus: i16, cond: Condition) f32 {
    if (cond.weak) return 0.5;
    var mult = 0.5 + f32i(str + str_bonus) / 75.0;
    if (cond.damaging) mult *= 1.5;
    return mult;
}

pub fn witMult(wit: i16, wit_bonus: i16) f32 {
    return 0.5 + f32i(wit + wit_bonus) / 75.0;
}

pub fn redToGreen(perc: f32) RGBA {
    return hslToRgb(perc / 3.0, 1.0, 0.5);
}

pub inline fn f16i(i: anytype) f16 {
    return @floatFromInt(i);
}

pub inline fn f32i(i: anytype) f32 {
    return @floatFromInt(i);
}

pub inline fn f64i(i: anytype) f64 {
    return @floatFromInt(i);
}

pub inline fn i8f(f: anytype) i8 {
    return @intFromFloat(f);
}

pub inline fn u8f(f: anytype) u8 {
    return @intFromFloat(f);
}

pub inline fn i16f(f: anytype) i16 {
    return @intFromFloat(f);
}

pub inline fn u16f(f: anytype) u16 {
    return @intFromFloat(f);
}

pub inline fn i32f(f: anytype) i32 {
    return @intFromFloat(f);
}

pub inline fn u32f(f: anytype) u32 {
    return @intFromFloat(f);
}

pub inline fn i64f(f: anytype) i64 {
    return @intFromFloat(f);
}

pub inline fn u64f(f: anytype) u64 {
    return @intFromFloat(f);
}

pub inline fn isizef(f: anytype) isize {
    return @intFromFloat(f);
}

pub inline fn usizef(f: anytype) usize {
    return @intFromFloat(f);
}
