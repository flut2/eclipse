const std = @import("std");
const shared = @import("shared");
const network_data = shared.network_data;
const game_data = shared.game_data;
const utils = shared.utils;
const uv = shared.uv;
const assets = @import("assets.zig");
const builtin = @import("builtin");
const glfw = @import("zglfw");
const zstbi = @import("zstbi");
const input = @import("input.zig");
const map = @import("game/map.zig");
const element = @import("ui/elements/element.zig");
const render = @import("render.zig");
const tracy = if (build_options.enable_tracy) @import("tracy") else {};
const zaudio = @import("zaudio");
const ui_systems = @import("ui/systems.zig");
const dialog = @import("ui/dialogs/dialog.zig");
const rpmalloc = @import("rpmalloc").RPMalloc(.{});
const build_options = @import("options");
const gpu = @import("zgpu");

const Camera = @import("Camera.zig");
const Settings = @import("Settings.zig");
const GameServer = @import("GameServer.zig");
const LoginServer = @import("LoginServer.zig");

const AccountData = struct {
    email: []const u8,
    token: u128,

    pub fn load() !AccountData {
        const file = try std.fs.cwd().openFile("login_data_do_not_share.json", .{});
        defer file.close();

        const file_data = try file.readToEndAlloc(account_arena_allocator, std.math.maxInt(u32));
        defer account_arena_allocator.free(file_data);

        return try std.json.parseFromSliceLeaky(
            AccountData,
            account_arena_allocator,
            file_data,
            .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
        );
    }

    pub fn save(self: AccountData) !void {
        const file = try std.fs.cwd().createFile("login_data_do_not_share.json", .{});
        defer file.close();

        const json = try std.json.stringifyAlloc(account_arena_allocator, self, .{ .whitespace = .indent_4 });
        try file.writeAll(json);
    }
};

pub export var NvOptimusEnablement: c_int = 1;
pub export var AmdPowerXpressRequestHighPerformance: c_int = 1;

pub var ctx: *gpu.GraphicsContext = undefined;
pub var window: *glfw.Window = undefined;
pub var account_arena_allocator: std.mem.Allocator = undefined;
pub var current_account: ?AccountData = null;
pub var character_list: ?network_data.CharacterListData = null;
pub var current_time: i64 = 0;
pub var win_freq: u64 = 0;
pub var render_thread: std.Thread = undefined;
pub var tick_frame = false;
pub var tick_render = true;
pub var editing_map = false;
pub var need_minimap_update = false;
pub var need_force_update = false;
pub var need_swap_chain_update = false;
pub var minimap_update: struct {
    min_x: u32 = std.math.maxInt(u32),
    max_x: u32 = std.math.minInt(u32),
    min_y: u32 = std.math.maxInt(u32),
    max_y: u32 = std.math.minInt(u32),
} = .{};
pub var version_text: []const u8 = undefined;
pub var allocator: std.mem.Allocator = undefined;
pub var start_time: i64 = 0;
pub var game_server: GameServer = undefined;
pub var login_server: LoginServer = undefined;
pub var camera: Camera = .{};
pub var settings: Settings = .{};
pub var main_loop: *uv.uv_loop_t = undefined;

fn onResize(_: *glfw.Window, w: i32, h: i32) callconv(.C) void {
    const float_w: f32 = @floatFromInt(w);
    const float_h: f32 = @floatFromInt(h);

    {
        camera.lock.lock();
        defer camera.lock.unlock();
        camera.width = float_w;
        camera.height = float_h;
        camera.clip_scale[0] = 2.0 / float_w;
        camera.clip_scale[1] = 2.0 / float_h;
        camera.clip_offset[0] = -float_w / 2.0;
        camera.clip_offset[1] = -float_h / 2.0;
    }

    ui_systems.resize(float_w, float_h);

    need_swap_chain_update = true;
}

// lock ui_systems.ui_lock before calling (UI already does this implicitly)
pub fn enterGame(selected_server: network_data.ServerData, char_id: u32, class_data_id: u16) void {
    if (current_account == null) return;

    // TODO: readd RLS when fixed
    game_server.hello_data = network_data.C2SPacket{ .hello = .{
        .build_ver = build_options.version,
        .email = current_account.?.email,
        .token = current_account.?.token,
        .char_id = @intCast(char_id),
        .class_id = class_data_id,
    } };

    game_server.connect(selected_server.ip, selected_server.port) catch |e| {
        std.log.err("Connection failed: {}", .{e});
        return;
    };
}

pub fn enterTest(selected_server: network_data.ServerData, char_id: u32, test_map: []u8) void {
    if (current_account == null) return;

    // TODO: readd RLS when fixed
    game_server.hello_data = network_data.C2SPacket{ .map_hello = .{
        .build_ver = build_options.version,
        .email = current_account.?.email,
        .token = current_account.?.token,
        .char_id = char_id,
        .map = test_map,
    } };

    game_server.connect(selected_server.ip, selected_server.port) catch |e| {
        std.log.err("Connection failed: {}", .{e});
        return;
    };
}

fn renderTick() !void {
    if (build_options.enable_tracy) tracy.SetThreadName("Render");

    rpmalloc.initThread() catch |e| {
        std.log.err("Render thread initialization failed: {}", .{e});
        return;
    };
    defer rpmalloc.deinitThread(true);

    var last_vsync = settings.enable_vsync;
    var fps_time_start: i64 = 0;
    var frames: usize = 0;
    while (tick_render) : (std.atomic.spinLoopHint()) {
        if (need_swap_chain_update or last_vsync != settings.enable_vsync) {
            ctx.swapchain.release();
            const framebuffer_size = ctx.window_provider.fn_getFramebufferSize(ctx.window_provider.window);
            ctx.swapchain_descriptor.width = framebuffer_size[0];
            ctx.swapchain_descriptor.height = framebuffer_size[1];
            ctx.swapchain_descriptor.present_mode = if (settings.enable_vsync) .fifo else .immediate;
            ctx.swapchain = ctx.device.createSwapChain(ctx.surface, ctx.swapchain_descriptor);
            last_vsync = settings.enable_vsync;
            need_swap_chain_update = false;
        }

        defer frames += 1;
        const back_buffer = ctx.swapchain.getCurrentTextureView();
        const encoder = ctx.device.createCommandEncoder(null);

        render.draw(current_time, back_buffer, encoder);

        const commands = encoder.finish(null);
        encoder.release();

        ctx.queue.submit(&.{commands});
        commands.release();

        ctx.swapchain.present();
        back_buffer.release();

        if (current_time - fps_time_start > 1 * std.time.us_per_s) {
            try if (settings.stats_enabled) switch (ui_systems.screen) {
                inline .game, .editor => |screen| screen.updateFpsText(frames, try utils.currentMemoryUse(current_time)),
                else => {},
            };
            frames = 0;
            fps_time_start = current_time;
        }

        minimapUpdate: {
            if (!tick_frame or ui_systems.screen == .editor)
                break :minimapUpdate;

            if (need_minimap_update) {
                const min_x = @min(map.minimap.width, minimap_update.min_x);
                const max_x = @max(map.minimap.width, minimap_update.max_x + 1);
                const min_y = @min(map.minimap.height, minimap_update.min_y);
                const max_y = @max(map.minimap.height, minimap_update.max_y + 1);

                const w = max_x - min_x;
                const h = max_y - min_y;
                if (w <= 0 or h <= 0)
                    break :minimapUpdate;

                const comp_len = map.minimap.num_components * map.minimap.bytes_per_component;

                for (min_y..max_y, 0..) |y, i| {
                    const base_map_idx = y * map.minimap.width * comp_len + min_x * comp_len;
                    @memcpy(
                        map.minimap_copy[i * w * comp_len .. (i + 1) * w * comp_len],
                        map.minimap.data[base_map_idx .. base_map_idx + w * comp_len],
                    );
                }

                ctx.queue.writeTexture(
                    .{ .texture = render.minimap.texture, .origin = .{ .x = min_x, .y = min_y } },
                    .{ .bytes_per_row = comp_len * w, .rows_per_image = h },
                    .{ .width = w, .height = h },
                    u8,
                    map.minimap_copy[0 .. w * h * comp_len],
                );

                need_minimap_update = false;
                minimap_update = .{};
            } else if (need_force_update) {
                ctx.queue.writeTexture(
                    .{ .texture = render.minimap.texture },
                    .{ .bytes_per_row = map.minimap.bytes_per_row, .rows_per_image = map.minimap.height },
                    .{ .width = map.minimap.width, .height = map.minimap.height },
                    u8,
                    map.minimap.data,
                );
                need_force_update = false;
            }
        }
    }
}

fn gameTick(_: [*c]uv.uv_idle_t) callconv(.C) void {
    if (window.shouldClose()) {
        @branchHint(.unlikely);
        uv.uv_stop(@ptrCast(main_loop));
        return;
    }

    glfw.pollEvents();

    const instant = std.time.Instant.now() catch {
        std.log.err("Platform not supported", .{});
        std.posix.exit(0);
    };
    const time = switch (builtin.os.tag) {
        .windows => @as(i64, @intCast(@divFloor(instant.timestamp * std.time.us_per_s, win_freq))),
        else => @divFloor(instant.timestamp.nsec, std.time.ns_per_us) + instant.timestamp.sec * std.time.us_per_s,
    } - start_time;
    const dt: f32 = @floatFromInt(if (current_time > 0) time - current_time else 0);
    current_time = time;

    if (tick_frame or editing_map) map.update(time, dt);
    ui_systems.update(time, dt) catch @panic("todo");
}

pub fn disconnect(has_lock: bool) void {
    map.dispose();
    input.reset();
    {
        if (!has_lock) ui_systems.ui_lock.lock();
        defer if (!has_lock) ui_systems.ui_lock.unlock();

        if (ui_systems.is_testing) {
            ui_systems.switchScreen(.editor);
            ui_systems.is_testing = false;
        } else {
            if (character_list == null)
                ui_systems.switchScreen(.main_menu)
            else if (character_list.?.characters.len > 0)
                ui_systems.switchScreen(.char_select)
            else
                ui_systems.switchScreen(.char_create);
        }
    }
}

pub fn oomPanic() noreturn {
    @panic("Out of memory");
}

pub fn main() !void {
    if (build_options.enable_tracy) tracy.SetThreadName("Main");

    win_freq = if (builtin.os.tag == .windows) std.os.windows.QueryPerformanceFrequency() else 0;
    const start_instant = std.time.Instant.now() catch {
        std.log.err("Platform not supported", .{});
        std.posix.exit(0);
    };
    start_time = switch (builtin.os.tag) {
        .windows => @intCast(@divFloor(start_instant.timestamp * std.time.us_per_s, win_freq)),
        else => @divFloor(start_instant.timestamp.nsec, std.time.ns_per_us) + start_instant.timestamp.sec * std.time.us_per_s,
    };
    utils.rng.seed(@intCast(start_time));

    const is_debug = builtin.mode == .Debug;
    var gpa = if (is_debug) std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 10 }).init else {};
    defer _ = if (is_debug) gpa.deinit();

    try rpmalloc.init(null, .{});
    defer rpmalloc.deinit();

    const child_allocator = if (is_debug)
        gpa.allocator()
    else
        rpmalloc.allocator();
    allocator = if (build_options.enable_tracy) blk: {
        var tracy_alloc = tracy.TracyAllocator.init(child_allocator);
        break :blk tracy_alloc.allocator();
    } else child_allocator;

    var account_arena: std.heap.ArenaAllocator = .init(allocator);
    account_arena_allocator = account_arena.allocator();
    defer account_arena.deinit();

    current_account = AccountData.load() catch null;
    defer if (settings.remember_login) if (current_account) |acc| acc.save() catch {};

    try glfw.init();
    defer glfw.terminate();

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

    ctx = gpu.GraphicsContext.create(
        allocator,
        .{
            .window = window,
            .fn_getTime = @ptrCast(&glfw.getTime),
            .fn_getFramebufferSize = @ptrCast(&glfw.Window.getFramebufferSize),
            .fn_getWin32Window = @ptrCast(&glfw.getWin32Window),
            .fn_getX11Display = @ptrCast(&glfw.getX11Display),
            .fn_getX11Window = @ptrCast(&glfw.getX11Window),
            .fn_getWaylandDisplay = @ptrCast(&glfw.getWaylandDisplay),
            .fn_getWaylandSurface = @ptrCast(&glfw.getWaylandWindow),
            .fn_getCocoaWindow = @ptrCast(&glfw.getCocoaWindow),
        },
        .{ .present_mode = if (settings.enable_vsync) .fifo else .immediate },
    ) catch |e| {
        std.log.err("Failed to create graphics context: {any}", .{e});
        return;
    };
    defer ctx.destroy(allocator);

    _ = window.setKeyCallback(input.keyEvent);
    _ = window.setCharCallback(input.charEvent);
    _ = window.setCursorPosCallback(input.mouseMoveEvent);
    _ = window.setMouseButtonCallback(input.mouseEvent);
    _ = window.setScrollCallback(input.scrollEvent);
    _ = window.setFramebufferSizeCallback(onResize);

    try render.init(ctx);
    defer render.deinit();

    render_thread = try .spawn(.{ .allocator = allocator }, renderTick, .{});
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
