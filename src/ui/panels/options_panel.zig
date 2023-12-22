const std = @import("std");
const element = @import("../element.zig");
const assets = @import("../../assets.zig");
const camera = @import("../../camera.zig");
const main = @import("../../main.zig");
const settings = @import("../../settings.zig");

const PanelController = @import("../controllers/panel_controller.zig").PanelController;
const NineSlice = element.NineSliceImageData;
const sc = @import("../controllers/screen_controller.zig");

pub const TabType = enum {
    general,
    hotkeys,
    graphics,
    misc,
};

pub const OptionsPanel = struct {
    visible: bool = false,
    inited: bool = false,
    selected_tab_type: TabType = .general,
    main: *element.Container = undefined,
    buttons: *element.Container = undefined,
    tabs: *element.Container = undefined,
    general_tab: *element.Container = undefined,
    keys_tab: *element.Container = undefined,
    graphics_tab: *element.Container = undefined,
    misc_tab: *element.Container = undefined,
    _allocator: std.mem.Allocator = undefined,

    pub fn init(allocator: std.mem.Allocator) !*OptionsPanel {
        var screen = try allocator.create(OptionsPanel);
        screen.* = .{ ._allocator = allocator };

        const button_width = 150;
        const button_height = 50;
        const button_half_width = button_width / 2;
        const button_half_height = button_height / 2;
        const width = camera.screen_width;
        const height = camera.screen_height;
        const buttons_x = width / 2;
        const buttons_y = height - button_height - 50;

        screen.main = try element.Container.create(allocator, .{
            .x = 0,
            .y = 0,
            .visible = screen.visible,
        });

        screen.buttons = try element.Container.create(allocator, .{
            .x = 0,
            .y = buttons_y,
            .visible = screen.visible,
        });

        screen.tabs = try element.Container.create(allocator, .{
            .x = 0,
            .y = 25,
            .visible = screen.visible,
        });

        screen.general_tab = try element.Container.create(allocator, .{
            .x = 100,
            .y = 150,
            .visible = screen.visible and screen.selected_tab_type == .general,
        });

        screen.keys_tab = try element.Container.create(allocator, .{
            .x = 100,
            .y = 150,
            .visible = screen.visible and screen.selected_tab_type == .hotkeys,
        });

        screen.graphics_tab = try element.Container.create(allocator, .{
            .x = 100,
            .y = 150,
            .visible = screen.visible and screen.selected_tab_type == .graphics,
        });

        screen.misc_tab = try element.Container.create(allocator, .{
            .x = 100,
            .y = 150,
            .visible = screen.visible and screen.selected_tab_type == .misc,
        });

        const options_background = assets.getUiData("options_background", 0);
        _ = try screen.main.createElement(element.Image, .{ .x = 0, .y = 0, .image_data = .{
            .nine_slice = NineSlice.fromAtlasData(options_background, width, height, 0, 0, 8, 8, 1.0),
        } });

        _ = try screen.main.createElement(element.Text, .{ .x = buttons_x - 76, .y = 25, .text_data = .{
            .text = "Options",
            .size = 32,
            .text_type = .bold,
        } });

        const button_data_base = assets.getUiData("button_base", 0);
        const button_data_hover = assets.getUiData("button_hover", 0);
        const button_data_press = assets.getUiData("button_press", 0);
        _ = try screen.buttons.createElement(element.Button, .{
            .x = buttons_x - button_half_width,
            .y = button_half_height - 20,
            .image_data = .{
                .base = .{ .nine_slice = NineSlice.fromAtlasData(button_data_base, button_width, button_height, 6, 6, 7, 7, 1.0) },
                .hover = .{ .nine_slice = NineSlice.fromAtlasData(button_data_hover, button_width, button_height, 6, 6, 7, 7, 1.0) },
                .press = .{ .nine_slice = NineSlice.fromAtlasData(button_data_press, button_width, button_height, 6, 6, 7, 7, 1.0) },
            },
            .text_data = .{
                .text = "Continue",
                .size = 16,
                .text_type = .bold,
            },
            .press_callback = closeCallback,
        });

        _ = try screen.buttons.createElement(element.Button, .{
            .x = width - button_width - 50,
            .y = button_half_height - 20,
            .image_data = .{
                .base = .{ .nine_slice = NineSlice.fromAtlasData(button_data_base, button_width, button_height, 6, 6, 7, 7, 1.0) },
                .hover = .{ .nine_slice = NineSlice.fromAtlasData(button_data_hover, button_width, button_height, 6, 6, 7, 7, 1.0) },
                .press = .{ .nine_slice = NineSlice.fromAtlasData(button_data_press, button_width, button_height, 6, 6, 7, 7, 1.0) },
            },
            .text_data = .{
                .text = "Disconnect",
                .size = 16,
                .text_type = .bold,
            },
            .press_callback = disconnectCallback,
        });

        _ = try screen.buttons.createElement(element.Button, .{
            .x = 50,
            .y = button_half_height - 20,
            .image_data = .{
                .base = .{ .nine_slice = NineSlice.fromAtlasData(button_data_base, button_width, button_height, 6, 6, 7, 7, 1.0) },
                .hover = .{ .nine_slice = NineSlice.fromAtlasData(button_data_hover, button_width, button_height, 6, 6, 7, 7, 1.0) },
                .press = .{ .nine_slice = NineSlice.fromAtlasData(button_data_press, button_width, button_height, 6, 6, 7, 7, 1.0) },
            },
            .text_data = .{
                .text = "Defaults",
                .size = 16,
                .text_type = .bold,
            },
            .press_callback = resetToDefaultsCallback,
        });

        var tab_x_offset: f32 = 50;
        const tab_y = 50;

        _ = try screen.tabs.createElement(element.Button, .{
            .x = tab_x_offset,
            .y = tab_y,
            .image_data = .{
                .base = .{ .nine_slice = NineSlice.fromAtlasData(button_data_base, button_width, button_height, 6, 6, 7, 7, 1.0) },
                .hover = .{ .nine_slice = NineSlice.fromAtlasData(button_data_hover, button_width, button_height, 6, 6, 7, 7, 1.0) },
                .press = .{ .nine_slice = NineSlice.fromAtlasData(button_data_press, button_width, button_height, 6, 6, 7, 7, 1.0) },
            },
            .text_data = .{
                .text = "General",
                .size = 16,
                .text_type = .bold,
            },
            .press_callback = generalTabCallback,
        });

        tab_x_offset += button_width + 10;

        _ = try screen.tabs.createElement(element.Button, .{
            .x = tab_x_offset,
            .y = tab_y,
            .image_data = .{
                .base = .{ .nine_slice = NineSlice.fromAtlasData(button_data_base, button_width, button_height, 6, 6, 7, 7, 1.0) },
                .hover = .{ .nine_slice = NineSlice.fromAtlasData(button_data_hover, button_width, button_height, 6, 6, 7, 7, 1.0) },
                .press = .{ .nine_slice = NineSlice.fromAtlasData(button_data_press, button_width, button_height, 6, 6, 7, 7, 1.0) },
            },
            .text_data = .{
                .text = "Hotkeys",
                .size = 16,
                .text_type = .bold,
            },
            .press_callback = hotkeysTabCallback,
        });

        tab_x_offset += button_width + 10;

        _ = try screen.tabs.createElement(element.Button, .{
            .x = tab_x_offset,
            .y = tab_y,
            .image_data = .{
                .base = .{ .nine_slice = NineSlice.fromAtlasData(button_data_base, button_width, button_height, 6, 6, 7, 7, 1.0) },
                .hover = .{ .nine_slice = NineSlice.fromAtlasData(button_data_hover, button_width, button_height, 6, 6, 7, 7, 1.0) },
                .press = .{ .nine_slice = NineSlice.fromAtlasData(button_data_press, button_width, button_height, 6, 6, 7, 7, 1.0) },
            },
            .text_data = .{
                .text = "Graphics",
                .size = 16,
                .text_type = .bold,
            },
            .press_callback = graphicsTabCallback,
        });

        tab_x_offset += button_width + 10;

        _ = try screen.tabs.createElement(element.Button, .{
            .x = tab_x_offset,
            .y = tab_y,
            .image_data = .{
                .base = .{ .nine_slice = NineSlice.fromAtlasData(button_data_base, button_width, button_height, 6, 6, 7, 7, 1.0) },
                .hover = .{ .nine_slice = NineSlice.fromAtlasData(button_data_hover, button_width, button_height, 6, 6, 7, 7, 1.0) },
                .press = .{ .nine_slice = NineSlice.fromAtlasData(button_data_press, button_width, button_height, 6, 6, 7, 7, 1.0) },
            },
            .text_data = .{
                .text = "Misc",
                .size = 16,
                .text_type = .bold,
            },
            .press_callback = miscTabCallback,
        });

        try addKeyMap(screen.general_tab, &settings.move_up, "Move Up", "");
        try addKeyMap(screen.general_tab, &settings.move_down, "Move Down", "");
        try addKeyMap(screen.general_tab, &settings.move_right, "Move Right", "");
        try addKeyMap(screen.general_tab, &settings.move_left, "Move Left", "");
        try addKeyMap(screen.general_tab, &settings.rotate_left, "Rotate Left", "");
        try addKeyMap(screen.general_tab, &settings.rotate_right, "Rotate Right", "");
        try addKeyMap(screen.general_tab, &settings.escape, "Return to Hub", "");
        try addKeyMap(screen.general_tab, &settings.interact, "Interact", "");
        try addKeyMap(screen.general_tab, &settings.shoot, "Shoot", "");
        try addKeyMap(screen.general_tab, &settings.ability_1, "Use Ability 1", "");
        try addKeyMap(screen.general_tab, &settings.ability_2, "Use Ability 2", "");
        try addKeyMap(screen.general_tab, &settings.ability_3, "Use Ability 3", "");
        try addKeyMap(screen.general_tab, &settings.ultimate_ability, "Use Ultimate Ability", "");
        try addKeyMap(screen.general_tab, &settings.reset_camera, "Reset Camera", "This resets the camera's angle to the default of 0");
        try addKeyMap(screen.general_tab, &settings.toggle_stats, "Toggle Stats", "This toggles whether to show the stats view");
        try addKeyMap(screen.general_tab, &settings.toggle_perf_stats, "Toggle Performance Counter", "This toggles whether to show the performance counter");
        try addKeyMap(screen.general_tab, &settings.toggle_centering, "Toggle Centering", "This toggles whether to center the camera on the player or ahead of it");

        try addToggle(screen.graphics_tab, &settings.enable_vsync, "V-Sync", "Toggles vertical syncing, which can reduce screen tearing");
        try addToggle(screen.graphics_tab, &settings.enable_lights, "Lights", "Toggles lights, which can reduce frame rates");
        try addToggle(screen.graphics_tab, &settings.enable_glow, "Sprite Glow", "Toggles the glow effect on sprites, which can reduce frame rates");
        try addSlider(screen.graphics_tab, &settings.fps_cap, 60.0, 999.99, "FPS Cap", "Changes the FPS cap");

        try addSlider(screen.misc_tab, &settings.sfx_volume, 0.0, 1.0, "SFX Volume", "Changes the volume of sound effects");
        try addSlider(screen.misc_tab, &settings.music_volume, 0.0, 1.0, "Music Volume", "Changes the volume of music");

        switch (screen.selected_tab_type) {
            .general => positionElements(screen.general_tab),
            .hotkeys => positionElements(screen.keys_tab),
            .graphics => positionElements(screen.graphics_tab),
            .misc => positionElements(screen.misc_tab),
        }

        screen.inited = true;
        return screen;
    }

    pub fn deinit(self: *OptionsPanel) void {
        self.main.destroy();
        self.buttons.destroy();
        self.tabs.destroy();
        self.general_tab.destroy();
        self.keys_tab.destroy();
        self.graphics_tab.destroy();
        self.misc_tab.destroy();
        self._allocator.destroy(self);
    }

    fn addKeyMap(target_tab: *element.Container, button: *settings.Button, title: []const u8, desc: []const u8) !void {
        const button_data_base = assets.getUiData("button_base", 0);
        const button_data_hover = assets.getUiData("button_hover", 0);
        const button_data_press = assets.getUiData("button_press", 0);

        const w = 50;
        const h = 50;

        _ = try target_tab.createElement(element.KeyMapper, .{
            .x = 0,
            .y = 0,
            .image_data = .{
                .base = .{ .nine_slice = NineSlice.fromAtlasData(button_data_base, w, h, 6, 6, 7, 7, 1.0) },
                .hover = .{ .nine_slice = NineSlice.fromAtlasData(button_data_hover, w, h, 6, 6, 7, 7, 1.0) },
                .press = .{ .nine_slice = NineSlice.fromAtlasData(button_data_press, w, h, 6, 6, 7, 7, 1.0) },
            },
            .title_text_data = .{
                .text = title,
                .size = 18,
                .text_type = .bold,
            },
            .tooltip_text = if (desc.len > 0) .{
                .text = desc,
                .size = 16,
                .text_type = .bold_italic,
            } else null,
            .key = button.getKey(),
            .mouse = button.getMouse(),
            .settings_button = button,
            .set_key_callback = keyCallback,
        });
    }

    fn addToggle(target_tab: *element.Container, value: *bool, title: []const u8, desc: []const u8) !void {
        const toggle_data_base_off = assets.getUiData("toggle_slider_base_off", 0);
        const toggle_data_hover_off = assets.getUiData("toggle_slider_hover_off", 0);
        const toggle_data_press_off = assets.getUiData("toggle_slider_press_off", 0);
        const toggle_data_base_on = assets.getUiData("toggle_slider_base_on", 0);
        const toggle_data_hover_on = assets.getUiData("toggle_slider_hover_on", 0);
        const toggle_data_press_on = assets.getUiData("toggle_slider_press_on", 0);

        _ = try target_tab.createElement(element.Toggle, .{
            .x = 0,
            .y = 0,
            .off_image_data = .{
                .base = .{ .normal = .{ .atlas_data = toggle_data_base_off } },
                .hover = .{ .normal = .{ .atlas_data = toggle_data_hover_off } },
                .press = .{ .normal = .{ .atlas_data = toggle_data_press_off } },
            },
            .on_image_data = .{
                .base = .{ .normal = .{ .atlas_data = toggle_data_base_on } },
                .hover = .{ .normal = .{ .atlas_data = toggle_data_hover_on } },
                .press = .{ .normal = .{ .atlas_data = toggle_data_press_on } },
            },
            .text_data = .{
                .text = title,
                .size = 16,
                .text_type = .bold,
            },
            .tooltip_text = if (desc.len > 0) .{
                .text = desc,
                .size = 16,
                .text_type = .bold_italic,
            } else null,
            .toggled = value,
        });
    }

    fn addSlider(target_tab: *element.Container, value: *f32, min_value: f32, max_value: f32, title: []const u8, desc: []const u8) !void {
        const background_data = assets.getUiData("slider_background", 0);
        const knob_data_base = assets.getUiData("slider_knob_base", 0);
        const knob_data_hover = assets.getUiData("slider_knob_hover", 0);
        const knob_data_press = assets.getUiData("slider_knob_press", 0);

        const w = 250;
        const h = 30;
        const knob_size = 40;

        _ = try target_tab.createElement(element.Slider, .{
            .x = 0,
            .y = 0,
            .w = w,
            .h = h,
            .min_value = min_value,
            .max_value = max_value,
            .decor_image_data = .{ .nine_slice = NineSlice.fromAtlasData(background_data, w, h, 1, 1, 2, 2, 1.0) },
            .knob_image_data = .{
                .base = .{ .nine_slice = NineSlice.fromAtlasData(knob_data_base, knob_size, knob_size, 5, 5, 2, 2, 1.0) },
                .hover = .{ .nine_slice = NineSlice.fromAtlasData(knob_data_hover, knob_size, knob_size, 5, 5, 2, 2, 1.0) },
                .press = .{ .nine_slice = NineSlice.fromAtlasData(knob_data_press, knob_size, knob_size, 5, 5, 2, 2, 1.0) },
            },
            .title_text_data = .{
                .text = title,
                .size = 16,
                .text_type = .bold,
            },
            .value_text_data = .{
                .text = "",
                .size = 10,
                .text_type = .bold,
                .max_chars = 64,
            },
            .tooltip_text = if (desc.len > 0) .{
                .text = desc,
                .size = 16,
                .text_type = .bold_italic,
            } else null,
            .stored_value = value,
            .state_change = sliderCallback,
        });
    }

    fn positionElements(container: *element.Container) void {
        for (container._elements.items, 0..) |elem, i| {
            switch (elem) {
                .scrollable_container, .container => {},
                inline else => |inner| {
                    inner.x = @floatFromInt(@divFloor(i, 6) * 300);
                    inner.y = @floatFromInt(@mod(i, 6) * 80);
                },
            }
        }
    }

    fn sliderCallback(slider: *element.Slider) void {
        if (slider.stored_value) |value_ptr| {
            value_ptr.* = slider._current_value;
            // another hack, but i don't see a better way of handling this without rearchitecting everything
            if (value_ptr == &settings.music_volume)
                assets.main_music.setVolume(slider._current_value);
        }

        trySave();
    }

    fn keyCallback(key_mapper: *element.KeyMapper) void {
        // Should rethink whether we want to keep this from flash. Binding things to ESC is legitimate
        if (key_mapper.key == .escape) {
            key_mapper.settings_button.* = .{ .key = .unknown };
        } else if (key_mapper.key != .unknown) {
            key_mapper.settings_button.* = .{ .key = key_mapper.key };
        } else {
            key_mapper.settings_button.* = .{ .mouse = key_mapper.mouse };
        }

        if (key_mapper.settings_button == &settings.interact)
            settings.interact_key_tex = settings.getKeyTexture(settings.interact);

        trySave();
    }

    fn closeCallback() void {
        sc.current_screen.game.panel_controller.setOptionsVisible(false);

        trySave();
    }

    fn resetToDefaultsCallback() void {
        settings.resetToDefault();
    }

    fn generalTabCallback() void {
        switchTab(.general);
    }

    fn hotkeysTabCallback() void {
        switchTab(.hotkeys);
    }

    fn graphicsTabCallback() void {
        switchTab(.graphics);
    }

    fn miscTabCallback() void {
        switchTab(.misc);
    }

    fn disconnectCallback() void {
        closeCallback();
        main.disconnect();
    }

    fn trySave() void {
        settings.save() catch |err| {
            std.debug.print("Caught error. {any}", .{err});
            return;
        };
    }

    pub fn switchTab(tab: TabType) void {
        var self = sc.current_screen.game.panel_controller.options;

        self.selected_tab_type = tab;
        self.general_tab.visible = tab == .general;
        self.keys_tab.visible = tab == .hotkeys;
        self.graphics_tab.visible = tab == .graphics;
        self.misc_tab.visible = tab == .misc;

        switch (tab) {
            .general => positionElements(self.general_tab),
            .hotkeys => positionElements(self.keys_tab),
            .graphics => positionElements(self.graphics_tab),
            .misc => positionElements(self.misc_tab),
        }
    }

    pub fn setVisible(self: *OptionsPanel, val: bool) void {
        self.visible = val;
        self.main.visible = val;
        self.buttons.visible = val;
        self.tabs.visible = val;

        if (val) {
            switchTab(.general);
        } else {
            self.general_tab.visible = false;
            self.keys_tab.visible = false;
            self.graphics_tab.visible = false;
            self.misc_tab.visible = false;
        }
    }

    pub fn resize(_: *OptionsPanel, _: f32, _: f32) void {}
};
