const std = @import("std");
const element = @import("../element.zig");
const assets = @import("../../assets.zig");
const camera = @import("../../camera.zig");
const game_data = @import("../../game_data.zig");
const map = @import("../../map/map.zig");
const tooltip = @import("tooltip.zig");

pub const ItemTooltip = struct {
    root: *element.Container = undefined,
    item: u16 = std.math.maxInt(u16),
    decor: *element.Image = undefined,
    image: *element.Image = undefined,
    item_name: *element.Text = undefined,
    rarity: *element.Text = undefined,
    line_break_one: *element.Image = undefined,
    main_text: *element.Text = undefined,
    line_break_two: *element.Image = undefined,
    footer: *element.Text = undefined,

    main_buffer_front: bool = false,
    footer_buffer_front: bool = false,
    _allocator: std.mem.Allocator = undefined,

    pub fn init(self: *ItemTooltip, allocator: std.mem.Allocator) !void {
        self._allocator = allocator;

        self.root = try element.create(allocator, element.Container{
            .visible = false,
            .layer = .tooltip,
            .x = 0,
            .y = 0,
        });

        const tooltip_background_data = assets.getUiData("tooltip_background", 0);
        self.decor = try self.root.createChild(element.Image{
            .x = 0,
            .y = 0,
            .image_data = .{
                .nine_slice = element.NineSliceImageData.fromAtlasData(tooltip_background_data, 360, 360, 14, 14, 2, 2, 1.0),
            },
        });

        self.image = try self.root.createChild(element.Image{
            .x = 10,
            .y = 10,
            .image_data = .{
                .normal = .{
                    .atlas_data = undefined,
                    .scale_x = 4,
                    .scale_y = 4,
                    .glow = true,
                },
            },
            .ui_quad = false,
        });

        self.item_name = try self.root.createChild(element.Text{
            .x = 8 * 4 + 30,
            .y = 10,
            .text_data = .{
                .text = "",
                .size = 16,
                .text_type = .bold_italic,
            },
        });

        self.rarity = try self.root.createChild(element.Text{
            .x = 8 * 4 + 30,
            .y = self.item_name.text_data._height + 10,
            .text_data = .{
                .text = "",
                .size = 14,
                .color = 0xB3B3B3,
                .max_chars = 64,
                .text_type = .medium_italic,
            },
        });

        const tooltip_line_spacer_data = assets.getUiData("tooltip_line_spacer", 0);
        self.line_break_one = try self.root.createChild(element.Image{
            .x = 20,
            .y = self.image.y + self.image.height(),
            .image_data = .{
                .nine_slice = element.NineSliceImageData.fromAtlasData(tooltip_line_spacer_data, self.decor.width() - 40, 14, 13, 0, 1, 14, 1.0),
            },
        });

        self.main_text = try self.root.createChild(element.Text{
            .x = 10,
            .y = self.line_break_one.y + self.line_break_one.height() + 20,
            .text_data = .{
                .text = "",
                .size = 14,
                .max_width = self.decor.width() - 20,
                .color = 0x9B9B9B,
                // only half of the buffer is used at a time to avoid aliasing, so the max len is half of this
                .max_chars = 2048 * 2,
            },
        });

        self.line_break_two = try self.root.createChild(element.Image{
            .x = 20,
            .y = self.main_text.y + self.main_text.text_data._height,
            .image_data = .{
                .nine_slice = element.NineSliceImageData.fromAtlasData(tooltip_line_spacer_data, self.decor.width() - 40, 14, 13, 0, 1, 14, 1.0),
            },
        });

        self.footer = try self.root.createChild(element.Text{
            .x = 10,
            .y = self.line_break_two.y + self.line_break_two.height() + 20,
            .text_data = .{
                .text = "",
                .size = 14,
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
        const buffer_len_half = @divExact(self.main_text.text_data._backing_buffer.len, 2);
        const back_buffer = self.main_text.text_data._backing_buffer[0..buffer_len_half];
        const front_buffer = self.main_text.text_data._backing_buffer[buffer_len_half..];

        if (self.main_buffer_front) {
            self.main_buffer_front = false;
            return front_buffer;
        } else {
            self.main_buffer_front = true;
            return back_buffer;
        }
    }

    fn getFooterBuffer(self: *ItemTooltip) []u8 {
        const buffer_len_half = @divExact(self.footer.text_data._backing_buffer.len, 2);
        const back_buffer = self.footer.text_data._backing_buffer[0..buffer_len_half];
        const front_buffer = self.footer.text_data._backing_buffer[buffer_len_half..];

        if (self.footer_buffer_front) {
            self.footer_buffer_front = false;
            return front_buffer;
        } else {
            self.footer_buffer_front = true;
            return back_buffer;
        }
    }

    pub fn update(self: *ItemTooltip, params: tooltip.ParamsFor(ItemTooltip)) void {
        const left_x = params.x - self.decor.width() - 15;
        const up_y = params.y - self.decor.height() - 15;
        self.root.x = if (left_x < 0) params.x + 15 else left_x;
        self.root.y = if (up_y < 0) params.y + 15 else up_y;

        if (self.item == params.item)
            return;

        self.item = params.item;

        if (game_data.item_type_to_props.get(@intCast(params.item))) |props| {
            self.decor.image_data.nine_slice.color_intensity = 0;
            self.line_break_one.image_data.nine_slice.color_intensity = 0;
            self.line_break_two.image_data.nine_slice.color_intensity = 0;

            var rarity_text_color: u32 = 0xB3B3B3;
            if (std.mem.eql(u8, props.tier, "Mythic")) {
                rarity_text_color = 0xB80000;
            } else if (std.mem.eql(u8, props.tier, "Legendary")) {
                rarity_text_color = 0xE6A100;
            } else if (std.mem.eql(u8, props.tier, "Epic")) {
                rarity_text_color = 0xA825E6;
            } else if (std.mem.eql(u8, props.tier, "Rare")) {
                rarity_text_color = 0x2575E6;
            }

            self.rarity.text_data.text = std.fmt.bufPrint(
                self.rarity.text_data._backing_buffer,
                "{s} {s}",
                .{ props.tier, props.slot_type.toString() },
            ) catch self.rarity.text_data.text;

            self.rarity.text_data.color = rarity_text_color;
            self.rarity.text_data.recalculateAttributes(self._allocator);

            if (assets.atlas_data.get(props.texture_data.sheet)) |data| {
                self.image.image_data.normal.atlas_data = data[props.texture_data.index];
            }

            self.item_name.text_data.text = props.display_id;
            self.item_name.text_data.recalculateAttributes(self._allocator);

            self.line_break_one.y = self.image.y + self.image.height() + 10;
            self.main_text.y = self.line_break_one.y - 5;

            const line_base = "{s}\n";
            const line_base_inset = line_base ++ "- ";

            const string_fmt = "&col=\"FFFF8F\"{s}&col=\"9B9B9B\"";
            const decimal_fmt = "&col=\"FFFF8F\"{d}&col=\"9B9B9B\"";
            const float_fmt = "&col=\"FFFF8F\"{d:.1}&col=\"9B9B9B\"";

            var written_on_use = false;
            var text: []u8 = "";
            if (props.activations) |activate| {
                for (activate) |data| {
                    if (!written_on_use) {
                        text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "On Use:", .{text}) catch text;
                        written_on_use = true;
                    }

                    text = switch (data.activation_type) {
                        .increment_stat => std.fmt.bufPrint(
                            self.getMainBuffer(),
                            line_base_inset ++ "Increases " ++ string_fmt ++ " by " ++ decimal_fmt,
                            .{ text, if (data.stat) |stat| stat.toString() else "Unknown", data.amount },
                        ),
                        .heal => std.fmt.bufPrint(self.getMainBuffer(), line_base_inset ++ "Restores " ++ decimal_fmt ++ " HP", .{ text, data.amount }),
                        .magic => std.fmt.bufPrint(self.getMainBuffer(), line_base_inset ++ "Restores " ++ decimal_fmt ++ " MP", .{ text, data.amount }),
                        .create => std.fmt.bufPrint(self.getMainBuffer(), line_base_inset ++ "Spawn the following: " ++ string_fmt, .{ text, data.id }),
                        .heal_nova => std.fmt.bufPrint(
                            self.getMainBuffer(),
                            line_base_inset ++ "Restores " ++ decimal_fmt ++ " HP within " ++ decimal_fmt ++ " tiles",
                            .{ text, data.amount, data.range },
                        ),
                        .magic_nova => std.fmt.bufPrint(
                            self.getMainBuffer(),
                            line_base_inset ++ "Restores " ++ decimal_fmt ++ " HP within " ++ decimal_fmt ++ " tiles",
                            .{ text, data.amount, data.range },
                        ),
                        .stat_boost_self => std.fmt.bufPrint(
                            self.getMainBuffer(),
                            line_base_inset ++ "Gain +" ++ decimal_fmt ++ " " ++ string_fmt ++ " for " ++ decimal_fmt ++ " seconds",
                            .{ text, data.amount, if (data.stat) |stat| stat.toString() else "Unknown", data.duration },
                        ),
                        .stat_boost_aura => std.fmt.bufPrint(
                            self.getMainBuffer(),
                            line_base_inset ++ "Grant players +" ++ decimal_fmt ++ " " ++ string_fmt ++ " within " ++ decimal_fmt ++
                                " tiles for " ++ decimal_fmt ++ " seconds",
                            .{ text, data.amount, if (data.stat) |stat| stat.toString() else "Unknown", data.range, data.duration },
                        ),
                        .condition_effect_aura => std.fmt.bufPrint(
                            self.getMainBuffer(),
                            line_base_inset ++ "Grant players " ++ string_fmt ++ " within " ++ decimal_fmt ++ " tiles for " ++ decimal_fmt ++ " seconds",
                            .{ text, data.effect.toString(), data.range, data.duration },
                        ),
                        .condition_effect_self => std.fmt.bufPrint(
                            self.getMainBuffer(),
                            line_base_inset ++ "Grant yourself " ++ string_fmt ++ " for " ++ decimal_fmt ++ " seconds",
                            .{ text, data.effect.toString(), data.duration },
                        ),
                        .teleport => std.fmt.bufPrint(self.getMainBuffer(), line_base_inset ++ "Teleport to cursor", .{text}),
                        .open_portal => std.fmt.bufPrint(
                            self.getMainBuffer(),
                            line_base_inset ++ "Opens the following dungeon: " ++ string_fmt,
                            .{ text, game_data.obj_type_to_name.get(data.obj_type) orelse "Unknown" },
                        ),
                        else => continue,
                    } catch text;
                }
            }

            if (props.extra_tooltip_data) |extra| {
                for (extra) |effect| {
                    if (!written_on_use) {
                        text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "On Use:", .{text}) catch text;
                        written_on_use = true;
                    }

                    text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "{s}: " ++ string_fmt, .{ text, effect.name, effect.description }) catch text;
                }
            }

            if (props.projectile) |proj| {
                text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Bullets: " ++ decimal_fmt, .{ text, props.num_projectiles }) catch text;
                if (proj.physical_damage > 0)
                    text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Physical Damage: " ++ decimal_fmt, .{ text, proj.physical_damage }) catch text;
                if (proj.magic_damage > 0)
                    text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Magic Damage: " ++ decimal_fmt, .{ text, proj.magic_damage }) catch text;
                if (proj.true_damage > 0)
                    text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "True Damage: " ++ decimal_fmt, .{ text, proj.true_damage }) catch text;
                text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Range: " ++ float_fmt, .{ text, proj.speed * @as(f32, @floatFromInt(proj.lifetime)) }) catch text;

                for (proj.effects, 0..) |effect, i| {
                    if (i == 0)
                        text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Shot effect:", .{text}) catch text;
                    text = std.fmt.bufPrint(
                        self.getMainBuffer(),
                        line_base_inset ++ "Inflict " ++ string_fmt ++ " for " ++ decimal_fmt ++ " seconds",
                        .{ text, effect.condition.toString(), effect.duration },
                    ) catch text;
                }

                if (props.rate_of_fire != 0)
                    text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Rate of Fire: " ++ decimal_fmt ++ "%", .{ text, props.rate_of_fire * 100 }) catch text;

                if (proj.multi_hit)
                    text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Bullets pierce", .{text}) catch text;
                if (proj.passes_cover)
                    text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Bullets pass through cover", .{text}) catch text;
                if (proj.wavy)
                    text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Bullets are wavy", .{text}) catch text;
                if (proj.parametric)
                    text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Bullets are parametric", .{text}) catch text;
                if (proj.boomerang)
                    text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Bullets boomerang", .{text}) catch text;
            }

            if (props.stat_increments) |stat_increments| {
                for (stat_increments, 0..) |stat_increment, i| {
                    if (i == 0)
                        text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "On Equip: ", .{text}) catch text;

                    if (stat_increment.amount > 0) {
                        text = std.fmt.bufPrint(
                            self.getMainBuffer(),
                            "{s}+" ++ decimal_fmt ++ " {s}{s}",
                            .{ text, stat_increment.amount, stat_increment.stat.toControlCode(), if (i == stat_increments.len - 1) "" else ", " },
                        ) catch text;
                    } else {
                        text = std.fmt.bufPrint(
                            self.getMainBuffer(),
                            "{s}" ++ decimal_fmt ++ " {s}{s}",
                            .{ text, stat_increment.amount, stat_increment.stat.toControlCode(), if (i == stat_increments.len - 1) "" else ", " },
                        ) catch text;
                    }
                }
            }

            if (props.mp_cost != 0)
                text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Cost: " ++ decimal_fmt ++ " MP", .{ text, props.mp_cost }) catch text;

            if (props.usable)
                text = std.fmt.bufPrint(self.getMainBuffer(), line_base ++ "Cooldown: " ++ decimal_fmt ++ " seconds", .{ text, props.cooldown }) catch text;

            self.main_text.text_data.text = text;
            self.main_text.text_data.recalculateAttributes(self._allocator);

            self.line_break_two.y = self.main_text.y + self.main_text.text_data._height + 5;
            self.footer.y = self.line_break_two.y - 5;

            var footer_text: []u8 = "";
            if (props.untradeable)
                footer_text = std.fmt.bufPrint(self.getFooterBuffer(), line_base ++ "Can not be traded", .{footer_text}) catch footer_text;

            if (props.slot_type != .no_item and
                props.slot_type != .any and
                props.slot_type != .consumable and
                props.slot_type != .boots and
                props.slot_type != .artifact)
            {
                if (map.localPlayerConst()) |player| {
                    const has_type = blk: {
                        for (player.class_data.slot_types) |slot_type| {
                            if (slot_type != .any and slot_type.slotsMatch(props.slot_type))
                                break :blk true;
                        }

                        break :blk false;
                    };

                    if (!has_type) {
                        footer_text = std.fmt.bufPrint(
                            self.getFooterBuffer(),
                            line_base ++ "&col=\"D00000\"Not usable by: " ++ string_fmt,
                            .{ footer_text, player.class_data.name },
                        ) catch footer_text;

                        self.decor.image_data.nine_slice.color = 0x8B0000;
                        self.decor.image_data.nine_slice.color_intensity = 0.4;

                        self.line_break_one.image_data.nine_slice.color = 0x8B0000;
                        self.line_break_one.image_data.nine_slice.color_intensity = 0.4;

                        self.line_break_two.image_data.nine_slice.color = 0x8B0000;
                        self.line_break_two.image_data.nine_slice.color_intensity = 0.4;
                    } else {
                        footer_text = std.fmt.bufPrint(self.getFooterBuffer(), line_base ++ "Usable by: ", .{footer_text}) catch footer_text;

                        var first = true;
                        var class_iter = game_data.classes.valueIterator();
                        slotsMatch: while (class_iter.next()) |class| {
                            for (class.slot_types) |slot_type| {
                                if (slot_type != .any and slot_type.slotsMatch(props.slot_type)) {
                                    if (first) {
                                        footer_text = std.fmt.bufPrint(self.getFooterBuffer(), "{s}" ++ string_fmt, .{ footer_text, class.name }) catch footer_text;
                                    } else {
                                        footer_text = std.fmt.bufPrint(self.getFooterBuffer(), "{s}, " ++ string_fmt, .{ footer_text, class.name }) catch footer_text;
                                    }

                                    first = false;
                                    continue :slotsMatch;
                                }
                            }
                        }
                    }
                }
            }

            if (props.consumable)
                footer_text = std.fmt.bufPrint(self.getFooterBuffer(), line_base ++ "Can be consumed", .{footer_text}) catch footer_text;

            self.footer.text_data.text = footer_text;
            self.footer.text_data.recalculateAttributes(self._allocator);

            if (footer_text.len == 0) {
                self.line_break_two.visible = false;
                self.decor.image_data.nine_slice.h = self.line_break_two.y;
            } else {
                self.line_break_two.visible = true;
                self.decor.image_data.nine_slice.h = self.footer.y + self.footer.text_data._height + 10;
            }

            self.root.x = params.x - self.decor.width() - 15;
            self.root.y = params.y - self.decor.height() - 15;
        }
    }
};
