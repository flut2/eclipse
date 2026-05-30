const std = @import("std");
const builtin = @import("builtin");

const game_data = @import("game_data.zig");

pub const PacketWriter = struct {
    list: std.ArrayList(u8) = .empty,

    pub fn init(self: *PacketWriter, allocator: std.mem.Allocator, size: usize) std.mem.Allocator.Error!void {
        self.list = try .initCapacity(allocator, size);
    }

    pub fn deinit(self: *PacketWriter, allocator: std.mem.Allocator) void {
        self.list.deinit(allocator);
    }

    pub fn writeLength(self: *PacketWriter) void {
        self.list.appendSliceAssumeCapacity(&.{ 0, 0, 0, 0 });
    }

    pub fn updateLength(self: *PacketWriter) void {
        const buf = self.list.items[0..4];
        const len: u32 = @intCast(self.list.items.len - 4);
        @memcpy(buf, std.mem.asBytes(&len));
    }

    pub fn write(self: *PacketWriter, value: anytype) void {
        const T = @TypeOf(value);
        const type_info = @typeInfo(T);

        switch (type_info) {
            .pointer => |p| {
                self.write(@as(u16, @intCast(value.len)));
                if (@alignOf(p.child) == 1) {
                    self.list.appendSliceAssumeCapacity(@ptrCast(value));
                    return;
                }
                for (value) |val| self.write(val);
                return;
            },
            .@"struct" => |s| switch (s.layout) {
                .auto => {
                    inline for (s.fields) |field| self.write(@field(value, field.name));
                    return;
                },
                .@"extern", .@"packed" => {},
            },
            else => {},
        }

        self.list.appendSliceAssumeCapacity(std.mem.asBytes(&value));
    }
};

pub const PacketReader = struct {
    index: u32 = 0,
    buffer: []u8 = &.{},
    fba: std.heap.FixedBufferAllocator = .{ .buffer = &.{}, .end_index = 0 },

    pub fn init(self: *PacketReader, allocator: std.mem.Allocator, size: usize) std.mem.Allocator.Error!void {
        self.buffer = try allocator.alloc(u8, size);
        self.fba = .init(try allocator.alloc(u8, size));
    }

    pub fn deinit(self: *PacketReader, allocator: std.mem.Allocator) void {
        allocator.free(self.buffer);
        allocator.free(self.fba.buffer);
    }

    pub fn reset(self: *PacketReader) void {
        self.index = 0;
        self.fba.reset();
    }

    pub fn read(self: *PacketReader, comptime T: type) T {
        const type_info = @typeInfo(T);
        switch (type_info) {
            .pointer => |p| {
                const len = self.read(u16);
                if (len == 0) return &.{};
                if (@alignOf(p.child) == 1) {
                    const byte_len = len * @sizeOf(p.child);
                    if (self.index + byte_len > self.buffer.len) @panic("Buffer attempted to read out of bounds");
                    defer self.index += byte_len;
                    return @ptrCast(self.buffer[self.index..][0..byte_len]);
                }
                const ret = self.fba.allocator().alloc(p.child, len) catch @panic("FBA buffer out of space");
                for (ret) |*r| r.* = self.read(p.child);
                return ret;
            },
            .@"struct" => |s| switch (s.layout) {
                .auto => {
                    var value: T = undefined;
                    inline for (type_info.@"struct".fields) |field| @field(value, field.name) = self.read(field.type);
                    return value;
                },
                .@"extern", .@"packed" => {},
            },
            else => {},
        }

        const len = @sizeOf(T);
        if (self.index + len > self.buffer.len) @panic("Buffer attempted to read out of bounds");
        defer self.index += len;
        return std.mem.bytesToValue(T, self.buffer[self.index..][0..len]);
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

        pub fn push(self: *@This(), item: T) bool {
            const write = self.write_index.load(.unordered);
            const next_write = (write + 1) % capacity;
            if (next_write == self.cached_read_index) {
                self.cached_read_index = self.read_index.load(.acquire);
                if (next_write == self.cached_read_index) return false;
            }
            self.data[write] = item;
            self.write_index.store(next_write, .release);
            return true;
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

pub fn currentMemoryUse(io: std.Io, time: i64) !f32 {
    if (time - last_memory_access < 5 * std.time.us_per_s) return last_memory_value;

    var memory_value: f32 = -1.0;
    switch (builtin.os.tag) {
        .windows => {
            const Psapi = struct {
                const DWORD = std.os.windows.DWORD;
                const HANDLE = std.os.windows.HANDLE;
                const BOOL = std.os.windows.BOOL;

                const PROCESS_MEMORY_COUNTERS_EX = extern struct {
                    cb: DWORD,
                    PageFaultCount: DWORD,
                    PeakWorkingSetSize: usize,
                    WorkingSetSize: usize,
                    QuotaPeakPagedPoolUsage: usize,
                    QuotaPagedPoolUsage: usize,
                    QuotaPeakNonPagedPoolUsage: usize,
                    QuotaNonPagedPoolUsage: usize,
                    PagefileUsage: usize,
                    PeakPagefileUsage: usize,
                    PrivateUsage: usize,
                };

                extern "psapi" fn GetProcessMemoryInfo(
                    Process: HANDLE,
                    ppsmemCounters: *PROCESS_MEMORY_COUNTERS_EX,
                    cb: DWORD,
                ) callconv(.winapi) BOOL;
            };

            var ct: Psapi.PROCESS_MEMORY_COUNTERS_EX = std.mem.zeroes(Psapi.PROCESS_MEMORY_COUNTERS_EX);
            ct.cb = @intCast(@sizeOf(Psapi.PROCESS_MEMORY_COUNTERS_EX));

            if (Psapi.GetProcessMemoryInfo(std.os.windows.GetCurrentProcess(), &ct, ct.cb) == .FALSE)
                return error.MemoryInfo;

            memory_value = f32i(ct.WorkingSetSize) / (1024.0 * 1024.0);
        },
        .linux => {
            const file = try std.Io.Dir.cwd().openFile(io, "/proc/self/statm", .{});
            defer file.close(io);

            var buf: [256]u8 = undefined;
            var rdr = file.reader(io, &buf);

            var text_buf: [1024]u8 = undefined;
            const size = try rdr.interface.readSliceShort(&text_buf);
            if (size == 0) {
                last_memory_access = time;
                last_memory_value = 0;
                return 0;
            }

            var split_iter = std.mem.splitScalar(u8, text_buf[0..size], ' ');
            _ = split_iter.next(); // total size
            const rss = f32i(try std.fmt.parseInt(
                u32,
                split_iter.next() orelse return error.RssMissing,
                0,
            ));
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
    return @mulAdd(f32, x_dt, x_dt, y_dt * y_dt);
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
