const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const f32i = shared.utils.f32i;

const assets = @import("../../assets.zig");
const input = @import("../../input.zig");
const main = @import("../../main.zig");
const Button = @import("../elements/Button.zig");
const Container = @import("../elements/Container.zig");
const element = @import("../elements/element.zig");
const Image = @import("../elements/Image.zig");
const Text = @import("../elements/Text.zig");
const systems = @import("../systems.zig");

const CardSelection = @This();
const card_w = 300;
const card_h = 350;
const card_padding = 30;

const SelectableCard = struct {
    base: *Container,
    button: *Button,
    title: *Text,
    line_break: *Image,
    description: *Text,

    fn buttonData(rarity: game_data.CardRarity) struct { assets.AtlasData, assets.AtlasData, assets.AtlasData } {
        return switch (rarity) {
            .mythic => .{
                assets.getUiData("tooltip_background_mythic", 0),
                assets.getUiData("tooltip_background_mythic", 1),
                assets.getUiData("tooltip_background_mythic", 2),
            },
            .legendary => .{
                assets.getUiData("tooltip_background_legendary", 0),
                assets.getUiData("tooltip_background_legendary", 1),
                assets.getUiData("tooltip_background_legendary", 2),
            },
            .epic => .{
                assets.getUiData("tooltip_background_epic", 0),
                assets.getUiData("tooltip_background_epic", 1),
                assets.getUiData("tooltip_background_epic", 2),
            },
            .rare => .{
                assets.getUiData("tooltip_background_rare", 0),
                assets.getUiData("tooltip_background_rare", 1),
                assets.getUiData("tooltip_background_rare", 2),
            },
            .common => .{
                assets.getUiData("tooltip_background", 0),
                assets.getUiData("tooltip_background", 1),
                assets.getUiData("tooltip_background", 2),
            },
        };
    }

    pub fn create(selection: *CardSelection, root: *Container, x: f32, y: f32, buttonCallback: fn (?*anyopaque) void) !SelectableCard {
        var self: SelectableCard = undefined;
        self.base = try root.createChild(Container, .{ .base = .{ .x = x, .y = y } });

        const button_base, const button_hover, const button_press = buttonData(.common);
        self.button = try self.base.createChild(Button, .{
            .base = .{ .x = 0, .y = 0 },
            .image_data = .fromNineSlices(button_base, button_hover, button_press, 300, 350, 26, 19, 1, 1, 1.0),
            .userdata = selection,
            .pressCallback = buttonCallback,
        });

        const inset_x = 6;
        self.title = try self.base.createChild(Text, .{
            .base = .{ .x = inset_x, .y = 6 },
            .text_data = .{
                .text = "",
                .size = 28,
                .text_type = .bold_italic,
                .vert_align = .middle,
                .hori_align = .middle,
                .max_width = 300 - 6 * 2,
                .max_height = 100,
            },
        });

        const tooltip_line_spacer_top_data = assets.getUiData("tooltip_line_spacer_top", 0);
        self.line_break = try self.base.createChild(Image, .{
            .base = .{ .x = inset_x + 5, .y = self.title.base.y + 100 + 5 },
            .image_data = .{ .nine_slice = .fromAtlasData(tooltip_line_spacer_top_data, 300 - 6 * 2 - 5 * 2, 6, 16, 0, 1, 6, 1.0) },
        });

        const desc_y = self.line_break.base.y + self.line_break.height() + 5;
        self.description = try self.base.createChild(Text, .{
            .base = .{ .x = inset_x, .y = desc_y },
            .text_data = .{
                .text = "",
                .size = 18,
                .text_type = .medium_italic,
                .vert_align = .middle,
                .hori_align = .middle,
                .max_width = 300 - inset_x * 2,
                .max_height = 350 - 6 - desc_y,
            },
        });

        return self;
    }

    pub fn update(self: *SelectableCard, data_id: u16) void {
        const data = game_data.card.from_id.get(data_id) orelse return;

        self.title.text_data.color, self.description.text_data.color = switch (data.rarity) {
            .mythic => .{ 0xE54E4E, 0xFFBFBF },
            .legendary => .{ 0xE5B84E, 0xFFEBBF },
            .epic => .{ 0x9F50E5, 0xE1BFFF },
            .rare => .{ 0x5066E5, 0xBFC7FF },
            .common => .{ 0xE5CCAC, 0xFFF3E5 },
        };

        self.title.text_data.setText(data.name);
        self.description.text_data.setText(data.description);

        const button_base, const button_hover, const button_press = buttonData(data.rarity);
        self.button.image_data = .fromNineSlices(button_base, button_hover, button_press, 300, 350, 26, 19, 1, 1, 1.0);

        const line_break = switch (data.rarity) {
            .mythic => assets.getUiData("tooltip_line_spacer_top_mythic", 0),
            .legendary => assets.getUiData("tooltip_line_spacer_top_legendary", 0),
            .epic => assets.getUiData("tooltip_line_spacer_top_epic", 0),
            .rare => assets.getUiData("tooltip_line_spacer_top_rare", 0),
            .common => assets.getUiData("tooltip_line_spacer_top", 0),
        };
        self.line_break.image_data.nine_slice = .fromAtlasData(line_break, 300 - 6 * 2 - 5 * 2, 6, 16, 0, 1, 6, 1.0);
    }
};

base: *Container = undefined,
background: *Image = undefined,
choose_text: *Text = undefined,
top_line_break: *Image = undefined,
bottom_line_break: *Image = undefined,
selectable_cards: [3]SelectableCard = undefined,
skip_button: *Button = undefined,

pub fn create() !*CardSelection {
    var self = try main.allocator.create(CardSelection);
    self.* = .{};

    self.base = try element.create(Container, .{ .base = .{ .x = 0, .y = 0, .visible = false } });

    const w = main.camera.width;
    const h = main.camera.height;

    const background = assets.getUiData("dark_background", 0);
    self.background = try self.base.createChild(Image, .{
        .base = .{ .x = 0, .y = 0 },
        .image_data = .{ .nine_slice = .fromAtlasData(background, w, h, 0, 0, 8, 8, 1.0) },
    });

    self.choose_text = try self.base.createChild(Text, .{
        .base = .{ .x = 40, .y = 0 },
        .text_data = .{
            .text = "Choose a Card",
            .size = 28,
            .text_type = .bold,
            .hori_align = .middle,
            .vert_align = .middle,
            .max_width = w - 40 * 2,
            .max_height = 100,
        },
    });

    const tooltip_line_spacer_top_data = assets.getUiData("tooltip_line_spacer_top", 0);
    self.top_line_break = try self.base.createChild(Image, .{
        .base = .{ .x = 40, .y = 100 },
        .image_data = .{ .nine_slice = .fromAtlasData(tooltip_line_spacer_top_data, w - 40 * 2, 6, 16, 0, 1, 6, 1.0) },
    });

    const tooltip_line_spacer_bottom_data = assets.getUiData("tooltip_line_spacer_bottom", 0);
    self.bottom_line_break = try self.base.createChild(Image, .{
        .base = .{ .x = 40, .y = h - 100 },
        .image_data = .{ .nine_slice = .fromAtlasData(tooltip_line_spacer_bottom_data, w - 40 * 2, 6, 16, 0, 1, 6, 1.0) },
    });

    const comptime_len = @typeInfo(@TypeOf(self.selectable_cards)).array.len;
    const start_x = (w - (card_w * comptime_len + card_padding * (comptime_len - 1))) / 2.0;
    inline for (0..comptime_len) |i| {
        const x = start_x + f32i((card_w + card_padding) * i);
        const y = 100 + ((h - 200) - card_h) / 2.0;
        self.selectable_cards[i] = try .create(self, self.base, x, y, switch (i) {
            0 => select1Callback,
            1 => select2Callback,
            2 => select3Callback,
            else => @compileError("Implement the rest of the callbacks on this"),
        });
    }

    const button_data_base = assets.getUiData("button_base", 0);
    const button_data_hover = assets.getUiData("button_hover", 0);
    const button_data_press = assets.getUiData("button_press", 0);
    self.skip_button = try self.base.createChild(Button, .{
        .base = .{
            .x = (w - button_data_base.width()) / 2.0,
            .y = h - 100 + (100 - button_data_base.height()) / 2.0,
        },
        .image_data = .fromNineSlices(button_data_base, button_data_hover, button_data_press, 100, 40, 26, 19, 1, 1, 1.0),
        .text_data = .{
            .text = "Skip",
            .size = 16,
            .text_type = .bold,
        },
        .userdata = self,
        .pressCallback = skipCallback,
    });

    return self;
}

pub fn destroy(self: *CardSelection) void {
    element.destroy(self.base);
    main.allocator.destroy(self);
}

pub fn resize(self: *CardSelection, w: f32, h: f32) void {
    self.background.image_data.scaleWidth(w);
    self.background.image_data.scaleHeight(h);
    self.choose_text.text_data.max_width = w - 40 * 2;
    self.bottom_line_break.base.y = h - 100;
    const comptime_len = @typeInfo(@TypeOf(self.selectable_cards)).array.len;
    const start_x = (w - (card_w * comptime_len + card_padding * (comptime_len - 1))) / 2.0;
    for (0..comptime_len) |i| {
        self.selectable_cards[i].base.base.x = start_x + f32i((card_w + card_padding) * i);
        self.selectable_cards[i].base.base.y = 100 + ((h - 200) - card_h) / 2.0;
    }
    self.skip_button.base.x = (w - self.skip_button.width()) / 2.0;
    self.skip_button.base.y = h - 100 + (100 - self.skip_button.height()) / 2.0;
}

pub fn updateSelectables(self: *CardSelection, data_ids: [3]u16) void {
    for (data_ids, 0..) |data_id, i| self.selectable_cards[i].update(data_id);
    self.base.base.visible = true;
}

fn skipCallback(ud: ?*anyopaque) void {
    const self: *CardSelection = @ptrCast(@alignCast(ud));
    defer self.base.base.visible = false;
    main.game_server.sendPacket(.{ .select_card = .{ .selection = .none } });
}

fn select1Callback(ud: ?*anyopaque) void {
    const self: *CardSelection = @ptrCast(@alignCast(ud));
    defer self.base.base.visible = false;
    main.game_server.sendPacket(.{ .select_card = .{ .selection = .first } });
}

fn select2Callback(ud: ?*anyopaque) void {
    const self: *CardSelection = @ptrCast(@alignCast(ud));
    defer self.base.base.visible = false;
    main.game_server.sendPacket(.{ .select_card = .{ .selection = .second } });
}

fn select3Callback(ud: ?*anyopaque) void {
    const self: *CardSelection = @ptrCast(@alignCast(ud));
    defer self.base.base.visible = false;
    main.game_server.sendPacket(.{ .select_card = .{ .selection = .third } });
}
