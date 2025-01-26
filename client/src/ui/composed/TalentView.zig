const std = @import("std");

const game_data = @import("shared").game_data;

const assets = @import("../../assets.zig");
const map = @import("../../game/map.zig");
const input = @import("../../input.zig");
const main = @import("../../main.zig");
const Button = @import("../elements/Button.zig");
const Container = @import("../elements/Container.zig");
const element = @import("../elements/element.zig");
const Image = @import("../elements/Image.zig");
const Text = @import("../elements/Text.zig");
const systems = @import("../systems.zig");

const TalentView = @This();
const TalentButton = struct {
    base: *Container,
    button: *Button,
    icon: *Image,
    level_text: *Text,
    index: u8,

    pub fn create(root: *Container, comptime index: u8) !TalentButton {
        const data = button_data[index];
        const base = try root.createChild(Container, .{ .base = .{ .x = data[0], .y = data[1] } });
        const sheet_name = if (data[2]) "talent_cell_big" else "talent_cell_small";
        const scale = if (data[2]) 5.0 else 4.0;
        const inner_size = if (data[2]) 44.0 else 34.0;
        return .{
            .base = base,
            .button = try base.createChild(Button, .{
                .base = .{ .x = 0, .y = 0 },
                .image_data = .fromImageData(
                    assets.getUiData(sheet_name, 0),
                    assets.getUiData(sheet_name, 1),
                    assets.getUiData(sheet_name, 2),
                ),
                .pressCallback = pressCallback,
            }),
            .icon = try base.createChild(Image, .{
                .base = .{
                    .x = 6 + (inner_size - assets.error_data.width() * scale) / 2.0,
                    .y = 6 + (inner_size - assets.error_data.height() * scale) / 2.0,
                    .event_policy = .pass_all,
                },
                .image_data = .{ .normal = .{ .atlas_data = assets.error_data, .scale_x = scale, .scale_y = scale } },
            }),
            .level_text = try base.createChild(Text, .{
                .base = .{ .x = 6, .y = 62 },
                .text_data = .{
                    .text = "",
                    .size = 8,
                    .max_chars = 32,
                    .vert_align = .middle,
                    .hori_align = .middle,
                    .max_width = 44,
                    .max_height = 12,
                },
            }),
            .index = index,
        };
    }

    pub fn update(self: *TalentButton, talents: []game_data.TalentData) void {
        const player = map.localPlayer(.con) orelse return;
        if (self.index > button_data.len - 1 or
            self.index > talents.len - 1 or
            self.index > player.talents.len - 1) return;
        const data = talents[self.index];
        self.level_text.text_data.text = try std.fmt.bufPrint(self.level_text.text_data.backing_buffer, "{}/{}", .{
            player.talents[self.index],
            data.max_level * player.aether,
        });
        const size = if (button_data[self.index][2]) 44.0 else 32.0; // TODO: hack, this is 34 instead of 32. fix in UI later
        const tex_list = assets.atlas_data.get(data.icon.sheet) orelse return;
        if (data.icon.index > tex_list.len - 1) return;
        const icon = tex_list[data.icon.index];
        self.icon.image_data = .{ .normal = .{
            .atlas_data = icon,
            .scale_x = size / icon.width(),
            .scale_y = size / icon.height(),
        } };
    }

    fn pressCallback(ud: ?*anyopaque) void {
        if (ud == null) return;
        const self: *TalentButton = @ptrCast(@alignCast(ud));
        if (map.localPlayer(.con)) |player|
            if (self.index >= 0 and self.index <= player.data.talents.len - 1)
                main.game_server.sendPacket(.{ .talent_upgrade = .{ .index = self.index } });
    }
};

/// X | Y | Large
const button_data = .{
    .{ 37.0, 84.0, true }, // Ability 1
    .{ 125.0, 84.0, true }, // Keystone 1
    .{ 205.0, 88.0, false }, // Minor 1-1
    .{ 275.0, 88.0, false }, // Minor 1-2
    .{ 345.0, 88.0, false }, // Minor 1-3
    .{ 59.0, 172.0, true }, // Ability 2
    .{ 147.0, 172.0, true }, // Keystone 2
    .{ 227.0, 176.0, false }, // Minor 2-1
    .{ 297.0, 176.0, false }, // Minor 2-2
    .{ 367.0, 176.0, false }, // Minor 2-3
    .{ 59.0, 260.0, true }, // Ability 3
    .{ 147.0, 260.0, true }, // Keystone 3
    .{ 227.0, 264.0, false }, // Minor 3-1
    .{ 297.0, 264.0, false }, // Minor 3-2
    .{ 367.0, 264.0, false }, // Minor 3-3
    .{ 37.0, 348.0, true }, // Ability 4
    .{ 125.0, 348.0, true }, // Keystone 4
    .{ 205.0, 352.0, false }, // Minor 4-1
    .{ 275.0, 352.0, false }, // Minor 4-2
    .{ 345.0, 352.0, false }, // Minor 4-3
};

base: *Container = undefined,
background: *Image = undefined,
title: *Text = undefined,
decor: *Image = undefined,
buttons: [4 * (1 + 1 + 3)]TalentButton = undefined,
quit_button: *Button = undefined,

pub fn create() !*TalentView {
    var self = try main.allocator.create(TalentView);
    const background = assets.getUiData("dark_background", 0);
    self.background = try element.create(Image, .{
        .base = .{ .x = 0, .y = 0 },
        .image_data = .{ .nine_slice = .fromAtlasData(background, 0, 0, 0, 0, 8, 8, 1.0) },
    });

    self.base = try element.create(Container, .{ .base = .{ .x = 0, .y = 0 } });
    self.decor = try self.base.createChild(Image, .{
        .base = .{ .x = 0, .y = 0 },
        .image_data = .{ .normal = .{ .atlas_data = assets.getUiData("player_talent_tree_view", 0) } },
    });
    self.title = try self.base.createChild(Text, .{
        .base = .{ .x = 76, .y = 26 },
        .text_data = .{
            .text = "Talents",
            .size = 22,
            .text_type = .bold,
            .max_chars = 32,
            .vert_align = .middle,
            .hori_align = .middle,
            .max_width = 298,
            .max_height = 31,
        },
    });
    inline for (&self.buttons, 0..) |*button, i| button.* = try .create(self.base, @intCast(i));
    const button_base = assets.getUiData("button_base", 0);
    self.quit_button = try self.base.createChild(Button, .{
        .base = .{ .x = (450 - button_base.width()) / 2.0, .y = 418 + (72 - button_base.height()) / 2.0 },
        .image_data = .fromImageData(
            button_base,
            assets.getUiData("button_hover", 0),
            assets.getUiData("button_press", 0),
        ),
        .text_data = .{
            .text = "Quit",
            .size = 16,
            .vert_align = .middle,
            .hori_align = .middle,
            .max_width = button_base.width(),
            .max_height = button_base.height(),
        },
        .userdata = self,
        .pressCallback = quitCallback,
    });
    self.resize(main.camera.width, main.camera.height);
    self.setVisible(false);
    return self;
}

pub fn destroy(self: *TalentView) void {
    element.destroy(self.base);
    element.destroy(self.background);
    main.allocator.destroy(self);
}

pub fn resize(self: *TalentView, w: f32, h: f32) void {
    self.background.image_data.scaleWidth(w);
    self.background.image_data.scaleHeight(h);
    self.base.base.x = (w - self.base.width()) / 2.0;
    self.base.base.y = (h - self.base.height()) / 2.0;
}

pub fn setVisible(self: *TalentView, visible: bool) void {
    self.base.base.visible = visible;
    self.background.base.visible = visible;
}

fn quitCallback(ud: ?*anyopaque) void {
    const self: *TalentView = @ptrCast(@alignCast(ud));
    defer self.setVisible(false);
}
