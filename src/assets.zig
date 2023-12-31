const xml = @import("xml.zig");
const zstbi = @import("zstbi");
const zstbrp = @import("zstbrp");
const asset_dir = @import("build_options").asset_dir;
const std = @import("std");
const game_data = @import("game_data.zig");
const settings = @import("settings.zig");
const builtin = @import("builtin");
const zaudio = @import("zaudio");
const main = @import("main.zig");
const zglfw = @import("zglfw");

pub const padding = 2;

pub const atlas_width: u32 = 2048;
pub const atlas_height: u32 = 1024;
pub const base_texel_w: f32 = 1.0 / 2048.0;
pub const base_texel_h: f32 = 1.0 / 1024.0;

pub const ui_atlas_width: u32 = 2048;
pub const ui_atlas_height: u32 = 1024;
pub const ui_texel_w: f32 = 1.0 / 2048.0;
pub const ui_texel_h: f32 = 1.0 / 1024.0;

pub const Action = enum {
    stand,
    walk,
    attack,
};

pub const Direction = enum {
    right,
    left,
    down,
    up,
};

pub const CharacterData = struct {
    pub const size = 64.0;
    pub const padding = 8.0;
    pub const padding_mult = 1.0 + CharacterData.padding * 2 / size;
    pub const line_height = 1.149;
    pub const px_range = 18.0;

    atlas_w: f32,
    atlas_h: f32,
    x_advance: f32,
    tex_u: f32,
    tex_v: f32,
    tex_w: f32,
    tex_h: f32,
    x_offset: f32,
    y_offset: f32,
    width: f32,
    height: f32,

    pub fn parse(split: *std.mem.SplitIterator(u8, .sequence), atlas_w: f32, atlas_h: f32) !CharacterData {
        var data = CharacterData{
            .atlas_w = atlas_w,
            .atlas_h = atlas_h,
            .x_advance = try std.fmt.parseFloat(f32, split.next().?) * size,
            .x_offset = try std.fmt.parseFloat(f32, split.next().?) * size,
            .y_offset = try std.fmt.parseFloat(f32, split.next().?) * size,
            .width = try std.fmt.parseFloat(f32, split.next().?) * size + CharacterData.padding * 2,
            .height = try std.fmt.parseFloat(f32, split.next().?) * size + CharacterData.padding * 2,
            .tex_u = (try std.fmt.parseFloat(f32, split.next().?) - CharacterData.padding) / atlas_w,
            .tex_h = (atlas_h - try std.fmt.parseFloat(f32, split.next().?) + CharacterData.padding * 2) / atlas_h,
            .tex_w = (try std.fmt.parseFloat(f32, split.next().?) + CharacterData.padding * 2) / atlas_w,
            .tex_v = (atlas_h - try std.fmt.parseFloat(f32, split.next().?) - CharacterData.padding) / atlas_h,
        };
        data.width -= data.x_offset;
        data.height -= data.y_offset;
        data.tex_h -= data.tex_v;
        data.tex_w -= data.tex_u;
        return data;
    }
};

pub const AnimEnemyData = struct {
    pub const directions = 2;
    pub const walk_actions = 3;
    pub const attack_actions = 2;

    walk_anims: [directions * walk_actions]AtlasData,
    attack_anims: [directions * attack_actions]AtlasData,
};

pub const AnimPlayerData = struct {
    pub const directions = 4;
    pub const walk_actions = 3;
    pub const attack_actions = 2;

    walk_anims: [directions * walk_actions]AtlasData,
    attack_anims: [directions * attack_actions]AtlasData,
};

pub const AtlasData = extern struct {
    tex_u: f32,
    tex_v: f32,
    tex_w: f32,
    tex_h: f32,
    ui: bool,

    pub fn removePadding(self: *AtlasData) void {
        const w: f32 = if (self.ui) ui_atlas_width else atlas_width;
        const h: f32 = if (self.ui) ui_atlas_height else atlas_height;
        const float_pad: f32 = padding;
        self.tex_u += float_pad / w;
        self.tex_v += float_pad / h;
        self.tex_w -= float_pad * 2 / w;
        self.tex_h -= float_pad * 2 / h;
    }

    pub inline fn fromRaw(u: u32, v: u32, w: u32, h: u32, ui: bool) AtlasData {
        return fromRawF32(@floatFromInt(u), @floatFromInt(v), @floatFromInt(w), @floatFromInt(h), ui);
    }

    pub inline fn fromRawF32(u: f32, v: f32, w: f32, h: f32, ui: bool) AtlasData {
        const atlas_w: f32 = if (ui) ui_atlas_width else atlas_width;
        const atlas_h: f32 = if (ui) ui_atlas_height else atlas_height;
        return AtlasData{
            .tex_u = u / atlas_w,
            .tex_v = v / atlas_h,
            .tex_w = w / atlas_w,
            .tex_h = h / atlas_h,
            .ui = ui,
        };
    }

    pub inline fn texURaw(self: AtlasData) f32 {
        const w: f32 = (if (self.ui) ui_atlas_width else atlas_width);
        return self.tex_u * w;
    }

    pub inline fn texVRaw(self: AtlasData) f32 {
        const h: f32 = (if (self.ui) ui_atlas_height else ui_atlas_height);
        return self.tex_v * h;
    }

    pub inline fn texWRaw(self: AtlasData) f32 {
        const w: f32 = (if (self.ui) ui_atlas_width else atlas_width);
        return self.tex_w * w;
    }

    pub inline fn texHRaw(self: AtlasData) f32 {
        const h: f32 = (if (self.ui) ui_atlas_height else ui_atlas_height);
        return self.tex_h * h;
    }
};

const AudioState = struct {
    device: *zaudio.Device,
    engine: *zaudio.Engine,

    fn audioCallback(
        device: *zaudio.Device,
        output: ?*anyopaque,
        _: ?*const anyopaque,
        num_frames: u32,
    ) callconv(.C) void {
        const audio = @as(*AudioState, @ptrCast(@alignCast(device.getUserData())));
        audio.engine.readPcmFrames(output.?, num_frames, null) catch {};
    }

    fn create(allocator: std.mem.Allocator) !*AudioState {
        const audio = try allocator.create(AudioState);

        const device = device: {
            var config = zaudio.Device.Config.init(.playback);
            config.data_callback = audioCallback;
            config.user_data = audio;
            config.sample_rate = 48000;
            config.period_size_in_frames = 480;
            config.period_size_in_milliseconds = 10;
            config.playback.format = .float32;
            config.playback.channels = 2;
            break :device try zaudio.Device.create(null, config);
        };

        const engine = engine: {
            var config = zaudio.Engine.Config.init();
            config.device = device;
            config.no_auto_start = .true32;
            break :engine try zaudio.Engine.create(config);
        };

        audio.* = .{
            .device = device,
            .engine = engine,
        };
        return audio;
    }

    fn destroy(audio: *AudioState, allocator: std.mem.Allocator) void {
        audio.engine.destroy();
        audio.device.destroy();
        allocator.destroy(audio);
    }
};

const RGBA = packed struct(u32) {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 0,
};

const AtlasHashHack = [5]u32;

pub var sfx_path_buffer: [256]u8 = undefined;
pub var audio_state: *AudioState = undefined;
pub var main_music: *zaudio.Sound = undefined;

pub var atlas: zstbi.Image = undefined;
pub var ui_atlas: zstbi.Image = undefined;
pub var light_tex: zstbi.Image = undefined;
pub var menu_background: zstbi.Image = undefined;

pub var bold_atlas: zstbi.Image = undefined;
pub var bold_chars: [256]CharacterData = undefined;
pub var bold_italic_atlas: zstbi.Image = undefined;
pub var bold_italic_chars: [256]CharacterData = undefined;
pub var medium_atlas: zstbi.Image = undefined;
pub var medium_chars: [256]CharacterData = undefined;
pub var medium_italic_atlas: zstbi.Image = undefined;
pub var medium_italic_chars: [256]CharacterData = undefined;

// horrible, but no other option since cursor is opaque
pub var default_cursor_pressed: *zglfw.Cursor = undefined;
pub var default_cursor: *zglfw.Cursor = undefined;
pub var royal_cursor_pressed: *zglfw.Cursor = undefined;
pub var royal_cursor: *zglfw.Cursor = undefined;
pub var ranger_cursor_pressed: *zglfw.Cursor = undefined;
pub var ranger_cursor: *zglfw.Cursor = undefined;
pub var aztec_cursor_pressed: *zglfw.Cursor = undefined;
pub var aztec_cursor: *zglfw.Cursor = undefined;
pub var fiery_cursor_pressed: *zglfw.Cursor = undefined;
pub var fiery_cursor: *zglfw.Cursor = undefined;
pub var target_enemy_cursor_pressed: *zglfw.Cursor = undefined;
pub var target_enemy_cursor: *zglfw.Cursor = undefined;
pub var target_ally_cursor_pressed: *zglfw.Cursor = undefined;
pub var target_ally_cursor: *zglfw.Cursor = undefined;

pub var sfx_copy_map: std.AutoHashMap(*zaudio.Sound, std.ArrayList(*zaudio.Sound)) = undefined;
pub var sfx_map: std.StringHashMap(*zaudio.Sound) = undefined;
pub var dominant_color_data: std.StringHashMap([]RGBA) = undefined;
pub var atlas_to_color_data: std.AutoHashMap(AtlasHashHack, []u32) = undefined;
pub var atlas_data: std.StringHashMap([]AtlasData) = undefined;
pub var ui_atlas_data: std.StringHashMap([]AtlasData) = undefined;
pub var anim_enemies: std.StringHashMap([]AnimEnemyData) = undefined;
pub var anim_players: std.StringHashMap([]AnimPlayerData) = undefined;

pub var left_top_mask_uv: [4]f32 = undefined;
pub var right_bottom_mask_uv: [4]f32 = undefined;
pub var wall_backface_data: AtlasData = undefined;
pub var empty_bar_data: AtlasData = undefined;
pub var hp_bar_data: AtlasData = undefined;
pub var mp_bar_data: AtlasData = undefined;
pub var particle_data: AtlasData = undefined;
pub var error_data: AtlasData = undefined;
pub var error_data_enemy: AnimEnemyData = undefined;
pub var error_data_player: AnimPlayerData = undefined;
pub var light_w: f32 = 1.0;
pub var light_h: f32 = 1.0;
pub var editor_tile: AtlasData = undefined;

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

fn addCursors(comptime image_name: [:0]const u8, comptime cut_width: u32, comptime cut_height: u32, allocator: std.mem.Allocator) !void {
    var img = try zstbi.Image.loadFromFile(asset_dir ++ "sheets/" ++ image_name, 4);
    defer img.deinit();

    const img_size = cut_width * cut_height;
    const len = @divFloor(img.width * img.height, img_size);

    for (0..len) |i| {
        const cur_src_x = (i * cut_width) % img.width;
        const cur_src_y = @divFloor(i * cut_width, img.width) * cut_height;

        var temp = try allocator.alloc(u8, img_size * 4);
        defer allocator.free(temp);

        for (0..img_size) |j| {
            const row_count = @divFloor(j, cut_width);
            const row_idx = j % cut_width;
            const target_idx = (row_count * cut_width + row_idx) * 4;
            const src_idx = ((cur_src_y + row_count) * img.width + cur_src_x + row_idx) * 4;
            @memcpy(temp[target_idx .. target_idx + 4], img.data[src_idx .. src_idx + 4]);
        }

        const cursor = try zglfw.Cursor.create(
            &zglfw.Image{ .w = cut_width, .h = cut_height, .pixels = @ptrCast(temp) },
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

fn addImage(
    comptime sheet_name: [:0]const u8,
    comptime image_name: [:0]const u8,
    comptime cut_width: u32,
    comptime cut_height: u32,
    comptime dont_trim: bool,
    ctx: *zstbrp.PackContext,
    allocator: std.mem.Allocator,
) !void {
    var img = try zstbi.Image.loadFromFile(asset_dir ++ "sheets/" ++ image_name, 4);
    defer img.deinit();

    const len = @divFloor(img.width * img.height, cut_width * cut_height);
    var current_rects = try allocator.alloc(zstbrp.PackRect, len);
    defer allocator.free(current_rects);

    for (0..len) |i| {
        const cur_src_x = (i * cut_width) % img.width;
        const cur_src_y = @divFloor(i * cut_width, img.width) * cut_height;
        const bounds = imageBounds(img, cur_src_x, cur_src_y, cut_width, cut_height);
        if (dont_trim) {
            current_rects[i].src_x = @intCast(cur_src_x);
            current_rects[i].src_y = @intCast(cur_src_y);
            if (bounds.w == 0 or bounds.h == 0) {
                current_rects[i].w = 0;
                current_rects[i].h = 0;
            } else {
                current_rects[i].w = cut_width + padding * 2;
                current_rects[i].h = cut_height + padding * 2;
            }
        } else {
            current_rects[i].src_x = @intCast(cur_src_x + bounds.x_offset);
            current_rects[i].src_y = @intCast(cur_src_y + bounds.y_offset);
            current_rects[i].w = bounds.w + padding * 2;
            current_rects[i].h = bounds.h + padding * 2;
        }
    }

    if (zstbrp.packRects(ctx, current_rects)) {
        var data = try allocator.alloc(AtlasData, len);

        var dominant_colors = try allocator.alloc(RGBA, len);
        @memset(dominant_colors, RGBA{});

        var color_counts = std.AutoHashMap(RGBA, u32).init(allocator);
        defer color_counts.deinit();

        for (0..len) |i| {
            const rect = current_rects[i];
            if (rect.w <= 0 or rect.h <= 0)
                continue;

            const cur_atlas_x = rect.x + padding;
            const cur_atlas_y = rect.y + padding;

            color_counts.clearRetainingCapacity();

            const w = rect.w - padding * 2;
            const h = rect.h - padding * 2;
            for (0..h) |j| {
                const atlas_idx = ((cur_atlas_y + j) * atlas_width + cur_atlas_x) * 4;
                const src_idx = ((rect.src_y + j) * img.width + rect.src_x) * 4;
                @memcpy(atlas.data[atlas_idx .. atlas_idx + w * 4], img.data[src_idx .. src_idx + w * 4]);

                for (0..w) |k| {
                    const x_offset = k * 4;
                    if (img.data[src_idx + 3 + x_offset] > 0) {
                        const rgba = RGBA{
                            .r = img.data[src_idx + x_offset],
                            .g = img.data[src_idx + 1 + x_offset],
                            .b = img.data[src_idx + 2 + x_offset],
                            .a = 255,
                        };
                        if (color_counts.get(rgba)) |count| {
                            try color_counts.put(rgba, count + 1);
                        } else {
                            try color_counts.put(rgba, 1);
                        }
                    }
                }
            }

            var colors = std.ArrayList(u32).init(allocator);
            defer colors.deinit();

            var max: u32 = 0;
            var count_iter = color_counts.iterator();
            while (count_iter.next()) |entry| {
                try colors.append(@as(u32, @intCast(entry.key_ptr.r)) << 16 |
                    @as(u32, @intCast(entry.key_ptr.g)) << 8 |
                    @as(u32, @intCast(entry.key_ptr.b)));

                if (entry.value_ptr.* > max) {
                    dominant_colors[i] = entry.key_ptr.*;
                    max = entry.value_ptr.*;
                }
            }

            data[i] = AtlasData.fromRaw(rect.x, rect.y, rect.w, rect.h, false);
            try atlas_to_color_data.put(@bitCast(data[i]), try allocator.dupe(u32, colors.items));
        }

        try atlas_data.put(sheet_name, data);
        try dominant_color_data.put(sheet_name, dominant_colors);
    } else {
        std.log.err("Could not pack " ++ image_name ++ " into the atlas", .{});
    }
}

fn addUiImage(
    comptime sheet_name: [:0]const u8,
    comptime image_name: [:0]const u8,
    comptime cut_width_base: u32,
    comptime cut_height_base: u32,
    ctx: *zstbrp.PackContext,
    allocator: std.mem.Allocator,
) !void {
    var img = try zstbi.Image.loadFromFile(asset_dir ++ image_name, 4);
    defer img.deinit();

    const imply_size = std.math.maxInt(u32);
    const cut_width = if (cut_width_base == imply_size) img.width else cut_width_base;
    const cut_height = if (cut_height_base == imply_size) img.height else cut_height_base;

    const len = @divFloor(img.width * img.height, cut_width * cut_height);
    var current_rects = try allocator.alloc(zstbrp.PackRect, len);
    defer allocator.free(current_rects);
    var data = try allocator.alloc(AtlasData, len);

    for (0..len) |i| {
        const cur_src_x = (i * cut_width) % img.width;
        const cur_src_y = @divFloor(i * cut_width, img.width) * cut_height;
        const bounds = imageBounds(img, cur_src_x, cur_src_y, cut_width, cut_height);
        current_rects[i].src_x = @intCast(cur_src_x + bounds.x_offset);
        current_rects[i].src_y = @intCast(cur_src_y + bounds.y_offset);
        current_rects[i].w = bounds.w + padding * 2;
        current_rects[i].h = bounds.h + padding * 2;
    }

    if (zstbrp.packRects(ctx, current_rects)) {
        for (0..len) |i| {
            const rect = current_rects[i];
            if (rect.w <= 0 or rect.h <= 0)
                continue;

            const cur_atlas_x = rect.x + padding;
            const cur_atlas_y = rect.y + padding;

            const w = rect.w - padding * 2;
            const h = rect.h - padding * 2;
            for (0..h) |j| {
                const atlas_idx = ((cur_atlas_y + j) * atlas_width + cur_atlas_x) * 4;
                const src_idx = ((rect.src_y + j) * img.width + rect.src_x) * 4;
                @memcpy(ui_atlas.data[atlas_idx .. atlas_idx + w * 4], img.data[src_idx .. src_idx + w * 4]);
            }

            data[i] = AtlasData.fromRaw(rect.x, rect.y, rect.w, rect.h, true);
        }

        try ui_atlas_data.put(sheet_name, data);
    } else {
        std.log.err("Could not pack " ++ image_name ++ " into the ui atlas", .{});
    }
}

fn addAnimEnemy(
    comptime sheet_name: [:0]const u8,
    comptime image_name: [:0]const u8,
    comptime cut_width: u32,
    comptime cut_height: u32,
    comptime full_cut_width: u32,
    comptime full_cut_height: u32,
    ctx: *zstbrp.PackContext,
    allocator: std.mem.Allocator,
) !void {
    var img = try zstbi.Image.loadFromFile(asset_dir ++ "sheets/" ++ image_name, 4);
    defer img.deinit();

    const len = @divFloor(img.width, full_cut_width) * @divFloor(img.height, full_cut_height) * 5;

    var current_rects = try allocator.alloc(zstbrp.PackRect, len * 2);
    defer allocator.free(current_rects);

    for (0..2) |i| {
        for (0..len) |j| {
            const cur_src_x = (j % 5) * cut_width;
            const cur_src_y = @divFloor(j, 5) * cut_height;
            const attack_scale = @as(u32, @intFromBool(j % 5 == 4)) + 1;
            const bounds = imageBounds(img, cur_src_x, cur_src_y, cut_width * attack_scale, cut_height);
            current_rects[i * len + j].src_x = @intCast(cur_src_x + bounds.x_offset);
            current_rects[i * len + j].src_y = @intCast(cur_src_y + bounds.y_offset);
            current_rects[i * len + j].w = bounds.w + padding * 2;
            current_rects[i * len + j].h = bounds.h + padding * 2;
        }
    }

    if (zstbrp.packRects(ctx, current_rects)) {
        const enemy_data = try allocator.alloc(AnimEnemyData, @divFloor(len, 5));

        var dominant_colors = try allocator.alloc(RGBA, len);
        @memset(dominant_colors, RGBA{});

        var color_counts = std.AutoHashMap(RGBA, u32).init(allocator);
        defer color_counts.deinit();

        for (0..2) |i| {
            for (0..len) |j| {
                const rect = current_rects[i * len + j];
                if (rect.w <= 0 or rect.h <= 0)
                    continue;

                color_counts.clearRetainingCapacity();

                const data = AtlasData.fromRaw(rect.x, rect.y, rect.w, rect.h, false);
                const frame_idx = j % 5;
                const set_idx = @divFloor(j, 5);
                if (frame_idx >= 3) {
                    const dir_idx = i * AnimEnemyData.attack_actions;
                    enemy_data[set_idx].attack_anims[dir_idx + frame_idx - 3] = data;
                } else {
                    const dir_idx = i * AnimEnemyData.walk_actions;
                    enemy_data[set_idx].walk_anims[dir_idx + frame_idx] = data;
                }

                const cur_atlas_x = rect.x + padding;
                const cur_atlas_y = rect.y + padding;
                const w = rect.w - padding * 2;
                const h = rect.h - padding * 2;

                for (0..w * h) |k| {
                    const row_count = @divFloor(k, w);
                    const row_idx = k % w;
                    const atlas_idx = ((cur_atlas_y + row_count) * atlas_width + cur_atlas_x + row_idx) * 4;

                    const src_idx = if (i == @intFromEnum(Direction.left))
                        ((rect.src_y + row_count) * img.width + rect.src_x + w - row_idx - 1) * 4
                    else
                        ((rect.src_y + row_count) * img.width + rect.src_x + row_idx) * 4;

                    @memcpy(atlas.data[atlas_idx .. atlas_idx + 4], img.data[src_idx .. src_idx + 4]);

                    if (img.data[src_idx + 3] > 0) {
                        const rgba = RGBA{
                            .r = img.data[src_idx],
                            .g = img.data[src_idx + 1],
                            .b = img.data[src_idx + 2],
                            .a = 255,
                        };
                        if (color_counts.get(rgba)) |count| {
                            try color_counts.put(rgba, count + 1);
                        } else {
                            try color_counts.put(rgba, 1);
                        }
                    }
                }

                var colors = std.ArrayList(u32).init(allocator);
                defer colors.deinit();

                var max: u32 = 0;
                var count_iter = color_counts.iterator();
                while (count_iter.next()) |entry| {
                    try colors.append(@as(u32, @intCast(entry.key_ptr.r)) << 16 |
                        @as(u32, @intCast(entry.key_ptr.g)) << 8 |
                        @as(u32, @intCast(entry.key_ptr.b)));

                    if (entry.value_ptr.* > max) {
                        dominant_colors[set_idx] = entry.key_ptr.*;
                        max = entry.value_ptr.*;
                    }
                }

                try atlas_to_color_data.put(@bitCast(data), try allocator.dupe(u32, colors.items));
            }
        }

        try anim_enemies.put(sheet_name, enemy_data);
        try dominant_color_data.put(sheet_name, dominant_colors);
    } else {
        std.log.err("Could not pack " ++ image_name ++ " into the atlas", .{});
    }
}

fn addAnimPlayer(
    comptime sheet_name: [:0]const u8,
    comptime image_name: [:0]const u8,
    comptime cut_width: u32,
    comptime cut_height: u32,
    comptime full_cut_width: u32,
    comptime full_cut_height: u32,
    ctx: *zstbrp.PackContext,
    allocator: std.mem.Allocator,
) !void {
    var img = try zstbi.Image.loadFromFile(asset_dir ++ "sheets/" ++ image_name, 4);
    defer img.deinit();

    var len = @divFloor(img.width, full_cut_width) * @divFloor(img.height, full_cut_height) * 5;
    len += @divFloor(len, 3);

    var current_rects = try allocator.alloc(zstbrp.PackRect, len);
    defer allocator.free(current_rects);

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
        current_rects[i].src_x = @intCast(cur_src_x + bounds.x_offset);
        current_rects[i].src_y = @intCast(cur_src_y + bounds.y_offset);
        current_rects[i].w = bounds.w + padding * 2;
        current_rects[i].h = bounds.h + padding * 2;
    }

    if (zstbrp.packRects(ctx, current_rects)) {
        left_sub = 0;

        const player_data = try allocator.alloc(AnimPlayerData, @divFloor(len, 5 * 4));

        var dominant_colors = try allocator.alloc(RGBA, len);
        @memset(dominant_colors, RGBA{});

        var color_counts = std.AutoHashMap(RGBA, u32).init(allocator);
        defer color_counts.deinit();

        for (0..len) |j| {
            const rect = current_rects[j];
            if (rect.w <= 0 or rect.h <= 0)
                continue;

            color_counts.clearRetainingCapacity();

            const data = AtlasData.fromRaw(rect.x, rect.y, rect.w, rect.h, false);
            const frame_idx = j % 5;
            const set_idx = @divFloor(j, 5);
            if (set_idx % 4 == 1 and frame_idx == 0) {
                left_sub += 1;
            }

            const data_idx = @divFloor(set_idx, 4);
            if (frame_idx >= 3) {
                const dir_idx = (set_idx % 4) * AnimPlayerData.attack_actions;
                player_data[data_idx].attack_anims[dir_idx + frame_idx - 3] = data;
            } else {
                const dir_idx = (set_idx % 4) * AnimPlayerData.walk_actions;
                player_data[data_idx].walk_anims[dir_idx + frame_idx] = data;
            }
            const cur_atlas_x = rect.x + padding;
            const cur_atlas_y = rect.y + padding;
            const w = rect.w - padding * 2;
            const h = rect.h - padding * 2;

            for (0..w * h) |k| {
                const row_count = @divFloor(k, w);
                const row_idx = k % w;
                const atlas_idx = ((cur_atlas_y + row_count) * atlas_width + cur_atlas_x + row_idx) * 4;

                const src_idx = if (set_idx % 4 == @intFromEnum(Direction.left))
                    ((rect.src_y + row_count) * img.width + rect.src_x + w - row_idx - 1) * 4
                else
                    ((rect.src_y + row_count) * img.width + rect.src_x + row_idx) * 4;

                @memcpy(atlas.data[atlas_idx .. atlas_idx + 4], img.data[src_idx .. src_idx + 4]);

                if (img.data[src_idx + 3] > 0) {
                    const rgba = RGBA{
                        .r = img.data[src_idx],
                        .g = img.data[src_idx + 1],
                        .b = img.data[src_idx + 2],
                        .a = 255,
                    };
                    if (color_counts.get(rgba)) |count| {
                        try color_counts.put(rgba, count + 1);
                    } else {
                        try color_counts.put(rgba, 1);
                    }
                }
            }

            var colors = std.ArrayList(u32).init(allocator);
            defer colors.deinit();

            var max: u32 = 0;
            var count_iter = color_counts.iterator();
            while (count_iter.next()) |entry| {
                try colors.append(@as(u32, @intCast(entry.key_ptr.r)) << 16 |
                    @as(u32, @intCast(entry.key_ptr.g)) << 8 |
                    @as(u32, @intCast(entry.key_ptr.b)));

                if (entry.value_ptr.* > max) {
                    dominant_colors[set_idx] = entry.key_ptr.*;
                    max = entry.value_ptr.*;
                }
            }

            try atlas_to_color_data.put(@bitCast(data), try allocator.dupe(u32, colors.items));
        }

        try anim_players.put(sheet_name, player_data);
        try dominant_color_data.put(sheet_name, dominant_colors);
    } else {
        std.log.err("Could not pack " ++ image_name ++ " into the atlas", .{});
    }
}

fn parseFontData(allocator: std.mem.Allocator, comptime atlas_w: f32, comptime atlas_h: f32, comptime path: []const u8, chars: *[256]CharacterData) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const data = try file.readToEndAlloc(allocator, std.math.maxInt(u16));
    defer allocator.free(data);

    var iter = std.mem.splitSequence(u8, data, if (std.mem.indexOf(u8, data, "\r\n") != null) "\r\n" else "\n");
    while (iter.next()) |line| {
        if (line.len == 0)
            continue;

        var split = std.mem.splitSequence(u8, line, ",");
        const idx = try std.fmt.parseInt(usize, split.next().?, 0);
        chars[idx] = try CharacterData.parse(&split, atlas_w, atlas_h);
    }
}

pub fn playSfx(name: []const u8) void {
    if (settings.sfx_volume <= 0.0)
        return;

    if (sfx_map.get(name)) |audio| {
        if (!audio.isPlaying()) {
            audio.setVolume(settings.sfx_volume);
            audio.start() catch return;
            return;
        }

        var audio_copies = sfx_copy_map.get(audio);
        if (audio_copies == null)
            audio_copies = std.ArrayList(*zaudio.Sound).init(main._allocator);

        for (audio_copies.?.items) |copy_audio| {
            if (!copy_audio.isPlaying()) {
                copy_audio.setVolume(settings.sfx_volume);
                copy_audio.start() catch return;
                return;
            }
        }

        var new_copy_audio = audio_state.engine.createSoundCopy(audio, .{}, null) catch return;
        new_copy_audio.setVolume(settings.sfx_volume);
        new_copy_audio.start() catch return;
        audio_copies.?.append(new_copy_audio) catch return;
        sfx_copy_map.put(audio, audio_copies.?) catch return;
        return;
    }

    const path = std.fmt.bufPrintZ(&sfx_path_buffer, "{s}sfx/{s}.mp3", .{ asset_dir, name }) catch return;

    if (std.fs.cwd().access(path, .{})) |_| {
        var audio = audio_state.engine.createSoundFromFile(path, .{}) catch return;
        audio.setVolume(settings.sfx_volume);
        audio.start() catch return;

        sfx_map.put(name, audio) catch return;
    } else |_| {
        std.log.err("Could not find sound effect for '{s}.mp3'", .{name});
    }
}

pub fn deinit(allocator: std.mem.Allocator) void {
    main_music.destroy();

    var copy_audio_iter = sfx_copy_map.valueIterator();
    while (copy_audio_iter.next()) |copy_audio_list| {
        for (copy_audio_list.items) |copy_audio| {
            copy_audio.*.destroy();
        }
        copy_audio_list.deinit();
    }
    sfx_copy_map.deinit();

    var audio_iter = sfx_map.valueIterator();
    while (audio_iter.next()) |audio| {
        audio.*.destroy();
    }
    sfx_map.deinit();
    audio_state.destroy(allocator);

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

    var colors_iter = atlas_to_color_data.valueIterator();
    while (colors_iter.next()) |colors| {
        allocator.free(colors.*);
    }

    var dominant_colors_iter = dominant_color_data.valueIterator();
    while (dominant_colors_iter.next()) |color_data| {
        allocator.free(color_data.*);
    }

    var rects_iter = atlas_data.valueIterator();
    while (rects_iter.next()) |sheet_rects| {
        if (sheet_rects.len > 0) {
            allocator.free(sheet_rects.*);
        }
    }

    var ui_rects_iter = ui_atlas_data.valueIterator();
    while (ui_rects_iter.next()) |sheet_rects| {
        if (sheet_rects.len > 0) {
            allocator.free(sheet_rects.*);
        }
    }

    var anim_enemy_iter = anim_enemies.valueIterator();
    while (anim_enemy_iter.next()) |enemy_data| {
        if (enemy_data.len > 0) {
            allocator.free(enemy_data.*);
        }
    }

    var anim_player_iter = anim_players.valueIterator();
    while (anim_player_iter.next()) |player_data| {
        if (player_data.len > 0) {
            allocator.free(player_data.*);
        }
    }

    dominant_color_data.deinit();
    atlas_to_color_data.deinit();
    atlas_data.deinit();
    ui_atlas_data.deinit();
    anim_enemies.deinit();
    anim_players.deinit();
}

pub fn init(allocator: std.mem.Allocator) !void {
    sfx_copy_map = std.AutoHashMap(*zaudio.Sound, std.ArrayList(*zaudio.Sound)).init(allocator);
    sfx_map = std.StringHashMap(*zaudio.Sound).init(allocator);
    dominant_color_data = std.StringHashMap([]RGBA).init(allocator);
    atlas_to_color_data = std.AutoHashMap(AtlasHashHack, []u32).init(allocator);
    atlas_data = std.StringHashMap([]AtlasData).init(allocator);
    ui_atlas_data = std.StringHashMap([]AtlasData).init(allocator);
    anim_enemies = std.StringHashMap([]AnimEnemyData).init(allocator);
    anim_players = std.StringHashMap([]AnimPlayerData).init(allocator);

    menu_background = try zstbi.Image.loadFromFile(asset_dir ++ "ui/menu_background.png", 4);

    bold_atlas = try zstbi.Image.loadFromFile(asset_dir ++ "fonts/ubuntu_bold.png", 4);
    bold_italic_atlas = try zstbi.Image.loadFromFile(asset_dir ++ "fonts/ubuntu_bold_italic.png", 4);
    medium_atlas = try zstbi.Image.loadFromFile(asset_dir ++ "fonts/ubuntu_medium.png", 4);
    medium_italic_atlas = try zstbi.Image.loadFromFile(asset_dir ++ "fonts/ubuntu_medium_italic.png", 4);

    try parseFontData(allocator, 1024, 1024, asset_dir ++ "fonts/ubuntu_bold.csv", &bold_chars);
    try parseFontData(allocator, 1024, 1024, asset_dir ++ "fonts/ubuntu_bold_italic.csv", &bold_italic_chars);
    try parseFontData(allocator, 1024, 512, asset_dir ++ "fonts/ubuntu_medium.csv", &medium_chars);
    try parseFontData(allocator, 1024, 1024, asset_dir ++ "fonts/ubuntu_medium_italic.csv", &medium_italic_chars);

    audio_state = try AudioState.create(allocator);
    try audio_state.engine.start();

    main_music = try audio_state.engine.createSoundFromFile(asset_dir ++ "music/main_menu.mp3", .{});
    main_music.setLooping(true);
    main_music.setVolume(settings.music_volume);
    try main_music.start();

    try addCursors("cursors.png", 32, 32, allocator);

    light_tex = try zstbi.Image.loadFromFile(asset_dir ++ "sheets/light.png", 4);
    light_w = @floatFromInt(light_tex.width);
    light_h = @floatFromInt(light_tex.height);

    atlas = try zstbi.Image.createEmpty(atlas_width, atlas_height, 4, .{});
    var ctx = zstbrp.PackContext{
        .width = atlas_width,
        .height = atlas_height,
        .num_nodes = 100,
    };

    const nodes = try allocator.alloc(zstbrp.PackNode, 4096);
    defer allocator.free(nodes);
    zstbrp.initPack(&ctx, nodes);

    try addImage("bars", "bars.png", 24, 8, false, &ctx, allocator);
    try addImage("conditions", "conditions.png", 16, 16, false, &ctx, allocator);
    try addImage("error_texture", "error_texture.png", 8, 8, false, &ctx, allocator);
    try addImage("invisible", "invisible.png", 8, 8, false, &ctx, allocator);
    try addImage("ground", "ground.png", 8, 8, false, &ctx, allocator);
    try addImage("ground_masks", "ground_masks.png", 8, 8, true, &ctx, allocator);
    try addImage("key_indicators", "key_indicators.png", 100, 100, false, &ctx, allocator);
    try addImage("items", "items.png", 8, 8, false, &ctx, allocator);
    try addImage("misc", "misc.png", 8, 8, false, &ctx, allocator);
    try addImage("misc_16", "misc_16.png", 16, 16, false, &ctx, allocator);
    try addImage("portals", "portals.png", 8, 8, false, &ctx, allocator);
    try addImage("portals_16", "portals_16.png", 16, 16, false, &ctx, allocator);
    try addImage("props", "props.png", 8, 8, false, &ctx, allocator);
    try addImage("props_16", "props_16.png", 16, 16, false, &ctx, allocator);
    try addImage("projectiles", "projectiles.png", 8, 8, false, &ctx, allocator);
    try addImage("tiered_items", "tiered_items.png", 8, 8, false, &ctx, allocator);
    try addImage("tiered_projectiles", "tiered_projectiles.png", 8, 8, false, &ctx, allocator);
    try addImage("wall_backface", "wall_backface.png", 8, 8, false, &ctx, allocator);
    try addImage("particles", "particles.png", 8, 8, false, &ctx, allocator);
    try addImage("editor_tile_base", "editor_tile_base.png", 8, 8, false, &ctx, allocator);

    try addAnimEnemy("low_realm", "low_realm.png", 8, 8, 48, 8, &ctx, allocator);
    try addAnimEnemy("low_realm_16", "low_realm_16.png", 16, 16, 96, 16, &ctx, allocator);
    try addAnimEnemy("mid_realm", "mid_realm.png", 8, 8, 48, 8, &ctx, allocator);
    try addAnimEnemy("mid_realm_16", "mid_realm_16.png", 16, 16, 96, 16, &ctx, allocator);
    try addAnimPlayer("players", "players.png", 8, 8, 48, 8, &ctx, allocator);
    try addAnimPlayer("player_skins", "player_skins.png", 8, 8, 48, 8, &ctx, allocator);

    if (settings.print_atlas)
        try zstbi.Image.writeToFile(atlas, "atlas.png", .png);

    ui_atlas = try zstbi.Image.createEmpty(ui_atlas_width, ui_atlas_height, 4, .{});
    var ui_ctx = zstbrp.PackContext{
        .width = ui_atlas_width,
        .height = ui_atlas_height,
        .num_nodes = 100,
    };

    const ui_nodes = try allocator.alloc(zstbrp.PackNode, 4096);
    defer allocator.free(ui_nodes);
    zstbrp.initPack(&ui_ctx, ui_nodes);

    const imply_size = std.math.maxInt(u32);
    try addUiImage("ability_icons", "sheets/ability_icons.png", 40, 40, &ctx, allocator);
    try addUiImage("hub_button", "ui/hub_button.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("options_button", "ui/options_button.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("rare_slot", "ui/rare_slot.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("epic_slot", "ui/epic_slot.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("legendary_slot", "ui/legendary_slot.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("mythic_slot", "ui/mythic_slot.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("out_of_mana_slot", "ui/out_of_mana_slot.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("out_of_health_slot", "ui/out_of_health_slot.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("basic_panel", "ui/basic_panel.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("dialog_base_background", "ui/screens/dialog_base_background.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("dialog_title_background", "ui/screens/dialog_title_background.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("chatbox_background", "ui/chat/chatbox_background.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("chatbox_input", "ui/chat/chatbox_input.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("chatbox_cursor", "ui/chat/chatbox_cursor.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("chatbox_scroll_background", "ui/chat/chatbox_scroll_background.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("chatbox_scroll_wheel_base", "ui/chat/chatbox_scroll_wheel_base.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("chatbox_scroll_wheel_hover", "ui/chat/chatbox_scroll_wheel_hover.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("chatbox_scroll_wheel_press", "ui/chat/chatbox_scroll_wheel_press.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("speech_balloons", "ui/chat/speech_balloons.png", 65, 45, &ui_ctx, allocator);
    try addUiImage("button_base", "ui/screens/button_base.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("button_hover", "ui/screens/button_hover.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("button_press", "ui/screens/button_press.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("checked_box_base", "ui/screens/checked_box_base.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("checked_box_hover", "ui/screens/checked_box_hover.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("checked_box_press", "ui/screens/checked_box_press.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("slider_background", "ui/screens/slider_background.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("slider_knob_base", "ui/screens/slider_knob_base.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("slider_knob_hover", "ui/screens/slider_knob_hover.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("slider_knob_press", "ui/screens/slider_knob_press.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("text_input_base", "ui/screens/text_input_base.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("text_input_hover", "ui/screens/text_input_hover.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("text_input_press", "ui/screens/text_input_press.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("toggle_slider_base_off", "ui/screens/toggle_slider_base_off.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("toggle_slider_hover_off", "ui/screens/toggle_slider_hover_off.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("toggle_slider_press_off", "ui/screens/toggle_slider_press_off.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("toggle_slider_base_on", "ui/screens/toggle_slider_base_on.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("toggle_slider_hover_on", "ui/screens/toggle_slider_hover_on.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("toggle_slider_press_on", "ui/screens/toggle_slider_press_on.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("tooltip_background", "ui/screens/tooltip_background.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("tooltip_line_spacer", "ui/screens/tooltip_line_spacer.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("unchecked_box_base", "ui/screens/unchecked_box_base.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("unchecked_box_hover", "ui/screens/unchecked_box_hover.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("unchecked_box_press", "ui/screens/unchecked_box_press.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("container_view", "ui/container_view.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("minimap", "ui/minimap.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("minimap_icons", "ui/minimap_icons.png", 8, 8, &ui_ctx, allocator);
    try addUiImage("player_inventory", "ui/player_inventory.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("player_health_bar", "ui/player_health_bar.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("player_mana_bar", "ui/player_mana_bar.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("player_abilities_bars", "ui/player_abilities_bars.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("player_xp_bar", "ui/player_xp_bar.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("player_xp_decor", "ui/player_xp_decor.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("options_background", "ui/options_background.png", imply_size, imply_size, &ui_ctx, allocator);
    try addUiImage("player_stats", "ui/player_stats.png", imply_size, imply_size, &ui_ctx, allocator);

    if (settings.print_ui_atlas)
        try zstbi.Image.writeToFile(ui_atlas, "ui_atlas.png", .png);

    if (atlas_data.get("ground_masks")) |ground_masks| {
        var left_mask_data = ground_masks[0x0];
        left_mask_data.removePadding();

        var top_mask_data = ground_masks[0x1];
        top_mask_data.removePadding();

        left_top_mask_uv = [4]f32{ left_mask_data.tex_u, left_mask_data.tex_v, top_mask_data.tex_u, top_mask_data.tex_v };

        var right_mask_rect = ground_masks[0x2];
        right_mask_rect.removePadding();

        var bottom_mask_rect = ground_masks[0x3];
        bottom_mask_rect.removePadding();

        right_bottom_mask_uv = [4]f32{ right_mask_rect.tex_u, right_mask_rect.tex_v, bottom_mask_rect.tex_u, bottom_mask_rect.tex_v };
    } else std.debug.panic("Could not find ground_masks in the atlas", .{});

    if (atlas_data.get("wall_backface")) |backfaces| {
        wall_backface_data = backfaces[0x0];
        wall_backface_data.removePadding();
    } else std.debug.panic("Could not find wall_backface in the atlas", .{});

    if (atlas_data.get("particles")) |particles| {
        particle_data = particles[0x0];
    } else std.debug.panic("Could not find particle in the atlas", .{});

    if (atlas_data.get("editor_tile_base")) |editor_tile_tex| {
        editor_tile = editor_tile_tex[0x0];
        editor_tile.removePadding();
    } else std.debug.panic("Could not find editor_tile_base in the atlas", .{});

    if (atlas_data.get("bars")) |bars| {
        hp_bar_data = bars[0x0];
        mp_bar_data = bars[0x1];
        empty_bar_data = bars[0x4];
    } else std.debug.panic("Could not find bars in the atlas", .{});

    if (atlas_data.get("error_texture")) |error_tex| {
        error_data = error_tex[0x0];

        const enemy_walk_frames = AnimEnemyData.directions * AnimEnemyData.walk_actions;
        const enemy_attack_frames = AnimEnemyData.directions * AnimEnemyData.attack_actions;
        error_data_enemy = AnimEnemyData{
            .walk_anims = [_]AtlasData{error_data} ** enemy_walk_frames,
            .attack_anims = [_]AtlasData{error_data} ** enemy_attack_frames,
        };

        const player_walk_frames = AnimPlayerData.directions * AnimPlayerData.walk_actions;
        const player_attack_frames = AnimPlayerData.directions * AnimPlayerData.attack_actions;
        error_data_player = AnimPlayerData{
            .walk_anims = [_]AtlasData{error_data} ** player_walk_frames,
            .attack_anims = [_]AtlasData{error_data} ** player_attack_frames,
        };
    } else std.debug.panic("Could not find error_texture in the atlas", .{});

    settings.assetsLoaded();
}

pub inline fn getUiData(comptime name: []const u8, idx: usize) AtlasData {
    return (ui_atlas_data.get(name) orelse std.debug.panic("Could not find " ++ name ++ " in the UI atlas", .{}))[idx];
}
