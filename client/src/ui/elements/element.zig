const std = @import("std");

const utils = @import("shared").utils;

const assets = @import("../../assets.zig");
const main = @import("../../main.zig");
const Renderer = @import("../../render/Renderer.zig");
const QuadOptions = @import("../../render/Renderer.zig").QuadOptions;
const Settings = @import("../../Settings.zig");
const systems = @import("../systems.zig");
const Bar = @import("Bar.zig");
const Button = @import("Button.zig");
const Container = @import("Container.zig");
const Dropdown = @import("Dropdown.zig");
const DropdownContainer = @import("DropdownContainer.zig");
const Image = @import("Image.zig");
const Input = @import("Input.zig");
const Item = @import("Item.zig");
const KeyMapper = @import("KeyMapper.zig");
const Minimap = @import("Minimap.zig");
const ScrollableContainer = @import("ScrollableContainer.zig");
const Slider = @import("Slider.zig");
const Text = @import("Text.zig");
const Toggle = @import("Toggle.zig");

pub const UiElement = union(enum) {
    bar: *Bar,
    button: *Button,
    container: *Container,
    dropdown: *Dropdown,
    // don't actually use this here. internal use only
    dropdown_container: *DropdownContainer,
    image: *Image,
    input_field: *Input,
    item: *Item,
    key_mapper: *KeyMapper,
    scrollable_container: *ScrollableContainer,
    slider: *Slider,
    text: *Text,
    toggle: *Toggle,
    minimap: *Minimap,

    pub fn draw(
        self: UiElement,
        generics: *std.ArrayList(Renderer.GenericData),
        sort_extras: *std.ArrayList(f32),
        x_offset: f32,
        y_offset: f32,
        time: i64,
    ) void {
        switch (self) {
            inline else => |elem| elem.draw(generics, sort_extras, x_offset, y_offset, time),
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
    menu,
    tooltip,
};

pub const EventPolicy = packed struct {
    pub const pass_all: EventPolicy = .{
        .pass_press = true,
        .pass_release = true,
        .pass_move = true,
        .pass_scroll = true,
    };

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

    pub fn font(self: TextType) assets.Font {
        return switch (self) {
            .medium => assets.medium_font,
            .medium_italic => assets.medium_italic_font,
            .bold => assets.bold_font,
            .bold_italic => assets.bold_italic_font,
        };
    }
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
    /// 0 implies that the backing buffer won't be used.
    /// If your element uses it, you must set this to something appropriate.
    max_chars: u32 = 0,
    text_type: TextType = .medium,
    color: u32 = 0xFFFFFF,
    alpha: f32 = 1.0,
    outline_color: u32 = 0x000000,
    outline_width: f32 = 0.33,
    password: bool = false,
    handle_special_chars: bool = true,
    disable_subpixel: bool = false,
    /// Disables text pos realignment based on the true width/height,
    /// for use with input fields and the like.
    disable_trim_pos: bool = false,
    scissor: ScissorRect = .{},
    /// Alignments other than default (left/top) need max width/height defined, respectively.
    hori_align: AlignHori = .left,
    vert_align: AlignVert = .top,
    max_width: f32 = std.math.floatMax(f32),
    max_height: f32 = std.math.floatMax(f32),
    backing_buffer: []u8 = &.{},
    width: f32 = 0.0,
    height: f32 = 0.0,
    line_count: f32 = 0.0,
    sort_extra: f32 = 0.0,
    generics: std.ArrayList(Renderer.GenericData) = .empty,
    sort_extras: std.ArrayList(f32) = .empty,

    pub fn setText(self: *TextData, text: []const u8) void {
        self.text = text;
        self.update();
    }

    fn norm(f: f32) f32 {
        return if (f == std.math.floatMax(f32)) 0.0 else f;
    }

    pub fn update(self: *TextData) void {
        self.generics.clearRetainingCapacity();
        self.sort_extras.clearRetainingCapacity();

        if (self.backing_buffer.len == 0 and self.max_chars > 0)
            self.backing_buffer = main.allocator.alloc(u8, self.max_chars) catch main.oomPanic();

        const render_type: Renderer.RenderType = if (self.disable_subpixel) .text_normal else .text_subpixel;

        var word_widths: std.ArrayList(f32) = .empty;
        defer word_widths.deinit(main.allocator);

        var line_widths: std.ArrayList(f32) = .empty;
        defer line_widths.deinit(main.allocator);

        var x_min_norm: f32 = 0.0;
        var y_min_norm: f32 = 0.0;

        const Pass = enum { width, line, render };
        inline for (.{ Pass.width, Pass.line, Pass.render }) |pass| @"continue": {
            var current_type = self.text_type;
            var current_font = current_type.font();

            const size_scale = self.size / current_font.size;
            const start_line_height = current_font.line_height * current_font.size * size_scale;
            var line_height = start_line_height;

            const max_width_off = self.max_width == std.math.floatMax(f32);
            const max_height_off = self.max_height == std.math.floatMax(f32);

            const start_x = if (self.disable_trim_pos) 0.0 else -x_min_norm;
            const start_y = line_height - if (self.disable_trim_pos) 0.0 else y_min_norm;
            const y_base: f32 = switch (pass) {
                .render => switch (self.vert_align) {
                    .top => start_y,
                    .middle => if (max_height_off) start_y else start_y + (self.max_height - self.height) / 2.0,
                    .bottom => if (max_height_off) start_y else start_y + (self.max_height - self.height),
                },
                else => start_y,
            };
            var line_idx: u16 = 1;
            var x_base: f32 = switch (pass) {
                .render => switch (self.hori_align) {
                    .left => start_x,
                    .middle => if (max_width_off) start_x else start_x + (self.max_width - line_widths.items[0]) / 2.0,
                    .right => if (max_width_off) start_x else start_x + (self.max_width - line_widths.items[0]),
                },
                else => start_x,
            };
            var x_pointer = x_base;
            var y_pointer = y_base;

            var line_x_min: f32 = std.math.floatMax(f32);
            var x_min: f32 = std.math.floatMax(f32);
            var x_max: f32 = 0.0;
            var y_min: f32 = std.math.floatMax(f32);
            var y_max: f32 = line_height;
            var last_x_off: f32 = 0.0;
            var last_y_off: f32 = 0.0;
            var last_nonzero_y_off: f32 = 0.0;
            var last_w: f32 = 0.0;
            var last_h: f32 = 0.0;
            var last_advance: f32 = 0.0;
            var current_size = size_scale;
            var current_color = self.color;
            var index_offset: u16 = 0;
            var word_idx: usize = 0;
            var last_word_start_pointer: f32 = 0.0;
            var needs_new_word_idx = true;
            var prev_char: u8 = std.math.maxInt(u8);
            defer {
                const right_x = x_pointer + last_x_off + last_w - last_advance;
                switch (pass) {
                    .width => word_widths.append(main.allocator, right_x - last_word_start_pointer) catch main.oomPanic(),
                    .line => {
                        x_min_norm = norm(x_min);
                        y_min_norm = norm(y_min);
                        self.width = x_max - x_min_norm;
                        self.height = y_max - y_min_norm;
                        line_widths.append(main.allocator, right_x - norm(line_x_min)) catch main.oomPanic();
                    },
                    .render => {},
                }
            }

            for (0..self.text.len) |i| {
                const offset_i = i + index_offset;
                if (offset_i >= self.text.len) break :@"continue";

                var skip_space_check = false;
                var char = self.text[offset_i];
                defer prev_char = char;
                if (self.handle_special_chars and char == '&') specialChar: {
                    const name_start = self.text[offset_i + 1 ..];

                    const reset = "reset";
                    if (self.text.len >= offset_i + 1 + reset.len and
                        std.mem.eql(u8, name_start[0..reset.len], reset))
                    {
                        current_type = self.text_type;
                        current_font = current_type.font();
                        current_color = self.color;
                        current_size = size_scale;
                        line_height = start_line_height;
                        index_offset += @intCast(reset.len);
                        continue;
                    }

                    const space = "space";
                    if (self.text.len >= offset_i + 1 + space.len and
                        std.mem.eql(u8, name_start[0..space.len], space))
                    {
                        char = ' ';
                        skip_space_check = true;
                        index_offset += @intCast(space.len);
                        break :specialChar;
                    }

                    const eql_idx = std.mem.indexOfScalar(u8, name_start, '=') orelse break :specialChar;
                    const value_start_idx = offset_i + 1 + eql_idx + 1;
                    if (self.text.len <= value_start_idx) break :specialChar;

                    const value_start = self.text[value_start_idx + 1 ..];
                    const value_end_idx = std.mem.indexOfScalar(u8, value_start, '"') orelse break :specialChar;
                    if (self.text.len <= value_end_idx) break :specialChar;

                    const name = name_start[0..eql_idx];
                    const value = value_start[0..value_end_idx];
                    if (std.mem.eql(u8, name, "size")) {
                        const size = std.fmt.parseFloat(f32, value) catch break :specialChar;
                        current_size = size / current_font.size;
                        line_height = current_font.line_height * current_font.size * current_size;
                    } else if (std.mem.eql(u8, name, "type")) {
                        if (std.mem.eql(u8, value, "med"))
                            current_type = .medium
                        else if (std.mem.eql(u8, value, "med_it"))
                            current_type = .medium_italic
                        else if (std.mem.eql(u8, value, "bold"))
                            current_type = .bold
                        else if (std.mem.eql(u8, value, "bold_it"))
                            current_type = .bold_italic;
                        current_font = current_type.font();
                    } else if (std.mem.eql(u8, name, "img")) {
                        var values = std.mem.splitScalar(u8, value, ',');
                        const sheet = values.next();
                        if (sheet == null or std.mem.eql(u8, sheet.?, value)) break :specialChar;
                        const index_str = values.next() orelse break :specialChar;
                        const index = std.fmt.parseInt(u32, index_str, 0) catch break :specialChar;
                        const atlas: assets.AtlasType = .fromString(values.next() orelse "base");
                        if (atlas == .invalid) break :specialChar;
                        const sheet_rects = assets.tryGet(sheet.?, atlas) orelse break :specialChar;
                        if (index >= sheet_rects.len) break :specialChar;

                        const scaled_size = current_size * current_font.size;
                        const w_larger = sheet_rects[index].tex_w > sheet_rects[index].tex_h;

                        last_h = if (w_larger)
                            sheet_rects[index].height() * (scaled_size / sheet_rects[index].width())
                        else
                            scaled_size;

                        last_w = if (w_larger)
                            scaled_size
                        else
                            sheet_rects[index].width() * (scaled_size / sheet_rects[index].height());

                        last_x_off = 0.0;
                        last_y_off = 0.0;

                        if (needs_new_word_idx) {
                            last_word_start_pointer = x_pointer;
                            if (pass == .line) {
                                defer word_idx += 1;
                                if (x_pointer + word_widths.items[word_idx] > self.max_width) {
                                    y_pointer += line_height;
                                    line_widths.append(main.allocator, x_pointer + last_w - norm(line_x_min)) catch main.oomPanic();
                                    x_min = @min(x_min, x_pointer);
                                    x_max = @max(x_max, x_pointer + last_w);
                                    x_pointer = 0.0;
                                    line_x_min = @min(line_x_min, 0.0);
                                }
                            }
                            needs_new_word_idx = false;
                        }

                        last_advance = last_w + 2;
                        const needs_new_line = x_pointer + last_advance > self.max_width;
                        switch (pass) {
                            .width => {},
                            .line => {
                                if (needs_new_line) {
                                    y_pointer += line_height;
                                    line_widths.append(main.allocator, x_pointer + last_w - norm(line_x_min)) catch main.oomPanic();
                                    x_pointer = 0.0;
                                    line_x_min = @min(line_x_min, 0.0);
                                }

                                x_min = @min(x_min, x_pointer);
                                x_max = @max(x_max, x_pointer + last_w);
                                y_min = @min(y_min, y_pointer);
                                y_max = @max(y_max, y_pointer + last_h);
                            },
                            .render => {
                                if (needs_new_line) {
                                    y_pointer += line_height;
                                    if (y_pointer - y_base > self.max_height) return;

                                    x_base = switch (self.hori_align) {
                                        .left => start_x,
                                        .middle => if (max_width_off) start_x else start_x + (self.max_width - line_widths.items[line_idx]) / 2.0,
                                        .right => if (max_width_off) start_x else start_x + (self.max_width - line_widths.items[line_idx]),
                                    };
                                    x_pointer = x_base;
                                    line_idx += 1;
                                }

                                Renderer.drawQuad(
                                    &self.generics,
                                    &self.sort_extras,
                                    x_pointer,
                                    y_pointer + last_nonzero_y_off - last_h / 2.0,
                                    last_w,
                                    last_h,
                                    sheet_rects[index],
                                    .{ .alpha_mult = self.alpha },
                                );
                            },
                        }

                        x_pointer += last_advance;
                    } else if (std.mem.eql(u8, name, "col")) {
                        current_color = std.fmt.parseInt(u32, value, 16) catch break :specialChar;
                    } else break :specialChar;

                    index_offset += @intCast(1 + eql_idx + 1 + value_end_idx + 1);
                    continue;
                }

                if (char == '\n') switch (pass) {
                    .width => {},
                    .line => {
                        y_pointer += line_height;
                        const old_right_x = x_pointer + last_x_off + last_w - last_advance;
                        line_widths.append(main.allocator, old_right_x - norm(line_x_min)) catch main.oomPanic();
                        x_min = @min(x_min, old_right_x);
                        x_max = @max(x_max, old_right_x);
                        x_pointer = 0.0;
                        line_x_min = @min(line_x_min, 0.0);
                        continue;
                    },
                    .render => {
                        y_pointer += line_height;
                        if (y_pointer - y_base > self.max_height) return;

                        x_base = switch (self.hori_align) {
                            .left => start_x,
                            .middle => if (max_width_off) start_x else start_x + (self.max_width - line_widths.items[line_idx]) / 2.0,
                            .right => if (max_width_off) start_x else start_x + (self.max_width - line_widths.items[line_idx]),
                        };
                        x_pointer = x_base;
                        line_idx += 1;
                        continue;
                    },
                };

                const mod_char = if (self.password) '*' else char;
                const char_info = current_font.characters[mod_char];
                const kern_x = current_font.characters[prev_char].kernings.get(mod_char) orelse 0.0;
                const scaled_advance = (if (char_info.isInvalid()) 0.0 else char_info.x_advance) * current_size;
                last_advance = scaled_advance;
                last_w = (char_info.width - current_font.padding * 2.0) * current_size;
                last_h = (char_info.height - current_font.padding * 2.0) * current_size;
                last_x_off = (char_info.x_offset + kern_x) * current_size;
                last_y_off = -char_info.y_offset * current_size;
                if (last_y_off > 0.0) last_nonzero_y_off = last_y_off;
                var left_x = x_pointer + last_x_off;
                var right_x = left_x + last_w;

                if (!skip_space_check and std.ascii.isWhitespace(char)) {
                    if (!needs_new_word_idx and pass == .width)
                        word_widths.append(main.allocator, x_pointer - last_word_start_pointer) catch main.oomPanic();
                    needs_new_word_idx = true;
                } else if (needs_new_word_idx) {
                    defer needs_new_word_idx = false;
                    switch (pass) {
                        .width => last_word_start_pointer = left_x,
                        .line => {
                            defer word_idx += 1;
                            if (left_x + word_widths.items[word_idx] > self.max_width) {
                                y_pointer += line_height;
                                line_widths.append(main.allocator, x_pointer - norm(line_x_min)) catch main.oomPanic();
                                x_min = @min(x_min, left_x);
                                x_max = @max(x_max, right_x);
                                x_pointer = 0.0;
                                left_x = last_x_off;
                                right_x = left_x + last_w;
                                line_x_min = @min(line_x_min, 0.0);
                            }
                        },
                        .render => {
                            defer word_idx += 1;
                            if (left_x + word_widths.items[word_idx] > self.max_width) {
                                y_pointer += line_height;
                                if (y_pointer - y_base > self.max_height) return;

                                x_base = switch (self.hori_align) {
                                    .left => start_x,
                                    .middle => if (max_width_off) start_x else start_x + (self.max_width - line_widths.items[line_idx]) / 2.0,
                                    .right => if (max_width_off) start_x else start_x + (self.max_width - line_widths.items[line_idx]),
                                };
                                x_pointer = x_base;
                                left_x = x_pointer + last_x_off;
                                right_x = left_x + last_w;
                                line_idx += 1;
                            }
                        },
                    }
                }

                switch (pass) {
                    .width => {},
                    .line => {
                        line_x_min = @min(line_x_min, left_x);
                        x_min = @min(x_min, left_x);
                        x_max = @max(x_max, right_x);

                        if (right_x > self.max_width) {
                            y_pointer += line_height;
                            line_widths.append(main.allocator, right_x - norm(line_x_min)) catch main.oomPanic();
                            x_pointer = 0.0;
                            line_x_min = 0.0;
                        }

                        const left_y = y_pointer + last_y_off;
                        y_min = @min(y_min, left_y);
                        y_max = @max(y_max, left_y + last_h);
                    },
                    .render => {
                        if (right_x > self.max_width) {
                            y_pointer += line_height;
                            if (y_pointer - y_base > self.max_height) return;

                            x_base = switch (self.hori_align) {
                                .left => start_x,
                                .middle => if (max_width_off) start_x else start_x + (self.max_width - line_widths.items[line_idx]) / 2.0,
                                .right => if (max_width_off) start_x else start_x + (self.max_width - line_widths.items[line_idx]),
                            };
                            x_pointer = x_base;
                            left_x = x_pointer + last_x_off;
                            right_x = left_x + last_w;
                            line_idx += 1;
                        }

                        if (char_info.tex_w <= 0) {
                            x_pointer += scaled_advance;
                            continue;
                        }

                        const pos: [2]f32 = .{
                            x_pointer + (char_info.x_offset + kern_x - current_font.padding) * current_size,
                            y_pointer + (-char_info.y_offset - current_font.padding) * current_size,
                        };

                        const w = char_info.width * current_size;
                        const h = char_info.height * current_size;
                        const uv_w_per_px = char_info.tex_w / w;
                        const uv_h_per_px = char_info.tex_h / h;
                        const x_off = -pos[0];
                        const y_off = -pos[1];

                        const dont_scissor = ScissorRect.dont_scissor;

                        self.sort_extras.append(main.allocator, self.sort_extra) catch main.oomPanic();
                        self.generics.append(main.allocator, .{
                            .render_type = render_type,
                            .text_type = current_type,
                            .text_dist_factor = current_font.px_range * current_size,
                            .alpha_mult = self.alpha,
                            .outline_color = self.outline_color,
                            .outline_width = self.outline_width,
                            .base_color = current_color,
                            .color_intensity = 1.0,
                            .pos = pos,
                            .size = .{ w, h },
                            .uv = .{ char_info.tex_u, char_info.tex_v },
                            .uv_size = .{ char_info.tex_w, char_info.tex_h },
                            .scissor = .{
                                char_info.tex_u + if (self.scissor.min_x == dont_scissor)
                                    0
                                else
                                    (self.scissor.min_x + x_off) * uv_w_per_px,
                                char_info.tex_u + if (self.scissor.max_x == dont_scissor)
                                    char_info.tex_w
                                else
                                    (self.scissor.max_x + x_off) * uv_w_per_px,
                                char_info.tex_v + if (self.scissor.min_y == dont_scissor)
                                    0
                                else
                                    (self.scissor.min_y + y_off) * uv_h_per_px,
                                char_info.tex_v + if (self.scissor.max_y == dont_scissor)
                                    char_info.tex_h
                                else
                                    (self.scissor.max_y + y_off) * uv_h_per_px,
                            },
                        }) catch main.oomPanic();
                    },
                }

                x_pointer += scaled_advance;
            }
        }
    }

    pub fn deinit(self: *TextData) void {
        main.allocator.free(self.backing_buffer);
        self.generics.deinit(main.allocator);
        self.sort_extras.deinit(main.allocator);
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

    pub fn draw(
        self: NineSliceImageData,
        generics: *std.ArrayList(Renderer.GenericData),
        sort_extras: *std.ArrayList(f32),
        x: f32,
        y: f32,
        scissor_override: ?ScissorRect,
    ) void {
        const scissor = if (scissor_override) |s| s else self.scissor;
        var opts: QuadOptions = .{
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
        Renderer.drawQuad(generics, sort_extras, x, y, top_left_w, top_left_h, top_left, opts);

        const top_right = self.topRight();
        const top_right_w = top_right.texWRaw();
        if (scissor.min_x != ScissorRect.dont_scissor) opts.scissor.min_x = scissor.min_x - (w - top_right_w);
        if (scissor.max_x != ScissorRect.dont_scissor) opts.scissor.max_x = scissor.max_x - (w - top_right_w);
        Renderer.drawQuad(generics, sort_extras, x + (w - top_right_w), y, top_right_w, top_right.texHRaw(), top_right, opts);

        const bottom_left = self.bottomLeft();
        const bottom_left_w = bottom_left.texWRaw();
        const bottom_left_h = bottom_left.texHRaw();
        opts.scissor.min_x = scissor.min_x;
        opts.scissor.max_x = scissor.max_x;
        if (scissor.min_y != ScissorRect.dont_scissor) opts.scissor.min_y = scissor.min_y - (h - bottom_left_h);
        if (scissor.max_y != ScissorRect.dont_scissor) opts.scissor.max_y = scissor.max_y - (h - bottom_left_h);
        Renderer.drawQuad(generics, sort_extras, x, y + (h - bottom_left_h), bottom_left_w, bottom_left_h, bottom_left, opts);

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
        Renderer.drawQuad(
            generics,
            sort_extras,
            x + (w - bottom_right_w),
            y + (h - bottom_right_h),
            bottom_right_w,
            bottom_right_h,
            bottom_right,
            opts,
        );

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
        Renderer.drawQuad(
            generics,
            sort_extras,
            x + top_left_w,
            y,
            w - top_left_w - top_right_w,
            top_center.texHRaw(),
            top_center,
            opts,
        );

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
        Renderer.drawQuad(
            generics,
            sort_extras,
            x + bottom_left_w,
            y + (h - bottom_center_h),
            w - bottom_left_w - bottom_right_w,
            bottom_center_h,
            bottom_center,
            opts,
        );

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
        Renderer.drawQuad(
            generics,
            sort_extras,
            x + top_left_w,
            y + top_left_h,
            w - top_left_w - top_right_w,
            h - top_left_h - bottom_left_h,
            middle_center,
            opts,
        );

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
        Renderer.drawQuad(
            generics,
            sort_extras,
            x,
            y + top_left_h,
            middle_left.texWRaw(),
            h - top_left_h - bottom_left_h,
            middle_left,
            opts,
        );

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
        Renderer.drawQuad(
            generics,
            sort_extras,
            x + (w - middle_right_w),
            y + top_left_h,
            middle_right_w,
            h - top_left_h - bottom_left_h,
            middle_right,
            opts,
        );
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

    pub fn draw(
        self: NormalImageData,
        generics: *std.ArrayList(Renderer.GenericData),
        sort_extras: *std.ArrayList(f32),
        x: f32,
        y: f32,
        scissor_override: ?ScissorRect,
    ) void {
        const opts: QuadOptions = .{
            .alpha_mult = self.alpha,
            .scissor = if (scissor_override) |s| s else self.scissor,
            .color = self.color,
            .color_intensity = self.color_intensity,
        };
        Renderer.drawQuad(generics, sort_extras, x, y, self.texWRaw(), self.texHRaw(), self.atlas_data, opts);
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

    pub fn draw(
        self: ImageData,
        generics: *std.ArrayList(Renderer.GenericData),
        sort_extras: *std.ArrayList(f32),
        x: f32,
        y: f32,
        scissor_override: ScissorRect,
    ) void {
        const scissor = if (scissor_override.isDefault()) null else scissor_override;
        switch (self) {
            .nine_slice => |nine_slice| nine_slice.draw(generics, sort_extras, x, y, scissor),
            .normal => |normal| normal.draw(generics, sort_extras, x, y, scissor),
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
pub const ScissorRect = struct {
    pub const dont_scissor = -1.0;

    min_x: f32 = dont_scissor,
    max_x: f32 = dont_scissor,
    min_y: f32 = dont_scissor,
    max_y: f32 = dont_scissor,

    pub fn isDefault(self: ScissorRect) bool {
        return !(self.min_x != dont_scissor or
            self.max_x != dont_scissor or
            self.min_y != dont_scissor or
            self.max_y != dont_scissor);
    }
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

    try systems.elements.append(main.allocator, @unionInit(UiElement, field_name, elem));
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

    if (systems.hover_target != null and
        systems.hover_target.? == tag.? and
        self == @field(systems.hover_target.?, field_name))
        systems.hover_target = null;

    for (systems.elements.items, 0..) |element, i|
        _ = if (element == tag.? and @field(element, field_name) == self)
            systems.elements.orderedRemove(i);

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
