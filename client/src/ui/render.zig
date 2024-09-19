const std = @import("std");
const element = @import("element.zig");
const render = @import("../render.zig");
const map = @import("../game/map.zig");
const assets = @import("../assets.zig");
const ui_systems = @import("systems.zig");
const gpu = @import("zgpu");
const main = @import("../main.zig");

fn drawNineSlice(x: f32, y: f32, image_data: element.NineSliceImageData) void {
    var opts: render.QuadOptions = .{
        .alpha_mult = image_data.alpha,
        .color = image_data.color,
        .color_intensity = image_data.color_intensity,
        .scissor = image_data.scissor,
    };

    const w = image_data.w;
    const h = image_data.h;

    const top_left = image_data.topLeft();
    const top_left_w = top_left.texWRaw();
    const top_left_h = top_left.texHRaw();
    render.drawQuad(x, y, top_left_w, top_left_h, top_left, opts);

    const top_right = image_data.topRight();
    const top_right_w = top_right.texWRaw();
    if (image_data.scissor.min_x != element.ScissorRect.dont_scissor)
        opts.scissor.min_x = image_data.scissor.min_x - (w - top_right_w);
    if (image_data.scissor.max_x != element.ScissorRect.dont_scissor)
        opts.scissor.max_x = image_data.scissor.max_x - (w - top_right_w);
    render.drawQuad(x + (w - top_right_w), y, top_right_w, top_right.texHRaw(), top_right, opts);

    const bottom_left = image_data.bottomLeft();
    const bottom_left_w = bottom_left.texWRaw();
    const bottom_left_h = bottom_left.texHRaw();
    opts.scissor.min_x = image_data.scissor.min_x;
    opts.scissor.max_x = image_data.scissor.max_x;
    if (image_data.scissor.min_y != element.ScissorRect.dont_scissor)
        opts.scissor.min_y = image_data.scissor.min_y - (h - bottom_left_h);
    if (image_data.scissor.max_y != element.ScissorRect.dont_scissor)
        opts.scissor.max_y = image_data.scissor.max_y - (h - bottom_left_h);
    render.drawQuad(x, y + (h - bottom_left_h), bottom_left_w, bottom_left_h, bottom_left, opts);

    const bottom_right = image_data.bottomRight();
    const bottom_right_w = bottom_right.texWRaw();
    const bottom_right_h = bottom_right.texHRaw();
    opts.scissor.min_x = if (image_data.scissor.min_x != element.ScissorRect.dont_scissor)
        image_data.scissor.min_x - (w - top_right_w)
    else
        element.ScissorRect.dont_scissor;
    opts.scissor.max_x = if (image_data.scissor.max_x != element.ScissorRect.dont_scissor)
        image_data.scissor.max_x - (w - top_right_w)
    else
        element.ScissorRect.dont_scissor;
    opts.scissor.min_y = if (image_data.scissor.min_y != element.ScissorRect.dont_scissor)
        image_data.scissor.min_y - (h - bottom_left_h)
    else
        element.ScissorRect.dont_scissor;
    opts.scissor.max_y = if (image_data.scissor.max_y != element.ScissorRect.dont_scissor)
        image_data.scissor.max_y - (h - bottom_left_h)
    else
        element.ScissorRect.dont_scissor;
    render.drawQuad(x + (w - bottom_right_w), y + (h - bottom_right_h), bottom_right_w, bottom_right_h, bottom_right, opts);

    const top_center = image_data.topCenter();
    opts.scissor.min_x = if (image_data.scissor.min_x != element.ScissorRect.dont_scissor)
        image_data.scissor.min_x - top_left_w
    else
        element.ScissorRect.dont_scissor;
    opts.scissor.max_x = if (image_data.scissor.max_x != element.ScissorRect.dont_scissor)
        image_data.scissor.max_x - top_left_w
    else
        element.ScissorRect.dont_scissor;
    opts.scissor.min_y = image_data.scissor.min_y;
    opts.scissor.max_y = image_data.scissor.max_y;
    render.drawQuad(x + top_left_w, y, w - top_left_w - top_right_w, top_center.texHRaw(), top_center, opts);

    const bottom_center = image_data.bottomCenter();
    const bottom_center_h = bottom_center.texHRaw();
    opts.scissor.min_x = if (image_data.scissor.min_x != element.ScissorRect.dont_scissor)
        image_data.scissor.min_x - bottom_left_w
    else
        element.ScissorRect.dont_scissor;
    opts.scissor.max_x = if (image_data.scissor.max_x != element.ScissorRect.dont_scissor)
        image_data.scissor.max_x - bottom_left_w
    else
        element.ScissorRect.dont_scissor;
    opts.scissor.min_y = if (image_data.scissor.min_y != element.ScissorRect.dont_scissor)
        image_data.scissor.min_y - (h - bottom_center_h)
    else
        element.ScissorRect.dont_scissor;
    opts.scissor.max_y = if (image_data.scissor.max_y != element.ScissorRect.dont_scissor)
        image_data.scissor.max_y - (h - bottom_center_h)
    else
        element.ScissorRect.dont_scissor;
    render.drawQuad(x + bottom_left_w, y + (h - bottom_center_h), w - bottom_left_w - bottom_right_w, bottom_center_h, bottom_center, opts);

    const middle_center = image_data.middleCenter();
    opts.scissor.min_x = if (image_data.scissor.min_x != element.ScissorRect.dont_scissor)
        image_data.scissor.min_x - top_left_w
    else
        element.ScissorRect.dont_scissor;
    opts.scissor.max_x = if (image_data.scissor.max_x != element.ScissorRect.dont_scissor)
        image_data.scissor.max_x - top_left_w
    else
        element.ScissorRect.dont_scissor;
    opts.scissor.min_y = if (image_data.scissor.min_y != element.ScissorRect.dont_scissor)
        image_data.scissor.min_y - top_left_h
    else
        element.ScissorRect.dont_scissor;
    opts.scissor.max_y = if (image_data.scissor.max_y != element.ScissorRect.dont_scissor)
        image_data.scissor.max_y - top_left_h
    else
        element.ScissorRect.dont_scissor;
    render.drawQuad(x + top_left_w, y + top_left_h, w - top_left_w - top_right_w, h - top_left_h - bottom_left_h, middle_center, opts);

    const middle_left = image_data.middleLeft();
    opts.scissor.min_x = image_data.scissor.min_x;
    opts.scissor.max_x = image_data.scissor.max_x;
    opts.scissor.min_y = if (image_data.scissor.min_y != element.ScissorRect.dont_scissor)
        image_data.scissor.min_y - top_left_h
    else
        element.ScissorRect.dont_scissor;
    opts.scissor.max_y = if (image_data.scissor.max_y != element.ScissorRect.dont_scissor)
        image_data.scissor.max_y - top_left_h
    else
        element.ScissorRect.dont_scissor;
    render.drawQuad(x, y + top_left_h, middle_left.texWRaw(), h - top_left_h - bottom_left_h, middle_left, opts);

    const middle_right = image_data.middleRight();
    const middle_right_w = middle_right.texWRaw();
    opts.scissor.min_x = if (image_data.scissor.min_x != element.ScissorRect.dont_scissor)
        image_data.scissor.min_x - (w - middle_right_w)
    else
        element.ScissorRect.dont_scissor;
    opts.scissor.max_x = if (image_data.scissor.max_x != element.ScissorRect.dont_scissor)
        image_data.scissor.max_x - (w - middle_right_w)
    else
        element.ScissorRect.dont_scissor;
    opts.scissor.min_y = if (image_data.scissor.min_y != element.ScissorRect.dont_scissor)
        image_data.scissor.min_y - top_left_h
    else
        element.ScissorRect.dont_scissor;
    opts.scissor.max_y = if (image_data.scissor.max_y != element.ScissorRect.dont_scissor)
        image_data.scissor.max_y - top_left_h
    else
        element.ScissorRect.dont_scissor;
    render.drawQuad(x + (w - middle_right_w), y + top_left_h, middle_right_w, h - top_left_h - bottom_left_h, middle_right, opts);
}

fn drawImageData(x: f32, y: f32, image_data: element.ImageData, scissor: element.ScissorRect) void {
    switch (image_data) {
        .nine_slice => |nine_slice| drawNineSlice(x, y, nine_slice),
        .normal => |normal| {
            const opts: render.QuadOptions = .{
                .alpha_mult = normal.alpha,
                .scissor = scissor,
                .color = normal.color,
                .color_intensity = normal.color_intensity,
                .shadow_texel_mult = if (normal.glow) 2.0 / @max(normal.scale_x, normal.scale_y) else 0.0,
            };
            render.drawQuad(
                x,
                y,
                normal.texWRaw(),
                normal.texHRaw(),
                normal.atlas_data,
                opts,
            );
        },
    }
}

fn drawImage(image: *element.Image, cam_data: render.CameraData, x_offset: f32, y_offset: f32) void {
    if (!image.visible) return;

    drawImageData(image.x + x_offset, image.y + y_offset, image.image_data, image.scissor);

    if (image.is_minimap_decor) {
        const fw: f32 = @floatFromInt(map.info.width);
        const fh: f32 = @floatFromInt(map.info.height);
        const fminimap_w: f32 = @floatFromInt(map.minimap.width);
        const fminimap_h: f32 = @floatFromInt(map.minimap.height);
        const zoom = cam_data.minimap_zoom;
        const uv_size = [_]f32{ fw / zoom / fminimap_w, fh / zoom / fminimap_h };
        render.generics.append(main.allocator, .{
            .render_type = .minimap,
            .pos = [_]f32{
                image.x + image.minimap_offset_x + x_offset + assets.padding,
                image.y + image.minimap_offset_y + y_offset + assets.padding,
            },
            .size = [_]f32{ image.minimap_width, image.minimap_height },
            .uv = [_]f32{ cam_data.x / fminimap_w - uv_size[0] / 2.0, cam_data.y / fminimap_h - uv_size[1] / 2.0 },
            .uv_size = uv_size,
        }) catch @panic("OOM");

        const player_icon = assets.minimap_icons[0];
        const scale = 2.0;
        const player_icon_w = player_icon.texWRaw() * scale;
        const player_icon_h = player_icon.texHRaw() * scale;
        render.drawQuad(
            image.x + image.minimap_offset_x + x_offset + (image.minimap_width - player_icon_w) / 2.0,
            image.y + image.minimap_offset_y + y_offset + (image.minimap_height - player_icon_h) / 2.0,
            player_icon_w,
            player_icon_h,
            player_icon,
            .{ .shadow_texel_mult = 0.5, .rotation = -cam_data.angle },
        );
    }
}

fn drawItem(item: *element.Item, x_offset: f32, y_offset: f32) void {
    if (!item.visible) return;

    if (item.background_image_data) |background_image_data| {
        drawImageData(item.background_x + x_offset, item.background_y + y_offset, background_image_data, item.scissor);
    }

    drawImageData(item.x + x_offset, item.y + y_offset, item.image_data, item.scissor);
}

fn drawBar(bar: *element.Bar, x_offset: f32, y_offset: f32) void {
    if (!bar.visible) return;

    const w, const h = switch (bar.image_data) {
        .nine_slice => |nine_slice| .{ nine_slice.w, nine_slice.h },
        .normal => |normal| .{ normal.texWRaw(), normal.texHRaw() },
    };

    drawImageData(bar.x + x_offset, bar.y + y_offset, bar.image_data, bar.scissor);
    render.drawText(
        bar.x + (w - bar.text_data.width) / 2 + x_offset,
        bar.y + (h - bar.text_data.height) / 2 + y_offset,
        1.0,
        &bar.text_data,
        .{},
    );
}

fn drawButton(button: *element.Button, x_offset: f32, y_offset: f32) void {
    if (!button.visible) return;

    drawImageData(button.x + x_offset, button.y + y_offset, button.image_data.current(button.state), button.scissor);
    if (button.text_data) |*text_data| render.drawText(
        button.x + x_offset,
        button.y + y_offset,
        1.0,
        text_data,
        button.scissor,
    );
}

fn drawCharacterBox(char_box: *element.CharacterBox, x_offset: f32, y_offset: f32) void {
    if (!char_box.visible) return;

    const image_data = char_box.image_data.current(char_box.state);
    const w, const h = switch (image_data) {
        .nine_slice => |nine_slice| .{ nine_slice.w, nine_slice.h },
        .normal => |normal| .{ normal.texWRaw(), normal.texHRaw() },
    };

    drawImageData(char_box.x + x_offset, char_box.y + y_offset, image_data, char_box.scissor);
    if (char_box.text_data) |*text_data| render.drawText(
        char_box.x + (w - text_data.width) / 2 + x_offset,
        char_box.y + (h - text_data.height) / 2 + y_offset,
        1.0,
        text_data,
        char_box.scissor,
    );
}

fn drawInputField(input_field: *element.Input, x_offset: f32, y_offset: f32, time: i64) void {
    if (!input_field.visible) return;

    drawImageData(input_field.x + x_offset, input_field.y + y_offset, input_field.image_data.current(input_field.state), input_field.scissor);

    const text_x = input_field.x + input_field.text_inlay_x + assets.padding + x_offset + input_field.x_offset;
    const text_y = input_field.y + input_field.text_inlay_y + assets.padding + y_offset;
    render.drawText(
        text_x,
        text_y,
        1.0,
        &input_field.text_data,
        input_field.scissor,
    );

    const flash_delay = 500 * std.time.us_per_ms;
    if (input_field.last_input != -1 and (time - input_field.last_input < flash_delay or @mod(@divFloor(time, flash_delay), 2) == 0)) {
        const cursor_x = @floor(text_x + input_field.text_data.width);
        drawImageData(cursor_x, text_y, input_field.cursor_image_data, input_field.scissor);
    }
}

fn drawToggle(toggle: *element.Toggle, x_offset: f32, y_offset: f32) void {
    if (!toggle.visible) return;

    const image_data = if (toggle.toggled.*)
        toggle.on_image_data.current(toggle.state)
    else
        toggle.off_image_data.current(toggle.state);
    const w, const h = switch (image_data) {
        .nine_slice => |nine_slice| .{ nine_slice.w, nine_slice.h },
        .normal => |normal| .{ normal.texWRaw(), normal.texHRaw() },
    };

    drawImageData(toggle.x + x_offset, toggle.y + y_offset, image_data, toggle.scissor);

    const pad = 5;
    if (toggle.text_data) |*text_data| render.drawText(
        toggle.x + w + pad + x_offset,
        toggle.y + (h - text_data.height) / 2 + y_offset,
        1.0,
        text_data,
        toggle.scissor,
    );
}

fn drawKeyMapper(key_mapper: *element.KeyMapper, x_offset: f32, y_offset: f32) void {
    if (!key_mapper.visible) return;

    const image_data = key_mapper.image_data.current(key_mapper.state);
    const w, const h = switch (image_data) {
        .nine_slice => |nine_slice| .{ nine_slice.w, nine_slice.h },
        .normal => |normal| .{ normal.texWRaw(), normal.texHRaw() },
    };

    render.drawQuad(
        key_mapper.x + x_offset,
        key_mapper.y + y_offset,
        w,
        h,
        assets.getKeyTexture(key_mapper.settings_button.*),
        .{},
    );

    const pad = 5;
    if (key_mapper.title_text_data) |*text_data| render.drawText(
        key_mapper.x + w + pad + x_offset,
        key_mapper.y + (h - text_data.height) / 2 + y_offset,
        1.0,
        text_data,
        key_mapper.scissor,
    );
}

fn drawSlider(slider: *element.Slider, x_offset: f32, y_offset: f32) void {
    if (!slider.visible) return;

    drawImageData(slider.x + x_offset, slider.y + y_offset, slider.decor_image_data, slider.scissor);

    const knob_image_data = slider.knob_image_data.current(slider.state);
    const knob_x = slider.x + slider.knob_x + x_offset;
    const knob_y = slider.y + slider.knob_y + y_offset;
    const knob_w, const knob_h = switch (knob_image_data) {
        .nine_slice => |nine_slice| .{ nine_slice.w, nine_slice.h },
        .normal => |normal| .{ normal.texWRaw(), normal.texHRaw() },
    };
    drawImageData(knob_x, knob_y, knob_image_data, slider.scissor);

    if (slider.title_text_data) |*text_data| render.drawText(
        slider.x + x_offset,
        slider.y + y_offset - slider.title_offset,
        1.0,
        text_data,
        slider.scissor,
    );

    if (slider.value_text_data) |*text_data| render.drawText(
        knob_x + if (slider.vertical) knob_w else 0,
        knob_y + if (slider.vertical) 0 else knob_h,
        1.0,
        text_data,
        slider.scissor,
    );
}

fn drawDropdown(dropdown: *element.Dropdown, x_offset: f32, y_offset: f32) void {
    if (!dropdown.visible) return;

    const base_x = dropdown.x + x_offset;
    const base_y = dropdown.y + y_offset;
    const title_w, const title_h = switch (dropdown.title_data) {
        .nine_slice => |nine_slice| .{ nine_slice.w, nine_slice.h },
        .normal => |normal| .{ normal.texWRaw(), normal.texHRaw() },
    };
    drawImageData(base_x, base_y, dropdown.title_data, dropdown.scissor);

    render.drawText(base_x, base_y, 1.0, &dropdown.title_text, dropdown.scissor);

    const toggled = dropdown.toggled;
    const button_image_data = (if (toggled) dropdown.button_data_extended else dropdown.button_data_collapsed).current(dropdown.button_state);
    drawImageData(base_x + title_w, base_y, button_image_data, dropdown.scissor);

    if (toggled) drawImageData(base_x, base_y + title_h, dropdown.background_data, dropdown.scissor);
}

fn drawElement(elem: element.UiElement, cam_data: render.CameraData, x_offset: f32, y_offset: f32, time: i64) void {
    switch (elem) {
        .scrollable_container => |scrollable_container| if (scrollable_container.visible) {
            drawElement(.{ .container = scrollable_container.container }, cam_data, x_offset, y_offset, time);
            drawElement(.{ .slider = scrollable_container.scroll_bar }, cam_data, x_offset, y_offset, time);
            drawElement(.{ .image = scrollable_container.scroll_bar_decor }, cam_data, x_offset, y_offset, time);
        },
        .container => |container| if (container.visible) {
            for (container.elements.items) |cont_elem| drawElement(cont_elem, cam_data, x_offset + container.x, y_offset + container.y, time);
        },
        .image => |image| drawImage(image, cam_data, x_offset, y_offset),
        .menu_bg => |menu_bg| if (menu_bg.visible) {
            render.generics.append(main.allocator, .{
                .render_type = .menu_bg,
                .pos = [_]f32{ menu_bg.x + x_offset, menu_bg.y + y_offset },
                .size = [_]f32{ menu_bg.w, menu_bg.h },
                .uv = [_]f32{ 0.0, 0.0 },
                .uv_size = [_]f32{ 1.0, 1.0 },
            }) catch @panic("OOM");
        },
        .item => |item| drawItem(item, x_offset, y_offset),
        .bar => |bar| drawBar(bar, x_offset, y_offset),
        .button => |button| drawButton(button, x_offset, y_offset),
        .char_box => |char_box| drawCharacterBox(char_box, x_offset, y_offset),
        .text => |text| if (text.visible)
            render.drawText(text.x + x_offset, text.y + y_offset, 1.0, &text.text_data, text.scissor),
        .input_field => |input_field| drawInputField(input_field, x_offset, y_offset, time),
        .toggle => |toggle| drawToggle(toggle, x_offset, y_offset),
        .key_mapper => |key_mapper| drawKeyMapper(key_mapper, x_offset, y_offset),
        .slider => |slider| drawSlider(slider, x_offset, y_offset),
        .dropdown => |dropdown| {
            const toggled = dropdown.toggled and dropdown.container.visible;
            if (toggled) dropdown.lock.lock();
            defer if (toggled) dropdown.lock.unlock();

            drawDropdown(dropdown, x_offset, y_offset);
            if (toggled) drawElement(.{ .scrollable_container = dropdown.container }, cam_data, x_offset, y_offset, time);
        },
        .dropdown_container => |dropdown_container| {
            drawImageData(
                dropdown_container.x + x_offset,
                dropdown_container.y + y_offset,
                dropdown_container.background_data.current(dropdown_container.state),
                dropdown_container.scissor,
            );

            drawElement(
                .{ .container = &dropdown_container.container },
                cam_data,
                dropdown_container.x + x_offset,
                dropdown_container.y + y_offset,
                time,
            );
        },
    }
}

pub fn drawElements(cam_data: render.CameraData, time: i64) void {
    ui_systems.ui_lock.lock();
    defer ui_systems.ui_lock.unlock();
    for (ui_systems.elements.items) |elem| drawElement(elem, cam_data, 0, 0, time);
}
