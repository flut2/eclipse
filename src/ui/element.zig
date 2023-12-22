const std = @import("std");
const camera = @import("../camera.zig");
const assets = @import("../assets.zig");
const main = @import("../main.zig");
const zglfw = @import("zglfw");
const settings = @import("../settings.zig");
const sc = @import("controllers/screen_controller.zig");
const tooltip = @import("tooltips/tooltip.zig");

pub const RGBF32 = extern struct {
    r: f32,
    g: f32,
    b: f32,

    pub fn fromValues(r: f32, g: f32, b: f32) RGBF32 {
        return RGBF32{ .r = r, .g = g, .b = b };
    }

    pub fn fromInt(int: u32) RGBF32 {
        return RGBF32{
            .r = @as(f32, @floatFromInt((int & 0xFF0000) >> 16)) / 255.0,
            .g = @as(f32, @floatFromInt((int & 0x00FF00) >> 8)) / 255.0,
            .b = @as(f32, @floatFromInt((int & 0x0000FF) >> 0)) / 255.0,
        };
    }
};

pub const InteractableState = enum {
    none,
    pressed,
    hovered,
};

pub const InteractableImageData = struct {
    base: ImageData,
    hover: ?ImageData = null,
    press: ?ImageData = null,

    pub fn current(self: InteractableImageData, state: InteractableState) ImageData {
        switch (state) {
            .none => return self.base,
            .pressed => return self.press orelse self.base,
            .hovered => return self.hover orelse self.base,
        }
    }
};

// Scissor positions are relative to the element it's attached to
pub const ScissorRect = extern struct {
    pub const dont_scissor = -1.0;

    min_x: f32 = dont_scissor,
    max_x: f32 = dont_scissor,
    min_y: f32 = dont_scissor,
    max_y: f32 = dont_scissor,

    // hack
    pub fn isDefault(self: ScissorRect) bool {
        return @as(u128, @bitCast(self)) == @as(u128, @bitCast(ScissorRect{}));
    }
};

pub const Input = struct {
    x: f32,
    y: f32,
    text_inlay_x: f32,
    text_inlay_y: f32,
    image_data: InteractableImageData,
    cursor_image_data: ImageData,
    text_data: TextData,
    allocator: std.mem.Allocator,
    enter_callback: ?*const fn ([]const u8) void = null,
    state: InteractableState = .none,
    is_chat: bool = false,
    scissor: ScissorRect = .{},
    visible: bool = true,
    // -1 means not selected
    _last_input: i64 = -1,
    _x_offset: f32 = 0.0,
    _index: u32 = 0,
    _disposed: bool = false,
    _allocator: std.mem.Allocator = undefined,

    pub fn create(allocator: std.mem.Allocator, data: Input) !*Input {
        const should_lock = sc.elements.capacity == 0;
        if (should_lock) {
            while (!sc.ui_lock.tryLock()) {}
        }
        defer if (should_lock) sc.ui_lock.unlock();

        var elem = try allocator.create(Input);
        elem.* = data;
        elem._allocator = allocator;

        if (elem.text_data.scissor.isDefault()) {
            elem.text_data.scissor = .{
                .min_x = 0,
                .min_y = 0,
                .max_x = elem.width() - elem.text_inlay_x * 2,
                .max_y = elem.height() - elem.text_inlay_y * 2,
            };
        }

        elem.text_data.recalculateAttributes(allocator);

        switch (elem.cursor_image_data) {
            .nine_slice => |*nine_slice| nine_slice.h = elem.text_data._height,
            .normal => |*image_data| image_data.scale_y = elem.text_data._height / image_data.height(),
        }

        try sc.elements.append(.{ .input_field = elem });
        return elem;
    }

    pub fn imageData(self: Input) ImageData {
        return self.image_data.current(self.state);
    }

    pub fn width(self: Input) f32 {
        return @max(self.text_data._width, switch (self.imageData()) {
            .nine_slice => |nine_slice| return nine_slice.w,
            .normal => |image_data| return image_data.width(),
        });
    }

    pub fn height(self: Input) f32 {
        return @max(self.text_data._height, switch (self.imageData()) {
            .nine_slice => |nine_slice| return nine_slice.h,
            .normal => |image_data| return image_data.height(),
        });
    }

    pub fn clear(self: *Input) void {
        self.text_data.text = "";
        self.text_data.recalculateAttributes(self._allocator);
        self._index = 0;
        self.inputUpdate();
    }

    pub fn inputUpdate(self: *Input) void {
        self._last_input = main.current_time;
        self.text_data.recalculateAttributes(self._allocator);

        const cursor_width = switch (self.cursor_image_data) {
            .nine_slice => |nine_slice| if (nine_slice.alpha > 0) nine_slice.w else 0.0,
            .normal => |image_data| if (image_data.alpha > 0) image_data.width() else 0.0,
        };

        const img_width = switch (self.imageData()) {
            .nine_slice => |nine_slice| nine_slice.w,
            .normal => |image_data| image_data.width(),
        } - self.text_inlay_x * 2 - cursor_width;
        const offset = @max(0, self.text_data._width - img_width);
        self._x_offset = -offset;
        self.text_data.scissor.min_x = offset;
        self.text_data.scissor.max_x = offset + img_width;
    }

    pub fn destroy(self: *Input) void {
        if (self._disposed)
            return;

        self._disposed = true;

        for (sc.elements.items, 0..) |element, i| {
            if (element == .input_field and element.input_field == self) {
                _ = sc.elements.swapRemove(i);
                break;
            }
        }

        self.text_data.deinit(self._allocator);
        self._allocator.destroy(self);
    }
};

pub const Button = struct {
    x: f32,
    y: f32,
    press_callback: *const fn () void,
    image_data: InteractableImageData,
    state: InteractableState = .none,
    text_data: ?TextData = null,
    scissor: ScissorRect = .{},
    visible: bool = true,
    _disposed: bool = false,
    _allocator: std.mem.Allocator = undefined,

    pub fn create(allocator: std.mem.Allocator, data: Button) !*Button {
        const should_lock = sc.elements.capacity == 0;
        if (should_lock) {
            while (!sc.ui_lock.tryLock()) {}
        }
        defer if (should_lock) sc.ui_lock.unlock();

        var elem = try allocator.create(Button);
        elem.* = data;
        elem._allocator = allocator;
        if (elem.text_data) |*text_data| {
            text_data.recalculateAttributes(allocator);
        }
        try sc.elements.append(.{ .button = elem });
        return elem;
    }

    pub fn imageData(self: Button) ImageData {
        return self.image_data.current(self.state);
    }

    pub fn width(self: Button) f32 {
        if (self.text_data) |text| {
            return @max(text._width, switch (self.imageData()) {
                .nine_slice => |nine_slice| return nine_slice.w,
                .normal => |image_data| return image_data.width(),
            });
        } else {
            return switch (self.imageData()) {
                .nine_slice => |nine_slice| return nine_slice.w,
                .normal => |image_data| return image_data.width(),
            };
        }
    }

    pub fn height(self: Button) f32 {
        if (self.text_data) |text| {
            return @max(text._height, switch (self.imageData()) {
                .nine_slice => |nine_slice| return nine_slice.h,
                .normal => |image_data| return image_data.height(),
            });
        } else {
            return switch (self.imageData()) {
                .nine_slice => |nine_slice| return nine_slice.h,
                .normal => |image_data| return image_data.height(),
            };
        }
    }

    pub fn destroy(self: *Button) void {
        if (self._disposed)
            return;

        self._disposed = true;

        for (sc.elements.items, 0..) |element, i| {
            if (element == .button and element.button == self) {
                _ = sc.elements.swapRemove(i);
                break;
            }
        }

        if (self.text_data) |*text_data| {
            text_data.deinit(self._allocator);
        }

        self._allocator.destroy(self);
    }
};

pub const KeyMapper = struct {
    x: f32,
    y: f32,
    set_key_callback: *const fn (*KeyMapper) void,
    image_data: InteractableImageData,
    settings_button: *settings.Button,
    key: zglfw.Key = zglfw.Key.unknown,
    mouse: zglfw.MouseButton = zglfw.MouseButton.unknown,
    title_text_data: ?TextData = null,
    tooltip_text: ?TextData = null,
    state: InteractableState = .none,
    scissor: ScissorRect = .{},
    visible: bool = true,
    listening: bool = false,
    _disposed: bool = false,
    _allocator: std.mem.Allocator = undefined,

    pub fn create(allocator: std.mem.Allocator, data: KeyMapper) !*KeyMapper {
        const should_lock = sc.elements.capacity == 0;
        if (should_lock) {
            while (!sc.ui_lock.tryLock()) {}
        }
        defer if (should_lock) sc.ui_lock.unlock();

        var elem = try allocator.create(KeyMapper);
        elem.* = data;
        elem._allocator = allocator;
        try elem.init();
        try sc.elements.append(.{ .key_mapper = elem });
        return elem;
    }

    pub fn init(self: *KeyMapper) !void {
        if (self.title_text_data) |*text_data| {
            text_data.recalculateAttributes(self._allocator);
        }
        if (self.tooltip_text) |*text_data| {
            text_data.recalculateAttributes(self._allocator);
        }
    }

    pub fn imageData(self: KeyMapper) ImageData {
        return self.image_data.current(self.state);
    }

    pub fn width(self: KeyMapper) f32 {
        const extra = if (self.title_text_data) |t| t._width else 0;
        return switch (self.imageData()) {
            .nine_slice => |nine_slice| return nine_slice.w + extra,
            .normal => |image_data| return image_data.width() + extra,
        };
    }

    pub fn height(self: KeyMapper) f32 {
        return switch (self.imageData()) {
            .nine_slice => |nine_slice| return nine_slice.h,
            .normal => |image_data| return image_data.height(),
        };
    }

    pub fn deinit(self: *KeyMapper) void {
        if (self.title_text_data) |*text_data| {
            text_data.deinit(self._allocator);
        }
        if (self.tooltip_text) |*text_data| {
            text_data.deinit(self._allocator);
        }
    }

    pub fn destroy(self: *KeyMapper) void {
        if (self._disposed)
            return;

        self._disposed = true;

        for (sc.elements.items, 0..) |element, i| {
            if (element == .key_mapper and element.key_mapper == self) {
                _ = sc.elements.swapRemove(i);
                break;
            }
        }

        self.deinit();
        self._allocator.destroy(self);
    }
};

pub const CharacterBox = struct {
    x: f32,
    y: f32,
    id: u32,
    obj_type: u16, //added so I don't have to make a NewCharacterBox struct rn
    press_callback: *const fn (*CharacterBox) void,
    image_data: InteractableImageData,
    state: InteractableState = .none,
    text_data: ?TextData = null,
    scissor: ScissorRect = .{},
    visible: bool = true,
    _disposed: bool = false,
    _allocator: std.mem.Allocator = undefined,

    pub fn create(allocator: std.mem.Allocator, data: CharacterBox) !*CharacterBox {
        const should_lock = sc.elements.capacity == 0;
        if (should_lock) {
            while (!sc.ui_lock.tryLock()) {}
        }
        defer if (should_lock) sc.ui_lock.unlock();

        var elem = try allocator.create(CharacterBox);
        elem.* = data;
        elem._allocator = allocator;
        if (elem.text_data) |*text_data| {
            text_data.recalculateAttributes(allocator);
        }
        try sc.elements.append(.{ .char_box = elem });
        return elem;
    }

    pub fn imageData(self: CharacterBox) ImageData {
        return self.image_data.current(self.state);
    }

    pub fn width(self: CharacterBox) f32 {
        if (self.text_data) |text| {
            return @max(text._width, switch (self.imageData()) {
                .nine_slice => |nine_slice| return nine_slice.w,
                .normal => |image_data| return image_data.width(),
            });
        } else {
            return switch (self.imageData()) {
                .nine_slice => |nine_slice| return nine_slice.w,
                .normal => |image_data| return image_data.width(),
            };
        }
    }

    pub fn height(self: CharacterBox) f32 {
        if (self.text_data) |text| {
            return @max(text._height, switch (self.imageData()) {
                .nine_slice => |nine_slice| return nine_slice.h,
                .normal => |image_data| return image_data.height(),
            });
        } else {
            return switch (self.imageData()) {
                .nine_slice => |nine_slice| return nine_slice.h,
                .normal => |image_data| return image_data.height(),
            };
        }
    }

    pub fn destroy(self: *CharacterBox) void {
        if (self._disposed)
            return;

        self._disposed = true;

        for (sc.elements.items, 0..) |element, i| {
            if (element == .char_box and element.char_box == self) {
                _ = sc.elements.swapRemove(i);
                break;
            }
        }

        if (self.text_data) |*text_data| {
            text_data.deinit(self._allocator);
        }

        self._allocator.destroy(self);
    }
};

pub const NineSliceImageData = struct {
    const AtlasData = assets.AtlasData;

    const top_left_idx = 0;
    const top_center_idx = 1;
    const top_right_idx = 2;
    const middle_left_idx = 3;
    const middle_center_idx = 4;
    const middle_right_idx = 5;
    const bottom_left_idx = 6;
    const bottom_center_idx = 7;
    const bottom_right_idx = 8;

    w: f32,
    h: f32,
    alpha: f32 = 1.0,
    color: u32 = std.math.maxInt(u32),
    color_intensity: f32 = 0,
    atlas_data: [9]AtlasData,

    pub fn fromAtlasData(data: AtlasData, w: f32, h: f32, slice_x: f32, slice_y: f32, slice_w: f32, slice_h: f32, alpha: f32) NineSliceImageData {
        const base_u = data.texURaw() + assets.padding;
        const base_v = data.texVRaw() + assets.padding;
        const base_w = data.texWRaw() - assets.padding * 2;
        const base_h = data.texHRaw() - assets.padding * 2;
        return .{
            .w = w,
            .h = h,
            .alpha = alpha,
            .atlas_data = .{
                AtlasData.fromRawF32(base_u, base_v, slice_x, slice_y),
                AtlasData.fromRawF32(base_u + slice_x, base_v, slice_w, slice_y),
                AtlasData.fromRawF32(base_u + slice_x + slice_w, base_v, base_w - slice_w - slice_x, slice_y),
                AtlasData.fromRawF32(base_u, base_v + slice_y, slice_x, slice_h),
                AtlasData.fromRawF32(base_u + slice_x, base_v + slice_y, slice_w, slice_h),
                AtlasData.fromRawF32(base_u + slice_x + slice_w, base_v + slice_y, base_w - slice_w - slice_x, slice_h),
                AtlasData.fromRawF32(base_u, base_v + slice_y + slice_h, slice_x, base_h - slice_h - slice_y),
                AtlasData.fromRawF32(base_u + slice_x, base_v + slice_y + slice_h, slice_w, base_h - slice_h - slice_y),
                AtlasData.fromRawF32(base_u + slice_x + slice_w, base_v + slice_y + slice_h, base_w - slice_w - slice_x, base_h - slice_h - slice_y),
            },
        };
    }

    pub fn topLeft(self: NineSliceImageData) AtlasData {
        return self.atlas_data[top_left_idx];
    }

    pub fn topCenter(self: NineSliceImageData) AtlasData {
        return self.atlas_data[top_center_idx];
    }

    pub fn topRight(self: NineSliceImageData) AtlasData {
        return self.atlas_data[top_right_idx];
    }

    pub fn middleLeft(self: NineSliceImageData) AtlasData {
        return self.atlas_data[middle_left_idx];
    }

    pub fn middleCenter(self: NineSliceImageData) AtlasData {
        return self.atlas_data[middle_center_idx];
    }

    pub fn middleRight(self: NineSliceImageData) AtlasData {
        return self.atlas_data[middle_right_idx];
    }

    pub fn bottomLeft(self: NineSliceImageData) AtlasData {
        return self.atlas_data[bottom_left_idx];
    }

    pub fn bottomCenter(self: NineSliceImageData) AtlasData {
        return self.atlas_data[bottom_center_idx];
    }

    pub fn bottomRight(self: NineSliceImageData) AtlasData {
        return self.atlas_data[bottom_right_idx];
    }
};

pub const NormalImageData = struct {
    scale_x: f32 = 1.0,
    scale_y: f32 = 1.0,
    alpha: f32 = 1.0,
    color: u32 = std.math.maxInt(u32),
    color_intensity: f32 = 0,
    atlas_data: assets.AtlasData,
    glow: bool = false,

    pub fn width(self: NormalImageData) f32 {
        return self.atlas_data.texWRaw() * self.scale_x;
    }

    pub fn height(self: NormalImageData) f32 {
        return self.atlas_data.texHRaw() * self.scale_y;
    }
};

pub const ImageData = union(enum) {
    nine_slice: NineSliceImageData,
    normal: NormalImageData,
};

pub const Image = struct {
    x: f32,
    y: f32,
    image_data: ImageData,
    scissor: ScissorRect = .{},
    ui_quad: bool = true,
    visible: bool = true,
    // hack
    is_minimap_decor: bool = false,
    minimap_offset_x: f32 = 0.0,
    minimap_offset_y: f32 = 0.0,
    minimap_width: f32 = 0.0,
    minimap_height: f32 = 0.0,
    _disposed: bool = false,
    _allocator: std.mem.Allocator = undefined,

    pub fn create(allocator: std.mem.Allocator, data: Image) !*Image {
        const should_lock = sc.elements.capacity == 0;
        if (should_lock) {
            while (!sc.ui_lock.tryLock()) {}
        }
        defer if (should_lock) sc.ui_lock.unlock();

        var elem = try allocator.create(Image);
        elem.* = data;
        elem._allocator = allocator;
        try sc.elements.append(.{ .image = elem });
        return elem;
    }

    pub fn width(self: Image) f32 {
        switch (self.image_data) {
            .nine_slice => |nine_slice| return nine_slice.w,
            .normal => |image_data| return image_data.width(),
        }
    }

    pub fn height(self: Image) f32 {
        switch (self.image_data) {
            .nine_slice => |nine_slice| return nine_slice.h,
            .normal => |image_data| return image_data.height(),
        }
    }

    pub fn destroy(self: *Image) void {
        if (self._disposed)
            return;

        self._disposed = true;

        for (sc.elements.items, 0..) |element, i| {
            if (element == .image and element.image == self) {
                _ = sc.elements.swapRemove(i);
                break;
            }
        }

        self._allocator.destroy(self);
    }
};

pub const MenuBackground = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    scissor: ScissorRect = .{},
    visible: bool = true,
    _disposed: bool = false,
    _allocator: std.mem.Allocator = undefined,

    pub fn create(allocator: std.mem.Allocator, data: MenuBackground) !*MenuBackground {
        const should_lock = sc.elements.capacity == 0;
        if (should_lock) {
            while (!sc.ui_lock.tryLock()) {}
        }
        defer if (should_lock) sc.ui_lock.unlock();

        var elem = try allocator.create(MenuBackground);
        elem.* = data;
        elem._allocator = allocator;
        try sc.elements.append(.{ .menu_bg = elem });
        return elem;
    }

    pub fn width(_: MenuBackground) f32 {
        return @floatFromInt(assets.menu_background.width);
    }

    pub fn height(_: MenuBackground) f32 {
        return @floatFromInt(assets.menu_background.height);
    }

    pub fn destroy(self: *MenuBackground) void {
        if (self._disposed)
            return;

        self._disposed = true;

        for (sc.elements.items, 0..) |element, i| {
            if (element == .menu_bg and element.menu_bg == self) {
                _ = sc.elements.swapRemove(i);
                break;
            }
        }

        self._allocator.destroy(self);
    }
};

pub const Item = struct {
    x: f32,
    y: f32,
    background_x: f32,
    background_y: f32,
    image_data: ImageData,
    drag_start_callback: *const fn (*Item) void,
    drag_end_callback: *const fn (*Item) void,
    double_click_callback: *const fn (*Item) void,
    shift_click_callback: *const fn (*Item) void,
    scissor: ScissorRect = .{},
    visible: bool = true,
    draggable: bool = false,
    // don't set this to anything, it's used for item tier backgrounds
    _background_image_data: ?ImageData = null,
    _is_dragging: bool = false,
    _drag_start_x: f32 = 0,
    _drag_start_y: f32 = 0,
    _drag_offset_x: f32 = 0,
    _drag_offset_y: f32 = 0,
    _last_click_time: i64 = 0,
    _item: u16 = std.math.maxInt(u16),
    _disposed: bool = false,
    _allocator: std.mem.Allocator = undefined,

    pub fn create(allocator: std.mem.Allocator, data: Item) !*Item {
        const should_lock = sc.elements.capacity == 0;
        if (should_lock) {
            while (!sc.ui_lock.tryLock()) {}
        }
        defer if (should_lock) sc.ui_lock.unlock();

        var elem = try allocator.create(Item);
        elem.* = data;
        elem._allocator = allocator;
        try sc.elements.append(.{ .item = elem });
        return elem;
    }

    pub fn width(self: Item) f32 {
        switch (self.image_data) {
            .nine_slice => |nine_slice| return nine_slice.w,
            .normal => |image_data| return image_data.width(),
        }
    }

    pub fn height(self: Item) f32 {
        switch (self.image_data) {
            .nine_slice => |nine_slice| return nine_slice.h,
            .normal => |image_data| return image_data.height(),
        }
    }

    pub fn destroy(self: *Item) void {
        if (self._disposed)
            return;

        self._disposed = true;

        for (sc.elements.items, 0..) |element, i| {
            if (element == .item and element.item == self) {
                _ = sc.elements.swapRemove(i);
                break;
            }
        }

        self._allocator.destroy(self);
    }
};

pub const Bar = struct {
    x: f32,
    y: f32,
    image_data: ImageData,
    scissor: ScissorRect = .{},
    visible: bool = true,
    text_data: TextData,
    _disposed: bool = false,
    _allocator: std.mem.Allocator = undefined,

    pub fn create(allocator: std.mem.Allocator, data: Bar) !*Bar {
        const should_lock = sc.elements.capacity == 0;
        if (should_lock) {
            while (!sc.ui_lock.tryLock()) {}
        }
        defer if (should_lock) sc.ui_lock.unlock();

        var elem = try allocator.create(Bar);
        elem.* = data;
        elem._allocator = allocator;
        elem.text_data.recalculateAttributes(allocator);
        try sc.elements.append(.{ .bar = elem });
        return elem;
    }

    pub fn width(self: Bar) f32 {
        switch (self.image_data) {
            .nine_slice => |nine_slice| return nine_slice.w,
            .normal => |image_data| return image_data.width(),
        }
    }

    pub fn height(self: Bar) f32 {
        switch (self.image_data) {
            .nine_slice => |nine_slice| return nine_slice.h,
            .normal => |image_data| return image_data.height(),
        }
    }

    pub fn destroy(self: *Bar) void {
        if (self._disposed)
            return;

        self._disposed = true;

        for (sc.elements.items, 0..) |element, i| {
            if (element == .bar and element.bar == self) {
                _ = sc.elements.swapRemove(i);
                break;
            }
        }

        self.text_data.deinit(self._allocator);
        self._allocator.destroy(self);
    }
};

pub const Text = struct {
    x: f32,
    y: f32,
    text_data: TextData,
    scissor: ScissorRect = .{},
    visible: bool = true,
    _disposed: bool = false,
    _allocator: std.mem.Allocator = undefined,

    pub fn create(allocator: std.mem.Allocator, data: Text) !*Text {
        const should_lock = sc.elements.capacity == 0;
        if (should_lock) {
            while (!sc.ui_lock.tryLock()) {}
        }
        defer if (should_lock) sc.ui_lock.unlock();

        var elem = try allocator.create(Text);
        elem.* = data;
        elem._allocator = allocator;
        elem.init();
        try sc.elements.append(.{ .text = elem });
        return elem;
    }

    pub fn init(self: *Text) void {
        self.text_data.recalculateAttributes(self._allocator);
    }

    pub fn deinit(self: *Text) void {
        self.text_data.deinit(self._allocator);
    }

    pub fn width(self: Text) f32 {
        return self.text_data._width;
    }

    pub fn height(self: Text) f32 {
        return self.text_data._height;
    }

    pub fn destroy(self: *Text) void {
        if (self._disposed)
            return;

        self._disposed = true;

        for (sc.elements.items, 0..) |*element, i| {
            if (element.* == .text and element.text == self) {
                _ = sc.elements.swapRemove(i);
                break;
            }
        }

        self.deinit();
        self._allocator.destroy(self);
    }
};

pub const TextType = enum(u32) {
    medium = 0,
    medium_italic = 1,
    bold = 2,
    bold_italic = 3,
};

pub const AlignHori = enum(u8) {
    left = 0,
    middle = 1,
    right = 2,
};

pub const AlignVert = enum(u8) {
    top = 0,
    middle = 1,
    bottom = 2,
};

pub const TextData = struct {
    text: []const u8,
    size: f32,
    // 0 implies that the backing buffer won't be used. if your element uses it, you must set this to something above 0
    max_chars: u32 = 0,
    text_type: TextType = .medium,
    color: u32 = 0xFFFFFF,
    alpha: f32 = 1.0,
    shadow_color: u32 = 0xFF000000,
    shadow_alpha_mult: f32 = 0.5,
    shadow_texel_offset_mult: f32 = 0.0,
    outline_color: u32 = 0xFF000000,
    outline_width: f32 = 1.2, // 0.5 for off
    password: bool = false,
    handle_special_chars: bool = true,
    disable_subpixel: bool = false,
    scissor: ScissorRect = .{},
    // alignments other than default need max width/height defined respectively
    hori_align: AlignHori = .left,
    vert_align: AlignVert = .top,
    max_width: f32 = std.math.floatMax(f32),
    max_height: f32 = std.math.floatMax(f32),
    _backing_buffer: []u8 = &[0]u8{},
    _lock: std.Thread.Mutex = .{},
    _width: f32 = 0.0,
    _height: f32 = 0.0,
    _line_count: f32 = 0.0,
    _line_widths: ?std.ArrayList(f32) = null,

    pub fn recalculateAttributes(self: *TextData, allocator: std.mem.Allocator) void {
        while (!self._lock.tryLock()) {}
        defer self._lock.unlock();

        if (self._backing_buffer.len == 0 and self.max_chars > 0)
            self._backing_buffer = allocator.alloc(u8, self.max_chars) catch @panic("Failed to allocate the backing buffer");

        if (self._line_widths) |*line_widths| {
            line_widths.clearRetainingCapacity();
        } else {
            self._line_widths = std.ArrayList(f32).init(allocator);
        }

        const size_scale = self.size / assets.CharacterData.size * camera.scale * assets.CharacterData.padding_mult;
        var line_height = assets.CharacterData.line_height * assets.CharacterData.size * size_scale;

        var x_max: f32 = 0.0;
        var x_pointer: f32 = 0.0;
        var y_pointer: f32 = line_height;
        var current_size = size_scale;
        var current_type = self.text_type;
        var index_offset: u16 = 0;
        for (0..self.text.len) |i| {
            if (i + index_offset >= self.text.len) {
                self._width = @max(x_max, x_pointer);
                self._line_widths.?.append(x_pointer) catch |e| {
                    std.log.err("Attribute recalculation for text data failed: {any}", .{e});
                    return;
                };
                self._height = y_pointer;
                return;
            }

            const char = self.text[i + index_offset];
            specialChar: {
                if (!self.handle_special_chars)
                    break :specialChar;

                if (char == '&') {
                    const start_idx = i + index_offset + 3;
                    if (self.text.len <= start_idx or self.text[start_idx - 1] != '=')
                        break :specialChar;

                    switch (self.text[start_idx - 2]) {
                        'c' => {
                            if (self.text.len < start_idx + 6)
                                break :specialChar;

                            index_offset += 8;
                            continue;
                        },
                        's' => {
                            var size_len: u8 = 0;
                            while (start_idx + size_len < self.text.len and std.ascii.isDigit(self.text[start_idx + size_len])) {
                                size_len += 1;
                            }

                            if (size_len == 0)
                                break :specialChar;

                            const size = std.fmt.parseFloat(f32, self.text[start_idx .. start_idx + size_len]) catch 16.0;
                            current_size = size / assets.CharacterData.size * camera.scale * assets.CharacterData.padding_mult;
                            line_height = assets.CharacterData.line_height * assets.CharacterData.size * current_size;
                            index_offset += 2 + size_len;
                            continue;
                        },
                        't' => {
                            switch (self.text[start_idx]) {
                                'm' => current_type = .medium,
                                'i' => current_type = .medium_italic,
                                'b' => current_type = .bold,
                                // this has no reason to be 'c', just a hack...
                                'c' => current_type = .bold_italic,
                                else => {},
                            }

                            index_offset += 3;
                            continue;
                        },
                        else => {},
                    }
                }
            }

            const mod_char = if (self.password) '*' else char;

            const char_data = switch (self.text_type) {
                .medium => assets.medium_chars[mod_char],
                .medium_italic => assets.medium_italic_chars[mod_char],
                .bold => assets.bold_chars[mod_char],
                .bold_italic => assets.bold_italic_chars[mod_char],
            };

            var next_x_pointer = x_pointer + char_data.x_advance * current_size;
            if (char == '\n' or next_x_pointer > self.max_width) {
                self._width = @max(x_max, x_pointer);
                self._line_widths.?.append(x_pointer) catch |e| {
                    std.log.err("Attribute recalculation for text data failed: {any}", .{e});
                    return;
                };
                self._line_count += 1;
                next_x_pointer = char_data.x_advance * current_size;
                y_pointer += line_height;
            }

            x_pointer = next_x_pointer;
            if (x_pointer > x_max)
                x_max = x_pointer;
        }

        self._width = @max(x_max, x_pointer);
        self._line_widths.?.append(x_pointer) catch |e| {
            std.log.err("Attribute recalculation for text data failed: {any}", .{e});
            return;
        };
        self._height = y_pointer;
    }

    pub fn deinit(self: *TextData, allocator: std.mem.Allocator) void {
        while (!self._lock.tryLock()) {}
        defer self._lock.unlock();

        if (self._backing_buffer.len > 0)
            allocator.free(self._backing_buffer);

        if (self._line_widths) |line_widths| {
            line_widths.deinit();
            self._line_widths = null;
        }
    }
};

pub const ScrollableContainer = struct {
    const Params = struct {
        x: f32,
        y: f32,
        scissor_w: f32,
        scissor_h: f32,
        scroll_x: f32,
        scroll_y: f32,
        scroll_w: f32,
        scroll_h: f32,
        scroll_decor_image_data: ImageData,
        scroll_knob_image_data: InteractableImageData,
        visible: bool = true,
    };

    visible: bool = true,
    base_y: f32 = 0.0,
    scissor_h: f32 = 0.0,
    _container: *Container = undefined,
    _scroll_bar: *Slider = undefined,
    _disposed: bool = false,
    _allocator: std.mem.Allocator,

    pub fn create(allocator: std.mem.Allocator, params: Params) !*ScrollableContainer {
        const should_lock = sc.elements.capacity == 0;
        if (should_lock) {
            while (!sc.ui_lock.tryLock()) {}
        }
        defer if (should_lock) sc.ui_lock.unlock();

        var elem = try allocator.create(ScrollableContainer);
        elem.visible = params.visible;
        elem.* = .{
            .base_y = params.y,
            .scissor_h = params.scissor_h,
            .visible = params.visible,
            ._allocator = allocator,
            ._container = try allocator.create(Container),
            ._scroll_bar = try allocator.create(Slider),
        };

        elem._container.* = .{ .x = params.x, .y = params.y, .scissor = .{
            .min_x = 0,
            .min_y = 0,
            .max_x = params.scissor_w,
            .max_y = params.scissor_h,
        } };
        elem._container._allocator = allocator;
        try elem._container.init();

        elem._scroll_bar.* = .{
            .x = params.scroll_x,
            .y = params.scroll_y,
            .w = params.scroll_w,
            .h = params.scroll_h,
            .decor_image_data = params.scroll_decor_image_data,
            .knob_image_data = params.scroll_knob_image_data,
            .min_value = 0.0,
            .max_value = 1.0,
            .continous_event_fire = true,
            .state_change = onScrollChanged,
            .vertical = true,
            .visible = false,
            ._parent_container = elem,
            ._current_value = 1.0,
        };
        elem._scroll_bar._allocator = allocator;
        try elem._scroll_bar.init();

        try sc.elements.append(.{ .scrollable_container = elem });
        return elem;
    }

    pub fn init(_: *ScrollableContainer) !void {}

    pub fn deinit(self: *ScrollableContainer) void {
        self._container.deinit();
        self._allocator.destroy(self._container);

        self._scroll_bar.deinit();
        self._allocator.destroy(self._scroll_bar);
    }

    pub fn width(self: ScrollableContainer) f32 {
        return @max(self._container.width(), (self._scroll_bar.x - self._container.x) + self._scroll_bar.width());
    }

    pub fn height(self: ScrollableContainer) f32 {
        return @max(self._container.height(), (self._scroll_bar.y - self._container.y) + self._scroll_bar.height());
    }

    pub fn createElement(self: *ScrollableContainer, comptime T: type, data: T) !*T {
        const elem = self._container.createElement(T, data);
        self.update();
        return elem;
    }

    pub fn update(self: *ScrollableContainer) void {
        if (self.scissor_h >= self._container.height()) {
            self._scroll_bar.visible = false;
            return;
        }

        const h_dt_base = (self.scissor_h - self._container.height());
        const h_dt = self._scroll_bar._current_value * h_dt_base;
        const new_h = self._scroll_bar.h / (2.0 + -h_dt_base / self.scissor_h);
        scaleImageData(&self._scroll_bar.knob_image_data.base, new_h);
        if (self._scroll_bar.knob_image_data.hover) |*image_data| scaleImageData(image_data, new_h);
        if (self._scroll_bar.knob_image_data.press) |*image_data| scaleImageData(image_data, new_h);
        self._scroll_bar.setValue(self._scroll_bar._current_value);
        self._scroll_bar.visible = true;

        self._container.y = self.base_y + h_dt;
        self._container.scissor.min_y = -h_dt;
        self._container.scissor.max_y = -h_dt + self.scissor_h;
        self._container.updateScissors();
    }

    fn scaleImageData(image_data: *ImageData, new_h: f32) void {
        switch (image_data.*) {
            .nine_slice => |*nine_slice| nine_slice.h = new_h,
            .normal => |*normal_image_data| normal_image_data.scale_y = normal_image_data.atlas_data.texHRaw() / new_h,
        }
    }

    fn onScrollChanged(scroll_bar: *Slider) void {
        var parent = scroll_bar._parent_container.?;
        if (parent.scissor_h >= parent._container.height()) {
            parent._scroll_bar.visible = false;
            return;
        }

        const h_dt_base = (parent.scissor_h - parent._container.height());
        const h_dt = scroll_bar._current_value * h_dt_base;
        const new_h = parent._scroll_bar.h / (2.0 + -h_dt_base / parent.scissor_h);
        scaleImageData(&parent._scroll_bar.knob_image_data.base, new_h);
        if (parent._scroll_bar.knob_image_data.hover) |*image_data| scaleImageData(image_data, new_h);
        if (parent._scroll_bar.knob_image_data.press) |*image_data| scaleImageData(image_data, new_h);
        parent._scroll_bar.visible = true;

        parent._container.y = parent.base_y + h_dt;
        parent._container.scissor.min_y = -h_dt;
        parent._container.scissor.max_y = -h_dt + parent.scissor_h;
        parent._container.updateScissors();
    }

    pub fn destroy(self: *ScrollableContainer) void {
        if (self._disposed)
            return;

        self._disposed = true;

        self.deinit();
        self._allocator.destroy(self);
    }
};

pub const Container = struct {
    x: f32,
    y: f32,
    scissor: ScissorRect = .{},
    visible: bool = true,
    draggable: bool = false,
    tooltip_container: bool = false,

    _elements: std.ArrayList(UiElement) = undefined,
    _disposed: bool = false,
    _allocator: std.mem.Allocator = undefined,

    _drag_start_x: f32 = 0,
    _drag_start_y: f32 = 0,
    _drag_offset_x: f32 = 0,
    _drag_offset_y: f32 = 0,
    _is_dragging: bool = false,
    _clamp_x: bool = false,
    _clamp_y: bool = false,
    _clamp_to_screen: bool = false,

    pub fn create(allocator: std.mem.Allocator, data: Container) !*Container {
        const should_lock = if (data.tooltip_container) sc.elements.capacity == 0 else sc.tooltip_elements.capacity == 0;
        if (should_lock) {
            while (!sc.ui_lock.tryLock()) {}
        }
        defer if (should_lock) sc.ui_lock.unlock();

        var elem = try allocator.create(Container);
        elem.* = data;
        elem._allocator = allocator;
        try elem.init();
        if (data.tooltip_container) {
            try sc.tooltip_elements.append(.{ .container = elem });
        } else {
            try sc.elements.append(.{ .container = elem });
        }
        return elem;
    }

    pub fn init(self: *Container) !void {
        self._elements = try std.ArrayList(UiElement).initCapacity(self._allocator, 8);
    }

    pub fn createElement(self: *Container, comptime T: type, data: T) !*T {
        var elem = try self._allocator.create(T);
        elem.* = data;
        elem._allocator = self._allocator;

        elem.scissor = .{
            .min_x = if (self.scissor.min_x == ScissorRect.dont_scissor)
                ScissorRect.dont_scissor
            else
                self.scissor.min_x - elem.x,
            .min_y = if (self.scissor.min_y == ScissorRect.dont_scissor)
                ScissorRect.dont_scissor
            else
                self.scissor.min_y - elem.y,
            .max_x = if (self.scissor.max_x == ScissorRect.dont_scissor)
                ScissorRect.dont_scissor
            else
                self.scissor.max_x - elem.x,
            .max_y = if (self.scissor.max_y == ScissorRect.dont_scissor)
                ScissorRect.dont_scissor
            else
                self.scissor.max_y - elem.y,
        };

        switch (T) {
            Image => try self._elements.append(.{ .image = elem }),
            Item => {
                try self._elements.append(.{ .item = elem });
            },
            Bar => {
                elem.text_data.recalculateAttributes(self._allocator);
                try self._elements.append(.{ .bar = elem });
            },
            Input => {
                if (elem.text_data.scissor.isDefault()) {
                    elem.text_data.scissor = .{
                        .min_x = 0,
                        .min_y = 0,
                        .max_x = elem.width() - elem.text_inlay_x * 2,
                        .max_y = elem.height() - elem.text_inlay_y * 2,
                    };
                }

                elem.text_data.recalculateAttributes(self._allocator);

                switch (elem.cursor_image_data) {
                    .nine_slice => |*nine_slice| nine_slice.h = elem.text_data._height,
                    .normal => |*image_data| image_data.scale_y = elem.text_data._height / image_data.height(),
                }

                try self._elements.append(.{ .input_field = elem });
            },
            Button => {
                if (elem.text_data) |*text_data| {
                    text_data.recalculateAttributes(self._allocator);
                }
                try self._elements.append(.{ .button = elem });
            },
            Text => {
                elem.init();
                try self._elements.append(.{ .text = elem });
            },
            CharacterBox => {
                if (elem.text_data) |*text_data| {
                    text_data.recalculateAttributes(self._allocator);
                }
                try self._elements.append(.{ .char_box = elem });
            },
            Container => {
                try elem.init();
                try self._elements.append(.{ .container = elem });
            },
            MenuBackground => try self._elements.append(.{ .menu_bg = elem }),
            Toggle => {
                try elem.init();
                try self._elements.append(.{ .toggle = elem });
            },
            KeyMapper => {
                try elem.init();
                try self._elements.append(.{ .key_mapper = elem });
            },
            Slider => {
                try elem.init();
                try self._elements.append(.{ .slider = elem });
            },
            else => @compileError("Element type not supported"),
        }
        return elem;
    }

    pub fn width(self: Container) f32 {
        if (self._elements.items.len <= 0)
            return 0.0;

        var min_x: f32 = std.math.floatMax(f32);
        var max_x: f32 = std.math.floatMin(f32);
        for (self._elements.items) |elem| {
            switch (elem) {
                .scrollable_container => {},
                inline else => |inner_elem| {
                    if (min_x > inner_elem.x) {
                        min_x = inner_elem.x;
                    }

                    const elem_max_x = inner_elem.x + inner_elem.width();
                    if (max_x < elem_max_x) {
                        max_x = elem_max_x;
                    }
                },
            }
        }

        return max_x - min_x;
    }

    pub fn height(self: Container) f32 {
        if (self._elements.items.len <= 0)
            return 0.0;

        var min_y: f32 = std.math.floatMax(f32);
        var max_y: f32 = std.math.floatMin(f32);
        for (self._elements.items) |elem| {
            switch (elem) {
                .scrollable_container => {},
                inline else => |inner_elem| {
                    if (min_y > inner_elem.y) {
                        min_y = inner_elem.y;
                    }

                    const elem_max_y = inner_elem.y + inner_elem.height();
                    if (max_y < elem_max_y) {
                        max_y = elem_max_y;
                    }
                },
            }
        }

        return max_y - min_y;
    }

    pub fn updateScissors(self: *Container) void {
        for (self._elements.items) |elem| {
            switch (elem) {
                .scrollable_container => {},
                inline else => |inner_elem| {
                    inner_elem.scissor = .{
                        .min_x = if (self.scissor.min_x == ScissorRect.dont_scissor)
                            ScissorRect.dont_scissor
                        else
                            self.scissor.min_x - inner_elem.x,
                        .min_y = if (self.scissor.min_y == ScissorRect.dont_scissor)
                            ScissorRect.dont_scissor
                        else
                            self.scissor.min_y - inner_elem.y,
                        .max_x = if (self.scissor.max_x == ScissorRect.dont_scissor)
                            ScissorRect.dont_scissor
                        else
                            self.scissor.max_x - inner_elem.x,
                        .max_y = if (self.scissor.max_y == ScissorRect.dont_scissor)
                            ScissorRect.dont_scissor
                        else
                            self.scissor.max_y - inner_elem.y,
                    };
                },
            }
        }
    }

    pub fn destroy(self: *Container) void {
        if (self._disposed)
            return;

        self._disposed = true;

        for (sc.elements.items, 0..) |element, i| {
            if (element == .container and element.container == self) {
                _ = sc.elements.swapRemove(i);
                break;
            }
        }

        self.deinit();
        self._allocator.destroy(self);
    }

    pub fn deinit(self: *Container) void {
        for (self._elements.items) |*elem| {
            switch (elem.*) {
                .scrollable_container => |scrollable_container| {
                    scrollable_container.destroy();
                    self._allocator.destroy(scrollable_container);
                },
                .container => |container| {
                    container.deinit();
                    self._allocator.destroy(container);
                },
                .bar => |bar| {
                    bar.text_data.deinit(self._allocator);
                    self._allocator.destroy(bar);
                },
                .input_field => |input_field| {
                    input_field.text_data.deinit(self._allocator);
                    self._allocator.destroy(input_field);
                },
                .button => |button| {
                    if (button.text_data) |*text_data| {
                        text_data.deinit(self._allocator);
                    }
                    self._allocator.destroy(button);
                },
                .char_box => |box| {
                    if (box.text_data) |*text_data| {
                        text_data.deinit(self._allocator);
                    }
                    self._allocator.destroy(box);
                },
                .text => |text| {
                    text.deinit();
                    self._allocator.destroy(text);
                },
                .item => |item| {
                    self._allocator.destroy(item);
                },
                .image => |image| {
                    self._allocator.destroy(image);
                },
                .menu_bg => |menu_bg| {
                    self._allocator.destroy(menu_bg);
                },
                .toggle => |toggle| {
                    toggle.deinit();
                    self._allocator.destroy(toggle);
                },
                .key_mapper => |key_mapper| {
                    key_mapper.deinit();
                    self._allocator.destroy(key_mapper);
                },
                .slider => |slider| {
                    slider.deinit();
                    self._allocator.destroy(slider);
                },
            }
        }
        self._elements.deinit();
    }
};

pub const Toggle = struct {
    x: f32,
    y: f32,
    toggled: *bool,
    off_image_data: InteractableImageData,
    on_image_data: InteractableImageData,
    scissor: ScissorRect = .{},
    state: InteractableState = .none,
    text_data: ?TextData = null,
    tooltip_text: ?TextData = null,
    state_change: ?*const fn (*Toggle) void = null,
    visible: bool = true,
    _disposed: bool = false,
    _allocator: std.mem.Allocator = undefined,

    pub fn create(allocator: std.mem.Allocator, data: Toggle) !*Toggle {
        const should_lock = sc.elements.capacity == 0;
        if (should_lock) {
            while (!sc.ui_lock.tryLock()) {}
        }
        defer if (should_lock) sc.ui_lock.unlock();

        var elem = try allocator.create(Toggle);
        elem.* = data;
        elem._allocator = allocator;
        try elem.init();
        try sc.elements.append(.{ .toggle = elem });
        return elem;
    }

    pub fn init(self: *Toggle) !void {
        if (self.text_data) |*text_data| {
            text_data.recalculateAttributes(self._allocator);
        }
        if (self.tooltip_text) |*text_data| {
            text_data.recalculateAttributes(self._allocator);
        }
    }

    pub fn imageData(self: Toggle) ImageData {
        return if (self.toggled.*)
            self.on_image_data.current(self.state)
        else
            self.off_image_data.current(self.state);
    }

    pub fn width(self: Toggle) f32 {
        switch (self.imageData()) {
            .nine_slice => |nine_slice| return nine_slice.w,
            .normal => |image_data| return image_data.width(),
        }
    }

    pub fn height(self: Toggle) f32 {
        switch (self.imageData()) {
            .nine_slice => |nine_slice| return nine_slice.h,
            .normal => |image_data| return image_data.height(),
        }
    }

    pub fn deinit(self: *Toggle) void {
        if (self.text_data) |*text_data| {
            text_data.deinit(self._allocator);
        }
        if (self.tooltip_text) |*text_data| {
            text_data.deinit(self._allocator);
        }
    }

    pub fn destroy(self: *Toggle) void {
        if (self._disposed)
            return;

        self._disposed = true;

        for (sc.elements.items, 0..) |element, i| {
            if (element == .toggle and element.toggle == self) {
                _ = sc.elements.swapRemove(i);
                break;
            }
        }

        self.deinit();
        self._allocator.destroy(self);
    }
};

pub const Slider = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    min_value: f32,
    max_value: f32,
    decor_image_data: ImageData,
    knob_image_data: InteractableImageData,
    state_change: *const fn (*Slider) void,
    scissor: ScissorRect = .{},
    vertical: bool = false,
    continous_event_fire: bool = true,
    state: InteractableState = .none,
    // the alignments and max w/h on these will be overwritten, don't bother setting it
    value_text_data: ?TextData = null,
    title_text_data: ?TextData = null,
    tooltip_text: ?TextData = null,
    title_offset: f32 = 30.0,
    stored_value: ?*f32 = null, // options hack. remove when callbacks will be able to take in arbitrary params...
    _parent_container: ?*ScrollableContainer = null, // another hack...
    visible: bool = true,
    _knob_x: f32 = 0,
    _knob_y: f32 = 0,
    _current_value: f32 = 0.0,
    _disposed: bool = false,
    _allocator: std.mem.Allocator = undefined,

    pub fn create(allocator: std.mem.Allocator, data: Slider) !*Slider {
        const should_lock = sc.elements.capacity == 0;
        if (should_lock) {
            while (!sc.ui_lock.tryLock()) {}
        }
        defer if (should_lock) sc.ui_lock.unlock();

        var elem = try allocator.create(Slider);
        elem.* = data;
        elem._allocator = allocator;
        try elem.init();
        try sc.elements.append(.{ .slider = elem });
        return elem;
    }

    pub fn width(self: Slider) f32 {
        const decor_w = switch (self.decor_image_data) {
            .nine_slice => |nine_slice| nine_slice.w,
            .normal => |image_data| image_data.width(),
        };

        const knob_w = switch (self.knob_image_data.current(self.state)) {
            .nine_slice => |nine_slice| nine_slice.w,
            .normal => |normal| normal.width(),
        };

        return @max(decor_w, knob_w);
    }

    pub fn height(self: Slider) f32 {
        const decor_h = switch (self.decor_image_data) {
            .nine_slice => |nine_slice| nine_slice.h,
            .normal => |image_data| image_data.height(),
        };

        const knob_h = switch (self.knob_image_data.current(self.state)) {
            .nine_slice => |nine_slice| nine_slice.h,
            .normal => |normal| normal.height(),
        };

        return @max(decor_h, knob_h);
    }

    pub fn init(self: *Slider) !void {
        if (self.stored_value) |value_ptr| {
            value_ptr.* = @min(self.max_value, @max(self.min_value, value_ptr.*));
            self._current_value = value_ptr.*;
        }

        switch (self.decor_image_data) {
            .nine_slice => |*nine_slice| {
                nine_slice.w = self.w;
                nine_slice.h = self.h;
            },
            .normal => |*image_data| {
                image_data.scale_x = self.w / image_data.width();
                image_data.scale_y = self.h / image_data.height();
            },
        }

        const knob_w = switch (self.knob_image_data.current(self.state)) {
            .nine_slice => |nine_slice| nine_slice.w,
            .normal => |normal| normal.width(),
        };
        const knob_h = switch (self.knob_image_data.current(self.state)) {
            .nine_slice => |nine_slice| nine_slice.h,
            .normal => |normal| normal.height(),
        };

        if (self.vertical) {
            const offset = (self.w - knob_w) / 2.0;
            if (offset < 0) {
                self.x = -offset;
            }
            self._knob_x = offset;

            if (self.value_text_data) |*text_data| {
                text_data.hori_align = .left;
                text_data.vert_align = .middle;
                text_data.max_height = knob_h;
            }

            if (self._current_value != 0.0)
                self._knob_y = (self._current_value - self.min_value) / (self.max_value - self.min_value) * self.h - knob_h / 2.0;
        } else {
            const offset = (self.h - knob_h) / 2.0;
            if (offset < 0) {
                self.y = -offset;
            }
            self._knob_y = offset;

            if (self.value_text_data) |*text_data| {
                text_data.hori_align = .middle;
                text_data.vert_align = .top;
                text_data.max_width = knob_w;
            }

            if (self._current_value != 0.0)
                self._knob_x = (self._current_value - self.min_value) / (self.max_value - self.min_value) * self.w - knob_w / 2.0;
        }

        if (self.value_text_data) |*text_data| {
            // have to do it for the backing buffer init
            text_data.recalculateAttributes(self._allocator);
            text_data.text = std.fmt.bufPrint(text_data._backing_buffer, "{d:.2}", .{self._current_value}) catch "-1.00";
            text_data.recalculateAttributes(self._allocator);
        }

        if (self.title_text_data) |*text_data| {
            text_data.vert_align = .middle;
            text_data.hori_align = .middle;
            text_data.max_width = self.w;
            text_data.max_height = self.title_offset;
            text_data.recalculateAttributes(self._allocator);
        }

        if (self.tooltip_text) |*text_data| {
            text_data.recalculateAttributes(self._allocator);
        }
    }

    pub fn setValue(self: *Slider, value: f32) void {
        const prev_value = self._current_value;

        const knob_w = switch (self.knob_image_data.current(self.state)) {
            .nine_slice => |nine_slice| nine_slice.w,
            .normal => |normal| normal.width(),
        };

        const knob_h = switch (self.knob_image_data.current(self.state)) {
            .nine_slice => |nine_slice| nine_slice.h,
            .normal => |normal| normal.height(),
        };

        self._current_value = value;
        if (self.vertical) {
            self._knob_y = (value - self.min_value) / (self.max_value - self.min_value) * (self.h - knob_h);
        } else {
            self._knob_x = (value - self.min_value) / (self.max_value - self.min_value) * (self.w - knob_w);
        }

        if (self._current_value != prev_value) {
            if (self.value_text_data) |*text_data| {
                text_data.text = std.fmt.bufPrint(text_data._backing_buffer, "{d:.2}", .{self._current_value}) catch "-1.00";
                text_data.recalculateAttributes(self._allocator);
            }

            if (self.continous_event_fire)
                self.state_change(self);
        }
    }

    pub fn destroy(self: *Slider) void {
        if (self._disposed)
            return;

        self._disposed = true;

        for (sc.elements.items, 0..) |element, i| {
            if (element == .slider and element.slider == self) {
                _ = sc.elements.swapRemove(i);
                break;
            }
        }

        self.deinit();
        self._allocator.destroy(self);
    }

    pub fn deinit(self: *Slider) void {
        if (self.value_text_data) |*text_data| {
            text_data.deinit(self._allocator);
        }
        if (self.title_text_data) |*text_data| {
            text_data.deinit(self._allocator);
        }
        if (self.tooltip_text) |*text_data| {
            text_data.deinit(self._allocator);
        }
    }
};

pub const UiElement = union(enum) {
    image: *Image,
    item: *Item,
    bar: *Bar,
    input_field: *Input,
    button: *Button,
    text: *Text,
    char_box: *CharacterBox,
    container: *Container,
    scrollable_container: *ScrollableContainer,
    menu_bg: *MenuBackground,
    toggle: *Toggle,
    key_mapper: *KeyMapper,
    slider: *Slider,
};

pub const SpeechBalloon = struct {
    image_data: ImageData,
    text_data: TextData,
    target_id: i32,
    start_time: i64,
    visible: bool = true,
    // the texts' internal x/y, don't touch outside of screen_controller.update()
    _screen_x: f32 = 0.0,
    _screen_y: f32 = 0.0,
    _disposed: bool = false,

    pub fn add(data: SpeechBalloon) !void {
        const should_lock = sc.temp_elements.capacity == 0;
        if (should_lock) {
            while (!sc.temp_elem_lock.tryLock()) {}
        }
        defer if (should_lock) sc.temp_elem_lock.unlock();

        var balloon = Temporary{ .balloon = data };
        balloon.balloon.text_data.recalculateAttributes(main._allocator);
        try sc.temp_elements.append(balloon);
    }

    pub fn width(self: SpeechBalloon) f32 {
        return @max(self.text_data._width, switch (self.image_data) {
            .nine_slice => |nine_slice| return nine_slice.w,
            .normal => |image_data| return image_data.width(),
        });
    }

    pub fn height(self: SpeechBalloon) f32 {
        return @max(self.text_data._height, switch (self.image_data) {
            .nine_slice => |nine_slice| return nine_slice.h,
            .normal => |image_data| return image_data.height(),
        });
    }

    pub fn destroy(self: *SpeechBalloon, allocator: std.mem.Allocator) void {
        if (self._disposed)
            return;

        self._disposed = true;

        while (!self.text_data._lock.tryLock()) {}
        allocator.free(self.text_data.text);
        self.text_data._lock.unlock();

        self.text_data.deinit(allocator);
    }
};

pub const StatusText = struct {
    text_data: TextData,
    initial_size: f32,
    lifetime: i64 = 500,
    start_time: i64 = 0,
    obj_id: i32 = -1,
    visible: bool = true,
    // the texts' internal x/y, don't touch outside of screen_controller.update()
    _screen_x: f32 = 0.0,
    _screen_y: f32 = 0.0,
    _disposed: bool = false,

    pub fn add(data: StatusText) !void {
        const should_lock = sc.temp_elements.capacity == 0;
        if (should_lock) {
            while (!sc.temp_elem_lock.tryLock()) {}
        }
        defer if (should_lock) sc.temp_elem_lock.unlock();

        var status = Temporary{ .status = data };
        status.status.text_data.recalculateAttributes(main._allocator);
        try sc.temp_elements.append(status);
    }

    pub fn width(self: StatusText) f32 {
        return self.text_data._width;
    }

    pub fn height(self: StatusText) f32 {
        return self.text_data._height;
    }

    pub fn destroy(self: *StatusText, allocator: std.mem.Allocator) void {
        if (self._disposed)
            return;

        self._disposed = true;

        while (!self.text_data._lock.tryLock()) {}
        allocator.free(self.text_data.text);
        self.text_data._lock.unlock();

        self.text_data.deinit(allocator);
    }
};

pub const Temporary = union(enum) {
    balloon: SpeechBalloon,
    status: StatusText,
};
