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

pub const atlas_width: u32 = 4096;
pub const atlas_height: u32 = 4096;
pub const base_texel_w: f32 = 1.0 / 4096.0;
pub const base_texel_h: f32 = 1.0 / 4096.0;

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
    // left/right dir
    walk_anims: [2][3]AtlasData,
    attack_anims: [2][2]AtlasData,
};

pub const AnimPlayerData = struct {
    // all dirs
    walk_anims: [4][3]AtlasData,
    attack_anims: [4][2]AtlasData,
};

pub const AtlasData = packed struct {
    tex_u: f32,
    tex_v: f32,
    tex_w: f32,
    tex_h: f32,

    pub fn removePadding(self: *AtlasData) void {
        const float_pad: f32 = padding;
        self.tex_u += float_pad / @as(f32, atlas_width);
        self.tex_v += float_pad / @as(f32, atlas_height);
        self.tex_w -= float_pad * 2 / @as(f32, atlas_width);
        self.tex_h -= float_pad * 2 / @as(f32, atlas_height);
    }

    pub inline fn fromRaw(u: u32, v: u32, w: u32, h: u32) AtlasData {
        return fromRawF32(@floatFromInt(u), @floatFromInt(v), @floatFromInt(w), @floatFromInt(h));
    }

    pub inline fn fromRawF32(u: f32, v: f32, w: f32, h: f32) AtlasData {
        return AtlasData{
            .tex_u = u / @as(f32, atlas_width),
            .tex_v = v / @as(f32, atlas_height),
            .tex_w = w / @as(f32, atlas_width),
            .tex_h = h / @as(f32, atlas_height),
        };
    }

    pub inline fn texURaw(self: AtlasData) f32 {
        return self.tex_u * atlas_width;
    }

    pub inline fn texVRaw(self: AtlasData) f32 {
        return self.tex_v * atlas_height;
    }

    pub inline fn texWRaw(self: AtlasData) f32 {
        return self.tex_w * atlas_width;
    }

    pub inline fn texHRaw(self: AtlasData) f32 {
        return self.tex_h * atlas_height;
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

const AtlasHashHack = [4]u32;

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

fn isImageEmpty(img: zstbi.Image, x: usize, y: usize, w: u32, h: u32) bool {
    for (y..y + h) |loop_y| {
        for (x..x + w) |loop_x| {
            if (img.data[(loop_y * img.width + loop_x) * 4 + 3] != 0)
                return false;
        }
    }

    return true;
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
    ctx: *zstbrp.PackContext,
    allocator: std.mem.Allocator,
) !void {
    var img = try zstbi.Image.loadFromFile(asset_dir ++ "sheets/" ++ image_name, 4);
    defer img.deinit();

    const img_size = cut_width * cut_height;
    const len = @divFloor(img.width * img.height, img_size);
    var current_rects = try allocator.alloc(zstbrp.PackRect, len);
    defer allocator.free(current_rects);

    for (0..len) |i| {
        const cur_src_x = (i * cut_width) % img.width;
        const cur_src_y = @divFloor(i * cut_width, img.width) * cut_height;

        if (!isImageEmpty(img, cur_src_x, cur_src_y, cut_width, cut_height)) {
            current_rects[i].w = cut_width + padding * 2;
            current_rects[i].h = cut_height + padding * 2;
        } else {
            current_rects[i].w = 0;
            current_rects[i].h = 0;
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
            if (rect.w == 0 or rect.h == 0)
                continue;

            const cur_atlas_x = rect.x + padding;
            const cur_atlas_y = rect.y + padding;
            const cur_src_x = (i * cut_width) % img.width;
            const cur_src_y = @divFloor(i * cut_width, img.width) * cut_height;

            color_counts.clearRetainingCapacity();

            for (0..img_size) |j| {
                const row_count = @divFloor(j, cut_width);
                const row_idx = j % cut_width;
                const atlas_idx = ((cur_atlas_y + row_count) * atlas_width + cur_atlas_x + row_idx) * 4;
                const src_idx = ((cur_src_y + row_count) * img.width + cur_src_x + row_idx) * 4;
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
                    dominant_colors[i] = entry.key_ptr.*;
                    max = entry.value_ptr.*;
                }
            }

            data[i] = AtlasData.fromRaw(rect.x, rect.y, rect.w, rect.h);
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

    const img_size = cut_width * cut_height;
    const len = @divFloor(img.width * img.height, img_size);
    var current_rects = try allocator.alloc(zstbrp.PackRect, len);
    defer allocator.free(current_rects);
    var data = try allocator.alloc(AtlasData, len);

    for (0..len) |i| {
        const cur_src_x = (i * cut_width) % img.width;
        const cur_src_y = @divFloor(i * cut_width, img.width) * cut_height;

        if (!isImageEmpty(img, cur_src_x, cur_src_y, cut_width, cut_height)) {
            current_rects[i].w = cut_width + padding * 2;
            current_rects[i].h = cut_height + padding * 2;
        } else {
            current_rects[i].w = 0;
            current_rects[i].h = 0;
        }
    }

    if (zstbrp.packRects(ctx, current_rects)) {
        for (0..len) |i| {
            const rect = current_rects[i];
            if (rect.w == 0 or rect.h == 0)
                continue;

            const cur_atlas_x = rect.x + padding;
            const cur_atlas_y = rect.y + padding;
            const cur_src_x = (i * cut_width) % img.width;
            const cur_src_y = @divFloor(i * cut_width, img.width) * cut_height;

            for (0..img_size) |j| {
                const row_count = @divFloor(j, cut_width);
                const row_idx = j % cut_width;
                const atlas_idx = ((cur_atlas_y + row_count) * atlas_width + cur_atlas_x + row_idx) * 4;
                const src_idx = ((cur_src_y + row_count) * img.width + cur_src_x + row_idx) * 4;
                @memcpy(ui_atlas.data[atlas_idx .. atlas_idx + 4], img.data[src_idx .. src_idx + 4]);
            }

            data[i] = AtlasData.fromRaw(rect.x, rect.y, rect.w, rect.h);
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

    const img_size = cut_width * cut_height;
    const len = @divFloor(img.width, full_cut_width) * @divFloor(img.height, full_cut_height) * 5;

    var current_rects = try allocator.alloc(zstbrp.PackRect, len * 2);
    defer allocator.free(current_rects);

    for (0..2) |i| {
        for (0..len) |j| {
            const cur_src_x = (j % 5) * cut_width;
            const cur_src_y = @divFloor(j, 5) * cut_height;

            const attack_scale = @as(u32, @intFromBool(j % 5 == 4)) + 1;
            if (!isImageEmpty(img, cur_src_x, cur_src_y, cut_width * attack_scale, cut_height)) {
                current_rects[i * len + j].w = (cut_width + padding * 2) * attack_scale;
                current_rects[i * len + j].h = cut_height + padding * 2;
            } else {
                current_rects[i * len + j].w = 0;
                current_rects[i * len + j].h = 0;
            }
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
                if (rect.w == 0 or rect.h == 0)
                    continue;

                color_counts.clearRetainingCapacity();

                const data = AtlasData.fromRaw(rect.x, rect.y, rect.w, rect.h);
                const frame_idx = j % 5;
                const set_idx = @divFloor(j, 5);
                if (frame_idx >= 3) {
                    enemy_data[set_idx].attack_anims[i][frame_idx - 3] = data;
                } else {
                    enemy_data[set_idx].walk_anims[i][frame_idx] = data;
                }

                const cur_atlas_x = rect.x + padding;
                const cur_atlas_y = rect.y + padding;
                const cur_src_x = frame_idx * cut_width;
                const cur_src_y = set_idx * cut_height;

                const attack_scale = @as(u32, @intFromBool(j % 5 == 4)) + 1;
                const size = img_size * attack_scale;
                const scaled_w = cut_width * attack_scale;
                for (0..size) |k| {
                    const row_count = @divFloor(k, scaled_w);
                    const row_idx = k % scaled_w;
                    const atlas_idx = ((cur_atlas_y + row_count) * atlas_width + cur_atlas_x + row_idx) * 4;

                    const src_idx = if (i == @intFromEnum(Direction.left))
                        ((cur_src_y + row_count) * img.width + cur_src_x + scaled_w - row_idx - 1) * 4
                    else
                        ((cur_src_y + row_count) * img.width + cur_src_x + row_idx) * 4;

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

    const img_size = cut_width * cut_height;
    var len = @divFloor(img.width, full_cut_width) * @divFloor(img.height, full_cut_height) * 5;
    len += @divFloor(len, 3);

    var current_rects = try allocator.alloc(zstbrp.PackRect, len);
    defer allocator.free(current_rects);

    var left_sub: u32 = 0;
    for (0..len) |j| {
        const frame_idx = j % 5;
        const set_idx = @divFloor(j, 5);
        const cur_src_x = frame_idx * cut_width;
        if (set_idx % 4 == 1 and frame_idx == 0) {
            left_sub += 1;
        }

        const cur_src_y = (set_idx - left_sub) * cut_height;

        const attack_scale = @as(u32, @intFromBool(frame_idx == 4)) + 1;
        if (!isImageEmpty(img, cur_src_x, cur_src_y, cut_width * attack_scale, cut_height)) {
            current_rects[j].w = (cut_width + padding * 2) * attack_scale;
            current_rects[j].h = cut_height + padding * 2;
        } else {
            current_rects[j].w = 0;
            current_rects[j].h = 0;
        }
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
            if (rect.w == 0 or rect.h == 0)
                continue;

            color_counts.clearRetainingCapacity();

            const data = AtlasData.fromRaw(rect.x, rect.y, rect.w, rect.h);
            const frame_idx = j % 5;
            const set_idx = @divFloor(j, 5);
            if (set_idx % 4 == 1 and frame_idx == 0) {
                left_sub += 1;
            }

            const data_idx = @divFloor(set_idx, 4);
            if (frame_idx >= 3) {
                player_data[data_idx].attack_anims[set_idx % 4][frame_idx - 3] = data;
            } else {
                player_data[data_idx].walk_anims[set_idx % 4][frame_idx] = data;
            }
            const cur_atlas_x = rect.x + padding;
            const cur_atlas_y = rect.y + padding;
            const cur_src_x = frame_idx * cut_width;
            const cur_src_y = (set_idx - left_sub) * cut_height;

            const attack_scale = @as(u32, @intFromBool(frame_idx == 4)) + 1;
            const size = img_size * attack_scale;
            const scaled_w = cut_width * attack_scale;
            for (0..size) |k| {
                const row_count = @divFloor(k, scaled_w);
                const row_idx = k % scaled_w;
                const atlas_idx = ((cur_atlas_y + row_count) * atlas_width + cur_atlas_x + row_idx) * 4;

                const src_idx = if (set_idx % 4 == @intFromEnum(Direction.left))
                    ((cur_src_y + row_count) * img.width + cur_src_x + scaled_w - row_idx - 1) * 4
                else
                    ((cur_src_y + row_count) * img.width + cur_src_x + row_idx) * 4;

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

    try addImage("bars", "bars.png", 24, 8, &ctx, allocator);
    try addImage("conditions", "conditions.png", 16, 16, &ctx, allocator);
    try addImage("error_texture", "error_texture.png", 8, 8, &ctx, allocator);
    try addImage("invisible", "invisible.png", 8, 8, &ctx, allocator);
    try addImage("ground", "ground.png", 8, 8, &ctx, allocator);
    try addImage("ground_masks", "ground_masks.png", 8, 8, &ctx, allocator);
    try addImage("key_indicators", "key_indicators.png", 100, 100, &ctx, allocator);
    try addImage("items", "items.png", 8, 8, &ctx, allocator);
    try addImage("misc", "misc.png", 8, 8, &ctx, allocator);
    try addImage("misc_16", "misc_16.png", 16, 16, &ctx, allocator);
    try addImage("portals", "portals.png", 8, 8, &ctx, allocator);
    try addImage("portals_16", "portals_16.png", 16, 16, &ctx, allocator);
    try addImage("props", "props.png", 8, 8, &ctx, allocator);
    try addImage("props_16", "props_16.png", 16, 16, &ctx, allocator);
    try addImage("projectiles", "projectiles.png", 8, 8, &ctx, allocator);
    try addImage("tiered_items", "tiered_items.png", 8, 8, &ctx, allocator);
    try addImage("tiered_projectiles", "tiered_projectiles.png", 8, 8, &ctx, allocator);
    try addImage("wall_backface", "wall_backface.png", 8, 8, &ctx, allocator);
    try addImage("particles", "particles.png", 8, 8, &ctx, allocator);
    try addImage("editor_tile_base", "editor_tile_base.png", 8, 8, &ctx, allocator);

    try addAnimEnemy("low_realm", "low_realm.png", 8, 8, 48, 8, &ctx, allocator);
    try addAnimEnemy("low_realm_16", "low_realm_16.png", 16, 16, 96, 16, &ctx, allocator);
    try addAnimEnemy("mid_realm", "mid_realm.png", 8, 8, 48, 8, &ctx, allocator);
    try addAnimEnemy("mid_realm_16", "mid_realm_16.png", 16, 16, 96, 16, &ctx, allocator);
    try addAnimPlayer("players", "players.png", 8, 8, 48, 8, &ctx, allocator);
    try addAnimPlayer("player_skins", "player_skins.png", 8, 8, 48, 8, &ctx, allocator);

    if (settings.print_atlas)
        try zstbi.Image.writeToFile(atlas, "atlas.png", .png);

    ui_atlas = try zstbi.Image.createEmpty(atlas_width, atlas_height, 4, .{});
    var ui_ctx = zstbrp.PackContext{
        .width = atlas_width,
        .height = atlas_height,
        .num_nodes = 100,
    };

    const ui_nodes = try allocator.alloc(zstbrp.PackNode, 4096);
    defer allocator.free(ui_nodes);
    zstbrp.initPack(&ui_ctx, ui_nodes);

    const imply_size = std.math.maxInt(u32);
    try addUiImage("ability_icons", "sheets/ability_icons.png", 40, 40, &ctx, allocator);
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

        error_data_enemy = AnimEnemyData{
            .walk_anims = [2][3]AtlasData{
                [_]AtlasData{ error_data, error_data, error_data },
                [_]AtlasData{ error_data, error_data, error_data },
            },
            .attack_anims = [2][2]AtlasData{
                [_]AtlasData{ error_data, error_data },
                [_]AtlasData{ error_data, error_data },
            },
        };

        error_data_player = AnimPlayerData{
            .walk_anims = [4][3]AtlasData{
                [_]AtlasData{ error_data, error_data, error_data },
                [_]AtlasData{ error_data, error_data, error_data },
                [_]AtlasData{ error_data, error_data, error_data },
                [_]AtlasData{ error_data, error_data, error_data },
            },
            .attack_anims = [4][2]AtlasData{
                [_]AtlasData{ error_data, error_data },
                [_]AtlasData{ error_data, error_data },
                [_]AtlasData{ error_data, error_data },
                [_]AtlasData{ error_data, error_data },
            },
        };
    } else std.debug.panic("Could not find error_texture in the atlas", .{});

    settings.assetsLoaded();
}

pub inline fn getUiData(comptime name: []const u8, idx: usize) AtlasData {
    return (ui_atlas_data.get(name) orelse std.debug.panic("Could not find " ++ name ++ " in the UI atlas", .{}))[idx];
}
