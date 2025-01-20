const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const utils = shared.utils;
const f32i = utils.f32i;

const assets = @import("../../assets.zig");
const Camera = @import("../../Camera.zig");
const Enemy = @import("../../game/Enemy.zig");
const map = @import("../../game/map.zig");
const Player = @import("../../game/Player.zig");
const Portal = @import("../../game/Portal.zig");
const main = @import("../../main.zig");
const CameraData = @import("../../render/CameraData.zig");
const tooltip = @import("../tooltips/tooltip.zig");
const element = @import("element.zig");
const ElementBase = element.ElementBase;

const MinimapIcon = struct {
    const self_id = 0;
    const portal_id = 1;
    const player_id = 3;
    const party_id = 4;
    const enemy_id = 5;

    x: f32,
    y: f32,
    id: u8,
};

const Minimap = @This();
base: ElementBase,
decor: element.ImageData,
offset_x: f32 = 0.0,
offset_y: f32 = 0.0,
map_width: f32 = 0.0,
map_height: f32 = 0.0,
icons: std.ArrayListUnmanaged(MinimapIcon) = .empty,
icon_lock: std.Thread.Mutex = .{},
last_update: i64 = -1,

pub fn deinit(self: *Minimap) void {
    self.icons.deinit(main.allocator);
}

pub fn draw(self: *Minimap, cam_data: CameraData, x_offset: f32, y_offset: f32, _: i64) void {
    if (!self.base.visible) return;

    self.decor.draw(self.base.x + x_offset, self.base.y + y_offset, self.base.scissor);

    const fw = f32i(map.info.width);
    const fh = f32i(map.info.height);
    const fminimap_w = f32i(map.minimap.width);
    const fminimap_h = f32i(map.minimap.height);
    const zoom = cam_data.minimap_zoom;
    const uv_size = .{ fw / zoom / fminimap_w, fh / zoom / fminimap_h };
    main.renderer.generics.append(main.allocator, .{
        .render_type = .minimap,
        .pos = .{
            self.base.x + self.offset_x + x_offset + assets.padding,
            self.base.y + self.offset_y + y_offset + assets.padding,
        },
        .size = .{ self.map_width, self.map_height },
        .uv = .{ cam_data.x / fminimap_w - uv_size[0] / 2.0, cam_data.y / fminimap_h - uv_size[1] / 2.0 },
        .uv_size = uv_size,
    }) catch main.oomPanic();

    const player_icon = assets.minimap_icons[MinimapIcon.self_id];
    const scale = 2.0;
    const player_icon_w = player_icon.texWRaw() * scale;
    const player_icon_h = player_icon.texHRaw() * scale;
    main.renderer.drawQuad(
        self.base.x + self.offset_x + x_offset + (self.map_width - player_icon_w) / 2.0,
        self.base.y + self.offset_y + y_offset + (self.map_height - player_icon_h) / 2.0,
        player_icon_w,
        player_icon_h,
        player_icon,
        .{ .shadow_texel_mult = 0.5, .scissor = self.base.scissor },
    );

    self.icon_lock.lock();
    defer self.icon_lock.unlock();
    for (self.icons.items) |icon| {
        const icon_data = assets.minimap_icons[icon.id];
        const icon_w = icon_data.width() * scale;
        const icon_h = icon_data.height() * scale;
        main.renderer.drawQuad(
            self.base.x + self.offset_x + x_offset + icon.x - icon_w / 2.0,
            self.base.y + self.offset_y + y_offset + icon.y - icon_h / 2.0,
            icon_w,
            icon_h,
            icon_data,
            .{ .shadow_texel_mult = 0.5, .scissor = self.base.scissor },
        );
    }
}

pub fn update(self: *Minimap, time: i64) void {
    if (time - self.last_update < 16 * std.time.us_per_ms) return;
    self.last_update = time;

    self.icon_lock.lock();
    defer self.icon_lock.unlock();

    self.icons.clearRetainingCapacity();

    const fw = f32i(map.info.width);
    const fh = f32i(map.info.height);
    main.camera.lock.lock();
    const zoom = main.camera.minimap_zoom;
    const x = main.camera.x;
    const y = main.camera.y;
    main.camera.lock.unlock();
    const vis_w = fw / zoom;
    const vis_h = fh / zoom;
    const edge_x = x - vis_w / 2.0;
    const edge_y = y - vis_h / 2.0;
    const px_per_x = self.map_width / vis_w;
    const px_per_y = self.map_height / vis_h;

    for (map.listForType(Portal).items) |portal| {
        if (!utils.isInBounds(portal.x, portal.y, edge_x, edge_y, vis_w, vis_h)) continue;
        self.icons.append(main.allocator, .{
            .id = MinimapIcon.portal_id,
            .x = (portal.x - edge_x) * px_per_x,
            .y = (portal.y - edge_y) * px_per_y,
        }) catch main.oomPanic();
    }

    for (map.listForType(Player).items) |player| {
        if (player.map_id == map.info.player_map_id or
            !utils.isInBounds(player.x, player.y, edge_x, edge_y, vis_w, vis_h)) continue;
        self.icons.append(main.allocator, .{
            .id = MinimapIcon.player_id,
            .x = (player.x - edge_x) * px_per_x,
            .y = (player.y - edge_y) * px_per_y,
        }) catch main.oomPanic();
    }

    for (map.listForType(Enemy).items) |enemy| {
        if (!utils.isInBounds(enemy.x, enemy.y, edge_x, edge_y, vis_w, vis_h)) continue;
        self.icons.append(main.allocator, .{
            .id = MinimapIcon.enemy_id,
            .x = (enemy.x - edge_x) * px_per_x,
            .y = (enemy.y - edge_y) * px_per_y,
        }) catch main.oomPanic();
    }
}

pub fn width(self: Minimap) f32 {
    return switch (self.decor) {
        .nine_slice => |nine_slice| nine_slice.w,
        .normal => |image_data| image_data.width(),
    };
}

pub fn height(self: Minimap) f32 {
    return switch (self.decor) {
        .nine_slice => |nine_slice| nine_slice.h,
        .normal => |image_data| image_data.height(),
    };
}

pub fn texWRaw(self: Minimap) f32 {
    return switch (self.decor) {
        .nine_slice => |nine_slice| nine_slice.w,
        .normal => |image_data| image_data.texWRaw(),
    };
}

pub fn texHRaw(self: Minimap) f32 {
    return switch (self.decor) {
        .nine_slice => |nine_slice| nine_slice.h,
        .normal => |image_data| image_data.texHRaw(),
    };
}
