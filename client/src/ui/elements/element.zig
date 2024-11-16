const std = @import("std");
const utils = @import("shared").utils;
const assets = @import("../../assets.zig");
const systems = @import("../systems.zig");
const render = @import("../../render.zig");
const main = @import("../../main.zig");

const Settings = @import("../../Settings.zig");
const Bar = @import("Bar.zig");
const Button = @import("Button.zig");
const CharacterBox = @import("CharacterBox.zig");
const Container = @import("Container.zig");
const Dropdown = @import("Dropdown.zig");
const DropdownContainer = @import("DropdownContainer.zig");
const Image = @import("Image.zig");
const Input = @import("Input.zig");
const Item = @import("Item.zig");
const KeyMapper = @import("KeyMapper.zig");
const MenuBackground = @import("MenuBackground.zig");
const ScrollableContainer = @import("ScrollableContainer.zig");
const Slider = @import("Slider.zig");
const Text = @import("Text.zig");
const Toggle = @import("Toggle.zig");

pub const UiElement = union(enum) {
    bar: *Bar,
    button: *Button,
    char_box: *CharacterBox,
    container: *Container,
    dropdown: *Dropdown,
    // don't actually use this here. internal use only
    dropdown_container: *DropdownContainer,
    image: *Image,
    input_field: *Input,
    item: *Item,
    key_mapper: *KeyMapper,
    menu_bg: *MenuBackground,
    scrollable_container: *ScrollableContainer,
    slider: *Slider,
    text: *Text,
    toggle: *Toggle,

    pub fn draw(self: UiElement, cam_data: render.CameraData, x_offset: f32, y_offset: f32, time: i64) void {
        switch (self) {
            inline else => |elem| elem.draw(cam_data, x_offset, y_offset, time),
        }
    }
};

pub const ElementBase = struct {
    x: f32,
    y: f32,
    layer: Layer = .default,
    scissor: ScissorRect = .{},
    visible: bool = true,
    event_policy: EventPolicy = .{},
};

pub const Layer = enum {
    default,
    dialog,
    tooltip,
};

pub const EventPolicy = packed struct {
    pass_press: bool = false,
    pass_release: bool = false,
    pass_move: bool = false,
    pass_scroll: bool = false,
};

// Renderer reuses this for extern structs, the explicit u32 is needed
pub const TextType = enum(u32) {
    medium = 0,
    medium_italic = 1,
    bold = 2,
    bold_italic = 3,
};

pub const AlignHori = enum {
    left,
    middle,
    right,
};

pub const AlignVert = enum {
    top,
    middle,
    bottom,
};

pub const TextData = struct {
    text: []const u8,
    size: f32,
    // 0 implies that the backing buffer won't be used. if your element uses it, you must set this to something above 0
    max_chars: u32 = 0,
    text_type: TextType = .medium,
    color: u32 = 0xFFFFFF,
    alpha: f32 = 1.0,
    shadow_color: u32 = 0x000000,
    shadow_alpha_mult: f32 = 0.5,
    shadow_texel_offset_mult: f32 = 0.0,
    outline_color: u32 = 0x000000,
    outline_width: f32 = 0.7,
    password: bool = false,
    handle_special_chars: bool = true,
    scissor: ScissorRect = .{},
    // alignments other than default need max width/height defined respectively
    hori_align: AlignHori = .left,
    vert_align: AlignVert = .top,
    max_width: f32 = std.math.floatMax(f32),
    max_height: f32 = std.math.floatMax(f32),
    backing_buffer: []u8 = &.{},
    lock: std.Thread.Mutex = .{},
    width: f32 = 0.0,
    height: f32 = 0.0,
    line_count: f32 = 0.0,
    sort_extra: f32 = 0.0,
    line_widths: ?std.ArrayListUnmanaged(f32) = null,
    break_indices: ?std.AutoHashMapUnmanaged(usize, void) = null,

    pub fn setText(self: *TextData, text: []const u8) void {
        self.lock.lock();
        defer self.lock.unlock();
        self.text = text;
        self.recalculateAttributes();
    }

    pub fn recalculateAttributes(self: *TextData) void {
        std.debug.assert(!self.lock.tryLock());

        if (self.backing_buffer.len == 0 and self.max_chars > 0) self.backing_buffer = main.allocator.alloc(u8, self.max_chars) catch @panic("OOM");
        if (self.line_widths) |*line_widths| line_widths.clearRetainingCapacity() else self.line_widths = .empty;
        if (self.break_indices) |*break_indices| break_indices.clearRetainingCapacity() else self.break_indices = .empty;

        var current_type = self.text_type;
        var current_font_data = switch (current_type) {
            .medium => assets.medium_data,
            .medium_italic => assets.medium_italic_data,
            .bold => assets.bold_data,
            .bold_italic => assets.bold_italic_data,
        };

        const size_scale = self.size / current_font_data.size * (1.0 + current_font_data.padding * 2 / current_font_data.size);
        const start_line_height = current_font_data.line_height * current_font_data.size * size_scale;
        var line_height = start_line_height;

        var x_pointer: f32 = 0.0;
        var y_pointer: f32 = line_height;
        var x_max: f32 = 0.0;
        var current_size = size_scale;
        var index_offset: u16 = 0;
        var word_start: usize = 0;
        var last_word_start_pointer: f32 = 0.0;
        var last_word_end_pointer: f32 = 0.0;
        var needs_new_word_idx = true;
        defer {
            self.width = @max(x_max, x_pointer);
            self.line_widths.?.append(main.allocator, x_pointer) catch @panic("OOM");
            self.height = y_pointer;
        }
        for (0..self.text.len) |i| {
            const offset_i = i + index_offset;
            if (offset_i >= self.text.len) return;

            var skip_space_check = false;
            var char = self.text[offset_i];
            specialChar: {
                if (!self.handle_special_chars) break :specialChar;

                if (char == '&') {
                    const name_start = self.text[offset_i + 1 ..];
                    const reset = "reset";
                    if (self.text.len >= offset_i + 1 + reset.len and std.mem.eql(u8, name_start[0..reset.len], reset)) {
                        current_type = self.text_type;
                        current_font_data = switch (current_type) {
                            .medium => assets.medium_data,
                            .medium_italic => assets.medium_italic_data,
                            .bold => assets.bold_data,
                            .bold_italic => assets.bold_italic_data,
                        };
                        current_size = size_scale;
                        line_height = start_line_height;
                        y_pointer += (line_height - start_line_height) / 2.0;
                        index_offset += @intCast(reset.len);
                        continue;
                    }

                    const space = "space";
                    if (self.text.len >= offset_i + 1 + space.len and std.mem.eql(u8, name_start[0..space.len], space)) {
                        char = ' ';
                        skip_space_check = true;
                        index_offset += @intCast(space.len);
                        break :specialChar;
                    }

                    if (std.mem.indexOfScalar(u8, name_start, '=')) |eql_idx| {
                        const value_start_idx = offset_i + 1 + eql_idx + 1;
                        if (self.text.len <= value_start_idx or self.text[value_start_idx] != '"') break :specialChar;

                        const value_start = self.text[value_start_idx + 1 ..];
                        if (std.mem.indexOfScalar(u8, value_start, '"')) |value_end_idx| {
                            const name = name_start[0..eql_idx];
                            const value = value_start[0..value_end_idx];
                            if (std.mem.eql(u8, name, "size")) {
                                const size = std.fmt.parseFloat(f32, value) catch {
                                    std.log.err("Invalid size given to control code: {s}", .{value});
                                    break :specialChar;
                                };
                                current_size = size / current_font_data.size * (1.0 + current_font_data.padding * 2 / current_font_data.size);
                                line_height = current_font_data.line_height * current_font_data.size * current_size;
                                y_pointer += (line_height - start_line_height) / 2.0;
                            } else if (std.mem.eql(u8, name, "type")) {
                                if (std.mem.eql(u8, value, "med"))
                                    current_type = .medium
                                else if (std.mem.eql(u8, value, "med_it"))
                                    current_type = .medium_italic
                                else if (std.mem.eql(u8, value, "bold"))
                                    current_type = .bold
                                else if (std.mem.eql(u8, value, "bold_it"))
                                    current_type = .bold_italic;
                                current_font_data = switch (current_type) {
                                    .medium => assets.medium_data,
                                    .medium_italic => assets.medium_italic_data,
                                    .bold => assets.bold_data,
                                    .bold_italic => assets.bold_italic_data,
                                };
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
                                    std.log.err("The index {} given for sheet {s} in control code was out of bounds", .{ index, sheet.? });
                                    break :specialChar;
                                }

                                if (needs_new_word_idx) {
                                    word_start = i;
                                    last_word_start_pointer = x_pointer;
                                    needs_new_word_idx = false;
                                }

                                x_pointer += current_size * current_font_data.size;
                                if (x_pointer > self.max_width) {
                                    self.line_widths.?.append(main.allocator, last_word_end_pointer) catch @panic("OOM");
                                    self.break_indices.?.put(main.allocator, word_start, {}) catch @panic("OOM");
                                    self.line_count += 1;
                                    x_pointer -= last_word_start_pointer;
                                    y_pointer += line_height;
                                }
                            } else if (!std.mem.eql(u8, name, "col")) break :specialChar;

                            index_offset += @intCast(1 + eql_idx + 1 + value_end_idx + 1);
                            x_max = @max(x_max, x_pointer);
                            continue;
                        } else break :specialChar;
                    } else break :specialChar;
                }
            }

            const mod_char = if (self.password) '*' else char;
            const char_data = current_font_data.characters[mod_char];

            const scaled_advance = char_data.x_advance * current_size;
            x_pointer += scaled_advance;

            if (!skip_space_check and std.ascii.isWhitespace(char)) {
                last_word_end_pointer = x_pointer;
                needs_new_word_idx = true;
            } else if (needs_new_word_idx) {
                word_start = i;
                last_word_start_pointer = x_pointer - scaled_advance;
                needs_new_word_idx = false;
            }

            const width_overflow = x_pointer > self.max_width;
            if (char == '\n' or width_overflow) {
                y_pointer += line_height;
                const next_pointer = if (width_overflow) last_word_end_pointer else x_pointer;
                self.line_widths.?.append(main.allocator, next_pointer) catch @panic("OOM");
                self.break_indices.?.put(main.allocator, if (width_overflow) word_start else i, {}) catch @panic("OOM");
                self.line_count += 1;
                if (width_overflow) x_pointer -= last_word_start_pointer else x_pointer = scaled_advance;
            }

            x_max = @max(x_max, x_pointer);
        }
    }

    pub fn deinit(self: *TextData) void {
        self.lock.lock();
        defer self.lock.unlock();

        main.allocator.free(self.backing_buffer);

        if (self.line_widths) |*line_widths| {
            line_widths.deinit(main.allocator);
            self.line_widths = null;
        }

        if (self.break_indices) |*break_indices| {
            break_indices.deinit(main.allocator);
            self.break_indices = null;
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
    scissor: ScissorRect = .{},
    atlas_data: [9]AtlasData,

    pub fn fromAtlasData(data: AtlasData, w: f32, h: f32, slice_x: f32, slice_y: f32, slice_w: f32, slice_h: f32, alpha: f32) NineSliceImageData {
        const base_u = data.texURaw();
        const base_v = data.texVRaw();
        const base_w = data.width();
        const base_h = data.height();
        return .{
            .w = w,
            .h = h,
            .alpha = alpha,
            .atlas_data = .{
                .fromRawF32(base_u, base_v, slice_x, slice_y, data.atlas_type),
                .fromRawF32(base_u + slice_x, base_v, slice_w, slice_y, data.atlas_type),
                .fromRawF32(base_u + slice_x + slice_w, base_v, base_w - slice_w - slice_x, slice_y, data.atlas_type),
                .fromRawF32(base_u, base_v + slice_y, slice_x, slice_h, data.atlas_type),
                .fromRawF32(base_u + slice_x, base_v + slice_y, slice_w, slice_h, data.atlas_type),
                .fromRawF32(base_u + slice_x + slice_w, base_v + slice_y, base_w - slice_w - slice_x, slice_h, data.atlas_type),
                .fromRawF32(base_u, base_v + slice_y + slice_h, slice_x, base_h - slice_h - slice_y, data.atlas_type),
                .fromRawF32(base_u + slice_x, base_v + slice_y + slice_h, slice_w, base_h - slice_h - slice_y, data.atlas_type),
                .fromRawF32(base_u + slice_x + slice_w, base_v + slice_y + slice_h, base_w - slice_w - slice_x, base_h - slice_h - slice_y, data.atlas_type),
            },
        };
    }

    pub fn draw(self: NineSliceImageData, x: f32, y: f32, scissor_override: ?ScissorRect) void {
        const scissor = if (scissor_override) |s| s else self.scissor;
        var opts: render.QuadOptions = .{
            .alpha_mult = self.alpha,
            .color = self.color,
            .color_intensity = self.color_intensity,
            .scissor = scissor,
        };

        const w = self.w;
        const h = self.h;

        const top_left = self.topLeft();
        const top_left_w = top_left.texWRaw();
        const top_left_h = top_left.texHRaw();
        render.drawQuad(x, y, top_left_w, top_left_h, top_left, opts);

        const top_right = self.topRight();
        const top_right_w = top_right.texWRaw();
        if (scissor.min_x != ScissorRect.dont_scissor) opts.scissor.min_x = scissor.min_x - (w - top_right_w);
        if (scissor.max_x != ScissorRect.dont_scissor) opts.scissor.max_x = scissor.max_x - (w - top_right_w);
        render.drawQuad(x + (w - top_right_w), y, top_right_w, top_right.texHRaw(), top_right, opts);

        const bottom_left = self.bottomLeft();
        const bottom_left_w = bottom_left.texWRaw();
        const bottom_left_h = bottom_left.texHRaw();
        opts.scissor.min_x = scissor.min_x;
        opts.scissor.max_x = scissor.max_x;
        if (scissor.min_y != ScissorRect.dont_scissor) opts.scissor.min_y = scissor.min_y - (h - bottom_left_h);
        if (scissor.max_y != ScissorRect.dont_scissor) opts.scissor.max_y = scissor.max_y - (h - bottom_left_h);
        render.drawQuad(x, y + (h - bottom_left_h), bottom_left_w, bottom_left_h, bottom_left, opts);

        const bottom_right = self.bottomRight();
        const bottom_right_w = bottom_right.texWRaw();
        const bottom_right_h = bottom_right.texHRaw();
        opts.scissor.min_x = if (scissor.min_x != ScissorRect.dont_scissor)
            scissor.min_x - (w - top_right_w)
        else
            ScissorRect.dont_scissor;
        opts.scissor.max_x = if (scissor.max_x != ScissorRect.dont_scissor)
            scissor.max_x - (w - top_right_w)
        else
            ScissorRect.dont_scissor;
        opts.scissor.min_y = if (scissor.min_y != ScissorRect.dont_scissor)
            scissor.min_y - (h - bottom_left_h)
        else
            ScissorRect.dont_scissor;
        opts.scissor.max_y = if (scissor.max_y != ScissorRect.dont_scissor)
            scissor.max_y - (h - bottom_left_h)
        else
            ScissorRect.dont_scissor;
        render.drawQuad(x + (w - bottom_right_w), y + (h - bottom_right_h), bottom_right_w, bottom_right_h, bottom_right, opts);

        const top_center = self.topCenter();
        opts.scissor.min_x = if (scissor.min_x != ScissorRect.dont_scissor)
            scissor.min_x - top_left_w
        else
            ScissorRect.dont_scissor;
        opts.scissor.max_x = if (scissor.max_x != ScissorRect.dont_scissor)
            scissor.max_x - top_left_w
        else
            ScissorRect.dont_scissor;
        opts.scissor.min_y = scissor.min_y;
        opts.scissor.max_y = scissor.max_y;
        render.drawQuad(x + top_left_w, y, w - top_left_w - top_right_w, top_center.texHRaw(), top_center, opts);

        const bottom_center = self.bottomCenter();
        const bottom_center_h = bottom_center.texHRaw();
        opts.scissor.min_x = if (scissor.min_x != ScissorRect.dont_scissor)
            scissor.min_x - bottom_left_w
        else
            ScissorRect.dont_scissor;
        opts.scissor.max_x = if (scissor.max_x != ScissorRect.dont_scissor)
            scissor.max_x - bottom_left_w
        else
            ScissorRect.dont_scissor;
        opts.scissor.min_y = if (scissor.min_y != ScissorRect.dont_scissor)
            scissor.min_y - (h - bottom_center_h)
        else
            ScissorRect.dont_scissor;
        opts.scissor.max_y = if (scissor.max_y != ScissorRect.dont_scissor)
            scissor.max_y - (h - bottom_center_h)
        else
            ScissorRect.dont_scissor;
        render.drawQuad(x + bottom_left_w, y + (h - bottom_center_h), w - bottom_left_w - bottom_right_w, bottom_center_h, bottom_center, opts);

        const middle_center = self.middleCenter();
        opts.scissor.min_x = if (scissor.min_x != ScissorRect.dont_scissor)
            scissor.min_x - top_left_w
        else
            ScissorRect.dont_scissor;
        opts.scissor.max_x = if (scissor.max_x != ScissorRect.dont_scissor)
            scissor.max_x - top_left_w
        else
            ScissorRect.dont_scissor;
        opts.scissor.min_y = if (scissor.min_y != ScissorRect.dont_scissor)
            scissor.min_y - top_left_h
        else
            ScissorRect.dont_scissor;
        opts.scissor.max_y = if (scissor.max_y != ScissorRect.dont_scissor)
            scissor.max_y - top_left_h
        else
            ScissorRect.dont_scissor;
        render.drawQuad(x + top_left_w, y + top_left_h, w - top_left_w - top_right_w, h - top_left_h - bottom_left_h, middle_center, opts);

        const middle_left = self.middleLeft();
        opts.scissor.min_x = scissor.min_x;
        opts.scissor.max_x = scissor.max_x;
        opts.scissor.min_y = if (scissor.min_y != ScissorRect.dont_scissor)
            scissor.min_y - top_left_h
        else
            ScissorRect.dont_scissor;
        opts.scissor.max_y = if (scissor.max_y != ScissorRect.dont_scissor)
            scissor.max_y - top_left_h
        else
            ScissorRect.dont_scissor;
        render.drawQuad(x, y + top_left_h, middle_left.texWRaw(), h - top_left_h - bottom_left_h, middle_left, opts);

        const middle_right = self.middleRight();
        const middle_right_w = middle_right.texWRaw();
        opts.scissor.min_x = if (scissor.min_x != ScissorRect.dont_scissor)
            scissor.min_x - (w - middle_right_w)
        else
            ScissorRect.dont_scissor;
        opts.scissor.max_x = if (scissor.max_x != ScissorRect.dont_scissor)
            scissor.max_x - (w - middle_right_w)
        else
            ScissorRect.dont_scissor;
        opts.scissor.min_y = if (scissor.min_y != ScissorRect.dont_scissor)
            scissor.min_y - top_left_h
        else
            ScissorRect.dont_scissor;
        opts.scissor.max_y = if (scissor.max_y != ScissorRect.dont_scissor)
            scissor.max_y - top_left_h
        else
            ScissorRect.dont_scissor;
        render.drawQuad(x + (w - middle_right_w), y + top_left_h, middle_right_w, h - top_left_h - bottom_left_h, middle_right, opts);
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
    glow: bool = false,
    color_intensity: f32 = 0,
    scissor: ScissorRect = .{},
    atlas_data: assets.AtlasData,

    pub fn draw(self: NormalImageData, x: f32, y: f32, scissor_override: ?ScissorRect) void {
        const opts: render.QuadOptions = .{
            .alpha_mult = self.alpha,
            .scissor = if (scissor_override) |s| s else self.scissor,
            .color = self.color,
            .color_intensity = self.color_intensity,
            .shadow_texel_mult = if (self.glow) 2.0 / @max(self.scale_x, self.scale_y) else 0.0,
        };
        render.drawQuad(x, y, self.texWRaw(), self.texHRaw(), self.atlas_data, opts);
    }

    pub fn width(self: NormalImageData) f32 {
        return self.atlas_data.width() * self.scale_x;
    }

    pub fn height(self: NormalImageData) f32 {
        return self.atlas_data.height() * self.scale_y;
    }

    pub fn texWRaw(self: NormalImageData) f32 {
        return self.atlas_data.texWRaw() * self.scale_x;
    }

    pub fn texHRaw(self: NormalImageData) f32 {
        return self.atlas_data.texHRaw() * self.scale_y;
    }
};

pub const ImageData = union(enum) {
    nine_slice: NineSliceImageData,
    normal: NormalImageData,

    pub fn draw(self: ImageData, x: f32, y: f32, scissor_override: ScissorRect) void {
        const scissor = if (scissor_override == ScissorRect{}) null else scissor_override;
        switch (self) {
            .nine_slice => |nine_slice| nine_slice.draw(x, y, scissor),
            .normal => |normal| normal.draw(x, y, scissor),
        }
    }

    pub fn setScissor(self: *ImageData, scissor: ScissorRect) void {
        switch (self.*) {
            .nine_slice => |*nine_slice| nine_slice.scissor = scissor,
            .normal => |*normal| normal.scissor = scissor,
        }
    }

    pub fn scaleWidth(self: *ImageData, w: f32) void {
        switch (self.*) {
            .nine_slice => |*nine_slice| nine_slice.w = w,
            .normal => |*normal| normal.scale_x = normal.atlas_data.texWRaw() / w,
        }
    }

    pub fn scaleHeight(self: *ImageData, h: f32) void {
        switch (self.*) {
            .nine_slice => |*nine_slice| nine_slice.h = h,
            .normal => |*normal| normal.scale_y = normal.atlas_data.texHRaw() / h,
        }
    }

    pub fn width(self: ImageData) f32 {
        return switch (self) {
            .nine_slice => |nine_slice| nine_slice.w,
            .normal => |normal| normal.width(),
        };
    }

    pub fn height(self: ImageData) f32 {
        return switch (self) {
            .nine_slice => |nine_slice| nine_slice.h,
            .normal => |normal| normal.height(),
        };
    }

    pub fn texWRaw(self: ImageData) f32 {
        return switch (self) {
            .nine_slice => |nine_slice| nine_slice.w,
            .normal => |normal| normal.texWRaw(),
        };
    }

    pub fn texHRaw(self: ImageData) f32 {
        return switch (self) {
            .nine_slice => |nine_slice| nine_slice.h,
            .normal => |normal| normal.texHRaw(),
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

    pub fn width(self: InteractableImageData, state: InteractableState) f32 {
        return self.current(state).width();
    }

    pub fn height(self: InteractableImageData, state: InteractableState) f32 {
        return self.current(state).height();
    }

    pub fn texWRaw(self: InteractableImageData, state: InteractableState) f32 {
        return self.current(state).texWRaw();
    }

    pub fn texHRaw(self: InteractableImageData, state: InteractableState) f32 {
        return self.current(state).texHRaw();
    }

    pub fn setScissor(self: *InteractableImageData, scissor: ScissorRect) void {
        self.base.setScissor(scissor);
        if (self.hover) |*data| data.setScissor(scissor);
        if (self.press) |*data| data.setScissor(scissor);
    }

    pub fn scaleWidth(self: *InteractableImageData, w: f32) void {
        self.base.scaleWidth(w);
        if (self.hover) |*data| data.scaleWidth(w);
        if (self.press) |*data| data.scaleWidth(w);
    }

    pub fn scaleHeight(self: *InteractableImageData, h: f32) void {
        self.base.scaleHeight(h);
        if (self.hover) |*data| data.scaleHeight(h);
        if (self.press) |*data| data.scaleHeight(h);
    }

    pub fn fromImageData(base: assets.AtlasData, hover: ?assets.AtlasData, press: ?assets.AtlasData) InteractableImageData {
        var ret: InteractableImageData = .{ .base = .{ .normal = .{ .atlas_data = base } } };
        if (hover) |hover_data| ret.hover = .{ .normal = .{ .atlas_data = hover_data } };
        if (press) |press_data| ret.press = .{ .normal = .{ .atlas_data = press_data } };
        return ret;
    }

    pub fn fromNineSlices(
        base: assets.AtlasData,
        hover: ?assets.AtlasData,
        press: ?assets.AtlasData,
        w: f32,
        h: f32,
        slice_x: f32,
        slice_y: f32,
        slice_w: f32,
        slice_h: f32,
        alpha: f32,
    ) InteractableImageData {
        var ret: InteractableImageData = .{ .base = .{ .nine_slice = .fromAtlasData(base, w, h, slice_x, slice_y, slice_w, slice_h, alpha) } };
        if (hover) |hover_data| ret.hover = .{ .nine_slice = .fromAtlasData(hover_data, w, h, slice_x, slice_y, slice_w, slice_h, alpha) };
        if (press) |press_data| ret.press = .{ .nine_slice = .fromAtlasData(press_data, w, h, slice_x, slice_y, slice_w, slice_h, alpha) };
        return ret;
    }
};

// Scissor positions are relative to the element it's attached to
pub const ScissorRect = packed struct {
    pub const dont_scissor = -1.0;

    min_x: f32 = dont_scissor,
    max_x: f32 = dont_scissor,
    min_y: f32 = dont_scissor,
    max_y: f32 = dont_scissor,
};

pub fn create(comptime T: type, data: T) !*@TypeOf(data) {
    var elem = try main.allocator.create(T);
    elem.* = data;
    if (std.meta.hasFn(T, "init")) elem.init();

    comptime var field_name: []const u8 = "";
    inline for (@typeInfo(UiElement).@"union".fields) |field| {
        if (@typeInfo(field.type).pointer.child == T) {
            field_name = field.name;
            break;
        }
    }

    if (field_name.len == 0) @compileError("Could not find field name");

    try systems.elements_to_add.append(main.allocator, @unionInit(UiElement, field_name, elem));
    return elem;
}

pub fn destroy(self: anytype) void {
    comptime var field_name: []const u8 = "";
    inline for (@typeInfo(UiElement).@"union".fields) |field| {
        if (field.type == @TypeOf(self)) {
            field_name = field.name;
            break;
        }
    }

    if (field_name.len == 0) @compileError("Could not find field name");

    const tag = std.meta.stringToEnum(std.meta.Tag(UiElement), field_name);

    systems.hover_lock.lock();
    defer systems.hover_lock.unlock();
    if (systems.hover_target != null and
        systems.hover_target.? == tag.? and
        self == @field(systems.hover_target.?, field_name))
        systems.hover_target = null;

    std.debug.assert(!systems.ui_lock.tryLock());

    removeFromList: inline for (.{ &systems.elements, &systems.elements_to_add }) |elems| {
        for (elems.items, 0..) |element, i| if (element == tag.? and @field(element, field_name) == self) {
            _ = elems.orderedRemove(i);
            break :removeFromList;
        };
    }

    if (std.meta.hasFn(@typeInfo(@TypeOf(self)).pointer.child, "deinit")) self.deinit();
    main.allocator.destroy(self);
}

pub fn intersects(self: anytype, x: f32, y: f32) bool {
    const has_scissor = @hasField(@typeInfo(@TypeOf(self)).pointer.child, "scissor");
    if (has_scissor and
        (self.base.scissor.min_x != ScissorRect.dont_scissor and x - self.base.x < self.scissor.min_x or
        self.base.scissor.min_y != ScissorRect.dont_scissor and y - self.base.y < self.scissor.min_y))
        return false;

    const w = if (has_scissor and self.base.scissor.max_x != ScissorRect.dont_scissor) @min(self.texWRaw(), self.base.scissor.max_x) else self.texWRaw();
    const h = if (has_scissor and self.base.scissor.max_y != ScissorRect.dont_scissor) @min(self.texHRaw(), self.base.scissor.max_y) else self.texHRaw();
    return utils.isInBounds(x, y, self.base.x, self.base.y, w, h);
}
