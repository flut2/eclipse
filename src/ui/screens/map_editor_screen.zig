const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const glfw = @import("mach-glfw");
const nfd = @import("nfd");
const assets = @import("../../assets.zig");
const camera = @import("../../camera.zig");
const main = @import("../../main.zig");
const input = @import("../../input.zig");
const map = @import("../../game/map.zig");
const element = @import("../element.zig");
const game_data = @import("../../game_data.zig");
const settings = @import("../../settings.zig");
const rpc = @import("rpc");

const systems = @import("../systems.zig");

const Player = @import("../../game/player.zig").Player;
const GameObject = @import("../../game/game_object.zig").GameObject;
const Square = @import("../../game/square.zig").Square;

const Interactable = element.InteractableImageData;
const NineSlice = element.NineSliceImageData;

const button_container_width = 420;
const button_container_height = 190;

const new_container_width = 345;
const new_container_height = 175;

// 0xFFFF is -1 in unsigned for those who dont know
// 0xFFFC is Editor Specific Empty Tile

const MapEditorTile = struct {
    object_type: u16 = 0xFFFF,
    object_id: i32 = -1, // used to keep track of what entity exists on this tile, used for removing from world on erase
    ground_type: u16 = 0xFFFC, // void tile
    region_type: i32 = -1, // todo make enum struct
};

pub const EditorCommand = union(enum) {
    place_tile: EditorPlaceTileCommand,
    erase_tile: EditorEraseTileCommand,
    place_object: EditorPlaceObjectCommand,
    erase_object: EditorEraseObjectCommand,
};

const EditorAction = enum(u8) {
    none = 0,
    place = 1,
    erase = 2,
    place_random = 3,
    erase_random = 4,
    undo = 5,
    redo = 6,
    sample = 7,
};

const EditorLayer = enum(u8) {
    ground = 0,
    object = 1,
    region = 2,
};

const EditorPlaceTileCommand = struct {
    screen: *MapEditorScreen,
    x: u32,
    y: u32,
    new_type: u16,
    old_type: u16,

    pub fn execute(self: EditorPlaceTileCommand) void {
        // todo make EditorPlaceTilesCommand -> supports multiple
        // for (self.screen.active_brush._visual_objects.items()) |id| {
        //     if (map.findEntityRef(id)) |en| {
        //         if (en.* == .object) {
        //             const o = &en.object;
        //             const xx = @as(u32, @intFromFloat(@floor(o.x)));
        //             const yy = @as(u32, @intFromFloat(@floor(o.y)));
        //             self.screen.setTile(xx, yy, self.new_type);
        //         }
        //     }
        // }
        self.screen.setTile(self.x, self.y, self.new_type);
    }

    pub fn unexecute(self: EditorPlaceTileCommand) void {
        self.screen.setTile(self.x, self.y, self.old_type);
    }
};

const EditorEraseTileCommand = struct {
    screen: *MapEditorScreen,
    x: u32,
    y: u32,
    old_type: u16,

    pub fn execute(self: EditorEraseTileCommand) void {
        self.screen.setTile(self.x, self.y, 0xFFFC);
    }

    pub fn unexecute(self: EditorEraseTileCommand) void {
        self.screen.setTile(self.x, self.y, self.old_type);
    }
};

const EditorPlaceObjectCommand = struct {
    screen: *MapEditorScreen,
    x: u32,
    y: u32,
    new_type: u16,
    old_type: u16,

    pub fn execute(self: EditorPlaceObjectCommand) void {
        self.screen.setObject(self.x, self.y, self.new_type);
    }

    pub fn unexecute(self: EditorPlaceObjectCommand) void {
        self.screen.setObject(self.x, self.y, self.old_type);
    }
};

const EditorEraseObjectCommand = struct {
    screen: *MapEditorScreen,
    x: u32,
    y: u32,
    old_type: u16,

    pub fn execute(self: EditorEraseObjectCommand) void {
        self.screen.setObject(self.x, self.y, 0xFFFF);
    }

    pub fn unexecute(self: EditorEraseObjectCommand) void {
        self.screen.setObject(self.x, self.y, self.old_type);
    }
};

const CommandQueue = struct {
    command_list: std.ArrayList(EditorCommand) = undefined,
    current_position: u32 = 0,

    pub fn init(self: *CommandQueue, allocator: Allocator) void {
        self.command_list = std.ArrayList(EditorCommand).init(allocator);
    }

    pub fn reset(self: *CommandQueue) void {
        if (self.command_list.items.len > 0)
            self.command_list.clearAndFree();
    }

    pub fn deinit(self: *CommandQueue) void {
        self.command_list.deinit();
    }

    // might be useful for multiple commands at once tool?
    // otherwise ill just make a command that executes the fill, of more than one object
    pub fn addCommandMultiple(self: *CommandQueue, commands: []EditorCommand) void {
        for (commands) |command| {
            self.addCommand(command);
        }
    }

    pub fn addCommand(self: *CommandQueue, command: EditorCommand) void {
        var i = self.command_list.items.len; // might be a better method for this
        while (i > self.current_position) {
            _ = self.command_list.pop();
            i -= 1;
        }

        switch (command) {
            inline else => |c| c.execute(),
        }

        self.command_list.append(command) catch return;
        self.current_position += 1;
    }

    pub fn undo(self: *CommandQueue) void {
        if (self.current_position == 0) {
            return;
        }

        self.current_position -= 1;

        const command = self.command_list.items[self.current_position];
        switch (command) {
            inline else => |c| c.unexecute(),
        }
    }

    pub fn redo(self: *CommandQueue) void {
        if (self.current_position == self.command_list.items.len) {
            return;
        }

        const command = self.command_list.items[self.current_position];
        switch (command) {
            inline else => |c| c.execute(),
        }

        self.current_position += 1;
    }
};

pub const EditorBrush = struct {
    size: i8 = 1,
    brush_type: enum(u8) {
        rectangle = 0,
        circle = 1,
        line = 2,
    } = .rectangle,

    _visual_objects: std.ArrayList(i32) = undefined,

    _screen: *MapEditorScreen = undefined,
    _last_x: i32 = 0,
    _last_y: i32 = 0,
    _need_update: bool = false,

    pub fn init(self: *EditorBrush, allocator: Allocator, screen: *MapEditorScreen) void {
        self._visual_objects = std.ArrayList(i32).initCapacity(allocator, 5 * 5) catch return; // max brush size if 5 * 5
        self._screen = screen;
    }

    pub fn reset(self: *EditorBrush) void {
        self.size = 1;
        self.brush_type = .rectangle;
        self._visual_objects.clearAndFree();
        self._need_update = false;
        self._last_x = 0;
        self._last_y = 0;
    }

    pub fn update(self: *EditorBrush) void {
        self._need_update = true;
    }

    pub fn deinit(self: *EditorBrush) void {
        self._visual_objects.deinit();
    }

    pub fn increaseSize(self: *EditorBrush) void {
        self.size = if (self.size + 1 > 5) 1 else self.size + 1;
        self._need_update = true;
    }

    pub fn decreaseSize(self: *EditorBrush) void {
        self.size = if (self.size - 1 <= 0) 5 else self.size - 1;
        self._need_update = true;
    }

    fn updateVisual(self: *EditorBrush, center_x: u32, center_y: u32, place_type: u16) void {
        const casted_x = @as(i32, @intCast(center_x));
        const casted_y = @as(i32, @intCast(center_y));

        if (!self._need_update) {
            const dx = (casted_x - self._last_x);
            const dy = (casted_y - self._last_y);
            if (dx != 0 or dy != 0) {
                const dx_cast = @as(f32, @floatFromInt(dx));
                const dy_cast = @as(f32, @floatFromInt(dy));

                for (self._visual_objects.items) |obj_id| {
                    if (map.findEntityRef(obj_id)) |en| {
                        if (en.* == .object) {
                            const o = &en.object;
                            o.x += dx_cast;
                            o.y += dy_cast;
                        }
                    }
                }
                self._last_x = casted_x;
                self._last_y = casted_y;
            }
            return;
        }

        self._need_update = false;

        for (self._visual_objects.items) |obj_id| {
            map.removeEntity(self._screen._allocator, obj_id);
        }
        self._visual_objects.clearRetainingCapacity();

        var x: i32 = -self.size;
        while (x <= self.size) {
            var y: i32 = -self.size;
            while (y <= self.size) {
                const offset_x = casted_x + x;
                const offset_y = casted_y + y;

                if (self.brush_type == .circle and x * x + y * y > self.size * self.size) {
                    y += 1;
                    continue;
                }

                if (offset_x < 0 or offset_y < 0 or offset_x >= self._screen.map_size or offset_y >= self._screen.map_size) {
                    y += 1;
                    continue;
                }

                self._screen.simulated_object_id_next += 1;

                var obj = GameObject{
                    .x = @as(f32, @floatFromInt(offset_x)) + 0.5,
                    .y = @as(f32, @floatFromInt(offset_y)) + 0.5,
                    .obj_id = self._screen.simulated_object_id_next,
                    .obj_type = place_type,
                    .size = 100,
                    .alpha = 0.6,
                };
                obj.addToMap(self._screen._allocator);

                self._visual_objects.append(obj.obj_id) catch return;

                y += 1;
            }

            x += 1;
        }

        self._last_x = casted_x;
        self._last_y = casted_y;
    }
};

pub const MapEditorScreen = struct {
    _allocator: Allocator,
    inited: bool = false,

    simulated_object_id_next: i32 = -1,
    editor_ready: bool = false,

    map_size: u32 = 128,
    map_size_64: bool = false,
    map_size_128: bool = true,
    map_size_256: bool = false,
    map_tile_data: []MapEditorTile = &[0]MapEditorTile{},

    command_queue: CommandQueue = undefined,

    action: EditorAction = .none,
    active_layer: EditorLayer = .ground,

    active_brush: EditorBrush = undefined,

    object_type_to_place: [3]u16 = .{ 0x48, 0x600, 0 }, //0x600, 0 },

    tile_list_index: u8 = 0,
    tile_list: [8]u16 = .{ 0x48, 0x36, 0x35, 0x74, 0x70, 0x72, 0x1c, 0x0c },

    object_list: [2]u16 = .{ 0x600, 0x01c5 },
    object_list_index: u8 = 0,

    size_text_visual_64: *element.Text = undefined,
    size_text_visual_128: *element.Text = undefined,
    size_text_visual_256: *element.Text = undefined,

    text_statistics: *element.Text = undefined,
    fps_text: *element.Text = undefined,

    new_container: *element.Container = undefined,

    buttons_container: *element.Container = undefined,

    place_key_settings: settings.Button = .{ .mouse = .left },
    sample_key_settings: settings.Button = .{ .mouse = .middle },
    erase_key_settings: settings.Button = .{ .mouse = .right },
    random_key_setting: settings.Button = .{ .key = .t },

    undo_key_setting: settings.Button = .{ .key = .u },
    redo_key_setting: settings.Button = .{ .key = .r },

    ground_key_setting: settings.Button = .{ .key = .F1 },
    object_key_setting: settings.Button = .{ .key = .F2 },
    region_key_setting: settings.Button = .{ .key = .F3 },

    cycle_up_setting: settings.Button = .{ .key = .one },
    cycle_down_setting: settings.Button = .{ .key = .two },

    pub fn init(allocator: Allocator) !*MapEditorScreen {
        var screen = try allocator.create(MapEditorScreen);
        screen.* = .{ ._allocator = allocator };

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

        screen.command_queue = .{};
        screen.command_queue.init(allocator);

        screen.active_brush = .{};
        screen.active_brush.init(allocator, screen);

        const button_data_base = assets.getUiData("button_base", 0);
        const button_data_hover = assets.getUiData("button_hover", 0);
        const button_data_press = assets.getUiData("button_press", 0);

        const background_data_base = assets.getUiData("text_input_base", 0);

        const check_box_base_on = assets.getUiData("checked_box_base", 0);
        const check_box_hover_on = assets.getUiData("checked_box_hover", 0);
        const check_box_press_on = assets.getUiData("checked_box_press", 0);
        const check_box_base_off = assets.getUiData("unchecked_box_base", 0);
        const check_box_hover_off = assets.getUiData("unchecked_box_hover", 0);
        const check_box_press_off = assets.getUiData("unchecked_box_press", 0);

        const button_width = 100.0;
        const button_height = 35.0;
        const button_padding = 10.0;

        screen.text_statistics = try element.create(allocator, element.Text{
            .x = 16,
            .y = 16,
            .text_data = .{
                .text = "",
                .size = 12,
                .text_type = .bold,
                .max_chars = 512,
                .color = 0x00FFFF00,
            },
        });

        var fps_text_data = element.TextData{
            .text = "",
            .size = 12,
            .text_type = .bold,
            .max_chars = 32,
            .color = 0x00FFFF00,
        };

        {
            fps_text_data._lock.lock();
            defer fps_text_data._lock.unlock();

            fps_text_data.recalculateAttributes(allocator);
        }

        screen.fps_text = try element.create(allocator, element.Text{
            .x = camera.screen_width - fps_text_data._width - 10,
            .y = 16,
            .text_data = fps_text_data,
        });

        // buttons container (bottom left)

        screen.buttons_container = try element.create(allocator, element.Container{
            .x = 0,
            .y = camera.screen_height - button_container_height,
        });

        _ = try screen.buttons_container.createChild(element.Image{
            .x = 0,
            .y = 0,
            .image_data = .{ .nine_slice = NineSlice.fromAtlasData(background_data_base, button_container_width, button_container_height, 12, 12, 2, 2, 1.0) },
        });

        var button_offset: f32 = button_padding;

        const new_button = try screen.buttons_container.createChild(element.Button{
            .x = button_padding,
            .y = button_offset,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 11, 9, 3, 3, 1.0),
            .text_data = .{
                .text = "New",
                .size = 16,
                .text_type = .bold,
            },
            .press_callback = newCallback,
        });

        button_offset += button_height + button_padding;

        _ = try screen.buttons_container.createChild(element.Button{
            .x = button_padding,
            .y = button_offset,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 11, 9, 3, 3, 1.0),
            .text_data = .{
                .text = "Open",
                .size = 16,
                .text_type = .bold,
            },
            .press_callback = openCallback,
        });

        button_offset += button_height + button_padding;

        _ = try screen.buttons_container.createChild(element.Button{
            .x = button_padding,
            .y = button_offset,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 11, 9, 3, 3, 1.0),
            .text_data = .{
                .text = "Save",
                .size = 16,
                .text_type = .bold,
            },
            .press_callback = saveCallback,
        });

        button_offset += button_height + button_padding;

        _ = try screen.buttons_container.createChild(element.Button{
            .x = button_padding,
            .y = button_offset,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 11, 9, 3, 3, 1.0),
            .text_data = .{
                .text = "Exit",
                .size = 16,
                .text_type = .bold,
            },
            .press_callback = exitCallback,
        });

        // new container (center)

        screen.new_container = try element.create(allocator, element.Container{
            .x = (camera.screen_width - new_container_width) / 2,
            .y = (camera.screen_height - new_container_height) / 2,
            .visible = false,
        });

        _ = try screen.new_container.createChild(element.Image{
            .x = 0,
            .y = 0,
            .image_data = .{ .nine_slice = NineSlice.fromAtlasData(background_data_base, new_container_width, new_container_height, 8, 8, 32, 32, 1.0) },
        });

        var text_size_64 = element.Text{
            .x = new_container_width / 2,
            .y = 32,
            .text_data = .{
                .text = "64x64",
                .size = 20,
                .text_type = .bold,
                .hori_align = .middle,
                .vert_align = .middle,
            },
            .visible = false,
        };

        {
            text_size_64.text_data._lock.lock();
            defer text_size_64.text_data._lock.unlock();

            text_size_64.text_data.recalculateAttributes(allocator);
        }

        text_size_64.x -= text_size_64.text_data._width / 2;
        text_size_64.y -= text_size_64.text_data._height / 2;

        var text_size_128 = element.Text{
            .x = new_container_width / 2,
            .y = 32,
            .text_data = .{
                .text = "128x128",
                .size = 20,
                .text_type = .bold,
                .hori_align = .middle,
                .vert_align = .middle,
            },
            .visible = true,
        };

        {
            text_size_128.text_data._lock.lock();
            defer text_size_128.text_data._lock.unlock();

            text_size_128.text_data.recalculateAttributes(allocator);
        }

        text_size_128.x -= text_size_128.text_data._width / 2;
        text_size_128.y -= text_size_128.text_data._height / 2;

        var text_size_256 = element.Text{
            .x = new_container_width / 2,
            .y = 32,
            .text_data = .{
                .text = "256x256",
                .size = 20,
                .text_type = .bold,
                .hori_align = .middle,
                .vert_align = .middle,
            },
            .visible = false,
        };

        {
            text_size_256.text_data._lock.lock();
            defer text_size_256.text_data._lock.unlock();

            text_size_256.text_data.recalculateAttributes(allocator);
        }

        text_size_256.x -= text_size_256.text_data._width / 2;
        text_size_256.y -= text_size_256.text_data._height / 2;

        const check_padding = 5.0;

        screen.size_text_visual_64 = try screen.new_container.createChild(text_size_64);
        screen.size_text_visual_128 = try screen.new_container.createChild(text_size_128);
        screen.size_text_visual_256 = try screen.new_container.createChild(text_size_256);

        const size_64 = try screen.new_container.createChild(element.Toggle{
            .x = (new_container_width / 2) - ((check_padding + check_box_base_on.texHRaw()) / 2) * 3,
            .y = (new_container_height - check_box_base_on.texHRaw()) / 2 - check_padding,
            .off_image_data = Interactable.fromImageData(check_box_base_off, check_box_hover_off, check_box_press_off),
            .on_image_data = Interactable.fromImageData(check_box_base_on, check_box_hover_on, check_box_press_on),
            .toggled = &screen.map_size_64,
            .state_change = mapState64Changed,
        });
        const size_128 = try screen.new_container.createChild(element.Toggle{
            .x = size_64.x + size_64.width() + 5,
            .y = size_64.y,
            .off_image_data = Interactable.fromImageData(check_box_base_off, check_box_hover_off, check_box_press_off),
            .on_image_data = Interactable.fromImageData(check_box_base_on, check_box_hover_on, check_box_press_on),
            .toggled = &screen.map_size_128,
            .state_change = mapState128Changed,
        });
        _ = try screen.new_container.createChild(element.Toggle{
            .x = size_128.x + size_128.width() + 5,
            .y = size_128.y,
            .off_image_data = Interactable.fromImageData(check_box_base_off, check_box_hover_off, check_box_press_off),
            .on_image_data = Interactable.fromImageData(check_box_base_on, check_box_hover_on, check_box_press_on),
            .toggled = &screen.map_size_256,
            .state_change = mapState256Changed,
        });

        const login_button = try screen.new_container.createChild(element.Button{
            .x = (screen.new_container.width() - (button_width * 2)) / 2 - (button_padding / 2),
            .y = (new_container_height - button_height - (button_padding * 2)),
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 11, 9, 3, 3, 1.0),
            .text_data = .{
                .text = "Create",
                .size = 16,
                .text_type = .bold,
            },
            .press_callback = newCreateCallback,
        });
        _ = try screen.new_container.createChild(element.Button{
            .x = login_button.x + login_button.width() + (button_padding / 2),
            .y = login_button.y,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 11, 9, 3, 3, 1.0),
            .text_data = .{
                .text = "Cancel",
                .size = 16,
                .text_type = .bold,
            },
            .press_callback = newCloseCallback,
        });

        const place_key = try screen.buttons_container.createChild(element.KeyMapper{
            .x = new_button.x + new_button.width() + button_padding,
            .y = new_button.y,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 11, 9, 3, 3, 1.0),
            .title_text_data = .{
                .text = "Place",
                .size = 12,
                .text_type = .bold,
            },
            .key = screen.place_key_settings.getKey(),
            .mouse = screen.place_key_settings.getMouse(),
            .settings_button = &screen.place_key_settings,
            .set_key_callback = noAction,
        });
        const sample_key = try screen.buttons_container.createChild(element.KeyMapper{
            .x = place_key.x,
            .y = place_key.y + new_button.height() + button_padding,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 11, 9, 3, 3, 1.0),
            .title_text_data = .{
                .text = "Sample",
                .size = 12,
                .text_type = .bold,
            },
            .key = screen.sample_key_settings.getKey(),
            .mouse = screen.sample_key_settings.getMouse(),
            .settings_button = &screen.sample_key_settings,
            .set_key_callback = noAction,
        });
        const erase_key = try screen.buttons_container.createChild(element.KeyMapper{
            .x = sample_key.x,
            .y = sample_key.y + sample_key.height() + button_padding,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 11, 9, 3, 3, 1.0),
            .title_text_data = .{
                .text = "Erase",
                .size = 12,
                .text_type = .bold,
            },
            .key = screen.erase_key_settings.getKey(),
            .mouse = screen.erase_key_settings.getMouse(),
            .settings_button = &screen.erase_key_settings,
            .set_key_callback = noAction,
        });
        const random_key = try screen.buttons_container.createChild(element.KeyMapper{
            .x = erase_key.x,
            .y = erase_key.y + erase_key.height() + button_padding,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 11, 9, 3, 3, 1.0),
            .title_text_data = .{
                .text = "Random",
                .size = 12,
                .text_type = .bold,
            },
            .key = screen.random_key_setting.getKey(),
            .mouse = screen.random_key_setting.getMouse(),
            .settings_button = &screen.random_key_setting,
            .set_key_callback = noAction,
        });
        const undo_key = try screen.buttons_container.createChild(element.KeyMapper{
            .x = place_key.x + random_key.width() + button_padding, // random has longest text so we use that one as offset
            .y = place_key.y,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 11, 9, 3, 3, 1.0),
            .title_text_data = .{
                .text = "Undo",
                .size = 12,
                .text_type = .bold,
            },
            .key = screen.undo_key_setting.getKey(),
            .mouse = screen.undo_key_setting.getMouse(),
            .settings_button = &screen.undo_key_setting,
            .set_key_callback = noAction,
        });
        const redo_key = try screen.buttons_container.createChild(element.KeyMapper{
            .x = undo_key.x,
            .y = undo_key.y + undo_key.height() + button_padding,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 11, 9, 3, 3, 1.0),
            .title_text_data = .{
                .text = "Redo",
                .size = 12,
                .text_type = .bold,
            },
            .key = screen.redo_key_setting.getKey(),
            .mouse = screen.redo_key_setting.getMouse(),
            .settings_button = &screen.redo_key_setting,
            .set_key_callback = noAction,
        });
        const ground_layer = try screen.buttons_container.createChild(element.KeyMapper{
            .x = redo_key.x,
            .y = redo_key.y + redo_key.height() + button_padding,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 11, 9, 3, 3, 1.0),
            .title_text_data = .{
                .text = "Ground",
                .size = 12,
                .text_type = .bold,
            },
            .key = screen.ground_key_setting.getKey(),
            .mouse = screen.ground_key_setting.getMouse(),
            .settings_button = &screen.ground_key_setting,
            .set_key_callback = noAction,
        });
        const object_layer = try screen.buttons_container.createChild(element.KeyMapper{
            .x = ground_layer.x,
            .y = ground_layer.y + ground_layer.height() + button_padding,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 11, 9, 3, 3, 1.0),
            .title_text_data = .{
                .text = "Object",
                .size = 12,
                .text_type = .bold,
            },
            .key = screen.object_key_setting.getKey(),
            .mouse = screen.object_key_setting.getMouse(),
            .settings_button = &screen.object_key_setting,
            .set_key_callback = noAction,
        });
        _ = object_layer;
        const region_layer = try screen.buttons_container.createChild(element.KeyMapper{
            .x = ground_layer.x + ground_layer.width() + button_padding,
            .y = undo_key.y,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 11, 9, 3, 3, 1.0),
            .title_text_data = .{
                .text = "Region",
                .size = 12,
                .text_type = .bold,
            },
            .key = screen.region_key_setting.getKey(),
            .mouse = screen.region_key_setting.getMouse(),
            .settings_button = &screen.region_key_setting,
            .set_key_callback = noAction,
        });
        const cycle_next = try screen.buttons_container.createChild(element.KeyMapper{
            .x = region_layer.x,
            .y = region_layer.y + region_layer.height() + button_padding,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 11, 9, 3, 3, 1.0),
            .title_text_data = .{
                .text = "Next",
                .size = 12,
                .text_type = .bold,
            },
            .key = screen.cycle_up_setting.getKey(),
            .mouse = screen.cycle_up_setting.getMouse(),
            .settings_button = &screen.cycle_up_setting,
            .set_key_callback = noAction,
        });
        _ = try screen.buttons_container.createChild(element.KeyMapper{
            .x = cycle_next.x,
            .y = cycle_next.y + cycle_next.height() + button_padding,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 11, 9, 3, 3, 1.0),
            .title_text_data = .{
                .text = "Prev",
                .size = 12,
                .text_type = .bold,
            },
            .key = screen.cycle_down_setting.getKey(),
            .mouse = screen.cycle_down_setting.getMouse(),
            .settings_button = &screen.cycle_down_setting,
            .set_key_callback = noAction,
        });

        screen.inited = true;
        return screen;
    }

    fn noAction(_: *element.KeyMapper) void {}

    fn mapState64Changed(_: *element.Toggle) void {
        const screen = systems.screen.editor;
        screen.size_text_visual_64.visible = true;
        screen.size_text_visual_128.visible = false;
        screen.size_text_visual_256.visible = false;
        screen.map_size_64 = true;
        screen.map_size_128 = false;
        screen.map_size_256 = false;
        screen.map_size = 64;
    }

    fn mapState128Changed(_: *element.Toggle) void {
        const screen = systems.screen.editor;
        screen.size_text_visual_64.visible = false;
        screen.size_text_visual_128.visible = true;
        screen.size_text_visual_256.visible = false;
        screen.map_size_64 = false;
        screen.map_size_128 = true;
        screen.map_size_256 = false;
        screen.map_size = 128;
    }

    fn mapState256Changed(_: *element.Toggle) void {
        const screen = systems.screen.editor;
        screen.size_text_visual_64.visible = false;
        screen.size_text_visual_128.visible = false;
        screen.size_text_visual_256.visible = true;
        screen.map_size_64 = false;
        screen.map_size_128 = false;
        screen.map_size_256 = true;
        screen.map_size = 256;
    }

    fn newCallback() void {
        const screen = systems.screen.editor;
        screen.new_container.visible = true;
        screen.buttons_container.visible = false;

        screen.active_brush.reset();
    }

    fn newCreateCallback() void {
        const screen = systems.screen.editor;

        screen.buttons_container.visible = true;
        screen.new_container.visible = false;

        map.setWH(screen.map_size, screen.map_size);

        if (screen.map_tile_data.len == 0) {
            screen.map_tile_data = screen._allocator.alloc(MapEditorTile, screen.map_size * screen.map_size) catch return;
        } else {
            screen.map_tile_data = screen._allocator.realloc(screen.map_tile_data, screen.map_size * screen.map_size) catch return;
        }

        map.local_player_id = 0xFFFC;

        const center = @as(f32, @floatFromInt(screen.map_size)) / 2.0 + 0.5;

        for (0..screen.map_size) |y| {
            for (0..screen.map_size) |x| {
                const index = y * screen.map_size + x;
                screen.map_tile_data[index] = MapEditorTile{};
                var square = Square{
                    .x = @as(f32, @floatFromInt(x)),
                    .y = @as(f32, @floatFromInt(y)),
                    .tile_type = screen.map_tile_data[index].ground_type,
                };
                square.addToMap();
            }
        }

        var player = Player{
            .x = center,
            .y = center,
            .obj_id = map.local_player_id,
            .obj_type = 0x0300,
            .size = 100,
            .speed = 300,
        };

        player.addToMap(screen._allocator);

        main.editing_map = true;

        systems.menu_background.visible = false; // hack
    }

    fn newCloseCallback() void {
        const screen = systems.screen.editor;
        screen.reset();
    }

    fn openCallback() void {
        // if (main.editing_map) {} // maybe a popup to ask to save?

        const file_path = nfd.openFileDialog("fm", null) catch return;
        if (file_path) |path| {
            defer nfd.freePath(path);
            std.debug.print("openFileDialog result: {s}\n", .{path});

            // todo: read map
            //const file = std.fs.openFileAbsolute(file_path) catch return;
        }
    }

    fn saveCallback() void {
        if (!main.editing_map) return;

        const file_path = nfd.saveFileDialog("fm", null) catch return;
        if (file_path) |path| {
            defer nfd.freePath(path);
            std.debug.print("saveFileDialog result: {s}\n", .{path});

            // todo: write map
        }
    }

    pub fn exitCallback() void {
        systems.switchScreen(.main_menu);
    }

    fn reset(screen: *MapEditorScreen) void {
        // todo mabye need the command_queue and brush recreation?

        screen.command_queue.reset();
        screen.active_brush.reset();

        screen.buttons_container.visible = true;
        screen.new_container.visible = false;

        screen.size_text_visual_64.visible = false;
        screen.size_text_visual_128.visible = true;
        screen.size_text_visual_256.visible = false;

        screen.map_size = 128;
        screen.map_size_64 = false;
        screen.map_size_128 = true;
        screen.map_size_256 = false;

        systems.menu_background.visible = true; // hack
    }

    pub fn deinit(self: *MapEditorScreen) void {
        self.inited = false;
        systems.menu_background.visible = true; // hack

        self.reset();

        element.destroy(self.fps_text);
        element.destroy(self.text_statistics);
        element.destroy(self.new_container);
        element.destroy(self.buttons_container);

        if (self.map_tile_data.len > 0) {
            self._allocator.free(self.map_tile_data);
        }

        if (main.editing_map) {
            main.editing_map = false;
            map.dispose(self._allocator);
        }

        self._allocator.destroy(self);
    }

    pub fn resize(self: *MapEditorScreen, width: f32, height: f32) void {
        self.new_container.x = (width - self.new_container.height()) / 2;
        self.new_container.y = (height - self.new_container.height()) / 2;
        self.buttons_container.x = 0;
        self.buttons_container.y = height - self.buttons_container.height();
    }

    // flickering is happening
    // todo figure out why and fix
    // cba to find out why now
    // more noticable on larger brush sizes
    // might need different approach for doing brush visualization ngl

    pub fn onMouseMove(self: *MapEditorScreen, x: f32, y: f32) void {
        _ = y;
        _ = x;
        _ = self;
        // const _x: f32 = @floatCast(x);
        // const _y: f32 = @floatCast(y);

        // var world_point = camera.screenToWorld(_x, _y);
        // world_point.x = @max(0, @min(world_point.x, @as(f32, @floatFromInt(self.map_size - 1))));
        // world_point.y = @max(0, @min(world_point.y, @as(f32, @floatFromInt(self.map_size - 1))));

        // const floor_x: u32 = @intFromFloat(@floor(world_point.x));
        // const floor_y: u32 = @intFromFloat(@floor(world_point.y));

        // self.active_brush.update(floor_x, floor_y);
    }

    pub fn onMousePress(self: *MapEditorScreen, x: f64, y: f64, button: glfw.MouseButton) void {
        self.action = if (button == self.place_key_settings.getMouse()) .place else if (button == self.erase_key_settings.getMouse()) .erase else .none;

        if (button == self.sample_key_settings.getMouse()) {
            // only used for visual naming on the statistics
            self.action = .sample;

            const _x: f32 = @floatCast(x);
            const _y: f32 = @floatCast(y);

            var world_point = camera.screenToWorld(_x, _y);
            world_point.x = @max(0, @min(world_point.x, @as(f32, @floatFromInt(self.map_size - 1))));
            world_point.y = @max(0, @min(world_point.y, @as(f32, @floatFromInt(self.map_size - 1))));

            const floor_x: u32 = @intFromFloat(@floor(world_point.x));
            const floor_y: u32 = @intFromFloat(@floor(world_point.y));

            const current_tile = self.map_tile_data[floor_y * self.map_size + floor_x];
            const layer = @intFromEnum(self.active_layer);

            // todo add region to the sample logic

            if (self.active_layer == .ground) {
                if (current_tile.ground_type != 0xFFFC) {
                    for (0..8) |i| {
                        if (self.tile_list[i] == current_tile.ground_type) {
                            self.tile_list_index = @as(u8, @intCast(i));
                            self.object_type_to_place[layer] = current_tile.ground_type;
                            break;
                        }
                    }
                }
            } else {
                if (current_tile.object_type != 0xFFFF) {
                    for (0..2) |i| {
                        if (self.object_list[i] == current_tile.object_type) {
                            self.object_list_index = @as(u8, @intCast(i));
                            self.object_type_to_place[layer] = current_tile.object_type;
                            break;
                        }
                    }
                }
            }
        }
    }

    pub fn onMouseRelease(self: *MapEditorScreen) void {
        self.action = .none;
    }

    pub fn onKeyPress(self: *MapEditorScreen, key: glfw.Key) void {
        // could convert into as witch statement

        // switch (key) {
        //     self.cycle_down_setting => {},
        //     else => {},
        //     //etc
        // }

        if (key == .F4) {
            self.active_brush.increaseSize();
        }
        if (key == .F5) {
            self.active_brush.decreaseSize();
        }
        if (key == .F6) {
            // todo add line
            if (self.active_brush.brush_type == .circle) {
                self.active_brush.brush_type = .rectangle;
            } else {
                self.active_brush.brush_type = .circle;
            }
        }

        if (key == self.cycle_down_setting.getKey()) {
            if (self.active_layer == .ground) {
                if (self.tile_list_index == 0) { // todo remove this garbage system of index checks xd
                    self.tile_list_index = 7;
                } else {
                    self.tile_list_index -= 1;
                }
                self.object_type_to_place[@intFromEnum(self.active_layer)] = self.tile_list[self.tile_list_index];
            } else {
                if (self.object_list_index == 0) {
                    self.object_list_index = 1; // 0, 1 so 2 is 1 confusing ik
                } else {
                    self.object_list_index -= 1;
                }
                self.object_type_to_place[@intFromEnum(self.active_layer)] = self.object_list[self.object_list_index];
            }
            self.active_brush.update();
        }

        if (key == self.cycle_up_setting.getKey()) {
            if (self.active_layer == .ground) {
                self.tile_list_index = (self.tile_list_index + 1) % 8;
                self.object_type_to_place[@intFromEnum(self.active_layer)] = self.tile_list[self.tile_list_index];
            } else {
                self.object_list_index = (self.object_list_index + 1) % 2; // hmmmm
                self.object_type_to_place[@intFromEnum(self.active_layer)] = self.object_list[self.object_list_index];
            }
            self.active_brush.update();
        }

        // redo undo | has a bug where it just stops when holding need to find out why but its not the end of the world if it happens
        if (key == self.undo_key_setting.getKey()) {
            self.action = .undo;
        }

        if (key == self.redo_key_setting.getKey()) {
            self.action = .redo;
        }

        if (key == self.ground_key_setting.getKey()) {
            self.active_layer = .ground;
        }

        if (key == self.object_key_setting.getKey()) {
            self.active_layer = .object;
        }

        if (key == self.region_key_setting.getKey()) {
            self.active_layer = .region;
        }
    }

    pub fn onKeyRelease(self: *MapEditorScreen, key: glfw.Key) void {
        _ = key;
        if (self.action == .redo or self.action == .undo) {
            self.action = .none;
        }
    }

    fn setTile(self: *MapEditorScreen, x: u32, y: u32, value: u16) void {
        const index = y * self.map_size + x;
        if (self.map_tile_data[index].ground_type == value) {
            return;
        }

        self.map_tile_data[index].ground_type = value;
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
        const index = y * self.map_size + x;

        if (self.map_tile_data[index].object_type == value) {
            return;
        }

        if (value == 0xFFFF) {
            map.removeEntity(self._allocator, self.map_tile_data[index].object_id);

            self.map_tile_data[index].object_type = value;
            self.map_tile_data[index].object_id = value;
        } else {
            if (self.map_tile_data[index].object_id != -1) {
                map.removeEntity(self._allocator, self.map_tile_data[index].object_id);
            }

            self.simulated_object_id_next += 1;

            self.map_tile_data[index].object_type = value;
            self.map_tile_data[index].object_id = self.simulated_object_id_next;

            var obj = GameObject{
                .x = @as(f32, @floatFromInt(x)) + 0.5,
                .y = @as(f32, @floatFromInt(y)) + 0.5,
                .obj_id = self.simulated_object_id_next,
                .obj_type = value,
                .size = 100,
                .alpha = 1.0,
            };

            obj.addToMap(self._allocator);
        }
    }

    fn setRegion(self: *MapEditorScreen, x: u32, y: u32, value: i32) void {
        const index = y * self.map_size + x;
        self.map_tile_data[index].region_type = value;
    }

    pub fn update(self: *MapEditorScreen, _: i64, _: f32) !void {
        if (self.map_tile_data.len <= 0)
            return;

        const cam_x = camera.x.load(.Acquire);
        const cam_y = camera.y.load(.Acquire);

        var world_point = camera.screenToWorld(input.mouse_x, input.mouse_y);
        world_point.x = @max(0, @min(world_point.x, @as(f32, @floatFromInt(self.map_size - 1))));
        world_point.y = @max(0, @min(world_point.y, @as(f32, @floatFromInt(self.map_size - 1))));

        const floor_x: u32 = @intFromFloat(@floor(world_point.x));
        const floor_y: u32 = @intFromFloat(@floor(world_point.y));

        const current_tile = self.map_tile_data[floor_y * self.map_size + floor_x];
        const type_to_place = self.object_type_to_place[@intFromEnum(self.active_layer)];

        self.active_brush.updateVisual(floor_x, floor_y, type_to_place);

        switch (self.action) {
            .none => {},
            .place => {
                switch (self.active_layer) {
                    .ground => {
                        if (current_tile.ground_type != type_to_place) {
                            self.command_queue.addCommand(.{ .place_tile = .{
                                .screen = self,
                                .x = floor_x,
                                .y = floor_y,
                                .new_type = type_to_place,
                                .old_type = current_tile.ground_type,
                            } });
                        }
                    },
                    .object => {
                        if (current_tile.object_type != type_to_place) {
                            self.command_queue.addCommand(.{ .place_object = .{
                                .screen = self,
                                .x = floor_x,
                                .y = floor_y,
                                .new_type = type_to_place,
                                .old_type = current_tile.object_type,
                            } });
                        }
                    },
                    .region => {
                        self.setRegion(floor_x, floor_y, type_to_place); // todo enum stuff},
                    },
                }
            },
            .erase => {
                switch (self.active_layer) {
                    .ground => {
                        if (current_tile.ground_type != 0xFFFC) {
                            self.command_queue.addCommand(.{ .erase_tile = .{
                                .screen = self,
                                .x = floor_x,
                                .y = floor_y,
                                .old_type = current_tile.ground_type,
                            } });
                        }
                    },
                    .object => {
                        if (current_tile.object_type != 0xFFFF) {
                            self.command_queue.addCommand(.{ .erase_object = .{
                                .screen = self,
                                .x = floor_x,
                                .y = floor_y,
                                .old_type = current_tile.object_type,
                            } });
                        }
                    },
                    .region => {
                        self.setRegion(floor_x, floor_y, 0); // .none);
                    },
                }
            },
            .undo => {
                self.command_queue.undo();
            },
            .redo => {
                self.command_queue.redo();
            },
            // todo rest
            else => {},
        }

        const index = floor_y * self.map_size + floor_x;
        const data = self.map_tile_data[index];

        var place_name: []const u8 = "Unknown";
        switch (self.active_layer) {
            .ground => {
                if (game_data.ground_type_to_props.getPtr(type_to_place)) |props| {
                    place_name = props.obj_id;
                }
            },
            .object => {
                if (game_data.obj_type_to_props.getPtr(type_to_place)) |props| {
                    place_name = props.obj_id;
                }
            },
            .region => {
                // todo
            },
        }

        var hover_ground_name: []const u8 = "(Empty)";
        if (game_data.ground_type_to_props.getPtr(data.ground_type)) |props| {
            hover_ground_name = props.obj_id;
        }

        var hover_obj_name: []const u8 = "(Empty)";
        if (game_data.obj_type_to_props.getPtr(data.object_type)) |props| {
            hover_obj_name = props.obj_id;
        }

        const layer_name = if (self.active_layer == .ground) "Ground" else if (self.active_layer == .object) "Object" else "Region";
        const mode = if (self.action == .none) "None" else if (self.action == .place) "Placing" else if (self.action == .erase) "Erasing" else if (self.action == .sample) "Sampling" else if (self.action == .undo) "Undoing" else if (self.action == .redo) "Redoing" else "Idle";

        self.text_statistics.text_data.text = try std.fmt.bufPrint(self.text_statistics.text_data._backing_buffer, "Size: ({d}x{d})\n\nLayer: {s}\nPlacing: {s}\n\nMode:{s}\nBrush Size {d}\n\nGround Type: {s}\nObject Type: {s}\nRegion Type: {d}\n\nPosition ({d:.1}, {d:.1}),\nFloor: ({d}, {d})\nWorld Coordinate ({d:.1}, {d:.1})", .{
            self.map_size,
            self.map_size,
            layer_name,
            place_name,
            mode,
            self.active_brush.size,
            hover_ground_name,
            hover_obj_name,
            data.region_type, // todo enum stuff and assets xml stuff if not already done?
            cam_x,
            cam_y,
            floor_x,
            floor_y,
            world_point.x,
            world_point.y,
        });
    }

    pub fn updateFpsText(self: *MapEditorScreen, fps: usize, mem: f32) !void {
        if (!self.inited)
            return;

        self.fps_text.text_data.setText(
            try std.fmt.bufPrint(self.fps_text.text_data._backing_buffer, "FPS: {d}\nMemory: {d:.1} MB", .{ fps, mem }),
            self._allocator,
        );
        self.fps_text.x = camera.screen_width - self.fps_text.text_data._width - 10;
    }
};
