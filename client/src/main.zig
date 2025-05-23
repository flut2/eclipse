const std = @import("std");
const builtin = @import("builtin");

const build_options = @import("options");
const glfw = @import("glfw");
const gpu = @import("zgpu");
const rpc = @import("rpc");
const shared = @import("shared");
const network_data = shared.network_data;
const game_data = shared.game_data;
const utils = shared.utils;
const uv = shared.uv;
const f32i = utils.f32i;
const u32f = utils.u32f;
const vk = @import("vulkan");
const zaudio = @import("zaudio");
const ziggy = @import("ziggy");
const zstbi = @import("zstbi");

const assets = @import("assets.zig");
const Camera = @import("Camera.zig");
const map = @import("game/map.zig");
const GameServer = @import("GameServer.zig");
const input = @import("input.zig");
const LoginServer = @import("LoginServer.zig");
const Renderer = @import("render/Renderer.zig");
const Settings = @import("Settings.zig");
const dialog = @import("ui/dialogs/dialog.zig");
const element = @import("ui/elements/element.zig");
const ui_systems = @import("ui/systems.zig");

pub const frames_in_flight = 2;

/// Data must have pointer stability and must be deallocated manually, usually in the callback (for type information)
pub const TimedCallback = struct { trigger_on: i64, callback: *const fn (*anyopaque) void, data: *anyopaque };

const tracy = if (build_options.enable_tracy) @import("tracy") else {};
const AccountData = struct {
    email: []const u8,
    token: u128,

    pub fn load() !AccountData {
        const file = try std.fs.cwd().openFile("login_data_do_not_share.ziggy", .{});
        defer file.close();

        const file_data = try file.readToEndAllocOptions(account_arena_allocator, std.math.maxInt(u32), null, .fromByteUnits(@alignOf(u8)), 0);
        defer account_arena_allocator.free(file_data);

        return try ziggy.parseLeaky(AccountData, account_arena_allocator, file_data, .{});
    }

    pub fn save(self: AccountData) !void {
        const file = try std.fs.cwd().createFile("login_data_do_not_share.ziggy", .{});
        defer file.close();

        try ziggy.stringify(self, .{ .whitespace = .space_4 }, file.writer());
    }
};

pub export var NvOptimusEnablement: c_int = 1;
pub export var AmdPowerXpressRequestHighPerformance: c_int = 1;

pub var account_arena_allocator: std.mem.Allocator = undefined;
pub var current_account: ?AccountData = null;
pub var character_list: ?network_data.CharacterListData = null;
pub var current_time: i64 = 0;
pub var render_thread: std.Thread = undefined;
pub var skip_verify_loop = false;
pub var tick_frame = false;
pub var tick_render = true;
pub var needs_map_bg = false;
pub var need_minimap_update = false;
pub var need_force_update = false;
pub var need_swap_chain_update = false;
pub var minimap_update: struct {
    min_x: u32 = std.math.maxInt(u32),
    max_x: u32 = std.math.minInt(u32),
    min_y: u32 = std.math.maxInt(u32),
    max_y: u32 = std.math.minInt(u32),
} = .{};
pub var allocator: std.mem.Allocator = undefined;
pub var start_time: i64 = 0;
pub var game_server: GameServer = undefined;
pub var login_server: LoginServer = undefined;
pub var camera: Camera = .{};
pub var settings: Settings = .{};
pub var main_loop: *uv.uv_loop_t = undefined;
pub var window: *glfw.Window = undefined;
pub var rpc_client: *rpc = undefined;
pub var rpc_start: u64 = 0;
pub var callbacks: std.ArrayListUnmanaged(TimedCallback) = .empty;

fn onResize(_: *glfw.Window, w: i32, h: i32) callconv(.C) void {
    const float_w = f32i(w);
    const float_h = f32i(h);

    camera.width = float_w;
    camera.height = float_h;
    camera.clip_scale[0] = 2.0 / float_w;
    camera.clip_scale[1] = 2.0 / float_h;
    camera.clip_offset[0] = -float_w / 2.0;
    camera.clip_offset[1] = -float_h / 2.0;

    ui_systems.resize(float_w, float_h);

    need_swap_chain_update = true;
}

fn updateCharIdSort(selected_char_id: u32) void {
    const char_list = character_list orelse return;
    var char_list_ids: std.ArrayListUnmanaged(u32) = .empty;
    for (char_list.characters) |char_data| char_list_ids.append(allocator, char_data.char_id) catch oomPanic();
    var new_list: std.ArrayListUnmanaged(u32) = .empty;
    new_list.append(allocator, selected_char_id) catch oomPanic();
    for (settings.char_ids_login_sort) |char_id|
        if (std.mem.indexOfScalar(u32, new_list.items, char_id) == null and
            std.mem.indexOfScalar(u32, char_list_ids.items, char_id) != null)
            new_list.append(allocator, char_id) catch oomPanic();
    for (char_list_ids.items) |char_id|
        if (std.mem.indexOfScalar(u32, new_list.items, char_id) == null)
            new_list.append(allocator, char_id) catch oomPanic();
    if (Settings.needs_char_id_dispose) allocator.free(settings.char_ids_login_sort);
    settings.char_ids_login_sort = new_list.toOwnedSlice(allocator) catch oomPanic();
    Settings.needs_char_id_dispose = true;
    char_list_ids.deinit(allocator);
}

// lock ui_systems.ui_lock before calling (UI already does this implicitly)
pub fn enterGame(selected_server: network_data.ServerData, char_id: u32, class_data_id: u16) void {
    if (current_account == null) return;

    game_server.hello_data = .{ .hello = .{
        .build_ver = build_options.version,
        .email = current_account.?.email,
        .token = current_account.?.token,
        .char_id = @intCast(char_id),
        .class_id = class_data_id,
    } };

    updateCharIdSort(char_id);

    game_server.connect(selected_server.ip, selected_server.port) catch |e| {
        std.log.err("Connection failed: {}", .{e});
        return;
    };
}

pub fn enterTest(selected_server: network_data.ServerData, char_id: u32, test_map: []u8) void {
    if (current_account == null) return;

    const fragment_size = 50000;
    const fragments = test_map.len / 50000 + 1;
    if (fragments == 1) {
        game_server.hello_data = .{ .map_hello = .{
            .build_ver = build_options.version,
            .email = current_account.?.email,
            .token = current_account.?.token,
            .char_id = char_id,
            .map_fragment = test_map,
        } };
    } else {
        var fragment_list: std.ArrayListUnmanaged(network_data.C2SPacket) = .empty;
        for (0..fragments) |i| {
            const map_slice = test_map[fragment_size * i .. @min(test_map.len, fragment_size * (i + 1))];
            if (i == fragments - 1) {
                game_server.hello_data = .{ .map_hello = .{
                    .build_ver = build_options.version,
                    .email = current_account.?.email,
                    .token = current_account.?.token,
                    .char_id = char_id,
                    .map_fragment = map_slice,
                } };
            } else fragment_list.append(allocator, .{ .map_hello_fragment = .{
                .map_fragment = map_slice,
            } }) catch oomPanic();
        }
        if (fragment_list.items.len > 0) {
            game_server.map_hello_fragments = fragment_list.toOwnedSlice(allocator) catch oomPanic();
        } else fragment_list.deinit(allocator);
    }

    updateCharIdSort(char_id);

    game_server.connect(selected_server.ip, selected_server.port) catch |e| {
        std.log.err("Connection failed: {}", .{e});
        return;
    };
}

fn renderTick(renderer: *Renderer) !void {
    if (build_options.enable_tracy) tracy.SetThreadName("Render");

    var last_vsync = settings.enable_vsync;
    var fps_time_start: i64 = 0;
    var frames: u32 = 0;
    while (tick_render) : (std.atomic.spinLoopHint()) {
        if (need_swap_chain_update or last_vsync != settings.enable_vsync) {
            const extent: vk.Extent2D = .{ .width = u32f(camera.width), .height = u32f(camera.height) };
            try renderer.context.device.queueWaitIdle(renderer.context.graphics_queue.handle);
            try renderer.swapchain.recreate(renderer.context, extent, if (settings.enable_vsync) .fifo_khr else .immediate_khr);
            renderer.destroyFrameAndCmdBuffers();
            try renderer.createFrameAndCmdBuffers();
            last_vsync = settings.enable_vsync;
            need_swap_chain_update = false;
        }

        if (try renderer.draw()) frames += 1;

        if (current_time - fps_time_start > 1 * std.time.us_per_s) {
            map.frames.store(frames, .release);
            frames = 0;
            fps_time_start = current_time;
        }

        minimapUpdate: {
            if (!tick_frame or ui_systems.screen == .editor) break :minimapUpdate;

            if (need_minimap_update) {
                const min_x = @min(map.minimap.width, minimap_update.min_x);
                const max_x = @max(map.minimap.width, minimap_update.max_x + 1);
                const min_y = @min(map.minimap.height, minimap_update.min_y);
                const max_y = @max(map.minimap.height, minimap_update.max_y + 1);

                const w = max_x - min_x;
                const h = max_y - min_y;
                if (w <= 0 or h <= 0) break :minimapUpdate;

                const comp_len = map.minimap.num_components * map.minimap.bytes_per_component;

                for (min_y..max_y, 0..) |y, i| {
                    const base_map_idx = y * map.minimap.width * comp_len + min_x * comp_len;
                    @memcpy(
                        map.minimap_copy[i * w * comp_len .. (i + 1) * w * comp_len],
                        map.minimap.data[base_map_idx .. base_map_idx + w * comp_len],
                    );
                }

                try Renderer.updateTexture(
                    renderer.context,
                    renderer.cmd_pool,
                    renderer.vk_allocator,
                    renderer.minimap,
                    map.minimap_copy[0 .. w * h * comp_len],
                    w,
                    h,
                    @intCast(min_x),
                    @intCast(min_y),
                );

                need_minimap_update = false;
                minimap_update = .{};
            } else if (need_force_update) {
                try Renderer.updateTexture(
                    renderer.context,
                    renderer.cmd_pool,
                    renderer.vk_allocator,
                    renderer.minimap,
                    map.minimap.data,
                    map.minimap.width,
                    map.minimap.height,
                    0,
                    0,
                );
                need_force_update = false;
            }
        }
    }
}

fn gameTick(idler: [*c]uv.uv_idle_t) callconv(.C) void {
    const renderer: *Renderer = @ptrCast(@alignCast(idler.*.data));
    if (window.shouldClose()) {
        @branchHint(.unlikely);
        uv.uv_stop(@ptrCast(main_loop));
        return;
    }

    glfw.pollEvents();

    const time = std.time.microTimestamp() - start_time;
    const dt = f32i(time - current_time);
    current_time = time;

    ui_systems.update(time, dt) catch |e| {
        std.log.err("Error while updating UI: {}", .{e});
        if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace.*);
    };
    if (tick_frame or needs_map_bg) map.update(renderer, time, dt);

    const cb_len = callbacks.items.len;
    if (cb_len > 0) {
        var iter = std.mem.reverseIterator(callbacks.items);
        var i = cb_len - 1;
        while (iter.next()) |timed_cb| : (i -%= 1)
            if (timed_cb.trigger_on <= time) {
                timed_cb.callback(timed_cb.data);
                _ = callbacks.swapRemove(i);
            };
    }
}

pub fn disconnect() void {
    map.dispose();
    input.reset();
    if (ui_systems.is_testing) {
        ui_systems.switchScreen(.editor);
        ui_systems.is_testing = false;
    } else {
        if (character_list == null)
            ui_systems.switchScreen(.main_menu)
        else
            ui_systems.switchScreen(.char_select);
    }
}

pub fn oomPanic() noreturn {
    @panic("Out of memory");
}

pub fn audioFailure() void {
    settings.sfx_volume = 0.0;
    settings.music_volume = 0.0;
    dialog.showDialog(.text, .{ .title = "Audio Error", .body = 
        \\There was a problem interacting with your audio device. 
        \\Audio has been turned off, but you can turn it back on in the Options if you believe this to be incorrect or temporary.
    });
}

fn uvMalloc(len: usize) callconv(.C) ?*anyopaque {
    const result = std.c.malloc(len);
    if (result) |addr| {
        tracy.Alloc(addr, len);
    } else {
        var buffer: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buffer, "Alloc failed, requesting {d} bytes", .{len}) catch return result;
        tracy.Message(msg);
    }
    return result;
}

fn uvCalloc(len: usize, elem_size: usize) callconv(.C) ?*anyopaque {
    const result = std.c.malloc(len * elem_size);
    if (result) |addr| {
        @memset(@as([*]u8, @ptrCast(@alignCast(result)))[0 .. len * elem_size], 0);
        tracy.Alloc(addr, len * elem_size);
    } else {
        var buffer: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buffer, "Calloc failed, requesting {d} bytes", .{len * elem_size}) catch return result;
        tracy.Message(msg);
    }
    return result;
}

fn uvResize(ptr: ?*anyopaque, new_len: usize) callconv(.C) ?*anyopaque {
    const result = std.c.realloc(ptr, new_len);
    if (result != null) {
        tracy.Free(ptr);
        tracy.Alloc(ptr, new_len);
    } else {
        var buffer: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buffer, "Resize failed, requesting {d} bytes", .{new_len}) catch return result;
        tracy.Message(msg);
    }
    return result;
}

fn uvFree(ptr: ?*anyopaque) callconv(.C) void {
    std.c.free(ptr);
    tracy.Free(ptr);
}

pub fn main() !void {
    if (build_options.enable_tracy) tracy.SetThreadName("Main");

    start_time = std.time.microTimestamp();
    utils.rng.seed(@intCast(start_time));

    const use_gpa = build_options.enable_gpa;
    var gpa = if (use_gpa) std.heap.DebugAllocator(.{ .stack_trace_frames = 10 }).init else {};
    defer _ = if (use_gpa) gpa.deinit();

    allocator = if (use_gpa)
        gpa.allocator()
    else
        std.heap.smp_allocator;
    // allocator = if (build_options.enable_tracy) blk: {
    //     var tracy_alloc: tracy.TracyAllocator = .init(child_allocator);
    //     break :blk tracy_alloc.allocator();
    // } else child_allocator;

    if (build_options.enable_tracy) {
        const replace_alloc_status = uv.uv_replace_allocator(uvMalloc, uvResize, uvCalloc, uvFree);
        if (replace_alloc_status != 0) {
            std.log.err("Libuv alloc replace error: {s}", .{uv.uv_strerror(replace_alloc_status)});
            return error.ReplaceAllocFailed;
        }
    }

    var account_arena: std.heap.ArenaAllocator = .init(allocator);
    account_arena_allocator = account_arena.allocator();
    defer account_arena.deinit();

    current_account = AccountData.load() catch null;
    defer if (settings.remember_login) if (current_account) |acc| acc.save() catch {};

    rpc_client = try rpc.init(allocator, &ready);
    defer rpc_client.deinit();

    try glfw.init();
    defer glfw.terminate();

    if (!glfw.isVulkanSupported()) {
        std.log.err("GLFW could not find libvulkan", .{});
        return error.NoVulkan;
    }

    zstbi.init(allocator);
    defer zstbi.deinit();

    zaudio.init(allocator);
    defer zaudio.deinit();

    settings = try .init(allocator);
    defer settings.deinit();

    try assets.init();
    defer assets.deinit();

    try game_data.init(allocator);
    defer game_data.deinit();

    try map.init();
    defer map.deinit();

    try ui_systems.init();
    defer ui_systems.deinit();

    defer input.deinit();

    glfw.windowHintTyped(.client_api, .no_api);
    window = try glfw.Window.create(1280, 720, "Eclipse", null);
    defer window.destroy();

    window.setSizeLimits(1280, 720, -1, -1);
    window.setCursor(switch (settings.cursor_type) {
        .basic => assets.default_cursor,
        .royal => assets.royal_cursor,
        .ranger => assets.ranger_cursor,
        .aztec => assets.aztec_cursor,
        .fiery => assets.fiery_cursor,
        .target_enemy => assets.target_enemy_cursor,
        .target_ally => assets.target_ally_cursor,
    });

    _ = window.setKeyCallback(input.keyEvent);
    _ = window.setCharCallback(input.charEvent);
    _ = window.setCursorPosCallback(input.mouseMoveEvent);
    _ = window.setMouseButtonCallback(input.mouseEvent);
    _ = window.setScrollCallback(input.scrollEvent);
    _ = window.setFramebufferSizeCallback(onResize);

    var renderer: Renderer = try .create(if (settings.enable_vsync) .fifo_khr else .immediate_khr);
    defer renderer.destroy() catch |e| {
        std.log.err("Error while destroying renderer: {}", .{e});
        if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace.*);
    };

    var rpc_thread: std.Thread = try .spawn(.{ .allocator = allocator }, runRpc, .{rpc_client});
    defer {
        rpc_client.stop();
        rpc_thread.join();
    }

    render_thread = try .spawn(.{ .allocator = allocator }, renderTick, .{&renderer});
    defer {
        tick_render = false;
        render_thread.join();
    }

    main_loop = try allocator.create(uv.uv_loop_t);
    const loop_status = uv.uv_loop_init(@ptrCast(main_loop));
    if (loop_status != 0) {
        std.log.err("Loop creation error: {s}", .{uv.uv_strerror(loop_status)});
        return error.NoLoop;
    }
    defer allocator.destroy(main_loop);

    login_server.needs_verify = true;

    try game_server.init();
    defer game_server.deinit();

    try login_server.init();
    defer login_server.deinit();

    var idler: uv.uv_idle_t = undefined;
    idler.data = &renderer;
    const idle_init_status = uv.uv_idle_init(@ptrCast(main_loop), &idler);
    if (idle_init_status != 0) {
        std.log.err("Idle creation error: {s}", .{uv.uv_strerror(loop_status)});
        return error.NoIdle;
    }

    const idle_start_status = uv.uv_idle_start(&idler, gameTick);
    if (idle_start_status != 0) {
        std.log.err("Idle start error: {s}", .{uv.uv_strerror(loop_status)});
        return error.IdleStartFailed;
    }

    const run_status = uv.uv_run(@ptrCast(main_loop), uv.UV_RUN_DEFAULT);
    if (run_status != 0 and run_status != 1) {
        std.log.err("Run error: {s}", .{uv.uv_strerror(run_status)});
        return error.RunFailed;
    }
}

fn ready(cli: *rpc) !void {
    rpc_start = @intCast(std.time.timestamp());
    try cli.setPresence(.{
        .assets = .{
            .large_image = .create("logo"),
            .large_text = .create("Alpha v" ++ build_options.version),
        },
        .timestamps = .{ .start = rpc_start },
    });
}

fn runRpc(cli: *rpc) void {
    if (build_options.enable_tracy) tracy.SetThreadName("RPC");

    cli.run(.{ .client_id = "1356002897095295047" }) catch |e| {
        std.log.err("Setting up RPC failed: {}", .{e});
    };
}
