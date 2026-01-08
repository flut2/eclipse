const std = @import("std");

var stbi_allocator: ?std.mem.Allocator = null;
var pointer_size_map: std.AutoHashMapUnmanaged(usize, usize) = .empty;
var alloc_mutex: std.Thread.Mutex = .{};
const alignment: std.mem.Alignment = .of(std.c.max_align_t);

fn allocatorMissing() noreturn {
    @panic("stbi: Allocator is missing, set it through `stbi.init()`");
}

fn outOfMemory() noreturn {
    @panic("stbi: Out of memory");
}

fn stbiMalloc(size: usize) callconv(.c) ?*anyopaque {
    const allocator = stbi_allocator orelse allocatorMissing();

    alloc_mutex.lock();
    defer alloc_mutex.unlock();

    const mem = allocator.alignedAlloc(u8, alignment, size) catch outOfMemory();
    pointer_size_map.put(allocator, @intFromPtr(mem.ptr), size) catch outOfMemory();
    return mem.ptr;
}

fn stbiRealloc(maybe_ptr: ?*anyopaque, new_size: usize) callconv(.c) ?*anyopaque {
    const allocator = stbi_allocator orelse allocatorMissing();

    alloc_mutex.lock();
    defer alloc_mutex.unlock();

    const old_size = if (maybe_ptr) |p| pointer_size_map.fetchRemove(@intFromPtr(p)).?.value else 0;
    const old_mem: [*]align(alignment.toByteUnits()) u8 = if (maybe_ptr) |p| @ptrCast(@alignCast(p)) else &.{};
    const new_mem = allocator.realloc(old_mem[0..old_size], new_size) catch outOfMemory();
    pointer_size_map.put(allocator, @intFromPtr(new_mem.ptr), new_size) catch outOfMemory();
    return new_mem.ptr;
}

fn stbiFree(maybe_ptr: ?*anyopaque) callconv(.c) void {
    const allocator = stbi_allocator orelse allocatorMissing();
    const ptr = maybe_ptr orelse return;

    alloc_mutex.lock();
    defer alloc_mutex.unlock();

    const kv = pointer_size_map.fetchRemove(@intFromPtr(ptr)) orelse {
        std.log.err("stbi: Invalid free attempted on {*}", .{ptr});
        return;
    };
    const mem: [*]align(alignment.toByteUnits()) u8 = @ptrCast(@alignCast(ptr));
    allocator.free(mem[0..kv.value]);
}

fn stbirMalloc(size: usize, _: ?*anyopaque) callconv(.c) ?*anyopaque {
    return stbiMalloc(size);
}

fn stbirFree(maybe_ptr: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
    stbiFree(maybe_ptr);
}

pub fn init(allocator: std.mem.Allocator) void {
    if (stbi_allocator != null)
        @panic("stbi: Library already initialized");
    stbi_allocator = allocator;

    mallocPtr = stbiMalloc;
    reallocPtr = stbiRealloc;
    freePtr = stbiFree;
}

pub fn deinit() void {
    const allocator = stbi_allocator orelse return;
    pointer_size_map.deinit(allocator);
    stbi_allocator = null;
}

pub const Image = struct {
    data: []u8,
    width: u32,
    height: u32,
    num_components: u32,
    bytes_per_component: u32,
    bytes_per_row: u32,

    pub const invalid: Image = .{
        .data = &.{},
        .width = std.math.maxInt(u32),
        .height = std.math.maxInt(u32),
        .num_components = std.math.maxInt(u32),
        .bytes_per_component = std.math.maxInt(u32),
        .bytes_per_row = std.math.maxInt(u32),
    };

    pub fn loadFromFile(path: [:0]const u8, forced_comps: u32) !Image {
        if (stbi_allocator == null) allocatorMissing();

        var x: i32 = 0;
        var y: i32 = 0;
        var c: i32 = 0;
        const data = stbi_load(path, &x, &y, &c, @intCast(forced_comps)) orelse {
            std.log.err("stbi: Loading image from path `{s}` failed", .{path});
            return error.ImageInitFailed;
        };

        const num_components: u32 = if (forced_comps == 0) @intCast(c) else forced_comps;
        const width: u32 = @intCast(x);
        const height: u32 = @intCast(y);
        const bytes_per_row = width * num_components;

        return .{
            .data = data[0 .. height * bytes_per_row],
            .width = width,
            .height = height,
            .num_components = num_components,
            .bytes_per_component = 1,
            .bytes_per_row = bytes_per_row,
        };
    }

    pub fn loadFromMemory(data: []const u8, forced_comps: u32) !Image {
        if (stbi_allocator == null) allocatorMissing();

        var x: i32 = 0;
        var y: i32 = 0;
        var c: i32 = 0;
        const image_data = stbi_load_from_memory(data.ptr, @intCast(data.len), &x, &y, &c, @intCast(forced_comps)) orelse {
            std.log.err("stbi: Loading image from data `{*}` failed", .{data.ptr});
            return error.ImageInitFailed;
        };

        const num_components: u32 = if (forced_comps == 0) @intCast(c) else forced_comps;
        const width: u32 = @intCast(x);
        const height: u32 = @intCast(y);
        const bytes_per_row = width * num_components;

        return .{
            .data = image_data[0 .. height * bytes_per_row],
            .width = width,
            .height = height,
            .num_components = num_components,
            .bytes_per_component = 1,
            .bytes_per_row = bytes_per_row,
        };
    }

    pub fn createEmpty(width: u32, height: u32, num_components: u32, opts: struct {
        bytes_per_component: u32 = 0,
        bytes_per_row: u32 = 0,
    }) !Image {
        if (stbi_allocator == null) allocatorMissing();

        const bytes_per_component = if (opts.bytes_per_component == 0) 1 else opts.bytes_per_component;
        const bytes_per_row = if (opts.bytes_per_row == 0)
            width * num_components * bytes_per_component
        else
            opts.bytes_per_row;

        const size = height * bytes_per_row;
        const data: [*]u8 = @ptrCast(stbiMalloc(size));
        const data_slice = data[0..size];
        @memset(data_slice, 0);

        return .{
            .data = data_slice,
            .width = width,
            .height = height,
            .num_components = num_components,
            .bytes_per_component = bytes_per_component,
            .bytes_per_row = bytes_per_row,
        };
    }

    pub fn deinit(image: *Image) void {
        stbi_image_free(image.data.ptr);
        image.* = undefined;
    }
};

extern var mallocPtr: ?*const fn (size: usize) callconv(.c) ?*anyopaque;
extern var reallocPtr: ?*const fn (ptr: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque;
extern var freePtr: ?*const fn (maybe_ptr: ?*anyopaque) callconv(.c) void;

extern fn stbi_load(
    filename: [*:0]const u8,
    x: *i32,
    y: *i32,
    channels_in_file: *i32,
    desired_channels: i32,
) ?[*]u8;

pub extern fn stbi_load_from_memory(
    buffer: [*]const u8,
    len: i32,
    x: *i32,
    y: *i32,
    channels_in_file: *i32,
    desired_channels: i32,
) ?[*]u8;

extern fn stbi_image_free(image_data: ?[*]u8) void;
