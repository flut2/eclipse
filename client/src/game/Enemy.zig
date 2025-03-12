const std = @import("std");

const shared = @import("shared");
const utils = shared.utils;
const game_data = shared.game_data;
const f32i = utils.f32i;
const i64f = utils.i64f;
const u8f = utils.u8f;

const assets = @import("../assets.zig");
const Camera = @import("../Camera.zig");
const px_per_tile = Camera.px_per_tile;
const main = @import("../main.zig");
const Renderer = @import("../render/Renderer.zig");
const element = @import("../ui/elements/element.zig");
const SpeechBalloon = @import("../ui/game/SpeechBalloon.zig");
const StatusText = @import("../ui/game/StatusText.zig");
const ui_systems = @import("../ui/systems.zig");
const base = @import("object_base.zig");
const map = @import("map.zig");
const particles = @import("particles.zig");

const Enemy = @This();

map_id: u32 = std.math.maxInt(u32),
data_id: u16 = std.math.maxInt(u16),
x: f32 = 0.0,
y: f32 = 0.0,
z: f32 = 0.0,
alpha: f32 = 1.0,
name: ?[]const u8 = null,
name_text_data: ?element.TextData = null,
size_mult: f32 = 1.0,
max_hp: i32 = 0,
hp: i32 = 0,
defense: i16 = 0,
resistance: i16 = 0,
condition: utils.Condition = .{},
anim_data: assets.AnimEnemyData = undefined,
move_angle: f32 = std.math.nan(f32),
move_step: f32 = 0.0,
target_x: f32 = 0.0,
target_y: f32 = 0.0,
attack_start: i64 = 0,
attack_angle: f32 = 0.0,
data: *const game_data.EnemyData = undefined,
colors: []u32 = &.{},
anim_idx: u8 = 0,
facing: f32 = std.math.nan(f32),
status_texts: std.ArrayListUnmanaged(StatusText) = .empty,
speech_balloon: ?SpeechBalloon = null,
next_anim: i64 = -1,

pub fn addToMap(enemy_data: Enemy) void {
    base.addToMap(enemy_data, Enemy);
}

pub fn deinit(self: *Enemy) void {
    base.deinit(self);
    for (self.status_texts.items) |*text| text.deinit();
    self.status_texts.deinit(main.allocator);
    if (self.speech_balloon) |*balloon| balloon.deinit();
}

pub fn draw(
    self: *Enemy,
    renderer: *Renderer,
    generics: *std.ArrayListUnmanaged(Renderer.GenericData),
    sort_extras: *std.ArrayListUnmanaged(f32),
    lights: *std.ArrayListUnmanaged(Renderer.LightData),
    float_time_ms: f32,
) void {
    if (ui_systems.screen == .editor and !ui_systems.screen.editor.show_enemy_layer or
        !main.camera.visibleInCamera(self.x, self.y)) return;

    var screen_pos = main.camera.worldToScreen(self.x, self.y);
    const size = Camera.size_mult * main.camera.scale * self.size_mult;

    const attack_period = std.time.us_per_s / 3;
    const move_period = std.time.us_per_s / 2;

    const time = main.current_time;
    var float_period: f32 = 0.0;
    var action: assets.Action = .stand;
    if (time < self.attack_start + attack_period) {
        const time_dt = f32i(time - self.attack_start);
        float_period = @mod(time_dt, attack_period) / attack_period;
        self.facing = self.attack_angle;
        action = .attack;
    } else if (!std.math.isNan(self.move_angle)) {
        const float_time = f32i(time);
        float_period = @mod(float_time, move_period) / move_period;
        self.facing = self.move_angle;
        action = .walk;
    } else {
        float_period = 0;
        action = .stand;
    }

    const angle = if (std.math.isNan(self.facing))
        0.0
    else
        utils.halfBound(self.facing) / (std.math.pi / 4.0);

    const dir: assets.Direction = switch (u8f(@round(angle + 4)) % 8) {
        2...5 => .right,
        else => .left,
    };

    const anim_idx = u8f(@max(0, @min(0.99999, float_period)) * 2.0);
    const dir_idx: u8 = @intFromEnum(dir);
    const stand_data = self.anim_data.walk_anims[dir_idx * assets.AnimEnemyData.walk_actions];
    var atlas_data = switch (action) {
        .walk => self.anim_data.walk_anims[dir_idx * assets.AnimEnemyData.walk_actions + 1 + anim_idx],
        .attack => self.anim_data.attack_anims[dir_idx * assets.AnimEnemyData.attack_actions + anim_idx],
        .stand => stand_data,
    };

    var sink: f32 = 1.0;
    if (map.getSquare(self.x, self.y, true, .con)) |square| {
        if (game_data.ground.from_id.get(square.data_id)) |data| sink += if (data.sink) 0.75 else 0;
    }
    atlas_data.tex_h /= sink;

    const w = atlas_data.texWRaw() * size;
    const h = atlas_data.texHRaw() * size;
    const stand_w = stand_data.width() * size;
    const x_offset = (if (dir == .left) stand_w - w else w - stand_w) / 2.0;

    screen_pos.x += x_offset;
    screen_pos.y += self.z * -px_per_tile - h + assets.padding * size;

    var alpha_mult: f32 = self.alpha;
    if (self.condition.invisible)
        alpha_mult = 0.6;

    var color: u32 = 0;
    var color_intensity: f32 = 0.0;
    if (self.condition.encased_in_stone) {
        color = 0xE0A628;
        color_intensity = 0.33;
    }
    // flash

    if (main.settings.enable_lights)
        Renderer.drawLight(
            lights,
            self.data.light,
            screen_pos.x - w / 2.0,
            screen_pos.y,
            w,
            h,
            main.camera.scale,
            float_time_ms,
        );

    if (self.data.show_name) if (self.name_text_data) |*data| {
        const name_h = (data.height + 5) * main.camera.scale;
        const name_y = screen_pos.y - name_h;
        data.sort_extra = (screen_pos.y - name_y) + (h - name_h);
        Renderer.drawText(
            generics,
            sort_extras,
            screen_pos.x - x_offset - data.width * main.camera.scale / 2,
            name_y,
            main.camera.scale,
            data,
            .{},
        );
    };

    Renderer.drawQuad(
        generics,
        sort_extras,
        screen_pos.x - w / 2.0,
        screen_pos.y,
        w,
        h,
        atlas_data,
        .{
            .shadow_texel_mult = 2.0 / size,
            .alpha_mult = alpha_mult,
            .color = color,
            .color_intensity = color_intensity,
        },
    );

    var y_pos: f32 = if (sink != 1.0) 15.0 else 5.0;

    if (self.hp >= 0 and self.hp < self.max_hp) {
        const hp_bar_w = assets.hp_bar_data.texWRaw() * 2 * main.camera.scale;
        const hp_bar_h = assets.hp_bar_data.texHRaw() * 2 * main.camera.scale;
        const hp_bar_y = screen_pos.y + h + y_pos;
        const hp_bar_sort_extra = (screen_pos.y - hp_bar_y) + (h - hp_bar_h);

        Renderer.drawQuad(
            generics,
            sort_extras,
            screen_pos.x - x_offset - hp_bar_w / 2.0,
            hp_bar_y,
            hp_bar_w,
            hp_bar_h,
            assets.empty_bar_data,
            .{ .shadow_texel_mult = 0.5, .sort_extra = hp_bar_sort_extra - 0.0001 },
        );

        const float_hp = f32i(self.hp);
        const float_max_hp = f32i(self.max_hp);
        const hp_perc = 1.0 / (float_hp / float_max_hp);
        var hp_bar_data = assets.hp_bar_data;
        hp_bar_data.tex_w /= hp_perc;

        Renderer.drawQuad(
            generics,
            sort_extras,
            screen_pos.x - x_offset - hp_bar_w / 2.0,
            hp_bar_y,
            hp_bar_w / hp_perc,
            hp_bar_h,
            hp_bar_data,
            .{ .shadow_texel_mult = 0.5, .sort_extra = hp_bar_sort_extra },
        );

        y_pos += hp_bar_h + 5.0;
    }

    const cond_int: @typeInfo(utils.Condition).@"struct".backing_integer.? = @bitCast(self.condition);
    if (cond_int > 0) {
        base.drawConditions(
            renderer,
            generics,
            sort_extras,
            cond_int,
            float_time_ms,
            screen_pos.x - x_offset,
            screen_pos.y + h + y_pos,
            main.camera.scale,
            screen_pos.y,
            h,
        );
        y_pos += 20;
    }

    base.drawStatusTexts(
        self,
        generics,
        sort_extras,
        i64f(float_time_ms) * std.time.us_per_ms,
        screen_pos.x - x_offset,
        screen_pos.y,
        main.camera.scale,
    );

    base.drawSpeechBalloon(
        self,
        generics,
        sort_extras,
        i64f(float_time_ms) * std.time.us_per_ms,
        screen_pos.x - x_offset,
        screen_pos.y,
        main.camera.scale,
    );
}

pub fn update(self: *Enemy, _: i64, dt: f32) void {
    if (!std.math.isNan(self.move_angle) and self.move_step > 0.0) {
        const cos_angle = @cos(self.move_angle);
        const sin_angle = @sin(self.move_angle);
        const next_x = self.x + dt * self.move_step * cos_angle;
        const next_y = self.y + dt * self.move_step * sin_angle;
        self.x = if (cos_angle > 0.0) @min(self.target_x, next_x) else @max(self.target_x, next_x);
        self.y = if (sin_angle > 0.0) @min(self.target_y, next_y) else @max(self.target_y, next_y);
        if (@abs(self.x - self.target_x) < 0.01 and @abs(self.y - self.target_y) < 0.01) {
            self.move_angle = std.math.nan(f32);
            self.move_step = 0.0;
            self.target_x = 0.0;
            self.target_y = 0.0;
        }
    }
}
