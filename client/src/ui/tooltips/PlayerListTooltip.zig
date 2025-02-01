const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const f32i = shared.utils.f32i;

const assets = @import("../../assets.zig");
const map = @import("../../game/map.zig");
const main = @import("../../main.zig");
const Container = @import("../elements/Container.zig");
const element = @import("../elements/element.zig");
const Image = @import("../elements/Image.zig");
const Text = @import("../elements/Text.zig");
const tooltip = @import("tooltip.zig");
const PlayerListItem = tooltip.PlayerListItem;

const ListItem = struct {
    base: *Container,
    decor: *Image,
    icon: *Image,
    name: *Text,

    pub fn create(root: *Container, player_list_item: PlayerListItem, idx: usize) !ListItem {
        const class_data = game_data.class.from_id.get(player_list_item.data_id) orelse return error.InvalidId;
        const icon_tex_list = assets.anim_players.get(class_data.texture.sheet) orelse return error.IconSheetNotFound;
        if (icon_tex_list.len <= class_data.texture.index) return error.IconIndexTooLarge;
        const icon = icon_tex_list[class_data.texture.index].walk_anims[0];

        const base = try root.createChild(Container, .{ .base = .{ .x = 0.0, .y = f32i(idx) * 29.0 } });

        const decor = try base.createChild(Image, .{
            .base = .{ .x = 0, .y = 0 },
            .image_data = .{ .normal = .{ .atlas_data = if (player_list_item.celestial)
                assets.getUiData("celestial_player_tooltip_line", 0)
            else
                assets.getUiData("player_tooltip_line", 0) } },
        });

        const icon_elem = try base.createChild(Image, .{
            .base = .{
                .x = 6 + (12 - icon.width()) / 2.0,
                .y = 6 + (12 - icon.height()) / 2.0,
            },
            .image_data = .{ .normal = .{ .atlas_data = icon } },
        });

        const name = try base.createChild(Text, .{
            .base = .{ .x = 30, .y = 6 },
            .text_data = .{
                .text = player_list_item.name,
                .size = 10,
                .max_chars = 16,
                .vert_align = .middle,
                .hori_align = .middle,
                .max_width = 78,
                .max_height = 12,
            },
        });

        return .{
            .base = base,
            .decor = decor,
            .icon = icon_elem,
            .name = name,
        };
    }

    pub fn destroy(self: *ListItem, root: *Container) void {
        root.destroyElement(self.base);
    }
};

const PlayerListTooltip = @This();
root: *Container = undefined,

decor: *Image = undefined,
list_container: *Container = undefined,
list_items: []ListItem = &.{},

pub fn init(self: *PlayerListTooltip) !void {
    self.decor = try self.root.createChild(Image, .{
        .base = .{ .x = 0, .y = 0 },
        .image_data = .{ .nine_slice = .fromAtlasData(assets.getUiData("tooltip_background", 0), 136, 0, 34, 34, 1, 1, 1.0) },
    });

    self.list_container = try self.root.createChild(Container, .{
        .base = .{ .x = 11.0, .y = 11.0 },
    });
}

pub fn deinit(self: *PlayerListTooltip) void {
    for (self.list_items) |*list_item| list_item.destroy(self.root);
    main.allocator.free(self.list_items);
    element.destroy(self.root);
}

pub fn update(self: *PlayerListTooltip, params: tooltip.ParamsFor(PlayerListTooltip)) void {
    defer {
        const left_x = params.x - self.decor.width() - 5;
        const up_y = params.y - self.decor.height() - 5;
        self.root.base.x = if (left_x < 0) params.x + 5 else left_x;
        self.root.base.y = if (up_y < 0) params.y + 5 else up_y;
    }

    for (self.list_items) |*list_item| list_item.destroy(self.list_container);
    main.allocator.free(self.list_items);

    var list_items: std.ArrayListUnmanaged(ListItem) = .empty;
    var i: usize = 0;
    for (params.items) |player_list_item| {
        list_items.append(main.allocator, ListItem.create(self.list_container, player_list_item, i) catch continue) catch main.oomPanic();
        i += 1;
    }
    self.list_items = list_items.toOwnedSlice(main.allocator) catch main.oomPanic();

    const new_h = self.list_container.height() + 5 + 5 + 6 + 6;
    switch (self.decor.image_data) {
        .nine_slice => |*nine_slice| nine_slice.h = new_h,
        .normal => |*image_data| image_data.scale_y = new_h / image_data.height(),
    }
}
