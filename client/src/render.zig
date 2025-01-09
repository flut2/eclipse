const std = @import("std");

const glfw = @import("zglfw");
const gpu = @import("zgpu");
const shared = @import("shared");
const game_data = shared.game_data;
const utils = shared.utils;
const zstbi = @import("zstbi");

const assets = @import("assets.zig");
const Ally = @import("game/Ally.zig");
const Container = @import("game/Container.zig");
const Enemy = @import("game/Enemy.zig");
const Entity = @import("game/Entity.zig");
const map = @import("game/map.zig");
const Particle = @import("game/particles.zig").Particle;
const Player = @import("game/Player.zig");
const Portal = @import("game/Portal.zig");
const Projectile = @import("game/Projectile.zig");
const Purchasable = @import("game/Purchasable.zig");
const Square = @import("game/Square.zig");
const main = @import("main.zig");
const px_per_tile = @import("Camera.zig").px_per_tile;
const element = @import("ui/elements/element.zig");
const ui_systems = @import("ui/systems.zig");

pub const CameraData = struct {
    minimap_zoom: f32,
    scale: f32,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    min_x: u32,
    max_x: u32,
    min_y: u32,
    max_y: u32,
    clip_scale: [2]f32,
    clip_offset: [2]f32,
    cam_offset_px: [2]f32,

    pub fn worldToScreen(self: CameraData, x_in: f32, y_in: f32) struct { x: f32, y: f32 } {
        return .{
            .x = x_in * px_per_tile * self.scale - self.cam_offset_px[0] - self.clip_offset[0],
            .y = y_in * px_per_tile * self.scale - self.cam_offset_px[1] - self.clip_offset[1],
        };
    }

    pub fn visibleInCamera(self: CameraData, x_in: f32, y_in: f32) bool {
        if (std.math.isNan(x_in) or
            std.math.isNan(y_in) or
            x_in < 0 or
            y_in < 0 or
            x_in > std.math.maxInt(u32) or
            y_in > std.math.maxInt(u32))
            return false;

        const floor_x: u32 = @intFromFloat(@floor(x_in));
        const floor_y: u32 = @intFromFloat(@floor(y_in));
        return !(floor_x < self.min_x or floor_x > self.max_x or floor_y < self.min_y or floor_y > self.max_y);
    }
};

pub const LightData = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    color: u32,
    intensity: f32,
};

pub const QuadOptions = struct {
    rotation: f32 = 0.0,
    color: u32 = 0x000000,
    color_intensity: f32 = 0.0,
    alpha_mult: f32 = 1.0,
    shadow_texel_mult: f32 = 0.0,
    shadow_color: u32 = 0x000000,
    scissor: element.ScissorRect = .{},
    sort_extra: f32 = 0,
    render_type_override: ?RenderType = null,
};

pub const RenderType = enum(u32) {
    quad = 0,
    ui_quad = 1,
    minimap = 2,
    menu_bg = 3,
    text_normal = 4,
    text_drop_shadow = 5,
};

pub const GenericData = extern struct {
    render_type: RenderType = .quad,
    text_type: element.TextType = .bold,
    rotation: f32 = 0.0,
    text_dist_factor: f32 = 0.0,
    shadow_color: u32 = 0,
    alpha_mult: f32 = 1.0,
    outline_color: u32 = 0,
    outline_width: f32 = 0.0,
    base_color: u32 = 0,
    color_intensity: f32 = 0.0,
    pos: [2]f32 = .{ 0.0, 0.0 },
    size: [2]f32 = .{ 1.0, 1.0 },
    uv: [2]f32 = .{ -1.0, -1.0 },
    uv_size: [2]f32 = .{ 0.0, 0.0 },
    shadow_texel_size: [2]f32 = .{ 0.0, 0.0 },
    scissor: [4]f32 = .{ 0.0, 1.0, 0.0, 1.0 }, // min x, max x, min y, max y, in tex coord space
};

pub const GroundData = extern struct {
    pos: [2]f32,
    uv: [2]f32,
    offset_uv: [2]f32,
    left_blend_uv: [2]f32,
    top_blend_uv: [2]f32,
    right_blend_uv: [2]f32,
    bottom_blend_uv: [2]f32,
    rotation: f32,
    padding: f32 = 0.0,
};

pub const GenericUniformData = extern struct {
    clip_scale: [2]f32,
    clip_offset: [2]f32,
};

pub const GroundUniformData = extern struct {
    padding: f32 = 0,
    scale: f32,
    left_mask_uv: [2]f32,
    top_mask_uv: [2]f32,
    right_mask_uv: [2]f32,
    bottom_mask_uv: [2]f32,
    clip_scale: [2]f32,
    clip_offset: [2]f32,
    atlas_size: [2]f32,
};

comptime {
    for (.{ GroundData, GroundUniformData, GenericData, GenericUniformData }) |T| {
        const missing_bytes = @mod(@sizeOf(T), 16);
        if (missing_bytes != 0)
            @compileError(std.fmt.comptimePrint("All GPU-facing structs must have byte lengths with multiples of 16, please add padding to {s}, pad bytes missing: {}", .{
                @typeName(T),
                missing_bytes,
            }));
    }
}

const TextureWithView = struct {
    texture: gpu.wgpu.Texture,
    view: gpu.wgpu.TextureView,

    pub fn release(self: TextureWithView) void {
        self.texture.release();
        self.view.release();
    }
};

const SizedBuffer = struct {
    buffer: gpu.wgpu.Buffer,
    size: usize,

    pub const empty: SizedBuffer = .{
        .buffer = undefined,
        .size = 0,
    };

    pub fn release(self: SizedBuffer) void {
        self.buffer.release();
    }
};

pub const ground_size = 100000;
pub const generic_size = 100000;
pub const ui_size = 5000;

pub var nearest_sampler: gpu.wgpu.Sampler = undefined;
pub var linear_sampler: gpu.wgpu.Sampler = undefined;

pub var generic_pipeline: gpu.wgpu.RenderPipeline = undefined;
pub var generic_bind_group: gpu.wgpu.BindGroup = undefined;
pub var ui_bind_group: gpu.wgpu.BindGroup = undefined;
pub var single_tex_bind_group: gpu.wgpu.BindGroup = undefined;
pub var ground_pipeline: gpu.wgpu.RenderPipeline = undefined;
pub var ground_bind_group: gpu.wgpu.BindGroup = undefined;

pub var generic_buffer: gpu.wgpu.Buffer = undefined;
pub var generic_uniforms: gpu.wgpu.Buffer = undefined;
pub var ui_buffer: gpu.wgpu.Buffer = undefined;
pub var ground_buffer: gpu.wgpu.Buffer = undefined;
pub var ground_uniforms: gpu.wgpu.Buffer = undefined;

pub var bold_text: TextureWithView = undefined;
pub var bold_italic_text: TextureWithView = undefined;
pub var medium_text: TextureWithView = undefined;
pub var medium_italic_text: TextureWithView = undefined;
pub var default: TextureWithView = undefined;
pub var ui: TextureWithView = undefined;
pub var minimap: TextureWithView = undefined;
pub var menu_bg: TextureWithView = undefined;

pub var condition_rects: [@bitSizeOf(utils.Condition)][]const assets.AtlasData = undefined;
pub var enter_text_data: element.TextData = undefined;
pub var sort_extras: std.ArrayListUnmanaged(f32) = .empty;
pub var generics: std.ArrayListUnmanaged(GenericData) = .empty;
pub var grounds: std.ArrayListUnmanaged(GroundData) = .empty;
pub var lights: std.ArrayListUnmanaged(LightData) = .empty;

fn createTexture(ctx: *gpu.GraphicsContext, tex: *TextureWithView, img: zstbi.Image) void {
    tex.texture = ctx.device.createTexture(.{
        .usage = .{ .texture_binding = true, .copy_dst = true },
        .size = .{ .width = img.width, .height = img.height, .depth_or_array_layers = 1 },
        .format = .rgba8_unorm,
        .mip_level_count = 1,
    });
    tex.view = tex.texture.createView(.{});

    ctx.queue.writeTexture(
        .{ .texture = tex.texture },
        .{ .bytes_per_row = img.bytes_per_row, .rows_per_image = img.height },
        .{ .width = img.width, .height = img.height },
        u8,
        img.data,
    );
}

fn groundBindGroupLayout(ctx: *gpu.GraphicsContext) gpu.wgpu.BindGroupLayout {
    return ctx.device.createBindGroupLayout(.{
        .entry_count = 4,
        .entries = &.{
            gpu.bufferEntry(0, .{ .vertex = true, .fragment = true }, .uniform, .false, 0),
            gpu.bufferEntry(1, .{ .vertex = true, .fragment = true }, .read_only_storage, .false, 0),
            gpu.samplerEntry(2, .{ .fragment = true }, .filtering),
            gpu.textureEntry(3, .{ .fragment = true }, .float, .tvdim_2d, .false),
        },
    });
}

fn genericBindGroupLayout(ctx: *gpu.GraphicsContext) gpu.wgpu.BindGroupLayout {
    return ctx.device.createBindGroupLayout(.{
        .entry_count = 10,
        .entries = &.{
            gpu.bufferEntry(0, .{ .vertex = true, .fragment = true }, .uniform, .false, 0),
            gpu.bufferEntry(1, .{ .vertex = true, .fragment = true }, .read_only_storage, .false, 0),
            gpu.samplerEntry(2, .{ .fragment = true }, .filtering),
            gpu.samplerEntry(3, .{ .fragment = true }, .filtering),
            gpu.textureEntry(4, .{ .fragment = true }, .float, .tvdim_2d, .false),
            gpu.textureEntry(5, .{ .fragment = true }, .float, .tvdim_2d, .false),
            gpu.textureEntry(6, .{ .fragment = true }, .float, .tvdim_2d, .false),
            gpu.textureEntry(7, .{ .fragment = true }, .float, .tvdim_2d, .false),
            gpu.textureEntry(8, .{ .fragment = true }, .float, .tvdim_2d, .false),
            gpu.textureEntry(9, .{ .fragment = true }, .float, .tvdim_2d, .false),
        },
    });
}

fn singleTexBindGroupLayout(ctx: *gpu.GraphicsContext) gpu.wgpu.BindGroupLayout {
    return ctx.device.createBindGroupLayout(.{
        .entry_count = 2,
        .entries = &.{
            gpu.textureEntry(0, .{ .fragment = true }, .float, .tvdim_2d, .false),
            gpu.textureEntry(1, .{ .fragment = true }, .float, .tvdim_2d, .false),
        },
    });
}

fn createPipelines(ctx: *gpu.GraphicsContext) void {
    const ground_bind_group_layout = groundBindGroupLayout(ctx);
    defer ground_bind_group_layout.release();

    const generic_bind_group_layout = genericBindGroupLayout(ctx);
    defer generic_bind_group_layout.release();

    const single_tex_bind_group_layout = singleTexBindGroupLayout(ctx);
    defer single_tex_bind_group_layout.release();

    const generic_pipeline_layout = ctx.device.createPipelineLayout(.{
        .bind_group_layout_count = 2,
        .bind_group_layouts = &.{ generic_bind_group_layout, single_tex_bind_group_layout },
    });
    defer generic_pipeline_layout.release();

    const ground_pipeline_layout = ctx.device.createPipelineLayout(.{
        .bind_group_layout_count = 1,
        .bind_group_layouts = &.{ground_bind_group_layout},
    });
    defer ground_pipeline_layout.release();

    const ground_shader = gpu.createWgslShaderModule(ctx.device, @embedFile("shaders/ground.wgsl"), "Ground Shader");
    defer ground_shader.release();

    const generic_shader = gpu.createWgslShaderModule(ctx.device, @embedFile("shaders/generic.wgsl"), "Generic Shader");
    defer generic_shader.release();

    const generic_color_targets: []const gpu.wgpu.ColorTargetState = &.{.{
        .format = gpu.GraphicsContext.swapchain_format,
        .blend = &.{
            .color = .{ .src_factor = .one, .dst_factor = .one_minus_src_alpha },
            .alpha = .{ .src_factor = .one, .dst_factor = .one_minus_src_alpha },
        },
    }};
    const generic_pipeline_descriptor: gpu.wgpu.RenderPipelineDescriptor = .{
        .layout = generic_pipeline_layout,
        .vertex = .{
            .module = generic_shader,
            .entry_point = "vertexMain",
        },
        .primitive = .{
            .front_face = .cw,
            .cull_mode = .none,
            .topology = .triangle_list,
        },
        .fragment = &.{
            .module = generic_shader,
            .entry_point = "fragmentMain",
            .target_count = generic_color_targets.len,
            .targets = generic_color_targets.ptr,
        },
    };
    generic_pipeline = ctx.device.createRenderPipeline(generic_pipeline_descriptor);

    const ground_color_targets: []const gpu.wgpu.ColorTargetState = &.{.{ .format = gpu.GraphicsContext.swapchain_format }};
    const ground_pipeline_descriptor = gpu.wgpu.RenderPipelineDescriptor{
        .layout = ground_pipeline_layout,
        .vertex = .{
            .module = ground_shader,
            .entry_point = "vertexMain",
        },
        .primitive = .{
            .front_face = .cw,
            .cull_mode = .none,
            .topology = .triangle_list,
        },
        .fragment = &.{
            .module = ground_shader,
            .entry_point = "fragmentMain",
            .target_count = ground_color_targets.len,
            .targets = ground_color_targets.ptr,
        },
    };
    ground_pipeline = ctx.device.createRenderPipeline(ground_pipeline_descriptor);
}

pub fn deinit() void {
    for (condition_rects) |rects| main.allocator.free(rects);

    enter_text_data.deinit();
    sort_extras.deinit(main.allocator);
    generics.deinit(main.allocator);
    grounds.deinit(main.allocator);
    lights.deinit(main.allocator);

    generic_pipeline.release();
    generic_bind_group.release();
    ground_pipeline.release();
    ground_bind_group.release();

    generic_buffer.release();
    generic_uniforms.release();
    ground_buffer.release();
    ground_uniforms.release();

    bold_text.release();
    bold_italic_text.release();
    medium_text.release();
    medium_italic_text.release();
    default.release();
    ui.release();
    minimap.release();
    menu_bg.release();

    nearest_sampler.release();
    linear_sampler.release();
}

pub fn init(ctx: *gpu.GraphicsContext) !void {
    for (0..@bitSizeOf(utils.Condition)) |i| {
        const sheet_name = "conditions";
        const sheet_indices: []const u16 = switch (std.meta.intToEnum(utils.ConditionEnum, i) catch continue) {
            .weak => &.{5},
            .slowed => &.{7},
            .sick => &.{10},
            .speedy => &.{6},
            .bleeding => &.{2},
            .healing => &.{1},
            .damaging => &.{4},
            .invulnerable => &.{11},
            .armored => &.{3},
            .armor_broken => &.{9},
            .targeted => &.{8},
            .hidden, .invisible, .paralyzed, .stunned, .silenced => &.{},
        };

        const indices_len = sheet_indices.len;
        if (indices_len == 0) {
            condition_rects[i] = &.{};
            continue;
        }

        var rects = main.allocator.alloc(assets.AtlasData, indices_len) catch continue;
        for (0..indices_len) |j| {
            rects[j] = (assets.atlas_data.get(sheet_name) orelse std.debug.panic("Could not find sheet {s} for cond parsing", .{sheet_name}))[sheet_indices[j]];
        }

        condition_rects[i] = rects;
    }

    enter_text_data = .{
        .text = undefined,
        .text_type = .bold,
        .size = 12,
    };
    enter_text_data.setText("Enter");

    generic_buffer = ctx.device.createBuffer(.{
        .usage = .{ .copy_dst = true, .storage = true },
        .size = generic_size * @sizeOf(GenericData),
    });

    ui_buffer = ctx.device.createBuffer(.{
        .usage = .{ .copy_dst = true, .storage = true },
        .size = ui_size * @sizeOf(GenericData),
    });

    ground_buffer = ctx.device.createBuffer(.{
        .usage = .{ .copy_dst = true, .storage = true },
        .size = ground_size * @sizeOf(GroundData),
    });

    generic_uniforms = ctx.device.createBuffer(.{
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = @sizeOf(GenericUniformData),
    });

    ground_uniforms = ctx.device.createBuffer(.{
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = @sizeOf(GroundUniformData),
    });

    createTexture(ctx, &minimap, map.minimap);
    createTexture(ctx, &medium_text, assets.medium_atlas);
    createTexture(ctx, &medium_italic_text, assets.medium_italic_atlas);
    createTexture(ctx, &bold_text, assets.bold_atlas);
    createTexture(ctx, &bold_italic_text, assets.bold_italic_atlas);
    createTexture(ctx, &default, assets.atlas);
    createTexture(ctx, &ui, assets.ui_atlas);
    createTexture(ctx, &menu_bg, assets.menu_background);

    assets.medium_atlas.deinit();
    assets.medium_italic_atlas.deinit();
    assets.bold_atlas.deinit();
    assets.bold_italic_atlas.deinit();
    assets.atlas.deinit();
    assets.ui_atlas.deinit();
    assets.menu_background.deinit();

    nearest_sampler = ctx.device.createSampler(.{});
    linear_sampler = ctx.device.createSampler(.{ .min_filter = .linear, .mag_filter = .linear });

    const ground_bind_group_layout = groundBindGroupLayout(ctx);
    defer ground_bind_group_layout.release();

    const generic_bind_group_layout = genericBindGroupLayout(ctx);
    defer generic_bind_group_layout.release();

    const single_tex_bind_group_layout = singleTexBindGroupLayout(ctx);
    defer single_tex_bind_group_layout.release();

    ground_bind_group = ctx.device.createBindGroup(.{
        .layout = ground_bind_group_layout,
        .entry_count = 4,
        .entries = &.{
            .{ .binding = 0, .buffer = ground_uniforms, .size = @sizeOf(GroundUniformData) },
            .{ .binding = 1, .buffer = ground_buffer, .size = ground_size * @sizeOf(GroundData) },
            .{ .binding = 2, .sampler = nearest_sampler, .size = 0 },
            .{ .binding = 3, .texture_view = default.view, .size = 0 },
        },
    });

    generic_bind_group = ctx.device.createBindGroup(.{
        .layout = generic_bind_group_layout,
        .entry_count = 10,
        .entries = &.{
            .{ .binding = 0, .buffer = generic_uniforms, .size = @sizeOf(GenericUniformData) },
            .{ .binding = 1, .buffer = generic_buffer, .size = generic_size * @sizeOf(GenericData) },
            .{ .binding = 2, .sampler = nearest_sampler, .size = 0 },
            .{ .binding = 3, .sampler = linear_sampler, .size = 0 },
            .{ .binding = 4, .texture_view = default.view, .size = 0 },
            .{ .binding = 5, .texture_view = ui.view, .size = 0 },
            .{ .binding = 6, .texture_view = medium_text.view, .size = 0 },
            .{ .binding = 7, .texture_view = medium_italic_text.view, .size = 0 },
            .{ .binding = 8, .texture_view = bold_text.view, .size = 0 },
            .{ .binding = 9, .texture_view = bold_italic_text.view, .size = 0 },
        },
    });

    ui_bind_group = ctx.device.createBindGroup(.{
        .layout = generic_bind_group_layout,
        .entry_count = 10,
        .entries = &.{
            .{ .binding = 0, .buffer = generic_uniforms, .size = @sizeOf(GenericUniformData) },
            .{ .binding = 1, .buffer = ui_buffer, .size = ui_size * @sizeOf(GenericData) },
            .{ .binding = 2, .sampler = nearest_sampler, .size = 0 },
            .{ .binding = 3, .sampler = linear_sampler, .size = 0 },
            .{ .binding = 4, .texture_view = default.view, .size = 0 },
            .{ .binding = 5, .texture_view = ui.view, .size = 0 },
            .{ .binding = 6, .texture_view = medium_text.view, .size = 0 },
            .{ .binding = 7, .texture_view = medium_italic_text.view, .size = 0 },
            .{ .binding = 8, .texture_view = bold_text.view, .size = 0 },
            .{ .binding = 9, .texture_view = bold_italic_text.view, .size = 0 },
        },
    });

    single_tex_bind_group = ctx.device.createBindGroup(.{
        .layout = single_tex_bind_group_layout,
        .entry_count = 2,
        .entries = &.{
            .{ .binding = 0, .texture_view = minimap.view, .size = 0 },
            .{ .binding = 1, .texture_view = menu_bg.view, .size = 0 },
        },
    });

    createPipelines(ctx);
}

pub fn drawQuad(x: f32, y: f32, w: f32, h: f32, atlas_data: assets.AtlasData, opts: QuadOptions) void {
    const render_type: RenderType = if (opts.render_type_override) |rt| rt else switch (atlas_data.atlas_type) {
        .ui => .ui_quad,
        .base => .quad,
    };

    const shadow_texel_w = opts.shadow_texel_mult / atlas_data.atlas_type.width();
    const shadow_texel_h = opts.shadow_texel_mult / atlas_data.atlas_type.height();

    const uv_w_per_px = atlas_data.tex_w / w;
    const uv_h_per_px = atlas_data.tex_h / h;

    const dont_scissor = element.ScissorRect.dont_scissor;

    sort_extras.append(main.allocator, opts.sort_extra) catch main.oomPanic();
    generics.append(main.allocator, .{
        .render_type = render_type,
        .rotation = opts.rotation,
        .shadow_color = opts.shadow_color,
        .alpha_mult = opts.alpha_mult,
        .base_color = opts.color,
        .color_intensity = opts.color_intensity,
        .pos = .{ x, y },
        .size = .{ w, h },
        .uv = .{ atlas_data.tex_u, atlas_data.tex_v },
        .uv_size = .{ atlas_data.tex_w, atlas_data.tex_h },
        .shadow_texel_size = .{ shadow_texel_w, shadow_texel_h },
        .scissor = .{
            atlas_data.tex_u + if (opts.scissor.min_x == dont_scissor) 0 else opts.scissor.min_x * uv_w_per_px,
            atlas_data.tex_u + if (opts.scissor.max_x == dont_scissor) atlas_data.tex_w else opts.scissor.max_x * uv_w_per_px,
            atlas_data.tex_v + if (opts.scissor.min_y == dont_scissor) 0 else opts.scissor.min_y * uv_h_per_px,
            atlas_data.tex_v + if (opts.scissor.max_y == dont_scissor) atlas_data.tex_h else opts.scissor.max_y * uv_h_per_px,
        },
    }) catch main.oomPanic();
}

pub fn drawText(
    x: f32,
    y: f32,
    scale: f32,
    text_data: *element.TextData,
    scissor_override: element.ScissorRect,
) void {
    text_data.lock.lock();
    defer text_data.lock.unlock();

    if (text_data.line_widths == null or text_data.break_indices == null) return;

    var current_type = text_data.text_type;
    var current_font_data = switch (current_type) {
        .medium => assets.medium_data,
        .medium_italic => assets.medium_italic_data,
        .bold => assets.bold_data,
        .bold_italic => assets.bold_italic_data,
    };

    const size_scale = text_data.size / current_font_data.size * scale * (1.0 + current_font_data.padding * 2 / current_font_data.size);
    const start_line_height = current_font_data.line_height * current_font_data.size * size_scale;
    var line_height = start_line_height;

    const max_width_off = text_data.max_width == std.math.floatMax(f32);
    const max_height_off = text_data.max_height == std.math.floatMax(f32);

    const render_type: RenderType = if (text_data.shadow_texel_offset_mult != 0) .text_drop_shadow else .text_normal;

    const start_x = x;
    const start_y = y + line_height;
    const y_base = switch (text_data.vert_align) {
        .top => start_y,
        .middle => if (max_height_off) start_y else start_y + (text_data.max_height - text_data.height) / 2.0,
        .bottom => if (max_height_off) start_y else start_y + (text_data.max_height - text_data.height),
    };
    var line_idx: u16 = 1;
    var x_base = switch (text_data.hori_align) {
        .left => start_x,
        .middle => if (max_width_off) start_x else start_x + (text_data.max_width - text_data.line_widths.?.items[0]) / 2.0,
        .right => if (max_width_off) start_x else start_x + (text_data.max_width - text_data.line_widths.?.items[0]),
    };
    var x_pointer = x_base;
    var y_pointer = y_base;
    var current_color = text_data.color;
    var current_size = size_scale;
    var index_offset: u16 = 0;
    for (0..text_data.text.len) |i| {
        const offset_i = i + index_offset;
        if (offset_i >= text_data.text.len) return;

        var char = text_data.text[offset_i];
        specialChar: {
            if (!text_data.handle_special_chars) break :specialChar;

            if (char == '&') {
                const name_start = text_data.text[offset_i + 1 ..];
                const reset = "reset";
                if (text_data.text.len >= offset_i + 1 + reset.len and std.mem.eql(u8, name_start[0..reset.len], reset)) {
                    current_type = text_data.text_type;
                    current_font_data = switch (current_type) {
                        .medium => assets.medium_data,
                        .medium_italic => assets.medium_italic_data,
                        .bold => assets.bold_data,
                        .bold_italic => assets.bold_italic_data,
                    };
                    current_color = text_data.color;
                    current_size = size_scale;
                    line_height = start_line_height;
                    y_pointer += (line_height - start_line_height) / 2.0;
                    index_offset += @intCast(reset.len);
                    continue;
                }

                const space = "space";
                if (text_data.text.len >= offset_i + 1 + space.len and std.mem.eql(u8, name_start[0..space.len], space)) {
                    char = ' ';
                    index_offset += @intCast(space.len);
                    break :specialChar;
                }

                if (std.mem.indexOfScalar(u8, name_start, '=')) |eql_idx| {
                    const value_start_idx = offset_i + 1 + eql_idx + 1;
                    if (text_data.text.len <= value_start_idx or text_data.text[value_start_idx] != '"') break :specialChar;

                    const value_start = text_data.text[value_start_idx + 1 ..];
                    if (std.mem.indexOfScalar(u8, value_start, '"')) |value_end_idx| {
                        const name = name_start[0..eql_idx];
                        const value = value_start[0..value_end_idx];
                        if (std.mem.eql(u8, name, "col")) {
                            current_color = std.fmt.parseInt(u32, value, 16) catch break :specialChar;
                        } else if (std.mem.eql(u8, name, "size")) {
                            const size = std.fmt.parseFloat(f32, value) catch break :specialChar;
                            current_size = size / current_font_data.size * scale * (1.0 + current_font_data.padding * 2 / current_font_data.size);
                            line_height = current_font_data.line_height * current_font_data.size * current_size;
                            y_pointer += (line_height - start_line_height) / 2.0;
                        } else if (std.mem.eql(u8, name, "type")) {
                            if (std.mem.eql(u8, value, "med")) {
                                current_type = .medium;
                                current_font_data = assets.medium_data;
                            } else if (std.mem.eql(u8, value, "med_it")) {
                                current_type = .medium_italic;
                                current_font_data = assets.medium_italic_data;
                            } else if (std.mem.eql(u8, value, "bold")) {
                                current_type = .bold;
                                current_font_data = assets.bold_data;
                            } else if (std.mem.eql(u8, value, "bold_it")) {
                                current_type = .bold_italic;
                                current_font_data = assets.bold_italic_data;
                            }
                        } else if (std.mem.eql(u8, name, "img")) {
                            var values = std.mem.splitScalar(u8, value, ',');
                            const sheet = values.next();
                            if (sheet == null or std.mem.eql(u8, sheet.?, value)) break :specialChar;
                            const index_str = values.next() orelse break :specialChar;
                            const index = std.fmt.parseInt(u32, index_str, 0) catch break :specialChar;
                            const data = assets.atlas_data.get(sheet.?) orelse break :specialChar;
                            if (index >= data.len) break :specialChar;

                            if (text_data.break_indices.?.get(i) != null) {
                                y_pointer += line_height;
                                if (y_pointer - y_base > text_data.max_height) return;

                                x_base = switch (text_data.hori_align) {
                                    .left => start_x,
                                    .middle => if (max_width_off) start_x else start_x + (text_data.max_width - text_data.line_widths.?.items[line_idx]) / 2.0,
                                    .right => if (max_width_off) start_x else start_x + (text_data.max_width - text_data.line_widths.?.items[line_idx]),
                                };
                                x_pointer = x_base;
                                line_idx += 1;
                            }

                            const w_larger = data[index].tex_w > data[index].tex_h;
                            const scaled_size = current_size * current_font_data.size;
                            drawQuad(
                                x_pointer,
                                y_pointer - scaled_size,
                                if (w_larger) scaled_size else data[index].width() * (scaled_size / data[index].height()),
                                if (w_larger) data[index].height() * (scaled_size / data[index].width()) else scaled_size,
                                data[index],
                                .{ .alpha_mult = text_data.alpha },
                            );

                            x_pointer += scaled_size;
                        } else break :specialChar;

                        index_offset += @intCast(1 + eql_idx + 1 + value_end_idx + 1);
                        continue;
                    } else break :specialChar;
                } else break :specialChar;
            }
        }

        const mod_char = if (text_data.password) '*' else char;
        const char_data = current_font_data.characters[mod_char];

        const shadow_texel_w = text_data.shadow_texel_offset_mult / current_font_data.width;
        const shadow_texel_h = text_data.shadow_texel_offset_mult / current_font_data.height;

        const scaled_advance = char_data.x_advance * current_size;
        var next_x_pointer = x_pointer + scaled_advance;
        defer x_pointer = next_x_pointer;
        if (text_data.break_indices.?.get(i) != null) {
            y_pointer += line_height;
            if (y_pointer - y_base > text_data.max_height) return;

            x_base = switch (text_data.hori_align) {
                .left => start_x,
                .middle => if (max_width_off) start_x else start_x + (text_data.max_width - text_data.line_widths.?.items[line_idx]) / 2.0,
                .right => if (max_width_off) start_x else start_x + (text_data.max_width - text_data.line_widths.?.items[line_idx]),
            };
            x_pointer = x_base;
            next_x_pointer = x_base + scaled_advance;
            line_idx += 1;
        }

        if (char_data.tex_w <= 0) continue;

        const w = char_data.width * current_size;
        const h = char_data.height * current_size;
        const pos = .{
            x_pointer + char_data.x_offset * current_size,
            // TODO: need to subtract pad height as well... maybe render padding properly later
            y_pointer + (-char_data.y_offset - current_font_data.padding * 2) * current_size - h,
        };

        const uv_w_per_px = char_data.tex_w / w;
        const uv_h_per_px = char_data.tex_h / h;
        const x_off = x_base - pos[0];
        const y_off = y_base - pos[1] - line_height;

        const dont_scissor = element.ScissorRect.dont_scissor;

        const scissor = if (scissor_override == element.ScissorRect{}) text_data.scissor else scissor_override;

        sort_extras.append(main.allocator, text_data.sort_extra) catch main.oomPanic();
        generics.append(main.allocator, .{
            .render_type = render_type,
            .text_type = current_type,
            .text_dist_factor = current_font_data.px_range * current_size,
            .shadow_color = text_data.shadow_color,
            .alpha_mult = text_data.alpha,
            .outline_color = text_data.outline_color,
            .outline_width = text_data.outline_width,
            .base_color = current_color,
            .color_intensity = 1.0,
            .pos = pos,
            .size = .{ w, h },
            .uv = .{ char_data.tex_u, char_data.tex_v },
            .uv_size = .{ char_data.tex_w, char_data.tex_h },
            .shadow_texel_size = .{ shadow_texel_w, shadow_texel_h },
            .scissor = .{
                char_data.tex_u + if (scissor.min_x == dont_scissor) 0 else (scissor.min_x + x_off) * uv_w_per_px,
                char_data.tex_u + if (scissor.max_x == dont_scissor) char_data.tex_w else (scissor.max_x + x_off) * uv_w_per_px,
                char_data.tex_v + if (scissor.min_y == dont_scissor) 0 else (scissor.min_y + y_off) * uv_h_per_px,
                char_data.tex_v + if (scissor.max_y == dont_scissor) char_data.tex_h else (scissor.max_y + y_off) * uv_h_per_px,
            },
        }) catch main.oomPanic();
    }
}

pub fn drawLight(data: game_data.LightData, tile_cx: f32, tile_cy: f32, scale: f32, float_time_ms: f32) void {
    if (data.color == std.math.maxInt(u32)) return;

    const size = px_per_tile * (data.radius + data.pulse * @sin(float_time_ms / 1000.0 * data.pulse_speed)) * scale * 4;
    lights.append(main.allocator, .{
        .x = tile_cx - size / 2.0,
        .y = tile_cy - size / 2.0,
        .w = size,
        .h = size,
        .color = data.color,
        .intensity = data.intensity,
    }) catch main.oomPanic();
}

pub fn draw(time: i64, back_buffer: gpu.wgpu.TextureView, encoder: gpu.wgpu.CommandEncoder) void {
    main.camera.lock.lock();
    var cam_data: CameraData = undefined;
    inline for (@typeInfo(CameraData).@"struct".fields) |field| @field(cam_data, field.name) = @field(main.camera, field.name);
    main.camera.lock.unlock();

    const clear_color_attachments: []const gpu.wgpu.RenderPassColorAttachment = &.{.{
        .view = back_buffer,
        .load_op = .clear,
        .store_op = .store,
        .clear_value = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
    }};
    const pass = encoder.beginRenderPass(.{
        .color_attachment_count = clear_color_attachments.len,
        .color_attachments = clear_color_attachments.ptr,
    });
    defer {
        pass.end();
        pass.release();
    }

    generics.clearRetainingCapacity();
    sort_extras.clearRetainingCapacity();

    if ((main.tick_frame or main.editing_map) and
        cam_data.x >= 0 and cam_data.y >= 0 and
        map.validPos(@intFromFloat(cam_data.x), @intFromFloat(cam_data.y)))
    {
        const float_time_ms = @as(f32, @floatFromInt(time)) / std.time.us_per_ms;
        grounds.clearRetainingCapacity();
        lights.clearRetainingCapacity();

        {
            map.square_lock.lock();
            defer map.square_lock.unlock();
            for (cam_data.min_y..cam_data.max_y) |y| {
                for (cam_data.min_x..cam_data.max_x) |x| {
                    const float_x: f32 = @floatFromInt(x);
                    const float_y: f32 = @floatFromInt(y);
                    const square = map.getSquare(float_x, float_y, false, .con).?;
                    if (square.data_id == Square.empty_tile) continue;

                    const screen_pos = cam_data.worldToScreen(square.x, square.y);

                    if (main.settings.enable_lights) drawLight(square.data.light, screen_pos.x, screen_pos.y, cam_data.scale, float_time_ms);

                    const time_sec = float_time_ms / std.time.ms_per_s;
                    const u_offset, const v_offset = switch (square.data.animation.type) {
                        .wave => .{
                            @sin(square.data.animation.delta_x * time_sec) * assets.base_texel_w,
                            @sin(square.data.animation.delta_y * time_sec) * assets.base_texel_h,
                        },
                        .flow => .{
                            (square.data.animation.delta_x * time_sec) * assets.base_texel_w,
                            (square.data.animation.delta_y * time_sec) * assets.base_texel_h,
                        },
                        .unset => .{ 0.0, 0.0 },
                    };

                    grounds.append(main.allocator, .{
                        .pos = .{ screen_pos.x, screen_pos.y },
                        .uv = .{ square.atlas_data.tex_u, square.atlas_data.tex_v },
                        .offset_uv = .{ u_offset, v_offset },
                        .left_blend_uv = @bitCast(square.blends[0]),
                        .top_blend_uv = @bitCast(square.blends[1]),
                        .right_blend_uv = @bitCast(square.blends[2]),
                        .bottom_blend_uv = @bitCast(square.blends[3]),
                        .rotation = square.rotation,
                    }) catch main.oomPanic();
                }
            }
        }

        {
            map.object_lock.lock();
            defer map.object_lock.unlock();
            inline for (.{ Entity, Enemy, Container, Player, Projectile, Purchasable, Ally }) |T|
                for (map.listForType(T).items) |*obj| obj.draw(cam_data, float_time_ms);

            const int_id = map.interactive.map_id.load(.acquire);
            for (map.listForType(Portal).items) |*portal| portal.draw(cam_data, float_time_ms, int_id);
            for (map.listForType(Particle).items) |particle| particle.draw(cam_data);
        }
    }

    const queue = main.ctx.queue;

    const ground_len: u32 = @min(grounds.items.len, ground_size);
    if (ground_len > 0) {
        queue.writeBuffer(ground_uniforms, 0, GroundUniformData, &.{.{
            .scale = cam_data.scale,
            .left_mask_uv = assets.left_mask_uv,
            .top_mask_uv = assets.top_mask_uv,
            .right_mask_uv = assets.right_mask_uv,
            .bottom_mask_uv = assets.bottom_mask_uv,
            .clip_scale = cam_data.clip_scale,
            .clip_offset = cam_data.clip_offset,
            .atlas_size = .{ assets.atlas_width, assets.atlas_height },
        }});
        queue.writeBuffer(ground_buffer, 0, GroundData, grounds.items[0..ground_len]);
        pass.setPipeline(ground_pipeline);
        pass.setBindGroup(0, ground_bind_group, null);
        pass.draw(ground_len * 6, 1, 0, 0);
    }

    if (main.settings.enable_lights) {
        sortGenerics();

        const opts: QuadOptions = .{ .color = map.info.bg_color, .color_intensity = 1.0, .alpha_mult = map.getLightIntensity(time) };
        drawQuad(0, 0, cam_data.width, cam_data.height, assets.generic_8x8, opts);

        for (lights.items) |data| drawQuad(
            data.x,
            data.y,
            data.w,
            data.h,
            assets.light_data,
            .{ .color = data.color, .color_intensity = 1.0, .alpha_mult = data.intensity },
        );
    } else sortGenerics();

    const game_len: u32 = @min(generics.items.len, generic_size);
    if (game_len > 0) {
        queue.writeBuffer(generic_uniforms, 0, GenericUniformData, &.{.{
            .clip_scale = cam_data.clip_scale,
            .clip_offset = cam_data.clip_offset,
        }});
        queue.writeBuffer(generic_buffer, 0, GenericData, generics.items[0..game_len]);
        pass.setPipeline(generic_pipeline);
        pass.setBindGroup(0, generic_bind_group, null);
        pass.setBindGroup(1, single_tex_bind_group, null);
        pass.draw(game_len * 6, 1, 0, 0);
    }

    generics.clearRetainingCapacity();

    {
        ui_systems.ui_lock.lock();
        defer ui_systems.ui_lock.unlock();
        for (ui_systems.elements.items) |elem| elem.draw(cam_data, 0, 0, time);
    }

    const ui_len: u32 = @min(generics.items.len, ui_size);
    if (ui_len > 0) {
        if (game_len == 0) {
            queue.writeBuffer(generic_uniforms, 0, GenericUniformData, &.{.{
                .clip_scale = cam_data.clip_scale,
                .clip_offset = cam_data.clip_offset,
            }});
            pass.setPipeline(generic_pipeline);
            pass.setBindGroup(1, single_tex_bind_group, null);
        }
        queue.writeBuffer(ui_buffer, 0, GenericData, generics.items[0..ui_len]);
        pass.setBindGroup(0, ui_bind_group, null);
        pass.draw(ui_len * 6, 1, 0, 0);
    }
}

fn sortGenerics() void {
    const Context = struct {
        items: []GenericData,
        sort_prios: []f32,

        pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
            const item_a = ctx.items[a];
            const item_b = ctx.items[b];
            return item_a.pos[1] + item_a.size[1] + ctx.sort_prios[a] < item_b.pos[1] + item_b.size[1] + ctx.sort_prios[b];
        }

        pub fn swap(ctx: @This(), a: usize, b: usize) void {
            std.mem.swap(f32, &ctx.sort_prios[a], &ctx.sort_prios[b]);
            std.mem.swap(GenericData, &ctx.items[a], &ctx.items[b]);
        }
    };

    std.sort.pdqContext(0, generics.items.len, Context{ .items = generics.items, .sort_prios = sort_extras.items });
}
