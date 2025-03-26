const std = @import("std");

const game_data = @import("shared").game_data;

const assets = @import("../../assets.zig");
const map = @import("../../game/map.zig");
const Player = @import("../../game/Player.zig");
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
    locked_overlay: *Image,
    index: u8,

    pub fn create(root: *Container, index: u8) !TalentButton {
        const data = button_data[index];
        const base = try root.createChild(Container, .{ .base = .{ .x = data.x, .y = data.y } });
        const sheet_name = if (data.large) "talent_cell_big" else "talent_cell_small";
        const scale: f32 = if (data.large) 5.0 else 4.0;
        const inner_size: f32 = if (data.large) 44.0 else 34.0;

        const button = try base.createChild(Button, .{
            .base = .{ .x = 0, .y = 0 },
            .image_data = .fromImageData(
                assets.getUiData(sheet_name, 0),
                assets.getUiData(sheet_name, 1),
                assets.getUiData(sheet_name, 2),
            ),
            .pressCallback = pressCallback,
        });

        const icon = try base.createChild(Image, .{
            .base = .{
                .x = 6 + (inner_size - assets.error_data.width() * scale) / 2.0,
                .y = 6 + (inner_size - assets.error_data.height() * scale) / 2.0,
                .event_policy = .pass_all,
            },
            .image_data = .{ .normal = .{ .atlas_data = assets.error_data, .scale_x = scale, .scale_y = scale } },
        });

        const level_text = try base.createChild(Text, .{
            .base = .{
                .x = 6,
                .y = if (data.large) 62 else 52,
            },
            .text_data = .{
                .text = "",
                .size = 8,
                .max_chars = 32,
                .vert_align = .middle,
                .hori_align = .middle,
                .max_width = if (data.large) 44 else 34,
                .max_height = 12,
            },
        });

        const locked_overlay = try base.createChild(Image, .{
            .base = .{ .x = 0, .y = 0, .event_policy = .pass_all, .visible = false },
            .image_data = .{ .normal = .{
                .atlas_data = if (data.large)
                    assets.getUiData("talent_cell_big_locked", 0)
                else
                    assets.getUiData("talent_cell_small_locked", 0),
            } },
        });

        return .{
            .base = base,
            .button = button,
            .icon = icon,
            .level_text = level_text,
            .locked_overlay = locked_overlay,
            .index = index,
        };
    }

    pub fn update(self: *TalentButton, talent_level: u16, aether: u8, locked: bool, talent_data: *const game_data.TalentData) void {
        if (aether < 1) return;
        self.level_text.text_data.setText(std.fmt.bufPrint(self.level_text.text_data.backing_buffer, "Lv. {}/{}", .{
            talent_level,
            talent_data.max_level[aether - 1],
        }) catch "Buffer overflow");
        const data = button_data[self.index];
        const scale = 2.0;
        const inner_size: f32 = if (data.large) 44.0 else 34.0;
        const tex_list = assets.atlas_data.get(talent_data.icon.sheet) orelse
            assets.ui_atlas_data.get(talent_data.icon.sheet) orelse return;
        if (talent_data.icon.index > tex_list.len - 1) return;
        const icon = tex_list[talent_data.icon.index];
        self.icon.image_data = .{ .normal = .{
            .atlas_data = icon,
            .scale_x = scale,
            .scale_y = scale,
        } };
        self.icon.base.x = 6 + (inner_size - icon.width() * scale) / 2.0;
        self.icon.base.y = 6 + (inner_size - icon.height() * scale) / 2.0;
        self.locked_overlay.base.visible = locked;
        self.button.enabled = !locked;
        self.button.talent = talent_data;
        self.button.talent_index = self.index;
    }

    fn pressCallback(ud: ?*anyopaque) void {
        if (ud == null) return;
        const self: *TalentButton = @ptrCast(@alignCast(ud));
        if (map.localPlayer(.con)) |player|
            if (self.index >= 0 and self.index <= player.data.talents.len - 1)
                main.game_server.sendPacket(.{ .talent_upgrade = .{ .index = self.index } });
    }
};

const ButtonData = struct { x: f32, y: f32, large: bool };

const button_data = [_]ButtonData{
    .{ .x = 37.0, .y = 84.0, .large = true }, // Ability 1
    .{ .x = 125.0, .y = 84.0, .large = true }, // Keystone 1
    .{ .x = 205.0, .y = 88.0, .large = false }, // Minor 1-1
    .{ .x = 275.0, .y = 88.0, .large = false }, // Minor 1-2
    .{ .x = 345.0, .y = 88.0, .large = false }, // Minor 1-3
    .{ .x = 59.0, .y = 172.0, .large = true }, // Ability 2
    .{ .x = 147.0, .y = 172.0, .large = true }, // Keystone 2
    .{ .x = 227.0, .y = 176.0, .large = false }, // Minor 2-1
    .{ .x = 297.0, .y = 176.0, .large = false }, // Minor 2-2
    .{ .x = 367.0, .y = 176.0, .large = false }, // Minor 2-3
    .{ .x = 59.0, .y = 260.0, .large = true }, // Ability 3
    .{ .x = 147.0, .y = 260.0, .large = true }, // Keystone 3
    .{ .x = 227.0, .y = 264.0, .large = false }, // Minor 3-1
    .{ .x = 297.0, .y = 264.0, .large = false }, // Minor 3-2
    .{ .x = 367.0, .y = 264.0, .large = false }, // Minor 3-3
    .{ .x = 37.0, .y = 348.0, .large = true }, // Ability 4
    .{ .x = 125.0, .y = 348.0, .large = true }, // Keystone 4
    .{ .x = 205.0, .y = 352.0, .large = false }, // Minor 4-1
    .{ .x = 275.0, .y = 352.0, .large = false }, // Minor 4-2
    .{ .x = 345.0, .y = 352.0, .large = false }, // Minor 4-3
};

base: *Container = undefined,
background: *Image = undefined,
title: *Text = undefined,
decor: *Image = undefined,
buttons: [4 * (1 + 1 + 3)]TalentButton = undefined,
quit_button: *Button = undefined,

pub fn create() !*TalentView {
    var self = try main.allocator.create(TalentView);
    self.* = .{};

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
    for (&self.buttons, 0..) |*button, i| button.* = try .create(self.base, @intCast(i));
    const button_base = assets.getUiData("button_base", 0);
    self.quit_button = try self.base.createChild(Button, .{
        .base = .{ .x = (450 - button_base.width()) / 2.0, .y = 428 + (72 - button_base.height()) / 2.0 },
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

pub fn update(self: *TalentView, player: Player) void {
    for (&self.buttons, 0..) |*button, i| {
        if (player.data.talents.len <= i) return;
        const data = &player.data.talents[i];
        const talent_level = blk: {
            for (player.talents) |talent| if (talent.data_id == i) break :blk talent.count;
            break :blk 0;
        };
        const meets_reqs = blk: {
            reqLoop: for (data.requires) |req| {
                for (player.talents) |talent|
                    if (talent.data_id == req.index and talent.count >= req.level_per_aether * player.aether)
                        continue :reqLoop;
                break :blk false;
            }

            break :blk true;
        };

        button.update(talent_level, player.aether, !meets_reqs, data);
    }
}

pub fn setVisible(self: *TalentView, visible: bool) void {
    self.base.base.visible = visible;
    self.background.base.visible = visible;
}

fn quitCallback(ud: ?*anyopaque) void {
    const self: *TalentView = @ptrCast(@alignCast(ud));
    defer self.setVisible(false);
}
