const std = @import("std");

const build_options = @import("options");
const vk = @import("vulkan");
const BaseWrapper = vk.BaseWrapper;
const InstanceWrapper = vk.InstanceWrapper;
const DeviceWrapper = vk.DeviceWrapper;
const Instance = vk.InstanceProxy;
const Device = vk.DeviceProxy;
const windy = @import("windy");

const main = @import("../main.zig");

const required_layers: []const [*:0]const u8 =
    // zig fmt: off
    if (build_options.vk_validation)
        &.{"VK_LAYER_KHRONOS_validation"}
    else
        &.{};
    // zig fmt: on
const required_device_extensions: []const [*:0]const u8 = &.{
    vk.extensions.khr_swapchain.name,
};

const apis: []const vk.ApiInfo = &.{
    vk.features.version_1_0,
    vk.extensions.khr_surface,
    vk.extensions.khr_swapchain,
};

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
        return .{ .handle = device.getDeviceQueue(family, 0), .family = family };
    }
};

const Context = @This();
pub const CommandBuffer = vk.CommandBufferProxy(apis);

base_dispatch: BaseWrapper,
instance: Instance,
surface: vk.SurfaceKHR,
phys_device: vk.PhysicalDevice,
device_props: vk.PhysicalDeviceProperties,
mem_props: vk.PhysicalDeviceMemoryProperties,
device: Device,
graphics_queue: Queue,
present_queue: Queue,

fn procAddrBounce(_: vk.Instance, name: [*:0]const u8) vk.PfnVoidFunction {
    return windy.vulkanProcAddr(vk, name);
}

pub fn init(window: *windy.Window) !Context {
    var self: Context = undefined;
    self.base_dispatch = .load(procAddrBounce);

    const exts = windy.vulkanExts();

    const app_info: vk.ApplicationInfo = .{
        .p_application_name = "Eclipse",
        .application_version = @bitCast(vk.makeApiVersion(1, 1, 0, 0)),
        .p_engine_name = "Eclipse",
        .engine_version = @bitCast(vk.makeApiVersion(1, 1, 0, 0)),
        .api_version = @bitCast(vk.API_VERSION_1_0),
    };

    const instance = try self.base_dispatch.createInstance(&.{
        .p_application_info = &app_info,
        .enabled_layer_count = @intCast(required_layers.len),
        .pp_enabled_layer_names = @ptrCast(required_layers),
        .enabled_extension_count = @intCast(exts.len),
        .pp_enabled_extension_names = @ptrCast(exts.ptr),
    }, null);

    const vki = try main.allocator.create(InstanceWrapper);
    errdefer main.allocator.destroy(vki);
    vki.* = .load(instance, self.base_dispatch.dispatch.vkGetInstanceProcAddr.?);
    self.instance = .init(instance, vki);
    errdefer self.instance.destroyInstance(null);

    self.surface = try window.createSurface(vk, self.instance);
    errdefer self.instance.destroySurfaceKHR(self.surface, null);

    const candidate = try pickPhysicalDevice(self.instance, self.surface);
    self.phys_device = candidate.phys_device;
    self.device_props = candidate.props;

    const dev = try initializeCandidate(self.instance, candidate);

    const vkd = try main.allocator.create(DeviceWrapper);
    errdefer main.allocator.destroy(vkd);
    vkd.* = .load(dev, self.instance.wrapper.dispatch.vkGetDeviceProcAddr.?);
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
    main.allocator.destroy(self.device.wrapper);
    main.allocator.destroy(self.instance.wrapper);
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

fn createSurface(instance: Instance, window: *windy.Window) !vk.SurfaceKHR {
    _ = instance; // autofix
    _ = window; // autofix

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

fn pickPhysicalDevice(instance: Instance, surface: vk.SurfaceKHR) !DeviceCandidate {
    const phys_devices = try instance.enumeratePhysicalDevicesAlloc(main.allocator);
    defer main.allocator.free(phys_devices);

    for (phys_devices) |phys_device| if (try checkSuitable(instance, phys_device, surface)) |candidate|
        return candidate;

    return error.NoSuitableDevice;
}

fn checkSuitable(instance: Instance, phys_device: vk.PhysicalDevice, surface: vk.SurfaceKHR) !?DeviceCandidate {
    if (!try checkExtensionSupport(instance, phys_device) or
        !try checkSurfaceSupport(instance, phys_device, surface))
        return null;

    if (try allocateQueues(instance, phys_device, surface)) |allocation| {
        const props = instance.getPhysicalDeviceProperties(phys_device);
        return .{ .phys_device = phys_device, .props = props, .queues = allocation };
    }

    return null;
}

fn allocateQueues(instance: Instance, phys_device: vk.PhysicalDevice, surface: vk.SurfaceKHR) !?QueueAllocation {
    const families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(phys_device, main.allocator);
    defer main.allocator.free(families);

    var graphics_family: ?u32 = null;
    var present_family: ?u32 = null;

    for (families, 0..) |properties, i| {
        const family: u32 = @intCast(i);
        if (graphics_family == null and properties.queue_flags.graphics_bit) graphics_family = family;
        if (present_family == null and
            (try instance.getPhysicalDeviceSurfaceSupportKHR(phys_device, family, surface)) == .true)
            present_family = family;
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

fn checkExtensionSupport(instance: Instance, pdev: vk.PhysicalDevice) !bool {
    const propsv = try instance.enumerateDeviceExtensionPropertiesAlloc(pdev, null, main.allocator);
    defer main.allocator.free(propsv);

    for (required_device_extensions) |ext| {
        for (propsv) |props| {
            if (std.mem.eql(u8, std.mem.span(ext), std.mem.sliceTo(&props.extension_name, 0))) break;
        } else return false;
    }

    return true;
}
