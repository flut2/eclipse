const std = @import("std");
const map = @import("map.zig");
const assets = @import("assets.zig");
const camera = @import("camera.zig");
const settings = @import("settings.zig");
const zgpu = @import("zgpu");
const utils = @import("utils.zig");
const zstbi = @import("zstbi");
const element = @import("ui/element.zig");
const main = @import("main.zig");
const sc = @import("ui/controllers/screen_controller.zig");

const VertexField = extern struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,
};

pub const BaseVertexData = extern struct {
    pos_uv: VertexField,
    base_color_and_intensity: VertexField = .{
        .x = 0.0,
        .y = 0.0,
        .z = 0.0,
        .w = 0.0,
    },
    alpha_and_shadow_color: VertexField = .{
        .x = 1.0,
        .y = 0.0,
        .z = 0.0,
        .w = 0.0,
    },
    texel_and_text_data: VertexField = .{
        .x = 0.0,
        .y = 0.0,
        .z = 0.0,
        .w = 0.0,
    },
    outline_color_and_w: VertexField = .{
        .x = 0.0,
        .y = 0.0,
        .z = 0.0,
        .w = 0.0,
    },
    render_type: f32,
};

pub const GroundVertexData = extern struct {
    pos_uv: VertexField,
    left_top_blend_uv: VertexField,
    right_bottom_blend_uv: VertexField,
    base_and_offset_uv: VertexField,
};

pub const LightVertexData = extern struct {
    color: element.RGBF32,
    pos: [2]f32,
    uv: [2]f32,
    intensity: f32,
};

// must be multiples of 16 bytes. be mindful
pub const GroundUniformData = extern struct {
    left_top_mask_uv: [4]f32,
    right_bottom_mask_uv: [4]f32,
};

const quad_render_type = 0.0;
const ui_quad_render_type = 1.0;
const quad_glow_off_render_type = 2.0;
const ui_quad_glow_off_render_type = 3.0;
const text_normal_render_type = 4.0;
const text_drop_shadow_render_type = 5.0;
const text_normal_no_subpixel_render_type = 6.0;
const text_drop_shadow_no_subpixel_render_type = 7.0;
const minimap_render_type = 8.0;
const menu_bg_render_type = 9.0;

const base_batch_vert_size = 40000;
const ground_batch_vert_size = 40000;

pub var base_pipeline: zgpu.RenderPipelineHandle = .{};
pub var base_bind_group: zgpu.BindGroupHandle = undefined;
pub var ground_pipeline: zgpu.RenderPipelineHandle = .{};
pub var ground_bind_group: zgpu.BindGroupHandle = undefined;
pub var light_pipeline: zgpu.RenderPipelineHandle = .{};
pub var light_bind_group: zgpu.BindGroupHandle = undefined;

pub var base_vb: zgpu.wgpu.Buffer = undefined;
pub var ground_vb: zgpu.wgpu.Buffer = undefined;
pub var light_vb: zgpu.wgpu.Buffer = undefined;
pub var index_buffer: zgpu.wgpu.Buffer = undefined;

pub var base_vert_data: [base_batch_vert_size]BaseVertexData = undefined;
pub var ground_vert_data: [ground_batch_vert_size]GroundVertexData = undefined;
// no nice way of having multiple batches for these
pub var light_vert_data: [80000]LightVertexData = undefined;

pub var bold_text_texture: zgpu.TextureHandle = undefined;
pub var bold_text_texture_view: zgpu.TextureViewHandle = undefined;
pub var bold_italic_text_texture: zgpu.TextureHandle = undefined;
pub var bold_italic_text_texture_view: zgpu.TextureViewHandle = undefined;
pub var medium_text_texture: zgpu.TextureHandle = undefined;
pub var medium_text_texture_view: zgpu.TextureViewHandle = undefined;
pub var medium_italic_text_texture: zgpu.TextureHandle = undefined;
pub var medium_italic_text_texture_view: zgpu.TextureViewHandle = undefined;
pub var texture: zgpu.TextureHandle = undefined;
pub var texture_view: zgpu.TextureViewHandle = undefined;
pub var ui_texture: zgpu.TextureHandle = undefined;
pub var ui_texture_view: zgpu.TextureViewHandle = undefined;
pub var light_texture: zgpu.TextureHandle = undefined;
pub var light_texture_view: zgpu.TextureViewHandle = undefined;
pub var minimap_texture: zgpu.TextureHandle = undefined;
pub var minimap_texture_view: zgpu.TextureViewHandle = undefined;
pub var menu_bg_texture: zgpu.TextureHandle = undefined;
pub var menu_bg_texture_view: zgpu.TextureViewHandle = undefined;
pub var color_texture: zgpu.TextureHandle = undefined;
pub var color_texture_view: zgpu.TextureViewHandle = undefined;

pub var color_tex_set = false;
pub var clear_render_pass_info: zgpu.wgpu.RenderPassDescriptor = undefined;
pub var load_render_pass_info: zgpu.wgpu.RenderPassDescriptor = undefined;
pub var first_draw = false;

pub var sampler: zgpu.SamplerHandle = undefined;
pub var linear_sampler: zgpu.SamplerHandle = undefined;

pub var condition_rects: [@bitSizeOf(utils.Condition)][]const assets.AtlasData = undefined;
pub var enter_text_data: element.TextData = undefined;

fn createTexture(gctx: *zgpu.GraphicsContext, tex: *zgpu.TextureHandle, view: *zgpu.TextureViewHandle, img: zstbi.Image) void {
    tex.* = gctx.createTexture(.{
        .usage = .{ .texture_binding = true, .copy_dst = true },
        .size = .{
            .width = img.width,
            .height = img.height,
            .depth_or_array_layers = 1,
        },
        .format = zgpu.imageInfoToTextureFormat(
            img.num_components,
            img.bytes_per_component,
            img.is_hdr,
        ),
        .mip_level_count = 1,
    });
    view.* = gctx.createTextureView(tex.*, .{});

    gctx.queue.writeTexture(
        .{ .texture = gctx.lookupResource(tex.*).? },
        .{
            .bytes_per_row = img.bytes_per_row,
            .rows_per_image = img.height,
        },
        .{ .width = img.width, .height = img.height },
        u8,
        img.data,
    );
}

pub fn createColorTexture(gctx: *zgpu.GraphicsContext, w: u32, h: u32) void {
    if (color_tex_set) {
        gctx.destroyResource(color_texture);
        gctx.destroyResource(color_texture_view);
        color_tex_set = false;
    }

    const sample_count: u32 = switch (settings.aa_type) {
        .msaa2x => 2,
        .msaa4x => 4,
        else => 1,
    };

    if (sample_count == 1)
        return;

    color_texture = gctx.createTexture(.{
        .usage = .{ .render_attachment = true },
        .dimension = .tdim_2d,
        .size = .{
            .width = w,
            .height = h,
        },
        .format = gctx.swapchain_descriptor.format,
        .sample_count = sample_count,
    });
    color_texture_view = gctx.createTextureView(color_texture, .{});

    color_tex_set = true;
}

pub fn deinit(allocator: std.mem.Allocator) void {
    for (condition_rects) |rects| {
        if (rects.len > 0)
            allocator.free(rects);
    }

    enter_text_data.deinit(allocator);
}

pub fn init(gctx: *zgpu.GraphicsContext, allocator: std.mem.Allocator) void {
    for (0..@bitSizeOf(utils.Condition)) |i| {
        const sheet_name = "conditions";
        const sheet_indices: []const u16 = switch (std.meta.intToEnum(utils.ConditionEnum, i + 1) catch continue) {
            .weak => &[_]u16{5},
            .slowed => &[_]u16{7},
            .sick => &[_]u16{10},
            .speedy => &[_]u16{6},
            .bleeding => &[_]u16{2},
            .healing => &[_]u16{1},
            .damaging => &[_]u16{4},
            .invulnerable => &[_]u16{11},
            .armored => &[_]u16{3},
            .armor_broken => &[_]u16{9},
            .targeted => &[_]u16{8},
            .unknown, .dead, .hidden, .invisible => &[0]u16{},
        };

        const indices_len = sheet_indices.len;
        if (indices_len == 0) {
            condition_rects[i] = &[0]assets.AtlasData{};
            continue;
        }

        var rects = allocator.alloc(assets.AtlasData, indices_len) catch continue;
        for (0..indices_len) |j| {
            rects[j] = (assets.atlas_data.get(sheet_name) orelse @panic("Could not find sheet for cond parsing"))[sheet_indices[j]];
        }

        condition_rects[i] = rects;
    }

    enter_text_data = element.TextData{
        .text = "Enter",
        .text_type = .bold,
        .size = 16,
    };
    enter_text_data.recalculateAttributes(main._allocator);

    base_vb = gctx.device.createBuffer(.{
        .usage = .{ .copy_dst = true, .vertex = true },
        .size = base_vert_data.len * @sizeOf(BaseVertexData),
    });
    gctx.queue.writeBuffer(base_vb, 0, BaseVertexData, base_vert_data[0..]);

    ground_vb = gctx.device.createBuffer(.{
        .usage = .{ .copy_dst = true, .vertex = true },
        .size = ground_vert_data.len * @sizeOf(GroundVertexData),
    });
    gctx.queue.writeBuffer(ground_vb, 0, GroundVertexData, ground_vert_data[0..]);

    light_vb = gctx.device.createBuffer(.{
        .usage = .{ .copy_dst = true, .vertex = true },
        .size = light_vert_data.len * @sizeOf(LightVertexData),
    });
    gctx.queue.writeBuffer(light_vb, 0, LightVertexData, light_vert_data[0..]);

    const ground_uniforms = gctx.createBuffer(.{
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = @sizeOf(GroundUniformData),
    });
    gctx.queue.writeBuffer(gctx.lookupResource(ground_uniforms).?, 0, GroundUniformData, &[_]GroundUniformData{.{
        .left_top_mask_uv = assets.left_top_mask_uv,
        .right_bottom_mask_uv = assets.right_bottom_mask_uv,
    }});

    var index_data: [60000]u16 = undefined;
    for (0..10000) |i| {
        const actual_i: u16 = @intCast(i * 6);
        const i_4: u16 = @intCast(i * 4);
        index_data[actual_i] = 0 + i_4;
        index_data[actual_i + 1] = 1 + i_4;
        index_data[actual_i + 2] = 3 + i_4;
        index_data[actual_i + 3] = 1 + i_4;
        index_data[actual_i + 4] = 2 + i_4;
        index_data[actual_i + 5] = 3 + i_4;
    }
    index_buffer = gctx.device.createBuffer(.{
        .usage = .{ .copy_dst = true, .index = true },
        .size = index_data.len * @sizeOf(u16),
    });
    gctx.queue.writeBuffer(index_buffer, 0, u16, index_data[0..]);

    const sample_count: u32 = switch (settings.aa_type) {
        .msaa2x => 2,
        .msaa4x => 4,
        else => 1,
    };

    createColorTexture(gctx, gctx.swapchain_descriptor.width, gctx.swapchain_descriptor.height);

    createTexture(gctx, &medium_text_texture, &medium_text_texture_view, assets.medium_atlas);
    createTexture(gctx, &medium_italic_text_texture, &medium_italic_text_texture_view, assets.medium_italic_atlas);
    createTexture(gctx, &bold_text_texture, &bold_text_texture_view, assets.bold_atlas);
    createTexture(gctx, &bold_italic_text_texture, &bold_italic_text_texture_view, assets.bold_italic_atlas);
    createTexture(gctx, &texture, &texture_view, assets.atlas);
    createTexture(gctx, &ui_texture, &ui_texture_view, assets.ui_atlas);
    createTexture(gctx, &light_texture, &light_texture_view, assets.light_tex);
    createTexture(gctx, &minimap_texture, &minimap_texture_view, map.minimap);
    createTexture(gctx, &menu_bg_texture, &menu_bg_texture_view, assets.menu_background);

    sampler = gctx.createSampler(.{});
    linear_sampler = gctx.createSampler(.{ .min_filter = .linear, .mag_filter = .linear });

    const ground_bind_group_layout = gctx.createBindGroupLayout(&.{
        zgpu.bufferEntry(0, .{ .vertex = true, .fragment = true }, .uniform, false, 0),
        zgpu.samplerEntry(1, .{ .fragment = true }, .filtering),
        zgpu.textureEntry(2, .{ .fragment = true }, .float, .tvdim_2d, false),
    });
    defer gctx.releaseResource(ground_bind_group_layout);
    ground_bind_group = gctx.createBindGroup(ground_bind_group_layout, &.{
        .{ .binding = 0, .buffer_handle = ground_uniforms, .size = @sizeOf(GroundUniformData) },
        .{ .binding = 1, .sampler_handle = sampler },
        .{ .binding = 2, .texture_view_handle = texture_view },
    });

    const light_bind_group_layout = gctx.createBindGroupLayout(&.{
        zgpu.samplerEntry(0, .{ .fragment = true }, .filtering),
        zgpu.textureEntry(1, .{ .fragment = true }, .float, .tvdim_2d, false),
    });
    defer gctx.releaseResource(light_bind_group_layout);
    light_bind_group = gctx.createBindGroup(light_bind_group_layout, &.{
        .{ .binding = 0, .sampler_handle = linear_sampler },
        .{ .binding = 1, .texture_view_handle = light_texture_view },
    });

    const base_bind_group_layout = gctx.createBindGroupLayout(&.{
        zgpu.samplerEntry(0, .{ .fragment = true }, .filtering),
        zgpu.samplerEntry(1, .{ .fragment = true }, .filtering),
        zgpu.textureEntry(2, .{ .fragment = true }, .float, .tvdim_2d, false),
        zgpu.textureEntry(3, .{ .fragment = true }, .float, .tvdim_2d, false),
        zgpu.textureEntry(4, .{ .fragment = true }, .float, .tvdim_2d, false),
        zgpu.textureEntry(5, .{ .fragment = true }, .float, .tvdim_2d, false),
        zgpu.textureEntry(6, .{ .fragment = true }, .float, .tvdim_2d, false),
        zgpu.textureEntry(7, .{ .fragment = true }, .float, .tvdim_2d, false),
        zgpu.textureEntry(8, .{ .fragment = true }, .float, .tvdim_2d, false),
        zgpu.textureEntry(9, .{ .fragment = true }, .float, .tvdim_2d, false),
    });
    defer gctx.releaseResource(base_bind_group_layout);
    base_bind_group = gctx.createBindGroup(base_bind_group_layout, &.{
        .{ .binding = 0, .sampler_handle = sampler },
        .{ .binding = 1, .sampler_handle = linear_sampler },
        .{ .binding = 2, .texture_view_handle = texture_view },
        .{ .binding = 3, .texture_view_handle = ui_texture_view },
        .{ .binding = 4, .texture_view_handle = medium_text_texture_view },
        .{ .binding = 5, .texture_view_handle = medium_italic_text_texture_view },
        .{ .binding = 6, .texture_view_handle = bold_text_texture_view },
        .{ .binding = 7, .texture_view_handle = bold_italic_text_texture_view },
        .{ .binding = 8, .texture_view_handle = minimap_texture_view },
        .{ .binding = 9, .texture_view_handle = menu_bg_texture_view },
    });

    {
        const pipeline_layout = gctx.createPipelineLayout(&.{
            base_bind_group_layout,
        });
        defer gctx.releaseResource(pipeline_layout);

        const s_mod = zgpu.createWgslShaderModule(gctx.device, @embedFile("./assets/shaders/base.wgsl"), null);
        defer s_mod.release();

        const color_targets = [_]zgpu.wgpu.ColorTargetState{.{
            .format = zgpu.GraphicsContext.swapchain_format,
            .blend = &zgpu.wgpu.BlendState{
                .color = .{ .src_factor = .src_alpha, .dst_factor = .one_minus_src_alpha },
                .alpha = .{ .src_factor = .src_alpha, .dst_factor = .one_minus_src_alpha },
            },
        }};

        const vertex_attributes = [_]zgpu.wgpu.VertexAttribute{
            .{ .format = .float32x4, .offset = @offsetOf(BaseVertexData, "pos_uv"), .shader_location = 0 },
            .{ .format = .float32x4, .offset = @offsetOf(BaseVertexData, "base_color_and_intensity"), .shader_location = 1 },
            .{ .format = .float32x4, .offset = @offsetOf(BaseVertexData, "alpha_and_shadow_color"), .shader_location = 2 },
            .{ .format = .float32x4, .offset = @offsetOf(BaseVertexData, "texel_and_text_data"), .shader_location = 3 },
            .{ .format = .float32x4, .offset = @offsetOf(BaseVertexData, "outline_color_and_w"), .shader_location = 4 },
            .{ .format = .float32, .offset = @offsetOf(BaseVertexData, "render_type"), .shader_location = 5 },
        };
        const vertex_buffers = [_]zgpu.wgpu.VertexBufferLayout{.{
            .array_stride = @sizeOf(BaseVertexData),
            .attribute_count = vertex_attributes.len,
            .attributes = &vertex_attributes,
        }};

        const pipeline_descriptor = zgpu.wgpu.RenderPipelineDescriptor{
            .vertex = zgpu.wgpu.VertexState{
                .module = s_mod,
                .entry_point = "vs_main",
                .buffer_count = vertex_buffers.len,
                .buffers = &vertex_buffers,
            },
            .primitive = zgpu.wgpu.PrimitiveState{
                .front_face = .cw,
                .cull_mode = .none,
                .topology = .triangle_list,
            },
            .fragment = &zgpu.wgpu.FragmentState{
                .module = s_mod,
                .entry_point = "fs_main",
                .target_count = color_targets.len,
                .targets = &color_targets,
            },
            .multisample = .{ .count = sample_count },
        };
        base_pipeline = gctx.createRenderPipeline(pipeline_layout, pipeline_descriptor);
    }

    {
        const pipeline_layout = gctx.createPipelineLayout(&.{
            ground_bind_group_layout,
        });
        defer gctx.releaseResource(pipeline_layout);

        const s_mod = zgpu.createWgslShaderModule(gctx.device, @embedFile("./assets/shaders/ground.wgsl"), null);
        defer s_mod.release();

        const color_targets = [_]zgpu.wgpu.ColorTargetState{.{
            .format = zgpu.GraphicsContext.swapchain_format,
        }};

        const vertex_attributes = [_]zgpu.wgpu.VertexAttribute{
            .{ .format = .float32x4, .offset = @offsetOf(GroundVertexData, "pos_uv"), .shader_location = 0 },
            .{ .format = .float32x4, .offset = @offsetOf(GroundVertexData, "left_top_blend_uv"), .shader_location = 1 },
            .{ .format = .float32x4, .offset = @offsetOf(GroundVertexData, "right_bottom_blend_uv"), .shader_location = 2 },
            .{ .format = .float32x4, .offset = @offsetOf(GroundVertexData, "base_and_offset_uv"), .shader_location = 3 },
        };
        const vertex_buffers = [_]zgpu.wgpu.VertexBufferLayout{.{
            .array_stride = @sizeOf(GroundVertexData),
            .attribute_count = vertex_attributes.len,
            .attributes = &vertex_attributes,
        }};

        const pipeline_descriptor = zgpu.wgpu.RenderPipelineDescriptor{
            .vertex = zgpu.wgpu.VertexState{
                .module = s_mod,
                .entry_point = "vs_main",
                .buffer_count = vertex_buffers.len,
                .buffers = &vertex_buffers,
            },
            .primitive = zgpu.wgpu.PrimitiveState{
                .front_face = .cw,
                .cull_mode = .none,
                .topology = .triangle_list,
            },
            .fragment = &zgpu.wgpu.FragmentState{
                .module = s_mod,
                .entry_point = "fs_main",
                .target_count = color_targets.len,
                .targets = &color_targets,
            },
            .multisample = .{ .count = sample_count },
        };
        ground_pipeline = gctx.createRenderPipeline(pipeline_layout, pipeline_descriptor);
    }

    {
        const pipeline_layout = gctx.createPipelineLayout(&.{
            light_bind_group_layout,
        });
        defer gctx.releaseResource(pipeline_layout);

        const s_mod = zgpu.createWgslShaderModule(gctx.device, @embedFile("./assets/shaders/light.wgsl"), null);
        defer s_mod.release();

        const color_targets = [_]zgpu.wgpu.ColorTargetState{.{
            .format = zgpu.GraphicsContext.swapchain_format,
            .blend = &zgpu.wgpu.BlendState{
                .color = .{ .src_factor = .src_alpha, .dst_factor = .one },
                .alpha = .{ .src_factor = .zero, .dst_factor = .zero },
            },
        }};

        const vertex_attributes = [_]zgpu.wgpu.VertexAttribute{
            .{ .format = .float32x3, .offset = @offsetOf(LightVertexData, "color"), .shader_location = 2 },
            .{ .format = .float32x2, .offset = @offsetOf(LightVertexData, "pos"), .shader_location = 0 },
            .{ .format = .float32x2, .offset = @offsetOf(LightVertexData, "uv"), .shader_location = 1 },
            .{ .format = .float32, .offset = @offsetOf(LightVertexData, "intensity"), .shader_location = 3 },
        };
        const vertex_buffers = [_]zgpu.wgpu.VertexBufferLayout{.{
            .array_stride = @sizeOf(LightVertexData),
            .attribute_count = vertex_attributes.len,
            .attributes = &vertex_attributes,
        }};

        const pipeline_descriptor = zgpu.wgpu.RenderPipelineDescriptor{
            .vertex = zgpu.wgpu.VertexState{
                .module = s_mod,
                .entry_point = "vs_main",
                .buffer_count = vertex_buffers.len,
                .buffers = &vertex_buffers,
            },
            .primitive = zgpu.wgpu.PrimitiveState{
                .front_face = .cw,
                .cull_mode = .none,
                .topology = .triangle_list,
            },
            .fragment = &zgpu.wgpu.FragmentState{
                .module = s_mod,
                .entry_point = "fs_main",
                .target_count = color_targets.len,
                .targets = &color_targets,
            },
            .multisample = .{ .count = sample_count },
        };
        light_pipeline = gctx.createRenderPipeline(pipeline_layout, pipeline_descriptor);
    }
}

const DrawData = struct {
    encoder: zgpu.wgpu.CommandEncoder,
    buffer: zgpu.wgpu.Buffer,
    pipeline: zgpu.wgpu.RenderPipeline,
    bind_group: zgpu.wgpu.BindGroup,
};

fn drawWall(idx: u16, x: f32, y: f32, alpha: f32, atlas_data: assets.AtlasData, top_atlas_data: assets.AtlasData, noalias draw_data: *const DrawData) u16 {
    var idx_new: u16 = idx;
    var atlas_data_new = atlas_data;

    const screen_pos = camera.rotateAroundCameraClip(x, y);
    const screen_x = screen_pos.x;
    const screen_y = -screen_pos.y;
    const screen_y_top = screen_y + camera.px_per_tile;

    const radius = @sqrt(@as(f32, camera.px_per_tile * camera.px_per_tile / 2)) + 1;
    const pi_div_4 = std.math.pi / 4.0;
    const top_right_angle = pi_div_4;
    const bottom_right_angle = 3.0 * pi_div_4;
    const bottom_left_angle = 5.0 * pi_div_4;
    const top_left_angle = 7.0 * pi_div_4;

    const x1 = (screen_x + radius * @cos(top_left_angle + camera.angle)) * camera.clip_scale_x;
    const y1 = (screen_y + radius * @sin(top_left_angle + camera.angle)) * camera.clip_scale_y;
    const x2 = (screen_x + radius * @cos(bottom_left_angle + camera.angle)) * camera.clip_scale_x;
    const y2 = (screen_y + radius * @sin(bottom_left_angle + camera.angle)) * camera.clip_scale_y;
    const x3 = (screen_x + radius * @cos(bottom_right_angle + camera.angle)) * camera.clip_scale_x;
    const y3 = (screen_y + radius * @sin(bottom_right_angle + camera.angle)) * camera.clip_scale_y;
    const x4 = (screen_x + radius * @cos(top_right_angle + camera.angle)) * camera.clip_scale_x;
    const y4 = (screen_y + radius * @sin(top_right_angle + camera.angle)) * camera.clip_scale_y;

    const top_y1 = (screen_y_top + radius * @sin(top_left_angle + camera.angle)) * camera.clip_scale_y;
    const top_y2 = (screen_y_top + radius * @sin(bottom_left_angle + camera.angle)) * camera.clip_scale_y;
    const top_y3 = (screen_y_top + radius * @sin(bottom_right_angle + camera.angle)) * camera.clip_scale_y;
    const top_y4 = (screen_y_top + radius * @sin(top_right_angle + camera.angle)) * camera.clip_scale_y;

    const floor_x: u32 = @intFromFloat(@floor(x));
    const floor_y: u32 = @intFromFloat(@floor(y));

    const pi_div_2 = std.math.pi / 2.0;
    const bound_angle = utils.halfBound(camera.angle);

    const base_color_intensity_sides = 0.25;
    const base_color_intensity_top = 0.1;
    const color = 0x000000;

    topSide: {
        if (bound_angle >= pi_div_2 and bound_angle <= std.math.pi or bound_angle >= -std.math.pi and bound_angle <= -pi_div_2 and floor_y > 0) {
            if (!map.validPos(floor_x, floor_y - 1)) {
                atlas_data_new.tex_u = assets.wall_backface_data.tex_u;
                atlas_data_new.tex_v = assets.wall_backface_data.tex_v;
            } else {
                const top_sq = map.squares[(floor_y - 1) * map.width + floor_x];
                if (top_sq.has_wall)
                    break :topSide;

                if (top_sq.tile_type == 0xFFFF or top_sq.tile_type == 0xFF) {
                    atlas_data_new.tex_u = assets.wall_backface_data.tex_u;
                    atlas_data_new.tex_v = assets.wall_backface_data.tex_v;
                }

                // no need to set back atlas_data_new here, nothing can override it prior to this
            }

            idx_new = drawQuadVerts(
                idx_new,
                x3,
                top_y3,
                x4,
                top_y4,
                x4,
                y4,
                x3,
                y3,
                atlas_data_new,
                draw_data,
                &.{ .base_color = color, .base_color_intensity = base_color_intensity_sides, .alpha_mult = alpha },
            );
        }
    }

    bottomSide: {
        if (bound_angle <= pi_div_2 and bound_angle >= -pi_div_2 and floor_y < std.math.maxInt(u32)) {
            if (!map.validPos(floor_x, floor_y + 1)) {
                atlas_data_new.tex_u = assets.wall_backface_data.tex_u;
                atlas_data_new.tex_v = assets.wall_backface_data.tex_v;
            } else {
                const bottom_sq = map.squares[(floor_y + 1) * map.width + floor_x];
                if (bottom_sq.has_wall)
                    break :bottomSide;

                if (bottom_sq.tile_type == 0xFFFF or bottom_sq.tile_type == 0xFF) {
                    atlas_data_new.tex_u = assets.wall_backface_data.tex_u;
                    atlas_data_new.tex_v = assets.wall_backface_data.tex_v;
                } else {
                    atlas_data_new.tex_u = atlas_data.tex_u;
                    atlas_data_new.tex_v = atlas_data.tex_v;
                }
            }

            idx_new = drawQuadVerts(
                idx_new,
                x1,
                top_y1,
                x2,
                top_y2,
                x2,
                y2,
                x1,
                y1,
                atlas_data_new,
                draw_data,
                &.{ .base_color = color, .base_color_intensity = base_color_intensity_sides, .alpha_mult = alpha },
            );
        }
    }

    leftSide: {
        if (bound_angle >= 0 and bound_angle <= std.math.pi and floor_x > 0) {
            if (!map.validPos(floor_x - 1, floor_y)) {
                atlas_data_new.tex_u = assets.wall_backface_data.tex_u;
                atlas_data_new.tex_v = assets.wall_backface_data.tex_v;
            } else {
                const left_sq = map.squares[floor_y * map.width + floor_x - 1];
                if (left_sq.has_wall)
                    break :leftSide;

                if (left_sq.tile_type == 0xFFFF or left_sq.tile_type == 0xFF) {
                    atlas_data_new.tex_u = assets.wall_backface_data.tex_u;
                    atlas_data_new.tex_v = assets.wall_backface_data.tex_v;
                } else {
                    atlas_data_new.tex_u = atlas_data.tex_u;
                    atlas_data_new.tex_v = atlas_data.tex_v;
                }
            }

            idx_new = drawQuadVerts(
                idx_new,
                x3,
                top_y3,
                x2,
                top_y2,
                x2,
                y2,
                x3,
                y3,
                atlas_data_new,
                draw_data,
                &.{ .base_color = color, .base_color_intensity = base_color_intensity_sides, .alpha_mult = alpha },
            );
        }
    }

    rightSide: {
        if (bound_angle <= 0 and bound_angle >= -std.math.pi and floor_x < std.math.maxInt(u32)) {
            if (!map.validPos(floor_x + 1, floor_y)) {
                atlas_data_new.tex_u = assets.wall_backface_data.tex_u;
                atlas_data_new.tex_v = assets.wall_backface_data.tex_v;
            } else {
                const right_sq = map.squares[floor_y * map.width + floor_x + 1];
                if (right_sq.has_wall)
                    break :rightSide;

                if (right_sq.tile_type == 0xFFFF or right_sq.tile_type == 0xFF) {
                    atlas_data_new.tex_u = assets.wall_backface_data.tex_u;
                    atlas_data_new.tex_v = assets.wall_backface_data.tex_v;
                } else {
                    atlas_data_new.tex_u = atlas_data.tex_u;
                    atlas_data_new.tex_v = atlas_data.tex_v;
                }
            }

            idx_new = drawQuadVerts(
                idx_new,
                x4,
                top_y4,
                x1,
                top_y1,
                x1,
                y1,
                x4,
                y4,
                atlas_data_new,
                draw_data,
                &.{ .base_color = color, .base_color_intensity = base_color_intensity_sides, .alpha_mult = alpha },
            );
        }
    }

    idx_new = drawQuadVerts(
        idx_new,
        x1,
        top_y1,
        x2,
        top_y2,
        x3,
        top_y3,
        x4,
        top_y4,
        top_atlas_data,
        draw_data,
        &.{ .base_color = color, .base_color_intensity = base_color_intensity_top, .alpha_mult = alpha },
    );

    return idx_new;
}

fn drawMinimap(
    idx: u16,
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    target_x: f32,
    target_y: f32,
    tex_w: f32,
    tex_h: f32,
    rotation: f32,
    noalias draw_data: *const DrawData,
    scissor: element.ScissorRect,
) u16 {
    var idx_new = idx;

    if (idx_new == base_batch_vert_size) {
        draw_data.encoder.writeBuffer(
            draw_data.buffer,
            0,
            BaseVertexData,
            base_vert_data[0..base_batch_vert_size],
        );
        endDraw(
            draw_data,
            base_batch_vert_size * @sizeOf(BaseVertexData),
            @divExact(base_batch_vert_size, 4) * 6,
            null,
        );
        idx_new = 0;
    }

    const scaled_w = w * camera.clip_scale_x;
    const scaled_h = h * camera.clip_scale_y;
    const scaled_x = (x - camera.screen_width / 2.0 + w / 2.0) * camera.clip_scale_x;
    const scaled_y = -(y - camera.screen_height / 2.0 + h / 2.0) * camera.clip_scale_y;

    const cos_angle = @cos(rotation);
    const sin_angle = @sin(rotation);
    const x_cos = cos_angle * scaled_w * 0.5;
    const x_sin = sin_angle * scaled_w * 0.5;
    const y_cos = cos_angle * scaled_h * 0.5;
    const y_sin = sin_angle * scaled_h * 0.5;

    const tex_u = target_x / 4096.0;
    const tex_v = target_y / 4096.0;
    const tex_w_scale = tex_w / 4096.0;
    const tex_h_scale = tex_h / 4096.0;
    const tex_w_half = tex_w_scale / 2.0;
    const tex_h_half = tex_h_scale / 2.0;

    const dont_scissor = element.ScissorRect.dont_scissor;
    const scaled_min_x = if (scissor.min_x != dont_scissor)
        (scissor.min_x + x - camera.screen_width / 2.0) * camera.clip_scale_x
    else if (rotation == 0) @as(f32, -1.0) else @as(f32, -2.0);
    const scaled_max_x = if (scissor.max_x != dont_scissor)
        (scissor.max_x + x - camera.screen_width / 2.0) * camera.clip_scale_x
    else if (rotation == 0) @as(f32, 1.0) else @as(f32, 2.0);

    // have to flip these, y is inverted... should be fixed later
    const scaled_min_y = if (scissor.max_y != dont_scissor)
        -(scissor.max_y + y - camera.screen_height / 2.0) * camera.clip_scale_y
    else if (rotation == 0) @as(f32, -1.0) else @as(f32, -2.0);
    const scaled_max_y = if (scissor.min_y != dont_scissor)
        -(scissor.min_y + y - camera.screen_height / 2.0) * camera.clip_scale_y
    else if (rotation == 0) @as(f32, 1.0) else @as(f32, 2.0);

    var x1 = -x_cos + x_sin + scaled_x;
    var tex_u1 = tex_u - tex_w_half;
    if (x1 < scaled_min_x) {
        const scale = (scaled_min_x - x1) / scaled_w;
        x1 = scaled_min_x;
        tex_u1 += scale * tex_w_scale;
    } else if (x1 > scaled_max_x) {
        const scale = (x1 - scaled_max_x) / scaled_w;
        x1 = scaled_max_x;
        tex_u1 -= scale * tex_w_scale;
    }

    var y1 = -y_sin - y_cos + scaled_y;
    var tex_v1 = tex_v + tex_h_half;
    if (y1 < scaled_min_y) {
        const scale = (scaled_min_y - y1) / scaled_h;
        y1 = scaled_min_y;
        tex_v1 -= scale * tex_h_scale;
    } else if (y1 > scaled_max_y) {
        const scale = (y1 - scaled_max_y) / scaled_h;
        y1 = scaled_max_y;
        tex_v1 += scale * tex_h_scale;
    }

    base_vert_data[idx_new] = BaseVertexData{
        .pos_uv = .{
            .x = x1,
            .y = y1,
            .z = tex_u1,
            .w = tex_v1,
        },
        .render_type = minimap_render_type,
    };

    var x2 = x_cos + x_sin + scaled_x;
    var tex_u2 = tex_u + tex_w_half;
    if (x2 < scaled_min_x) {
        const scale = (scaled_min_x - x2) / scaled_w;
        x2 = scaled_min_x;
        tex_u2 += scale * tex_w_scale;
    } else if (x2 > scaled_max_x) {
        const scale = (x2 - scaled_max_x) / scaled_w;
        x2 = scaled_max_x;
        tex_u2 -= scale * tex_w_scale;
    }

    var y2 = y_sin - y_cos + scaled_y;
    var tex_v2 = tex_v + tex_h_half;
    if (y2 < scaled_min_y) {
        const scale = (scaled_min_y - y2) / scaled_h;
        y2 = scaled_min_y;
        tex_v2 -= scale * tex_h_scale;
    } else if (y2 > scaled_max_y) {
        const scale = (y2 - scaled_max_y) / scaled_h;
        y2 = scaled_max_y;
        tex_v2 += scale * tex_h_scale;
    }

    base_vert_data[idx_new + 1] = BaseVertexData{
        .pos_uv = .{
            .x = x2,
            .y = y2,
            .z = tex_u2,
            .w = tex_v2,
        },
        .render_type = minimap_render_type,
    };

    var x3 = x_cos - x_sin + scaled_x;
    var tex_u3 = tex_u + tex_w_half;
    if (x3 < scaled_min_x) {
        const scale = (scaled_min_x - x3) / scaled_w;
        x3 = scaled_min_x;
        tex_u3 += scale * tex_w_scale;
    } else if (x3 > scaled_max_x) {
        const scale = (x3 - scaled_max_x) / scaled_w;
        x3 = scaled_max_x;
        tex_u3 -= scale * tex_w_scale;
    }

    var y3 = y_sin + y_cos + scaled_y;
    var tex_v3 = tex_v - tex_h_half;
    if (y3 < scaled_min_y) {
        const scale = (scaled_min_y - y3) / scaled_h;
        y3 = scaled_min_y;
        tex_v3 -= scale * tex_h_scale;
    } else if (y3 > scaled_max_y) {
        const scale = (y3 - scaled_max_y) / scaled_h;
        y3 = scaled_max_y;
        tex_v3 += scale * tex_h_scale;
    }

    base_vert_data[idx_new + 2] = BaseVertexData{
        .pos_uv = .{
            .x = x3,
            .y = y3,
            .z = tex_u3,
            .w = tex_v3,
        },
        .render_type = minimap_render_type,
    };

    var x4 = -x_cos - x_sin + scaled_x;
    var tex_u4 = tex_u - tex_w_half;
    if (x4 < scaled_min_x) {
        const scale = (scaled_min_x - x4) / scaled_w;
        x4 = scaled_min_x;
        tex_u4 += scale * tex_w_scale;
    } else if (x4 > scaled_max_x) {
        const scale = (x4 - scaled_max_x) / scaled_w;
        x4 = scaled_max_x;
        tex_u4 -= scale * tex_w_scale;
    }

    var y4 = -y_sin + y_cos + scaled_y;
    var tex_v4 = tex_v - tex_h_half;
    if (y4 < scaled_min_y) {
        const scale = (scaled_min_y - y4) / scaled_h;
        y4 = scaled_min_y;
        tex_v4 -= scale * tex_h_scale;
    } else if (y4 > scaled_max_y) {
        const scale = (y4 - scaled_max_y) / scaled_h;
        y4 = scaled_max_y;
        tex_v4 += scale * tex_h_scale;
    }

    base_vert_data[idx_new + 3] = BaseVertexData{
        .pos_uv = .{
            .x = x4,
            .y = y4,
            .z = tex_u4,
            .w = tex_v4,
        },
        .render_type = minimap_render_type,
    };

    return idx_new + 4;
}

fn drawMenuBackground(
    idx: u16,
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    rotation: f32,
    noalias draw_data: *const DrawData,
    scissor: element.ScissorRect,
) u16 {
    var idx_new = idx;

    if (idx_new == base_batch_vert_size) {
        draw_data.encoder.writeBuffer(
            draw_data.buffer,
            0,
            BaseVertexData,
            base_vert_data[0..base_batch_vert_size],
        );
        endDraw(
            draw_data,
            base_batch_vert_size * @sizeOf(BaseVertexData),
            @divExact(base_batch_vert_size, 4) * 6,
            null,
        );
        idx_new = 0;
    }

    const scaled_w = w * camera.clip_scale_x;
    const scaled_h = h * camera.clip_scale_y;
    const scaled_x = (x - camera.screen_width / 2.0 + w / 2.0) * camera.clip_scale_x;
    const scaled_y = -(y - camera.screen_height / 2.0 + h / 2.0) * camera.clip_scale_y;

    const cos_angle = @cos(rotation);
    const sin_angle = @sin(rotation);
    const x_cos = cos_angle * scaled_w * 0.5;
    const x_sin = sin_angle * scaled_w * 0.5;
    const y_cos = cos_angle * scaled_h * 0.5;
    const y_sin = sin_angle * scaled_h * 0.5;

    const dont_scissor = element.ScissorRect.dont_scissor;
    const scaled_min_x = if (scissor.min_x != dont_scissor)
        (scissor.min_x + x - camera.screen_width / 2.0) * camera.clip_scale_x
    else if (rotation == 0) @as(f32, -1.0) else @as(f32, -2.0);
    const scaled_max_x = if (scissor.max_x != dont_scissor)
        (scissor.max_x + x - camera.screen_width / 2.0) * camera.clip_scale_x
    else if (rotation == 0) @as(f32, 1.0) else @as(f32, 2.0);

    // have to flip these, y is inverted... should be fixed later
    const scaled_min_y = if (scissor.max_y != dont_scissor)
        -(scissor.max_y + y - camera.screen_height / 2.0) * camera.clip_scale_y
    else if (rotation == 0) @as(f32, -1.0) else @as(f32, -2.0);
    const scaled_max_y = if (scissor.min_y != dont_scissor)
        -(scissor.min_y + y - camera.screen_height / 2.0) * camera.clip_scale_y
    else if (rotation == 0) @as(f32, 1.0) else @as(f32, 2.0);

    const tex_w = 1.0;
    const tex_h = 1.0;

    var x1 = -x_cos + x_sin + scaled_x;
    var tex_u1: f32 = 0;
    if (x1 < scaled_min_x) {
        const scale = (scaled_min_x - x1) / scaled_w;
        x1 = scaled_min_x;
        tex_u1 += scale * tex_w;
    } else if (x1 > scaled_max_x) {
        const scale = (x1 - scaled_max_x) / scaled_w;
        x1 = scaled_max_x;
        tex_u1 -= scale * tex_w;
    }

    var y1 = -y_sin - y_cos + scaled_y;
    var tex_v1: f32 = 1;
    if (y1 < scaled_min_y) {
        const scale = (scaled_min_y - y1) / scaled_h;
        y1 = scaled_min_y;
        tex_v1 -= scale * tex_h;
    } else if (y1 > scaled_max_y) {
        const scale = (y1 - scaled_max_y) / scaled_h;
        y1 = scaled_max_y;
        tex_v1 += scale * tex_h;
    }

    base_vert_data[idx_new] = BaseVertexData{
        .pos_uv = .{
            .x = x1,
            .y = y1,
            .z = tex_u1,
            .w = tex_v1,
        },
        .render_type = menu_bg_render_type,
    };

    var x2 = x_cos + x_sin + scaled_x;
    var tex_u2: f32 = 1;
    if (x2 < scaled_min_x) {
        const scale = (scaled_min_x - x2) / scaled_w;
        x2 = scaled_min_x;
        tex_u2 += scale * tex_w;
    } else if (x2 > scaled_max_x) {
        const scale = (x2 - scaled_max_x) / scaled_w;
        x2 = scaled_max_x;
        tex_u2 -= scale * tex_w;
    }

    var y2 = y_sin - y_cos + scaled_y;
    var tex_v2: f32 = 1;
    if (y2 < scaled_min_y) {
        const scale = (scaled_min_y - y2) / scaled_h;
        y2 = scaled_min_y;
        tex_v2 -= scale * tex_h;
    } else if (y2 > scaled_max_y) {
        const scale = (y2 - scaled_max_y) / scaled_h;
        y2 = scaled_max_y;
        tex_v2 += scale * tex_h;
    }

    base_vert_data[idx_new + 1] = BaseVertexData{
        .pos_uv = .{
            .x = x2,
            .y = y2,
            .z = tex_u2,
            .w = tex_v2,
        },
        .render_type = menu_bg_render_type,
    };

    var x3 = x_cos - x_sin + scaled_x;
    var tex_u3: f32 = 1;
    if (x3 < scaled_min_x) {
        const scale = (scaled_min_x - x3) / scaled_w;
        x3 = scaled_min_x;
        tex_u3 += scale * tex_w;
    } else if (x3 > scaled_max_x) {
        const scale = (x3 - scaled_max_x) / scaled_w;
        x3 = scaled_max_x;
        tex_u3 -= scale * tex_w;
    }

    var y3 = y_sin + y_cos + scaled_y;
    var tex_v3: f32 = 0;
    if (y3 < scaled_min_y) {
        const scale = (scaled_min_y - y3) / scaled_h;
        y3 = scaled_min_y;
        tex_v3 -= scale * tex_h;
    } else if (y3 > scaled_max_y) {
        const scale = (y3 - scaled_max_y) / scaled_h;
        y3 = scaled_max_y;
        tex_v3 += scale * tex_h;
    }

    base_vert_data[idx_new + 2] = BaseVertexData{
        .pos_uv = .{
            .x = x3,
            .y = y3,
            .z = tex_u3,
            .w = tex_v3,
        },
        .render_type = menu_bg_render_type,
    };

    var x4 = -x_cos - x_sin + scaled_x;
    var tex_u4: f32 = 0;
    if (x4 < scaled_min_x) {
        const scale = (scaled_min_x - x4) / scaled_w;
        x4 = scaled_min_x;
        tex_u4 += scale * tex_w;
    } else if (x4 > scaled_max_x) {
        const scale = (x4 - scaled_max_x) / scaled_w;
        x4 = scaled_max_x;
        tex_u4 -= scale * tex_w;
    }

    var y4 = -y_sin + y_cos + scaled_y;
    var tex_v4: f32 = 0;
    if (y4 < scaled_min_y) {
        const scale = (scaled_min_y - y4) / scaled_h;
        y4 = scaled_min_y;
        tex_v4 -= scale * tex_h;
    } else if (y4 > scaled_max_y) {
        const scale = (y4 - scaled_max_y) / scaled_h;
        y4 = scaled_max_y;
        tex_v4 += scale * tex_h;
    }

    base_vert_data[idx_new + 3] = BaseVertexData{
        .pos_uv = .{
            .x = x4,
            .y = y4,
            .z = tex_u4,
            .w = tex_v4,
        },
        .render_type = menu_bg_render_type,
    };

    return idx_new + 4;
}

const QuadOptions = struct {
    rotation: f32 = 0.0,
    base_color: u32 = std.math.maxInt(u32),
    base_color_intensity: f32 = 0.0,
    alpha_mult: f32 = 1.0,
    shadow_texel_mult: f32 = 0.0,
    shadow_color: u32 = std.math.maxInt(u32),
    force_glow_off: bool = false,
    ui_quad: bool = false,
    scissor: element.ScissorRect = .{},
};

fn drawQuad(
    idx: u16,
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    atlas_data: assets.AtlasData,
    noalias draw_data: *const DrawData,
    noalias opts: *const QuadOptions,
) u16 {
    var idx_new = idx;

    if (idx_new == base_batch_vert_size) {
        draw_data.encoder.writeBuffer(
            draw_data.buffer,
            0,
            BaseVertexData,
            base_vert_data[0..base_batch_vert_size],
        );
        endDraw(
            draw_data,
            base_batch_vert_size * @sizeOf(BaseVertexData),
            @divExact(base_batch_vert_size, 4) * 6,
            null,
        );
        idx_new = 0;
    }

    var base_rgb = element.RGBF32.fromValues(0.0, 0.0, 0.0);
    if (opts.base_color != std.math.maxInt(u32))
        base_rgb = element.RGBF32.fromInt(opts.base_color);

    var shadow_rgb = element.RGBF32.fromValues(0.0, 0.0, 0.0);
    if (opts.shadow_color != std.math.maxInt(u32))
        shadow_rgb = element.RGBF32.fromInt(opts.shadow_color);

    const texel_w = assets.base_texel_w * opts.shadow_texel_mult;
    const texel_h = assets.base_texel_h * opts.shadow_texel_mult;

    const scaled_w = w * camera.clip_scale_x;
    const scaled_h = h * camera.clip_scale_y;
    const scaled_x = (x - camera.screen_width / 2.0 + w / 2.0) * camera.clip_scale_x;
    const scaled_y = -(y - camera.screen_height / 2.0 + h / 2.0) * camera.clip_scale_y;

    const cos_angle = @cos(opts.rotation);
    const sin_angle = @sin(opts.rotation);
    const x_cos = cos_angle * scaled_w * 0.5;
    const x_sin = sin_angle * scaled_w * 0.5;
    const y_cos = cos_angle * scaled_h * 0.5;
    const y_sin = sin_angle * scaled_h * 0.5;

    var render_type: f32 = quad_render_type;

    if (settings.enable_glow and !opts.force_glow_off) {
        render_type = if (opts.ui_quad) ui_quad_render_type else quad_render_type;
    } else {
        render_type = if (opts.ui_quad) ui_quad_glow_off_render_type else quad_glow_off_render_type;
    }

    const dont_scissor = element.ScissorRect.dont_scissor;
    const scaled_min_x = if (opts.scissor.min_x != dont_scissor)
        (opts.scissor.min_x + x - camera.screen_width / 2.0) * camera.clip_scale_x
    else if (opts.rotation == 0) @as(f32, -1.0) else @as(f32, -2.0);
    const scaled_max_x = if (opts.scissor.max_x != dont_scissor)
        (opts.scissor.max_x + x - camera.screen_width / 2.0) * camera.clip_scale_x
    else if (opts.rotation == 0) @as(f32, 1.0) else @as(f32, 2.0);

    // have to flip these, y is inverted... should be fixed later
    const scaled_min_y = if (opts.scissor.max_y != dont_scissor)
        -(opts.scissor.max_y + y - camera.screen_height / 2.0) * camera.clip_scale_y
    else if (opts.rotation == 0) @as(f32, -1.0) else @as(f32, -2.0);
    const scaled_max_y = if (opts.scissor.min_y != dont_scissor)
        -(opts.scissor.min_y + y - camera.screen_height / 2.0) * camera.clip_scale_y
    else if (opts.rotation == 0) @as(f32, 1.0) else @as(f32, 2.0);

    var x1 = -x_cos + x_sin + scaled_x;
    var tex_u1 = atlas_data.tex_u;
    if (x1 < scaled_min_x) {
        const scale = (scaled_min_x - x1) / scaled_w;
        x1 = scaled_min_x;
        tex_u1 += scale * atlas_data.tex_w;
    } else if (x1 > scaled_max_x) {
        const scale = (x1 - scaled_max_x) / scaled_w;
        x1 = scaled_max_x;
        tex_u1 -= scale * atlas_data.tex_w;
    }

    var y1 = -y_sin - y_cos + scaled_y;
    var tex_v1 = atlas_data.tex_v + atlas_data.tex_h;
    if (y1 < scaled_min_y) {
        const scale = (scaled_min_y - y1) / scaled_h;
        y1 = scaled_min_y;
        tex_v1 -= scale * atlas_data.tex_h;
    } else if (y1 > scaled_max_y) {
        const scale = (y1 - scaled_max_y) / scaled_h;
        y1 = scaled_max_y;
        tex_v1 += scale * atlas_data.tex_h;
    }

    base_vert_data[idx_new] = BaseVertexData{
        .pos_uv = .{
            .x = x1,
            .y = y1,
            .z = tex_u1,
            .w = tex_v1,
        },
        .base_color_and_intensity = .{
            .x = base_rgb.r,
            .y = base_rgb.g,
            .z = base_rgb.b,
            .w = opts.base_color_intensity,
        },
        .alpha_and_shadow_color = .{
            .x = opts.alpha_mult,
            .y = shadow_rgb.r,
            .z = shadow_rgb.g,
            .w = shadow_rgb.b,
        },
        .texel_and_text_data = .{
            .x = texel_w,
            .y = texel_h,
            .z = 0.0,
            .w = 0.0,
        },
        .outline_color_and_w = .{
            .x = shadow_rgb.r,
            .y = shadow_rgb.g,
            .z = shadow_rgb.b,
            .w = 0.5,
        },
        .render_type = render_type,
    };

    var x2 = x_cos + x_sin + scaled_x;
    var tex_u2 = atlas_data.tex_u + atlas_data.tex_w;
    if (x2 < scaled_min_x) {
        const scale = (scaled_min_x - x2) / scaled_w;
        x2 = scaled_min_x;
        tex_u2 += scale * atlas_data.tex_w;
    } else if (x2 > scaled_max_x) {
        const scale = (x2 - scaled_max_x) / scaled_w;
        x2 = scaled_max_x;
        tex_u2 -= scale * atlas_data.tex_w;
    }

    var y2 = y_sin - y_cos + scaled_y;
    var tex_v2 = atlas_data.tex_v + atlas_data.tex_h;
    if (y2 < scaled_min_y) {
        const scale = (scaled_min_y - y2) / scaled_h;
        y2 = scaled_min_y;
        tex_v2 -= scale * atlas_data.tex_h;
    } else if (y2 > scaled_max_y) {
        const scale = (y2 - scaled_max_y) / scaled_h;
        y2 = scaled_max_y;
        tex_v2 += scale * atlas_data.tex_h;
    }

    base_vert_data[idx_new + 1] = BaseVertexData{
        .pos_uv = .{
            .x = x2,
            .y = y2,
            .z = tex_u2,
            .w = tex_v2,
        },
        .base_color_and_intensity = .{
            .x = base_rgb.r,
            .y = base_rgb.g,
            .z = base_rgb.b,
            .w = opts.base_color_intensity,
        },
        .alpha_and_shadow_color = .{
            .x = opts.alpha_mult,
            .y = shadow_rgb.r,
            .z = shadow_rgb.g,
            .w = shadow_rgb.b,
        },
        .texel_and_text_data = .{
            .x = texel_w,
            .y = texel_h,
            .z = 0.0,
            .w = 0.0,
        },
        .outline_color_and_w = .{
            .x = shadow_rgb.r,
            .y = shadow_rgb.g,
            .z = shadow_rgb.b,
            .w = 0.5,
        },
        .render_type = render_type,
    };

    var x3 = x_cos - x_sin + scaled_x;
    var tex_u3 = atlas_data.tex_u + atlas_data.tex_w;
    if (x3 < scaled_min_x) {
        const scale = (scaled_min_x - x3) / scaled_w;
        x3 = scaled_min_x;
        tex_u3 += scale * atlas_data.tex_w;
    } else if (x3 > scaled_max_x) {
        const scale = (x3 - scaled_max_x) / scaled_w;
        x3 = scaled_max_x;
        tex_u3 -= scale * atlas_data.tex_w;
    }

    var y3 = y_sin + y_cos + scaled_y;
    var tex_v3 = atlas_data.tex_v;
    if (y3 < scaled_min_y) {
        const scale = (scaled_min_y - y3) / scaled_h;
        y3 = scaled_min_y;
        tex_v3 -= scale * atlas_data.tex_h;
    } else if (y3 > scaled_max_y) {
        const scale = (y3 - scaled_max_y) / scaled_h;
        y3 = scaled_max_y;
        tex_v3 += scale * atlas_data.tex_h;
    }

    base_vert_data[idx_new + 2] = BaseVertexData{
        .pos_uv = .{
            .x = x3,
            .y = y3,
            .z = tex_u3,
            .w = tex_v3,
        },
        .base_color_and_intensity = .{
            .x = base_rgb.r,
            .y = base_rgb.g,
            .z = base_rgb.b,
            .w = opts.base_color_intensity,
        },
        .alpha_and_shadow_color = .{
            .x = opts.alpha_mult,
            .y = shadow_rgb.r,
            .z = shadow_rgb.g,
            .w = shadow_rgb.b,
        },
        .texel_and_text_data = .{
            .x = texel_w,
            .y = texel_h,
            .z = 0.0,
            .w = 0.0,
        },
        .outline_color_and_w = .{
            .x = shadow_rgb.r,
            .y = shadow_rgb.g,
            .z = shadow_rgb.b,
            .w = 0.5,
        },
        .render_type = render_type,
    };

    var x4 = -x_cos - x_sin + scaled_x;
    var tex_u4 = atlas_data.tex_u;
    if (x4 < scaled_min_x) {
        const scale = (scaled_min_x - x4) / scaled_w;
        x4 = scaled_min_x;
        tex_u4 += scale * atlas_data.tex_w;
    } else if (x4 > scaled_max_x) {
        const scale = (x4 - scaled_max_x) / scaled_w;
        x4 = scaled_max_x;
        tex_u4 -= scale * atlas_data.tex_w;
    }

    var y4 = -y_sin + y_cos + scaled_y;
    var tex_v4 = atlas_data.tex_v;
    if (y4 < scaled_min_y) {
        const scale = (scaled_min_y - y4) / scaled_h;
        y4 = scaled_min_y;
        tex_v4 -= scale * atlas_data.tex_h;
    } else if (y4 > scaled_max_y) {
        const scale = (y4 - scaled_max_y) / scaled_h;
        y4 = scaled_max_y;
        tex_v4 += scale * atlas_data.tex_h;
    }

    base_vert_data[idx_new + 3] = BaseVertexData{
        .pos_uv = .{
            .x = x4,
            .y = y4,
            .z = tex_u4,
            .w = tex_v4,
        },
        .base_color_and_intensity = .{
            .x = base_rgb.r,
            .y = base_rgb.g,
            .z = base_rgb.b,
            .w = opts.base_color_intensity,
        },
        .alpha_and_shadow_color = .{
            .x = opts.alpha_mult,
            .y = shadow_rgb.r,
            .z = shadow_rgb.g,
            .w = shadow_rgb.b,
        },
        .texel_and_text_data = .{
            .x = texel_w,
            .y = texel_h,
            .z = 0.0,
            .w = 0.0,
        },
        .outline_color_and_w = .{
            .x = shadow_rgb.r,
            .y = shadow_rgb.g,
            .z = shadow_rgb.b,
            .w = 0.5,
        },
        .render_type = render_type,
    };

    return idx_new + 4;
}

fn drawQuadVerts(
    idx: u16,
    x1: f32,
    y1: f32,
    x2: f32,
    y2: f32,
    x3: f32,
    y3: f32,
    x4: f32,
    y4: f32,
    atlas_data: assets.AtlasData,
    noalias draw_data: *const DrawData,
    noalias opts: *const QuadOptions,
) u16 {
    var idx_new = idx;

    if (idx_new == base_batch_vert_size) {
        draw_data.encoder.writeBuffer(
            draw_data.buffer,
            0,
            BaseVertexData,
            base_vert_data[0..base_batch_vert_size],
        );
        endDraw(
            draw_data,
            base_batch_vert_size * @sizeOf(BaseVertexData),
            @divExact(base_batch_vert_size, 4) * 6,
            null,
        );
        idx_new = 0;
    }

    var base_rgb = element.RGBF32.fromValues(-1.0, -1.0, -1.0);
    if (opts.base_color != std.math.maxInt(u32))
        base_rgb = element.RGBF32.fromInt(opts.base_color);

    var shadow_rgb = element.RGBF32.fromValues(0.0, 0.0, 0.0);
    if (opts.shadow_color != std.math.maxInt(u32))
        shadow_rgb = element.RGBF32.fromInt(opts.shadow_color);

    const texel_w = assets.base_texel_w * opts.shadow_texel_mult;
    const texel_h = assets.base_texel_h * opts.shadow_texel_mult;

    const render_type: f32 = if (settings.enable_glow)
        quad_render_type
    else
        quad_glow_off_render_type;

    base_vert_data[idx_new] = BaseVertexData{
        .pos_uv = .{
            .x = x1,
            .y = y1,
            .z = atlas_data.tex_u,
            .w = atlas_data.tex_v,
        },
        .base_color_and_intensity = .{
            .x = base_rgb.r,
            .y = base_rgb.g,
            .z = base_rgb.b,
            .w = opts.base_color_intensity,
        },
        .alpha_and_shadow_color = .{
            .x = opts.alpha_mult,
            .y = shadow_rgb.r,
            .z = shadow_rgb.g,
            .w = shadow_rgb.b,
        },
        .texel_and_text_data = .{
            .x = texel_w,
            .y = texel_h,
            .z = 0.0,
            .w = 0.0,
        },
        .outline_color_and_w = .{
            .x = shadow_rgb.r,
            .y = shadow_rgb.g,
            .z = shadow_rgb.b,
            .w = 0.5,
        },
        .render_type = render_type,
    };

    base_vert_data[idx_new + 1] = BaseVertexData{
        .pos_uv = .{
            .x = x2,
            .y = y2,
            .z = atlas_data.tex_u + atlas_data.tex_w,
            .w = atlas_data.tex_v,
        },
        .base_color_and_intensity = .{
            .x = base_rgb.r,
            .y = base_rgb.g,
            .z = base_rgb.b,
            .w = opts.base_color_intensity,
        },
        .alpha_and_shadow_color = .{
            .x = opts.alpha_mult,
            .y = shadow_rgb.r,
            .z = shadow_rgb.g,
            .w = shadow_rgb.b,
        },
        .texel_and_text_data = .{
            .x = texel_w,
            .y = texel_h,
            .z = 0.0,
            .w = 0.0,
        },
        .outline_color_and_w = .{
            .x = shadow_rgb.r,
            .y = shadow_rgb.g,
            .z = shadow_rgb.b,
            .w = 0.5,
        },
        .render_type = render_type,
    };

    base_vert_data[idx_new + 2] = BaseVertexData{
        .pos_uv = .{
            .x = x3,
            .y = y3,
            .z = atlas_data.tex_u + atlas_data.tex_w,
            .w = atlas_data.tex_v + atlas_data.tex_h,
        },
        .base_color_and_intensity = .{
            .x = base_rgb.r,
            .y = base_rgb.g,
            .z = base_rgb.b,
            .w = opts.base_color_intensity,
        },
        .alpha_and_shadow_color = .{
            .x = opts.alpha_mult,
            .y = shadow_rgb.r,
            .z = shadow_rgb.g,
            .w = shadow_rgb.b,
        },
        .texel_and_text_data = .{
            .x = texel_w,
            .y = texel_h,
            .z = 0.0,
            .w = 0.0,
        },
        .outline_color_and_w = .{
            .x = shadow_rgb.r,
            .y = shadow_rgb.g,
            .z = shadow_rgb.b,
            .w = 0.5,
        },
        .render_type = render_type,
    };

    base_vert_data[idx_new + 3] = BaseVertexData{
        .pos_uv = .{
            .x = x4,
            .y = y4,
            .z = atlas_data.tex_u,
            .w = atlas_data.tex_v + atlas_data.tex_h,
        },
        .base_color_and_intensity = .{
            .x = base_rgb.r,
            .y = base_rgb.g,
            .z = base_rgb.b,
            .w = opts.base_color_intensity,
        },
        .alpha_and_shadow_color = .{
            .x = opts.alpha_mult,
            .y = shadow_rgb.r,
            .z = shadow_rgb.g,
            .w = shadow_rgb.b,
        },
        .texel_and_text_data = .{
            .x = texel_w,
            .y = texel_h,
            .z = 0.0,
            .w = 0.0,
        },
        .outline_color_and_w = .{
            .x = shadow_rgb.r,
            .y = shadow_rgb.g,
            .z = shadow_rgb.b,
            .w = 0.5,
        },
        .render_type = render_type,
    };

    return idx_new + 4;
}

fn drawSquare(
    idx: u16,
    x1: f32,
    y1: f32,
    x2: f32,
    y2: f32,
    x3: f32,
    y3: f32,
    x4: f32,
    y4: f32,
    atlas_data: assets.AtlasData,
    u_offset: f32,
    v_offset: f32,
    left_blend_u: f32,
    left_blend_v: f32,
    top_blend_u: f32,
    top_blend_v: f32,
    right_blend_u: f32,
    right_blend_v: f32,
    bottom_blend_u: f32,
    bottom_blend_v: f32,
) void {
    ground_vert_data[idx] = GroundVertexData{
        .pos_uv = .{
            .x = x1,
            .y = y1,
            .z = atlas_data.tex_w,
            .w = atlas_data.tex_h,
        },
        .left_top_blend_uv = .{
            .x = left_blend_u,
            .y = left_blend_v,
            .z = top_blend_u,
            .w = top_blend_v,
        },
        .right_bottom_blend_uv = .{
            .x = right_blend_u,
            .y = right_blend_v,
            .z = bottom_blend_u,
            .w = bottom_blend_v,
        },
        .base_and_offset_uv = .{
            .x = atlas_data.tex_u,
            .y = atlas_data.tex_v,
            .z = u_offset,
            .w = v_offset,
        },
    };

    ground_vert_data[idx + 1] = GroundVertexData{
        .pos_uv = .{
            .x = x2,
            .y = y2,
            .z = 0,
            .w = atlas_data.tex_h,
        },
        .left_top_blend_uv = .{
            .x = left_blend_u,
            .y = left_blend_v,
            .z = top_blend_u,
            .w = top_blend_v,
        },
        .right_bottom_blend_uv = .{
            .x = right_blend_u,
            .y = right_blend_v,
            .z = bottom_blend_u,
            .w = bottom_blend_v,
        },
        .base_and_offset_uv = .{
            .x = atlas_data.tex_u,
            .y = atlas_data.tex_v,
            .z = u_offset,
            .w = v_offset,
        },
    };

    ground_vert_data[idx + 2] = GroundVertexData{
        .pos_uv = .{
            .x = x3,
            .y = y3,
            .z = 0,
            .w = 0,
        },
        .left_top_blend_uv = .{
            .x = left_blend_u,
            .y = left_blend_v,
            .z = top_blend_u,
            .w = top_blend_v,
        },
        .right_bottom_blend_uv = .{
            .x = right_blend_u,
            .y = right_blend_v,
            .z = bottom_blend_u,
            .w = bottom_blend_v,
        },
        .base_and_offset_uv = .{
            .x = atlas_data.tex_u,
            .y = atlas_data.tex_v,
            .z = u_offset,
            .w = v_offset,
        },
    };

    ground_vert_data[idx + 3] = GroundVertexData{
        .pos_uv = .{
            .x = x4,
            .y = y4,
            .z = atlas_data.tex_w,
            .w = 0,
        },
        .left_top_blend_uv = .{
            .x = left_blend_u,
            .y = left_blend_v,
            .z = top_blend_u,
            .w = top_blend_v,
        },
        .right_bottom_blend_uv = .{
            .x = right_blend_u,
            .y = right_blend_v,
            .z = bottom_blend_u,
            .w = bottom_blend_v,
        },
        .base_and_offset_uv = .{
            .x = atlas_data.tex_u,
            .y = atlas_data.tex_v,
            .z = u_offset,
            .w = v_offset,
        },
    };
}

fn drawText(
    idx: u16,
    x: f32,
    y: f32,
    noalias text_data: *const element.TextData,
    noalias draw_data: *const DrawData,
) u16 {
    // this is extremely bad, but the alternative is even worse
    while (!@constCast(text_data)._lock.tryLock()) {}
    defer @constCast(text_data)._lock.unlock();

    // text data not initiated
    if (text_data._line_widths == null)
        return idx;

    var idx_new = idx;

    const rgb = element.RGBF32.fromInt(text_data.color);
    const shadow_rgb = element.RGBF32.fromInt(text_data.shadow_color);
    const outline_rgb = element.RGBF32.fromInt(text_data.outline_color);

    const size_scale = text_data.size / assets.CharacterData.size * camera.scale * assets.CharacterData.padding_mult;
    var line_height = assets.CharacterData.line_height * assets.CharacterData.size * size_scale;

    const max_width_off = text_data.max_width == std.math.floatMax(f32);
    const max_height_off = text_data.max_height == std.math.floatMax(f32);

    var render_type: f32 = text_normal_render_type;
    if (text_data.shadow_texel_offset_mult != 0) {
        render_type = if (text_data.disable_subpixel) text_drop_shadow_no_subpixel_render_type else text_drop_shadow_render_type;
    } else {
        render_type = if (text_data.disable_subpixel) text_normal_no_subpixel_render_type else text_normal_render_type;
    }

    const start_x = x - camera.screen_width / 2.0;
    const start_y = y - camera.screen_height / 2.0 + line_height;
    const y_base = switch (text_data.vert_align) {
        .top => start_y,
        .middle => if (max_height_off) start_y else start_y + (text_data.max_height - text_data._height) / 2,
        .bottom => if (max_height_off) start_y else start_y + text_data.max_height - text_data._height,
    };
    var line_idx: u16 = 1;
    var x_base = switch (text_data.hori_align) {
        .left => start_x,
        .middle => if (max_width_off) start_x else start_x + (text_data.max_width - text_data._line_widths.?.items[0]) / 2,
        .right => if (max_width_off) start_x else start_x + text_data.max_width - text_data._line_widths.?.items[0],
    };
    var x_pointer = x_base;
    var y_pointer = y_base;
    var current_color = rgb;
    var current_size = size_scale;
    var current_type = text_data.text_type;
    var index_offset: u16 = 0;
    for (0..text_data.text.len) |i| {
        if (i + index_offset >= text_data.text.len)
            return idx_new;

        const char = text_data.text[i + index_offset];
        specialChar: {
            if (!text_data.handle_special_chars)
                break :specialChar;

            if (char == '&') {
                const start_idx = i + index_offset + 3;
                if (text_data.text.len <= start_idx or text_data.text[start_idx - 1] != '=')
                    break :specialChar;

                switch (text_data.text[start_idx - 2]) {
                    'c' => {
                        if (text_data.text.len < start_idx + 6)
                            break :specialChar;

                        const int_color = std.fmt.parseInt(u32, text_data.text[start_idx .. start_idx + 6], 16) catch 0;
                        current_color = element.RGBF32.fromInt(int_color);
                        index_offset += 8;
                        continue;
                    },
                    's' => {
                        var size_len: u8 = 0;
                        while (start_idx + size_len < text_data.text.len and std.ascii.isDigit(text_data.text[start_idx + size_len])) {
                            size_len += 1;
                        }

                        if (size_len == 0)
                            break :specialChar;

                        const size = std.fmt.parseFloat(f32, text_data.text[start_idx .. start_idx + size_len]) catch 16.0;
                        current_size = size / assets.CharacterData.size * camera.scale * assets.CharacterData.padding_mult;
                        line_height = assets.CharacterData.line_height * assets.CharacterData.size * current_size;
                        index_offset += 2 + size_len;
                        continue;
                    },
                    't' => {
                        switch (text_data.text[start_idx]) {
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
        const mod_char = if (text_data.password) '*' else char;

        const char_data = switch (current_type) {
            .medium => assets.medium_chars[mod_char],
            .medium_italic => assets.medium_italic_chars[mod_char],
            .bold => assets.bold_chars[mod_char],
            .bold_italic => assets.bold_italic_chars[mod_char],
        };

        const shadow_texel_w = text_data.shadow_texel_offset_mult / char_data.atlas_w;
        const shadow_texel_h = text_data.shadow_texel_offset_mult / char_data.atlas_h;

        var next_x_pointer = x_pointer + char_data.x_advance * current_size;
        if (char == '\n' or next_x_pointer - x_base > text_data.max_width) {
            y_pointer += line_height;
            if (y_pointer - y_base > text_data.max_height)
                return idx_new;

            x_base = switch (text_data.hori_align) {
                .left => start_x,
                .middle => if (max_width_off) start_x else start_x + (text_data.max_width - text_data._line_widths.?.items[line_idx]) / 2,
                .right => if (max_width_off) start_x else start_x + text_data.max_width - text_data._line_widths.?.items[line_idx],
            };
            x_pointer = x_base;
            next_x_pointer = x_base + char_data.x_advance * current_size;
            line_idx += 1;
        }

        if (char_data.tex_w <= 0) {
            x_pointer += char_data.x_advance * current_size;
            continue;
        }

        const w = char_data.width * current_size;
        const h = char_data.height * current_size;
        const scaled_x = (x_pointer + char_data.x_offset * current_size + w / 2) * camera.clip_scale_x;
        const scaled_y = -(y_pointer - char_data.y_offset * current_size - h / 2) * camera.clip_scale_y;
        const scaled_w = w * camera.clip_scale_x;
        const scaled_h = h * camera.clip_scale_y;
        const px_range = assets.CharacterData.px_range / camera.scale;

        // text type could be incorporated into render type, would save us another vertex block and reduce branches
        // would be hell to maintain and extend though...
        const text_type: f32 = @floatFromInt(@intFromEnum(current_type));

        const dont_scissor = element.ScissorRect.dont_scissor;
        const scaled_min_x = if (text_data.scissor.min_x != dont_scissor)
            (text_data.scissor.min_x + start_x) * camera.clip_scale_x
        else
            -1.0;
        const scaled_max_x = if (text_data.scissor.max_x != dont_scissor)
            (text_data.scissor.max_x + start_x) * camera.clip_scale_x
        else
            1.0;

        // have to flip these, y is inverted... should be fixed later
        const scaled_min_y = if (text_data.scissor.max_y != dont_scissor)
            -(text_data.scissor.max_y + start_y - line_height) * camera.clip_scale_y
        else
            -1.0;
        const scaled_max_y = if (text_data.scissor.min_y != dont_scissor)
            -(text_data.scissor.min_y + start_y - line_height) * camera.clip_scale_y
        else
            1.0;

        x_pointer = next_x_pointer;

        var x1 = scaled_w * -0.5 + scaled_x;
        var tex_u1 = char_data.tex_u;
        if (x1 < scaled_min_x) {
            const scale = (scaled_min_x - x1) / scaled_w;
            x1 = scaled_min_x;
            tex_u1 += scale * char_data.tex_w;
        } else if (x1 > scaled_max_x) {
            const scale = (x1 - scaled_max_x) / scaled_w;
            x1 = scaled_max_x;
            tex_u1 -= scale * char_data.tex_w;
        }

        var y1 = scaled_h * 0.5 + scaled_y;
        var tex_v1 = char_data.tex_v;
        if (y1 < scaled_min_y) {
            const scale = (scaled_min_y - y1) / scaled_h;
            y1 = scaled_min_y;
            tex_v1 -= scale * char_data.tex_h;
        } else if (y1 > scaled_max_y) {
            const scale = (y1 - scaled_max_y) / scaled_h;
            y1 = scaled_max_y;
            tex_v1 += scale * char_data.tex_h;
        }

        base_vert_data[idx_new] = BaseVertexData{
            .pos_uv = .{
                .x = x1,
                .y = y1,
                .z = tex_u1,
                .w = tex_v1,
            },
            .base_color_and_intensity = .{
                .x = current_color.r,
                .y = current_color.g,
                .z = current_color.b,
                .w = 1.0,
            },
            .alpha_and_shadow_color = .{
                .x = text_data.alpha,
                .y = shadow_rgb.r,
                .z = shadow_rgb.g,
                .w = shadow_rgb.b,
            },
            .texel_and_text_data = .{
                .x = shadow_texel_w,
                .y = shadow_texel_h,
                .z = current_size * px_range,
                .w = text_type,
            },
            .outline_color_and_w = .{
                .x = outline_rgb.r,
                .y = outline_rgb.g,
                .z = outline_rgb.b,
                .w = text_data.outline_width,
            },
            .render_type = render_type,
        };

        var x2 = scaled_w * 0.5 + scaled_x;
        var tex_u2 = char_data.tex_u + char_data.tex_w;
        if (x2 < scaled_min_x) {
            const scale = (scaled_min_x - x2) / scaled_w;
            x2 = scaled_min_x;
            tex_u2 += scale * char_data.tex_w;
        } else if (x2 > scaled_max_x) {
            const scale = (x2 - scaled_max_x) / scaled_w;
            x2 = scaled_max_x;
            tex_u2 -= scale * char_data.tex_w;
        }

        var y2 = scaled_h * 0.5 + scaled_y;
        var tex_v2 = char_data.tex_v;
        if (y2 < scaled_min_y) {
            const scale = (scaled_min_y - y2) / scaled_h;
            y2 = scaled_min_y;
            tex_v2 -= scale * char_data.tex_h;
        } else if (y2 > scaled_max_y) {
            const scale = (y2 - scaled_max_y) / scaled_h;
            y2 = scaled_max_y;
            tex_v2 += scale * char_data.tex_h;
        }

        base_vert_data[idx_new + 1] = BaseVertexData{
            .pos_uv = .{
                .x = x2,
                .y = y2,
                .z = tex_u2,
                .w = tex_v2,
            },
            .base_color_and_intensity = .{
                .x = current_color.r,
                .y = current_color.g,
                .z = current_color.b,
                .w = 1.0,
            },
            .alpha_and_shadow_color = .{
                .x = text_data.alpha,
                .y = shadow_rgb.r,
                .z = shadow_rgb.g,
                .w = shadow_rgb.b,
            },
            .texel_and_text_data = .{
                .x = shadow_texel_w,
                .y = shadow_texel_h,
                .z = current_size * px_range,
                .w = text_type,
            },
            .outline_color_and_w = .{
                .x = outline_rgb.r,
                .y = outline_rgb.g,
                .z = outline_rgb.b,
                .w = text_data.outline_width,
            },
            .render_type = render_type,
        };

        var x3 = scaled_w * 0.5 + scaled_x;
        var tex_u3 = char_data.tex_u + char_data.tex_w;
        if (x3 < scaled_min_x) {
            const scale = (scaled_min_x - x3) / scaled_w;
            x3 = scaled_min_x;
            tex_u3 += scale * char_data.tex_w;
        } else if (x3 > scaled_max_x) {
            const scale = (x3 - scaled_max_x) / scaled_w;
            x3 = scaled_max_x;
            tex_u3 -= scale * char_data.tex_w;
        }

        var y3 = scaled_h * -0.5 + scaled_y;
        var tex_v3 = char_data.tex_v + char_data.tex_h;
        if (y3 < scaled_min_y) {
            const scale = (scaled_min_y - y3) / scaled_h;
            y3 = scaled_min_y;
            tex_v3 -= scale * char_data.tex_h;
        } else if (y3 > scaled_max_y) {
            const scale = (y3 - scaled_max_y) / scaled_h;
            y3 = scaled_max_y;
            tex_v3 += scale * char_data.tex_h;
        }

        base_vert_data[idx_new + 2] = BaseVertexData{
            .pos_uv = .{
                .x = x3,
                .y = y3,
                .z = tex_u3,
                .w = tex_v3,
            },
            .base_color_and_intensity = .{
                .x = current_color.r,
                .y = current_color.g,
                .z = current_color.b,
                .w = 1.0,
            },
            .alpha_and_shadow_color = .{
                .x = text_data.alpha,
                .y = shadow_rgb.r,
                .z = shadow_rgb.g,
                .w = shadow_rgb.b,
            },
            .texel_and_text_data = .{
                .x = shadow_texel_w,
                .y = shadow_texel_h,
                .z = current_size * px_range,
                .w = text_type,
            },
            .outline_color_and_w = .{
                .x = outline_rgb.r,
                .y = outline_rgb.g,
                .z = outline_rgb.b,
                .w = text_data.outline_width,
            },
            .render_type = render_type,
        };

        var x4 = scaled_w * -0.5 + scaled_x;
        var tex_u4 = char_data.tex_u;
        if (x4 < scaled_min_x) {
            const scale = (scaled_min_x - x4) / scaled_w;
            x4 = scaled_min_x;
            tex_u4 += scale * char_data.tex_w;
        } else if (x4 > scaled_max_x) {
            const scale = (x4 - scaled_max_x) / scaled_w;
            x4 = scaled_max_x;
            tex_u4 -= scale * char_data.tex_w;
        }

        var y4 = scaled_h * -0.5 + scaled_y;
        var tex_v4 = char_data.tex_v + char_data.tex_h;
        if (y4 < scaled_min_y) {
            const scale = (scaled_min_y - y4) / scaled_h;
            y4 = scaled_min_y;
            tex_v4 -= scale * char_data.tex_h;
        } else if (y4 > scaled_max_y) {
            const scale = (y4 - scaled_max_y) / scaled_h;
            y4 = scaled_max_y;
            tex_v4 += scale * char_data.tex_h;
        }

        base_vert_data[idx_new + 3] = BaseVertexData{
            .pos_uv = .{
                .x = x4,
                .y = y4,
                .z = tex_u4,
                .w = tex_v4,
            },
            .base_color_and_intensity = .{
                .x = current_color.r,
                .y = current_color.g,
                .z = current_color.b,
                .w = 1.0,
            },
            .alpha_and_shadow_color = .{
                .x = text_data.alpha,
                .y = shadow_rgb.r,
                .z = shadow_rgb.g,
                .w = shadow_rgb.b,
            },
            .texel_and_text_data = .{
                .x = shadow_texel_w,
                .y = shadow_texel_h,
                .z = current_size * px_range,
                .w = text_type,
            },
            .outline_color_and_w = .{
                .x = outline_rgb.r,
                .y = outline_rgb.g,
                .z = outline_rgb.b,
                .w = text_data.outline_width,
            },
            .render_type = render_type,
        };

        idx_new += 4;

        if (idx == base_batch_vert_size) {
            draw_data.encoder.writeBuffer(
                draw_data.buffer,
                0,
                BaseVertexData,
                base_vert_data[0..base_batch_vert_size],
            );
            endDraw(
                draw_data,
                base_batch_vert_size * @sizeOf(BaseVertexData),
                @divExact(base_batch_vert_size, 4) * 6,
                null,
            );
            idx_new = 0;
        }
    }

    return idx_new;
}

fn drawNineSlice(
    idx: u16,
    x: f32,
    y: f32,
    noalias image_data: *const element.NineSliceImageData,
    noalias draw_data: *const DrawData,
) u16 {
    var idx_new = idx;

    const opts: *const QuadOptions = &.{
        .alpha_mult = image_data.alpha,
        .ui_quad = true,
        .scissor = image_data.scissor,
        .base_color = image_data.color,
        .base_color_intensity = image_data.color_intensity,
    };

    const w = image_data.w;
    const h = image_data.h;

    const top_left = image_data.topLeft();
    const top_left_w = top_left.texWRaw();
    const top_left_h = top_left.texHRaw();
    idx_new = drawQuad(idx_new, x, y, top_left_w, top_left_h, top_left, draw_data, opts);

    const top_right = image_data.topRight();
    const top_right_w = top_right.texWRaw();
    idx_new = drawQuad(idx_new, x + (w - top_right_w), y, top_right_w, top_right.texHRaw(), top_right, draw_data, opts);

    const bottom_left = image_data.bottomLeft();
    const bottom_left_w = bottom_left.texWRaw();
    const bottom_left_h = bottom_left.texHRaw();
    idx_new = drawQuad(idx_new, x, y + (h - bottom_left_h), bottom_left.texWRaw(), bottom_left_h, bottom_left, draw_data, opts);

    const bottom_right = image_data.bottomRight();
    const bottom_right_w = bottom_right.texWRaw();
    const bottom_right_h = bottom_right.texHRaw();
    idx_new = drawQuad(idx_new, x + (w - bottom_right_w), y + (h - bottom_right_h), bottom_right_w, bottom_right_h, bottom_right, draw_data, opts);

    const top_center = image_data.topCenter();
    idx_new = drawQuad(idx_new, x + top_left_w, y, w - top_left_w - top_right_w, top_center.texHRaw(), top_center, draw_data, opts);

    const bottom_center = image_data.bottomCenter();
    const bottom_center_h = bottom_center.texHRaw();
    idx_new = drawQuad(idx_new, x + bottom_left_w, y + (h - bottom_center_h), w - bottom_left_w - bottom_right_w, bottom_center_h, bottom_center, draw_data, opts);

    const middle_center = image_data.middleCenter();
    idx_new = drawQuad(idx_new, x + top_left_w, y + top_left_h, w - top_left_w - top_right_w, h - top_left_h - bottom_left_h, middle_center, draw_data, opts);

    const middle_left = image_data.middleLeft();
    idx_new = drawQuad(idx_new, x, y + top_left_h, middle_left.texWRaw(), h - top_left_h - bottom_left_h, middle_left, draw_data, opts);

    const middle_right = image_data.middleRight();
    const middle_right_w = middle_right.texWRaw();
    idx_new = drawQuad(idx_new, x + (w - middle_right_w), y + top_left_h, middle_right_w, h - top_left_h - bottom_left_h, middle_right, draw_data, opts);

    return idx_new;
}

fn drawLight(idx: u16, w: f32, h: f32, x: f32, y: f32, color: u32, intensity: f32) u16 {
    const rgb = element.RGBF32.fromInt(color);

    // 2x normal size
    const scaled_w = w * 4 * camera.clip_scale_x * camera.scale;
    const scaled_h = h * 4 * camera.clip_scale_y * camera.scale;
    const scaled_x = (x - camera.screen_width / 2.0) * camera.clip_scale_x;
    const scaled_y = -(y - camera.screen_height / 2.0) * camera.clip_scale_y;

    light_vert_data[idx] = LightVertexData{
        .pos = [2]f32{ scaled_w * -0.5 + scaled_x, scaled_h * 0.5 + scaled_y },
        .uv = [2]f32{ 1, 1 },
        .color = rgb,
        .intensity = intensity,
    };

    light_vert_data[idx + 1] = LightVertexData{
        .pos = [2]f32{ scaled_w * 0.5 + scaled_x, scaled_h * 0.5 + scaled_y },
        .uv = [2]f32{ 0, 1 },
        .color = rgb,
        .intensity = intensity,
    };

    light_vert_data[idx + 2] = LightVertexData{
        .pos = [2]f32{ scaled_w * 0.5 + scaled_x, scaled_h * -0.5 + scaled_y },
        .uv = [2]f32{ 0, 0 },
        .color = rgb,
        .intensity = intensity,
    };

    light_vert_data[idx + 3] = LightVertexData{
        .pos = [2]f32{ scaled_w * -0.5 + scaled_x, scaled_h * -0.5 + scaled_y },
        .uv = [2]f32{ 1, 0 },
        .color = rgb,
        .intensity = intensity,
    };

    return idx + 4;
}

fn drawElement(idx: u16, elem: element.UiElement, noalias draw_data: *const DrawData, cam_x: f32, cam_y: f32, x_offset: f32, y_offset: f32, time: i64) u16 {
    var ui_idx = idx;
    switch (elem) {
        .image => |image| {
            if (!image.visible)
                return ui_idx;

            switch (image.image_data) {
                .nine_slice => |nine_slice| ui_idx = drawNineSlice(ui_idx, image.x + x_offset, image.y + y_offset, &nine_slice, draw_data),
                .normal => |image_data| {
                    const opts: *const QuadOptions = &.{
                        .alpha_mult = image_data.alpha,
                        .ui_quad = image.ui_quad,
                        .scissor = image_data.scissor,
                        .base_color = image_data.color,
                        .base_color_intensity = image_data.color_intensity,
                        .shadow_texel_mult = if (image_data.glow) 2.0 / @max(image_data.scale_x, image_data.scale_y) else 0.0,
                    };
                    ui_idx = drawQuad(ui_idx, image.x + x_offset, image.y + y_offset, image_data.width(), image_data.height(), image_data.atlas_data, draw_data, opts);
                },
            }

            if (image.is_minimap_decor) {
                const float_w: f32 = @floatFromInt(map.width);
                const float_h: f32 = @floatFromInt(map.height);
                const zoom = camera.minimap_zoom;
                ui_idx = drawMinimap(
                    ui_idx,
                    image.x + image.minimap_offset_x + x_offset,
                    image.y + image.minimap_offset_y + y_offset,
                    image.minimap_width,
                    image.minimap_height,
                    cam_x,
                    cam_y,
                    float_w / zoom,
                    float_h / zoom,
                    0,
                    draw_data,
                    .{
                        .min_x = 0,
                        .min_y = 0,
                        .max_x = image.minimap_width,
                        .max_y = image.minimap_height,
                    },
                );

                const player_icon = assets.getUiData("minimap_icons", 0); // doing a hashmap lookup every frame is not wise. todo
                const scale = 2.0;
                const player_icon_w = player_icon.texWRaw() * scale;
                const player_icon_h = player_icon.texHRaw() * scale;
                ui_idx = drawQuad(
                    ui_idx,
                    image.x + image.minimap_offset_x + x_offset + (image.minimap_width - player_icon_w) / 2.0,
                    image.y + image.minimap_offset_y + y_offset + (image.minimap_height - player_icon_h) / 2.0,
                    player_icon_w,
                    player_icon_h,
                    player_icon,
                    draw_data,
                    &.{ .rotation = -camera.angle, .ui_quad = true, .force_glow_off = true, .shadow_texel_mult = 1.0 / scale },
                );
            }
        },
        .menu_bg => |menu_bg| {
            if (!menu_bg.visible)
                return ui_idx;

            ui_idx = drawMenuBackground(ui_idx, menu_bg.x + x_offset, menu_bg.y + y_offset, menu_bg.w, menu_bg.h, 0, draw_data, menu_bg.scissor);
        },
        .item => |item| {
            if (!item.visible)
                return ui_idx;

            switch (item.image_data) {
                .nine_slice => |nine_slice| {
                    ui_idx = drawNineSlice(ui_idx, item.x + x_offset, item.y + y_offset, &nine_slice, draw_data);
                },
                .normal => |image_data| {
                    const opts: *const QuadOptions = &.{
                        .shadow_texel_mult = 2.0 / @max(image_data.scale_x, image_data.scale_y),
                        .alpha_mult = image_data.alpha,
                        .ui_quad = false,
                        .scissor = image_data.scissor,
                        .base_color = image_data.color,
                        .base_color_intensity = image_data.color_intensity,
                    };
                    ui_idx = drawQuad(ui_idx, item.x + x_offset, item.y + y_offset, image_data.width(), image_data.height(), image_data.atlas_data, draw_data, opts);
                },
            }
        },
        .bar => |bar| {
            if (!bar.visible)
                return ui_idx;

            var w: f32 = 0;
            var h: f32 = 0;
            switch (bar.image_data) {
                .nine_slice => |nine_slice| {
                    w = nine_slice.w;
                    h = nine_slice.h;
                    ui_idx = drawNineSlice(ui_idx, bar.x + x_offset, bar.y + y_offset, &nine_slice, draw_data);
                },
                .normal => |image_data| {
                    w = image_data.width();
                    h = image_data.height();
                    const atlas_data = image_data.atlas_data;
                    const scale: f32 = 1.0;

                    const opts: *const QuadOptions = &.{
                        .alpha_mult = image_data.alpha,
                        .ui_quad = true,
                        .scissor = image_data.scissor,
                        .base_color = image_data.color,
                        .base_color_intensity = image_data.color_intensity,
                        .shadow_texel_mult = if (image_data.glow) 2.0 / @max(image_data.scale_x, image_data.scale_y) else 0.0,
                    };
                    ui_idx = drawQuad(ui_idx, bar.x + x_offset, bar.y + y_offset, w * scale, image_data.height(), atlas_data, draw_data, opts);
                },
            }

            ui_idx = drawText(
                ui_idx,
                bar.x + (w - bar.text_data._width) / 2 + x_offset,
                bar.y + (h - bar.text_data._height) / 2 + y_offset,
                &bar.text_data,
                draw_data,
            );
        },
        .button => |button| {
            if (!button.visible)
                return ui_idx;

            var w: f32 = 0;
            var h: f32 = 0;

            switch (button.imageData()) {
                .nine_slice => |nine_slice| {
                    w = nine_slice.w;
                    h = nine_slice.h;
                    ui_idx = drawNineSlice(ui_idx, button.x + x_offset, button.y + y_offset, &nine_slice, draw_data);
                },
                .normal => |image_data| {
                    w = image_data.width();
                    h = image_data.height();
                    const opts: *const QuadOptions = &.{
                        .alpha_mult = image_data.alpha,
                        .ui_quad = true,
                        .scissor = image_data.scissor,
                        .base_color = image_data.color,
                        .base_color_intensity = image_data.color_intensity,
                        .shadow_texel_mult = if (image_data.glow) 2.0 / @max(image_data.scale_x, image_data.scale_y) else 0.0,
                    };
                    ui_idx = drawQuad(ui_idx, button.x + x_offset, button.y + y_offset, w, h, image_data.atlas_data, draw_data, opts);
                },
            }

            if (button.text_data) |text_data| {
                ui_idx = drawText(
                    ui_idx,
                    button.x + (w - text_data._width) / 2 + x_offset,
                    button.y + (h - text_data._height) / 2 + y_offset,
                    &text_data,
                    draw_data,
                );
            }
        },
        .char_box => |char_box| {
            if (!char_box.visible)
                return ui_idx;

            var w: f32 = 0;
            var h: f32 = 0;

            switch (char_box.imageData()) {
                .nine_slice => |nine_slice| {
                    w = nine_slice.w;
                    h = nine_slice.h;
                    ui_idx = drawNineSlice(ui_idx, char_box.x + x_offset, char_box.y + y_offset, &nine_slice, draw_data);
                },
                .normal => |image_data| {
                    w = image_data.width();
                    h = image_data.height();
                    const opts: *const QuadOptions = &.{
                        .alpha_mult = image_data.alpha,
                        .ui_quad = true,
                        .scissor = image_data.scissor,
                        .base_color = image_data.color,
                        .base_color_intensity = image_data.color_intensity,
                        .shadow_texel_mult = if (image_data.glow) 2.0 / @max(image_data.scale_x, image_data.scale_y) else 0.0,
                    };
                    ui_idx = drawQuad(
                        ui_idx,
                        char_box.x + x_offset,
                        char_box.y + y_offset,
                        image_data.width(),
                        image_data.height(),
                        image_data.atlas_data,
                        draw_data,
                        opts,
                    );
                },
            }

            if (char_box.text_data) |text_data| {
                ui_idx = drawText(
                    ui_idx,
                    char_box.x + (w - text_data._width) / 2 + x_offset,
                    char_box.y + (h - text_data._height) / 2 + y_offset,
                    &text_data,
                    draw_data,
                );
            }
        },
        .text => |text| {
            if (!text.visible)
                return ui_idx;

            ui_idx = drawText(ui_idx, text.x + x_offset, text.y + y_offset, &text.text_data, draw_data);
        },
        .input_field => |input_field| {
            if (!input_field.visible)
                return ui_idx;

            var w: f32 = 0;
            var h: f32 = 0;

            switch (input_field.imageData()) {
                .nine_slice => |nine_slice| {
                    w = nine_slice.w;
                    h = nine_slice.h;
                    ui_idx = drawNineSlice(ui_idx, input_field.x + x_offset, input_field.y + y_offset, &nine_slice, draw_data);
                },
                .normal => |image_data| {
                    w = image_data.width();
                    h = image_data.height();
                    const opts: *const QuadOptions = &.{
                        .alpha_mult = image_data.alpha,
                        .ui_quad = true,
                        .scissor = image_data.scissor,
                        .base_color = image_data.color,
                        .base_color_intensity = image_data.color_intensity,
                        .shadow_texel_mult = if (image_data.glow) 2.0 / @max(image_data.scale_x, image_data.scale_y) else 0.0,
                    };
                    ui_idx = drawQuad(ui_idx, input_field.x + x_offset, input_field.y + y_offset, w, h, image_data.atlas_data, draw_data, opts);
                },
            }

            const text_x = input_field.x + input_field.text_inlay_x + x_offset + input_field._x_offset;
            const text_y = input_field.y + input_field.text_inlay_y + y_offset;
            ui_idx = drawText(ui_idx, text_x, text_y, &input_field.text_data, draw_data);

            const flash_delay = 500 * std.time.us_per_ms;
            if (input_field._last_input != -1 and (time - input_field._last_input < flash_delay or @mod(@divFloor(time, flash_delay), 2) == 0)) {
                const cursor_x = text_x + input_field.text_data._width;
                switch (input_field.cursor_image_data) {
                    .nine_slice => |nine_slice| ui_idx = drawNineSlice(ui_idx, cursor_x, text_y, &nine_slice, draw_data),
                    .normal => |image_data| {
                        const opts: *const QuadOptions = &.{
                            .alpha_mult = image_data.alpha,
                            .ui_quad = true,
                            .scissor = image_data.scissor,
                            .base_color = image_data.color,
                            .base_color_intensity = image_data.color_intensity,
                            .shadow_texel_mult = if (image_data.glow) 2.0 / @max(image_data.scale_x, image_data.scale_y) else 0.0,
                        };
                        ui_idx = drawQuad(ui_idx, cursor_x, text_y, image_data.width(), image_data.height(), image_data.atlas_data, draw_data, opts);
                    },
                }
            }
        },
        .toggle => |toggle| {
            if (!toggle.visible)
                return ui_idx;

            var w: f32 = 0;
            var h: f32 = 0;

            switch (toggle.imageData()) {
                .nine_slice => |nine_slice| {
                    w = nine_slice.w;
                    h = nine_slice.h;
                    ui_idx = drawNineSlice(ui_idx, toggle.x + x_offset, toggle.y + y_offset, &nine_slice, draw_data);
                },
                .normal => |image_data| {
                    w = image_data.width();
                    h = image_data.height();
                    const opts: *const QuadOptions = &.{
                        .alpha_mult = image_data.alpha,
                        .ui_quad = true,
                        .scissor = image_data.scissor,
                        .base_color = image_data.color,
                        .base_color_intensity = image_data.color_intensity,
                        .shadow_texel_mult = if (image_data.glow) 2.0 / @max(image_data.scale_x, image_data.scale_y) else 0.0,
                    };
                    ui_idx = drawQuad(ui_idx, toggle.x + x_offset, toggle.y + y_offset, image_data.width(), image_data.height(), image_data.atlas_data, draw_data, opts);
                },
            }

            if (toggle.text_data) |text_data| {
                const pad = 5;
                ui_idx = drawText(
                    ui_idx,
                    toggle.x + w + pad + x_offset,
                    toggle.y + (h - text_data._height) / 2 + y_offset,
                    &text_data,
                    draw_data,
                );
            }
        },
        .key_mapper => |key_mapper| {
            if (!key_mapper.visible)
                return ui_idx;

            var w: f32 = 0;
            var h: f32 = 0;

            switch (key_mapper.imageData()) {
                .nine_slice => |nine_slice| {
                    w = nine_slice.w;
                    h = nine_slice.h;
                    ui_idx = drawNineSlice(ui_idx, key_mapper.x + x_offset, key_mapper.y + y_offset, &nine_slice, draw_data);
                },
                .normal => |image_data| {
                    w = image_data.width();
                    h = image_data.height();
                    const opts: *const QuadOptions = &.{
                        .alpha_mult = image_data.alpha,
                        .ui_quad = true,
                        .scissor = image_data.scissor,
                        .base_color = image_data.color,
                        .base_color_intensity = image_data.color_intensity,
                        .shadow_texel_mult = if (image_data.glow) 2.0 / @max(image_data.scale_x, image_data.scale_y) else 0.0,
                    };
                    ui_idx = drawQuad(ui_idx, key_mapper.x + x_offset, key_mapper.y + y_offset, w, h, image_data.atlas_data, draw_data, opts);
                },
            }

            ui_idx = drawQuad(
                ui_idx,
                key_mapper.x + x_offset,
                key_mapper.y + y_offset,
                w,
                h,
                settings.getKeyTexture(key_mapper.settings_button.*),
                draw_data,
                &.{ .force_glow_off = true },
            );

            if (key_mapper.title_text_data) |text_data| {
                const pad = 5;
                ui_idx = drawText(
                    ui_idx,
                    key_mapper.x + w + pad + x_offset,
                    key_mapper.y + (h - text_data._height) / 2 + y_offset,
                    &text_data,
                    draw_data,
                );
            }
        },
        .slider => |slider| {
            if (!slider.visible)
                return ui_idx;

            switch (slider.decor_image_data) {
                .nine_slice => |nine_slice| ui_idx = drawNineSlice(
                    ui_idx,
                    slider.x + x_offset,
                    slider.y + y_offset,
                    &nine_slice,
                    draw_data,
                ),
                .normal => |image_data| {
                    const opts: *const QuadOptions = &.{
                        .alpha_mult = image_data.alpha,
                        .ui_quad = true,
                        .scissor = image_data.scissor,
                        .base_color = image_data.color,
                        .base_color_intensity = image_data.color_intensity,
                        .shadow_texel_mult = if (image_data.glow) 2.0 / @max(image_data.scale_x, image_data.scale_y) else 0.0,
                    };
                    ui_idx = drawQuad(
                        ui_idx,
                        slider.x + x_offset,
                        slider.y + y_offset,
                        slider.w,
                        slider.h,
                        image_data.atlas_data,
                        draw_data,
                        opts,
                    );
                },
            }

            if (slider.title_text_data) |text_data| {
                ui_idx = drawText(
                    ui_idx,
                    slider.x + x_offset,
                    slider.y + y_offset - slider.title_offset,
                    &text_data,
                    draw_data,
                );
            }

            const knob_image_data = slider.knob_image_data.current(slider.state);
            const knob_x = slider.x + slider._knob_x + x_offset;
            const knob_y = slider.y + slider._knob_y + y_offset;
            var knob_w: f32 = 0.0;
            var knob_h: f32 = 0.0;
            switch (knob_image_data) {
                .nine_slice => |nine_slice| {
                    ui_idx = drawNineSlice(
                        ui_idx,
                        knob_x,
                        knob_y,
                        &nine_slice,
                        draw_data,
                    );

                    knob_w = nine_slice.w;
                    knob_h = nine_slice.h;
                },
                .normal => |image_data| {
                    const opts: *const QuadOptions = &.{
                        .alpha_mult = image_data.alpha,
                        .ui_quad = true,
                        .scissor = image_data.scissor,
                        .base_color = image_data.color,
                        .base_color_intensity = image_data.color_intensity,
                        .shadow_texel_mult = if (image_data.glow) 2.0 / @max(image_data.scale_x, image_data.scale_y) else 0.0,
                    };
                    ui_idx = drawQuad(
                        ui_idx,
                        knob_x,
                        knob_y,
                        slider.w,
                        slider.h,
                        image_data.atlas_data,
                        draw_data,
                        opts,
                    );

                    knob_w = image_data.width();
                    knob_h = image_data.height();
                },
            }

            ui_idx = drawText(
                ui_idx,
                knob_x + if (slider.vertical) knob_w else 0,
                knob_y + if (slider.vertical) 0 else knob_h,
                &slider.value_text_data,
                draw_data,
            );
        },
        else => {},
    }

    return ui_idx;
}

inline fn endDraw(noalias draw_data: *const DrawData, verts: u64, indices: u32, offsets: ?[]const u32) void {
    const pass = draw_data.encoder.beginRenderPass(if (first_draw) clear_render_pass_info else load_render_pass_info);
    pass.setVertexBuffer(0, draw_data.buffer, 0, verts);
    pass.setIndexBuffer(index_buffer, .uint16, 0, indices * @sizeOf(u16));
    pass.setPipeline(draw_data.pipeline);
    pass.setBindGroup(0, draw_data.bind_group, offsets);
    pass.drawIndexed(indices, 1, 0, 0, 0);
    pass.end();
    pass.release();
    first_draw = false;
}

pub fn draw(
    time: i64,
    noalias gctx: *zgpu.GraphicsContext,
    noalias back_buffer: zgpu.wgpu.TextureView,
    noalias encoder: zgpu.wgpu.CommandEncoder,
) void {
    var light_idx: u16 = 0;

    const cam_x = camera.x.load(.Acquire);
    const cam_y = camera.y.load(.Acquire);

    const sample_count: u8 = switch (settings.aa_type) {
        .msaa2x => 2,
        .msaa4x => 4,
        else => 1,
    };

    const clear_color_attachments = if (sample_count != 1)
        [_]zgpu.wgpu.RenderPassColorAttachment{.{
            .view = gctx.lookupResource(color_texture_view).?,
            .resolve_target = back_buffer,
            .load_op = .clear,
            .store_op = .store,
        }}
    else
        [_]zgpu.wgpu.RenderPassColorAttachment{.{
            .view = back_buffer,
            .load_op = .clear,
            .store_op = .store,
        }};
    clear_render_pass_info = .{
        .color_attachment_count = clear_color_attachments.len,
        .color_attachments = &clear_color_attachments,
    };

    const load_color_attachments = if (sample_count != 1)
        [_]zgpu.wgpu.RenderPassColorAttachment{.{
            .view = gctx.lookupResource(color_texture_view).?,
            .resolve_target = back_buffer,
            .load_op = .load,
            .store_op = .store,
        }}
    else
        [_]zgpu.wgpu.RenderPassColorAttachment{.{
            .view = back_buffer,
            .load_op = .load,
            .store_op = .store,
        }};
    load_render_pass_info = .{
        .color_attachment_count = load_color_attachments.len,
        .color_attachments = &load_color_attachments,
    };

    first_draw = true;

    gamePass: {
        if ((!main.tick_frame and sc.current_screen == .game or !main.editing_map and sc.current_screen == .editor) or !map.validPos(@intFromFloat(cam_x), @intFromFloat(cam_y)))
            break :gamePass;

        const float_time_ms = @as(f32, @floatFromInt(time)) / std.time.us_per_ms;

        groundPass: {
            const pipeline = gctx.lookupResource(ground_pipeline) orelse break :groundPass;
            const bind_group = gctx.lookupResource(ground_bind_group) orelse break :groundPass;

            var square_idx: u16 = 0;
            for (camera.min_y..camera.max_y) |y| {
                for (camera.min_x..camera.max_x) |x| {
                    if (square_idx == ground_batch_vert_size) {
                        encoder.writeBuffer(
                            ground_vb,
                            0,
                            GroundVertexData,
                            ground_vert_data[0..ground_batch_vert_size],
                        );
                        endDraw(
                            &.{
                                .encoder = encoder,
                                .buffer = ground_vb,
                                .pipeline = pipeline,
                                .bind_group = bind_group,
                            },
                            ground_batch_vert_size * @sizeOf(GroundVertexData),
                            @divExact(ground_batch_vert_size, 4) / 6,
                            null,
                        );
                        square_idx = 0;
                    }

                    const dx = cam_x - @as(f32, @floatFromInt(x)) - 0.5;
                    const dy = cam_y - @as(f32, @floatFromInt(y)) - 0.5;
                    if (dx * dx + dy * dy > camera.max_dist_sq)
                        continue;

                    const map_square_idx = x + y * map.width;
                    const square = map.squares[map_square_idx];
                    if (square.tile_type == 0xFFFF or square.tile_type == 0xFF)
                        continue;

                    const screen_pos = camera.rotateAroundCameraClip(square.x, square.y);
                    const screen_x = screen_pos.x;
                    const screen_y = -screen_pos.y;

                    var u_offset = square.u_offset;
                    var v_offset = square.v_offset;
                    if (square.props != null) {
                        if (settings.enable_lights) {
                            const light_color = square.props.?.light_color;
                            if (light_color > 0) {
                                const size = camera.px_per_tile * (square.props.?.light_radius + square.props.?.light_pulse *
                                    @sin(float_time_ms / 1000.0 * square.props.?.light_pulse_speed));
                                light_idx = drawLight(
                                    light_idx,
                                    size,
                                    size,
                                    screen_pos.x + camera.screen_width / 2.0,
                                    screen_pos.y + camera.screen_height / 2.0,
                                    light_color,
                                    square.props.?.light_intensity,
                                );
                            }
                        }

                        switch (square.props.?.anim_type) {
                            .wave => {
                                u_offset += @sin(square.props.?.anim_dx * float_time_ms / 1000.0) * assets.base_texel_w;
                                v_offset += @sin(square.props.?.anim_dy * float_time_ms / 1000.0) * assets.base_texel_h;
                            },
                            .flow => {
                                u_offset += (square.props.?.anim_dx * float_time_ms / 1000.0) * assets.base_texel_w;
                                v_offset += (square.props.?.anim_dy * float_time_ms / 1000.0) * assets.base_texel_h;
                            },
                            else => {},
                        }
                    }

                    const radius = @sqrt(@as(f32, camera.px_per_tile * camera.px_per_tile / 2)) + 1;
                    const pi_div_4 = std.math.pi / 4.0;
                    const top_right_angle = pi_div_4;
                    const bottom_right_angle = 3.0 * pi_div_4;
                    const bottom_left_angle = 5.0 * pi_div_4;
                    const top_left_angle = 7.0 * pi_div_4;

                    drawSquare(
                        square_idx,
                        (screen_x + radius * @cos(top_left_angle + camera.angle)) * camera.clip_scale_x,
                        (screen_y + radius * @sin(top_left_angle + camera.angle)) * camera.clip_scale_y,
                        (screen_x + radius * @cos(bottom_left_angle + camera.angle)) * camera.clip_scale_x,
                        (screen_y + radius * @sin(bottom_left_angle + camera.angle)) * camera.clip_scale_y,
                        (screen_x + radius * @cos(bottom_right_angle + camera.angle)) * camera.clip_scale_x,
                        (screen_y + radius * @sin(bottom_right_angle + camera.angle)) * camera.clip_scale_y,
                        (screen_x + radius * @cos(top_right_angle + camera.angle)) * camera.clip_scale_x,
                        (screen_y + radius * @sin(top_right_angle + camera.angle)) * camera.clip_scale_y,
                        square.atlas_data,
                        u_offset,
                        v_offset,
                        square.left_blend_u,
                        square.left_blend_v,
                        square.top_blend_u,
                        square.top_blend_v,
                        square.right_blend_u,
                        square.right_blend_v,
                        square.bottom_blend_u,
                        square.bottom_blend_v,
                    );
                    square_idx += 4;
                }
            }

            if (square_idx > 0) {
                encoder.writeBuffer(
                    ground_vb,
                    0,
                    GroundVertexData,
                    ground_vert_data[0..square_idx],
                );
                endDraw(
                    &.{
                        .encoder = encoder,
                        .buffer = ground_vb,
                        .pipeline = pipeline,
                        .bind_group = bind_group,
                    },
                    @as(u64, square_idx) * @sizeOf(GroundVertexData),
                    @divFloor(square_idx, 4) * 6,
                    null,
                );
            }
        }

        normalPass: {
            if (map.entities.capacity <= 0)
                break :normalPass;

            const pipeline = gctx.lookupResource(base_pipeline) orelse break :normalPass;
            const bind_group = gctx.lookupResource(base_bind_group) orelse break :normalPass;

            const draw_data: *const DrawData = &.{
                .encoder = encoder,
                .buffer = base_vb,
                .pipeline = pipeline,
                .bind_group = bind_group,
            };

            while (!map.object_lock.tryLockShared()) {}
            defer map.object_lock.unlockShared();

            var idx: u16 = 0;
            for (map.entities.items) |en| {
                switch (en) {
                    .particle_effect => {},
                    .particle => |pt| {
                        switch (pt) {
                            inline else => |particle| {
                                if (!camera.visibleInCamera(particle.x, particle.y))
                                    continue;

                                const w = particle.atlas_data.texWRaw() * particle.size;
                                const h = particle.atlas_data.texHRaw() * particle.size;
                                const screen_pos = camera.rotateAroundCamera(particle.x, particle.y);
                                const z_off = particle.z * -camera.px_per_tile - (h - particle.size * assets.padding);

                                idx = drawQuad(
                                    idx,
                                    screen_pos.x - w / 2.0,
                                    screen_pos.y + z_off,
                                    w,
                                    h,
                                    particle.atlas_data,
                                    draw_data,
                                    &.{
                                        .shadow_texel_mult = 1.0 / particle.size,
                                        .alpha_mult = particle.alpha_mult,
                                        .base_color = particle.color,
                                        .base_color_intensity = 1.0,
                                        .force_glow_off = true,
                                    },
                                );
                            },
                        }
                    },
                    .player => |player| {
                        // hack just dont render players
                        if (sc.current_screen == .editor or player.dead or !camera.visibleInCamera(player.x, player.y)) {
                            continue;
                        }

                        const size = camera.size_mult * camera.scale * player.size;

                        const sec = player.anim_sector;
                        const anim_idx = player.anim_index;

                        var atlas_data = switch (player.action) {
                            assets.walk_action => player.anim_data.walk_anims[sec][1 + anim_idx],
                            assets.attack_action => player.anim_data.attack_anims[sec][anim_idx],
                            assets.stand_action => player.anim_data.walk_anims[sec][0],
                            else => unreachable,
                        };

                        var x_offset: f32 = 0.0;
                        if (player.action == assets.attack_action and anim_idx == 1) {
                            const w = atlas_data.texWRaw() * size;
                            x_offset = if (sec == assets.left_dir) -assets.padding * size else w / 4.0;
                        }

                        var sink: f32 = 1.0;
                        if (map.getSquare(player.x, player.y)) |square| {
                            if (square.tile_type != 0xFFFF) {
                                sink += if (square.props != null and square.props.?.sink and !square.protect_from_sink) 0.75 else 0;
                            }
                        }

                        atlas_data.tex_h /= sink;

                        const w = atlas_data.texWRaw() * size;
                        const h = atlas_data.texHRaw() * size;

                        var screen_pos = camera.rotateAroundCamera(player.x, player.y);
                        screen_pos.x += x_offset;
                        screen_pos.y += player.z * -camera.px_per_tile - (h - size * assets.padding);

                        var alpha_mult: f32 = player.alpha;
                        if (player.condition.invisible)
                            alpha_mult = 0.6;

                        var color: u32 = 0;
                        var color_intensity: f32 = 0.0;
                        _ = &color;
                        _ = &color_intensity;
                        // flash

                        if (settings.enable_lights and player.light_color > 0) {
                            const light_size = player.light_radius + player.light_pulse * @sin(float_time_ms / 1000.0 * player.light_pulse_speed);

                            light_idx = drawLight(
                                light_idx,
                                w * light_size,
                                h * light_size,
                                screen_pos.x,
                                screen_pos.y,
                                player.light_color,
                                player.light_intensity,
                            );
                        }

                        idx = drawText(
                            idx,
                            screen_pos.x - x_offset - player.name_text_data._width / 2,
                            screen_pos.y - player.name_text_data._height,
                            &player.name_text_data,
                            draw_data,
                        );

                        idx = drawQuad(
                            idx,
                            screen_pos.x - w / 2.0,
                            screen_pos.y,
                            w,
                            h,
                            atlas_data,
                            draw_data,
                            &.{
                                .shadow_texel_mult = 2.0 / size,
                                .alpha_mult = alpha_mult,
                                .base_color = color,
                                .base_color_intensity = color_intensity,
                            },
                        );

                        // todo make sink calculate actual values based on h, pad, etc
                        var y_pos: f32 = 5.0 + if (sink != 1.0) @as(f32, 15.0) else @as(f32, 0.0);

                        const pad_scale_obj = assets.padding * size * camera.scale;
                        const pad_scale_bar = assets.padding * 2 * camera.scale;
                        if (player.hp >= 0 and player.hp < player.max_hp) {
                            const hp_bar_w = assets.hp_bar_data.texWRaw() * 2 * camera.scale;
                            const hp_bar_h = assets.hp_bar_data.texHRaw() * 2 * camera.scale;
                            const hp_bar_y = screen_pos.y + h - pad_scale_obj + y_pos;

                            idx = drawQuad(
                                idx,
                                screen_pos.x - x_offset - hp_bar_w / 2.0,
                                hp_bar_y,
                                hp_bar_w,
                                hp_bar_h,
                                assets.empty_bar_data,
                                draw_data,
                                &.{ .shadow_texel_mult = 0.5, .force_glow_off = true },
                            );

                            const float_hp: f32 = @floatFromInt(player.hp);
                            const float_max_hp: f32 = @floatFromInt(player.max_hp);
                            const left_pad = 2.0;
                            const w_no_pad = 20.0;
                            const total_w = 24.0;
                            const hp_perc = (left_pad / total_w) + (w_no_pad / total_w) * (float_hp / float_max_hp);

                            var hp_bar_data = assets.hp_bar_data;
                            hp_bar_data.tex_w *= hp_perc;

                            idx = drawQuad(
                                idx,
                                screen_pos.x - x_offset - hp_bar_w / 2.0,
                                hp_bar_y,
                                hp_bar_w * hp_perc,
                                hp_bar_h,
                                hp_bar_data,
                                draw_data,
                                &.{ .shadow_texel_mult = 0.5, .force_glow_off = true },
                            );

                            y_pos += hp_bar_h - pad_scale_bar;
                        }

                        if (player.mp >= 0 and player.mp < player.max_mp) {
                            const mp_bar_w = assets.mp_bar_data.texWRaw() * 2 * camera.scale;
                            const mp_bar_h = assets.mp_bar_data.texHRaw() * 2 * camera.scale;
                            const mp_bar_y = screen_pos.y + h - pad_scale_obj + y_pos;

                            idx = drawQuad(
                                idx,
                                screen_pos.x - x_offset - mp_bar_w / 2.0,
                                mp_bar_y,
                                mp_bar_w,
                                mp_bar_h,
                                assets.empty_bar_data,
                                draw_data,
                                &.{ .shadow_texel_mult = 0.5, .force_glow_off = true },
                            );

                            const float_mp: f32 = @floatFromInt(player.mp);
                            const float_max_mp: f32 = @floatFromInt(player.max_mp);
                            const left_pad = 2.0;
                            const w_no_pad = 20.0;
                            const total_w = 24.0;
                            const mp_perc = (left_pad / total_w) + (w_no_pad / total_w) * (float_mp / float_max_mp);

                            var mp_bar_data = assets.mp_bar_data;
                            mp_bar_data.tex_w *= mp_perc;

                            idx = drawQuad(
                                idx,
                                screen_pos.x - x_offset - mp_bar_w / 2.0,
                                mp_bar_y,
                                mp_bar_w * mp_perc,
                                mp_bar_h,
                                mp_bar_data,
                                draw_data,
                                &.{ .shadow_texel_mult = 0.5, .force_glow_off = true },
                            );

                            y_pos += mp_bar_h - pad_scale_bar;
                        }

                        const cond_int: @typeInfo(utils.Condition).Struct.backing_integer.? = @bitCast(player.condition);
                        if (cond_int > 0) {
                            var cond_len: f32 = 0.0;
                            for (0..@bitSizeOf(utils.Condition)) |i| {
                                if (cond_int & (@as(usize, 1) << @intCast(i)) != 0)
                                    cond_len += if (condition_rects[i].len > 0) 1.0 else 0.0;
                            }

                            var cond_idx: f32 = 0.0;
                            for (0..@bitSizeOf(utils.Condition)) |i| {
                                if (cond_int & (@as(usize, 1) << @intCast(i)) != 0) {
                                    const data = condition_rects[i];
                                    if (data.len > 0) {
                                        const frame_idx: usize = @intCast(@divFloor(time, 500 * std.time.us_per_ms));
                                        const current_frame = data[@mod(frame_idx, data.len)];
                                        const cond_w = current_frame.texWRaw() * 2;
                                        const cond_h = current_frame.texHRaw() * 2;

                                        idx = drawQuad(
                                            idx,
                                            screen_pos.x - x_offset - cond_len * (cond_w + 2) / 2 + cond_idx * (cond_w + 2),
                                            screen_pos.y + h - pad_scale_obj + y_pos,
                                            cond_w,
                                            cond_h,
                                            current_frame,
                                            draw_data,
                                            &.{ .shadow_texel_mult = 0.5, .force_glow_off = true },
                                        );
                                        cond_idx += 1.0;
                                    }
                                }
                            }

                            y_pos += 20;
                        }
                    },
                    .object => |bo| {
                        if (bo.dead or !camera.visibleInCamera(bo.x, bo.y)) {
                            continue;
                        }

                        var screen_pos = camera.rotateAroundCamera(bo.x, bo.y);
                        const size = camera.size_mult * camera.scale * bo.size;

                        if (bo.draw_on_ground) {
                            const tile_size = @as(f32, camera.px_per_tile) * camera.scale;
                            idx = drawQuad(
                                idx,
                                screen_pos.x - tile_size / 2.0,
                                screen_pos.y - tile_size / 2.0,
                                tile_size,
                                tile_size,
                                bo.atlas_data,
                                draw_data,
                                &.{ .rotation = camera.angle, .alpha_mult = bo.alpha },
                            );
                            continue;
                        }

                        if (bo.is_wall) {
                            idx = drawWall(idx, bo.x, bo.y, bo.alpha, bo.atlas_data, bo.top_atlas_data, draw_data);
                            continue;
                        }

                        const sec = bo.anim_sector;
                        const anim_idx = bo.anim_index;

                        var atlas_data = bo.atlas_data;
                        var x_offset: f32 = 0.0;
                        if (bo.anim_data) |anim_data| {
                            atlas_data = switch (bo.action) {
                                assets.walk_action => anim_data.walk_anims[sec][1 + anim_idx],
                                assets.attack_action => anim_data.attack_anims[sec][anim_idx],
                                assets.stand_action => anim_data.walk_anims[sec][0],
                                else => unreachable,
                            };

                            if (bo.action == assets.attack_action and anim_idx == 1) {
                                const w = atlas_data.texWRaw() * size;
                                x_offset = if (sec == assets.left_dir) -assets.padding * size else w / 4.0;
                            }
                        }

                        var sink: f32 = 1.0;
                        if (map.getSquare(bo.x, bo.y)) |square| {
                            if (square.tile_type != 0xFFFF) {
                                sink += if (square.props != null and square.props.?.sink and !square.protect_from_sink) 0.75 else 0;
                            }
                        }

                        atlas_data.tex_h /= sink;

                        const w = atlas_data.texWRaw() * size;
                        const h = atlas_data.texHRaw() * size;

                        screen_pos.x += x_offset;
                        screen_pos.y += bo.z * -camera.px_per_tile - (h - size * assets.padding);

                        var alpha_mult: f32 = bo.alpha;
                        if (bo.condition.invisible)
                            alpha_mult = 0.6;

                        var color: u32 = 0;
                        var color_intensity: f32 = 0.0;
                        _ = &color;
                        _ = &color_intensity;
                        // flash

                        if (settings.enable_lights and bo.light_color > 0) {
                            const light_size = bo.light_radius + bo.light_pulse * @sin(float_time_ms / 1000.0 * bo.light_pulse_speed);

                            light_idx = drawLight(
                                light_idx,
                                w * light_size,
                                h * light_size,
                                screen_pos.x,
                                screen_pos.y + h / 2.0,
                                bo.light_color,
                                bo.light_intensity,
                            );
                        }

                        const is_portal = bo.class == .portal;
                        if (bo.show_name or is_portal) {
                            idx = drawText(
                                idx,
                                screen_pos.x - x_offset - bo.name_text_data._width / 2,
                                screen_pos.y - bo.name_text_data._height,
                                &bo.name_text_data,
                                draw_data,
                            );

                            if (is_portal and map.interactive_id.load(.Acquire) == bo.obj_id) {
                                const button_w = 100 / 4;
                                const button_h = 100 / 4;
                                const total_w = enter_text_data._width + button_w;

                                idx = drawQuad(
                                    idx,
                                    screen_pos.x - x_offset - total_w / 2,
                                    screen_pos.y + h + 5,
                                    button_w,
                                    button_h,
                                    settings.interact_key_tex,
                                    draw_data,
                                    &.{ .force_glow_off = true },
                                );

                                idx = drawText(
                                    idx,
                                    screen_pos.x - x_offset - total_w / 2 + button_w,
                                    screen_pos.y + h + 5,
                                    &enter_text_data,
                                    draw_data,
                                );
                            }
                        }

                        idx = drawQuad(
                            idx,
                            screen_pos.x - w / 2.0,
                            screen_pos.y,
                            w,
                            h,
                            atlas_data,
                            draw_data,
                            &.{
                                .shadow_texel_mult = 2.0 / size,
                                .alpha_mult = alpha_mult,
                                .base_color = color,
                                .base_color_intensity = color_intensity,
                            },
                        );

                        if (!bo.is_enemy)
                            continue;

                        var y_pos: f32 = 5.0 + if (sink != 1.0) @as(f32, 15.0) else @as(f32, 0.0);

                        const pad_scale_obj = assets.padding * size * camera.scale;
                        const pad_scale_bar = assets.padding * 2 * camera.scale;
                        if (bo.hp >= 0 and bo.hp < bo.max_hp) {
                            const hp_bar_w = assets.hp_bar_data.texWRaw() * 2 * camera.scale;
                            const hp_bar_h = assets.hp_bar_data.texHRaw() * 2 * camera.scale;
                            const hp_bar_y = screen_pos.y + h - pad_scale_obj + y_pos;

                            idx = drawQuad(
                                idx,
                                screen_pos.x - x_offset - hp_bar_w / 2.0,
                                hp_bar_y,
                                hp_bar_w,
                                hp_bar_h,
                                assets.empty_bar_data,
                                draw_data,
                                &.{ .shadow_texel_mult = 0.5, .force_glow_off = true },
                            );

                            const float_hp: f32 = @floatFromInt(bo.hp);
                            const float_max_hp: f32 = @floatFromInt(bo.max_hp);
                            const hp_perc = 1.0 / (float_hp / float_max_hp);
                            var hp_bar_data = assets.hp_bar_data;
                            hp_bar_data.tex_w /= hp_perc;

                            idx = drawQuad(
                                idx,
                                screen_pos.x - x_offset - hp_bar_w / 2.0,
                                hp_bar_y,
                                hp_bar_w / hp_perc,
                                hp_bar_h,
                                hp_bar_data,
                                draw_data,
                                &.{ .shadow_texel_mult = 0.5, .force_glow_off = true },
                            );

                            y_pos += hp_bar_h - pad_scale_bar;
                        }

                        const cond_int: @typeInfo(utils.Condition).Struct.backing_integer.? = @bitCast(bo.condition);
                        if (cond_int > 0) {
                            var cond_len: f32 = 0.0;
                            for (0..@bitSizeOf(utils.Condition)) |i| {
                                if (cond_int & (@as(usize, 1) << @intCast(i)) != 0)
                                    cond_len += if (condition_rects[i].len > 0) 1.0 else 0.0;
                            }

                            var cond_idx: f32 = 0.0;
                            for (0..@bitSizeOf(utils.Condition)) |i| {
                                if (cond_int & (@as(usize, 1) << @intCast(i)) != 0) {
                                    const data = condition_rects[i];
                                    if (data.len > 0) {
                                        const frame_idx: usize = @intCast(@divFloor(time, 500 * std.time.us_per_ms));
                                        const current_frame = data[@mod(frame_idx, data.len)];
                                        const cond_w = current_frame.texWRaw() * 2;
                                        const cond_h = current_frame.texHRaw() * 2;

                                        idx = drawQuad(
                                            idx,
                                            screen_pos.x - x_offset - cond_len * (cond_w + 2) / 2 + cond_idx * (cond_w + 2),
                                            screen_pos.y + h - pad_scale_obj + y_pos,
                                            cond_w,
                                            cond_h,
                                            current_frame,
                                            draw_data,
                                            &.{ .shadow_texel_mult = 0.5, .force_glow_off = true },
                                        );
                                        cond_idx += 1.0;
                                    }
                                }
                            }

                            y_pos += 20;
                        }
                    },
                    .projectile => |proj| {
                        if (!camera.visibleInCamera(proj.x, proj.y)) {
                            continue;
                        }

                        const size = camera.size_mult * camera.scale * proj.props.size;
                        const w = proj.atlas_data.texWRaw() * size;
                        const h = proj.atlas_data.texHRaw() * size;
                        var screen_pos = camera.rotateAroundCamera(proj.x, proj.y);
                        screen_pos.y += proj.z * -camera.px_per_tile - (h - size * assets.padding);
                        const rotation = proj.props.rotation;
                        const angle = -(proj.visual_angle + proj.props.angle_correction +
                            (if (rotation == 0) 0 else @as(f32, @floatFromInt(time)) / rotation / std.time.us_per_ms) - camera.angle);

                        if (settings.enable_lights and proj.props.light_color > 0) {
                            const light_size = proj.props.light_radius + proj.props.light_pulse * @sin(float_time_ms / 1000.0 * proj.props.light_pulse_speed);

                            light_idx = drawLight(
                                light_idx,
                                w * light_size,
                                h * light_size,
                                screen_pos.x,
                                screen_pos.y + h / 2.0,
                                proj.props.light_color,
                                proj.props.light_intensity,
                            );
                        }

                        idx = drawQuad(
                            idx,
                            screen_pos.x - w / 2.0,
                            screen_pos.y,
                            w,
                            h,
                            proj.atlas_data,
                            draw_data,
                            &.{ .shadow_texel_mult = 2.0 / size, .rotation = angle, .force_glow_off = true },
                        );
                    },
                }
            }

            if (settings.enable_lights) {
                idx = drawQuad(
                    idx,
                    0,
                    0,
                    camera.screen_width,
                    camera.screen_height,
                    assets.wall_backface_data,
                    draw_data,
                    &.{ .base_color = map.bg_light_color, .base_color_intensity = 1.0, .alpha_mult = map.getLightIntensity(time) },
                );
            }

            if (idx > 0) {
                encoder.writeBuffer(
                    base_vb,
                    0,
                    BaseVertexData,
                    base_vert_data[0..idx],
                );
                endDraw(
                    draw_data,
                    @as(u64, idx) * @sizeOf(BaseVertexData),
                    @divFloor(idx, 4) * 6,
                    null,
                );
            }
        }

        if (settings.enable_lights and light_idx != 0) {
            lightPass: {
                const draw_data: *const DrawData = &.{
                    .encoder = encoder,
                    .buffer = light_vb,
                    .pipeline = gctx.lookupResource(light_pipeline) orelse break :lightPass,
                    .bind_group = gctx.lookupResource(light_bind_group) orelse break :lightPass,
                };

                encoder.writeBuffer(
                    light_vb,
                    0,
                    LightVertexData,
                    light_vert_data[0..light_idx],
                );
                endDraw(
                    draw_data,
                    @as(u64, light_idx) * @sizeOf(LightVertexData),
                    @divFloor(light_idx, 4) * 6,
                    null,
                );
            }
        }
    }

    uiPass: {
        const pipeline = gctx.lookupResource(base_pipeline) orelse break :uiPass;
        const bind_group = gctx.lookupResource(base_bind_group) orelse break :uiPass;

        const draw_data: *const DrawData = &.{
            .encoder = encoder,
            .buffer = base_vb,
            .pipeline = pipeline,
            .bind_group = bind_group,
        };

        var ui_idx: u16 = 0;

        while (!sc.temp_elem_lock.tryLock()) {}
        for (sc.temp_elements.items) |elem| {
            switch (elem) {
                .status => |text| {
                    if (!text.visible)
                        continue;

                    ui_idx = drawText(ui_idx, text._screen_x, text._screen_y, &text.text_data, draw_data);
                },
                .balloon => |balloon| {
                    if (!balloon.visible)
                        continue;

                    const image_data = balloon.image_data.normal; // assume no 9 slice
                    const w = image_data.width();
                    const h = image_data.height();

                    const opts: *const QuadOptions = &.{
                        .alpha_mult = image_data.alpha,
                        .ui_quad = true,
                        .scissor = image_data.scissor,
                        .base_color = image_data.color,
                        .base_color_intensity = image_data.color_intensity,
                        .shadow_texel_mult = if (image_data.glow) 1.0 / @max(image_data.scale_x, image_data.scale_y) else 0.0,
                    };
                    ui_idx = drawQuad(ui_idx, balloon._screen_x, balloon._screen_y, w, h, image_data.atlas_data, draw_data, opts);

                    const decor_offset = h / 10;
                    ui_idx = drawText(
                        ui_idx,
                        balloon._screen_x + ((w - assets.padding * image_data.scale_x) - balloon.text_data._width) / 2,
                        balloon._screen_y + (h - balloon.text_data._height) / 2 - decor_offset,
                        &balloon.text_data,
                        draw_data,
                    );
                },
            }
        }
        sc.temp_elem_lock.unlock();

        while (!sc.ui_lock.tryLock()) {}
        for (sc.elements.items) |elem| {
            switch (elem) {
                .container => |container| {
                    if (!container.visible)
                        continue;

                    for (container._elements.items) |cont_elem| {
                        ui_idx = drawElement(ui_idx, cont_elem, draw_data, cam_x, cam_y, container.x, container.y, time);
                    }
                },
                else => {
                    ui_idx = drawElement(ui_idx, elem, draw_data, cam_x, cam_y, 0, 0, time);
                },
            }
        }
        sc.ui_lock.unlock();

        if (ui_idx != 0) {
            encoder.writeBuffer(
                base_vb,
                0,
                BaseVertexData,
                base_vert_data[0..ui_idx],
            );
            endDraw(
                draw_data,
                @as(u64, ui_idx) * @sizeOf(BaseVertexData),
                @divFloor(ui_idx, 4) * 6,
                null,
            );
        }
    }
}
