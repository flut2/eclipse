const std = @import("std");
const element = @import("../element.zig");
const assets = @import("../../assets.zig");
const camera = @import("../../camera.zig");
const network = @import("../../network.zig");
const main = @import("../../main.zig");
const utils = @import("../../utils.zig");
const game_data = @import("../../game_data.zig");
const map = @import("../../map.zig");
const input = @import("../../input.zig");
const settings = @import("../../settings.zig");

const sc = @import("../controllers/screen_controller.zig");
const PanelController = @import("../controllers/panel_controller.zig").PanelController;
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
            if (!sc.current_screen.game.container_visible)
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

        pub fn nextEquippableSlot(slot_types: [22]game_data.ItemType, base_slot_type: game_data.ItemType) Slot {
            for (0..22) |idx| {
                if (slot_types[idx].slotsMatch(base_slot_type))
                    return .{ .idx = @intCast(idx) };
            }
            return .{ .idx = 255 };
        }

        pub fn nextAvailableSlot(screen: GameScreen) Slot {
            for (0..22) |idx| {
                if (screen.inventory_items[idx]._item == std.math.maxInt(u16))
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
    container_visible: bool = false,
    container_id: i32 = -1,

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

    inventory_pos_data: [22]utils.Rect = undefined,
    container_pos_data: [9]utils.Rect = undefined,

    abilities_inited: bool = false,
    inited: bool = false,
    _allocator: std.mem.Allocator = undefined,

    interact_class: game_data.ClassType = game_data.ClassType.game_object,
    panel_controller: *PanelController = undefined,

    pub fn init(allocator: std.mem.Allocator) !*GameScreen {
        var screen = try allocator.create(GameScreen);
        screen.* = .{ ._allocator = allocator };

        screen.chat_lines = std.ArrayList(*element.Text).init(allocator);

        const inventory_data = assets.getUiData("player_inventory", 0);
        screen.parseItemRects();

        const minimap_data = assets.getUiData("minimap", 0);
        screen.minimap_decor = try element.Image.create(allocator, .{
            .x = camera.screen_width - minimap_data.texWRaw() - 10,
            .y = 10,
            .image_data = .{ .normal = .{ .atlas_data = minimap_data } },
            .is_minimap_decor = true,
            .minimap_offset_x = 6.0,
            .minimap_offset_y = 6.0,
            .minimap_width = 174.0,
            .minimap_height = 174.0,
        });

        screen.inventory_decor = try element.Image.create(allocator, .{
            .x = camera.screen_width - inventory_data.texWRaw() - 10,
            .y = camera.screen_height - inventory_data.texHRaw() - 10,
            .image_data = .{ .normal = .{ .atlas_data = inventory_data } },
        });

        for (0..22) |i| {
            screen.inventory_items[i] = try element.Item.create(allocator, .{
                .x = screen.inventory_decor.x + screen.inventory_pos_data[i].x + (screen.inventory_pos_data[i].w - assets.error_data.texWRaw() * 4.0 + assets.padding * 2) / 2,
                .y = screen.inventory_decor.y + screen.inventory_pos_data[i].y + (screen.inventory_pos_data[i].h - assets.error_data.texHRaw() * 4.0 + assets.padding * 2) / 2,
                .background_x = screen.inventory_decor.x + screen.inventory_pos_data[i].x,
                .background_y = screen.inventory_decor.y + screen.inventory_pos_data[i].y,
                .image_data = .{ .normal = .{ .scale_x = 4.0, .scale_y = 4.0, .atlas_data = assets.error_data } },
                .visible = false,
                .draggable = true,
                .drag_start_callback = itemDragStartCallback,
                .drag_end_callback = itemDragEndCallback,
                .double_click_callback = itemDoubleClickCallback,
                .shift_click_callback = itemShiftClickCallback,
            });
        }

        const container_data = assets.getUiData("container_view", 0);
        screen.container_decor = try element.Image.create(allocator, .{
            .x = screen.inventory_decor.x - container_data.texWRaw() - 10,
            .y = camera.screen_height - container_data.texHRaw() - 10,
            .image_data = .{ .normal = .{ .atlas_data = container_data } },
            .visible = false,
        });

        for (0..9) |i| {
            screen.container_items[i] = try element.Item.create(allocator, .{
                .x = screen.container_decor.x + screen.container_pos_data[i].x + (screen.container_pos_data[i].w - assets.error_data.texWRaw() * 4.0 + assets.padding * 2) / 2,
                .y = screen.container_decor.y + screen.container_pos_data[i].y + (screen.container_pos_data[i].h - assets.error_data.texHRaw() * 4.0 + assets.padding * 2) / 2,
                .background_x = screen.container_decor.x + screen.container_pos_data[i].x,
                .background_y = screen.container_decor.y + screen.container_pos_data[i].y,
                .image_data = .{ .normal = .{
                    .scale_x = 4.0,
                    .scale_y = 4.0,
                    .atlas_data = assets.error_data,
                } },
                .visible = false,
                .draggable = true,
                .drag_start_callback = itemDragStartCallback,
                .drag_end_callback = itemDragEndCallback,
                .double_click_callback = itemDoubleClickCallback,
                .shift_click_callback = itemShiftClickCallback,
            });
        }

        const xp_bar_decor_data = assets.getUiData("player_xp_decor", 0);
        const bars_data = assets.getUiData("player_abilities_bars", 0);
        screen.bars_decor = try element.Image.create(allocator, .{
            .x = (camera.screen_width - bars_data.texWRaw()) / 2,
            .y = camera.screen_height - bars_data.texHRaw() - 10 - 25, // -25 for the xp bar to fit
            .image_data = .{ .normal = .{ .atlas_data = bars_data } },
        });

        const stats_button_data = assets.getUiData("minimap_icons", 0);
        screen.stats_button = try element.Button.create(allocator, .{
            .x = screen.bars_decor.x + 23 + (22 - stats_button_data.texWRaw() + assets.padding * 2) / 2.0,
            .y = screen.bars_decor.y + 10 + (24 - stats_button_data.texHRaw() + assets.padding * 2) / 2.0,
            .image_data = .{ .base = .{ .normal = .{ .atlas_data = stats_button_data } } },
            .press_callback = statsCallback,
        });

        screen.ability_container = try element.Container.create(allocator, .{
            .x = screen.bars_decor.x + 7,
            .y = screen.bars_decor.y + 39,
        });

        const decor_offset_x = -60;
        const decor_offset_y = 56;
        _ = try screen.ability_container.createElement(element.Image, .{
            .x = decor_offset_x,
            .y = decor_offset_y,
            .image_data = .{ .normal = .{ .atlas_data = xp_bar_decor_data } },
        });

        const xp_bar_data = assets.getUiData("player_xp_bar", 0);
        screen.xp_bar = try screen.ability_container.createElement(element.Bar, .{
            .x = decor_offset_x + 24,
            .y = decor_offset_y + 9,
            .image_data = .{ .normal = .{ .atlas_data = xp_bar_data } },
            .text_data = .{
                .text = "",
                .size = 12,
                .text_type = .bold_italic,
                .max_chars = 64,
            },
        });

        const stats_decor_data = assets.getUiData("player_stats", 0);
        screen.stats_container = try element.Container.create(allocator, .{
            .x = screen.bars_decor.x + (bars_data.texWRaw() - stats_decor_data.texWRaw()) / 2.0,
            .y = screen.bars_decor.y + 32,
            .visible = false,
        });

        screen.stats_decor = try screen.stats_container.createElement(element.Image, .{
            .x = 0,
            .y = 0,
            .image_data = .{ .normal = .{ .atlas_data = stats_decor_data } },
        });

        var idx: f32 = 0;
        try addStatText(screen.stats_container, &screen.strength_stat_text, &idx);
        try addStatText(screen.stats_container, &screen.resistance_stat_text, &idx);
        try addStatText(screen.stats_container, &screen.intelligence_stat_text, &idx);
        try addStatText(screen.stats_container, &screen.haste_stat_text, &idx);
        try addStatText(screen.stats_container, &screen.wit_stat_text, &idx);
        try addStatText(screen.stats_container, &screen.speed_stat_text, &idx);
        try addStatText(screen.stats_container, &screen.penetration_stat_text, &idx);
        try addStatText(screen.stats_container, &screen.tenacity_stat_text, &idx);
        try addStatText(screen.stats_container, &screen.defense_stat_text, &idx);
        try addStatText(screen.stats_container, &screen.stamina_stat_text, &idx);
        try addStatText(screen.stats_container, &screen.piercing_stat_text, &idx);

        const health_bar_data = assets.getUiData("player_health_bar", 0);
        screen.health_bar = try element.Bar.create(allocator, .{
            .x = screen.bars_decor.x + 47,
            .y = screen.bars_decor.y + 4,
            .image_data = .{ .normal = .{ .atlas_data = health_bar_data } },
            .text_data = .{
                .text = "",
                .size = 10,
                .text_type = .bold_italic,
                .max_chars = 64,
            },
        });

        const mana_bar_data = assets.getUiData("player_mana_bar", 0);
        screen.mana_bar = try element.Bar.create(allocator, .{
            .x = screen.bars_decor.x + 47,
            .y = screen.bars_decor.y + 18,
            .image_data = .{ .normal = .{ .atlas_data = mana_bar_data } },
            .text_data = .{
                .text = "",
                .size = 10,
                .text_type = .bold_italic,
                .max_chars = 64,
            },
        });

        const chat_data = assets.getUiData("chatbox_background", 0);
        const input_data = assets.getUiData("chatbox_input", 0);
        screen.chat_decor = try element.Image.create(allocator, .{
            .x = 10,
            .y = camera.screen_height - chat_data.texHRaw() - input_data.texHRaw() - 10,
            .image_data = .{ .normal = .{ .atlas_data = chat_data } },
        });

        const cursor_data = assets.getUiData("chatbox_cursor", 0);
        screen.chat_input = try element.Input.create(allocator, .{
            .x = screen.chat_decor.x,
            .y = screen.chat_decor.y + screen.chat_decor.height(),
            .text_inlay_x = 9,
            .text_inlay_y = 8,
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
        screen.chat_container = try element.ScrollableContainer.create(allocator, .{
            .x = screen.chat_decor.x + 9,
            .y = screen.chat_decor.y + 9,
            .scissor_w = 380,
            .scissor_h = 240,
            .scroll_x = screen.chat_decor.x + 386,
            .scroll_y = screen.chat_decor.y + 12,
            .scroll_w = 12,
            .scroll_h = 241,
            .scroll_decor_image_data = .{ .nine_slice = NineSlice.fromAtlasData(chat_scroll_background_data, 12, 240, 5, 0, 2, 2, 1.0) },
            .scroll_knob_image_data = .{
                .base = .{ .nine_slice = NineSlice.fromAtlasData(chat_scroll_knob_base, 8, 16, 3, 3, 2, 2, 1.0) },
                .hover = .{ .nine_slice = NineSlice.fromAtlasData(chat_scroll_knob_hover, 8, 16, 3, 3, 2, 2, 1.0) },
                .press = .{ .nine_slice = NineSlice.fromAtlasData(chat_scroll_knob_press, 8, 16, 3, 3, 2, 2, 1.0) },
            },
        });

        var fps_text_data = element.TextData{
            .text = "",
            .size = 12,
            .text_type = .bold,
            .hori_align = .middle,
            .max_width = screen.minimap_decor.width(),
            .max_chars = 256,
        };
        fps_text_data.recalculateAttributes(allocator);
        screen.fps_text = try element.Text.create(allocator, .{
            .x = screen.minimap_decor.x,
            .y = screen.minimap_decor.y + screen.minimap_decor.height() + 10,
            .text_data = fps_text_data,
        });

        screen.panel_controller = try PanelController.init(allocator, .{
            .x = camera.screen_width,
            .y = camera.screen_height,
            .width = inventory_data.texWRaw() + 10,
            .height = inventory_data.texHRaw() + 10,
        });

        screen.inited = true;
        return screen;
    }

    pub fn addChatLine(self: *GameScreen, name: []const u8, text: []const u8, name_color: u32, text_color: u32) !void {
        var chat_line = blk: {
            if (name.len > 0) {
                const line_str = try std.fmt.allocPrint(self._allocator, "&c={x}[{s}]: &c={x}{s}", .{ name_color, name, text_color, text });
                break :blk try self.chat_container.createElement(element.Text, .{
                    .x = 0,
                    .y = 0,
                    .text_data = .{
                        .text = line_str,
                        .size = 12,
                        .text_type = .bold,
                        .max_width = 380,
                        ._backing_buffer = line_str, // putting it here to dispose automatically. kind of a hack
                    },
                });
            } else {
                const line_str = try std.fmt.allocPrint(self._allocator, "&c={x}{s}", .{text_color, text});
                break :blk try self.chat_container.createElement(element.Text, .{
                    .x = 0,
                    .y = 0,
                    .text_data = .{
                        .text = line_str,
                        .size = 12,
                        .text_type = .bold,
                        .max_width = 380,
                        ._backing_buffer = line_str, // putting it here to dispose automatically. kind of a hack
                    },
                });
            }
        };
        const line_h = chat_line.height();

        if (self.chat_container.scissor_h >= self.chat_container._container.height()) {
            chat_line.y = self.chat_container.scissor_h - line_h;
            for (self.chat_lines.items) |line| {
                line.y -= line_h;
            }
        } else {
            chat_line.y = self.chat_container._container.height();
        }

        self.chat_container.update();
        try self.chat_lines.append(chat_line);
    }

    fn addAbility(container: *element.Container, ability: game_data.Ability, idx: *f32) !void {
        defer idx.* += 1;

        if (assets.ui_atlas_data.get(ability.icon.sheet)) |data| {
            const index = ability.icon.index;
            if (data.len <= index) {
                std.log.err("Could not initiate ability for GameScreen, index was out of bounds", .{});
                return;
            }

            _ = try container.createElement(element.Image, .{
                .x = idx.* * 48.0,
                .y = 0,
                .image_data = .{ .normal = .{ .atlas_data = data[index] } },
            });
        } else {
            std.log.err("Could not initiate ability for GameScreen, sheet was missing", .{});
        }
    }

    fn addStatText(container: *element.Container, text: **element.Text, idx: *f32) !void {
        defer idx.* += 1;

        const x = 33.0 + 74.0 * @mod(idx.*, 4.0);
        const y = 5.0 + 28.0 * @floor(idx.* / 4.0);
        text.* = try container.createElement(element.Text, .{ .x = x, .y = y, .text_data = .{
            .text = "",
            .size = 12,
            .text_type = .bold,
            .max_width = 45,
            .max_height = 26,
            .hori_align = .middle,
            .vert_align = .middle,
            .max_chars = 64,
        } });
    }

    pub fn deinit(self: *GameScreen) void {
        self.inited = false;

        self.minimap_decor.destroy();
        self.inventory_decor.destroy();
        self.container_decor.destroy();
        self.bars_decor.destroy();
        self.stats_button.destroy();
        self.stats_container.destroy();
        self.ability_container.destroy();
        self.chat_container.destroy();
        self.health_bar.destroy();
        self.mana_bar.destroy();
        self.chat_decor.destroy();
        self.chat_input.destroy();
        self.fps_text.destroy();

        for (self.inventory_items) |item| {
            item.destroy();
        }

        for (self.container_items) |item| {
            item.destroy();
        }

        self.chat_lines.deinit();
        self.panel_controller.deinit();

        self._allocator.destroy(self);
    }

    pub fn resize(self: *GameScreen, w: f32, h: f32) void {
        self.minimap_decor.x = w - self.minimap_decor.width() - 10;
        self.fps_text.x = self.minimap_decor.x;
        self.inventory_decor.x = w - self.inventory_decor.width() - 10;
        self.inventory_decor.y = h - self.inventory_decor.height() - 10;
        self.container_decor.x = self.inventory_decor.x - self.container_decor.width() - 10;
        self.container_decor.y = h - self.container_decor.height() - 10;
        self.bars_decor.x = (w - self.bars_decor.width()) / 2;
        self.bars_decor.y = h - self.bars_decor.height() - 10 - 25;
        self.stats_container.x = self.bars_decor.x + (self.bars_decor.width() - self.stats_decor.width()) / 2.0;
        self.stats_container.y = self.bars_decor.y + 32;
        self.ability_container.x = self.bars_decor.x + 7;
        self.ability_container.y = self.bars_decor.y + 39;
        self.stats_button.x = self.bars_decor.x + 23 + (22 - self.stats_button.width() + assets.padding * 2) / 2.0;
        self.stats_button.y = self.bars_decor.y + 10 + (24 - self.stats_button.height() + assets.padding * 2) / 2.0;
        self.health_bar.x = self.bars_decor.x + 47;
        self.health_bar.y = self.bars_decor.y + 4;
        self.mana_bar.x = self.bars_decor.x + 47;
        self.mana_bar.y = self.bars_decor.y + 18;
        const chat_decor_h = self.chat_decor.height();
        self.chat_decor.y = h - chat_decor_h - self.chat_input.imageData().normal.height() - 10;
        self.chat_container._container.x = self.chat_decor.x + 9;
        const old_y = self.chat_container.base_y;
        self.chat_container.base_y = self.chat_decor.y + 9;
        self.chat_container._container.y += (self.chat_container.base_y - old_y);
        self.chat_container._scroll_bar.x = self.chat_decor.x + 386;
        self.chat_container._scroll_bar.y = self.chat_decor.y + 12;
        self.chat_input.y = self.chat_decor.y + chat_decor_h;
        self.fps_text.y = self.minimap_decor.y + self.minimap_decor.height() + 10;

        for (0..22) |idx| {
            self.inventory_items[idx].x = self.inventory_decor.x + sc.current_screen.game.inventory_pos_data[idx].x + (sc.current_screen.game.inventory_pos_data[idx].w - self.inventory_items[idx].width() + assets.padding * 2) / 2;
            self.inventory_items[idx].y = self.inventory_decor.y + sc.current_screen.game.inventory_pos_data[idx].y + (sc.current_screen.game.inventory_pos_data[idx].h - self.inventory_items[idx].height() + assets.padding * 2) / 2;
            self.inventory_items[idx].background_x = self.inventory_decor.x + sc.current_screen.game.inventory_pos_data[idx].x;
            self.inventory_items[idx].background_y = self.inventory_decor.y + sc.current_screen.game.inventory_pos_data[idx].y;
        }

        for (0..9) |idx| {
            self.container_items[idx].x = self.container_decor.x + sc.current_screen.game.container_pos_data[idx].x + (sc.current_screen.game.container_pos_data[idx].w - self.container_items[idx].width() + assets.padding * 2) / 2;
            self.container_items[idx].y = self.container_decor.y + sc.current_screen.game.container_pos_data[idx].y + (sc.current_screen.game.container_pos_data[idx].h - self.container_items[idx].height() + assets.padding * 2) / 2;
            self.container_items[idx].background_x = self.container_decor.x + sc.current_screen.game.container_pos_data[idx].x;
            self.container_items[idx].background_y = self.container_decor.y + sc.current_screen.game.container_pos_data[idx].y;
        }

        self.panel_controller.resize(w, h);
    }

    pub fn update(self: *GameScreen, _: i64, _: f32) !void {
        self.fps_text.visible = settings.stats_enabled;

        if (map.localPlayerConst()) |local_player| {
            if (game_data.classes.get(local_player.obj_type)) |char_class| {
                if (!self.abilities_inited) {
                    var idx: f32 = 0;
                    try addAbility(self.ability_container, char_class.ability_1, &idx);
                    try addAbility(self.ability_container, char_class.ability_2, &idx);
                    try addAbility(self.ability_container, char_class.ability_3, &idx);
                    try addAbility(self.ability_container, char_class.ultimate_ability, &idx);
                    self.abilities_inited = true;
                }

                if (self.last_hp != local_player.hp or self.last_max_hp != local_player.max_hp) {
                    const hp_perc = @as(f32, @floatFromInt(local_player.hp)) / @as(f32, @floatFromInt(local_player.max_hp));
                    self.health_bar.scissor.max_x = self.health_bar.width() * hp_perc;

                    var health_text_data = &self.health_bar.text_data;
                    health_text_data.color = if (local_player.max_hp - local_player.hp_bonus >= char_class.health.max_values[local_player.tier - 1])
                        0xFFE770
                    else
                        0xFFFFFF;
                    health_text_data.text = try std.fmt.bufPrint(health_text_data._backing_buffer, "{d}/{d}", .{ local_player.hp, local_player.max_hp });
                    health_text_data.recalculateAttributes(self._allocator);

                    self.last_hp = local_player.hp;
                    self.last_max_hp = local_player.max_hp;
                }

                if (self.last_mp != local_player.mp or self.last_max_mp != local_player.max_mp) {
                    const mp_perc = @as(f32, @floatFromInt(local_player.mp)) / @as(f32, @floatFromInt(local_player.max_mp));
                    self.mana_bar.scissor.max_x = self.mana_bar.width() * mp_perc;

                    var mana_text_data = &self.mana_bar.text_data;
                    mana_text_data.color = if (local_player.max_mp - local_player.mp_bonus >= char_class.mana.max_values[local_player.tier - 1])
                        0xFFE770
                    else
                        0xFFFFFF;
                    mana_text_data.text = try std.fmt.bufPrint(mana_text_data._backing_buffer, "{d}/{d}", .{ local_player.mp, local_player.max_mp });
                    mana_text_data.recalculateAttributes(self._allocator);

                    self.last_mp = local_player.mp;
                    self.last_max_mp = local_player.max_mp;
                }
            } else {
                std.log.err("Could not update UI: CharacterClass was missing for object type 0x{x}", .{local_player.obj_type});
            }
        }
    }

    fn updateStat(allocator: std.mem.Allocator, text_data: *element.TextData, base_val: i32, bonus_val: i32, max_val: i32) void {
        text_data.color = if (base_val - bonus_val >= max_val) 0xFFE770 else 0xFFFFFF;
        text_data.text = (if (bonus_val > 0)
            std.fmt.bufPrint(
                text_data._backing_buffer,
                "{d}&s=8&c=65E698\n(+{d})",
                .{ base_val, bonus_val },
            )
        else if (bonus_val < 0)
            std.fmt.bufPrint(
                text_data._backing_buffer,
                "{d}&s=8&c=FF7070\n({d})",
                .{ base_val, bonus_val },
            )
        else
            std.fmt.bufPrint(text_data._backing_buffer, "{d}", .{base_val})) catch text_data.text;
        text_data.recalculateAttributes(allocator);
    }

    pub fn updateStats(self: *GameScreen) void {
        if (!self.inited)
            return;

        if (map.localPlayerConst()) |player| {
            if (game_data.classes.get(player.obj_type)) |char_class| {
                updateStat(
                    self._allocator,
                    &self.strength_stat_text.text_data,
                    player.strength,
                    player.strength_bonus,
                    char_class.strength.max_values[player.tier - 1],
                );
                updateStat(
                    self._allocator,
                    &self.resistance_stat_text.text_data,
                    player.resistance,
                    player.resistance_bonus,
                    char_class.resistance.max_values[player.tier - 1],
                );
                updateStat(
                    self._allocator,
                    &self.intelligence_stat_text.text_data,
                    player.intelligence,
                    player.intelligence_bonus,
                    char_class.intelligence.max_values[player.tier - 1],
                );
                updateStat(
                    self._allocator,
                    &self.haste_stat_text.text_data,
                    player.haste,
                    player.haste_bonus,
                    char_class.haste.max_values[player.tier - 1],
                );
                updateStat(
                    self._allocator,
                    &self.wit_stat_text.text_data,
                    player.wit,
                    player.wit_bonus,
                    char_class.wit.max_values[player.tier - 1],
                );
                updateStat(
                    self._allocator,
                    &self.speed_stat_text.text_data,
                    player.speed,
                    player.speed_bonus,
                    char_class.speed.max_values[player.tier - 1],
                );
                updateStat(
                    self._allocator,
                    &self.penetration_stat_text.text_data,
                    player.penetration,
                    player.penetration_bonus,
                    char_class.penetration.max_values[player.tier - 1],
                );
                updateStat(
                    self._allocator,
                    &self.tenacity_stat_text.text_data,
                    player.tenacity,
                    player.tenacity_bonus,
                    char_class.tenacity.max_values[player.tier - 1],
                );
                updateStat(
                    self._allocator,
                    &self.defense_stat_text.text_data,
                    player.defense,
                    player.defense_bonus,
                    char_class.defense.max_values[player.tier - 1],
                );
                updateStat(
                    self._allocator,
                    &self.stamina_stat_text.text_data,
                    player.stamina,
                    player.stamina_bonus,
                    char_class.stamina.max_values[player.tier - 1],
                );
                updateStat(
                    self._allocator,
                    &self.piercing_stat_text.text_data,
                    player.piercing,
                    player.piercing_bonus,
                    char_class.piercing.max_values[player.tier - 1],
                );
            } else {
                std.log.err("Could not update UI stats: CharacterClass was missing for object type 0x{x}", .{player.obj_type});
            }
        }
    }

    pub fn updateFpsText(self: *GameScreen, fps: f64, mem: f32) !void {
        const fmt =
            \\FPS: {d:.1}
            \\Memory: {d:.1} MB
        ;
        self.fps_text.text_data.text = try std.fmt.bufPrint(self.fps_text.text_data._backing_buffer, fmt, .{ fps, mem });
        self.fps_text.text_data.recalculateAttributes(self._allocator);
    }

    fn parseItemRects(self: *GameScreen) void {
        for (0..22) |i| {
            if (i < 4) {
                const hori_idx: f32 = @floatFromInt(@mod(i, 4));
                self.inventory_pos_data[i] = utils.Rect{
                    .x = 51 + hori_idx * 48,
                    .y = 7,
                    .w = 40,
                    .h = 40,
                    .w_pad = 4,
                    .h_pad = 4,
                };
            } else {
                const hori_idx: f32 = @floatFromInt(@mod(i - 4, 6));
                const vert_idx: f32 = @floatFromInt(@divFloor(i - 4, 6));
                self.inventory_pos_data[i] = utils.Rect{
                    .x = 3 + hori_idx * 48,
                    .y = 59 + vert_idx * 48,
                    .w = 40,
                    .h = 40,
                    .w_pad = 4,
                    .h_pad = 4,
                };
            }
        }

        for (0..9) |i| {
            const hori_idx: f32 = @floatFromInt(@mod(i, 3));
            const vert_idx: f32 = @floatFromInt(@divFloor(i, 3));
            self.container_pos_data[i] = utils.Rect{
                .x = 7 + hori_idx * 48,
                .y = 33 + vert_idx * 48,
                .w = 40,
                .h = 40,
                .w_pad = 4,
                .h_pad = 4,
            };
        }
    }

    pub fn swapSlots(self: *GameScreen, start_slot: Slot, end_slot: Slot) void {
        const int_id = map.interactive_id.load(.Acquire);

        if (end_slot.idx == 255) {
            if (start_slot.is_container) {
                self.setContainerItem(std.math.maxInt(u16), start_slot.idx);
                network.queuePacket(.{ .inv_drop = .{
                    .obj_id = int_id,
                    .slot_id = start_slot.idx,
                } });
            } else {
                self.setInvItem(std.math.maxInt(u16), start_slot.idx);
                network.queuePacket(.{ .inv_drop = .{
                    .obj_id = map.local_player_id,
                    .slot_id = start_slot.idx,
                } });
            }
        } else {
            while (!map.object_lock.tryLockShared()) {}
            defer map.object_lock.unlockShared();

            if (map.localPlayerConst()) |local_player| {
                const start_item = if (start_slot.is_container)
                    self.container_items[start_slot.idx]._item
                else
                    self.inventory_items[start_slot.idx]._item;

                if (end_slot.idx >= 4 + 9 and local_player.tier < 2) {
                    if (start_slot.is_container) {
                        self.setContainerItem(start_item, start_slot.idx);
                    } else {
                        self.setInvItem(start_item, start_slot.idx);
                    }

                    assets.playSfx("error");
                    return;
                }

                const end_item = if (end_slot.is_container)
                    self.container_items[end_slot.idx]._item
                else
                    self.inventory_items[end_slot.idx]._item;

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

                network.queuePacket(.{ .inv_swap = .{
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
        if (item._item < 0)
            return;

        const start_slot = Slot.findSlotId(sc.current_screen.game.*, item.x + 4, item.y + 4);
        if (game_data.item_type_to_props.get(@intCast(item._item))) |props| {
            if (props.consumable and !start_slot.is_container) {
                while (!map.object_lock.tryLockShared()) {}
                defer map.object_lock.unlockShared();

                if (map.localPlayerConst()) |local_player| {
                    network.queuePacket(.{ .use_item = .{
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

        if (start_slot.is_container) {
            const end_slot = Slot.nextAvailableSlot(sc.current_screen.game.*);
            if (start_slot.idx == end_slot.idx and start_slot.is_container == end_slot.is_container) {
                item.x = item._drag_start_x;
                item.y = item._drag_start_y;
                return;
            }

            sc.current_screen.game.swapSlots(start_slot, end_slot);
        } else {
            if (game_data.item_type_to_props.get(@intCast(item._item))) |props| {
                while (!map.object_lock.tryLockShared()) {}
                defer map.object_lock.unlockShared();

                if (map.localPlayerConst()) |local_player| {
                    const end_slot = Slot.nextEquippableSlot(local_player.slot_types, props.slot_type);
                    if (end_slot.idx == 255 or // we don't want to drop
                        start_slot.idx == end_slot.idx and start_slot.is_container == end_slot.is_container)
                    {
                        item.x = item._drag_start_x;
                        item.y = item._drag_start_y;
                        return;
                    }

                    sc.current_screen.game.swapSlots(start_slot, end_slot);
                }
            }
        }
    }

    pub fn statsCallback() void {
        sc.current_screen.game.stats_container.visible = !sc.current_screen.game.stats_container.visible;
        if (sc.current_screen.game.stats_container.visible) {
            const abil_button_data = assets.getUiData("minimap_icons", 1);
            sc.current_screen.game.stats_button.image_data.base.normal.atlas_data = abil_button_data;

            sc.current_screen.game.ability_container.visible = false;
            sc.current_screen.game.updateStats();
        } else {
            const stats_button_data = assets.getUiData("minimap_icons", 0);
            sc.current_screen.game.stats_button.image_data.base.normal.atlas_data = stats_button_data;

            sc.current_screen.game.ability_container.visible = true;
        }
    }

    fn chatCallback(input_text: []const u8) void {
        if (input_text.len > 0) {
            network.queuePacket(.{ .player_text = .{ .text = input_text } });

            const current_screen = sc.current_screen.game;
            const text_copy = current_screen._allocator.dupe(u8, input_text) catch unreachable;
            input.input_history.append(text_copy) catch unreachable;
            input.input_history_idx = @intCast(input.input_history.items.len);
        }
    }

    fn interactCallback() void {}

    fn itemDragStartCallback(item: *element.Item) void {
        item._background_image_data = null;
    }

    fn itemDragEndCallback(item: *element.Item) void {
        var current_screen = sc.current_screen.game;
        const start_slot = Slot.findSlotId(current_screen.*, item._drag_start_x + 4, item._drag_start_y + 4);
        const end_slot = Slot.findSlotId(current_screen.*, item.x - item._drag_offset_x, item.y - item._drag_offset_y);
        if (start_slot.idx == end_slot.idx and start_slot.is_container == end_slot.is_container) {
            item.x = item._drag_start_x;
            item.y = item._drag_start_y;

            // to update the background image
            if (start_slot.is_container) {
                current_screen.setContainerItem(item._item, start_slot.idx);
            } else {
                current_screen.setInvItem(item._item, start_slot.idx);
            }
            return;
        }

        current_screen.swapSlots(start_slot, end_slot);
    }

    fn itemShiftClickCallback(item: *element.Item) void {
        if (item._item < 0)
            return;

        const current_screen = sc.current_screen.game.*;
        const slot = Slot.findSlotId(current_screen, item.x + 4, item.y + 4);

        if (game_data.item_type_to_props.get(@intCast(item._item))) |props| {
            if (props.consumable) {
                while (!map.object_lock.tryLockShared()) {}
                defer map.object_lock.unlockShared();

                if (map.localPlayerConst()) |local_player| {
                    network.queuePacket(.{ .use_item = .{
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
            self.container_items[idx]._item = std.math.maxInt(u16);
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

                self.container_items[idx]._item = item;
                self.container_items[idx].image_data.normal.atlas_data = atlas_data;
                self.container_items[idx].x = base_x + (pos_w - self.container_items[idx].width() + assets.padding * 2) / 2;
                self.container_items[idx].y = base_y + (pos_h - self.container_items[idx].height() + assets.padding * 2) / 2;

                if (std.mem.eql(u8, props.tier, "Mythic")) {
                    self.container_items[idx]._background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("mythic_slot", 0) } };
                } else if (std.mem.eql(u8, props.tier, "Legendary")) {
                    self.container_items[idx]._background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("legendary_slot", 0) } };
                } else if (std.mem.eql(u8, props.tier, "Epic")) {
                    self.container_items[idx]._background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("epic_slot", 0) } };
                } else if (std.mem.eql(u8, props.tier, "Rare")) {
                    self.container_items[idx]._background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("rare_slot", 0) } };
                } else {
                    self.container_items[idx]._background_image_data = null;
                }

                return;
            } else {
                std.log.err("Could not find ui sheet {s} for item with type 0x{x}, index {d}", .{ props.texture_data.sheet, item, idx });
            }
        } else {
            std.log.err("Attempted to populate inventory index {d} with item 0x{x}, but props was not found", .{ idx, item });
        }

        self.container_items[idx]._item = std.math.maxInt(u16);
        self.container_items[idx].image_data.normal.atlas_data = assets.error_data;
        self.container_items[idx].x = self.container_decor.x + self.container_pos_data[idx].x + (self.container_pos_data[idx].w - self.container_items[idx].width() + assets.padding * 2) / 2;
        self.container_items[idx].y = self.container_decor.y + self.container_pos_data[idx].y + (self.container_pos_data[idx].h - self.container_items[idx].height() + assets.padding * 2) / 2;
        self.container_items[idx]._background_image_data = null;
    }

    pub fn setInvItem(self: *GameScreen, item: u16, idx: u8) void {
        if (item == std.math.maxInt(u16)) {
            self.inventory_items[idx]._item = std.math.maxInt(u16);
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

                self.inventory_items[idx]._item = item;
                self.inventory_items[idx].image_data.normal.atlas_data = atlas_data;
                self.inventory_items[idx].x = base_x + (pos_w - self.inventory_items[idx].width() + assets.padding * 2) / 2;
                self.inventory_items[idx].y = base_y + (pos_h - self.inventory_items[idx].height() + assets.padding * 2) / 2;

                if (std.mem.eql(u8, props.tier, "Mythic")) {
                    self.inventory_items[idx]._background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("mythic_slot", 0) } };
                } else if (std.mem.eql(u8, props.tier, "Legendary")) {
                    self.inventory_items[idx]._background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("legendary_slot", 0) } };
                } else if (std.mem.eql(u8, props.tier, "Epic")) {
                    self.inventory_items[idx]._background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("epic_slot", 0) } };
                } else if (std.mem.eql(u8, props.tier, "Rare")) {
                    self.inventory_items[idx]._background_image_data = .{ .normal = .{ .atlas_data = assets.getUiData("rare_slot", 0) } };
                } else {
                    self.inventory_items[idx]._background_image_data = null;
                }

                return;
            } else {
                std.log.err("Could not find ui sheet {s} for item with type 0x{x}, index {d}", .{ props.texture_data.sheet, item, idx });
            }
        } else {
            std.log.err("Attempted to populate inventory index {d} with item 0x{x}, but props was not found", .{ idx, item });
        }

        const atlas_data = assets.error_data;
        self.inventory_items[idx]._item = std.math.maxInt(u16);
        self.inventory_items[idx].image_data.normal.atlas_data = atlas_data;
        self.inventory_items[idx].x = self.inventory_decor.x + self.inventory_pos_data[idx].x + (self.inventory_pos_data[idx].w - self.inventory_items[idx].width() + assets.padding * 2) / 2;
        self.inventory_items[idx].y = self.inventory_decor.y + self.inventory_pos_data[idx].y + (self.inventory_pos_data[idx].h - self.inventory_items[idx].height() + assets.padding * 2) / 2;
        self.inventory_items[idx]._background_image_data = null;
    }

    pub inline fn setContainerVisible(self: *GameScreen, visible: bool) void {
        if (!self.inited)
            return;

        self.container_visible = visible;
        self.container_decor.visible = visible;
    }

    pub fn showPanel(self: *GameScreen, class_type: game_data.ClassType) void {
        self.interact_class = class_type;
        const text_size = 16.0;
        switch (self.interact_class) {
            .guild_register => self.panel_controller.showBasicPanel("Guild Register", text_size),
            .guild_merchant => self.panel_controller.showBasicPanel("Guild Merchant", text_size),
            .guild_chronicle => self.panel_controller.showBasicPanel("Guild Chronicle", text_size),
            .guild_board => self.panel_controller.showBasicPanel("Guild Board", text_size),
            else => {},
        }
    }
};
