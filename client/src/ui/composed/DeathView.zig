const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const network_data = shared.network_data;
const f32i = shared.utils.f32i;

const assets = @import("../../assets.zig");
const map = @import("../../game/map.zig");
const input = @import("../../input.zig");
const main = @import("../../main.zig");
const Bar = @import("../elements/Bar.zig");
const Button = @import("../elements/Button.zig");
const Container = @import("../elements/Container.zig");
const element = @import("../elements/element.zig");
const Image = @import("../elements/Image.zig");
const ScrollableContainer = @import("../elements/ScrollableContainer.zig");
const Text = @import("../elements/Text.zig");
const systems = @import("../systems.zig");

const DeathView = @This();

base: *Container = undefined,
background: *Image = undefined,
decor: *Image = undefined,
class_icon: *Image = undefined,
death_text: *Text = undefined,
aether_bar: *Bar = undefined,
keystone_bar: *Bar = undefined,
minor_bar: *Bar = undefined,
ability_bar: *Bar = undefined,
common_card_count: *Text = undefined,
rare_card_count: *Text = undefined,
epic_card_count: *Text = undefined,
legendary_card_count: *Text = undefined,
back_button: *Button = undefined,

pub fn create() !*DeathView {
    var self = try main.allocator.create(DeathView);
    self.* = .{};

    const background = assets.getUiData("dark_background", 0);
    self.background = try element.create(Image, .{
        .base = .{ .x = 0, .y = 0 },
        .image_data = .{ .nine_slice = .fromAtlasData(background, 0, 0, 0, 0, 8, 8, 1.0) },
    });

    const decor_data = assets.getUiData("death_screen_background", 0);
    const decor_x = (main.camera.width - decor_data.width()) / 2.0;
    const decor_y = (main.camera.height - decor_data.height()) / 2.0;
    self.base = try element.create(Container, .{ .base = .{ .x = decor_x, .y = decor_y } });

    self.decor = try self.base.createChild(Image, .{
        .base = .{ .x = 0, .y = 0 },
        .image_data = .{ .normal = .{ .atlas_data = decor_data } },
    });

    self.class_icon = try self.base.createChild(Image, .{
        .base = .{ .x = 24, .y = 24 },
        .image_data = .{ .normal = .{ .atlas_data = undefined, .scale_x = 4.0, .scale_y = 4.0 } },
    });
    self.death_text = try self.base.createChild(Text, .{
        .base = .{ .x = 80, .y = 24 },
        .text_data = .{
            .text = "",
            .size = 16,
            .text_type = .bold,
            .max_chars = 128,
            .vert_align = .middle,
            .hori_align = .middle,
            .max_width = 280,
            .max_height = 44,
        },
    });

    self.aether_bar = try self.base.createChild(Bar, .{
        .base = .{ .x = 25, .y = 105 },
        .image_data = .{ .normal = .{ .atlas_data = assets.getUiData("death_screen_aether_bar", 0) } },
        .text_data = .{
            .text = "",
            .size = 12,
            .text_type = .bold_italic,
            .max_chars = 64,
        },
    });

    self.keystone_bar = try self.base.createChild(Bar, .{
        .base = .{ .x = 56, .y = 149 },
        .image_data = .{ .normal = .{ .atlas_data = assets.getUiData("death_screen_talent_bar_1", 0) } },
        .text_data = .{
            .text = "",
            .size = 12,
            .text_type = .bold_italic,
            .max_chars = 64,
        },
    });

    self.minor_bar = try self.base.createChild(Bar, .{
        .base = .{ .x = 51, .y = 187 },
        .image_data = .{ .normal = .{ .atlas_data = assets.getUiData("death_screen_talent_bar_2", 0) } },
        .text_data = .{
            .text = "",
            .size = 12,
            .text_type = .bold_italic,
            .max_chars = 64,
        },
    });

    self.ability_bar = try self.base.createChild(Bar, .{
        .base = .{ .x = 56, .y = 221 },
        .image_data = .{ .normal = .{ .atlas_data = assets.getUiData("death_screen_talent_bar_1", 0) } },
        .text_data = .{
            .text = "",
            .size = 12,
            .text_type = .bold_italic,
            .max_chars = 64,
        },
    });

    self.common_card_count = try self.base.createChild(Text, .{
        .base = .{ .x = 105, .y = 268 },
        .text_data = .{
            .text = "",
            .size = 10,
            .max_chars = 8,
            .vert_align = .middle,
            .hori_align = .middle,
            .max_width = 20,
            .max_height = 20,
        },
    });

    self.rare_card_count = try self.base.createChild(Text, .{
        .base = .{ .x = 165, .y = 268 },
        .text_data = .{
            .text = "",
            .size = 10,
            .max_chars = 8,
            .vert_align = .middle,
            .hori_align = .middle,
            .max_width = 20,
            .max_height = 20,
        },
    });

    self.epic_card_count = try self.base.createChild(Text, .{
        .base = .{ .x = 225, .y = 268 },
        .text_data = .{
            .text = "",
            .size = 10,
            .max_chars = 8,
            .vert_align = .middle,
            .hori_align = .middle,
            .max_width = 20,
            .max_height = 20,
        },
    });

    self.legendary_card_count = try self.base.createChild(Text, .{
        .base = .{ .x = 285, .y = 268 },
        .text_data = .{
            .text = "",
            .size = 10,
            .max_chars = 8,
            .vert_align = .middle,
            .hori_align = .middle,
            .max_width = 20,
            .max_height = 20,
        },
    });

    const button_w = 100;
    const button_h = 40;

    const button_base = assets.getUiData("button_base", 0);
    const button_hover = assets.getUiData("button_hover", 0);
    const button_press = assets.getUiData("button_press", 0);
    self.back_button = try element.create(Button, .{
        .base = .{ .x = (main.camera.width - button_base.width()) / 2.0, .y = self.base.base.y + self.base.height() + 10, .visible = false },
        .image_data = .fromNineSlices(button_base, button_hover, button_press, button_w, button_h, 26, 19, 1, 1, 1.0),
        .text_data = .{
            .text = "Back",
            .size = 16,
            .vert_align = .middle,
            .hori_align = .middle,
            .max_width = button_base.width(),
            .max_height = button_base.height(),
        },
        .userdata = self,
        .pressCallback = backCallback,
    });

    self.resize(main.camera.width, main.camera.height);
    self.setVisible(false);
    return self;
}

pub fn destroy(self: *DeathView) void {
    element.destroy(self.background);
    element.destroy(self.base);
    element.destroy(self.back_button);
    main.allocator.destroy(self);
}

pub fn resize(self: *DeathView, w: f32, h: f32) void {
    self.background.image_data.scaleWidth(w);
    self.background.image_data.scaleHeight(h);
    self.base.base.x = (w - self.base.width()) / 2.0;
    self.base.base.y = (h - self.base.height()) / 2.0;
    self.back_button.base.x = (w - self.back_button.width()) / 2.0;
    self.back_button.base.y = self.base.base.y + self.base.height() + 10;
}

pub fn setVisible(self: *DeathView, visible: bool) void {
    self.base.base.visible = visible;
    self.background.base.visible = visible;
    self.back_button.base.visible = visible;
}

pub fn show(self: *DeathView, death_data: network_data.DeathData) !void {
    const class_data = game_data.class.from_id.get(death_data.class_id) orelse return error.InvalidClassId;
    const tex_list = assets.anim_players.get(class_data.texture.sheet) orelse return error.IconSheetNotFound;
    if (tex_list.len <= class_data.texture.index) return error.IconIndexTooLarge;
    const icon = tex_list[class_data.texture.index].walk_anims[0];

    self.class_icon.image_data.normal.atlas_data = icon;
    self.class_icon.base.x = 24 + (44 - icon.width() * 4.0) / 2.0;
    self.class_icon.base.y = 24 + (44 - icon.height() * 4.0) / 2.0;

    self.death_text.text_data.setText(
        try std.fmt.bufPrint(self.death_text.text_data.backing_buffer, "You have been killed by a &type=\"bold_it\"{s}&reset", .{death_data.killer}),
    );

    inline for (.{
        .{ "keystone", "Keystone" },
        .{ "minor", "Minor" },
        .{ "ability", "Ability" },
    }) |talent_map| {
        const perc = @field(death_data, talent_map[0] ++ "_perc");
        const bar = @field(self, talent_map[0] ++ "_bar");
        bar.image_data.normal.scale_x = perc;
        bar.text_data.setText(
            try std.fmt.bufPrint(bar.text_data.backing_buffer, "{d:.0}% " ++ talent_map[1] ++ " Talents unlocked", .{perc}),
        );
    }

    inline for (.{ "common", "rare", "epic", "legendary" }) |rarity| {
        const field_name = rarity ++ "_card_count";
        @field(self, field_name).text_data.setText(
            try std.fmt.bufPrint(@field(self, field_name).text_data.backing_buffer, "{}", .{@field(death_data, field_name)}),
        );
    }

    self.setVisible(true);
}

fn backCallback(ud: ?*anyopaque) void {
    const self: *DeathView = @ptrCast(@alignCast(ud));
    defer self.setVisible(false);
}
