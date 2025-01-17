const std = @import("std");

const glfw = @import("zglfw");
const nfd = @import("nfd");
const shared = @import("shared");
const map_data = shared.map_data;
const game_data = shared.game_data;
const utils = shared.utils;
const f32i = utils.f32i;
const u16f = utils.u16f;
const usizef = utils.usizef;

const assets = @import("../../assets.zig");
const Container = @import("../../game/Container.zig");
const Enemy = @import("../../game/Enemy.zig");
const Entity = @import("../../game/Entity.zig");
const map = @import("../../game/map.zig");
const Player = @import("../../game/Player.zig");
const Portal = @import("../../game/Portal.zig");
const Square = @import("../../game/Square.zig");
const input = @import("../../input.zig");
const main = @import("../../main.zig");
const Settings = @import("../../Settings.zig");
const dialog = @import("../dialogs/dialog.zig");
const Button = @import("../elements/Button.zig");
const UiContainer = @import("../elements/Container.zig");
const Dropdown = @import("../elements/Dropdown.zig");
const DropdownContainer = @import("../elements/DropdownContainer.zig");
const element = @import("../elements/element.zig");
const Image = @import("../elements/Image.zig");
const KeyMapper = @import("../elements/KeyMapper.zig");
const ScrollableContainer = @import("../elements/ScrollableContainer.zig");
const Slider = @import("../elements/Slider.zig");
const Text = @import("../elements/Text.zig");
const ui_systems = @import("../systems.zig");

const press_delay_ms = 25;
const update_delay_ms = 10;
const move_select_delay_ms = 15;

const MapEditorTile = struct {
    // map ids
    entity: u32 = std.math.maxInt(u32),
    enemy: u32 = std.math.maxInt(u32),
    portal: u32 = std.math.maxInt(u32),
    container: u32 = std.math.maxInt(u32),
    region_map_id: u32 = std.math.maxInt(u32), // for the indicator

    // data ids
    ground: u16 = Square.editor_tile,
    region: u16 = std.math.maxInt(u16),
};

pub const EditorCommand = union(enum) {
    place: Place,
    multi_place: MultiPlace,
};

const EditorAction = enum {
    none,
    place,
    erase,
    random,
    undo,
    redo,
    sample,
    fill,
    wand,
    unselect,
};

const Layer = enum(u8) {
    entity,
    enemy,
    portal,
    container,
    ground,
    region,
};

const Place = struct {
    x: u16,
    y: u16,
    new_id: u16,
    old_id: u16,
    layer: Layer,

    pub fn execute(self: Place) void {
        switch (self.layer) {
            .ground => ui_systems.screen.editor.setTile(self.x, self.y, self.new_id),
            .region => ui_systems.screen.editor.setRegion(self.x, self.y, self.new_id),
            .entity => ui_systems.screen.editor.setObject(Entity, self.x, self.y, self.new_id),
            .enemy => ui_systems.screen.editor.setObject(Enemy, self.x, self.y, self.new_id),
            .portal => ui_systems.screen.editor.setObject(Portal, self.x, self.y, self.new_id),
            .container => ui_systems.screen.editor.setObject(Container, self.x, self.y, self.new_id),
        }
    }

    pub fn unexecute(self: Place) void {
        switch (self.layer) {
            .ground => ui_systems.screen.editor.setTile(self.x, self.y, self.old_id),
            .region => ui_systems.screen.editor.setRegion(self.x, self.y, self.old_id),
            .entity => ui_systems.screen.editor.setObject(Entity, self.x, self.y, self.old_id),
            .enemy => ui_systems.screen.editor.setObject(Enemy, self.x, self.y, self.old_id),
            .portal => ui_systems.screen.editor.setObject(Portal, self.x, self.y, self.old_id),
            .container => ui_systems.screen.editor.setObject(Container, self.x, self.y, self.old_id),
        }
    }
};

const MultiPlace = struct {
    places: []Place,

    pub fn execute(self: MultiPlace) void {
        for (self.places) |p| p.execute();
    }

    pub fn unexecute(self: MultiPlace) void {
        for (self.places) |p| p.unexecute();
    }
};

const CommandQueue = struct {
    command_list: std.ArrayListUnmanaged(EditorCommand) = .empty,
    current_position: usize = 0,

    pub fn clear(self: *CommandQueue) void {
        self.command_list.clearRetainingCapacity();
        self.current_position = 0;
    }

    pub fn deinit(self: *CommandQueue) void {
        for (self.command_list.items) |cmd| if (cmd == .multi_place) main.allocator.free(cmd.multi_place.places);
        self.command_list.deinit(main.allocator);
    }

    pub fn addCommand(self: *CommandQueue, command: EditorCommand) void {
        var i = self.command_list.items.len;
        while (i > self.current_position) : (i -= 1) {
            _ = self.command_list.pop();
        }

        switch (command) {
            inline else => |c| c.execute(),
        }

        self.command_list.append(main.allocator, command) catch return;
        self.current_position += 1;
    }

    pub fn undo(self: *CommandQueue) void {
        if (self.current_position == 0) return;

        self.current_position -= 1;

        const command = self.command_list.items[self.current_position];
        switch (command) {
            inline else => |c| c.unexecute(),
        }
    }

    pub fn redo(self: *CommandQueue) void {
        if (self.current_position == self.command_list.items.len) return;

        const command = self.command_list.items[self.current_position];
        switch (command) {
            inline else => |c| c.execute(),
        }

        self.current_position += 1;
    }
};

const Position = struct { x: u16, y: u16 };

const MapEditorScreen = @This();
const layers_text = [_][]const u8{ "Tiles", "Entities", "Enemies", "Portal", "Container", "Regions" };
const layers = [_]Layer{ .ground, .entity, .enemy, .portal, .container, .region };

const sizes_text = [_][]const u8{ "64x64", "128x128", "256x256", "512x512", "1024x1024", "2048x2048" };
const sizes = [_]u16{ 64, 128, 256, 512, 1024, 2048 };

const control_decor_w = 220;
const control_decor_h = 440;

const palette_decor_w = 200;
const palette_decor_h = 400;

const dropdown_w = 200;
const dropdown_h = 130;

next_map_ids: struct {
    entity: u32 = 0,
    enemy: u32 = 0,
    portal: u32 = 0,
    container: u32 = 0,
} = .{},
editor_ready: bool = false,

map_size: u16 = 64,
map_tile_data: []MapEditorTile = &.{},

command_queue: CommandQueue = .{},

action: EditorAction = .none,
active_layer: Layer = .ground,
selected: struct {
    entity: u16 = defaultType(.entity),
    enemy: u16 = defaultType(.enemy),
    portal: u16 = defaultType(.portal),
    container: u16 = defaultType(.container),
    ground: u16 = defaultType(.ground),
    region: u16 = defaultType(.region),
} = .{},
selected_tiles: []Position = &.{},

brush_size: f32 = 0.5,
random_chance: f32 = 0.01,

selection_image: *Image = undefined,
selection_start_point: ?Position = null,
selection_end_point: ?Position = null,
fps_text: *Text = undefined,
controls_container: *UiContainer = undefined,
map_size_dropdown: *Dropdown = undefined,
palette_decor: *Image = undefined,
palette_containers: struct {
    ground: *ScrollableContainer,
    entity: *ScrollableContainer,
    enemy: *ScrollableContainer,
    portal: *ScrollableContainer,
    container: *ScrollableContainer,
    region: *ScrollableContainer,
} = undefined,
layer_dropdown: *Dropdown = undefined,

place_key: Settings.Button = .{ .mouse = .left },
sample_key: Settings.Button = .{ .mouse = .middle },
erase_key: Settings.Button = .{ .mouse = .right },
random_key: Settings.Button = .{ .key = .t },
undo_key: Settings.Button = .{ .key = .u },
redo_key: Settings.Button = .{ .key = .r },
fill_key: Settings.Button = .{ .key = .f },
wand_key: Settings.Button = .{ .key = .m },
curve_key: Settings.Button = .{ .key = .l },
unselect_key: Settings.Button = .{ .key = .l },

start_x_override: u16 = std.math.maxInt(u16),
start_y_override: u16 = std.math.maxInt(u16),

last_press: i64 = -1,
last_update: i64 = -1,
last_move_select: i64 = -1,

pub fn nextMapIdForType(self: *MapEditorScreen, comptime T: type) *u32 {
    return switch (T) {
        Entity => &self.next_map_ids.entity,
        Enemy => &self.next_map_ids.enemy,
        Portal => &self.next_map_ids.portal,
        Container => &self.next_map_ids.container,
        else => @compileError("Invalid type"),
    };
}

pub fn init(self: *MapEditorScreen) !void {
    const button_data_base = assets.getUiData("button_base", 0);
    const button_data_hover = assets.getUiData("button_hover", 0);
    const button_data_press = assets.getUiData("button_press", 0);

    const button_width = 90.0;
    const button_height = 35.0;
    const button_inset = 15.0;
    const button_pad_w = 10.0;
    const button_pad_h = 5.0;

    const key_mapper_width = 35.0;
    const key_mapper_height = 35.0;

    const selection = assets.getUiData("editor_selection", 0);
    self.selection_image = try element.create(Image, .{
        .base = .{
            .x = 0,
            .y = 0,
            .visible = false,
            .event_policy = .{
                .pass_press = false,
                .pass_release = false,
                .pass_move = false,
                .pass_scroll = false,
            },
        },
        .image_data = .{ .nine_slice = .fromAtlasData(selection, 0, 0, 1, 1, 1, 1, 1.0) },
    });

    self.fps_text = try element.create(Text, .{
        .base = .{ .x = 5 + control_decor_w + 5, .y = 5 },
        .text_data = .{
            .text = "",
            .size = 12,
            .text_type = .bold,
            .hori_align = .left,
            .max_width = control_decor_w,
            .max_chars = 64,
            .color = 0x6F573F,
        },
    });

    self.controls_container = try element.create(UiContainer, .{ .base = .{ .x = 5, .y = 5 } });

    const collapsed_icon_base = assets.getUiData("dropdown_collapsed_icon_base", 0);
    const collapsed_icon_hover = assets.getUiData("dropdown_collapsed_icon_hover", 0);
    const collapsed_icon_press = assets.getUiData("dropdown_collapsed_icon_press", 0);
    const extended_icon_base = assets.getUiData("dropdown_extended_icon_base", 0);
    const extended_icon_hover = assets.getUiData("dropdown_extended_icon_hover", 0);
    const extended_icon_press = assets.getUiData("dropdown_extended_icon_press", 0);
    const dropdown_main_color_base = assets.getUiData("dropdown_main_color_base", 0);
    const dropdown_main_color_hover = assets.getUiData("dropdown_main_color_hover", 0);
    const dropdown_main_color_press = assets.getUiData("dropdown_main_color_press", 0);
    const dropdown_alt_color_base = assets.getUiData("dropdown_alt_color_base", 0);
    const dropdown_alt_color_hover = assets.getUiData("dropdown_alt_color_hover", 0);
    const dropdown_alt_color_press = assets.getUiData("dropdown_alt_color_press", 0);
    const title_background = assets.getUiData("dropdown_title_background", 0);
    const background_data = assets.getUiData("dropdown_background", 0);

    const scroll_background_data = assets.getUiData("scroll_background", 0);
    const scroll_knob_base = assets.getUiData("scroll_wheel_base", 0);
    const scroll_knob_hover = assets.getUiData("scroll_wheel_hover", 0);
    const scroll_knob_press = assets.getUiData("scroll_wheel_press", 0);
    const scroll_decor_data = assets.getUiData("scrollbar_decor", 0);

    self.map_size_dropdown = try element.create(Dropdown, .{
        .base = .{ .x = 5, .y = 5 + control_decor_h + 5 },
        .w = control_decor_w,
        .container_inlay_x = 8,
        .container_inlay_y = 2,
        .button_data_collapsed = .fromImageData(collapsed_icon_base, collapsed_icon_hover, collapsed_icon_press),
        .button_data_extended = .fromImageData(extended_icon_base, extended_icon_hover, extended_icon_press),
        .main_background_data = .fromNineSlices(dropdown_main_color_base, dropdown_main_color_hover, dropdown_main_color_press, dropdown_w, 40, 0, 0, 2, 2, 1.0),
        .alt_background_data = .fromNineSlices(dropdown_alt_color_base, dropdown_alt_color_hover, dropdown_alt_color_press, dropdown_w, 40, 0, 0, 2, 2, 1.0),
        .title_data = .{ .nine_slice = .fromAtlasData(title_background, dropdown_w, dropdown_h, 20, 20, 4, 4, 1.0) },
        .title_text = .{
            .text = "Map Size",
            .size = 20,
            .text_type = .bold_italic,
        },
        .background_data = .{ .nine_slice = .fromAtlasData(background_data, dropdown_w, dropdown_h, 20, 8, 4, 4, 1.0) },
        .scroll_w = 4,
        .scroll_h = dropdown_h - 10,
        .scroll_side_x_rel = -6,
        .scroll_side_y_rel = 0,
        .scroll_decor_image_data = .{ .nine_slice = .fromAtlasData(scroll_background_data, 4, dropdown_h - 10, 0, 0, 2, 2, 1.0) },
        .scroll_knob_image_data = .fromNineSlices(scroll_knob_base, scroll_knob_hover, scroll_knob_press, 10, 16, 4, 4, 1, 2, 1.0),
        .scroll_side_decor_image_data = .{ .nine_slice = .fromAtlasData(scroll_decor_data, 6, dropdown_h - 10, 0, 41, 6, 3, 1.0) },
        .selected_index = 0,
    });

    for (sizes_text) |size| {
        const line = try self.map_size_dropdown.createChild(sizeCallback);
        _ = try line.container.createChild(Text, .{
            .base = .{ .x = 0, .y = 0 },
            .text_data = .{
                .text = size,
                .size = 20,
                .text_type = .bold,
                .hori_align = .middle,
                .vert_align = .middle,
                .max_width = line.background_data.width(.none),
                .max_height = line.background_data.height(.none),
            },
        });
    }

    const background_decor = assets.getUiData("tooltip_background", 0);
    _ = try self.controls_container.createChild(Image, .{
        .base = .{ .x = 0, .y = 0 },
        .image_data = .{ .nine_slice = .fromAtlasData(background_decor, control_decor_w, control_decor_h, 34, 34, 1, 1, 1.0) },
    });

    _ = try self.controls_container.createChild(Button, .{
        .base = .{ .x = button_inset, .y = button_inset },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 26, 19, 1, 1, 1.0),
        .text_data = .{
            .text = "Open",
            .size = 16,
            .text_type = .bold,
        },
        .userdata = self,
        .pressCallback = openCallback,
    });

    _ = try self.controls_container.createChild(Button, .{
        .base = .{ .x = button_inset + button_pad_w + button_width, .y = button_inset },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 26, 19, 1, 1, 1.0),
        .text_data = .{
            .text = "Save",
            .size = 16,
            .text_type = .bold,
        },
        .userdata = self,
        .pressCallback = saveCallback,
    });

    _ = try self.controls_container.createChild(Button, .{
        .base = .{ .x = button_inset, .y = button_inset + button_pad_h + button_height },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 26, 19, 1, 1, 1.0),
        .text_data = .{
            .text = "Test",
            .size = 16,
            .text_type = .bold,
        },
        .userdata = self,
        .pressCallback = testCallback,
    });

    _ = try self.controls_container.createChild(Button, .{
        .base = .{ .x = button_inset + button_pad_w + button_width, .y = button_inset + button_pad_h + button_height },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 26, 19, 1, 1, 1.0),
        .text_data = .{
            .text = "Exit",
            .size = 16,
            .text_type = .bold,
        },
        .userdata = self,
        .pressCallback = exitCallback,
    });

    _ = try self.controls_container.createChild(KeyMapper, .{
        .base = .{ .x = button_inset, .y = button_inset + (button_pad_h + button_height) * 2 },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, key_mapper_width, key_mapper_height, 26, 19, 1, 1, 1.0),
        .title_text_data = .{
            .text = "Place",
            .size = 12,
            .text_type = .bold,
        },
        .settings_button = &self.place_key,
        .setKeyCallback = noAction,
    });
    _ = try self.controls_container.createChild(KeyMapper, .{
        .base = .{ .x = button_inset + button_pad_w + button_width, .y = button_inset + (button_pad_h + button_height) * 2 },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, key_mapper_width, key_mapper_height, 26, 19, 1, 1, 1.0),
        .title_text_data = .{
            .text = "Sample",
            .size = 12,
            .text_type = .bold,
        },
        .settings_button = &self.sample_key,
        .setKeyCallback = noAction,
    });
    _ = try self.controls_container.createChild(KeyMapper, .{
        .base = .{ .x = button_inset, .y = button_inset + (button_pad_h + button_height) * 3 },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, key_mapper_width, key_mapper_height, 26, 19, 1, 1, 1.0),
        .title_text_data = .{
            .text = "Erase",
            .size = 12,
            .text_type = .bold,
        },
        .settings_button = &self.erase_key,
        .setKeyCallback = noAction,
    });
    _ = try self.controls_container.createChild(KeyMapper, .{
        .base = .{ .x = button_inset + button_pad_w + button_width, .y = button_inset + (button_pad_h + button_height) * 3 },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, key_mapper_width, key_mapper_height, 26, 19, 1, 1, 1.0),
        .title_text_data = .{
            .text = "Random",
            .size = 12,
            .text_type = .bold,
        },
        .settings_button = &self.random_key,
        .setKeyCallback = noAction,
    });
    _ = try self.controls_container.createChild(KeyMapper, .{
        .base = .{ .x = button_inset, .y = button_inset + (button_pad_h + button_height) * 4 },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, key_mapper_width, key_mapper_height, 26, 19, 1, 1, 1.0),
        .title_text_data = .{
            .text = "Undo",
            .size = 12,
            .text_type = .bold,
        },
        .settings_button = &self.undo_key,
        .setKeyCallback = noAction,
    });
    _ = try self.controls_container.createChild(KeyMapper, .{
        .base = .{ .x = button_inset + button_pad_w + button_width, .y = button_inset + (button_pad_h + button_height) * 4 },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, key_mapper_width, key_mapper_height, 26, 19, 1, 1, 1.0),
        .title_text_data = .{
            .text = "Redo",
            .size = 12,
            .text_type = .bold,
        },
        .settings_button = &self.redo_key,
        .setKeyCallback = noAction,
    });

    _ = try self.controls_container.createChild(KeyMapper, .{
        .base = .{ .x = button_inset, .y = button_inset + (button_pad_h + button_height) * 5 },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, key_mapper_width, key_mapper_height, 26, 19, 1, 1, 1.0),
        .title_text_data = .{
            .text = "Fill",
            .size = 12,
            .text_type = .bold,
        },
        .settings_button = &self.fill_key,
        .setKeyCallback = noAction,
    });

    _ = try self.controls_container.createChild(KeyMapper, .{
        .base = .{ .x = button_inset + button_pad_w + button_width, .y = button_inset + (button_pad_h + button_height) * 5 },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, key_mapper_width, key_mapper_height, 26, 19, 1, 1, 1.0),
        .title_text_data = .{
            .text = "Wand",
            .size = 12,
            .text_type = .bold,
        },
        .settings_button = &self.wand_key,
        .setKeyCallback = noAction,
    });

    _ = try self.controls_container.createChild(KeyMapper, .{
        .base = .{ .x = button_inset, .y = button_inset + (button_pad_h + button_height) * 6 },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, key_mapper_width, key_mapper_height, 26, 19, 1, 1, 1.0),
        .title_text_data = .{
            .text = "Curve",
            .size = 12,
            .text_type = .bold,
        },
        .settings_button = &self.curve_key,
        .setKeyCallback = noAction,
    });

    _ = try self.controls_container.createChild(KeyMapper, .{
        .base = .{ .x = button_inset + button_pad_w + button_width, .y = button_inset + (button_pad_h + button_height) * 6 },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, key_mapper_width, key_mapper_height, 26, 19, 1, 1, 1.0),
        .title_text_data = .{
            .text = "Unselect",
            .size = 12,
            .text_type = .bold,
        },
        .settings_button = &self.unselect_key,
        .setKeyCallback = noAction,
    });

    const slider_background_data = assets.getUiData("slider_background", 0);
    const knob_data_base = assets.getUiData("slider_knob_base", 0);
    const knob_data_hover = assets.getUiData("slider_knob_hover", 0);
    const knob_data_press = assets.getUiData("slider_knob_press", 0);

    const slider_w = control_decor_w - button_inset * 2 - 5;
    const slider_h = button_height - 5 - 10;
    const knob_size = button_height - 5;

    _ = try self.controls_container.createChild(Slider, .{
        .base = .{ .x = button_inset + 2, .y = (button_pad_h + button_height) * 8 },
        .w = slider_w,
        .h = slider_h,
        .min_value = 0.5,
        .max_value = 9.9,
        .decor_image_data = .{ .nine_slice = .fromAtlasData(slider_background_data, slider_w, slider_h, 6, 6, 1, 1, 1.0) },
        .knob_image_data = .fromNineSlices(knob_data_base, knob_data_hover, knob_data_press, knob_size, knob_size, 12, 12, 1, 1, 1.0),
        .target = &self.brush_size,
        .title_text_data = .{
            .text = "Brush Size",
            .size = 12,
            .text_type = .bold,
        },
        .value_text_data = .{
            .text = "",
            .size = 10,
            .text_type = .bold,
            .max_chars = 64,
        },
    });

    _ = try self.controls_container.createChild(Slider, .{
        .base = .{ .x = button_inset + 2, .y = (button_pad_h + button_height) * 9 + 20 },
        .w = slider_w,
        .h = slider_h,
        .min_value = 0.01,
        .max_value = 1.0,
        .decor_image_data = .{ .nine_slice = .fromAtlasData(slider_background_data, slider_w, slider_h, 6, 6, 1, 1, 1.0) },
        .knob_image_data = .fromNineSlices(knob_data_base, knob_data_hover, knob_data_press, knob_size, knob_size, 12, 12, 1, 1, 1.0),
        .target = &self.random_chance,
        .title_text_data = .{
            .text = "Random Chance",
            .size = 12,
            .text_type = .bold,
        },
        .value_text_data = .{
            .text = "",
            .size = 10,
            .text_type = .bold,
            .max_chars = 64,
        },
    });

    self.palette_decor = try element.create(Image, .{
        .base = .{ .x = main.camera.width - palette_decor_w - 5, .y = 5 },
        .image_data = .{ .nine_slice = .fromAtlasData(background_decor, palette_decor_w, palette_decor_h, 34, 34, 1, 1, 1.0) },
    });

    self.palette_containers.ground = try element.create(ScrollableContainer, .{
        .base = .{ .x = self.palette_decor.base.x + 8, .y = self.palette_decor.base.y + 9 },
        .scissor_w = palette_decor_w - 20 - 6,
        .scissor_h = palette_decor_h - 17,
        .scroll_x = self.palette_decor.base.x + palette_decor_w - 20 + 2,
        .scroll_y = self.palette_decor.base.y + 9,
        .scroll_w = 4,
        .scroll_h = palette_decor_h - 17,
        .scroll_side_x = self.palette_decor.base.x + palette_decor_w - 20 + 2 - 6,
        .scroll_side_y = self.palette_decor.base.y + 9,
        .scroll_decor_image_data = .{ .nine_slice = .fromAtlasData(scroll_background_data, 4, palette_decor_h - 17, 0, 0, 2, 2, 1.0) },
        .scroll_knob_image_data = .fromNineSlices(scroll_knob_base, scroll_knob_hover, scroll_knob_press, 10, 16, 4, 4, 1, 2, 1.0),
        .scroll_side_decor_image_data = .{ .nine_slice = .fromAtlasData(scroll_decor_data, 6, palette_decor_h - 17, 0, 41, 6, 3, 1.0) },
    });

    var tile_iter = game_data.ground.from_id.iterator();
    var i: isize = 0;
    while (tile_iter.next()) |entry| : (i += 1) {
        if (entry.key_ptr.* == Square.editor_tile) {
            i -= 1;
            continue;
        }

        var atlas_data = blk: {
            if (entry.value_ptr.textures.len <= 0) {
                std.log.err("Tile with data id {} has an empty texture list. Using error texture", .{entry.key_ptr.*});
                break :blk assets.error_data;
            }

            const tex = if (entry.value_ptr.textures.len == 1) entry.value_ptr.textures[0] else entry.value_ptr.textures[utils.rng.next() % entry.value_ptr.textures.len];

            if (assets.atlas_data.get(tex.sheet)) |data| {
                if (tex.index >= data.len) {
                    std.log.err("Could not find index {} for tile with data id {}. Using error texture", .{ tex.index, entry.key_ptr.* });
                    break :blk assets.error_data;
                }

                break :blk data[tex.index];
            } else {
                std.log.err("Could not find sheet {s} for tile with data id {}. Using error texture", .{ tex.sheet, entry.key_ptr.* });
                break :blk assets.error_data;
            }
        };

        if (atlas_data.tex_w <= 0 or atlas_data.tex_h <= 0) {
            std.log.err("Tile with data id {} has an empty texture. Using error texture", .{entry.key_ptr.*});
            atlas_data = assets.error_data;
        }

        _ = try self.palette_containers.ground.createChild(Button, .{
            .base = .{
                .x = f32i(@mod(i, 5) * 34),
                .y = f32i(@divFloor(i, 5) * 34),
            },
            .image_data = .{ .base = .{ .normal = .{ .atlas_data = atlas_data, .scale_x = 4.0, .scale_y = 4.0 } } },
            .userdata = entry.key_ptr,
            .pressCallback = groundClicked,
            .tooltip_text = .{
                .text = (game_data.ground.from_id.get(entry.key_ptr.*) orelse {
                    std.log.err("Could find name for tile with data id {}. Not adding to tile list", .{entry.key_ptr.*});
                    i -= 1;
                    continue;
                }).name,
                .size = 12,
                .text_type = .bold_italic,
            },
        });
    }

    try addObjectContainer(
        &self.palette_containers.entity,
        self.palette_decor.base.x,
        self.palette_decor.base.y,
        scroll_background_data,
        scroll_knob_base,
        scroll_knob_hover,
        scroll_knob_press,
        scroll_decor_data,
        game_data.EntityData,
        game_data.entity,
        entityClicked,
    );
    try addObjectContainer(
        &self.palette_containers.enemy,
        self.palette_decor.base.x,
        self.palette_decor.base.y,
        scroll_background_data,
        scroll_knob_base,
        scroll_knob_hover,
        scroll_knob_press,
        scroll_decor_data,
        game_data.EnemyData,
        game_data.enemy,
        enemyClicked,
    );
    try addObjectContainer(
        &self.palette_containers.portal,
        self.palette_decor.base.x,
        self.palette_decor.base.y,
        scroll_background_data,
        scroll_knob_base,
        scroll_knob_hover,
        scroll_knob_press,
        scroll_decor_data,
        game_data.PortalData,
        game_data.portal,
        portalClicked,
    );
    try addObjectContainer(
        &self.palette_containers.container,
        self.palette_decor.base.x,
        self.palette_decor.base.y,
        scroll_background_data,
        scroll_knob_base,
        scroll_knob_hover,
        scroll_knob_press,
        scroll_decor_data,
        game_data.ContainerData,
        game_data.container,
        containerClicked,
    );

    self.palette_containers.region = try element.create(ScrollableContainer, .{
        .base = .{ .x = self.palette_decor.base.x + 8, .y = self.palette_decor.base.y + 9, .visible = false },
        .scissor_w = palette_decor_w - 20 - 6,
        .scissor_h = palette_decor_h - 17,
        .scroll_x = self.palette_decor.base.x + palette_decor_w - 20 + 2,
        .scroll_y = self.palette_decor.base.y + 9,
        .scroll_w = 4,
        .scroll_h = palette_decor_h - 17,
        .scroll_side_x = self.palette_decor.base.x + palette_decor_w - 20 + 2 - 6,
        .scroll_side_y = self.palette_decor.base.y + 9,
        .scroll_decor_image_data = .{ .nine_slice = .fromAtlasData(scroll_background_data, 4, palette_decor_h - 17, 0, 0, 2, 2, 1.0) },
        .scroll_knob_image_data = .fromNineSlices(scroll_knob_base, scroll_knob_hover, scroll_knob_press, 10, 16, 4, 4, 1, 2, 1.0),
        .scroll_side_decor_image_data = .{ .nine_slice = .fromAtlasData(scroll_decor_data, 6, palette_decor_h - 17, 0, 41, 6, 3, 1.0) },
    });

    var region_iter = game_data.region.from_id.iterator();
    i = 0;
    while (region_iter.next()) |entry| : (i += 1) {
        _ = try self.palette_containers.region.createChild(Button, .{
            .base = .{ .x = f32i(@mod(i, 5) * 34), .y = f32i(@divFloor(i, 5) * 34) },
            .image_data = .{ .base = .{ .normal = .{
                .atlas_data = assets.generic_8x8,
                .scale_x = 4.0,
                .scale_y = 4.0,
                .alpha = 0.6,
                .color = entry.value_ptr.color,
                .color_intensity = 1.0,
            } } },
            .userdata = entry.key_ptr,
            .pressCallback = regionClicked,
            .tooltip_text = .{
                .text = entry.value_ptr.name,
                .size = 12,
                .text_type = .bold_italic,
            },
        });
    }

    self.layer_dropdown = try element.create(Dropdown, .{
        .base = .{ .x = self.palette_decor.base.x, .y = self.palette_decor.base.y + self.palette_decor.height() + 5 },
        .w = dropdown_w,
        .container_inlay_x = 8,
        .container_inlay_y = 2,
        .button_data_collapsed = .fromImageData(collapsed_icon_base, collapsed_icon_hover, collapsed_icon_press),
        .button_data_extended = .fromImageData(extended_icon_base, extended_icon_hover, extended_icon_press),
        .main_background_data = .fromNineSlices(dropdown_main_color_base, dropdown_main_color_hover, dropdown_main_color_press, dropdown_w, 40, 0, 0, 2, 2, 1.0),
        .alt_background_data = .fromNineSlices(dropdown_alt_color_base, dropdown_alt_color_hover, dropdown_alt_color_press, dropdown_w, 40, 0, 0, 2, 2, 1.0),
        .title_data = .{ .nine_slice = .fromAtlasData(title_background, dropdown_w, dropdown_h, 20, 20, 4, 4, 1.0) },
        .title_text = .{
            .text = "Layer",
            .size = 20,
            .text_type = .bold_italic,
        },
        .background_data = .{ .nine_slice = .fromAtlasData(background_data, dropdown_w, dropdown_h, 20, 8, 4, 4, 1.0) },
        .scroll_w = 4,
        .scroll_h = dropdown_h - 10,
        .scroll_side_x_rel = -6,
        .scroll_side_y_rel = 0,
        .scroll_decor_image_data = .{ .nine_slice = .fromAtlasData(scroll_background_data, 4, dropdown_h - 10, 0, 0, 2, 2, 1.0) },
        .scroll_knob_image_data = .fromNineSlices(scroll_knob_base, scroll_knob_hover, scroll_knob_press, 10, 16, 4, 4, 1, 2, 1.0),
        .scroll_side_decor_image_data = .{ .nine_slice = .fromAtlasData(scroll_decor_data, 6, dropdown_h - 10, 0, 41, 6, 3, 1.0) },
        .selected_index = 0,
    });

    for (layers_text) |layer| {
        const layer_line = try self.layer_dropdown.createChild(layerCallback);
        _ = try layer_line.container.createChild(Text, .{
            .base = .{ .x = 0, .y = 0 },
            .text_data = .{
                .text = layer,
                .size = 20,
                .text_type = .bold,
                .hori_align = .middle,
                .vert_align = .middle,
                .max_width = layer_line.background_data.width(.none),
                .max_height = layer_line.background_data.height(.none),
            },
        });
    }

    if (ui_systems.last_map_data) |data| {
        var fbs = std.io.fixedBufferStream(data);
        try self.loadMap(fbs.reader());
    } else self.initialize();
}

fn addObjectContainer(
    container: **ScrollableContainer,
    px: f32,
    py: f32,
    scroll_background_data: assets.AtlasData,
    scroll_knob_base: assets.AtlasData,
    scroll_knob_hover: assets.AtlasData,
    scroll_knob_press: assets.AtlasData,
    scroll_decor_data: assets.AtlasData,
    comptime T: type,
    data: game_data.Maps(T),
    callback: *const fn (?*anyopaque) void,
) !void {
    container.* = try element.create(ScrollableContainer, .{
        .base = .{ .x = px + 8, .y = py + 9, .visible = false },
        .scissor_w = palette_decor_w - 20 - 6,
        .scissor_h = palette_decor_h - 17,
        .scroll_x = px + palette_decor_w - 20 + 2,
        .scroll_y = py + 9,
        .scroll_w = 4,
        .scroll_h = palette_decor_h - 17,
        .scroll_side_x = px + palette_decor_w - 20 + 2 - 6,
        .scroll_side_y = py + 9,
        .scroll_decor_image_data = .{ .nine_slice = .fromAtlasData(scroll_background_data, 4, palette_decor_h - 17, 0, 0, 2, 2, 1.0) },
        .scroll_knob_image_data = .fromNineSlices(scroll_knob_base, scroll_knob_hover, scroll_knob_press, 10, 16, 4, 4, 1, 2, 1.0),
        .scroll_side_decor_image_data = .{ .nine_slice = .fromAtlasData(scroll_decor_data, 6, palette_decor_h - 17, 0, 41, 6, 3, 1.0) },
    });

    var iter = data.from_id.iterator();
    var i: usize = 0;
    while (iter.next()) |entry| {
        // region placeholder
        if (T == game_data.EntityData and entry.key_ptr.* == 65534) continue;

        defer i += 1;

        var atlas_data = blk: {
            const tex = texBlk: {
                if (@hasField(@TypeOf(entry.value_ptr.*), "texture"))
                    break :texBlk entry.value_ptr.texture;

                const tex_list = entry.value_ptr.textures;
                if (tex_list.len <= 0) {
                    std.log.err("Object with data id {} has an empty texture list. Using error texture", .{entry.key_ptr.*});
                    break :blk assets.error_data;
                }

                break :texBlk tex_list[utils.rng.next() % tex_list.len];
            };

            if (assets.anim_enemies.get(tex.sheet)) |anim_data| {
                if (tex.index >= anim_data.len) {
                    std.log.err("Could not find index {} for object with data id {}. Using error texture", .{ tex.index, entry.key_ptr.* });
                    break :blk assets.error_data;
                }

                break :blk anim_data[tex.index].walk_anims[0];
            } else if (assets.atlas_data.get(tex.sheet)) |atlas_data| {
                if (tex.index >= atlas_data.len) {
                    std.log.err("Could not find index {} for object with data id {}. Using error texture", .{ tex.index, entry.key_ptr.* });
                    break :blk assets.error_data;
                }

                break :blk atlas_data[tex.index];
            } else if (assets.walls.get(tex.sheet)) |wall_data| {
                if (tex.index >= wall_data.len) {
                    std.log.err("Could not find index {} for wall with data id {}. Using error texture", .{ tex.index, entry.key_ptr.* });
                    break :blk assets.error_data_wall.base;
                }

                break :blk wall_data[tex.index].base;
            } else {
                std.log.err("Could not find sheet {s} for object with data id {}. Using error texture", .{ tex.sheet, entry.key_ptr.* });
                break :blk if (@hasField(@TypeOf(entry.value_ptr.*), "is_wall") and entry.value_ptr.is_wall)
                    assets.error_data_wall.base
                else
                    assets.error_data;
            }
        };

        if (atlas_data.tex_w <= 0 or atlas_data.tex_h <= 0) {
            std.log.err("Object with data id {} has an empty texture. Using error texture", .{entry.key_ptr.*});
            atlas_data = assets.error_data;
        }

        const scale = 8.0 / @max(atlas_data.width(), atlas_data.height()) * 3.0;

        _ = try container.*.createChild(Button, .{
            .base = .{
                .x = f32i(@mod(i, 5) * 32) + (32 - atlas_data.width() * scale) / 2.0,
                .y = f32i(@divFloor(i, 5) * 32) + (32 - atlas_data.height() * scale) / 2.0,
            },
            .image_data = .{ .base = .{ .normal = .{ .atlas_data = atlas_data, .scale_x = scale, .scale_y = scale } } },
            .userdata = entry.key_ptr,
            .pressCallback = callback,
            .tooltip_text = .{
                .text = entry.value_ptr.name,
                .size = 12,
                .text_type = .bold_italic,
            },
        });
    }
}

fn groundClicked(ud: ?*anyopaque) void {
    ui_systems.screen.editor.selected.ground = @as(*u16, @alignCast(@ptrCast(ud))).*;
}

fn entityClicked(ud: ?*anyopaque) void {
    ui_systems.screen.editor.selected.entity = @as(*u16, @alignCast(@ptrCast(ud))).*;
}

fn enemyClicked(ud: ?*anyopaque) void {
    ui_systems.screen.editor.selected.enemy = @as(*u16, @alignCast(@ptrCast(ud))).*;
}

fn portalClicked(ud: ?*anyopaque) void {
    ui_systems.screen.editor.selected.portal = @as(*u16, @alignCast(@ptrCast(ud))).*;
}

fn containerClicked(ud: ?*anyopaque) void {
    ui_systems.screen.editor.selected.container = @as(*u16, @alignCast(@ptrCast(ud))).*;
}

fn regionClicked(ud: ?*anyopaque) void {
    ui_systems.screen.editor.selected.region = @as(*u8, @alignCast(@ptrCast(ud))).*;
}

fn sizeCallback(dc: *DropdownContainer) void {
    const screen = ui_systems.screen.editor;
    screen.map_size = sizes[dc.index];
    screen.initialize();
}

fn layerCallback(dc: *DropdownContainer) void {
    const next_layer = layers[dc.index];
    const screen = ui_systems.screen.editor;
    screen.active_layer = next_layer;
    inline for (@typeInfo(@TypeOf(screen.palette_containers)).@"struct".fields) |field| {
        @field(screen.palette_containers, field.name).base.visible = false;
    }
    switch (next_layer) {
        inline else => |tag| @field(screen.palette_containers, @tagName(tag)).base.visible = true,
    }
}

fn noAction(_: *KeyMapper) void {}

fn initialize(self: *MapEditorScreen) void {
    map.dispose();
    map.setMapInfo(.{ .width = self.map_size, .height = self.map_size, .bg_color = 0, .bg_intensity = 0.15 });
    self.command_queue.clear();

    self.map_tile_data = if (self.map_tile_data.len == 0)
        main.allocator.alloc(MapEditorTile, @as(u32, self.map_size) * @as(u32, self.map_size)) catch return
    else
        main.allocator.realloc(self.map_tile_data, @as(u32, self.map_size) * @as(u32, self.map_size)) catch return;

    @memset(self.map_tile_data, MapEditorTile{});

    const center = f32i(self.map_size) / 2.0;

    {
        map.square_lock.lock();
        defer map.square_lock.unlock();
        for (0..self.map_size) |y| for (0..self.map_size) |x|
            Square.addToMap(.{
                .x = f32i(x) + 0.5,
                .y = f32i(y) + 0.5,
                .data_id = Square.editor_tile,
            });
    }

    map.info.player_map_id = std.math.maxInt(u32) - 1;
    Player.addToMap(.{
        .x = if (self.start_x_override == std.math.maxInt(u16)) center else f32i(self.start_x_override),
        .y = if (self.start_y_override == std.math.maxInt(u16)) center else f32i(self.start_y_override),
        .map_id = map.info.player_map_id,
        .data_id = 0,
        .speed = 300,
    });

    main.editing_map = true;
    self.start_x_override = std.math.maxInt(u16);
    self.start_y_override = std.math.maxInt(u16);
}

fn loadMap(screen: *MapEditorScreen, data_reader: anytype) !void {
    var arena: std.heap.ArenaAllocator = .init(main.allocator);
    defer arena.deinit();
    const parsed_map = try map_data.parseMap(data_reader, &arena);
    screen.start_x_override = parsed_map.x + @divFloor(parsed_map.w, 2);
    screen.start_y_override = parsed_map.y + @divFloor(parsed_map.h, 2);
    screen.map_size = utils.nextPowerOfTwo(@max(parsed_map.x + parsed_map.w, parsed_map.y + parsed_map.h));
    screen.initialize();

    for (parsed_map.tiles, 0..) |tile, i| {
        const ux: u16 = @intCast(i % parsed_map.w + parsed_map.x);
        const uy: u16 = @intCast(@divFloor(i, parsed_map.w) + parsed_map.y);
        if (tile.ground_name.len > 0) screen.setTile(ux, uy, game_data.ground.from_name.get(tile.ground_name).?.id);
        if (tile.region_name.len > 0) screen.setRegion(ux, uy, game_data.region.from_name.get(tile.region_name).?.id);
        if (tile.entity_name.len > 0) screen.setObject(Entity, ux, uy, game_data.entity.from_name.get(tile.entity_name).?.id);
        if (tile.enemy_name.len > 0) screen.setObject(Enemy, ux, uy, game_data.enemy.from_name.get(tile.enemy_name).?.id);
        if (tile.portal_name.len > 0) screen.setObject(Portal, ux, uy, game_data.portal.from_name.get(tile.portal_name).?.id);
        if (tile.container_name.len > 0) screen.setObject(Container, ux, uy, game_data.container.from_name.get(tile.container_name).?.id);
    }
}

// for easier error handling
fn openInner(screen: *MapEditorScreen) !void {
    // TODO: popup for save

    const file_path = try nfd.openFileDialog("map", null);
    if (file_path) |path| {
        defer nfd.freePath(path);
        const file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();
        try screen.loadMap(file.reader());
    }
}

fn openCallback(ud: ?*anyopaque) void {
    openInner(@alignCast(@ptrCast(ud.?))) catch |e| {
        std.log.err("Error while parsing map: {}", .{e});
        if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace.*);
    };
}

fn tileBounds(tiles: []MapEditorTile) struct { min_x: u16, max_x: u16, min_y: u16, max_y: u16 } {
    var min_x = map.info.width;
    var min_y = map.info.height;
    var max_x: u16 = 0;
    var max_y: u16 = 0;

    for (0..map.info.height) |y| {
        for (0..map.info.width) |x| {
            const map_tile = tiles[@intCast(y * map.info.width + x)];
            inline for (@typeInfo(MapEditorTile).@"struct".fields) |field| {
                if (comptime std.mem.eql(u8, field.name, "object_id"))
                    continue;

                if (@field(map_tile, field.name) != @as(*const field.type, @ptrCast(@alignCast(field.default_value.?))).*) {
                    const ux: u16 = @intCast(x);
                    const uy: u16 = @intCast(y);

                    min_x = @min(min_x, ux);
                    min_y = @min(min_y, uy);
                    max_x = @max(max_x, ux);
                    max_y = @max(max_y, uy);
                    break;
                }
            }
        }
    }

    return .{ .min_x = @intCast(min_x), .min_y = @intCast(min_y), .max_x = @intCast(max_x + 1), .max_y = @intCast(max_y + 1) };
}

pub fn indexOfTile(tiles: []const map_data.Tile, value: map_data.Tile) ?usize {
    tileLoop: for (tiles, 0..) |tile, i| {
        inline for (@typeInfo(map_data.Tile).@"struct".fields) |field| {
            if (!std.mem.eql(u8, @field(tile, field.name), @field(value, field.name)))
                continue :tileLoop;
        }

        return i;
    }

    return null;
}

fn mapData(screen: *MapEditorScreen) ![]u8 {
    var data: std.ArrayListUnmanaged(u8) = .empty;
    defer data.deinit(main.allocator);

    const bounds = tileBounds(screen.map_tile_data);
    if (bounds.min_x >= bounds.max_x or bounds.min_y >= bounds.max_y)
        return error.InvalidMap;

    var writer = data.writer(main.allocator);
    try writer.writeInt(u8, 0, .little); // version
    try writer.writeInt(u16, bounds.min_x, .little);
    try writer.writeInt(u16, bounds.min_y, .little);
    try writer.writeInt(u16, bounds.max_x - bounds.min_x, .little);
    try writer.writeInt(u16, bounds.max_y - bounds.min_y, .little);

    var tiles: std.ArrayListUnmanaged(map_data.Tile) = .empty;
    defer tiles.deinit(main.allocator);

    for (bounds.min_y..bounds.max_y) |y| {
        for (bounds.min_x..bounds.max_x) |x| {
            const map_tile = screen.getTile(x, y);
            const tile: map_data.Tile = .{
                .ground_name = if (map_tile.ground == defaultType(.ground)) "" else game_data.ground.from_id.get(map_tile.ground).?.name,
                .region_name = if (map_tile.region == defaultType(.region)) "" else game_data.region.from_id.get(map_tile.region).?.name,
                .enemy_name = blk: {
                    map.object_lock.lock();
                    defer map.object_lock.unlock();
                    break :blk if (map.findObject(Enemy, map_tile.enemy, .con)) |e| e.data.name else "";
                },
                .entity_name = blk: {
                    map.object_lock.lock();
                    defer map.object_lock.unlock();
                    break :blk if (map.findObject(Entity, map_tile.entity, .con)) |e| e.data.name else "";
                },
                .portal_name = blk: {
                    map.object_lock.lock();
                    defer map.object_lock.unlock();
                    break :blk if (map.findObject(Portal, map_tile.portal, .con)) |p| p.data.name else "";
                },
                .container_name = blk: {
                    map.object_lock.lock();
                    defer map.object_lock.unlock();
                    break :blk if (map.findObject(Container, map_tile.container, .con)) |c| c.data.name else "";
                },
            };

            if (indexOfTile(tiles.items, tile) == null)
                try tiles.append(main.allocator, tile);
        }
    }

    try writer.writeInt(u16, @intCast(tiles.items.len), .little);
    const byte_len = tiles.items.len <= 256;

    for (tiles.items) |tile| {
        inline for (@typeInfo(map_data.Tile).@"struct".fields) |field| {
            try writer.writeInt(u16, @intCast(@field(tile, field.name).len), .little);
            try writer.writeAll(@field(tile, field.name));
        }
    }

    for (bounds.min_y..bounds.max_y) |y| {
        for (bounds.min_x..bounds.max_x) |x| {
            const map_tile = screen.getTile(x, y);
            const tile: map_data.Tile = .{
                .ground_name = if (map_tile.ground == defaultType(.ground)) "" else game_data.ground.from_id.get(map_tile.ground).?.name,
                .region_name = if (map_tile.region == defaultType(.region)) "" else game_data.region.from_id.get(map_tile.region).?.name,
                .enemy_name = blk: {
                    map.object_lock.lock();
                    defer map.object_lock.unlock();
                    break :blk if (map.findObject(Enemy, map_tile.enemy, .con)) |e| e.data.name else "";
                },
                .entity_name = blk: {
                    map.object_lock.lock();
                    defer map.object_lock.unlock();
                    break :blk if (map.findObject(Entity, map_tile.entity, .con)) |e| e.data.name else "";
                },
                .portal_name = blk: {
                    map.object_lock.lock();
                    defer map.object_lock.unlock();
                    break :blk if (map.findObject(Portal, map_tile.portal, .con)) |p| p.data.name else "";
                },
                .container_name = blk: {
                    map.object_lock.lock();
                    defer map.object_lock.unlock();
                    break :blk if (map.findObject(Container, map_tile.container, .con)) |c| c.data.name else "";
                },
            };

            if (indexOfTile(tiles.items, tile)) |idx| {
                if (byte_len)
                    try writer.writeInt(u8, @intCast(idx), .little)
                else
                    try writer.writeInt(u16, @intCast(idx), .little);
            } else @panic("No index found");
        }
    }

    var compressed_data: std.ArrayListUnmanaged(u8) = .empty;
    var fbs = std.io.fixedBufferStream(data.items);
    try std.compress.zlib.compress(fbs.reader(), compressed_data.writer(main.allocator), .{});
    return try compressed_data.toOwnedSlice(main.allocator);
}

fn saveInner(screen: *MapEditorScreen) !void {
    if (!main.editing_map) return;

    const file_path = nfd.saveFileDialog("map", null) catch return;
    if (file_path) |path| {
        defer nfd.freePath(path);

        const data = mapData(screen) catch {
            dialog.showDialog(.text, .{
                .title = "Map Error",
                .body = "Map was invalid",
            });
            return;
        };
        defer main.allocator.free(data);

        const file = try std.fs.createFileAbsolute(path, .{});
        defer file.close();
        try file.writeAll(data);
    }
}

fn saveCallback(ud: ?*anyopaque) void {
    saveInner(@alignCast(@ptrCast(ud.?))) catch |e| {
        std.log.err("Error while saving map: {}", .{e});
        if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace.*);
    };
}

fn exitCallback(ud: ?*anyopaque) void {
    const screen: *MapEditorScreen = @alignCast(@ptrCast(ud.?));
    const data = mapData(screen) catch |e| {
        std.log.err("Error while saving map (for testing): {}", .{e});
        if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace.*);
        return;
    };
    if (ui_systems.last_map_data) |last_map_data| main.allocator.free(last_map_data);
    ui_systems.last_map_data = data;

    if (main.character_list == null)
        ui_systems.switchScreen(.main_menu)
    else if (main.character_list.?.characters.len > 0)
        ui_systems.switchScreen(.char_select)
    else
        ui_systems.switchScreen(.char_create);
}

fn testCallback(ud: ?*anyopaque) void {
    if (main.character_list) |list| {
        if (list.servers.len > 0 and list.characters.len > 0) {
            const screen: *MapEditorScreen = @alignCast(@ptrCast(ud.?));

            const data = mapData(screen) catch |e| {
                std.log.err("Error while saving map (for testing): {}", .{e});
                if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace.*);
                return;
            };
            if (ui_systems.last_map_data) |last_map_data| main.allocator.free(last_map_data);
            ui_systems.last_map_data = data;
            ui_systems.is_testing = true;

            main.enterTest(list.servers[0], list.characters[0].char_id, data);
            return;
        }
    }
}

pub fn deinit(self: *MapEditorScreen) void {
    self.command_queue.deinit();

    element.destroy(self.selection_image);
    element.destroy(self.fps_text);
    element.destroy(self.palette_decor);
    inline for (@typeInfo(@TypeOf(self.palette_containers)).@"struct".fields) |field| {
        element.destroy(@field(self.palette_containers, field.name));
    }
    element.destroy(self.layer_dropdown);
    element.destroy(self.controls_container);
    element.destroy(self.map_size_dropdown);

    main.allocator.free(self.map_tile_data);
    main.allocator.free(self.selected_tiles);

    main.editing_map = false;
    map.dispose();

    main.allocator.destroy(self);
}

pub fn resize(self: *MapEditorScreen, w: f32, _: f32) void {
    const palette_x = w - palette_decor_w - 5;
    const cont_x = palette_x + 8;

    self.palette_decor.base.x = palette_x;
    inline for (@typeInfo(@TypeOf(self.palette_containers)).@"struct".fields) |field| {
        @field(self.palette_containers, field.name).base.x = cont_x;
    }
    self.layer_dropdown.base.x = palette_x;
    self.layer_dropdown.container.base.x = palette_x + self.layer_dropdown.container_inlay_x;
    self.layer_dropdown.container.container.base.x = palette_x + self.layer_dropdown.container_inlay_x;
    self.layer_dropdown.base.y = self.palette_decor.base.y + self.palette_decor.height() + 5;
}

pub fn hideRectSelect(self: *MapEditorScreen) void {
    self.selection_image.image_data.scaleWidth(0);
    self.selection_image.image_data.scaleHeight(0);
    self.selection_image.base.x = 0;
    self.selection_image.base.y = 0;
    self.selection_image.base.visible = false;
    self.selection_start_point = null;
    self.selection_end_point = null;
}

pub fn clearSelection(self: *MapEditorScreen) void {
    for (self.selected_tiles) |pos| {
        const square = map.getSquare(f32i(pos.x), f32i(pos.y), true, .ref) orelse continue;
        square.color = .{};
    }

    main.allocator.free(self.selected_tiles);
    self.selected_tiles = &.{};
}

fn processRectSelect(self: *MapEditorScreen) void {
    const start_point = self.selection_start_point orelse return;
    const end_point = self.selection_end_point orelse return;

    const min_y = @min(end_point.y, start_point.y);
    const max_y = @max(end_point.y, start_point.y);
    const min_x = @min(end_point.x, start_point.x);
    const max_x = @max(end_point.x, start_point.x);

    var positions: std.ArrayListUnmanaged(Position) = .empty;
    for (min_y..max_y + 1) |y| for (min_x..max_x + 1) |x|
        positions.append(main.allocator, .{ .x = @intCast(x), .y = @intCast(y) }) catch main.oomPanic();
    self.clearSelection();
    self.selected_tiles = positions.toOwnedSlice(main.allocator) catch main.oomPanic();
}

pub fn onMousePress(self: *MapEditorScreen, button: glfw.MouseButton) void {
    if (self.place_key == .mouse and button == self.place_key.mouse)
        self.action = .place
    else if (self.erase_key == .mouse and button == self.erase_key.mouse)
        self.action = .erase;

    (if (self.unselect_key == .mouse and button == self.unselect_key.mouse)
        self.handleAction(.unselect)
    else if (self.wand_key == .mouse and button == self.wand_key.mouse)
        self.handleAction(.wand)
    else if (self.undo_key == .mouse and button == self.undo_key.mouse)
        self.handleAction(.undo)
    else if (self.redo_key == .mouse and button == self.redo_key.mouse)
        self.handleAction(.redo)
    else if (self.sample_key == .mouse and button == self.sample_key.mouse)
        self.handleAction(.sample)
    else if (self.random_key == .mouse and button == self.random_key.mouse)
        self.handleAction(.random)
    else if (self.fill_key == .mouse and button == self.fill_key.mouse)
        self.handleAction(.fill)) catch |e| {
        std.log.err("Editor mouse press error: {}", .{e});
        return;
    };
}

pub fn onMouseRelease(self: *MapEditorScreen, button: glfw.MouseButton) void {
    if (self.place_key == .mouse and button == self.place_key.mouse or
        self.erase_key == .mouse and button == self.erase_key.mouse)
        self.action = .none;
}

pub fn onMouseMove(self: *MapEditorScreen, mouse_x: f32, mouse_y: f32) void {
    if (self.selection_start_point == null) return;

    self.selection_image.image_data.scaleWidth(mouse_x - self.selection_image.base.x);
    self.selection_image.image_data.scaleHeight(mouse_y - self.selection_image.base.y);
    const world_point = main.camera.screenToWorld(mouse_x, mouse_y);
    self.selection_end_point = .{ .x = u16f(world_point.x), .y = u16f(world_point.y) };

    if (main.current_time - self.last_move_select < move_select_delay_ms * std.time.us_per_ms) return;
    defer self.last_move_select = main.current_time;

    self.processRectSelect();
}

pub fn onKeyPress(self: *MapEditorScreen, key: glfw.Key) void {
    if (self.place_key == .key and key == self.place_key.key)
        self.action = .place
    else if (self.erase_key == .key and key == self.erase_key.key)
        self.action = .erase;

    if (key == .left_shift or key == .right_shift) {
        self.selection_image.image_data.scaleWidth(3);
        self.selection_image.image_data.scaleHeight(3);
        self.selection_image.base.x = input.mouse_x;
        self.selection_image.base.y = input.mouse_y;
        self.selection_image.base.visible = true;
        const world_point = main.camera.screenToWorld(input.mouse_x, input.mouse_y);
        self.selection_start_point = .{ .x = u16f(world_point.x), .y = u16f(world_point.y) };
    }

    (if (self.unselect_key == .key and key == self.unselect_key.key)
        self.handleAction(.unselect)
    else if (self.wand_key == .key and key == self.wand_key.key)
        self.handleAction(.wand)
    else if (self.undo_key == .key and key == self.undo_key.key)
        self.handleAction(.undo)
    else if (self.redo_key == .key and key == self.redo_key.key)
        self.handleAction(.redo)
    else if (self.sample_key == .key and key == self.sample_key.key)
        self.handleAction(.sample)
    else if (self.random_key == .key and key == self.random_key.key)
        self.handleAction(.random)
    else if (self.fill_key == .key and key == self.fill_key.key)
        self.handleAction(.fill)) catch |e| {
        std.log.err("Editor key press error: {}", .{e});
        return;
    };
}

pub fn onKeyRelease(self: *MapEditorScreen, key: glfw.Key) void {
    if (self.place_key == .key and key == self.place_key.key or
        self.erase_key == .key and key == self.erase_key.key)
        self.action = .none;

    if (key == .left_shift or key == .right_shift) {
        const world_point = main.camera.screenToWorld(input.mouse_x, input.mouse_y);
        self.selection_end_point = .{ .x = u16f(world_point.x), .y = u16f(world_point.y) };
        self.processRectSelect();
        self.hideRectSelect();
    }
}

fn getTile(self: *MapEditorScreen, x: usize, y: usize) MapEditorTile {
    return self.map_tile_data[y * self.map_size + x];
}

fn getTilePtr(self: *MapEditorScreen, x: usize, y: usize) *MapEditorTile {
    return &self.map_tile_data[y * self.map_size + x];
}

fn setTile(self: *MapEditorScreen, x: u16, y: u16, data_id: u16) void {
    const tile = self.getTilePtr(x, y);
    if (tile.ground == data_id) return;

    if (game_data.ground.from_id.get(data_id) == null) {
        std.log.err("Data not found for tile with data id {}, setting at x={}, y={} cancelled", .{ data_id, x, y });
        return;
    }

    tile.ground = data_id;

    map.square_lock.lock();
    defer map.square_lock.unlock();
    Square.addToMap(.{
        .x = f32i(x) + 0.5,
        .y = f32i(y) + 0.5,
        .data_id = data_id,
    });
}

fn setRegion(self: *MapEditorScreen, x: u16, y: u16, data_id: u16) void {
    const tile = self.getTilePtr(x, y);

    if (data_id == std.math.maxInt(u16)) {
        map.object_lock.lock();
        defer map.object_lock.unlock();
        _ = map.removeEntity(Entity, tile.region_map_id);
        tile.region_map_id = std.math.maxInt(u32);
    } else {
        const data = game_data.region.from_id.get(data_id) orelse {
            std.log.err("Data not found for region with data id {}, setting at x={}, y={} cancelled", .{ data_id, x, y });
            return;
        };

        if (tile.region_map_id != std.math.maxInt(u32)) {
            map.object_lock.lock();
            defer map.object_lock.unlock();
            if (map.findObject(Entity, tile.region_map_id, .con)) |obj| if (std.mem.eql(u8, obj.name orelse "", data.name)) return;
            _ = map.removeEntity(Entity, tile.region_map_id);
        }

        const next_map_id = self.nextMapIdForType(Entity);
        defer next_map_id.* += 1;
        tile.region_map_id = next_map_id.*;

        const duped_name = main.allocator.dupe(u8, data.name) catch main.oomPanic();
        var indicator: Entity = .{
            .x = f32i(x) + 0.5,
            .y = f32i(y) + 0.5,
            .map_id = next_map_id.*,
            .data_id = 0xFFFE,
            .name = duped_name,
            .render_color_override = data.color,
            .name_text_data = .{
                .text = undefined,
                .text_type = .bold,
                .size = 12,
            },
        };
        indicator.name_text_data.?.setText(duped_name);
        Entity.addToMap(indicator);

        tile.region = data_id;
    }
}

fn setObject(self: *MapEditorScreen, comptime ObjType: type, x: u16, y: u16, data_id: u16) void {
    const tile = self.getTilePtr(x, y);
    const field = switch (ObjType) {
        Entity => &tile.entity,
        Enemy => &tile.enemy,
        Portal => &tile.portal,
        Container => &tile.container,
        else => @compileError("Invalid type"),
    };

    if (data_id == std.math.maxInt(u16)) {
        map.object_lock.lock();
        defer map.object_lock.unlock();
        _ = map.removeEntity(ObjType, field.*);
        field.* = std.math.maxInt(u32);
    } else {
        const data = switch (ObjType) {
            Entity => game_data.entity,
            Enemy => game_data.enemy,
            Portal => game_data.portal,
            Container => game_data.container,
            else => @compileError("Invalid type"),
        }.from_id.get(data_id);
        if (data == null) {
            std.log.err("Data not found for object with data id {}, setting at x={}, y={} cancelled", .{ data_id, x, y });
            return;
        }

        if (field.* != std.math.maxInt(u32)) {
            map.object_lock.lock();
            defer map.object_lock.unlock();
            if (map.findObject(ObjType, field.*, .con)) |obj| if (obj.data_id == data_id) return;
            _ = map.removeEntity(ObjType, field.*);
        }

        const next_map_id = self.nextMapIdForType(ObjType);
        defer next_map_id.* += 1;

        field.* = next_map_id.*;

        const needs_lock = ObjType == Entity and data.?.is_wall;
        if (needs_lock) map.object_lock.lock();
        defer if (needs_lock) map.object_lock.unlock();
        ObjType.addToMap(.{
            .x = f32i(x) + 0.5,
            .y = f32i(y) + 0.5,
            .map_id = next_map_id.*,
            .data_id = data_id,
        });
    }
}

fn place(self: *MapEditorScreen, center_x: f32, center_y: f32, comptime place_type: enum { place, erase, random }) void {
    var places: std.ArrayListUnmanaged(Place) = .empty;

    const size_sqr = self.brush_size * self.brush_size;
    const sel_type = if (place_type == .erase) defaultType(self.active_layer) else switch (self.active_layer) {
        inline else => |tag| @field(self.selected, @tagName(tag)),
    };

    if (place_type != .erase and sel_type == defaultType(self.active_layer)) return;

    const size: f32 = f32i(self.map_size - 1);
    const y_left = usizef(@max(0, center_y - self.brush_size));
    const y_right = usizef(@min(size, @ceil(center_y + self.brush_size)));
    const x_left = usizef(@max(0, center_x - self.brush_size));
    const x_right = usizef(@min(size, @ceil(center_x + self.brush_size)));
    for (y_left..y_right) |y| for (x_left..x_right) |x| {
        const fx = f32i(x);
        const fy = f32i(y);
        const dx = center_x - fx;
        const dy = center_y - fy;
        if (dx * dx + dy * dy <= size_sqr) {
            if (place_type == .random and utils.rng.random().float(f32) > self.random_chance) continue;

            const old_id = blk: {
                const tile = self.map_tile_data[y * self.map_size + x];
                switch (self.active_layer) {
                    .ground => break :blk tile.ground,
                    .region => break :blk tile.region,
                    .entity => break :blk lockBlk: {
                        map.object_lock.lock();
                        defer map.object_lock.unlock();
                        break :lockBlk if (map.findObject(Entity, tile.entity, .con)) |e| e.data_id else std.math.maxInt(u16);
                    },
                    .enemy => break :blk lockBlk: {
                        map.object_lock.lock();
                        defer map.object_lock.unlock();
                        break :lockBlk if (map.findObject(Enemy, tile.enemy, .con)) |e| e.data_id else std.math.maxInt(u16);
                    },
                    .portal => break :blk lockBlk: {
                        map.object_lock.lock();
                        defer map.object_lock.unlock();
                        break :lockBlk if (map.findObject(Portal, tile.portal, .con)) |p| p.data_id else std.math.maxInt(u16);
                    },
                    .container => break :blk lockBlk: {
                        map.object_lock.lock();
                        defer map.object_lock.unlock();
                        break :lockBlk if (map.findObject(Container, tile.container, .con)) |c| c.data_id else std.math.maxInt(u16);
                    },
                }

                break :blk defaultType(self.active_layer);
            };

            if (sel_type == old_id) continue;

            places.append(main.allocator, .{
                .x = @intCast(x),
                .y = @intCast(y),
                .new_id = sel_type,
                .old_id = old_id,
                .layer = self.active_layer,
            }) catch main.oomPanic();
        }
    };

    if (places.items.len == 0) {
        places.deinit(main.allocator);
        return;
    }

    if (self.selected_tiles.len > 0) {
        var places_to_remove: std.ArrayListUnmanaged(usize) = .empty;
        defer places_to_remove.deinit(main.allocator);

        var idx: usize = 0;
        placeIter: for (places.items) |p| {
            for (self.selected_tiles) |pos| if (p.x == pos.x and p.y == pos.y) continue :placeIter;
            places_to_remove.append(main.allocator, idx) catch main.oomPanic();
            idx += 1;
        }

        var iter = std.mem.reverseIterator(places_to_remove.items);
        while (iter.next()) |i| _ = places.orderedRemove(i);
    }

    if (places.items.len <= 1) {
        if (places.items.len == 1) self.command_queue.addCommand(.{ .place = places.items[0] });
        places.deinit(main.allocator);
    } else {
        self.command_queue.addCommand(.{ .multi_place = .{ .places = places.toOwnedSlice(main.allocator) catch main.oomPanic() } });
    }
}

fn placesContain(places: []Place, x: i32, y: i32) bool {
    if (x < 0 or y < 0) return false;
    for (places) |p| if (p.x == x and p.y == y) return true;
    return false;
}

fn defaultType(layer: Layer) u16 {
    return switch (layer) {
        .ground => Square.editor_tile,
        else => std.math.maxInt(u16),
    };
}

fn typeAt(layer: Layer, screen: *MapEditorScreen, x: u16, y: u16) u16 {
    if (x < 0 or y < 0) return defaultType(layer);

    const map_tile = screen.getTile(x, y);
    return switch (layer) {
        .ground => map_tile.ground,
        .region => map_tile.region,
        .enemy => blk: {
            map.object_lock.lock();
            defer map.object_lock.unlock();
            break :blk if (map.findObject(Enemy, map_tile.enemy, .con)) |e| e.data_id else std.math.maxInt(u16);
        },
        .entity => blk: {
            map.object_lock.lock();
            defer map.object_lock.unlock();
            break :blk if (map.findObject(Entity, map_tile.entity, .con)) |e| e.data_id else std.math.maxInt(u16);
        },
        .portal => blk: {
            map.object_lock.lock();
            defer map.object_lock.unlock();
            break :blk if (map.findObject(Portal, map_tile.portal, .con)) |p| p.data_id else std.math.maxInt(u16);
        },
        .container => blk: {
            map.object_lock.lock();
            defer map.object_lock.unlock();
            break :blk if (map.findObject(Container, map_tile.container, .con)) |c| c.data_id else std.math.maxInt(u16);
        },
    };
}

fn inside(screen: *MapEditorScreen, places: []Place, x: i32, y: i32, layer: Layer, current_type: u16) bool {
    return x >= 0 and y >= 0 and x < screen.map_size and y < screen.map_size and
        !placesContain(places, x, y) and typeAt(layer, screen, @intCast(x), @intCast(y)) == current_type;
}

fn fill(screen: *MapEditorScreen, x: u16, y: u16, selection: bool) void {
    const FillData = struct { x1: i32, x2: i32, y: i32, dy: i32 };

    var places: std.ArrayListUnmanaged(Place) = .empty;

    const layer = screen.active_layer;
    const target_id = switch (screen.active_layer) {
        inline else => |tag| @field(screen.selected, @tagName(tag)),
    };

    const current_id = typeAt(layer, screen, x, y);
    if (!selection and (current_id == target_id or target_id == defaultType(layer))) return;

    var stack: std.ArrayListUnmanaged(FillData) = .empty;
    defer stack.deinit(main.allocator);

    stack.append(main.allocator, .{ .x1 = x, .x2 = x, .y = y, .dy = 1 }) catch main.oomPanic();
    stack.append(main.allocator, .{ .x1 = x, .x2 = x, .y = y - 1, .dy = -1 }) catch main.oomPanic();

    while (stack.items.len > 0) {
        const pop = stack.pop();
        var px = pop.x1;

        if (inside(screen, places.items, px, pop.y, layer, current_id)) {
            while (inside(screen, places.items, px - 1, pop.y, layer, current_id)) {
                places.append(main.allocator, .{
                    .x = @intCast(px - 1),
                    .y = @intCast(pop.y),
                    .new_id = target_id,
                    .old_id = current_id,
                    .layer = layer,
                }) catch main.oomPanic();
                px -= 1;
            }

            if (px < pop.x1)
                stack.append(main.allocator, .{ .x1 = px, .x2 = pop.x1 - 1, .y = pop.y - pop.dy, .dy = -pop.dy }) catch main.oomPanic();
        }

        var x1 = pop.x1;
        while (x1 <= pop.x2) {
            while (inside(screen, places.items, x1, pop.y, layer, current_id)) {
                places.append(main.allocator, .{
                    .x = @intCast(x1),
                    .y = @intCast(pop.y),
                    .old_id = current_id,
                    .new_id = target_id,
                    .layer = layer,
                }) catch main.oomPanic();
                x1 += 1;
            }

            if (x1 > px)
                stack.append(main.allocator, .{ .x1 = px, .x2 = x1 - 1, .y = pop.y + pop.dy, .dy = pop.dy }) catch main.oomPanic();

            if (x1 - 1 > pop.x2)
                stack.append(main.allocator, .{ .x1 = pop.x2 + 1, .x2 = x1 - 1, .y = pop.y - pop.dy, .dy = -pop.dy }) catch main.oomPanic();

            x1 += 1;
            while (x1 < pop.x2 and !inside(screen, places.items, x1, pop.y, layer, current_id))
                x1 += 1;
            px = x1;
        }
    }

    if (places.items.len == 0) {
        places.deinit(main.allocator);
        return;
    }

    if (screen.selected_tiles.len > 0) {
        var places_to_remove: std.ArrayListUnmanaged(usize) = .empty;
        defer places_to_remove.deinit(main.allocator);

        var idx: usize = 0;
        placeIter: for (places.items) |p| {
            for (screen.selected_tiles) |pos| if (p.x == pos.x and p.y == pos.y) continue :placeIter;
            places_to_remove.append(main.allocator, idx) catch main.oomPanic();
            idx += 1;
        }

        var iter = std.mem.reverseIterator(places_to_remove.items);
        while (iter.next()) |i| _ = places.orderedRemove(i);
    }

    if (selection) {
        var positions: std.ArrayListUnmanaged(Position) = .empty;
        for (places.items) |p| positions.append(main.allocator, .{ .x = p.x, .y = p.y }) catch main.oomPanic();
        screen.selected_tiles = positions.toOwnedSlice(main.allocator) catch main.oomPanic();
        places.deinit(main.allocator);
        return;
    }

    if (places.items.len <= 1) {
        if (places.items.len == 1) screen.command_queue.addCommand(.{ .place = places.items[0] });
        places.deinit(main.allocator);
    } else {
        screen.command_queue.addCommand(.{ .multi_place = .{ .places = places.toOwnedSlice(main.allocator) catch main.oomPanic() } });
    }
}

pub fn update(self: *MapEditorScreen, time: i64, _: f32) !void {
    if (self.map_tile_data.len <= 0) return;

    const time_sec = f32i(time) / std.time.us_per_s * 2;
    for (self.selected_tiles) |pos| {
        const square = map.getSquare(f32i(pos.x), f32i(pos.y), true, .ref) orelse continue;
        square.color = .fromColor(0xFF00FF, (@sin(time_sec) + 1) * 0.25);
    }

    if (main.current_time - self.last_update < press_delay_ms * std.time.us_per_ms) return;
    defer self.last_update = main.current_time;

    const world_point = main.camera.screenToWorld(input.mouse_x, input.mouse_y);
    const size: f32 = f32i(self.map_size - 1);
    const x = @floor(@max(0, @min(world_point.x, size)));
    const y = @floor(@max(0, @min(world_point.y, size)));
    switch (self.action) {
        .place => place(self, x, y, .place),
        .erase => place(self, x, y, .erase),
        .none => {},
        else => @panic("Unimplemented"),
    }
}

pub fn handleAction(self: *MapEditorScreen, action: EditorAction) !void {
    if (self.map_tile_data.len <= 0) return;

    if (main.current_time - self.last_press < press_delay_ms * std.time.us_per_ms) return;
    defer self.last_press = main.current_time;

    const world_point = main.camera.screenToWorld(input.mouse_x, input.mouse_y);
    const size: f32 = f32i(self.map_size - 1);
    const x = @floor(@max(0, @min(world_point.x, size)));
    const y = @floor(@max(0, @min(world_point.y, size)));
    const ux = u16f(x);
    const uy = u16f(y);
    const map_tile = self.getTile(ux, uy);

    switch (action) {
        .place => place(self, x, y, .place),
        .erase => place(self, x, y, .erase),
        .random => place(self, x, y, .random),
        .undo => self.command_queue.undo(),
        .redo => self.command_queue.redo(),
        .sample => switch (self.active_layer) {
            .ground => self.selected.ground = map_tile.ground,
            .region => self.selected.region = map_tile.region,
            .enemy => self.selected.enemy = blk: {
                map.object_lock.lock();
                defer map.object_lock.unlock();
                break :blk if (map.findObject(Enemy, map_tile.entity, .con)) |e| e.data_id else std.math.maxInt(u16);
            },
            .entity => self.selected.entity = blk: {
                map.object_lock.lock();
                defer map.object_lock.unlock();
                break :blk if (map.findObject(Entity, map_tile.entity, .con)) |e| e.data_id else std.math.maxInt(u16);
            },
            .portal => self.selected.portal = blk: {
                map.object_lock.lock();
                defer map.object_lock.unlock();
                break :blk if (map.findObject(Portal, map_tile.entity, .con)) |p| p.data_id else std.math.maxInt(u16);
            },
            .container => self.selected.container = blk: {
                map.object_lock.lock();
                defer map.object_lock.unlock();
                break :blk if (map.findObject(Container, map_tile.entity, .con)) |c| c.data_id else std.math.maxInt(u16);
            },
        },
        .fill => fill(self, ux, uy, false),
        .wand => fill(self, ux, uy, true),
        .unselect => self.clearSelection(),
        .none => {},
    }
}

pub fn updateFpsText(self: *MapEditorScreen, fps: usize, mem: f32) void {
    self.fps_text.text_data.setText(std.fmt.bufPrint(
        self.fps_text.text_data.backing_buffer,
        \\FPS: {}
        \\Memory: {d:.1} MB
    ,
        .{ fps, mem },
    ) catch "Buffer out of memory");
}
