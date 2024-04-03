const std = @import("std");
const assets = @import("assets.zig");
const game_data = @import("game_data.zig");
const settings = @import("settings.zig");
const requests = @import("requests.zig");
const network = @import("network.zig");
const builtin = @import("builtin");
const xml = @import("xml.zig");
const asset_dir = @import("build_options").asset_dir;
const glfw = @import("mach-glfw");
const zstbi = @import("zstbi");
const input = @import("input.zig");
const utils = @import("utils.zig");
const camera = @import("camera.zig");
const map = @import("game/map.zig");
const element = @import("ui/element.zig");
const render = @import("render/base.zig");
const ztracy = @import("ztracy");
const zaudio = @import("zaudio");
const ui_systems = @import("ui/systems.zig");
const rpc = @import("rpc");
const dialog = @import("ui/dialogs/dialog.zig");
const rpmalloc = @import("rpmalloc").RPMalloc(.{});
const xev = @import("xev");

const sysgpu = @import("mach").sysgpu;
const wgpu = @import("mach-gpu");
const use_dawn = @import("build_options").use_dawn;
const gpu = if (use_dawn) wgpu else sysgpu.sysgpu;

pub const GPUInterface = wgpu.dawn.Interface;
pub const SYSGPUInterface = sysgpu.Impl;

pub const AccountData = struct {
    name: []const u8 = "",
    email: []const u8 = "",
    password: []const u8 = "",
    admin: bool = false,
    guild_name: []const u8 = "",
    guild_rank: u8 = 0,
};

pub var current_account = AccountData{};
pub var character_list: []game_data.CharacterData = undefined;
pub var server_list: ?[]game_data.ServerData = null;
pub var next_char_id: u32 = 0;
pub var max_chars: u32 = 0;
pub var current_time: i64 = 0;
pub var render_thread: std.Thread = undefined;
pub var network_thread: ?std.Thread = null;
pub var tick_render = true;
pub var tick_frame = false;
pub var editing_map = false;
pub var need_minimap_update = false;
pub var need_force_update = false;
pub var minimap_lock: std.Thread.Mutex = .{};
pub var need_swap_chain_update = false;
pub var minimap_update_min_x: u32 = std.math.maxInt(u32);
pub var minimap_update_max_x: u32 = std.math.minInt(u32);
pub var minimap_update_min_y: u32 = std.math.maxInt(u32);
pub var minimap_update_max_y: u32 = std.math.minInt(u32);
pub var rpc_client: *rpc = undefined;
pub var rpc_start: u64 = 0;
pub var version_text: []const u8 = undefined;
pub var allocator: std.mem.Allocator = undefined;
pub var start_time: i64 = 0;
pub var server: network.Server = undefined;

fn onResize(_: glfw.Window, w: u32, h: u32) void {
    const float_w: f32 = @floatFromInt(w);
    const float_h: f32 = @floatFromInt(h);

    camera.screen_width = float_w;
    camera.screen_height = float_h;
    camera.clip_scale_x = 2.0 / float_w;
    camera.clip_scale_y = 2.0 / float_h;

    ui_systems.resize(float_w, float_h);

    need_swap_chain_update = true;
}

fn networkCallback(ip: []const u8, port: u16, hello_data: network.C2SPacket) void {
    rpmalloc.initThread() catch |e| {
        std.log.err("Network thread initialization failed: {}", .{e});
        return;
    };

    if (server.socket != null)
        return;

    server.connect(ip, port, hello_data) catch |e| {
        std.log.err("Connection failed: {}", .{e});
        return;
    };

    rpmalloc.deinitThread(true);
    network_thread = null;
}

// lock ui_systems.ui_lock before calling (UI already does this implicitly)
pub fn enterGame(selected_server: game_data.ServerData, selected_char_id: u32, char_create_type: u16, char_create_skin_type: u16) void {
    if (network_thread != null)
        return;

    ui_systems.switchScreen(.game);
    network_thread = std.Thread.spawn(.{}, networkCallback, .{ selected_server.dns, selected_server.port, network.C2SPacket{ .hello = .{
        .build_ver = settings.build_version,
        .game_id = -2,
        .email = current_account.email,
        .password = current_account.password,
        .char_id = @intCast(selected_char_id),
        .class_type = char_create_type,
        .skin_type = char_create_skin_type,
    } } }) catch |e| {
        std.log.err("Connection failed: {}", .{e});
        return;
    };
}

fn renderTick(window: glfw.Window) !void {
    rpmalloc.initThread() catch |e| {
        std.log.err("Render thread initialization failed: {}", .{e});
        return;
    };
    defer rpmalloc.deinitThread(true);

    var last_aa_type = settings.aa_type;
    var last_vsync = settings.enable_vsync;
    var fps_time_start: i64 = 0;
    var frames: usize = 0;
    while (tick_render) {
        if (need_swap_chain_update or last_vsync != settings.enable_vsync) {
            render.swap_chain.release();
            const framebuffer_size = window.getFramebufferSize();
            render.swap_chain_desc.width = framebuffer_size.width;
            render.swap_chain_desc.height = framebuffer_size.height;
            render.swap_chain_desc.present_mode = if (settings.enable_vsync) .fifo else .immediate;
            render.swap_chain = render.device.createSwapChain(render.surface, &render.swap_chain_desc);
            render.createColorTexture();
            last_vsync = settings.enable_vsync;
            need_swap_chain_update = false;
        }

        // ticking can get turned off while in sleep
        if (!tick_render)
            return;

        defer {
            frames += 1;
            std.time.sleep(settings.fps_ns);
        }

        const time = std.time.microTimestamp();
        render.draw(time);

        if (last_aa_type != settings.aa_type) {
            render.createColorTexture();
            last_aa_type = settings.aa_type;
        }

        if (time - fps_time_start > 1 * std.time.us_per_s) {
            try if (settings.stats_enabled) switch (ui_systems.screen) {
                inline .game, .editor => |screen| if (screen.inited) screen.updateFpsText(frames, try utils.currentMemoryUse()),
                else => {},
            };
            frames = 0;
            fps_time_start = time;
        }

        minimapUpdate: {
            minimap_lock.lock();
            defer minimap_lock.unlock();

            if (need_minimap_update) {
                const min_x = @min(map.minimap.width, minimap_update_min_x);
                const max_x = @max(map.minimap.width, minimap_update_max_x + 1);
                const min_y = @min(map.minimap.height, minimap_update_min_y);
                const max_y = @max(map.minimap.height, minimap_update_max_y + 1);

                const w = max_x - min_x;
                const h = max_y - min_y;
                if (w <= 0 or h <= 0)
                    break :minimapUpdate;

                const comp_len = map.minimap.num_components * map.minimap.bytes_per_component;
                const copy = allocator.alloc(u8, w * h * comp_len) catch |e| {
                    std.log.err("Minimap alloc failed: {}", .{e});
                    need_minimap_update = false;
                    minimap_update_min_x = std.math.maxInt(u32);
                    minimap_update_max_x = std.math.minInt(u32);
                    minimap_update_min_y = std.math.maxInt(u32);
                    minimap_update_max_y = std.math.minInt(u32);
                    break :minimapUpdate;
                };
                defer allocator.free(copy);

                var idx: u32 = 0;
                for (min_y..max_y) |y| {
                    const base_map_idx = y * map.minimap.width * comp_len + min_x * comp_len;
                    @memcpy(
                        copy[idx * w * comp_len .. (idx + 1) * w * comp_len],
                        map.minimap.data[base_map_idx .. base_map_idx + w * comp_len],
                    );
                    idx += 1;
                }

                render.queue.writeTexture(
                    &.{ .texture = render.minimap_texture, .origin = .{ .x = min_x, .y = min_y } },
                    &.{ .bytes_per_row = comp_len * w, .rows_per_image = h },
                    &.{ .width = w, .height = h },
                    copy,
                );

                need_minimap_update = false;
                minimap_update_min_x = std.math.maxInt(u32);
                minimap_update_max_x = std.math.minInt(u32);
                minimap_update_min_y = std.math.maxInt(u32);
                minimap_update_max_y = std.math.minInt(u32);
            } else if (need_force_update) {
                render.queue.writeTexture(
                    &.{ .texture = render.minimap_texture },
                    &.{ .bytes_per_row = map.minimap.bytes_per_row, .rows_per_image = map.minimap.height },
                    &.{ .width = map.minimap.width, .height = map.minimap.height },
                    map.minimap.data,
                );
                need_force_update = false;
            }
        }
    }
}

pub fn disconnect(has_lock: bool) void {
    server.shutdown();
    map.dispose(allocator);
    input.reset();
    {
        if (!has_lock) ui_systems.ui_lock.lock();
        defer if (!has_lock) ui_systems.ui_lock.unlock();
        ui_systems.switchScreen(.char_select);
    }
    dialog.showDialog(.none, {});
}

// This is effectively just raw_c_allocator wrapped in the Tracy stuff
fn tracyAlloc(_: *anyopaque, len: usize, _: u8, _: usize) ?[*]u8 {
    const malloc = std.c.malloc(len);
    ztracy.Alloc(malloc, len);
    return @ptrCast(malloc);
}

fn tracyResize(_: *anyopaque, buf: []u8, _: u8, new_len: usize, _: usize) bool {
    return new_len <= buf.len;
}

fn tracyFree(_: *anyopaque, buf: []u8, _: u8, _: usize) void {
    ztracy.Free(buf.ptr);
    std.c.free(buf.ptr);
}

pub fn main() !void {
    // needed for tracy to register
    var main_zone: ztracy.ZoneCtx = undefined;
    if (settings.enable_tracy)
        main_zone = ztracy.ZoneNC(@src(), "Main Zone", 0x00FF0000);
    defer if (settings.enable_tracy) main_zone.End();

    start_time = std.time.microTimestamp();
    utils.rng.seed(@intCast(start_time));

    const is_debug = builtin.mode == .Debug;
    var gpa = if (is_debug) std.heap.GeneralPurposeAllocator(.{}){} else {};
    defer _ = if (is_debug) gpa.deinit();

    const tracy_allocator_vtable = std.mem.Allocator.VTable{
        .alloc = tracyAlloc,
        .resize = tracyResize,
        .free = tracyFree,
    };
    const tracy_allocator = std.mem.Allocator{
        .ptr = undefined,
        .vtable = &tracy_allocator_vtable,
    };

    try rpmalloc.init(null, .{});
    defer rpmalloc.deinit();

    allocator = if (settings.enable_tracy) tracy_allocator else switch (builtin.mode) {
        .Debug => gpa.allocator(),
        else => rpmalloc.allocator(),
    };

    defer {
        if (current_account.name.len > 0)
            allocator.free(current_account.name);

        if (current_account.email.len > 0)
            allocator.free(current_account.email);

        if (current_account.password.len > 0)
            allocator.free(current_account.password);

        if (character_list.len > 0) {
            for (character_list) |char| {
                char.deinit(allocator);
            }
            allocator.free(character_list);
        }

        if (server_list) |srv_list| {
            for (srv_list) |srv| {
                srv.deinit(allocator);
            }
            allocator.free(srv_list);
        }
    }

    version_text = "v" ++ settings.build_version;
    rpc_client = try rpc.init(allocator, &ready);
    defer rpc_client.deinit();

    if (!glfw.init(.{})) {
        glfw.getErrorCode() catch |err| switch (err) {
            error.PlatformError,
            error.PlatformUnavailable,
            => return err,
            else => unreachable,
        };
    }
    defer glfw.terminate();

    zstbi.init(allocator);
    defer zstbi.deinit();

    zaudio.init(allocator);
    defer zaudio.deinit();

    try settings.init(allocator);
    defer settings.deinit(allocator);

    try assets.init(allocator);
    defer assets.deinit(allocator);

    try game_data.init(allocator);
    defer game_data.deinit(allocator);

    requests.init(allocator);
    defer requests.deinit();

    try map.init(allocator);
    defer map.deinit(allocator);

    input.init(allocator);
    defer input.deinit(allocator);

    try ui_systems.init(allocator);
    defer ui_systems.deinit();

    {
        ui_systems.ui_lock.lock();
        defer ui_systems.ui_lock.unlock();
        ui_systems.switchScreen(.main_menu);
    }

    const window = glfw.Window.create(
        1280,
        720,
        "Eclipse",
        null,
        null,
        .{ .client_api = .no_api, .cocoa_retina_framebuffer = true },
    ) orelse switch (glfw.mustGetErrorCode()) {
        error.InvalidEnum,
        error.InvalidValue,
        error.FormatUnavailable,
        => unreachable,
        error.APIUnavailable,
        error.VersionUnavailable,
        error.PlatformError,
        => |err| return err,
        else => unreachable,
    };
    defer window.destroy();
    window.setSizeLimits(.{ .width = 1280, .height = 720 }, .{ .width = null, .height = null });
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

    try render.init(window, allocator);
    defer render.deinit();

    var thread_pool = xev.ThreadPool.init(.{});
    defer thread_pool.deinit();
    defer thread_pool.shutdown();

    server = try network.Server.init(allocator, &thread_pool);
    defer server.deinit();

    var rpc_thread = try std.Thread.spawn(.{}, runRpc, .{rpc_client});
    defer {
        rpc_client.stop();
        rpc_thread.join();
    }

    render_thread = try std.Thread.spawn(.{}, renderTick, .{window});
    defer {
        tick_render = false;
        render_thread.join();
    }

    var last_update: i64 = 0;
    var last_ui_update: i64 = 0;
    while (!window.shouldClose()) {
        const time = std.time.microTimestamp() - start_time;
        current_time = time;

        glfw.pollEvents();

        if (tick_frame or editing_map) {
            map.update(allocator);
            last_update = time;
        }

        if (time - last_ui_update > 16 * std.time.us_per_ms) {
            try ui_systems.update();
            last_ui_update = time;
        }

        std.time.sleep(settings.fps_ns);
    }
}

fn ready(cli: *rpc) !void {
    rpc_start = @intCast(std.time.timestamp());
    try cli.setPresence(.{
        .assets = .{
            .large_image = rpc.Packet.ArrayString(256).create("logo"),
            .large_text = rpc.Packet.ArrayString(128).create(version_text),
        },
        .timestamps = .{
            .start = rpc_start,
        },
    });
}

fn runRpc(cli: *rpc) void {
    rpmalloc.initThread() catch |e| {
        std.log.err("RPC thread initialization failed: {}", .{e});
        return;
    };
    defer rpmalloc.deinitThread(true);

    cli.run(.{ .client_id = "1223822665748320317" }) catch |e| {
        std.log.err("Setting up RPC failed: {}", .{e});
    };
}
