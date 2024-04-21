const std = @import("std");
const glfw = @import("mach-glfw");
const nfd = @import("nfd");
const assets = @import("../../assets.zig");
const camera = @import("../../camera.zig");
const main = @import("../../main.zig");
const input = @import("../../input.zig");
const map = @import("../../game/map.zig");
const element = @import("../element.zig");
const game_data = @import("shared").game_data;
const settings = @import("../../settings.zig");
const utils = @import("shared").utils;
const rpc = @import("rpc");

const ui_systems = @import("../systems.zig");

const Player = @import("../../game/player.zig").Player;
const GameObject = @import("../../game/game_object.zig").GameObject;
const Square = @import("../../game/square.zig").Square;

const Interactable = element.InteractableImageData;
const NineSlice = element.NineSliceImageData;

const control_decor_w = 220;
const control_decor_h = 400;

const palette_decor_w = 200;
const palette_decor_h = 400;

const dropdown_w = 200;
const dropdown_h = 130;

// used for map parse/write
const Tile = struct { tile_type: u16, obj_type: u16, region_type: u8 };

const MapEditorTile = struct {
    object_id: i32 = -1,
    obj_type: u16 = std.math.maxInt(u16),
    tile_type: u16 = 0xFFFE,
    region_type: u8 = std.math.maxInt(u8),
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
};

const Layer = enum(u8) {
    ground = 0,
    object = 1,
    region = 2,
};

const Place = packed struct {
    x: u16,
    y: u16,
    new_type: u16,
    old_type: u16,
    layer: Layer,

    pub fn execute(self: Place) void {
        switch (self.layer) {
            .ground => ui_systems.screen.editor.setTile(self.x, self.y, self.new_type),
            .object => ui_systems.screen.editor.setObject(self.x, self.y, self.new_type),
            .region => ui_systems.screen.editor.setRegion(self.x, self.y, @intCast(self.new_type)),
        }
    }

    pub fn unexecute(self: Place) void {
        switch (self.layer) {
            .ground => ui_systems.screen.editor.setTile(self.x, self.y, self.old_type),
            .object => ui_systems.screen.editor.setObject(self.x, self.y, self.old_type),
            .region => ui_systems.screen.editor.setRegion(self.x, self.y, @intCast(self.old_type)),
        }
    }
};

const MultiPlace = struct {
    places: []Place,

    pub fn execute(self: MultiPlace) void {
        for (self.places) |place| place.execute();
    }

    pub fn unexecute(self: MultiPlace) void {
        for (self.places) |place| place.unexecute();
    }
};

const CommandQueue = struct {
    command_list: std.ArrayList(EditorCommand) = undefined,
    current_position: u32 = 0,
    allocator: std.mem.Allocator = undefined,

    pub fn init(self: *CommandQueue, allocator: std.mem.Allocator) void {
        self.allocator = allocator;
        self.command_list = std.ArrayList(EditorCommand).init(allocator);
    }

    pub fn deinit(self: *CommandQueue) void {
        for (self.command_list.items) |cmd| {
            if (cmd == .multi_place)
                self.allocator.free(cmd.multi_place.places);
        }
        self.command_list.deinit();
    }

    pub fn addCommand(self: *CommandQueue, command: EditorCommand) void {
        var i = self.command_list.items.len;
        while (i > self.current_position) : (i -= 1) {
            _ = self.command_list.pop();
        }

        switch (command) {
            inline else => |c| c.execute(),
        }

        self.command_list.append(command) catch return;
        self.current_position += 1;
    }

    pub fn undo(self: *CommandQueue) void {
        if (self.current_position == 0)
            return;

        self.current_position -= 1;

        const command = self.command_list.items[self.current_position];
        switch (command) {
            inline else => |c| c.unexecute(),
        }
    }

    pub fn redo(self: *CommandQueue) void {
        if (self.current_position == self.command_list.items.len)
            return;

        const command = self.command_list.items[self.current_position];
        switch (command) {
            inline else => |c| c.execute(),
        }

        self.current_position += 1;
    }
};

pub const MapEditorScreen = struct {
    const layers_text = [_][]const u8{ "Tiles", "Objects", "Regions" };
    const layers = [_]Layer{ .ground, .object, .region };

    const sizes_text = [_][]const u8{ "64x64", "128x128", "256x256", "512x512", "1024x1024", "2048x2048" };
    const sizes = [_]u32{ 64, 128, 256, 512, 1024, 2048 };

    allocator: std.mem.Allocator,
    inited: bool = false,

    next_obj_id: i32 = -1,
    editor_ready: bool = false,

    map_size: u32 = 0,
    map_tile_data: []MapEditorTile = &[0]MapEditorTile{},

    command_queue: CommandQueue = .{},

    action: EditorAction = .none,
    active_layer: Layer = .ground,
    selected_tile: u16 = defaultType(.ground),
    selected_object: u16 = defaultType(.object),
    selected_region: u8 = defaultType(.region),

    brush_size: f32 = 0.5,
    random_chance: f32 = 0.01,

    fps_text: *element.Text = undefined,
    controls_container: *element.Container = undefined,
    map_size_dropdown: *element.Dropdown = undefined,
    palette_decor: *element.Image = undefined,
    palette_container_tile: *element.ScrollableContainer = undefined,
    palette_container_object: *element.ScrollableContainer = undefined,
    palette_container_region: *element.ScrollableContainer = undefined,
    layer_dropdown: *element.Dropdown = undefined,

    place_key: settings.Button = .{ .mouse = .left },
    sample_key: settings.Button = .{ .mouse = .middle },
    erase_key: settings.Button = .{ .mouse = .right },
    random_key: settings.Button = .{ .key = .t },
    undo_key: settings.Button = .{ .key = .u },
    redo_key: settings.Button = .{ .key = .r },
    fill_key: settings.Button = .{ .key = .f },

    start_x_override: u16 = 0xFFFF,
    start_y_override: u16 = 0xFFFF,

    pub fn init(allocator: std.mem.Allocator) !*MapEditorScreen {
        var screen = try allocator.create(MapEditorScreen);
        screen.* = .{ .allocator = allocator };

        const presence = rpc.Packet.Presence{
            .assets = .{
                .large_image = rpc.Packet.ArrayString(256).create("logo"),
                .large_text = rpc.Packet.ArrayString(128).create(main.version_text),
            },
            .state = rpc.Packet.ArrayString(128).create("Map Editor"),
            .timestamps = .{
                .start = main.rpc_start,
            },
        };
        try main.rpc_client.setPresence(presence);

        screen.command_queue.init(allocator);

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

        var fps_text_data = element.TextData{
            .text = "",
            .size = 12,
            .text_type = .bold,
            .hori_align = .left,
            .max_width = control_decor_w,
            .max_chars = 64,
            .color = 0x6F573F,
        };

        {
            fps_text_data.lock.lock();
            defer fps_text_data.lock.unlock();

            fps_text_data.recalculateAttributes(allocator);
        }

        screen.fps_text = try element.create(allocator, element.Text{
            .x = 5 + control_decor_w + 5,
            .y = 5,
            .text_data = fps_text_data,
        });

        screen.controls_container = try element.create(allocator, element.Container{
            .x = 5,
            .y = 5,
        });

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

        screen.map_size_dropdown = try element.create(allocator, element.Dropdown{
            .x = 5,
            .y = 5 + control_decor_h + 5,
            .w = control_decor_w,
            .container_inlay_x = 8,
            .container_inlay_y = 2,
            .button_data_collapsed = Interactable.fromImageData(collapsed_icon_base, collapsed_icon_hover, collapsed_icon_press),
            .button_data_extended = Interactable.fromImageData(extended_icon_base, extended_icon_hover, extended_icon_press),
            .main_background_data = Interactable.fromNineSlices(dropdown_main_color_base, dropdown_main_color_hover, dropdown_main_color_press, dropdown_w, 40, 0, 0, 2, 2, 1.0),
            .alt_background_data = Interactable.fromNineSlices(dropdown_alt_color_base, dropdown_alt_color_hover, dropdown_alt_color_press, dropdown_w, 40, 0, 0, 2, 2, 1.0),
            .title_data = .{ .nine_slice = NineSlice.fromAtlasData(title_background, dropdown_w, dropdown_h, 20, 20, 4, 4, 1.0) },
            .title_text = .{
                .text = "Map Size",
                .size = 20,
                .text_type = .bold_italic,
            },
            .background_data = .{ .nine_slice = NineSlice.fromAtlasData(background_data, dropdown_w, dropdown_h, 20, 8, 4, 4, 1.0) },
            .scroll_w = 4,
            .scroll_h = dropdown_h - 10,
            .scroll_side_x_rel = -6,
            .scroll_side_y_rel = 0,
            .scroll_decor_image_data = .{ .nine_slice = NineSlice.fromAtlasData(scroll_background_data, 4, dropdown_h - 10, 0, 0, 2, 2, 1.0) },
            .scroll_knob_image_data = Interactable.fromNineSlices(scroll_knob_base, scroll_knob_hover, scroll_knob_press, 10, 16, 4, 4, 1, 2, 1.0),
            .scroll_side_decor_image_data = .{ .nine_slice = NineSlice.fromAtlasData(scroll_decor_data, 6, dropdown_h - 10, 0, 41, 6, 3, 1.0) },
            .selected_index = 0,
        });

        for (sizes_text) |size| {
            const line = try screen.map_size_dropdown.createChild(sizeCallback);
            _ = try line.container.createChild(element.Text{
                .x = 0,
                .y = 0,
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
        _ = try screen.controls_container.createChild(element.Image{
            .x = 0,
            .y = 0,
            .image_data = .{ .nine_slice = NineSlice.fromAtlasData(background_decor, control_decor_w, control_decor_h, 34, 34, 1, 1, 1.0) },
        });

        _ = try screen.controls_container.createChild(element.Button{
            .x = button_inset,
            .y = button_inset,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 26, 21, 3, 3, 1.0),
            .text_data = .{
                .text = "Open",
                .size = 16,
                .text_type = .bold,
            },
            .userdata = screen,
            .press_callback = openCallback,
        });

        _ = try screen.controls_container.createChild(element.Button{
            .x = button_inset + button_pad_w + button_width,
            .y = button_inset,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 26, 21, 3, 3, 1.0),
            .text_data = .{
                .text = "Save",
                .size = 16,
                .text_type = .bold,
            },
            .userdata = screen,
            .press_callback = saveCallback,
        });

        _ = try screen.controls_container.createChild(element.Button{
            .x = button_inset,
            .y = button_inset + button_pad_h + button_height,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 26, 21, 3, 3, 1.0),
            .text_data = .{
                .text = "Test",
                .size = 16,
                .text_type = .bold,
            },
            .userdata = screen,
            .press_callback = testCallback,
        });

        _ = try screen.controls_container.createChild(element.Button{
            .x = button_inset + button_pad_w + button_width,
            .y = button_inset + button_pad_h + button_height,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 26, 21, 3, 3, 1.0),
            .text_data = .{
                .text = "Exit",
                .size = 16,
                .text_type = .bold,
            },
            .press_callback = exitCallback,
        });

        _ = try screen.controls_container.createChild(element.KeyMapper{
            .x = button_inset,
            .y = button_inset + (button_pad_h + button_height) * 2,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, key_mapper_width, key_mapper_height, 26, 21, 3, 3, 1.0),
            .title_text_data = .{
                .text = "Place",
                .size = 12,
                .text_type = .bold,
            },
            .key = screen.place_key.getKey(),
            .mouse = screen.place_key.getMouse(),
            .settings_button = &screen.place_key,
            .set_key_callback = noAction,
        });
        _ = try screen.controls_container.createChild(element.KeyMapper{
            .x = button_inset + button_pad_w + button_width,
            .y = button_inset + (button_pad_h + button_height) * 2,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, key_mapper_width, key_mapper_height, 26, 21, 3, 3, 1.0),
            .title_text_data = .{
                .text = "Sample",
                .size = 12,
                .text_type = .bold,
            },
            .key = screen.sample_key.getKey(),
            .mouse = screen.sample_key.getMouse(),
            .settings_button = &screen.sample_key,
            .set_key_callback = noAction,
        });
        _ = try screen.controls_container.createChild(element.KeyMapper{
            .x = button_inset,
            .y = button_inset + (button_pad_h + button_height) * 3,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, key_mapper_width, key_mapper_height, 26, 21, 3, 3, 1.0),
            .title_text_data = .{
                .text = "Erase",
                .size = 12,
                .text_type = .bold,
            },
            .key = screen.erase_key.getKey(),
            .mouse = screen.erase_key.getMouse(),
            .settings_button = &screen.erase_key,
            .set_key_callback = noAction,
        });
        _ = try screen.controls_container.createChild(element.KeyMapper{
            .x = button_inset + button_pad_w + button_width,
            .y = button_inset + (button_pad_h + button_height) * 3,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, key_mapper_width, key_mapper_height, 26, 21, 3, 3, 1.0),
            .title_text_data = .{
                .text = "Random",
                .size = 12,
                .text_type = .bold,
            },
            .key = screen.random_key.getKey(),
            .mouse = screen.random_key.getMouse(),
            .settings_button = &screen.random_key,
            .set_key_callback = noAction,
        });
        _ = try screen.controls_container.createChild(element.KeyMapper{
            .x = button_inset,
            .y = button_inset + (button_pad_h + button_height) * 4,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, key_mapper_width, key_mapper_height, 26, 21, 3, 3, 1.0),
            .title_text_data = .{
                .text = "Undo",
                .size = 12,
                .text_type = .bold,
            },
            .key = screen.undo_key.getKey(),
            .mouse = screen.undo_key.getMouse(),
            .settings_button = &screen.undo_key,
            .set_key_callback = noAction,
        });
        _ = try screen.controls_container.createChild(element.KeyMapper{
            .x = button_inset + button_pad_w + button_width,
            .y = button_inset + (button_pad_h + button_height) * 4,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, key_mapper_width, key_mapper_height, 26, 21, 3, 3, 1.0),
            .title_text_data = .{
                .text = "Redo",
                .size = 12,
                .text_type = .bold,
            },
            .key = screen.redo_key.getKey(),
            .mouse = screen.redo_key.getMouse(),
            .settings_button = &screen.redo_key,
            .set_key_callback = noAction,
        });

        _ = try screen.controls_container.createChild(element.KeyMapper{
            .x = button_inset,
            .y = button_inset + (button_pad_h + button_height) * 5,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, key_mapper_width, key_mapper_height, 26, 21, 3, 3, 1.0),
            .title_text_data = .{
                .text = "Fill",
                .size = 12,
                .text_type = .bold,
            },
            .key = screen.fill_key.getKey(),
            .mouse = screen.fill_key.getMouse(),
            .settings_button = &screen.fill_key,
            .set_key_callback = noAction,
        });

        const slider_background_data = assets.getUiData("slider_background", 0);
        const knob_data_base = assets.getUiData("slider_knob_base", 0);
        const knob_data_hover = assets.getUiData("slider_knob_hover", 0);
        const knob_data_press = assets.getUiData("slider_knob_press", 0);

        const slider_w = control_decor_w - button_inset * 2 - 5;
        const slider_h = button_height - 5 - 10;
        const knob_size = button_height - 5;

        _ = try screen.controls_container.createChild(element.Slider{
            .x = button_inset + 2,
            .y = (button_pad_h + button_height) * 7,
            .w = slider_w,
            .h = slider_h,
            .min_value = 0.5,
            .max_value = 9.9,
            .decor_image_data = .{ .nine_slice = NineSlice.fromAtlasData(slider_background_data, slider_w, slider_h, 6, 6, 1, 1, 1.0) },
            .knob_image_data = Interactable.fromNineSlices(knob_data_base, knob_data_hover, knob_data_press, knob_size, knob_size, 12, 12, 1, 1, 1.0),
            .target = &screen.brush_size,
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

        _ = try screen.controls_container.createChild(element.Slider{
            .x = button_inset + 2,
            .y = (button_pad_h + button_height) * 8 + 20,
            .w = slider_w,
            .h = slider_h,
            .min_value = 0.01,
            .max_value = 1.0,
            .decor_image_data = .{ .nine_slice = NineSlice.fromAtlasData(slider_background_data, slider_w, slider_h, 6, 6, 1, 1, 1.0) },
            .knob_image_data = Interactable.fromNineSlices(knob_data_base, knob_data_hover, knob_data_press, knob_size, knob_size, 12, 12, 1, 1, 1.0),
            .target = &screen.random_chance,
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

        screen.palette_decor = try element.create(allocator, element.Image{
            .x = camera.screen_width - palette_decor_w - 5,
            .y = 5,
            .image_data = .{ .nine_slice = element.NineSliceImageData.fromAtlasData(background_decor, palette_decor_w, palette_decor_h, 34, 34, 1, 1, 1.0) },
        });

        screen.palette_container_tile = try element.create(allocator, element.ScrollableContainer{
            .x = screen.palette_decor.x + 8,
            .y = screen.palette_decor.y + 9,
            .scissor_w = palette_decor_w - 20 - 6,
            .scissor_h = palette_decor_h - 17,
            .scroll_x = screen.palette_decor.x + palette_decor_w - 20 + 2,
            .scroll_y = screen.palette_decor.y + 9,
            .scroll_w = 4,
            .scroll_h = palette_decor_h - 17,
            .scroll_side_x = screen.palette_decor.x + palette_decor_w - 20 + 2 - 6,
            .scroll_side_y = screen.palette_decor.y + 9,
            .scroll_decor_image_data = .{ .nine_slice = NineSlice.fromAtlasData(scroll_background_data, 4, palette_decor_h - 17, 0, 0, 2, 2, 1.0) },
            .scroll_knob_image_data = Interactable.fromNineSlices(scroll_knob_base, scroll_knob_hover, scroll_knob_press, 10, 16, 4, 4, 1, 2, 1.0),
            .scroll_side_decor_image_data = .{ .nine_slice = NineSlice.fromAtlasData(scroll_decor_data, 6, palette_decor_h - 17, 0, 41, 6, 3, 1.0) },
        });

        var tile_iter = game_data.ground_type_to_tex_data.iterator();
        var i: isize = 0;
        while (tile_iter.next()) |entry| : (i += 1) {
            if (entry.key_ptr.* == 0xFF or entry.key_ptr.* == 0xFFFE) {
                i -= 1;
                continue;
            }

            var atlas_data = blk: {
                if (entry.value_ptr.len <= 0) {
                    std.log.err("Tile with type 0x{x} has an empty texture list. Using error texture", .{entry.key_ptr.*});
                    break :blk assets.error_data;
                }

                const tex = if (entry.value_ptr.len == 1) entry.value_ptr.*[0] else entry.value_ptr.*[utils.rng.next() % entry.value_ptr.len];

                if (assets.atlas_data.get(tex.sheet)) |data| {
                    if (tex.index >= data.len) {
                        std.log.err("Could not find index 0x{x} for tile with type 0x{x}. Using error texture", .{ tex.sheet, entry.key_ptr.* });
                        break :blk assets.error_data;
                    }

                    break :blk data[tex.index];
                } else {
                    std.log.err("Could not find sheet {s} for tile with type 0x{x}. Using error texture", .{ tex.sheet, entry.key_ptr.* });
                    break :blk assets.error_data;
                }
            };

            if (atlas_data.tex_w <= 0 or atlas_data.tex_h <= 0) {
                std.log.err("Tile with type 0x{x} has an empty texture. Using error texture", .{entry.key_ptr.*});
                atlas_data = assets.error_data;
            }

            _ = try screen.palette_container_tile.createChild(element.Button{
                .x = @floatFromInt(@mod(i, 5) * 34),
                .y = @floatFromInt(@divFloor(i, 5) * 34),
                .image_data = .{ .base = .{ .normal = .{ .atlas_data = atlas_data, .scale_x = 4.0, .scale_y = 4.0 } } },
                .userdata = entry.key_ptr,
                .press_callback = groundClicked,
                .tooltip_text = .{
                    .text = game_data.ground_type_to_name.get(entry.key_ptr.*) orelse {
                        std.log.err("Could find name for tile with type 0x{x}. Not adding to tile list", .{entry.key_ptr.*});
                        i -= 1;
                        continue;
                    },
                    .size = 12,
                    .text_type = .bold_italic,
                },
            });
        }

        screen.palette_container_object = try element.create(allocator, element.ScrollableContainer{
            .x = screen.palette_decor.x + 8,
            .y = screen.palette_decor.y + 9,
            .scissor_w = palette_decor_w - 20 - 6,
            .scissor_h = palette_decor_h - 17,
            .scroll_x = screen.palette_decor.x + palette_decor_w - 20 + 2,
            .scroll_y = screen.palette_decor.y + 9,
            .scroll_w = 4,
            .scroll_h = palette_decor_h - 17,
            .scroll_side_x = screen.palette_decor.x + palette_decor_w - 20 + 2 - 6,
            .scroll_side_y = screen.palette_decor.y + 9,
            .scroll_decor_image_data = .{ .nine_slice = NineSlice.fromAtlasData(scroll_background_data, 4, palette_decor_h - 17, 0, 0, 2, 2, 1.0) },
            .scroll_knob_image_data = Interactable.fromNineSlices(scroll_knob_base, scroll_knob_hover, scroll_knob_press, 10, 16, 4, 4, 1, 2, 1.0),
            .scroll_side_decor_image_data = .{ .nine_slice = NineSlice.fromAtlasData(scroll_decor_data, 6, palette_decor_h - 17, 0, 41, 6, 3, 1.0) },
            .visible = false,
        });

        var obj_iter = game_data.obj_type_to_tex_data.iterator();
        i = 0;
        while (obj_iter.next()) |entry| : (i += 1) {
            if (game_data.obj_type_to_class.get(entry.key_ptr.*)) |class| {
                if (class == .projectile or class == .character or class == .player or class == .skin) {
                    i -= 1;
                    continue;
                }
            } else {
                i -= 1;
                std.log.err("Could not find class for object with type 0x{x}, skipping", .{entry.key_ptr.*});
                continue;
            }

            var atlas_data = blk: {
                if (entry.value_ptr.len <= 0) {
                    std.log.err("Object with type 0x{x} has an empty texture list. Using error texture", .{entry.key_ptr.*});
                    break :blk assets.error_data;
                }

                const tex = if (entry.value_ptr.len == 1) entry.value_ptr.*[0] else entry.value_ptr.*[utils.rng.next() % entry.value_ptr.len];

                if (assets.atlas_data.get(tex.sheet)) |data| {
                    if (tex.index >= data.len) {
                        std.log.err("Could not find index 0x{x} for object with type 0x{x}. Using error texture", .{ tex.sheet, entry.key_ptr.* });
                        break :blk assets.error_data;
                    }

                    break :blk data[tex.index];
                } else {
                    std.log.err("Could not find sheet {s} for object with type 0x{x}. Using error texture", .{ tex.sheet, entry.key_ptr.* });
                    break :blk assets.error_data;
                }
            };

            if (atlas_data.tex_w <= 0 or atlas_data.tex_h <= 0) {
                std.log.err("Object with type 0x{x} has an empty texture. Using error texture", .{entry.key_ptr.*});
                atlas_data = assets.error_data;
            }

            const scale = 10.0 / @max(atlas_data.texWRaw(), atlas_data.texHRaw()) * 3.0;

            _ = try screen.palette_container_object.createChild(element.Button{
                .x = @as(f32, @floatFromInt(@mod(i, 5) * 32)) + (32 - atlas_data.texWRaw() * scale) / 2.0,
                .y = @as(f32, @floatFromInt(@divFloor(i, 5) * 32)) + (32 - atlas_data.texHRaw() * scale) / 2.0,
                .image_data = .{ .base = .{ .normal = .{ .atlas_data = atlas_data, .scale_x = scale, .scale_y = scale } } },
                .userdata = entry.key_ptr,
                .press_callback = objectClicked,
                .tooltip_text = .{
                    .text = game_data.obj_type_to_name.get(entry.key_ptr.*) orelse {
                        std.log.err("Could find name for object with type 0x{x}. Not adding to object list", .{entry.key_ptr.*});
                        i -= 1;
                        continue;
                    },
                    .size = 12,
                    .text_type = .bold_italic,
                },
            });
        }

        screen.palette_container_region = try element.create(allocator, element.ScrollableContainer{
            .x = screen.palette_decor.x + 8,
            .y = screen.palette_decor.y + 9,
            .scissor_w = palette_decor_w - 20 - 6,
            .scissor_h = palette_decor_h - 17,
            .scroll_x = screen.palette_decor.x + palette_decor_w - 20 + 2,
            .scroll_y = screen.palette_decor.y + 9,
            .scroll_w = 4,
            .scroll_h = palette_decor_h - 17,
            .scroll_side_x = screen.palette_decor.x + palette_decor_w - 20 + 2 - 6,
            .scroll_side_y = screen.palette_decor.y + 9,
            .scroll_decor_image_data = .{ .nine_slice = NineSlice.fromAtlasData(scroll_background_data, 4, palette_decor_h - 17, 0, 0, 2, 2, 1.0) },
            .scroll_knob_image_data = Interactable.fromNineSlices(scroll_knob_base, scroll_knob_hover, scroll_knob_press, 10, 16, 4, 4, 1, 2, 1.0),
            .scroll_side_decor_image_data = .{ .nine_slice = NineSlice.fromAtlasData(scroll_decor_data, 6, palette_decor_h - 17, 0, 41, 6, 3, 1.0) },
            .visible = false,
        });

        var region_iter = game_data.region_type_to_color.iterator();
        i = 0;
        while (region_iter.next()) |entry| : (i += 1) {
            _ = try screen.palette_container_region.createChild(element.Button{
                .x = @floatFromInt(@mod(i, 5) * 34),
                .y = @floatFromInt(@divFloor(i, 5) * 34),
                .image_data = .{ .base = .{ .normal = .{
                    .atlas_data = assets.wall_backface_data,
                    .scale_x = 4.0,
                    .scale_y = 4.0,
                    .alpha = 0.6,
                    .color = entry.value_ptr.*,
                    .color_intensity = 1.0,
                } } },
                .userdata = entry.key_ptr,
                .press_callback = regionClicked,
                .tooltip_text = .{
                    .text = game_data.region_type_to_name.get(entry.key_ptr.*) orelse {
                        std.log.err("Could find name for region with type 0x{x}. Not adding to region list", .{entry.key_ptr.*});
                        i -= 1;
                        continue;
                    },
                    .size = 12,
                    .text_type = .bold_italic,
                },
            });
        }

        screen.layer_dropdown = try element.create(allocator, element.Dropdown{
            .x = screen.palette_decor.x,
            .y = screen.palette_decor.y + screen.palette_decor.height() + 5,
            .w = dropdown_w,
            .container_inlay_x = 8,
            .container_inlay_y = 2,
            .button_data_collapsed = Interactable.fromImageData(collapsed_icon_base, collapsed_icon_hover, collapsed_icon_press),
            .button_data_extended = Interactable.fromImageData(extended_icon_base, extended_icon_hover, extended_icon_press),
            .main_background_data = Interactable.fromNineSlices(dropdown_main_color_base, dropdown_main_color_hover, dropdown_main_color_press, dropdown_w, 40, 0, 0, 2, 2, 1.0),
            .alt_background_data = Interactable.fromNineSlices(dropdown_alt_color_base, dropdown_alt_color_hover, dropdown_alt_color_press, dropdown_w, 40, 0, 0, 2, 2, 1.0),
            .title_data = .{ .nine_slice = NineSlice.fromAtlasData(title_background, dropdown_w, dropdown_h, 20, 20, 4, 4, 1.0) },
            .title_text = .{
                .text = "Layer",
                .size = 20,
                .text_type = .bold_italic,
            },
            .background_data = .{ .nine_slice = NineSlice.fromAtlasData(background_data, dropdown_w, dropdown_h, 20, 8, 4, 4, 1.0) },
            .scroll_w = 4,
            .scroll_h = dropdown_h - 10,
            .scroll_side_x_rel = -6,
            .scroll_side_y_rel = 0,
            .scroll_decor_image_data = .{ .nine_slice = NineSlice.fromAtlasData(scroll_background_data, 4, dropdown_h - 10, 0, 0, 2, 2, 1.0) },
            .scroll_knob_image_data = Interactable.fromNineSlices(scroll_knob_base, scroll_knob_hover, scroll_knob_press, 10, 16, 4, 4, 1, 2, 1.0),
            .scroll_side_decor_image_data = .{ .nine_slice = NineSlice.fromAtlasData(scroll_decor_data, 6, dropdown_h - 10, 0, 41, 6, 3, 1.0) },
            .selected_index = 0,
        });

        for (layers_text) |layer| {
            const layer_line = try screen.layer_dropdown.createChild(layerCallback);
            _ = try layer_line.container.createChild(element.Text{
                .x = 0,
                .y = 0,
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

        screen.inited = true;
        return screen;
    }

    fn groundClicked(ud: ?*anyopaque) void {
        ui_systems.screen.editor.selected_tile = @as(*u16, @alignCast(@ptrCast(ud))).*;
    }

    fn objectClicked(ud: ?*anyopaque) void {
        ui_systems.screen.editor.selected_object = @as(*u16, @alignCast(@ptrCast(ud))).*;
    }

    fn regionClicked(ud: ?*anyopaque) void {
        ui_systems.screen.editor.selected_region = @as(*u8, @alignCast(@ptrCast(ud))).*;
    }

    fn sizeCallback(dc: *element.DropdownContainer) void {
        const screen = ui_systems.screen.editor;
        screen.map_size = sizes[dc.index];
    }

    fn layerCallback(dc: *element.DropdownContainer) void {
        const next_layer = layers[dc.index];
        const screen = ui_systems.screen.editor;
        screen.active_layer = next_layer;
        switch (next_layer) {
            .ground => {
                screen.palette_container_tile.visible = true;
                screen.palette_container_object.visible = false;
                screen.palette_container_region.visible = false;
            },
            .object => {
                screen.palette_container_tile.visible = false;
                screen.palette_container_object.visible = true;
                screen.palette_container_region.visible = false;
            },
            .region => {
                screen.palette_container_tile.visible = false;
                screen.palette_container_object.visible = false;
                screen.palette_container_region.visible = true;
            },
        }
    }

    fn noAction(_: *element.KeyMapper) void {}

    fn newCreateCallback(ud: ?*anyopaque) void {
        const screen: *MapEditorScreen = @alignCast(@ptrCast(ud.?));

        map.dispose(screen.allocator);
        map.setWH(screen.map_size, screen.map_size, screen.allocator);
        map.bg_light_color = 0;
        map.bg_light_intensity = 0.15;

        if (screen.map_tile_data.len == 0) {
            screen.map_tile_data = screen.allocator.alloc(MapEditorTile, screen.map_size * screen.map_size) catch return;
        } else {
            screen.map_tile_data = screen.allocator.realloc(screen.map_tile_data, screen.map_size * screen.map_size) catch return;
        }

        @memset(screen.map_tile_data, MapEditorTile{});

        const center = @as(f32, @floatFromInt(screen.map_size)) / 2.0;

        for (0..screen.map_size) |y| {
            for (0..screen.map_size) |x| {
                var square = Square{
                    .x = @as(f32, @floatFromInt(x)),
                    .y = @as(f32, @floatFromInt(y)),
                    .tile_type = 0xFFFE,
                };
                square.addToMap();
            }
        }

        map.local_player_id = 0x7D000000 - 1; // particle effect base id = 0x7D000000
        var player = Player{
            .x = if (screen.start_x_override == 0xFFFF) center else @floatFromInt(screen.start_x_override),
            .y = if (screen.start_y_override == 0xFFFF) center else @floatFromInt(screen.start_y_override),
            .obj_id = map.local_player_id,
            .obj_type = 0x0300,
            .size = 100,
            .speed = 300,
        };
        player.addToMap(screen.allocator);

        main.editing_map = true;
        ui_systems.menu_background.visible = false;
        screen.start_x_override = 0xFFFF;
        screen.start_y_override = 0xFFFF;
    }

    // for easier error handling
    fn openInner(screen: *MapEditorScreen) !void {
        // todo popup for save

        const file_path = try nfd.openFileDialog("em", null);
        if (file_path) |path| {
            defer nfd.freePath(path);

            const file = try std.fs.openFileAbsolute(path, .{});
            defer file.close();

            var dcp = std.compress.zlib.decompressor(file.reader());

            const version = try dcp.reader().readInt(u8, .little);
            if (version != 2)
                std.log.err("Reading map failed, unsupported version: {d}", .{version});

            const x_start = try dcp.reader().readInt(u16, .little);
            const y_start = try dcp.reader().readInt(u16, .little);
            const w = try dcp.reader().readInt(u16, .little);
            const h = try dcp.reader().readInt(u16, .little);

            screen.start_x_override = x_start + @divFloor(w, 2);
            screen.start_y_override = y_start + @divFloor(h, 2);
            screen.map_size = utils.nextPowerOfTwo(@max(x_start + w, y_start + h));
            newCreateCallback(screen);

            const tiles = try screen.allocator.alloc(Tile, try dcp.reader().readInt(u16, .little));
            defer screen.allocator.free(tiles);
            for (tiles) |*tile| {
                const tile_type = try dcp.reader().readInt(u16, .little);
                const obj_type = try dcp.reader().readInt(u16, .little);
                const region_type = try dcp.reader().readInt(u8, .little);

                tile.* = .{
                    .tile_type = tile_type,
                    .obj_type = obj_type,
                    .region_type = region_type,
                };
            }

            const byte_len = tiles.len <= 256;
            for (y_start..y_start + h) |y| {
                for (x_start..x_start + w) |x| {
                    const ux: u32 = @intCast(x);
                    const uy: u32 = @intCast(y);
                    const idx = if (byte_len) try dcp.reader().readInt(u8, .little) else try dcp.reader().readInt(u16, .little);
                    const tile = tiles[idx];
                    if (tile.tile_type != std.math.maxInt(u16)) screen.setTile(ux, uy, tile.tile_type);
                    if (tile.obj_type != std.math.maxInt(u16)) screen.setObject(ux, uy, tile.obj_type);
                    if (tile.region_type != std.math.maxInt(u8)) screen.setRegion(ux, uy, tile.region_type);
                }
            }
        }
    }

    fn openCallback(ud: ?*anyopaque) void {
        openInner(@alignCast(@ptrCast(ud.?))) catch |e| {
            std.log.err("Error while parsing map: {}", .{e});
            if (@errorReturnTrace()) |trace| {
                std.debug.dumpStackTrace(trace.*);
            }
        };
    }

    fn tileBounds(tiles: []MapEditorTile) struct { min_x: u16, max_x: u16, min_y: u16, max_y: u16 } {
        var min_x = map.width;
        var min_y = map.height;
        var max_x: u32 = 0;
        var max_y: u32 = 0;

        for (0..map.height) |y| {
            for (0..map.width) |x| {
                const map_tile = tiles[@intCast(y * map.width + x)];
                if (map_tile.tile_type != 0xFFFE or
                    map_tile.obj_type != std.math.maxInt(u16) or
                    map_tile.region_type != std.math.maxInt(u8))
                {
                    const ux: u32 = @intCast(x);
                    const uy: u32 = @intCast(y);

                    min_x = @min(min_x, ux);
                    min_y = @min(min_y, uy);
                    max_x = @max(max_x, ux);
                    max_y = @max(max_y, uy);
                }
            }
        }

        return .{ .min_x = @intCast(min_x), .min_y = @intCast(min_y), .max_x = @intCast(max_x), .max_y = @intCast(max_y) };
    }

    pub fn indexOfTile(tiles: []const Tile, value: Tile) ?usize {
        for (tiles, 0..) |tile, i| {
            if (tile.obj_type == value.obj_type and
                tile.region_type == value.region_type and
                tile.tile_type == value.tile_type)
                return i;
        }

        return null;
    }

    fn mapData(screen: *MapEditorScreen) ![]u8 {
        var data = std.ArrayList(u8).init(screen.allocator);

        const tile_data = screen.map_tile_data;
        const bounds = tileBounds(tile_data);

        try data.writer().writeInt(u8, 2, .little); // version
        try data.writer().writeInt(u16, bounds.min_x, .little);
        try data.writer().writeInt(u16, bounds.min_y, .little);
        try data.writer().writeInt(u16, bounds.max_x - bounds.min_x, .little);
        try data.writer().writeInt(u16, bounds.max_y - bounds.min_y, .little);

        var tiles = std.ArrayList(Tile).init(screen.allocator);
        defer tiles.deinit();

        for (bounds.min_y..bounds.max_y) |y| {
            for (bounds.min_x..bounds.max_x) |x| {
                const map_tile = tile_data[y * map.width + x];
                const tile = Tile{
                    .tile_type = if (map_tile.tile_type == 0xFFFE) 0xFFFF else map_tile.tile_type,
                    .obj_type = map_tile.obj_type,
                    .region_type = map_tile.region_type,
                };

                if (indexOfTile(tiles.items, tile) == null)
                    try tiles.append(tile);
            }
        }

        try data.writer().writeInt(u16, @intCast(tiles.items.len), .little);
        const byte_len = tiles.items.len <= 256;

        for (tiles.items) |tile| {
            try data.writer().writeInt(u16, tile.tile_type, .little);
            try data.writer().writeInt(u16, tile.obj_type, .little);
            try data.writer().writeInt(u8, tile.region_type, .little);
        }

        for (bounds.min_y..bounds.max_y) |y| {
            for (bounds.min_x..bounds.max_x) |x| {
                const map_tile = tile_data[y * map.width + x];
                const tile = Tile{
                    .tile_type = if (map_tile.tile_type == 0xFFFE) 0xFFFF else map_tile.tile_type,
                    .obj_type = map_tile.obj_type,
                    .region_type = map_tile.region_type,
                };

                if (indexOfTile(tiles.items, tile)) |idx| {
                    if (byte_len)
                        try data.writer().writeInt(u8, @intCast(idx), .little)
                    else
                        try data.writer().writeInt(u16, @intCast(idx), .little);
                }
            }
        }

        return try data.toOwnedSlice();
    }

    fn saveInner(screen: *MapEditorScreen) !void {
        if (!main.editing_map) return;

        const file_path = nfd.saveFileDialog("em", null) catch return;
        if (file_path) |path| {
            defer nfd.freePath(path);

            const file = try std.fs.createFileAbsolute(path, .{});
            defer file.close();

            const data = try mapData(screen);
            defer screen.allocator.free(data);

            var fbs = std.io.fixedBufferStream(data);
            try std.compress.zlib.compress(fbs.reader(), file.writer(), .{});
        }
    }

    fn saveCallback(ud: ?*anyopaque) void {
        saveInner(@alignCast(@ptrCast(ud.?))) catch |e| {
            std.log.err("Error while saving map: {}", .{e});
            if (@errorReturnTrace()) |trace| {
                std.debug.dumpStackTrace(trace.*);
            }
        };
    }

    fn exitCallback(_: ?*anyopaque) void {
        ui_systems.switchScreen(.main_menu);
    }

    fn testCallback(ud: ?*anyopaque) void {
        if (main.character_list.len == 0)
            return;

        if (main.server_list) |server_list| {
            if (server_list.len > 0) {
                const screen: *MapEditorScreen = @alignCast(@ptrCast(ud.?));
                if (ui_systems.editor_backup == null)
                    ui_systems.editor_backup = screen.allocator.create(MapEditorScreen) catch return;
                // @memcpy(ui_systems.editor_backup.?, screen);

                const data = mapData(screen) catch |e| {
                    std.log.err("Error while testing map: {}", .{e});
                    if (@errorReturnTrace()) |trace| {
                        std.debug.dumpStackTrace(trace.*);
                    }
                    return;
                };
                defer screen.allocator.free(data);

                var eclipse_map = std.ArrayList(u8).init(screen.allocator);
                var fbs = std.io.fixedBufferStream(data);
                std.compress.zlib.compress(fbs.reader(), eclipse_map.writer(), .{}) catch |e| {
                    std.log.err("Error while testing map: {}", .{e});
                    if (@errorReturnTrace()) |trace| {
                        std.debug.dumpStackTrace(trace.*);
                    }
                    return;
                };
                main.enterTest(server_list[0], main.character_list[0].id, eclipse_map.toOwnedSlice() catch return);
                return;
            }
        }
    }

    pub fn deinit(self: *MapEditorScreen) void {
        self.inited = false;
        self.command_queue.deinit();

        element.destroy(self.fps_text);
        element.destroy(self.palette_decor);
        element.destroy(self.palette_container_tile);
        element.destroy(self.palette_container_object);
        element.destroy(self.palette_container_region);
        element.destroy(self.layer_dropdown);
        element.destroy(self.controls_container);

        if (self.map_tile_data.len > 0)
            self.allocator.free(self.map_tile_data);

        if (main.editing_map) {
            main.editing_map = false;
            map.dispose(self.allocator);
        }

        self.allocator.destroy(self);

        ui_systems.menu_background.visible = true;
    }

    pub fn resize(self: *MapEditorScreen, w: f32, _: f32) void {
        const palette_x = w - palette_decor_w - 5;
        const cont_x = palette_x + 8;

        self.palette_decor.x = palette_x;
        self.palette_container_tile.x = cont_x;
        self.palette_container_tile.container.x = cont_x;
        self.palette_container_object.x = cont_x;
        self.palette_container_object.container.x = cont_x;
        self.palette_container_region.x = cont_x;
        self.palette_container_region.container.x = cont_x;
        self.layer_dropdown.x = palette_x;
        self.layer_dropdown.container.x = palette_x + self.layer_dropdown.container_inlay_x;
        self.layer_dropdown.container.container.x = palette_x + self.layer_dropdown.container_inlay_x;
        self.layer_dropdown.y = self.palette_decor.y + self.palette_decor.height() + 5;
    }

    pub fn onMousePress(self: *MapEditorScreen, button: glfw.MouseButton) void {
        if (button == self.undo_key.getMouse())
            self.action = .undo
        else if (button == self.redo_key.getMouse())
            self.action = .redo
        else if (button == self.place_key.getMouse())
            self.action = .place
        else if (button == self.erase_key.getMouse())
            self.action = .erase
        else if (button == self.sample_key.getMouse())
            self.action = .sample
        else if (button == self.random_key.getMouse())
            self.action = .random
        else if (button == self.fill_key.getMouse())
            self.action = .fill;
    }

    pub fn onMouseRelease(self: *MapEditorScreen, button: glfw.MouseButton) void {
        if (button == self.undo_key.getMouse() or
            button == self.redo_key.getMouse() or
            button == self.place_key.getMouse() or
            button == self.erase_key.getMouse() or
            button == self.sample_key.getMouse() or
            button == self.random_key.getMouse() or
            button == self.fill_key.getMouse())
            self.action = .none;
    }

    pub fn onKeyPress(self: *MapEditorScreen, key: glfw.Key) void {
        if (key == self.undo_key.getKey())
            self.action = .undo
        else if (key == self.redo_key.getKey())
            self.action = .redo
        else if (key == self.place_key.getKey())
            self.action = .place
        else if (key == self.erase_key.getKey())
            self.action = .erase
        else if (key == self.sample_key.getKey())
            self.action = .sample
        else if (key == self.random_key.getKey())
            self.action = .random
        else if (key == self.fill_key.getKey())
            self.action = .fill;
    }

    pub fn onKeyRelease(self: *MapEditorScreen, key: glfw.Key) void {
        if (key == self.undo_key.getKey() or
            key == self.redo_key.getKey() or
            key == self.place_key.getKey() or
            key == self.erase_key.getKey() or
            key == self.sample_key.getKey() or
            key == self.random_key.getKey() or
            key == self.fill_key.getKey())
            self.action = .none;
    }

    fn setTile(self: *MapEditorScreen, x: u32, y: u32, value: u16) void {
        const tile = &self.map_tile_data[y * self.map_size + x];
        if (tile.tile_type == value)
            return;

        tile.tile_type = value;
        var square = Square{
            .x = @as(f32, @floatFromInt(x)),
            .y = @as(f32, @floatFromInt(y)),
            .tile_type = value,
        };
        square.addToMap();
    }

    fn getTile(self: *MapEditorScreen, x: f32, y: f32) MapEditorTile {
        const floor_x: u32 = @intFromFloat(@floor(x));
        const floor_y: u32 = @intFromFloat(@floor(y));
        return self.map_tile_data[floor_y * self.map_size + floor_x];
    }

    fn setObject(self: *MapEditorScreen, x: u32, y: u32, value: u16) void {
        const tile = &self.map_tile_data[y * self.map_size + x];

        if (tile.obj_type == value)
            return;

        if (value == std.math.maxInt(u16)) {
            map.object_lock.lock();
            defer map.object_lock.unlock();
            map.removeEntity(self.allocator, tile.object_id);

            tile.obj_type = value;
            tile.object_id = value;
        } else {
            if (tile.object_id != -1) {
                map.object_lock.lock();
                defer map.object_lock.unlock();
                map.removeEntity(self.allocator, tile.object_id);
            }

            self.next_obj_id += 1;

            tile.obj_type = value;
            tile.object_id = self.next_obj_id;

            var obj = GameObject{
                .x = @as(f32, @floatFromInt(x)),
                .y = @as(f32, @floatFromInt(y)),
                .obj_id = self.next_obj_id,
                .obj_type = value,
                .size = 100,
                .alpha = 1.0,
            };

            obj.addToMap(self.allocator, true);
        }
    }

    fn setRegion(self: *MapEditorScreen, x: u32, y: u32, value: u8) void {
        self.map_tile_data[y * self.map_size + x].region_type = value;
    }

    fn place(self: *MapEditorScreen, center_x: f32, center_y: f32, comptime place_type: enum { place, erase, random }) !void {
        var places = std.ArrayList(Place).init(self.allocator);
        const size_sqr = self.brush_size * self.brush_size;
        const sel_type: u16 = if (place_type == .erase) defaultType(self.active_layer) else switch (self.active_layer) {
            .ground => self.selected_tile,
            .object => self.selected_object,
            .region => @intCast(self.selected_region),
        };
        if (place_type != .erase and sel_type == defaultType(self.active_layer))
            return;

        const size: f32 = @floatFromInt(self.map_size - 1);
        const y_left: usize = @intFromFloat(@max(0, @floor(center_y - self.brush_size)));
        const y_right: usize = @intFromFloat(@min(size, @ceil(center_y + self.brush_size)));
        const x_left: usize = @intFromFloat(@max(0, @floor(center_x - self.brush_size)));
        const x_right: usize = @intFromFloat(@min(size, @ceil(center_x + self.brush_size)));
        for (y_left..y_right) |y| {
            for (x_left..x_right) |x| {
                const fx: f32 = @floatFromInt(x);
                const fy: f32 = @floatFromInt(y);
                const dx = center_x - fx;
                const dy = center_y - fy;
                if (dx * dx + dy * dy <= size_sqr) {
                    if (place_type == .random and utils.rng.random().float(f32) > self.random_chance)
                        continue;

                    try places.append(.{
                        .x = @intCast(x),
                        .y = @intCast(y),
                        .new_type = sel_type,
                        .old_type = blk: {
                            const tile = self.map_tile_data[y * self.map_size + x];
                            switch (self.active_layer) {
                                .ground => break :blk tile.tile_type,
                                .object => break :blk tile.obj_type,
                                .region => break :blk @intCast(tile.region_type),
                            }

                            break :blk defaultType(self.active_layer);
                        },
                        .layer = self.active_layer,
                    });
                }
            }
        }

        if (places.items.len <= 1) {
            if (places.items.len == 1) self.command_queue.addCommand(.{ .place = places.items[0] });
            places.deinit();
        } else {
            self.command_queue.addCommand(.{ .multi_place = .{ .places = try places.toOwnedSlice() } });
        }
    }

    fn placesContain(places: []Place, x: i32, y: i32) bool {
        if (x < 0 or y < 0)
            return false;

        for (places) |p| {
            if (p.x == x and p.y == y)
                return true;
        }

        return false;
    }

    inline fn defaultType(layer: Layer) u16 {
        return switch (layer) {
            .ground => 0xFFFE,
            .object => 0xFFFF,
            .region => 0xFF,
        };
    }

    inline fn typeAt(layer: Layer, screen: *MapEditorScreen, x: i32, y: i32) u16 {
        if (x < 0 or y < 0)
            return defaultType(layer);

        const size: i32 = @intCast(screen.map_size);
        const tile = screen.map_tile_data[@intCast(y * size + x)];
        return switch (layer) {
            .ground => tile.tile_type,
            .object => tile.obj_type,
            .region => @as(u16, tile.region_type),
        };
    }

    inline fn inside(screen: *MapEditorScreen, places: []Place, x: i32, y: i32, layer: Layer, current_type: u16) bool {
        return !placesContain(places, x, y) and typeAt(layer, screen, x, y) == current_type;
    }

    fn fill(screen: *MapEditorScreen, x: u16, y: u16) !void {
        const FillData = struct { x1: i32, x2: i32, y: i32, dy: i32 };

        var places = std.ArrayList(Place).init(screen.allocator);

        const layer = screen.active_layer;
        const target_type = switch (screen.active_layer) {
            .ground => screen.selected_tile,
            .object => screen.selected_object,
            .region => screen.selected_region,
        };

        const current_type = typeAt(layer, screen, x, y);
        if (current_type == target_type or target_type == defaultType(layer))
            return;

        var stack = std.ArrayList(FillData).init(screen.allocator);
        defer stack.deinit();

        try stack.append(.{ .x1 = x, .x2 = x, .y = y, .dy = 1 });
        try stack.append(.{ .x1 = x, .x2 = x, .y = y - 1, .dy = -1 });

        while (stack.items.len > 0) {
            const pop = stack.pop();
            var px = pop.x1;

            if (inside(screen, places.items, px, pop.y, layer, current_type)) {
                while (inside(screen, places.items, px - 1, pop.y, layer, current_type)) {
                    try places.append(.{
                        .x = @intCast(px - 1),
                        .y = @intCast(pop.y),
                        .new_type = target_type,
                        .old_type = current_type,
                        .layer = layer,
                    });
                    px -= 1;
                }

                if (px < pop.x1)
                    try stack.append(.{ .x1 = px, .x2 = pop.x1 - 1, .y = pop.y - pop.dy, .dy = -pop.dy });
            }

            var x1 = pop.x1;
            while (x1 <= pop.x2) {
                while (inside(screen, places.items, x1, pop.y, layer, current_type)) {
                    try places.append(.{
                        .x = @intCast(x1),
                        .y = @intCast(pop.y),
                        .old_type = current_type,
                        .new_type = target_type,
                        .layer = layer,
                    });
                    x1 += 1;
                }

                if (x1 > px)
                    try stack.append(.{ .x1 = px, .x2 = x1 - 1, .y = pop.y + pop.dy, .dy = pop.dy });

                if (x1 - 1 > pop.x2)
                    try stack.append(.{ .x1 = pop.x2 + 1, .x2 = x1 - 1, .y = pop.y - pop.dy, .dy = -pop.dy });

                x1 += 1;
                while (x1 < pop.x2 and !inside(screen, places.items, x1, pop.y, layer, current_type))
                    x1 += 1;
                px = x1;
            }
        }

        if (places.items.len <= 1) {
            if (places.items.len == 1) screen.command_queue.addCommand(.{ .place = places.items[0] });
            places.deinit();
        } else {
            screen.command_queue.addCommand(.{ .multi_place = .{ .places = try places.toOwnedSlice() } });
        }
    }

    pub fn update(self: *MapEditorScreen, _: i64, _: f32) !void {
        if (self.map_tile_data.len <= 0)
            return;

        const world_point = camera.screenToWorld(input.mouse_x, input.mouse_y);
        const size: f32 = @floatFromInt(self.map_size - 1);
        const x = @floor(@max(0, @min(world_point.x, size)));
        const y = @floor(@max(0, @min(world_point.y, size)));
        const int_x: u16 = @intFromFloat(x);
        const int_y: u16 = @intFromFloat(y);

        switch (self.action) {
            .place => try place(self, x, y, .place),
            .erase => try place(self, x, y, .erase),
            .random => try place(self, x, y, .random),
            .undo => self.command_queue.undo(),
            .redo => self.command_queue.redo(),
            .sample => switch (self.active_layer) {
                .ground => self.selected_tile = self.map_tile_data[int_y * self.map_size + int_x].tile_type,
                .object => self.selected_object = self.map_tile_data[int_y * self.map_size + int_x].obj_type,
                .region => self.selected_region = self.map_tile_data[int_y * self.map_size + int_x].region_type,
            },
            .fill => try fill(self, int_x, int_y),
            .none => {},
        }
    }

    pub fn updateFpsText(self: *MapEditorScreen, fps: usize, mem: f32) !void {
        if (!self.inited)
            return;

        self.fps_text.text_data.setText(
            try std.fmt.bufPrint(self.fps_text.text_data.backing_buffer, "FPS: {d}\nMemory: {d:.1} MB", .{ fps, mem }),
            self.allocator,
        );
    }
};
