const std = @import("std");
const element = @import("../element.zig");
const assets = @import("../../assets.zig");
const camera = @import("../../camera.zig");
const network = @import("../../network.zig");
const main = @import("../../main.zig");
const utils = @import("../../utils.zig");
const game_data = @import("../../game_data.zig");
const map = @import("../../game/map.zig");
const input = @import("../../input.zig");
const settings = @import("../../settings.zig");

const systems = @import("../systems.zig");
const Options = @import("options.zig").Options;
const Interactable = element.InteractableImageData;
const NineSlice = element.NineSliceImageData;

pub const GameScreen = struct {
    pub const Slot = struct {
        idx: u8,
        is_container: bool = false,

        fn findInvSlotId(screen: GameScreen, x: f32, y: f32) u8 {
            for (0..22) |i| {
                const data = screen.inventory_pos_data[i];
                if (utils.isInBounds(
                    x,
                    y,
                    screen.inventory_decor.x + data.x - data.w_pad,
                    screen.inventory_decor.y + data.y - data.h_pad,
                    data.w + data.w_pad * 2,
                    data.h + data.h_pad * 2,
                )) {
                    return @intCast(i);
                }
            }

            return 255;
        }

        fn findContainerSlotId(screen: GameScreen, x: f32, y: f32) u8 {
            if (!systems.screen.game.container_visible)
                return 255;

            for (0..9) |i| {
                const data = screen.container_pos_data[i];
                if (utils.isInBounds(
                    x,
                    y,
                    screen.container_decor.x + data.x - data.w_pad,
                    screen.container_decor.y + data.y - data.h_pad,
                    data.w + data.w_pad * 2,
                    data.h + data.h_pad * 2,
                )) {
                    return @intCast(i);
                }
            }

            return 255;
        }

        pub fn findSlotId(screen: GameScreen, x: f32, y: f32) Slot {
            const inv_slot = findInvSlotId(screen, x, y);
            if (inv_slot != 255) {
                return .{ .idx = inv_slot };
            }

            const container_slot = findContainerSlotId(screen, x, y);
            if (container_slot != 255) {
                return .{ .idx = container_slot, .is_container = true };
            }

            return .{ .idx = 255 };
        }

        pub fn nextEquippableSlot(slot_types: []game_data.ItemType, base_slot_type: game_data.ItemType) Slot {
            for (0..slot_types.len) |idx| {
                if (slot_types[idx].slotsMatch(base_slot_type))
                    return .{ .idx = @intCast(idx) };
            }
            return .{ .idx = 255 };
        }

        pub fn nextAvailableSlot(screen: GameScreen, slot_types: []game_data.ItemType, base_slot_type: game_data.ItemType) Slot {
            for (0..slot_types.len) |idx| {
                if (screen.inventory_items[idx].item == std.math.maxInt(u16) and slot_types[idx].slotsMatch(base_slot_type))
                    return .{ .idx = @intCast(idx) };
            }
            return .{ .idx = 255 };
        }
    };

    last_level: i32 = -1,
    last_xp: i32 = -1,
    last_xp_goal: i32 = -1,
    last_fame: i32 = -1,
    last_fame_goal: i32 = -1,
    last_hp: i32 = -1,
    last_max_hp: i32 = -1,
    last_mp: i32 = -1,
    last_max_mp: i32 = -1,
    last_spirits: i32 = -1,
    last_next_spirits: i32 = -1,
    last_in_combat: bool = false,
    interact_class: game_data.ClassType = game_data.ClassType.game_object,
    container_visible: bool = false,
    container_id: i32 = -1,

    options: *Options = undefined,

    fps_text: *element.Text = undefined,
    chat_input: *element.Input = undefined,
    chat_decor: *element.Image = undefined,
    chat_container: *element.ScrollableContainer = undefined,
    chat_lines: std.ArrayList(*element.Text) = undefined,
    bars_decor: *element.Image = undefined,
    stats_button: *element.Button = undefined,
    stats_container: *element.Container = undefined,
    ability_container: *element.Container = undefined,
    stats_decor: *element.Image = undefined,
    strength_stat_text: *element.Text = undefined,
    defense_stat_text: *element.Text = undefined,
    speed_stat_text: *element.Text = undefined,
    haste_stat_text: *element.Text = undefined,
    wit_stat_text: *element.Text = undefined,
    resistance_stat_text: *element.Text = undefined,
    stamina_stat_text: *element.Text = undefined,
    intelligence_stat_text: *element.Text = undefined,
    penetration_stat_text: *element.Text = undefined,
    piercing_stat_text: *element.Text = undefined,
    tenacity_stat_text: *element.Text = undefined,
    xp_bar: *element.Bar = undefined,
    health_bar: *element.Bar = undefined,
    mana_bar: *element.Bar = undefined,
    inventory_decor: *element.Image = undefined,
    inventory_items: [22]*element.Item = undefined,
    container_decor: *element.Image = undefined,
    container_name: *element.Text = undefined,
    container_items: [9]*element.Item = undefined,
    minimap_decor: *element.Image = undefined,
    minimap_slots: *element.Image = undefined,
    retrieve_button: *element.Button = undefined,
    options_button: *element.Button = undefined,
    combat_indicator: *element.Image = undefined,

    inventory_pos_data: [22]utils.Rect = undefined,
    container_pos_data: [9]utils.Rect = undefined,

    abilities_inited: bool = false,
    inited: bool = false,
    allocator: std.mem.Allocator = undefined,

    pub fn init(allocator: std.mem.Allocator) !*GameScreen {
        var screen = try allocator.create(GameScreen);
        screen.* = .{ .allocator = allocator };

        screen.chat_lines = std.ArrayList(*element.Text).init(allocator);

        const inventory_data = assets.getUiData("player_inventory", 0);
        screen.parseItemRects();

        const minimap_data = assets.getUiData("minimap", 0);
        screen.minimap_decor = try element.create(allocator, element.Image{
            .x = camera.screen_width - minimap_data.texWRaw() + 10,
            .y = -10,
            .image_data = .{ .normal = .{ .atlas_data = minimap_data } },
            .is_minimap_decor = true,
            .minimap_offset_x = 21.0 + assets.padding,
            .minimap_offset_y = 21.0 + assets.padding,
            .minimap_width = 212.0,
            .minimap_height = 212.0,
        });

        const minimap_slots_data = assets.getUiData("minimap_slots", 0);
        screen.minimap_slots = try element.create(allocator, element.Image{
            .x = screen.minimap_decor.x + 15,
            .y = screen.minimap_decor.y + 209,
            .image_data = .{ .normal = .{ .atlas_data = minimap_slots_data } },
        });

        const retrieve_button_data = assets.getUiData("retrieve_button", 0);
        screen.retrieve_button = try element.create(allocator, element.Button{
            .x = screen.minimap_slots.x + 6 + (18 - retrieve_button_data.texWRaw()) / 2.0,
            .y = screen.minimap_slots.y + 6 + (18 - retrieve_button_data.texHRaw()) / 2.0,
            .image_data = .{ .base = .{ .normal = .{ .atlas_data = retrieve_button_data } } },
            .tooltip_text = .{
                .text = "Return to the Retrieve",
                .size = 12,
                .text_type = .bold_italic,
            },
            .press_callback = returnToRetrieve,
        });

        const options_button_data = assets.getUiData("options_button", 0);
        screen.options_button = try element.create(allocator, element.Button{
            .x = screen.minimap_slots.x + 36 + (18 - options_button_data.texWRaw()) / 2.0,
            .y = screen.minimap_slots.y + 6 + (18 - options_button_data.texHRaw()) / 2.0,
            .image_data = .{ .base = .{ .normal = .{ .atlas_data = options_button_data } } },
            .tooltip_text = .{
                .text = "Open Options",
                .size = 12,
                .text_type = .bold_italic,
            },
            .press_callback = openOptions,
        });

        screen.inventory_decor = try element.create(allocator, element.Image{
            .x = camera.screen_width - inventory_data.texWRaw() + 10,
            .y = camera.screen_height - inventory_data.texHRaw() + 10,
            .image_data = .{ .normal = .{ .atlas_data = inventory_data } },
        });

        for (0..22) |i| {
            const scale: f32 = if (i < 4) 4.0 else 3.0;
            screen.inventory_items[i] = try element.create(allocator, element.Item{
                .x = screen.inventory_decor.x + screen.inventory_pos_data[i].x + (screen.inventory_pos_data[i].w - assets.error_data.texWRaw() * 4.0 + assets.padding * 2) / 2,
                .y = screen.inventory_decor.y + screen.inventory_pos_data[i].y + (screen.inventory_pos_data[i].h - assets.error_data.texHRaw() * 4.0 + assets.padding * 2) / 2,
                .background_x = screen.inventory_decor.x + screen.inventory_pos_data[i].x,
                .background_y = screen.inventory_decor.y + screen.inventory_pos_data[i].y,
                .image_data = .{ .normal = .{ .scale_x = scale, .scale_y = scale, .atlas_data = assets.error_data } },
                .visible = false,
                .draggable = true,
                .drag_start_callback = itemDragStartCallback,
                .drag_end_callback = itemDragEndCallback,
                .double_click_callback = itemDoubleClickCallback,
                .shift_click_callback = itemShiftClickCallback,
            });
        }

        const container_data = assets.getUiData("container_view", 0);
        screen.container_decor = try element.create(allocator, element.Image{
            .x = screen.inventory_decor.x - container_data.texWRaw() + 10,
            .y = camera.screen_height - container_data.texHRaw() + 10,
            .image_data = .{ .normal = .{ .atlas_data = container_data } },
            .visible = false,
        });

        for (0..9) |i| {
            screen.container_items[i] = try element.create(allocator, element.Item{
                .x = screen.container_decor.x + screen.container_pos_data[i].x + (screen.container_pos_data[i].w - assets.error_data.texWRaw() * 4.0 + assets.padding * 2) / 2,
                .y = screen.container_decor.y + screen.container_pos_data[i].y + (screen.container_pos_data[i].h - assets.error_data.texHRaw() * 4.0 + assets.padding * 2) / 2,
                .background_x = screen.container_decor.x + screen.container_pos_data[i].x,
                .background_y = screen.container_decor.y + screen.container_pos_data[i].y,
                .image_data = .{ .normal = .{ .scale_x = 3.0, .scale_y = 3.0, .atlas_data = assets.error_data } },
                .visible = false,
                .draggable = true,
                .drag_start_callback = itemDragStartCallback,
                .drag_end_callback = itemDragEndCallback,
                .double_click_callback = itemDoubleClickCallback,
                .shift_click_callback = itemShiftClickCallback,
            });
        }

        const bars_data = assets.getUiData("player_abilities_bars", 0);
        screen.bars_decor = try element.create(allocator, element.Image{
            .x = (camera.screen_width - bars_data.texWRaw()) / 2,
            .y = camera.screen_height - bars_data.texHRaw() + 10,
            .image_data = .{ .normal = .{ .atlas_data = bars_data } },
        });

        const out_of_combat_data = assets.getUiData("out_of_combat_icon", 0);
        screen.combat_indicator = try element.create(allocator, element.Image{
            .x = screen.bars_decor.x + 15 + (44 - out_of_combat_data.texWRaw()) / 2,
            .y = screen.bars_decor.y + 66 - out_of_combat_data.texHRaw() - 10,
            .image_data = .{ .normal = .{ .atlas_data = out_of_combat_data } },
            .tooltip_text = .{
                .text = "Out of Combat",
                .size = 16,
                .text_type = .bold_italic,
            },
        });

        const stats_button_data = assets.getUiData("minimap_icons", 0);
        screen.stats_button = try element.create(allocator, element.Button{
            .x = screen.bars_decor.x + 21 + (32 - stats_button_data.texWRaw() + assets.padding * 2) / 2.0,
            .y = screen.bars_decor.y + 117 + (32 - stats_button_data.texHRaw() + assets.padding * 2) / 2.0,
            .image_data = .{ .base = .{ .normal = .{ .atlas_data = stats_button_data } } },
            .userdata = screen,
            .press_callback = statsCallback,
        });

        screen.ability_container = try element.create(allocator, element.Container{
            .x = screen.bars_decor.x + 69,
            .y = screen.bars_decor.y + 45,
        });

        const stats_decor_data = assets.getUiData("player_stats", 0);
        screen.stats_container = try element.create(allocator, element.Container{
            .x = screen.bars_decor.x + 63 - 15,
            .y = screen.bars_decor.y + 95 - stats_decor_data.texHRaw(),
            .visible = false,
        });

        screen.stats_decor = try screen.stats_container.createChild(element.Image{
            .x = 0,
            .y = 0,
            .image_data = .{ .normal = .{ .atlas_data = stats_decor_data } },
        });

        var idx: f32 = 0;
        try addStatText(screen.stats_container, &screen.strength_stat_text, &idx);
        try addStatText(screen.stats_container, &screen.defense_stat_text, &idx);
        try addStatText(screen.stats_container, &screen.piercing_stat_text, &idx);
        try addStatText(screen.stats_container, &screen.wit_stat_text, &idx);
        try addStatText(screen.stats_container, &screen.resistance_stat_text, &idx);
        try addStatText(screen.stats_container, &screen.penetration_stat_text, &idx);
        try addStatText(screen.stats_container, &screen.stamina_stat_text, &idx);
        try addStatText(screen.stats_container, &screen.intelligence_stat_text, &idx);
        try addStatText(screen.stats_container, &screen.speed_stat_text, &idx);
        try addStatText(screen.stats_container, &screen.haste_stat_text, &idx);
        try addStatText(screen.stats_container, &screen.tenacity_stat_text, &idx);

        const health_bar_data = assets.getUiData("player_health_bar", 0);
        screen.health_bar = try element.create(allocator, element.Bar{
            .x = screen.bars_decor.x + 70,
            .y = screen.bars_decor.y + 102,
            .image_data = .{ .normal = .{ .atlas_data = health_bar_data } },
            .text_data = .{
                .text = "",
                .size = 12,
                .text_type = .bold_italic,
                .max_chars = 64,
            },
        });

        const mana_bar_data = assets.getUiData("player_mana_bar", 0);
        screen.mana_bar = try element.create(allocator, element.Bar{
            .x = screen.bars_decor.x + 70,
            .y = screen.bars_decor.y + 132,
            .image_data = .{ .normal = .{ .atlas_data = mana_bar_data } },
            .text_data = .{
                .text = "",
                .size = 12,
                .text_type = .bold_italic,
                .max_chars = 64,
            },
        });

        const xp_bar_data = assets.getUiData("player_xp_bar", 0);
        screen.xp_bar = try screen.ability_container.createChild(element.Bar{
            .x = 1,
            .y = -23,
            .image_data = .{ .normal = .{ .atlas_data = xp_bar_data } },
            .text_data = .{
                .text = "",
                .size = 10,
                .text_type = .bold_italic,
                .max_chars = 64,
            },
        });

        const chat_data = assets.getUiData("chatbox_background", 0);
        const input_data = assets.getUiData("chatbox_input", 0);
        screen.chat_decor = try element.create(allocator, element.Image{
            .x = -10,
            .y = camera.screen_height - chat_data.texHRaw() - input_data.texHRaw() + 15,
            .image_data = .{ .normal = .{ .atlas_data = chat_data } },
        });

        const cursor_data = assets.getUiData("chatbox_cursor", 0);
        screen.chat_input = try element.create(allocator, element.Input{
            .x = screen.chat_decor.x,
            .y = screen.chat_decor.y + screen.chat_decor.height() - 10,
            .text_inlay_x = 21 + assets.padding,
            .text_inlay_y = 21 + assets.padding,
            .image_data = .{ .base = .{ .normal = .{ .atlas_data = input_data } } },
            .cursor_image_data = .{ .normal = .{ .atlas_data = cursor_data } },
            .text_data = .{
                .text = "",
                .size = 12,
                .text_type = .bold,
                .max_chars = 256,
                .handle_special_chars = false,
            },
            .allocator = allocator,
            .enter_callback = chatCallback,
            .is_chat = true,
        });

        const chat_scroll_background_data = assets.getUiData("chatbox_scroll_background", 0);
        const chat_scroll_knob_base = assets.getUiData("chatbox_scroll_wheel_base", 0);
        const chat_scroll_knob_hover = assets.getUiData("chatbox_scroll_wheel_hover", 0);
        const chat_scroll_knob_press = assets.getUiData("chatbox_scroll_wheel_press", 0);
        const chat_scroll_decor_data = assets.getUiData("chatbox_scrollbar_decor", 0);
        screen.chat_container = try element.create(allocator, element.ScrollableContainer{
            .x = screen.chat_decor.x + 24,
            .y = screen.chat_decor.y + 24,
            .scissor_w = 380,
            .scissor_h = 240,
            .scroll_x = screen.chat_decor.x + 400,
            .scroll_y = screen.chat_decor.y + 24,
            .scroll_w = 4,
            .scroll_h = 240,
            .scroll_side_x = screen.chat_decor.x + 393,
            .scroll_side_y = screen.chat_decor.y + 24,
            .scroll_decor_image_data = .{ .nine_slice = NineSlice.fromAtlasData(chat_scroll_background_data, 4, 240, 0, 0, 2, 2, 1.0) },
            .scroll_knob_image_data = Interactable.fromNineSlices(chat_scroll_knob_base, chat_scroll_knob_hover, chat_scroll_knob_press, 10, 16, 4, 4, 1, 2, 1.0),
            .scroll_side_decor_image_data = .{ .nine_slice = NineSlice.fromAtlasData(chat_scroll_decor_data, 6, 240, 0, 41, 6, 3, 1.0) },
            .start_value = 1.0,
        });

        var fps_text_data = element.TextData{
            .text = "",
            .size = 12,
            .text_type = .bold,
            .hori_align = .middle,
            .max_width = screen.minimap_decor.width(),
            .max_chars = 256,
        };

        {
            fps_text_data.lock.lock();
            defer fps_text_data.lock.unlock();

            fps_text_data.recalculateAttributes(allocator);
        }

        screen.fps_text = try element.create(allocator, element.Text{
            .x = screen.minimap_decor.x,
            .y = screen.minimap_decor.y + screen.minimap_decor.height() - 10,
            .text_data = fps_text_data,
        });

        screen.options = try Options.init(allocator);

        screen.inited = true;
        return screen;
    }

    pub fn addChatLine(self: *GameScreen, name: []const u8, text: []const u8, name_color: u32, text_color: u32) !void {
        const container_h = self.chat_container.container.height();

        const line_str = try if (name.len > 0)
            std.fmt.allocPrint(self.allocator, "&col=\"{x}\"[{s}]: &col=\"{x}\"{s}", .{ name_color, name, text_color, text })
        else
            std.fmt.allocPrint(self.allocator, "&col=\"{x}\"{s}", .{ text_color, text });

        var chat_line = try self.chat_container.createChild(element.Text{
            .x = 0,
            .y = 0,
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
            chat_line.y = self.chat_container.scissor_h - line_h;

            for (self.chat_lines.items) |line| {
                line.y -= line_h;
            }
        } else {
            chat_line.y = container_h;
            const first_line_y = if (self.chat_lines.items.len == 0) 0 else self.chat_lines.items[0].y;
            if (first_line_y > 0) {
                for (self.chat_lines.items) |line| {
                    line.y -= first_line_y;
                }
            }
        }

        try self.chat_lines.append(chat_line);
        self.chat_container.update();
    }

    fn addAbility(container: *element.Container, ability: game_data.Ability, idx: *f32) !void {
        defer idx.* += 1;

        if (assets.ui_atlas_data.get(ability.icon.sheet)) |data| {
            const index = ability.icon.index;
            if (data.len <= index) {
                std.log.err("Could not initiate ability for GameScreen, index was out of bounds", .{});
                return;
            }

            _ = try container.createChild(element.Image{
                .x = idx.* * 56.0,
                .y = 0,
                .image_data = .{ .normal = .{ .atlas_data = data[index] } },
                .ability_props = ability,
            });
        } else {
            std.log.err("Could not initiate ability for GameScreen, sheet was missing", .{});
        }
    }

    fn addStatText(container: *element.Container, text: **element.Text, idx: *f32) !void {
        defer idx.* += 1;

        const x = 50.0 + 70.0 * @mod(idx.*, 3.0);
        const y = 27.0 + 28.0 * @floor(idx.* / 3.0);
        text.* = try container.createChild(element.Text{ .x = x, .y = y, .text_data = .{
            .text = "",
            .size = 10,
            .text_type = .bold,
            .max_width = 37,
            .max_height = 18,
            .hori_align = .middle,
            .vert_align = .middle,
            .max_chars = 64,
        } });
    }

    pub fn deinit(self: *GameScreen) void {
        self.inited = false;

        element.destroy(self.minimap_decor);
        element.destroy(self.minimap_slots);
        element.destroy(self.inventory_decor);
        element.destroy(self.container_decor);
        element.destroy(self.bars_decor);
        element.destroy(self.combat_indicator);
        element.destroy(self.stats_button);
        element.destroy(self.stats_container);
        element.destroy(self.ability_container);
        element.destroy(self.chat_container);
        element.destroy(self.health_bar);
        element.destroy(self.mana_bar);
        element.destroy(self.chat_decor);
        element.destroy(self.chat_input);
        element.destroy(self.fps_text);
        element.destroy(self.options_button);
        element.destroy(self.retrieve_button);

        for (self.inventory_items) |item| {
            element.destroy(item);
        }

        for (self.container_items) |item| {
            element.destroy(item);
        }

        self.chat_lines.deinit();
        self.options.deinit();

        self.allocator.destroy(self);
    }

    pub fn resize(self: *GameScreen, w: f32, h: f32) void {
        self.minimap_decor.x = w - self.minimap_decor.width() + 10;
        self.minimap_slots.x = self.minimap_decor.x + 15;
        self.minimap_slots.y = self.minimap_decor.y + 209;
        self.fps_text.x = self.minimap_decor.x;
        self.fps_text.y = self.minimap_decor.y + self.minimap_decor.height() - 10;
        self.inventory_decor.x = w - self.inventory_decor.width() + 10;
        self.inventory_decor.y = h - self.inventory_decor.height() + 10;
        self.container_decor.x = self.inventory_decor.x - self.container_decor.width() + 10;
        self.container_decor.y = h - self.container_decor.height() + 10;
        self.bars_decor.x = (w - self.bars_decor.width()) / 2;
        self.bars_decor.y = h - self.bars_decor.height() + 10;
        self.combat_indicator.x = self.bars_decor.x + 15 + (44 - self.combat_indicator.width()) / 2;
        self.combat_indicator.y = self.bars_decor.y + 66 - self.combat_indicator.height() - 10;
        self.stats_container.x = self.bars_decor.x + 63 - 15;
        self.stats_container.y = self.bars_decor.y + 95 - self.stats_decor.height();
        self.ability_container.x = self.bars_decor.x + 71;
        self.ability_container.y = self.bars_decor.y + 47;
        self.stats_button.x = self.bars_decor.x + 21 + (32 - self.stats_button.width() + assets.padding * 2) / 2.0;
        self.stats_button.y = self.bars_decor.y + 117 + (32 - self.stats_button.height() + assets.padding * 2) / 2.0;
        self.health_bar.x = self.bars_decor.x + 70;
        self.health_bar.y = self.bars_decor.y + 102;
        self.mana_bar.x = self.bars_decor.x + 70;
        self.mana_bar.y = self.bars_decor.y + 132;
        const chat_decor_h = self.chat_decor.height();
        self.chat_decor.y = h - chat_decor_h - self.chat_input.image_data.current(self.chat_input.state).normal.height() + 15;
        self.chat_container.container.x = self.chat_decor.x + 26;
        const old_y = self.chat_container.base_y;
        self.chat_container.base_y = self.chat_decor.y + 26;
        self.chat_container.container.y += (self.chat_container.base_y - old_y);
        self.chat_container.scroll_bar.x = self.chat_decor.x + 386;
        self.chat_container.scroll_bar.y = self.chat_decor.y + 26;
        self.chat_input.y = self.chat_decor.y + chat_decor_h - 10;
        self.retrieve_button.x = self.minimap_slots.x + 6 + (18 - self.retrieve_button.width()) / 2.0;
        self.retrieve_button.y = self.minimap_slots.y + 6 + (18 - self.retrieve_button.height()) / 2.0;
        self.options_button.x = self.minimap_slots.x + 36 + (18 - self.options_button.width()) / 2.0;
        self.options_button.y = self.minimap_slots.y + 6 + (18 - self.options_button.height()) / 2.0;

        for (0..22) |idx| {
            self.inventory_items[idx].x = self.inventory_decor.x + systems.screen.game.inventory_pos_data[idx].x + (systems.screen.game.inventory_pos_data[idx].w - self.inventory_items[idx].width() + assets.padding * 2) / 2;
            self.inventory_items[idx].y = self.inventory_decor.y + systems.screen.game.inventory_pos_data[idx].y + (systems.screen.game.inventory_pos_data[idx].h - self.inventory_items[idx].height() + assets.padding * 2) / 2;
            self.inventory_items[idx].background_x = self.inventory_decor.x + systems.screen.game.inventory_pos_data[idx].x;
            self.inventory_items[idx].background_y = self.inventory_decor.y + systems.screen.game.inventory_pos_data[idx].y;
        }

        for (0..9) |idx| {
            self.container_items[idx].x = self.container_decor.x + systems.screen.game.container_pos_data[idx].x + (systems.screen.game.container_pos_data[idx].w - self.container_items[idx].width() + assets.padding * 2) / 2;
            self.container_items[idx].y = self.container_decor.y + systems.screen.game.container_pos_data[idx].y + (systems.screen.game.container_pos_data[idx].h - self.container_items[idx].height() + assets.padding * 2) / 2;
            self.container_items[idx].background_x = self.container_decor.x + systems.screen.game.container_pos_data[idx].x;
            self.container_items[idx].background_y = self.container_decor.y + systems.screen.game.container_pos_data[idx].y;
        }

        self.options.resize(w, h);
    }

    pub fn update(self: *GameScreen, _: i64, _: f32) !void {
        self.fps_text.visible = settings.stats_enabled;

        map.object_lock.lockShared();
        defer map.object_lock.unlockShared();

        if (map.localPlayerConst()) |local_player| {
            if (!self.abilities_inited) {
                var idx: f32 = 0;
                try addAbility(self.ability_container, local_player.class_data.ability_1, &idx);
                try addAbility(self.ability_container, local_player.class_data.ability_2, &idx);
                try addAbility(self.ability_container, local_player.class_data.ability_3, &idx);
                try addAbility(self.ability_container, local_player.class_data.ultimate_ability, &idx);
                self.abilities_inited = true;
            }

            if (self.last_in_combat != local_player.in_combat) {
                if (local_player.in_combat) {
                    const in_combat_data = assets.getUiData("in_combat_icon", 0);
                    self.combat_indicator.image_data.normal.atlas_data = in_combat_data;
                    self.combat_indicator.tooltip_text.?.text = "In Combat&size=\"12\"&type=\"med\"\n\nYou are unable to return to the Retrieve, teleport or enter portals until you exit combat.";
                    self.combat_indicator.tooltip_text.?.hori_align = .middle;
                    self.combat_indicator.tooltip_text.?.max_width = 250;
                } else {
                    const out_of_combat_data = assets.getUiData("out_of_combat_icon", 0);
                    self.combat_indicator.image_data.normal.atlas_data = out_of_combat_data;
                    self.combat_indicator.tooltip_text.?.text = "Out of Combat";
                    self.combat_indicator.tooltip_text.?.hori_align = .left;
                    self.combat_indicator.tooltip_text.?.max_width = std.math.floatMax(f32);
                }

                self.combat_indicator.tooltip_text.?.lock.lock();
                defer self.combat_indicator.tooltip_text.?.lock.unlock();

                self.combat_indicator.tooltip_text.?.recalculateAttributes(self.allocator);
                self.combat_indicator.x = self.bars_decor.x + (self.bars_decor.width() - self.combat_indicator.width()) / 2;
                self.combat_indicator.y = self.bars_decor.y - self.combat_indicator.height() - 10;

                self.last_in_combat = local_player.in_combat;
            }

            if (self.last_spirits != local_player.spirits_communed or self.last_next_spirits != local_player.next_spirits) {
                const xp_perc = @as(f32, @floatFromInt(local_player.spirits_communed)) / @as(f32, @floatFromInt(local_player.next_spirits));
                self.xp_bar.scissor.max_x = self.xp_bar.width() * xp_perc;

                var xp_text_data = &self.xp_bar.text_data;
                xp_text_data.setText(
                    try std.fmt.bufPrint(xp_text_data.backing_buffer, "{d}/{d}", .{ local_player.spirits_communed, local_player.next_spirits }),
                    self.allocator,
                );

                self.last_spirits = local_player.spirits_communed;
                self.last_next_spirits = local_player.next_spirits;
            }

            if (self.last_hp != local_player.hp or self.last_max_hp != local_player.max_hp) {
                const hp_perc = @as(f32, @floatFromInt(local_player.hp)) / @as(f32, @floatFromInt(local_player.max_hp));
                self.health_bar.scissor.max_x = self.health_bar.width() * hp_perc;

                var health_text_data = &self.health_bar.text_data;
                health_text_data.setText(
                    try std.fmt.bufPrint(health_text_data.backing_buffer, "{d}/{d}", .{ local_player.hp, local_player.max_hp }),
                    self.allocator,
                );

                self.last_hp = local_player.hp;
                self.last_max_hp = local_player.max_hp;
            }

            if (self.last_mp != local_player.mp or self.last_max_mp != local_player.max_mp) {
                const mp_perc = @as(f32, @floatFromInt(local_player.mp)) / @as(f32, @floatFromInt(local_player.max_mp));
                self.mana_bar.scissor.max_x = self.mana_bar.width() * mp_perc;

                var mana_text_data = &self.mana_bar.text_data;
                mana_text_data.setText(
                    try std.fmt.bufPrint(mana_text_data.backing_buffer, "{d}/{d}", .{ local_player.mp, local_player.max_mp }),
                    self.allocator,
                );

                self.last_mp = local_player.mp;
                self.last_max_mp = local_player.max_mp;
            }
        }
    }

    fn updateStat(allocator: std.mem.Allocator, text_data: *element.TextData, base_val: i32, bonus_val: i32) void {
        text_data.setText((if (bonus_val > 0)
            std.fmt.bufPrint(
                text_data.backing_buffer,
                "{d}&size=\"8\"&col=\"65E698\"\n(+{d})",
                .{ base_val, bonus_val },
            )
        else if (bonus_val < 0)
            std.fmt.bufPrint(
                text_data.backing_buffer,
                "{d}&size=\"8\"&col=\"FF7070\"\n({d})",
                .{ base_val, bonus_val },
            )
        else
            std.fmt.bufPrint(text_data.backing_buffer, "{d}", .{base_val})) catch text_data.text, allocator);
    }

    pub fn updateStats(self: *GameScreen) void {
        if (!self.inited)
            return;

        if (map.localPlayerConst()) |player| {
            updateStat(self.allocator, &self.strength_stat_text.text_data, player.strength, player.strength_bonus);
            updateStat(self.allocator, &self.resistance_stat_text.text_data, player.resistance, player.resistance_bonus);
            updateStat(self.allocator, &self.intelligence_stat_text.text_data, player.intelligence, player.intelligence_bonus);
            updateStat(self.allocator, &self.haste_stat_text.text_data, player.haste, player.haste_bonus);
            updateStat(self.allocator, &self.wit_stat_text.text_data, player.wit, player.wit_bonus);
            updateStat(self.allocator, &self.speed_stat_text.text_data, player.speed, player.speed_bonus);
            updateStat(self.allocator, &self.penetration_stat_text.text_data, player.penetration, player.penetration_bonus);
            updateStat(self.allocator, &self.tenacity_stat_text.text_data, player.tenacity, player.tenacity_bonus);
            updateStat(self.allocator, &self.defense_stat_text.text_data, player.defense, player.defense_bonus);
            updateStat(self.allocator, &self.stamina_stat_text.text_data, player.stamina, player.stamina_bonus);
            updateStat(self.allocator, &self.piercing_stat_text.text_data, player.piercing, player.piercing_bonus);
        }
    }

    pub fn updateFpsText(self: *GameScreen, fps: usize, mem: f32) !void {
        const fmt =
            \\FPS: {d}
            \\Memory: {d:.1} MB
        ;
        self.fps_text.text_data.setText(try std.fmt.bufPrint(self.fps_text.text_data.backing_buffer, fmt, .{ fps, mem }), self.allocator);
    }

    fn parseItemRects(self: *GameScreen) void {
        for (0..22) |i| {
            if (i < 4) {
                const hori_idx: f32 = @floatFromInt(@mod(i, 4));
                self.inventory_pos_data[i] = utils.Rect{
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
                self.inventory_pos_data[i] = utils.Rect{
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
            self.container_pos_data[i] = utils.Rect{
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

        assets.playSfx("error");
    }

    pub fn swapSlots(self: *GameScreen, start_slot: Slot, end_slot: Slot) void {
        const int_id = map.interactive_id.load(.Acquire);

        if (end_slot.idx == 255) {
            if (start_slot.is_container) {
                self.setContainerItem(std.math.maxInt(u16), start_slot.idx);
                main.server.queuePacket(.{ .inv_drop = .{
                    .obj_id = int_id,
                    .slot_id = start_slot.idx,
                } });
            } else {
                self.setInvItem(std.math.maxInt(u16), start_slot.idx);
                main.server.queuePacket(.{ .inv_drop = .{
                    .obj_id = map.local_player_id,
                    .slot_id = start_slot.idx,
                } });
            }
        } else {
            map.object_lock.lockShared();
            defer map.object_lock.unlockShared();

            if (map.localPlayerConst()) |local_player| {
                const start_item = if (start_slot.is_container)
                    self.container_items[start_slot.idx].item
                else
                    self.inventory_items[start_slot.idx].item;

                const end_item = if (end_slot.is_container)
                    self.container_items[end_slot.idx].item
                else
                    self.inventory_items[end_slot.idx].item;

                const start_props = game_data.item_type_to_props.get(start_item) orelse {
                    self.swapError(start_slot, start_item);
                    return;
                };

                const end_slot_types = switch (map.findEntityConst(if (end_slot.is_container) self.container_id else map.local_player_id) orelse {
                    self.swapError(start_slot, start_item);
                    return;
                }) {
                    .object => |obj| obj.props.slot_types,
                    .player => |player| player.class_data.slot_types,
                    else => {
                        self.swapError(start_slot, start_item);
                        return;
                    },
                };

                if (!game_data.ItemType.slotsMatch(start_props.slot_type, end_slot_types[end_slot.idx])) {
                    self.swapError(start_slot, start_item);
                    return;
                }

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

                main.server.queuePacket(.{ .inv_swap = .{
                    .time = main.current_time,
                    .x = local_player.x,
                    .y = local_player.y,
                    .from_obj_id = if (start_slot.is_container) int_id else map.local_player_id,
                    .from_slot_id = start_slot.idx,
                    .to_obj_id = if (end_slot.is_container) int_id else map.local_player_id,
                    .to_slot_id = end_slot.idx,
                } });

                assets.playSfx("inventory_move_item");
            }
        }
    }

    fn itemDoubleClickCallback(item: *element.Item) void {
        if (item.item < 0)
            return;

        const start_slot = Slot.findSlotId(systems.screen.game.*, item.x + 4, item.y + 4);
        if (game_data.item_type_to_props.get(@intCast(item.item))) |props| {
            if (props.consumable and !start_slot.is_container) {
                map.object_lock.lockShared();
                defer map.object_lock.unlockShared();

                if (map.localPlayerConst()) |local_player| {
                    main.server.queuePacket(.{ .use_item = .{
                        .obj_id = map.local_player_id,
                        .slot_id = start_slot.idx,
                        .x = local_player.x,
                        .y = local_player.y,
                        .time = main.current_time,
                        .use_type = game_data.UseType.default,
                    } });
                    assets.playSfx("use_potion");
                }

                return;
            }
        }

        map.object_lock.lockShared();
        defer map.object_lock.unlockShared();

        if (map.localPlayerConst()) |local_player| {
            if (game_data.item_type_to_props.get(@intCast(item.item))) |props| {
                if (start_slot.is_container) {
                    const end_slot = Slot.nextAvailableSlot(systems.screen.game.*, local_player.class_data.slot_types, props.slot_type);
                    if (start_slot.idx == end_slot.idx and start_slot.is_container == end_slot.is_container) {
                        item.x = item.drag_start_x;
                        item.y = item.drag_start_y;
                        return;
                    }

                    systems.screen.game.swapSlots(start_slot, end_slot);
                } else {
                    const end_slot = Slot.nextEquippableSlot(local_player.class_data.slot_types, props.slot_type);
                    if (end_slot.idx == 255 or // we don't want to drop
                        start_slot.idx == end_slot.idx and start_slot.is_container == end_slot.is_container)
                    {
                        item.x = item.drag_start_x;
                        item.y = item.drag_start_y;
                        return;
                    }

                    systems.screen.game.swapSlots(start_slot, end_slot);
                }
            }
        }
    }

    fn returnToRetrieve(_: ?*anyopaque) void {
        input.tryEscape();
    }

    fn openOptions(_: ?*anyopaque) void {
        input.openOptions();
    }

    pub fn statsCallback(ud: ?*anyopaque) void {
        const screen: *GameScreen = @alignCast(@ptrCast(ud.?));
        screen.stats_container.visible = !screen.stats_container.visible;
        if (screen.stats_container.visible) {
            const abil_button_data = assets.getUiData("minimap_icons", 1);
            screen.stats_button.image_data.base.normal.atlas_data = abil_button_data;

            screen.ability_container.visible = false;

            map.object_lock.lockShared();
            defer map.object_lock.unlockShared();

            screen.updateStats();
        } else {
            const stats_button_data = assets.getUiData("minimap_icons", 0);
            screen.stats_button.image_data.base.normal.atlas_data = stats_button_data;

            screen.ability_container.visible = true;
        }
    }

    fn chatCallback(input_text: []const u8) void {
        if (input_text.len > 0) {
            main.server.queuePacket(.{ .player_text = .{ .text = input_text } });

            const current_screen = systems.screen.game;
            const text_copy = current_screen.allocator.dupe(u8, input_text) catch unreachable;
            input.input_history.append(text_copy) catch unreachable;
            input.input_history_idx = @intCast(input.input_history.items.len);
        }
    }

    fn interactCallback() void {}

    fn itemDragStartCallback(item: *element.Item) void {
        item.background_image_data = null;
    }

    fn itemDragEndCallback(item: *element.Item) void {
        var current_screen = systems.screen.game;
        const start_slot = Slot.findSlotId(current_screen.*, item.drag_start_x + 4, item.drag_start_y + 4);
        const end_slot = Slot.findSlotId(current_screen.*, item.x - item.drag_offset_x, item.y - item.drag_offset_y);
        if (start_slot.idx == end_slot.idx and start_slot.is_container == end_slot.is_container) {
            item.x = item.drag_start_x;
            item.y = item.drag_start_y;

            // to update the background image
            if (start_slot.is_container) {
                current_screen.setContainerItem(item.item, start_slot.idx);
            } else {
                current_screen.setInvItem(item.item, start_slot.idx);
            }
            return;
        }

        current_screen.swapSlots(start_slot, end_slot);
    }

    fn itemShiftClickCallback(item: *element.Item) void {
        if (item.item < 0)
            return;

        const current_screen = systems.screen.game.*;
        const slot = Slot.findSlotId(current_screen, item.x + 4, item.y + 4);

        if (game_data.item_type_to_props.get(@intCast(item.item))) |props| {
            if (props.consumable) {
                map.object_lock.lockShared();
                defer map.object_lock.unlockShared();

                if (map.localPlayerConst()) |local_player| {
                    main.server.queuePacket(.{ .use_item = .{
                        .obj_id = if (slot.is_container) current_screen.container_id else map.local_player_id,
                        .slot_id = slot.idx,
                        .x = local_player.x,
                        .y = local_player.y,
                        .time = main.current_time,
                        .use_type = game_data.UseType.default,
                    } });
                    assets.playSfx("use_potion");
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
            self.container_items[idx].visible = false;
            return;
        }

        self.container_items[idx].visible = true;

        if (game_data.item_type_to_props.get(@intCast(item))) |props| {
            if (assets.atlas_data.get(props.texture_data.sheet)) |data| {
                const atlas_data = data[props.texture_data.index];
                const base_x = self.container_decor.x + self.container_pos_data[idx].x;
                const base_y = self.container_decor.y + self.container_pos_data[idx].y;
                const pos_w = self.container_pos_data[idx].w;
                const pos_h = self.container_pos_data[idx].h;

                if (std.mem.eql(u8, props.rarity, "Mythic")) {
                    self.container_items[idx].background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("mythic_slot", 0) } };
                } else if (std.mem.eql(u8, props.rarity, "Legendary")) {
                    self.container_items[idx].background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("legendary_slot", 0) } };
                } else if (std.mem.eql(u8, props.rarity, "Epic")) {
                    self.container_items[idx].background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("epic_slot", 0) } };
                } else if (std.mem.eql(u8, props.rarity, "Rare")) {
                    self.container_items[idx].background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("rare_slot", 0) } };
                } else {
                    self.container_items[idx].background_image_data = null;
                }

                self.container_items[idx].item = item;
                self.container_items[idx].image_data.normal.atlas_data = atlas_data;
                self.container_items[idx].x = base_x + (pos_w - self.container_items[idx].width() + assets.padding * 2) / 2;
                self.container_items[idx].y = base_y + (pos_h - self.container_items[idx].height() + assets.padding * 2) / 2;

                return;
            } else {
                std.log.err("Could not find ui sheet {s} for item with type 0x{x}, index {d}", .{ props.texture_data.sheet, item, idx });
            }
        } else {
            std.log.err("Attempted to populate inventory index {d} with item 0x{x}, but props was not found", .{ idx, item });
        }

        self.container_items[idx].item = std.math.maxInt(u16);
        self.container_items[idx].image_data.normal.atlas_data = assets.error_data;
        self.container_items[idx].x = self.container_decor.x + self.container_pos_data[idx].x + (self.container_pos_data[idx].w - self.container_items[idx].width() + assets.padding * 2) / 2;
        self.container_items[idx].y = self.container_decor.y + self.container_pos_data[idx].y + (self.container_pos_data[idx].h - self.container_items[idx].height() + assets.padding * 2) / 2;
        self.container_items[idx].background_image_data = null;
    }

    pub fn setInvItem(self: *GameScreen, item: u16, idx: u8) void {
        if (item == std.math.maxInt(u16)) {
            self.inventory_items[idx].item = std.math.maxInt(u16);
            self.inventory_items[idx].visible = false;
            return;
        }

        self.inventory_items[idx].visible = true;

        if (game_data.item_type_to_props.get(@intCast(item))) |props| {
            if (assets.atlas_data.get(props.texture_data.sheet)) |data| {
                const atlas_data = data[props.texture_data.index];
                const base_x = self.inventory_decor.x + self.inventory_pos_data[idx].x;
                const base_y = self.inventory_decor.y + self.inventory_pos_data[idx].y;
                const pos_w = self.inventory_pos_data[idx].w;
                const pos_h = self.inventory_pos_data[idx].h;

                if (idx < 4) {
                    self.inventory_items[idx].image_data.normal.scale_x = 4.0;
                    self.inventory_items[idx].image_data.normal.scale_y = 4.0;

                    if (std.mem.eql(u8, props.rarity, "Mythic")) {
                        self.inventory_items[idx].background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("mythic_slot_equip", 0) } };
                    } else if (std.mem.eql(u8, props.rarity, "Legendary")) {
                        self.inventory_items[idx].background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("legendary_slot_equip", 0) } };
                    } else if (std.mem.eql(u8, props.rarity, "Epic")) {
                        self.inventory_items[idx].background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("epic_slot_equip", 0) } };
                    } else if (std.mem.eql(u8, props.rarity, "Rare")) {
                        self.inventory_items[idx].background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("rare_slot_equip", 0) } };
                    } else {
                        self.inventory_items[idx].background_image_data = null;
                    }
                } else {
                    self.inventory_items[idx].image_data.normal.scale_x = 3.0;
                    self.inventory_items[idx].image_data.normal.scale_y = 3.0;

                    if (std.mem.eql(u8, props.rarity, "Mythic")) {
                        self.inventory_items[idx].background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("mythic_slot", 0) } };
                    } else if (std.mem.eql(u8, props.rarity, "Legendary")) {
                        self.inventory_items[idx].background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("legendary_slot", 0) } };
                    } else if (std.mem.eql(u8, props.rarity, "Epic")) {
                        self.inventory_items[idx].background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("epic_slot", 0) } };
                    } else if (std.mem.eql(u8, props.rarity, "Rare")) {
                        self.inventory_items[idx].background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("rare_slot", 0) } };
                    } else {
                        self.inventory_items[idx].background_image_data = null;
                    }
                }

                self.inventory_items[idx].item = item;
                self.inventory_items[idx].image_data.normal.atlas_data = atlas_data;
                self.inventory_items[idx].x = base_x + (pos_w - self.inventory_items[idx].width() + assets.padding * 2) / 2;
                self.inventory_items[idx].y = base_y + (pos_h - self.inventory_items[idx].height() + assets.padding * 2) / 2;

                return;
            } else {
                std.log.err("Could not find ui sheet {s} for item with type 0x{x}, index {d}", .{ props.texture_data.sheet, item, idx });
            }
        } else {
            std.log.err("Attempted to populate inventory index {d} with item 0x{x}, but props was not found", .{ idx, item });
        }

        if (idx < 4) {
            self.inventory_items[idx].image_data.normal.scale_x = 4.0;
            self.inventory_items[idx].image_data.normal.scale_y = 4.0;
        } else {
            self.inventory_items[idx].image_data.normal.scale_x = 3.0;
            self.inventory_items[idx].image_data.normal.scale_y = 3.0;
        }

        const atlas_data = assets.error_data;
        self.inventory_items[idx].item = std.math.maxInt(u16);
        self.inventory_items[idx].image_data.normal.atlas_data = atlas_data;
        self.inventory_items[idx].x = self.inventory_decor.x + self.inventory_pos_data[idx].x + (self.inventory_pos_data[idx].w - self.inventory_items[idx].width() + assets.padding * 2) / 2;
        self.inventory_items[idx].y = self.inventory_decor.y + self.inventory_pos_data[idx].y + (self.inventory_pos_data[idx].h - self.inventory_items[idx].height() + assets.padding * 2) / 2;
        self.inventory_items[idx].background_image_data = null;
    }

    pub inline fn setContainerVisible(self: *GameScreen, visible: bool) void {
        if (!self.inited)
            return;

        self.container_visible = visible;
        self.container_decor.visible = visible;
    }
};
