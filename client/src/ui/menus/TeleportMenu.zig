const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const network_data = shared.network_data;
const f32i = shared.utils.f32i;

const assets = @import("../../assets.zig");
const map = @import("../../game/map.zig");
const Player = @import("../../game/Player.zig");
const main = @import("../../main.zig");
const Bar = @import("../elements/Bar.zig");
const Button = @import("../elements/Button.zig");
const Container = @import("../elements/Container.zig");
const element = @import("../elements/element.zig");
const Image = @import("../elements/Image.zig");
const Item = @import("../elements/Item.zig");
const Text = @import("../elements/Text.zig");
const menu = @import("menu.zig");

const TeleportMenu = @This();
root: *Container = undefined,

decor: *Image = undefined,
player_decor: *Image = undefined,
player_name: *Text = undefined,
char_icon: *Image = undefined,
teleport_button: *Button = undefined,
teleport_button_icon: *Image = undefined,

player_map_id: u32 = std.math.maxInt(u32),

pub fn init(self: *TeleportMenu) !void {
    self.decor = try self.root.createChild(Image, .{
        .base = .{ .x = 0, .y = 0 },
        .image_data = .{ .nine_slice = .fromAtlasData(assets.getUiData("tooltip_background", 0), 130, 76, 34, 34, 1, 1, 1.0) },
    });

    self.player_decor = try self.root.createChild(Image, .{
        .base = .{ .x = 8, .y = 8 },
        .image_data = .{ .normal = .{ .atlas_data = assets.getUiData("player_tooltip_line", 0) } },
    });

    self.player_name = try self.root.createChild(Text, .{
        .base = .{
            .x = self.player_decor.base.x + 30,
            .y = self.player_decor.base.y + 6,
        },
        .text_data = .{
            .text = "",
            .size = 10,
            .max_chars = 16,
            .vert_align = .middle,
            .hori_align = .middle,
            .max_width = 78,
            .max_height = 12,
        },
    });

    self.char_icon = try self.root.createChild(Image, .{
        .base = .{
            .x = self.player_decor.base.x + 6 + (12 - assets.error_data.width()),
            .y = self.player_decor.base.y + 6 + (12 - assets.error_data.height()),
        },
        .image_data = .{ .normal = .{ .atlas_data = assets.error_data, .glow = true } },
    });

    self.teleport_button = try self.root.createChild(Button, .{
        .base = .{ .x = 8, .y = 34 },
        .image_data = .fromImageData(
            assets.getUiData("player_menu_buttons", 0),
            assets.getUiData("player_menu_buttons", 1),
            assets.getUiData("player_menu_buttons", 2),
        ),
        .userdata = self,
        .pressCallback = teleportCallback,
        .text_offset_x = 35,
        .text_offset_y = 6,
        .text_data = .{
            .text = "Teleport",
            .size = 14,
            .text_type = .bold,
            .hori_align = .middle,
            .vert_align = .middle,
            .max_width = 73,
            .max_height = 22,
        },
    });

    const teleport_icon = assets.getUiData("teleport_icon", 0);
    self.teleport_button_icon = try self.root.createChild(Image, .{
        .base = .{
            .x = self.teleport_button.base.x + 6 + (22 - teleport_icon.width()) / 2.0,
            .y = self.teleport_button.base.y + 6 + (22 - teleport_icon.height()) / 2.0,
        },
        .image_data = .{ .normal = .{ .atlas_data = teleport_icon } },
    });
}

fn teleportCallback(ud: ?*anyopaque) void {
    const player_menu: *TeleportMenu = @ptrCast(@alignCast(ud));
    if (player_menu.player_map_id == std.math.maxInt(u32)) return;
    main.game_server.sendPacket(.{ .teleport = .{ .player_map_id = player_menu.player_map_id } });
}

pub fn deinit(self: *TeleportMenu) void {
    element.destroy(self.root);
}

pub fn update(self: *TeleportMenu, params: menu.ParamsFor(TeleportMenu)) void {
    self.root.base.x = params.x;
    self.root.base.y = params.y;
    self.player_map_id = params.map_id;

    self.player_name.text_data.setText(params.name);

    const is_celestial = @intFromEnum(params.rank) >= @intFromEnum(network_data.Rank.celestial);
    self.player_decor.image_data.normal.atlas_data = if (is_celestial)
        assets.getUiData("celestial_player_tooltip_line", 0)
    else
        assets.getUiData("player_tooltip_line", 0);

    setTex: {
        const data = game_data.class.from_id.get(params.data_id) orelse break :setTex;
        const anim_player_list = assets.anim_players.get(data.texture.sheet) orelse break :setTex;
        if (anim_player_list.len <= data.texture.index) break :setTex;
        self.char_icon.image_data.normal.atlas_data = anim_player_list[data.texture.index].walk_anims[0];
        self.char_icon.base.x = self.player_decor.base.x + 6 + (12 - self.char_icon.width()) / 2.0;
        self.char_icon.base.y = self.player_decor.base.y + 6 + (12 - self.char_icon.height()) / 2.0;
    }
}
