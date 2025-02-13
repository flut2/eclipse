const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const network_data = shared.network_data;
const f32i = shared.utils.f32i;

const assets = @import("../../assets.zig");
const map = @import("../../game/map.zig");
const input = @import("../../input.zig");
const main = @import("../../main.zig");
const Button = @import("../elements/Button.zig");
const Container = @import("../elements/Container.zig");
const element = @import("../elements/element.zig");
const Image = @import("../elements/Image.zig");
const ScrollableContainer = @import("../elements/ScrollableContainer.zig");
const Text = @import("../elements/Text.zig");
const systems = @import("../systems.zig");

const ResourceView = @This();
const ResourceSlot = struct {
    base: *Container,
    decor: *Image,
    icon: *Image,
    amount_text: *Text,

    pub fn create(root: *ScrollableContainer, data: game_data.ResourceData, idx: usize, amount: u32) !ResourceSlot {
        const icon_tex_list = assets.atlas_data.get(data.icon.sheet) orelse return error.IconSheetNotFound;
        if (icon_tex_list.len <= data.icon.index) return error.IconIndexTooLarge;
        const icon = icon_tex_list[data.icon.index];

        const base = try root.createChild(Container, .{ .base = .{
            .x = f32i(idx / 2) * 185.0,
            .y = f32i(idx % 2) * 49.0,
        } });

        // this is extracted for ordering
        const decor = try base.createChild(Image, .{
            .base = .{ .x = 0, .y = 0 },
            .image_data = .{ .normal = .{ .atlas_data = assets.getUiData("resource_view_cell", 0) } },
        });

        const amount_text = try base.createChild(Text, .{
            .base = .{ .x = 38, .y = 5 },
            .text_data = .{
                .text = "",
                .size = 10,
                .max_chars = 128,
                .vert_align = .middle,
                .hori_align = .middle,
                .max_width = 131,
                .max_height = 28,
            },
        });
        amount_text.text_data.setText(
            try std.fmt.bufPrint(amount_text.text_data.backing_buffer, "{}x {s}", .{ amount, data.name }),
        );

        return .{
            .base = base,
            .decor = decor,
            .icon = try base.createChild(Image, .{
                .base = .{
                    .x = 5 + (28 - icon.width()) / 2.0,
                    .y = 5 + (28 - icon.height()) / 2.0,
                },
                .image_data = .{ .normal = .{ .atlas_data = icon } },
            }),
            .amount_text = amount_text,
        };
    }

    pub fn destroy(self: *ResourceSlot, root: *ScrollableContainer) void {
        root.container.destroyElement(self.base);
    }
};

base: *Container = undefined,
slot_base: *ScrollableContainer = undefined,
background: *Image = undefined,
title: *Text = undefined,
decor: *Image = undefined,
quit_button: *Button = undefined,
slots: []ResourceSlot = &.{},

pub fn create() !*ResourceView {
    var self = try main.allocator.create(ResourceView);
    self.slots = &.{};

    const background = assets.getUiData("dark_background", 0);
    self.background = try element.create(Image, .{
        .base = .{ .x = 0, .y = 0 },
        .image_data = .{ .nine_slice = .fromAtlasData(background, 0, 0, 0, 0, 8, 8, 1.0) },
    });

    self.base = try element.create(Container, .{ .base = .{ .x = 0, .y = 0 } });
    self.decor = try self.base.createChild(Image, .{
        .base = .{ .x = 0, .y = 0 },
        .image_data = .{ .normal = .{ .atlas_data = assets.getUiData("resource_view_background", 0) } },
    });
    self.title = try self.base.createChild(Text, .{
        .base = .{ .x = 76, .y = 26 },
        .text_data = .{
            .text = "Resources",
            .size = 22,
            .text_type = .bold,
            .max_chars = 32,
            .vert_align = .middle,
            .hori_align = .middle,
            .max_width = 298,
            .max_height = 31,
        },
    });

    const scroll_background_data = assets.getUiData("scroll_background", 0);
    const scroll_knob_base = assets.getUiData("scroll_wheel_base", 0);
    const scroll_knob_hover = assets.getUiData("scroll_wheel_hover", 0);
    const scroll_knob_press = assets.getUiData("scroll_wheel_press", 0);
    const scroll_decor_data = assets.getUiData("scrollbar_decor", 0);
    self.slot_base = try self.base.createChild(ScrollableContainer, .{
        .base = .{ .x = 31, .y = 80 },
        .scissor_w = 358,
        .scissor_h = 360,
        .scroll_x = 413 - 31,
        .scroll_y = 76 - 80,
        .scroll_w = 4,
        .scroll_h = 360,
        .scroll_side_x = 399 - 31,
        .scroll_side_y = 76 - 80,
        .scroll_decor_image_data = .{ .nine_slice = .fromAtlasData(scroll_background_data, 4, 360, 0, 0, 2, 2, 1.0) },
        .scroll_knob_image_data = .fromNineSlices(scroll_knob_base, scroll_knob_hover, scroll_knob_press, 10, 16, 4, 4, 1, 2, 1.0),
        .scroll_side_decor_image_data = .{ .nine_slice = .fromAtlasData(scroll_decor_data, 6, 360, 0, 41, 6, 3, 1.0) },
        .start_value = 1.0,
    });

    const button_base = assets.getUiData("button_base", 0);
    self.quit_button = try self.base.createChild(Button, .{
        .base = .{ .x = 21 + (378 - button_base.width()) / 2.0, .y = 440 + (60 - button_base.height()) / 2.0 },
        .image_data = .fromImageData(
            button_base,
            assets.getUiData("button_hover", 0),
            assets.getUiData("button_press", 0),
        ),
        .text_data = .{
            .text = "Quit",
            .size = 16,
            .vert_align = .middle,
            .hori_align = .middle,
            .max_width = button_base.width(),
            .max_height = button_base.height(),
        },
        .userdata = self,
        .pressCallback = quitCallback,
    });
    self.resize(main.camera.width, main.camera.height);
    self.setVisible(false);
    return self;
}

pub fn destroy(self: *ResourceView) void {
    element.destroy(self.base);
    element.destroy(self.background);
    main.allocator.free(self.slots);
    main.allocator.destroy(self);
}

pub fn resize(self: *ResourceView, w: f32, h: f32) void {
    self.background.image_data.scaleWidth(w);
    self.background.image_data.scaleHeight(h);
    self.base.base.x = (w - self.base.width()) / 2.0;
    self.base.base.y = (h - self.base.height()) / 2.0;
}

pub fn update(self: *ResourceView, resources: []const network_data.DataIdWithCount(u32)) !void {
    for (self.slots) |*slot| slot.destroy(self.slot_base);
    main.allocator.free(self.slots);

    var slots: std.ArrayListUnmanaged(ResourceSlot) = .empty;
    var i: usize = 0;
    for (resources) |resource| {
        const resource_data = game_data.resource.from_id.get(resource.data_id) orelse {
            std.log.err("Could not populate resource with id {}", .{resource.data_id});
            continue;
        };
        slots.append(main.allocator, try .create(self.slot_base, resource_data, i, resource.count)) catch main.oomPanic();
        i += 1;
    }
    self.slots = slots.toOwnedSlice(main.allocator) catch main.oomPanic();
}

pub fn setVisible(self: *ResourceView, visible: bool) void {
    self.base.base.visible = visible;
    self.background.base.visible = visible;
}

fn quitCallback(ud: ?*anyopaque) void {
    const self: *ResourceView = @ptrCast(@alignCast(ud));
    defer self.setVisible(false);
}
