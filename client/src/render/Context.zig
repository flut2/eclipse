const std = @import("std");

const build_options = @import("options");
const glfw = @import("glfw");
const vk = @import("vulkan");

const required_layers: []const [*:0]const u8 =
    // zig fmt: off
    if (build_options.enable_validation_layers)
        &.{"VK_LAYER_KHRONOS_validation"}
    else
        &.{};
    // zig fmt: on
const required_device_extensions: []const [*:0]const u8 = &.{
    khr_swapchain.name,
};

// need to have a modded version for RenderDoc...
pub const khr_swapchain: vk.ApiInfo = .{
    .name = "VK_KHR_swapchain",
    .version = 70,
    .base_commands = .{},
    .instance_commands = .{},
    .device_commands = .{
        .getSwapchainImagesKHR = true,
        .acquireNextImageKHR = true,
        .queuePresentKHR = true,
        .destroySwapchainKHR = true,
        .createSwapchainKHR = true,
    },
};

const apis: []const vk.ApiInfo = &.{
    vk.features.version_1_0,
    vk.extensions.khr_surface,
    khr_swapchain,
};

const BaseDispatch = vk.BaseWrapper(apis);
const InstanceDispatch = vk.InstanceWrapper(apis);
const DeviceDispatch = vk.DeviceWrapper(apis);

const Instance = vk.InstanceProxy(apis);
const Device = vk.DeviceProxy(apis);

const DeviceCandidate = struct {
    phys_device: vk.PhysicalDevice,
    props: vk.PhysicalDeviceProperties,
    queues: QueueAllocation,
};

const QueueAllocation = struct {
    graphics_family: u32,
    present_family: u32,
};

pub const Queue = struct {
    handle: vk.Queue,
    family: u32,

    fn init(device: Device, family: u32) Queue {
        return .{
            .handle = device.getDeviceQueue(family, 0),
            .family = family,
        };
    }
};

const Context = @This();
pub const CommandBuffer = vk.CommandBufferProxy(apis);

allocator: std.mem.Allocator,
base_dispatch: BaseDispatch,
instance: Instance,
surface: vk.SurfaceKHR,
phys_device: vk.PhysicalDevice,
device_props: vk.PhysicalDeviceProperties,
mem_props: vk.PhysicalDeviceMemoryProperties,
device: Device,
graphics_queue: Queue,
present_queue: Queue,

pub const VkProc = *const anyopaque;
extern fn glfwGetInstanceProcAddress(instance: vk.Instance, procname: [*:0]const u8) ?VkProc;

pub fn init(allocator: std.mem.Allocator, window: *glfw.Window) !Context {
    var self: Context = undefined;
    self.allocator = allocator;
    self.base_dispatch = try .load(glfwGetInstanceProcAddress);

    const glfw_exts = try glfw.getRequiredInstanceExtensions();

    const app_info: vk.ApplicationInfo = .{
        .p_application_name = "Eclipse",
        .application_version = vk.makeApiVersion(1, 1, 0, 0),
        .p_engine_name = "Eclipse",
        .engine_version = vk.makeApiVersion(1, 1, 0, 0),
        .api_version = vk.API_VERSION_1_0,
    };

    const instance = try self.base_dispatch.createInstance(&.{
        .p_application_info = &app_info,
        .enabled_layer_count = @intCast(required_layers.len),
        .pp_enabled_layer_names = @ptrCast(required_layers),
        .enabled_extension_count = @intCast(glfw_exts.len),
        .pp_enabled_extension_names = @ptrCast(glfw_exts),
    }, null);

    const vki = try allocator.create(InstanceDispatch);
    errdefer allocator.destroy(vki);
    vki.* = try .load(instance, self.base_dispatch.dispatch.vkGetInstanceProcAddr);
    self.instance = .init(instance, vki);
    errdefer self.instance.destroyInstance(null);

    self.surface = try createSurface(self.instance, window);
    errdefer self.instance.destroySurfaceKHR(self.surface, null);

    const candidate = try pickPhysicalDevice(self.instance, allocator, self.surface);
    self.phys_device = candidate.phys_device;
    self.device_props = candidate.props;

    const dev = try initializeCandidate(self.instance, candidate);

    const vkd = try allocator.create(DeviceDispatch);
    errdefer allocator.destroy(vkd);
    vkd.* = try .load(dev, self.instance.wrapper.dispatch.vkGetDeviceProcAddr);
    self.device = .init(dev, vkd);
    errdefer self.device.destroyDevice(null);

    self.graphics_queue = .init(self.device, candidate.queues.graphics_family);
    self.present_queue = .init(self.device, candidate.queues.present_family);

    self.mem_props = self.instance.getPhysicalDeviceMemoryProperties(self.phys_device);

    return self;
}

pub fn deinit(self: Context) void {
    self.device.destroyDevice(null);
    self.instance.destroySurfaceKHR(self.surface, null);
    self.instance.destroyInstance(null);
    self.allocator.destroy(self.device.wrapper);
    self.allocator.destroy(self.instance.wrapper);
}

pub fn deviceName(self: *const Context) []const u8 {
    return std.mem.sliceTo(&self.device_props.device_name, 0);
}

pub fn findMemoryTypeIndex(self: Context, memory_type_bits: u32, flags: vk.MemoryPropertyFlags) !u32 {
    for (self.mem_props.memory_types[0..self.mem_props.memory_type_count], 0..) |mem_type, i|
        if (memory_type_bits & (@as(u32, 1) << @truncate(i)) != 0 and mem_type.property_flags.contains(flags))
            return @truncate(i);

    return error.NoSuitableMemoryType;
}

pub fn allocate(self: Context, requirements: vk.MemoryRequirements, flags: vk.MemoryPropertyFlags) !vk.DeviceMemory {
    return try self.device.allocateMemory(&.{
        .allocation_size = requirements.size,
        .memory_type_index = try self.findMemoryTypeIndex(requirements.memory_type_bits, flags),
    }, null);
}

extern fn glfwCreateWindowSurface(
    instance: vk.Instance,
    window: *glfw.Window,
    allocator: ?*const vk.AllocationCallbacks,
    surface: *vk.SurfaceKHR,
) vk.Result;

fn createSurface(instance: Instance, window: *glfw.Window) !vk.SurfaceKHR {
    var surface: vk.SurfaceKHR = undefined;
    if (glfwCreateWindowSurface(instance.handle, window, null, &surface) != .success) return error.SurfaceInitFailed;
    return surface;
}

fn initializeCandidate(instance: Instance, candidate: DeviceCandidate) !vk.Device {
    const priority: []const f32 = &.{1};
    const qci: []const vk.DeviceQueueCreateInfo = &.{
        .{ .queue_family_index = candidate.queues.graphics_family, .queue_count = 1, .p_queue_priorities = @ptrCast(priority) },
        .{ .queue_family_index = candidate.queues.present_family, .queue_count = 1, .p_queue_priorities = @ptrCast(priority) },
    };

    const queue_count: u32 = if (candidate.queues.graphics_family == candidate.queues.present_family)
        1
    else
        2;

    return try instance.createDevice(candidate.phys_device, &.{
        .queue_create_info_count = queue_count,
        .p_queue_create_infos = @ptrCast(qci),
        .enabled_extension_count = @intCast(required_device_extensions.len),
        .pp_enabled_extension_names = @ptrCast(required_device_extensions),
    }, null);
}

fn pickPhysicalDevice(instance: Instance, allocator: std.mem.Allocator, surface: vk.SurfaceKHR) !DeviceCandidate {
    const pdevs = try instance.enumeratePhysicalDevicesAlloc(allocator);
    defer allocator.free(pdevs);

    for (pdevs) |pdev| if (try checkSuitable(instance, pdev, allocator, surface)) |candidate|
        return candidate;

    return error.NoSuitableDevice;
}

fn checkSuitable(
    instance: Instance,
    phys_device: vk.PhysicalDevice,
    allocator: std.mem.Allocator,
    surface: vk.SurfaceKHR,
) !?DeviceCandidate {
    if (!try checkExtensionSupport(instance, phys_device, allocator) or
        !try checkSurfaceSupport(instance, phys_device, surface))
        return null;

    if (try allocateQueues(instance, phys_device, allocator, surface)) |allocation| {
        const props = instance.getPhysicalDeviceProperties(phys_device);
        return .{
            .phys_device = phys_device,
            .props = props,
            .queues = allocation,
        };
    }

    return null;
}

fn allocateQueues(instance: Instance, pdev: vk.PhysicalDevice, allocator: std.mem.Allocator, surface: vk.SurfaceKHR) !?QueueAllocation {
    const families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(pdev, allocator);
    defer allocator.free(families);

    var graphics_family: ?u32 = null;
    var present_family: ?u32 = null;

    for (families, 0..) |properties, i| {
        const family: u32 = @intCast(i);
        if (graphics_family == null and properties.queue_flags.graphics_bit) graphics_family = family;
        if (present_family == null and (try instance.getPhysicalDeviceSurfaceSupportKHR(pdev, family, surface)) == vk.TRUE) present_family = family;
    }

    if (graphics_family != null and present_family != null) return .{
        .graphics_family = graphics_family.?,
        .present_family = present_family.?,
    };

    return null;
}

fn checkSurfaceSupport(instance: Instance, pdev: vk.PhysicalDevice, surface: vk.SurfaceKHR) !bool {
    var format_count: u32 = undefined;
    _ = try instance.getPhysicalDeviceSurfaceFormatsKHR(pdev, surface, &format_count, null);
    var present_mode_count: u32 = undefined;
    _ = try instance.getPhysicalDeviceSurfacePresentModesKHR(pdev, surface, &present_mode_count, null);
    return format_count > 0 and present_mode_count > 0;
}

fn checkExtensionSupport(instance: Instance, pdev: vk.PhysicalDevice, allocator: std.mem.Allocator) !bool {
    const propsv = try instance.enumerateDeviceExtensionPropertiesAlloc(pdev, null, allocator);
    defer allocator.free(propsv);

    for (required_device_extensions) |ext| {
        for (propsv) |props| {
            if (std.mem.eql(u8, std.mem.span(ext), std.mem.sliceTo(&props.extension_name, 0))) break;
        } else return false;
    }

    return true;
}
