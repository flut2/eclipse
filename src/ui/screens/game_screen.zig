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
                return Slot{ .idx = inv_slot };
            }

            const container_slot = findContainerSlotId(screen, x, y);
            if (container_slot != 255) {
                return Slot{ .idx = container_slot, .is_container = true };
            }

            return Slot{ .idx = 255 };
        }

        pub fn nextEquippableSlot(slot_types: [22]i8, base_slot_type: i8) Slot {
            for (0..22) |idx| {
                if (slot_types[idx] > 0 and game_data.ItemType.slotsMatch(slot_types[idx], base_slot_type))
                    return Slot{ .idx = @intCast(idx) };
            }
            return Slot{ .idx = 255 };
        }

        pub fn nextAvailableSlot(screen: GameScreen) Slot {
            for (0..22) |idx| {
                if (screen.inventory_items[idx]._item == std.math.maxInt(u16))
                    return Slot{ .idx = @intCast(idx) };
            }
            return Slot{ .idx = 255 };
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
    inited: bool = false,
    main_buffer_front: bool = false,
    footer_buffer_front: bool = false,

    fps_text: *element.Text = undefined,
    chat_input: *element.Input = undefined,
    chat_decor: *element.Image = undefined,
    bars_decor: *element.Image = undefined,
    stats_button: *element.Button = undefined,
    stats_container: *element.Container = undefined,
    stats_decor: *element.Image = undefined,
    stats_attack: *element.Text = undefined,
    stats_dexterity: *element.Text = undefined,
    stats_speed: *element.Text = undefined,
    stats_defense: *element.Text = undefined,
    stats_vitality: *element.Text = undefined,
    stats_wisdom: *element.Text = undefined,
    level_text: *element.Text = undefined,
    xp_bar: *element.Bar = undefined,
    fame_bar: *element.Bar = undefined,
    health_bar: *element.Bar = undefined,
    mana_bar: *element.Bar = undefined,
    inventory_decor: *element.Image = undefined,
    inventory_items: [22]*element.Item = undefined,
    health_potion: *element.Image = undefined,
    health_potion_text: *element.Text = undefined,
    magic_potion: *element.Image = undefined,
    magic_potion_text: *element.Text = undefined,
    container_decor: *element.Image = undefined,
    container_name: *element.Text = undefined,
    container_items: [9]*element.Item = undefined,
    minimap_decor: *element.Image = undefined,
    tooltip_container: *element.Container = undefined,
    tooltip_item: u16 = std.math.maxInt(u16),
    tooltip_decor: *element.Image = undefined,
    tooltip_image: *element.Image = undefined,
    tooltip_item_name: *element.Text = undefined,
    tooltip_rarity: *element.Text = undefined,
    tooltip_description: *element.Text = undefined,
    tooltip_spacer_one: *element.Image = undefined,
    tooltip_main: *element.Text = undefined,
    tooltip_spacer_two: *element.Image = undefined,
    tooltip_footer: *element.Text = undefined,

    inventory_pos_data: [22]utils.Rect = undefined,
    container_pos_data: [9]utils.Rect = undefined,

    _allocator: std.mem.Allocator = undefined,

    interact_class: game_data.ClassType = game_data.ClassType.game_object,
    panel_controller: *PanelController = undefined,

    pub fn init(allocator: std.mem.Allocator) !*GameScreen {
        var screen = try allocator.create(GameScreen);
        screen.* = .{ ._allocator = allocator };

        const inventory_data = assets.getUiData("player_inventory", 0);
        screen.parseItemRects();

        const minimap_data = assets.getUiData("minimap", 0);
        screen.minimap_decor = try element.Image.create(allocator, .{
            .x = camera.screen_width - minimap_data.texWRaw() - 10,
            .y = 10,
            .image_data = .{ .normal = .{ .atlas_data = minimap_data } },
            .is_minimap_decor = true,
            .minimap_offset_x = 7.0,
            .minimap_offset_y = 10.0,
            .minimap_width = 172.0,
            .minimap_height = 172.0,
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
                .image_data = .{ .normal = .{ .scale_x = 4.0, .scale_y = 4.0, .atlas_data = assets.error_data } },
                .visible = false,
                .draggable = true,
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
                .image_data = .{ .normal = .{
                    .scale_x = 4.0,
                    .scale_y = 4.0,
                    .atlas_data = assets.error_data,
                } },
                .visible = false,
                .draggable = true,
                .drag_end_callback = itemDragEndCallback,
                .double_click_callback = itemDoubleClickCallback,
                .shift_click_callback = itemShiftClickCallback,
            });
        }

        const bars_data = assets.getUiData("player_status_bars_decor", 0);
        screen.bars_decor = try element.Image.create(allocator, .{
            .x = (camera.screen_width - bars_data.texWRaw()) / 2,
            .y = camera.screen_height - bars_data.texHRaw() - 10,
            .image_data = .{ .normal = .{ .atlas_data = bars_data } },
        });

        const stats_button_data = assets.getUiData("player_status_bar_stat_icon", 0);
        screen.stats_button = try element.Button.create(allocator, .{
            .x = screen.bars_decor.x + 7,
            .y = screen.bars_decor.y + 8,
            .image_data = .{ .base = .{ .normal = .{ .atlas_data = stats_button_data } } },
            .press_callback = statsCallback,
        });

        const stats_decor_data = assets.getUiData("stats_view", 0);
        const decor_scale = 2;
        screen.stats_container = try element.Container.create(allocator, .{
            .x = screen.bars_decor.x - (stats_decor_data.texWRaw() * decor_scale - bars_data.texWRaw()) / 2,
            .y = screen.bars_decor.y - stats_decor_data.texHRaw() * decor_scale - 5,
            .visible = false,
        });

        screen.stats_decor = try screen.stats_container.createElement(element.Image, .{ .x = 0, .y = 0, .image_data = .{
            .normal = .{ .atlas_data = stats_decor_data, .scale_x = 2, .scale_y = 2 },
        } });

        if (assets.ui_atlas_data.get("stats_view_icons")) |data| {
            const w_spacing = 126.0;
            const h_spacing = 60.0;
            var base_x: f32 = 28.0;
            var base_y: f32 = 16.0;

            _ = try screen.stats_container.createElement(element.Image, .{ .x = base_x + 2, .y = base_y - 2, .image_data = .{
                .normal = .{ .atlas_data = data[2], .scale_x = 4, .scale_y = 4 },
            } });

            _ = try screen.stats_container.createElement(element.Image, .{ .x = base_x + w_spacing, .y = base_y, .image_data = .{
                .normal = .{ .atlas_data = data[4], .scale_x = 4, .scale_y = 4 },
            } });

            _ = try screen.stats_container.createElement(element.Image, .{ .x = base_x - 2 + w_spacing * 2, .y = base_y, .image_data = .{
                .normal = .{ .atlas_data = data[5], .scale_x = 4, .scale_y = 4 },
            } });

            _ = try screen.stats_container.createElement(element.Image, .{ .x = base_x - 2, .y = base_y + 2 + h_spacing, .image_data = .{
                .normal = .{ .atlas_data = data[3], .scale_x = 4, .scale_y = 4 },
            } });

            _ = try screen.stats_container.createElement(element.Image, .{ .x = base_x - 2 + w_spacing, .y = base_y + h_spacing, .image_data = .{
                .normal = .{ .atlas_data = data[6], .scale_x = 4, .scale_y = 4 },
            } });

            _ = try screen.stats_container.createElement(element.Image, .{ .x = base_x + w_spacing * 2, .y = base_y - 2 + h_spacing, .image_data = .{
                .normal = .{ .atlas_data = data[7], .scale_x = 4, .scale_y = 4 },
            } });

            base_x += 48;
            base_y += 2;

            screen.stats_attack = try screen.stats_container.createElement(element.Text, .{ .x = base_x, .y = base_y, .text_data = .{
                .text = "",
                .size = 18,
                .text_type = .bold,
                .max_width = 62,
                .max_height = 40,
                .hori_align = .middle,
                .vert_align = .middle,
                .max_chars = 64,
            } });

            screen.stats_dexterity = try screen.stats_container.createElement(element.Text, .{ .x = base_x + w_spacing, .y = base_y, .text_data = .{
                .text = "",
                .size = 18,
                .text_type = .bold,
                .max_width = 62,
                .max_height = 40,
                .hori_align = .middle,
                .vert_align = .middle,
                .max_chars = 64,
            } });

            screen.stats_speed = try screen.stats_container.createElement(element.Text, .{ .x = base_x + w_spacing * 2, .y = base_y, .text_data = .{
                .text = "",
                .size = 18,
                .text_type = .bold,
                .max_width = 62,
                .max_height = 40,
                .hori_align = .middle,
                .vert_align = .middle,
                .max_chars = 64,
            } });

            screen.stats_defense = try screen.stats_container.createElement(element.Text, .{ .x = base_x, .y = base_y + h_spacing, .text_data = .{
                .text = "",
                .size = 18,
                .text_type = .bold,
                .max_width = 62,
                .max_height = 40,
                .hori_align = .middle,
                .vert_align = .middle,
                .max_chars = 64,
            } });

            screen.stats_vitality = try screen.stats_container.createElement(element.Text, .{ .x = base_x + w_spacing, .y = base_y + h_spacing, .text_data = .{
                .text = "",
                .size = 18,
                .text_type = .bold,
                .max_width = 62,
                .max_height = 40,
                .hori_align = .middle,
                .vert_align = .middle,
                .max_chars = 64,
            } });

            screen.stats_wisdom = try screen.stats_container.createElement(element.Text, .{ .x = base_x + w_spacing * 2, .y = base_y + h_spacing, .text_data = .{
                .text = "",
                .size = 18,
                .text_type = .bold,
                .max_width = 62,
                .max_height = 40,
                .hori_align = .middle,
                .vert_align = .middle,
                .max_chars = 64,
            } });
        } else @panic("Could not find stats_view_icons in the UI atlas");

        screen.level_text = try element.Text.create(allocator, .{
            .x = screen.bars_decor.x + 178,
            .y = screen.bars_decor.y + 9,
            .text_data = .{
                .text = "",
                .size = 12,
                .text_type = .bold,
                .max_chars = 8,
                .max_width = 24,
                .max_height = 24,
                .vert_align = .middle,
                .hori_align = .middle,
            },
        });

        const xp_bar_data = assets.getUiData("player_status_bar_xp", 0);
        screen.xp_bar = try element.Bar.create(allocator, .{
            .x = screen.bars_decor.x + 42,
            .y = screen.bars_decor.y + 12,
            .image_data = .{ .normal = .{ .atlas_data = xp_bar_data } },
            .text_data = .{
                .text = "",
                .size = 12,
                .text_type = .bold_italic,
                .max_chars = 64,
            },
        });

        const fame_bar_data = assets.getUiData("player_status_bar_fame", 0);
        screen.fame_bar = try element.Bar.create(allocator, .{
            .x = screen.bars_decor.x + 42,
            .y = screen.bars_decor.y + 12,
            .image_data = .{ .normal = .{ .atlas_data = fame_bar_data } },
            .text_data = .{
                .text = "",
                .size = 12,
                .text_type = .bold_italic,
                .max_chars = 64,
            },
        });

        const health_bar_data = assets.getUiData("player_status_bar_health", 0);
        screen.health_bar = try element.Bar.create(allocator, .{
            .x = screen.bars_decor.x + 8,
            .y = screen.bars_decor.y + 47,
            .image_data = .{ .normal = .{ .atlas_data = health_bar_data } },
            .text_data = .{
                .text = "",
                .size = 12,
                .text_type = .bold_italic,
                .max_chars = 64,
            },
        });

        const mana_bar_data = assets.getUiData("player_status_bar_mana", 0);
        screen.mana_bar = try element.Bar.create(allocator, .{
            .x = screen.bars_decor.x + 8,
            .y = screen.bars_decor.y + 73,
            .image_data = .{ .normal = .{ .atlas_data = mana_bar_data } },
            .text_data = .{
                .text = "",
                .size = 12,
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

        screen.tooltip_container = try element.Container.create(allocator, .{
            .visible = false,
            .x = 0,
            .y = 0,
        });

        const tooltip_background_data = assets.getUiData("tooltip_background", 0);
        screen.tooltip_decor = try screen.tooltip_container.createElement(element.Image, .{
            .x = 0,
            .y = 0,
            .image_data = .{
                .nine_slice = element.NineSliceImageData.fromAtlasData(tooltip_background_data, camera.screen_width / 3.5, camera.screen_height / 2, 16, 16, 1, 1, 1.0),
            },
        });

        screen.tooltip_image = try screen.tooltip_container.createElement(element.Image, .{
            .x = 10,
            .y = 10,
            .image_data = .{
                .normal = .{
                    .atlas_data = undefined,
                    .scale_x = 4,
                    .scale_y = 4,
                    .glow = true,
                },
            },
            .ui_quad = false,
        });

        screen.tooltip_item_name = try screen.tooltip_container.createElement(element.Text, .{
            .x = 8 * 4 + 30,
            .y = 10,
            .text_data = .{
                .text = "",
                .size = 16,
                .text_type = .bold,
            },
        });

        screen.tooltip_rarity = try screen.tooltip_container.createElement(element.Text, .{
            .x = 8 * 4 + 30,
            .y = screen.tooltip_item_name.text_data._height + 10,
            .text_data = .{
                .text = "",
                .size = 14,
                .color = 0xB3B3B3,
            },
        });

        screen.tooltip_description = try screen.tooltip_container.createElement(element.Text, .{
            .x = 10,
            .y = 8 * 4 + 30,
            .text_data = .{
                .text = "",
                .size = 12,
                .max_width = screen.tooltip_decor.width() - 20,
                .color = 0xB3B3B3,
            },
        });

        const tooltip_line_spacer_data = assets.getUiData("tooltip_line_spacer", 0);
        screen.tooltip_spacer_one = try screen.tooltip_container.createElement(element.Image, .{
            .x = 20,
            .y = screen.tooltip_description.y + screen.tooltip_description.text_data._height + 10,
            .image_data = .{
                .nine_slice = element.NineSliceImageData.fromAtlasData(tooltip_line_spacer_data, screen.tooltip_decor.width() - 40, 4, 13, 0, 1, 4, 1.0),
            },
        });

        screen.tooltip_main = try screen.tooltip_container.createElement(element.Text, .{
            .x = 10,
            .y = screen.tooltip_spacer_one.y + screen.tooltip_spacer_one.height() + 10,
            .text_data = .{
                .text = "",
                .size = 14,
                .max_width = screen.tooltip_decor.width() - 20,
                .color = 0x9B9B9B,
                // only half of the buffer is used at a time to avoid aliasing, so the max len is half of this
                .max_chars = 2048 * 2,
            },
        });

        screen.tooltip_spacer_two = try screen.tooltip_container.createElement(element.Image, .{
            .x = 20,
            .y = screen.tooltip_main.y + screen.tooltip_main.text_data._height + 10,
            .image_data = .{
                .nine_slice = element.NineSliceImageData.fromAtlasData(tooltip_line_spacer_data, screen.tooltip_decor.width() - 40, 4, 13, 0, 1, 4, 1.0),
            },
        });

        screen.tooltip_footer = try screen.tooltip_container.createElement(element.Text, .{
            .x = 10,
            .y = screen.tooltip_spacer_two.y + screen.tooltip_spacer_two.height() + 10,
            .text_data = .{
                .text = "",
                .size = 14,
                .max_width = screen.tooltip_decor.width() - 20,
                .color = 0x9B9B9B,
                // only half of the buffer is used at a time to avoid aliasing, so the max len is half of this
                .max_chars = 256 * 2,
            },
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

    fn addStatsLine(
        container: *element.Container,
    ) void {
        _ = container;
    }

    pub fn deinit(self: *GameScreen) void {
        self.inited = false;

        self.minimap_decor.destroy();
        self.inventory_decor.destroy();
        self.container_decor.destroy();
        self.bars_decor.destroy();
        self.stats_button.destroy();
        self.stats_container.destroy();
        self.level_text.destroy();
        self.xp_bar.destroy();
        self.fame_bar.destroy();
        self.health_bar.destroy();
        self.mana_bar.destroy();
        self.chat_decor.destroy();
        self.chat_input.destroy();
        self.fps_text.destroy();
        self.tooltip_container.destroy();

        for (self.inventory_items) |item| {
            item.destroy();
        }

        for (self.container_items) |item| {
            item.destroy();
        }

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
        self.bars_decor.y = h - self.bars_decor.height() - 10;
        self.stats_button.x = self.bars_decor.x + 7;
        self.stats_button.y = self.bars_decor.y + 8;
        self.level_text.x = self.bars_decor.x + 178;
        self.level_text.y = self.bars_decor.y + 9;
        self.xp_bar.x = self.bars_decor.x + 42;
        self.xp_bar.y = self.bars_decor.y + 12;
        self.fame_bar.x = self.bars_decor.x + 42;
        self.fame_bar.y = self.bars_decor.y + 12;
        self.health_bar.x = self.bars_decor.x + 8;
        self.health_bar.y = self.bars_decor.y + 47;
        self.mana_bar.x = self.bars_decor.x + 8;
        self.mana_bar.y = self.bars_decor.y + 73;
        const chat_decor_h = self.chat_decor.height();
        self.chat_decor.y = h - chat_decor_h - self.chat_input.imageData().normal.height() - 10;
        self.chat_input.y = self.chat_decor.y + chat_decor_h;
        self.fps_text.y = self.minimap_decor.y + self.minimap_decor.height() + 10;
        self.stats_container.x = (camera.screen_width - self.stats_decor.width()) / 2;
        self.stats_container.y = camera.screen_height - self.bars_decor.height() - self.stats_decor.height() - 10;

        for (0..20) |idx| {
            self.inventory_items[idx].x = self.inventory_decor.x + sc.current_screen.game.inventory_pos_data[idx].x + (sc.current_screen.game.inventory_pos_data[idx].w - self.inventory_items[idx].width() + assets.padding * 2) / 2;
            self.inventory_items[idx].y = self.inventory_decor.y + sc.current_screen.game.inventory_pos_data[idx].y + (sc.current_screen.game.inventory_pos_data[idx].h - self.inventory_items[idx].height() + assets.padding * 2) / 2;
        }

        for (0..8) |idx| {
            self.container_items[idx].x = self.container_decor.x + sc.current_screen.game.container_pos_data[idx].x + (sc.current_screen.game.container_pos_data[idx].w - self.container_items[idx].width() + assets.padding * 2) / 2;
            self.container_items[idx].y = self.container_decor.y + sc.current_screen.game.container_pos_data[idx].y + (sc.current_screen.game.container_pos_data[idx].h - self.container_items[idx].height() + assets.padding * 2) / 2;
        }

        self.panel_controller.resize(w, h);
    }

    pub fn update(self: *GameScreen, _: i64, _: f32) !void {
        self.fps_text.visible = settings.stats_enabled;

        if (map.localPlayerConst()) |local_player| {
            // if (self.last_level != local_player.level) {
            //     var level_text_data = &self.level_text.text_data;
            //     level_text_data.text = try std.fmt.bufPrint(level_text_data._backing_buffer, "{d}", .{local_player.level});
            //     level_text_data.recalculateAttributes(self._allocator);

            //     self.last_level = local_player.level;
            // }

            // const max_level = local_player.level >= 20;
            // if (max_level) {
            //     if (self.last_fame != local_player.fame or self.last_fame_goal != local_player.fame_goal) {
            //         self.fame_bar.visible = true;
            //         self.xp_bar.visible = false;

            //         const fame_perc = @as(f32, @floatFromInt(local_player.fame)) / @as(f32, @floatFromInt(local_player.fame_goal));
            //         self.fame_bar.image_data.normal.scissor.max_x = self.fame_bar.width() * fame_perc;

            //         var fame_text_data = &self.fame_bar.text_data;
            //         fame_text_data.text = try std.fmt.bufPrint(fame_text_data._backing_buffer, "{d}/{d} Fame", .{ local_player.fame, local_player.fame_goal });
            //         fame_text_data.recalculateAttributes(self._allocator);

            //         self.last_fame = local_player.fame;
            //         self.last_fame_goal = local_player.fame_goal;
            //     }
            // } else {
            //     if (self.last_xp != local_player.exp or self.last_xp_goal != local_player.exp_goal) {
            //         self.xp_bar.visible = true;
            //         self.fame_bar.visible = false;

            //         const exp_perc = @as(f32, @floatFromInt(local_player.exp)) / @as(f32, @floatFromInt(local_player.exp_goal));
            //         self.xp_bar.image_data.normal.scissor.max_x = self.xp_bar.width() * exp_perc;

            //         var xp_text_data = &self.xp_bar.text_data;
            //         xp_text_data.text = try std.fmt.bufPrint(xp_text_data._backing_buffer, "{d}/{d} XP", .{ local_player.exp, local_player.exp_goal });
            //         xp_text_data.recalculateAttributes(self._allocator);

            //         self.last_xp = local_player.exp;
            //         self.last_xp_goal = local_player.exp_goal;
            //     }
            // }

            if (self.last_hp != local_player.hp or self.last_max_hp != local_player.max_hp) {
                const hp_perc = @as(f32, @floatFromInt(local_player.hp)) / @as(f32, @floatFromInt(local_player.max_hp));
                self.health_bar.image_data.normal.scissor.max_x = self.health_bar.width() * hp_perc;

                var health_text_data = &self.health_bar.text_data;
                health_text_data.text = try std.fmt.bufPrint(health_text_data._backing_buffer, "{d}/{d} HP", .{ local_player.hp, local_player.max_hp });
                health_text_data.recalculateAttributes(self._allocator);

                self.last_hp = local_player.hp;
                self.last_max_hp = local_player.max_hp;
            }

            if (self.last_mp != local_player.mp or self.last_max_mp != local_player.max_mp) {
                const mp_perc = @as(f32, @floatFromInt(local_player.mp)) / @as(f32, @floatFromInt(local_player.max_mp));
                self.mana_bar.image_data.normal.scissor.max_x = self.mana_bar.width() * mp_perc;

                var mana_text_data = &self.mana_bar.text_data;
                mana_text_data.text = try std.fmt.bufPrint(mana_text_data._backing_buffer, "{d}/{d} MP", .{ local_player.mp, local_player.max_mp });
                mana_text_data.recalculateAttributes(self._allocator);

                self.last_mp = local_player.mp;
                self.last_max_mp = local_player.max_mp;
            }
        }
    }

    fn updateStat(allocator: std.mem.Allocator, text_data: *element.TextData, base_val: i32, bonus_val: i32) void {
        text_data.text = (if (bonus_val > 0)
            std.fmt.bufPrint(
                text_data._backing_buffer,
                "{d}&s=10&c=00FF00\n(+{d})",
                .{ base_val, bonus_val },
            )
        else if (bonus_val < 0)
            std.fmt.bufPrint(
                text_data._backing_buffer,
                "{d}&s=10&c=FF0000\n({d})",
                .{ base_val, bonus_val },
            )
        else
            std.fmt.bufPrint(text_data._backing_buffer, "{d}", .{base_val})) catch text_data.text;
        text_data.recalculateAttributes(allocator);
    }

    pub fn updateStats(self: *GameScreen) void {
        if (!self.inited)
            return;

        // if (map.localPlayerConst()) |player| {
        //     updateStat(self._allocator, &self.stats_attack.text_data, player.attack, player.attack_bonus);
        //     updateStat(self._allocator, &self.stats_dexterity.text_data, player.dexterity, player.dexterity_bonus);
        //     updateStat(self._allocator, &self.stats_speed.text_data, player.speed, player.speed_bonus);
        //     updateStat(self._allocator, &self.stats_defense.text_data, player.defense, player.defense_bonus);
        //     updateStat(self._allocator, &self.stats_vitality.text_data, player.vitality, player.vitality_bonus);
        //     updateStat(self._allocator, &self.stats_wisdom.text_data, player.wisdom, player.wisdom_bonus);
        // }
    }

    pub fn updateFpsText(self: *GameScreen, fps: f64, mem: f32) !void {
        const fmt =
            \\FPS: {d:.3}
            \\Memory: {d:.1} MB
        ;
        self.fps_text.text_data.text = try std.fmt.bufPrint(self.fps_text.text_data._backing_buffer, fmt, .{ fps, mem });
        self.fps_text.text_data.recalculateAttributes(self._allocator);
    }

    fn getMainBuffer(self: *GameScreen) []u8 {
        const buffer_len_half = @divExact(self.tooltip_main.text_data._backing_buffer.len, 2);
        const back_buffer = self.tooltip_main.text_data._backing_buffer[0..buffer_len_half];
        const front_buffer = self.tooltip_main.text_data._backing_buffer[buffer_len_half..];

        if (self.main_buffer_front) {
            self.main_buffer_front = false;
            return front_buffer;
        } else {
            self.main_buffer_front = true;
            return back_buffer;
        }
    }

    fn getFooterBuffer(self: *GameScreen) []u8 {
        const buffer_len_half = @divExact(self.tooltip_footer.text_data._backing_buffer.len, 2);
        const back_buffer = self.tooltip_footer.text_data._backing_buffer[0..buffer_len_half];
        const front_buffer = self.tooltip_footer.text_data._backing_buffer[buffer_len_half..];

        if (self.footer_buffer_front) {
            self.footer_buffer_front = false;
            return front_buffer;
        } else {
            self.footer_buffer_front = true;
            return back_buffer;
        }
    }

    pub fn updateTooltip(self: *GameScreen, x: f32, y: f32, item: u16) void {
        self.tooltip_container.x = x - self.tooltip_decor.width() - 15;
        self.tooltip_container.y = y - self.tooltip_decor.height() - 15;

        if (self.tooltip_item == item)
            return;

        self.tooltip_item = item;

        if (game_data.item_type_to_props.get(@intCast(item))) |props| {
            self.tooltip_decor.image_data.nine_slice.color_intensity = 0;
            self.tooltip_spacer_one.image_data.nine_slice.color_intensity = 0;
            self.tooltip_spacer_two.image_data.nine_slice.color_intensity = 0;

            if (std.mem.eql(u8, props.tier, "UT")) {
                self.tooltip_rarity.text_data.color = 0x8A2BE2;
                self.tooltip_rarity.text_data.text = "Untiered";
            } else {
                self.tooltip_rarity.text_data.color = 0xB3B3B3;
                self.tooltip_rarity.text_data.text = "Tiered";
            }

            if (props.is_potion)
                self.tooltip_rarity.text_data.text = "Potion";

            self.tooltip_rarity.text_data.recalculateAttributes(self._allocator);

            if (assets.atlas_data.get(props.texture_data.sheet)) |data| {
                self.tooltip_image.image_data.normal.atlas_data = data[props.texture_data.index];
            }

            self.tooltip_item_name.text_data.text = props.display_id;
            self.tooltip_item_name.text_data.recalculateAttributes(self._allocator);

            self.tooltip_description.text_data.text = props.description;
            self.tooltip_description.text_data.recalculateAttributes(self._allocator);

            self.tooltip_spacer_one.y = self.tooltip_description.y + self.tooltip_description.text_data._height + 10;
            self.tooltip_main.y = self.tooltip_spacer_one.y - 10;

            const line_base = "{s}\n";
            const inset_spaces = "    ";
            const line_base_inset = line_base ++ inset_spaces ++ "- ";

            const string_fmt = "&c=FFFF8F{s}&c=9B9B9B";
            const decimal_fmt = "&c=FFFF8F{d}&c=9B9B9B";
            const float_fmt = "&c=FFFF8F{d:.1}&c=9B9B9B";

            var written_on_use = false;
            var text: []u8 = "";
            if (props.activations) |activate| {
                for (activate) |data| {
                    if (!written_on_use) {
                        text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "On Use:", .{text}) catch text;
                        written_on_use = true;
                    }

                    text = switch (data.activation_type) {
                        .increment_stat => std.fmt.bufPrint(
                            self.getMainBuffer(),
                            line_base_inset ++ "Increases " ++ string_fmt ++ " by " ++ decimal_fmt,
                            .{ text, if (data.stat) |stat| stat.toString() else "Unknown", data.amount },
                        ),
                        .heal => std.fmt.bufPrint(self.getMainBuffer(), line_base_inset ++ "Restores " ++ decimal_fmt ++ " HP", .{ text, data.amount }),
                        .magic => std.fmt.bufPrint(self.getMainBuffer(), line_base_inset ++ "Restores " ++ decimal_fmt ++ " MP", .{ text, data.amount }),
                        .create => std.fmt.bufPrint(self.getMainBuffer(), line_base_inset ++ "Spawn the following: " ++ string_fmt, .{ text, data.id }),
                        .heal_nova => std.fmt.bufPrint(
                            self.getMainBuffer(),
                            line_base_inset ++ "Restores " ++ decimal_fmt ++ " HP within " ++ decimal_fmt ++ " tiles",
                            .{ text, data.amount, data.range },
                        ),
                        .magic_nova => std.fmt.bufPrint(
                            self.getMainBuffer(),
                            line_base_inset ++ "Restores " ++ decimal_fmt ++ " HP within " ++ decimal_fmt ++ " tiles",
                            .{ text, data.amount, data.range },
                        ),
                        .stat_boost_self => std.fmt.bufPrint(
                            self.getMainBuffer(),
                            line_base_inset ++ "Gain +" ++ decimal_fmt ++ " " ++ string_fmt ++ " for " ++ decimal_fmt ++ " seconds",
                            .{ text, data.amount, if (data.stat) |stat| stat.toString() else "Unknown", data.duration },
                        ),
                        .stat_boost_aura => std.fmt.bufPrint(
                            self.getMainBuffer(),
                            line_base_inset ++ "Grant players +" ++ decimal_fmt ++ " " ++ string_fmt ++ " within " ++ decimal_fmt ++
                                " tiles for " ++ decimal_fmt ++ " seconds",
                            .{ text, data.amount, if (data.stat) |stat| stat.toString() else "Unknown", data.range, data.duration },
                        ),
                        .condition_effect_aura => std.fmt.bufPrint(
                            self.getMainBuffer(),
                            line_base_inset ++ "Grant players " ++ string_fmt ++ " within " ++ decimal_fmt ++ " tiles for " ++ decimal_fmt ++ " seconds",
                            .{ text, data.effect.toString(), data.range, data.duration },
                        ),
                        .condition_effect_self => std.fmt.bufPrint(
                            self.getMainBuffer(),
                            line_base_inset ++ "Grant yourself " ++ string_fmt ++ " for " ++ decimal_fmt ++ " seconds",
                            .{ text, data.effect.toString(), data.duration },
                        ),
                        .teleport => std.fmt.bufPrint(self.getMainBuffer(), line_base_inset ++ "Teleport to cursor", .{text}),
                        .unlock_portal => std.fmt.bufPrint(
                            self.getMainBuffer(),
                            line_base_inset ++ "Unlocks the following dungeon: " ++ string_fmt,
                            .{ text, data.dungeon_name },
                        ),
                        else => continue,
                    } catch text;
                }
            }

            if (props.xp_boost) {
                if (!written_on_use) {
                    text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "On Use:", .{text}) catch text;
                    written_on_use = true;
                }

                if (props.timer > 0) {
                    text = std.fmt.bufPrint(
                        self.getMainBuffer(),
                        line_base ++ "Gain double XP for " ++ decimal_fmt ++ " minutes",
                        .{ text, props.timer / 60.0 },
                    ) catch text;
                } else {
                    text = std.fmt.bufPrint(
                        self.getMainBuffer(),
                        line_base ++ "Gain double XP until death",
                        .{text},
                    ) catch text;
                }
            }

            if (props.lt_boosted) {
                if (!written_on_use) {
                    text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "On Use:", .{text}) catch text;
                    written_on_use = true;
                }

                if (props.timer > 0) {
                    text = std.fmt.bufPrint(
                        self.getMainBuffer(),
                        line_base ++ "Gain items with higher tiers for " ++ decimal_fmt ++ " minutes",
                        .{ text, props.timer / 60.0 },
                    ) catch text;
                } else {
                    text = std.fmt.bufPrint(
                        self.getMainBuffer(),
                        line_base ++ "Gain items with higher tiers until death",
                        .{text},
                    ) catch text;
                }
            }

            if (props.ld_boosted) {
                if (!written_on_use) {
                    text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "On Use:", .{text}) catch text;
                    written_on_use = true;
                }

                if (props.timer > 0) {
                    text = std.fmt.bufPrint(
                        self.getMainBuffer(),
                        line_base ++ "Gain +50% loot drop chance for " ++ decimal_fmt ++ " minutes",
                        .{ text, props.timer / 60.0 },
                    ) catch text;
                } else {
                    text = std.fmt.bufPrint(
                        self.getMainBuffer(),
                        line_base ++ "Gain +50% loot drop chance until death",
                        .{text},
                    ) catch text;
                }
            }

            if (props.extra_tooltip_data) |extra| {
                if (!written_on_use) {
                    text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "On Use:", .{text}) catch text;
                    written_on_use = true;
                }

                for (extra) |effect| {
                    text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "{s}: " ++ string_fmt, .{ text, effect.name, effect.description }) catch text;
                }
            }

            if (props.projectile) |proj| {
                text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Bullets: " ++ decimal_fmt, .{ text, props.num_projectiles }) catch text;
                if (proj.physical_damage > 0)
                    text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Physical Damage: " ++ decimal_fmt, .{ text, proj.physical_damage }) catch text;
                if (proj.magic_damage > 0)
                    text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Magic Damage: " ++ decimal_fmt, .{ text, proj.magic_damage }) catch text;
                if (proj.true_damage > 0)
                    text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "True Damage: " ++ decimal_fmt, .{ text, proj.true_damage }) catch text;
                text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Range: " ++ float_fmt, .{ text, proj.speed * @as(f32, @floatFromInt(proj.lifetime_ms)) }) catch text;

                for (proj.effects, 0..) |effect, i| {
                    if (i == 0)
                        text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Shot effect:", .{text}) catch text;
                    text = std.fmt.bufPrint(
                        self.getMainBuffer(),
                        line_base_inset ++ "Inflict " ++ string_fmt ++ " for " ++ decimal_fmt ++ " seconds",
                        .{ text, effect.condition.toString(), effect.duration },
                    ) catch text;
                }

                if (props.rate_of_fire != 0)
                    text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Rate of Fire: " ++ decimal_fmt ++ "%", .{ text, props.rate_of_fire * 100 }) catch text;

                if (proj.multi_hit)
                    text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Bullets pierce", .{text}) catch text;
                if (proj.passes_cover)
                    text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Bullets pass through cover", .{text}) catch text;
                if (proj.armor_piercing)
                    text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Bullets ignore Defense", .{text}) catch text;
                if (proj.wavy)
                    text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Bullets are wavy", .{text}) catch text;
                if (proj.parametric)
                    text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Bullets are parametric", .{text}) catch text;
                if (proj.boomerang)
                    text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Bullets boomerang", .{text}) catch text;
            }

            if (props.stat_increments) |stat_increments| {
                for (stat_increments, 0..) |stat_increment, i| {
                    if (i == 0)
                        text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "On Equip:", .{text}) catch text;

                    if (stat_increment.amount > 0) {
                        text = std.fmt.bufPrint(
                            self.getMainBuffer(),
                            line_base ++ inset_spaces ++ "+" ++ decimal_fmt ++ " {s}",
                            .{ text, stat_increment.amount, stat_increment.stat.toString() },
                        ) catch text;
                    } else {
                        text = std.fmt.bufPrint(
                            self.getMainBuffer(),
                            line_base ++ inset_spaces ++ decimal_fmt ++ " {s}",
                            .{ text, stat_increment.amount, stat_increment.stat.toString() },
                        ) catch text;
                    }
                }
            }

            if (props.mp_cost != 0)
                text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Cost: " ++ decimal_fmt ++ " MP", .{ text, props.mp_cost }) catch text;

            if (props.usable)
                text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Cooldown: " ++ decimal_fmt ++ " seconds", .{ text, props.cooldown }) catch text;

            self.tooltip_main.text_data.text = text;
            self.tooltip_main.text_data.recalculateAttributes(self._allocator);

            self.tooltip_spacer_two.y = self.tooltip_main.y + self.tooltip_main.text_data._height + 10;
            self.tooltip_footer.y = self.tooltip_spacer_two.y - 10;

            var footer_text: []u8 = "";
            if (props.untradeable)
                footer_text = std.fmt.bufPrint(self.getFooterBuffer(), line_base ++ "Can not be traded", .{footer_text}) catch footer_text;

            const item_type: game_data.ItemType = @enumFromInt(props.slot_type);
            if (item_type != game_data.ItemType.no_item and
                item_type != game_data.ItemType.any and
                item_type != game_data.ItemType.consumable and
                item_type != game_data.ItemType.ring)
            {
                if (map.localPlayerConst()) |player| {
                    var has_type = false;
                    for (player.slot_types) |slot_type| {
                        if (slot_type == props.slot_type)
                            has_type = true;
                    }

                    if (!has_type) {
                        footer_text = std.fmt.bufPrint(
                            self.getFooterBuffer(),
                            line_base ++ "&c=D00000Not usable by: " ++ string_fmt,
                            .{ footer_text, player.class_name },
                        ) catch footer_text;

                        self.tooltip_decor.image_data.nine_slice.color = 0x8B0000;
                        self.tooltip_decor.image_data.nine_slice.color_intensity = 0.4;

                        self.tooltip_spacer_one.image_data.nine_slice.color = 0x8B0000;
                        self.tooltip_spacer_one.image_data.nine_slice.color_intensity = 0.4;

                        self.tooltip_spacer_two.image_data.nine_slice.color = 0x8B0000;
                        self.tooltip_spacer_two.image_data.nine_slice.color_intensity = 0.4;
                    }

                    footer_text = std.fmt.bufPrint(self.getFooterBuffer(), line_base ++ "Usable by: ", .{footer_text}) catch footer_text;

                    var first = true;
                    for (game_data.classes) |class| {
                        for (class.slot_types) |slot_type| {
                            if (slot_type == props.slot_type) {
                                if (first) {
                                    footer_text = std.fmt.bufPrint(self.getFooterBuffer(), "{s}" ++ string_fmt, .{ footer_text, class.name }) catch footer_text;
                                } else {
                                    footer_text = std.fmt.bufPrint(self.getFooterBuffer(), "{s}, " ++ string_fmt, .{ footer_text, class.name }) catch footer_text;
                                }

                                first = false;
                            }
                        }
                    }
                }
            }

            if (props.consumable)
                footer_text = std.fmt.bufPrint(self.getFooterBuffer(), line_base ++ "Can be consumed", .{footer_text}) catch footer_text;

            self.tooltip_footer.text_data.text = footer_text;
            self.tooltip_footer.text_data.recalculateAttributes(self._allocator);

            if (footer_text.len == 0) {
                self.tooltip_spacer_two.visible = false;
                self.tooltip_decor.image_data.nine_slice.h = self.tooltip_spacer_two.y;
            } else {
                self.tooltip_spacer_two.visible = true;
                self.tooltip_decor.image_data.nine_slice.h = self.tooltip_footer.y + self.tooltip_footer.text_data._height + 10;
            }

            self.tooltip_container.x = x - self.tooltip_decor.width() - 15;
            self.tooltip_container.y = y - self.tooltip_decor.height() - 15;
        }
    }

    fn parseItemRects(self: *GameScreen) void {
        for (0..20) |i| {
            const hori_idx: f32 = @floatFromInt(@mod(i, 4));
            const vert_idx: f32 = @floatFromInt(@divFloor(i, 4));
            if (i < 4) {
                self.inventory_pos_data[i] = utils.Rect{
                    .x = 5 + hori_idx * 44,
                    .y = 8,
                    .w = 40,
                    .h = 40,
                    .w_pad = 2,
                    .h_pad = 13,
                };
            } else {
                self.inventory_pos_data[i] = utils.Rect{
                    .x = 5 + hori_idx * 44,
                    .y = 63 + (vert_idx - 1) * 44,
                    .w = 40,
                    .h = 40,
                    .w_pad = 2,
                    .h_pad = 2,
                };
            }
        }

        for (0..8) |i| {
            const hori_idx: f32 = @floatFromInt(@mod(i, 4));
            const vert_idx: f32 = @floatFromInt(@divFloor(i, 4));
            self.container_pos_data[i] = utils.Rect{
                .x = 5 + hori_idx * 44,
                .y = 8 + vert_idx * 44,
                .w = 40,
                .h = 40,
                .w_pad = 2,
                .h_pad = 2,
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

                if (end_slot.idx >= 12 and local_player.tier < 2) {
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

    fn statsCallback() void {
        sc.current_screen.game.stats_container.visible = !sc.current_screen.game.stats_container.visible;
        sc.current_screen.game.updateStats();
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

    fn itemDragEndCallback(item: *element.Item) void {
        var current_screen = sc.current_screen.game;
        const start_slot = Slot.findSlotId(current_screen.*, item._drag_start_x + 4, item._drag_start_y + 4);
        const end_slot = Slot.findSlotId(current_screen.*, item.x - item._drag_offset_x, item.y - item._drag_offset_y);
        if (start_slot.idx == end_slot.idx and start_slot.is_container == end_slot.is_container) {
            item.x = item._drag_start_x;
            item.y = item._drag_start_y;
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
                return;
            } else {
                std.log.err("Could not find ui sheet {s} for item with type 0x{x}, index {d}", .{ props.texture_data.sheet, item, idx });
            }
        } else {
            std.log.err("Attempted to populate inventory index {d} with item 0x{x}, but props was not found", .{ idx, item });
        }

        const atlas_data = assets.error_data;
        self.container_items[idx]._item = std.math.maxInt(u16);
        self.container_items[idx].image_data.normal.atlas_data = atlas_data;
        self.container_items[idx].x = self.container_decor.x + self.container_pos_data[idx].x + (self.container_pos_data[idx].w - self.container_items[idx].width() + assets.padding * 2) / 2;
        self.container_items[idx].y = self.container_decor.y + self.container_pos_data[idx].y + (self.container_pos_data[idx].h - self.container_items[idx].height() + assets.padding * 2) / 2;
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
