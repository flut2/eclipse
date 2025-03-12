const std = @import("std");
const builtin = @import("builtin");

const glfw = @import("glfw");
const pack = @import("turbopack");
const shared = @import("shared");
const game_data = shared.game_data;
const utils = shared.utils;
const f32i = utils.f32i;
const RGBA = utils.RGBA;
const zaudio = @import("zaudio");
const ziggy = @import("ziggy");
const zstbi = @import("zstbi");

const main = @import("main.zig");
const Settings = @import("Settings.zig");

// for packing
const Position = struct { x: u16, y: u16 };

const GameSheet = struct {
    type: enum { image, anim_enemy, anim_player },
    name: []const u8,
    path: []const u8,
    w: u32,
    h: u32,
    dont_trim: bool = false,
};

const WallSheet = struct {
    name: []const u8,
    path: []const u8,
    full_w: u32,
    full_h: u32,
    w: u32,
    h: u32,
};

const UiSheet = struct {
    const imply_size = std.math.maxInt(u32);

    name: []const u8,
    path: []const u8,
    w: u32 = imply_size,
    h: u32 = imply_size,
};

const PlaneBounds = struct {
    left: f32 = 0.0,
    bottom: f32 = 0.0,
    right: f32 = 0.0,
    top: f32 = 0.0,
};

const AtlasBounds = struct {
    left: f32 = 0.0,
    bottom: f32 = 0.0,
    right: f32 = 0.0,
    top: f32 = 0.0,
};

const GlyphData = struct {
    unicode: u8,
    advance: f32,
    plane_bounds: ?PlaneBounds = null,
    atlas_bounds: ?AtlasBounds = null,
};

const InternalFontData = struct {
    atlas: struct {
        type: enum { sdf, psdf, msdf, mtsdf },
        distance_range: f32,
        distance_range_middle: f32,
        size: f32,
        width: f32,
        height: f32,
        y_origin: enum { top, bottom },
    },
    metrics: struct {
        em_size: f32,
        line_height: f32,
        ascender: f32,
        descender: f32,
        underline_y: f32,
        underline_thickness: f32,
    },
    glyphs: []GlyphData,
    kerning: []struct { dummy: f32 },
};

const ParsedFontData = struct {
    characters: [256]CharacterData,
    size: f32,
    padding: f32,
    px_range: f32,
    line_height: f32,
    width: f32,
    height: f32,
};

const AudioState = struct {
    device: *zaudio.Device,
    engine: *zaudio.Engine,

    fn audioCallback(device: *zaudio.Device, output: ?*anyopaque, _: ?*const anyopaque, num_frames: u32) callconv(.C) void {
        const audio: *AudioState = @ptrCast(@alignCast(device.getUserData()));
        audio.engine.readPcmFrames(output.?, num_frames, null) catch {};
    }

    fn create() !*AudioState {
        const audio = try arena.allocator().create(AudioState);

        var device_config: zaudio.Device.Config = .init(.playback);
        device_config.data_callback = audioCallback;
        device_config.user_data = audio;
        device_config.sample_rate = 48000;
        device_config.period_size_in_frames = 480;
        device_config.period_size_in_milliseconds = 10;
        device_config.playback.format = .float32;
        device_config.playback.channels = 2;
        const device = try zaudio.Device.create(null, device_config);

        var engine_config: zaudio.Engine.Config = .init();
        engine_config.device = device;
        engine_config.no_auto_start = .true32;
        const engine = try zaudio.Engine.create(engine_config);

        audio.* = .{ .device = device, .engine = engine };
        return audio;
    }

    fn destroy(audio: *AudioState) void {
        audio.engine.destroy();
        audio.device.destroy();
    }
};

pub const padding = 0;

pub const atlas_width = 2048;
pub const atlas_height = 1024;
pub const base_texel_w = 1.0 / @as(comptime_float, atlas_width);
pub const base_texel_h = 1.0 / @as(comptime_float, atlas_height);

pub const ui_atlas_width = 2048;
pub const ui_atlas_height = 4096;
pub const ui_texel_w = 1.0 / @as(comptime_float, ui_atlas_width);
pub const ui_texel_h = 1.0 / @as(comptime_float, ui_atlas_height);

pub const Action = enum { stand, walk, attack };
pub const Direction = enum { right, left, down, up };

pub const CharacterData = struct {
    x_advance: f32,
    tex_u: f32,
    tex_v: f32,
    tex_w: f32,
    tex_h: f32,
    x_offset: f32,
    y_offset: f32,
    width: f32,
    height: f32,

    pub fn parse(glyph: GlyphData, size: f32, atlas_w: f32, atlas_h: f32) !CharacterData {
        const plane_bounds: PlaneBounds = glyph.plane_bounds orelse .{};
        const atlas_bounds: AtlasBounds = glyph.atlas_bounds orelse .{};
        return .{
            .x_advance = glyph.advance * size,
            .x_offset = plane_bounds.left * size,
            .y_offset = plane_bounds.bottom * size,
            .width = (plane_bounds.right - plane_bounds.left) * size,
            .height = (plane_bounds.top - plane_bounds.bottom) * size,
            .tex_u = atlas_bounds.left / atlas_w,
            .tex_v = (atlas_h - atlas_bounds.top) / atlas_h,
            .tex_h = (atlas_bounds.top - atlas_bounds.bottom) / atlas_h,
            .tex_w = (atlas_bounds.right - atlas_bounds.left) / atlas_w,
        };
    }
};

pub const WallData = struct {
    base: AtlasData,
    left_outline: AtlasData,
    right_outline: AtlasData,
    top_outline: AtlasData,
    bottom_outline: AtlasData,

    pub const default: WallData = .{
        .base = .fromRaw(0, 0, 0, 0, .base),
        .left_outline = .fromRaw(0, 0, 0, 0, .base),
        .right_outline = .fromRaw(0, 0, 0, 0, .base),
        .top_outline = .fromRaw(0, 0, 0, 0, .base),
        .bottom_outline = .fromRaw(0, 0, 0, 0, .base),
    };
};

pub const AnimEnemyData = struct {
    pub const directions = 2;
    pub const walk_actions = 3;
    pub const attack_actions = 2;

    walk_anims: [directions * walk_actions]AtlasData,
    attack_anims: [directions * attack_actions]AtlasData,

    pub fn removePadding(self: *AnimEnemyData) void {
        for (&self.walk_anims) |*data| data.removePadding();
        for (&self.attack_anims) |*data| data.removePadding();
    }
};

pub const AnimPlayerData = struct {
    pub const directions = 4;
    pub const walk_actions = 3;
    pub const attack_actions = 2;

    walk_anims: [directions * walk_actions]AtlasData,
    attack_anims: [directions * attack_actions]AtlasData,

    pub fn removePadding(self: *AnimPlayerData) void {
        for (&self.walk_anims) |*data| data.removePadding();
        for (&self.attack_anims) |*data| data.removePadding();
    }
};

pub const AtlasType = enum(u8) {
    base,
    ui,

    pub fn width(self: AtlasType) f32 {
        return switch (self) {
            .base => atlas_width,
            .ui => ui_atlas_width,
        };
    }

    pub fn height(self: AtlasType) f32 {
        return switch (self) {
            .base => atlas_height,
            .ui => ui_atlas_height,
        };
    }
};

pub const AtlasData = extern struct {
    pub fn whole(atlas_type: AtlasType) AtlasData {
        return fromRawF32(1.0, 1.0, 1.0, 1.0, atlas_type);
    }

    pub const default: AtlasData = .fromRaw(0, 0, 0, 0, .base);

    tex_u: f32,
    tex_v: f32,
    tex_w: f32,
    tex_h: f32,
    atlas_type: AtlasType,

    pub fn removePadding(self: *AtlasData) void {
        const w = self.atlas_type.width();
        const h = self.atlas_type.height();
        const float_pad: f32 = padding;
        self.tex_u += float_pad / w;
        self.tex_v += float_pad / h;
        self.tex_w -= float_pad * 2 / w;
        self.tex_h -= float_pad * 2 / h;
    }

    pub fn fromRaw(u: c_int, v: c_int, w: c_int, h: c_int, ui: AtlasType) AtlasData {
        return fromRawF32(f32i(u), f32i(v), f32i(w), f32i(h), ui);
    }

    pub fn fromRawF32(u: f32, v: f32, w: f32, h: f32, atlas_type: AtlasType) AtlasData {
        const atlas_w = atlas_type.width();
        const atlas_h = atlas_type.height();
        return .{
            .tex_u = u / atlas_w,
            .tex_v = v / atlas_h,
            .tex_w = w / atlas_w,
            .tex_h = h / atlas_h,
            .atlas_type = atlas_type,
        };
    }

    pub fn texURaw(self: AtlasData) f32 {
        return self.tex_u * self.atlas_type.width() + padding;
    }

    pub fn texVRaw(self: AtlasData) f32 {
        return self.tex_v * self.atlas_type.height() + padding;
    }

    pub fn texWRaw(self: AtlasData) f32 {
        return self.tex_w * self.atlas_type.width();
    }

    pub fn texHRaw(self: AtlasData) f32 {
        return self.tex_h * self.atlas_type.height();
    }

    pub fn width(self: AtlasData) f32 {
        return self.texWRaw() - padding * 2.0;
    }

    pub fn height(self: AtlasData) f32 {
        return self.texHRaw() - padding * 2.0;
    }
};

pub var sfx_path_buffer: [256]u8 = undefined;
pub var audio_state: ?*AudioState = undefined;
pub var main_music: ?*zaudio.Sound = undefined;
pub var arena: std.heap.ArenaAllocator = undefined;

pub var atlas: zstbi.Image = undefined;
pub var ui_atlas: zstbi.Image = undefined;

pub var bold_atlas: zstbi.Image = undefined;
pub var bold_data: ParsedFontData = undefined;
pub var bold_italic_atlas: zstbi.Image = undefined;
pub var bold_italic_data: ParsedFontData = undefined;
pub var medium_atlas: zstbi.Image = undefined;
pub var medium_data: ParsedFontData = undefined;
pub var medium_italic_atlas: zstbi.Image = undefined;
pub var medium_italic_data: ParsedFontData = undefined;

// horrible, but no other option since cursor is opaque
pub var default_cursor_pressed: *glfw.Cursor = undefined;
pub var default_cursor: *glfw.Cursor = undefined;
pub var royal_cursor_pressed: *glfw.Cursor = undefined;
pub var royal_cursor: *glfw.Cursor = undefined;
pub var ranger_cursor_pressed: *glfw.Cursor = undefined;
pub var ranger_cursor: *glfw.Cursor = undefined;
pub var aztec_cursor_pressed: *glfw.Cursor = undefined;
pub var aztec_cursor: *glfw.Cursor = undefined;
pub var fiery_cursor_pressed: *glfw.Cursor = undefined;
pub var fiery_cursor: *glfw.Cursor = undefined;
pub var target_enemy_cursor_pressed: *glfw.Cursor = undefined;
pub var target_enemy_cursor: *glfw.Cursor = undefined;
pub var target_ally_cursor_pressed: *glfw.Cursor = undefined;
pub var target_ally_cursor: *glfw.Cursor = undefined;

pub var sfx_copy_map: std.AutoHashMapUnmanaged(*zaudio.Sound, std.ArrayListUnmanaged(*zaudio.Sound)) = .empty;
pub var sfx_map: std.StringHashMapUnmanaged(*zaudio.Sound) = .empty;
pub var dominant_color_data: std.StringHashMapUnmanaged([]RGBA) = .empty;
pub var atlas_to_color_data: std.AutoHashMapUnmanaged(u160, []u32) = .empty;
pub var atlas_data: std.StringHashMapUnmanaged([]AtlasData) = .empty;
pub var ui_atlas_data: std.StringHashMapUnmanaged([]AtlasData) = .empty;
pub var anim_enemies: std.StringHashMapUnmanaged([]AnimEnemyData) = .empty;
pub var anim_players: std.StringHashMapUnmanaged([]AnimPlayerData) = .empty;
pub var walls: std.StringHashMapUnmanaged([]WallData) = .empty;

pub var interact_key_tex: AtlasData = AtlasData.fromRawF32(0.0, 0.0, 0.0, 0.0, .ui);
pub var key_tex_map: std.AutoHashMapUnmanaged(Settings.Button, u16) = .empty;

pub var left_mask_uv: [2]f32 = undefined;
pub var top_mask_uv: [2]f32 = undefined;
pub var right_mask_uv: [2]f32 = undefined;
pub var bottom_mask_uv: [2]f32 = undefined;
pub var minimap_icons: []AtlasData = undefined;
pub var particle: AtlasData = undefined;
pub var generic_8x8: AtlasData = undefined;
pub var empty_bar_data: AtlasData = undefined;
pub var hp_bar_data: AtlasData = undefined;
pub var mp_bar_data: AtlasData = undefined;
pub var error_data: AtlasData = undefined;
pub var error_data_enemy: AnimEnemyData = undefined;
pub var error_data_player: AnimPlayerData = undefined;
pub var error_data_wall: WallData = undefined;
pub var light_w: f32 = 1.0;
pub var light_h: f32 = 1.0;
pub var light_data: AtlasData = undefined;
pub var bloodfont_data: AnimPlayerData = undefined;

fn packSort(_: void, lhs: pack.IdRect, rhs: pack.IdRect) bool {
    return lhs.rect.w < rhs.rect.w;
}

fn imageBounds(img: zstbi.Image, x: usize, y: usize, cut_w: u32, cut_h: u32) struct {
    w: u32,
    h: u32,
    x_offset: u16,
    y_offset: u16,
} {
    var min_x = x + cut_w;
    var min_y = y + cut_h;
    var max_x = x;
    var max_y = y;

    for (y..y + cut_h) |loop_y| {
        for (x..x + cut_w) |loop_x| {
            if (img.data[(loop_y * img.width + loop_x) * 4 + 3] != 0) {
                min_x = @min(min_x, loop_x);
                min_y = @min(min_y, loop_y);
                max_x = @max(max_x, loop_x);
                max_y = @max(max_y, loop_y);
            }
        }
    }

    const w = if (min_x > max_x) 0 else max_x - min_x + 1;
    const h = if (min_y > max_y) 0 else max_y - min_y + 1;
    return .{
        .w = @intCast(w),
        .h = @intCast(h),
        .x_offset = @intCast(if (w == 0 or x > min_x) 0 else min_x - x),
        .y_offset = @intCast(if (h == 0 or y > min_y) 0 else min_y - y),
    };
}

fn addCursors(comptime image_name: [:0]const u8, comptime cut_width: u32, comptime cut_height: u32) !void {
    var img: zstbi.Image = try .loadFromFile("./assets/sheets/" ++ image_name, 4);
    defer img.deinit();

    const img_size = cut_width * cut_height;
    const len = std.math.divExact(u32, img.width * img.height, img_size) catch
        std.debug.panic("Cursor image " ++ image_name ++ " has an incorrect resolution: {}x{} (cut_w={}, cut_h={})", .{ img.width, img.height, cut_width, cut_height });

    for (0..len) |i| {
        const cur_src_x = (i * cut_width) % img.width;
        const cur_src_y = @divFloor(i * cut_width, img.width) * cut_height;

        var temp = try arena.allocator().alloc(u8, img_size * 4);
        defer arena.allocator().free(temp);

        for (0..img_size) |j| {
            const row_count = @divFloor(j, cut_width);
            const row_idx = j % cut_width;
            const target_idx = (row_count * cut_width + row_idx) * 4;
            const src_idx = ((cur_src_y + row_count) * img.width + cur_src_x + row_idx) * 4;
            @memcpy(temp[target_idx .. target_idx + 4], img.data[src_idx .. src_idx + 4]);
        }

        const cursor = try glfw.Cursor.create(
            .{ .w = cut_width, .h = cut_height, .pixels = temp.ptr },
            cut_width / 2,
            cut_height / 2,
        );

        switch (i) {
            0 => default_cursor_pressed = cursor,
            1 => default_cursor = cursor,
            2 => royal_cursor_pressed = cursor,
            3 => royal_cursor = cursor,
            4 => ranger_cursor_pressed = cursor,
            5 => ranger_cursor = cursor,
            6 => aztec_cursor_pressed = cursor,
            7 => aztec_cursor = cursor,
            8 => fiery_cursor_pressed = cursor,
            9 => fiery_cursor = cursor,
            10 => target_enemy_cursor_pressed = cursor,
            11 => target_enemy_cursor = cursor,
            12 => target_ally_cursor_pressed = cursor,
            13 => target_ally_cursor = cursor,
            else => {},
        }
    }
}

fn addWall(
    sheet_name: []const u8,
    image_path: []const u8,
    full_cut_width: u32,
    full_cut_height: u32,
    base_cut_width: u32,
    base_cut_height: u32,
    ctx: *pack.Context,
) !void {
    if (walls.contains(sheet_name)) std.debug.panic("\"{s}\" is already present in wall data", .{sheet_name});

    const x_off = f32i(full_cut_width - base_cut_width) / 2.0;
    const y_off = f32i(full_cut_height - base_cut_height) / 2.0;
    if (x_off < 0 or y_off < 0) @panic("Invalid base cut w/h");
    if (std.mem.indexOf(u8, image_path, "..") != null) {
        std.log.err("Going backwards in paths is not allowed. Problematic path: {s}", .{image_path});
        std.posix.exit(0);
    }
    var buf: [128]u8 = undefined;
    const path = try std.fmt.bufPrintZ(&buf, "./assets/sheets/{s}", .{image_path});
    var img: zstbi.Image = try .loadFromFile(path, 4);
    defer img.deinit();

    const len = std.math.divExact(u32, img.width * img.height, full_cut_width * full_cut_height) catch
        std.debug.panic("Sheet {s} has an incorrect resolution: {}x{} (cut_w={}, cut_h={})", .{
            sheet_name,
            img.width,
            img.height,
            full_cut_width,
            full_cut_height,
        });

    var current_rects = try arena.allocator().alloc(pack.IdRect, len);
    defer arena.allocator().free(current_rects);

    var current_positions = try arena.allocator().alloc(Position, len);
    defer arena.allocator().free(current_positions);

    for (0..len) |i| {
        const cur_src_x = (i * full_cut_width) % img.width;
        const cur_src_y = @divFloor(i * full_cut_width, img.width) * full_cut_height;
        const bounds = imageBounds(img, cur_src_x, cur_src_y, full_cut_width, full_cut_height);
        current_positions[i].x = @intCast(cur_src_x + bounds.x_offset);
        current_positions[i].y = @intCast(cur_src_y + bounds.y_offset);
        current_rects[i].rect.w = @intCast(bounds.w + padding * 2);
        current_rects[i].rect.h = @intCast(bounds.h + padding * 2);
        current_rects[i].id = @intCast(i);
    }

    try pack.pack(pack.IdRect, ctx, current_rects, .{ .assume_capacity = true, .sortLessThanFn = packSort });

    var data = try arena.allocator().alloc(WallData, len);

    var dominant_colors = try arena.allocator().alloc(RGBA, len);
    @memset(dominant_colors, RGBA{});

    var color_counts: std.AutoHashMapUnmanaged(RGBA, u32) = .{};
    defer color_counts.deinit(arena.allocator());

    for (0..len) |i| {
        const id_rect = current_rects[i];
        const rect = id_rect.rect;
        const idx: usize = @intCast(id_rect.id);
        const pos = current_positions[idx];
        if (rect.w <= 0 or rect.h <= 0) {
            data[idx] = .{
                .base = .fromRaw(0, 0, 0, 0, .base),
                .left_outline = .fromRaw(0, 0, 0, 0, .base),
                .right_outline = .fromRaw(0, 0, 0, 0, .base),
                .top_outline = .fromRaw(0, 0, 0, 0, .base),
                .bottom_outline = .fromRaw(0, 0, 0, 0, .base),
            };
            continue;
        }

        const cur_atlas_x: u32 = @intCast(rect.x + padding);
        const cur_atlas_y: u32 = @intCast(rect.y + padding);

        color_counts.clearRetainingCapacity();

        const w: u32 = @intCast(rect.w - padding * 2);
        const h: u32 = @intCast(rect.h - padding * 2);
        for (0..h) |j| {
            const atlas_idx = ((cur_atlas_y + j) * atlas_width + cur_atlas_x) * 4;
            const src_idx = ((pos.y + j) * img.width + pos.x) * 4;
            @memcpy(atlas.data[atlas_idx .. atlas_idx + w * 4], img.data[src_idx .. src_idx + w * 4]);

            for (0..w) |k| {
                const x_offset = k * 4;
                if (img.data[src_idx + 3 + x_offset] > 0) {
                    const rgba: RGBA = .{
                        .r = img.data[src_idx + x_offset],
                        .g = img.data[src_idx + 1 + x_offset],
                        .b = img.data[src_idx + 2 + x_offset],
                        .a = 255,
                    };
                    if (color_counts.get(rgba)) |count| {
                        try color_counts.put(arena.allocator(), rgba, count + 1);
                    } else {
                        try color_counts.put(arena.allocator(), rgba, 1);
                    }
                }
            }
        }

        var colors: std.ArrayListUnmanaged(u32) = .empty;
        defer colors.deinit(arena.allocator());

        var max: u32 = 0;
        var count_iter = color_counts.iterator();
        while (count_iter.next()) |entry| {
            try colors.append(arena.allocator(), @as(u32, @intCast(entry.key_ptr.r)) << 16 |
                @as(u32, @intCast(entry.key_ptr.g)) << 8 |
                @as(u32, @intCast(entry.key_ptr.b)));

            if (entry.value_ptr.* > max) {
                dominant_colors[idx] = entry.key_ptr.*;
                max = entry.value_ptr.*;
            }
        }

        const fx = f32i(rect.x);
        const fy = f32i(rect.y);
        const fw = f32i(rect.w);
        const fh = f32i(rect.h);
        const base_w = fw - x_off * 2.0;
        const base_h = fh - y_off * 2.0;
        const base_atlas_data: AtlasData = .fromRawF32(fx + x_off, fy + y_off, base_w, base_h, .base);
        data[idx] = .{
            .base = base_atlas_data,
            .left_outline = .fromRawF32(fx, fy + y_off, x_off, base_h, .base),
            .right_outline = .fromRawF32(fx + x_off + base_w, fy + y_off, x_off, base_h, .base),
            .top_outline = .fromRawF32(fx + x_off, fy, base_w, y_off, .base),
            .bottom_outline = .fromRawF32(fx + x_off, fy + y_off + base_h, base_w, y_off, .base),
        };
        try atlas_to_color_data.put(arena.allocator(), @bitCast(base_atlas_data), try arena.allocator().dupe(u32, colors.items));
    }

    try walls.put(arena.allocator(), sheet_name, data);
    try dominant_color_data.put(arena.allocator(), sheet_name, dominant_colors);
}

fn addImage(
    sheet_name: []const u8,
    image_path: []const u8,
    cut_width: u32,
    cut_height: u32,
    dont_trim: bool,
    ctx: *pack.Context,
) !void {
    if (atlas_data.contains(sheet_name)) std.debug.panic("\"{s}\" is already present in game atlas data", .{sheet_name});

    if (std.mem.indexOf(u8, image_path, "..") != null) {
        std.log.err("Going backwards in paths is not allowed. Problematic path: {s}", .{image_path});
        std.posix.exit(0);
    }
    var buf: [128]u8 = undefined;
    const path = try std.fmt.bufPrintZ(&buf, "./assets/sheets/{s}", .{image_path});
    var img: zstbi.Image = try .loadFromFile(path, 4);
    defer img.deinit();

    const len = std.math.divExact(u32, img.width * img.height, cut_width * cut_height) catch
        std.debug.panic("Sheet {s} has an incorrect resolution: {}x{} (cut_w={}, cut_h={})", .{ sheet_name, img.width, img.height, cut_width, cut_height });

    var current_rects = try arena.allocator().alloc(pack.IdRect, len);
    defer arena.allocator().free(current_rects);

    var current_positions = try arena.allocator().alloc(Position, len);
    defer arena.allocator().free(current_positions);

    for (0..len) |i| {
        const cur_src_x = (i * cut_width) % img.width;
        const cur_src_y = @divFloor(i * cut_width, img.width) * cut_height;
        const bounds = imageBounds(img, cur_src_x, cur_src_y, cut_width, cut_height);
        if (dont_trim) {
            current_positions[i].x = @intCast(cur_src_x);
            current_positions[i].y = @intCast(cur_src_y);
            if (bounds.w == 0 or bounds.h == 0) {
                current_rects[i].rect.w = 0;
                current_rects[i].rect.h = 0;
            } else {
                current_rects[i].rect.w = @intCast(cut_width + padding * 2);
                current_rects[i].rect.h = @intCast(cut_height + padding * 2);
            }
            current_rects[i].id = @intCast(i);
        } else {
            current_positions[i].x = @intCast(cur_src_x + bounds.x_offset);
            current_positions[i].y = @intCast(cur_src_y + bounds.y_offset);
            current_rects[i].rect.w = @intCast(bounds.w + padding * 2);
            current_rects[i].rect.h = @intCast(bounds.h + padding * 2);
            current_rects[i].id = @intCast(i);
        }
    }

    try pack.pack(pack.IdRect, ctx, current_rects, .{ .assume_capacity = true, .sortLessThanFn = packSort });

    var data = try arena.allocator().alloc(AtlasData, len);

    var dominant_colors = try arena.allocator().alloc(RGBA, len);
    @memset(dominant_colors, RGBA{});

    var color_counts: std.AutoHashMapUnmanaged(RGBA, u32) = .{};
    defer color_counts.deinit(arena.allocator());

    for (0..len) |i| {
        const id_rect = current_rects[i];
        const rect = id_rect.rect;
        const idx: usize = @intCast(id_rect.id);
        const pos = current_positions[idx];
        if (rect.w <= 0 or rect.h <= 0) {
            data[idx] = .fromRaw(0, 0, 0, 0, .base);
            continue;
        }

        const cur_atlas_x: u32 = @intCast(rect.x + padding);
        const cur_atlas_y: u32 = @intCast(rect.y + padding);

        color_counts.clearRetainingCapacity();

        const w: u32 = @intCast(rect.w - padding * 2);
        const h: u32 = @intCast(rect.h - padding * 2);
        for (0..h) |j| {
            const atlas_idx = ((cur_atlas_y + j) * atlas_width + cur_atlas_x) * 4;
            const src_idx = ((pos.y + j) * img.width + pos.x) * 4;
            @memcpy(atlas.data[atlas_idx .. atlas_idx + w * 4], img.data[src_idx .. src_idx + w * 4]);

            for (0..w) |k| {
                const x_offset = k * 4;
                if (img.data[src_idx + 3 + x_offset] > 0) {
                    const rgba: RGBA = .{
                        .r = img.data[src_idx + x_offset],
                        .g = img.data[src_idx + 1 + x_offset],
                        .b = img.data[src_idx + 2 + x_offset],
                        .a = 255,
                    };
                    if (color_counts.get(rgba)) |count| {
                        try color_counts.put(arena.allocator(), rgba, count + 1);
                    } else {
                        try color_counts.put(arena.allocator(), rgba, 1);
                    }
                }
            }
        }

        var colors: std.ArrayListUnmanaged(u32) = .empty;
        defer colors.deinit(arena.allocator());

        var max: u32 = 0;
        var count_iter = color_counts.iterator();
        while (count_iter.next()) |entry| {
            try colors.append(arena.allocator(), @as(u32, @intCast(entry.key_ptr.r)) << 16 |
                @as(u32, @intCast(entry.key_ptr.g)) << 8 |
                @as(u32, @intCast(entry.key_ptr.b)));

            if (entry.value_ptr.* > max) {
                dominant_colors[idx] = entry.key_ptr.*;
                max = entry.value_ptr.*;
            }
        }

        data[idx] = .fromRaw(rect.x, rect.y, rect.w, rect.h, .base);
        try atlas_to_color_data.put(arena.allocator(), @bitCast(data[idx]), try arena.allocator().dupe(u32, colors.items));
    }

    try atlas_data.put(arena.allocator(), sheet_name, data);
    try dominant_color_data.put(arena.allocator(), sheet_name, dominant_colors);
}

fn addUiImage(
    sheet_name: []const u8,
    image_path: []const u8,
    cut_width_base: u32,
    cut_height_base: u32,
    ctx: *pack.Context,
) !void {
    if (ui_atlas_data.contains(sheet_name)) std.debug.panic("\"{s}\" is already present in UI atlas data", .{sheet_name});

    if (std.mem.indexOf(u8, image_path, "..") != null) {
        std.log.err("Going backwards in paths is not allowed. Problematic path: {s}", .{image_path});
        std.posix.exit(0);
    }
    var buf: [128]u8 = undefined;
    const path = try std.fmt.bufPrintZ(&buf, "./assets/ui/{s}", .{image_path});
    var img: zstbi.Image = try .loadFromFile(path, 4);
    defer img.deinit();

    const cut_width = if (cut_width_base == UiSheet.imply_size) img.width else cut_width_base;
    const cut_height = if (cut_height_base == UiSheet.imply_size) img.height else cut_height_base;

    const len = std.math.divExact(u32, img.width * img.height, cut_width * cut_height) catch
        std.debug.panic("Sheet {s} has an incorrect resolution: {}x{} (cut_w={}, cut_h={})", .{ sheet_name, img.width, img.height, cut_width, cut_height });

    var current_rects = try arena.allocator().alloc(pack.IdRect, len);
    defer arena.allocator().free(current_rects);

    var current_positions = try arena.allocator().alloc(Position, len);
    defer arena.allocator().free(current_positions);

    var data = try arena.allocator().alloc(AtlasData, len);

    for (0..len) |i| {
        const cur_src_x = (i * cut_width) % img.width;
        const cur_src_y = @divFloor(i * cut_width, img.width) * cut_height;
        const bounds = imageBounds(img, cur_src_x, cur_src_y, cut_width, cut_height);
        current_positions[i].x = @intCast(cur_src_x + bounds.x_offset);
        current_positions[i].y = @intCast(cur_src_y + bounds.y_offset);
        current_rects[i].rect.w = @intCast(bounds.w + padding * 2);
        current_rects[i].rect.h = @intCast(bounds.h + padding * 2);
        current_rects[i].id = @intCast(i);
    }

    try pack.pack(pack.IdRect, ctx, current_rects, .{ .assume_capacity = true, .sortLessThanFn = packSort });

    for (0..len) |i| {
        const id_rect = current_rects[i];
        const rect = id_rect.rect;
        const idx: usize = @intCast(id_rect.id);
        const pos = current_positions[idx];
        if (rect.w <= 0 or rect.h <= 0) {
            data[idx] = .fromRaw(rect.x, rect.y, rect.w, rect.h, .ui);
            continue;
        }

        const cur_atlas_x: u32 = @intCast(rect.x + padding);
        const cur_atlas_y: u32 = @intCast(rect.y + padding);
        const w: u32 = @intCast(rect.w - padding * 2);
        const h: u32 = @intCast(rect.h - padding * 2);
        for (0..h) |j| {
            const atlas_idx = ((cur_atlas_y + j) * atlas_width + cur_atlas_x) * 4;
            const src_idx = ((pos.y + j) * img.width + pos.x) * 4;
            @memcpy(ui_atlas.data[atlas_idx .. atlas_idx + w * 4], img.data[src_idx .. src_idx + w * 4]);
        }

        data[idx] = .fromRaw(rect.x, rect.y, rect.w, rect.h, .ui);
    }

    try ui_atlas_data.put(arena.allocator(), sheet_name, data);
}

fn addAnimEnemy(
    sheet_name: []const u8,
    image_path: []const u8,
    cut_width: u32,
    cut_height: u32,
    ctx: *pack.Context,
) !void {
    if (anim_enemies.contains(sheet_name)) std.debug.panic("\"{s}\" is already present in animated enemy data", .{sheet_name});

    if (std.mem.indexOf(u8, image_path, "..") != null) {
        std.log.err("Going backwards in paths is not allowed. Problematic path: {s}", .{image_path});
        std.posix.exit(0);
    }
    var buf: [128]u8 = undefined;
    const path = try std.fmt.bufPrintZ(&buf, "./assets/sheets/{s}", .{image_path});
    var img: zstbi.Image = try .loadFromFile(path, 4);
    defer img.deinit();

    const len = @divExact(std.math.divExact(u32, img.width * img.height, cut_width * cut_height) catch
        std.debug.panic(
            "Sheet {s} has an incorrect resolution: {}x{} (cut_w={}, cut_h={})",
            .{ sheet_name, img.width, img.height, cut_width, cut_height },
        ), 6) * 5 * AnimEnemyData.directions;

    var current_rects = try arena.allocator().alloc(pack.IdRect, len);
    defer arena.allocator().free(current_rects);

    var current_positions = try arena.allocator().alloc(Position, len);
    defer arena.allocator().free(current_positions);

    var left_sub: u32 = 0;
    for (0..len) |i| {
        const frame_idx = i % 5;
        const set_idx = @divFloor(i, 5);
        const cur_src_x = frame_idx * cut_width;
        if (set_idx % 2 == 1 and frame_idx == 0) {
            left_sub += 1;
        }

        const cur_src_y = (set_idx - left_sub) * cut_height;
        const attack_scale = @as(u32, @intFromBool(frame_idx == 4)) + 1;
        const bounds = imageBounds(img, cur_src_x, cur_src_y, cut_width * attack_scale, cut_height);

        current_positions[i].x = @intCast(cur_src_x);
        current_positions[i].y = @intCast(cur_src_y);
        if (bounds.w == 0 or bounds.h == 0) {
            current_rects[i].rect.w = 0;
            current_rects[i].rect.h = 0;
        } else {
            current_rects[i].rect.w = @intCast(cut_width * attack_scale + padding * 2);
            current_rects[i].rect.h = @intCast(cut_height + padding * 2);
        }
        current_rects[i].id = @intCast(i);
    }

    try pack.pack(pack.IdRect, ctx, current_rects, .{ .assume_capacity = true, .sortLessThanFn = packSort });

    const enemy_data = try arena.allocator().alloc(AnimEnemyData, @divFloor(len, 5));

    var dominant_colors = try arena.allocator().alloc(RGBA, len);
    @memset(dominant_colors, RGBA{});

    var color_counts: std.AutoHashMapUnmanaged(RGBA, u32) = .{};
    defer color_counts.deinit(arena.allocator());

    for (0..len) |i| {
        const id_rect = current_rects[i];
        const rect = id_rect.rect;
        const idx: usize = @intCast(id_rect.id);
        const pos = current_positions[idx];

        color_counts.clearRetainingCapacity();

        const data: AtlasData = .fromRaw(rect.x, rect.y, rect.w, rect.h, .base);
        const frame_idx = idx % 5;
        const set_idx = @divFloor(idx, 5);
        const data_idx = @divFloor(set_idx, 2);
        const dir_idx = set_idx % 2;
        if (frame_idx >= 3) {
            enemy_data[data_idx].attack_anims[dir_idx * AnimEnemyData.attack_actions + frame_idx - AnimEnemyData.walk_actions] = data;
        } else {
            enemy_data[data_idx].walk_anims[dir_idx * AnimEnemyData.walk_actions + frame_idx] = data;
        }

        if (rect.w <= 0 or rect.h <= 0)
            continue;

        const cur_atlas_x: u32 = @intCast(rect.x + padding);
        const cur_atlas_y: u32 = @intCast(rect.y + padding);
        const w: u32 = @intCast(rect.w - padding * 2);
        const h: u32 = @intCast(rect.h - padding * 2);

        for (0..w * h) |k| {
            const row_count = @divFloor(k, w);
            const row_idx = k % w;
            const atlas_idx = ((cur_atlas_y + row_count) * atlas_width + cur_atlas_x + row_idx) * 4;

            const src_idx = if (dir_idx == @intFromEnum(Direction.left))
                ((pos.y + row_count) * img.width + pos.x + w - row_idx - 1) * 4
            else
                ((pos.y + row_count) * img.width + pos.x + row_idx) * 4;

            @memcpy(atlas.data[atlas_idx .. atlas_idx + 4], img.data[src_idx .. src_idx + 4]);

            if (img.data[src_idx + 3] > 0) {
                const rgba: RGBA = .{
                    .r = img.data[src_idx],
                    .g = img.data[src_idx + 1],
                    .b = img.data[src_idx + 2],
                    .a = 255,
                };
                if (color_counts.get(rgba)) |count| {
                    try color_counts.put(arena.allocator(), rgba, count + 1);
                } else {
                    try color_counts.put(arena.allocator(), rgba, 1);
                }
            }
        }

        var colors: std.ArrayListUnmanaged(u32) = .empty;
        defer colors.deinit(arena.allocator());

        var max: u32 = 0;
        var count_iter = color_counts.iterator();
        while (count_iter.next()) |entry| {
            try colors.append(arena.allocator(), @as(u32, @intCast(entry.key_ptr.r)) << 16 |
                @as(u32, @intCast(entry.key_ptr.g)) << 8 |
                @as(u32, @intCast(entry.key_ptr.b)));

            if (entry.value_ptr.* > max) {
                dominant_colors[set_idx] = entry.key_ptr.*;
                max = entry.value_ptr.*;
            }
        }

        try atlas_to_color_data.put(arena.allocator(), @bitCast(data), try arena.allocator().dupe(u32, colors.items));
    }

    try anim_enemies.put(arena.allocator(), sheet_name, enemy_data);
    try dominant_color_data.put(arena.allocator(), sheet_name, dominant_colors);
}

fn addAnimPlayer(
    sheet_name: []const u8,
    image_path: []const u8,
    cut_width: u32,
    cut_height: u32,
    ctx: *pack.Context,
) !void {
    if (anim_players.contains(sheet_name)) std.debug.panic("\"{s}\" is already present in animated player data", .{sheet_name});

    if (std.mem.indexOf(u8, image_path, "..") != null) {
        std.log.err("Going backwards in paths is not allowed. Problematic path: {s}", .{image_path});
        std.posix.exit(0);
    }
    var buf: [128]u8 = undefined;
    const path = try std.fmt.bufPrintZ(&buf, "./assets/sheets/{s}", .{image_path});
    var img: zstbi.Image = try .loadFromFile(path, 4);
    defer img.deinit();

    var len = @divExact(std.math.divExact(u32, img.width * img.height, cut_width * cut_height) catch
        std.debug.panic(
            "Sheet {s} has an incorrect resolution: {}x{} (cut_w={}, cut_h={})",
            .{ sheet_name, img.width, img.height, cut_width, cut_height },
        ), 6) * 5;
    len += @divFloor(len, 3); // for the "missing" left side

    var current_rects = try arena.allocator().alloc(pack.IdRect, len);
    defer arena.allocator().free(current_rects);

    var current_positions = try arena.allocator().alloc(Position, len);
    defer arena.allocator().free(current_positions);

    var left_sub: u32 = 0;
    for (0..len) |i| {
        const frame_idx = i % 5;
        const set_idx = @divFloor(i, 5);
        const cur_src_x = frame_idx * cut_width;
        if (set_idx % 4 == 1 and frame_idx == 0) {
            left_sub += 1;
        }

        const cur_src_y = (set_idx - left_sub) * cut_height;
        const attack_scale = @as(u32, @intFromBool(frame_idx == 4)) + 1;
        const bounds = imageBounds(img, cur_src_x, cur_src_y, cut_width * attack_scale, cut_height);
        current_positions[i].x = @intCast(cur_src_x);
        current_positions[i].y = @intCast(cur_src_y);
        if (bounds.w == 0 or bounds.h == 0) {
            current_rects[i].rect.w = 0;
            current_rects[i].rect.h = 0;
        } else {
            current_rects[i].rect.w = @intCast(cut_width * attack_scale + padding * 2);
            current_rects[i].rect.h = @intCast(cut_height + padding * 2);
        }
        current_rects[i].id = @intCast(i);
    }

    try pack.pack(pack.IdRect, ctx, current_rects, .{ .assume_capacity = true, .sortLessThanFn = packSort });

    left_sub = 0;

    const player_data = try arena.allocator().alloc(AnimPlayerData, @divFloor(len, 5 * 4));

    var dominant_colors = try arena.allocator().alloc(RGBA, len);
    @memset(dominant_colors, RGBA{});

    var color_counts: std.AutoHashMapUnmanaged(RGBA, u32) = .{};
    defer color_counts.deinit(arena.allocator());

    for (0..len) |j| {
        const id_rect = current_rects[j];
        const rect = id_rect.rect;
        const idx: usize = @intCast(id_rect.id);
        const pos = current_positions[idx];

        color_counts.clearRetainingCapacity();

        const data = AtlasData.fromRaw(rect.x, rect.y, rect.w, rect.h, .base);
        const frame_idx = idx % 5;
        const set_idx = @divFloor(idx, 5);
        if (set_idx % 4 == 1 and frame_idx == 0) {
            left_sub += 1;
        }

        const data_idx = @divFloor(set_idx, 4);
        const dir_idx = set_idx % 4;
        if (frame_idx >= 3) {
            player_data[data_idx].attack_anims[dir_idx * AnimPlayerData.attack_actions + frame_idx - AnimEnemyData.walk_actions] = data;
        } else {
            player_data[data_idx].walk_anims[dir_idx * AnimPlayerData.walk_actions + frame_idx] = data;
        }

        if (rect.w <= 0 or rect.h <= 0)
            continue;

        const cur_atlas_x: u32 = @intCast(rect.x + padding);
        const cur_atlas_y: u32 = @intCast(rect.y + padding);
        const w: u32 = @intCast(rect.w - padding * 2);
        const h: u32 = @intCast(rect.h - padding * 2);

        for (0..w * h) |k| {
            const row_count = @divFloor(k, w);
            const row_idx = k % w;
            const atlas_idx = ((cur_atlas_y + row_count) * atlas_width + cur_atlas_x + row_idx) * 4;

            const src_idx = if (set_idx % 4 == @intFromEnum(Direction.left))
                ((pos.y + row_count) * img.width + pos.x + w - row_idx - 1) * 4
            else
                ((pos.y + row_count) * img.width + pos.x + row_idx) * 4;

            @memcpy(atlas.data[atlas_idx .. atlas_idx + 4], img.data[src_idx .. src_idx + 4]);

            if (img.data[src_idx + 3] > 0) {
                const rgba: RGBA = .{
                    .r = img.data[src_idx],
                    .g = img.data[src_idx + 1],
                    .b = img.data[src_idx + 2],
                    .a = 255,
                };
                if (color_counts.get(rgba)) |count| {
                    try color_counts.put(arena.allocator(), rgba, count + 1);
                } else {
                    try color_counts.put(arena.allocator(), rgba, 1);
                }
            }
        }

        var colors: std.ArrayListUnmanaged(u32) = .empty;
        defer colors.deinit(arena.allocator());

        var max: u32 = 0;
        var count_iter = color_counts.iterator();
        while (count_iter.next()) |entry| {
            try colors.append(arena.allocator(), @as(u32, entry.key_ptr.r) << 16 |
                @as(u32, entry.key_ptr.g) << 8 |
                @as(u32, entry.key_ptr.b));

            if (entry.value_ptr.* > max) {
                dominant_colors[set_idx] = entry.key_ptr.*;
                max = entry.value_ptr.*;
            }
        }

        try atlas_to_color_data.put(arena.allocator(), @bitCast(data), try arena.allocator().dupe(u32, colors.items));
    }

    try anim_players.put(arena.allocator(), sheet_name, player_data);
    try dominant_color_data.put(arena.allocator(), sheet_name, dominant_colors);
}

fn parseFontData(comptime path: []const u8) !ParsedFontData {
    const arena_allocator = arena.allocator();

    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const file_data = try file.readToEndAllocOptions(arena_allocator, std.math.maxInt(u32), null, @alignOf(u8), 0);
    defer arena_allocator.free(file_data);

    const font_data = try ziggy.parseLeaky(InternalFontData, arena_allocator, file_data, .{});

    const empty_char: CharacterData = .{
        .x_advance = 0.0,
        .tex_u = 0.0,
        .tex_v = 0.0,
        .tex_w = 0.0,
        .tex_h = 0.0,
        .x_offset = 0.0,
        .y_offset = 0.0,
        .width = 0.0,
        .height = 0.0,
    };
    var ret: ParsedFontData = .{
        .characters = @splat(empty_char),
        .size = font_data.atlas.size,
        .padding = 8.0,
        .px_range = font_data.atlas.distance_range,
        .line_height = font_data.metrics.line_height,
        .width = font_data.atlas.width,
        .height = font_data.atlas.height,
    };
    for (font_data.glyphs) |glyph| ret.characters[glyph.unicode] = try .parse(glyph, ret.size, ret.width, ret.height);
    return ret;
}

pub fn playSfx(name: []const u8) void {
    if (main.settings.sfx_volume <= 0.0) return;
    if (audio_state == null) {
        audio_state = AudioState.create() catch {
            main.audioFailure();
            return;
        };
        audio_state.?.engine.start() catch {
            main.audioFailure();
            return;
        };

        initMusic: {
            main_music = audio_state.?.engine.createSoundFromFile("./assets/music/main_menu.mp3", .{}) catch break :initMusic;
            main_music.?.setLooping(true);
            main_music.?.setVolume(main.settings.music_volume);
            if (main.settings.music_volume > 0.0) main_music.?.start() catch main.audioFailure();
        }
    }

    if (sfx_map.get(name)) |audio| {
        if (!audio.isPlaying()) {
            audio.setVolume(main.settings.sfx_volume);
            audio.start() catch return;
            return;
        }

        var audio_copies = sfx_copy_map.get(audio);
        if (audio_copies == null)
            audio_copies = .empty;

        for (audio_copies.?.items) |copy_audio| {
            if (!copy_audio.isPlaying()) {
                copy_audio.setVolume(main.settings.sfx_volume);
                copy_audio.start() catch return;
                return;
            }
        }

        var new_copy_audio = audio_state.?.engine.createSoundCopy(audio, .{}, null) catch return;
        new_copy_audio.setVolume(main.settings.sfx_volume);
        new_copy_audio.start() catch return;
        audio_copies.?.append(arena.allocator(), new_copy_audio) catch return;
        sfx_copy_map.put(arena.allocator(), audio, audio_copies.?) catch return;
        return;
    }

    const path = std.fmt.bufPrintZ(&sfx_path_buffer, "./assets/sfx/{s}", .{name}) catch return;

    if (std.fs.cwd().access(path, .{})) |_| {
        var audio = audio_state.?.engine.createSoundFromFile(path, .{}) catch return;
        audio.setVolume(main.settings.sfx_volume);
        audio.start() catch return;

        sfx_map.put(arena.allocator(), name, audio) catch return;
    } else |_| {
        // TODO: maybe an actual unknown sound? can't imagine debugging this being great with users
        if (!std.mem.eql(u8, name, "Unknown.mp3")) {
            std.log.err("Could not find sound effect for \"{s}\"", .{name});
            playSfx("error.mp3");
        }
    }
}

pub fn deinit() void {
    if (main_music) |music| music.destroy();
    var copy_audio_iter = sfx_copy_map.valueIterator();
    while (copy_audio_iter.next()) |copy_audio_list| for (copy_audio_list.items) |copy_audio| copy_audio.*.destroy();
    var audio_iter = sfx_map.valueIterator();
    while (audio_iter.next()) |audio| audio.*.destroy();
    if (audio_state) |state| state.destroy();

    default_cursor_pressed.destroy();
    default_cursor.destroy();
    royal_cursor_pressed.destroy();
    royal_cursor.destroy();
    ranger_cursor_pressed.destroy();
    ranger_cursor.destroy();
    aztec_cursor_pressed.destroy();
    aztec_cursor.destroy();
    fiery_cursor_pressed.destroy();
    fiery_cursor.destroy();
    target_enemy_cursor_pressed.destroy();
    target_enemy_cursor.destroy();
    target_ally_cursor_pressed.destroy();
    target_ally_cursor.destroy();

    arena.deinit();
}

pub fn init() !void {
    arena = .init(main.allocator);
    const arena_allocator = arena.allocator();

    defer {
        const dummy_string_ctx: std.hash_map.StringContext = undefined;
        if (sfx_map.capacity() > 0) sfx_map.rehash(dummy_string_ctx);
        if (dominant_color_data.capacity() > 0) dominant_color_data.rehash(dummy_string_ctx);
        if (atlas_data.capacity() > 0) atlas_data.rehash(dummy_string_ctx);
        if (ui_atlas_data.capacity() > 0) ui_atlas_data.rehash(dummy_string_ctx);
        if (anim_enemies.capacity() > 0) anim_enemies.rehash(dummy_string_ctx);
        if (anim_players.capacity() > 0) anim_players.rehash(dummy_string_ctx);

        const dummy_sfx_ctx: std.hash_map.AutoContext(*zaudio.Sound) = undefined;
        if (sfx_copy_map.capacity() > 0) sfx_copy_map.rehash(dummy_sfx_ctx);

        const dummy_atlas_ctx: std.hash_map.AutoContext(u160) = undefined;
        if (atlas_to_color_data.capacity() > 0) atlas_to_color_data.rehash(dummy_atlas_ctx);

        const dummy_button_ctx: std.hash_map.AutoContext(Settings.Button) = undefined;
        if (key_tex_map.capacity() > 0) key_tex_map.rehash(dummy_button_ctx);
    }

    bold_atlas = try .loadFromFile("./assets/fonts/amaranth_bold.png", 4);
    bold_italic_atlas = try .loadFromFile("./assets/fonts/amaranth_bold_italic.png", 4);
    medium_atlas = try .loadFromFile("./assets/fonts/amaranth_regular.png", 4);
    medium_italic_atlas = try .loadFromFile("./assets/fonts/amaranth_italic.png", 4);

    bold_data = try parseFontData("./assets/fonts/amaranth_bold.ziggy");
    bold_italic_data = try parseFontData("./assets/fonts/amaranth_bold_italic.ziggy");
    medium_data = try parseFontData("./assets/fonts/amaranth_regular.ziggy");
    medium_italic_data = try parseFontData("./assets/fonts/amaranth_italic.ziggy");

    audio_state = AudioState.create() catch blk: {
        main.audioFailure();
        break :blk null;
    };
    if (audio_state) |state| {
        state.engine.start() catch main.audioFailure();

        main_music = state.engine.createSoundFromFile("./assets/music/main_menu.mp3", .{}) catch null;
        if (main_music) |music| {
            music.setLooping(true);
            music.setVolume(main.settings.music_volume);
            if (main.settings.music_volume > 0.0) music.start() catch main.audioFailure();
        }
    }

    try addCursors("cursors.png", 32, 32);

    atlas = try .createEmpty(atlas_width, atlas_height, 4, .{});
    var ctx: pack.Context = try .create(main.allocator, atlas_width, atlas_height, .{ .spaces_to_prealloc = 4096 });
    defer ctx.deinit();

    ui_atlas = try .createEmpty(ui_atlas_width, ui_atlas_height, 4, .{});
    var ui_ctx: pack.Context = try .create(main.allocator, ui_atlas_width, ui_atlas_height, .{ .spaces_to_prealloc = 4096 });
    defer ui_ctx.deinit();

    const game_sheets_data = try std.fs.cwd().openFile("./assets/sheets/game_sheets.ziggy", .{});
    defer game_sheets_data.close();

    const game_sheets_file_data = try game_sheets_data.readToEndAllocOptions(arena_allocator, std.math.maxInt(u32), null, @alignOf(u8), 0);

    for (try ziggy.parseLeaky([]GameSheet, arena_allocator, game_sheets_file_data, .{})) |game_sheet| {
        switch (game_sheet.type) {
            .image => try addImage(
                game_sheet.name,
                game_sheet.path,
                game_sheet.w,
                game_sheet.h,
                game_sheet.dont_trim,
                &ctx,
            ),
            .anim_enemy => try addAnimEnemy(
                game_sheet.name,
                game_sheet.path,
                game_sheet.w,
                game_sheet.h,
                &ctx,
            ),
            .anim_player => try addAnimPlayer(
                game_sheet.name,
                game_sheet.path,
                game_sheet.w,
                game_sheet.h,
                &ctx,
            ),
        }
    }

    const wall_sheets_file = try std.fs.cwd().openFile("./assets/sheets/wall_sheets.ziggy", .{});
    defer wall_sheets_file.close();

    const wall_sheets_file_data = try wall_sheets_file.readToEndAllocOptions(arena_allocator, std.math.maxInt(u32), null, @alignOf(u8), 0);

    for (try ziggy.parseLeaky([]WallSheet, arena_allocator, wall_sheets_file_data, .{})) |wall_sheet|
        try addWall(
            wall_sheet.name,
            wall_sheet.path,
            wall_sheet.full_w,
            wall_sheet.full_h,
            wall_sheet.w,
            wall_sheet.h,
            &ctx,
        );

    const ui_sheets_data = try std.fs.cwd().openFile("./assets/ui/ui_sheets.ziggy", .{});
    defer ui_sheets_data.close();

    const ui_sheets_file_data = try ui_sheets_data.readToEndAllocOptions(arena_allocator, std.math.maxInt(u32), null, @alignOf(u8), 0);

    for (try ziggy.parseLeaky([]UiSheet, arena_allocator, ui_sheets_file_data, .{})) |ui_sheet|
        try addUiImage(ui_sheet.name, ui_sheet.path, ui_sheet.w, ui_sheet.h, &ui_ctx);

    if (ui_atlas_data.get("minimap_icons")) |icons| minimap_icons = icons else @panic("minimap_icons not found in UI atlas");

    if (atlas_data.get("light")) |light| {
        light_data = light[0];
    } else @panic("Could not find light in the atlas");

    if (atlas_data.get("ground_masks")) |ground_masks| {
        var left_mask_rect = ground_masks[0];
        left_mask_rect.removePadding();

        var top_mask_rect = ground_masks[1];
        top_mask_rect.removePadding();

        var right_mask_rect = ground_masks[2];
        right_mask_rect.removePadding();

        var bottom_mask_rect = ground_masks[3];
        bottom_mask_rect.removePadding();

        left_mask_uv = .{ left_mask_rect.tex_u, left_mask_rect.tex_v };
        top_mask_uv = .{ top_mask_rect.tex_u, top_mask_rect.tex_v };
        right_mask_uv = .{ right_mask_rect.tex_u, right_mask_rect.tex_v };
        bottom_mask_uv = .{ bottom_mask_rect.tex_u, bottom_mask_rect.tex_v };
    } else @panic("Could not find ground_masks in the atlas");

    if (atlas_data.get("generic_8x8")) |backfaces| {
        generic_8x8 = backfaces[0];
        generic_8x8.removePadding();
    } else @panic("Could not find generic_8x8 in the atlas");

    if (atlas_data.get("particles")) |particles| {
        particle = particles[0];
    } else @panic("Could not find particle in the atlas");

    if (atlas_data.get("bars")) |bars| {
        hp_bar_data = bars[0];
        mp_bar_data = bars[1];
        empty_bar_data = bars[2];
    } else std.debug.panic("Could not find bars in the atlas", .{});

    if (atlas_data.get("error_texture")) |error_tex| {
        error_data = error_tex[0];
        error_data_enemy = .{ .walk_anims = @splat(error_data), .attack_anims = @splat(error_data) };
        error_data_player = .{ .walk_anims = @splat(error_data), .attack_anims = @splat(error_data) };
        error_data_wall = .{
            .base = error_data,
            .left_outline = error_data,
            .right_outline = error_data,
            .top_outline = error_data,
            .bottom_outline = error_data,
        };
    } else @panic("Could not find error_texture in the atlas");

    if (anim_players.get("bloodfont_demon")) |bloodfont| {
        bloodfont_data = bloodfont[0];
    } else @panic("Could not find bloodfont_demon in the atlas");

    populateKeyMap();
    interact_key_tex = getKeyTexture(main.settings.interact);
}

fn populateKeyMap() void {
    const arena_allocator = arena.allocator();
    inline for (.{
        .{ Settings.Button{ .mouse = .left }, 46 },
        .{ Settings.Button{ .mouse = .right }, 59 },
        .{ Settings.Button{ .mouse = .middle }, 58 },
        .{ Settings.Button{ .mouse = .four }, 108 },
        .{ Settings.Button{ .mouse = .five }, 109 },
        .{ Settings.Button{ .key = .zero }, 0 },
        .{ Settings.Button{ .key = .one }, 4 },
        .{ Settings.Button{ .key = .two }, 5 },
        .{ Settings.Button{ .key = .three }, 6 },
        .{ Settings.Button{ .key = .four }, 7 },
        .{ Settings.Button{ .key = .five }, 8 },
        .{ Settings.Button{ .key = .six }, 16 },
        .{ Settings.Button{ .key = .seven }, 17 },
        .{ Settings.Button{ .key = .eight }, 18 },
        .{ Settings.Button{ .key = .nine }, 19 },
        .{ Settings.Button{ .key = .kp_0 }, 91 },
        .{ Settings.Button{ .key = .kp_1 }, 92 },
        .{ Settings.Button{ .key = .kp_2 }, 93 },
        .{ Settings.Button{ .key = .kp_3 }, 94 },
        .{ Settings.Button{ .key = .kp_4 }, 95 },
        .{ Settings.Button{ .key = .kp_5 }, 96 },
        .{ Settings.Button{ .key = .kp_6 }, 97 },
        .{ Settings.Button{ .key = .kp_7 }, 98 },
        .{ Settings.Button{ .key = .kp_8 }, 99 },
        .{ Settings.Button{ .key = .kp_9 }, 100 },
        .{ Settings.Button{ .key = .F1 }, 68 },
        .{ Settings.Button{ .key = .F2 }, 69 },
        .{ Settings.Button{ .key = .F3 }, 70 },
        .{ Settings.Button{ .key = .F4 }, 71 },
        .{ Settings.Button{ .key = .F5 }, 72 },
        .{ Settings.Button{ .key = .F6 }, 73 },
        .{ Settings.Button{ .key = .F7 }, 74 },
        .{ Settings.Button{ .key = .F8 }, 75 },
        .{ Settings.Button{ .key = .F9 }, 76 },
        .{ Settings.Button{ .key = .F10 }, 1 },
        .{ Settings.Button{ .key = .F11 }, 2 },
        .{ Settings.Button{ .key = .F12 }, 3 },
        .{ Settings.Button{ .key = .a }, 20 },
        .{ Settings.Button{ .key = .b }, 34 },
        .{ Settings.Button{ .key = .c }, 39 },
        .{ Settings.Button{ .key = .d }, 50 },
        .{ Settings.Button{ .key = .e }, 52 },
        .{ Settings.Button{ .key = .f }, 84 },
        .{ Settings.Button{ .key = .g }, 85 },
        .{ Settings.Button{ .key = .h }, 86 },
        .{ Settings.Button{ .key = .i }, 88 },
        .{ Settings.Button{ .key = .j }, 63 },
        .{ Settings.Button{ .key = .k }, 74 },
        .{ Settings.Button{ .key = .l }, 75 },
        .{ Settings.Button{ .key = .m }, 76 },
        .{ Settings.Button{ .key = .n }, 61 },
        .{ Settings.Button{ .key = .o }, 65 },
        .{ Settings.Button{ .key = .p }, 66 },
        .{ Settings.Button{ .key = .q }, 25 },
        .{ Settings.Button{ .key = .r }, 28 },
        .{ Settings.Button{ .key = .s }, 29 },
        .{ Settings.Button{ .key = .t }, 73 },
        .{ Settings.Button{ .key = .u }, 67 },
        .{ Settings.Button{ .key = .v }, 31 },
        .{ Settings.Button{ .key = .w }, 10 },
        .{ Settings.Button{ .key = .x }, 12 },
        .{ Settings.Button{ .key = .y }, 13 },
        .{ Settings.Button{ .key = .z }, 14 },
        .{ Settings.Button{ .key = .up }, 32 },
        .{ Settings.Button{ .key = .down }, 22 },
        .{ Settings.Button{ .key = .left }, 23 },
        .{ Settings.Button{ .key = .right }, 24 },
        .{ Settings.Button{ .key = .left_shift }, 15 },
        .{ Settings.Button{ .key = .right_shift }, 9 },
        .{ Settings.Button{ .key = .left_bracket }, 37 },
        .{ Settings.Button{ .key = .right_bracket }, 38 },
        .{ Settings.Button{ .key = .left_control }, 49 },
        .{ Settings.Button{ .key = .right_control }, 49 },
        .{ Settings.Button{ .key = .left_alt }, 21 },
        .{ Settings.Button{ .key = .right_alt }, 21 },
        .{ Settings.Button{ .key = .comma }, 101 },
        .{ Settings.Button{ .key = .period }, 102 },
        .{ Settings.Button{ .key = .slash }, 103 },
        .{ Settings.Button{ .key = .backslash }, 41 },
        .{ Settings.Button{ .key = .semicolon }, 30 },
        .{ Settings.Button{ .key = .minus }, 45 },
        .{ Settings.Button{ .key = .equal }, 42 },
        .{ Settings.Button{ .key = .tab }, 79 },
        .{ Settings.Button{ .key = .space }, 57 },
        .{ Settings.Button{ .key = .backspace }, 35 },
        .{ Settings.Button{ .key = .enter }, 54 },
        .{ Settings.Button{ .key = .delete }, 51 },
        .{ Settings.Button{ .key = .end }, 53 },
        .{ Settings.Button{ .key = .print_screen }, 44 },
        .{ Settings.Button{ .key = .insert }, 62 },
        .{ Settings.Button{ .key = .escape }, 64 },
        .{ Settings.Button{ .key = .home }, 87 },
        .{ Settings.Button{ .key = .page_up }, 89 },
        .{ Settings.Button{ .key = .page_down }, 90 },
        .{ Settings.Button{ .key = .caps_lock }, 40 },
        .{ Settings.Button{ .key = .kp_add }, 43 },
        .{ Settings.Button{ .key = .kp_subtract }, 107 },
        .{ Settings.Button{ .key = .kp_multiply }, 33 },
        .{ Settings.Button{ .key = .kp_divide }, 106 },
        .{ Settings.Button{ .key = .kp_decimal }, 105 },
        .{ Settings.Button{ .key = .kp_enter }, 56 },
        .{ Settings.Button{ .key = .left_super }, if (builtin.os.tag == .windows) 11 else 48 },
        .{ Settings.Button{ .key = .right_super }, if (builtin.os.tag == .windows) 11 else 48 },
    }) |key_with_idx|
        key_tex_map.put(arena_allocator, key_with_idx[0], key_with_idx[1]) catch main.oomPanic();
}

pub fn getKeyTexture(button: Settings.Button) AtlasData {
    const tex_list = ui_atlas_data.get("key_indicators") orelse @panic("Key texture parsing failed, the key_indicators sheet is missing");
    return tex_list[key_tex_map.get(button) orelse 104];
}

pub fn getUiData(name: []const u8, idx: u16) AtlasData {
    return (ui_atlas_data.get(name) orelse std.debug.panic("Could not find {s} in the UI atlas", .{name}))[idx];
}
