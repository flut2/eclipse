const std = @import("std");
const element = @import("../element.zig");
const game_data = @import("../../game_data.zig");
const input = @import("../../input.zig");

const BasicPanel = @import("../panels/basic_panel.zig").BasicPanel;
const OptionsPanel = @import("../panels/options_panel.zig").OptionsPanel;
const sc = @import("screen_controller.zig");

const NineSlice = element.NineSliceImageData;

pub const PanelController = struct {
    x: f32 = 0,
    y: f32 = 0,
    width: f32 = 0,
    height: f32 = 0,
    inited: bool = false,
    _allocator: std.mem.Allocator = undefined,

    basic_panel: *BasicPanel = undefined,
    options: *OptionsPanel = undefined,

    pub fn init(allocator: std.mem.Allocator, data: PanelController) !*PanelController {
        var controller = try allocator.create(PanelController);
        controller.* = data;
        controller._allocator = allocator;

        controller.basic_panel = try BasicPanel.init(allocator, .{
            .x = controller.x - controller.width,
            .y = controller.y - (controller.height / 2) - 5,
            .width = controller.width,
            .height = controller.height,
            .visible = false,
        });

        controller.options = try OptionsPanel.init(allocator);

        controller.inited = true;
        return controller;
    }

    pub fn deinit(self: *PanelController) void {
        self.basic_panel.deinit();
        self.options.deinit();
        self._allocator.destroy(self);
    }

    pub fn hidePanels(self: *PanelController) void {
        self.basic_panel.setVisible(false);
    }

    fn hideSmallPanels(self: *PanelController) void {
        self.basic_panel.setVisible(false);
    }

    pub fn showBasicPanel(self: *PanelController, text: []const u8, size: f32) void {
        self.basic_panel.title_text.text_data.text = text;
        self.basic_panel.title_text.text_data.size = size;
        self.basic_panel.setVisible(true);
    }

    pub fn showPanel(self: *PanelController, class_type: game_data.ClassType) void {
        input.disable_input = true;
        input.reset();

        self.hideSmallPanels();
        switch (class_type) {
            else => {
                self.hidePanels();
                std.log.err("screen_controller:: {} screen not implemented", .{class_type});
            },
        }
    }

    pub fn basicPanelCallback() void {
        const game_screen = sc.current_screen.game;
        var self = game_screen.panel_controller;
        self.showPanel(game_screen.interact_class);
        self.hidePanels();
    }

    pub fn resize(self: *PanelController, w: f32, h: f32) void {
        self.basic_panel.resize(w, h, self.width, self.height);
        self.options.resize(w, h);
    }

    pub fn setOptionsVisible(self: *PanelController, vis: bool) void {
        self.options.setVisible(vis);
        input.disable_input = vis;
    }
};
