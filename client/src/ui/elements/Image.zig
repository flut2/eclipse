const element = @import("element.zig");
const tooltip = @import("../tooltips/tooltip.zig");
const assets = @import("../../assets.zig");
const map = @import("../../game/map.zig");
const game_data = @import("shared").game_data;
const main = @import("../../main.zig");
const render = @import("../../render.zig");

const Image = @This();
const ElementBase = element.ElementBase;

base: ElementBase,
image_data: element.ImageData,
tooltip_text: ?element.TextData = null,
ability_props: ?game_data.AbilityData = null,
// hack
is_minimap_decor: bool = false,
minimap_offset_x: f32 = 0.0,
minimap_offset_y: f32 = 0.0,
minimap_width: f32 = 0.0,
minimap_height: f32 = 0.0,

pub fn mouseMove(self: *Image, x: f32, y: f32, x_offset: f32, y_offset: f32) bool {
    if (!self.base.visible) return false;

    const in_bounds = element.intersects(self, x, y);
    if (in_bounds) {
        if (self.ability_props) |props| {
            tooltip.switchTooltip(.ability, .{
                .x = x + x_offset,
                .y = y + y_offset,
                .props = props,
            });
            return true;
        } else if (self.tooltip_text) |text| {
            tooltip.switchTooltip(.text, .{
                .x = x + x_offset,
                .y = y + y_offset,
                .text_data = text,
            });
            return true;
        }
    }

    return !(self.base.event_policy.pass_move or !in_bounds);
}

pub fn init(self: *Image) void {
    if (self.tooltip_text) |*text_data| {
        text_data.lock.lock();
        defer text_data.lock.unlock();
        text_data.recalculateAttributes();
    }
}

pub fn deinit(self: *Image) void {
    if (self.tooltip_text) |*text_data| text_data.deinit();
}

pub fn draw(self: Image, cam_data: render.CameraData, x_offset: f32, y_offset: f32, _: i64) void {
    if (!self.base.visible) return;

    self.image_data.draw(self.base.x + x_offset, self.base.y + y_offset, self.base.scissor);

    if (self.is_minimap_decor) {
        const fw: f32 = @floatFromInt(map.info.width);
        const fh: f32 = @floatFromInt(map.info.height);
        const fminimap_w: f32 = @floatFromInt(map.minimap.width);
        const fminimap_h: f32 = @floatFromInt(map.minimap.height);
        const zoom = cam_data.minimap_zoom;
        const uv_size = [_]f32{ fw / zoom / fminimap_w, fh / zoom / fminimap_h };
        render.generics.append(main.allocator, .{
            .render_type = .minimap,
            .pos = [_]f32{
                self.base.x + self.minimap_offset_x + x_offset + assets.padding,
                self.base.y + self.minimap_offset_y + y_offset + assets.padding,
            },
            .size = [_]f32{ self.minimap_width, self.minimap_height },
            .uv = [_]f32{ cam_data.x / fminimap_w - uv_size[0] / 2.0, cam_data.y / fminimap_h - uv_size[1] / 2.0 },
            .uv_size = uv_size,
        }) catch @panic("OOM");

        const player_icon = assets.minimap_icons[0];
        const scale = 2.0;
        const player_icon_w = player_icon.texWRaw() * scale;
        const player_icon_h = player_icon.texHRaw() * scale;
        render.drawQuad(
            self.base.x + self.minimap_offset_x + x_offset + (self.minimap_width - player_icon_w) / 2.0,
            self.base.y + self.minimap_offset_y + y_offset + (self.minimap_height - player_icon_h) / 2.0,
            player_icon_w,
            player_icon_h,
            player_icon,
            .{ .shadow_texel_mult = 0.5, .scissor = self.base.scissor },
        );
    }
}

pub fn width(self: Image) f32 {
    return switch (self.image_data) {
        .nine_slice => |nine_slice| nine_slice.w,
        .normal => |image_data| image_data.width(),
    };
}

pub fn height(self: Image) f32 {
    return switch (self.image_data) {
        .nine_slice => |nine_slice| nine_slice.h,
        .normal => |image_data| image_data.height(),
    };
}

pub fn texWRaw(self: Image) f32 {
    return switch (self.image_data) {
        .nine_slice => |nine_slice| nine_slice.w,
        .normal => |image_data| image_data.texWRaw(),
    };
}

pub fn texHRaw(self: Image) f32 {
    return switch (self.image_data) {
        .nine_slice => |nine_slice| nine_slice.h,
        .normal => |image_data| image_data.texHRaw(),
    };
}
