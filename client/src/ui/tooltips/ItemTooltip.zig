const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const f32i = shared.utils.f32i;
const ItemData = shared.network_data.ItemData;

const assets = @import("../../assets.zig");
const map = @import("../../game/map.zig");
const Player = @import("../../game/Player.zig");
const Bar = @import("../elements/Bar.zig");
const Container = @import("../elements/Container.zig");
const element = @import("../elements/element.zig");
const Image = @import("../elements/Image.zig");
const Text = @import("../elements/Text.zig");
const tooltip = @import("tooltip.zig");

const ItemTooltip = @This();
root: *Container = undefined,

decor: *Image = undefined,
image: *Image = undefined,
item_name: *Text = undefined,
rarity: *Text = undefined,
description: *Text = undefined,
tooltip_level_bar_decor: *Image = undefined,
tooltip_level_bar: *Bar = undefined,
tooltip_level_item: *Image = undefined,
line_break_one: *Image = undefined,
main_text: *Text = undefined,
line_break_two: *Image = undefined,
footer: *Text = undefined,
main_buffer_front: bool = false,
footer_buffer_front: bool = false,

last_item: u16 = std.math.maxInt(u16),
last_item_data: ItemData = .{ .amount = std.math.maxInt(u16), .unused = std.math.maxInt(u16) },

pub fn init(self: *ItemTooltip) !void {
    const tooltip_background_data = assets.getUiData("tooltip_background", 0);
    self.decor = try self.root.createChild(Image, .{
        .base = .{ .x = 0, .y = 0 },
        .image_data = .{ .nine_slice = .fromAtlasData(tooltip_background_data, 360, 360, 34, 34, 1, 1, 1.0) },
    });

    self.image = try self.root.createChild(Image, .{
        .base = .{ .x = 10, .y = 10 },
        .image_data = .{ .normal = .{ .atlas_data = undefined, .scale_x = 4, .scale_y = 4, .glow = true } },
    });

    self.item_name = try self.root.createChild(Text, .{
        .base = .{ .x = 8 * 4 + 25, .y = 10 },
        .text_data = .{ .text = "", .size = 14, .max_chars = 64, .text_type = .bold_italic },
    });

    self.rarity = try self.root.createChild(Text, .{
        .base = .{ .x = 8 * 4 + 25, .y = self.item_name.text_data.height + 10 },
        .text_data = .{
            .text = "",
            .size = 12,
            .color = 0xB3B3B3,
            .max_chars = 64,
            .text_type = .medium_italic,
        },
    });

    self.description = try self.root.createChild(Text, .{
        .base = .{ .x = 10, .y = self.rarity.base.y + self.rarity.height() + 10 },
        .text_data = .{
            .text = "",
            .size = 12,
            .max_width = self.decor.width() - 20,
            .color = 0xB3B3B3,
            .max_chars = 64,
            .text_type = .medium,
        },
    });

    self.tooltip_level_bar_decor = try self.root.createChild(Image, .{
        .base = .{ .x = 10, .y = self.description.base.y + self.description.height() + 10, .visible = false },
        .image_data = .{ .normal = .{ .atlas_data = assets.getUiData("tooltip_level_bar_background", 0) } },
    });

    self.tooltip_level_bar = try self.root.createChild(Bar, .{
        .base = .{ .x = self.tooltip_level_bar_decor.base.x + 36, .y = self.tooltip_level_bar_decor.base.y + 6, .visible = false },
        .image_data = .{ .normal = .{ .atlas_data = assets.getUiData("tooltip_level_bar", 0) } },
        .text_data = .{
            .text = "",
            .size = 12,
            .text_type = .bold_italic,
            .max_chars = 128,
        },
    });

    self.tooltip_level_item = try self.root.createChild(Image, .{
        .base = .{ .x = self.tooltip_level_bar_decor.base.x + 5, .y = self.tooltip_level_bar_decor.base.y + 5, .visible = false },
        .image_data = .{ .normal = .{ .atlas_data = undefined, .scale_x = 2, .scale_y = 2, .glow = true } },
    });

    const tooltip_line_spacer_top_data = assets.getUiData("tooltip_line_spacer_top", 0);
    self.line_break_one = try self.root.createChild(Image, .{
        .base = .{ .x = 20, .y = self.description.base.y + self.description.height() + 10 },
        .image_data = .{
            .nine_slice = .fromAtlasData(tooltip_line_spacer_top_data, self.decor.width() - 40, 6, 16, 0, 1, 6, 1.0),
        },
    });

    self.main_text = try self.root.createChild(Text, .{
        .base = .{ .x = 10, .y = self.line_break_one.base.y + self.line_break_one.height() - 10 },
        .text_data = .{
            .text = "",
            .size = 12,
            .max_width = self.decor.width() - 20,
            .color = 0x9B9B9B,
            // only half of the buffer is used at a time to avoid aliasing, so the max len is half of this
            .max_chars = 2048 * 2,
        },
    });

    const tooltip_line_spacer_bottom_data = assets.getUiData("tooltip_line_spacer_bottom", 0);
    self.line_break_two = try self.root.createChild(Image, .{
        .base = .{ .x = 20, .y = self.main_text.base.y + self.main_text.text_data.height + 11 },
        .image_data = .{
            .nine_slice = .fromAtlasData(tooltip_line_spacer_bottom_data, self.decor.width() - 40, 6, 16, 0, 1, 6, 1.0),
        },
    });

    self.footer = try self.root.createChild(Text, .{
        .base = .{ .x = 10, .y = self.line_break_two.base.y + self.line_break_two.height() - 10 },
        .text_data = .{
            .text = "",
            .size = 12,
            .max_width = self.decor.width() - 20,
            .color = 0x9B9B9B,
            // only half of the buffer is used at a time to avoid aliasing, so the max len is half of this
            .max_chars = 256 * 2,
        },
    });
}

pub fn deinit(self: *ItemTooltip) void {
    element.destroy(self.root);
}

fn getMainBuffer(self: *ItemTooltip) []u8 {
    const buffer_len_half = @divExact(self.main_text.text_data.backing_buffer.len, 2);
    defer self.main_buffer_front = !self.main_buffer_front;
    return if (self.main_buffer_front)
        self.main_text.text_data.backing_buffer[buffer_len_half..]
    else
        self.main_text.text_data.backing_buffer[0..buffer_len_half];
}

fn getFooterBuffer(self: *ItemTooltip) []u8 {
    const buffer_len_half = @divExact(self.footer.text_data.backing_buffer.len, 2);
    defer self.footer_buffer_front = !self.footer_buffer_front;
    return if (self.footer_buffer_front)
        self.footer.text_data.backing_buffer[buffer_len_half..]
    else
        self.footer.text_data.backing_buffer[0..buffer_len_half];
}

pub fn update(self: *ItemTooltip, params: tooltip.ParamsFor(ItemTooltip)) void {
    defer {
        const left_x = params.x - self.decor.width() - 5;
        const up_y = params.y - self.decor.height() - 5;
        self.root.base.x = if (left_x < 0) params.x + 5 else left_x;
        self.root.base.y = if (up_y < 0) params.y + 5 else up_y;
    }

    if (self.last_item == params.item and self.last_item_data == params.item_data) return;
    self.last_item = params.item;
    self.last_item_data = params.item_data;

    const data = game_data.item.from_id.get(@intCast(params.item)) orelse return;

    self.decor.image_data.nine_slice.color_intensity = 0;
    self.line_break_one.image_data.nine_slice.color_intensity = 0;
    self.line_break_two.image_data.nine_slice.color_intensity = 0;
    var rarity_text_color: u32 = 0xB3B3B3;
    switch (data.rarity) {
        .mythic => {
            const tooltip_background_data = assets.getUiData("tooltip_background_mythic", 0);
            const tooltip_line_spacer_top_data = assets.getUiData("tooltip_line_spacer_top_mythic", 0);
            const tooltip_line_spacer_bottom_data = assets.getUiData("tooltip_line_spacer_bottom_mythic", 0);
            self.decor.image_data.nine_slice = element.NineSliceImageData.fromAtlasData(tooltip_background_data, 360, 360, 34, 34, 1, 1, 1.0);
            self.line_break_one.image_data.nine_slice = element.NineSliceImageData.fromAtlasData(tooltip_line_spacer_top_data, self.decor.width() - 40, 6, 16, 0, 1, 6, 1.0);
            self.line_break_two.image_data.nine_slice = element.NineSliceImageData.fromAtlasData(tooltip_line_spacer_bottom_data, self.decor.width() - 40, 6, 16, 0, 1, 6, 1.0);
            rarity_text_color = 0xB80000;
        },
        .legendary => {
            const tooltip_background_data = assets.getUiData("tooltip_background_legendary", 0);
            const tooltip_line_spacer_top_data = assets.getUiData("tooltip_line_spacer_top_legendary", 0);
            const tooltip_line_spacer_bottom_data = assets.getUiData("tooltip_line_spacer_bottom_legendary", 0);
            self.decor.image_data.nine_slice = element.NineSliceImageData.fromAtlasData(tooltip_background_data, 360, 360, 34, 34, 1, 1, 1.0);
            self.line_break_one.image_data.nine_slice = element.NineSliceImageData.fromAtlasData(tooltip_line_spacer_top_data, self.decor.width() - 40, 6, 16, 0, 1, 6, 1.0);
            self.line_break_two.image_data.nine_slice = element.NineSliceImageData.fromAtlasData(tooltip_line_spacer_bottom_data, self.decor.width() - 40, 6, 16, 0, 1, 6, 1.0);
            rarity_text_color = 0xE6A100;
        },
        .epic => {
            const tooltip_background_data = assets.getUiData("tooltip_background_epic", 0);
            const tooltip_line_spacer_top_data = assets.getUiData("tooltip_line_spacer_top_epic", 0);
            const tooltip_line_spacer_bottom_data = assets.getUiData("tooltip_line_spacer_bottom_epic", 0);
            self.decor.image_data.nine_slice = element.NineSliceImageData.fromAtlasData(tooltip_background_data, 360, 360, 34, 34, 1, 1, 1.0);
            self.line_break_one.image_data.nine_slice = element.NineSliceImageData.fromAtlasData(tooltip_line_spacer_top_data, self.decor.width() - 40, 6, 16, 0, 1, 6, 1.0);
            self.line_break_two.image_data.nine_slice = element.NineSliceImageData.fromAtlasData(tooltip_line_spacer_bottom_data, self.decor.width() - 40, 6, 16, 0, 1, 6, 1.0);
            rarity_text_color = 0xA825E6;
        },
        .rare => {
            const tooltip_background_data = assets.getUiData("tooltip_background_rare", 0);
            const tooltip_line_spacer_top_data = assets.getUiData("tooltip_line_spacer_top_rare", 0);
            const tooltip_line_spacer_bottom_data = assets.getUiData("tooltip_line_spacer_bottom_rare", 0);
            self.decor.image_data.nine_slice = element.NineSliceImageData.fromAtlasData(tooltip_background_data, 360, 360, 34, 34, 1, 1, 1.0);
            self.line_break_one.image_data.nine_slice = element.NineSliceImageData.fromAtlasData(tooltip_line_spacer_top_data, self.decor.width() - 40, 6, 16, 0, 1, 6, 1.0);
            self.line_break_two.image_data.nine_slice = element.NineSliceImageData.fromAtlasData(tooltip_line_spacer_bottom_data, self.decor.width() - 40, 6, 16, 0, 1, 6, 1.0);
            rarity_text_color = 0x2575E6;
        },
        .common => {
            const tooltip_background_data = assets.getUiData("tooltip_background", 0);
            const tooltip_line_spacer_top_data = assets.getUiData("tooltip_line_spacer_top", 0);
            const tooltip_line_spacer_bottom_data = assets.getUiData("tooltip_line_spacer_bottom", 0);
            self.decor.image_data.nine_slice = element.NineSliceImageData.fromAtlasData(tooltip_background_data, 360, 360, 34, 34, 1, 1, 1.0);
            self.line_break_one.image_data.nine_slice = element.NineSliceImageData.fromAtlasData(tooltip_line_spacer_top_data, self.decor.width() - 40, 6, 16, 0, 1, 6, 1.0);
            self.line_break_two.image_data.nine_slice = element.NineSliceImageData.fromAtlasData(tooltip_line_spacer_bottom_data, self.decor.width() - 40, 6, 16, 0, 1, 6, 1.0);
        },
    }

    const rarity_text = switch (data.rarity) {
        .mythic => "Mythic",
        .legendary => "Legendary",
        .epic => "Epic",
        .rare => "Rare",
        .common => "Common",
    };

    self.rarity.text_data.setText(std.fmt.bufPrint(
        self.rarity.text_data.backing_buffer,
        "{s} {s}",
        .{ rarity_text, data.item_type.toString() },
    ) catch self.rarity.text_data.text);
    self.rarity.text_data.color = rarity_text_color;

    if (assets.atlas_data.get(data.texture.sheet)) |tex_data| {
        self.image.image_data.normal.atlas_data = tex_data[data.texture.index];
        const scale_x = self.image.image_data.normal.scale_x;
        const scale_y = self.image.image_data.normal.scale_y;
        self.image.base.x = 10 + (10 * scale_x - self.image.width()) / 2;
        self.image.base.y = 10 + (10 * scale_y - self.image.height()) / 2;
    }

    self.item_name.text_data.setText(if (data.max_stack == 0)
        data.name
    else
        std.fmt.bufPrint(self.item_name.text_data.backing_buffer, "{}x {s}", .{
            params.item_data.amount,
            data.name,
        }) catch "Buffer overflow");
    self.description.text_data.setText(data.description);

    const levelable = data.level_spirits > 0;
    if (levelable) {
        levelSet: {
            const next_data = game_data.item.from_name.get(data.level_transform_item.?) orelse break :levelSet;
            const tex_data = assets.atlas_data.get(next_data.texture.sheet) orelse break :levelSet;

            self.tooltip_level_bar_decor.base.y = self.description.base.y + self.description.height() + 10;
            self.tooltip_level_bar.base.y = self.tooltip_level_bar_decor.base.y + 6;

            self.tooltip_level_item.image_data.normal.atlas_data = tex_data[next_data.texture.index];
            self.tooltip_level_item.base.x = self.tooltip_level_bar_decor.base.x + 5 + (24 - self.tooltip_level_item.width()) / 2;
            self.tooltip_level_item.base.y = self.tooltip_level_bar_decor.base.y + 5 + (24 - self.tooltip_level_item.height()) / 2;

            const spirit_perc = f32i(params.item_data.amount) / f32i(data.level_spirits);
            self.tooltip_level_bar.base.scissor.max_x = self.tooltip_level_bar.texWRaw() * spirit_perc;

            self.tooltip_level_bar.text_data.setText(
                std.fmt.bufPrint(self.tooltip_level_bar.text_data.backing_buffer, "{s} - {}/{}", .{
                    data.level_transform_item.?,
                    params.item_data.amount,
                    data.level_spirits,
                }) catch break :levelSet,
            );

            self.tooltip_level_bar.base.visible = true;
            self.tooltip_level_bar_decor.base.visible = true;
            self.tooltip_level_item.base.visible = true;
        }
    } else {
        self.tooltip_level_bar.base.visible = false;
        self.tooltip_level_bar_decor.base.visible = false;
        self.tooltip_level_item.base.visible = false;
    }

    const bottom = if (levelable)
        self.tooltip_level_bar_decor.base.y + self.tooltip_level_bar_decor.height()
    else
        self.description.base.y + self.description.height();
    self.line_break_one.base.y = bottom + 10;
    self.main_text.base.y = self.line_break_one.base.y - 10;

    const line_base = "{s}\n";
    const line_base_inset = line_base ++ "- ";

    const string_fmt = "&col=\"FFFF8F\"{s}&col=\"9B9B9B\"";
    const decimal_fmt = "&col=\"FFFF8F\"{}&col=\"9B9B9B\"";
    const float_fmt = "&col=\"FFFF8F\"{d:.1}&col=\"9B9B9B\"";

    var written_on_use = false;
    var text: []u8 = "";
    if (data.activations) |activation_data| {
        for (activation_data) |activation| {
            if (!written_on_use) {
                text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "On Use:", .{text}) catch text;
                written_on_use = true;
            }

            text = switch (activation) {
                .heal => |value| std.fmt.bufPrint(
                    self.getMainBuffer(),
                    line_base_inset ++ "Restores " ++ decimal_fmt ++ " HP",
                    .{ text, value },
                ),
                .magic => |value| std.fmt.bufPrint(
                    self.getMainBuffer(),
                    line_base_inset ++ "Restores " ++ decimal_fmt ++ " MP",
                    .{ text, value },
                ),
                .heal_nova => |value| std.fmt.bufPrint(
                    self.getMainBuffer(),
                    line_base_inset ++ "Restores " ++ decimal_fmt ++ " HP within " ++ float_fmt ++ " tiles",
                    .{ text, value.amount, value.radius },
                ),
                .magic_nova => |value| std.fmt.bufPrint(
                    self.getMainBuffer(),
                    line_base_inset ++ "Restores " ++ decimal_fmt ++ " HP within " ++ float_fmt ++ " tiles",
                    .{ text, value.amount, value.radius },
                ),
                .create_portal => |value| std.fmt.bufPrint(
                    self.getMainBuffer(),
                    line_base_inset ++ "Opens the following dungeon: " ++ string_fmt,
                    .{ text, value.name },
                ),
                .create_ally => |value| std.fmt.bufPrint(
                    self.getMainBuffer(),
                    line_base_inset ++ "Bring an ally to battle: " ++ string_fmt,
                    .{ text, value.name },
                ),
            } catch text;
        }
    }

    if (data.projectile) |proj| {
        text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Projectiles: " ++ decimal_fmt, .{ text, data.projectile_count }) catch text;
        if (proj.phys_dmg > 0)
            text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Physical Damage: " ++ decimal_fmt, .{ text, proj.phys_dmg }) catch text;
        if (proj.magic_dmg > 0)
            text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Magic Damage: " ++ decimal_fmt, .{ text, proj.magic_dmg }) catch text;
        if (proj.true_dmg > 0)
            text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "True Damage: " ++ decimal_fmt, .{ text, proj.true_dmg }) catch text;
        text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Range: " ++ float_fmt, .{ text, proj.range() }) catch text;

        if (proj.conditions) |conditions| for (conditions, 0..) |cond, i| {
            if (i == 0) text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Shot effect:", .{text}) catch text;
            text = std.fmt.bufPrint(
                self.getMainBuffer(),
                line_base_inset ++ "Inflict " ++ string_fmt ++ " for " ++ float_fmt ++ " seconds",
                .{ text, cond.type.toString(), cond.duration },
            ) catch text;
        };

        if (data.fire_rate != 1.0)
            text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Rate of Fire: " ++ float_fmt ++ "%", .{ text, data.fire_rate * 100 }) catch text;

        if (proj.piercing) text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Projectiles pierce", .{text}) catch text;
        if (proj.boomerang) text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Projectiles boomerang", .{text}) catch text;
    }

    var i: usize = 0;
    if (data.stat_increases) |stat_increases| for (stat_increases) |incr| {
        defer i += 1;
        if (i == 0) text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "On Equip: ", .{text}) catch text;

        const amount = incr.amount();
        if (amount > 0) {
            text = std.fmt.bufPrint(
                self.getMainBuffer(),
                "{s}+" ++ decimal_fmt ++ " {s}{s}",
                .{ text, amount, incr.toControlCode(), if (i == stat_increases.len - 1) "" else ", " },
            ) catch text;
        } else {
            text = std.fmt.bufPrint(
                self.getMainBuffer(),
                "{s}" ++ decimal_fmt ++ " {s}{s}",
                .{ text, amount, incr.toControlCode(), if (i == stat_increases.len - 1) "" else ", " },
            ) catch text;
        }
    };

    if (data.perc_stat_increases) |stat_increases| for (stat_increases) |incr| {
        defer i += 1;
        if (i == 0) text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "On Equip: ", .{text}) catch text;

        const amount = incr.amount();
        if (amount > 0) {
            text = std.fmt.bufPrint(
                self.getMainBuffer(),
                "{s}+" ++ float_fmt ++ "% {s}{s}",
                .{ text, amount * 100.0, incr.toControlCode(), if (i == stat_increases.len - 1) "" else ", " },
            ) catch text;
        } else {
            text = std.fmt.bufPrint(
                self.getMainBuffer(),
                "{s}" ++ float_fmt ++ "% {s}{s}",
                .{ text, amount * 100.0, incr.toControlCode(), if (i == stat_increases.len - 1) "" else ", " },
            ) catch text;
        }
    };

    if (data.mana_cost) |cost| {
        const mana_icon = comptime game_data.StatIncreaseData.toControlCode(.{ .max_mp = undefined });
        text = std.fmt.bufPrint(
            self.getMainBuffer(),
            line_base ++ float_fmt ++ "% chance to consume " ++ decimal_fmt ++ "&space{s}",
            .{ text, cost.chance * 100.0, cost.amount, mana_icon },
        ) catch text;
    }

    if (data.health_cost) |cost| {
        const health_icon = comptime game_data.StatIncreaseData.toControlCode(.{ .max_hp = undefined });
        text = std.fmt.bufPrint(
            self.getMainBuffer(),
            line_base ++ float_fmt ++ "% chance to consume " ++ decimal_fmt ++ "&space{s}",
            .{ text, cost.chance * 100.0, cost.amount, health_icon },
        ) catch text;
    }

    if (data.gold_cost) |cost| {
        const gold_icon = "&img=\"misc,0\"";
        text = std.fmt.bufPrint(
            self.getMainBuffer(),
            line_base ++ float_fmt ++ "% chance to consume " ++ decimal_fmt ++ "&space{s}",
            .{ text, cost.chance * 100.0, cost.amount, gold_icon },
        ) catch text;
    }

    if (data.health_gain_incr > 0) {
        text = std.fmt.bufPrint(
            self.getMainBuffer(),
            line_base ++ "Improves Health restoration efficiency by " ++ float_fmt ++ "%",
            .{ text, data.health_gain_incr * 100.0 },
        ) catch text;
    }

    if (data.mana_gain_incr > 0) {
        text = std.fmt.bufPrint(
            self.getMainBuffer(),
            line_base ++ "Improves Mana restoration efficiency by " ++ float_fmt ++ "%",
            .{ text, data.mana_gain_incr * 100.0 },
        ) catch text;
    }

    if (data.env_dmg_reduction > 0) {
        text = std.fmt.bufPrint(
            self.getMainBuffer(),
            line_base ++ "Reduce environmental damage received by " ++ float_fmt ++ "%",
            .{ text, data.env_dmg_reduction * 100.0 },
        ) catch text;
    }

    if (data.activations != null and data.cooldown > 0.0)
        text = std.fmt.bufPrint(
            self.getMainBuffer(),
            line_base ++ "Cooldown: " ++ float_fmt ++ " seconds",
            .{ text, data.cooldown },
        ) catch text;

    self.main_text.text_data.setText(text);

    self.line_break_two.base.y = self.main_text.base.y + self.main_text.text_data.height + 5;
    self.footer.base.y = self.line_break_two.base.y - 10;

    var footer_text: []u8 = "";
    if (data.untradeable)
        footer_text = std.fmt.bufPrint(self.getFooterBuffer(), line_base ++ "Can not be traded", .{footer_text}) catch footer_text;
    if (data.ephemeral)
        footer_text = std.fmt.bufPrint(
            self.getFooterBuffer(),
            line_base ++ "This item will disappear on map switch",
            .{footer_text},
        ) catch footer_text;

    if (data.item_type == .boots or data.item_type == .artifact) {
        footer_text = std.fmt.bufPrint(
            self.getFooterBuffer(),
            line_base ++ "Usable by: " ++ string_fmt,
            .{ footer_text, "All Classes" },
        ) catch footer_text;
    } else if (data.item_type != .any and data.item_type != .consumable) {
        if (map.localPlayerCon()) |player| {
            const has_type = blk: {
                for (player.data.item_types) |item_type| {
                    if (item_type != .any and item_type.typesMatch(data.item_type))
                        break :blk true;
                }

                break :blk false;
            };

            if (!has_type) {
                footer_text = std.fmt.bufPrint(
                    self.getFooterBuffer(),
                    line_base ++ "&col=\"D00000\"Not usable by: " ++ string_fmt,
                    .{ footer_text, player.data.name },
                ) catch footer_text;

                self.decor.image_data.nine_slice.color = 0x8B0000;
                self.decor.image_data.nine_slice.color_intensity = 0.1;

                self.line_break_one.image_data.nine_slice.color = 0x8B0000;
                self.line_break_one.image_data.nine_slice.color_intensity = 0.1;

                self.line_break_two.image_data.nine_slice.color = 0x8B0000;
                self.line_break_two.image_data.nine_slice.color_intensity = 0.1;
            } else {
                footer_text = std.fmt.bufPrint(self.getFooterBuffer(), line_base ++ "Usable by: ", .{footer_text}) catch footer_text;

                var first = true;
                var class_iter = game_data.class.from_id.valueIterator();
                typesMatch: while (class_iter.next()) |class| {
                    for (class.item_types) |item_type| {
                        if (item_type != .any and item_type.typesMatch(data.item_type)) {
                            if (first) {
                                footer_text = std.fmt.bufPrint(
                                    self.getFooterBuffer(),
                                    "{s}" ++ string_fmt,
                                    .{ footer_text, class.name },
                                ) catch footer_text;
                            } else {
                                footer_text = std.fmt.bufPrint(
                                    self.getFooterBuffer(),
                                    "{s}, " ++ string_fmt,
                                    .{ footer_text, class.name },
                                ) catch footer_text;
                            }

                            first = false;
                            continue :typesMatch;
                        }
                    }
                }
            }
        }
    }

    if (data.item_type == .consumable)
        footer_text = std.fmt.bufPrint(self.getFooterBuffer(), line_base ++ "Consumed on use", .{footer_text}) catch footer_text;

    self.footer.text_data.setText(footer_text);

    if (footer_text.len == 0) {
        self.line_break_two.base.visible = false;
        self.decor.image_data.nine_slice.h = self.line_break_two.base.y + 5;
    } else {
        self.line_break_two.base.visible = true;
        self.decor.image_data.nine_slice.h = self.footer.base.y + self.footer.text_data.height + 10;
    }
}
