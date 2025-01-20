const std = @import("std");

const vk = @import("vulkan");

const Context = @import("Context.zig");
const main = @import("../main.zig");

const Swapchain = @This();
const SwapImage = struct {
    image: vk.Image,
    view: vk.ImageView,
    image_acquired: vk.Semaphore,
    render_finished: vk.Semaphore,
    frame_fence: vk.Fence,

    fn init(ctx: Context, image: vk.Image, format: vk.Format) !SwapImage {
        const view = try ctx.device.createImageView(&.{
            .image = image,
            .view_type = .@"2d",
            .format = format,
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }, null);
        errdefer ctx.device.destroyImageView(view, null);

        const image_acquired = try ctx.device.createSemaphore(&.{}, null);
        errdefer ctx.device.destroySemaphore(image_acquired, null);

        const render_finished = try ctx.device.createSemaphore(&.{}, null);
        errdefer ctx.device.destroySemaphore(render_finished, null);

        const frame_fence = try ctx.device.createFence(&.{ .flags = .{ .signaled_bit = true } }, null);
        errdefer ctx.device.destroyFence(frame_fence, null);

        return .{
            .image = image,
            .view = view,
            .image_acquired = image_acquired,
            .render_finished = render_finished,
            .frame_fence = frame_fence,
        };
    }

    fn deinit(self: SwapImage, ctx: Context) void {
        _ = ctx.device.waitForFences(1, @ptrCast(&self.frame_fence), vk.TRUE, std.math.maxInt(u64)) catch {};
        ctx.device.destroyImageView(self.view, null);
        ctx.device.destroySemaphore(self.image_acquired, null);
        ctx.device.destroySemaphore(self.render_finished, null);
        ctx.device.destroyFence(self.frame_fence, null);
    }
};

pub const PresentState = enum { optimal, suboptimal };

surface_format: vk.SurfaceFormatKHR,
present_mode: vk.PresentModeKHR,
extent: vk.Extent2D,
handle: vk.SwapchainKHR,

swap_images: []SwapImage,
image_index: u32,
next_image_acquired: vk.Semaphore,

pub fn init(ctx: Context, extent: vk.Extent2D, present_mode: vk.PresentModeKHR) !Swapchain {
    return try initRecycle(ctx, extent, .null_handle, present_mode);
}

pub fn initRecycle(
    ctx: Context,
    extent: vk.Extent2D,
    old_handle: vk.SwapchainKHR,
    present_mode: vk.PresentModeKHR,
) !Swapchain {
    const caps = try ctx.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(ctx.phys_device, ctx.surface);
    const actual_extent = findActualExtent(caps, extent);
    if (actual_extent.width == 0 or actual_extent.height == 0) return error.InvalidSurfaceDimensions;

    const surface_format = try findSurfaceFormat(ctx);
    const final_present_mode = try findPresentMode(ctx, present_mode);

    var image_count = caps.min_image_count + 1;
    if (caps.max_image_count > 0) image_count = @min(image_count, caps.max_image_count);

    const qfi: []const u32 = &.{ ctx.graphics_queue.family, ctx.present_queue.family };
    const sharing_mode: vk.SharingMode = if (ctx.graphics_queue.family != ctx.present_queue.family)
        .concurrent
    else
        .exclusive;

    const handle = try ctx.device.createSwapchainKHR(&.{
        .surface = ctx.surface,
        .min_image_count = image_count,
        .image_format = surface_format.format,
        .image_color_space = surface_format.color_space,
        .image_extent = actual_extent,
        .image_array_layers = 1,
        .image_usage = .{ .color_attachment_bit = true, .transfer_dst_bit = true },
        .image_sharing_mode = sharing_mode,
        .queue_family_index_count = @intCast(qfi.len),
        .p_queue_family_indices = @ptrCast(qfi),
        .pre_transform = caps.current_transform,
        .composite_alpha = .{ .opaque_bit_khr = true },
        .present_mode = final_present_mode,
        .clipped = vk.TRUE,
        .old_swapchain = old_handle,
    }, null);
    errdefer ctx.device.destroySwapchainKHR(handle, null);

    if (old_handle != .null_handle) ctx.device.destroySwapchainKHR(old_handle, null);

    const swap_images = try initSwapchainImages(ctx, handle, surface_format.format);
    errdefer {
        for (swap_images) |img| img.deinit(ctx);
        main.allocator.free(swap_images);
    }

    var next_image_acquired = try ctx.device.createSemaphore(&.{}, null);
    errdefer ctx.device.destroySemaphore(next_image_acquired, null);

    const result = try ctx.device.acquireNextImageKHR(handle, std.math.maxInt(u64), next_image_acquired, .null_handle);
    if (result.result != .success) return error.ImageAcquireFailed;

    std.mem.swap(vk.Semaphore, &swap_images[result.image_index].image_acquired, &next_image_acquired);
    return .{
        .surface_format = surface_format,
        .present_mode = final_present_mode,
        .extent = actual_extent,
        .handle = handle,
        .swap_images = swap_images,
        .image_index = result.image_index,
        .next_image_acquired = next_image_acquired,
    };
}

fn deinitExceptSwapchain(self: Swapchain, ctx: Context) void {
    for (self.swap_images) |swap_img| swap_img.deinit(ctx);
    main.allocator.free(self.swap_images);
    ctx.device.destroySemaphore(self.next_image_acquired, null);
}

pub fn waitForAllFences(self: Swapchain, ctx: Context) !void {
    for (self.swap_images) |swap_img|
        _ = try ctx.device.waitForFences(1, @ptrCast(&swap_img.frame_fence), vk.TRUE, std.math.maxInt(u64));
}

pub fn deinit(self: Swapchain, ctx: Context) void {
    self.deinitExceptSwapchain(ctx);
    ctx.device.destroySwapchainKHR(self.handle, null);
}

pub fn recreate(self: *Swapchain, ctx: Context, new_extent: vk.Extent2D, present_mode: vk.PresentModeKHR) !void {
    const old_handle = self.handle;
    self.deinitExceptSwapchain(ctx);
    self.* = try initRecycle(ctx, new_extent, old_handle, present_mode);
}

pub fn present(self: *Swapchain, ctx: Context, cmd_buffer: vk.CommandBuffer) !PresentState {
    const current = &self.swap_images[self.image_index];
    _ = try ctx.device.waitForFences(1, @ptrCast(&current.frame_fence), vk.TRUE, std.math.maxInt(u64));
    try ctx.device.resetFences(1, @ptrCast(&current.frame_fence));

    const wait_stage = [_]vk.PipelineStageFlags{.{ .top_of_pipe_bit = true }};
    try ctx.device.queueSubmit(ctx.graphics_queue.handle, 1, &[_]vk.SubmitInfo{.{
        .wait_semaphore_count = 1,
        .p_wait_semaphores = @ptrCast(&current.image_acquired),
        .p_wait_dst_stage_mask = &wait_stage,
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&cmd_buffer),
        .signal_semaphore_count = 1,
        .p_signal_semaphores = @ptrCast(&current.render_finished),
    }}, current.frame_fence);

    _ = try ctx.device.queuePresentKHR(ctx.present_queue.handle, &.{
        .wait_semaphore_count = 1,
        .p_wait_semaphores = @ptrCast(&current.render_finished),
        .swapchain_count = 1,
        .p_swapchains = @ptrCast(&self.handle),
        .p_image_indices = @ptrCast(&self.image_index),
    });

    const result = try ctx.device.acquireNextImageKHR(
        self.handle,
        std.math.maxInt(u64),
        self.next_image_acquired,
        .null_handle,
    );

    std.mem.swap(vk.Semaphore, &self.swap_images[result.image_index].image_acquired, &self.next_image_acquired);
    self.image_index = result.image_index;

    return switch (result.result) {
        .success => .optimal,
        .suboptimal_khr => .suboptimal,
        else => unreachable,
    };
}

fn initSwapchainImages(ctx: Context, swapchain: vk.SwapchainKHR, format: vk.Format) ![]SwapImage {
    const images = try ctx.device.getSwapchainImagesAllocKHR(swapchain, main.allocator);
    defer main.allocator.free(images);

    const swap_images = try main.allocator.alloc(SwapImage, images.len);
    errdefer main.allocator.free(swap_images);

    var i: usize = 0;
    errdefer for (swap_images[0..i]) |si| si.deinit(ctx);

    for (images) |image| {
        swap_images[i] = try .init(ctx, image, format);
        i += 1;
    }

    return swap_images;
}

fn findSurfaceFormat(ctx: Context) !vk.SurfaceFormatKHR {
    const preferred: vk.SurfaceFormatKHR = .{ .format = .b8g8r8a8_srgb, .color_space = .srgb_nonlinear_khr };
    const surface_formats = try ctx.instance.getPhysicalDeviceSurfaceFormatsAllocKHR(ctx.phys_device, ctx.surface, main.allocator);
    defer main.allocator.free(surface_formats);
    for (surface_formats) |sfmt| if (std.meta.eql(sfmt, preferred)) return preferred;
    return surface_formats[0];
}

fn findPresentMode(ctx: Context, present_mode: vk.PresentModeKHR) !vk.PresentModeKHR {
    const present_modes = try ctx.instance.getPhysicalDeviceSurfacePresentModesAllocKHR(ctx.phys_device, ctx.surface, main.allocator);
    defer main.allocator.free(present_modes);
    if (std.mem.indexOfScalar(vk.PresentModeKHR, present_modes, present_mode) != null) return present_mode;
    inline for (.{ .mailbox_khr, .immediate_khr }) |mode|
        if (std.mem.indexOfScalar(vk.PresentModeKHR, present_modes, mode) != null) return mode;
    return .fifo_khr;
}

fn findActualExtent(caps: vk.SurfaceCapabilitiesKHR, extent: vk.Extent2D) vk.Extent2D {
    if (caps.current_extent.width != 0xFFFFFFFF) return caps.current_extent;
    return .{
        .width = std.math.clamp(extent.width, caps.min_image_extent.width, caps.max_image_extent.width),
        .height = std.math.clamp(extent.height, caps.min_image_extent.height, caps.max_image_extent.height),
    };
}
