const std = @import("std");

const glfw = @import("glfw");
const shared = @import("shared");
const game_data = shared.game_data;
const network_data = shared.network_data;
const utils = shared.utils;
const f32i = utils.f32i;

const assets = @import("../../assets.zig");
const Camera = @import("../../Camera.zig");
const Ally = @import("../../game/Ally.zig");
const Container = @import("../../game/Container.zig");
const Enemy = @import("../../game/Enemy.zig");
const map = @import("../../game/map.zig");
const Player = @import("../../game/Player.zig");
const Portal = @import("../../game/Portal.zig");
const main = @import("../../main.zig");
const Renderer = @import("../../render/Renderer.zig");
const menu = @import("../menus/menu.zig");
const tooltip = @import("../tooltips/tooltip.zig");
const element = @import("element.zig");
const ElementBase = element.ElementBase;

const MinimapIcon = struct {
    const self_id = 0;
    const portal_id = 1;
    const player_id = 3;
    const enemy_id = 4;
    const elite_id = 8;
    const ally_id = 9;
    const common_container_id = 10;
    const rare_container_id = 11;
    const epic_container_id = 12;
    const legendary_container_id = 13;
    const mythic_container_id = 14;

    x: f32,
    y: f32,
    id: u8,
    map_id: u32 = std.math.maxInt(u32),
};

const Minimap = @This();
base: ElementBase,
decor: element.ImageData,
offset_x: f32 = 0.0,
offset_y: f32 = 0.0,
map_width: f32 = 0.0,
map_height: f32 = 0.0,
icons: std.ArrayListUnmanaged(MinimapIcon) = .empty,
last_update: i64 = -1,
list_items: [9]tooltip.PlayerListItem = undefined,
list_item_idx: usize = 0,
first_list_map_id: u32 = std.math.maxInt(u32),
first_list_rank: network_data.Rank = .default,

pub fn mouseMove(self: *Minimap, x: f32, y: f32, x_offset: f32, y_offset: f32) bool {
    if (!self.base.visible) return false;

    if (menu.current.* == .teleport) {
        const in_bounds = element.intersects(self, x, y);
        return !(self.base.event_policy.pass_move or !in_bounds);
    }

    self.first_list_rank = .default;
    self.first_list_map_id = std.math.maxInt(u32);
    self.list_item_idx = 0;
    for (self.icons.items) |icon|
        if (icon.id == MinimapIcon.player_id and utils.distSqr(
            self.base.x + self.offset_x + icon.x,
            self.base.y + self.offset_y + icon.y,
            x,
            y,
        ) < 20 * 20) {
            const player = map.findObjectCon(Player, icon.map_id) orelse continue;
            self.list_items[self.list_item_idx] = .{
                .data_id = player.data_id,
                .name = player.name orelse "Unknown",
                .celestial = @intFromEnum(player.rank) >= @intFromEnum(network_data.Rank.celestial),
            };
            if (self.list_item_idx == 0) {
                self.first_list_map_id = player.map_id;
                self.first_list_rank = player.rank;
            }
            self.list_item_idx += 1;
            if (self.list_item_idx == self.list_items.len) break;
        };

    if (self.list_item_idx > 0)
        tooltip.switchTooltip(.player_list, .{
            .x = x + x_offset,
            .y = y + y_offset,
            .items = self.list_items[0..self.list_item_idx],
        });

    const in_bounds = element.intersects(self, x, y);
    return !(self.base.event_policy.pass_move or !in_bounds);
}

pub fn mousePress(self: *Minimap, x: f32, y: f32, _: f32, _: f32, _: glfw.Mods) bool {
    if (!self.base.visible) return false;

    if (menu.current.* != .teleport and self.list_item_idx > 0) {
        tooltip.switchTooltip(.none, {});
        menu.switchMenu(.teleport, .{
            .x = x,
            .y = y,
            .map_id = self.first_list_map_id,
            .rank = self.first_list_rank,
            .data_id = self.list_items[0].data_id,
            .name = self.list_items[0].name,
        });
        return true;
    }

    const in_bounds = element.intersects(self, x, y);
    return !(self.base.event_policy.pass_press or !in_bounds);
}

pub fn deinit(self: *Minimap) void {
    self.icons.deinit(main.allocator);
}

pub fn draw(
    self: *Minimap,
    generics: *std.ArrayListUnmanaged(Renderer.GenericData),
    sort_extras: *std.ArrayListUnmanaged(f32),
    x_offset: f32,
    y_offset: f32,
    _: i64,
) void {
    if (!self.base.visible) return;

    self.decor.draw(generics, sort_extras, self.base.x + x_offset, self.base.y + y_offset, self.base.scissor);

    const fw = f32i(map.info.width);
    const fh = f32i(map.info.height);
    const fminimap_w = f32i(map.minimap.width);
    const fminimap_h = f32i(map.minimap.height);
    const zoom = main.camera.minimap_zoom;
    const uv_size = .{ fw / zoom / fminimap_w, fh / zoom / fminimap_h };
    generics.append(main.allocator, .{
        .render_type = .minimap,
        .pos = .{
            self.base.x + self.offset_x + x_offset + assets.padding,
            self.base.y + self.offset_y + y_offset + assets.padding,
        },
        .size = .{ self.map_width, self.map_height },
        .uv = .{ main.camera.x / fminimap_w - uv_size[0] / 2.0, main.camera.y / fminimap_h - uv_size[1] / 2.0 },
        .uv_size = uv_size,
    }) catch main.oomPanic();

    const player_icon = assets.minimap_icons[MinimapIcon.self_id];
    const scale = 2.0;
    const player_icon_w = player_icon.texWRaw() * scale;
    const player_icon_h = player_icon.texHRaw() * scale;
    Renderer.drawQuad(
        generics,
        sort_extras,
        self.base.x + self.offset_x + x_offset + (self.map_width - player_icon_w) / 2.0,
        self.base.y + self.offset_y + y_offset + (self.map_height - player_icon_h) / 2.0,
        player_icon_w,
        player_icon_h,
        player_icon,
        .{ .shadow_texel_mult = 0.5, .scissor = self.base.scissor },
    );

    for (self.icons.items) |icon| {
        const icon_data = assets.minimap_icons[icon.id];
        const icon_w = icon_data.width() * scale;
        const icon_h = icon_data.height() * scale;
        Renderer.drawQuad(
            generics,
            sort_extras,
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

    self.icons.clearRetainingCapacity();

    const fw = f32i(map.info.width);
    const fh = f32i(map.info.height);
    const zoom = main.camera.minimap_zoom;
    const x = main.camera.x;
    const y = main.camera.y;
    const vis_w = fw / zoom;
    const vis_h = fh / zoom;
    const edge_x = x - vis_w / 2.0;
    const edge_y = y - vis_h / 2.0;
    const px_per_x = self.map_width / vis_w;
    const px_per_y = self.map_height / vis_h;

    for (map.listForType(Portal).items) |portal| {
        if (utils.distSqr(portal.x, portal.y, x, y) > 16 * 16) continue;
        if (!utils.isInBounds(portal.x, portal.y, edge_x, edge_y, vis_w, vis_h)) continue;
        self.icons.append(main.allocator, .{
            .id = MinimapIcon.portal_id,
            .x = (portal.x - edge_x) * px_per_x,
            .y = (portal.y - edge_y) * px_per_y,
        }) catch main.oomPanic();
    }

    for (map.listForType(Ally).items) |ally| {
        if (utils.distSqr(ally.x, ally.y, x, y) > 16 * 16) continue;
        if (!utils.isInBounds(ally.x, ally.y, edge_x, edge_y, vis_w, vis_h)) continue;
        self.icons.append(main.allocator, .{
            .id = MinimapIcon.ally_id,
            .x = (ally.x - edge_x) * px_per_x,
            .y = (ally.y - edge_y) * px_per_y,
        }) catch main.oomPanic();
    }

    for (map.listForType(Container).items) |container| {
        if (utils.distSqr(container.x, container.y, x, y) > 16 * 16) continue;
        if (!utils.isInBounds(container.x, container.y, edge_x, edge_y, vis_w, vis_h)) continue;
        self.icons.append(main.allocator, .{
            .id = @intCast(MinimapIcon.common_container_id + container.data_id),
            .x = (container.x - edge_x) * px_per_x,
            .y = (container.y - edge_y) * px_per_y,
        }) catch main.oomPanic();
    }

    for (map.listForType(Player).items) |player| {
        if (player.map_id == map.info.player_map_id or
            !utils.isInBounds(player.x, player.y, edge_x, edge_y, vis_w, vis_h)) continue;
        self.icons.append(main.allocator, .{
            .id = MinimapIcon.player_id,
            .x = (player.x - edge_x) * px_per_x,
            .y = (player.y - edge_y) * px_per_y,
            .map_id = player.map_id,
        }) catch main.oomPanic();
    }

    for (map.listForType(Enemy).items) |enemy| {
        if (!enemy.data.elite and utils.distSqr(enemy.x, enemy.y, x, y) > 16 * 16) continue;
        if (!utils.isInBounds(enemy.x, enemy.y, edge_x, edge_y, vis_w, vis_h)) continue;
        self.icons.append(main.allocator, .{
            .id = if (enemy.data.elite) MinimapIcon.elite_id else MinimapIcon.enemy_id,
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
