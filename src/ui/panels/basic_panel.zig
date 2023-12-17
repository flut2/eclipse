const std = @import("std");
const element = @import("../element.zig");
const assets = @import("../../assets.zig");
const PanelController = @import("../controllers/panel_controller.zig").PanelController;
const NineSlice = element.NineSliceImageData;

pub const BasicPanel = struct {
    x: f32 = 0,
    y: f32 = 0,
    width: f32 = 0,
    height: f32 = 0,
    visible: bool = false,
    _allocator: std.mem.Allocator = undefined,
    inited: bool = false,
    cont: *element.Container = undefined,
    title_text: *element.Text = undefined,

    pub fn init(allocator: std.mem.Allocator, data: BasicPanel) !*BasicPanel {
        var panel = try allocator.create(BasicPanel);
        panel.* = data;
        panel._allocator = allocator;

        const basic_panel_data = assets.getUiData("basic_panel", 0);

        panel.cont = try element.Container.create(allocator, .{
            .x = panel.x - basic_panel_data.texWRaw(),
            .y = panel.y,
            .visible = panel.visible,
        });

        _ = try panel.cont.createElement(element.Image, .{
            .x = 0,
            .y = 0,
            .image_data = .{ .normal = .{ .atlas_data = basic_panel_data } },
        });

        panel.title_text = try panel.cont.createElement(element.Text, .{ .x = 10, .y = 10, .text_data = .{
            .text = "",
            .size = 22,
            .text_type = .bold,
        } });

        const button_data_base = assets.getUiData("button_base", 0);
        const button_data_hover = assets.getUiData("button_hover", 0);
        const button_data_press = assets.getUiData("button_press", 0);

        const button_width: f32 = basic_panel_data.texWRaw() - 20;
        const button_height: f32 = 25;

        _ = try panel.cont.createElement(element.Button, .{
            .x = 10,
            .y = basic_panel_data.texHRaw() - button_height - 15,
            .image_data = .{
                .base = .{ .nine_slice = NineSlice.fromAtlasData(button_data_base, button_width, button_height, 6, 6, 7, 7, 1.0) },
                .hover = .{ .nine_slice = NineSlice.fromAtlasData(button_data_hover, button_width, button_height, 6, 6, 7, 7, 1.0) },
                .press = .{ .nine_slice = NineSlice.fromAtlasData(button_data_press, button_width, button_height, 6, 6, 7, 7, 1.0) },
            },
            .text_data = .{
                .text = "Open",
                .size = 16,
                .text_type = .bold,
            },
            .press_callback = PanelController.basicPanelCallback,
        });

        panel.inited = true;
        return panel;
    }

    pub fn setVisible(self: *BasicPanel, val: bool) void {
        self.cont.visible = val;
    }

    pub fn deinit(self: *BasicPanel) void {
        self.cont.destroy();
        self._allocator.destroy(self);
    }

    pub fn resize(self: *BasicPanel, screen_w: f32, screen_h: f32, w: f32, h: f32) void {
        self.cont.x = screen_w - w - w;
        self.cont.y = screen_h - (h / 2) - 10;
    }
};
