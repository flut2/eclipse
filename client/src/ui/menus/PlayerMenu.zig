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

const PlayerMenu = @This();
root: *Container = undefined,

decor: *Image = undefined,
player_name: *Text = undefined,
char_icon: *Image = undefined,
spirit_bar: *Bar = undefined,
health_bar: *Bar = undefined,
mana_bar: *Bar = undefined,
items: [4]*Item = undefined,
line_break: *Image = undefined,
teleport_button: *Button = undefined,
teleport_button_icon: *Image = undefined,
block_button: *Button = undefined,
block_button_icon: *Image = undefined,

player_map_id: u32 = std.math.maxInt(u32),

pub fn init(self: *PlayerMenu) !void {
    self.decor = try self.root.createChild(Image, .{
        .base = .{ .x = 0, .y = 0 },
        .image_data = .{ .normal = .{ .atlas_data = assets.getUiData("player_menu", 0) } },
    });

    self.player_name = try self.root.createChild(Text, .{
        .base = .{ .x = 14, .y = 14 },
        .text_data = .{
            .text = "",
            .size = 10,
            .max_chars = 16,
            .vert_align = .middle,
            .hori_align = .middle,
            .max_width = 75,
            .max_height = 12,
        },
    });

    self.char_icon = try self.root.createChild(Image, .{
        .base = .{
            .x = 14 + (36 - assets.error_data.width() * 3.0),
            .y = 40 + (36 - assets.error_data.height() * 3.0),
        },
        .image_data = .{ .normal = .{ .atlas_data = assets.error_data, .scale_x = 3.0, .scale_y = 3.0, .glow = true } },
    });

    self.spirit_bar = try self.root.createChild(Bar, .{
        .base = .{ .x = 102, .y = 15 },
        .image_data = .{ .normal = .{ .atlas_data = assets.getUiData("player_menu_spirit_bar", 0) } },
        .text_data = .{
            .text = "Aether 0 - 0/0",
            .size = 10,
            .text_type = .bold_italic,
            .max_chars = 128,
        },
    });

    self.health_bar = try self.root.createChild(Bar, .{
        .base = .{ .x = 65, .y = 41 },
        .image_data = .{ .normal = .{ .atlas_data = assets.getUiData("player_menu_health_bar", 0) } },
        .text_data = .{
            .text = "0/0",
            .size = 10,
            .text_type = .bold_italic,
            .max_chars = 128,
        },
    });

    self.mana_bar = try self.root.createChild(Bar, .{
        .base = .{ .x = 65, .y = 65 },
        .image_data = .{ .normal = .{ .atlas_data = assets.getUiData("player_menu_mana_bar", 0) } },
        .text_data = .{
            .text = "0/0",
            .size = 10,
            .text_type = .bold_italic,
            .max_chars = 128,
        },
    });

    for (&self.items, 0..) |*item, i| {
        const x_offset = f32i(i) * 48.0;
        item.* = try self.root.createChild(Item, .{
            .base = .{
                .x = 34.0 + x_offset + (34.0 - assets.error_data.texWRaw() * 3.0) / 2,
                .y = 90.0 + (34.0 - assets.error_data.texHRaw() * 3.0) / 2,
            },
            .background_x = 28.0 + x_offset,
            .background_y = 84.0,
            .image_data = .{ .normal = .{ .scale_x = 3.0, .scale_y = 3.0, .atlas_data = assets.error_data, .glow = true } },
        });
    }

    self.line_break = try self.root.createChild(Image, .{
        .base = .{ .x = 8, .y = 133 },
        .image_data = .{ .nine_slice = .fromAtlasData(assets.getUiData("tooltip_line_spacer_top", 0), 230, 6, 16, 0, 1, 6, 1.0) },
    });

    const button_base = assets.getUiData("player_menu_buttons", 0);
    const button_hover = assets.getUiData("player_menu_buttons", 1);
    const button_press = assets.getUiData("player_menu_buttons", 2);

    self.teleport_button = try self.root.createChild(Button, .{
        .base = .{ .x = 8, .y = 133 + 2 + 6 },
        .image_data = .fromImageData(button_base, button_hover, button_press),
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

    self.block_button = try self.root.createChild(Button, .{
        .base = .{ .x = 124, .y = 133 + 2 + 6 },
        .image_data = .fromImageData(button_base, button_hover, button_press),
        .userdata = self,
        .pressCallback = blockCallback,
        .text_offset_x = 35,
        .text_offset_y = 6,
        .text_data = .{
            .text = "Block",
            .size = 14,
            .text_type = .bold,
            .hori_align = .middle,
            .vert_align = .middle,
            .max_width = 73,
            .max_height = 22,
        },
    });

    const block_icon = assets.getUiData("block_icon", 0);
    self.block_button_icon = try self.root.createChild(Image, .{
        .base = .{
            .x = self.block_button.base.x + 6 + (22 - block_icon.width()) / 2.0,
            .y = self.block_button.base.y + 6 + (22 - block_icon.height()) / 2.0,
        },
        .image_data = .{ .normal = .{ .atlas_data = block_icon } },
    });
}

fn teleportCallback(ud: ?*anyopaque) void {
    const player_menu: *PlayerMenu = @ptrCast(@alignCast(ud));
    if (player_menu.player_map_id == std.math.maxInt(u32)) return;
    main.game_server.sendPacket(.{ .teleport = .{ .player_map_id = player_menu.player_map_id } });
}

fn blockCallback(ud: ?*anyopaque) void {
    const player_menu: *PlayerMenu = @ptrCast(@alignCast(ud));
    if (player_menu.player_map_id == std.math.maxInt(u32)) return;
    // TODO
    // main.game_server.sendPacket(.{ .block = .{ .player_map_id = player_menu.player_map_id } });
}

pub fn deinit(self: *PlayerMenu) void {
    element.destroy(self.root);
}

pub fn update(self: *PlayerMenu, params: menu.ParamsFor(PlayerMenu)) void {
    self.root.base.x = params.x;
    self.root.base.y = params.y;
    self.player_map_id = params.player.map_id;

    self.player_name.text_data.setText(params.player.name orelse "");

    const is_celestial = @intFromEnum(params.player.rank) >= @intFromEnum(network_data.Rank.celestial);
    self.decor.image_data.normal.atlas_data = if (is_celestial)
        assets.getUiData("celestial_player_menu", 0)
    else
        assets.getUiData("player_menu", 0);

    setTex: {
        const data = game_data.class.from_id.get(params.player.data_id) orelse break :setTex;
        const anim_player_list = assets.anim_players.get(data.texture.sheet) orelse break :setTex;
        if (anim_player_list.len <= data.texture.index) break :setTex;
        self.char_icon.image_data.normal.atlas_data = anim_player_list[data.texture.index].walk_anims[0];
        self.char_icon.base.x = 14 + (36 - self.char_icon.width()) / 2.0;
        self.char_icon.base.y = 40 + (36 - self.char_icon.height()) / 2.0;
    }

    for (self.items, 0..) |item, i| {
        const data_id = params.player.inventory[i];
        const data = game_data.item.from_id.get(data_id) orelse continue;
        const tex_list = assets.atlas_data.get(data.texture.sheet) orelse continue;
        if (tex_list.len <= data.texture.index) continue;
        const tex = tex_list[data.texture.index];
        item.data_id = data_id;
        item.item_data = params.player.inv_data[i];
        item.image_data.normal.atlas_data = tex;

        item.background_image_data = switch (data.rarity) {
            .mythic => .{ .normal = .{ .atlas_data = assets.getUiData("mythic_slot", 0) } },
            .legendary => .{ .normal = .{ .atlas_data = assets.getUiData("legendary_slot", 0) } },
            .epic => .{ .normal = .{ .atlas_data = assets.getUiData("epic_slot", 0) } },
            .rare => .{ .normal = .{ .atlas_data = assets.getUiData("rare_slot", 0) } },
            .common => null,
        };

        const x_offset = f32i(i) * 48.0;
        item.base.x = 34.0 + x_offset + (34.0 - tex.width() * 3.0) / 2.0;
        item.base.y = 90.0 + (34.0 - tex.height() * 3.0) / 2.0;
    }

    const aether_goal = game_data.spiritGoal(params.player.aether);
    const aether_perc = f32i(params.player.spirits_communed) / f32i(aether_goal);
    self.spirit_bar.base.scissor.max_x = self.spirit_bar.texWRaw() * aether_perc;
    self.spirit_bar.text_data.setText(
        std.fmt.bufPrint(self.spirit_bar.text_data.backing_buffer, "Aether {} - {}/{}", .{
            params.player.aether,
            params.player.spirits_communed,
            aether_goal,
        }) catch "Buffer overflow",
    );

    const hp_perc = f32i(params.player.hp) / f32i(params.player.max_hp + params.player.max_hp_bonus);
    self.health_bar.base.scissor.max_x = self.health_bar.texWRaw() * hp_perc;

    var health_text_data = &self.health_bar.text_data;
    if (params.player.max_hp_bonus > 0) {
        health_text_data.setText(std.fmt.bufPrint(health_text_data.backing_buffer, "{}/{} &size=\"10\"&col=\"65E698\"(+{})", .{
            params.player.hp,
            params.player.max_hp + params.player.max_hp_bonus,
            params.player.max_hp_bonus,
        }) catch "Buffer overflow");
    } else if (params.player.max_hp_bonus < 0) {
        health_text_data.setText(std.fmt.bufPrint(health_text_data.backing_buffer, "{}/{} &size=\"10\"&col=\"FF7070\"({})", .{
            params.player.hp,
            params.player.max_hp + params.player.max_hp_bonus,
            params.player.max_hp_bonus,
        }) catch "Buffer overflow");
    } else {
        health_text_data.setText(
            std.fmt.bufPrint(health_text_data.backing_buffer, "{}/{}", .{ params.player.hp, params.player.max_hp }) catch "Buffer overflow",
        );
    }

    const mp_perc = f32i(params.player.mp) / f32i(params.player.max_mp + params.player.max_mp_bonus);
    self.mana_bar.base.scissor.max_x = self.mana_bar.texWRaw() * mp_perc;

    var mana_text_data = &self.mana_bar.text_data;
    if (params.player.max_mp_bonus > 0) {
        mana_text_data.setText(std.fmt.bufPrint(mana_text_data.backing_buffer, "{}/{} &size=\"10\"&col=\"65E698\"(+{})", .{
            params.player.mp,
            params.player.max_mp + params.player.max_mp_bonus,
            params.player.max_mp_bonus,
        }) catch "Buffer overflow");
    } else if (params.player.max_mp_bonus < 0) {
        mana_text_data.setText(std.fmt.bufPrint(mana_text_data.backing_buffer, "{}/{} &size=\"10\"&col=\"FF7070\"({})", .{
            params.player.mp,
            params.player.max_mp + params.player.max_mp_bonus,
            params.player.max_mp_bonus,
        }) catch "Buffer overflow");
    } else {
        mana_text_data.setText(
            std.fmt.bufPrint(mana_text_data.backing_buffer, "{}/{}", .{ params.player.mp, params.player.max_mp }) catch "Buffer overflow",
        );
    }
}
