const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const f32i = shared.utils.f32i;

const assets = @import("../../assets.zig");
const map = @import("../../game/map.zig");
const Player = @import("../../game/Player.zig");
const Bar = @import("../elements/Bar.zig");
const Container = @import("../elements/Container.zig");
const element = @import("../elements/element.zig");
const Image = @import("../elements/Image.zig");
const Item = @import("../elements/Item.zig");
const Text = @import("../elements/Text.zig");
const tooltip = @import("tooltip.zig");

const CharacterTooltip = @This();
root: *Container = undefined,

decor: *Image = undefined,
char_icon: *Image = undefined,
spirit_bar: *Bar = undefined,
items: [4]*Item = undefined,
keystone_talents: *Bar = undefined,
ability_talents: *Bar = undefined,
minor_talents: *Bar = undefined,
common_card_count: *Text = undefined,
rare_card_count: *Text = undefined,
epic_card_count: *Text = undefined,
legendary_card_count: *Text = undefined,

pub fn init(self: *CharacterTooltip) !void {
    self.decor = try self.root.createChild(Image, .{
        .base = .{ .x = 0, .y = 0 },
        .image_data = .{ .normal = .{ .atlas_data = assets.getUiData("character_tooltip", 0) } },
    });

    self.char_icon = try self.root.createChild(Image, .{
        .base = .{
            .x = 14 + (44 - assets.error_data.width() * 4.0),
            .y = 40 + (44 - assets.error_data.height() * 4.0),
        },
        .image_data = .{ .normal = .{ .atlas_data = assets.error_data, .scale_x = 4.0, .scale_y = 4.0, .glow = true } },
    });

    self.spirit_bar = try self.root.createChild(Bar, .{
        .base = .{ .x = 15, .y = 15 },
        .image_data = .{ .normal = .{ .atlas_data = assets.getUiData("character_tooltip_spirit_bar", 0) } },
        .text_data = .{
            .text = "Aether 0 - 0/0",
            .size = 10,
            .text_type = .bold_italic,
            .max_chars = 128,
        },
    });

    for (&self.items, 0..) |*item, i| {
        const x_offset = f32i(i) * 46.0;
        item.* = try self.root.createChild(Item, .{
            .base = .{
                .x = 72.0 + x_offset + (34.0 - assets.error_data.texWRaw() * 3.0) / 2,
                .y = 45.0 + (34.0 - assets.error_data.texHRaw() * 3.0) / 2,
            },
            .background_x = 66.0 + x_offset,
            .background_y = 39.0,
            .image_data = .{ .normal = .{ .scale_x = 3.0, .scale_y = 3.0, .atlas_data = assets.error_data, .glow = true } },
        });
    }

    // Keystone icon
    _ = try self.root.createChild(Image, .{
        .base = .{
            .x = 14 + (24 - assets.error_data.width() * 3.0),
            .y = 98 + (24 - assets.error_data.height() * 3.0),
        },
        .image_data = .{ .normal = .{ .atlas_data = assets.error_data, .scale_x = 3.0, .scale_y = 3.0, .glow = true } },
    });

    // Minor icon
    _ = try self.root.createChild(Image, .{
        .base = .{
            .x = 18 + (20 - assets.error_data.width() * 2.0),
            .y = 136 + (20 - assets.error_data.height() * 2.0),
        },
        .image_data = .{ .normal = .{ .atlas_data = assets.error_data, .scale_x = 2.0, .scale_y = 2.0, .glow = true } },
    });

    // Ability icon
    _ = try self.root.createChild(Image, .{
        .base = .{
            .x = 14 + (24 - assets.error_data.width() * 3.0),
            .y = 170 + (24 - assets.error_data.height() * 3.0),
        },
        .image_data = .{ .normal = .{ .atlas_data = assets.error_data, .scale_x = 3.0, .scale_y = 3.0, .glow = true } },
    });

    self.keystone_talents = try self.root.createChild(Bar, .{
        .base = .{ .x = 46, .y = 99 },
        .image_data = .{ .normal = .{ .atlas_data = assets.getUiData("character_tooltip_talent_bar_1", 0) } },
        .text_data = .{
            .text = "0% Keystone Talents unlocked",
            .size = 11,
            .text_type = .bold_italic,
            .max_chars = 128,
        },
    });

    self.ability_talents = try self.root.createChild(Bar, .{
        .base = .{ .x = 46, .y = 171 },
        .image_data = .{ .normal = .{ .atlas_data = assets.getUiData("character_tooltip_talent_bar_1", 0) } },
        .text_data = .{
            .text = "0% Ability Talents unlocked",
            .size = 11,
            .text_type = .bold_italic,
            .max_chars = 128,
        },
    });

    self.minor_talents = try self.root.createChild(Bar, .{
        .base = .{ .x = 45, .y = 137 },
        .image_data = .{ .normal = .{ .atlas_data = assets.getUiData("character_tooltip_talent_bar_2", 0) } },
        .text_data = .{
            .text = "0% Minor Talents unlocked",
            .size = 10,
            .text_type = .bold_italic,
            .max_chars = 128,
        },
    });

    const card_icons = assets.ui_atlas_data.get("character_tooltip_card_icons") orelse
        @panic("Could not find character_tooltip_card_icons in the UI atlas");
    inline for (.{
        &self.common_card_count,
        &self.rare_card_count,
        &self.epic_card_count,
        &self.legendary_card_count,
    }, 0..) |count, i| {
        count.* = try self.root.createChild(Text, .{
            .base = .{ .x = 42 + i * 60, .y = 208 },
            .text_data = .{
                .text = "",
                .size = 10,
                .max_chars = 32,
                .text_type = .bold,
                .hori_align = .middle,
                .vert_align = .middle,
                .max_width = 20,
                .max_height = 20,
            },
        });
        _ = try self.root.createChild(Image, .{
            .base = .{
                .x = 16 + i * 60 + (20 - card_icons[i].width()) / 2.0,
                .y = 208 + (20 - card_icons[i].height()) / 2.0,
            },
            .image_data = .{ .normal = .{ .atlas_data = card_icons[i] } },
        });
    }
}

pub fn deinit(self: *CharacterTooltip) void {
    element.destroy(self.root);
}

pub fn update(self: *CharacterTooltip, params: tooltip.ParamsFor(CharacterTooltip)) void {
    defer {
        const left_x = params.x - self.decor.width() - 5;
        const up_y = params.y - self.decor.height() - 5;
        self.root.base.x = if (left_x < 0) params.x + 5 else left_x;
        self.root.base.y = if (up_y < 0) params.y + 5 else up_y;
    }
    
    self.decor.image_data.normal.atlas_data = if (params.data.celestial)
        assets.getUiData("celestial_character_tooltip", 0)
    else
        assets.getUiData("character_tooltip", 0);

    setTex: {
        const data = game_data.class.from_id.get(params.data.class_id) orelse break :setTex;
        const anim_player_list = assets.anim_players.get(data.texture.sheet) orelse break :setTex;
        if (anim_player_list.len <= data.texture.index) break :setTex;
        self.char_icon.image_data.normal.atlas_data = anim_player_list[data.texture.index].walk_anims[0];
        self.char_icon.base.x = 14 + (44 - self.char_icon.width()) / 2.0;
        self.char_icon.base.y = 40 + (44 - self.char_icon.height()) / 2.0;
    }

    for (self.items, 0..) |item, i| {
        const data = game_data.item.from_id.get(params.data.equips[i]) orelse continue;
        const tex_list = assets.atlas_data.get(data.texture.sheet) orelse continue;
        if (tex_list.len <= data.texture.index) continue;
        const tex = tex_list[data.texture.index];
        item.image_data.normal.atlas_data = tex;
        
        item.background_image_data = switch (data.rarity) {
            .mythic => .{ .normal = .{ .atlas_data = assets.getUiData("mythic_slot", 0) } },
            .legendary => .{ .normal = .{ .atlas_data = assets.getUiData("legendary_slot", 0) } },
            .epic => .{ .normal = .{ .atlas_data = assets.getUiData("epic_slot", 0) } },
            .rare => .{ .normal = .{ .atlas_data = assets.getUiData("rare_slot", 0) } },
            .common => null,
        };

        const x_offset = f32i(i) * 46.0;
        item.base.x = 72.0 + x_offset + (34.0 - tex.width() * 3.0) / 2.0;
        item.base.y = 45.0 + (34.0 - tex.height() * 3.0) / 2.0;
    }

    const aether_goal = game_data.spiritGoal(params.data.aether);
    const aether_perc = f32i(params.data.spirits_communed) / f32i(aether_goal);
    self.spirit_bar.base.scissor.max_x = self.spirit_bar.texWRaw() * aether_perc;
    self.spirit_bar.text_data.setText(
        std.fmt.bufPrint(self.spirit_bar.text_data.backing_buffer, "Aether {} - {}/{}", .{
            params.data.aether,
            params.data.spirits_communed,
            aether_goal,
        }) catch "Buffer overflow",
    );

    inline for (.{
        .{ &self.common_card_count.text_data, params.data.common_card_count },
        .{ &self.rare_card_count.text_data, params.data.rare_card_count },
        .{ &self.epic_card_count.text_data, params.data.epic_card_count },
        .{ &self.legendary_card_count.text_data, params.data.legendary_card_count },
    }) |mapping| mapping[0].setText(
        std.fmt.bufPrint(mapping[0].backing_buffer, "{}", .{mapping[1]}) catch "-1",
    );

    inline for (.{
        .{
            self.keystone_talents,
            params.data.keystone_talent_perc,
            "{d:.0}% Keystone Talents unlocked",
        },
        .{
            self.ability_talents,
            params.data.ability_talent_perc,
            "{d:.0}% Ability Talents unlocked",
        },
        .{
            self.minor_talents,
            params.data.minor_talent_perc,
            "{d:.0}% Minor Talents unlocked",
        },
    }) |mapping| {
        mapping[0].text_data.setText(
            std.fmt.bufPrint(mapping[0].text_data.backing_buffer, mapping[2], .{mapping[1]}) catch "Buffer overflow",
        );
        mapping[0].base.scissor.max_x = mapping[0].texHRaw() * mapping[1];
    }
}
