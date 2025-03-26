const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const network_data = shared.network_data;
const f32i = shared.utils.f32i;

const assets = @import("../../assets.zig");
const map = @import("../../game/map.zig");
const input = @import("../../input.zig");
const main = @import("../../main.zig");
const Button = @import("../elements/Button.zig");
const Container = @import("../elements/Container.zig");
const element = @import("../elements/element.zig");
const Image = @import("../elements/Image.zig");
const ScrollableContainer = @import("../elements/ScrollableContainer.zig");
const Text = @import("../elements/Text.zig");
const systems = @import("../systems.zig");

const CharacterCreate = @This();
const ClassButton = struct {
    char_create: *CharacterCreate,
    base: *Container,
    button: *Button,
    class_icon: *Image,
    class_id: u16,

    pub fn create(self: *ClassButton, char_create: *CharacterCreate, x: f32, y: f32, data: *const game_data.ClassData) !ClassButton {
        const tex_list = assets.anim_players.get(data.texture.sheet) orelse return error.IconSheetNotFound;
        if (tex_list.len <= data.texture.index) return error.IconIndexTooLarge;
        const icon = tex_list[data.texture.index].walk_anims[0];

        const base = try char_create.base.createChild(Container, .{ .base = .{ .x = x, .y = y } });

        return .{
            .char_create = char_create,
            .base = base,
            .button = try base.createChild(Button, .{
                .base = .{ .x = 0, .y = 0 },
                .image_data = .fromImageData(
                    assets.getUiData("character_create_class_button_background", 0),
                    assets.getUiData("character_create_class_button_background", 1),
                    assets.getUiData("character_create_class_button_background", 2),
                ),
                .userdata = self,
                .pressCallback = buttonCallback,
            }),
            .class_icon = try base.createChild(Image, .{
                .base = .{ .x = 6 + (64 - icon.width() * 5.0) / 2.0, .y = 6 + (64 - icon.height() * 5.0) / 2.0 },
                .image_data = .{ .normal = .{ .atlas_data = icon, .scale_x = 5.0, .scale_y = 5.0 } },
            }),
            .class_id = data.id,
        };
    }

    fn buttonCallback(ud: ?*anyopaque) void {
        const self: *ClassButton = @alignCast(@ptrCast(ud));
        const data = game_data.class.from_id.get(self.class_id) orelse {
            std.log.err("Class with data id {} is missing, creation select failed", .{self.class_id});
            return;
        };
        self.char_create.selected_class = self.class_id;

        self.char_create.class_icon.image_data.normal.atlas_data = self.class_icon.image_data.normal.atlas_data;
        self.char_create.class_icon.base.x = 193 + (44 - self.char_create.class_icon.width()) / 2.0;
        self.char_create.class_icon.base.y = 61 + (44 - self.char_create.class_icon.height()) / 2.0;
        self.char_create.class_name.text_data.setText(data.name);
        self.char_create.class_desc.text_data.setText(data.description);

        for (self.char_create.ability_icons, 0..) |ability_icon, i| {
            const ability = data.abilities[i];
            if (assets.ui_atlas_data.get(ability.icon.sheet)) |tex_data| {
                const index = ability.icon.index;
                if (tex_data.len <= index) {
                    std.log.err("Index {} is out of bound {} for \"{s}\"'s ability", .{ index, tex_data.len, data.name });
                    return;
                }

                ability_icon.image_data.normal.atlas_data = tex_data[index];
                ability_icon.ability_data = ability;
            } else {
                std.log.err("Sheet {s} missing for \"{s}\"'s ability", .{ ability.icon.sheet, data.name });
                return;
            }
        }

        inline for (.{
            "health",
            "mana",
            "strength",
            "wit",
            "defense",
            "resistance",
            "stamina",
            "intelligence",
            "speed",
            "haste",
        }, 0..) |field, i| self.char_create.stat_texts[i].text_data.setText(
            std.fmt.bufPrint(self.char_create.stat_texts[i].text_data.backing_buffer, "{}", .{@field(data.stats, field)}) catch "-1",
        );

        for (self.char_create.talent_icons, 0..) |talent_icon, i| {
            const talent_data = data.talents[i];
            const inner_size: f32 = if (i % 5 < 2) 44.0 else 34.0;
            const tex_list = assets.atlas_data.get(talent_data.icon.sheet) orelse
                assets.ui_atlas_data.get(talent_data.icon.sheet) orelse {
                std.log.err("Sheet {s} missing for \"{s}\"'s talent", .{ talent_data.icon.sheet, data.name });
                return;
            };
            if (talent_data.icon.index > tex_list.len - 1) {
                std.log.err("Index {} is out of bound {} for \"{s}\"'s ability", .{ talent_data.icon.index, tex_list.len, data.name });
                return;
            }
            const icon = tex_list[talent_data.icon.index];
            talent_icon.image_data.normal.atlas_data = icon;
            const x_offsets: [5]f32 = .{ 0, 62, 124, 176, 228 };
            const base_x = 698 + x_offsets[i % 5];
            const base_y = 61 + f32i(i / 5) * 70 + @as(f32, (if (i % 5 >= 2) 5 else 0));
            talent_icon.base.x = base_x + (inner_size - icon.width() * 2.0) / 2.0;
            talent_icon.base.y = base_y + (inner_size - icon.height() * 2.0) / 2.0;
            talent_icon.talent_data = &data.talents[i];
            talent_icon.talent_index = @intCast(i);
        }

        inline for (.{ "class_icon", "class_name", "class_desc" }) |field|
            @field(self.char_create, field).base.visible = true;

        inline for (.{ "ability_icons", "stat_texts", "talent_icons" }) |field| {
            for (@field(self.char_create, field)) |elem| elem.base.visible = true;
        }
    }
};

base: *Container = undefined,
background: *Image = undefined,
decor: *Image = undefined,
class_buttons: []ClassButton = &.{},
class_icon: *Image = undefined,
class_name: *Text = undefined,
class_desc: *Text = undefined,
ability_icons: [4]*Image = @splat(undefined),
stat_texts: [10]*Text = @splat(undefined),
talent_icons: [20]*Image = @splat(undefined),
select_button: *Button = undefined,
back_button: *Button = undefined,
selected_class: u16 = std.math.maxInt(u16),

pub fn create() !*CharacterCreate {
    var self = try main.allocator.create(CharacterCreate);
    self.* = .{};

    const background = assets.getUiData("dark_background", 0);
    self.background = try element.create(Image, .{
        .base = .{ .x = 0, .y = 0 },
        .image_data = .{ .nine_slice = .fromAtlasData(background, 0, 0, 0, 0, 8, 8, 1.0) },
    });

    const decor_data = assets.getUiData("character_create_background", 0);
    const decor_x = (main.camera.width - decor_data.width()) / 2.0;
    const decor_y = (main.camera.height - decor_data.height()) / 2.0;
    self.base = try element.create(Container, .{ .base = .{ .x = decor_x, .y = decor_y } });

    self.decor = try self.base.createChild(Image, .{
        .base = .{ .x = 0, .y = 0 },
        .image_data = .{ .normal = .{ .atlas_data = decor_data } },
    });

    self.class_buttons = main.allocator.alloc(ClassButton, game_data.class.from_id.size) catch main.oomPanic();
    var iter = game_data.class.from_id.valueIterator();
    for (self.class_buttons, 0..) |*class_button, i| {
        const data = iter.next() orelse continue;
        class_button.* = try class_button.create(self, 30, 30 + f32i(i) * 120, data);
    }

    self.class_icon = try self.base.createChild(Image, .{
        .base = .{ .x = 193, .y = 61, .visible = false },
        .image_data = .{ .normal = .{ .atlas_data = undefined, .scale_x = 4.0, .scale_y = 4.0 } },
    });
    self.class_name = try self.base.createChild(Text, .{
        .base = .{ .x = 249, .y = 61, .visible = false },
        .text_data = .{
            .text = "",
            .size = 16,
            .text_type = .bold,
            .max_chars = 32,
            .vert_align = .middle,
            .hori_align = .middle,
            .max_width = 138,
            .max_height = 44,
        },
    });
    self.class_desc = try self.base.createChild(Text, .{
        .base = .{ .x = 187, .y = 129, .visible = false },
        .text_data = .{
            .text = "",
            .size = 16,
            .text_type = .medium_italic,
            .max_chars = 256,
            .vert_align = .middle,
            .hori_align = .middle,
            .max_width = 205,
            .max_height = 118,
        },
    });

    for (&self.ability_icons, 0..) |*ability_icon, i|
        ability_icon.* = try self.base.createChild(Image, .{
            .base = .{ .x = 184 + 56 * f32i(i), .y = 271, .visible = false },
            .image_data = .{ .normal = .{ .atlas_data = undefined, .scale_x = 2.0, .scale_y = 2.0 } },
        });

    for (&self.stat_texts, 0..) |*stat_text, i|
        stat_text.* = try self.base.createChild(Text, .{
            .base = .{ .x = 486 + f32i(i % 2) * 107, .y = 70 + f32i(i / 2) * 50, .visible = false },
            .text_data = .{
                .text = "",
                .size = 18,
                .text_type = .medium,
                .max_chars = 32,
                .vert_align = .middle,
                .hori_align = .middle,
                .max_width = 52,
                .max_height = 36,
            },
        });

    for (&self.talent_icons, 0..) |*talent_icon, i| {
        const x_offsets: [5]f32 = .{ 0, 62, 124, 176, 228 };
        talent_icon.* = try self.base.createChild(Image, .{
            .base = .{
                .x = 698 + x_offsets[i % 5],
                .y = 61 + f32i(i / 5) * 70 + @as(f32, (if (i % 5 >= 2) 5 else 0)),
                .visible = false,
            },
            .image_data = .{ .normal = .{ .atlas_data = undefined, .scale_x = 2.0, .scale_y = 2.0 } },
        });
    }

    const button_w = 100;
    const button_h = 40;

    const button_base = assets.getUiData("button_base", 0);
    const button_hover = assets.getUiData("button_hover", 0);
    const button_press = assets.getUiData("button_press", 0);
    self.select_button = try element.create(Button, .{
        .base = .{ .x = decor_x, .y = decor_y + decor_data.height() + 5, .visible = false },
        .image_data = .fromNineSlices(button_base, button_hover, button_press, button_w, button_h, 26, 19, 1, 1, 1.0),
        .text_data = .{
            .text = "Select",
            .size = 16,
            .vert_align = .middle,
            .hori_align = .middle,
            .max_width = button_base.width(),
            .max_height = button_base.height(),
        },
        .userdata = self,
        .pressCallback = selectCallback,
    });
    self.back_button = try element.create(Button, .{
        .base = .{ .x = self.select_button.base.x + self.select_button.width() + 5, .y = self.select_button.base.y, .visible = false },
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

pub fn destroy(self: *CharacterCreate) void {
    element.destroy(self.background);
    element.destroy(self.base);
    element.destroy(self.select_button);
    element.destroy(self.back_button);
    main.allocator.destroy(self);
}

pub fn resize(self: *CharacterCreate, w: f32, h: f32) void {
    self.background.image_data.scaleWidth(w);
    self.background.image_data.scaleHeight(h);
    self.base.base.x = (w - self.base.width()) / 2.0;
    self.base.base.y = (h - self.base.height()) / 2.0;
    self.select_button.base.x = self.base.base.x;
    self.select_button.base.y = self.base.base.y + self.base.height() + 5;
    self.back_button.base.x = self.select_button.base.x + self.select_button.width() + 5;
    self.back_button.base.y = self.select_button.base.y;
}

pub fn setVisible(self: *CharacterCreate, visible: bool) void {
    self.base.base.visible = visible;
    self.background.base.visible = visible;
    self.select_button.base.visible = visible;
    self.back_button.base.visible = visible;
}

fn classSwitchCallback(ud: ?*anyopaque) void {
    const self: *CharacterCreate = @ptrCast(@alignCast(ud));
    defer self.setVisible(false);
}

fn backCallback(ud: ?*anyopaque) void {
    const self: *CharacterCreate = @ptrCast(@alignCast(ud));
    defer self.setVisible(false);
}

fn selectCallback(ud: ?*anyopaque) void {
    const self: *CharacterCreate = @ptrCast(@alignCast(ud));
    if (self.selected_class == std.math.maxInt(u16)) return;
    defer self.setVisible(false);

    if (main.character_list) |*list| if (list.servers.len > 0) {
        main.enterGame(list.servers[0], list.next_char_id, self.selected_class);
        list.next_char_id += 1;
        return;
    };

    // TODO: dialog for failure
}
