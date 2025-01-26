const std = @import("std");

const build_options = @import("options");
const shared = @import("shared");
const game_data = shared.game_data;
const network_data = shared.network_data;
const f32i = shared.utils.f32i;

const assets = @import("../../assets.zig");
const main = @import("../../main.zig");
const Bar = @import("../elements/Bar.zig");
const Button = @import("../elements/Button.zig");
const Container = @import("../elements/Container.zig");
const Dropdown = @import("../elements/Dropdown.zig");
const element = @import("../elements/element.zig");
const Image = @import("../elements/Image.zig");
const Text = @import("../elements/Text.zig");
const ui_systems = @import("../systems.zig");

const CharSelectScreen = @This();

const CharacterBox = struct {
    base: *Container,
    decor: *Button,
    class_tex: *Image,
    class_name: *Text,
    aether_bar: *Bar,
    delete_button: *Button,
    favorite_button: *Button,

    pub fn create(root: *Container, char: *const network_data.CharacterData, idx: usize) !CharacterBox {
        const data = game_data.class.from_id.getPtr(char.class_id) orelse return error.InvalidClassId;
        const anim_player_list = assets.anim_players.get(data.texture.sheet) orelse return error.TexSheetNotFound;
        if (anim_player_list.len <= data.texture.index) return error.TexIndexTooLarge;
        const tex = anim_player_list[data.texture.index].walk_anims[0];

        const base = try root.createChild(Container, .{ .base = .{
            .x = 12.0 + f32i(idx % 4) * 404.0,
            .y = 48.0 + f32i(idx / 4) * 88.0,
        } });

        const decor = try base.createChild(Button, .{
            .base = .{ .x = 38, .y = 0 },
            .image_data = .fromImageData(
                if (char.celestial) assets.getUiData("celestial_character_line", 0) else assets.getUiData("character_line", 0),
                if (char.celestial) assets.getUiData("celestial_character_line", 1) else assets.getUiData("character_line", 1),
                if (char.celestial) assets.getUiData("celestial_character_line", 2) else assets.getUiData("character_line", 2),
            ),
            .userdata = @constCast(&char.char_id),
            .pressCallback = charCallback,
            .char = char,
        });

        const aether_bar = try base.createChild(Bar, .{
            .base = .{ .x = 117, .y = 45 },
            .image_data = .{ .normal = .{ .atlas_data = assets.getUiData("character_line_aether_bar", 0) } },
            .text_data = .{
                .text = "",
                .size = 12,
                .text_type = .bold_italic,
                .max_chars = 64,
            },
        });

        const aether_goal = game_data.spiritGoal(char.aether);
        const aether_perc = f32i(char.spirits_communed) / f32i(aether_goal);
        aether_bar.base.scissor.max_x = aether_bar.texWRaw() * aether_perc;
        aether_bar.text_data.setText(
            try std.fmt.bufPrint(aether_bar.text_data.backing_buffer, "Aether {} - {}/{}", .{
                char.aether,
                char.spirits_communed,
                aether_goal,
            }),
        );

        return .{
            .base = base,
            .decor = decor,
            .class_tex = try base.createChild(Image, .{
                .base = .{
                    .x = 38 + 6 + (64 - tex.width() * 5.0) / 2.0,
                    .y = 6 + (64 - tex.height() * 5.0) / 2.0,
                },
                .image_data = .{ .normal = .{ .atlas_data = tex, .scale_x = 5.0, .scale_y = 5.0 } },
            }),
            .class_name = try base.createChild(Text, .{ .base = .{ .x = 38 + 77, .y = 5 }, .text_data = .{
                .text = data.name,
                .size = 20,
                .text_type = .bold,
                .hori_align = .middle,
                .vert_align = .middle,
                .max_width = 229,
                .max_height = 26,
            } }),
            .aether_bar = aether_bar,
            .favorite_button = try base.createChild(Button, .{
                .base = .{ .x = 0, .y = 16 },
                .image_data = .fromImageData(
                    if (char.celestial)
                        assets.getUiData("celestial_character_favorite_button", 0)
                    else
                        assets.getUiData("character_favorite_button", 0),
                    if (char.celestial)
                        assets.getUiData("celestial_character_favorite_button", 1)
                    else
                        assets.getUiData("character_favorite_button", 1),
                    if (char.celestial)
                        assets.getUiData("celestial_character_favorite_button", 2)
                    else
                        assets.getUiData("character_favorite_button", 2),
                ),
                .userdata = @constCast(&char.char_id),
                .pressCallback = deleteCallback,
            }),
            .delete_button = try base.createChild(Button, .{
                .base = .{ .x = 350, .y = 16 },
                .image_data = .fromImageData(
                    if (char.celestial)
                        assets.getUiData("celestial_character_delete_button", 0)
                    else
                        assets.getUiData("character_delete_button", 0),
                    if (char.celestial)
                        assets.getUiData("celestial_character_delete_button", 1)
                    else
                        assets.getUiData("character_delete_button", 1),
                    if (char.celestial)
                        assets.getUiData("celestial_character_delete_button", 2)
                    else
                        assets.getUiData("character_delete_button", 2),
                ),
                .userdata = @constCast(&char.char_id),
                .pressCallback = deleteCallback,
            }),
        };
    }

    pub fn destroy(self: *CharacterBox, root: *Container) void {
        root.container.destroyElement(self.base);
    }

    fn charCallback(ud: ?*anyopaque) void {
        const char_id: *u32 = @alignCast(@ptrCast(ud));
        if (main.character_list) |list| if (list.servers.len > 0) {
            main.enterGame(list.servers[0], char_id.*, std.math.maxInt(u16));
            return;
        };

        std.log.err("No servers found", .{});
    }

    fn favCallback(ud: ?*anyopaque) void {
        const char_id: *u32 = @alignCast(@ptrCast(ud));
        _ = char_id;
    }

    fn deleteCallback(ud: ?*anyopaque) void {
        const char_id: *u32 = @alignCast(@ptrCast(ud));
        _ = char_id;
    }
};

box_container: *Container = undefined,
decor: *Image = undefined,
char_boxes: []CharacterBox = &.{},
new_char_button: *Button = undefined,

name_text: *Text = undefined,
gold_text: *Text = undefined,
gems_text: *Text = undefined,

pub fn init(self: *CharSelectScreen) !void {
    // TODO: dialog for these
    const char_list = main.character_list orelse return;
    if (char_list.characters.len == 0 or char_list.servers.len == 0) return;

    const button_base = assets.getUiData("button_base", 0);
    const button_hover = assets.getUiData("button_hover", 0);
    const button_press = assets.getUiData("button_press", 0);
    const button_w = 100;
    const button_h = 40;

    main.camera.lock.lock();
    const cam_w = main.camera.width;
    const cam_h = main.camera.height;
    main.camera.lock.unlock();

    const decor = assets.getUiData("character_list_background", 0);
    self.box_container = try element.create(Container, .{
        .base = .{ .x = (cam_w - decor.width()) / 2.0, .y = (cam_h - decor.height()) / 2.0 },
    });

    self.decor = try self.box_container.createChild(Image, .{
        .base = .{ .x = 0.0, .y = 0.0 },
        .image_data = .{ .normal = .{ .atlas_data = decor } },
    });

    var num_celestial: u8 = 0;
    var char_boxes: std.ArrayListUnmanaged(CharacterBox) = .empty;
    for (char_list.characters, 0..) |*char, i| {
        char_boxes.append(main.allocator, try .create(self.box_container, char, i)) catch main.oomPanic();
        if (char.celestial) num_celestial += 1;
    }
    self.char_boxes = char_boxes.toOwnedSlice(main.allocator) catch main.oomPanic();

    const max_slots: u8 = if (@intFromEnum(char_list.rank) >= @intFromEnum(network_data.Rank.celestial)) 12 else 3;
    self.new_char_button = try self.box_container.createChild(Button, .{
        .base = .{
            .x = 38.0 + 12.0 + f32i(self.char_boxes.len % 4) * 404.0,
            .y = 48.0 + f32i(self.char_boxes.len / 4) * 88.0,
            .visible = self.char_boxes.len < max_slots,
        },
        .image_data = .fromImageData(
            if (num_celestial > 3) assets.getUiData("celestial_new_character_line", 0) else assets.getUiData("new_character_line", 0),
            if (num_celestial > 3) assets.getUiData("celestial_new_character_line", 1) else assets.getUiData("new_character_line", 1),
            if (num_celestial > 3) assets.getUiData("celestial_new_character_line", 2) else assets.getUiData("new_character_line", 2),
        ),
        .pressCallback = newCharCallback,
        .text_offset_x = 77,
        .text_offset_y = 12,
        .text_data = .{
            .text = "Create a New Character",
            .size = 16,
            .text_type = .bold,
            .hori_align = .middle,
            .vert_align = .middle,
            .max_width = 229,
            .max_height = 52,
        },
    });

    self.gold_text = try self.box_container.createChild(Text, .{ .base = .{ .x = 1032.0, .y = 5.0 }, .text_data = .{
        .text = "",
        .size = 10,
        .max_chars = 32,
        .hori_align = .middle,
        .vert_align = .middle,
        .max_width = 77,
        .max_height = 26,
    } });
    self.gold_text.text_data.setText(
        try std.fmt.bufPrint(self.gold_text.text_data.backing_buffer, "{}", .{char_list.gold}),
    );

    self.gems_text = try self.box_container.createChild(Text, .{ .base = .{ .x = 1150.0, .y = 5.0 }, .text_data = .{
        .text = "",
        .size = 10,
        .max_chars = 32,
        .hori_align = .middle,
        .vert_align = .middle,
        .max_width = 77,
        .max_height = 26,
    } });
    self.gems_text.text_data.setText(
        try std.fmt.bufPrint(self.gems_text.text_data.backing_buffer, "{}", .{char_list.gems}),
    );

    self.name_text = try element.create(Text, .{
        .base = .{ .x = 0.0, .y = 0.0 },
        .text_data = .{
            .text = "",
            .size = 36,
            .max_chars = 32,
            .hori_align = .middle,
            .vert_align = .middle,
            .max_width = cam_w,
            .max_height = self.box_container.base.y,
            .outline_width = 2.5,
        },
    });
    self.name_text.text_data.setText(
        try std.fmt.bufPrint(self.name_text.text_data.backing_buffer, "{s}", .{char_list.name}),
    );

    const decor_h = decor.height();
    const log_out_button = try self.box_container.createChild(Button, .{
        .base = .{ .x = decor.width() - button_w, .y = decor_h + 10 },
        .image_data = .fromNineSlices(button_base, button_hover, button_press, button_w, button_h, 26, 19, 1, 1, 1.0),
        .text_data = .{
            .text = "Log Out",
            .size = 16,
            .text_type = .bold,
        },
        .pressCallback = logOutCallback,
    });

    if (@intFromEnum(char_list.rank) >= @intFromEnum(network_data.Rank.mod))
        _ = try self.box_container.createChild(Button, .{
            .base = .{ .x = log_out_button.base.x, .y = decor_h + 10 + button_h + 10 },
            .image_data = .fromNineSlices(button_base, button_hover, button_press, button_w, button_h, 26, 19, 1, 1, 1.0),
            .text_data = .{
                .text = "Editor",
                .size = 16,
                .text_type = .bold,
            },
            .pressCallback = editorCallback,
        });
}

pub fn resize(self: *CharSelectScreen, w: f32, h: f32) void {
    self.box_container.base = .{ .x = (w - self.decor.width()) / 2.0, .y = (h - self.decor.height()) / 2.0 };
    self.name_text.text_data.max_width = w;
    self.name_text.text_data.max_height = self.box_container.base.y;
}

pub fn deinit(self: *CharSelectScreen) void {
    element.destroy(self.box_container);
    element.destroy(self.name_text);
    main.allocator.free(self.char_boxes);
    main.allocator.destroy(self);
}

fn newCharCallback(_: ?*anyopaque) void {
    ui_systems.switchScreen(.char_create);
}

pub fn editorCallback(_: ?*anyopaque) void {
    ui_systems.switchScreen(.editor);
}

pub fn logOutCallback(_: ?*anyopaque) void {
    main.current_account = null;
    ui_systems.switchScreen(.main_menu);
}
