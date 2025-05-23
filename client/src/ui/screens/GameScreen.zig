const std = @import("std");

const shared = @import("shared");
const utils = shared.utils;
const game_data = shared.game_data;
const network_data = shared.network_data;
const f32i = utils.f32i;
const i64f = utils.i64f;
const ItemData = network_data.ItemData;

const assets = @import("../../assets.zig");
const Container = @import("../../game/Container.zig");
const map = @import("../../game/map.zig");
const Player = @import("../../game/Player.zig");
const input = @import("../../input.zig");
const main = @import("../../main.zig");
const CardSelection = @import("../composed/CardSelection.zig");
const Options = @import("../composed/Options.zig");
const ResourceView = @import("../composed/ResourceView.zig");
const TalentView = @import("../composed/TalentView.zig");
const Bar = @import("../elements/Bar.zig");
const Button = @import("../elements/Button.zig");
const UiContainer = @import("../elements/Container.zig");
const element = @import("../elements/element.zig");
const Image = @import("../elements/Image.zig");
const Input = @import("../elements/Input.zig");
const Item = @import("../elements/Item.zig");
const Minimap = @import("../elements/Minimap.zig");
const ScrollableContainer = @import("../elements/ScrollableContainer.zig");
const Text = @import("../elements/Text.zig");
const systems = @import("../systems.zig");

const GameScreen = @This();

pub const ItemRect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    w_pad: f32,
    h_pad: f32,
};

pub const Slot = struct {
    idx: u8,
    is_container: bool = false,

    fn findInvSlotId(screen: GameScreen, x: f32, y: f32) u8 {
        for (0..screen.inventory_items.len) |i| {
            const data = screen.inventory_pos_data[i];
            if (utils.isInBounds(
                x,
                y,
                screen.inventory_decor.base.x + data.x - data.w_pad,
                screen.inventory_decor.base.y + data.y - data.h_pad,
                data.w + data.w_pad * 2,
                data.h + data.h_pad * 2,
            )) return @intCast(i);
        }

        return 255;
    }

    fn findContainerSlotId(screen: GameScreen, x: f32, y: f32) u8 {
        if (!systems.screen.game.container_visible) return 255;

        for (0..screen.container_items.len) |i| {
            const data = screen.container_pos_data[i];
            if (utils.isInBounds(
                x,
                y,
                screen.container_decor.base.x + data.x - data.w_pad,
                screen.container_decor.base.y + data.y - data.h_pad,
                data.w + data.w_pad * 2,
                data.h + data.h_pad * 2,
            )) return @intCast(i);
        }

        return 255;
    }

    pub fn findSlotId(screen: GameScreen, x: f32, y: f32) Slot {
        const inv_slot = findInvSlotId(screen, x, y);
        if (inv_slot != 255) return .{ .idx = inv_slot };

        const container_slot = findContainerSlotId(screen, x, y);
        if (container_slot != 255) return .{ .idx = container_slot, .is_container = true };

        return .{ .idx = 255 };
    }

    pub fn nextEquippableSlot(item_types: []const game_data.ItemType, item_type: game_data.ItemType) Slot {
        for (0..22) |idx| {
            if (idx >= 4 or item_types[idx].typesMatch(item_type)) return .{ .idx = @intCast(idx) };
        }
        return .{ .idx = 255 };
    }

    pub fn nextAvailableSlot(screen: GameScreen, item_types: []const game_data.ItemType, item_type: game_data.ItemType) Slot {
        for (0..screen.inventory_items.len) |idx| {
            if (screen.inventory_items[idx].data_id == std.math.maxInt(u16) and
                (idx >= 4 or item_types[idx].typesMatch(item_type)))
                return .{ .idx = @intCast(idx) };
        }
        return .{ .idx = 255 };
    }
};

const CardSlot = struct {
    base: *UiContainer,
    decor: *Image,
    title: *Text,
    data_id: u16 = std.math.maxInt(u16),

    pub fn create(root: *UiContainer, x: f32, y: f32) !CardSlot {
        const decor_image = assets.getUiData("empty_card_slot", 0);
        const base = try root.createChild(UiContainer, .{ .base = .{ .x = x, .y = y } });
        const decor = try base.createChild(Image, .{
            .base = .{ .x = 0.0, .y = 0.0 },
            .image_data = .{ .normal = .{ .atlas_data = decor_image } },
            .tooltip_text = .{
                .text = "Empty Card Slot",
                .size = 16,
                .text_type = .bold_italic,
                .max_width = 200,
            },
        });
        return .{
            .base = base,
            .decor = decor,
            .title = try base.createChild(Text, .{
                .base = .{ .x = 0.0, .y = 0.0, .visible = false },
                .text_data = .{
                    .text = "",
                    .size = 10,
                    .text_type = .bold,
                    .max_chars = 64,
                    .hori_align = .middle,
                    .vert_align = .middle,
                    .max_width = decor.width(),
                    .max_height = decor.height(),
                },
            }),
        };
    }

    pub fn setCard(self: *CardSlot, data_id: u16) !void {
        if (self.data_id == data_id) return;
        self.data_id = data_id;

        if (data_id == std.math.maxInt(u16)) {
            self.title.base.visible = false;
            self.decor.image_data.normal.atlas_data = assets.getUiData("empty_card_slot", 0);
            self.decor.card_data = null;
            self.decor.tooltip_text = .{
                .text = "Empty Card Slot",
                .size = 16,
                .text_type = .bold_italic,
                .max_width = 200,
            };
            return;
        }

        const data = game_data.card.from_id.get(data_id) orelse return;
        self.title.text_data.color = switch (data.rarity) {
            .mythic => 0xE54E4E,
            .legendary => 0xE5B84E,
            .epic => 0x9F50E5,
            .rare => 0x5066E5,
            .common => 0xE5CCAC,
        };
        self.title.text_data.setText(data.name);
        self.title.base.visible = true;

        self.decor.image_data.normal.atlas_data = switch (data.rarity) {
            .mythic => assets.getUiData("mythic_card_slot", 0),
            .legendary => assets.getUiData("legendary_card_slot", 0),
            .epic => assets.getUiData("epic_card_slot", 0),
            .rare => assets.getUiData("rare_card_slot", 0),
            .common => assets.getUiData("common_card_slot", 0),
        };
        if (self.decor.tooltip_text) |*text_data| text_data.deinit();
        self.decor.tooltip_text = null;
        self.decor.card_data = data;
    }
};

fps_text: *Text = undefined,
chat_input: *Input = undefined,
chat_decor: *Image = undefined,
chat_container: *ScrollableContainer = undefined,
chat_lines: std.ArrayListUnmanaged(*Text) = .empty,
bars_decor: *Image = undefined,
stats_button: *Button = undefined,
cards_button: *Button = undefined,
talents_button: *Button = undefined,
resources_button: *Button = undefined,
stats_container: *UiContainer = undefined,
cards_container: *UiContainer = undefined,
ability_container: *UiContainer = undefined,
ability_overlays: [4]*Image = undefined,
ability_cd_overlays: [4]*Image = undefined,
ability_cd_overlay_texts: [4]*Text = undefined,

stats_decor: *Image = undefined,
cards_decor: *Image = undefined,
cards_text: *Text = undefined,
left_card_flipper: *Button = undefined,
right_card_flipper: *Button = undefined,
card_slots: []CardSlot = &.{},
strength_stat_text: *Text = undefined,
wit_stat_text: *Text = undefined,
defense_stat_text: *Text = undefined,
resistance_stat_text: *Text = undefined,
speed_stat_text: *Text = undefined,
stamina_stat_text: *Text = undefined,
intelligence_stat_text: *Text = undefined,
haste_stat_text: *Text = undefined,
health_bar: *Bar = undefined,
mana_bar: *Bar = undefined,
spirit_bar: *Bar = undefined,
inventory_decor: *Image = undefined,
inventory_items: [22]*Item = undefined,
container_decor: *Image = undefined,
container_name: *Text = undefined,
container_items: [9]*Item = undefined,
minimap: *Minimap = undefined,
gold_text: *Text = undefined,
gems_text: *Text = undefined,

options: *Options = undefined,
card_selection: *CardSelection = undefined,
talent_view: *TalentView = undefined,
resource_view: *ResourceView = undefined,

inventory_pos_data: [22]ItemRect = undefined,
container_pos_data: [9]ItemRect = undefined,
container_visible: bool = false,
container_id: u32 = std.math.maxInt(u32),
abilities_inited: bool = false,
card_page: u8 = 1,
last_aether: u8 = std.math.maxInt(u8),
last_spirits_communed: u32 = std.math.maxInt(u32),
last_hp: i32 = -1,
last_max_hp_bonus: i32 = -1,
last_mp: i32 = -1,
last_max_mp_bonus: i32 = -1,
last_card_count: i32 = -1,
last_gold: u32 = std.math.maxInt(u32),
last_gems: u32 = std.math.maxInt(u32),
last_resources: []const network_data.DataIdWithCount(u32) = &.{.{ .count = std.math.maxInt(u32), .data_id = std.math.maxInt(u16) }},
last_talents: []const network_data.DataIdWithCount(u16) = &.{.{ .count = std.math.maxInt(u16), .data_id = std.math.maxInt(u16) }},

pub fn init(self: *GameScreen) !void {
    const inventory_data = assets.getUiData("player_inventory", 0);
    self.parseItemRects();

    const minimap_decor = assets.getUiData("minimap", 0);
    self.minimap = try element.create(Minimap, .{
        .base = .{ .x = main.camera.width - minimap_decor.width() + 10, .y = -10 },
        .decor = .{ .normal = .{ .atlas_data = minimap_decor } },
        .offset_x = 21.0,
        .offset_y = 21.0,
        .map_width = 212.0,
        .map_height = 212.0,
    });

    self.gold_text = try element.create(Text, .{
        .base = .{ .x = self.minimap.base.x + 47, .y = self.minimap.base.y + 244 },
        .text_data = .{
            .text = "",
            .size = 10,
            .max_chars = 32,
            .vert_align = .middle,
            .hori_align = .middle,
            .max_width = 75,
            .max_height = 22,
        },
    });

    self.gems_text = try element.create(Text, .{
        .base = .{ .x = self.minimap.base.x + 159, .y = self.minimap.base.y + 244 },
        .text_data = .{
            .text = "",
            .size = 10,
            .max_chars = 32,
            .vert_align = .middle,
            .hori_align = .middle,
            .max_width = 75,
            .max_height = 22,
        },
    });

    self.inventory_decor = try element.create(Image, .{
        .base = .{
            .x = main.camera.width - inventory_data.width() + 10,
            .y = main.camera.height - inventory_data.height() + 10,
        },
        .image_data = .{ .normal = .{ .atlas_data = inventory_data } },
    });

    for (0..self.inventory_items.len) |i| {
        const scale: f32 = if (i < 4) 4.0 else 3.0;
        self.inventory_items[i] = try element.create(Item, .{
            .base = .{
                .x = self.inventory_decor.base.x + self.inventory_pos_data[i].x +
                    (self.inventory_pos_data[i].w - assets.error_data.texWRaw() * scale) / 2 + assets.padding,
                .y = self.inventory_decor.base.y + self.inventory_pos_data[i].y +
                    (self.inventory_pos_data[i].h - assets.error_data.texHRaw() * scale) / 2 + assets.padding,
                .visible = false,
            },
            .background_x = self.inventory_decor.base.x + self.inventory_pos_data[i].x,
            .background_y = self.inventory_decor.base.y + self.inventory_pos_data[i].y,
            .amount_text = .{ .text = "", .size = 10, .max_chars = 8, .color = 0xD2D2D2 },
            .image_data = .{ .normal = .{ .scale_x = scale, .scale_y = scale, .atlas_data = assets.error_data, .glow = true } },
            .draggable = true,
            .dragStartCallback = itemDragStartCallback,
            .dragEndCallback = itemDragEndCallback,
            .doubleClickCallback = itemDoubleClickCallback,
            .shiftClickCallback = itemShiftClickCallback,
        });
    }

    const container_data = assets.getUiData("container_view", 0);
    self.container_decor = try element.create(Image, .{
        .base = .{
            .x = self.inventory_decor.base.x - container_data.width() + 10,
            .y = main.camera.height - container_data.height() + 10,
            .visible = false,
        },
        .image_data = .{ .normal = .{ .atlas_data = container_data } },
    });

    self.container_name = try element.create(Text, .{
        .base = .{ .x = self.container_decor.base.x + 21, .y = self.container_decor.base.y + 159 },
        .text_data = .{
            .text = "",
            .size = 14,
            .vert_align = .middle,
            .hori_align = .middle,
            .max_width = 126,
            .max_height = 18,
        },
    });

    for (0..self.container_items.len) |i| {
        self.container_items[i] = try element.create(Item, .{
            .base = .{
                .x = self.container_decor.base.x + self.container_pos_data[i].x +
                    (self.container_pos_data[i].w - assets.error_data.texWRaw() * 3.0) / 2 + assets.padding,
                .y = self.container_decor.base.y + self.container_pos_data[i].y +
                    (self.container_pos_data[i].h - assets.error_data.texHRaw() * 3.0) / 2 + assets.padding,
                .visible = false,
            },
            .background_x = self.container_decor.base.x + self.container_pos_data[i].x,
            .background_y = self.container_decor.base.y + self.container_pos_data[i].y,
            .amount_text = .{ .text = "", .size = 10, .max_chars = 8, .color = 0xD2D2D2 },
            .image_data = .{ .normal = .{ .scale_x = 3.0, .scale_y = 3.0, .atlas_data = assets.error_data, .glow = true } },
            .draggable = true,
            .dragStartCallback = itemDragStartCallback,
            .dragEndCallback = itemDragEndCallback,
            .doubleClickCallback = itemDoubleClickCallback,
            .shiftClickCallback = itemShiftClickCallback,
        });
    }

    const bars_data = assets.getUiData("player_abilities_bars", 0);
    self.bars_decor = try element.create(Image, .{
        .base = .{
            .x = (main.camera.width - bars_data.width()) / 2 - 44,
            .y = main.camera.height - bars_data.height() + 10,
        },
        .image_data = .{ .normal = .{ .atlas_data = bars_data } },
    });

    const health_bar_data = assets.getUiData("player_health_bar", 0);
    self.health_bar = try element.create(Bar, .{
        .base = .{ .x = self.bars_decor.base.x + 114, .y = self.bars_decor.base.y + 102 },
        .image_data = .{ .normal = .{ .atlas_data = health_bar_data } },
        .text_data = .{
            .text = "",
            .size = 12,
            .text_type = .bold_italic,
            .max_chars = 64,
        },
    });

    const mana_bar_data = assets.getUiData("player_mana_bar", 0);
    self.mana_bar = try element.create(Bar, .{
        .base = .{ .x = self.bars_decor.base.x + 114, .y = self.bars_decor.base.y + 132 },
        .image_data = .{ .normal = .{ .atlas_data = mana_bar_data } },
        .text_data = .{
            .text = "",
            .size = 12,
            .text_type = .bold_italic,
            .max_chars = 64,
        },
    });

    const spirit_bar_data = assets.getUiData("player_spirit_bar", 0);
    self.spirit_bar = try element.create(Bar, .{
        .base = .{ .x = self.bars_decor.base.x + 114, .y = self.bars_decor.base.y + 22 },
        .image_data = .{ .normal = .{ .atlas_data = spirit_bar_data } },
        .text_data = .{
            .text = "",
            .size = 10,
            .text_type = .bold_italic,
            .max_chars = 64,
        },
    });

    const talents_button_base = assets.getUiData("talent_view_button", 0);
    self.talents_button = try element.create(Button, .{
        .base = .{
            .x = self.bars_decor.base.x + 65 + (32 - talents_button_base.width() + assets.padding * 2) / 2.0,
            .y = self.bars_decor.base.y + 73 + (32 - talents_button_base.height() + assets.padding * 2) / 2.0,
        },
        .image_data = .fromImageData(
            talents_button_base,
            assets.getUiData("talent_view_button", 1),
            assets.getUiData("talent_view_button", 2),
        ),
        .userdata = self,
        .pressCallback = talentsCallback,
    });

    const resources_button_base = assets.getUiData("resource_view_button", 0);
    self.resources_button = try element.create(Button, .{
        .base = .{
            .x = self.bars_decor.base.x + 65 + (32 - resources_button_base.width() + assets.padding * 2) / 2.0,
            .y = self.bars_decor.base.y + 117 + (32 - resources_button_base.height() + assets.padding * 2) / 2.0,
        },
        .image_data = .fromImageData(
            resources_button_base,
            assets.getUiData("resource_view_button", 1),
            assets.getUiData("resource_view_button", 2),
        ),
        .userdata = self,
        .pressCallback = resourcesCallback,
    });

    const cards_button_base = assets.getUiData("cards_button", 0);
    self.cards_button = try element.create(Button, .{
        .base = .{
            .x = self.bars_decor.base.x + 22 + (32 - cards_button_base.width() + assets.padding * 2) / 2.0,
            .y = self.bars_decor.base.y + 73 + (32 - cards_button_base.height() + assets.padding * 2) / 2.0,
        },
        .image_data = .fromImageData(
            cards_button_base,
            assets.getUiData("cards_button", 1),
            assets.getUiData("cards_button", 2),
        ),
        .userdata = self,
        .pressCallback = cardsCallback,
    });

    const cards_decor_data = assets.getUiData("card_panel_bg", 0);
    self.cards_container = try element.create(UiContainer, .{ .base = .{
        .x = self.bars_decor.base.x + 107 - 15,
        .y = self.bars_decor.base.y + 15 - cards_decor_data.height(),
        .visible = false,
    } });

    self.cards_decor = try self.cards_container.createChild(Image, .{
        .base = .{ .x = 0, .y = 0 },
        .image_data = .{ .normal = .{ .atlas_data = cards_decor_data } },
    });

    self.cards_text = try self.cards_container.createChild(Text, .{
        .base = .{ .x = 21, .y = 21 },
        .text_data = .{
            .text = "Cards - 1/1",
            .size = 16,
            .text_type = .bold_italic,
            .hori_align = .middle,
            .vert_align = .middle,
            .max_width = 212,
            .max_height = 24,
            .max_chars = 32,
        },
    });

    const left_flipper_normal = assets.getUiData("card_panel_buttons", 0);
    const left_flipper_hover = assets.getUiData("card_panel_buttons", 2);
    const left_flipper_press = assets.getUiData("card_panel_buttons", 4);
    self.left_card_flipper = try self.cards_container.createChild(Button, .{
        .base = .{ .x = 132, .y = 105 },
        .image_data = .fromImageData(left_flipper_normal, left_flipper_hover, left_flipper_press),
        .disabled_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("card_panel_buttons", 6) } },
        .userdata = self,
        .enabled = false,
        .pressCallback = leftCardFlipperCallback,
    });

    const right_flipper_normal = assets.getUiData("card_panel_buttons", 1);
    const right_flipper_hover = assets.getUiData("card_panel_buttons", 3);
    const right_flipper_press = assets.getUiData("card_panel_buttons", 5);
    self.right_card_flipper = try self.cards_container.createChild(Button, .{
        .base = .{ .x = 181, .y = 105 },
        .image_data = .fromImageData(right_flipper_normal, right_flipper_hover, right_flipper_press),
        .disabled_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("card_panel_buttons", 7) } },
        .userdata = self,
        .enabled = false,
        .pressCallback = rightCardFlipperCallback,
    });

    const stats_button_base = assets.getUiData("stats_button", 0);
    const stats_button_hover = assets.getUiData("stats_button", 1);
    const stats_button_press = assets.getUiData("stats_button", 2);
    self.stats_button = try element.create(Button, .{
        .base = .{
            .x = self.bars_decor.base.x + 22 + (32 - stats_button_base.width() + assets.padding * 2) / 2.0,
            .y = self.bars_decor.base.y + 117 + (32 - stats_button_base.height() + assets.padding * 2) / 2.0,
        },
        .image_data = .fromImageData(stats_button_base, stats_button_hover, stats_button_press),
        .userdata = self,
        .pressCallback = statsCallback,
    });

    const stats_decor_data = assets.getUiData("player_stats", 0);
    self.stats_container = try element.create(UiContainer, .{ .base = .{
        .x = self.bars_decor.base.x + 107 - 15,
        .y = self.bars_decor.base.y + 15 - stats_decor_data.height(),
        .visible = false,
    } });

    self.stats_decor = try self.stats_container.createChild(Image, .{
        .base = .{ .x = 0, .y = 0 },
        .image_data = .{ .normal = .{ .atlas_data = stats_decor_data } },
    });

    var idx: f32 = 0;
    try addStatText(self.stats_container, &self.strength_stat_text, &idx);
    try addStatText(self.stats_container, &self.wit_stat_text, &idx);
    try addStatText(self.stats_container, &self.defense_stat_text, &idx);
    try addStatText(self.stats_container, &self.resistance_stat_text, &idx);
    try addStatText(self.stats_container, &self.stamina_stat_text, &idx);
    try addStatText(self.stats_container, &self.intelligence_stat_text, &idx);
    try addStatText(self.stats_container, &self.speed_stat_text, &idx);
    try addStatText(self.stats_container, &self.haste_stat_text, &idx);

    self.ability_container = try element.create(UiContainer, .{ .base = .{
        .x = self.bars_decor.base.x + 113,
        .y = self.bars_decor.base.y + 45,
    } });

    const chat_data = assets.getUiData("chatbox_background", 0);
    const input_data = assets.getUiData("chatbox_input", 0);
    self.chat_decor = try element.create(Image, .{
        .base = .{
            .x = -10,
            .y = main.camera.height - chat_data.height() - input_data.height() + 15,
        },
        .image_data = .{ .normal = .{ .atlas_data = chat_data } },
    });

    const cursor_data = assets.getUiData("chatbox_cursor", 0);
    self.chat_input = try element.create(Input, .{
        .base = .{
            .x = self.chat_decor.base.x,
            .y = self.chat_decor.base.y + self.chat_decor.height() - 10,
        },
        .text_inlay_x = 21,
        .text_inlay_y = 21,
        .image_data = .{ .base = .{ .normal = .{ .atlas_data = input_data } } },
        .cursor_image_data = .{ .normal = .{ .atlas_data = cursor_data } },
        .text_data = .{
            .text = "",
            .size = 12,
            .text_type = .bold,
            .max_chars = 256,
            .handle_special_chars = false,
        },
        .enterCallback = chatCallback,
        .is_chat = true,
    });

    const scroll_background_data = assets.getUiData("scroll_background", 0);
    const scroll_knob_base = assets.getUiData("scroll_wheel_base", 0);
    const scroll_knob_hover = assets.getUiData("scroll_wheel_hover", 0);
    const scroll_knob_press = assets.getUiData("scroll_wheel_press", 0);
    const scroll_decor_data = assets.getUiData("scrollbar_decor", 0);
    self.chat_container = try element.create(ScrollableContainer, .{
        .base = .{ .x = self.chat_decor.base.x + 24, .y = self.chat_decor.base.y + 24 },
        .scissor_w = 380,
        .scissor_h = 240,
        .scroll_x = 376,
        .scroll_y = 0,
        .scroll_w = 4,
        .scroll_h = 240,
        .scroll_side_x = 369,
        .scroll_side_y = 0,
        .scroll_decor_image_data = .{ .nine_slice = .fromAtlasData(scroll_background_data, 4, 240, 0, 0, 2, 2, 1.0) },
        .scroll_knob_image_data = .fromNineSlices(scroll_knob_base, scroll_knob_hover, scroll_knob_press, 10, 16, 4, 4, 1, 2, 1.0),
        .scroll_side_decor_image_data = .{ .nine_slice = .fromAtlasData(scroll_decor_data, 6, 240, 0, 41, 6, 3, 1.0) },
        .start_value = 1.0,
    });

    self.fps_text = try element.create(Text, .{
        .base = .{
            .x = self.minimap.base.x,
            .y = self.minimap.base.y + self.minimap.height() - 10,
        },
        .text_data = .{
            .text = "",
            .size = 12,
            .text_type = .bold,
            .hori_align = .middle,
            .max_width = self.minimap.width(),
            .max_chars = 256,
        },
    });

    self.options = try .create();
    self.card_selection = try .create();
    self.talent_view = try .create();
    self.resource_view = try .create();
}

pub fn addChatLine(self: *GameScreen, name: []const u8, text: []const u8, name_color: u32, text_color: u32) !void {
    const container_h = self.chat_container.container.height();

    const line_str = try if (name.len > 0)
        std.fmt.allocPrint(main.allocator, "&col=\"{x}\"[{s}]: &col=\"{x}\"{s}", .{ name_color, name, text_color, text })
    else
        std.fmt.allocPrint(main.allocator, "&col=\"{x}\"{s}", .{ text_color, text });

    var chat_line = try self.chat_container.createChild(Text, .{
        .base = .{ .x = 0, .y = 0 },
        .text_data = .{
            .text = line_str,
            .size = 12,
            .text_type = .bold,
            .max_width = 370,
            .backing_buffer = line_str, // putting it here to dispose automatically. kind of a hack
        },
    });

    const line_h = chat_line.height();
    const total_h = container_h + line_h;
    if (self.chat_container.scissor_h >= total_h) {
        chat_line.base.y = self.chat_container.scissor_h - line_h;
        for (self.chat_lines.items) |line| line.base.y -= line_h;
    } else {
        chat_line.base.y = container_h;
        const first_line_y = if (self.chat_lines.items.len == 0) 0 else self.chat_lines.items[0].base.y;
        if (first_line_y > 0) {
            for (self.chat_lines.items) |line| line.base.y -= first_line_y;
        }
    }

    try self.chat_lines.append(main.allocator, chat_line);
    self.chat_container.update();
}

fn addAbility(self: *GameScreen, ability: game_data.AbilityData, idx: usize) !void {
    const fidx = f32i(idx);

    if (assets.ui_atlas_data.get(ability.icon.sheet)) |data| {
        const index = ability.icon.index;
        if (data.len <= index) @panic("Could not initiate ability for GameScreen, index was out of bounds");

        _ = try self.ability_container.createChild(Image, .{
            .base = .{ .x = fidx * 56.0, .y = 0.0 },
            .image_data = .{ .normal = .{ .atlas_data = data[index], .scale_x = 2.0, .scale_y = 2.0 } },
            .ability_data = ability,
        });
    } else @panic("Could not initiate ability for GameScreen, sheet was missing");

    self.ability_cd_overlays[idx] = try self.ability_container.createChild(Image, .{
        .base = .{ .x = fidx * 56.0, .y = 0.0, .visible = false, .event_policy = .pass_all },
        .image_data = .{ .normal = .{ .atlas_data = assets.getUiData("on_cooldown_slot", 0) } },
    });

    self.ability_cd_overlay_texts[idx] = try self.ability_container.createChild(Text, .{
        .base = .{ .x = fidx * 56.0, .y = 0.0, .visible = false, .event_policy = .pass_all },
        .text_data = .{
            .text = "",
            .size = 12.0,
            .text_type = .bold,
            .hori_align = .middle,
            .vert_align = .middle,
            .max_chars = 32,
            .max_width = 44.0,
            .max_height = 44.0,
        },
    });

    self.ability_overlays[idx] = try self.ability_container.createChild(Image, .{
        .base = .{ .x = fidx * 56.0, .y = 0.0, .visible = false, .event_policy = .pass_all },
        .image_data = undefined,
    });
}

fn addStatText(container: *UiContainer, text: **Text, idx: *f32) !void {
    defer idx.* += 1;

    const x = 54.0 + 105.0 * @mod(idx.*, 2.0);
    const y = 27.0 + 28.0 * @floor(idx.* / 2.0);
    text.* = try container.createChild(Text, .{ .base = .{ .x = x, .y = y }, .text_data = .{
        .text = "",
        .size = 12,
        .text_type = .bold,
        .max_width = 64,
        .max_height = 18,
        .hori_align = .middle,
        .vert_align = .middle,
        .max_chars = 64,
    } });
}

pub fn deinit(self: *GameScreen) void {
    element.destroy(self.minimap);
    element.destroy(self.gold_text);
    element.destroy(self.gems_text);
    element.destroy(self.inventory_decor);
    element.destroy(self.container_decor);
    element.destroy(self.container_name);
    element.destroy(self.bars_decor);
    element.destroy(self.resources_button);
    element.destroy(self.talents_button);
    element.destroy(self.cards_button);
    element.destroy(self.cards_container);
    element.destroy(self.stats_button);
    element.destroy(self.stats_container);
    element.destroy(self.ability_container);
    element.destroy(self.chat_container);
    element.destroy(self.health_bar);
    element.destroy(self.mana_bar);
    element.destroy(self.spirit_bar);
    element.destroy(self.chat_decor);
    element.destroy(self.chat_input);
    element.destroy(self.fps_text);
    for (self.inventory_items) |item| element.destroy(item);
    for (self.container_items) |item| element.destroy(item);

    self.chat_lines.deinit(main.allocator);
    self.options.destroy();
    self.card_selection.destroy();
    self.talent_view.destroy();
    self.resource_view.destroy();

    main.allocator.free(self.card_slots);
    main.allocator.destroy(self);
}

pub fn resize(self: *GameScreen, w: f32, h: f32) void {
    self.minimap.base.x = w - self.minimap.width() + 10;
    self.gold_text.base.x = self.minimap.base.x + 47;
    self.gold_text.base.y = self.minimap.base.y + 244;
    self.gems_text.base.x = self.minimap.base.x + 159;
    self.gems_text.base.y = self.minimap.base.y + 244;
    self.fps_text.base.x = self.minimap.base.x;
    self.fps_text.base.y = self.minimap.base.y + self.minimap.height() - 10;
    self.inventory_decor.base.x = w - self.inventory_decor.width() + 10;
    self.inventory_decor.base.y = h - self.inventory_decor.height() + 10;
    self.container_decor.base.x = self.inventory_decor.base.x - self.container_decor.width() + 10;
    self.container_decor.base.y = h - self.container_decor.height() + 10;
    self.container_name.base.x = self.container_decor.base.x + 21;
    self.container_name.base.y = self.container_decor.base.y + 159;
    self.bars_decor.base.x = (w - self.bars_decor.width()) / 2;
    self.bars_decor.base.y = h - self.bars_decor.height() + 10;
    self.stats_container.base.x = self.bars_decor.base.x + 108 - 15;
    self.stats_container.base.y = self.bars_decor.base.y + 15 - self.stats_decor.height();
    self.cards_container.base.x = self.bars_decor.base.x + 108 - 15;
    self.cards_container.base.y = self.bars_decor.base.y + 15 - self.cards_decor.height();
    self.ability_container.base.x = self.bars_decor.base.x + 113;
    self.ability_container.base.y = self.bars_decor.base.y + 45;
    self.talents_button.base.x = self.bars_decor.base.x + 65 + (32 - self.talents_button.width() + assets.padding * 2) / 2.0;
    self.talents_button.base.y = self.bars_decor.base.y + 73 + (32 - self.talents_button.height() + assets.padding * 2) / 2.0;
    self.resources_button.base.x = self.bars_decor.base.x + 65 + (32 - self.resources_button.width() + assets.padding * 2) / 2.0;
    self.resources_button.base.y = self.bars_decor.base.y + 117 + (32 - self.resources_button.height() + assets.padding * 2) / 2.0;
    self.cards_button.base.x = self.bars_decor.base.x + 22 + (32 - self.cards_button.width() + assets.padding * 2) / 2.0;
    self.cards_button.base.y = self.bars_decor.base.y + 73 + (32 - self.cards_button.height() + assets.padding * 2) / 2.0;
    self.stats_button.base.x = self.bars_decor.base.x + 22 + (32 - self.stats_button.width() + assets.padding * 2) / 2.0;
    self.stats_button.base.y = self.bars_decor.base.y + 117 + (32 - self.stats_button.height() + assets.padding * 2) / 2.0;
    self.health_bar.base.x = self.bars_decor.base.x + 114;
    self.health_bar.base.y = self.bars_decor.base.y + 102;
    self.mana_bar.base.x = self.bars_decor.base.x + 114;
    self.mana_bar.base.y = self.bars_decor.base.y + 132;
    self.spirit_bar.base.x = self.bars_decor.base.x + 114;
    self.spirit_bar.base.y = self.bars_decor.base.y + 22;
    const chat_decor_h = self.chat_decor.height();
    self.chat_decor.base.y = h - chat_decor_h - self.chat_input.image_data.current(self.chat_input.state).normal.height() + 15;
    self.chat_container.container.base.x = self.chat_decor.base.x + 26;
    const old_y = self.chat_container.base_y;
    self.chat_container.base_y = self.chat_decor.base.y + 26;
    self.chat_container.container.base.y += (self.chat_container.base_y - old_y);
    self.chat_container.scroll_bar.base.x = self.chat_decor.base.x + 400;
    self.chat_container.scroll_bar.base.y = self.chat_decor.base.y + 24;
    if (self.chat_container.hasScrollDecor()) {
        self.chat_container.scroll_bar_decor.base.x = self.chat_decor.base.x + 393;
        self.chat_container.scroll_bar_decor.base.y = self.chat_decor.base.y + 24;
    }
    self.chat_input.base.y = self.chat_decor.base.y + chat_decor_h - 10;

    for (0..self.inventory_items.len) |idx| {
        self.inventory_items[idx].base.x = self.inventory_decor.base.x +
            systems.screen.game.inventory_pos_data[idx].x + (systems.screen.game.inventory_pos_data[idx].w - self.inventory_items[idx].texWRaw()) / 2;
        self.inventory_items[idx].base.y = self.inventory_decor.base.y +
            systems.screen.game.inventory_pos_data[idx].y + (systems.screen.game.inventory_pos_data[idx].h - self.inventory_items[idx].texHRaw()) / 2;
        self.inventory_items[idx].background_x = self.inventory_decor.base.x + systems.screen.game.inventory_pos_data[idx].x;
        self.inventory_items[idx].background_y = self.inventory_decor.base.y + systems.screen.game.inventory_pos_data[idx].y;
    }

    for (0..self.container_items.len) |idx| {
        self.container_items[idx].base.x = self.container_decor.base.x +
            systems.screen.game.container_pos_data[idx].x + (systems.screen.game.container_pos_data[idx].w - self.container_items[idx].texWRaw()) / 2;
        self.container_items[idx].base.y = self.container_decor.base.y +
            systems.screen.game.container_pos_data[idx].y + (systems.screen.game.container_pos_data[idx].h - self.container_items[idx].texHRaw()) / 2;
        self.container_items[idx].background_x = self.container_decor.base.x + systems.screen.game.container_pos_data[idx].x;
        self.container_items[idx].background_y = self.container_decor.base.y + systems.screen.game.container_pos_data[idx].y;
    }

    self.options.resize(w, h);
    self.card_selection.resize(w, h);
    self.talent_view.resize(w, h);
    self.resource_view.resize(w, h);
}

pub fn update(self: *GameScreen, time: i64, _: f32) !void {
    self.fps_text.base.visible = main.settings.stats_enabled;

    if (map.localPlayerCon()) |local_player| {
        if (!self.abilities_inited) {
            for (0..4) |i| try addAbility(self, local_player.data.abilities[i], i);
            self.abilities_inited = true;
        }

        for (0..4) |i| {
            const time_elapsed = time - local_player.last_ability_use[i];
            const cooldown_us = i64f(local_player.data.abilities[i].cooldown /
                (1.0 + f32i(local_player.data.stats.haste + local_player.haste_bonus) / 150.0) * std.time.us_per_s);
            if (time_elapsed < cooldown_us) {
                const cooldown_left = f32i(cooldown_us - time_elapsed) / std.time.us_per_s;

                self.ability_cd_overlays[i].image_data.normal.scissor.max_x =
                    self.ability_cd_overlays[i].texWRaw() * (cooldown_left / (f32i(cooldown_us) / std.time.us_per_s));

                self.ability_cd_overlay_texts[i].text_data.setText(try std.fmt.bufPrint(
                    self.ability_cd_overlay_texts[i].text_data.backing_buffer,
                    "{d:.1}s",
                    .{cooldown_left},
                ));

                self.ability_cd_overlays[i].base.visible = true;
                self.ability_cd_overlay_texts[i].base.visible = true;
            } else {
                self.ability_cd_overlays[i].base.visible = false;
                self.ability_cd_overlay_texts[i].base.visible = false;
            }

            const mana_cost = local_player.data.abilities[i].mana_cost;
            if (mana_cost != 0 and mana_cost > local_player.mp) {
                self.ability_overlays[i].image_data = .{ .normal = .{ .atlas_data = assets.getUiData("out_of_mana_slot", 0) } };
                self.ability_overlays[i].base.visible = true;
                continue;
            }

            const health_cost = local_player.data.abilities[i].health_cost;
            if (health_cost != 0 and health_cost > local_player.hp) {
                self.ability_overlays[i].image_data = .{ .normal = .{ .atlas_data = assets.getUiData("out_of_health_slot", 0) } };
                self.ability_overlays[i].base.visible = true;
                continue;
            }

            const gold_cost = local_player.data.abilities[i].gold_cost;
            if (gold_cost != 0 and gold_cost > local_player.gold) {
                self.ability_overlays[i].image_data = .{ .normal = .{ .atlas_data = assets.getUiData("out_of_gold_slot", 0) } };
                self.ability_overlays[i].base.visible = true;
                continue;
            }

            self.ability_overlays[i].base.visible = false;
        }

        if (!std.mem.eql(network_data.DataIdWithCount(u32), self.last_resources, local_player.resources)) {
            try self.resource_view.update(local_player.resources);
            self.last_resources = local_player.resources;
        }

        if (!std.mem.eql(network_data.DataIdWithCount(u16), self.last_talents, local_player.talents)) {
            self.talent_view.update(local_player);
            self.last_talents = local_player.talents;
        }

        if (self.last_gold != local_player.gold) {
            self.gold_text.text_data.setText(
                try std.fmt.bufPrint(self.gold_text.text_data.backing_buffer, "{}", .{local_player.gold}),
            );
            self.last_gold = local_player.gold;
        }

        if (self.last_gems != local_player.gems) {
            self.gems_text.text_data.setText(
                try std.fmt.bufPrint(self.gems_text.text_data.backing_buffer, "{}", .{local_player.gems}),
            );
            self.last_gems = local_player.gems;
        }

        const aether_changed = self.last_aether != local_player.aether;
        if (self.last_card_count != local_player.cards.len or aether_changed) {
            const old_cards_len = if (self.last_aether == std.math.maxInt(u8)) 0 else self.last_aether * 5;
            const new_cards_len = local_player.aether * 5;

            self.card_page = @min(self.card_page, local_player.aether);
            if (self.card_page <= 1) self.left_card_flipper.enabled = false;
            if (self.card_page >= local_player.aether) self.right_card_flipper.enabled = false;

            if (old_cards_len != new_cards_len) {
                self.card_slots = try main.allocator.realloc(self.card_slots, new_cards_len);
                if (new_cards_len > old_cards_len) for (old_cards_len..new_cards_len) |i| {
                    const current_page = @divFloor(i, 5) + 1;
                    const paged_idx = i % 5;
                    const x = 24 + @divFloor(paged_idx, 3) * 108;
                    const y = 45 + paged_idx % 3 * 30;
                    self.card_slots[i] = try .create(self.cards_container, f32i(x), f32i(y));
                    if (current_page != self.card_page) self.card_slots[i].base.base.visible = false;
                };
            }
            var i: usize = 0;
            for (local_player.cards) |data_id| {
                defer i += 1;
                try self.card_slots[i].setCard(data_id);
            }
            for (i..new_cards_len) |j| try self.card_slots[j].setCard(std.math.maxInt(u16));

            self.cards_text.text_data.setText(try std.fmt.bufPrint(
                self.cards_text.text_data.backing_buffer,
                "Cards - {d}/{d}",
                .{ self.card_page, local_player.aether },
            ));

            self.last_card_count = @intCast(local_player.cards.len);
            self.last_aether = local_player.aether;
        }

        if (self.last_spirits_communed != local_player.spirits_communed or aether_changed) {
            const spirit_goal = game_data.spiritGoal(local_player.aether);
            const spirit_perc = f32i(local_player.spirits_communed) / f32i(spirit_goal);
            self.spirit_bar.base.scissor.max_x = self.spirit_bar.texWRaw() * spirit_perc;

            var spirit_text_data = &self.spirit_bar.text_data;
            spirit_text_data.setText(try std.fmt.bufPrint(spirit_text_data.backing_buffer, "Aether {} - {}/{}", .{
                local_player.aether,
                local_player.spirits_communed,
                spirit_goal,
            }));

            self.last_spirits_communed = local_player.spirits_communed;
            self.last_aether = local_player.aether;
        }

        if (self.last_hp != local_player.hp or self.last_max_hp_bonus != local_player.max_hp_bonus) {
            const hp_perc = f32i(local_player.hp) / f32i(local_player.data.stats.health + local_player.max_hp_bonus);
            self.health_bar.base.scissor.max_x = self.health_bar.texWRaw() * hp_perc;

            var health_text_data = &self.health_bar.text_data;
            if (local_player.max_hp_bonus > 0) {
                health_text_data.setText(try std.fmt.bufPrint(health_text_data.backing_buffer, "{}/{} &size=\"10\"&col=\"65E698\"(+{})", .{
                    local_player.hp,
                    local_player.data.stats.health + local_player.max_hp_bonus,
                    local_player.max_hp_bonus,
                }));
            } else if (local_player.max_hp_bonus < 0) {
                health_text_data.setText(try std.fmt.bufPrint(health_text_data.backing_buffer, "{}/{} &size=\"10\"&col=\"FF7070\"({})", .{
                    local_player.hp,
                    local_player.data.stats.health + local_player.max_hp_bonus,
                    local_player.max_hp_bonus,
                }));
            } else {
                health_text_data.setText(try std.fmt.bufPrint(health_text_data.backing_buffer, "{}/{}", .{ local_player.hp, local_player.data.stats.health }));
            }

            self.last_hp = local_player.hp;
            self.last_max_hp_bonus = local_player.max_hp_bonus;
        }

        if (self.last_mp != local_player.mp or self.last_max_mp_bonus != local_player.max_mp_bonus) {
            const mp_perc = f32i(local_player.mp) / f32i(local_player.data.stats.mana + local_player.max_mp_bonus);
            self.mana_bar.base.scissor.max_x = self.mana_bar.texWRaw() * mp_perc;

            var mana_text_data = &self.mana_bar.text_data;
            if (local_player.max_mp_bonus > 0) {
                mana_text_data.setText(try std.fmt.bufPrint(mana_text_data.backing_buffer, "{}/{} &size=\"10\"&col=\"65E698\"(+{})", .{
                    local_player.mp,
                    local_player.data.stats.mana + local_player.max_mp_bonus,
                    local_player.max_mp_bonus,
                }));
            } else if (local_player.max_mp_bonus < 0) {
                mana_text_data.setText(try std.fmt.bufPrint(mana_text_data.backing_buffer, "{}/{} &size=\"10\"&col=\"FF7070\"({})", .{
                    local_player.mp,
                    local_player.data.stats.mana + local_player.max_mp_bonus,
                    local_player.max_mp_bonus,
                }));
            } else {
                mana_text_data.setText(try std.fmt.bufPrint(mana_text_data.backing_buffer, "{}/{}", .{ local_player.mp, local_player.data.stats.mana }));
            }

            self.last_mp = local_player.mp;
            self.last_max_mp_bonus = local_player.max_mp_bonus;
        }
    }
}

fn updateStat(text_data: *element.TextData, base_val: i32, bonus_val: i32) void {
    text_data.setText((if (bonus_val > 0)
        std.fmt.bufPrint(
            text_data.backing_buffer,
            "{}&size=\"10\"&col=\"65E698\" (+{})",
            .{ base_val + bonus_val, bonus_val },
        )
    else if (bonus_val < 0)
        std.fmt.bufPrint(
            text_data.backing_buffer,
            "{}&size=\"10\"&col=\"FF7070\" ({})",
            .{ base_val + bonus_val, bonus_val },
        )
    else
        std.fmt.bufPrint(text_data.backing_buffer, "{}", .{base_val + bonus_val})) catch text_data.text);
}

pub fn updateStats(self: *GameScreen) void {
    if (map.localPlayerCon()) |player| {
        updateStat(&self.strength_stat_text.text_data, player.data.stats.strength, player.strength_bonus);
        updateStat(&self.wit_stat_text.text_data, player.data.stats.wit, player.wit_bonus);
        updateStat(&self.defense_stat_text.text_data, player.data.stats.defense, player.defense_bonus);
        updateStat(&self.resistance_stat_text.text_data, player.data.stats.resistance, player.resistance_bonus);
        updateStat(&self.stamina_stat_text.text_data, player.data.stats.stamina, player.stamina_bonus);
        updateStat(&self.intelligence_stat_text.text_data, player.data.stats.intelligence, player.intelligence_bonus);
        updateStat(&self.speed_stat_text.text_data, player.data.stats.speed, player.speed_bonus);
        updateStat(&self.haste_stat_text.text_data, player.data.stats.haste, player.haste_bonus);
    }
}

pub fn updateFpsText(self: *GameScreen, fps: usize, mem: f32) void {
    self.fps_text.text_data.setText(std.fmt.bufPrint(
        self.fps_text.text_data.backing_buffer,
        \\FPS: {}
        \\Memory: {d:.1} MB
    ,
        .{ fps, mem },
    ) catch "Buffer out of memory");
}

fn parseItemRects(self: *GameScreen) void {
    for (0..22) |i| {
        if (i < 4) {
            const hori_idx = f32i(@mod(i, 4));
            self.inventory_pos_data[i] = .{ .x = 113 + hori_idx * 56, .y = 15, .w = 56, .h = 56, .w_pad = 0, .h_pad = 0 };
        } else {
            const hori_idx = f32i(@mod(i - 4, 6));
            const vert_idx = f32i(@divFloor(i - 4, 6));
            self.inventory_pos_data[i] = .{ .x = 15 + hori_idx * 46, .y = 75 + vert_idx * 46, .w = 46, .h = 46, .w_pad = 0, .h_pad = 0 };
        }
    }

    for (0..9) |i| {
        const hori_idx = f32i(@mod(i, 3));
        const vert_idx = f32i(@divFloor(i, 3));
        self.container_pos_data[i] = .{ .x = 15 + hori_idx * 46, .y = 15 + vert_idx * 46, .w = 46, .h = 46, .w_pad = 0, .h_pad = 0 };
    }
}

fn swapError(self: *GameScreen, start_slot: Slot, start_item: u16, start_item_data: ItemData) void {
    if (start_slot.is_container) {
        self.setContainerItem(start_item, start_slot.idx);
        self.setContainerItemData(start_item_data, start_slot.idx);
    } else {
        self.setInvItem(start_item, start_slot.idx);
        self.setInvItemData(start_item_data, start_slot.idx);
    }

    assets.playSfx("error.mp3");
}

pub fn swapSlots(self: *GameScreen, start_slot: Slot, end_slot: Slot) void {
    const int_id = map.interactive.map_id.load(.acquire);

    const start_item = if (start_slot.is_container)
        self.container_items[start_slot.idx].data_id
    else
        self.inventory_items[start_slot.idx].data_id;

    const start_item_data = if (start_slot.is_container)
        self.container_items[start_slot.idx].item_data
    else
        self.inventory_items[start_slot.idx].item_data;

    if (end_slot.idx == 255) {
        if (!start_slot.is_container) {
            self.setInvItem(std.math.maxInt(u16), start_slot.idx);
            self.setInvItemData(.{}, start_slot.idx);
            main.game_server.sendPacket(.{ .inv_drop = .{
                .player_map_id = map.info.player_map_id,
                .slot_id = start_slot.idx,
            } });
        } else {
            self.swapError(start_slot, start_item, start_item_data);
            return;
        }
    } else {
        if (map.localPlayerCon()) |local_player| {
            const start_data = game_data.item.from_id.get(start_item) orelse {
                self.swapError(start_slot, start_item, start_item_data);
                return;
            };

            const end_item_types = blk: {
                if (end_slot.is_container) {
                    const container = map.findObjectCon(Container, self.container_id) orelse {
                        self.swapError(start_slot, start_item, start_item_data);
                        return;
                    };
                    break :blk &container.data.item_types;
                } else break :blk local_player.data.item_types;
            };

            if (!start_data.item_type.typesMatch(if (end_slot.idx < 4) end_item_types[end_slot.idx] else .any)) {
                self.swapError(start_slot, start_item, start_item_data);
                return;
            }

            const end_item = if (end_slot.is_container)
                self.container_items[end_slot.idx].data_id
            else
                self.inventory_items[end_slot.idx].data_id;

            const end_item_data = if (end_slot.is_container)
                self.container_items[end_slot.idx].item_data
            else
                self.inventory_items[end_slot.idx].item_data;

            if (start_slot.is_container) {
                self.setContainerItem(end_item, start_slot.idx);
                self.setContainerItemData(end_item_data, start_slot.idx);
            } else {
                self.setInvItem(end_item, start_slot.idx);
                self.setInvItemData(end_item_data, start_slot.idx);
            }

            if (end_slot.is_container) {
                self.setContainerItem(start_item, end_slot.idx);
                self.setContainerItemData(start_item_data, end_slot.idx);
            } else {
                self.setInvItem(start_item, end_slot.idx);
                self.setInvItemData(start_item_data, end_slot.idx);
            }

            main.game_server.sendPacket(.{ .inv_swap = .{
                .time = main.current_time,
                .x = local_player.x,
                .y = local_player.y,
                .from_obj_type = if (start_slot.is_container) .container else .player,
                .from_map_id = if (start_slot.is_container) int_id else map.info.player_map_id,
                .from_slot_id = start_slot.idx,
                .to_obj_type = if (end_slot.is_container) .container else .player,
                .to_map_id = if (end_slot.is_container) int_id else map.info.player_map_id,
                .to_slot_id = end_slot.idx,
            } });

            assets.playSfx("move_item.mp3");
        }
    }
}

fn itemDoubleClickCallback(item: *Item) void {
    if (item.data_id < 0) return;

    const start_slot = Slot.findSlotId(systems.screen.game.*, item.base.x + 4, item.base.y + 4);
    const data = game_data.item.from_id.get(item.data_id) orelse return;
    const local_player = map.localPlayerCon() orelse return;

    if (data.item_type == .consumable and !start_slot.is_container) {
        main.game_server.sendPacket(.{ .use_item = .{
            .obj_type = .player,
            .map_id = map.info.player_map_id,
            .slot_id = start_slot.idx,
            .x = local_player.x,
            .y = local_player.y,
            .time = main.current_time,
        } });
        assets.playSfx("consume.mp3");
        return;
    }

    if (start_slot.is_container) {
        const end_slot = Slot.nextAvailableSlot(systems.screen.game.*, local_player.data.item_types, data.item_type);
        if (start_slot.idx == end_slot.idx and start_slot.is_container == end_slot.is_container) {
            item.base.x = item.drag_start_x;
            item.base.y = item.drag_start_y;
            return;
        }

        systems.screen.game.swapSlots(start_slot, end_slot);
    } else {
        const end_slot = Slot.nextEquippableSlot(local_player.data.item_types, data.item_type);
        if (end_slot.idx == 255 or // we don't want to drop
            start_slot.idx == end_slot.idx and start_slot.is_container == end_slot.is_container)
        {
            item.base.x = item.drag_start_x;
            item.base.y = item.drag_start_y;
            return;
        }

        systems.screen.game.swapSlots(start_slot, end_slot);
    }
}

fn statsCallback(ud: ?*anyopaque) void {
    const screen: *GameScreen = @alignCast(@ptrCast(ud.?));
    screen.stats_container.base.visible = !screen.stats_container.base.visible;
    screen.cards_container.base.visible = false;
    screen.talent_view.setVisible(false);
    screen.resource_view.setVisible(false);
    if (screen.stats_container.base.visible) screen.updateStats();
}

fn cardsCallback(ud: ?*anyopaque) void {
    const screen: *GameScreen = @alignCast(@ptrCast(ud.?));
    screen.cards_container.base.visible = !screen.cards_container.base.visible;
    screen.stats_container.base.visible = false;
    screen.talent_view.setVisible(false);
    screen.resource_view.setVisible(false);
}

fn talentsCallback(ud: ?*anyopaque) void {
    const screen: *GameScreen = @alignCast(@ptrCast(ud.?));
    screen.talent_view.setVisible(!screen.talent_view.base.base.visible);
    screen.cards_container.base.visible = false;
    screen.stats_container.base.visible = false;
    screen.resource_view.setVisible(false);
}

fn resourcesCallback(ud: ?*anyopaque) void {
    const screen: *GameScreen = @alignCast(@ptrCast(ud.?));
    screen.resource_view.setVisible(!screen.resource_view.base.base.visible);
    screen.cards_container.base.visible = false;
    screen.stats_container.base.visible = false;
    screen.talent_view.setVisible(false);
}

fn leftCardFlipperCallback(ud: ?*anyopaque) void {
    const screen: *GameScreen = @alignCast(@ptrCast(ud.?));
    screen.card_page = @max(1, screen.card_page - 1);
}

fn rightCardFlipperCallback(ud: ?*anyopaque) void {
    const screen: *GameScreen = @alignCast(@ptrCast(ud.?));
    if (map.localPlayerCon()) |player| screen.card_page = @min(@divFloor(player.cards.len, 5), screen.card_page + 1);
}

fn chatCallback(input_text: []const u8) void {
    if (input_text.len > 0) {
        main.game_server.sendPacket(.{ .player_text = .{ .text = input_text } });

        const text_copy = main.allocator.dupe(u8, input_text) catch main.oomPanic();
        input.input_history.append(main.allocator, text_copy) catch main.oomPanic();
        input.input_history_idx = @intCast(input.input_history.items.len);
    }
}

fn interactCallback() void {}

fn itemDragStartCallback(item: *Item) void {
    item.background_image_data = null;
}

fn itemDragEndCallback(item: *Item) void {
    var current_screen = systems.screen.game;
    const start_slot = Slot.findSlotId(current_screen.*, item.drag_start_x + 4, item.drag_start_y + 4);
    const end_slot = Slot.findSlotId(current_screen.*, item.base.x - item.drag_offset_x, item.base.y - item.drag_offset_y);
    if (start_slot.idx == end_slot.idx and start_slot.is_container == end_slot.is_container) {
        item.base.x = item.drag_start_x;
        item.base.y = item.drag_start_y;

        if (start_slot.is_container) {
            current_screen.setContainerItem(item.data_id, start_slot.idx);
            current_screen.setContainerItemData(item.item_data, start_slot.idx);
        } else {
            current_screen.setInvItem(item.data_id, start_slot.idx);
            current_screen.setInvItemData(item.item_data, start_slot.idx);
        }
        return;
    }

    current_screen.swapSlots(start_slot, end_slot);
}

fn itemShiftClickCallback(item: *Item) void {
    if (item.data_id < 0) return;

    const current_screen = systems.screen.game.*;
    const slot = Slot.findSlotId(current_screen, item.base.x + 4, item.base.y + 4);
    const data = game_data.item.from_id.get(@intCast(item.data_id)) orelse return;
    if (data.item_type != .consumable) return;

    const local_player = map.localPlayerCon() orelse return;

    main.game_server.sendPacket(.{ .use_item = .{
        .obj_type = if (slot.is_container) .container else .player,
        .map_id = if (slot.is_container) current_screen.container_id else map.info.player_map_id,
        .slot_id = slot.idx,
        .x = local_player.x,
        .y = local_player.y,
        .time = main.current_time,
    } });
    assets.playSfx("consume.mp3");
}

pub fn useItem(self: *GameScreen, idx: u8) void {
    itemDoubleClickCallback(self.inventory_items[idx]);
}

fn containerFailure(self: *GameScreen, idx: u8) void {
    self.container_items[idx].data_id = std.math.maxInt(u16);
    self.container_items[idx].image_data.normal.atlas_data = assets.error_data;
    self.container_items[idx].base.x = self.container_decor.base.x +
        self.container_pos_data[idx].x + (self.container_pos_data[idx].w - self.container_items[idx].texWRaw()) / 2 + assets.padding;
    self.container_items[idx].base.y = self.container_decor.base.y +
        self.container_pos_data[idx].y + (self.container_pos_data[idx].h - self.container_items[idx].texHRaw()) / 2 + assets.padding;
    self.container_items[idx].background_image_data = null;
}

pub fn setContainerItem(self: *GameScreen, item: u16, idx: u8) void {
    if (item == std.math.maxInt(u16)) {
        self.container_items[idx].data_id = std.math.maxInt(u16);
        self.container_items[idx].base.visible = false;
        return;
    }

    self.container_items[idx].base.visible = true;

    const data = game_data.item.from_id.get(@intCast(item)) orelse {
        std.log.err("Attempted to populate container index {} with item id {}, but props was not found", .{ idx, item });
        self.itemFailure(idx);
        return;
    };

    const tex = assets.atlas_data.get(data.texture.sheet) orelse {
        std.log.err("Could not find ui sheet {s} for item with data id {}, index {}", .{ data.texture.sheet, item, idx });
        self.itemFailure(idx);
        return;
    };

    const atlas_data = tex[data.texture.index];
    const base_x = self.container_decor.base.x + self.container_pos_data[idx].x;
    const base_y = self.container_decor.base.y + self.container_pos_data[idx].y;
    const pos_w = self.container_pos_data[idx].w;
    const pos_h = self.container_pos_data[idx].h;

    self.container_items[idx].background_image_data = switch (data.rarity) {
        .mythic => .{ .normal = .{ .atlas_data = assets.getUiData("mythic_slot", 0) } },
        .legendary => .{ .normal = .{ .atlas_data = assets.getUiData("legendary_slot", 0) } },
        .epic => .{ .normal = .{ .atlas_data = assets.getUiData("epic_slot", 0) } },
        .rare => .{ .normal = .{ .atlas_data = assets.getUiData("rare_slot", 0) } },
        .common => null,
    };

    self.container_items[idx].data_id = item;
    self.container_items[idx].image_data.normal.atlas_data = atlas_data;
    self.container_items[idx].base.x = base_x + (pos_w - self.container_items[idx].texWRaw()) / 2 + assets.padding;
    self.container_items[idx].base.y = base_y + (pos_h - self.container_items[idx].texHRaw()) / 2 + assets.padding;
}

pub fn setContainerItemData(self: *GameScreen, item_data: ItemData, idx: u8) void {
    const data = game_data.item.from_id.get(self.container_items[idx].data_id) orelse return;
    self.container_items[idx].item_data = item_data;
    if (data.max_stack > 0) {
        self.container_items[idx].amount_text.?.setText(
            std.fmt.bufPrint(self.container_items[idx].amount_text.?.backing_buffer, "{}", .{item_data.amount}) catch "Buffer overflow",
        );
        self.container_items[idx].amount_visible = true;
    } else self.container_items[idx].amount_visible = false;
}

fn itemFailure(self: *GameScreen, idx: u8) void {
    const atlas_data = assets.error_data;
    self.inventory_items[idx].data_id = std.math.maxInt(u16);
    self.inventory_items[idx].image_data.normal.atlas_data = atlas_data;
    self.inventory_items[idx].base.x = self.inventory_decor.base.x + self.inventory_pos_data[idx].x + (self.inventory_pos_data[idx].w - self.inventory_items[idx].texWRaw()) / 2 + assets.padding;
    self.inventory_items[idx].base.y = self.inventory_decor.base.y + self.inventory_pos_data[idx].y + (self.inventory_pos_data[idx].h - self.inventory_items[idx].texHRaw()) / 2 + assets.padding;
    self.inventory_items[idx].background_image_data = null;
}

pub fn setInvItem(self: *GameScreen, item: u16, idx: u8) void {
    if (item == std.math.maxInt(u16)) {
        self.inventory_items[idx].data_id = std.math.maxInt(u16);
        self.inventory_items[idx].base.visible = false;
        return;
    }

    const scale: f32 = if (idx < 4) 4.0 else 3.0;
    self.inventory_items[idx].base.visible = true;
    self.inventory_items[idx].image_data.normal.scale_x = scale;
    self.inventory_items[idx].image_data.normal.scale_y = scale;

    const data = game_data.item.from_id.get(@intCast(item)) orelse {
        std.log.err("Attempted to populate inventory index {} with item id {}, but props was not found", .{ idx, item });
        self.itemFailure(idx);
        return;
    };

    const tex = assets.atlas_data.get(data.texture.sheet) orelse {
        std.log.err("Could not find ui sheet {s} for item with data id {}, index {}", .{ data.texture.sheet, item, idx });
        self.itemFailure(idx);
        return;
    };

    const atlas_data = tex[data.texture.index];
    const base_x = self.inventory_decor.base.x + self.inventory_pos_data[idx].x;
    const base_y = self.inventory_decor.base.y + self.inventory_pos_data[idx].y;
    const pos_w = self.inventory_pos_data[idx].w;
    const pos_h = self.inventory_pos_data[idx].h;

    self.inventory_items[idx].background_image_data = if (idx < 4)
        switch (data.rarity) {
            .mythic => .{ .normal = .{ .atlas_data = assets.getUiData("mythic_slot_equip", 0) } },
            .legendary => .{ .normal = .{ .atlas_data = assets.getUiData("legendary_slot_equip", 0) } },
            .epic => .{ .normal = .{ .atlas_data = assets.getUiData("epic_slot_equip", 0) } },
            .rare => .{ .normal = .{ .atlas_data = assets.getUiData("rare_slot_equip", 0) } },
            .common => null,
        }
    else switch (data.rarity) {
        .mythic => .{ .normal = .{ .atlas_data = assets.getUiData("mythic_slot", 0) } },
        .legendary => .{ .normal = .{ .atlas_data = assets.getUiData("legendary_slot", 0) } },
        .epic => .{ .normal = .{ .atlas_data = assets.getUiData("epic_slot", 0) } },
        .rare => .{ .normal = .{ .atlas_data = assets.getUiData("rare_slot", 0) } },
        .common => null,
    };

    self.inventory_items[idx].data_id = item;
    self.inventory_items[idx].image_data.normal.atlas_data = atlas_data;
    self.inventory_items[idx].base.x = base_x + (pos_w - self.inventory_items[idx].texWRaw()) / 2 + assets.padding;
    self.inventory_items[idx].base.y = base_y + (pos_h - self.inventory_items[idx].texHRaw()) / 2 + assets.padding;
}

pub fn setInvItemData(self: *GameScreen, item_data: ItemData, idx: u8) void {
    const data = game_data.item.from_id.get(self.inventory_items[idx].data_id) orelse return;
    self.inventory_items[idx].item_data = item_data;
    if (data.max_stack > 0) {
        self.inventory_items[idx].amount_text.?.setText(
            std.fmt.bufPrint(self.inventory_items[idx].amount_text.?.backing_buffer, "{}", .{item_data.amount}) catch "Buffer overflow",
        );
        self.inventory_items[idx].amount_visible = true;
    } else self.inventory_items[idx].amount_visible = false;
}

pub fn setContainerVisible(self: *GameScreen, visible: bool) void {
    self.container_visible = visible;
    self.container_decor.base.visible = visible;
}
