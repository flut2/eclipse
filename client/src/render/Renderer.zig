const std = @import("std");

const shared = @import("shared");
const game_data = shared.game_data;
const utils = shared.utils;
const f32i = utils.f32i;
const u32f = utils.u32f;
const stbi = @import("stbi");
const vk = @import("vulkan");

const assets = @import("../assets.zig");
const px_per_tile = @import("../Camera.zig").px_per_tile;
const Camera = @import("../Camera.zig");
const Ally = @import("../game/Ally.zig");
const Container = @import("../game/Container.zig");
const Enemy = @import("../game/Enemy.zig");
const Entity = @import("../game/Entity.zig");
const map = @import("../game/map.zig");
const Particle = @import("../game/particles.zig").Particle;
const Player = @import("../game/Player.zig");
const Portal = @import("../game/Portal.zig");
const Projectile = @import("../game/Projectile.zig");
const Square = @import("../game/Square.zig");
const main = @import("../main.zig");
const element = @import("../ui/elements/element.zig");
const ui_systems = @import("../ui/systems.zig");
const Context = @import("Context.zig");
const Swapchain = @import("Swapchain.zig");
const vma = @import("vma.zig");

const Renderer = @This();

const generic_vert_spv align(@alignOf(u32)) = @embedFile("generic_vert").*;
const generic_frag_spv align(@alignOf(u32)) = @embedFile("generic_frag").*;
const ground_vert_spv align(@alignOf(u32)) = @embedFile("ground_vert").*;
const ground_frag_spv align(@alignOf(u32)) = @embedFile("ground_frag").*;

const DrawData = struct {
    grounds: []const GroundData = &.{},
    generics: []const GenericData = &.{},
    ui_generics: []const GenericData = &.{},
    camera: Camera = .{},
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
    scissor: element.ScissorRect = .{},
    sort_extra: f32 = 0,
    render_type_override: ?RenderType = null,
};

pub const RenderType = enum(u32) {
    quad = 0,
    ui_quad = 1,
    minimap = 2,
    text_normal = 3,
    text_subpixel = 4,
};

pub const GenericData = extern struct {
    render_type: RenderType = .quad,
    text_type: element.TextType = .bold,
    rotation: f32 = 0.0,
    text_dist_factor: f32 = 0.0,
    padding1: u32 = 0,
    alpha_mult: f32 = 1.0,
    outline_color: u32 = 0,
    outline_width: f32 = 0.0,
    base_color: u32 = 0,
    color_intensity: f32 = 0.0,
    pos: [2]f32 = .{ 0.0, 0.0 },
    size: [2]f32 = .{ 1.0, 1.0 },
    uv: [2]f32 = .{ -1.0, -1.0 },
    uv_size: [2]f32 = .{ 0.0, 0.0 },
    padding2: [2]f32 = .{ 0.0, 0.0 },
    scissor: [4]f32 = .{ 0.0, 1.0, 0.0, 1.0 }, // min x, max x, min y, max y, in tex coord space
};

pub const GroundData = extern struct {
    pos: [2]f32,
    uv: [2]f32,
    offset_uv: [2]f32,
    left_blend_uv: [2]f32,
    left_blend_offset_uv: [2]f32,
    top_blend_uv: [2]f32,
    top_blend_offset_uv: [2]f32,
    right_blend_uv: [2]f32,
    right_blend_offset_uv: [2]f32,
    bottom_blend_uv: [2]f32,
    bottom_blend_offset_uv: [2]f32,
    rotation: f32,
    color: utils.RGBA,
};

pub const GenericPushConstants = extern struct {
    clip_scale: [2]f32,
    clip_offset: [2]f32,
    is_ui: u32,
};

pub const GroundPushConstants = extern struct {
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
    for (.{ GroundData, GenericData }) |T| {
        const missing_bytes = @mod(@sizeOf(T), 16);
        if (missing_bytes != 0)
            @compileError(std.fmt.comptimePrint(
                "All GPU-facing structs must have byte lengths with multiples of 16, please add padding to {s}, pad bytes missing: {}",
                .{
                    @typeName(T),
                    missing_bytes,
                },
            ));
    }
}

const Buffer = struct {
    buffer: vma.AllocatedBuffer = .{ .handle = .null_handle, .allocation = null },
    size: vk.DeviceSize = 0,

    pub fn destroy(self: Buffer, vk_allocator: vma.Allocator) void {
        vk_allocator.destroyBuffer(self.buffer.handle, self.buffer.allocation);
    }
};

const StagingBuffer = struct {
    buffer: vma.AllocatedBuffer = .{ .handle = .null_handle, .allocation = null },
    alloc_info: vma.AllocationInfo = .{},

    pub fn destroy(self: StagingBuffer, vk_allocator: vma.Allocator) void {
        vk_allocator.destroyBuffer(self.buffer.handle, self.buffer.allocation);
    }
};

const Texture = struct {
    image: vma.AllocatedImage = .{ .handle = .null_handle, .allocation = null },
    view: vk.ImageView = .null_handle,
    format: vk.Format = .undefined,
    extent: vk.Extent3D = .{ .depth = 0, .width = 0, .height = 0 },

    pub fn destroy(self: Texture, ctx: Context, vk_allocator: vma.Allocator) void {
        vk_allocator.destroyImage(self.image.handle, self.image.allocation);
        ctx.device.destroyImageView(self.view, null);
    }
};

const Material = struct {
    // not really generic but whatever
    descriptor_sets: [2]vk.DescriptorSet = .{ .null_handle, .null_handle },
    descriptor_layouts: [2]vk.DescriptorSetLayout = .{ .null_handle, .null_handle },
    pipeline: vk.Pipeline = .null_handle,
    pipeline_layout: vk.PipelineLayout = .null_handle,

    pub fn destroy(self: Material, ctx: Context) void {
        for (self.descriptor_layouts) |layout| if (layout != .null_handle) ctx.device.destroyDescriptorSetLayout(layout, null);
        ctx.device.destroyPipeline(self.pipeline, null);
        ctx.device.destroyPipelineLayout(self.pipeline_layout, null);
    }
};

pub const ground_size = 200000;
pub const generic_size = 50000;
pub const ui_size = 2000;

medium_text: Texture = .{},
medium_italic_text: Texture = .{},
bold_text: Texture = .{},
bold_italic_text: Texture = .{},
default: Texture = .{},
ui: Texture = .{},
minimap: Texture = .{},

generic_material: Material = .{},
ground_material: Material = .{},

generic_buffer: Buffer = .{},
ground_buffer: Buffer = .{},
ui_buffer: Buffer = .{},

generic_staging_buffer: StagingBuffer = .{},
ground_staging_buffer: StagingBuffer = .{},
ui_staging_buffer: StagingBuffer = .{},

nearest_sampler: vk.Sampler = .null_handle,
linear_sampler: vk.Sampler = .null_handle,

condition_rects: [@bitSizeOf(utils.Condition)][]const assets.AtlasData = @splat(&.{}),
enter_text_data: element.TextData = .{ .text = "", .size = 0 },
sort_extras: std.ArrayList(f32) = .empty,
generics: std.ArrayList(GenericData) = .empty,
grounds: std.ArrayList(GroundData) = .empty,
lights: std.ArrayList(LightData) = .empty,

render_pass: vk.RenderPass = .null_handle,
cmd_pool: vk.CommandPool = .null_handle,
descriptor_pool: vk.DescriptorPool = .null_handle,
framebuffers: []vk.Framebuffer = &.{},
cmd_buffers: []vk.CommandBuffer = &.{},
context: Context = undefined,
swapchain: Swapchain = undefined,
vk_allocator: vma.Allocator = undefined,

draw_queue: utils.SpscQueue(DrawData, main.frames_in_flight) = .{},

pub fn create(present_mode: vk.PresentModeKHR) !Renderer {
    var self: Renderer = .{};

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
            .hidden, .invisible, .paralyzed, .stunned, .silenced, .encased_in_stone => &.{},
        };

        const indices_len = sheet_indices.len;
        if (indices_len == 0) {
            self.condition_rects[i] = &.{};
            continue;
        }

        var rects = main.allocator.alloc(assets.AtlasData, indices_len) catch continue;
        for (0..indices_len) |j|
            rects[j] = (assets.atlas_data.get(sheet_name) orelse
                std.debug.panic("Could not find sheet {s} for cond parsing", .{sheet_name}))[sheet_indices[j]];

        self.condition_rects[i] = rects;
    }

    self.enter_text_data = .{ .text = undefined, .text_type = .bold, .size = 12 };
    self.enter_text_data.setText("Enter");

    self.context = try .init(main.window);

    const extent: vk.Extent2D = .{ .width = u32f(main.camera.width), .height = u32f(main.camera.height) };
    self.swapchain = try .init(self.context, extent, present_mode);

    self.vk_allocator = try .create(&.{
        .physical_device = self.context.phys_device,
        .device = self.context.device.handle,
        .instance = self.context.instance.handle,
    });

    self.cmd_pool = try self.context.device.createCommandPool(&.{
        .flags = .{ .reset_command_buffer_bit = true },
        .queue_family_index = self.context.graphics_queue.family,
    }, null);

    self.descriptor_pool = try self.context.device.createDescriptorPool(&.{
        .max_sets = 4,
        .pool_size_count = 2,
        .p_pool_sizes = &.{
            .{ .type = .combined_image_sampler, .descriptor_count = 32 },
            .{ .type = .storage_buffer, .descriptor_count = 4 },
        },
    }, null);

    const generic_buf_size = @sizeOf(GenericData) * generic_size;
    self.generic_buffer = .{
        .buffer = try self.vk_allocator.createBuffer(
            &.{
                .size = generic_buf_size,
                .usage = .{ .storage_buffer_bit = true, .transfer_dst_bit = true },
                .sharing_mode = .exclusive,
            },
            &.{
                .usage = .gpu_only,
                .required_flags = .{ .device_local_bit = true },
            },
            null,
        ),
        .size = generic_buf_size,
    };

    const ground_buf_size = @sizeOf(GroundData) * ground_size;
    self.ground_buffer = .{
        .buffer = try self.vk_allocator.createBuffer(
            &.{
                .size = ground_buf_size,
                .usage = .{ .storage_buffer_bit = true, .transfer_dst_bit = true },
                .sharing_mode = .exclusive,
            },
            &.{
                .usage = .gpu_only,
                .required_flags = .{ .device_local_bit = true },
            },
            null,
        ),
        .size = ground_buf_size,
    };

    const ui_buf_size = @sizeOf(GenericData) * ui_size;
    self.ui_buffer = .{
        .buffer = try self.vk_allocator.createBuffer(
            &.{
                .size = ui_buf_size,
                .usage = .{ .storage_buffer_bit = true, .transfer_dst_bit = true },
                .sharing_mode = .exclusive,
            },
            &.{
                .usage = .gpu_only,
                .required_flags = .{ .device_local_bit = true },
            },
            null,
        ),
        .size = ui_buf_size,
    };

    var generic_alloc_info: vma.AllocationInfo = undefined;
    const generic_staging_buffer = try self.vk_allocator.createBuffer(
        &.{
            .size = generic_buf_size,
            .usage = .{ .transfer_src_bit = true },
            .sharing_mode = .exclusive,
        },
        &.{
            .usage = .cpu_only,
            .flags = .{ .host_access_sequential_write_bit = true, .mapped_bit = true },
        },
        &generic_alloc_info,
    );
    self.generic_staging_buffer = .{
        .buffer = generic_staging_buffer,
        .alloc_info = generic_alloc_info,
    };

    var ui_alloc_info: vma.AllocationInfo = undefined;
    const ui_staging_buffer = try self.vk_allocator.createBuffer(
        &.{
            .size = ui_buf_size,
            .usage = .{ .transfer_src_bit = true },
            .sharing_mode = .exclusive,
        },
        &.{
            .usage = .cpu_only,
            .flags = .{ .host_access_sequential_write_bit = true, .mapped_bit = true },
        },
        &ui_alloc_info,
    );
    self.ui_staging_buffer = .{
        .buffer = ui_staging_buffer,
        .alloc_info = ui_alloc_info,
    };

    var ground_alloc_info: vma.AllocationInfo = undefined;
    const ground_staging_buffer = try self.vk_allocator.createBuffer(
        &.{
            .size = ground_buf_size,
            .usage = .{ .transfer_src_bit = true },
            .sharing_mode = .exclusive,
        },
        &.{
            .usage = .cpu_only,
            .flags = .{ .host_access_sequential_write_bit = true, .mapped_bit = true },
        },
        &ground_alloc_info,
    );
    self.ground_staging_buffer = .{
        .buffer = ground_staging_buffer,
        .alloc_info = ground_alloc_info,
    };

    self.nearest_sampler = try self.context.device.createSampler(&.{
        .mag_filter = .nearest,
        .min_filter = .nearest,
        .mipmap_mode = .nearest,
        .address_mode_u = .repeat,
        .address_mode_v = .repeat,
        .address_mode_w = .repeat,
        .mip_lod_bias = 0.0,
        .anisotropy_enable = .false,
        .max_anisotropy = 1.0,
        .compare_enable = .false,
        .compare_op = .always,
        .min_lod = 0.0,
        .max_lod = 0.0,
        .border_color = .float_transparent_black,
        .unnormalized_coordinates = .false,
    }, null);

    self.linear_sampler = try self.context.device.createSampler(&.{
        .mag_filter = .linear,
        .min_filter = .linear,
        .mipmap_mode = .linear,
        .address_mode_u = .repeat,
        .address_mode_v = .repeat,
        .address_mode_w = .repeat,
        .mip_lod_bias = 0.0,
        .anisotropy_enable = .false,
        .max_anisotropy = 1.0,
        .compare_enable = .false,
        .compare_op = .always,
        .min_lod = 0.0,
        .max_lod = 0.0,
        .border_color = .float_transparent_black,
        .unnormalized_coordinates = .false,
    }, null);

    try self.createRenderPass();
    try self.createFrameAndCmdBuffers();

    inline for (.{
        .{ &self.medium_text, assets.medium_atlas, true },
        .{ &self.medium_italic_text, assets.medium_italic_atlas, true },
        .{ &self.bold_text, assets.bold_atlas, true },
        .{ &self.bold_italic_text, assets.bold_italic_atlas, true },
        .{ &self.default, assets.atlas, false },
        .{ &self.ui, assets.ui_atlas, false },
        .{ &self.minimap, map.minimap, false },
    }) |mapping| mapping[0].* = try createTexture(
        self.context,
        self.cmd_pool,
        self.vk_allocator,
        .{ .depth = 1, .width = mapping[1].width, .height = mapping[1].height },
        if (mapping[2]) .r8_unorm else .r8g8b8a8_srgb,
        .{ .transfer_dst_bit = true, .sampled_bit = true },
        mapping[1].data,
    );

    assets.medium_atlas.deinit();
    assets.medium_italic_atlas.deinit();
    assets.bold_atlas.deinit();
    assets.bold_italic_atlas.deinit();
    assets.atlas.deinit();
    assets.ui_atlas.deinit();

    try self.createGenericMaterial();
    try self.createGroundMaterial();

    return self;
}

pub fn destroy(self: *Renderer) !void {
    try self.swapchain.waitForAllFences(self.context);
    try self.context.device.deviceWaitIdle();

    self.medium_text.destroy(self.context, self.vk_allocator);
    self.medium_italic_text.destroy(self.context, self.vk_allocator);
    self.bold_text.destroy(self.context, self.vk_allocator);
    self.bold_italic_text.destroy(self.context, self.vk_allocator);
    self.default.destroy(self.context, self.vk_allocator);
    self.ui.destroy(self.context, self.vk_allocator);
    self.minimap.destroy(self.context, self.vk_allocator);

    self.generic_material.destroy(self.context);
    self.ground_material.destroy(self.context);

    self.generic_buffer.destroy(self.vk_allocator);
    self.ground_buffer.destroy(self.vk_allocator);
    self.ui_buffer.destroy(self.vk_allocator);

    self.generic_staging_buffer.destroy(self.vk_allocator);
    self.ground_staging_buffer.destroy(self.vk_allocator);
    self.ui_staging_buffer.destroy(self.vk_allocator);

    self.context.device.destroySampler(self.nearest_sampler, null);
    self.context.device.destroySampler(self.linear_sampler, null);

    self.sort_extras.deinit(main.allocator);
    self.generics.deinit(main.allocator);
    self.grounds.deinit(main.allocator);
    self.lights.deinit(main.allocator);

    self.enter_text_data.deinit();
    for (self.condition_rects) |rects| main.allocator.free(rects);

    self.destroyFrameAndCmdBuffers();
    self.context.device.destroyRenderPass(self.render_pass, null);
    self.context.device.destroyCommandPool(self.cmd_pool, null);
    self.context.device.destroyDescriptorPool(self.descriptor_pool, null);
    self.swapchain.deinit(self.context);
    self.vk_allocator.destroy();
    self.context.deinit();
}

fn writeToBuffer(
    ctx: Context,
    cmd_pool: vk.CommandPool,
    staging_buffer: StagingBuffer,
    dst_buffer: vk.Buffer,
    comptime T: type,
    data: []const T,
) !void {
    const size = @sizeOf(T) * data.len;
    if (size == 0) return;
    @memcpy(@as([*]u8, @ptrCast(staging_buffer.alloc_info.p_mapped_data.?)), std.mem.sliceAsBytes(data));
    try copyBuffer(ctx, cmd_pool, staging_buffer.buffer.handle, dst_buffer, size);
}

fn writeToBufferSimple(
    ctx: Context,
    cmd_buffer: vk.CommandBuffer,
    staging_buffer: StagingBuffer,
    dst_buffer: vk.Buffer,
    comptime T: type,
    data: []const T,
) void {
    const size = @sizeOf(T) * data.len;
    if (size == 0) return;
    @memcpy(@as([*]u8, @ptrCast(staging_buffer.alloc_info.p_mapped_data.?)), std.mem.sliceAsBytes(data));
    copySimple(ctx, cmd_buffer, staging_buffer.buffer.handle, dst_buffer, size);
}

pub fn createFrameAndCmdBuffers(self: *Renderer) !void {
    self.cmd_buffers = main.allocator.alloc(vk.CommandBuffer, self.swapchain.swap_images.len) catch main.oomPanic();
    try self.context.device.allocateCommandBuffers(&.{
        .command_pool = self.cmd_pool,
        .level = .primary,
        .command_buffer_count = @intCast(self.cmd_buffers.len),
    }, self.cmd_buffers.ptr);
    self.framebuffers = main.allocator.alloc(vk.Framebuffer, self.swapchain.swap_images.len) catch main.oomPanic();
    for (self.swapchain.swap_images, self.framebuffers) |swap_img, *framebuffer|
        framebuffer.* = try self.context.device.createFramebuffer(&.{
            .render_pass = self.render_pass,
            .attachment_count = 1,
            .p_attachments = @ptrCast(&swap_img.view),
            .width = self.swapchain.extent.width,
            .height = self.swapchain.extent.height,
            .layers = 1,
        }, null);
}

pub fn destroyFrameAndCmdBuffers(self: *Renderer) void {
    for (self.framebuffers) |framebuffer| if (framebuffer != .null_handle)
        self.context.device.destroyFramebuffer(framebuffer, null);
    main.allocator.free(self.framebuffers);
    self.framebuffers = &.{};
    self.context.device.freeCommandBuffers(self.cmd_pool, @intCast(self.cmd_buffers.len), self.cmd_buffers.ptr);
    main.allocator.free(self.cmd_buffers);
    self.cmd_buffers = &.{};
}

fn createImmediateSubmit(ctx: Context, cmd_pool: vk.CommandPool) !vk.CommandBuffer {
    var ret: vk.CommandBuffer = undefined;
    try ctx.device.allocateCommandBuffers(&.{
        .level = .primary,
        .command_pool = cmd_pool,
        .command_buffer_count = 1,
    }, @ptrCast(&ret));
    try ctx.device.beginCommandBuffer(ret, &.{ .flags = .{ .one_time_submit_bit = true } });
    return ret;
}

fn destroyImmediateSubmit(ctx: Context, cmd_pool: vk.CommandPool, cmd_buffer: vk.CommandBuffer) !void {
    try ctx.device.endCommandBuffer(cmd_buffer);
    try ctx.device.queueSubmit(ctx.graphics_queue.handle, 1, &.{.{
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&cmd_buffer),
    }}, .null_handle);
    try ctx.device.queueWaitIdle(ctx.graphics_queue.handle);
    ctx.device.freeCommandBuffers(cmd_pool, 1, @ptrCast(&cmd_buffer));
}

fn copyBuffer(
    ctx: Context,
    cmd_pool: vk.CommandPool,
    src_buffer: vk.Buffer,
    dst_buffer: vk.Buffer,
    size: vk.DeviceSize,
) !void {
    const cmd_buffer = try createImmediateSubmit(ctx, cmd_pool);
    copySimple(ctx, cmd_buffer, src_buffer, dst_buffer, size);
    try destroyImmediateSubmit(ctx, cmd_pool, cmd_buffer);
}

fn copySimple(
    ctx: Context,
    cmd_buffer: vk.CommandBuffer,
    src_buffer: vk.Buffer,
    dst_buffer: vk.Buffer,
    size: vk.DeviceSize,
) void {
    ctx.device.cmdCopyBuffer(
        cmd_buffer,
        src_buffer,
        dst_buffer,
        1,
        &.{.{
            .src_offset = 0,
            .dst_offset = 0,
            .size = size,
        }},
    );
}

fn transitionImageLayout(
    ctx: Context,
    cmd_pool: vk.CommandPool,
    texture: Texture,
    old_layout: vk.ImageLayout,
    new_layout: vk.ImageLayout,
) !void {
    const cmd_buffer = try createImmediateSubmit(ctx, cmd_pool);

    // zig fmt: off
    const barrier_src_mask: vk.AccessFlags,
    const barrier_dst_mask: vk.AccessFlags,
    const src_stage_mask: vk.PipelineStageFlags, 
    const dst_stage_mask: vk.PipelineStageFlags = 
        if (old_layout == .undefined and new_layout == .transfer_dst_optimal) .{
            .{},
            .{ .transfer_write_bit = true },
            .{ .top_of_pipe_bit = true },
            .{ .transfer_bit = true },
        } else if (old_layout == .transfer_dst_optimal and new_layout == .shader_read_only_optimal) .{
            .{ .transfer_write_bit = true },
            .{ .shader_read_bit = true },
            .{ .transfer_bit = true },
            .{ .fragment_shader_bit = true },
        } else @panic("Invalid image transition");
    // zig fmt: on

    ctx.device.cmdPipelineBarrier(
        cmd_buffer,
        src_stage_mask,
        dst_stage_mask,
        .{},
        0,
        null,
        0,
        null,
        1,
        &.{.{
            .image = texture.image.handle,
            .src_access_mask = barrier_src_mask,
            .dst_access_mask = barrier_dst_mask,
            .old_layout = old_layout,
            .new_layout = new_layout,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .subresource_range = .{
                .aspect_mask = if (texture.format == .d32_sfloat) .{ .depth_bit = true } else .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }},
    );
    try destroyImmediateSubmit(ctx, cmd_pool, cmd_buffer);
}

fn copyBufferToTexture(
    ctx: Context,
    cmd_pool: vk.CommandPool,
    buffer: vk.Buffer,
    texture: Texture,
    w: u32,
    h: u32,
    offset_x: i32,
    offset_y: i32,
) !void {
    const cmd_buffer = try createImmediateSubmit(ctx, cmd_pool);
    ctx.device.cmdCopyBufferToImage(
        cmd_buffer,
        buffer,
        texture.image.handle,
        .transfer_dst_optimal,
        1,
        &.{.{
            .buffer_offset = 0,
            .buffer_image_height = 0,
            .buffer_row_length = 0,
            .image_extent = .{ .depth = 1, .width = w, .height = h },
            .image_offset = .{ .x = offset_x, .y = offset_y, .z = 0 },
            .image_subresource = .{
                .aspect_mask = if (texture.format == .d32_sfloat) .{ .depth_bit = true } else .{ .color_bit = true },
                .mip_level = 0,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }},
    );
    try destroyImmediateSubmit(ctx, cmd_pool, cmd_buffer);
}

fn createTexture(
    ctx: Context,
    cmd_pool: vk.CommandPool,
    vk_allocator: vma.Allocator,
    size: vk.Extent3D,
    format: vk.Format,
    usage: vk.ImageUsageFlags,
    image_data: []const u8,
) !Texture {
    const image = try vk_allocator.createImage(
        &.{
            .image_type = .@"2d",
            .extent = size,
            .format = format,
            .usage = usage,
            .mip_levels = 1,
            .array_layers = 1,
            .samples = .{ .@"1_bit" = true },
            .tiling = .optimal,
            .sharing_mode = .exclusive,
            .initial_layout = .undefined,
        },
        &.{
            .usage = .gpu_only,
            .required_flags = .{ .device_local_bit = true },
        },
        null,
    );
    const tex: Texture = .{
        .format = format,
        .extent = size,
        .image = image,
        .view = try ctx.device.createImageView(&.{
            .image = image.handle,
            .view_type = .@"2d",
            .format = format,
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{
                .aspect_mask = if (format == .d32_sfloat) .{ .depth_bit = true } else .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }, null),
    };

    try updateTexture(ctx, cmd_pool, vk_allocator, tex, image_data, size.width, size.height, 0, 0);

    return tex;
}

pub fn updateTexture(
    ctx: Context,
    cmd_pool: vk.CommandPool,
    vk_allocator: vma.Allocator,
    tex: Texture,
    image_data: []const u8,
    w: u32,
    h: u32,
    offset_x: i32,
    offset_y: i32,
) !void {
    const staging_buffer = try vk_allocator.createBuffer(
        &.{
            .size = image_data.len * @sizeOf(u8),
            .usage = .{ .transfer_src_bit = true },
            .sharing_mode = .exclusive,
        },
        &.{
            .usage = .cpu_only,
            .flags = .{ .host_access_sequential_write_bit = true },
        },
        null,
    );
    defer vk_allocator.destroyBuffer(staging_buffer.handle, staging_buffer.allocation);
    {
        const data = try vk_allocator.mapMemory(staging_buffer.allocation);
        defer vk_allocator.unmapMemory(staging_buffer.allocation);
        @memcpy(@as([*]u8, @ptrCast(data.?)), image_data);
    }

    try transitionImageLayout(ctx, cmd_pool, tex, .undefined, .transfer_dst_optimal);
    try copyBufferToTexture(ctx, cmd_pool, staging_buffer.handle, tex, w, h, offset_x, offset_y);
    try transitionImageLayout(ctx, cmd_pool, tex, .transfer_dst_optimal, .shader_read_only_optimal);
}

fn createRenderPass(self: *Renderer) !void {
    const color_attachment: vk.AttachmentDescription = .{
        .format = self.swapchain.surface_format.format,
        .samples = .{ .@"1_bit" = true },
        .load_op = .clear,
        .store_op = .store,
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        .initial_layout = .undefined,
        .final_layout = .present_src_khr,
    };

    const color_attachment_ref: vk.AttachmentReference = .{
        .attachment = 0,
        .layout = .color_attachment_optimal,
    };

    const subpass: vk.SubpassDescription = .{
        .pipeline_bind_point = .graphics,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast(&color_attachment_ref),
    };

    self.render_pass = try self.context.device.createRenderPass(&.{
        .attachment_count = 1,
        .p_attachments = @ptrCast(&color_attachment),
        .subpass_count = 1,
        .p_subpasses = @ptrCast(&subpass),
    }, null);
}

fn createGenericMaterial(self: *Renderer) !void {
    const descriptor_bindings_one: []const vk.DescriptorSetLayoutBinding = &.{
        .{
            .binding = 0,
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = 1,
            .stage_flags = .{ .fragment_bit = true },
            .p_immutable_samplers = @ptrCast(&self.nearest_sampler),
        },
        .{
            .binding = 1,
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = 1,
            .stage_flags = .{ .fragment_bit = true },
            .p_immutable_samplers = @ptrCast(&self.nearest_sampler),
        },
        .{
            .binding = 2,
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = 1,
            .stage_flags = .{ .fragment_bit = true },
            .p_immutable_samplers = @ptrCast(&self.linear_sampler),
        },
        .{
            .binding = 3,
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = 1,
            .stage_flags = .{ .fragment_bit = true },
            .p_immutable_samplers = @ptrCast(&self.linear_sampler),
        },
        .{
            .binding = 4,
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = 1,
            .stage_flags = .{ .fragment_bit = true },
            .p_immutable_samplers = @ptrCast(&self.linear_sampler),
        },
        .{
            .binding = 5,
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = 1,
            .stage_flags = .{ .fragment_bit = true },
            .p_immutable_samplers = @ptrCast(&self.linear_sampler),
        },
        .{
            .binding = 6,
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = 1,
            .stage_flags = .{ .fragment_bit = true },
            .p_immutable_samplers = @ptrCast(&self.nearest_sampler),
        },
        .{
            .binding = 7,
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = 1,
            .stage_flags = .{ .fragment_bit = true },
            .p_immutable_samplers = @ptrCast(&self.linear_sampler),
        },
    };
    const descriptor_layout_one = try self.context.device.createDescriptorSetLayout(&.{
        .binding_count = @intCast(descriptor_bindings_one.len),
        .p_bindings = @ptrCast(descriptor_bindings_one),
    }, null);

    const descriptor_bindings_two: []const vk.DescriptorSetLayoutBinding = &.{
        .{
            .binding = 0,
            .descriptor_type = .storage_buffer,
            .descriptor_count = 1,
            .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
        },
        .{
            .binding = 1,
            .descriptor_type = .storage_buffer,
            .descriptor_count = 1,
            .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
        },
    };
    const descriptor_layout_two = try self.context.device.createDescriptorSetLayout(&.{
        .binding_count = @intCast(descriptor_bindings_two.len),
        .p_bindings = @ptrCast(descriptor_bindings_two),
    }, null);

    const push_constant_range: vk.PushConstantRange = .{
        .offset = 0,
        .size = @sizeOf(GenericPushConstants),
        .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
    };

    const descriptor_layouts: [2]vk.DescriptorSetLayout = .{ descriptor_layout_one, descriptor_layout_two };

    const pipeline_layout = try self.context.device.createPipelineLayout(&.{
        .set_layout_count = 2,
        .p_set_layouts = @ptrCast(&descriptor_layouts),
        .push_constant_range_count = 1,
        .p_push_constant_ranges = @ptrCast(&push_constant_range),
    }, null);

    var descriptor_sets: [2]vk.DescriptorSet = .{ .null_handle, .null_handle };
    try self.context.device.allocateDescriptorSets(&.{
        .descriptor_pool = self.descriptor_pool,
        .descriptor_set_count = 2,
        .p_set_layouts = @ptrCast(&descriptor_layouts),
    }, @ptrCast(&descriptor_sets));

    self.context.device.updateDescriptorSets(9, &.{
        .{
            .dst_set = descriptor_sets[0],
            .dst_binding = 0,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = &.{.{
                .sampler = self.nearest_sampler,
                .image_view = self.default.view,
                .image_layout = .shader_read_only_optimal,
            }},
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
        },
        .{
            .dst_set = descriptor_sets[0],
            .dst_binding = 1,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = &.{.{
                .sampler = self.nearest_sampler,
                .image_view = self.ui.view,
                .image_layout = .shader_read_only_optimal,
            }},
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
        },
        .{
            .dst_set = descriptor_sets[0],
            .dst_binding = 2,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = &.{.{
                .sampler = self.linear_sampler,
                .image_view = self.medium_text.view,
                .image_layout = .shader_read_only_optimal,
            }},
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
        },
        .{
            .dst_set = descriptor_sets[0],
            .dst_binding = 3,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = &.{.{
                .sampler = self.linear_sampler,
                .image_view = self.medium_italic_text.view,
                .image_layout = .shader_read_only_optimal,
            }},
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
        },
        .{
            .dst_set = descriptor_sets[0],
            .dst_binding = 4,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = &.{.{
                .sampler = self.linear_sampler,
                .image_view = self.bold_text.view,
                .image_layout = .shader_read_only_optimal,
            }},
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
        },
        .{
            .dst_set = descriptor_sets[0],
            .dst_binding = 5,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = &.{.{
                .sampler = self.linear_sampler,
                .image_view = self.bold_italic_text.view,
                .image_layout = .shader_read_only_optimal,
            }},
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
        },
        .{
            .dst_set = descriptor_sets[0],
            .dst_binding = 6,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = &.{.{
                .sampler = self.nearest_sampler,
                .image_view = self.minimap.view,
                .image_layout = .shader_read_only_optimal,
            }},
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
        },
        .{
            .dst_set = descriptor_sets[1],
            .dst_binding = 0,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .storage_buffer,
            .p_image_info = undefined,
            .p_buffer_info = &.{.{
                .buffer = self.generic_buffer.buffer.handle,
                .offset = 0,
                .range = @sizeOf(GenericData) * generic_size,
            }},
            .p_texel_buffer_view = undefined,
        },
        .{
            .dst_set = descriptor_sets[1],
            .dst_binding = 1,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .storage_buffer,
            .p_image_info = undefined,
            .p_buffer_info = &.{.{
                .buffer = self.ui_buffer.buffer.handle,
                .offset = 0,
                .range = @sizeOf(GenericData) * ui_size,
            }},
            .p_texel_buffer_view = undefined,
        },
    }, 0, undefined);

    const vert_shader = try self.context.device.createShaderModule(&.{
        .code_size = generic_vert_spv.len,
        .p_code = @ptrCast(&generic_vert_spv),
    }, null);
    defer self.context.device.destroyShaderModule(vert_shader, null);

    const frag_shader = try self.context.device.createShaderModule(&.{
        .code_size = generic_frag_spv.len,
        .p_code = @ptrCast(&generic_frag_spv),
    }, null);
    defer self.context.device.destroyShaderModule(frag_shader, null);

    const attachments: []const vk.PipelineColorBlendAttachmentState = &.{.{
        .blend_enable = .true,
        .src_color_blend_factor = .one,
        .dst_color_blend_factor = .one_minus_src_alpha,
        .color_blend_op = .add,
        .src_alpha_blend_factor = .one,
        .dst_alpha_blend_factor = .one_minus_src_alpha,
        .alpha_blend_op = .add,
        .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
    }};

    const pipeline_info: vk.GraphicsPipelineCreateInfo = .{
        .flags = .{},
        .stage_count = 2,
        .p_stages = &.{
            .{ .stage = .{ .vertex_bit = true }, .module = vert_shader, .p_name = "main" },
            .{ .stage = .{ .fragment_bit = true }, .module = frag_shader, .p_name = "main" },
        },
        .p_vertex_input_state = &.{},
        .p_input_assembly_state = &.{
            .topology = .triangle_list,
            .primitive_restart_enable = .false,
        },
        .p_tessellation_state = null,
        .p_viewport_state = &.{
            .viewport_count = 1,
            .p_viewports = undefined,
            .scissor_count = 1,
            .p_scissors = undefined,
        },
        .p_rasterization_state = &.{
            .depth_clamp_enable = .false,
            .rasterizer_discard_enable = .false,
            .polygon_mode = .fill,
            .cull_mode = .{},
            .front_face = .clockwise,
            .depth_bias_enable = .false,
            .depth_bias_constant_factor = 0,
            .depth_bias_clamp = 0,
            .depth_bias_slope_factor = 0,
            .line_width = 1,
        },
        .p_multisample_state = &.{
            .rasterization_samples = .{ .@"1_bit" = true },
            .sample_shading_enable = .false,
            .min_sample_shading = 1,
            .alpha_to_coverage_enable = .false,
            .alpha_to_one_enable = .false,
        },
        .p_depth_stencil_state = null,
        .p_color_blend_state = &.{
            .logic_op_enable = .false,
            .logic_op = .copy,
            .attachment_count = 1,
            .p_attachments = @ptrCast(attachments),
            .blend_constants = [_]f32{ 0, 0, 0, 0 },
        },
        .p_dynamic_state = &.{
            .flags = .{},
            .dynamic_state_count = 2,
            .p_dynamic_states = &.{ .viewport, .scissor },
        },
        .layout = pipeline_layout,
        .render_pass = self.render_pass,
        .subpass = 0,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    };

    var pipeline: vk.Pipeline = undefined;
    _ = try self.context.device.createGraphicsPipelines(.null_handle, 1, @ptrCast(&pipeline_info), null, @ptrCast(&pipeline));
    self.generic_material = .{
        .descriptor_layouts = descriptor_layouts,
        .descriptor_sets = descriptor_sets,
        .pipeline = pipeline,
        .pipeline_layout = pipeline_layout,
    };
}

fn createGroundMaterial(self: *Renderer) !void {
    const descriptor_bindings_one: []const vk.DescriptorSetLayoutBinding = &.{
        .{
            .binding = 0,
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = 1,
            .stage_flags = .{ .fragment_bit = true },
            .p_immutable_samplers = @ptrCast(&self.nearest_sampler),
        },
    };
    const descriptor_layout_one = try self.context.device.createDescriptorSetLayout(&.{
        .binding_count = @intCast(descriptor_bindings_one.len),
        .p_bindings = @ptrCast(descriptor_bindings_one),
    }, null);

    const descriptor_bindings_two: []const vk.DescriptorSetLayoutBinding = &.{
        .{
            .binding = 0,
            .descriptor_type = .storage_buffer,
            .descriptor_count = 1,
            .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
        },
    };
    const descriptor_layout_two = try self.context.device.createDescriptorSetLayout(&.{
        .binding_count = @intCast(descriptor_bindings_two.len),
        .p_bindings = @ptrCast(descriptor_bindings_two),
    }, null);

    const push_constant_range: vk.PushConstantRange = .{
        .offset = 0,
        .size = @sizeOf(GroundPushConstants),
        .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
    };

    const descriptor_layouts: [2]vk.DescriptorSetLayout = .{ descriptor_layout_one, descriptor_layout_two };

    const pipeline_layout = try self.context.device.createPipelineLayout(&.{
        .set_layout_count = 2,
        .p_set_layouts = @ptrCast(&descriptor_layouts),
        .push_constant_range_count = 1,
        .p_push_constant_ranges = @ptrCast(&push_constant_range),
    }, null);

    var descriptor_sets: [2]vk.DescriptorSet = .{ .null_handle, .null_handle };
    try self.context.device.allocateDescriptorSets(&.{
        .descriptor_pool = self.descriptor_pool,
        .descriptor_set_count = 2,
        .p_set_layouts = @ptrCast(&descriptor_layouts),
    }, @ptrCast(&descriptor_sets));

    self.context.device.updateDescriptorSets(2, &.{
        .{
            .dst_set = descriptor_sets[0],
            .dst_binding = 0,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = &.{.{
                .sampler = self.nearest_sampler,
                .image_view = self.default.view,
                .image_layout = .shader_read_only_optimal,
            }},
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
        },
        .{
            .dst_set = descriptor_sets[1],
            .dst_binding = 0,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .storage_buffer,
            .p_image_info = undefined,
            .p_buffer_info = &.{.{
                .buffer = self.ground_buffer.buffer.handle,
                .offset = 0,
                .range = @sizeOf(GroundData) * ground_size,
            }},
            .p_texel_buffer_view = undefined,
        },
    }, 0, undefined);

    const vert_shader = try self.context.device.createShaderModule(&.{
        .code_size = ground_vert_spv.len,
        .p_code = @ptrCast(&ground_vert_spv),
    }, null);
    defer self.context.device.destroyShaderModule(vert_shader, null);

    const frag_shader = try self.context.device.createShaderModule(&.{
        .code_size = ground_frag_spv.len,
        .p_code = @ptrCast(&ground_frag_spv),
    }, null);
    defer self.context.device.destroyShaderModule(frag_shader, null);

    const attachments: []const vk.PipelineColorBlendAttachmentState = &.{.{
        .blend_enable = .false,
        .src_color_blend_factor = .one,
        .dst_color_blend_factor = .one,
        .color_blend_op = .add,
        .src_alpha_blend_factor = .one,
        .dst_alpha_blend_factor = .one,
        .alpha_blend_op = .add,
        .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
    }};

    const pipeline_info: vk.GraphicsPipelineCreateInfo = .{
        .flags = .{},
        .stage_count = 2,
        .p_stages = &.{
            .{ .stage = .{ .vertex_bit = true }, .module = vert_shader, .p_name = "main" },
            .{ .stage = .{ .fragment_bit = true }, .module = frag_shader, .p_name = "main" },
        },
        .p_vertex_input_state = &.{},
        .p_input_assembly_state = &.{
            .topology = .triangle_list,
            .primitive_restart_enable = .false,
        },
        .p_tessellation_state = null,
        .p_viewport_state = &.{
            .viewport_count = 1,
            .p_viewports = undefined,
            .scissor_count = 1,
            .p_scissors = undefined,
        },
        .p_rasterization_state = &.{
            .depth_clamp_enable = .false,
            .rasterizer_discard_enable = .false,
            .polygon_mode = .fill,
            .cull_mode = .{},
            .front_face = .clockwise,
            .depth_bias_enable = .false,
            .depth_bias_constant_factor = 0,
            .depth_bias_clamp = 0,
            .depth_bias_slope_factor = 0,
            .line_width = 1,
        },
        .p_multisample_state = &.{
            .rasterization_samples = .{ .@"1_bit" = true },
            .sample_shading_enable = .false,
            .min_sample_shading = 1,
            .alpha_to_coverage_enable = .false,
            .alpha_to_one_enable = .false,
        },
        .p_depth_stencil_state = null,
        .p_color_blend_state = &.{
            .logic_op_enable = .false,
            .logic_op = .copy,
            .attachment_count = 1,
            .p_attachments = @ptrCast(attachments),
            .blend_constants = [_]f32{ 0, 0, 0, 0 },
        },
        .p_dynamic_state = &.{
            .flags = .{},
            .dynamic_state_count = 2,
            .p_dynamic_states = &.{ .viewport, .scissor },
        },
        .layout = pipeline_layout,
        .render_pass = self.render_pass,
        .subpass = 0,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    };

    var pipeline: vk.Pipeline = undefined;
    _ = try self.context.device.createGraphicsPipelines(.null_handle, 1, @ptrCast(&pipeline_info), null, @ptrCast(&pipeline));
    self.ground_material = .{
        .descriptor_layouts = descriptor_layouts,
        .descriptor_sets = descriptor_sets,
        .pipeline = pipeline,
        .pipeline_layout = pipeline_layout,
    };
}

pub fn drawQuad(
    generics: *std.ArrayList(GenericData),
    sort_extras: *std.ArrayList(f32),
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    atlas_data: assets.AtlasData,
    opts: QuadOptions,
) void {
    const render_type: RenderType = if (opts.render_type_override) |rt| rt else switch (atlas_data.atlas_type) {
        .ui => .ui_quad,
        .base => .quad,
        .invalid => @panic("Invalid atlas type passed to `drawQuad()`"),
    };

    const uv_w_per_px = atlas_data.tex_w / w;
    const uv_h_per_px = atlas_data.tex_h / h;

    const dont_scissor = element.ScissorRect.dont_scissor;

    sort_extras.append(main.allocator, opts.sort_extra) catch main.oomPanic();
    generics.append(main.allocator, .{
        .render_type = render_type,
        .rotation = opts.rotation,
        .alpha_mult = opts.alpha_mult,
        .base_color = opts.color,
        .color_intensity = opts.color_intensity,
        .pos = .{ x, y },
        .size = .{ w, h },
        .uv = .{ atlas_data.tex_u, atlas_data.tex_v },
        .uv_size = .{ atlas_data.tex_w, atlas_data.tex_h },
        .scissor = .{
            atlas_data.tex_u + if (opts.scissor.min_x == dont_scissor) 0 else opts.scissor.min_x * uv_w_per_px,
            atlas_data.tex_u + if (opts.scissor.max_x == dont_scissor) atlas_data.tex_w else opts.scissor.max_x * uv_w_per_px,
            atlas_data.tex_v + if (opts.scissor.min_y == dont_scissor) 0 else opts.scissor.min_y * uv_h_per_px,
            atlas_data.tex_v + if (opts.scissor.max_y == dont_scissor) atlas_data.tex_h else opts.scissor.max_y * uv_h_per_px,
        },
    }) catch main.oomPanic();
}

pub fn drawText(
    generics: *std.ArrayList(GenericData),
    sort_extras: *std.ArrayList(f32),
    x: f32,
    y: f32,
    scale: f32,
    text_data: *element.TextData,
    scissor_override: element.ScissorRect,
) void {
    // TODO: handle scales properly
    if (scale < 1.0 or text_data.text.len == 0) return;

    sort_extras.appendSlice(main.allocator, text_data.sort_extras.items) catch main.oomPanic();
    for (text_data.generics.items) |generic| {
        var mod_generic = generic;
        mod_generic.pos[0] += x;
        mod_generic.pos[1] += y;

        const scissor = if (scissor_override.isDefault())
            text_data.scissor
        else
            scissor_override;
        const dont_scissor = element.ScissorRect.dont_scissor;

        const uv_w_per_px = mod_generic.uv_size[0] / mod_generic.size[0];
        const uv_h_per_px = mod_generic.uv_size[1] / mod_generic.size[1];
        const x_off = x - mod_generic.pos[0];
        const y_off = y - mod_generic.pos[1];

        mod_generic.scissor = .{
            mod_generic.uv[0] + if (scissor.min_x == dont_scissor)
                0.0
            else
                (scissor.min_x + x_off) * uv_w_per_px,
            mod_generic.uv[0] + if (scissor.max_x == dont_scissor)
                mod_generic.uv_size[0]
            else
                (scissor.max_x + x_off) * uv_w_per_px,
            mod_generic.uv[1] + if (scissor.min_y == dont_scissor)
                0.0
            else
                (scissor.min_y + y_off) * uv_h_per_px,
            mod_generic.uv[1] + if (scissor.max_y == dont_scissor)
                mod_generic.uv_size[1]
            else
                (scissor.max_y + y_off) * uv_h_per_px,
        };

        generics.append(main.allocator, mod_generic) catch main.oomPanic();
    }
}

pub fn drawLight(
    lights: *std.ArrayList(LightData),
    data: game_data.LightData,
    owner_x: f32,
    owner_y: f32,
    owner_w: f32,
    owner_h: f32,
    scale: f32,
    float_time_ms: f32,
) void {
    if (data.color == std.math.maxInt(u32)) return;

    const size = 64.0 * (data.radius + data.pulse * @sin(float_time_ms / 1000.0 * data.pulse_speed)) * scale * 4;
    lights.append(main.allocator, .{
        .x = owner_x - (size - owner_w) / 2.0,
        .y = owner_y - (size - owner_h) / 2.0,
        .w = size,
        .h = size,
        .color = data.color,
        .intensity = data.intensity,
    }) catch main.oomPanic();
}

pub fn draw(
    self: *Renderer,
    draw_data: DrawData,
    extent: vk.Extent2D,
    caps: vk.SurfaceCapabilitiesKHR,
) !void {
    const clear: vk.ClearValue = .{ .color = .{ .float_32 = .{ 0.0, 0.0, 0.0, 0.0 } } };
    const viewport: vk.Viewport = .{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(self.swapchain.extent.width),
        .height = @floatFromInt(self.swapchain.extent.height),
        .min_depth = 0,
        .max_depth = 1,
    };
    const scissor: vk.Rect2D = .{
        .offset = .{ .x = 0, .y = 0 },
        .extent = self.swapchain.extent,
    };

    const cmd_buffer = self.cmd_buffers[self.swapchain.image_index];
    try self.context.device.beginCommandBuffer(cmd_buffer, &.{ .flags = .{} });
    self.context.device.cmdSetViewport(cmd_buffer, 0, 1, @ptrCast(&viewport));
    self.context.device.cmdSetScissor(cmd_buffer, 0, 1, @ptrCast(&scissor));
    const render_area: vk.Rect2D = .{
        .offset = .{ .x = 0, .y = 0 },
        .extent = self.swapchain.extent,
    };

    self.context.device.cmdBeginRenderPass(cmd_buffer, &.{
        .render_pass = self.render_pass,
        .framebuffer = self.framebuffers[self.swapchain.image_index],
        .render_area = render_area,
        .clear_value_count = 1,
        .p_clear_values = @ptrCast(&clear),
    }, .@"inline");

    const ground_push_constants: GroundPushConstants = .{
        .scale = draw_data.camera.scale,
        .left_mask_uv = assets.left_mask_uv,
        .top_mask_uv = assets.top_mask_uv,
        .right_mask_uv = assets.right_mask_uv,
        .bottom_mask_uv = assets.bottom_mask_uv,
        .clip_scale = draw_data.camera.clip_scale,
        .clip_offset = draw_data.camera.clip_offset,
        .atlas_size = .{ assets.atlas_width, assets.atlas_height },
    };
    const ground_len: u32 = @min(draw_data.grounds.len, ground_size);
    if (ground_len > 0) {
        try writeToBuffer(
            self.context,
            self.cmd_pool,
            self.ground_staging_buffer,
            self.ground_buffer.buffer.handle,
            GroundData,
            draw_data.grounds[0..ground_len],
        );

        self.context.device.cmdPushConstants(
            cmd_buffer,
            self.ground_material.pipeline_layout,
            .{ .vertex_bit = true, .fragment_bit = true },
            0,
            @sizeOf(GroundPushConstants),
            &ground_push_constants,
        );
        self.context.device.cmdBindPipeline(cmd_buffer, .graphics, self.ground_material.pipeline);
        self.context.device.cmdBindDescriptorSets(
            cmd_buffer,
            .graphics,
            self.ground_material.pipeline_layout,
            0,
            2,
            @ptrCast(&self.ground_material.descriptor_sets),
            0,
            null,
        );
        self.context.device.cmdDraw(cmd_buffer, ground_len * 6, 1, 0, 0);
    }

    const ui_off: GenericPushConstants = .{
        .clip_scale = draw_data.camera.clip_scale,
        .clip_offset = draw_data.camera.clip_offset,
        .is_ui = 0,
    };
    const ui_on: GenericPushConstants = .{
        .clip_scale = draw_data.camera.clip_scale,
        .clip_offset = draw_data.camera.clip_offset,
        .is_ui = 1,
    };

    const game_len: u32 = @min(draw_data.generics.len, generic_size);
    if (game_len > 0) {
        try writeToBuffer(
            self.context,
            self.cmd_pool,
            self.generic_staging_buffer,
            self.generic_buffer.buffer.handle,
            GenericData,
            draw_data.generics[0..game_len],
        );

        self.context.device.cmdPushConstants(
            cmd_buffer,
            self.generic_material.pipeline_layout,
            .{ .vertex_bit = true, .fragment_bit = true },
            0,
            @sizeOf(GenericPushConstants),
            &ui_off,
        );
        self.context.device.cmdBindPipeline(cmd_buffer, .graphics, self.generic_material.pipeline);
        self.context.device.cmdBindDescriptorSets(
            cmd_buffer,
            .graphics,
            self.generic_material.pipeline_layout,
            0,
            2,
            @ptrCast(&self.generic_material.descriptor_sets),
            0,
            null,
        );
        self.context.device.cmdDraw(cmd_buffer, game_len * 6, 1, 0, 0);
    }

    const ui_len: u32 = @min(draw_data.ui_generics.len, generic_size);
    if (ui_len > 0) {
        try writeToBuffer(
            self.context,
            self.cmd_pool,
            self.ui_staging_buffer,
            self.ui_buffer.buffer.handle,
            GenericData,
            draw_data.ui_generics[0..ui_len],
        );

        self.context.device.cmdPushConstants(
            cmd_buffer,
            self.generic_material.pipeline_layout,
            .{ .vertex_bit = true, .fragment_bit = true },
            0,
            @sizeOf(GenericPushConstants),
            &ui_on,
        );

        if (game_len == 0) {
            self.context.device.cmdBindPipeline(cmd_buffer, .graphics, self.generic_material.pipeline);
            self.context.device.cmdBindDescriptorSets(
                cmd_buffer,
                .graphics,
                self.generic_material.pipeline_layout,
                0,
                2,
                @ptrCast(&self.generic_material.descriptor_sets),
                0,
                null,
            );
        }

        self.context.device.cmdDraw(cmd_buffer, ui_len * 6, 1, 0, 0);
    }

    self.context.device.cmdEndRenderPass(cmd_buffer);
    try self.context.device.endCommandBuffer(cmd_buffer);

    const state: Swapchain.PresentState = self.swapchain.present(self.context, cmd_buffer) catch |err| switch (err) {
        error.OutOfDateKHR => .suboptimal,
        else => |e| return e,
    };

    if (state == .suboptimal) {
        try self.context.device.queueWaitIdle(self.context.graphics_queue.handle);
        try self.swapchain.recreate(
            self.context,
            extent,
            caps,
            if (main.settings.enable_vsync) .fifo_khr else .immediate_khr,
        );
        self.destroyFrameAndCmdBuffers();
        try self.createFrameAndCmdBuffers();
    }
}
