const std = @import("std");
const map = @import("../game/map.zig");
const assets = @import("../assets.zig");
const camera = @import("../camera.zig");
const settings = @import("../settings.zig");
const gpu = @import("mach-sysgpu").sysgpu;
const utils = @import("../utils.zig");
const zstbi = @import("zstbi");
const element = @import("../ui/element.zig");
const main = @import("../main.zig");
const systems = @import("../ui/systems.zig");
const gpu_util = @import("gpu_util.zig");
const glfw = @import("mach-glfw");

const game_render = @import("game.zig");
const ground_render = @import("ground.zig");
const ui_render = @import("ui.zig");

const VertexField = extern struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,
};

pub const LightData = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    color: u32,
    intensity: f32,
};

pub const DrawData = struct {
    encoder: *gpu.CommandEncoder,
    buffer: *gpu.Buffer,
    pipeline: *gpu.RenderPipeline,
    bind_group: *gpu.BindGroup,
};

pub const QuadOptions = struct {
    rotation: f32 = 0.0,
    base_color: u32 = std.math.maxInt(u32),
    base_color_intensity: f32 = 0.0,
    alpha_mult: f32 = 1.0,
    shadow_texel_mult: f32 = 0.0,
    shadow_color: u32 = std.math.maxInt(u32),
    scissor: element.ScissorRect = .{},
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

// must be multiples of 16 bytes. be mindful
pub const GroundUniformData = extern struct {
    left_top_mask_uv: [4]f32,
    right_bottom_mask_uv: [4]f32,
};

pub const quad_render_type = 0.0;
pub const ui_quad_render_type = 1.0;
pub const minimap_render_type = 2.0;
pub const menu_bg_render_type = 3.0;
pub const text_normal_render_type = 4.0;
pub const text_drop_shadow_render_type = 5.0;
pub const text_normal_no_subpixel_render_type = 6.0;
pub const text_drop_shadow_no_subpixel_render_type = 7.0;

pub const base_batch_vert_size = 10000 * 4;
pub const ground_batch_vert_size = 10000 * 4;
pub const max_lights = 1000;

pub var base_pipeline: *gpu.RenderPipeline = undefined;
pub var base_bind_group: *gpu.BindGroup = undefined;
pub var ground_pipeline: *gpu.RenderPipeline = undefined;
pub var ground_bind_group: *gpu.BindGroup = undefined;

pub var base_vb: *gpu.Buffer = undefined;
pub var ground_vb: *gpu.Buffer = undefined;
pub var ground_uniforms: *gpu.Buffer = undefined;
pub var index_buffer: *gpu.Buffer = undefined;

pub var base_vert_data: [base_batch_vert_size]BaseVertexData = undefined;
pub var ground_vert_data: [ground_batch_vert_size]GroundVertexData = undefined;

pub var bold_text_texture: *gpu.Texture = undefined;
pub var bold_text_texture_view: *gpu.TextureView = undefined;
pub var bold_italic_text_texture: *gpu.Texture = undefined;
pub var bold_italic_text_texture_view: *gpu.TextureView = undefined;
pub var medium_text_texture: *gpu.Texture = undefined;
pub var medium_text_texture_view: *gpu.TextureView = undefined;
pub var medium_italic_text_texture: *gpu.Texture = undefined;
pub var medium_italic_text_texture_view: *gpu.TextureView = undefined;
pub var texture: *gpu.Texture = undefined;
pub var texture_view: *gpu.TextureView = undefined;
pub var ui_texture: *gpu.Texture = undefined;
pub var ui_texture_view: *gpu.TextureView = undefined;
pub var minimap_texture: *gpu.Texture = undefined;
pub var minimap_texture_view: *gpu.TextureView = undefined;
pub var menu_bg_texture: *gpu.Texture = undefined;
pub var menu_bg_texture_view: *gpu.TextureView = undefined;
pub var color_texture: *gpu.Texture = undefined;
pub var color_texture_view: *gpu.TextureView = undefined;

pub var clear_render_pass_info: gpu.RenderPassDescriptor = undefined;
pub var load_render_pass_info: gpu.RenderPassDescriptor = undefined;
pub var color_tex_set = false;
pub var first_draw = false;

pub var sampler: *gpu.Sampler = undefined;
pub var linear_sampler: *gpu.Sampler = undefined;

pub var condition_rects: [@bitSizeOf(utils.Condition)][]const assets.AtlasData = undefined;
pub var enter_text_data: element.TextData = undefined;
pub var light_idx: usize = 0;
pub var lights: [max_lights]LightData = undefined;

pub var surface: *gpu.Surface = undefined;
pub var queue: *gpu.Queue = undefined;
pub var adapter: *gpu.Adapter = undefined;
pub var device: *gpu.Device = undefined;
pub var swap_chain: *gpu.SwapChain = undefined;
pub var swap_chain_desc: gpu.SwapChain.Descriptor = undefined;

var instance: *gpu.Instance = undefined;
var allocator: std.mem.Allocator = undefined;
var last_ms_count: u32 = 1;

fn createTexture(tex: **gpu.Texture, view: **gpu.TextureView, img: zstbi.Image) void {
    tex.* = device.createTexture(&.{
        .usage = .{ .texture_binding = true, .copy_dst = true },
        .size = .{
            .width = img.width,
            .height = img.height,
            .depth_or_array_layers = 1,
        },
        .format = .rgba8_unorm,
        .mip_level_count = 1,
    });
    view.* = tex.*.createView(null);

    queue.writeTexture(
        &.{ .texture = tex.* },
        &.{
            .bytes_per_row = img.bytes_per_row,
            .rows_per_image = img.height,
        },
        &.{ .width = img.width, .height = img.height },
        img.data,
    );
}

fn createPipelines() void {
    const sample_count: u32 = switch (settings.aa_type) {
        .msaa2x => 2,
        .msaa4x => 4,
        else => 1,
    };

    const bufferLayoutEntry = gpu.BindGroupLayout.Entry.buffer;
    const samplerLayoutEntry = gpu.BindGroupLayout.Entry.sampler;
    const textureLayoutEntry = gpu.BindGroupLayout.Entry.texture;

    const ground_bind_group_layout = device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor.init(.{
        .label = "Ground bind group",
        .entries = &[_]gpu.BindGroupLayout.Entry{
            bufferLayoutEntry(0, .{ .vertex = true, .fragment = true }, .uniform, false, 0),
            samplerLayoutEntry(1, .{ .fragment = true }, .filtering),
            textureLayoutEntry(2, .{ .fragment = true }, .float, .dimension_2d, false),
        },
    }));
    defer ground_bind_group_layout.release();

    const base_bind_group_layout = device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor.init(.{
        .label = "Base bind group",
        .entries = &[_]gpu.BindGroupLayout.Entry{
            samplerLayoutEntry(0, .{ .fragment = true }, .filtering),
            samplerLayoutEntry(1, .{ .fragment = true }, .filtering),
            textureLayoutEntry(2, .{ .fragment = true }, .float, .dimension_2d, false),
            textureLayoutEntry(3, .{ .fragment = true }, .float, .dimension_2d, false),
            textureLayoutEntry(4, .{ .fragment = true }, .float, .dimension_2d, false),
            textureLayoutEntry(5, .{ .fragment = true }, .float, .dimension_2d, false),
            textureLayoutEntry(6, .{ .fragment = true }, .float, .dimension_2d, false),
            textureLayoutEntry(7, .{ .fragment = true }, .float, .dimension_2d, false),
            textureLayoutEntry(8, .{ .fragment = true }, .float, .dimension_2d, false),
            textureLayoutEntry(9, .{ .fragment = true }, .float, .dimension_2d, false),
        },
    }));
    defer base_bind_group_layout.release();

    const base_pipeline_layout = device.createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(.{
        .bind_group_layouts = &[_]*gpu.BindGroupLayout{base_bind_group_layout},
    }));
    defer base_pipeline_layout.release();

    const ground_shader = device.createShaderModuleWGSL("Ground shader", @embedFile("../assets/shaders/ground.wgsl"));
    defer ground_shader.release();

    const base_shader = device.createShaderModuleWGSL("Base shader", @embedFile("../assets/shaders/base.wgsl"));
    defer base_shader.release();

    const base_color_targets = [_]gpu.ColorTargetState{.{
        .format = swap_chain_desc.format,
        .blend = &gpu.BlendState{
            .color = .{ .src_factor = .src_alpha, .dst_factor = .one_minus_src_alpha },
            .alpha = .{ .src_factor = .src_alpha, .dst_factor = .one_minus_src_alpha },
        },
    }};

    const base_vertex_attributes = [_]gpu.VertexAttribute{
        .{ .format = .float32x4, .offset = @offsetOf(BaseVertexData, "pos_uv"), .shader_location = 0 },
        .{ .format = .float32x4, .offset = @offsetOf(BaseVertexData, "base_color_and_intensity"), .shader_location = 1 },
        .{ .format = .float32x4, .offset = @offsetOf(BaseVertexData, "alpha_and_shadow_color"), .shader_location = 2 },
        .{ .format = .float32x4, .offset = @offsetOf(BaseVertexData, "texel_and_text_data"), .shader_location = 3 },
        .{ .format = .float32x4, .offset = @offsetOf(BaseVertexData, "outline_color_and_w"), .shader_location = 4 },
        .{ .format = .float32, .offset = @offsetOf(BaseVertexData, "render_type"), .shader_location = 5 },
    };
    const base_vertex_buffers = [_]gpu.VertexBufferLayout{.{
        .array_stride = @sizeOf(BaseVertexData),
        .attribute_count = base_vertex_attributes.len,
        .attributes = &base_vertex_attributes,
    }};

    const base_pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .layout = base_pipeline_layout,
        .vertex = gpu.VertexState{
            .module = base_shader,
            .entry_point = "vs_main",
            .buffer_count = base_vertex_buffers.len,
            .buffers = &base_vertex_buffers,
        },
        .primitive = gpu.PrimitiveState{
            .front_face = .cw,
            .cull_mode = .none,
            .topology = .triangle_list,
        },
        .fragment = &gpu.FragmentState{
            .module = base_shader,
            .entry_point = "fs_main",
            .target_count = base_color_targets.len,
            .targets = &base_color_targets,
        },
        .multisample = .{ .count = sample_count },
    };
    base_pipeline = device.createRenderPipeline(&base_pipeline_descriptor);

    const ground_pipeline_layout = device.createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(.{
        .bind_group_layouts = &[_]*gpu.BindGroupLayout{ground_bind_group_layout},
    }));
    defer ground_pipeline_layout.release();

    const ground_color_targets = [_]gpu.ColorTargetState{.{
        .format = swap_chain_desc.format,
    }};

    const ground_vertex_attributes = [_]gpu.VertexAttribute{
        .{ .format = .float32x4, .offset = @offsetOf(GroundVertexData, "pos_uv"), .shader_location = 0 },
        .{ .format = .float32x4, .offset = @offsetOf(GroundVertexData, "left_top_blend_uv"), .shader_location = 1 },
        .{ .format = .float32x4, .offset = @offsetOf(GroundVertexData, "right_bottom_blend_uv"), .shader_location = 2 },
        .{ .format = .float32x4, .offset = @offsetOf(GroundVertexData, "base_and_offset_uv"), .shader_location = 3 },
    };
    const ground_vertex_buffers = [_]gpu.VertexBufferLayout{.{
        .array_stride = @sizeOf(GroundVertexData),
        .attribute_count = ground_vertex_attributes.len,
        .attributes = &ground_vertex_attributes,
    }};

    const ground_pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .layout = ground_pipeline_layout,
        .vertex = gpu.VertexState{
            .module = ground_shader,
            .entry_point = "vs_main",
            .buffer_count = ground_vertex_buffers.len,
            .buffers = &ground_vertex_buffers,
        },
        .primitive = gpu.PrimitiveState{
            .front_face = .cw,
            .cull_mode = .none,
            .topology = .triangle_list,
        },
        .fragment = &gpu.FragmentState{
            .module = ground_shader,
            .entry_point = "fs_main",
            .target_count = ground_color_targets.len,
            .targets = &ground_color_targets,
        },
        .multisample = .{ .count = sample_count },
    };
    ground_pipeline = device.createRenderPipeline(&ground_pipeline_descriptor);
}

pub fn createColorTexture() void {
    const sample_count: u32 = switch (settings.aa_type) {
        .msaa2x => 2,
        .msaa4x => 4,
        else => 1,
    };

    if (color_tex_set) {
        color_texture.release();
        color_texture_view.release();
        color_tex_set = false;
    }

    if (sample_count == 1) {
        last_ms_count = 1;
        return;
    }

    color_texture = device.createTexture(&.{
        .usage = .{ .render_attachment = true },
        .dimension = .dimension_2d,
        .size = .{
            .width = swap_chain_desc.width,
            .height = swap_chain_desc.height,
        },
        .format = swap_chain_desc.format,
        .sample_count = sample_count,
    });
    color_texture_view = color_texture.createView(null);

    base_pipeline.release();
    ground_pipeline.release();
    createPipelines();

    last_ms_count = sample_count;

    color_tex_set = true;
}

pub fn deinit() void {
    for (condition_rects) |rects| {
        if (rects.len > 0)
            allocator.free(rects);
    }

    enter_text_data.deinit(allocator);

    base_pipeline.release();
    base_bind_group.release();
    ground_pipeline.release();
    ground_bind_group.release();

    base_vb.release();
    ground_vb.release();
    ground_uniforms.release();
    index_buffer.release();

    bold_text_texture.release();
    bold_text_texture_view.release();
    bold_italic_text_texture.release();
    bold_italic_text_texture_view.release();
    medium_text_texture.release();
    medium_text_texture_view.release();
    medium_italic_text_texture.release();
    medium_italic_text_texture_view.release();
    texture.release();
    texture_view.release();
    ui_texture.release();
    ui_texture_view.release();
    minimap_texture.release();
    minimap_texture_view.release();
    menu_bg_texture.release();
    menu_bg_texture_view.release();
    if (color_tex_set) {
        color_texture.release();
        color_texture_view.release();
    }

    sampler.release();
    linear_sampler.release();

    swap_chain.release();
    surface.release();
    queue.release();
    adapter.release();
    device.release();

    instance.release();
}

fn deviceLostCallback(reason: gpu.Device.LostReason, msg: [*:0]const u8, _: ?*anyopaque) callconv(.C) void {
    if (reason != .destroyed)
        std.log.err("Device lost: {s}", .{msg});
}

pub fn init(window: glfw.Window, _allocator: std.mem.Allocator) !void {
    allocator = _allocator;

    try main.SYSGPUInterface.init(allocator, .{});
    instance = gpu.createInstance(null) orelse {
        std.debug.panic("Failed to create GPU instance", .{});
    };
    surface = try gpu_util.createSurfaceForWindow(instance, window, comptime gpu_util.detectGLFWOptions());

    var response: gpu_util.RequestAdapterResponse = undefined;
    instance.requestAdapter(&gpu.RequestAdapterOptions{
        .compatible_surface = surface,
        .power_preference = .high_performance,
        .force_fallback_adapter = .false,
    }, &response, gpu_util.requestAdapterCallback);
    if (response.status != .success) {
        std.debug.panic("Failed to create GPU adapter: {?s}", .{response.message});
    }

    adapter = response.adapter.?;

    var props = std.mem.zeroes(gpu.Adapter.Properties);
    response.adapter.?.getProperties(&props);
    if (props.backend_type == .null) {
        std.debug.panic("No backend found for {s} adapter", .{props.adapter_type.name()});
    }

    device = response.adapter.?.createDevice(&.{
        .next_in_chain = .{
            .dawn_toggles_descriptor = &gpu.dawn.TogglesDescriptor.init(.{
                .enabled_toggles = &[_][*:0]const u8{
                    "allow_unsafe_apis",
                },
            }),
        },

        .required_features_count = 0,
        .required_features = null,
        .required_limits = null,
        .device_lost_callback = &deviceLostCallback,
        .device_lost_userdata = null,
    }) orelse {
        std.debug.panic("Failed to create GPU device\n", .{});
    };
    device.setUncapturedErrorCallback({}, gpu_util.printUnhandledErrorCallback);
    queue = device.getQueue();

    const framebuffer_size = window.getFramebufferSize();
    swap_chain_desc = gpu.SwapChain.Descriptor{
        .label = "Main Swap Chain",
        .usage = .{ .render_attachment = true },
        .format = .bgra8_unorm,
        .width = framebuffer_size.width,
        .height = framebuffer_size.height,
        .present_mode = if (settings.enable_vsync) .fifo else .immediate,
    };
    swap_chain = device.createSwapChain(surface, &swap_chain_desc);

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
            rects[j] = (assets.atlas_data.get(sheet_name) orelse std.debug.panic("Could not find sheet {s} for cond parsing", .{sheet_name}))[sheet_indices[j]];
        }

        condition_rects[i] = rects;
    }

    enter_text_data = element.TextData{
        .text = "Enter",
        .text_type = .bold,
        .size = 12,
    };

    {
        enter_text_data._lock.lock();
        defer enter_text_data._lock.unlock();

        enter_text_data.recalculateAttributes(main._allocator);
    }

    base_vb = device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .vertex = true },
        .size = base_vert_data.len * @sizeOf(BaseVertexData),
    });
    queue.writeBuffer(base_vb, 0, base_vert_data[0..]);

    ground_vb = device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .vertex = true },
        .size = ground_vert_data.len * @sizeOf(GroundVertexData),
    });
    queue.writeBuffer(ground_vb, 0, ground_vert_data[0..]);

    ground_uniforms = device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = @sizeOf(GroundUniformData),
    });
    queue.writeBuffer(ground_uniforms, 0, &[_]GroundUniformData{.{
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
    index_buffer = device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .index = true },
        .size = index_data.len * @sizeOf(u16),
    });
    queue.writeBuffer(index_buffer, 0, index_data[0..]);

    createTexture(&minimap_texture, &minimap_texture_view, map.minimap);
    createTexture(&medium_text_texture, &medium_text_texture_view, assets.medium_atlas);
    createTexture(&medium_italic_text_texture, &medium_italic_text_texture_view, assets.medium_italic_atlas);
    createTexture(&bold_text_texture, &bold_text_texture_view, assets.bold_atlas);
    createTexture(&bold_italic_text_texture, &bold_italic_text_texture_view, assets.bold_italic_atlas);
    createTexture(&texture, &texture_view, assets.atlas);
    createTexture(&ui_texture, &ui_texture_view, assets.ui_atlas);
    createTexture(&menu_bg_texture, &menu_bg_texture_view, assets.menu_background);

    assets.medium_atlas.deinit();
    assets.medium_italic_atlas.deinit();
    assets.bold_atlas.deinit();
    assets.bold_italic_atlas.deinit();
    assets.atlas.deinit();
    assets.ui_atlas.deinit();
    assets.menu_background.deinit();

    sampler = device.createSampler(&.{});
    linear_sampler = device.createSampler(&.{ .min_filter = .linear, .mag_filter = .linear });

    const bufferLayoutEntry = gpu.BindGroupLayout.Entry.buffer;
    const samplerLayoutEntry = gpu.BindGroupLayout.Entry.sampler;
    const textureLayoutEntry = gpu.BindGroupLayout.Entry.texture;

    const bufferEntry = gpu.BindGroup.Entry.buffer;
    const samplerEntry = gpu.BindGroup.Entry.sampler;
    const textureEntry = gpu.BindGroup.Entry.textureView;

    const ground_bind_group_layout = device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor.init(.{
        .label = "Ground bind group layout",
        .entries = &[_]gpu.BindGroupLayout.Entry{
            bufferLayoutEntry(0, .{ .vertex = true, .fragment = true }, .uniform, false, 0),
            samplerLayoutEntry(1, .{ .fragment = true }, .filtering),
            textureLayoutEntry(2, .{ .fragment = true }, .float, .dimension_2d, false),
        },
    }));
    defer ground_bind_group_layout.release();
    ground_bind_group = device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
        .label = "Ground bind group",
        .layout = ground_bind_group_layout,
        .entries = &[_]gpu.BindGroup.Entry{
            bufferEntry(0, ground_uniforms, 0, @sizeOf(GroundUniformData), 0),
            samplerEntry(1, sampler),
            textureEntry(2, texture_view),
        },
    }));

    const base_bind_group_layout = device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor.init(.{
        .label = "Base bind group layout",
        .entries = &[_]gpu.BindGroupLayout.Entry{
            samplerLayoutEntry(0, .{ .fragment = true }, .filtering),
            samplerLayoutEntry(1, .{ .fragment = true }, .filtering),
            textureLayoutEntry(2, .{ .fragment = true }, .float, .dimension_2d, false),
            textureLayoutEntry(3, .{ .fragment = true }, .float, .dimension_2d, false),
            textureLayoutEntry(4, .{ .fragment = true }, .float, .dimension_2d, false),
            textureLayoutEntry(5, .{ .fragment = true }, .float, .dimension_2d, false),
            textureLayoutEntry(6, .{ .fragment = true }, .float, .dimension_2d, false),
            textureLayoutEntry(7, .{ .fragment = true }, .float, .dimension_2d, false),
            textureLayoutEntry(8, .{ .fragment = true }, .float, .dimension_2d, false),
            textureLayoutEntry(9, .{ .fragment = true }, .float, .dimension_2d, false),
        },
    }));
    defer base_bind_group_layout.release();

    base_bind_group = device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
        .label = "Base bind group",
        .layout = base_bind_group_layout,
        .entries = &[_]gpu.BindGroup.Entry{
            samplerEntry(0, sampler),
            samplerEntry(1, linear_sampler),
            textureEntry(2, texture_view),
            textureEntry(3, ui_texture_view),
            textureEntry(4, medium_text_texture_view),
            textureEntry(5, medium_italic_text_texture_view),
            textureEntry(6, bold_text_texture_view),
            textureEntry(7, bold_italic_text_texture_view),
            textureEntry(8, minimap_texture_view),
            textureEntry(9, menu_bg_texture_view),
        },
    }));

    createPipelines();
    createColorTexture();
}

pub inline fn drawQuad(
    idx: u16,
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    atlas_data: assets.AtlasData,
    draw_data: DrawData,
    opts: QuadOptions,
) u16 {
    var idx_new = idx;

    if (idx_new == base_batch_vert_size) {
        draw_data.encoder.writeBuffer(
            draw_data.buffer,
            0,
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

    const texel_w = 1.0 / atlas_data.atlas_type.width() * opts.shadow_texel_mult;
    const texel_h = 1.0 / atlas_data.atlas_type.height() * opts.shadow_texel_mult;

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

    const render_type: f32 = if (atlas_data.atlas_type == .ui) ui_quad_render_type else quad_render_type;

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

pub inline fn drawQuadVerts(
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
    draw_data: DrawData,
    opts: QuadOptions,
) u16 {
    var idx_new = idx;

    if (idx_new == base_batch_vert_size) {
        draw_data.encoder.writeBuffer(
            draw_data.buffer,
            0,
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

    const render_type = quad_render_type;

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

pub inline fn drawText(
    idx: u16,
    x: f32,
    y: f32,
    text_data: *element.TextData,
    draw_data: DrawData,
    scissor_override: element.ScissorRect,
) u16 {
    text_data._lock.lock();
    defer text_data._lock.unlock();

    // text data not initiated
    if (text_data._line_widths == null)
        return idx;

    var idx_new = idx;

    const rgb = element.RGBF32.fromInt(text_data.color);
    const shadow_rgb = element.RGBF32.fromInt(text_data.shadow_color);
    const outline_rgb = element.RGBF32.fromInt(text_data.outline_color);

    const size_scale = text_data.size / assets.CharacterData.size * camera.scale * assets.CharacterData.padding_mult;
    const start_line_height = assets.CharacterData.line_height * assets.CharacterData.size * size_scale;
    var line_height = start_line_height;

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
        const offset_i = i + index_offset;
        if (offset_i >= text_data.text.len)
            return idx_new;

        const char = text_data.text[offset_i];
        specialChar: {
            if (!text_data.handle_special_chars)
                break :specialChar;

            if (char == '&') {
                const name_start = text_data.text[offset_i + 1 ..];
                if (std.mem.indexOfScalar(u8, name_start, '=')) |eql_idx| {
                    const value_start_idx = offset_i + 1 + eql_idx + 1;
                    if (text_data.text.len <= value_start_idx or text_data.text[value_start_idx] != '"')
                        break :specialChar;

                    const reset = "reset";
                    if (text_data.text.len > offset_i + 1 + reset.len and std.mem.eql(u8, name_start[0..reset.len], reset)) {
                        current_type = text_data.text_type;
                        current_color = rgb;
                        current_size = size_scale;
                        line_height = assets.CharacterData.line_height * assets.CharacterData.size * current_size;
                        y_pointer += line_height - start_line_height;
                        index_offset += @intCast(reset.len);
                        continue;
                    }

                    const value_start = text_data.text[value_start_idx + 1 ..];
                    if (std.mem.indexOfScalar(u8, value_start, '"')) |value_end_idx| {
                        const name = name_start[0..eql_idx];
                        const value = value_start[0..value_end_idx];
                        if (std.mem.eql(u8, name, "col")) {
                            const int_color = std.fmt.parseInt(u32, value, 16) catch {
                                std.log.err("Invalid color given to control code: {s}", .{value});
                                break :specialChar;
                            };
                            current_color = element.RGBF32.fromInt(int_color);
                        } else if (std.mem.eql(u8, name, "size")) {
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

                            const quad_size = current_size * assets.CharacterData.size;
                            idx_new = drawQuad(
                                idx_new,
                                x_pointer + camera.screen_width / 2.0,
                                y_pointer - quad_size + camera.screen_height / 2.0,
                                quad_size,
                                quad_size,
                                data[index],
                                draw_data,
                                .{ .alpha_mult = text_data.alpha },
                            );

                            x_pointer += quad_size;
                        } else break :specialChar;

                        index_offset += @intCast(1 + eql_idx + 1 + value_end_idx + 1);
                        continue;
                    } else break :specialChar;
                } else break :specialChar;
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
        const scissor = if (scissor_override.isDefault()) text_data.scissor else scissor_override;
        const scaled_min_x = if (scissor.min_x != dont_scissor)
            (scissor.min_x + start_x) * camera.clip_scale_x
        else
            -1.0;
        const scaled_max_x = if (scissor.max_x != dont_scissor)
            (scissor.max_x + start_x) * camera.clip_scale_x
        else
            1.0;

        // have to flip these, y is inverted... should be fixed later
        const scaled_min_y = if (scissor.max_y != dont_scissor)
            -(scissor.max_y + start_y - line_height) * camera.clip_scale_y
        else
            -1.0;
        const scaled_max_y = if (scissor.min_y != dont_scissor)
            -(scissor.min_y + start_y - line_height) * camera.clip_scale_y
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

pub inline fn endDraw(draw_data: DrawData, verts: u64, indices: u32, offsets: ?[]const u32) void {
    @setEvalBranchQuota(100000);

    const pass = draw_data.encoder.beginRenderPass(if (first_draw) &clear_render_pass_info else &load_render_pass_info);
    pass.setVertexBuffer(0, draw_data.buffer, 0, verts);
    pass.setIndexBuffer(index_buffer, .uint16, 0, indices * @sizeOf(u16));
    pass.setPipeline(draw_data.pipeline);
    pass.setBindGroup(0, draw_data.bind_group, offsets);
    pass.drawIndexed(indices, 1, 0, 0, 0);
    pass.end();
    pass.release();
    first_draw = false;
}

pub fn draw(time: i64) void {
    const back_buffer = swap_chain.getCurrentTextureView();
    const encoder = device.createCommandEncoder(null);

    defer {
        const command = encoder.finish(null);
        encoder.release();

        queue.submit(&[_]*gpu.CommandBuffer{command});
        command.release();
        swap_chain.present();

        back_buffer.?.release();
    }

    map.object_lock.lockShared();

    const cam_x = camera.x.load(.Acquire);
    const cam_y = camera.y.load(.Acquire);

    const clear_color_attachments = if (last_ms_count > 1)
        [_]gpu.RenderPassColorAttachment{.{
            .view = color_texture_view,
            .resolve_target = back_buffer,
            .load_op = .clear,
            .store_op = .store,
            .clear_value = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
        }}
    else
        [_]gpu.RenderPassColorAttachment{.{
            .view = back_buffer,
            .load_op = .clear,
            .store_op = .store,
            .clear_value = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
        }};
    clear_render_pass_info = .{
        .color_attachment_count = clear_color_attachments.len,
        .color_attachments = &clear_color_attachments,
    };

    const load_color_attachments = if (last_ms_count > 1)
        [_]gpu.RenderPassColorAttachment{.{
            .view = color_texture_view,
            .resolve_target = back_buffer,
            .load_op = .load,
            .store_op = .store,
            .clear_value = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
        }}
    else
        [_]gpu.RenderPassColorAttachment{.{
            .view = back_buffer,
            .load_op = .load,
            .store_op = .store,
            .clear_value = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
        }};
    load_render_pass_info = .{
        .color_attachment_count = load_color_attachments.len,
        .color_attachments = &load_color_attachments,
    };

    first_draw = true;
    var idx: u16 = 0;
    var square_idx: u16 = 0;

    const base_draw_data = DrawData{
        .encoder = encoder,
        .buffer = base_vb,
        .pipeline = base_pipeline,
        .bind_group = base_bind_group,
    };
    const ground_draw_data = DrawData{
        .encoder = encoder,
        .buffer = ground_vb,
        .pipeline = ground_pipeline,
        .bind_group = ground_bind_group,
    };

    if ((main.tick_frame or main.editing_map) and
        cam_x > 0 and cam_y > 0 and
        map.validPos(@intFromFloat(cam_x), @intFromFloat(cam_y)))
    {
        const float_time_ms = @as(f32, @floatFromInt(time)) / std.time.us_per_ms;
        light_idx = 0;

        square_idx = ground_render.drawSquares(square_idx, ground_draw_data, float_time_ms, cam_x, cam_y);

        if (square_idx > 0) {
            encoder.writeBuffer(
                ground_vb,
                0,
                ground_vert_data[0..square_idx],
            );
            endDraw(
                ground_draw_data,
                @as(u64, square_idx) * @sizeOf(GroundVertexData),
                @divFloor(square_idx, 4) * 6,
                null,
            );
        }

        @prefetch(map.entities.items, .{ .locality = 0 });
        idx = game_render.drawEntities(idx, base_draw_data, float_time_ms);
        map.object_lock.unlockShared();

        if (settings.enable_lights) {
            const opts = QuadOptions{ .base_color = map.bg_light_color, .base_color_intensity = 1.0, .alpha_mult = map.getLightIntensity(time) };
            idx = drawQuad(idx, 0, 0, camera.screen_width, camera.screen_height, assets.wall_backface_data, base_draw_data, opts);

            @prefetch(&lights[0..light_idx], .{ .locality = 0 });
            for (lights[0..light_idx]) |data| {
                idx = drawQuad(
                    idx,
                    data.x,
                    data.y,
                    data.w,
                    data.h,
                    assets.light_data,
                    base_draw_data,
                    .{ .base_color = data.color, .base_color_intensity = 1.0, .alpha_mult = data.intensity },
                );
            }
        }
    } else map.object_lock.unlockShared();

    idx = ui_render.drawTempElements(idx, base_draw_data);
    idx = ui_render.drawUiElements(idx, base_draw_data, cam_x, cam_y, time);

    if (idx > 0) {
        encoder.writeBuffer(
            base_vb,
            0,
            base_vert_data[0..idx],
        );
        endDraw(
            base_draw_data,
            @as(u64, idx) * @sizeOf(BaseVertexData),
            @divFloor(idx, 4) * 6,
            null,
        );
    }
}
