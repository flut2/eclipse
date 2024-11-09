const std = @import("std");
const element = @import("../elements/element.zig");
const assets = @import("../../assets.zig");
const network = @import("../../network.zig");
const main = @import("../../main.zig");
const shared = @import("shared");
const utils = shared.utils;
const game_data = shared.game_data;
const map = @import("../../game/map.zig");
const input = @import("../../input.zig");
const systems = @import("../systems.zig");

const GameScreen = @This();
const Text = @import("../elements/Text.zig");
const Input = @import("../elements/Input.zig");
const Image = @import("../elements/Image.zig");
const ScrollableContainer = @import("../elements/ScrollableContainer.zig");
const UiContainer = @import("../elements/Container.zig");
const Bar = @import("../elements/Bar.zig");
const Button = @import("../elements/Button.zig");
const Item = @import("../elements/Item.zig");
const Options = @import("../composed/Options.zig");
const Container = @import("../../game/Container.zig");
const Player = @import("../../game/Player.zig");

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
        for (0..20) |idx| {
            if (idx >= 4 or item_types[idx].typesMatch(item_type)) return .{ .idx = @intCast(idx) };
        }
        return .{ .idx = 255 };
    }

    pub fn nextAvailableSlot(screen: GameScreen, item_types: []const game_data.ItemType, item_type: game_data.ItemType) Slot {
        for (0..screen.inventory_items.len) |idx| {
            if (screen.inventory_items[idx].item == std.math.maxInt(u16) and
                (idx >= 4 or item_types[idx].typesMatch(item_type)))
                return .{ .idx = @intCast(idx) };
        }
        return .{ .idx = 255 };
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
stats_container: *UiContainer = undefined,
cards_container: *UiContainer = undefined,
ability_container: *UiContainer = undefined,
ability_overlays: [4]*Image = undefined,
ability_overlay_texts: [4]*Text = undefined,

stats_decor: *Image = undefined,
strength_stat_text: *Text = undefined,
wit_stat_text: *Text = undefined,
defense_stat_text: *Text = undefined,
resistance_stat_text: *Text = undefined,
speed_stat_text: *Text = undefined,
stamina_stat_text: *Text = undefined,
intelligence_stat_text: *Text = undefined,
penetration_stat_text: *Text = undefined,
piercing_stat_text: *Text = undefined,
haste_stat_text: *Text = undefined,
tenacity_stat_text: *Text = undefined,
health_bar: *Bar = undefined,
mana_bar: *Bar = undefined,
spirit_bar: *Bar = undefined,
inventory_decor: *Image = undefined,
inventory_items: [22]*Item = undefined,
container_decor: *Image = undefined,
container_name: *Text = undefined,
container_items: [9]*Item = undefined,
minimap_decor: *Image = undefined,
minimap_slots: *Image = undefined,
retrieve_button: *Button = undefined,
options_button: *Button = undefined,
options: *Options = undefined,
inventory_pos_data: [22]utils.Rect = undefined,
container_pos_data: [9]utils.Rect = undefined,
last_aether: u8 = std.math.maxInt(u8),
last_spirits_communed: u32 = std.math.maxInt(u32),
last_hp: i32 = -1,
last_max_hp: i32 = -1,
last_max_hp_bonus: i32 = -1,
last_mp: i32 = -1,
last_max_mp: i32 = -1,
last_max_mp_bonus: i32 = -1,
last_in_combat: bool = false,
container_visible: bool = false,
container_id: u32 = std.math.maxInt(u32),
abilities_inited: bool = false,

pub fn init(self: *GameScreen) !void {
    const inventory_data = assets.getUiData("player_inventory", 0);
    self.parseItemRects();

    const minimap_data = assets.getUiData("minimap", 0);
    self.minimap_decor = try element.create(Image, .{
        .base = .{ .x = main.camera.width - minimap_data.width() + 10, .y = -10 },
        .image_data = .{ .normal = .{ .atlas_data = minimap_data } },
        .is_minimap_decor = true,
        .minimap_offset_x = 21.0,
        .minimap_offset_y = 21.0,
        .minimap_width = 212.0,
        .minimap_height = 212.0,
    });

    const minimap_slots_data = assets.getUiData("minimap_slots", 0);
    self.minimap_slots = try element.create(Image, .{
        .base = .{ .x = self.minimap_decor.base.x + 15, .y = self.minimap_decor.base.y + 209 },
        .image_data = .{ .normal = .{ .atlas_data = minimap_slots_data } },
    });

    const retrieve_button_data = assets.getUiData("retrieve_button", 0);
    self.retrieve_button = try element.create(Button, .{
        .base = .{
            .x = self.minimap_slots.base.x + 6 + (18 - retrieve_button_data.width()) / 2.0,
            .y = self.minimap_slots.base.y + 6 + (18 - retrieve_button_data.height()) / 2.0,
        },
        .image_data = .{ .base = .{ .normal = .{ .atlas_data = retrieve_button_data } } },
        .tooltip_text = .{
            .text = "Return to the Retrieve",
            .size = 12,
            .text_type = .bold_italic,
        },
        .press_callback = returnToRetrieve,
    });

    const options_button_data = assets.getUiData("options_button", 0);
    self.options_button = try element.create(Button, .{
        .base = .{
            .x = self.minimap_slots.base.x + 36 + (18 - options_button_data.width()) / 2.0,
            .y = self.minimap_slots.base.y + 6 + (18 - options_button_data.height()) / 2.0,
        },
        .image_data = .{ .base = .{ .normal = .{ .atlas_data = options_button_data } } },
        .tooltip_text = .{
            .text = "Open Options",
            .size = 12,
            .text_type = .bold_italic,
        },
        .press_callback = openOptions,
    });

    self.inventory_decor = try element.create(Image, .{
        .base = .{
            .x = main.camera.width - inventory_data.width() + 10,
            .y = main.camera.height - inventory_data.height() + 10,
        },
        .image_data = .{ .normal = .{ .atlas_data = inventory_data } },
    });

    for (0..self.inventory_items.len) |i| {
        self.inventory_items[i] = try element.create(Item, .{
            .base = .{
                .x = self.inventory_decor.base.x + self.inventory_pos_data[i].x +
                    (self.inventory_pos_data[i].w - assets.error_data.texWRaw() * 4.0) / 2 + assets.padding,
                .y = self.inventory_decor.base.y + self.inventory_pos_data[i].y +
                    (self.inventory_pos_data[i].h - assets.error_data.texHRaw() * 4.0) / 2 + assets.padding,
                .visible = false,
            },
            .background_x = self.inventory_decor.base.x + self.inventory_pos_data[i].x,
            .background_y = self.inventory_decor.base.y + self.inventory_pos_data[i].y,
            .image_data = .{ .normal = .{ .scale_x = 4.0, .scale_y = 4.0, .atlas_data = assets.error_data, .glow = true } },
            .draggable = true,
            .drag_start_callback = itemDragStartCallback,
            .drag_end_callback = itemDragEndCallback,
            .double_click_callback = itemDoubleClickCallback,
            .shift_click_callback = itemShiftClickCallback,
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
        .base = .{ .x = self.container_decor.base.x + 22, .y = self.container_decor.base.y + 126 },
        .text_data = .{
            .text = "",
            .size = 14,
            .vert_align = .middle,
            .hori_align = .middle,
            .max_width = 196,
            .max_height = 18,
        },
    });

    for (0..self.container_items.len) |i| {
        self.container_items[i] = try element.create(Item, .{
            .base = .{
                .x = self.container_decor.base.x + self.container_pos_data[i].x +
                    (self.container_pos_data[i].w - assets.error_data.texWRaw() * 4.0) / 2 + assets.padding,
                .y = self.container_decor.base.y + self.container_pos_data[i].y +
                    (self.container_pos_data[i].h - assets.error_data.texHRaw() * 4.0) / 2 + assets.padding,
                .visible = false,
            },
            .background_x = self.container_decor.base.x + self.container_pos_data[i].x,
            .background_y = self.container_decor.base.y + self.container_pos_data[i].y,
            .image_data = .{ .normal = .{ .scale_x = 4.0, .scale_y = 4.0, .atlas_data = assets.error_data, .glow = true } },
            .draggable = true,
            .drag_start_callback = itemDragStartCallback,
            .drag_end_callback = itemDragEndCallback,
            .double_click_callback = itemDoubleClickCallback,
            .shift_click_callback = itemShiftClickCallback,
        });
    }

    const bars_data = assets.getUiData("player_abilities_bars", 0);
    self.bars_decor = try element.create(Image, .{
        .base = .{
            .x = (main.camera.width - bars_data.width()) / 2,
            .y = main.camera.height - bars_data.height() + 10,
        },
        .image_data = .{ .normal = .{ .atlas_data = bars_data } },
    });

    const health_bar_data = assets.getUiData("player_health_bar", 0);
    self.health_bar = try element.create(Bar, .{
        .base = .{ .x = self.bars_decor.base.x + 70, .y = self.bars_decor.base.y + 102 },
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
        .base = .{ .x = self.bars_decor.base.x + 70, .y = self.bars_decor.base.y + 132 },
        .image_data = .{ .normal = .{ .atlas_data = mana_bar_data } },
        .text_data = .{
            .text = "",
            .size = 12,
            .text_type = .bold_italic,
            .max_chars = 64,
        },
    });

    const xp_bar_data = assets.getUiData("player_xp_bar", 0);
    self.spirit_bar = try element.create(Bar, .{
        .base = .{ .x = self.bars_decor.base.x + 70, .y = self.bars_decor.base.y + 22 },
        .image_data = .{ .normal = .{ .atlas_data = xp_bar_data } },
        .text_data = .{
            .text = "",
            .size = 10,
            .text_type = .bold_italic,
            .max_chars = 64,
        },
    });

    const cards_button_data = assets.getUiData("cards_button", 0);
    self.cards_button = try element.create(Button, .{
        .base = .{
            .x = self.bars_decor.base.x + 21 + (32 - cards_button_data.width() + assets.padding * 2) / 2.0,
            .y = self.bars_decor.base.y + 73 + (32 - cards_button_data.height() + assets.padding * 2) / 2.0,
        },
        .image_data = .{ .base = .{ .normal = .{ .atlas_data = cards_button_data, .glow = true } } },
        .userdata = self,
        .press_callback = cardsCallback,
    });

    const cards_decor_data = assets.getUiData("player_stats", 0);
    self.cards_container = try element.create(UiContainer, .{ .base = .{
        .x = self.bars_decor.base.x + 63 - 15,
        .y = self.bars_decor.base.y + 15 - cards_decor_data.height(),
        .visible = false,
    } });

    const stats_button_data = assets.getUiData("stats_button", 0);
    self.stats_button = try element.create(Button, .{
        .base = .{
            .x = self.bars_decor.base.x + 21 + (32 - stats_button_data.width() + assets.padding * 2) / 2.0,
            .y = self.bars_decor.base.y + 117 + (32 - stats_button_data.height() + assets.padding * 2) / 2.0,
        },
        .image_data = .{ .base = .{ .normal = .{ .atlas_data = stats_button_data, .glow = true } } },
        .userdata = self,
        .press_callback = statsCallback,
    });

    const stats_decor_data = assets.getUiData("player_stats", 0);
    self.stats_container = try element.create(UiContainer, .{ .base = .{
        .x = self.bars_decor.base.x + 63 - 15,
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
    try addStatText(self.stats_container, &self.speed_stat_text, &idx);
    try addStatText(self.stats_container, &self.stamina_stat_text, &idx);
    try addStatText(self.stats_container, &self.intelligence_stat_text, &idx);
    try addStatText(self.stats_container, &self.penetration_stat_text, &idx);
    try addStatText(self.stats_container, &self.piercing_stat_text, &idx);
    try addStatText(self.stats_container, &self.haste_stat_text, &idx);
    try addStatText(self.stats_container, &self.tenacity_stat_text, &idx);

    self.ability_container = try element.create(UiContainer, .{ .base = .{
        .x = self.bars_decor.base.x + 69,
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
        .scroll_x = self.chat_decor.base.x + 400,
        .scroll_y = self.chat_decor.base.y + 24,
        .scroll_w = 4,
        .scroll_h = 240,
        .scroll_side_x = self.chat_decor.base.x + 393,
        .scroll_side_y = self.chat_decor.base.y + 24,
        .scroll_decor_image_data = .{ .nine_slice = .fromAtlasData(scroll_background_data, 4, 240, 0, 0, 2, 2, 1.0) },
        .scroll_knob_image_data = .fromNineSlices(scroll_knob_base, scroll_knob_hover, scroll_knob_press, 10, 16, 4, 4, 1, 2, 1.0),
        .scroll_side_decor_image_data = .{ .nine_slice = .fromAtlasData(scroll_decor_data, 6, 240, 0, 41, 6, 3, 1.0) },
        .start_value = 1.0,
    });

    var fps_text_data: element.TextData = .{
        .text = "",
        .size = 12,
        .text_type = .bold,
        .hori_align = .middle,
        .max_width = self.minimap_decor.width(),
        .max_chars = 256,
    };

    {
        fps_text_data.lock.lock();
        defer fps_text_data.lock.unlock();
        fps_text_data.recalculateAttributes();
    }

    self.fps_text = try element.create(Text, .{
        .base = .{
            .x = self.minimap_decor.base.x,
            .y = self.minimap_decor.base.y + self.minimap_decor.height() - 10,
        },
        .text_data = fps_text_data,
    });

    self.options = try .create();
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
    const fidx: f32 = @floatFromInt(idx);

    if (assets.ui_atlas_data.get(ability.icon.sheet)) |data| {
        const index = ability.icon.index;
        if (data.len <= index) @panic("Could not initiate ability for GameScreen, index was out of bounds");

        _ = try self.ability_container.createChild(Image, .{
            .base = .{ .x = fidx * 56.0, .y = 0 },
            .image_data = .{ .normal = .{ .atlas_data = data[index], .scale_x = 2.0, .scale_y = 2.0 } },
            .ability_props = ability,
        });
    } else @panic("Could not initiate ability for GameScreen, sheet was missing");

    self.ability_overlays[idx] = try self.ability_container.createChild(Image, .{
        .base = .{ .x = fidx * 56.0, .y = 0, .visible = false },
        .image_data = undefined,
    });

    self.ability_overlay_texts[idx] = try self.ability_container.createChild(Text, .{
        .base = .{ .x = fidx * 56.0 - 7.0, .y = -7.0, .visible = false },
        .text_data = .{
            .text = "",
            .size = 12.0,
            .text_type = .bold,
            .hori_align = .middle,
            .vert_align = .middle,
            .max_chars = 32,
            .max_width = 56.0,
            .max_height = 56.0,
        },
    });
    self.ability_overlay_texts[idx].text_data.lock.lock();
    defer self.ability_overlay_texts[idx].text_data.lock.unlock();
    self.ability_overlay_texts[idx].text_data.recalculateAttributes();
}

fn addStatText(container: *UiContainer, text: **Text, idx: *f32) !void {
    defer idx.* += 1;

    const x = 38.0 + 70.0 * @mod(idx.*, 3.0);
    const y = 27.0 + 28.0 * @floor(idx.* / 3.0);
    text.* = try container.createChild(Text, .{ .base = .{ .x = x, .y = y }, .text_data = .{
        .text = "",
        .size = 10,
        .text_type = .bold,
        .max_width = 67,
        .max_height = 18,
        .hori_align = .middle,
        .vert_align = .middle,
        .max_chars = 64,
    } });
}

pub fn deinit(self: *GameScreen) void {
    element.destroy(self.minimap_decor);
    element.destroy(self.minimap_slots);
    element.destroy(self.inventory_decor);
    element.destroy(self.container_decor);
    element.destroy(self.container_name);
    element.destroy(self.bars_decor);
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
    element.destroy(self.options_button);
    element.destroy(self.retrieve_button);
    for (self.inventory_items) |item| element.destroy(item);
    for (self.container_items) |item| element.destroy(item);

    self.chat_lines.deinit(main.allocator);
    self.options.deinit();

    main.allocator.destroy(self);
}

pub fn resize(self: *GameScreen, w: f32, h: f32) void {
    self.minimap_decor.base.x = w - self.minimap_decor.width() + 10;
    self.minimap_slots.base.x = self.minimap_decor.base.x + 15;
    self.minimap_slots.base.y = self.minimap_decor.base.y + 209;
    self.fps_text.base.x = self.minimap_decor.base.x;
    self.fps_text.base.y = self.minimap_decor.base.y + self.minimap_decor.height() - 10;
    self.inventory_decor.base.x = w - self.inventory_decor.width() + 10;
    self.inventory_decor.base.y = h - self.inventory_decor.height() + 10;
    self.container_decor.base.x = self.inventory_decor.base.x - self.container_decor.width() + 10;
    self.container_decor.base.y = h - self.container_decor.height() + 10;
    self.container_name.base.x = self.container_decor.base.x + 22;
    self.container_name.base.y = self.container_decor.base.y + 126;
    self.bars_decor.base.x = (w - self.bars_decor.width()) / 2;
    self.bars_decor.base.y = h - self.bars_decor.height() + 10;
    self.stats_container.base.x = self.bars_decor.base.x + 63 - 15;
    self.stats_container.base.y = self.bars_decor.base.y + 15 - self.stats_decor.height();
    self.ability_container.base.x = self.bars_decor.base.x + 69;
    self.ability_container.base.y = self.bars_decor.base.y + 45;
    self.cards_button.base.x = self.bars_decor.base.x + 21 + (32 - self.cards_button.width() + assets.padding * 2) / 2.0;
    self.cards_button.base.y = self.bars_decor.base.y + 73 + (32 - self.cards_button.height() + assets.padding * 2) / 2.0;
    self.stats_button.base.x = self.bars_decor.base.x + 21 + (32 - self.stats_button.width() + assets.padding * 2) / 2.0;
    self.stats_button.base.y = self.bars_decor.base.y + 117 + (32 - self.stats_button.height() + assets.padding * 2) / 2.0;
    self.health_bar.base.x = self.bars_decor.base.x + 70;
    self.health_bar.base.y = self.bars_decor.base.y + 102;
    self.mana_bar.base.x = self.bars_decor.base.x + 70;
    self.mana_bar.base.y = self.bars_decor.base.y + 132;
    self.spirit_bar.base.x = self.bars_decor.base.x + 70;
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
    self.retrieve_button.base.x = self.minimap_slots.base.x + 6 + (18 - self.retrieve_button.width()) / 2.0;
    self.retrieve_button.base.y = self.minimap_slots.base.y + 6 + (18 - self.retrieve_button.height()) / 2.0;
    self.options_button.base.x = self.minimap_slots.base.x + 36 + (18 - self.options_button.width()) / 2.0;
    self.options_button.base.y = self.minimap_slots.base.y + 6 + (18 - self.options_button.height()) / 2.0;

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
}

pub fn update(self: *GameScreen, time: i64, _: f32) !void {
    self.fps_text.base.visible = main.settings.stats_enabled;

    var lock = map.useLockForType(Player);
    lock.lock();
    defer lock.unlock();
    if (map.localPlayer(.con)) |local_player| {
        if (!self.abilities_inited) {
            for (0..4) |i| try addAbility(self, local_player.data.abilities[i], i);
            self.abilities_inited = true;
        }

        for (0..4) |i| {
            const mana_cost = local_player.data.abilities[i].mana_cost;
            if (mana_cost != 0 and mana_cost > local_player.mp) {
                self.ability_overlays[i].image_data = .{ .normal = .{ .atlas_data = assets.getUiData("out_of_mana_slot", 0) } };
                self.ability_overlays[i].base.visible = true;
                self.ability_overlay_texts[i].base.visible = false;
                continue;
            }

            const health_cost = local_player.data.abilities[i].health_cost;
            if (health_cost != 0 and health_cost > local_player.hp) {
                self.ability_overlays[i].image_data = .{ .normal = .{ .atlas_data = assets.getUiData("out_of_health_slot", 0) } };
                self.ability_overlays[i].base.visible = true;
                self.ability_overlay_texts[i].base.visible = false;
                continue;
            }

            const gold_cost = local_player.data.abilities[i].gold_cost;
            if (gold_cost != 0 and gold_cost > local_player.gold) {
                self.ability_overlays[i].image_data = .{ .normal = .{ .atlas_data = assets.getUiData("out_of_gold_slot", 0) } };
                self.ability_overlays[i].base.visible = true;
                self.ability_overlay_texts[i].base.visible = false;
                continue;
            }

            const time_elapsed = time - local_player.last_ability_use[i];
            const cooldown_us = @as(i64, @intFromFloat(local_player.data.abilities[i].cooldown)) * std.time.us_per_s;
            if (time_elapsed < cooldown_us) {
                const cooldown_left = @as(f32, @floatFromInt(cooldown_us - time_elapsed)) / std.time.us_per_s;

                self.ability_overlays[i].image_data = .{ .normal = .{ .atlas_data = assets.getUiData("on_cooldown_slot", 0) } };
                self.ability_overlays[i].image_data.normal.scissor.max_x =
                    self.ability_overlays[i].texWRaw() * (cooldown_left / local_player.data.abilities[i].cooldown);

                {
                    self.ability_overlay_texts[i].text_data.lock.lock();
                    defer self.ability_overlay_texts[i].text_data.lock.unlock();
                    self.ability_overlay_texts[i].text_data.text = try std.fmt.bufPrint(
                        self.ability_overlay_texts[i].text_data.backing_buffer,
                        "{d:.1}s",
                        .{cooldown_left},
                    );
                    self.ability_overlay_texts[i].text_data.recalculateAttributes();
                }

                self.ability_overlays[i].base.visible = true;
                self.ability_overlay_texts[i].base.visible = true;
                continue;
            }

            self.ability_overlays[i].base.visible = false;
            self.ability_overlay_texts[i].base.visible = false;
        }

        if (self.last_spirits_communed != local_player.spirits_communed or self.last_aether != local_player.aether) {
            const spirit_goal = game_data.spiritGoal(local_player.aether);
            const spirit_perc = @as(f32, @floatFromInt(local_player.spirits_communed)) / @as(f32, @floatFromInt(spirit_goal));
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

        if (self.last_hp != local_player.hp or self.last_max_hp != local_player.max_hp or self.last_max_hp_bonus != local_player.max_hp_bonus) {
            const hp_perc = @as(f32, @floatFromInt(local_player.hp)) / @as(f32, @floatFromInt(local_player.max_hp + local_player.max_hp_bonus));
            self.health_bar.base.scissor.max_x = self.health_bar.texWRaw() * hp_perc;

            var health_text_data = &self.health_bar.text_data;
            if (local_player.max_hp_bonus > 0) {
                health_text_data.setText(try std.fmt.bufPrint(health_text_data.backing_buffer, "{}/{} &size=\"10\"&col=\"65E698\"(+{})", .{
                    local_player.hp,
                    local_player.max_hp + local_player.max_hp_bonus,
                    local_player.max_hp_bonus,
                }));
            } else if (local_player.max_hp_bonus < 0) {
                health_text_data.setText(try std.fmt.bufPrint(health_text_data.backing_buffer, "{}/{} &size=\"10\"&col=\"FF7070\"(+{})", .{
                    local_player.hp,
                    local_player.max_hp + local_player.max_hp_bonus,
                    local_player.max_hp_bonus,
                }));
            } else {
                health_text_data.setText(try std.fmt.bufPrint(health_text_data.backing_buffer, "{}/{}", .{ local_player.hp, local_player.max_hp }));
            }

            self.last_hp = local_player.hp;
            self.last_max_hp = local_player.max_hp;
            self.last_max_hp_bonus = local_player.max_hp_bonus;
        }

        if (self.last_mp != local_player.mp or self.last_max_mp != local_player.max_mp or self.last_max_mp_bonus != local_player.max_mp_bonus) {
            const mp_perc = @as(f32, @floatFromInt(local_player.mp)) / @as(f32, @floatFromInt(local_player.max_mp + local_player.max_mp_bonus));
            self.mana_bar.base.scissor.max_x = self.mana_bar.texWRaw() * mp_perc;

            var mana_text_data = &self.mana_bar.text_data;
            if (local_player.max_mp_bonus > 0) {
                mana_text_data.setText(try std.fmt.bufPrint(mana_text_data.backing_buffer, "{}/{} &size=\"10\"&col=\"65E698\"(+{})", .{
                    local_player.mp,
                    local_player.max_mp + local_player.max_mp_bonus,
                    local_player.max_mp_bonus,
                }));
            } else if (local_player.max_mp_bonus < 0) {
                mana_text_data.setText(try std.fmt.bufPrint(mana_text_data.backing_buffer, "{}/{} &size=\"10\"&col=\"FF7070\"(+{})", .{
                    local_player.mp,
                    local_player.max_mp + local_player.max_mp_bonus,
                    local_player.max_mp_bonus,
                }));
            } else {
                mana_text_data.setText(try std.fmt.bufPrint(mana_text_data.backing_buffer, "{}/{}", .{ local_player.mp, local_player.max_mp }));
            }

            self.last_mp = local_player.mp;
            self.last_max_mp = local_player.max_mp;
        }
    }
}

fn updateStat(text_data: *element.TextData, base_val: i32, bonus_val: i32) void {
    text_data.setText((if (bonus_val > 0)
        std.fmt.bufPrint(
            text_data.backing_buffer,
            "{} &size=\"8\"&col=\"65E698\"(+{})",
            .{ base_val + bonus_val, bonus_val },
        )
    else if (bonus_val < 0)
        std.fmt.bufPrint(
            text_data.backing_buffer,
            "{} &size=\"8\"&col=\"FF7070\"({})",
            .{ base_val + bonus_val, bonus_val },
        )
    else
        std.fmt.bufPrint(text_data.backing_buffer, "{}", .{base_val + bonus_val})) catch text_data.text);
}

pub fn updateStats(self: *GameScreen) void {
    std.debug.assert(!map.useLockForType(Player).tryLock());
    if (map.localPlayer(.con)) |player| {
        updateStat(&self.strength_stat_text.text_data, player.strength, player.strength_bonus);
        updateStat(&self.wit_stat_text.text_data, player.wit, player.wit_bonus);
        updateStat(&self.defense_stat_text.text_data, player.defense, player.defense_bonus);
        updateStat(&self.resistance_stat_text.text_data, player.resistance, player.resistance_bonus);
        updateStat(&self.speed_stat_text.text_data, player.speed, player.speed_bonus);
        updateStat(&self.stamina_stat_text.text_data, player.stamina, player.stamina);
        updateStat(&self.intelligence_stat_text.text_data, player.intelligence, player.intelligence_bonus);
        updateStat(&self.penetration_stat_text.text_data, player.penetration, player.penetration_bonus);
        updateStat(&self.piercing_stat_text.text_data, player.piercing, player.piercing_bonus);
        updateStat(&self.haste_stat_text.text_data, player.haste, player.haste_bonus);
        updateStat(&self.tenacity_stat_text.text_data, player.tenacity, player.tenacity_bonus);
    }
}

pub fn updateFpsText(self: *GameScreen, fps: usize, mem: f32) !void {
    const fmt =
        \\FPS: {}
        \\Memory: {d:.1} MB
    ;
    self.fps_text.text_data.setText(try std.fmt.bufPrint(self.fps_text.text_data.backing_buffer, fmt, .{ fps, mem }));
}

fn parseItemRects(self: *GameScreen) void {
    for (0..22) |i| {
        if (i < 4) {
            const hori_idx: f32 = @floatFromInt(@mod(i, 4));
            self.inventory_pos_data[i] = .{
                .x = 113 + hori_idx * 56,
                .y = 15,
                .w = 56,
                .h = 56,
                .w_pad = 0,
                .h_pad = 0,
            };
        } else {
            const hori_idx: f32 = @floatFromInt(@mod(i - 4, 6));
            const vert_idx: f32 = @floatFromInt(@divFloor(i - 4, 6));
            self.inventory_pos_data[i] = .{
                .x = 15 + hori_idx * 46,
                .y = 75 + vert_idx * 46,
                .w = 46,
                .h = 46,
                .w_pad = 0,
                .h_pad = 0,
            };
        }
    }

    for (0..9) |i| {
        const hori_idx: f32 = @floatFromInt(@mod(i, 3));
        const vert_idx: f32 = @floatFromInt(@divFloor(i, 3));
        self.container_pos_data[i] = .{
            .x = 15 + hori_idx * 46,
            .y = 15 + vert_idx * 46,
            .w = 46,
            .h = 46,
            .w_pad = 0,
            .h_pad = 0,
        };
    }
}

fn swapError(self: *GameScreen, start_slot: Slot, start_item: u16) void {
    if (start_slot.is_container) {
        self.setContainerItem(start_item, start_slot.idx);
    } else {
        self.setInvItem(start_item, start_slot.idx);
    }

    assets.playSfx("error.mp3");
}

pub fn swapSlots(self: *GameScreen, start_slot: Slot, end_slot: Slot) void {
    std.debug.assert(!map.useLockForType(Player).tryLock());

    const int_id = map.interactive.map_id.load(.acquire);

    const start_item = if (start_slot.is_container)
        self.container_items[start_slot.idx].item
    else
        self.inventory_items[start_slot.idx].item;

    if (end_slot.idx == 255) {
        if (!start_slot.is_container) {
            self.setInvItem(std.math.maxInt(u16), start_slot.idx);
            main.server.sendPacket(.{ .inv_drop = .{
                .player_map_id = map.info.player_map_id,
                .slot_id = start_slot.idx,
            } });
        } else {
            self.swapError(start_slot, start_item);
            return;
        }
    } else {
        if (map.localPlayer(.con)) |local_player| {
            const start_data = game_data.item.from_id.get(start_item) orelse {
                self.swapError(start_slot, start_item);
                return;
            };

            const end_item_types = blk: {
                if (end_slot.is_container) {
                    var cont_lock = map.useLockForType(Container);
                    cont_lock.lock();
                    defer cont_lock.unlock();
                    const container = map.findObject(Container, self.container_id, .con) orelse {
                        self.swapError(start_slot, start_item);
                        return;
                    };
                    break :blk &container.data.item_types;
                } else break :blk local_player.data.item_types;
            };

            if (!game_data.ItemType.typesMatch(start_data.item_type, if (end_slot.idx < 4) end_item_types[end_slot.idx] else .any)) {
                self.swapError(start_slot, start_item);
                return;
            }

            const end_item = if (end_slot.is_container)
                self.container_items[end_slot.idx].item
            else
                self.inventory_items[end_slot.idx].item;

            if (start_slot.is_container) {
                self.setContainerItem(end_item, start_slot.idx);
            } else {
                self.setInvItem(end_item, start_slot.idx);
            }

            if (end_slot.is_container) {
                self.setContainerItem(start_item, end_slot.idx);
            } else {
                self.setInvItem(start_item, end_slot.idx);
            }

            main.server.sendPacket(.{ .inv_swap = .{
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
    if (item.item < 0) return;

    const start_slot = Slot.findSlotId(systems.screen.game.*, item.base.x + 4, item.base.y + 4);
    if (game_data.item.from_id.get(@intCast(item.item))) |props| {
        if (props.consumable and !start_slot.is_container) {
            var lock = map.useLockForType(Player);
            lock.lock();
            defer lock.unlock();
            if (map.localPlayer(.con)) |local_player| {
                main.server.sendPacket(.{ .use_item = .{
                    .obj_type = .player,
                    .map_id = map.info.player_map_id,
                    .slot_id = start_slot.idx,
                    .x = local_player.x,
                    .y = local_player.y,
                    .time = main.current_time,
                } });
                assets.playSfx("consume.mp3");
            }

            return;
        }
    }

    var lock = map.useLockForType(Player);
    lock.lock();
    defer lock.unlock();
    if (map.localPlayer(.con)) |local_player| {
        if (game_data.item.from_id.get(@intCast(item.item))) |data| {
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
    }
}

fn returnToRetrieve(_: ?*anyopaque) void {
    if (systems.screen == .game) main.server.sendPacket(.{ .escape = .{} });
}

fn openOptions(_: ?*anyopaque) void {
    input.handleOptions();
}

fn statsCallback(ud: ?*anyopaque) void {
    const screen: *GameScreen = @alignCast(@ptrCast(ud.?));
    screen.stats_container.base.visible = !screen.stats_container.base.visible;
    screen.cards_container.base.visible = false;
    if (screen.stats_container.base.visible) {
        var lock = map.useLockForType(Player);
        lock.lock();
        defer lock.unlock();
        screen.updateStats();
    }
}

pub fn cardsCallback(ud: ?*anyopaque) void {
    const screen: *GameScreen = @alignCast(@ptrCast(ud.?));
    screen.cards_container.base.visible = !screen.cards_container.base.visible;
    screen.stats_container.base.visible = false;
}

fn chatCallback(input_text: []const u8) void {
    if (input_text.len > 0) {
        main.server.sendPacket(.{ .player_text = .{ .text = input_text } });

        const text_copy = main.allocator.dupe(u8, input_text) catch unreachable;
        input.input_history.append(main.allocator, text_copy) catch unreachable;
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

        // to update the background image
        if (start_slot.is_container)
            current_screen.setContainerItem(item.item, start_slot.idx)
        else
            current_screen.setInvItem(item.item, start_slot.idx);
        return;
    }

    var lock = map.useLockForType(Player);
    lock.lock();
    defer lock.unlock();
    current_screen.swapSlots(start_slot, end_slot);
}

fn itemShiftClickCallback(item: *Item) void {
    if (item.item < 0) return;

    const current_screen = systems.screen.game.*;
    const slot = Slot.findSlotId(current_screen, item.base.x + 4, item.base.y + 4);

    if (game_data.item.from_id.get(@intCast(item.item))) |props| {
        if (props.consumable) {
            var lock = map.useLockForType(Player);
            lock.lock();
            defer lock.unlock();
            if (map.localPlayer(.con)) |local_player| {
                main.server.sendPacket(.{ .use_item = .{
                    .obj_type = if (slot.is_container) .container else .player,
                    .map_id = if (slot.is_container) current_screen.container_id else map.info.player_map_id,
                    .slot_id = slot.idx,
                    .x = local_player.x,
                    .y = local_player.y,
                    .time = main.current_time,
                } });
                assets.playSfx("consume.mp3");
            }

            return;
        }
    }
}

pub fn useItem(self: *GameScreen, idx: u8) void {
    itemDoubleClickCallback(self.inventory_items[idx]);
}

pub fn setContainerItem(self: *GameScreen, item: u16, idx: u8) void {
    if (item == std.math.maxInt(u16)) {
        self.container_items[idx].item = std.math.maxInt(u16);
        self.container_items[idx].base.visible = false;
        return;
    }

    self.container_items[idx].base.visible = true;

    if (game_data.item.from_id.get(@intCast(item))) |data| {
        if (assets.atlas_data.get(data.texture.sheet)) |tex| {
            const atlas_data = tex[data.texture.index];
            const base_x = self.container_decor.base.x + self.container_pos_data[idx].x;
            const base_y = self.container_decor.base.y + self.container_pos_data[idx].y;
            const pos_w = self.container_pos_data[idx].w;
            const pos_h = self.container_pos_data[idx].h;

            if (std.mem.eql(u8, data.rarity, "Mythic")) {
                self.container_items[idx].background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("mythic_slot", 0) } };
            } else if (std.mem.eql(u8, data.rarity, "Legendary")) {
                self.container_items[idx].background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("legendary_slot", 0) } };
            } else if (std.mem.eql(u8, data.rarity, "Epic")) {
                self.container_items[idx].background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("epic_slot", 0) } };
            } else if (std.mem.eql(u8, data.rarity, "Rare")) {
                self.container_items[idx].background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("rare_slot", 0) } };
            } else {
                self.container_items[idx].background_image_data = null;
            }

            self.container_items[idx].item = item;
            self.container_items[idx].image_data.normal.atlas_data = atlas_data;
            self.container_items[idx].base.x = base_x + (pos_w - self.container_items[idx].texWRaw()) / 2 + assets.padding;
            self.container_items[idx].base.y = base_y + (pos_h - self.container_items[idx].texHRaw()) / 2 + assets.padding;

            return;
        } else {
            std.log.err("Could not find ui sheet {s} for item with data id {}, index {}", .{ data.texture.sheet, item, idx });
        }
    } else {
        std.log.err("Attempted to populate inventory index {} with item {}, but props was not found", .{ idx, item });
    }

    self.container_items[idx].item = std.math.maxInt(u16);
    self.container_items[idx].image_data.normal.atlas_data = assets.error_data;
    self.container_items[idx].base.x = self.container_decor.base.x +
        self.container_pos_data[idx].x + (self.container_pos_data[idx].w - self.container_items[idx].texWRaw()) / 2 + assets.padding;
    self.container_items[idx].base.y = self.container_decor.base.y +
        self.container_pos_data[idx].y + (self.container_pos_data[idx].h - self.container_items[idx].texHRaw()) / 2 + assets.padding;
    self.container_items[idx].background_image_data = null;
}

pub fn setInvItem(self: *GameScreen, item: u16, idx: u8) void {
    if (item == std.math.maxInt(u16)) {
        self.inventory_items[idx].item = std.math.maxInt(u16);
        self.inventory_items[idx].base.visible = false;
        return;
    }

    self.inventory_items[idx].base.visible = true;

    if (game_data.item.from_id.get(@intCast(item))) |data| {
        if (assets.atlas_data.get(data.texture.sheet)) |tex| {
            const atlas_data = tex[data.texture.index];
            const base_x = self.inventory_decor.base.x + self.inventory_pos_data[idx].x;
            const base_y = self.inventory_decor.base.y + self.inventory_pos_data[idx].y;
            const pos_w = self.inventory_pos_data[idx].w;
            const pos_h = self.inventory_pos_data[idx].h;

            if (idx < 4) {
                if (std.mem.eql(u8, data.rarity, "Mythic")) {
                    self.inventory_items[idx].background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("mythic_slot_equip", 0) } };
                } else if (std.mem.eql(u8, data.rarity, "Legendary")) {
                    self.inventory_items[idx].background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("legendary_slot_equip", 0) } };
                } else if (std.mem.eql(u8, data.rarity, "Epic")) {
                    self.inventory_items[idx].background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("epic_slot_equip", 0) } };
                } else if (std.mem.eql(u8, data.rarity, "Rare")) {
                    self.inventory_items[idx].background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("rare_slot_equip", 0) } };
                } else {
                    self.inventory_items[idx].background_image_data = null;
                }
            } else {
                if (std.mem.eql(u8, data.rarity, "Mythic")) {
                    self.inventory_items[idx].background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("mythic_slot", 0) } };
                } else if (std.mem.eql(u8, data.rarity, "Legendary")) {
                    self.inventory_items[idx].background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("legendary_slot", 0) } };
                } else if (std.mem.eql(u8, data.rarity, "Epic")) {
                    self.inventory_items[idx].background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("epic_slot", 0) } };
                } else if (std.mem.eql(u8, data.rarity, "Rare")) {
                    self.inventory_items[idx].background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("rare_slot", 0) } };
                } else {
                    self.inventory_items[idx].background_image_data = null;
                }
            }

            self.inventory_items[idx].item = item;
            self.inventory_items[idx].image_data.normal.atlas_data = atlas_data;
            self.inventory_items[idx].base.x = base_x + (pos_w - self.inventory_items[idx].texWRaw()) / 2 + assets.padding;
            self.inventory_items[idx].base.y = base_y + (pos_h - self.inventory_items[idx].texHRaw()) / 2 + assets.padding;

            return;
        } else {
            std.log.err("Could not find ui sheet {s} for item with data id {}, index {}", .{ data.texture.sheet, item, idx });
        }
    } else {
        std.log.err("Attempted to populate inventory index {} with item id {}, but props was not found", .{ idx, item });
    }

    const atlas_data = assets.error_data;
    self.inventory_items[idx].item = std.math.maxInt(u16);
    self.inventory_items[idx].image_data.normal.atlas_data = atlas_data;
    self.inventory_items[idx].base.x = self.inventory_decor.base.x + self.inventory_pos_data[idx].x + (self.inventory_pos_data[idx].w - self.inventory_items[idx].texWRaw()) / 2 + assets.padding;
    self.inventory_items[idx].base.y = self.inventory_decor.base.y + self.inventory_pos_data[idx].y + (self.inventory_pos_data[idx].h - self.inventory_items[idx].texHRaw()) / 2 + assets.padding;
    self.inventory_items[idx].background_image_data = null;
}

pub fn setContainerVisible(self: *GameScreen, visible: bool) void {
    self.container_visible = visible;
    self.container_decor.base.visible = visible;
}
