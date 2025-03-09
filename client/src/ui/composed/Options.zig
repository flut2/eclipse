const std = @import("std");

const f32i = @import("shared").utils.f32i;

const assets = @import("../../assets.zig");
const input = @import("../../input.zig");
const main = @import("../../main.zig");
const Settings = @import("../../Settings.zig");
const Button = @import("../elements/Button.zig");
const Container = @import("../elements/Container.zig");
const element = @import("../elements/element.zig");
const Image = @import("../elements/Image.zig");
const KeyMapper = @import("../elements/KeyMapper.zig");
const Slider = @import("../elements/Slider.zig");
const Text = @import("../elements/Text.zig");
const Toggle = @import("../elements/Toggle.zig");
const systems = @import("../systems.zig");

const Options = @This();
const button_width = 150;
const button_height = 50;

pub const TabType = enum { general, graphics, misc };

visible: bool = false,

selected_tab: TabType = .general,
main_container: *Container = undefined,
buttons: *Container = undefined,
tabs: *Container = undefined,
general_tab: *Container = undefined,
graphics_tab: *Container = undefined,
misc_tab: *Container = undefined,
options_bg: *Image = undefined,
options_text: *Text = undefined,
continue_button: *Button = undefined,
disconnect_button: *Button = undefined,
defaults_button: *Button = undefined,

pub fn create() !*Options {
    var options = try main.allocator.create(Options);
    options.* = .{};

    options.main_container = try element.create(Container, .{ .base = .{
        .x = 0,
        .y = 0,
        .visible = options.visible,
    } });

    options.buttons = try element.create(Container, .{ .base = .{
        .x = 0,
        .y = main.camera.height - button_height - 50,
        .visible = options.visible,
    } });

    options.tabs = try element.create(Container, .{ .base = .{
        .x = 0,
        .y = 25,
        .visible = options.visible,
    } });

    options.general_tab = try element.create(Container, .{ .base = .{
        .x = 100,
        .y = 150,
        .visible = options.visible and options.selected_tab == .general,
    } });

    options.graphics_tab = try element.create(Container, .{ .base = .{
        .x = 100,
        .y = 150,
        .visible = options.visible and options.selected_tab == .graphics,
    } });

    options.misc_tab = try element.create(Container, .{ .base = .{
        .x = 100,
        .y = 150,
        .visible = options.visible and options.selected_tab == .misc,
    } });

    const background = assets.getUiData("dark_background", 0);
    options.options_bg = try options.main_container.createChild(Image, .{
        .base = .{ .x = 0, .y = 0 },
        .image_data = .{ .nine_slice = .fromAtlasData(background, main.camera.width, main.camera.height, 0, 0, 8, 8, 1.0) },
    });

    options.options_text = try options.main_container.createChild(Text, .{
        .base = .{ .x = 0, .y = 25 },
        .text_data = .{
            .text = "Options",
            .size = 32,
            .text_type = .bold,
        },
    });
    options.options_text.base.x = (main.camera.width - options.options_text.width()) / 2;

    const button_data_base = assets.getUiData("button_base", 0);
    const button_data_hover = assets.getUiData("button_hover", 0);
    const button_data_press = assets.getUiData("button_press", 0);
    options.continue_button = try options.buttons.createChild(Button, .{
        .base = .{
            .x = (main.camera.width - button_width) / 2,
            .y = button_height / 2 - 20,
        },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 26, 19, 1, 1, 1.0),
        .text_data = .{
            .text = "Continue",
            .size = 16,
            .text_type = .bold,
        },
        .userdata = options,
        .pressCallback = closeCallback,
    });

    options.disconnect_button = try options.buttons.createChild(Button, .{
        .base = .{
            .x = main.camera.width - button_width - 50,
            .y = button_height / 2 - 20,
        },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 26, 19, 1, 1, 1.0),
        .text_data = .{
            .text = "Disconnect",
            .size = 16,
            .text_type = .bold,
        },
        .userdata = options,
        .pressCallback = disconnectCallback,
    });

    options.defaults_button = try options.buttons.createChild(Button, .{
        .base = .{ .x = 50, .y = button_height / 2 - 20 },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 26, 19, 1, 1, 1.0),
        .text_data = .{
            .text = "Defaults",
            .size = 16,
            .text_type = .bold,
        },
        .pressCallback = resetToDefaultsCallback,
    });

    var tabx_offset: f32 = 50;
    const tab_y = 50;

    _ = try options.tabs.createChild(Button, .{
        .base = .{ .x = tabx_offset, .y = tab_y },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 26, 19, 1, 1, 1.0),
        .text_data = .{
            .text = "General",
            .size = 16,
            .text_type = .bold,
        },
        .userdata = options,
        .pressCallback = generalTabCallback,
    });

    tabx_offset += button_width + 10;

    _ = try options.tabs.createChild(Button, .{
        .base = .{ .x = tabx_offset, .y = tab_y },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 26, 19, 1, 1, 1.0),
        .text_data = .{
            .text = "Graphics",
            .size = 16,
            .text_type = .bold,
        },
        .userdata = options,
        .pressCallback = graphicsTabCallback,
    });

    tabx_offset += button_width + 10;

    _ = try options.tabs.createChild(Button, .{
        .base = .{ .x = tabx_offset, .y = tab_y },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 26, 19, 1, 1, 1.0),
        .text_data = .{
            .text = "Misc",
            .size = 16,
            .text_type = .bold,
        },
        .userdata = options,
        .pressCallback = miscTabCallback,
    });

    try addKeyMap(options.general_tab, &main.settings.move_up, "Move Up", "");
    try addKeyMap(options.general_tab, &main.settings.move_down, "Move Down", "");
    try addKeyMap(options.general_tab, &main.settings.move_right, "Move Right", "");
    try addKeyMap(options.general_tab, &main.settings.move_left, "Move Left", "");
    try addKeyMap(options.general_tab, &main.settings.ability_1, "Cast Basic Ability 1", "");
    try addKeyMap(options.general_tab, &main.settings.ability_2, "Cast Basic Ability 2", "");
    try addKeyMap(options.general_tab, &main.settings.ability_3, "Cast Basic Ability 3", "");
    try addKeyMap(options.general_tab, &main.settings.ability_4, "Cast Ultimate Ability", "");
    try addKeyMap(options.general_tab, &main.settings.escape, "Return to the Retrieve", "");
    try addKeyMap(options.general_tab, &main.settings.interact, "Interact", "");
    try addKeyMap(options.general_tab, &main.settings.shoot, "Shoot", "");
    try addKeyMap(options.general_tab, &main.settings.walk, "Walk", "Allows you to move slowly");
    try addKeyMap(options.general_tab, &main.settings.toggle_perf_stats, "Toggle Performance Counter", "This toggles whether to show the performance counter");

    try addToggle(options.graphics_tab, &main.settings.enable_vsync, "V-Sync", "Toggles vertical syncing, which can reduce screen tearing");
    try addToggle(options.graphics_tab, &main.settings.enable_lights, "Lights", "Toggles lights, which can reduce frame rates");

    try addSlider(options.misc_tab, &main.settings.sfx_volume, 0.0, 1.0, "SFX Volume", "Changes the volume of sound effects");
    try addSlider(options.misc_tab, &main.settings.music_volume, 0.0, 1.0, "Music Volume", "Changes the volume of music");

    switch (options.selected_tab) {
        .general => positionElements(options.general_tab),
        .graphics => positionElements(options.graphics_tab),
        .misc => positionElements(options.misc_tab),
    }

    return options;
}

pub fn destroy(self: *Options) void {
    element.destroy(self.main_container);
    element.destroy(self.buttons);
    element.destroy(self.tabs);
    element.destroy(self.general_tab);
    element.destroy(self.graphics_tab);
    element.destroy(self.misc_tab);

    main.allocator.destroy(self);
}

pub fn resize(self: *Options, w: f32, h: f32) void {
    self.options_bg.image_data.nine_slice.w = w;
    self.options_bg.image_data.nine_slice.h = h;
    self.options_text.base.x = (w - self.options_text.width()) / 2;
    self.buttons.base.y = h - button_height - 50;
    self.disconnect_button.base.x = w - button_width - 50;
    self.continue_button.base.x = (w - button_width) / 2;
    switch (self.selected_tab) {
        .general => positionElements(self.general_tab),
        .graphics => positionElements(self.graphics_tab),
        .misc => positionElements(self.misc_tab),
    }
}

fn addKeyMap(target_tab: *Container, button: *Settings.Button, title: []const u8, desc: []const u8) !void {
    const button_data_base = assets.getUiData("button_base", 0);
    const button_data_hover = assets.getUiData("button_hover", 0);
    const button_data_press = assets.getUiData("button_press", 0);

    const w = 50;
    const h = 50;

    _ = try target_tab.createChild(KeyMapper, .{
        .base = .{ .x = 0, .y = 0 },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, w, h, 26, 19, 1, 1, 1.0),
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
        .settings_button = button,
        .setKeyCallback = keyCallback,
    });
}

fn addToggle(target_tab: *Container, value: *bool, title: []const u8, desc: []const u8) !void {
    const toggle_data_base_off = assets.getUiData("toggle_slider_base_off", 0);
    const toggle_data_hover_off = assets.getUiData("toggle_slider_hover_off", 0);
    const toggle_data_press_off = assets.getUiData("toggle_slider_press_off", 0);
    const toggle_data_base_on = assets.getUiData("toggle_slider_base_on", 0);
    const toggle_data_hover_on = assets.getUiData("toggle_slider_hover_on", 0);
    const toggle_data_press_on = assets.getUiData("toggle_slider_press_on", 0);

    _ = try target_tab.createChild(Toggle, .{
        .base = .{ .x = 0, .y = 0 },
        .off_image_data = .fromImageData(toggle_data_base_off, toggle_data_hover_off, toggle_data_press_off),
        .on_image_data = .fromImageData(toggle_data_base_on, toggle_data_hover_on, toggle_data_press_on),
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

fn addSlider(target_tab: *Container, value: *f32, min_value: f32, max_value: f32, title: []const u8, desc: []const u8) !void {
    const background_data = assets.getUiData("slider_background", 0);
    const knob_data_base = assets.getUiData("slider_knob_base", 0);
    const knob_data_hover = assets.getUiData("slider_knob_hover", 0);
    const knob_data_press = assets.getUiData("slider_knob_press", 0);

    const w = 250;
    const h = 30;
    const knob_size = 40;

    _ = try target_tab.createChild(Slider, .{
        .base = .{ .x = 0, .y = 0 },
        .w = w,
        .h = h,
        .min_value = min_value,
        .max_value = max_value,
        .decor_image_data = .{ .nine_slice = .fromAtlasData(background_data, w, h, 6, 6, 1, 1, 1.0) },
        .knob_image_data = .fromNineSlices(knob_data_base, knob_data_hover, knob_data_press, knob_size, knob_size, 12, 12, 1, 1, 1.0),
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
        .target = value,
        .state_change = sliderCallback,
    });
}

fn positionElements(container: *Container) void {
    for (container.elements.items, 0..) |elem, i| {
        switch (elem) {
            .scrollable_container, .container => {},
            inline else => |inner| {
                inner.base.x = f32i(@divFloor(i, 6)) * (main.camera.width / 4.0);
                inner.base.y = f32i(@mod(i, 6)) * (main.camera.height / 9.0);
            },
        }
    }
}

fn sliderCallback(slider: *Slider) void {
    if (slider.target) |target| {
        if (target == &main.settings.music_volume)
            if (assets.main_music) |music| {
                music.setVolume(slider.current_value);
                if (main.settings.music_volume > 0.0) music.start() catch main.audioFailure();
            };
    } else @panic("Options slider has no target pointer. This is a bug, please add");

    trySave();
}

fn keyCallback(key_mapper: *KeyMapper) void {
    if (key_mapper.settings_button == &main.settings.interact)
        assets.interact_key_tex = assets.getKeyTexture(main.settings.interact);

    trySave();
}

fn closeCallback(ud: ?*anyopaque) void {
    const screen: *Options = @alignCast(@ptrCast(ud.?));
    screen.setVisible(false);
    input.disable_input = false;

    trySave();
}

fn resetToDefaultsCallback(_: ?*anyopaque) void {
    main.settings.resetToDefaults();
}

fn generalTabCallback(ud: ?*anyopaque) void {
    switchTab(@alignCast(@ptrCast(ud.?)), .general);
}

fn graphicsTabCallback(ud: ?*anyopaque) void {
    switchTab(@alignCast(@ptrCast(ud.?)), .graphics);
}

fn miscTabCallback(ud: ?*anyopaque) void {
    switchTab(@alignCast(@ptrCast(ud.?)), .misc);
}

fn disconnectCallback(ud: ?*anyopaque) void {
    closeCallback(ud);
    main.game_server.shutdown();
    main.disconnect();
}

fn trySave() void {
    main.settings.save() catch |e| {
        std.log.err("Error while saving settings in options: {}", .{e});
        return;
    };
}

pub fn switchTab(self: *Options, tab: TabType) void {
    self.selected_tab = tab;
    self.general_tab.base.visible = tab == .general;
    self.graphics_tab.base.visible = tab == .graphics;
    self.misc_tab.base.visible = tab == .misc;

    switch (tab) {
        .general => positionElements(self.general_tab),
        .graphics => positionElements(self.graphics_tab),
        .misc => positionElements(self.misc_tab),
    }
}

pub fn setVisible(self: *Options, val: bool) void {
    self.visible = val;
    self.main_container.base.visible = val;
    self.buttons.base.visible = val;
    self.tabs.base.visible = val;

    if (val) {
        self.switchTab(.general);
    } else {
        self.general_tab.base.visible = false;
        self.graphics_tab.base.visible = false;
        self.misc_tab.base.visible = false;
    }
}
