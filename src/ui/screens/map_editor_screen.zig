const std = @import("std");
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

const ui_systems = @import("../systems.zig");

const Player = @import("../../game/player.zig").Player;
const GameObject = @import("../../game/game_object.zig").GameObject;
const Square = @import("../../game/square.zig").Square;

const Interactable = element.InteractableImageData;
const NineSlice = element.NineSliceImageData;

const button_container_width = 420;
const button_container_height = 190;

const new_container_width = 345;
const new_container_height = 175;

// used for map parse/write
const Tile = struct { tile_type: u16, obj_type: u16, region_type: u8 };

const MapEditorTile = struct {
    object_id: i32 = -1,
    obj_type: u16 = std.math.maxInt(u16),
    tile_type: u16 = 0xFFFE,
    region_type: u8 = std.math.maxInt(u8),
};

pub const EditorCommand = union(enum) {
    place_tile: PlaceTile,
    erase_tile: EraseTile,
    place_object: PlaceObject,
    erase_object: EraseObject,
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

const PlaceTile = packed struct {
    x: u16,
    y: u16,
    new_type: u16,
    old_type: u16,

    pub fn execute(self: PlaceTile) void {
        ui_systems.screen.editor.setTile(self.x, self.y, self.new_type);
    }

    pub fn unexecute(self: PlaceTile) void {
        ui_systems.screen.editor.setTile(self.x, self.y, self.old_type);
    }
};

const EraseTile = packed struct {
    x: u16,
    y: u16,
    old_type: u16,

    pub fn execute(self: EraseTile) void {
        ui_systems.screen.editor.setTile(self.x, self.y, 0xFFFE);
    }

    pub fn unexecute(self: EraseTile) void {
        ui_systems.screen.editor.setTile(self.x, self.y, self.old_type);
    }
};

const PlaceObject = packed struct {
    x: u16,
    y: u16,
    new_type: u16,
    old_type: u16,

    pub fn execute(self: PlaceObject) void {
        ui_systems.screen.editor.setObject(self.x, self.y, self.new_type);
    }

    pub fn unexecute(self: PlaceObject) void {
        ui_systems.screen.editor.setObject(self.x, self.y, self.old_type);
    }
};

const EraseObject = struct {
    x: u16,
    y: u16,
    old_type: u16,

    pub fn execute(self: EraseObject) void {
        ui_systems.screen.editor.setObject(self.x, self.y, 0xFFFF);
    }

    pub fn unexecute(self: EraseObject) void {
        ui_systems.screen.editor.setObject(self.x, self.y, self.old_type);
    }
};

const CommandQueue = struct {
    command_list: std.ArrayList(EditorCommand) = undefined,
    current_position: u32 = 0,

    pub fn init(self: *CommandQueue, allocator: std.mem.Allocator) void {
        self.command_list = std.ArrayList(EditorCommand).init(allocator);
    }

    pub fn reset(self: *CommandQueue) void {
        if (self.command_list.items.len > 0)
            self.command_list.clearAndFree();
    }

    pub fn deinit(self: *CommandQueue) void {
        self.command_list.deinit();
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
    brush_type: enum { rectangle, circle, line } = .rectangle,
    visual_objects: std.ArrayList(i32) = undefined,
    screen: *MapEditorScreen = undefined,
    last_x: i32 = 0,
    last_y: i32 = 0,
    need_update: bool = false,

    pub fn init(self: *EditorBrush, allocator: std.mem.Allocator, screen: *MapEditorScreen) void {
        self.visual_objects = std.ArrayList(i32).initCapacity(allocator, 5 * 5) catch return; // max brush size if 5 * 5
        self.screen = screen;
    }

    pub fn reset(self: *EditorBrush) void {
        self.size = 1;
        self.brush_type = .rectangle;
        self.visual_objects.clearAndFree();
        self.need_update = false;
        self.last_x = 0;
        self.last_y = 0;
    }

    pub fn update(self: *EditorBrush) void {
        self.need_update = true;
    }

    pub fn deinit(self: *EditorBrush) void {
        self.visual_objects.deinit();
    }

    pub fn increaseSize(self: *EditorBrush) void {
        self.size = if (self.size + 1 > 5) 1 else self.size + 1;
        self.need_update = true;
    }

    pub fn decreaseSize(self: *EditorBrush) void {
        self.size = if (self.size - 1 <= 0) 5 else self.size - 1;
        self.need_update = true;
    }

    fn updateVisual(self: *EditorBrush, center_x: u32, center_y: u32, place_type: u16) void {
        const casted_x = @as(i32, @intCast(center_x));
        const casted_y = @as(i32, @intCast(center_y));

        if (!self.need_update) {
            const dx = (casted_x - self.last_x);
            const dy = (casted_y - self.last_y);
            if (dx != 0 or dy != 0) {
                const dx_cast = @as(f32, @floatFromInt(dx));
                const dy_cast = @as(f32, @floatFromInt(dy));

                for (self.visual_objects.items) |obj_id| {
                    map.object_lock.lock();
                    defer map.object_lock.unlock();

                    if (map.findEntityRef(obj_id)) |en| {
                        if (en.* == .object) {
                            const o = &en.object;
                            o.x += dx_cast;
                            o.y += dy_cast;
                        }
                    }
                }
                self.last_x = casted_x;
                self.last_y = casted_y;
            }
            return;
        }

        self.need_update = false;

        for (self.visual_objects.items) |obj_id| {
            map.removeEntity(self.screen.allocator, obj_id);
        }
        self.visual_objects.clearRetainingCapacity();

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

                if (offset_x < 0 or offset_y < 0 or offset_x >= self.screen.map_size or offset_y >= self.screen.map_size) {
                    y += 1;
                    continue;
                }

                self.screen.next_obj_id += 1;

                var obj = GameObject{
                    .x = @as(f32, @floatFromInt(offset_x)),
                    .y = @as(f32, @floatFromInt(offset_y)),
                    .obj_id = self.screen.next_obj_id,
                    .obj_type = place_type,
                    .size = 100,
                    .alpha = 0.6,
                };
                obj.addToMap(self.screen.allocator, true);

                self.visual_objects.append(obj.obj_id) catch return;

                y += 1;
            }

            x += 1;
        }

        self.last_x = casted_x;
        self.last_y = casted_y;
    }
};

pub const MapEditorScreen = struct {
    allocator: std.mem.Allocator,
    inited: bool = false,

    next_obj_id: i32 = -1,
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

    fps_text: *element.Text = undefined,

    new_container: *element.Container = undefined,

    buttons_container: *element.Container = undefined,

    place_key_settings: settings.Button = .{ .mouse = .left },
    sample_key_settings: settings.Button = .{ .mouse = .middle },
    erase_key_settings: settings.Button = .{ .mouse = .right },
    random_key_setting: settings.Button = .{ .key = .t },

    undo_key_setting: settings.Button = .{ .key = .u },
    redo_key_setting: settings.Button = .{ .key = .r },

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

        screen.command_queue = .{};
        screen.command_queue.init(allocator);

        screen.active_brush = .{};
        screen.active_brush.init(allocator, screen);

        const button_data_base = assets.getUiData("button_base", 0);
        const button_data_hover = assets.getUiData("button_hover", 0);
        const button_data_press = assets.getUiData("button_press", 0);

        const background_data_base = assets.getUiData("dialog_title_background", 0);

        const check_box_base_on = assets.getUiData("checked_box_base", 0);
        const check_box_hover_on = assets.getUiData("checked_box_hover", 0);
        const check_box_press_on = assets.getUiData("checked_box_press", 0);
        const check_box_base_off = assets.getUiData("unchecked_box_base", 0);
        const check_box_hover_off = assets.getUiData("unchecked_box_hover", 0);
        const check_box_press_off = assets.getUiData("unchecked_box_press", 0);

        const button_width = 100.0;
        const button_height = 35.0;
        const button_padding = 10.0;

        const key_mapper_width = 35.0;
        const key_mapper_height = 35.0;

        var fps_text_data = element.TextData{
            .text = "",
            .size = 12,
            .text_type = .bold,
            .max_chars = 64,
            .color = 0xFFFF00,
        };

        {
            fps_text_data.lock.lock();
            defer fps_text_data.lock.unlock();

            fps_text_data.recalculateAttributes(allocator);
        }

        screen.fps_text = try element.create(allocator, element.Text{
            .x = camera.screen_width - fps_text_data.width - 10,
            .y = 16,
            .text_data = fps_text_data,
        });

        screen.buttons_container = try element.create(allocator, element.Container{
            .x = 0,
            .y = camera.screen_height - button_container_height,
        });

        _ = try screen.buttons_container.createChild(element.Image{
            .x = 0,
            .y = 0,
            .image_data = .{ .nine_slice = NineSlice.fromAtlasData(background_data_base, button_container_width, button_container_height, 6, 11, 2, 2, 1.0) },
        });

        var button_offset: f32 = button_padding;

        const new_button = try screen.buttons_container.createChild(element.Button{
            .x = button_padding,
            .y = button_offset,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 26, 21, 3, 3, 1.0),
            .text_data = .{
                .text = "New",
                .size = 16,
                .text_type = .bold,
            },
            .userdata = screen,
            .press_callback = newCallback,
        });

        button_offset += button_height + button_padding;

        _ = try screen.buttons_container.createChild(element.Button{
            .x = button_padding,
            .y = button_offset,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 26, 21, 3, 3, 1.0),
            .text_data = .{
                .text = "Open",
                .size = 16,
                .text_type = .bold,
            },
            .userdata = screen,
            .press_callback = openCallback,
        });

        button_offset += button_height + button_padding;

        _ = try screen.buttons_container.createChild(element.Button{
            .x = button_padding,
            .y = button_offset,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 26, 21, 3, 3, 1.0),
            .text_data = .{
                .text = "Save",
                .size = 16,
                .text_type = .bold,
            },
            .userdata = screen,
            .press_callback = saveCallback,
        });

        button_offset += button_height + button_padding;

        _ = try screen.buttons_container.createChild(element.Button{
            .x = button_padding,
            .y = button_offset,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 26, 21, 3, 3, 1.0),
            .text_data = .{
                .text = "Exit",
                .size = 16,
                .text_type = .bold,
            },
            .press_callback = exitCallback,
        });

        screen.new_container = try element.create(allocator, element.Container{
            .x = (camera.screen_width - new_container_width) / 2,
            .y = (camera.screen_height - new_container_height) / 2,
            .visible = false,
        });

        _ = try screen.new_container.createChild(element.Image{
            .x = 0,
            .y = 0,
            .image_data = .{ .nine_slice = NineSlice.fromAtlasData(background_data_base, new_container_width, new_container_height, 6, 11, 2, 2, 1.0) },
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
            text_size_64.text_data.lock.lock();
            defer text_size_64.text_data.lock.unlock();

            text_size_64.text_data.recalculateAttributes(allocator);
        }

        text_size_64.x -= text_size_64.text_data.width / 2;
        text_size_64.y -= text_size_64.text_data.height / 2;

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
            text_size_128.text_data.lock.lock();
            defer text_size_128.text_data.lock.unlock();

            text_size_128.text_data.recalculateAttributes(allocator);
        }

        text_size_128.x -= text_size_128.text_data.width / 2;
        text_size_128.y -= text_size_128.text_data.height / 2;

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
            text_size_256.text_data.lock.lock();
            defer text_size_256.text_data.lock.unlock();

            text_size_256.text_data.recalculateAttributes(allocator);
        }

        text_size_256.x -= text_size_256.text_data.width / 2;
        text_size_256.y -= text_size_256.text_data.height / 2;

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
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 26, 21, 3, 3, 1.0),
            .text_data = .{
                .text = "Create",
                .size = 16,
                .text_type = .bold,
            },
            .userdata = screen,
            .press_callback = newCreateCallback,
        });
        _ = try screen.new_container.createChild(element.Button{
            .x = login_button.x + login_button.width() + (button_padding / 2),
            .y = login_button.y,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, button_width, button_height, 26, 21, 3, 3, 1.0),
            .text_data = .{
                .text = "Cancel",
                .size = 16,
                .text_type = .bold,
            },
            .userdata = screen,
            .press_callback = newCloseCallback,
        });

        const place_key = try screen.buttons_container.createChild(element.KeyMapper{
            .x = new_button.x + new_button.width() + button_padding,
            .y = new_button.y,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, key_mapper_width, key_mapper_height, 26, 21, 3, 3, 1.0),
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
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, key_mapper_width, key_mapper_height, 26, 21, 3, 3, 1.0),
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
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, key_mapper_width, key_mapper_height, 26, 21, 3, 3, 1.0),
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
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, key_mapper_width, key_mapper_height, 26, 21, 3, 3, 1.0),
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
            .x = place_key.x + random_key.width() + button_padding,
            .y = place_key.y,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, key_mapper_width, key_mapper_height, 26, 21, 3, 3, 1.0),
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
        _ = try screen.buttons_container.createChild(element.KeyMapper{
            .x = undo_key.x,
            .y = undo_key.y + undo_key.height() + button_padding,
            .image_data = Interactable.fromNineSlices(button_data_base, button_data_hover, button_data_press, key_mapper_width, key_mapper_height, 26, 21, 3, 3, 1.0),
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

        screen.inited = true;
        return screen;
    }

    fn noAction(_: *element.KeyMapper) void {}

    fn mapState64Changed(_: *element.Toggle) void {
        const screen = ui_systems.screen.editor;
        screen.size_text_visual_64.visible = true;
        screen.size_text_visual_128.visible = false;
        screen.size_text_visual_256.visible = false;
        screen.map_size_64 = true;
        screen.map_size_128 = false;
        screen.map_size_256 = false;
        screen.map_size = 64;
    }

    fn mapState128Changed(_: *element.Toggle) void {
        const screen = ui_systems.screen.editor;
        screen.size_text_visual_64.visible = false;
        screen.size_text_visual_128.visible = true;
        screen.size_text_visual_256.visible = false;
        screen.map_size_64 = false;
        screen.map_size_128 = true;
        screen.map_size_256 = false;
        screen.map_size = 128;
    }

    fn mapState256Changed(_: *element.Toggle) void {
        const screen = ui_systems.screen.editor;
        screen.size_text_visual_64.visible = false;
        screen.size_text_visual_128.visible = false;
        screen.size_text_visual_256.visible = true;
        screen.map_size_64 = false;
        screen.map_size_128 = false;
        screen.map_size_256 = true;
        screen.map_size = 256;
    }

    fn newCallback(ud: ?*anyopaque) void {
        const screen: *MapEditorScreen = @alignCast(@ptrCast(ud.?));
        screen.new_container.visible = true;
        screen.buttons_container.visible = false;

        screen.active_brush.reset();
    }

    fn newCreateCallback(ud: ?*anyopaque) void {
        const screen: *MapEditorScreen = @alignCast(@ptrCast(ud.?));

        screen.buttons_container.visible = true;
        screen.new_container.visible = false;

        map.dispose(screen.allocator);
        map.setWH(screen.map_size, screen.map_size);
        map.bg_light_color = 0;
        map.bg_light_intensity = 0.15;

        if (screen.map_tile_data.len != 0) {
            screen.map_tile_data = screen.allocator.alloc(MapEditorTile, screen.map_size * screen.map_size) catch return;
        } else {
            screen.map_tile_data = screen.allocator.realloc(screen.map_tile_data, screen.map_size * screen.map_size) catch return;
        }

        @memset(screen.map_tile_data, MapEditorTile{});

        map.local_player_id = 0xFFFE;

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

        var player = Player{
            .x = center,
            .y = center,
            .obj_id = map.local_player_id,
            .obj_type = 0x0300,
            .size = 100,
            .speed = 300,
        };
        player.addToMap(screen.allocator);

        main.editing_map = true;

        ui_systems.menu_background.visible = false; // hack
    }

    fn newCloseCallback(ud: ?*anyopaque) void {
        const screen: *MapEditorScreen = @alignCast(@ptrCast(ud.?));
        screen.reset();
    }

    // for easier error handling
    fn openInner(screen: *MapEditorScreen) !void {
        // if (main.editing_map) {} // maybe a popup to ask to save?

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

            screen.map_size = 256;
            screen.map_size_256 = true;
            screen.map_size_128 = false;
            screen.map_size_64 = false;
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

    fn saveInner(screen: *MapEditorScreen) !void {
        if (!main.editing_map) return;

        const file_path = nfd.saveFileDialog("em", null) catch return;
        if (file_path) |path| {
            defer nfd.freePath(path);

            var data = std.ArrayList(u8).init(screen.allocator);
            defer data.deinit();

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

            const file = try std.fs.createFileAbsolute(path, .{});
            defer file.close();

            var fbs = std.io.fixedBufferStream(data.items);
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

    pub fn exitCallback(_: ?*anyopaque) void {
        ui_systems.switchScreen(.main_menu);
    }

    fn reset(screen: *MapEditorScreen) void {
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

        ui_systems.menu_background.visible = true;
    }

    pub fn deinit(self: *MapEditorScreen) void {
        self.inited = false;
        ui_systems.menu_background.visible = true;

        self.reset();

        element.destroy(self.fps_text);
        element.destroy(self.new_container);
        element.destroy(self.buttons_container);

        if (self.map_tile_data.len > 0) {
            self.allocator.free(self.map_tile_data);
        }

        if (main.editing_map) {
            main.editing_map = false;
            map.dispose(self.allocator);
        }

        self.allocator.destroy(self);
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

            if (self.active_layer == .ground) {
                if (current_tile.tile_type != 0xFFFE) {
                    for (0..8) |i| {
                        if (self.tile_list[i] == current_tile.tile_type) {
                            self.tile_list_index = @as(u8, @intCast(i));
                            self.object_type_to_place[layer] = current_tile.tile_type;
                            break;
                        }
                    }
                }
            } else {
                if (current_tile.obj_type != 0xFFFF) {
                    for (0..2) |i| {
                        if (self.object_list[i] == current_tile.obj_type) {
                            self.object_list_index = @as(u8, @intCast(i));
                            self.object_type_to_place[layer] = current_tile.obj_type;
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

        if (key == self.undo_key_setting.getKey()) {
            self.action = .undo;
        }

        if (key == self.redo_key_setting.getKey()) {
            self.action = .redo;
        }
    }

    pub fn onKeyRelease(self: *MapEditorScreen, key: glfw.Key) void {
        if (key == self.undo_key_setting.getKey() or key == self.redo_key_setting.getKey()) {
            self.action = .none;
        }
    }

    fn setTile(self: *MapEditorScreen, x: u32, y: u32, value: u16) void {
        const index = y * self.map_size + x;
        if (self.map_tile_data[index].tile_type == value) {
            return;
        }

        self.map_tile_data[index].tile_type = value;
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

        if (self.map_tile_data[index].obj_type == value) {
            return;
        }

        if (value == std.math.maxInt(u16)) {
            map.removeEntity(self.allocator, self.map_tile_data[index].object_id);

            self.map_tile_data[index].obj_type = value;
            self.map_tile_data[index].object_id = value;
        } else {
            if (self.map_tile_data[index].object_id != -1) {
                map.removeEntity(self.allocator, self.map_tile_data[index].object_id);
            }

            self.next_obj_id += 1;

            self.map_tile_data[index].obj_type = value;
            self.map_tile_data[index].object_id = self.next_obj_id;

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
        const index = y * self.map_size + x;
        self.map_tile_data[index].region_type = value;
    }

    pub fn update(self: *MapEditorScreen, _: i64, _: f32) !void {
        if (self.map_tile_data.len <= 0)
            return;

        var world_point = camera.screenToWorld(input.mouse_x, input.mouse_y);
        world_point.x = @max(0, @min(world_point.x, @as(f32, @floatFromInt(self.map_size - 1))));
        world_point.y = @max(0, @min(world_point.y, @as(f32, @floatFromInt(self.map_size - 1))));

        const floor_x: u16 = @intFromFloat(@floor(world_point.x));
        const floor_y: u16 = @intFromFloat(@floor(world_point.y));

        const current_tile = self.map_tile_data[floor_y * self.map_size + floor_x];
        const type_to_place = self.object_type_to_place[@intFromEnum(self.active_layer)];

        self.active_brush.updateVisual(floor_x, floor_y, type_to_place);

        switch (self.action) {
            .none => {},
            .place => {
                switch (self.active_layer) {
                    .ground => {
                        if (current_tile.tile_type != type_to_place) {
                            self.command_queue.addCommand(.{ .place_tile = .{
                                .x = floor_x,
                                .y = floor_y,
                                .new_type = type_to_place,
                                .old_type = current_tile.tile_type,
                            } });
                        }
                    },
                    .object => {
                        if (current_tile.obj_type != type_to_place) {
                            self.command_queue.addCommand(.{ .place_object = .{
                                .x = floor_x,
                                .y = floor_y,
                                .new_type = type_to_place,
                                .old_type = current_tile.obj_type,
                            } });
                        }
                    },
                    .region => {
                        self.setRegion(floor_x, floor_y, @intCast(type_to_place)); // todo enum stuff},
                    },
                }
            },
            .erase => {
                switch (self.active_layer) {
                    .ground => {
                        if (current_tile.tile_type != 0xFFFE) {
                            self.command_queue.addCommand(.{ .erase_tile = .{
                                .x = floor_x,
                                .y = floor_y,
                                .old_type = current_tile.tile_type,
                            } });
                        }
                    },
                    .object => {
                        if (current_tile.obj_type != 0xFFFF) {
                            self.command_queue.addCommand(.{ .erase_object = .{
                                .x = floor_x,
                                .y = floor_y,
                                .old_type = current_tile.obj_type,
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
        if (game_data.ground_type_to_props.getPtr(data.tile_type)) |props| {
            hover_ground_name = props.obj_id;
        }

        var hover_obj_name: []const u8 = "(Empty)";
        if (game_data.obj_type_to_props.getPtr(data.obj_type)) |props| {
            hover_obj_name = props.obj_id;
        }
    }

    pub fn updateFpsText(self: *MapEditorScreen, fps: usize, mem: f32) !void {
        if (!self.inited)
            return;

        self.fps_text.text_data.setText(
            try std.fmt.bufPrint(self.fps_text.text_data.backing_buffer, "FPS: {d}\nMemory: {d:.1} MB", .{ fps, mem }),
            self.allocator,
        );
        self.fps_text.x = camera.screen_width - self.fps_text.text_data.width - 10;
    }
};
