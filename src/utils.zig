const std = @import("std");
const main = @import("main.zig");
const builtin = @import("builtin");
const game_data = @import("game_data.zig");

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
        const len = self.index - self.length_index;
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
                        const byte_size = (@bitSizeOf(field.type) + 7) / 8;
                        const buf = self.buffer[self.index .. self.index + byte_size];
                        self.index += byte_size;
                        @memcpy(buf, @field(value, field.name));
                    }
                    return value;
                },
                .Packed => {}, // will be handled below, packed structs are just ints
            }
        }

        const byte_size = (@bitSizeOf(T) + 7) / 8;
        const buf = self.buffer[self.index .. self.index + byte_size];
        self.index += byte_size;
        @memcpy(buf, std.mem.asBytes(&value));
    }
};

// Big endian isn't supported on this
pub const PacketReader = struct {
    index: u16 = 0,
    buffer: []u8 = undefined,

    pub fn read(self: *PacketReader, comptime T: type) T {
        const type_info = @typeInfo(T);
        if (type_info == .Pointer or type_info == .Array) {
            @compileError("PacketReader.read() does not support slices or arrays. Use PacketReader.readArray() instead");
        }

        if (type_info == .Struct) {
            switch (type_info.Struct.layout) {
                .Auto, .Extern => {
                    var value: T = undefined;
                    inline for (type_info.Struct.fields) |field| {
                        const byte_size = (@bitSizeOf(field.type) + 7) / 8;
                        const buf = self.buffer[self.index .. self.index + byte_size];
                        self.index += byte_size;
                        @field(value, field.name) = std.mem.bytesToValue(field.type, buf[0..byte_size]);
                    }
                    return value;
                },
                .Packed => {}, // will be handled below, packed structs are just ints
            }
        }

        const byte_size = (@bitSizeOf(T) + 7) / 8;
        var buf = self.buffer[self.index .. self.index + byte_size];
        self.index += byte_size;
        return std.mem.bytesToValue(T, buf[0..byte_size]);
    }

    pub fn readArray(self: *PacketReader, comptime T: type) []align(1) T {
        const byte_size = (@bitSizeOf(T) + 7) / 8 * self.read(u16);
        const buf = self.buffer[self.index .. self.index + byte_size];
        self.index += byte_size;
        return std.mem.bytesAsSlice(T, buf);
    }
};

pub const ConditionEnum = enum(u8) {
    unknown = 0,
    dead = 1,
    quiet = 2,
    weak = 3,
    slowed = 4,
    sick = 5,
    dazed = 6,
    stunned = 7,
    blind = 8,
    hallucinating = 9,
    drunk = 10,
    confused = 11,
    stun_immune = 12,
    invisible = 13,
    paralyzed = 14,
    speedy = 15,
    bleeding = 16,
    not_used = 17,
    healing = 18,
    damaging = 19,
    berserk = 20,
    paused = 21,
    stasis = 22,
    stasis_immune = 23,
    invincible = 24,
    invulnerable = 25,
    armored = 26,
    armor_broken = 27,
    hexed = 28,
    ninja_speedy = 29,

    const map = std.ComptimeStringMap(ConditionEnum, .{
        .{ "Unknown", .unknown },
        .{ "Dead", .dead },
        .{ "Quiet", .quiet },
        .{ "Weak", .weak },
        .{ "Slowed", .slowed },
        .{ "Sick", .sick },
        .{ "Dazed", .dazed },
        .{ "Stunned", .stunned },
        .{ "Blind", .blind },
        .{ "Hallucinating", .hallucinating },
        .{ "Drunk", .drunk },
        .{ "Confused", .confused },
        .{ "StunImmune", .stun_immune },
        .{ "Stun Immune", .stun_immune },
        .{ "Invisible", .invisible },
        .{ "Paralyzed", .paralyzed },
        .{ "Speedy", .speedy },
        .{ "Bleeding", .bleeding },
        .{ "Healing", .healing },
        .{ "Damaging", .damaging },
        .{ "Berserk", .berserk },
        .{ "Paused", .paused },
        .{ "Stasis", .stasis },
        .{ "StasisImmune", .stasis_immune },
        .{ "Stasis Immune", .stasis_immune },
        .{ "Invincible", .invincible },
        .{ "Invulnerable", .invulnerable },
        .{ "Armored", .armored },
        .{ "ArmorBroken", .armor_broken },
        .{ "Armor Broken", .armor_broken },
        .{ "Hexed", .hexed },
        .{ "NinjaSpeedy", .ninja_speedy },
        .{ "Ninja Speedy", .ninja_speedy },
    });

    pub fn fromString(str: []const u8) ConditionEnum {
        return map.get(str) orelse .unknown;
    }

    pub fn toString(self: ConditionEnum) []const u8 {
        return switch (self) {
            .dead => "Dead",
            .quiet => "Quiet",
            .weak => "Weak",
            .slowed => "Slowed",
            .sick => "Sick",
            .dazed => "Dazed",
            .stunned => "Stunned",
            .blind => "Blind",
            .hallucinating => "Hallucinating",
            .drunk => "Drunk",
            .confused => "Confused",
            .stun_immune => "Stun Immune",
            .invisible => "Invisible",
            .paralyzed => "Paralyzed",
            .speedy => "Speedy",
            .bleeding => "Bleeding",
            .healing => "Healing",
            .damaging => "Damaging",
            .berserk => "Berserk",
            .paused => "Paused",
            .stasis => "Stasis",
            .stasis_immune => "Stasis Immune",
            .invincible => "Invincible",
            .invulnerable => "Invulnerable",
            .armored => "Armored",
            .armor_broken => "Armor Broken",
            .hexed => "Hexed",
            .ninja_speedy => "Ninja Speedy",
            else => "",
        };
    }
};

pub const Condition = packed struct(u64) {
    dead: bool = false,
    quiet: bool = false,
    weak: bool = false,
    slowed: bool = false,
    sick: bool = false,
    dazed: bool = false,
    stunned: bool = false,
    blind: bool = false,
    hallucinating: bool = false,
    drunk: bool = false,
    confused: bool = false,
    stun_immune: bool = false,
    invisible: bool = false,
    paralyzed: bool = false,
    speedy: bool = false,
    bleeding: bool = false,
    not_used: bool = false,
    healing: bool = false,
    damaging: bool = false,
    berserk: bool = false,
    paused: bool = false,
    stasis: bool = false,
    stasis_immune: bool = false,
    invincible: bool = false,
    invulnerable: bool = false,
    armored: bool = false,
    armor_broken: bool = false,
    hexed: bool = false,
    ninja_speedy: bool = false,
    _padding: u35 = 0,

    pub inline fn fromCondSlice(slice: []game_data.ConditionEffect) Condition {
        var ret = Condition{};
        for (slice) |cond| {
            ret.set(cond.condition, true);
        }
        return ret;
    }

    pub fn set(self: *Condition, cond: ConditionEnum, value: bool) void {
        switch (cond) {
            .quiet => self.quiet = value,
            .weak => self.weak = value,
            .slowed => self.slowed = value,
            .sick => self.sick = value,
            .dazed => self.dazed = value,
            .stunned => self.stunned = value,
            .blind => self.blind = value,
            .hallucinating => self.hallucinating = value,
            .drunk => self.drunk = value,
            .confused => self.confused = value,
            .stun_immune => self.stun_immune = value,
            .invisible => self.invisible = value,
            .paralyzed => self.paralyzed = value,
            .speedy => self.speedy = value,
            .bleeding => self.bleeding = value,
            .healing => self.healing = value,
            .damaging => self.damaging = value,
            .berserk => self.berserk = value,
            .paused => self.paused = value,
            .stasis => self.stasis = value,
            .stasis_immune => self.stasis_immune = value,
            .invincible => self.invincible = value,
            .invulnerable => self.invulnerable = value,
            .armored => self.armored = value,
            .armor_broken => self.armor_broken = value,
            .hexed => self.hexed = value,
            .ninja_speedy => self.ninja_speedy = value,
            else => std.log.err("Invalid enum specified for condition set: {any}", .{@errorReturnTrace() orelse return}),
        }
    }

    pub fn toggle(self: *Condition, cond: ConditionEnum) void {
        switch (cond) {
            .quiet => self.quiet = !self.quiet,
            .weak => self.weak = !self.weak,
            .slowed => self.slowed = !self.slowed,
            .sick => self.sick = !self.sick,
            .dazed => self.dazed = !self.dazed,
            .stunned => self.stunned = !self.stunned,
            .blind => self.blind = !self.blind,
            .hallucinating => self.hallucinating = !self.hallucinating,
            .drunk => self.drunk = !self.drunk,
            .confused => self.confused = !self.confused,
            .stun_immune => self.stun_immune = !self.stun_immune,
            .invisible => self.invisible = !self.invisible,
            .paralyzed => self.paralyzed = !self.paralyzed,
            .speedy => self.speedy = !self.speedy,
            .bleeding => self.bleeding = !self.bleeding,
            .healing => self.healing = !self.healing,
            .damaging => self.damaging = !self.damaging,
            .berserk => self.berserk = !self.berserk,
            .paused => self.paused = !self.paused,
            .stasis => self.stasis = !self.stasis,
            .stasis_immune => self.stasis_immune = !self.stasis_immune,
            .invincible => self.invincible = !self.invincible,
            .invulnerable => self.invulnerable = !self.invulnerable,
            .armored => self.armored = !self.armored,
            .armor_broken => self.armor_broken = !self.armor_broken,
            .hexed => self.hexed = !self.hexed,
            .ninja_speedy => self.ninja_speedy = !self.ninja_speedy,
            else => std.log.err("Invalid enum specified for condition toggle: {any}", .{@errorReturnTrace() orelse return}),
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

pub const Random = struct {
    seed: u32 = 0,

    pub fn init(seed: u32) Random {
        return .{ .seed = seed };
    }

    pub fn setSeed(self: *Random, seed: u32) void {
        self.seed = seed;
    }

    pub fn nextIntRange(self: *Random, min: u32, max: u32) u32 {
        return if (min == max) min else min + (self.gen() % (max - min));
    }

    fn gen(self: *Random) u32 {
        var lo = 16807 * (self.seed & 0xFFFF);
        const hi = 16807 * (self.seed >> 16);

        lo += (hi & 0x7FFF) << 16;
        lo += hi >> 15;

        if (lo > 0x7FFFFFFF)
            lo -= 0x7FFFFFFF;

        self.seed = lo;
        return lo;
    }
};

pub const VM_COUNTERS_EX = extern struct {
    PeakVirtualSize: std.os.windows.SIZE_T,
    VirtualSize: std.os.windows.SIZE_T,
    PageFaultCount: std.os.windows.ULONG,
    PeakWorkingSetSize: std.os.windows.SIZE_T,
    WorkingSetSize: std.os.windows.SIZE_T,
    QuotaPeakPagedPoolUsage: std.os.windows.SIZE_T,
    QuotaPagedPoolUsage: std.os.windows.SIZE_T,
    QuotaPeakNonPagedPoolUsage: std.os.windows.SIZE_T,
    QuotaNonPagedPoolUsage: std.os.windows.SIZE_T,
    PagefileUsage: std.os.windows.SIZE_T,
    PeakPagefileUsage: std.os.windows.SIZE_T,
    PrivateUsage: std.os.windows.SIZE_T,
};

pub var rng = std.rand.DefaultPrng.init(0);

var last_memory_access: i64 = -1;
var last_memory_value: f32 = -1.0;

pub fn currentMemoryUse(allocator: std.mem.Allocator) !f32 {
    if (main.current_time - last_memory_access < 5000 * std.time.us_per_ms)
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

            const data = try file.readToEndAlloc(allocator, std.math.maxInt(u8));
            defer allocator.free(data);

            var split_iter = std.mem.split(u8, data, " ");
            _ = split_iter.next(); // total size
            const rss: f32 = @floatFromInt(try std.fmt.parseInt(u32, split_iter.next().?, 0));
            memory_value = rss / 1024.0;
        },
        else => memory_value = 0,
    }

    last_memory_access = main.current_time;
    last_memory_value = memory_value;
    return memory_value;
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
