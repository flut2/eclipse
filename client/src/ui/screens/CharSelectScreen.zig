const std = @import("std");

const build_options = @import("options");
const shared = @import("shared");
const game_data = shared.game_data;
const network_data = shared.network_data;
const f32i = shared.utils.f32i;

const assets = @import("../../assets.zig");
const main = @import("../../main.zig");
const Settings = @import("../../Settings.zig");
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
    spirit_bar: *Bar,
    delete_button: *Button,
    favorite_button: *Button,
    unfavorite_button: *Button,
    char_id: u32,

    pub fn create(root: *Container, char: *const network_data.CharacterData, idx: usize) !CharacterBox {
        const data = game_data.class.from_id.getPtr(char.class_id) orelse return error.InvalidClassId;
        const anim_player_list = assets.anim_players.get(data.texture.sheet) orelse return error.TexSheetNotFound;
        if (anim_player_list.len <= data.texture.index) return error.TexIndexTooLarge;
        const tex = anim_player_list[data.texture.index].walk_anims[0];

        const base = try root.createChild(Container, .{ .base = .{
            .x = 12.0 + f32i(idx % 3) * 404.0,
            .y = 48.0 + f32i(idx / 3) * 88.0,
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

        const spirit_bar = try base.createChild(Bar, .{
            .base = .{ .x = 117, .y = 45 },
            .image_data = .{ .normal = .{ .atlas_data = assets.getUiData("character_line_spirit_bar", 0) } },
            .text_data = .{
                .text = "",
                .size = 12,
                .text_type = .bold_italic,
                .max_chars = 64,
            },
        });

        const spirit_goal = game_data.spiritGoal(char.aether);
        const spirit_perc = f32i(char.spirits_communed) / f32i(spirit_goal);
        spirit_bar.base.scissor.max_x = spirit_bar.texWRaw() * spirit_perc;
        spirit_bar.text_data.setText(
            try std.fmt.bufPrint(spirit_bar.text_data.backing_buffer, "Aether {} - {}/{}", .{
                char.aether,
                char.spirits_communed,
                spirit_goal,
            }),
        );

        const is_char_fav = std.mem.indexOfScalar(u32, main.settings.favorite_char_ids, char.char_id) != null;
        return .{
            .base = base,
            .decor = decor,
            .class_tex = try base.createChild(Image, .{
                .base = .{
                    .x = 38 + 6 + (64 - tex.width() * 5.0) / 2.0,
                    .y = 6 + (64 - tex.height() * 5.0) / 2.0,
                    .event_policy = .pass_all,
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
            .spirit_bar = spirit_bar,
            .favorite_button = try base.createChild(Button, .{
                .base = .{ .x = 0, .y = 16, .visible = !is_char_fav },
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
                .pressCallback = favCallback,
            }),
            .unfavorite_button = try base.createChild(Button, .{
                .base = .{ .x = 0, .y = 16, .visible = is_char_fav },
                .image_data = .fromImageData(
                    if (char.celestial)
                        assets.getUiData("celestial_character_unfavorite_button", 0)
                    else
                        assets.getUiData("character_unfavorite_button", 0),
                    if (char.celestial)
                        assets.getUiData("celestial_character_unfavorite_button", 1)
                    else
                        assets.getUiData("character_unfavorite_button", 1),
                    if (char.celestial)
                        assets.getUiData("celestial_character_unfavorite_button", 2)
                    else
                        assets.getUiData("character_unfavorite_button", 2),
                ),
                .userdata = @constCast(&char.char_id),
                .pressCallback = unfavCallback,
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
            .char_id = char.char_id,
        };
    }

    pub fn destroy(self: *CharacterBox, root: *Container) void {
        root.container.destroyElement(self.base);
    }

    pub fn reposition(self: *CharacterBox, idx: usize) void {
        self.base.base.x = 12.0 + f32i(idx % 3) * 404.0;
        self.base.base.y = 48.0 + f32i(idx / 3) * 88.0;
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
        if (std.mem.indexOfScalar(u32, main.settings.favorite_char_ids, char_id.*) != null) return;
        const prev_fav_len = main.settings.favorite_char_ids.len;
        const fav_char_ids = main.allocator.alloc(u32, prev_fav_len + 1) catch main.oomPanic();
        @memcpy(fav_char_ids[0..prev_fav_len], main.settings.favorite_char_ids);
        fav_char_ids[prev_fav_len] = char_id.*;
        if (Settings.needs_fav_char_id_dispose) main.allocator.free(main.settings.favorite_char_ids);
        main.settings.favorite_char_ids = fav_char_ids;
        Settings.needs_fav_char_id_dispose = true;

        if (ui_systems.screen != .char_select) return;

        for (ui_systems.screen.char_select.char_boxes) |*char_box|
            if (char_box.char_id == char_id.*) {
                char_box.favorite_button.base.visible = false;
                char_box.unfavorite_button.base.visible = true;
            };
        ui_systems.screen.char_select.rearrange();
    }

    fn unfavCallback(ud: ?*anyopaque) void {
        const char_id: *u32 = @alignCast(@ptrCast(ud));
        if (std.mem.indexOfScalar(u32, main.settings.favorite_char_ids, char_id.*) == null) return;
        const prev_fav_len = main.settings.favorite_char_ids.len;
        const fav_char_ids = main.allocator.alloc(u32, prev_fav_len - 1) catch main.oomPanic();

        delete: {
            for (main.settings.favorite_char_ids, 0..) |fav_char_id, i| {
                if (char_id.* != fav_char_id) continue;
                @memcpy(fav_char_ids[0..i], main.settings.favorite_char_ids[0..i]);
                @memcpy(fav_char_ids[i..], main.settings.favorite_char_ids[i + 1 ..]);
                break :delete;
            }
            return;
        }

        if (Settings.needs_fav_char_id_dispose) main.allocator.free(main.settings.favorite_char_ids);
        main.settings.favorite_char_ids = fav_char_ids;
        Settings.needs_fav_char_id_dispose = true;

        if (ui_systems.screen != .char_select) return;

        for (ui_systems.screen.char_select.char_boxes) |*char_box|
            if (char_box.char_id == char_id.*) {
                char_box.favorite_button.base.visible = true;
                char_box.unfavorite_button.base.visible = false;
            };
        ui_systems.screen.char_select.rearrange();
    }

    fn deleteCallback(ud: ?*anyopaque) void {
        const char_id: *u32 = @alignCast(@ptrCast(ud));
        // TODO: dialog for failure
        if (main.current_account) |acc| main.login_server.sendPacket(.{ .delete = .{
            .email = acc.email,
            .token = acc.token,
            .char_id = char_id.*,
        } });
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
    try self.refresh();
}

pub fn resize(self: *CharSelectScreen, w: f32, h: f32) void {
    self.box_container.base = .{ .x = (w - self.decor.width()) / 2.0, .y = (h - self.decor.height()) / 2.0 };
    self.name_text.text_data.max_width = w;
    self.name_text.text_data.max_height = self.box_container.base.y;
}

fn deinitExceptSelf(self: *CharSelectScreen) void {
    if (self.char_boxes.len == 0) return;
    element.destroy(self.box_container);
    element.destroy(self.name_text);
    main.allocator.free(self.char_boxes);
}

pub fn deinit(self: *CharSelectScreen) void {
    self.deinitExceptSelf();
    main.allocator.destroy(self);
}

pub fn refresh(self: *CharSelectScreen) !void {
    self.deinitExceptSelf();

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

    var num_normal: u8 = 0;
    var char_boxes: std.ArrayListUnmanaged(CharacterBox) = .empty;
    for (char_list.characters, 0..) |*char, i| {
        char_boxes.append(main.allocator, try .create(self.box_container, char, i)) catch main.oomPanic();
        if (!char.celestial) num_normal += 1;
    }
    self.char_boxes = char_boxes.toOwnedSlice(main.allocator) catch main.oomPanic();

    const max_slots: u8 = if (@intFromEnum(char_list.rank) >= @intFromEnum(network_data.Rank.celestial)) 12 else 3;
    self.new_char_button = try self.box_container.createChild(Button, .{
        .base = .{
            .x = 38.0 + 12.0 + f32i(self.char_boxes.len % 3) * 404.0,
            .y = 48.0 + f32i(self.char_boxes.len / 3) * 88.0,
            .visible = self.char_boxes.len < max_slots,
        },
        .image_data = .fromImageData(
            if (num_normal >= 3) assets.getUiData("celestial_new_character_line", 0) else assets.getUiData("new_character_line", 0),
            if (num_normal >= 3) assets.getUiData("celestial_new_character_line", 1) else assets.getUiData("new_character_line", 1),
            if (num_normal >= 3) assets.getUiData("celestial_new_character_line", 2) else assets.getUiData("new_character_line", 2),
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

    self.rearrange();
}

fn loginLessThan(_: void, a: CharacterBox, b: CharacterBox) bool {
    const a_idx = std.mem.indexOfScalar(u32, main.settings.char_ids_login_sort, a.char_id);
    const b_idx = std.mem.indexOfScalar(u32, main.settings.char_ids_login_sort, b.char_id);
    if (a_idx == null and b_idx == null) return false;
    if (a_idx == null and b_idx != null) return true;
    if (a_idx != null and b_idx == null) return false;
    return a_idx.? < b_idx.?;
}

fn favLessThan(_: void, a: CharacterBox, b: CharacterBox) bool {
    const a_idx = std.mem.indexOfScalar(u32, main.settings.favorite_char_ids, a.char_id);
    const b_idx = std.mem.indexOfScalar(u32, main.settings.favorite_char_ids, b.char_id);
    if (a_idx == null and b_idx == null) return false;
    if (a_idx == null and b_idx != null) return false;
    if (a_idx != null and b_idx == null) return true;
    return false;
}

pub fn rearrange(self: *CharSelectScreen) void {
    std.sort.block(CharacterBox, self.char_boxes, {}, loginLessThan);
    std.sort.block(CharacterBox, self.char_boxes, {}, favLessThan);
    for (self.char_boxes, 0..) |*char_box, i| char_box.reposition(i);
}

fn newCharCallback(_: ?*anyopaque) void {
    ui_systems.switchScreen(.char_create);
}

fn editorCallback(_: ?*anyopaque) void {
    ui_systems.switchScreen(.editor);
}

fn logOutCallback(_: ?*anyopaque) void {
    main.current_account = null;
    ui_systems.switchScreen(.main_menu);
}
