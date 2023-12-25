const std = @import("std");
const camera = @import("../camera.zig");
const assets = @import("../assets.zig");
const main = @import("../main.zig");
const zglfw = @import("zglfw");
const game_data = @import("../game_data.zig");
const settings = @import("../settings.zig");
const sc = @import("controllers/screen_controller.zig");
const tooltip = @import("tooltips/tooltip.zig");
const input = @import("../input.zig");
const utils = @import("../utils.zig");

inline fn createAny(allocator: std.mem.Allocator, data: anytype) !*@TypeOf(data) {
    var elem = try allocator.create(@TypeOf(data));
    elem.* = data;
    elem._allocator = allocator;
    if (std.meta.hasFn(@TypeOf(data), "init")) elem.init();

    comptime var field_name: []const u8 = "";
    comptime {
        for (std.meta.fields(UiElement)) |field| {
            if (@typeInfo(field.type).Pointer.child == @TypeOf(data)) {
                field_name = field.name;
                break;
            }
        }
    }

    if (field_name.len == 0)
        @compileError("Could not find field name");

    const should_lock = sc.elements.capacity == 0;
    if (should_lock) {
        while (!sc.ui_lock.tryLock()) {}
    }
    defer if (should_lock) sc.ui_lock.unlock();
    try sc.elements.append(@unionInit(UiElement, field_name, elem));
    return elem;
}

inline fn destroyAny(self: anytype) void {
    if (self._disposed)
        return;

    self._disposed = true;

    comptime var field_name: []const u8 = "";
    comptime {
        for (std.meta.fields(UiElement)) |field| {
            if (field.type == @TypeOf(self)) {
                field_name = field.name;
                break;
            }
        }
    }

    if (field_name.len == 0)
        @compileError("Could not find field name");

    const tag = std.meta.stringToEnum(std.meta.Tag(UiElement), field_name);
    for (sc.elements.items, 0..) |element, i| {
        if (std.meta.activeTag(element) == tag and @field(element, field_name) == self) {
            _ = sc.elements.swapRemove(i);
            break;
        }
    }

    if (std.meta.hasFn(@typeInfo(@TypeOf(self)).Pointer.child, "deinit")) self.deinit();
    self._allocator.destroy(self);
}

pub const Layer = enum(u8) {
    default = 0,
    dialog = 1,
    tooltip = 2,
};

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

pub const TextType = enum(u8) {
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
    outline_width: f32 = 1.0, // 0.5 for off
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
        const start_line_height = assets.CharacterData.line_height * assets.CharacterData.size * size_scale;
        var line_height = start_line_height;

        var x_max: f32 = 0.0;
        var x_pointer: f32 = 0.0;
        var y_pointer: f32 = line_height;
        var current_size = size_scale;
        var current_type = self.text_type;
        var index_offset: u16 = 0;
        for (0..self.text.len) |i| {
            const offset_i = i + index_offset;
            if (offset_i >= self.text.len) {
                self._width = @max(x_max, x_pointer);
                self._line_widths.?.append(x_pointer) catch |e| {
                    std.log.err("Attribute recalculation for text data failed: {any}", .{e});
                    return;
                };
                self._height = y_pointer;
                return;
            }

            const char = self.text[offset_i];
            specialChar: {
                if (!self.handle_special_chars)
                    break :specialChar;

                if (char == '&') {
                    const name_start = self.text[offset_i + 1 ..];
                    if (std.mem.indexOfScalar(u8, name_start, '=')) |eql_idx| {
                        const value_start_idx = offset_i + 1 + eql_idx + 1;
                        if (self.text.len <= value_start_idx or self.text[value_start_idx] != '"')
                            break :specialChar;

                        const reset = "reset";
                        if (self.text.len > offset_i + 1 + reset.len and std.mem.eql(u8, name_start[0..reset.len], reset)) {
                            current_type = self.text_type;
                            current_size = size_scale;
                            line_height = assets.CharacterData.line_height * assets.CharacterData.size * current_size;
                            y_pointer += line_height - start_line_height;
                            index_offset += @intCast(reset.len);
                            continue;
                        }

                        const value_start = self.text[value_start_idx + 1 ..];
                        if (std.mem.indexOfScalar(u8, value_start, '"')) |value_end_idx| {
                            const name = name_start[0..eql_idx];
                            const value = value_start[0..value_end_idx];
                            if (std.mem.eql(u8, name, "size")) {
                                const size = std.fmt.parseFloat(f32, value) catch {
                                    std.log.err("Invalid size given to control code: {s}", .{value});
                                    break :specialChar;
                                };
                                current_size = size / assets.CharacterData.size * camera.scale * assets.CharacterData.padding_mult;
                                line_height = assets.CharacterData.line_height * assets.CharacterData.size * current_size;
                                y_pointer += line_height - start_line_height;
                            } else if (std.mem.eql(u8, name, "type")) {
                                if (std.mem.eql(u8, value, "med")) {
                                    current_type = .medium;
                                } else if (std.mem.eql(u8, value, "med_it")) {
                                    current_type = .medium_italic;
                                } else if (std.mem.eql(u8, value, "bold")) {
                                    current_type = .bold;
                                } else if (std.mem.eql(u8, value, "bold_it")) {
                                    current_type = .bold_italic;
                                }
                            } else if (std.mem.eql(u8, name, "img")) {
                                var values = std.mem.splitScalar(u8, value, ',');
                                const sheet = values.next();
                                if (sheet == null or std.mem.eql(u8, sheet.?, value)) {
                                    std.log.err("Invalid sheet given to control code: {?s}", .{sheet});
                                    break :specialChar;
                                }

                                const index_str = values.next() orelse {
                                    std.log.err("Index was not found for control code with sheet {s}", .{sheet.?});
                                    break :specialChar;
                                };
                                const index = std.fmt.parseInt(u32, index_str, 0) catch {
                                    std.log.err("Invalid index given to control code with sheet {s}: {s}", .{ sheet.?, index_str });
                                    break :specialChar;
                                };
                                const data = assets.atlas_data.get(sheet.?) orelse {
                                    std.log.err("Sheet {s} given to control code was not found in atlas", .{sheet.?});
                                    break :specialChar;
                                };
                                if (index >= data.len) {
                                    std.log.err("The index {d} given for sheet {s} in control code was out of bounds", .{ index, sheet.? });
                                    break :specialChar;
                                }

                                x_pointer += current_size * assets.CharacterData.size;
                            } else if (!std.mem.eql(u8, name, "col"))
                                break :specialChar;

                            index_offset += @intCast(1 + eql_idx + 1 + value_end_idx + 1);
                            continue;
                        } else break :specialChar;
                    } else break :specialChar;
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

pub const Temporary = union(enum) {
    balloon: SpeechBalloon,
    status: StatusText,
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
    layer: Layer = .default,
    is_chat: bool = false,
    scissor: ScissorRect = .{},
    visible: bool = true,
    // -1 means not selected
    _last_input: i64 = -1,
    _x_offset: f32 = 0.0,
    _index: u32 = 0,
    _disposed: bool = false,
    _allocator: std.mem.Allocator = undefined,

    pub fn mousePress(self: *Input, x: f32, y: f32, _: f32, _: f32, _: zglfw.Mods) bool {
        if (!self.visible)
            return false;

        if (utils.isInBounds(x, y, self.x, self.y, self.width(), self.height())) {
            input.selected_input_field = self;
            self._last_input = 0;
            self.state = .pressed;
            return true;
        }

        return false;
    }

    pub fn mouseRelease(self: *Input, x: f32, y: f32, _: f32, _: f32) void {
        if (!self.visible)
            return;

        if (utils.isInBounds(x, y, self.x, self.y, self.width(), self.height())) {
            self.state = .none;
        }
    }

    pub fn mouseMove(self: *Input, x: f32, y: f32, _: f32, _: f32) void {
        if (!self.visible)
            return;

        if (utils.isInBounds(x, y, self.x, self.y, self.width(), self.height())) {
            self.state = .hovered;
        } else {
            self.state = .none;
        }
    }

    pub fn init(self: *Input) void {
        if (self.text_data.scissor.isDefault()) {
            self.text_data.scissor = .{
                .min_x = 0,
                .min_y = 0,
                .max_x = self.width() - self.text_inlay_x * 2,
                .max_y = self.height() - self.text_inlay_y * 2,
            };
        }

        self.text_data.recalculateAttributes(self._allocator);

        switch (self.cursor_image_data) {
            .nine_slice => |*nine_slice| nine_slice.h = self.text_data._height,
            .normal => |*image_data| image_data.scale_y = self.text_data._height / image_data.height(),
        }
    }

    pub fn deinit(self: *Input) void {
        if (self == input.selected_input_field)
            input.selected_input_field = null;

        self.text_data.deinit(self._allocator);
    }

    pub fn width(self: Input) f32 {
        return @max(self.text_data._width, switch (self.image_data.current(self.state)) {
            .nine_slice => |nine_slice| return nine_slice.w,
            .normal => |image_data| return image_data.width(),
        });
    }

    pub fn height(self: Input) f32 {
        return @max(self.text_data._height, switch (self.image_data.current(self.state)) {
            .nine_slice => |nine_slice| return nine_slice.h,
            .normal => |image_data| return image_data.height(),
        });
    }

    pub fn create(allocator: std.mem.Allocator, data: Input) !*Input {
        return try createAny(allocator, data);
    }

    pub fn destroy(self: *Input) void {
        destroyAny(self);
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

        const img_width = switch (self.image_data.current(self.state)) {
            .nine_slice => |nine_slice| nine_slice.w,
            .normal => |image_data| image_data.width(),
        } - self.text_inlay_x * 2 - cursor_width;
        const offset = @max(0, self.text_data._width - img_width);
        self._x_offset = -offset;
        self.text_data.scissor.min_x = offset;
        self.text_data.scissor.max_x = offset + img_width;
    }
};

pub const Button = struct {
    x: f32,
    y: f32,
    press_callback: *const fn () void,
    image_data: InteractableImageData,
    state: InteractableState = .none,
    layer: Layer = .default,
    text_data: ?TextData = null,
    scissor: ScissorRect = .{},
    visible: bool = true,
    _disposed: bool = false,
    _allocator: std.mem.Allocator = undefined,

    pub fn mousePress(self: *Button, x: f32, y: f32, _: f32, _: f32, _: zglfw.Mods) bool {
        if (!self.visible)
            return false;

        if (utils.isInBounds(x, y, self.x, self.y, self.width(), self.height())) {
            self.state = .pressed;
            self.press_callback();
            assets.playSfx("button_click");
            return true;
        }

        return false;
    }

    pub fn mouseRelease(self: *Button, x: f32, y: f32, _: f32, _: f32) void {
        if (!self.visible)
            return;

        if (utils.isInBounds(x, y, self.x, self.y, self.width(), self.height())) {
            self.state = .none;
        }
    }

    pub fn mouseMove(self: *Button, x: f32, y: f32, _: f32, _: f32) void {
        if (!self.visible)
            return;

        if (utils.isInBounds(x, y, self.x, self.y, self.width(), self.height())) {
            self.state = .hovered;
        } else {
            self.state = .none;
        }
    }

    pub fn init(self: *Button) void {
        if (self.text_data) |*text_data| {
            text_data.recalculateAttributes(self._allocator);
        }
    }

    pub fn deinit(self: *Button) void {
        if (self.text_data) |*text_data| {
            text_data.deinit(self._allocator);
        }
    }

    pub fn width(self: Button) f32 {
        if (self.text_data) |text| {
            return @max(text._width, switch (self.image_data.current(self.state)) {
                .nine_slice => |nine_slice| return nine_slice.w,
                .normal => |image_data| return image_data.width(),
            });
        } else {
            return switch (self.image_data.current(self.state)) {
                .nine_slice => |nine_slice| return nine_slice.w,
                .normal => |image_data| return image_data.width(),
            };
        }
    }

    pub fn height(self: Button) f32 {
        if (self.text_data) |text| {
            return @max(text._height, switch (self.image_data.current(self.state)) {
                .nine_slice => |nine_slice| return nine_slice.h,
                .normal => |image_data| return image_data.height(),
            });
        } else {
            return switch (self.image_data.current(self.state)) {
                .nine_slice => |nine_slice| return nine_slice.h,
                .normal => |image_data| return image_data.height(),
            };
        }
    }

    pub fn create(allocator: std.mem.Allocator, data: Button) !*Button {
        return try createAny(allocator, data);
    }

    pub fn destroy(self: *Button) void {
        destroyAny(self);
    }
};

pub const KeyMapper = struct {
    x: f32,
    y: f32,
    set_key_callback: *const fn (*KeyMapper) void,
    image_data: InteractableImageData,
    settings_button: *settings.Button,
    key: zglfw.Key = .unknown,
    mouse: zglfw.MouseButton = .unknown,
    title_text_data: ?TextData = null,
    tooltip_text: ?TextData = null,
    state: InteractableState = .none,
    layer: Layer = .default,
    scissor: ScissorRect = .{},
    visible: bool = true,
    listening: bool = false,
    _disposed: bool = false,
    _allocator: std.mem.Allocator = undefined,

    pub fn mousePress(self: *KeyMapper, x: f32, y: f32, _: f32, _: f32, _: zglfw.Mods) bool {
        if (!self.visible)
            return false;

        if (utils.isInBounds(x, y, self.x, self.y, self.width(), self.height())) {
            self.state = .pressed;

            if (input.selected_key_mapper == null) {
                self.listening = true;
                input.selected_key_mapper = self;
            }

            assets.playSfx("button_click");
            return true;
        }

        return false;
    }

    pub fn mouseRelease(self: *KeyMapper, x: f32, y: f32, _: f32, _: f32) void {
        if (!self.visible)
            return;

        if (utils.isInBounds(x, y, self.x, self.y, self.width(), self.height())) {
            self.state = .none;
        }
    }

    pub fn mouseMove(self: *KeyMapper, x: f32, y: f32, x_offset: f32, y_offset: f32) void {
        if (!self.visible)
            return;

        if (utils.isInBounds(x, y, self.x, self.y, self.width(), self.height())) {
            if (self.tooltip_text) |text_data| {
                tooltip.switchTooltip(.text);
                tooltip.current_tooltip.text.update(x + x_offset, y + y_offset, text_data);
            }

            self.state = .hovered;
        } else {
            self.state = .none;
        }
    }

    pub fn init(self: *KeyMapper) void {
        if (self.title_text_data) |*text_data| {
            text_data.recalculateAttributes(self._allocator);
        }
        if (self.tooltip_text) |*text_data| {
            text_data.recalculateAttributes(self._allocator);
        }
    }

    pub fn deinit(self: *KeyMapper) void {
        if (self.title_text_data) |*text_data| {
            text_data.deinit(self._allocator);
        }
        if (self.tooltip_text) |*text_data| {
            text_data.deinit(self._allocator);
        }
    }

    pub fn width(self: KeyMapper) f32 {
        const extra = if (self.title_text_data) |t| t._width else 0;
        return switch (self.image_data.current(self.state)) {
            .nine_slice => |nine_slice| return nine_slice.w + extra,
            .normal => |image_data| return image_data.width() + extra,
        };
    }

    pub fn height(self: KeyMapper) f32 {
        return switch (self.image_data.current(self.state)) {
            .nine_slice => |nine_slice| return nine_slice.h,
            .normal => |image_data| return image_data.height(),
        };
    }

    pub fn create(allocator: std.mem.Allocator, data: KeyMapper) !*KeyMapper {
        return try createAny(allocator, data);
    }

    pub fn destroy(self: *KeyMapper) void {
        destroyAny(self);
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
    layer: Layer = .default,
    text_data: ?TextData = null,
    scissor: ScissorRect = .{},
    visible: bool = true,
    _disposed: bool = false,
    _allocator: std.mem.Allocator = undefined,

    pub fn mousePress(self: *CharacterBox, x: f32, y: f32, _: f32, _: f32, _: zglfw.Mods) bool {
        if (!self.visible)
            return false;

        if (utils.isInBounds(x, y, self.x, self.y, self.width(), self.height())) {
            self.state = .pressed;
            self.press_callback(self);
            assets.playSfx("button_click");
            return true;
        }

        return false;
    }

    pub fn mouseRelease(self: *CharacterBox, x: f32, y: f32, _: f32, _: f32) void {
        if (!self.visible)
            return;

        if (utils.isInBounds(x, y, self.x, self.y, self.width(), self.height())) {
            self.state = .none;
        }
    }

    pub fn mouseMove(self: *CharacterBox, x: f32, y: f32, _: f32, _: f32) void {
        if (!self.visible)
            return;

        if (utils.isInBounds(x, y, self.x, self.y, self.width(), self.height())) {
            self.state = .hovered;
        } else {
            self.state = .none;
        }
    }

    pub fn init(self: *CharacterBox) void {
        if (self.text_data) |*text_data| {
            text_data.recalculateAttributes(self._allocator);
        }
    }

    pub fn deinit(self: *CharacterBox) void {
        if (self.text_data) |*text_data| {
            text_data.deinit(self._allocator);
        }
    }

    pub fn width(self: CharacterBox) f32 {
        if (self.text_data) |text| {
            return @max(text._width, switch (self.image_data.current(self.state)) {
                .nine_slice => |nine_slice| return nine_slice.w,
                .normal => |image_data| return image_data.width(),
            });
        } else {
            return switch (self.image_data.current(self.state)) {
                .nine_slice => |nine_slice| return nine_slice.w,
                .normal => |image_data| return image_data.width(),
            };
        }
    }

    pub fn height(self: CharacterBox) f32 {
        if (self.text_data) |text| {
            return @max(text._height, switch (self.image_data.current(self.state)) {
                .nine_slice => |nine_slice| return nine_slice.h,
                .normal => |image_data| return image_data.height(),
            });
        } else {
            return switch (self.image_data.current(self.state)) {
                .nine_slice => |nine_slice| return nine_slice.h,
                .normal => |image_data| return image_data.height(),
            };
        }
    }

    pub fn create(allocator: std.mem.Allocator, data: CharacterBox) !*CharacterBox {
        return try createAny(allocator, data);
    }

    pub fn destroy(self: *CharacterBox) void {
        destroyAny(self);
    }
};

pub const Image = struct {
    x: f32,
    y: f32,
    image_data: ImageData,
    layer: Layer = .default,
    scissor: ScissorRect = .{},
    ui_quad: bool = true,
    visible: bool = true,
    // hack
    is_minimap_decor: bool = false,
    ability_props: ?game_data.Ability = null,
    minimap_offset_x: f32 = 0.0,
    minimap_offset_y: f32 = 0.0,
    minimap_width: f32 = 0.0,
    minimap_height: f32 = 0.0,
    _disposed: bool = false,
    _allocator: std.mem.Allocator = undefined,

    pub fn mouseMove(self: *Image, x: f32, y: f32, x_offset: f32, y_offset: f32) void {
        if (!self.visible)
            return;

        if (self.ability_props != null and utils.isInBounds(x, y, self.x, self.y, self.width(), self.height())) {
            tooltip.switchTooltip(.ability);
            tooltip.current_tooltip.ability.update(x + x_offset, y + y_offset, self.ability_props.?);
        }
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

    pub fn create(allocator: std.mem.Allocator, data: Image) !*Image {
        return try createAny(allocator, data);
    }

    pub fn destroy(self: *Image) void {
        destroyAny(self);
    }
};

pub const MenuBackground = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    layer: Layer = .default,
    scissor: ScissorRect = .{},
    visible: bool = true,
    _disposed: bool = false,
    _allocator: std.mem.Allocator = undefined,

    pub fn width(_: MenuBackground) f32 {
        return @floatFromInt(assets.menu_background.width);
    }

    pub fn height(_: MenuBackground) f32 {
        return @floatFromInt(assets.menu_background.height);
    }

    pub fn create(allocator: std.mem.Allocator, data: MenuBackground) !*MenuBackground {
        return try createAny(allocator, data);
    }

    pub fn destroy(self: *MenuBackground) void {
        destroyAny(self);
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
    layer: Layer = .default,
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

    pub fn mousePress(self: *Item, x: f32, y: f32, _: f32, _: f32, mods: zglfw.Mods) bool {
        if (!self.visible or !self.draggable)
            return false;

        if (utils.isInBounds(x, y, self.x, self.y, self.width(), self.height())) {
            if (mods.shift) {
                self.shift_click_callback(self);
                return true;
            }

            if (self._last_click_time + 333 * std.time.us_per_ms > main.current_time) {
                self.double_click_callback(self);
                return true;
            }

            self._is_dragging = true;
            self._drag_start_x = self.x;
            self._drag_start_y = self.y;
            self._drag_offset_x = self.x - x;
            self._drag_offset_y = self.y - y;
            self._last_click_time = main.current_time;
            self.drag_start_callback(self);
            return true;
        }

        return false;
    }

    pub fn mouseRelease(self: *Item, _: f32, _: f32, _: f32, _: f32) void {
        if (!self._is_dragging)
            return;

        self._is_dragging = false;
        self.drag_end_callback(self);
    }

    pub fn mouseMove(self: *Item, x: f32, y: f32, x_offset: f32, y_offset: f32) void {
        if (!self.visible)
            return;

        if (utils.isInBounds(x, y, self.x, self.y, self.width(), self.height())) {
            tooltip.switchTooltip(.item);
            tooltip.current_tooltip.item.update(x + x_offset, y + y_offset, self._item);
        }

        if (!self._is_dragging)
            return;

        self.x = x + self._drag_offset_x;
        self.y = y + self._drag_offset_y;
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

    pub fn create(allocator: std.mem.Allocator, data: Item) !*Item {
        return try createAny(allocator, data);
    }

    pub fn destroy(self: *Item) void {
        destroyAny(self);
    }
};

pub const Bar = struct {
    x: f32,
    y: f32,
    image_data: ImageData,
    layer: Layer = .default,
    scissor: ScissorRect = .{},
    visible: bool = true,
    text_data: TextData,
    _disposed: bool = false,
    _allocator: std.mem.Allocator = undefined,

    pub fn init(self: *Bar) void {
        self.text_data.recalculateAttributes(self._allocator);
    }

    pub fn deinit(self: *Bar) void {
        self.text_data.deinit(self._allocator);
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

    pub fn create(allocator: std.mem.Allocator, data: Bar) !*Bar {
        return try createAny(allocator, data);
    }

    pub fn destroy(self: *Bar) void {
        destroyAny(self);
    }
};

pub const Text = struct {
    x: f32,
    y: f32,
    text_data: TextData,
    layer: Layer = .default,
    scissor: ScissorRect = .{},
    visible: bool = true,
    _disposed: bool = false,
    _allocator: std.mem.Allocator = undefined,

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

    pub fn create(allocator: std.mem.Allocator, data: Text) !*Text {
        return try createAny(allocator, data);
    }

    pub fn destroy(self: *Text) void {
        destroyAny(self);
    }
};

pub const ScrollableContainer = struct {
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
    layer: Layer = .default,

    visible: bool = true,
    base_y: f32 = 0.0,
    _container: *Container = undefined,
    _scroll_bar: *Slider = undefined,
    _disposed: bool = false,
    _allocator: std.mem.Allocator = undefined,

    pub fn mousePress(self: *ScrollableContainer, x: f32, y: f32, x_offset: f32, y_offset: f32, mods: zglfw.Mods) bool {
        if (!self.visible)
            return false;

        var container = self._container;
        if (container.mousePress(x - container.x, y - container.y, container.x + x_offset, container.y + y_offset, mods) or
            self._scroll_bar.mousePress(x, y, x_offset, y_offset, mods))
            return true;

        return false;
    }

    pub fn mouseRelease(self: *ScrollableContainer, x: f32, y: f32, x_offset: f32, y_offset: f32) void {
        if (!self.visible)
            return;

        var container = self._container;
        container.mouseRelease(x - container.x, y - container.y, container.x + x_offset, container.y + y_offset);
        self._scroll_bar.mouseRelease(x, y, x_offset, y_offset);
    }

    pub fn mouseMove(self: *ScrollableContainer, x: f32, y: f32, x_offset: f32, y_offset: f32) void {
        if (!self.visible)
            return;

        var container = self._container;
        container.mouseMove(x - container.x, y - container.y, container.x + x_offset, container.y + y_offset);
        self._scroll_bar.mouseMove(x, y, x_offset, y_offset);
    }

    pub fn mouseScroll(self: *ScrollableContainer, x: f32, y: f32, _: f32, _: f32, _: f32, y_scroll: f32) bool {
        if (!self.visible)
            return false;

        const container = self._container;
        if (utils.isInBounds(x, y, container.x, container.y, self.width(), self.height())) {
            const scroll_bar = self._scroll_bar;
            self._scroll_bar.setValue(
                @min(
                    scroll_bar.max_value,
                    @max(
                        scroll_bar.min_value,
                        scroll_bar._current_value + (scroll_bar.max_value - scroll_bar.min_value) * -y_scroll / 64.0,
                    ),
                ),
            );
            return true;
        }

        return false;
    }

    pub fn init(self: *ScrollableContainer) void {
        self.base_y = self.y;

        self._container = self._allocator.create(Container) catch @panic("ScrollableContainer child container alloc failed");
        self._container.* = .{ .x = self.x, .y = self.y, .scissor = .{
            .min_x = 0,
            .min_y = 0,
            .max_x = self.scissor_w,
            .max_y = self.scissor_h,
        } };
        self._container._allocator = self._allocator;
        self._container.init();

        self._scroll_bar = self._allocator.create(Slider) catch @panic("ScrollableContainer scroll bar alloc failed");
        self._scroll_bar.* = .{
            .x = self.scroll_x,
            .y = self.scroll_y,
            .w = self.scroll_w,
            .h = self.scroll_h,
            .decor_image_data = self.scroll_decor_image_data,
            .knob_image_data = self.scroll_knob_image_data,
            .min_value = 0.0,
            .max_value = 1.0,
            .continous_event_fire = true,
            .state_change = onScrollChanged,
            .vertical = true,
            .visible = false,
            ._parent_container = self,
            ._current_value = 1.0,
        };
        self._scroll_bar._allocator = self._allocator;
        self._scroll_bar.init();
    }

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

    pub fn create(allocator: std.mem.Allocator, data: ScrollableContainer) !*ScrollableContainer {
        return try createAny(allocator, data);
    }

    pub fn destroy(self: *ScrollableContainer) void {
        destroyAny(self);
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
};

pub const Container = struct {
    x: f32,
    y: f32,
    scissor: ScissorRect = .{},
    visible: bool = true,
    draggable: bool = false,
    layer: Layer = .default,

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

    pub fn mousePress(self: *Container, x: f32, y: f32, x_offset: f32, y_offset: f32, mods: zglfw.Mods) bool {
        if (!self.visible)
            return false;

        var iter = std.mem.reverseIterator(self._elements.items);
        while (iter.next()) |elem| {
            switch (elem) {
                inline else => |inner_elem| {
                    if (std.meta.hasFn(@typeInfo(@TypeOf(inner_elem)).Pointer.child, "mousePress") and
                        inner_elem.mousePress(x - self.x, y - self.y, self.x + x_offset, self.y + y_offset, mods))
                        return true;
                },
            }
        }

        if (self.draggable and utils.isInBounds(x, y, self.x, self.y, self.width(), self.height())) {
            self._is_dragging = true;
            self._drag_start_x = self.x;
            self._drag_start_y = self.y;
            self._drag_offset_x = self.x - x;
            self._drag_offset_y = self.y - y;
        }

        return false;
    }

    pub fn mouseRelease(self: *Container, x: f32, y: f32, x_offset: f32, y_offset: f32) void {
        if (!self.visible)
            return;

        if (self._is_dragging)
            self._is_dragging = false;

        var iter = std.mem.reverseIterator(self._elements.items);
        while (iter.next()) |elem| {
            switch (elem) {
                inline else => |inner_elem| {
                    if (std.meta.hasFn(@typeInfo(@TypeOf(inner_elem)).Pointer.child, "mouseRelease"))
                        inner_elem.mouseRelease(x - self.x, y - self.y, self.x + x_offset, self.y + y_offset);
                },
            }
        }
    }

    pub fn mouseMove(self: *Container, x: f32, y: f32, x_offset: f32, y_offset: f32) void {
        if (!self.visible)
            return;

        if (self._is_dragging) {
            if (!self._clamp_x) {
                self.x = x + self._drag_offset_x;
                if (self._clamp_to_screen) {
                    if (self.x > 0)
                        self.x = 0;

                    const bottom_x = self.x + self.width();
                    if (bottom_x < camera.screen_width)
                        self.x = self.width();
                }
            }
            if (!self._clamp_y) {
                self.y = y + self._drag_offset_y;
                if (self._clamp_to_screen) {
                    if (self.y > 0)
                        self.y = 0;

                    const bottom_y = self.y + self.height();
                    if (bottom_y < camera.screen_height)
                        self.y = bottom_y;
                }
            }
        }

        var iter = std.mem.reverseIterator(self._elements.items);
        while (iter.next()) |elem| {
            switch (elem) {
                inline else => |inner_elem| {
                    if (std.meta.hasFn(@typeInfo(@TypeOf(inner_elem)).Pointer.child, "mouseMove"))
                        inner_elem.mouseMove(x - self.x, y - self.y, self.x + x_offset, self.y + y_offset);
                },
            }
        }
    }

    pub fn mouseScroll(self: *Container, x: f32, y: f32, x_offset: f32, y_offset: f32, x_scroll: f32, y_scroll: f32) bool {
        if (!self.visible)
            return false;

        var iter = std.mem.reverseIterator(self._elements.items);
        while (iter.next()) |elem| {
            switch (elem) {
                inline else => |inner_elem| {
                    if (std.meta.hasFn(@typeInfo(@TypeOf(inner_elem)).Pointer.child, "mouseScroll") and
                        inner_elem.mouseScroll(x - self.x, y - self.y, self.x + x_offset, self.y + y_offset, x_scroll, y_scroll))
                        return true;
                },
            }
        }

        return false;
    }

    pub fn init(self: *Container) void {
        self._elements = std.ArrayList(UiElement).initCapacity(self._allocator, 8) catch @panic("Container element buffer alloc failed");
    }

    pub fn deinit(self: *Container) void {
        for (self._elements.items) |*elem| {
            switch (elem.*) {
                inline else => |inner_elem| {
                    if (std.meta.hasFn(@typeInfo(@TypeOf(inner_elem)).Pointer.child, "deinit")) inner_elem.deinit();
                    self._allocator.destroy(inner_elem);
                },
            }
        }
        self._elements.deinit();
    }

    pub fn width(self: Container) f32 {
        if (self._elements.items.len <= 0)
            return 0.0;

        var min_x: f32 = std.math.floatMax(f32);
        var max_x: f32 = std.math.floatMin(f32);
        for (self._elements.items) |elem| {
            switch (elem) {
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

    pub fn create(allocator: std.mem.Allocator, data: Container) !*Container {
        return try createAny(allocator, data);
    }

    pub fn destroy(self: *Container) void {
        destroyAny(self);
    }

    pub fn createElement(self: *Container, comptime T: type, data: T) !*T {
        var elem = try self._allocator.create(T);
        elem.* = data;
        elem._allocator = self._allocator;
        if (std.meta.hasFn(T, "init")) elem.init();
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

        comptime var field_name: []const u8 = "";
        comptime {
            for (std.meta.fields(UiElement)) |field| {
                if (@typeInfo(field.type).Pointer.child == T) {
                    field_name = field.name;
                    break;
                }
            }
        }

        if (field_name.len == 0)
            @compileError("Could not find field name");

        try self._elements.append(@unionInit(UiElement, field_name, elem));
        return elem;
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
};

pub const Toggle = struct {
    x: f32,
    y: f32,
    toggled: *bool,
    off_image_data: InteractableImageData,
    on_image_data: InteractableImageData,
    scissor: ScissorRect = .{},
    state: InteractableState = .none,
    layer: Layer = .default,
    text_data: ?TextData = null,
    tooltip_text: ?TextData = null,
    state_change: ?*const fn (*Toggle) void = null,
    visible: bool = true,
    _disposed: bool = false,
    _allocator: std.mem.Allocator = undefined,

    pub fn mousePress(self: *Toggle, x: f32, y: f32, _: f32, _: f32, _: zglfw.Mods) bool {
        if (!self.visible)
            return false;

        if (utils.isInBounds(x, y, self.x, self.y, self.width(), self.height())) {
            self.state = .pressed;
            self.toggled.* = !self.toggled.*;
            if (self.state_change) |callback| {
                callback(self);
            }
            assets.playSfx("button_click");
            return true;
        }

        return false;
    }

    pub fn mouseRelease(self: *Toggle, x: f32, y: f32, _: f32, _: f32) void {
        if (!self.visible)
            return;

        if (utils.isInBounds(x, y, self.x, self.y, self.width(), self.height())) {
            self.state = .none;
        }
    }

    pub fn mouseMove(self: *Toggle, x: f32, y: f32, x_offset: f32, y_offset: f32) void {
        if (!self.visible)
            return;

        if (utils.isInBounds(x, y, self.x, self.y, self.width(), self.height())) {
            if (self.tooltip_text) |text_data| {
                tooltip.switchTooltip(.text);
                tooltip.current_tooltip.text.update(x + x_offset, y + y_offset, text_data);
            }

            self.state = .hovered;
        } else {
            self.state = .none;
        }
    }

    pub fn init(self: *Toggle) void {
        if (self.text_data) |*text_data| {
            text_data.recalculateAttributes(self._allocator);
        }
        if (self.tooltip_text) |*text_data| {
            text_data.recalculateAttributes(self._allocator);
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

    pub fn width(self: Toggle) f32 {
        switch (if (self.toggled.*)
            self.on_image_data.current(self.state)
        else
            self.off_image_data.current(self.state)) {
            .nine_slice => |nine_slice| return nine_slice.w,
            .normal => |image_data| return image_data.width(),
        }
    }

    pub fn height(self: Toggle) f32 {
        switch (if (self.toggled.*)
            self.on_image_data.current(self.state)
        else
            self.off_image_data.current(self.state)) {
            .nine_slice => |nine_slice| return nine_slice.h,
            .normal => |image_data| return image_data.height(),
        }
    }

    pub fn create(allocator: std.mem.Allocator, data: Toggle) !*Toggle {
        return try createAny(allocator, data);
    }

    pub fn destroy(self: *Toggle) void {
        destroyAny(self);
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
    layer: Layer = .default,
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

    pub fn mousePress(self: *Slider, x: f32, y: f32, _: f32, _: f32, _: zglfw.Mods) bool {
        if (!self.visible)
            return false;

        if (utils.isInBounds(x, y, self.x, self.y, self.w, self.h)) {
            const knob_w = switch (self.knob_image_data.current(self.state)) {
                .nine_slice => |nine_slice| nine_slice.w,
                .normal => |normal| normal.width(),
            };

            const knob_h = switch (self.knob_image_data.current(self.state)) {
                .nine_slice => |nine_slice| nine_slice.h,
                .normal => |normal| normal.height(),
            };

            self.pressed(x, y, knob_h, knob_w);
        }

        return false;
    }

    pub fn mouseRelease(self: *Slider, x: f32, y: f32, _: f32, _: f32) void {
        if (!self.visible)
            return;

        if (self.state == .pressed) {
            const knob_w = switch (self.knob_image_data.current(self.state)) {
                .nine_slice => |nine_slice| nine_slice.w,
                .normal => |normal| normal.width(),
            };

            const knob_h = switch (self.knob_image_data.current(self.state)) {
                .nine_slice => |nine_slice| nine_slice.h,
                .normal => |normal| normal.height(),
            };

            if (utils.isInBounds(x, y, self._knob_x, self._knob_y, knob_w, knob_h)) {
                self.state = .hovered;
            } else {
                self.state = .none;
            }
            self.state_change(self);
        }
    }

    pub fn mouseMove(self: *Slider, x: f32, y: f32, x_offset: f32, y_offset: f32) void {
        if (!self.visible)
            return;

        const knob_w = switch (self.knob_image_data.current(self.state)) {
            .nine_slice => |nine_slice| nine_slice.w,
            .normal => |normal| normal.width(),
        };

        const knob_h = switch (self.knob_image_data.current(self.state)) {
            .nine_slice => |nine_slice| nine_slice.h,
            .normal => |normal| normal.height(),
        };

        if (utils.isInBounds(x, y, self.x, self.y, self.width(), self.height())) {
            if (self.tooltip_text) |text_data| {
                tooltip.switchTooltip(.text);
                tooltip.current_tooltip.text.update(x + x_offset, y + y_offset, text_data);
            }
        }

        if (self.state == .pressed) {
            self.pressed(x, y, knob_h, knob_w);
        } else if (utils.isInBounds(x, y, self.x + self._knob_x, self.y + self._knob_y, knob_w, knob_h)) {
            self.state = .hovered;
        } else if (self.state == .hovered) {
            self.state = .none;
        }
    }

    pub fn mouseScroll(self: *Slider, x: f32, y: f32, _: f32, _: f32, _: f32, y_scroll: f32) bool {
        if (utils.isInBounds(x, y, self.x, self.y, self.width(), self.height())) {
            self.setValue(
                @min(
                    self.max_value,
                    @max(
                        self.min_value,
                        self._current_value + (self.max_value - self.min_value) * -y_scroll / 64.0,
                    ),
                ),
            );
            return true;
        }

        return false;
    }

    pub fn init(self: *Slider) void {
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

    pub fn create(allocator: std.mem.Allocator, data: Slider) !*Slider {
        return try createAny(allocator, data);
    }

    pub fn destroy(self: *Slider) void {
        destroyAny(self);
    }

    fn pressed(self: *Slider, x: f32, y: f32, knob_h: f32, knob_w: f32) void {
        const prev_value = self._current_value;

        if (self.vertical) {
            self._knob_y = @min(self.h - knob_h, @max(0, y - knob_h - self.y));
            self._current_value = self._knob_y / (self.h - knob_h) * (self.max_value - self.min_value) + self.min_value;
        } else {
            self._knob_x = @min(self.w - knob_w, @max(0, x - knob_w - self.x));
            self._current_value = self._knob_x / (self.w - knob_w) * (self.max_value - self.min_value) + self.min_value;
        }

        if (self._current_value != prev_value) {
            if (self.value_text_data) |*text_data| {
                text_data.text = std.fmt.bufPrint(text_data._backing_buffer, "{d:.2}", .{self._current_value}) catch "-1.00";
                text_data.recalculateAttributes(self._allocator);
            }

            if (self.continous_event_fire)
                self.state_change(self);
        }

        self.state = .pressed;
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
};

pub const SpeechBalloon = struct {
    image_data: ImageData,
    text_data: TextData,
    target_id: i32,
    start_time: i64 = 0,
    visible: bool = true,
    // the texts' internal x/y, don't touch outside of screen_controller.update()
    _screen_x: f32 = 0.0,
    _screen_y: f32 = 0.0,
    _disposed: bool = false,

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

    pub fn add(data: SpeechBalloon) !void {
        var balloon = Temporary{ .balloon = data };
        balloon.balloon.start_time = main.current_time;
        balloon.balloon.text_data.recalculateAttributes(main._allocator);

        while (!sc.temp_elem_lock.tryLock()) {}
        defer sc.temp_elem_lock.unlock();
        try sc.temp_elements.append(balloon);
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
    delay: i64 = 0,
    obj_id: i32 = -1,
    visible: bool = true,
    // the texts' internal x/y, don't touch outside of screen_controller.update()
    _screen_x: f32 = 0.0,
    _screen_y: f32 = 0.0,
    _disposed: bool = false,

    pub fn width(self: StatusText) f32 {
        return self.text_data._width;
    }

    pub fn height(self: StatusText) f32 {
        return self.text_data._height;
    }

    pub fn add(data: StatusText) !void {
        var status = Temporary{ .status = data };
        status.status.start_time = main.current_time + data.delay;
        status.status.text_data.recalculateAttributes(main._allocator);

        while (!sc.temp_elem_lock.tryLock()) {}
        defer sc.temp_elem_lock.unlock();
        try sc.temp_elements.append(status);
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
